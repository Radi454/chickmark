// supabase/functions/pip-realtime-session/usage.ts
//
// Daily budget accounting for Realtime voice.
//
// A budget that only counts SETTLED seconds is a budget you can walk straight
// through: usage is settled when a session ends, so a caller who never ends a
// session never accrues anything. The check therefore counts
//
//     settled seconds (agent_realtime_usage_seconds, today in UTC)
//   + in-flight seconds of every non-terminal session that reached READY
//
// The in-flight term is clamped on both ends so it can never overstate:
//
//     max(0,
//         min(now, end_of_utc_day, ready_at + MAX_SESSION_SECONDS)
//       - max(ready_at, start_of_utc_day))
//
//   * `ready_at` is authoritative_ready_at. A session that never reached READY
//     contributes ZERO — it was provisioned but never billable.
//   * `end_of_utc_day` keeps a session that crosses midnight from charging
//     tomorrow's seconds against today, matching how the usage ledger settles
//     one row per (session, UTC date).
//   * `ready_at + MAX_SESSION_SECONDS` caps a session whose row was orphaned by
//     a crash: it cannot bill more than its own ceiling however long the row
//     sits there un-swept.

const SECOND_MS = 1000

export interface InFlightSession {
  /** authoritative_ready_at; null when the session never became billable. */
  readonly readyAt: Date | null
}

export interface UtcDayBounds {
  readonly start: Date
  readonly end: Date
}

/** [00:00:00, next 00:00:00) of the UTC day containing `now`. */
export function utcDayBounds(now: Date): UtcDayBounds {
  const start = new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate(),
  ))
  const end = new Date(start.getTime() + 24 * 60 * 60 * SECOND_MS)
  return { start, end }
}

/** YYYY-MM-DD for the UTC day containing `now` — the usage ledger's key. */
export function utcDateKey(now: Date): string {
  return now.toISOString().slice(0, 10)
}

/**
 * Seconds one non-terminal session has already consumed today. Floors to whole
 * seconds; a session that never reached READY contributes 0.
 */
export function inFlightSecondsToday(params: {
  readonly session: InFlightSession
  readonly now: Date
  readonly day: UtcDayBounds
  readonly maxSessionSeconds: number
}): number {
  const readyAt = params.session.readyAt
  if (!readyAt || Number.isNaN(readyAt.getTime())) return 0

  const ceiling = readyAt.getTime() + params.maxSessionSeconds * SECOND_MS
  const upper = Math.min(
    params.now.getTime(),
    params.day.end.getTime(),
    ceiling,
  )
  const lower = Math.max(readyAt.getTime(), params.day.start.getTime())
  const elapsedMs = upper - lower
  if (elapsedMs <= 0) return 0
  return Math.floor(elapsedMs / SECOND_MS)
}

/** settled + in-flight, the number the budget gate actually compares. */
export function totalSecondsToday(params: {
  readonly settledSeconds: number
  readonly inFlight: readonly InFlightSession[]
  readonly now: Date
  readonly maxSessionSeconds: number
}): number {
  const day = utcDayBounds(params.now)
  let total = Math.max(0, Math.floor(params.settledSeconds))
  for (const session of params.inFlight) {
    total += inFlightSecondsToday({
      session,
      now: params.now,
      day,
      maxSessionSeconds: params.maxSessionSeconds,
    })
  }
  return total
}

/** Tenant budgets carry headroom so the last session is not cut mid-sentence. */
export function effectiveTenantLimitSeconds(
  dailySecondsPerTenant: number,
  tenantOverageFactor: number,
): number {
  return Math.floor(dailySecondsPerTenant * tenantOverageFactor)
}
