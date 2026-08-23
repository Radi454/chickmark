// Usage settlement.
//
// Exactly-once, defended twice:
//
//   * `agent_realtime_usage_seconds` has PK (session_id, usage_date) and every
//     write is INSERT ... ON CONFLICT DO NOTHING. Replaying settlement can never
//     add seconds. This is the defence that actually protects the numbers.
//   * `agent_realtime_sessions.usage_settled_at` is set by compare-and-swap and
//     is the marker that stops repeated work and reports "already settled".
//
// Order matters: slices are inserted FIRST, then the marker is CAS'd. A crash
// between the two leaves a settled ledger with no marker, and the sweeper simply
// retries — the inserts no-op and the marker lands. The reverse order would let
// a crash mark a session settled whose seconds were never recorded, and that
// loss is unrecoverable.
//
// A session that crosses UTC midnight settles as two slices that sum to its true
// active seconds. Daily budgets are per UTC day, so a single slice attributed to
// the start day would let a 23:50 session spend tomorrow's allowance too.

import type { RealtimeStore, SessionRow, UsageSlice } from './store.ts'
import { log } from './log.ts'

export type SettlementResult =
  | {
    readonly settled: true
    readonly slices: readonly UsageSlice[]
    readonly seconds: number
  }
  | { readonly settled: false; readonly reason: 'already_settled' | 'never_active' }

function utcDateKey(date: Date): string {
  return date.toISOString().slice(0, 10)
}

function nextUtcMidnight(date: Date): Date {
  const next = new Date(date)
  next.setUTCHours(24, 0, 0, 0)
  return next
}

/**
 * Split [start, end) into per-UTC-day second counts.
 *
 * Each boundary is rounded from the CUMULATIVE elapsed time rather than from the
 * slice length, so per-slice rounding error cannot accumulate: the slices always
 * sum to `round((end - start) / 1000)` exactly.
 */
export function splitByUtcDay(
  start: Date,
  end: Date,
): readonly { readonly usageDate: string; readonly seconds: number }[] {
  if (!(end.getTime() > start.getTime())) return []

  const slices: { usageDate: string; seconds: number }[] = []
  let cursor = start
  let cumulative = 0

  while (cursor.getTime() < end.getTime()) {
    const boundary = nextUtcMidnight(cursor)
    const sliceEnd = boundary.getTime() < end.getTime() ? boundary : end
    const nextCumulative = Math.round((sliceEnd.getTime() - start.getTime()) / 1000)
    const seconds = nextCumulative - cumulative
    if (seconds > 0) slices.push({ usageDate: utcDateKey(cursor), seconds })
    cumulative = nextCumulative
    cursor = sliceEnd
  }

  return slices
}

export async function settleSessionUsage(input: {
  store: RealtimeStore
  session: SessionRow
  now: Date
}): Promise<SettlementResult> {
  const { store, session, now } = input

  if (session.usageSettledAt) {
    return { settled: false, reason: 'already_settled' }
  }

  // Seconds are counted from the authoritative READY moment. A session that
  // never reached READY consumed no conversational time, so it settles as a
  // marker with an empty ledger rather than being left unsettled forever.
  if (!session.authoritativeReadyAt) {
    const marked = await store.markUsageSettled(session.id, now.toISOString())
    return marked
      ? { settled: false, reason: 'never_active' }
      : { settled: false, reason: 'already_settled' }
  }

  const start = new Date(session.authoritativeReadyAt)
  const end = session.endedAt ? new Date(session.endedAt) : now
  const parts = splitByUtcDay(start, end)

  const slices: UsageSlice[] = parts.map((part) => ({
    sessionId: session.id,
    usageDate: part.usageDate,
    ownerProfileId: session.ownerProfileId,
    tenantId: session.tenantId,
    seconds: part.seconds,
  }))

  if (slices.length > 0) await store.insertUsageSlices(slices)

  const marked = await store.markUsageSettled(session.id, now.toISOString())
  if (!marked) {
    // Someone else settled concurrently. The ledger PK guarantees their rows and
    // ours cannot both count, so there is nothing to undo.
    return { settled: false, reason: 'already_settled' }
  }

  const seconds = slices.reduce((total, slice) => total + slice.seconds, 0)
  log.info('usage.settled', {
    session_id: session.id,
    slices: slices.length,
    seconds,
  })
  return { settled: true, slices, seconds }
}
