// Identifier, hashing and encoding helpers.

const encoder = new TextEncoder()

export function newId(prefix: string): string {
  return `${prefix}_${crypto.randomUUID()}`
}

export function toHex(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  let out = ''
  for (const byte of view) out += byte.toString(16).padStart(2, '0')
  return out
}

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(input))
  return toHex(digest)
}

/**
 * Constant-time-ish comparison for secrets compared as hex strings. Both inputs
 * are fixed-length digests here, so a length check leaks nothing.
 */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

/**
 * Stable hash of tool-call arguments.
 *
 * Object keys are sorted recursively so two semantically identical argument
 * payloads that differ only in key order produce the SAME hash — otherwise a
 * provider redelivery would look like a different call and defeat idempotency.
 */
export function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value ?? null)
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, entryValue]) => entryValue !== undefined)
    .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))
  return `{${
    entries.map(([key, entryValue]) =>
      `${JSON.stringify(key)}:${canonicalJson(entryValue)}`
    )
      .join(',')
  }}`
}

export function argumentHash(args: unknown): Promise<string> {
  return sha256Hex(canonicalJson(args))
}

export function base64UrlDecode(input: string): Uint8Array {
  const padded = input.replace(/-/g, '+').replace(/_/g, '/')
  const withPadding = padded + '='.repeat((4 - (padded.length % 4)) % 4)
  const binary = atob(withPadding)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

export function base64UrlDecodeToString(input: string): string {
  return new TextDecoder().decode(base64UrlDecode(input))
}

/** ISO-8601 UTC string, the convention used by the shared `text` timestamp columns. */
export function isoAt(date: Date): string {
  return date.toISOString()
}
