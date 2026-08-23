import { assert, assertEquals } from '@std/assert'
import { SupabaseJwtVerifier } from '../src/jwt.ts'
import { FakeClock } from './fakes.ts'

const SUPABASE_URL = 'https://example.supabase.co'
const ISSUER = `${SUPABASE_URL}/auth/v1`

function b64url(bytes: Uint8Array): string {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function encodeJson(value: unknown): string {
  return b64url(new TextEncoder().encode(JSON.stringify(value)))
}

async function makeKeyPair(kid: string) {
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify'],
  )
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey)
  return { pair, jwk: { ...jwk, kid, alg: 'ES256', use: 'sig' } }
}

async function sign(
  privateKey: CryptoKey,
  kid: string,
  claims: Record<string, unknown>,
  alg = 'ES256',
): Promise<string> {
  const head = encodeJson({ alg, typ: 'JWT', kid })
  const body = encodeJson(claims)
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    privateKey,
    new TextEncoder().encode(`${head}.${body}`) as unknown as ArrayBuffer,
  )
  return `${head}.${body}.${b64url(new Uint8Array(signature))}`
}

function validClaims(overrides: Record<string, unknown> = {}) {
  return {
    sub: 'profile_1',
    iss: ISSUER,
    aud: 'authenticated',
    exp: Math.floor(new Date('2026-08-16T11:00:00Z').getTime() / 1000),
    iat: Math.floor(new Date('2026-08-16T09:00:00Z').getTime() / 1000),
    ...overrides,
  }
}

Deno.test('jwt: a well-formed ES256 token verifies against the published JWKS', async () => {
  const clock = new FakeClock()
  const { pair, jwk } = await makeKeyPair('kid-1')
  const verifier = new SupabaseJwtVerifier({
    supabaseUrl: SUPABASE_URL,
    now: clock.now,
    fetchJwks: () => Promise.resolve({ keys: [jwk] }),
  })
  const result = await verifier.verify(
    await sign(pair.privateKey, 'kid-1', validClaims()),
  )
  assert(result.ok)
  assertEquals(result.claims.sub, 'profile_1')
})

Deno.test('jwt: HS256 is rejected — no shared-secret path exists', async () => {
  const clock = new FakeClock()
  const { jwk } = await makeKeyPair('kid-1')
  const verifier = new SupabaseJwtVerifier({
    supabaseUrl: SUPABASE_URL,
    now: clock.now,
    fetchJwks: () => Promise.resolve({ keys: [jwk] }),
  })
  const forged = `${encodeJson({ alg: 'HS256', kid: 'kid-1' })}.${
    encodeJson(validClaims())
  }.signature`
  const result = await verifier.verify(forged)
  assert(!result.ok)
  assertEquals(result.reason, 'unsupported_algorithm')
})

Deno.test('jwt: wrong issuer, wrong audience and expiry each reject', async () => {
  const clock = new FakeClock()
  const { pair, jwk } = await makeKeyPair('kid-1')
  const verifier = new SupabaseJwtVerifier({
    supabaseUrl: SUPABASE_URL,
    now: clock.now,
    fetchJwks: () => Promise.resolve({ keys: [jwk] }),
  })

  const wrongIssuer = await verifier.verify(
    await sign(
      pair.privateKey,
      'kid-1',
      validClaims({ iss: 'https://evil.example/auth/v1' }),
    ),
  )
  assert(!wrongIssuer.ok)
  assertEquals(wrongIssuer.reason, 'wrong_issuer')

  const wrongAudience = await verifier.verify(
    await sign(pair.privateKey, 'kid-1', validClaims({ aud: 'anon' })),
  )
  assert(!wrongAudience.ok)
  assertEquals(wrongAudience.reason, 'wrong_audience')

  const expired = await verifier.verify(
    await sign(
      pair.privateKey,
      'kid-1',
      validClaims({ exp: Math.floor(new Date('2026-08-16T09:00:00Z').getTime() / 1000) }),
    ),
  )
  assert(!expired.ok)
  assertEquals(expired.reason, 'expired')
})

Deno.test('jwt: an unknown kid triggers exactly one JWKS refresh', async () => {
  const clock = new FakeClock()
  const first = await makeKeyPair('kid-1')
  const rotated = await makeKeyPair('kid-2')
  let fetches = 0
  const verifier = new SupabaseJwtVerifier({
    supabaseUrl: SUPABASE_URL,
    now: clock.now,
    fetchJwks: () => {
      fetches += 1
      return Promise.resolve({
        keys: fetches === 1 ? [first.jwk] : [first.jwk, rotated.jwk],
      })
    },
  })

  const before = await verifier.verify(
    await sign(first.pair.privateKey, 'kid-1', validClaims()),
  )
  assert(before.ok)
  assertEquals(fetches, 1)

  // Rotation: the new kid is unknown, so one forced refresh happens and the
  // token then verifies.
  clock.advance(60_000)
  const after = await verifier.verify(
    await sign(rotated.pair.privateKey, 'kid-2', validClaims()),
  )
  assert(after.ok)
  assertEquals(fetches, 2)
})

Deno.test('jwt: a token signed by the wrong key fails the signature check', async () => {
  const clock = new FakeClock()
  const published = await makeKeyPair('kid-1')
  const attacker = await makeKeyPair('kid-1')
  const verifier = new SupabaseJwtVerifier({
    supabaseUrl: SUPABASE_URL,
    now: clock.now,
    fetchJwks: () => Promise.resolve({ keys: [published.jwk] }),
  })
  const result = await verifier.verify(
    await sign(attacker.pair.privateKey, 'kid-1', validClaims()),
  )
  assert(!result.ok)
  assertEquals(result.reason, 'bad_signature')
})
