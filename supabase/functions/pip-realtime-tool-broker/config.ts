// supabase/functions/pip-realtime-tool-broker/config.ts
//
// The broker's only knob is the shared secret the Cloud Run sideband presents.
//
// FAIL CLOSED. When PIP_REALTIME_BROKER_SECRET is absent, blank, or too short to
// be a real secret, `readBrokerSecret` returns null and the endpoint refuses
// every request with 503. It must never degrade into "no secret configured, so
// accept anyone" — that would turn the least-privilege boundary into an open
// door onto the whole tool catalogue.

/** Reads one environment variable. Injectable so tests never touch Deno.env. */
export type EnvReader = (name: string) => string | undefined

/**
 * Minimum accepted secret length. Short enough not to be arbitrary theatre,
 * long enough that a hand-typed placeholder ("test", "changeme") is rejected at
 * deploy time rather than protecting production.
 */
export const MIN_BROKER_SECRET_LENGTH = 32

export function readBrokerSecret(
  env: EnvReader = (name) => Deno.env.get(name),
): string | null {
  const value = env('PIP_REALTIME_BROKER_SECRET')?.trim()
  if (!value || value.length < MIN_BROKER_SECRET_LENGTH) return null
  return value
}

/** Header the sideband presents the shared secret in. */
export const BROKER_SECRET_HEADER = 'x-pip-broker-secret'
