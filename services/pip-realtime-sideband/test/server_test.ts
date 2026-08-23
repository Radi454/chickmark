import { assert, assertEquals } from '@std/assert'
import {
  CLOSE_BIND_REJECTED,
  CLOSE_BIND_TIMEOUT,
  CLOSE_DRAINING,
  CLOSE_MALFORMED,
  RealtimeServer,
} from '../src/server.ts'
import { testConfig } from '../src/config.ts'
import { sha256Hex } from '../src/ids.ts'
import type { JwtResult, TokenVerifier } from '../src/jwt.ts'
import { runCleanupSweep } from '../src/cleanup.ts'
import { drain } from '../src/drain.ts'
import {
  captureLogs,
  FakeClientSocket,
  FakeClock,
  FakeSidebandSocket,
  FakeStore,
} from './fakes.ts'

const BINDING_TOKEN = 'one-time-binding-token'

const verifier: TokenVerifier = {
  verify: (): Promise<JwtResult> =>
    Promise.resolve({
      ok: true,
      claims: {
        sub: 'profile_1',
        iss: 'https://example.supabase.co/auth/v1',
        aud: 'authenticated',
        exp: 9_999_999_999,
      },
    }),
}

/**
 * Hand-driven timers. Nothing fires on its own, so a test says exactly which
 * deadline elapsed — and a timer that was CLEARED can no longer be fired, which
 * is what proves the bind deadline is disarmed on a healthy session.
 */
/** Let the close path's awaits settle; `#fail` closes asynchronously. */
function flush(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0))
}

function manualTimers() {
  const pending = new Map<number, { fn: () => void; ms: number }>()
  const order: number[] = []
  let nextHandle = 1
  return {
    setTimer(fn: () => void, ms: number): number {
      const handle = nextHandle++
      pending.set(handle, { fn, ms })
      order.push(handle)
      return handle
    },
    clearTimer(handle: number): void {
      pending.delete(handle)
    },
    /** The first timer ever scheduled on a connection is its bind deadline. */
    firstHandle(): number {
      return order[0]
    },
    delayOf(handle: number): number | null {
      return pending.get(handle)?.ms ?? null
    },
    isArmed(handle: number): boolean {
      return pending.has(handle)
    },
    fire(handle: number): void {
      const timer = pending.get(handle)
      if (!timer) return
      pending.delete(handle)
      timer.fn()
    },
  }
}

async function build(
  options: {
    setTimer?: (fn: () => void, ms: number) => number
    clearTimer?: (handle: number) => void
  } = {},
) {
  const store = new FakeStore()
  store.setCall('sess_1', 1, {
    bindingTokenHash: await sha256Hex(BINDING_TOKEN),
    webrtcHealthy: true,
    dataChannelHealthy: true,
  })
  const clock = new FakeClock()
  const providerSocket = new FakeSidebandSocket()
  const server = new RealtimeServer({
    config: testConfig(),
    store,
    verifier,
    authorize: () => Promise.resolve({ authorized: true, fingerprint: 'admin:all' }),
    tools: [],
    ownership: { ledger: 'sideband', executors: new Map() },
    instructions: 'You are ChickMark.',
    now: clock.now,
    openSidebandSocket: () => providerSocket,
    // Heartbeat timers are inert here: renewal is exercised directly in
    // lease_test.ts, and a live 10s timer would leak past the test.
    setTimer: options.setTimer ?? (() => 0),
    clearTimer: options.clearTimer ?? (() => {}),
  })
  const client = new FakeClientSocket()
  const connection = server.attachClient(client)
  return { store, clock, server, client, connection, providerSocket }
}

function bindFrame(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    type: 'bind',
    session_id: 'sess_1',
    generation: 1,
    access_token: 'access-token',
    binding_token: BINDING_TOKEN,
    ...overrides,
  })
}

/**
 * Runs the bind handshake and delivers the provider's `session.updated`.
 *
 * The ack cannot be sent until the sideband exists, and the sideband is created
 * partway through an async bind, so the test waits for it rather than guessing a
 * number of microtask turns.
 */
async function bindAndAck(
  connection: {
    handleClientMessage(raw: string): Promise<void>
    sideband: { handleEvent(event: Record<string, unknown>): Promise<void> } | null
  },
  frame = bindFrame(),
): Promise<void> {
  const bound = connection.handleClientMessage(frame)
  for (let i = 0; i < 200 && !connection.sideband; i++) {
    await new Promise((resolve) => setTimeout(resolve, 0))
  }
  await connection.sideband?.handleEvent({ type: 'session.updated' })
  await bound
}

Deno.test('the first frame must be the bind frame; anything else closes the socket', async () => {
  const { connection, client } = await build()
  await connection.handleClientMessage(JSON.stringify({ type: 'health', webrtc: true }))
  assertEquals(connection.bound, false)
  assertEquals(client.closedWith?.code, CLOSE_MALFORMED)
})

Deno.test('binding, lease and sideband attach run in order, and READY follows the ack', async () => {
  const { connection, client, store, providerSocket } = await build()
  await bindAndAck(connection)

  assertEquals(connection.bound, true)
  assertEquals(providerSocket.sentOfType('session.update').length, 1)
  const update = providerSocket.sentOfType('session.update')[0] as Record<string, unknown>
  const configured = update.session as Record<string, unknown>
  assertEquals(configured.instructions, 'You are ChickMark.')
  assertEquals(client.noticeTypes(), ['ready'])
  assertEquals(store.calls.get('sess_1:1')?.setupState, 'active')
  // The binding token is spent.
  assert(store.calls.get('sess_1:1')?.bindingTokenConsumedAt !== null)
})

Deno.test('READY is withheld when the client has not reported WebRTC health', async () => {
  const { connection, client, store } = await build()
  store.setCall('sess_1', 1, { webrtcHealthy: false, dataChannelHealthy: false })

  await bindAndAck(connection)

  assertEquals(client.noticeTypes(), [])
  assertEquals(connection.sideband?.gate.missing.sort(), [
    'dataChannelHealthy',
    'webrtcHealthy',
  ])

  // The client reports both legs healthy; READY follows immediately.
  await connection.handleClientMessage(
    JSON.stringify({ type: 'health', webrtc: true, data_channel: true }),
  )
  assertEquals(client.noticeTypes(), ['ready'])
})

Deno.test('a health frame right behind the bind frame is queued, not fatal', async () => {
  const { connection, client, store } = await build()
  // The client is the one reporting health here; the seeded row must not
  // pre-mark the legs healthy.
  store.setCall('sess_1', 1, { webrtcHealthy: false, dataChannelHealthy: false })

  // Production delivery is fire-and-forget: the socket hands over both frames
  // back-to-back and nothing awaits the bind before the health frame lands.
  const bound = connection.handleClientMessage(bindFrame())
  const health = connection.handleClientMessage(
    JSON.stringify({ type: 'health', webrtc: true, data_channel: true }),
  )
  for (let i = 0; i < 200 && !connection.sideband; i++) await flush()
  await connection.sideband?.handleEvent({ type: 'session.updated' })
  await bound
  await health

  assertEquals(client.closedWith ?? null, null)
  assertEquals(connection.bound, true)
  assertEquals(client.noticeTypes(), ['ready'])
})

Deno.test('a socket that dies mid-bind never keeps the lease', async () => {
  const { connection, store } = await build()
  const bound = connection.handleClientMessage(bindFrame())
  await connection.close('client_socket_closed')
  await bound
  await flush()

  assertEquals(connection.bound, false)
  assertEquals(store.calls.get('sess_1:1')?.leaseOwner ?? null, null)
})

Deno.test('a rejected bind never reaches the provider', async () => {
  const store = new FakeStore()
  const clock = new FakeClock()
  const providerSocket = new FakeSidebandSocket()
  const server = new RealtimeServer({
    config: testConfig(),
    store,
    verifier,
    authorize: () => Promise.resolve({ authorized: false, fingerprint: '' }),
    tools: [],
    ownership: { ledger: 'sideband', executors: new Map() },
    instructions: 'You are ChickMark.',
    now: clock.now,
    openSidebandSocket: () => providerSocket,
    // Heartbeat timers are inert here: renewal is exercised directly in
    // lease_test.ts, and a live 10s timer would leak past the test.
    setTimer: () => 0,
    clearTimer: () => {},
  })
  const client = new FakeClientSocket()
  const connection = server.attachClient(client)
  await connection.handleClientMessage(bindFrame())

  assertEquals(connection.bound, false)
  assertEquals(client.closedWith?.code, CLOSE_BIND_REJECTED)
  assertEquals(providerSocket.sent.length, 0)
})

Deno.test('the bind frame is never logged', async () => {
  const capture = captureLogs()
  try {
    const { connection } = await build()
    await bindAndAck(connection)
    const joined = capture.lines.join('\n')
    assert(!joined.includes(BINDING_TOKEN))
    assert(!joined.includes('access-token'))
  } finally {
    capture.restore()
  }
})

Deno.test('SIGTERM hands off in ONE batched write and closes clients inside the budget', async () => {
  const { server, connection, client, store } = await build()
  await bindAndAck(connection)

  const report = await server.drainNow()

  assertEquals(store.handoffCalls, 1)
  assertEquals(report.handedOff, 1)
  assertEquals(report.closed, 1)
  assert(report.withinBudget)
  // Well inside Cloud Run's fixed 10s grace.
  assert(report.durationMs < 1000)
  assertEquals(client.closedWith?.code, CLOSE_DRAINING)

  const call = store.calls.get('sess_1:1')
  assertEquals(call?.setupState, 'cleanup_pending')
  assertEquals(call?.endReason, 'server_drain')
  assertEquals(call?.leaseOwner, null)
  assertEquals(server.draining, true)
})

Deno.test('a slow database cannot consume the whole SIGTERM grace', async () => {
  const store = new FakeStore()
  const config = testConfig({ drainBudgetMs: 50 })
  // A handoff that never returns — the failure the 10s SIGKILL punishes.
  store.markGenerationsCleanupPending = () => new Promise<number>(() => {})
  const started = Date.now()
  const report = await drain({
    store,
    config,
    registry: new (await import('../src/drain.ts')).ConnectionRegistry(),
    owner: 'worker_a',
    now: () => new Date(),
  })
  assertEquals(report.handedOff, -1)
  assert(Date.now() - started < 1000)
})

Deno.test('the drain defers hangups to the sweeper instead of doing them itself', async () => {
  const store = new FakeStore()
  store.setCall('sess_1', 1, {
    bindingTokenHash: await sha256Hex(BINDING_TOKEN),
    webrtcHealthy: true,
    dataChannelHealthy: true,
  })
  let hangups = 0
  const hangup = () => {
    hangups += 1
    return Promise.resolve('succeeded' as const)
  }
  const server = new RealtimeServer({
    config: testConfig(),
    store,
    verifier,
    authorize: () => Promise.resolve({ authorized: true, fingerprint: 'admin:all' }),
    tools: [],
    ownership: { ledger: 'sideband', executors: new Map() },
    instructions: 'You are ChickMark.',
    now: new FakeClock().now,
    openSidebandSocket: () => new FakeSidebandSocket(),
    hangup,
    setTimer: () => 0,
    clearTimer: () => {},
  })
  const connection = server.attachClient(new FakeClientSocket())
  await bindAndAck(connection)

  await server.drainNow()
  // No third-party round trip inside the 10s grace.
  assertEquals(hangups, 0)
  assertEquals(store.calls.get('sess_1:1')?.setupState, 'cleanup_pending')

  // The sweeper picks up exactly what the drain handed off.
  const report = await runCleanupSweep({
    store,
    config: testConfig(),
    hangup,
    now: () => new Date('2026-08-16T10:05:00.000Z'),
  })
  assertEquals(report.terminalized, 1)
  assertEquals(hangups, 1)
})

Deno.test('cleanup sweeps expired setups and cleanup_pending generations idempotently', async () => {
  const store = new FakeStore()
  store.setCall('sess_1', 1, {
    setupState: 'sideband_connecting',
    setupDeadlineAt: '2026-08-16T09:00:00.000Z',
  })
  const hangups: string[] = []

  const report = await runCleanupSweep({
    store,
    config: testConfig(),
    hangup: (callId) => {
      hangups.push(callId)
      return Promise.resolve('succeeded')
    },
    now: () => new Date('2026-08-16T10:00:00.000Z'),
  })

  assertEquals(report.claimed, 1)
  assertEquals(report.terminalized, 1)
  assertEquals(hangups, ['rtc_abc'])
  const call = store.calls.get('sess_1:1')
  assertEquals(call?.setupState, 'ended')
  assertEquals(call?.hangupState, 'succeeded')
  // The fence advanced past any worker that still thinks it owns this.
  assertEquals(call?.fencingToken, 1)

  // A second sweep finds nothing: terminal states are not candidates.
  const second = await runCleanupSweep({
    store,
    config: testConfig(),
    hangup: (callId) => {
      hangups.push(callId)
      return Promise.resolve('succeeded')
    },
    now: () => new Date('2026-08-16T10:01:00.000Z'),
  })
  assertEquals(second.examined, 0)
  assertEquals(hangups.length, 1)
})

Deno.test('a non-2xx hangup is treated as done, not retried forever', async () => {
  const store = new FakeStore()
  store.setCall('sess_1', 1, { setupState: 'cleanup_pending' })
  const report = await runCleanupSweep({
    store,
    config: testConfig(),
    hangup: () => Promise.resolve('failed'),
    now: () => new Date('2026-08-16T10:00:00.000Z'),
  })
  assertEquals(report.terminalized, 1)
  assertEquals(store.calls.get('sess_1:1')?.setupState, 'ended')
  assertEquals(store.calls.get('sess_1:1')?.hangupState, 'failed')
})

Deno.test('cleanup settles usage for sessions terminalized without settlement', async () => {
  const store = new FakeStore({
    session: {
      state: 'ended',
      authoritativeReadyAt: '2026-08-16T09:50:00.000Z',
      endedAt: '2026-08-16T10:00:00.000Z',
    },
    call: { setupState: 'ended' },
  })
  const report = await runCleanupSweep({
    store,
    config: testConfig(),
    hangup: () => Promise.resolve('succeeded'),
    now: () => new Date('2026-08-16T10:05:00.000Z'),
  })
  assertEquals(report.settled, 1)
  assertEquals(store.usage.get('sess_1:2026-08-16')?.seconds, 600)
})

Deno.test('cleanup is unauthenticated-proof: no OIDC token means 401', async () => {
  const { server } = await build()
  const response = await server.handle(
    new Request('https://service/internal/cleanup', { method: 'POST' }),
  )
  assertEquals(response.status, 401)
})

Deno.test('an unconfigured cleanup audience refuses to accept any token', async () => {
  const { server } = await build()
  const response = await server.handle(
    new Request('https://service/internal/cleanup', {
      method: 'POST',
      headers: { authorization: 'Bearer whatever' },
    }),
  )
  assertEquals(response.status, 401)
})

Deno.test('health reports draining after SIGTERM so the load balancer stops sending work', async () => {
  const { server } = await build()
  assertEquals((await server.handle(new Request('https://service/healthz'))).status, 200)
  await server.drainNow()
  assertEquals((await server.handle(new Request('https://service/healthz'))).status, 503)
})

// ---------------------------------------------------------------------------
// BIND DEADLINE. An upgraded socket that never binds holds a Cloud Run
// concurrency slot for its whole life. This service runs with held WebSockets
// and a small max-instance count, so a silent, unauthenticated socket is an
// availability cost — it is closed with 4408, which the client already maps.
// ---------------------------------------------------------------------------

Deno.test('a socket that never sends a bind frame is closed 4408', async () => {
  const timers = manualTimers()
  const { client, connection } = await build({
    setTimer: timers.setTimer,
    clearTimer: timers.clearTimer,
  })

  const deadline = timers.firstHandle()
  assertEquals(timers.delayOf(deadline), testConfig().bindDeadlineSeconds * 1000)

  timers.fire(deadline)
  await flush()

  assertEquals(client.closedWith?.code, CLOSE_BIND_TIMEOUT)
  assertEquals(client.closedWith?.reason, 'bind_timeout')
  // The client is TOLD why, rather than seeing an unexplained disconnect.
  assertEquals(client.noticeTypes(), ['error'])
  assertEquals(client.notices()[0].code, 'bind_timeout')
  assertEquals(connection.bound, false)
})

Deno.test('a bind that arrives in time succeeds and disarms the deadline', async () => {
  const timers = manualTimers()
  const { client, connection } = await build({
    setTimer: timers.setTimer,
    clearTimer: timers.clearTimer,
  })
  const deadline = timers.firstHandle()

  await bindAndAck(connection)

  assertEquals(connection.bound, true)
  // Disarmed: a healthy session lives for minutes and must never be closed by
  // a deadline that was only ever about the handshake.
  assertEquals(timers.isArmed(deadline), false)
  timers.fire(deadline)
  await flush()
  assertEquals(client.closedWith, null)
  assert(client.noticeTypes().includes('ready'))
})

Deno.test('a late timer cannot close an already bound session', async () => {
  // Belt and braces: even if the handle were fired after bind — a race between
  // the timer firing and the bind completing — the callback re-checks state.
  const fired: (() => void)[] = []
  const { client, connection } = await build({
    setTimer: (fn) => {
      fired.push(fn)
      return fired.length
    },
    clearTimer: () => {},
  })

  await bindAndAck(connection)
  for (const fn of fired) fn()
  await flush()

  assertEquals(client.closedWith, null)
  assertEquals(connection.bound, true)
})

Deno.test('a malformed first frame still closes on the malformed path, not 4408', async () => {
  const timers = manualTimers()
  const { client, connection } = await build({
    setTimer: timers.setTimer,
    clearTimer: timers.clearTimer,
  })

  await connection.handleClientMessage('not a frame')

  assertEquals(client.closedWith?.code, CLOSE_MALFORMED)
  assertEquals(client.closedWith?.reason, 'bind_frame_required')
  assertEquals(connection.bound, false)
  // And the deadline is disarmed by the close, so nothing fires afterwards.
  assertEquals(timers.isArmed(timers.firstHandle()), false)
})
