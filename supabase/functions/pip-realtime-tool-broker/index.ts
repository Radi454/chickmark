// pip-realtime-tool-broker — the internal tool-execution boundary for Realtime.
//
// WHY THIS EXISTS
//
// The Cloud Run sideband carries audio and owns the Realtime CONTROL path. It
// must not own the tool catalogue and it must not hold broad database
// privileges: forking a second copy of the catalogue would let the voice channel
// drift away from the text channel, and handing a long-lived audio process
// service-role reach over the whole schema would make the least-privilege
// boundary decorative. So the sideband calls exactly one narrow, authenticated
// endpoint — this one — with a single tool call, and this endpoint executes it
// through the SAME shared runtime the Telegram and in-app doors use
// (`executeAgentTool`).
//
// WHAT THIS ENDPOINT IS RESPONSIBLE FOR
//
//   1. Authenticating the SIDEBAND (a server), not an end user.
//   2. RE-RESOLVING the caller's authority from the database and recomputing the
//      authorization fingerprint. The fingerprint on the request is compared,
//      never trusted: it is a claim, and this function is where the claim is
//      checked against the current state of `profiles` / `auditor_customers`.
//   3. Confirming the generation is still the live one and still executable.
//   4. Executing through `executeAgentTool`, which is where scope enforcement on
//      the arguments (`enforceArgumentScope`) already lives.
//   5. Idempotency, via `agent_tool_call_claims` on the Realtime key shape.
//   6. Immutable evidence, via one `agent_tool_events` insert.
//
// WHAT THIS ENDPOINT MUST NOT DO
//
//   * It must NOT enforce the per-interaction tool-call cap. See the
//     TOOL BUDGET BOUNDARY note further down.
//   * It must NOT log tool arguments, tool results, transcripts, or secrets.
//     Every log line here carries identifiers and outcome codes only.
//
// AUTH MECHANISM: shared secret, constant-time compared.
//
// Chosen over Google OIDC because this runs on Supabase Edge Functions, which
// have no Google identity trust anchor: verifying an OIDC token would mean
// fetching and caching Google's JWKS from inside the hot tool path, adding a
// third-party network dependency to every tool call and a new failure mode to
// the one code path that must answer the model quickly. The sideband already
// verifies inbound Google OIDC for its own /internal/cleanup route, so the two
// directions are deliberately asymmetric: outbound to a Supabase function is a
// shared secret, inbound from Google Cloud Scheduler is OIDC. The secret is
// compared in constant time and the endpoint FAILS CLOSED when it is unset.
//
// DEPLOYMENT NOTE: deploy with `--no-verify-jwt`. The caller is a server and
// presents no end-user JWT; authentication is the shared secret checked here.

import { createClient } from '@supabase/supabase-js'

import {
  type AppAgentProfile,
  AppAgentScopeError,
  type AppScopeClient,
  loadAppProfile,
  resolveAppAgentScope,
} from '../app-hatchery-agent/app_agent_scope.ts'
import type {
  AgentScope,
  AgentToolName,
  AgentToolResult,
} from '../telegram-hatchery-agent/agent_protocol.ts'
import {
  type AgentConversationContextPort,
  type AgentToolEvidence,
  type AgentToolEvidencePort,
  type AgentToolHandler,
  executeAgentTool,
} from '../telegram-hatchery-agent/agent_tools.ts'
import {
  type AdminClient as TelegramAdminClient,
  createUnifiedAgentToolHandlers,
} from '../telegram-hatchery-agent/index.ts'
import {
  type AgentConversationContextClient,
  createSupabaseAgentConversationContextStore,
} from '../telegram-hatchery-agent/agent_conversation_context.ts'
import { computeAuthorizationFingerprint } from '../pip-realtime-session/fingerprint.ts'
import { argumentHash, timingSafeEqual } from './argument_hash.ts'
import { BROKER_SECRET_HEADER, readBrokerSecret } from './config.ts'

// ---------------------------------------------------------------------------
// TOOL BUDGET BOUNDARY — do not add a call cap here.
//
// The Realtime tool cap (PIP_REALTIME_MAX_TOOL_CALLS_PER_INTERACTION, 5 by
// default) is INTERACTION-scoped: it counts the tool calls the model made while
// answering one user utterance, and it is spent in the sideband's
// InteractionTracker before the call ever reaches the network. This function
// sees one call at a time and has no view of an interaction's shape, so any cap
// it invented would be a SECOND, differently-scoped limit that could reject a
// call the sideband had already budgeted for — the model would then be told
// "budget exhausted" by two different authorities with two different counts.
//
// The text channel has its own, separate cap (MAX_AGENT_TOOL_CALLS_PER_TURN in
// agent_tools.ts) enforced in its own runtime loop. Three channels, one cap
// each, each enforced where the loop that spends it lives.
// ---------------------------------------------------------------------------

/**
 * Tools that can change durable state. Used ONLY to decide how a claim settles
 * when execution ends without a trustworthy answer: a read that fails halfway is
 * simply failed and may be retried, but a WRITE that fails halfway is
 * `indeterminate` — we do not know whether the row landed — and an indeterminate
 * claim is never auto-replayed.
 */
const MUTATION_TOOL_NAMES: ReadonlySet<string> = new Set<AgentToolName>([
  'propose_intake',
  'start_intake',
  'record_station_values',
  'create_station_summary',
  'confirm_station_summary',
  'submit_station_for_review',
  'pause_intake',
  'resume_intake',
  'cancel_intake',
  'answer_legacy_draft_question',
])

/** Claim states that mean the call has settled and must not run again. */
const TERMINAL_CLAIM_STATES: ReadonlySet<string> = new Set([
  'succeeded',
  'rejected',
  'failed',
])

/** Postgres SQLSTATE for a unique-index collision. */
const UNIQUE_VIOLATION = '23505'

/** Lease held on a claim while this request executes it. */
const CLAIM_LEASE_SECONDS = 30
const CLAIM_LEASE_OWNER = 'pip-realtime-tool-broker'

/** How many times a `tool_sequence` collision is re-allocated before giving up. */
const MAX_SEQUENCE_ATTEMPTS = 5

// ---------------------------------------------------------------------------
// Narrow client surface — the same shape the sibling Realtime function uses.
// ---------------------------------------------------------------------------

interface DatabaseError {
  message: string
  code?: string
}

interface DatabaseResult<T = unknown> {
  data: T | null
  error: DatabaseError | null
}

interface AdminUpdateFilter {
  eq(column: string, value: unknown): Promise<DatabaseResult>
}

interface AdminQuery {
  select(columns: string): AdminQuery
  eq(column: string, value: unknown): AdminQuery
  order(column: string, options: { ascending: boolean }): AdminQuery
  limit(count: number): Promise<DatabaseResult<Record<string, unknown>[]>>
  maybeSingle(): Promise<DatabaseResult<Record<string, unknown>>>
  insert(values: unknown): Promise<DatabaseResult>
  update(values: unknown): AdminUpdateFilter
}

export interface ToolBrokerAdminClient {
  from(table: string): AdminQuery
}

export interface ToolBrokerDeps {
  adminClient: ToolBrokerAdminClient
  /** null when PIP_REALTIME_BROKER_SECRET is unset — the endpoint then refuses. */
  brokerSecret: string | null
  handlers: Partial<Record<AgentToolName, AgentToolHandler>>
  conversationContext?: AgentConversationContextPort
  newId?: () => string
  now?: () => Date
}

interface BrokerRequestBody {
  readonly sessionId: string
  readonly generation: number
  readonly toolCallId: string
  readonly toolName: string
  readonly arguments: Record<string, unknown>
  readonly interactionId: string
  readonly authorizationFingerprint: string
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export async function handleToolBrokerRequest(
  request: Request,
  deps: ToolBrokerDeps,
): Promise<Response> {
  if (request.method !== 'POST') {
    return failure(405, 'invalid_request', 'Only POST is supported.')
  }

  // Fail closed. An unconfigured secret is a misconfiguration, not permission.
  if (!deps.brokerSecret) {
    console.error('pip-realtime-tool-broker: broker secret is not configured')
    return failure(
      503,
      'broker_not_configured',
      'The tool broker is not configured.',
    )
  }

  const presented = request.headers.get(BROKER_SECRET_HEADER) ?? ''
  if (!timingSafeEqual(presented, deps.brokerSecret)) {
    return failure(401, 'unauthenticated', 'A valid broker secret is required.')
  }

  const body = await readBody(request)
  if (!body) {
    return failure(400, 'invalid_request', 'The request body is not valid.')
  }

  const now = deps.now ?? (() => new Date())
  const newId = deps.newId ?? (() => crypto.randomUUID())
  const client = deps.adminClient

  // --- 1. The session must exist and still be live. ------------------------
  const sessionResult = await client
    .from('agent_realtime_sessions')
    .select(
      'id, conversation_id, context_epoch, authorization_fingerprint, ' +
        'owner_profile_id, active_generation, state',
    )
    .eq('id', body.sessionId)
    .maybeSingle()
  if (sessionResult.error) {
    console.error('pip-realtime-tool-broker: session lookup failed')
    return failure(500, 'server_error', 'Could not load the session.')
  }
  const session = sessionResult.data
  if (!session) {
    return failure(404, 'unknown_session', 'No such Realtime session.')
  }
  if (text(session.state) !== 'active') {
    return refused(
      409,
      'session_not_active',
      'The Realtime session is not active.',
      { session_id: body.sessionId, generation: body.generation },
    )
  }

  // --- 2. The generation must be the CURRENT one and still executable. -----
  if (integer(session.active_generation) !== body.generation) {
    return refused(
      409,
      'stale_generation',
      'That generation is no longer the live one.',
      { session_id: body.sessionId, generation: body.generation },
    )
  }
  const callResult = await client
    .from('agent_realtime_calls')
    .select('session_id, generation, setup_state, authorization_fingerprint')
    .eq('session_id', body.sessionId)
    .eq('generation', body.generation)
    .maybeSingle()
  if (callResult.error) {
    console.error('pip-realtime-tool-broker: generation lookup failed')
    return failure(500, 'server_error', 'Could not load the generation.')
  }
  const call = callResult.data
  if (!call) {
    return refused(
      409,
      'stale_generation',
      'That generation does not exist.',
      { session_id: body.sessionId, generation: body.generation },
    )
  }
  if (text(call.setup_state) !== 'active') {
    return refused(
      409,
      'terminal_generation',
      'That generation is no longer executing tools.',
      { session_id: body.sessionId, generation: body.generation },
    )
  }

  // --- 3. Re-resolve authority. Never trust the caller's fingerprint. ------
  const ownerProfileId = text(session.owner_profile_id)
  if (!ownerProfileId) {
    return refused(
      409,
      'authorization_changed',
      'The session has no resolvable owner.',
      { session_id: body.sessionId, generation: body.generation },
    )
  }

  let profile: AppAgentProfile
  let scope: AgentScope
  try {
    profile = await loadAppProfile(client as AppScopeClient, ownerProfileId)
    scope = await resolveAppAgentScope(
      client as AppScopeClient,
      ownerProfileId,
      profile,
    )
  } catch (error) {
    if (error instanceof AppAgentScopeError) {
      return refused(
        409,
        'authorization_changed',
        'The caller is no longer authorized.',
        { session_id: body.sessionId, generation: body.generation },
      )
    }
    console.error('pip-realtime-tool-broker: scope resolution failed')
    return failure(500, 'server_error', 'Could not resolve authorization.')
  }

  const currentFingerprint = await computeAuthorizationFingerprint({
    staffLinkId: scope.staffLinkId,
    accessRole: scope.accessRole,
    allowedCustomerIds: scope.allowedCustomerIds,
    profileRole: profile.role,
    profileStatus: profile.status,
  })

  // Three values must agree: what the caller claims, what was stamped on the
  // session when it was provisioned, and what the database says right now. Any
  // disagreement means authority moved while the call was in flight.
  const stamped = text(session.authorization_fingerprint) ?? ''
  if (
    !timingSafeEqual(currentFingerprint, stamped) ||
    !timingSafeEqual(currentFingerprint, body.authorizationFingerprint)
  ) {
    return refused(
      409,
      'authorization_changed',
      'Authorization changed while the session was open.',
      { session_id: body.sessionId, generation: body.generation },
    )
  }

  // --- 4. Idempotency: the claim decides whether this executes at all. -----
  const hash = await argumentHash(body.arguments)
  const existing = await loadClaim(client, body)
  if (existing.error) {
    console.error('pip-realtime-tool-broker: claim lookup failed')
    return failure(500, 'server_error', 'Could not load the tool claim.')
  }
  if (existing.row) {
    return await replay(client, existing.row, hash, body)
  }

  const claimId = newId()
  const claimedAt = now()
  const inserted = await client.from('agent_tool_call_claims').insert({
    id: claimId,
    inbound_turn_id: null,
    realtime_session_id: body.sessionId,
    realtime_generation: body.generation,
    realtime_interaction_id: body.interactionId,
    openai_tool_call_id: body.toolCallId,
    tool_name: body.toolName,
    argument_hash: hash,
    state: 'claimed',
    lease_owner: CLAIM_LEASE_OWNER,
    lease_expires_at: new Date(
      claimedAt.getTime() + CLAIM_LEASE_SECONDS * 1000,
    ).toISOString(),
    tool_event_id: null,
    claimed_at: claimedAt.toISOString(),
    settled_at: null,
  })
  if (inserted.error) {
    if (inserted.error.code !== UNIQUE_VIOLATION) {
      console.error('pip-realtime-tool-broker: claim insert failed')
      return failure(500, 'server_error', 'Could not claim the tool call.')
    }
    // Lost a race with a concurrent delivery of the same call id. The winner
    // owns execution; this request must not run the side effect again.
    const raced = await loadClaim(client, body)
    if (raced.error || !raced.row) {
      return failure(500, 'server_error', 'Could not claim the tool call.')
    }
    return await replay(client, raced.row, hash, body)
  }

  // --- 5. Execute through the shared runtime. -----------------------------
  const conversationId = text(session.conversation_id) ?? ''
  const contextEpoch = integer(session.context_epoch)
  if (!conversationId || contextEpoch === null || contextEpoch < 1) {
    await settleClaim(client, claimId, 'failed', null, now())
    return failure(
      500,
      'server_error',
      'The session has no usable conversation.',
    )
  }

  const activeVisitId = await loadActiveVisitId(client, conversationId)
  if (activeVisitId === undefined) {
    await settleClaim(client, claimId, 'failed', null, now())
    return failure(500, 'server_error', 'Could not load the conversation.')
  }

  const startedAt = now()
  const evidence = createRealtimeEvidencePort({
    client,
    newId,
    now,
    sessionId: body.sessionId,
    generation: body.generation,
    interactionId: body.interactionId,
    argumentHash: hash,
    startedAt,
  })

  let result: AgentToolResult
  try {
    result = await executeAgentTool(
      {
        id: body.toolCallId,
        name: body.toolName,
        arguments: body.arguments,
      },
      {
        scope,
        conversationId,
        activeVisitId,
        // conversationTurnId is deliberately omitted. Realtime evidence carries
        // a NULL conversation_turn_id: the inbound transcript may never
        // finalize, and no placeholder turn is ever fabricated to satisfy a
        // foreign key. The turn link is back-filled on the mutable CLAIM.
        conversationContextEpoch: contextEpoch,
        evidence,
        conversationContext: deps.conversationContext,
        handlers: deps.handlers,
        now: () => now().getTime(),
      },
    )
  } catch (_) {
    // executeAgentTool swallows handler failures itself, so a throw here comes
    // from AFTER the side effect ran: the evidence write or the conversation
    // context update. For a mutation that is genuinely indeterminate.
    const state = MUTATION_TOOL_NAMES.has(body.toolName)
      ? 'indeterminate'
      : 'failed'
    await settleClaim(client, claimId, state, evidence.eventId(), now())
    console.error('pip-realtime-tool-broker: tool execution did not settle', {
      session_id: body.sessionId,
      generation: body.generation,
      interaction_id: body.interactionId,
      tool_name: body.toolName,
      claim_state: state,
    })
    return refused(
      state === 'indeterminate' ? 409 : 500,
      state === 'indeterminate' ? 'tool_indeterminate' : 'tool_failed',
      'The tool call did not settle.',
      { session_id: body.sessionId, generation: body.generation },
    )
  }

  const status: ToolStatus = result.ok
    ? 'succeeded'
    : REJECTION_CODES.has(result.code)
    ? 'rejected'
    : 'failed'
  await settleClaim(client, claimId, status, evidence.eventId(), now())

  console.info('pip-realtime-tool-broker: tool executed', {
    session_id: body.sessionId,
    generation: body.generation,
    interaction_id: body.interactionId,
    tool_name: body.toolName,
    status,
  })

  return json(200, { status, result, disposition: 'executed' })
}

/**
 * Result codes `executeAgentTool` uses for a refusal rather than a failure.
 *
 * The distinction is not cosmetic: a `failed` claim reads, in the ledger and
 * in any later incident reconstruction, as "the tool broke". A refusal is the
 * tool working correctly and declining — a scope denial, an argument the
 * contract rejects, or a precondition the model has to satisfy first. Every
 * code a handler can return DELIBERATELY belongs here; only an unexpected
 * `tool_failed`/`tool_unavailable` should settle as a failure.
 */
const REJECTION_CODES: ReadonlySet<string> = new Set([
  'unknown_tool',
  'invalid_arguments',
  'scope_denied',
  'unsupported_station_schema',
  // Audit-selection preconditions. Both name a recovery the model can act on
  // by itself (list the options; ask for a number in range), which is exactly
  // what makes them refusals rather than breakage.
  'audit_options_required',
  'audit_position_out_of_range',
  'fresh_audit_selection_required',
])

type ToolStatus = 'succeeded' | 'rejected' | 'failed'

// ---------------------------------------------------------------------------
// Idempotency
// ---------------------------------------------------------------------------

async function loadClaim(
  client: ToolBrokerAdminClient,
  body: BrokerRequestBody,
): Promise<{ row: Record<string, unknown> | null; error: boolean }> {
  const result = await client
    .from('agent_tool_call_claims')
    .select('id, argument_hash, state, tool_event_id')
    .eq('realtime_session_id', body.sessionId)
    .eq('realtime_generation', body.generation)
    .eq('openai_tool_call_id', body.toolCallId)
    .maybeSingle()
  if (result.error) return { row: null, error: true }
  return { row: result.data, error: false }
}

/**
 * A claim already exists for this call id. Nothing is executed on this path —
 * the only question is which answer the caller gets.
 */
async function replay(
  client: ToolBrokerAdminClient,
  claim: Record<string, unknown>,
  hash: string,
  body: BrokerRequestBody,
): Promise<Response> {
  const recordedHash = text(claim.argument_hash) ?? ''
  if (!timingSafeEqual(recordedHash, hash)) {
    // Same call id, different arguments. That is not a redelivery, it is a
    // conflict, and executing it would apply the NEWER arguments under an
    // identity that already answered for the older ones.
    return refused(
      409,
      'argument_conflict',
      'This tool call id was already claimed with different arguments.',
      { session_id: body.sessionId, generation: body.generation },
    )
  }

  const state = text(claim.state) ?? ''
  if (state === 'indeterminate') {
    // A mutation whose outcome is unknown is NEVER auto-replayed: re-running it
    // could double-apply the write, and reporting success could report a write
    // that never landed. A human decides.
    return refused(
      409,
      'indeterminate_not_replayable',
      'A previous attempt at this tool call did not settle.',
      { session_id: body.sessionId, generation: body.generation },
    )
  }

  if (!TERMINAL_CLAIM_STATES.has(state)) {
    return refused(
      409,
      'claim_in_flight',
      'This tool call is already being executed.',
      { session_id: body.sessionId, generation: body.generation },
    )
  }

  const eventId = text(claim.tool_event_id)
  let recorded: unknown = null
  if (eventId) {
    const event = await client
      .from('agent_tool_events')
      .select('id, result_json')
      .eq('id', eventId)
      .maybeSingle()
    if (event.error) {
      return failure(500, 'server_error', 'Could not load the recorded result.')
    }
    recorded = event.data?.result_json ?? null
  }

  console.info('pip-realtime-tool-broker: duplicate tool call', {
    session_id: body.sessionId,
    generation: body.generation,
    interaction_id: body.interactionId,
    tool_name: body.toolName,
    claim_state: state,
  })

  return json(200, {
    status: state as ToolStatus,
    result: recorded ?? { ok: state === 'succeeded', code: state, data: null },
    disposition: 'duplicate',
  })
}

async function settleClaim(
  client: ToolBrokerAdminClient,
  claimId: string,
  state: string,
  toolEventId: string | null,
  settledAt: Date,
): Promise<void> {
  const result = await client
    .from('agent_tool_call_claims')
    .update({
      state,
      tool_event_id: toolEventId,
      lease_owner: null,
      lease_expires_at: null,
      settled_at: settledAt.toISOString(),
    })
    .eq('id', claimId)
  if (result.error) {
    // The evidence row is already durable; a failed settle leaves the claim
    // leased, and the lease expiry is what recovers it. Never throw from here.
    console.error('pip-realtime-tool-broker: claim settle failed')
  }
}

// ---------------------------------------------------------------------------
// Evidence
// ---------------------------------------------------------------------------

interface RealtimeEvidencePort extends AgentToolEvidencePort {
  /** Id of the row written, or null if nothing was written. */
  eventId(): string | null
}

/**
 * Writes ONE immutable `agent_tool_events` row per tool call.
 *
 * The table has a trigger that raises on UPDATE and DELETE, so this is
 * insert-only: there is no correcting a row afterwards. `tool_sequence` is NOT
 * NULL and is protected by a partial unique index on
 * (realtime_session_id, realtime_generation, tool_sequence), so the sequence is
 * allocated from the rows already present and re-allocated on collision rather
 * than being tracked in memory — two brokers serving the same generation must
 * not both believe they own sequence 3.
 */
function createRealtimeEvidencePort(options: {
  client: ToolBrokerAdminClient
  newId: () => string
  now: () => Date
  sessionId: string
  generation: number
  interactionId: string
  argumentHash: string
  startedAt: Date
}): RealtimeEvidencePort {
  let writtenId: string | null = null
  return {
    eventId: () => writtenId,
    async record(event: AgentToolEvidence): Promise<void> {
      const completedAt = options.now()
      const id = options.newId()
      let lastError: DatabaseError | null = null
      for (let attempt = 0; attempt < MAX_SEQUENCE_ATTEMPTS; attempt++) {
        const sequence = await nextToolSequence(
          options.client,
          options.sessionId,
          options.generation,
        )
        if (sequence === null) {
          throw new Error('Could not allocate a tool sequence')
        }
        const inserted = await options.client.from('agent_tool_events').insert({
          id,
          conversation_turn_id: null,
          tool_call_id: event.callId,
          tool_name: event.toolName,
          arguments_json: { ...event.arguments, _scope: event.scope },
          result_json: event.result,
          status: event.status,
          duration_ms: event.durationMs,
          state_version_before: event.stateVersionBefore,
          state_version_after: event.stateVersionAfter,
          tool_sequence: sequence,
          realtime_session_id: options.sessionId,
          realtime_generation: options.generation,
          realtime_interaction_id: options.interactionId,
          argument_hash: options.argumentHash,
          source_channel: 'realtime_voice',
          confirmation_state: null,
          started_at: options.startedAt.toISOString(),
          completed_at: completedAt.toISOString(),
          created_at: completedAt.toISOString(),
        })
        if (!inserted.error) {
          writtenId = id
          return
        }
        lastError = inserted.error
        if (inserted.error.code !== UNIQUE_VIOLATION) break
      }
      // Never log the row. The caller turns this into an indeterminate claim.
      console.error('pip-realtime-tool-broker: evidence write failed', {
        session_id: options.sessionId,
        generation: options.generation,
        code: lastError?.code ?? 'unknown',
      })
      throw new Error('Could not store realtime tool evidence')
    },
  }
}

async function nextToolSequence(
  client: ToolBrokerAdminClient,
  sessionId: string,
  generation: number,
): Promise<number | null> {
  const result = await client
    .from('agent_tool_events')
    .select('tool_sequence')
    .eq('realtime_session_id', sessionId)
    .eq('realtime_generation', generation)
    .order('tool_sequence', { ascending: false })
    .limit(1)
  if (result.error) return null
  const highest = integer(result.data?.[0]?.tool_sequence)
  return (highest ?? 0) + 1
}

// ---------------------------------------------------------------------------
// Conversation lookup
// ---------------------------------------------------------------------------

/** Returns the active visit id, or `undefined` when the lookup itself failed. */
async function loadActiveVisitId(
  client: ToolBrokerAdminClient,
  conversationId: string,
): Promise<string | null | undefined> {
  const result = await client
    .from('agent_conversations')
    .select('id, active_visit_id')
    .eq('id', conversationId)
    .maybeSingle()
  if (result.error) return undefined
  if (!result.data) return undefined
  return text(result.data.active_visit_id)
}

// ---------------------------------------------------------------------------
// Request parsing
// ---------------------------------------------------------------------------

async function readBody(request: Request): Promise<BrokerRequestBody | null> {
  let parsed: unknown
  try {
    parsed = await request.json()
  } catch (_) {
    return null
  }
  if (!isRecord(parsed)) return null

  const sessionId = boundedText(parsed.session_id, 160)
  const generation = integer(parsed.generation)
  const toolCallId = boundedText(parsed.tool_call_id, 160)
  const toolName = boundedText(parsed.tool_name, 120)
  const interactionId = boundedText(parsed.interaction_id, 160)
  const authorizationFingerprint = boundedText(
    parsed.authorization_fingerprint,
    128,
  )
  const args = parsed.arguments === undefined || parsed.arguments === null
    ? {}
    : parsed.arguments

  if (
    !sessionId ||
    generation === null ||
    generation < 1 ||
    !toolCallId ||
    !toolName ||
    !interactionId ||
    !authorizationFingerprint ||
    !isRecord(args)
  ) {
    return null
  }

  return {
    sessionId,
    generation,
    toolCallId,
    toolName,
    arguments: args,
    interactionId,
    authorizationFingerprint,
  }
}

// ---------------------------------------------------------------------------
// Responses and helpers
// ---------------------------------------------------------------------------

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function failure(status: number, code: string, error: string): Response {
  return json(status, { error, code })
}

/** A refusal the control plane made deliberately. Logged with ids only. */
function refused(
  status: number,
  code: string,
  error: string,
  context: Record<string, unknown>,
): Response {
  console.warn(`pip-realtime-tool-broker: ${code}`, context)
  return json(status, { error, code })
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function text(value: unknown): string | null {
  if (typeof value !== 'string') return value === null ? null : null
  const trimmed = value.trim()
  return trimmed ? trimmed : null
}

function boundedText(value: unknown, maxLength: number): string | null {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  if (!trimmed || trimmed.length > maxLength) return null
  return trimmed
}

function integer(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) ? value : null
}

// ---------------------------------------------------------------------------
// Deployment wiring
// ---------------------------------------------------------------------------

export function serveToolBroker(
  request: Request,
): Response | Promise<Response> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, {
      error: 'The realtime tool broker is not configured.',
      code: 'server_error',
    })
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  return handleToolBrokerRequest(request, {
    adminClient: supabase as unknown as ToolBrokerAdminClient,
    brokerSecret: readBrokerSecret(),
    // The SAME catalogue the Telegram and in-app doors execute. Never a copy.
    handlers: createUnifiedAgentToolHandlers(
      supabase as unknown as TelegramAdminClient,
    ),
    conversationContext: createSupabaseAgentConversationContextStore(
      supabase as unknown as AgentConversationContextClient,
    ),
  })
}

if (import.meta.main) {
  Deno.serve(serveToolBroker)
}
