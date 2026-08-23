// Supabase access-token verification.
//
// Supabase signs asymmetrically with ES256. Verification is therefore local
// against the project's published JWKS — there is no shared JWT secret to hold,
// and no auth round-trip per connection.
//
// A verified token proves IDENTITY ONLY. It says nothing about approval status,
// role, or which customer the caller may touch: those are resolved server-side
// from the database by the caller of this module.

import { base64UrlDecode, base64UrlDecodeToString } from './ids.ts'

export interface JwtClaims {
  readonly sub: string
  readonly iss: string
  readonly aud: string | string[]
  readonly exp: number
  readonly iat?: number
  readonly email?: string
  readonly role?: string
}

export type JwtFailure =
  | 'malformed'
  | 'unsupported_algorithm'
  | 'unknown_key'
  | 'bad_signature'
  | 'expired'
  | 'not_yet_valid'
  | 'wrong_issuer'
  | 'wrong_audience'

export type JwtResult =
  | { ok: true; claims: JwtClaims }
  | { ok: false; reason: JwtFailure }

interface Jwk {
  kid?: string
  kty?: string
  alg?: string
  crv?: string
  x?: string
  y?: string
  use?: string
}

/**
 * The verification port. Callers depend on this rather than on the concrete
 * class so a test can substitute a double without a network or a key pair.
 */
export interface TokenVerifier {
  verify(token: string): Promise<JwtResult>
}

export interface JwksFetcher {
  (url: string): Promise<{ keys: Jwk[] }>
}

/** Clock skew tolerated on `exp`/`iat`, bounded so an expired token cannot linger. */
const CLOCK_SKEW_SECONDS = 60

/** Never re-fetch the JWKS more often than this, even on repeated unknown kids. */
const MIN_REFRESH_INTERVAL_MS = 30_000

export class SupabaseJwtVerifier implements TokenVerifier {
  readonly #jwksUrl: string
  readonly #issuer: string
  readonly #fetchJwks: JwksFetcher
  readonly #now: () => Date
  #keys = new Map<string, CryptoKey>()
  #lastFetchMs = 0
  #inFlight: Promise<void> | null = null

  constructor(options: {
    supabaseUrl: string
    fetchJwks?: JwksFetcher
    now?: () => Date
  }) {
    const base = options.supabaseUrl.replace(/\/+$/, '')
    this.#jwksUrl = `${base}/auth/v1/.well-known/jwks.json`
    this.#issuer = `${base}/auth/v1`
    this.#now = options.now ?? (() => new Date())
    this.#fetchJwks = options.fetchJwks ?? (async (url) => {
      const response = await fetch(url, { headers: { accept: 'application/json' } })
      if (!response.ok) throw new Error(`jwks_status_${response.status}`)
      return await response.json() as { keys: Jwk[] }
    })
  }

  async #refresh(force: boolean): Promise<void> {
    const nowMs = this.#now().getTime()
    if (!force && this.#keys.size > 0) return
    if (nowMs - this.#lastFetchMs < MIN_REFRESH_INTERVAL_MS && this.#keys.size > 0) return
    if (this.#inFlight) return await this.#inFlight

    this.#inFlight = (async () => {
      const document = await this.#fetchJwks(this.#jwksUrl)
      const next = new Map<string, CryptoKey>()
      for (const jwk of document.keys ?? []) {
        if (jwk.kty !== 'EC' || jwk.crv !== 'P-256' || !jwk.kid) continue
        const key = await crypto.subtle.importKey(
          'jwk',
          { kty: 'EC', crv: 'P-256', x: jwk.x, y: jwk.y, ext: true },
          { name: 'ECDSA', namedCurve: 'P-256' },
          false,
          ['verify'],
        )
        next.set(jwk.kid, key)
      }
      this.#keys = next
      this.#lastFetchMs = this.#now().getTime()
    })()

    try {
      await this.#inFlight
    } finally {
      this.#inFlight = null
    }
  }

  async verify(token: string): Promise<JwtResult> {
    const parts = token.split('.')
    if (parts.length !== 3) return { ok: false, reason: 'malformed' }

    let header: { alg?: string; kid?: string }
    let claims: JwtClaims
    try {
      header = JSON.parse(base64UrlDecodeToString(parts[0]))
      claims = JSON.parse(base64UrlDecodeToString(parts[1])) as JwtClaims
    } catch {
      return { ok: false, reason: 'malformed' }
    }

    // HS256 is rejected outright: accepting it would re-open the shared-secret
    // path this design deliberately does not have, and is the classic algorithm
    // confusion attack.
    if (header.alg !== 'ES256') return { ok: false, reason: 'unsupported_algorithm' }
    if (!header.kid) return { ok: false, reason: 'malformed' }

    await this.#refresh(false)
    let key = this.#keys.get(header.kid)
    if (!key) {
      // Unknown kid means a rotation may have happened; refresh once, rate-limited.
      await this.#refresh(true)
      key = this.#keys.get(header.kid)
    }
    if (!key) return { ok: false, reason: 'unknown_key' }

    const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`)
    let signature: Uint8Array
    try {
      signature = base64UrlDecode(parts[2])
    } catch {
      return { ok: false, reason: 'malformed' }
    }

    const valid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      key,
      signature as unknown as ArrayBuffer,
      signed as unknown as ArrayBuffer,
    )
    if (!valid) return { ok: false, reason: 'bad_signature' }

    const nowSeconds = Math.floor(this.#now().getTime() / 1000)
    if (typeof claims.exp !== 'number') return { ok: false, reason: 'malformed' }
    if (claims.exp + CLOCK_SKEW_SECONDS < nowSeconds) {
      return { ok: false, reason: 'expired' }
    }
    if (typeof claims.iat === 'number' && claims.iat - CLOCK_SKEW_SECONDS > nowSeconds) {
      return { ok: false, reason: 'not_yet_valid' }
    }
    if (claims.iss !== this.#issuer) return { ok: false, reason: 'wrong_issuer' }

    const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud]
    if (!audiences.includes('authenticated')) {
      return { ok: false, reason: 'wrong_audience' }
    }
    if (typeof claims.sub !== 'string' || claims.sub === '') {
      return { ok: false, reason: 'malformed' }
    }

    return { ok: true, claims }
  }
}
