// The sweeper behind POST /internal/cleanup (Cloud Scheduler, ~60s cadence).
//
// This is the only component allowed to take time. The drain path deliberately
// hands work here instead of doing it inside Cloud Run's fixed 10s SIGTERM
// grace, and every setup that stalls past its deadline ends up here too.
//
// It must be safe to run concurrently with itself and with a live worker: every
// generation it touches is claimed via compare-and-swap on the fencing token
// first, which both prevents two sweepers colliding and fences out any worker
// still holding a stale lease.

import type { RealtimeConfig } from './config.ts'
import { errorShape, log } from './log.ts'
import { newId } from './ids.ts'
import type { CleanupCandidate, RealtimeStore } from './store.ts'
import { settleSessionUsage } from './usage.ts'

export type HangupFn = (callId: string) => Promise<'succeeded' | 'failed'>

export interface CleanupReport {
  readonly examined: number
  readonly claimed: number
  readonly hungUp: number
  readonly terminalized: number
  readonly settled: number
}

/**
 * Best-effort, idempotent hangup.
 *
 * 404 is a TERMINAL SUCCESS, not a failure. Verified against the provider on
 * 2026-08-17: hanging up a call it has already dropped returns
 * `404 {"error":{"message":"No session found for the provided call_id"}}`, and
 * that is the ordinary outcome for an orphan — the client is long gone, so the
 * provider closed the call before the sweeper reached it. Recording it as
 * `failed` made every routine sweep look like a failure and would have buried
 * a genuine one in the noise.
 *
 * Any other non-2xx is still recorded as failed, but is NOT retried forever:
 * a generation must reach a terminal state rather than hang on a provider
 * error we cannot resolve.
 */
/**
 * A hangup is one third-party round trip with no latency guarantee, and the
 * sweep makes up to `limit` (50) of them in series. `fetch` has no default
 * timeout, so ONE unresponsive hangup stalls the entire sweep and the
 * `/internal/cleanup` request behind it — and the sweeper is the only thing
 * that terminalizes a generation, so that stall delays cleanup for every
 * session, not just this one. Failure here is already non-fatal.
 */
const HANGUP_TIMEOUT_MS = 5_000

export function makeHangup(config: RealtimeConfig): HangupFn {
  return async (callId) => {
    const base = config.openAiRealtimeUrl.replace(/^wss:/, 'https:').replace(/\/+$/, '')
    try {
      const response = await fetch(
        `${base}/calls/${encodeURIComponent(callId)}/hangup`,
        {
          method: 'POST',
          signal: AbortSignal.timeout(HANGUP_TIMEOUT_MS),
          headers: { authorization: `Bearer ${config.openAiApiKey}` },
        },
      )
      if (response.status === 404) {
        // Already closed provider-side: nothing left to hang up.
        log.info('cleanup.hangup_already_closed')
        return 'succeeded'
      }
      if (!response.ok) {
        log.info('cleanup.hangup_non_2xx', { status: response.status })
        return 'failed'
      }
      return 'succeeded'
    } catch (error) {
      log.warn('cleanup.hangup_error', { detail: errorShape(error) })
      return 'failed'
    }
  }
}

export async function runCleanupSweep(input: {
  store: RealtimeStore
  config: RealtimeConfig
  hangup: HangupFn
  now: () => Date
  limit?: number
}): Promise<CleanupReport> {
  const { store, config, hangup } = input
  const limit = input.limit ?? 50
  const owner = newId('sweeper')
  const nowDate = input.now()
  const candidates: CleanupCandidate[] = await store.findCleanupCandidates(
    nowDate.toISOString(),
    limit,
  )

  let claimed = 0
  let hungUp = 0
  let terminalized = 0

  for (const candidate of candidates) {
    const claimNow = input.now()
    const lease = await store.claimCleanup({
      sessionId: candidate.sessionId,
      generation: candidate.generation,
      owner,
      expectedFence: candidate.fencingToken,
      now: claimNow.toISOString(),
      expiresAt: new Date(claimNow.getTime() + config.leaseSeconds * 1000).toISOString(),
    })
    if (!lease) continue
    claimed += 1

    let hangupState: 'not_required' | 'succeeded' | 'failed' = 'not_required'
    if (candidate.openaiCallId) {
      hangupState = await hangup(candidate.openaiCallId)
      if (hangupState === 'succeeded') hungUp += 1
    }

    const endedAt = input.now().toISOString()
    const ok = await store.updateCall(lease, {
      setupState: 'ended',
      sidebandHealthy: false,
      endedAt,
      endReason: candidate.setupState === 'cleanup_pending'
        ? 'cleanup_swept'
        : 'setup_deadline_exceeded',
      hangupState,
      leaseOwner: null,
      leaseExpiresAt: null,
      cleanupNextAttemptAt: null,
    })
    if (!ok) continue
    terminalized += 1

    await store.updateSession(candidate.sessionId, {
      state: 'ended',
      endedAt,
      endReason: 'cleanup_swept',
    })
  }

  // Usage is settled here, and only here, for sessions that reached a terminal
  // state without a settlement — a crashed worker never gets to settle its own.
  let settled = 0
  const unsettled = await store.findUnsettledSessions(limit)
  for (const session of unsettled) {
    const result = await settleSessionUsage({ store, session, now: input.now() })
    if (result.settled) settled += 1
  }

  log.info('cleanup.sweep', {
    examined: candidates.length,
    claimed,
    hung_up: hungUp,
    terminalized,
    settled,
  })

  return { examined: candidates.length, claimed, hungUp, terminalized, settled }
}
