import { assert, assertEquals } from '@std/assert'
import { settleSessionUsage, splitByUtcDay } from '../src/usage.ts'
import { FakeStore } from './fakes.ts'

function totalOf(slices: readonly { seconds: number }[]): number {
  return slices.reduce((sum, slice) => sum + slice.seconds, 0)
}

Deno.test('a session inside one UTC day settles as a single slice', () => {
  const slices = splitByUtcDay(
    new Date('2026-08-16T10:00:00Z'),
    new Date('2026-08-16T10:08:20Z'),
  )
  assertEquals(slices.length, 1)
  assertEquals(slices[0], { usageDate: '2026-08-16', seconds: 500 })
})

Deno.test('a session crossing midnight splits into two slices that sum exactly', () => {
  const start = new Date('2026-08-16T23:55:00Z')
  const end = new Date('2026-08-17T00:05:00Z')
  const slices = splitByUtcDay(start, end)

  assertEquals(slices.length, 2)
  assertEquals(slices[0], { usageDate: '2026-08-16', seconds: 300 })
  assertEquals(slices[1], { usageDate: '2026-08-17', seconds: 300 })
  assertEquals(totalOf(slices), 600)
})

Deno.test('sub-second boundaries never lose or invent seconds', () => {
  const start = new Date('2026-08-16T23:59:59.400Z')
  const end = new Date('2026-08-17T00:00:30.900Z')
  const slices = splitByUtcDay(start, end)
  const expected = Math.round((end.getTime() - start.getTime()) / 1000)
  assertEquals(totalOf(slices), expected)
  assertEquals(slices.map((slice) => slice.usageDate), ['2026-08-16', '2026-08-17'])
})

Deno.test('a session spanning three UTC days produces three slices summing to the total', () => {
  const start = new Date('2026-08-15T23:00:00Z')
  const end = new Date('2026-08-17T01:00:00Z')
  const slices = splitByUtcDay(start, end)
  assertEquals(slices.length, 3)
  assertEquals(totalOf(slices), 26 * 3600)
})

Deno.test('settlement writes the ledger and marks the session settled', async () => {
  const store = new FakeStore({
    session: {
      state: 'ended',
      authoritativeReadyAt: '2026-08-16T23:55:00.000Z',
      endedAt: '2026-08-17T00:05:00.000Z',
    },
  })
  const session = (await store.loadSession('sess_1'))!
  const result = await settleSessionUsage({ store, session, now: new Date() })

  assert(result.settled)
  assertEquals(result.seconds, 600)
  assertEquals(store.usage.size, 2)
  assertEquals(store.usage.get('sess_1:2026-08-16')?.seconds, 300)
  assertEquals(store.usage.get('sess_1:2026-08-17')?.seconds, 300)
  assert((await store.loadSession('sess_1'))!.usageSettledAt !== null)
})

Deno.test('double settlement is blocked and never double-counts seconds', async () => {
  const store = new FakeStore({
    session: {
      state: 'ended',
      authoritativeReadyAt: '2026-08-16T10:00:00.000Z',
      endedAt: '2026-08-16T10:10:00.000Z',
    },
  })
  const session = (await store.loadSession('sess_1'))!

  const first = await settleSessionUsage({ store, session, now: new Date() })
  assert(first.settled)
  assertEquals(store.usage.get('sess_1:2026-08-16')?.seconds, 600)

  // A retry that still holds the pre-settlement snapshot — the case a crashed
  // worker plus the sweeper actually produces.
  const second = await settleSessionUsage({ store, session, now: new Date() })
  assert(!second.settled)
  assertEquals(second.reason, 'already_settled')
  assertEquals(store.usage.size, 1)
  assertEquals(store.usage.get('sess_1:2026-08-16')?.seconds, 600)

  // And a settlement driven from the reloaded row short-circuits immediately.
  const reloaded = (await store.loadSession('sess_1'))!
  const third = await settleSessionUsage({ store, session: reloaded, now: new Date() })
  assert(!third.settled)
  assertEquals(third.reason, 'already_settled')
})

Deno.test('a session that never reached READY settles as zero, not as unsettled forever', async () => {
  const store = new FakeStore({
    session: { state: 'failed', authoritativeReadyAt: null },
  })
  const session = (await store.loadSession('sess_1'))!
  const result = await settleSessionUsage({ store, session, now: new Date() })

  assert(!result.settled)
  assertEquals(result.reason, 'never_active')
  assertEquals(store.usage.size, 0)
  assert((await store.loadSession('sess_1'))!.usageSettledAt !== null)
})
