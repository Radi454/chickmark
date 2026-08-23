// Google OIDC verification for POST /internal/cleanup.
//
// Cloud Scheduler calls the endpoint with an OIDC ID token minted for a specific
// service account and audience. Both are checked: the audience stops a token
// issued for some other service being replayed here, and the service-account
// allowlist stops any other identity in the project from sweeping sessions.

import { base64UrlDecode, base64UrlDecodeToString } from './ids.ts'

const GOOGLE_JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs'
const GOOGLE_ISSUERS = ['https://accounts.google.com', 'accounts.google.com']
const CLOCK_SKEW_SECONDS = 60

export type OidcFailure =
  | 'missing_token'
  | 'malformed'
  | 'unsupported_algorithm'
  | 'unknown_key'
  | 'bad_signature'
  | 'expired'
  | 'wrong_issuer'
  | 'wrong_audience'
  | 'not_allowed'
  | 'not_configured'

export type OidcResult =
  | { readonly ok: true; readonly email: string }
  | { readonly ok: false; readonly reason: OidcFailure }

interface RsaJwk {
  kid?: string
  kty?: string
  alg?: string
  n?: string
  e?: string
}

const keyCache = new Map<string, CryptoKey>()
let lastFetchMs = 0

async function loadKeys(
  fetchImpl: typeof fetch,
  force: boolean,
  nowMs: number,
): Promise<void> {
  if (!force && keyCache.size > 0) return
  if (force && nowMs - lastFetchMs < 30_000 && keyCache.size > 0) return
  const response = await fetchImpl(GOOGLE_JWKS_URL)
  if (!response.ok) throw new Error(`google_jwks_status_${response.status}`)
  const document = await response.json() as { keys?: RsaJwk[] }
  keyCache.clear()
  for (const jwk of document.keys ?? []) {
    if (jwk.kty !== 'RSA' || !jwk.kid) continue
    const key = await crypto.subtle.importKey(
      'jwk',
      { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    )
    keyCache.set(jwk.kid, key)
  }
  lastFetchMs = nowMs
}

export function resetOidcKeyCache(): void {
  keyCache.clear()
  lastFetchMs = 0
}

export async function verifyGoogleOidc(
  token: string,
  options: {
    audience: string
    allowedEmails: readonly string[]
    now: () => Date
    fetchImpl?: typeof fetch
  },
): Promise<OidcResult> {
  if (!token) return { ok: false, reason: 'missing_token' }
  // Refusing to run unconfigured is deliberate: an empty audience or an empty
  // allowlist would otherwise accept any Google-signed token in existence.
  if (!options.audience || options.allowedEmails.length === 0) {
    return { ok: false, reason: 'not_configured' }
  }

  const parts = token.split('.')
  if (parts.length !== 3) return { ok: false, reason: 'malformed' }

  let header: { alg?: string; kid?: string }
  let claims: {
    iss?: string
    aud?: string
    exp?: number
    email?: string
    email_verified?: boolean
  }
  try {
    header = JSON.parse(base64UrlDecodeToString(parts[0]))
    claims = JSON.parse(base64UrlDecodeToString(parts[1]))
  } catch {
    return { ok: false, reason: 'malformed' }
  }

  if (header.alg !== 'RS256') return { ok: false, reason: 'unsupported_algorithm' }
  if (!header.kid) return { ok: false, reason: 'malformed' }

  const fetchImpl = options.fetchImpl ?? fetch
  const nowMs = options.now().getTime()
  await loadKeys(fetchImpl, false, nowMs)
  let key = keyCache.get(header.kid)
  if (!key) {
    await loadKeys(fetchImpl, true, nowMs)
    key = keyCache.get(header.kid)
  }
  if (!key) return { ok: false, reason: 'unknown_key' }

  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    base64UrlDecode(parts[2]) as unknown as ArrayBuffer,
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`) as unknown as ArrayBuffer,
  )
  if (!valid) return { ok: false, reason: 'bad_signature' }

  const nowSeconds = Math.floor(nowMs / 1000)
  if (typeof claims.exp !== 'number' || claims.exp + CLOCK_SKEW_SECONDS < nowSeconds) {
    return { ok: false, reason: 'expired' }
  }
  if (!claims.iss || !GOOGLE_ISSUERS.includes(claims.iss)) {
    return { ok: false, reason: 'wrong_issuer' }
  }
  if (claims.aud !== options.audience) return { ok: false, reason: 'wrong_audience' }
  const email = claims.email ?? ''
  if (!email || claims.email_verified === false) {
    return { ok: false, reason: 'not_allowed' }
  }
  if (!options.allowedEmails.includes(email)) return { ok: false, reason: 'not_allowed' }

  return { ok: true, email }
}
