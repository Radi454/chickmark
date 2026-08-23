// supabase/functions/pip-realtime-session/openai_realtime.ts
//
// Mints the short-lived, client-visible OpenAI Realtime credential.
//
// Two hard rules:
//   * The standing OPENAI_API_KEY never leaves this module. It is used only as
//     the Authorization header on the mint call; it is never returned to the
//     client, never written to the database, and never included in an error
//     message or log line.
//   * The minted secret is anchored at created_at with a short TTL, so a secret
//     that leaks in transit is useless within seconds.

const CLIENT_SECRETS_ENDPOINT =
  'https://api.openai.com/v1/realtime/client_secrets'

export class RealtimeProviderError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'RealtimeProviderError'
  }
}

export interface MintClientSecretParams {
  readonly apiKey: string
  readonly model: string
  readonly voice: string
  readonly ttlSeconds: number
  readonly fetchImpl?: typeof fetch
}

export interface MintedClientSecret {
  /** The ephemeral value the browser/app hands to OpenAI. Never persisted. */
  readonly value: string
  /** Provider-reported expiry, ISO-8601. */
  readonly expiresAt: string
}

export async function mintRealtimeClientSecret(
  params: MintClientSecretParams,
): Promise<MintedClientSecret> {
  const fetchImpl = params.fetchImpl ?? fetch
  let response: Response
  try {
    response = await fetchImpl(CLIENT_SECRETS_ENDPOINT, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${params.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        expires_after: { anchor: 'created_at', seconds: params.ttlSeconds },
        session: {
          type: 'realtime',
          model: params.model,
          audio: { output: { voice: params.voice } },
        },
      }),
    })
  } catch (_) {
    // The cause is deliberately dropped: it can echo request headers.
    throw new RealtimeProviderError('Client secret request failed')
  }
  if (!response.ok) {
    throw new RealtimeProviderError(
      `Client secret request returned HTTP ${response.status}`,
    )
  }

  let payload: unknown
  try {
    payload = await response.json()
  } catch (_) {
    throw new RealtimeProviderError('Client secret response is invalid JSON')
  }
  if (!isRecord(payload)) {
    throw new RealtimeProviderError('Client secret response is not an object')
  }

  const value = typeof payload.value === 'string' ? payload.value.trim() : ''
  if (!value) {
    throw new RealtimeProviderError('Client secret response carried no value')
  }

  const expiresAt = readExpiry(payload.expires_at)
  return { value, expiresAt: expiresAt ?? '' }
}

function readExpiry(value: unknown): string | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return new Date(value * 1000).toISOString()
  }
  if (typeof value === 'string' && value.trim()) {
    const parsed = Date.parse(value)
    if (Number.isFinite(parsed)) return new Date(parsed).toISOString()
  }
  return null
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
