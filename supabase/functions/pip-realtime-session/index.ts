// pip-realtime-session — the authenticated control plane for Pip Realtime V1.
//
// This function is the ONLY thing that can create a Realtime session, and the
// only thing that decides whether one may exist. It does not carry audio, does
// not run the agent, and does not grant tool authority. Its job is admission
// control and the durable record of it:
//
//   start         kill switch -> rate limit -> identity -> budget -> the
//                 one-session invariant, then provision generation 1, mint a
//                 short-lived OpenAI client secret and hand the client a
//                 one-shot binding token.
//   register_call the client created an OpenAI call and reports its id onto the
//                 PRE-PROVISIONED generation row. Nothing else. In particular it
//                 does NOT consume the binding token, claim the lease, mark the
//                 call active, or grant tool authority — the sideband service
//                 does all of that, and only against a token it verifies itself.
//   abort_setup   the client got a call id but cannot continue. Records the id
//                 and marks the generation cleanup_pending so the sweeper hangs
//                 it up. Grants nothing.
//   end           the user hung up. Marks the session ending and the live
//                 generation cleanup_pending; the actual OpenAI hangup is the
//                 sweeper's job, never this request's.
//
// Deployed WITH JWT verification. The bearer token is re-read here and resolved
// through the service-role client, and authorization is RECOMPUTED on every
// action — a demotion between `start` and `register_call` invalidates the
// session rather than riding on the token's own lifetime.
//
// Credential discipline: Realtime is OpenAI-only (config.ts). The standing API
// key never leaves openai_realtime.ts. The binding token is returned exactly
// once, in the body of a successful start; only its hash is stored.
//
// Logging discipline: never log tokens, client secrets, transcripts, or the
// provider key. Error paths log a bare identifier and nothing else.
//
// Clock discipline: every instant this function persists comes from ONE read of
// the DATABASE clock (public.realtime_now()) taken at the top of the request.
// The Edge Function writes setup_deadline_at, the Cloud Run sideband evaluates
// it and the SQL sweeper compares it against now() — three hosts arbitrating
// one deadline, so they must share one clock. If that read fails the request is
// refused; it never falls back to the local clock.

import { createClient } from '@supabase/supabase-js'

import {
  APP_CHANNEL_CHAT_ID,
  type AppAgentProfile,
  AppAgentScopeError,
  type AppScopeClient,
  appStaffLinkId,
  ensureAppStaffLink,
  loadAppProfile,
  resolveAppAgentScope,
} from '../app-hatchery-agent/app_agent_scope.ts'
import type { AgentScope } from '../telegram-hatchery-agent/agent_protocol.ts'
import {
  type PipRealtimeConfig,
  readPipRealtimeConfig,
  readRealtimeOpenAiKey,
} from './config.ts'
import { computeAuthorizationFingerprint } from './fingerprint.ts'
import { type BindingToken, issueBindingToken } from './binding_token.ts'
import {
  type MintedClientSecret,
  mintRealtimeClientSecret,
} from './openai_realtime.ts'
import {
  effectiveTenantLimitSeconds,
  type InFlightSession,
  totalSecondsToday,
  utcDateKey,
} from './usage.ts'

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

/** Session states that still hold the one-session-per-profile slot. */
const NON_TERMINAL_SESSION_STATES = [
  'provisioning',
  'active',
  'ending',
] as const

/** Generation states that are still in setup and may still be registered. */
const SETUP_STATES = [
  'provisioning',
  'call_registered',
  'binding',
  'sideband_connecting',
] as const

/** The only end reasons a client may name on `end`. */
const CLIENT_END_REASONS: readonly string[] = [
  'user_ended',
  'client_error',
  'app_backgrounded',
  'network_lost',
]

export type PipRealtimeAction =
  | 'start'
  | 'register_call'
  | 'abort_setup'
  | 'end'

// ---------------------------------------------------------------------------
// Narrow client surface (same shape as the app door's, plus `in`)
// ---------------------------------------------------------------------------

interface DatabaseError {
  message: string
  /** Postgres SQLSTATE. '23505' is a unique violation. */
  code?: string
}

/** Postgres SQLSTATE for a unique violation. */
const UNIQUE_VIOLATION = '23505'

function isUniqueViolation(error: DatabaseError | null): boolean {
  return error?.code === UNIQUE_VIOLATION
}

interface DatabaseResult<T = unknown> {
  data: T | null
  error: DatabaseError | null
}

interface UpdateFilter {
  eq(column: string, value: unknown): Promise<DatabaseResult>
}

interface AdminQuery {
  select(columns: string): AdminQuery
  eq(column: string, value: unknown): AdminQuery
  gte(column: string, value: unknown): AdminQuery
  in(column: string, values: readonly unknown[]): AdminQuery
  order(column: string, options: { ascending: boolean }): AdminQuery
  limit(count: number): Promise<DatabaseResult<Record<string, unknown>[]>>
  maybeSingle(): Promise<DatabaseResult<Record<string, unknown>>>
  insert(values: unknown): Promise<DatabaseResult>
  update(values: unknown): UpdateFilter
}

export interface PipRealtimeAdminClient {
  from(table: string): AdminQuery
  rpc(fn: string, args?: Record<string, unknown>): Promise<DatabaseResult>
}

export interface PipRealtimeAuthUser {
  id: string
}

export interface PipRealtimeDeps {
  adminClient: PipRealtimeAdminClient
  /** Resolves the bearer token to an auth user, or null when it is invalid. */
  authenticate(accessToken: string): Promise<PipRealtimeAuthUser | null>
  config: PipRealtimeConfig
  /** null when OPENAI_API_KEY is absent — Realtime is then simply unavailable. */
  openAiApiKey: string | null
  mintClientSecret(params: {
    apiKey: string
    model: string
    voice: string
    ttlSeconds: number
  }): Promise<MintedClientSecret>
  newId?: () => string
  /**
   * The DATABASE clock, read once per request and threaded through everything
   * that request persists.
   *
   * Three hosts arbitrate a single deadline: this function writes
   * `setup_deadline_at`, the Cloud Run sideband evaluates it, and the cleanup
   * sweeper compares it against SQL now(). If each read its own host clock,
   * skew between them would silently move the deadline — a session could be
   * swept while the sideband still believed it had time. Reading now() from
   * Postgres makes all three agree by construction.
   *
   * Defaults to `public.realtime_now()`; overridable only so tests can pin it.
   */
  serverNow?: () => Promise<Date>
}

/** Reads the database clock. Never falls back to the local clock. */
export async function readDatabaseNow(
  adminClient: PipRealtimeAdminClient,
): Promise<Date> {
  const result = await adminClient.rpc('realtime_now')
  if (result.error) throw new ServerClockError('realtime_now failed')
  const parsed = parseDate(result.data)
  if (!parsed) throw new ServerClockError('realtime_now returned no instant')
  return parsed
}

export class ServerClockError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'ServerClockError'
  }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export async function handlePipRealtimeRequest(
  request: Request,
  deps: PipRealtimeDeps,
): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 200, headers: { ...CORS_HEADERS } })
  }
  if (request.method !== 'POST') {
    return failure(405, 'invalid_request', 'Only POST is supported.')
  }

  const accessToken = readBearerToken(request)
  if (!accessToken) {
    return failure(401, 'unauthenticated', 'A bearer token is required.')
  }

  const body = await readJsonBody(request)
  if (body === undefined) {
    return failure(
      400,
      'invalid_request',
      'The request body is not valid JSON.',
    )
  }
  const action = readAction(body.action)
  if (!action) return failure(400, 'invalid_request', 'Unknown action.')

  let authUser: PipRealtimeAuthUser | null
  try {
    authUser = await deps.authenticate(accessToken)
  } catch (_) {
    authUser = null
  }
  const ownerProfileId = authUser ? nullableString(authUser.id) : null
  if (!ownerProfileId) {
    return failure(401, 'unauthenticated', 'The session is not valid.')
  }

  // Seeded ONCE, before any handler runs, and threaded through every instant
  // this request persists — so a single request cannot straddle two readings of
  // the clock and write a deadline that disagrees with its own start time.
  const readNow = deps.serverNow ?? (() => readDatabaseNow(deps.adminClient))
  let now: Date
  try {
    now = await readNow()
  } catch (_) {
    // A wrong clock is worse than a refused start: it silently moves deadlines
    // for the sideband and the sweeper. Never fall back to the local clock.
    console.error('pip-realtime-session: server clock unavailable')
    return failure(
      503,
      'clock_unavailable',
      'Pip voice is temporarily unavailable.',
    )
  }

  const context: RequestContext = {
    deps,
    body,
    ownerProfileId,
    newId: deps.newId ?? (() => crypto.randomUUID()),
    now,
  }

  try {
    if (action === 'start') return await handleStart(context)
    if (action === 'register_call') return await handleRegisterCall(context)
    if (action === 'abort_setup') return await handleAbortSetup(context)
    return await handleEnd(context)
  } catch (error) {
    if (error instanceof AppAgentScopeError) {
      return failure(
        403,
        'not_approved',
        'This account is not approved for Pip.',
      )
    }
    console.error(`pip-realtime-session: ${action} failed`)
    return failure(500, 'server_error', 'The request could not be completed.')
  }
}

interface RequestContext {
  deps: PipRealtimeDeps
  body: Record<string, unknown>
  ownerProfileId: string
  newId: () => string
  /** The database clock for this request. One instant, read once. */
  now: Date
}

interface ResolvedIdentity {
  profile: AppAgentProfile
  scope: AgentScope
  staffLinkId: string
  tenantId: string | null
  fingerprint: string
}

// ---------------------------------------------------------------------------
// start
// ---------------------------------------------------------------------------

async function handleStart(context: RequestContext): Promise<Response> {
  const { deps, ownerProfileId } = context
  const config = deps.config
  const now = context.now

  // A build-time disable and a missing credential are both "Realtime is not
  // available here" — never a fallback to a text provider.
  if (!config.enabled) {
    return failure(503, 'realtime_unavailable', 'Pip voice is not enabled.')
  }
  if (!deps.openAiApiKey) {
    return failure(503, 'realtime_unavailable', 'Pip voice is not configured.')
  }
  if (!config.cloudRunUrl) {
    return failure(503, 'realtime_unavailable', 'Pip voice is not configured.')
  }

  // 0. Conversation key. Pure input validation, same style as the other
  //    actions' body checks (e.g. register_call's openaiCallId): rejected
  //    before any DB work or rate-limit/budget accounting is touched.
  const conversationKey = resolveConversationKey(context.body)
  if (conversationKey.key === null) {
    return failure(400, 'invalid_request', 'conversationId is invalid.')
  }

  // 1. Kill switch. Only NEW Realtime starts are refused; typed Pip runs through
  //    app-hatchery-agent and is not touched by this table at all.
  const control = await loadRuntimeControl(context)
  if (control === null) {
    return failure(500, 'server_error', 'Could not read the runtime control.')
  }
  const blocked = killSwitchReason(control, now)
  if (blocked) {
    await recordStartAttempt(context, 'kill_switch', now)
    return failure(503, 'kill_switch', 'Pip voice is temporarily unavailable.')
  }

  // 2. Rate limit. The attempt row is written FIRST and only then counted, so a
  //    concurrent burst cannot each read a stale count and all be admitted.
  const slot = await claimStartSlot(context, now)
  if (slot === null) {
    return failure(500, 'server_error', 'Could not record the start attempt.')
  }
  if (slot.limited) {
    return failure(429, 'rate_limited', 'Too many voice sessions were started.')
  }
  const attemptId = slot.attemptId

  // 3. Identity and scope. Rejects an unapproved or unknown caller, and yields
  //    the fingerprint the whole session is pinned to. Resolved before the
  //    budget check because the tenant budget needs the caller's organization.
  const identity = await resolveIdentity(context, now)

  // 4. Budgets: settled seconds plus everything currently in flight.
  const budget = await evaluateBudget(context, identity, now)
  if (budget === null) {
    return failure(500, 'server_error', 'Could not evaluate the voice budget.')
  }
  if (budget.exhausted) {
    await markStartAttempt(context, attemptId, 'budget_exhausted')
    return failure(
      429,
      'budget_exhausted',
      "Today's Pip voice allowance is used up.",
    )
  }

  // 5. One session per profile — by REPLACEMENT, not refusal. The plan's race
  //    table: "Second session starts → lock profile, clean old active or
  //    orphaned generation, then provision replacement." A refusal here fights
  //    the user: a failed setup leaves its session provisioning for up to the
  //    60s deadline, and a retry inside that window would 409. The caller can
  //    only ever displace their OWN session. The partial unique index still
  //    decides a genuine concurrent race: if another start replaces and
  //    inserts between our cleanup and our insert, ours loses with a 409.
  const existing = await loadActiveSession(context, ownerProfileId)
  if (existing === undefined) {
    return failure(500, 'server_error', 'Could not check for a live session.')
  }
  if (existing) {
    const replaced = await replaceExistingSession(context, existing, now)
    if (!replaced) {
      return failure(500, 'server_error', 'Could not replace the live session.')
    }
  }

  const conversation = await loadOrCreateConversation(
    context,
    identity,
    now,
    conversationKey.key,
  )
  if (!conversation) {
    return failure(500, 'server_error', 'Could not load the conversation.')
  }

  const sessionId = context.newId()
  const nowIso = now.toISOString()
  const expiresAt = new Date(
    now.getTime() + config.maxSessionSeconds * 1000,
  ).toISOString()

  const sessionInsert = await deps.adminClient
    .from('agent_realtime_sessions')
    .insert({
      id: sessionId,
      conversation_id: conversation.id,
      context_epoch: conversation.contextEpoch,
      authorization_fingerprint: identity.fingerprint,
      owner_profile_id: ownerProfileId,
      owner_staff_link_id: identity.staffLinkId,
      tenant_id: identity.tenantId,
      active_generation: 1,
      state: 'provisioning',
      recovery_used: false,
      created_at: nowIso,
      expires_at: expiresAt,
    })
  if (sessionInsert.error) {
    if (isUniqueViolation(sessionInsert.error)) {
      // Lost the partial unique index to a concurrent start; the other wins.
      await markStartAttempt(context, attemptId, 'replaced')
      return failure(409, 'session_active', 'A voice session is already open.')
    }
    // Anything else is a real failure and must not be dressed up as a
    // conflict — a 409 tells the client "you already have a session", which
    // would be a lie that hides an outage. Downgrade the attempt so our own
    // outage does not burn the caller's rate-limit allowance: only 'accepted'
    // rows count toward the window.
    await markStartAttempt(context, attemptId, 'server_error')
    console.error('pip-realtime-session: session insert failed')
    return failure(500, 'server_error', 'Could not open a voice session.')
  }

  // The client secret is minted only after the session slot is won, so a losing
  // racer never burns one.
  let secret: MintedClientSecret
  try {
    secret = await deps.mintClientSecret({
      apiKey: deps.openAiApiKey,
      model: config.realtimeModel,
      voice: config.realtimeVoice,
      ttlSeconds: config.clientSecretTtlSeconds,
    })
  } catch (_) {
    await failSession(context, sessionId, 'client_secret_failed', now)
    return failure(502, 'provider_unavailable', 'Pip voice could not start.')
  }

  // The token exists only in this local and in the response body below.
  const binding: BindingToken = await issueBindingToken()
  const setupDeadlineAt = new Date(
    now.getTime() + config.setupDeadlineSeconds * 1000,
  ).toISOString()
  const bindingExpiresAt = new Date(
    now.getTime() + config.bindTokenTtlSeconds * 1000,
  ).toISOString()
  const secretExpiresAt = secret.expiresAt ||
    new Date(now.getTime() + config.clientSecretTtlSeconds * 1000).toISOString()

  const callId = context.newId()
  const callInsert = await deps.adminClient
    .from('agent_realtime_calls')
    .insert({
      id: callId,
      session_id: sessionId,
      generation: 1,
      openai_call_id: null,
      setup_state: 'provisioning',
      authorization_fingerprint: identity.fingerprint,
      provisioned_at: nowIso,
      setup_deadline_at: setupDeadlineAt,
      webrtc_healthy: false,
      data_channel_healthy: false,
      sideband_healthy: false,
      fencing_token: 0,
      // ONLY the hash is persisted. The token itself is in the response below
      // and nowhere else, ever.
      binding_token_hash: binding.hash,
      binding_token_expires_at: bindingExpiresAt,
      // The ephemeral secret VALUE is persisted, unlike the binding token:
      // the sideband must present it as the attach bearer (the provider
      // rejects the standard API key on `?call_id=` attach — proven live
      // 2026-08-17). The table is service-role-only with zero client
      // policies, and the secret expires on its own TTL regardless.
      client_secret: secret.value,
      client_secret_issued_at: nowIso,
      client_secret_expires_at: secretExpiresAt,
      cleanup_attempts: 0,
    })
  if (callInsert.error) {
    await failSession(context, sessionId, 'generation_insert_failed', now)
    return failure(500, 'server_error', 'Could not provision the voice call.')
  }

  return success({
    sessionId,
    generation: 1,
    conversationId: conversation.id,
    contextEpoch: conversation.contextEpoch,
    clientSecret: { value: secret.value, expiresAt: secretExpiresAt },
    bindingToken: binding.token,
    bindingTokenExpiresAt: bindingExpiresAt,
    sidebandUrl: config.cloudRunUrl,
    setupDeadlineAt,
    sessionExpiresAt: expiresAt,
    maxSessionSeconds: config.maxSessionSeconds,
    serverTime: nowIso,
  })
}

// ---------------------------------------------------------------------------
// register_call
// ---------------------------------------------------------------------------

async function handleRegisterCall(context: RequestContext): Promise<Response> {
  const openAiCallId = nullableString(context.body.openaiCallId)
  if (!openAiCallId) {
    return failure(400, 'invalid_request', 'openaiCallId is required.')
  }

  const now = context.now
  const identity = await resolveIdentity(context, now)
  const located = await locateGeneration(context, identity, now, {
    requireFreshAuthorization: true,
    requireSetupDeadline: true,
  })
  if ('response' in located) return located.response
  const { session, call } = located

  const registered = nullableString(call.openai_call_id)
  if (registered) {
    // Idempotent for an identical repeat; a DIFFERENT id is a second call
    // fighting for one generation and is always refused.
    if (registered !== openAiCallId) {
      return failure(
        409,
        'call_conflict',
        'Another call is already registered for this generation.',
      )
    }
    return registrationResponse(session, call, registered)
  }

  const nowIso = now.toISOString()
  const update = await context.deps.adminClient
    .from('agent_realtime_calls')
    .update({
      openai_call_id: openAiCallId,
      call_registered_at: nowIso,
      // The ONLY state advance this action may make. It never touches
      // lease_owner, fencing_token, binding_token_consumed_at or setup_state
      // 'active' — registration is a fact, not an authority.
      setup_state: 'call_registered',
    })
    .eq('id', nullableString(call.id) ?? '')
  if (update.error) {
    // openai_call_id is globally UNIQUE: a 23505 means this call id is already
    // bound to some other generation. Any other error is a real failure.
    if (isUniqueViolation(update.error)) {
      return failure(409, 'call_conflict', 'That call id is already in use.')
    }
    console.error('pip-realtime-session: call registration failed')
    return failure(500, 'server_error', 'Could not register the voice call.')
  }

  return registrationResponse(
    session,
    { ...call, call_registered_at: nowIso },
    openAiCallId,
  )
}

function registrationResponse(
  session: Record<string, unknown>,
  call: Record<string, unknown>,
  openAiCallId: string,
): Response {
  // Deliberately carries no binding token, no client secret, no lease and no
  // fencing token: registering a call grants no sideband authority whatsoever.
  return success({
    sessionId: nullableString(session.id),
    generation: integerValue(call.generation),
    openaiCallId: openAiCallId,
    setupState: 'call_registered',
    registeredAt: nullableString(call.call_registered_at),
    setupDeadlineAt: nullableString(call.setup_deadline_at),
    authority: 'none',
  })
}

// ---------------------------------------------------------------------------
// abort_setup
// ---------------------------------------------------------------------------

async function handleAbortSetup(context: RequestContext): Promise<Response> {
  const now = context.now
  const identity = await resolveIdentity(context, now)
  // The setup deadline is NOT enforced here: a client that blew the deadline is
  // exactly the client that most needs to report its orphaned call id.
  const located = await locateGeneration(context, identity, now, {
    requireFreshAuthorization: false,
    requireSetupDeadline: false,
  })
  if ('response' in located) return located.response
  const { session, call } = located

  const reported = nullableString(context.body.openaiCallId)
  const registered = nullableString(call.openai_call_id)
  if (reported && registered && reported !== registered) {
    return failure(409, 'call_conflict', 'That call id is already in use.')
  }
  const knownCallId = registered ?? reported

  const nowIso = now.toISOString()
  const callUpdate = await context.deps.adminClient
    .from('agent_realtime_calls')
    .update({
      ...(knownCallId ? { openai_call_id: knownCallId } : {}),
      setup_state: 'cleanup_pending',
      // A call id we know about must be hung up; with no call id there is
      // nothing at the provider to hang up.
      hangup_state: knownCallId ? 'pending' : 'not_required',
      cleanup_next_attempt_at: nowIso,
      ending_at: nowIso,
      end_reason: 'setup_aborted',
    })
    .eq('id', nullableString(call.id) ?? '')
  if (callUpdate.error) {
    return failure(500, 'server_error', 'Could not abort the voice setup.')
  }

  const sessionUpdate = await context.deps.adminClient
    .from('agent_realtime_sessions')
    .update({
      state: 'ending',
      ending_at: nowIso,
      end_reason: 'setup_aborted',
    })
    .eq('id', nullableString(session.id) ?? '')
  if (sessionUpdate.error) {
    return failure(500, 'server_error', 'Could not abort the voice setup.')
  }

  return success({
    sessionId: nullableString(session.id),
    generation: integerValue(call.generation),
    setupState: 'cleanup_pending',
    hangupState: knownCallId ? 'pending' : 'not_required',
    authority: 'none',
  })
}

// ---------------------------------------------------------------------------
// end
// ---------------------------------------------------------------------------

async function handleEnd(context: RequestContext): Promise<Response> {
  const sessionId = nullableString(context.body.sessionId)
  if (!sessionId) {
    return failure(400, 'invalid_request', 'sessionId is required.')
  }
  const now = context.now
  const nowIso = now.toISOString()

  // Ending is deliberately NOT gated on a fresh authorization fingerprint: a
  // caller whose authority just changed must still be able to hang up.
  const loaded = await context.deps.adminClient
    .from('agent_realtime_sessions')
    .select('*')
    .eq('id', sessionId)
    .maybeSingle()
  if (loaded.error) {
    return failure(500, 'server_error', 'Could not load the voice session.')
  }
  const session = loaded.data
  if (!session) return failure(404, 'unknown_session', 'No such voice session.')
  if (nullableString(session.owner_profile_id) !== context.ownerProfileId) {
    return failure(404, 'unknown_session', 'No such voice session.')
  }

  const state = nullableString(session.state)
  if (state === 'ended' || state === 'failed') {
    return success({ sessionId, state, alreadyEnded: true })
  }

  // end_reason is an audit column, so the client picks from a fixed vocabulary
  // rather than writing free text into it.
  const requested = nullableString(context.body.reason)
  const reason = requested && CLIENT_END_REASONS.includes(requested)
    ? requested
    : 'user_ended'
  const sessionUpdate = await context.deps.adminClient
    .from('agent_realtime_sessions')
    .update({ state: 'ending', ending_at: nowIso, end_reason: reason })
    .eq('id', sessionId)
  if (sessionUpdate.error) {
    return failure(500, 'server_error', 'Could not end the voice session.')
  }

  // Hand the live generation to the sweeper. The OpenAI hangup itself is never
  // performed on this request: a user-facing action must not block on a
  // provider call that can hang.
  const call = await loadGenerationRow(
    context,
    sessionId,
    integerValue(session.active_generation) ?? 1,
  )
  if (call && !isTerminalSetupState(nullableString(call.setup_state))) {
    await context.deps.adminClient
      .from('agent_realtime_calls')
      .update({
        setup_state: 'cleanup_pending',
        hangup_state: nullableString(call.openai_call_id)
          ? 'pending'
          : 'not_required',
        cleanup_next_attempt_at: nowIso,
        ending_at: nowIso,
        end_reason: reason,
      })
      .eq('id', nullableString(call.id) ?? '')
  }

  return success({ sessionId, state: 'ending', endReason: reason })
}

// ---------------------------------------------------------------------------
// Shared steps
// ---------------------------------------------------------------------------

async function resolveIdentity(
  context: RequestContext,
  now: Date,
): Promise<ResolvedIdentity> {
  const scopeClient = context.deps.adminClient as unknown as AppScopeClient
  const profile = await loadAppProfile(scopeClient, context.ownerProfileId)
  const scope = await resolveAppAgentScope(
    scopeClient,
    context.ownerProfileId,
    profile,
  )
  const staffLinkId = await ensureAppStaffLink(
    scopeClient,
    profile,
    now.toISOString(),
  )
  const tenantId = await loadTenantId(context)
  const fingerprint = await computeAuthorizationFingerprint({
    staffLinkId: scope.staffLinkId,
    accessRole: scope.accessRole,
    allowedCustomerIds: scope.allowedCustomerIds,
    profileRole: profile.role,
    profileStatus: profile.status,
  })
  return { profile, scope, staffLinkId, tenantId, fingerprint }
}

async function loadTenantId(context: RequestContext): Promise<string | null> {
  const result = await context.deps.adminClient
    .from('profiles')
    .select('organization_id')
    .eq('id', context.ownerProfileId)
    .maybeSingle()
  if (result.error) throw new Error('Could not load the caller organization')
  return result.data ? nullableString(result.data.organization_id) : null
}

interface RuntimeControl {
  enabled: boolean
  draining: boolean
  forceStopAt: Date | null
}

async function loadRuntimeControl(
  context: RequestContext,
): Promise<RuntimeControl | null> {
  const result = await context.deps.adminClient
    .from('agent_realtime_runtime_control')
    .select('enabled, draining, force_stop_at')
    .eq('id', 1)
    .maybeSingle()
  if (result.error) return null
  const row = result.data
  // A missing control row means the migration seeded it and something deleted
  // it; treat that as "enabled" rather than locking voice out permanently.
  if (!row) return { enabled: true, draining: false, forceStopAt: null }
  return {
    enabled: row.enabled !== false,
    draining: row.draining === true,
    forceStopAt: parseDate(row.force_stop_at),
  }
}

function killSwitchReason(control: RuntimeControl, now: Date): string | null {
  if (!control.enabled) return 'disabled'
  if (control.draining) return 'draining'
  if (control.forceStopAt && control.forceStopAt.getTime() <= now.getTime()) {
    return 'force_stop'
  }
  return null
}

interface StartSlot {
  attemptId: string
  limited: boolean
}

/**
 * Claims one start slot. The attempt row is inserted OPTIMISTICALLY as
 * 'accepted' and only then counted, so the count a request sees already
 * includes every attempt committed before it — the ordering that makes this
 * atomic enough to bound admission. Only rows still marked 'accepted' consume
 * the window, so a refused attempt never eats a later legitimate start.
 */
async function claimStartSlot(
  context: RequestContext,
  now: Date,
): Promise<StartSlot | null> {
  const attemptId = await recordStartAttempt(context, 'accepted', now)
  if (!attemptId) return null

  const cutoff = new Date(
    now.getTime() - context.deps.config.sessionStartWindowSeconds * 1000,
  ).toISOString()
  const counted = await context.deps.adminClient
    .from('agent_realtime_start_attempts')
    .select('id')
    .eq('owner_profile_id', context.ownerProfileId)
    .eq('outcome', 'accepted')
    .gte('attempted_at', cutoff)
    .limit(context.deps.config.sessionStartLimit + 2)
  if (counted.error) return null

  if ((counted.data ?? []).length > context.deps.config.sessionStartLimit) {
    await markStartAttempt(context, attemptId, 'rate_limited')
    return { attemptId, limited: true }
  }
  return { attemptId, limited: false }
}

async function recordStartAttempt(
  context: RequestContext,
  outcome: string,
  now: Date,
): Promise<string | null> {
  const attemptId = context.newId()
  const result = await context.deps.adminClient
    .from('agent_realtime_start_attempts')
    .insert({
      id: attemptId,
      owner_profile_id: context.ownerProfileId,
      attempted_at: now.toISOString(),
      outcome,
    })
  return result.error ? null : attemptId
}

async function markStartAttempt(
  context: RequestContext,
  attemptId: string,
  outcome: string,
): Promise<void> {
  await context.deps.adminClient
    .from('agent_realtime_start_attempts')
    .update({ outcome })
    .eq('id', attemptId)
}

interface BudgetVerdict {
  exhausted: boolean
  profileSeconds: number
  tenantSeconds: number
}

async function evaluateBudget(
  context: RequestContext,
  identity: ResolvedIdentity,
  now: Date,
): Promise<BudgetVerdict | null> {
  const config = context.deps.config
  const usageDate = utcDateKey(now)

  const profileSettled = await sumSettledSeconds(context, {
    column: 'owner_profile_id',
    value: context.ownerProfileId,
    usageDate,
  })
  if (profileSettled === null) return null
  const profileInFlight = await loadInFlightSessions(context, {
    column: 'owner_profile_id',
    value: context.ownerProfileId,
  })
  if (profileInFlight === null) return null

  const profileSeconds = totalSecondsToday({
    settledSeconds: profileSettled,
    inFlight: profileInFlight,
    now,
    maxSessionSeconds: config.maxSessionSeconds,
  })
  if (profileSeconds >= config.dailySecondsPerProfile) {
    return { exhausted: true, profileSeconds, tenantSeconds: 0 }
  }

  if (!identity.tenantId) {
    return { exhausted: false, profileSeconds, tenantSeconds: 0 }
  }

  const tenantSettled = await sumSettledSeconds(context, {
    column: 'tenant_id',
    value: identity.tenantId,
    usageDate,
  })
  if (tenantSettled === null) return null
  const tenantInFlight = await loadInFlightSessions(context, {
    column: 'tenant_id',
    value: identity.tenantId,
  })
  if (tenantInFlight === null) return null

  const tenantSeconds = totalSecondsToday({
    settledSeconds: tenantSettled,
    inFlight: tenantInFlight,
    now,
    maxSessionSeconds: config.maxSessionSeconds,
  })
  const tenantLimit = effectiveTenantLimitSeconds(
    config.dailySecondsPerTenant,
    config.tenantOverageFactor,
  )
  return {
    exhausted: tenantSeconds >= tenantLimit,
    profileSeconds,
    tenantSeconds,
  }
}

async function sumSettledSeconds(
  context: RequestContext,
  params: { column: string; value: string; usageDate: string },
): Promise<number | null> {
  const result = await context.deps.adminClient
    .from('agent_realtime_usage_seconds')
    .select('seconds')
    .eq(params.column, params.value)
    .eq('usage_date', params.usageDate)
    .limit(1000)
  if (result.error) return null
  let total = 0
  for (const row of result.data ?? []) {
    total += Math.max(0, integerValue(row.seconds) ?? 0)
  }
  return total
}

async function loadInFlightSessions(
  context: RequestContext,
  params: { column: string; value: string },
): Promise<InFlightSession[] | null> {
  const result = await context.deps.adminClient
    .from('agent_realtime_sessions')
    .select('authoritative_ready_at')
    .eq(params.column, params.value)
    .in('state', [...NON_TERMINAL_SESSION_STATES])
    .limit(200)
  if (result.error) return null
  return (result.data ?? []).map((row) => ({
    readyAt: parseDate(row.authoritative_ready_at),
  }))
}

/**
 * Terminalizes the caller's own lingering session so a fresh one can be
 * provisioned. The session leaves the one-per-profile slot immediately
 * (`ended`/`replaced`); the hangup obligation is NOT lost — every non-terminal
 * generation goes to `cleanup_pending`, and the sweeper owns the actual OpenAI
 * hangup through the same idempotent, fence-aware contract as every other
 * cleanup. A session that never reached READY settles zero usage by design.
 */
async function replaceExistingSession(
  context: RequestContext,
  existing: Record<string, unknown>,
  now: Date,
): Promise<boolean> {
  const sessionId = String(existing.id)
  const nowIso = now.toISOString()
  // Generations are enumerated and updated by id: the typed admin surface
  // deliberately keeps UpdateFilter to a single eq(), and a session never has
  // more than a couple of generations.
  const calls = await context.deps.adminClient
    .from('agent_realtime_calls')
    .select('id, setup_state')
    .eq('session_id', sessionId)
    .limit(10)
  if (calls.error) return false
  for (const call of calls.data ?? []) {
    const setupState = String(call.setup_state)
    if (['ended', 'failed', 'cleanup_pending'].includes(setupState)) continue
    const updated = await context.deps.adminClient
      .from('agent_realtime_calls')
      .update({
        setup_state: 'cleanup_pending',
        end_reason: 'replaced',
        hangup_state: 'pending',
        ending_at: nowIso,
        cleanup_next_attempt_at: nowIso,
      })
      .eq('id', String(call.id))
    if (updated.error) return false
  }
  const session = await context.deps.adminClient
    .from('agent_realtime_sessions')
    .update({
      state: 'ended',
      end_reason: 'replaced',
      ending_at: nowIso,
      ended_at: nowIso,
    })
    .eq('id', sessionId)
  return !session.error
}

async function loadActiveSession(
  context: RequestContext,
  ownerProfileId: string,
): Promise<Record<string, unknown> | null | undefined> {
  const result = await context.deps.adminClient
    .from('agent_realtime_sessions')
    .select('*')
    .eq('owner_profile_id', ownerProfileId)
    .in('state', [...NON_TERMINAL_SESSION_STATES])
    .limit(1)
  if (result.error) return undefined
  return result.data?.[0] ?? null
}

interface LocatedGeneration {
  session: Record<string, unknown>
  call: Record<string, unknown>
}

/**
 * Resolves (sessionId, generation) from the body and validates every gate the
 * caller must pass before touching a generation row: ownership, live session,
 * the CURRENT generation, a generation that is still in setup, and — for
 * register_call — a fresh fingerprint and an unexpired setup deadline.
 */
async function locateGeneration(
  context: RequestContext,
  identity: ResolvedIdentity,
  now: Date,
  options: {
    requireFreshAuthorization: boolean
    requireSetupDeadline: boolean
  },
): Promise<LocatedGeneration | { response: Response }> {
  const sessionId = nullableString(context.body.sessionId)
  const generation = integerValue(context.body.generation)
  if (!sessionId || generation === null || generation < 1) {
    return {
      response: failure(
        400,
        'invalid_request',
        'sessionId and generation are required.',
      ),
    }
  }

  const loaded = await context.deps.adminClient
    .from('agent_realtime_sessions')
    .select('*')
    .eq('id', sessionId)
    .maybeSingle()
  if (loaded.error) {
    return {
      response: failure(500, 'server_error', 'Could not load the session.'),
    }
  }
  const session = loaded.data
  // An unknown session and someone else's session are the same 404: session ids
  // must not be probeable.
  if (
    !session ||
    nullableString(session.owner_profile_id) !== context.ownerProfileId
  ) {
    return {
      response: failure(404, 'unknown_session', 'No such voice session.'),
    }
  }
  if (
    nullableString(session.owner_staff_link_id) !==
      appStaffLinkId(context.ownerProfileId)
  ) {
    return {
      response: failure(404, 'unknown_session', 'No such voice session.'),
    }
  }

  const state = nullableString(session.state)
  if (state !== 'provisioning' && state !== 'active') {
    return {
      response: failure(
        409,
        'session_closed',
        'This voice session is closing.',
      ),
    }
  }

  if (
    options.requireFreshAuthorization &&
    nullableString(session.authorization_fingerprint) !== identity.fingerprint
  ) {
    return {
      response: failure(
        403,
        'authorization_changed',
        'Your access changed. Start a new voice session.',
      ),
    }
  }

  const activeGeneration = integerValue(session.active_generation) ?? 1
  if (generation !== activeGeneration) {
    return {
      response: failure(
        409,
        'stale_generation',
        'This attempt has been replaced.',
      ),
    }
  }

  const call = await loadGenerationRow(context, sessionId, generation)
  if (!call) {
    // Never fabricated here: only `start` (and, later, a recovery) provisions a
    // generation row.
    return {
      response: failure(
        409,
        'stale_generation',
        'This attempt has been replaced.',
      ),
    }
  }

  const setupState = nullableString(call.setup_state)
  if (!SETUP_STATES.includes(setupState as typeof SETUP_STATES[number])) {
    return {
      response: failure(
        409,
        'generation_closed',
        'This attempt is no longer in setup.',
      ),
    }
  }
  if (
    options.requireFreshAuthorization &&
    nullableString(call.authorization_fingerprint) !== identity.fingerprint
  ) {
    return {
      response: failure(
        403,
        'authorization_changed',
        'Your access changed. Start a new voice session.',
      ),
    }
  }

  if (options.requireSetupDeadline) {
    const deadline = parseDate(call.setup_deadline_at)
    if (!deadline || deadline.getTime() <= now.getTime()) {
      return {
        response: failure(409, 'setup_expired', 'Voice setup took too long.'),
      }
    }
  }

  return { session, call }
}

async function loadGenerationRow(
  context: RequestContext,
  sessionId: string,
  generation: number,
): Promise<Record<string, unknown> | null> {
  const result = await context.deps.adminClient
    .from('agent_realtime_calls')
    .select('*')
    .eq('session_id', sessionId)
    .eq('generation', generation)
    .maybeSingle()
  if (result.error) return null
  return result.data ?? null
}

function isTerminalSetupState(state: string | null): boolean {
  return state === 'ended' || state === 'failed' || state === 'cleanup_pending'
}

async function failSession(
  context: RequestContext,
  sessionId: string,
  reason: string,
  now: Date,
): Promise<void> {
  const nowIso = now.toISOString()
  await context.deps.adminClient
    .from('agent_realtime_sessions')
    .update({ state: 'failed', ended_at: nowIso, end_reason: reason })
    .eq('id', sessionId)
}

interface ResolvedConversation {
  id: string
  contextEpoch: number
}

/**
 * Body-supplied conversation key for `start`. Either the app sentinel
 * ('app', the single-conversation default and current behaviour) or
 * 'app:' followed by a lowercase UUID v4, naming one of the caller's
 * per-conversation threads. Ownership is inherent: the lookup is always
 * scoped to the caller's own staff_link_id, so no other validation of the
 * UUID's provenance is needed.
 */
// Standard UUID v4 shape: 8-4-4-4-12 hex digits, version nibble '4', variant
// nibble one of 8/9/a/b — matches what crypto.randomUUID() produces. (The
// spec text quoted a group-4 length of {4}; that yields a 5-character group
// that no real UUID v4 has, so this uses the standard {3} instead.)
const CONVERSATION_KEY_PATTERN =
  /^app:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

/**
 * Resolves and validates the optional `conversationId` field on a `start`
 * body. Missing/null falls back to the legacy single-conversation sentinel;
 * anything else must match the sentinel or the per-conversation pattern
 * exactly, or the request is refused.
 */
function resolveConversationKey(
  body: Record<string, unknown>,
): { key: string } | { key: null } {
  const raw = body.conversationId
  if (raw === undefined || raw === null) return { key: APP_CHANNEL_CHAT_ID }
  if (typeof raw !== 'string') return { key: null }
  if (raw === APP_CHANNEL_CHAT_ID || CONVERSATION_KEY_PATTERN.test(raw)) {
    return { key: raw }
  }
  return { key: null }
}

/**
 * Realtime shares the app user's agent conversation identified by
 * `conversationKey`, so a voice session continues the same thread typed Pip
 * was using. Same key shape as the app door: (app staff link, chat id),
 * where the chat id defaults to APP_CHANNEL_CHAT_ID for the legacy single
 * conversation and may otherwise name one of the caller's other threads.
 */
async function loadOrCreateConversation(
  context: RequestContext,
  identity: ResolvedIdentity,
  now: Date,
  conversationKey: string,
): Promise<ResolvedConversation | null> {
  const load = () =>
    context.deps.adminClient
      .from('agent_conversations')
      .select('*')
      .eq('staff_link_id', identity.staffLinkId)
      .eq('telegram_chat_id', conversationKey)
      .maybeSingle()

  const existing = await load()
  if (existing.error) return null
  if (existing.data) {
    const id = nullableString(existing.data.id)
    if (!id) return null
    return { id, contextEpoch: integerValue(existing.data.context_epoch) ?? 1 }
  }

  const nowIso = now.toISOString()
  const id = context.newId()
  const created = await context.deps.adminClient
    .from('agent_conversations')
    .insert({
      id,
      staff_link_id: identity.staffLinkId,
      telegram_chat_id: conversationKey,
      owner_profile_id: context.ownerProfileId,
      state_version: 1,
      context_epoch: 1,
      pending_action_json: null,
      active_visit_id: null,
      selected_customer_id: null,
      selected_flock_id: null,
      selected_audit_id: null,
      context_updated_at: nowIso,
      created_at: nowIso,
      updated_at: nowIso,
    })
  if (!created.error) return { id, contextEpoch: 1 }

  const retry = await load()
  if (retry.error || !retry.data) return null
  const retryId = nullableString(retry.data.id)
  if (!retryId) return null
  return {
    id: retryId,
    contextEpoch: integerValue(retry.data.context_epoch) ?? 1,
  }
}

// ---------------------------------------------------------------------------
// Request/response plumbing
// ---------------------------------------------------------------------------

function readBearerToken(request: Request): string | null {
  const header = request.headers.get('Authorization') ??
    request.headers.get('authorization')
  if (!header) return null
  const match = /^Bearer\s+(.+)$/i.exec(header.trim())
  return match ? nullableString(match[1]) : null
}

async function readJsonBody(
  request: Request,
): Promise<Record<string, unknown> | undefined> {
  let raw: string
  try {
    raw = await request.text()
  } catch (_) {
    return undefined
  }
  if (raw.trim().length === 0) return {}
  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch (_) {
    return undefined
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return undefined
  }
  return parsed as Record<string, unknown>
}

function readAction(value: unknown): PipRealtimeAction | null {
  const action = nullableString(value)
  if (
    action === 'start' || action === 'register_call' ||
    action === 'abort_setup' || action === 'end'
  ) {
    return action
  }
  return null
}

function parseDate(value: unknown): Date | null {
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value
  const text = nullableString(value)
  if (!text) return null
  const parsed = Date.parse(text)
  return Number.isFinite(parsed) ? new Date(parsed) : null
}

function nullableString(value: unknown): string | null {
  if (value === null || value === undefined) return null
  const text = String(value).trim()
  return text ? text : null
}

function integerValue(value: unknown): number | null {
  if (typeof value === 'number' && Number.isInteger(value)) return value
  if (typeof value === 'string' && /^-?\d+$/.test(value.trim())) {
    return Number.parseInt(value.trim(), 10)
  }
  return null
}

function success(payload: Record<string, unknown>): Response {
  return json(200, payload)
}

function failure(status: number, code: string, error: string): Response {
  return json(status, { error, code })
}

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  })
}

// ---------------------------------------------------------------------------
// Deployment wiring
// ---------------------------------------------------------------------------

export function servePipRealtimeSession(
  request: Request,
): Response | Promise<Response> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, {
      error: 'Pip realtime is not configured.',
      code: 'server_error',
    })
  }

  // Invalid PIP_REALTIME_* configuration fails fast and loudly rather than
  // running on a silently clamped budget.
  let config: PipRealtimeConfig
  try {
    config = readPipRealtimeConfig()
  } catch (error) {
    console.error(
      `pip-realtime-session: invalid configuration — ${
        error instanceof Error ? error.message : 'unknown'
      }`,
    )
    return json(500, {
      error: 'Pip realtime is misconfigured.',
      code: 'server_error',
    })
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const adminClient = supabase as unknown as PipRealtimeAdminClient

  return handlePipRealtimeRequest(request, {
    adminClient,
    authenticate: async (accessToken) => {
      const result = await supabase.auth.getUser(accessToken)
      if (result.error || !result.data?.user) return null
      return { id: result.data.user.id }
    },
    config,
    openAiApiKey: readRealtimeOpenAiKey(),
    mintClientSecret: (params) => mintRealtimeClientSecret(params),
  })
}

if (import.meta.main) {
  Deno.serve(servePipRealtimeSession)
}
