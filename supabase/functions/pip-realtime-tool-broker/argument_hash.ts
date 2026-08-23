// Argument canonicalisation and constant-time comparison.
//
// This MUST stay byte-compatible with services/pip-realtime-sideband/src/ids.ts.
// The sideband hashes the arguments it received from the provider; the broker
// re-hashes the arguments it was handed. If the two encodings ever diverge, a
// perfectly ordinary redelivery would look like an argument conflict and be
// refused. It is duplicated rather than imported because an edge function and a
// Cloud Run service do not share a module graph — the parity is enforced by
// tests on both sides, not by the file system.

const encoder = new TextEncoder()

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(value))
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

/**
 * Stable JSON encoding: object keys sorted recursively, `undefined` dropped, so
 * two semantically identical argument payloads that differ only in key order
 * hash the same.
 */
export function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value ?? null)
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, entryValue]) => entryValue !== undefined)
    .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))
  return `{${
    entries
      .map(([key, entryValue]) =>
        `${JSON.stringify(key)}:${canonicalJson(entryValue)}`
      )
      .join(',')
  }}`
}

export function argumentHash(args: unknown): Promise<string> {
  return sha256Hex(canonicalJson(args))
}

/**
 * Constant-time comparison for secrets and digests presented as strings.
 *
 * The length check leaks only the length. For the shared secret that is an
 * acceptable disclosure (it is fixed-length per deployment and an attacker who
 * can guess the length has learned nothing about the bytes); for hex digests it
 * is constant by construction.
 */
export function timingSafeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false
  let diff = 0
  for (let index = 0; index < left.length; index++) {
    diff |= left.charCodeAt(index) ^ right.charCodeAt(index)
  }
  return diff === 0
}
