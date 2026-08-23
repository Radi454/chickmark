// Binding: the first application frame on a client WebSocket.
//
// Credentials arrive in the FIRST FRAME, never in the URL. A URL query string is
// written to proxy logs, browser history and Cloud Run request logs; a frame
// body is not. The frame itself is never logged here either — not even its
// shape, because the shape includes the token field.
//
// Until binding succeeds the connection may do NOTHING. No control action, no
// lease claim, no provider traffic.
//
// The frame shape is the canonical one, written down in ../WIRE_CONTRACT.md and
// pinned character for character against the Flutter client in
// ../test/binding_test.ts. It is snake_case; camelCase is not accepted.

import { sha256Hex, timingSafeEqual } from './ids.ts'
import { log } from './log.ts'
import type { TokenVerifier } from './jwt.ts'
import type { BindingConsumeResult, RealtimeStore, SessionRow } from './store.ts'

export interface BindFrame {
  readonly type: 'bind'
  readonly session_id: string
  readonly generation: number
  readonly access_token: string
  readonly binding_token: string
}

export type BindFailure =
  | 'malformed_frame'
  | 'not_first_frame'
  | 'invalid_token'
  | 'unknown_session'
  | 'session_not_bindable'
  | 'identity_mismatch'
  | 'unauthorized'
  | 'binding_token_rejected'
  | 'kill_switch'

export type BindResult =
  | {
    readonly ok: true
    readonly session: SessionRow
    readonly generation: number
    readonly profileId: string
  }
  | {
    readonly ok: false
    readonly reason: BindFailure
    readonly detail?: BindingConsumeResult
  }

export function parseBindFrame(raw: string): BindFrame | null {
  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch {
    return null
  }
  if (!parsed || typeof parsed !== 'object') return null
  const frame = parsed as Record<string, unknown>
  if (frame.type !== 'bind') return null
  if (typeof frame.session_id !== 'string' || frame.session_id === '') return null
  if (typeof frame.access_token !== 'string' || frame.access_token === '') return null
  if (typeof frame.binding_token !== 'string' || frame.binding_token === '') return null
  const generation = frame.generation
  if (typeof generation !== 'number' || !Number.isInteger(generation) || generation < 1) {
    return null
  }
  return {
    type: 'bind',
    session_id: frame.session_id,
    generation,
    access_token: frame.access_token,
    binding_token: frame.binding_token,
  }
}

/**
 * Resolves authorization server-side. A verified JWT proves only that the caller
 * is who they say they are; whether that identity may drive THIS session is a
 * database question, re-asked here rather than trusted from the token.
 */
export type AuthorizationCheck = (
  profileId: string,
  session: SessionRow,
) => Promise<{ authorized: boolean; fingerprint: string }>

export async function bindConnection(input: {
  frame: BindFrame
  store: RealtimeStore
  verifier: TokenVerifier
  authorize: AuthorizationCheck
  now: Date
}): Promise<BindResult> {
  const { frame, store, verifier, now } = input

  const verified = await verifier.verify(frame.access_token)
  if (!verified.ok) {
    log.warn('bind.token_rejected', { reason: verified.reason })
    return { ok: false, reason: 'invalid_token' }
  }
  const profileId = verified.claims.sub

  const control = await store.loadRuntimeControl()
  if (!control.enabled) return { ok: false, reason: 'kill_switch' }

  const session = await store.loadSession(frame.session_id)
  if (!session) return { ok: false, reason: 'unknown_session' }
  if (session.ownerProfileId !== profileId) {
    // Deliberately reported as an identity mismatch and not as "unknown
    // session": the caller authenticated fine, they just do not own this one.
    log.warn('bind.identity_mismatch', { session_id: session.id })
    return { ok: false, reason: 'identity_mismatch' }
  }
  if (session.state === 'ended' || session.state === 'failed') {
    return { ok: false, reason: 'session_not_bindable' }
  }

  const authorization = await input.authorize(profileId, session)
  if (!authorization.authorized) {
    return { ok: false, reason: 'unauthorized' }
  }
  if (authorization.fingerprint !== session.authorizationFingerprint) {
    // The caller's effective access changed between session creation and bind
    // (approval revoked, customer reassigned). The session's provisioned scope
    // is no longer the scope they hold, so it cannot be resumed.
    log.warn('bind.fingerprint_changed', { session_id: session.id })
    return { ok: false, reason: 'unauthorized' }
  }

  const presentedHash = await sha256Hex(frame.binding_token)
  const consumed = await store.consumeBindingToken({
    sessionId: session.id,
    generation: frame.generation,
    presentedHash,
    now: now.toISOString(),
  })
  if (consumed !== 'consumed') {
    log.warn('bind.binding_token_rejected', {
      session_id: session.id,
      generation: frame.generation,
      outcome: consumed,
    })
    return { ok: false, reason: 'binding_token_rejected', detail: consumed }
  }

  log.info('bind.succeeded', { session_id: session.id, generation: frame.generation })
  return { ok: true, session, generation: frame.generation, profileId }
}

/** Compare a presented token against a stored hash without leaking either. */
export async function bindingTokenMatches(
  presented: string,
  storedHash: string,
): Promise<boolean> {
  return timingSafeEqual(await sha256Hex(presented), storedHash)
}
