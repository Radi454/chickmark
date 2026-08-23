// Small helpers shared by the IoT gateway. Nothing here touches the network or
// Deno.env, so it is all directly testable.

const HEX = '0123456789abcdef'

export function toHex(bytes: Uint8Array): string {
  let out = ''
  for (const b of bytes) out += HEX[b >> 4] + HEX[b & 15]
  return out
}

export function randomHex(byteLength: number): string {
  const buf = new Uint8Array(byteLength)
  crypto.getRandomValues(buf)
  return toHex(buf)
}

/** Lowercase hex SHA-256 of a UTF-8 string. Mirrors the SQL side exactly:
 *  encode(sha256(convert_to(x,'UTF8')),'hex'). */
export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return toHex(new Uint8Array(digest))
}

/** Constant-time string compare. Length is not secret here (all our secrets are
 *  fixed-width hex), but the content is. */
export function timingSafeEqual(a: string, b: string): boolean {
  if (typeof a !== 'string' || typeof b !== 'string') return false
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000)
}

/** Epoch seconds -> ISO8601, for timestamptz columns. */
export function secondsToIso(seconds: number): string {
  return new Date(seconds * 1000).toISOString()
}

/** ISO8601 (or null) -> epoch seconds (or null). */
export function isoToSeconds(iso: string | null | undefined): number | null {
  if (!iso) return null
  const ms = Date.parse(iso)
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : null
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value))
}

export function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

export function asFiniteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

/** Integer epoch seconds only. Rejects strings, floats and NaN -- the contract
 *  is explicit that timestamps are never strings. */
export function asEpochSeconds(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) && value > 0 ? value : null
}

export function asBoundedInt(value: unknown, min: number, max: number): number | null {
  const n = asFiniteNumber(value)
  if (n === null) return null
  const i = Math.round(n)
  return i >= min && i <= max ? i : null
}

export function asShortString(value: unknown, maxLength: number): string | null {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  if (!trimmed) return null
  return trimmed.slice(0, maxLength)
}

/** Byte length of a UTF-8 encoding. Wire limits are specified in bytes, and a
 *  string's .length counts UTF-16 units -- non-ASCII would pass a byte cap it
 *  actually exceeds. */
export function utf8Length(value: string): number {
  return new TextEncoder().encode(value).length
}
