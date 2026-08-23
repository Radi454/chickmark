// supabase/functions/pip-realtime-session/binding_token.ts
//
// The binding token is the one-shot proof the client presents to the sideband
// service to bind itself to a pre-provisioned generation. It is returned to the
// caller EXACTLY ONCE, in the body of a successful `start`, and never again:
// only its SHA-256 hash reaches the database, so a later read of
// agent_realtime_calls (by an operator, a backup, or a leaked dump) cannot
// recover a usable token.
//
// Never log a token, and never echo one back on any action other than start.

const TOKEN_BYTES = 32 // 256 bits

export interface BindingToken {
  /** The secret. Returned to the client once; never stored, never logged. */
  readonly token: string
  /** SHA-256 hex of the token. This is what the database holds. */
  readonly hash: string
}

export async function issueBindingToken(
  generate: () => string = generateBindingTokenValue,
): Promise<BindingToken> {
  const token = generate()
  return { token, hash: await hashBindingToken(token) }
}

/** 256 bits of CSPRNG entropy, base64url encoded (no padding). */
export function generateBindingTokenValue(): string {
  const bytes = new Uint8Array(TOKEN_BYTES)
  crypto.getRandomValues(bytes)
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

export async function hashBindingToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(token),
  )
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}
