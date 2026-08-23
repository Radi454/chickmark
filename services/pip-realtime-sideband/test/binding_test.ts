import { assert, assertEquals } from '@std/assert'
import { bindConnection, parseBindFrame } from '../src/binding.ts'
import type { JwtResult, TokenVerifier } from '../src/jwt.ts'
import { sha256Hex } from '../src/ids.ts'
import { FakeClock, FakeStore } from './fakes.ts'

const BINDING_TOKEN = 'one-time-binding-token'

function verifierFor(sub: string | null): TokenVerifier {
  return {
    verify: (): Promise<JwtResult> =>
      Promise.resolve(
        sub === null ? { ok: false, reason: 'bad_signature' } : {
          ok: true,
          claims: {
            sub,
            iss: 'https://example.supabase.co/auth/v1',
            aud: 'authenticated',
            exp: 9_999_999_999,
          },
        },
      ),
  }
}

async function seededStore(): Promise<FakeStore> {
  const store = new FakeStore()
  store.setCall('sess_1', 1, { bindingTokenHash: await sha256Hex(BINDING_TOKEN) })
  return store
}

function frame(overrides: Record<string, unknown> = {}) {
  return {
    type: 'bind' as const,
    session_id: 'sess_1',
    generation: 1,
    access_token: 'access',
    binding_token: BINDING_TOKEN,
    ...overrides,
  }
}

const authorizeOk = () => Promise.resolve({ authorized: true, fingerprint: 'admin:all' })

Deno.test('bind frame: rejects anything that is not a complete bind frame', () => {
  assertEquals(parseBindFrame('not json'), null)
  assertEquals(parseBindFrame(JSON.stringify({ type: 'health' })), null)
  assertEquals(parseBindFrame(JSON.stringify(frame({ binding_token: '' }))), null)
  assertEquals(parseBindFrame(JSON.stringify(frame({ generation: 0 }))), null)
  assert(parseBindFrame(JSON.stringify(frame())) !== null)
})

// The wire contract lives in WIRE_CONTRACT.md. This literal is asserted
// verbatim on the client side too, by `encodeBindFrame` in
// test/services/realtime/realtime_sideband_channel_test.dart: an edit to either
// side fails the other side's test.
Deno.test('bind frame: the literal the Flutter client encodes is accepted', () => {
  const literal =
    '{"type":"bind","session_id":"sess_1","generation":1,"access_token":"access","binding_token":"one-time-binding-token"}'

  assertEquals(parseBindFrame(literal), {
    type: 'bind',
    session_id: 'sess_1',
    generation: 1,
    access_token: 'access',
    binding_token: 'one-time-binding-token',
  })

  // camelCase is NOT the contract. A client that drifts back to it is refused
  // outright rather than binding with missing fields.
  assertEquals(
    parseBindFrame(JSON.stringify({
      type: 'bind',
      sessionId: 'sess_1',
      generation: 1,
      accessToken: 'access',
      bindingToken: 'one-time-binding-token',
    })),
    null,
  )
  assertEquals(parseBindFrame(JSON.stringify(frame({ session_id: undefined }))), null)
  assertEquals(parseBindFrame(JSON.stringify(frame({ access_token: undefined }))), null)
})

Deno.test('binding token is single-use: the second presentation is rejected', async () => {
  const store = await seededStore()
  const clock = new FakeClock()
  const common = {
    store,
    verifier: verifierFor('profile_1'),
    authorize: authorizeOk,
    now: clock.now(),
  }

  const first = await bindConnection({ frame: frame(), ...common })
  assert(first.ok)

  // The same token replayed — by a retry, or by anyone who intercepted it.
  const second = await bindConnection({ frame: frame(), ...common })
  assert(!second.ok)
  assertEquals(second.reason, 'binding_token_rejected')
  assertEquals(second.detail, 'already_consumed')
})

Deno.test('binding rejects a wrong token, an expired token, and a missing one', async () => {
  const clock = new FakeClock()
  const base = {
    verifier: verifierFor('profile_1'),
    authorize: authorizeOk,
    now: clock.now(),
  }

  const wrong = await bindConnection({
    frame: frame({ binding_token: 'guessed' }),
    store: await seededStore(),
    ...base,
  })
  assert(!wrong.ok)
  assertEquals(wrong.detail, 'mismatch')

  const expiredStore = await seededStore()
  expiredStore.setCall('sess_1', 1, { bindingTokenExpiresAt: '2026-08-16T09:59:00.000Z' })
  const expired = await bindConnection({ frame: frame(), store: expiredStore, ...base })
  assert(!expired.ok)
  assertEquals(expired.detail, 'expired')

  const noToken = new FakeStore()
  const missing = await bindConnection({ frame: frame(), store: noToken, ...base })
  assert(!missing.ok)
  assertEquals(missing.detail, 'no_token_issued')
})

Deno.test('binding rejects an invalid access token before touching the session', async () => {
  const store = await seededStore()
  const result = await bindConnection({
    frame: frame(),
    store,
    verifier: verifierFor(null),
    authorize: authorizeOk,
    now: new FakeClock().now(),
  })
  assert(!result.ok)
  assertEquals(result.reason, 'invalid_token')
  // The one-time token must survive a failed authentication, or an attacker
  // could burn a legitimate user's binding token with a junk JWT.
  assertEquals(store.calls.get('sess_1:1')?.bindingTokenConsumedAt, null)
})

Deno.test('a valid identity that does not own the session is rejected', async () => {
  const store = await seededStore()
  const result = await bindConnection({
    frame: frame(),
    store,
    verifier: verifierFor('profile_other'),
    authorize: authorizeOk,
    now: new FakeClock().now(),
  })
  assert(!result.ok)
  assertEquals(result.reason, 'identity_mismatch')
})

Deno.test('a valid JWT alone does not authorize: server-side scope still decides', async () => {
  const store = await seededStore()
  const result = await bindConnection({
    frame: frame(),
    store,
    verifier: verifierFor('profile_1'),
    // Authenticated, but not approved / no longer allowed.
    authorize: () => Promise.resolve({ authorized: false, fingerprint: '' }),
    now: new FakeClock().now(),
  })
  assert(!result.ok)
  assertEquals(result.reason, 'unauthorized')
  assertEquals(store.calls.get('sess_1:1')?.bindingTokenConsumedAt, null)
})

Deno.test('a changed authorization fingerprint blocks resuming the session', async () => {
  const store = await seededStore()
  const result = await bindConnection({
    frame: frame(),
    store,
    verifier: verifierFor('profile_1'),
    authorize: () =>
      Promise.resolve({ authorized: true, fingerprint: 'customer:cust_9' }),
    now: new FakeClock().now(),
  })
  assert(!result.ok)
  assertEquals(result.reason, 'unauthorized')
})

Deno.test('the kill switch refuses binds', async () => {
  const store = await seededStore()
  store.runtimeControl = { enabled: false, draining: false, forceStopAt: null }
  const result = await bindConnection({
    frame: frame(),
    store,
    verifier: verifierFor('profile_1'),
    authorize: authorizeOk,
    now: new FakeClock().now(),
  })
  assert(!result.ok)
  assertEquals(result.reason, 'kill_switch')
})
