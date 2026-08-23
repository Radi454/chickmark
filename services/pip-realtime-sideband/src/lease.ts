// Lease + fencing.
//
// Exactly one worker may drive a given (session, generation). Ownership is a
// lease in `agent_realtime_calls`: `lease_owner` + `lease_expires_at`, with a
// monotonically increasing `fencing_token` bumped on every successful claim.
//
// The fence is what makes this safe under the failure that actually happens:
// a worker that is alive but paused (GC, CPU starvation, a stalled socket) does
// NOT know it lost the lease. It may wake up and try to write. Every
// authoritative write therefore carries the fence it was issued, and the DB
// rejects the write if a newer owner has bumped past it. On rejection the stale
// worker must stop — not retry, not reclaim.

import type { LeaseHandle, RealtimeStore } from './store.ts'
import { log } from './log.ts'

export class FenceLostError extends Error {
  readonly sessionId: string
  readonly generation: number
  constructor(sessionId: string, generation: number) {
    super('fence_lost')
    this.name = 'FenceLostError'
    this.sessionId = sessionId
    this.generation = generation
  }
}

export interface LeaseKeeperOptions {
  readonly store: RealtimeStore
  readonly owner: string
  readonly leaseSeconds: number
  readonly heartbeatSeconds: number
  readonly now: () => Date
  /** Injected so tests drive time without wall-clock waits. */
  readonly setTimer?: (fn: () => void, ms: number) => number
  readonly clearTimer?: (handle: number) => void
}

function plusSeconds(now: Date, seconds: number): string {
  return new Date(now.getTime() + seconds * 1000).toISOString()
}

/**
 * Owns one lease for its whole life: claim, heartbeat, fenced writes, release.
 *
 * Once `lost` is true the keeper is permanently dead. There is no reclaim path
 * from inside a stale worker — reclaiming is the *new* owner's job, via
 * `claimLease`'s compare-and-swap, and letting the stale one re-take it would
 * reintroduce exactly the split-brain the fence exists to prevent.
 */
export class LeaseKeeper {
  #handle: LeaseHandle | null = null
  #lost = false
  #timer: number | null = null
  readonly #options: LeaseKeeperOptions
  readonly #setTimer: (fn: () => void, ms: number) => number
  readonly #clearTimer: (handle: number) => void
  #onLost: ((reason: 'fence_lost' | 'renew_failed') => void) | null = null

  constructor(options: LeaseKeeperOptions) {
    this.#options = options
    this.#setTimer = options.setTimer ??
      ((fn, ms) => setTimeout(fn, ms) as unknown as number)
    this.#clearTimer = options.clearTimer ?? ((handle) => clearTimeout(handle))
  }

  get handle(): LeaseHandle | null {
    return this.#handle
  }

  get held(): boolean {
    return this.#handle !== null && !this.#lost
  }

  get lost(): boolean {
    return this.#lost
  }

  onLost(listener: (reason: 'fence_lost' | 'renew_failed') => void): void {
    this.#onLost = listener
  }

  /** Claim the exact (session, generation). Returns null when someone else owns it. */
  async claim(sessionId: string, generation: number): Promise<LeaseHandle | null> {
    const now = this.#options.now()
    const handle = await this.#options.store.claimLease({
      sessionId,
      generation,
      owner: this.#options.owner,
      now: now.toISOString(),
      expiresAt: plusSeconds(now, this.#options.leaseSeconds),
    })
    if (!handle) {
      log.warn('lease.claim_rejected', { session_id: sessionId, generation })
      return null
    }
    this.#handle = handle
    this.#lost = false
    log.info('lease.claimed', {
      session_id: sessionId,
      generation,
      fencing_token: handle.fencingToken,
    })
    return handle
  }

  startHeartbeat(): void {
    if (this.#timer !== null) return
    const tick = () => {
      this.#timer = null
      // The `.catch` is load-bearing twice over. `heartbeat()` awaits
      // `store.renewLease`, which THROWS on any non-2xx or network error
      // rather than returning false — so without it, one PostgREST hiccup is
      // an unhandled rejection that kills the whole Cloud Run instance. And
      // if that were merely suppressed, the second-order failure is worse:
      // `#markLost` would never run, `held` would stay true, the sideband's
      // liveness guard would keep saying "I am live" while the lease quietly
      // expired, and another worker would claim it — exactly the split-brain
      // the fence exists to prevent. A store error on renewal is
      // indistinguishable, from inside a stale worker, from a lost lease, and
      // this file's rule is that a stale worker stops rather than retries.
      void this.heartbeat()
        .then((ok) => {
          if (ok && this.held) schedule()
        })
        .catch(() => this.#markLost('renew_failed'))
    }
    const schedule = () => {
      this.#timer = this.#setTimer(tick, this.#options.heartbeatSeconds * 1000)
    }
    schedule()
  }

  stopHeartbeat(): void {
    if (this.#timer !== null) {
      this.#clearTimer(this.#timer)
      this.#timer = null
    }
  }

  /** One renewal round. False means the lease is gone and the worker must stop. */
  async heartbeat(): Promise<boolean> {
    if (!this.#handle || this.#lost) return false
    const now = this.#options.now()
    const expiresAt = plusSeconds(now, this.#options.leaseSeconds)
    const renewed = await this.#options.store.renewLease(
      this.#handle,
      expiresAt,
      now.toISOString(),
    )
    if (!renewed) {
      this.#markLost('renew_failed')
      return false
    }
    this.#handle = { ...this.#handle, expiresAt }
    return true
  }

  /**
   * The only sanctioned way to write call state. A false result from the store
   * means a newer generation/fence exists; the keeper dies rather than retrying.
   */
  async fencedUpdate(
    patch: Parameters<RealtimeStore['updateCall']>[1],
  ): Promise<void> {
    const handle = this.#requireHandle()
    const ok = await this.#options.store.updateCall(handle, patch)
    if (!ok) {
      this.#markLost('fence_lost')
      throw new FenceLostError(handle.sessionId, handle.generation)
    }
  }

  async release(): Promise<void> {
    this.stopHeartbeat()
    if (!this.#handle || this.#lost) return
    const now = this.#options.now().toISOString()
    await this.#options.store.releaseLease(this.#handle, now)
    log.info('lease.released', {
      session_id: this.#handle.sessionId,
      generation: this.#handle.generation,
    })
    this.#handle = null
  }

  #requireHandle(): LeaseHandle {
    if (!this.#handle || this.#lost) {
      throw new FenceLostError(
        this.#handle?.sessionId ?? 'unknown',
        this.#handle?.generation ?? 0,
      )
    }
    return this.#handle
  }

  #markLost(reason: 'fence_lost' | 'renew_failed'): void {
    if (this.#lost) return
    this.#lost = true
    this.stopHeartbeat()
    log.warn('lease.lost', {
      reason,
      session_id: this.#handle?.sessionId ?? null,
      generation: this.#handle?.generation ?? null,
    })
    this.#onLost?.(reason)
  }
}
