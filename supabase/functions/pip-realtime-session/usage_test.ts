import { assertEquals } from '@std/assert'

import {
  effectiveTenantLimitSeconds,
  inFlightSecondsToday,
  totalSecondsToday,
  utcDateKey,
  utcDayBounds,
} from './usage.ts'

const MAX = 600

function at(iso: string): Date {
  return new Date(iso)
}

Deno.test('utc day bounds and key split on UTC midnight', () => {
  const now = at('2026-08-16T23:59:59.000Z')
  const day = utcDayBounds(now)
  assertEquals(day.start.toISOString(), '2026-08-16T00:00:00.000Z')
  assertEquals(day.end.toISOString(), '2026-08-17T00:00:00.000Z')
  assertEquals(utcDateKey(now), '2026-08-16')
})

Deno.test('a session that never reached READY contributes zero in-flight', () => {
  const now = at('2026-08-16T12:00:00.000Z')
  assertEquals(
    inFlightSecondsToday({
      session: { readyAt: null },
      now,
      day: utcDayBounds(now),
      maxSessionSeconds: MAX,
    }),
    0,
  )
})

Deno.test('in-flight seconds are the elapsed seconds since READY', () => {
  const now = at('2026-08-16T12:05:00.000Z')
  assertEquals(
    inFlightSecondsToday({
      session: { readyAt: at('2026-08-16T12:00:00.000Z') },
      now,
      day: utcDayBounds(now),
      maxSessionSeconds: MAX,
    }),
    300,
  )
})

Deno.test('in-flight seconds are capped at ready + MAX_SESSION_SECONDS', () => {
  // An orphaned row left behind by a crash must not bill for hours.
  const now = at('2026-08-16T20:00:00.000Z')
  assertEquals(
    inFlightSecondsToday({
      session: { readyAt: at('2026-08-16T08:00:00.000Z') },
      now,
      day: utcDayBounds(now),
      maxSessionSeconds: MAX,
    }),
    MAX,
  )
})

Deno.test('a session that became ready yesterday only bills today from midnight', () => {
  const now = at('2026-08-16T00:03:00.000Z')
  assertEquals(
    inFlightSecondsToday({
      session: { readyAt: at('2026-08-15T23:58:00.000Z') },
      now,
      day: utcDayBounds(now),
      maxSessionSeconds: MAX,
    }),
    180,
  )
})

Deno.test('a ready timestamp in the future contributes zero, never negative', () => {
  const now = at('2026-08-16T12:00:00.000Z')
  assertEquals(
    inFlightSecondsToday({
      session: { readyAt: at('2026-08-16T12:10:00.000Z') },
      now,
      day: utcDayBounds(now),
      maxSessionSeconds: MAX,
    }),
    0,
  )
})

Deno.test('total combines settled seconds with every in-flight session', () => {
  const now = at('2026-08-16T12:05:00.000Z')
  assertEquals(
    totalSecondsToday({
      settledSeconds: 1500,
      inFlight: [
        { readyAt: at('2026-08-16T12:00:00.000Z') }, // 300
        { readyAt: null }, // 0
        { readyAt: at('2026-08-16T11:00:00.000Z') }, // capped at 600
      ],
      now,
      maxSessionSeconds: MAX,
    }),
    2400,
  )
})

Deno.test('the tenant limit carries the overage factor', () => {
  assertEquals(effectiveTenantLimitSeconds(14400, 1.25), 18000)
  assertEquals(effectiveTenantLimitSeconds(14400, 1), 14400)
})
