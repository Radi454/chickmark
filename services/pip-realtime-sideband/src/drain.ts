// SIGTERM drain.
//
// Cloud Run's grace period is a FIXED, NON-CONFIGURABLE 10 seconds, then
// SIGKILL. Whatever is not done by then does not happen, so the drain does the
// smallest set of things that must be durable and hands everything slow to the
// scheduler sweeper:
//
//   * ONE batched statement marks every generation this worker owns
//     `cleanup_pending` with end reason `server_drain` and releases the leases.
//     Per-generation round trips would scale with concurrency and blow the
//     budget exactly when the instance is busiest.
//   * A close frame is pushed to each client so it can fail over immediately
//     instead of waiting for a socket timeout.
//   * NO OpenAI hangups. Each is a network round trip to a third party with no
//     latency guarantee; the sweeper does them where there is time.
//
// The whole path is bounded by `drainBudgetMs` (default 7s) so the process still
// has room to exit inside the grace window.

import type { RealtimeConfig } from './config.ts'
import { errorShape, log } from './log.ts'
import type { RealtimeStore } from './store.ts'

export interface DrainableConnection {
  readonly sessionId: string
  readonly generation: number
  /** Push a close frame. Must not throw and must not await the peer. */
  closeForDrain(): void
}

export class ConnectionRegistry {
  readonly #connections = new Set<DrainableConnection>()

  add(connection: DrainableConnection): void {
    this.#connections.add(connection)
  }

  remove(connection: DrainableConnection): void {
    this.#connections.delete(connection)
  }

  get size(): number {
    return this.#connections.size
  }

  list(): DrainableConnection[] {
    return [...this.#connections]
  }
}

export interface DrainReport {
  readonly handedOff: number
  readonly closed: number
  readonly durationMs: number
  readonly withinBudget: boolean
}

export async function drain(input: {
  store: RealtimeStore
  config: RealtimeConfig
  registry: ConnectionRegistry
  owner: string
  now: () => Date
}): Promise<DrainReport> {
  const started = input.now().getTime()
  const connections = input.registry.list()

  let handedOff = 0
  try {
    const handoff = input.store.markGenerationsCleanupPending({
      owner: input.owner,
      endReason: 'server_drain',
      now: new Date(started).toISOString(),
    })
    // The handoff is bounded: a slow database must not consume the whole grace
    // period and leave clients hanging with no close frame.
    handedOff = await Promise.race([
      handoff,
      new Promise<number>((resolve) =>
        setTimeout(() => resolve(-1), input.config.drainBudgetMs)
      ),
    ])
  } catch (error) {
    log.error('drain.handoff_failed', { detail: errorShape(error) })
    handedOff = -1
  }

  let closed = 0
  for (const connection of connections) {
    try {
      connection.closeForDrain()
      closed += 1
    } catch (error) {
      log.warn('drain.close_failed', { detail: errorShape(error) })
    }
  }

  const durationMs = input.now().getTime() - started
  const report: DrainReport = {
    handedOff,
    closed,
    durationMs,
    withinBudget: durationMs <= input.config.drainBudgetMs,
  }
  log.info('drain.complete', {
    handed_off: handedOff,
    closed,
    duration_ms: durationMs,
    within_budget: report.withinBudget,
  })
  return report
}
