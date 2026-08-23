import { assert, assertEquals, assertRejects } from '@std/assert'
import { FenceLostError, LeaseKeeper } from '../src/lease.ts'
import { FakeClock, FakeStore } from './fakes.ts'

function keeper(store: FakeStore, clock: FakeClock, owner: string): LeaseKeeper {
  return new LeaseKeeper({
    store,
    owner,
    leaseSeconds: 30,
    heartbeatSeconds: 10,
    now: clock.now,
    // Timers are injected and never fired: heartbeat behaviour is driven
    // explicitly so the test has no wall-clock dependency.
    setTimer: () => 0,
    clearTimer: () => {},
  })
}

Deno.test('lease: claiming bumps the fencing token', async () => {
  const store = new FakeStore()
  const clock = new FakeClock()
  const first = keeper(store, clock, 'worker_a')
  const handle = await first.claim('sess_1', 1)
  assert(handle)
  assertEquals(handle.fencingToken, 1)
  assertEquals(store.calls.get('sess_1:1')?.leaseOwner, 'worker_a')
})

Deno.test('lease: a live lease held by another worker cannot be claimed', async () => {
  const store = new FakeStore()
  const clock = new FakeClock()
  await keeper(store, clock, 'worker_a').claim('sess_1', 1)
  const second = await keeper(store, clock, 'worker_b').claim('sess_1', 1)
  assertEquals(second, null)
})

Deno.test('lease: an expired lease is reclaimed by compare-and-swap, advancing the fence', async () => {
  const store = new FakeStore()
  const clock = new FakeClock()
  const stale = keeper(store, clock, 'worker_a')
  const first = await stale.claim('sess_1', 1)
  assert(first)

  clock.advance(31_000)
  const fresh = await keeper(store, clock, 'worker_b').claim('sess_1', 1)
  assert(fresh)
  assertEquals(fresh.fencingToken, 2)
})

Deno.test('a stale worker STOPS on fence mismatch: writes fail and the lease is dead', async () => {
  const store = new FakeStore()
  const clock = new FakeClock()
  const stale = keeper(store, clock, 'worker_a')
  await stale.claim('sess_1', 1)

  // The instance pauses; its lease expires; a new worker takes over.
  clock.advance(31_000)
  const fresh = keeper(store, clock, 'worker_b')
  const freshHandle = await fresh.claim('sess_1', 1)
  assert(freshHandle)

  let lostReason: string | null = null
  stale.onLost((reason) => {
    lostReason = reason
  })

  // The stale worker wakes up and tries to write with its old fence.
  await assertRejects(
    () => stale.fencedUpdate({ setupState: 'active' }),
    FenceLostError,
  )
  assertEquals(lostReason, 'fence_lost')
  assertEquals(stale.lost, true)
  assertEquals(stale.held, false)

  // And it may not renew its way back in — reclaim is the new owner's job only.
  assertEquals(await stale.heartbeat(), false)
  // The new owner is unaffected.
  assertEquals(await fresh.heartbeat(), true)
  assertEquals(store.calls.get('sess_1:1')?.leaseOwner, 'worker_b')
})

Deno.test('lease: a failed renewal marks the keeper lost', async () => {
  const store = new FakeStore()
  const clock = new FakeClock()
  const worker = keeper(store, clock, 'worker_a')
  await worker.claim('sess_1', 1)

  // Someone else bumped the fence without the lease expiring (a cleanup sweep).
  store.setCall('sess_1', 1, { fencingToken: 99 })

  let lostReason: string | null = null
  worker.onLost((reason) => {
    lostReason = reason
  })
  assertEquals(await worker.heartbeat(), false)
  assertEquals(lostReason, 'renew_failed')
})

Deno.test('lease: release clears ownership', async () => {
  const store = new FakeStore()
  const clock = new FakeClock()
  const worker = keeper(store, clock, 'worker_a')
  await worker.claim('sess_1', 1)
  await worker.release()
  assertEquals(store.calls.get('sess_1:1')?.leaseOwner, null)
})
