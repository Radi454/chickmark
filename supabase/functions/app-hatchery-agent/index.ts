// app-hatchery-agent — the in-app door into the unified ChickMark agent brain.
//
// This function does NOT implement an agent. It reuses telegram-hatchery-agent's
// runtime, prompt, tool catalog, provider and tool handlers verbatim, and writes
// to the same agent_conversations / agent_conversation_turns / agent_tool_events
// tables. The only differences from the Telegram door are the transport
// (authenticated JSON over HTTPS instead of a Telegram webhook), the identity
// (a Supabase auth user instead of a Telegram user), and text-only input.
//
// Deployed WITH JWT verification. The bearer token is additionally re-read here
// and resolved through the service-role client.
//
// Logging discipline: never log message text, replies, tokens or provider keys.

import { createClient } from '@supabase/supabase-js'

import { readVoiceConfig, synthesizeSpeech, transcribeAudio } from './voice.ts'
import { createResponsesAgentProvider } from '../telegram-hatchery-agent/agent_provider.ts'
import type { AgentScope } from '../telegram-hatchery-agent/agent_protocol.ts'
import {
  type AgentTurnInput,
  type AgentTurnResult,
  type AgentTurnTelemetry,
  runAgentTurn,
} from '../telegram-hatchery-agent/agent_runtime.ts'
import { executeAgentTool } from '../telegram-hatchery-agent/agent_tools.ts'
import type { AgentToolEvidence } from '../telegram-hatchery-agent/agent_tools.ts'
import {
  type AdminClient as TelegramAdminClient,
  createUnifiedAgentToolHandlers,
} from '../telegram-hatchery-agent/index.ts'
import {
  type AgentConversationContextClient,
  createSupabaseAgentConversationContextStore,
} from '../telegram-hatchery-agent/agent_conversation_context.ts'
import {
  resolveOpenRouterTextModels,
  resolvePipTextModel,
} from '../_shared/pip_model_routing.ts'
import {
  type AgentContextClient,
  allocateAgentTurnSlot,
  buildAgentContext,
} from '../telegram-hatchery-agent/agent_context.ts'
import {
  APP_CHANNEL_CHAT_ID,
  type AppAgentProfile,
  AppAgentScopeError,
  type AppScopeClient,
  ensureAppStaffLink,
  loadAppProfile,
  resolveAppAgentScope,
} from './app_agent_scope.ts'
import { deriveConversationTitle } from './conversation_title.ts'

const MAX_MESSAGE_CHARS = 4000
const DEFAULT_HISTORY_LIMIT = 50
const MAX_HISTORY_LIMIT = 100
const DEFAULT_CONVERSATIONS_LIMIT = 50
const MAX_CONVERSATIONS_LIMIT = 100
const CONVERSATION_PREVIEW_CHARS = 140
// Defensive upper bound on how many of the caller's own app conversations are
// ever fetched from the database before sorting/truncating to the requested
// page size in code.
const CONVERSATIONS_FETCH_CAP = 1000
// 'app' is the legacy single-conversation key; 'app:<uuid v4>' keys any
// additional conversation the same app user opens. Both share the app
// channel's staff-link row — see APP_CHANNEL_CHAT_ID.
const APP_CONVERSATION_KEY_PATTERN =
  /^app:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
// The model-context window itself lives in
// ../telegram-hatchery-agent/agent_context.ts, shared with the Telegram door.
const RATE_LIMIT_SENDS = 20
const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000
// Keep numerically equal to the client's assistantAudioMaxBase64Chars
// (lib/services/supabase/assistant_chat_service.dart) — a few seconds of
// speech, not tens of minutes, to bound the Whisper/TTS spend.
const MAX_AUDIO_BASE64_CHARS = 1_500_000

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

interface DatabaseError {
  message: string
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
  like(column: string, pattern: string): AdminQuery
  in(column: string, values: unknown[]): AdminQuery
  order(column: string, options: { ascending: boolean }): AdminQuery
  limit(count: number): Promise<DatabaseResult<Record<string, unknown>[]>>
  maybeSingle(): Promise<DatabaseResult<Record<string, unknown>>>
  insert(values: unknown): Promise<DatabaseResult>
  update(values: unknown): UpdateFilter
}

export interface AppAgentAdminClient {
  from(table: string): AdminQuery
}

export interface AppAgentAuthUser {
  id: string
}

export interface AppAgentDeps {
  adminClient: AppAgentAdminClient
  /** Resolves the bearer token to an auth user, or null when it is invalid. */
  authenticate(accessToken: string): Promise<AppAgentAuthUser | null>
  runAgentTurn(input: AgentTurnInput): Promise<AgentTurnResult>
  /** Transcribes a base64 audio clip. Undefined when voice is not configured. */
  transcribeAudio?(audioBase64: string): Promise<string>
  /** Synthesizes speech for a reply. Undefined when voice is not configured. */
  synthesizeSpeech?(
    text: string,
    language?: 'en' | 'ar' | 'mixed',
  ): Promise<string>
  newId?: () => string
  now?: () => string
}

type AppAction = 'send' | 'history' | 'reset' | 'conversations'

export async function handleAppAgentRequest(
  request: Request,
  deps: AppAgentDeps,
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
  if (hasAttachmentField(body)) {
    return failure(
      400,
      'invalid_request',
      'The assistant accepts text only. Attachments are not supported.',
    )
  }
  const action = readAction(body.action)
  if (!action) {
    return failure(400, 'invalid_request', 'Unknown action.')
  }

  let authUser: AppAgentAuthUser | null
  try {
    authUser = await deps.authenticate(accessToken)
  } catch (_) {
    authUser = null
  }
  const authUserId = authUser ? nullableString(authUser.id) : null
  if (!authUserId) {
    return failure(401, 'unauthenticated', 'The session is not valid.')
  }

  const newId = deps.newId ?? (() => crypto.randomUUID())
  const now = deps.now ?? (() => new Date().toISOString())
  const scopeClient = deps.adminClient as unknown as AppScopeClient

  let profile: AppAgentProfile
  let scope: AgentScope
  let staffLinkId: string
  try {
    profile = await loadAppProfile(scopeClient, authUserId)
    scope = await resolveAppAgentScope(scopeClient, authUserId, profile)
    staffLinkId = await ensureAppStaffLink(scopeClient, profile, now())
  } catch (error) {
    if (error instanceof AppAgentScopeError) {
      return failure(
        403,
        'not_approved',
        'This account is not approved for the assistant.',
      )
    }
    console.error('app-hatchery-agent: scope resolution failed')
    return failure(500, 'server_error', 'Could not resolve the caller.')
  }

  if (action === 'conversations') {
    return await handleConversations({
      deps,
      staffLinkId,
      limit: readConversationsLimit(body.limit),
    })
  }

  const conversationKey = readConversationKey(body.conversationId)
  if (!conversationKey) {
    return failure(400, 'invalid_request', 'conversationId is invalid.')
  }

  // Only `send` may durably create a conversation row. `history` and `reset`
  // are read/no-op paths: hitting them for a conversation key that was never
  // sent to (e.g. the app opens a fresh `app:<uuid>` screen and the user
  // backs out without typing) must never leave a placeholder row behind.
  if (action === 'history') {
    const limit = readHistoryLimit(body.limit)
    if (limit === null) {
      return failure(400, 'invalid_request', 'limit must be between 1 and 100.')
    }
    const conversation = await loadConversation({
      adminClient: deps.adminClient,
      staffLinkId,
      chatKey: conversationKey,
    })
    if (conversation === undefined) {
      return failure(500, 'server_error', 'Could not load the conversation.')
    }
    if (conversation === null) {
      return success({
        conversationId: null,
        conversationKey,
        messages: [],
      })
    }
    const conversationId = nullableString(conversation.id)
    if (!conversationId) {
      return failure(500, 'server_error', 'The conversation is invalid.')
    }
    const contextEpoch = positiveInteger(conversation.context_epoch) ?? 1
    return await handleHistory({
      deps,
      conversationId,
      conversationKey,
      contextEpoch,
      limit,
    })
  }
  if (action === 'reset') {
    const conversation = await loadConversation({
      adminClient: deps.adminClient,
      staffLinkId,
      chatKey: conversationKey,
    })
    if (conversation === undefined) {
      return failure(500, 'server_error', 'Could not load the conversation.')
    }
    if (conversation === null) {
      return success({ cleared: true })
    }
    const conversationId = nullableString(conversation.id)
    if (!conversationId) {
      return failure(500, 'server_error', 'The conversation is invalid.')
    }
    const contextEpoch = positiveInteger(conversation.context_epoch) ?? 1
    return await handleReset({
      deps,
      conversation,
      conversationId,
      contextEpoch,
      timestamp: now(),
    })
  }

  const conversation = await loadOrCreateConversation({
    adminClient: deps.adminClient,
    staffLinkId,
    chatKey: conversationKey,
    ownerProfileId: authUserId,
    newId,
    timestamp: now(),
  })
  if (!conversation) {
    return failure(500, 'server_error', 'Could not load the conversation.')
  }
  const conversationId = nullableString(conversation.id)
  if (!conversationId) {
    return failure(500, 'server_error', 'The conversation is invalid.')
  }
  const contextEpoch = positiveInteger(conversation.context_epoch) ?? 1

  return await handleSend({
    deps,
    scope,
    staffLinkId,
    conversation,
    conversationId,
    conversationKey,
    contextEpoch,
    body,
    newId,
    now,
  })
}

/**
 * Load-only lookup for `history` and `reset`: never creates a row. Returns
 * `undefined` on a database error, `null` when no conversation exists yet
 * for this key.
 */
async function loadConversation(params: {
  adminClient: AppAgentAdminClient
  staffLinkId: string
  chatKey: string
}): Promise<Record<string, unknown> | null | undefined> {
  const result = await params.adminClient
    .from('agent_conversations')
    .select('*')
    .eq('staff_link_id', params.staffLinkId)
    .eq('telegram_chat_id', params.chatKey)
    .maybeSingle()
  if (result.error) return undefined
  return result.data ?? null
}

async function handleHistory(params: {
  deps: AppAgentDeps
  conversationId: string
  conversationKey: string
  contextEpoch: number
  limit: number
}): Promise<Response> {
  const result = await params.deps.adminClient
    .from('agent_conversation_turns')
    .select(
      'id, direction, text, language, created_at, source_channel, completion_status',
    )
    .eq('conversation_id', params.conversationId)
    .eq('context_epoch', params.contextEpoch)
    // conversation_seq is the allocator-issued, monotonic chronological key.
    // created_at is a wall clock stamped by whichever runtime wrote the row
    // (historical voice rows came from a different runtime), and those clocks
    // can disagree enough to invert a pair — conversation_seq cannot.
    .order('conversation_seq', { ascending: false })
    .order('id', { ascending: false })
    .limit(params.limit)
  if (result.error) {
    return failure(500, 'server_error', 'Could not load the conversation.')
  }
  const messages = (result.data ?? [])
    .slice()
    .reverse()
    .flatMap((turn) => {
      const role = directionToRole(turn.direction)
      const id = nullableString(turn.id)
      const text = nullableString(turn.text)
      if (!role || !id || !text) return []
      return [{
        id,
        role,
        text,
        language: readLanguage(turn.language),
        source: turn.source_channel === 'realtime_voice' ? 'voice' : 'text',
        createdAt: nullableString(turn.created_at) ?? '',
      }]
    })
  return success({
    conversationId: params.conversationId,
    conversationKey: params.conversationKey,
    messages,
  })
}

async function handleReset(params: {
  deps: AppAgentDeps
  conversation: Record<string, unknown>
  conversationId: string
  contextEpoch: number
  timestamp: string
}): Promise<Response> {
  const nextStateVersion =
    (positiveInteger(params.conversation.state_version) ?? 1) + 1
  const update = await params.deps.adminClient
    .from('agent_conversations')
    .update({
      context_epoch: params.contextEpoch + 1,
      state_version: nextStateVersion,
      pending_action_json: null,
      active_visit_id: null,
      selected_customer_id: null,
      selected_flock_id: null,
      selected_audit_id: null,
      context_updated_at: params.timestamp,
      updated_at: params.timestamp,
    })
    .eq('id', params.conversationId)
  if (update.error) {
    return failure(500, 'server_error', 'Could not reset the conversation.')
  }
  return success({ conversationId: params.conversationId, cleared: true })
}

interface ConversationListItem {
  conversationKey: string
  title: string | null
  lastMessageText: string | null
  lastMessageAt: string | null
  updatedAt: string
  createdAt: string
}

async function handleConversations(params: {
  deps: AppAgentDeps
  staffLinkId: string
  limit: number | null
}): Promise<Response> {
  if (params.limit === null) {
    return failure(400, 'invalid_request', 'limit must be between 1 and 100.')
  }
  const result = await params.deps.adminClient
    .from('agent_conversations')
    .select('id, telegram_chat_id, title, created_at, updated_at')
    .eq('staff_link_id', params.staffLinkId)
    .like('telegram_chat_id', 'app%')
    .order('updated_at', { ascending: false })
    .limit(CONVERSATIONS_FETCH_CAP)
  if (result.error) {
    return failure(500, 'server_error', 'Could not load conversations.')
  }

  // Defensive: PostgREST's `like` only narrows by prefix, so re-check the
  // exact key shape here rather than trusting every 'app%' row is really
  // this caller's own conversation key.
  const rows = (result.data ?? []).filter((row) =>
    isAppConversationKey(nullableString(row.telegram_chat_id))
  )
  if (rows.length === 0) return success({ conversations: [] })

  const ids = rows
    .map((row) => nullableString(row.id))
    .filter((id): id is string => id !== null)
  const previews = await loadConversationPreviews(params.deps, ids)

  const conversations: ConversationListItem[] = rows
    .flatMap((row): ConversationListItem[] => {
      const id = nullableString(row.id)
      const conversationKey = nullableString(row.telegram_chat_id)
      const createdAt = nullableString(row.created_at)
      const updatedAt = nullableString(row.updated_at)
      if (!id || !conversationKey || !createdAt || !updatedAt) return []
      const title = nullableString(row.title)
      const preview = previews.get(id)
      const hasAnyTurn = preview?.hasAnyTurn ?? false
      // Placeholder rows: opened but never used, never titled, and not the
      // legacy 'app' conversation — nothing distinguishes them for the
      // caller yet, so they are omitted rather than shown as empty.
      if (!hasAnyTurn && !title && conversationKey !== APP_CHANNEL_CHAT_ID) {
        return []
      }
      return [{
        conversationKey,
        title,
        lastMessageText: preview?.text ?? null,
        lastMessageAt: preview?.createdAt ?? null,
        updatedAt,
        createdAt,
      }]
    })
    .sort((a, b) => compareText(b.updatedAt, a.updatedAt))
    .slice(0, params.limit)

  return success({ conversations })
}

interface ConversationPreview {
  hasAnyTurn: boolean
  text: string | null
  createdAt: string | null
}

// Per-conversation preview lookup: cheap enough (the list a caller sees is
// capped at MAX_CONVERSATIONS_LIMIT) that one small query per conversation,
// run concurrently, beats a single globally-limited query. conversation_seq
// is per-conversation, not global — a single `.order().limit(n)` query
// across every conversation lets one long-running thread's turns fill the
// entire window, starving every other conversation's preview (and, since a
// starved voice-only conversation then looks turn-less, getting it wrongly
// filtered out as a placeholder in handleConversations).
const CONVERSATION_PREVIEW_FETCH_LIMIT = 3

async function loadConversationPreviews(
  deps: AppAgentDeps,
  conversationIds: string[],
): Promise<Map<string, ConversationPreview>> {
  const previews = new Map<string, ConversationPreview>()
  if (conversationIds.length === 0) return previews
  const entries = await Promise.all(
    conversationIds.map(async (conversationId) =>
      [
        conversationId,
        await loadConversationPreview(deps, conversationId),
      ] as const
    ),
  )
  for (const [conversationId, preview] of entries) {
    previews.set(conversationId, preview)
  }
  return previews
}

async function loadConversationPreview(
  deps: AppAgentDeps,
  conversationId: string,
): Promise<ConversationPreview> {
  const empty: ConversationPreview = {
    hasAnyTurn: false,
    text: null,
    createdAt: null,
  }
  const result = await deps.adminClient
    .from('agent_conversation_turns')
    .select('text, created_at')
    .eq('conversation_id', conversationId)
    .order('conversation_seq', { ascending: false })
    .limit(CONVERSATION_PREVIEW_FETCH_LIMIT)
  if (result.error) return empty
  const rows = result.data ?? []
  if (rows.length === 0) return empty
  for (const row of rows) {
    const text = nullableString(row.text)
    if (text) {
      return {
        hasAnyTurn: true,
        text: truncatePreview(text),
        createdAt: nullableString(row.created_at),
      }
    }
  }
  return { hasAnyTurn: true, text: null, createdAt: null }
}

async function handleSend(params: {
  deps: AppAgentDeps
  scope: AgentScope
  staffLinkId: string
  conversation: Record<string, unknown>
  conversationId: string
  conversationKey: string
  contextEpoch: number
  body: Record<string, unknown>
  newId: () => string
  now: () => string
}): Promise<Response> {
  const clientMessageId = nullableString(params.body.clientMessageId)
  if (!clientMessageId || clientMessageId.length > 200) {
    return failure(400, 'invalid_request', 'clientMessageId is required.')
  }
  const idempotencyKey = `app:${clientMessageId}`

  const audioProvided = params.body.audioBase64 !== undefined &&
    params.body.audioBase64 !== null
  let audioBase64Input: string | null = null
  if (audioProvided) {
    audioBase64Input = readAudioBase64(params.body.audioBase64)
    if (!audioBase64Input) {
      return failure(
        400,
        'invalid_request',
        `audioBase64 must be a non-empty base64 string under ${MAX_AUDIO_BASE64_CHARS} characters.`,
      )
    }
  }

  // Replay: the same clientMessageId must return the stored reply, never a
  // second model call (and, for voice, never a second transcription call).
  // Scoped to this conversation (defense in depth: the id is already in
  // hand, and telegram_update_id is not otherwise guaranteed unique).
  const existingInbound = await params.deps.adminClient
    .from('agent_conversation_turns')
    .select('id, turn_index, context_epoch, text')
    .eq('conversation_id', params.conversationId)
    .eq('telegram_update_id', idempotencyKey)
    .maybeSingle()
  if (existingInbound.error) {
    return failure(500, 'server_error', 'Could not check the message.')
  }
  const replayInboundId = existingInbound.data
    ? nullableString(existingInbound.data.id)
    : null
  if (replayInboundId) {
    const storedReply = await loadStoredReply(
      params.deps,
      params.conversationId,
      replayInboundId,
    )
    if (storedReply.error) {
      return failure(500, 'server_error', 'Could not load the stored reply.')
    }
    if (storedReply.reply) {
      const payload: Record<string, unknown> = {
        conversationId: params.conversationId,
        conversationKey: params.conversationKey,
        userTurnId: replayInboundId,
        replyTurnId: storedReply.reply.id,
        reply: storedReply.reply.text,
        language: storedReply.reply.language,
        createdAt: storedReply.reply.createdAt,
      }
      if (audioProvided) {
        const transcript = nullableString(existingInbound.data?.text)
        if (transcript) payload.transcript = transcript
        const audio = await synthesizeReplyAudio(
          params.deps,
          storedReply.reply.text,
          storedReply.reply.language,
        )
        if (audio) payload.audioBase64 = audio
      }
      return success(payload)
    }
    // The earlier attempt stored the inbound turn but never produced a reply.
    // Fall through and finish that same turn instead of creating a duplicate.
  }

  let message: string | null
  if (audioProvided) {
    if (!params.deps.transcribeAudio) {
      return failure(
        502,
        'agent_unavailable',
        'Voice is not available right now.',
      )
    }
    let transcript: string
    try {
      transcript = await params.deps.transcribeAudio(audioBase64Input!)
    } catch (_) {
      return failure(
        502,
        'agent_unavailable',
        'Could not understand the audio. Please try again.',
      )
    }
    message = readMessage(transcript)
  } else {
    message = readMessage(params.body.message)
  }
  if (!message) {
    return audioProvided
      ? failure(
        502,
        'agent_unavailable',
        'Could not understand the audio. Please try again.',
      )
      : failure(
        400,
        'invalid_request',
        `message must be between 1 and ${MAX_MESSAGE_CHARS} characters.`,
      )
  }

  const timestamp = params.now()
  if (!replayInboundId) {
    const limited = await isRateLimited(
      params.deps,
      params.staffLinkId,
      timestamp,
    )
    if (limited === null) {
      return failure(500, 'server_error', 'Could not check the send rate.')
    }
    if (limited) {
      return failure(
        429,
        'rate_limited',
        'Too many messages. Please wait a moment and try again.',
      )
    }
  }

  const contextClient = params.deps
    .adminClient as unknown as AgentContextClient
  const activeVisitId = nullableString(params.conversation.active_visit_id)
  const agentContext = await buildAgentContext(contextClient, {
    conversationId: params.conversationId,
    contextEpoch: params.contextEpoch,
    activeVisitId,
  })
  if (!agentContext) {
    return failure(500, 'server_error', 'Could not load the conversation.')
  }

  let inboundTurnId = replayInboundId
  let turnIndex = replayInboundId && existingInbound.data
    ? integerValue(existingInbound.data.turn_index) ?? 1
    : 0
  if (!inboundTurnId) {
    const inboundSlot = await allocateAgentTurnSlot(contextClient, {
      conversationId: params.conversationId,
      contextEpoch: params.contextEpoch,
      direction: 'inbound',
    })
    if (!inboundSlot) {
      return failure(500, 'server_error', 'Could not store the message.')
    }
    turnIndex = inboundSlot.turnIndex
    inboundTurnId = params.newId()
    const inboundInsert = await params.deps.adminClient
      .from('agent_conversation_turns')
      .insert({
        id: inboundTurnId,
        conversation_id: params.conversationId,
        direction: 'inbound',
        turn_index: turnIndex,
        conversation_seq: inboundSlot.conversationSeq,
        context_epoch: params.contextEpoch,
        source_channel: 'app_text',
        completion_status: 'finalized',
        telegram_update_id: idempotencyKey,
        telegram_message_id: null,
        text: message,
        language: detectAgentLanguage(message),
        provider: null,
        model: null,
        provider_response_id: null,
        attachment_json: null,
        delivery_status: 'received',
        created_at: timestamp,
      })
    if (inboundInsert.error) {
      // A concurrent request won the idempotency race.
      const stored = await loadStoredReplyByKey(
        params.deps,
        params.conversationId,
        idempotencyKey,
      )
      if (stored) {
        return success({
          conversationId: params.conversationId,
          conversationKey: params.conversationKey,
          ...stored,
        })
      }
      return failure(500, 'server_error', 'Could not store the message.')
    }

    await maybeSetConversationTitle(
      params.deps,
      params.conversation,
      params.conversationId,
      message,
    )
    // Best-effort: a durable turn was just written, so the conversation's
    // recency in `conversations` list ordering must reflect it — nothing
    // else ever bumps updated_at on a turn write.
    await touchConversationUpdatedAt(
      params.deps,
      params.conversationId,
      timestamp,
    )
  }

  let result: AgentTurnResult
  try {
    result = await params.deps.runAgentTurn({
      scope: params.scope,
      conversationId: params.conversationId,
      activeVisitId,
      conversationTurnId: inboundTurnId,
      conversationTurnIndex: turnIndex,
      conversationContextEpoch: params.contextEpoch,
      text: message,
      attachment: null,
      recentTurns: agentContext.recentTurns,
      pendingAction: jsonObjectOrNull(params.conversation.pending_action_json),
      activeIntake: agentContext.activeIntake,
    })
  } catch (_) {
    console.error('app-hatchery-agent: agent turn threw')
    // Sink (a): still one structured line even for this defensive,
    // unexpected-throw branch — `runAgentTurn` is designed to return a
    // status rather than throw, so reaching here is itself worth observing.
    logAgentTurnTelemetry({
      door: 'app',
      conversationId: params.conversationId,
      status: 'runtime_threw',
      telemetry: null,
      toolCallCount: 0,
    })
    return failure(
      502,
      'agent_unavailable',
      'The assistant is temporarily unavailable. Please try again shortly.',
    )
  }

  // Sink (a): a structured log line for EVERY turn, success or failure — a
  // `provider_unavailable` / `provider_timeout` turn is exactly the one most
  // worth observing, and it never writes an outbound row (see sink (b)
  // below), so this is the only durable trace it leaves. Deliberately never
  // includes message text, reply text, tokens, or provider keys.
  logAgentTurnTelemetry({
    door: 'app',
    conversationId: params.conversationId,
    status: result.status,
    telemetry: result.telemetry,
    toolCallCount: result.toolCallCount,
  })

  if (result.status !== 'replied') {
    console.error(`app-hatchery-agent: agent turn status ${result.status}`)
    return failure(
      502,
      'agent_unavailable',
      'The assistant is temporarily unavailable. Please try again shortly.',
    )
  }

  const replyTimestamp = params.now()
  const outboundSlot = await allocateAgentTurnSlot(contextClient, {
    conversationId: params.conversationId,
    contextEpoch: params.contextEpoch,
    direction: 'outbound',
    turnIndexOverride: turnIndex,
  })
  if (!outboundSlot) {
    return failure(500, 'server_error', 'Could not store the reply.')
  }
  const outboundTurnId = params.newId()
  const language = detectAgentLanguage(result.reply)
  const outboundInsert = await params.deps.adminClient
    .from('agent_conversation_turns')
    .insert({
      id: outboundTurnId,
      conversation_id: params.conversationId,
      direction: 'outbound',
      turn_index: outboundSlot.turnIndex,
      conversation_seq: outboundSlot.conversationSeq,
      context_epoch: params.contextEpoch,
      source_channel: 'app_text',
      completion_status: 'finalized',
      reply_to_turn_id: inboundTurnId,
      telegram_update_id: null,
      telegram_message_id: null,
      text: result.reply,
      language,
      provider: result.provider ?? null,
      model: result.model ?? null,
      provider_response_id: result.providerResponseId,
      provider_telemetry_json: result.telemetry ?? null,
      attachment_json: null,
      delivery_status: 'delivered',
      created_at: replyTimestamp,
    })
  if (outboundInsert.error) {
    return failure(500, 'server_error', 'Could not store the reply.')
  }

  const replyPayload: Record<string, unknown> = {
    conversationId: params.conversationId,
    conversationKey: params.conversationKey,
    userTurnId: inboundTurnId,
    replyTurnId: outboundTurnId,
    reply: result.reply,
    language,
    createdAt: replyTimestamp,
  }
  if (audioProvided) {
    replyPayload.transcript = message
    const audio = await synthesizeReplyAudio(
      params.deps,
      result.reply,
      language,
    )
    if (audio) replyPayload.audioBase64 = audio
  }
  return success(replyPayload)
}

/**
 * Sink (a) of the two required observability sinks — see the doc comments at
 * the call sites. One `console.log(JSON.stringify(...))` per turn. Never
 * logs message text, reply text, tokens, or provider keys, matching this
 * file's existing logging discipline.
 */
function logAgentTurnTelemetry(params: {
  door: 'app'
  conversationId: string
  status: string
  /** The TURN-level aggregate (see `AgentTurnTelemetry`), not a single call's. */
  telemetry: AgentTurnTelemetry | null | undefined
  toolCallCount: number
}): void {
  console.log(JSON.stringify({
    event: 'agent_turn_telemetry',
    door: params.door,
    conversationId: params.conversationId,
    status: params.status,
    provider: params.telemetry?.provider ?? null,
    primaryModel: params.telemetry?.primaryModel ?? null,
    fallbackModel: params.telemetry?.fallbackModel ?? null,
    modelsUsed: params.telemetry?.modelsUsed ?? [],
    totalCallCount: params.telemetry?.totalCallCount ?? 0,
    fallbackCallCount: params.telemetry?.fallbackCallCount ?? 0,
    fallbackOccurred: params.telemetry?.fallbackOccurred ?? false,
    fallbackReasons: params.telemetry?.fallbackReasons ?? [],
    providerResponseIds: params.telemetry?.providerResponseIds ?? [],
    latencyMs: params.telemetry?.latencyMs ?? null,
    toolCallCount: params.toolCallCount,
  }))
}

async function synthesizeReplyAudio(
  deps: AppAgentDeps,
  text: string,
  language: 'en' | 'ar' | 'mixed',
): Promise<string | null> {
  if (!deps.synthesizeSpeech) return null
  try {
    return await deps.synthesizeSpeech(text, language)
  } catch (_) {
    console.error('app-hatchery-agent: speech synthesis failed')
    return null
  }
}

async function loadOrCreateConversation(params: {
  adminClient: AppAgentAdminClient
  staffLinkId: string
  /**
   * 'app' (the legacy single conversation) or 'app:<uuid>' (any additional
   * conversation). With the app staff-link id it keys one row per
   * conversation under unique(staff_link_id, chat id). Ownership is
   * inherent: this lookup is always scoped to the caller's own staffLinkId.
   */
  chatKey: string
  /** The caller's profile id. */
  ownerProfileId: string
  newId: () => string
  timestamp: string
}): Promise<Record<string, unknown> | null> {
  const load = () =>
    params.adminClient
      .from('agent_conversations')
      .select('*')
      .eq('staff_link_id', params.staffLinkId)
      .eq('telegram_chat_id', params.chatKey)
      .maybeSingle()

  const existing = await load()
  if (existing.error) return null
  if (existing.data) return existing.data

  const conversation = {
    id: params.newId(),
    staff_link_id: params.staffLinkId,
    telegram_chat_id: params.chatKey,
    owner_profile_id: params.ownerProfileId,
    state_version: 1,
    context_epoch: 1,
    pending_action_json: null,
    active_visit_id: null,
    selected_customer_id: null,
    selected_flock_id: null,
    selected_audit_id: null,
    title: null,
    context_updated_at: params.timestamp,
    created_at: params.timestamp,
    updated_at: params.timestamp,
  }
  const created = await params.adminClient
    .from('agent_conversations')
    .insert(conversation)
  if (!created.error) return conversation

  const retry = await load()
  if (retry.error || !retry.data) return null
  return retry.data
}

/**
 * Sets `agent_conversations.title` from the caller's first message, once.
 * Non-fatal: a write failure never blocks the reply, and nothing is logged
 * (the title itself is message text and must not appear in logs).
 */
async function maybeSetConversationTitle(
  deps: AppAgentDeps,
  conversation: Record<string, unknown>,
  conversationId: string,
  message: string,
): Promise<void> {
  if (nullableString(conversation.title) !== null) return
  const title = deriveConversationTitle(message)
  if (!title) return
  try {
    await deps.adminClient
      .from('agent_conversations')
      .update({ title })
      .eq('id', conversationId)
  } catch (_) {
    // Non-fatal.
  }
}

/**
 * Bumps `agent_conversations.updated_at` after a durable turn write, so the
 * `conversations` list orders by actual activity rather than by creation
 * time. Non-fatal: a write failure never blocks the reply.
 */
async function touchConversationUpdatedAt(
  deps: AppAgentDeps,
  conversationId: string,
  timestamp: string,
): Promise<void> {
  try {
    await deps.adminClient
      .from('agent_conversations')
      .update({ updated_at: timestamp })
      .eq('id', conversationId)
  } catch (_) {
    // Non-fatal.
  }
}

interface StoredReply {
  id: string
  text: string
  language: 'en' | 'ar' | 'mixed'
  createdAt: string
}

async function loadStoredReply(
  deps: AppAgentDeps,
  conversationId: string,
  inboundTurnId: string,
): Promise<{ reply: StoredReply | null; error: boolean }> {
  const result = await deps.adminClient
    .from('agent_conversation_turns')
    .select('id, text, language, created_at')
    .eq('conversation_id', conversationId)
    .eq('reply_to_turn_id', inboundTurnId)
    .eq('direction', 'outbound')
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(1)
  if (result.error) return { reply: null, error: true }
  const row = result.data?.[0]
  if (!row) return { reply: null, error: false }
  const id = nullableString(row.id)
  const text = nullableString(row.text)
  if (!id || !text) return { reply: null, error: false }
  return {
    reply: {
      id,
      text,
      language: readLanguage(row.language),
      createdAt: nullableString(row.created_at) ?? '',
    },
    error: false,
  }
}

async function loadStoredReplyByKey(
  deps: AppAgentDeps,
  conversationId: string,
  idempotencyKey: string,
): Promise<Record<string, unknown> | null> {
  const inbound = await deps.adminClient
    .from('agent_conversation_turns')
    .select('id')
    .eq('conversation_id', conversationId)
    .eq('telegram_update_id', idempotencyKey)
    .maybeSingle()
  const inboundId = inbound.data ? nullableString(inbound.data.id) : null
  if (!inboundId) return null
  const stored = await loadStoredReply(deps, conversationId, inboundId)
  if (!stored.reply) return null
  return {
    userTurnId: inboundId,
    replyTurnId: stored.reply.id,
    reply: stored.reply.text,
    language: stored.reply.language,
    createdAt: stored.reply.createdAt,
  }
}

/**
 * Rate-limits the CALLER, not one conversation: the budget is counted across
 * every app conversation this staff link owns. Scoping to a single
 * conversation_id let a caller reset their budget for free by simply opening
 * a fresh `app:<uuid>` conversation — the send rate is a property of the
 * caller, not of whichever conversation happens to be open.
 */
async function isRateLimited(
  deps: AppAgentDeps,
  staffLinkId: string,
  timestamp: string,
): Promise<boolean | null> {
  const conversationIds = await loadAppConversationIds(deps, staffLinkId)
  if (conversationIds === null) return null
  if (conversationIds.length === 0) return false
  const nowMs = Date.parse(timestamp)
  const cutoff = new Date(
    (Number.isFinite(nowMs) ? nowMs : Date.now()) - RATE_LIMIT_WINDOW_MS,
  ).toISOString()
  const result = await deps.adminClient
    .from('agent_conversation_turns')
    .select('id')
    .in('conversation_id', conversationIds)
    .eq('direction', 'inbound')
    .gte('created_at', cutoff)
    .limit(RATE_LIMIT_SENDS + 1)
  if (result.error) return null
  return (result.data ?? []).length >= RATE_LIMIT_SENDS
}

/** Every app conversation (legacy 'app' or 'app:<uuid>') this staff link owns. */
async function loadAppConversationIds(
  deps: AppAgentDeps,
  staffLinkId: string,
): Promise<string[] | null> {
  const result = await deps.adminClient
    .from('agent_conversations')
    .select('id, telegram_chat_id')
    .eq('staff_link_id', staffLinkId)
    .like('telegram_chat_id', 'app%')
    .limit(CONVERSATIONS_FETCH_CAP)
  if (result.error) return null
  return (result.data ?? [])
    .filter((row) => isAppConversationKey(nullableString(row.telegram_chat_id)))
    .map((row) => nullableString(row.id))
    .filter((id): id is string => id !== null)
}

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
  try {
    const parsed: unknown = JSON.parse(raw)
    if (
      parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)
    ) {
      return undefined
    }
    return parsed as Record<string, unknown>
  } catch (_) {
    return undefined
  }
}

const ATTACHMENT_FIELDS = [
  'attachment',
  'attachments',
  'audio',
  'voice',
  'photo',
  'photos',
  'image',
  'images',
  'file',
  'files',
  'fileData',
  'mimeType',
]

function hasAttachmentField(body: Record<string, unknown>): boolean {
  return ATTACHMENT_FIELDS.some((field) => {
    const value = body[field]
    return value !== undefined && value !== null
  })
}

function readAction(value: unknown): AppAction | null {
  if (value === undefined || value === null) return 'send'
  const text = nullableString(value)
  if (
    text === 'send' || text === 'history' || text === 'reset' ||
    text === 'conversations'
  ) {
    return text
  }
  return null
}

function readMessage(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  if (trimmed.length === 0 || trimmed.length > MAX_MESSAGE_CHARS) return null
  return trimmed
}

function readAudioBase64(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  if (trimmed.length === 0 || trimmed.length > MAX_AUDIO_BASE64_CHARS) {
    return null
  }
  return trimmed
}

function readHistoryLimit(value: unknown): number | null {
  if (value === undefined || value === null) return DEFAULT_HISTORY_LIMIT
  if (typeof value !== 'number' || !Number.isInteger(value)) return null
  if (value < 1 || value > MAX_HISTORY_LIMIT) return null
  return value
}

function readConversationsLimit(value: unknown): number | null {
  if (value === undefined || value === null) {
    return DEFAULT_CONVERSATIONS_LIMIT
  }
  if (typeof value !== 'number' || !Number.isInteger(value)) return null
  if (value < 1 || value > MAX_CONVERSATIONS_LIMIT) return null
  return value
}

/**
 * Missing/null resolves to the legacy 'app' conversation, preserving today's
 * behavior exactly. Any other value must be either 'app' or 'app:<uuid v4>'.
 */
function readConversationKey(value: unknown): string | null {
  if (value === undefined || value === null) return APP_CHANNEL_CHAT_ID
  if (typeof value !== 'string') return null
  return isAppConversationKey(value) ? value : null
}

function isAppConversationKey(value: string | null): boolean {
  if (value === null) return false
  return value === APP_CHANNEL_CHAT_ID ||
    APP_CONVERSATION_KEY_PATTERN.test(value)
}

function truncatePreview(text: string): string {
  return text.length > CONVERSATION_PREVIEW_CHARS
    ? text.slice(0, CONVERSATION_PREVIEW_CHARS)
    : text
}

function compareText(a: string, b: string): number {
  return a === b ? 0 : a < b ? -1 : 1
}

function readLanguage(value: unknown): 'en' | 'ar' | 'mixed' {
  const text = nullableString(value)
  return text === 'ar' || text === 'mixed' ? text : 'en'
}

function directionToRole(value: unknown): 'user' | 'assistant' | null {
  if (value === 'inbound') return 'user'
  if (value === 'outbound') return 'assistant'
  return null
}

function detectAgentLanguage(value: string): 'en' | 'ar' | 'mixed' {
  const arabic = /[\u0600-\u06ff]/u.test(value)
  const latin = /[A-Za-z]/u.test(value)
  return arabic && latin ? 'mixed' : arabic ? 'ar' : 'en'
}

function jsonObjectOrNull(value: unknown): Record<string, unknown> | null {
  if (value === null || value === undefined) return null
  if (typeof value === 'string') {
    try {
      return jsonObjectOrNull(JSON.parse(value))
    } catch (_) {
      return null
    }
  }
  return typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function nullableString(value: unknown): string | null {
  if (value === null || value === undefined) return null
  const text = value.toString().trim()
  return text.length > 0 ? text : null
}

function positiveInteger(value: unknown): number | null {
  const parsed = integerValue(value)
  return parsed !== null && parsed >= 1 ? parsed : null
}

function integerValue(value: unknown): number | null {
  if (typeof value === 'number' && Number.isInteger(value)) return value
  if (typeof value === 'string') {
    const parsed = Number.parseInt(value, 10)
    return Number.isFinite(parsed) ? parsed : null
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

export function serveAppAgent(request: Request): Response | Promise<Response> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const aiConfig = readAiConfig()
  if (!supabaseUrl || !serviceRoleKey || !aiConfig) {
    return json(500, {
      error: 'The app hatchery agent is not configured.',
      code: 'server_error',
    })
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const adminClient = supabase as unknown as AppAgentAdminClient
  const handlers = createUnifiedAgentToolHandlers(
    supabase as unknown as TelegramAdminClient,
  )
  const provider = createResponsesAgentProvider(aiConfig)
  const conversationContext = createSupabaseAgentConversationContextStore(
    supabase as unknown as AgentConversationContextClient,
  )

  const voiceConfig = readVoiceConfig()

  return handleAppAgentRequest(request, {
    adminClient,
    authenticate: async (accessToken) => {
      const result = await supabase.auth.getUser(accessToken)
      if (result.error || !result.data?.user) return null
      return { id: result.data.user.id }
    },
    transcribeAudio: voiceConfig
      ? (audioBase64) => transcribeAudio(audioBase64, voiceConfig)
      : undefined,
    synthesizeSpeech: voiceConfig
      ? (text, language) => synthesizeSpeech(text, voiceConfig, language)
      : undefined,
    runAgentTurn: (input) =>
      runAgentTurn(input, {
        provider,
        executeTool: (call) =>
          executeAgentTool(call, {
            scope: input.scope,
            conversationId: input.conversationId,
            activeVisitId: input.activeVisitId,
            conversationTurnId: input.conversationTurnId,
            conversationTurnIndex: input.conversationTurnIndex,
            conversationContextEpoch: input.conversationContextEpoch,
            handlers,
            conversationContext,
            evidence: {
              record: (event) =>
                recordAgentToolEvidence(
                  adminClient,
                  input.conversationTurnId,
                  event,
                ),
            },
          }),
      }),
  })
}

async function recordAgentToolEvidence(
  client: AppAgentAdminClient,
  conversationTurnId: string,
  event: AgentToolEvidence,
): Promise<void> {
  const result = await client.from('agent_tool_events').insert({
    id: crypto.randomUUID(),
    conversation_turn_id: conversationTurnId,
    tool_call_id: event.callId,
    tool_name: event.toolName,
    arguments_json: { ...event.arguments, _scope: event.scope },
    result_json: event.result,
    status: event.status,
    duration_ms: event.durationMs,
    state_version_before: event.stateVersionBefore,
    state_version_after: event.stateVersionAfter,
    tool_sequence: event.toolSequence ?? null,
    created_at: new Date().toISOString(),
  })
  if (result.error) throw new Error('Could not store agent tool evidence')
}

interface AppAiConfig {
  provider: 'openai' | 'openrouter'
  apiKey: string
  model?: string
  /**
   * The text agent's one-step OpenRouter fallback model (see
   * `agent_provider.ts`'s `classifyProviderFailure`). Only ever set when
   * `provider === 'openrouter'`.
   */
  fallbackModel?: string
  /**
   * The vision-capable model a call is routed to when its input carries an
   * image or video (see `requestIsVisual` in `agent_provider.ts`). Only
   * ever set when `provider === 'openrouter'`, from
   * `resolveOpenRouterTextModels(...).vision`.
   *
   * NOTE for this door specifically: `serveAppAgent` hardcodes
   * `attachment: null` for every turn (see `handleAppAgentRequest` /
   * `runAgentTurn` call site), so the app door never actually sends visual
   * `input`. This field is wired through for parity with the Telegram door
   * and so a future app-side attachment upload has somewhere to route to,
   * but today it is configured and unused.
   */
  visionModel?: string
  /**
   * Optional fallback for a failed vision call. Only set when
   * `OPENROUTER_VISION_FALLBACK_MODEL` is explicitly configured — see the
   * CRITICAL doc comment on `visionFallbackModel` in
   * `ResponsesAgentProviderConfig` (`agent_provider.ts`) for why this
   * defaults to unset rather than reusing `fallbackModel`.
   */
  visionFallbackModel?: string
}

export function readAiConfig(): AppAiConfig | null {
  const configuredProvider = nullableString(Deno.env.get('AI_PROVIDER'))
    ?.toLowerCase()
  if (
    configuredProvider &&
    configuredProvider !== 'openai' &&
    configuredProvider !== 'openrouter'
  ) {
    return null
  }

  const openRouterApiKey = nullableString(Deno.env.get('OPENROUTER_API_KEY'))
  const openAiApiKey = nullableString(Deno.env.get('OPENAI_API_KEY'))
  const provider = (configuredProvider ??
    (openRouterApiKey ? 'openrouter' : 'openai')) as 'openai' | 'openrouter'
  const apiKey = provider === 'openrouter' ? openRouterApiKey : openAiApiKey
  if (!apiKey) return null

  if (provider === 'openai') {
    return { provider, apiKey, model: resolvePipTextModel(Deno.env.get) }
  }
  const { primary, fallback, vision } = resolveOpenRouterTextModels(
    Deno.env.get,
  )
  const visionFallbackModel = nullableString(
    Deno.env.get('OPENROUTER_VISION_FALLBACK_MODEL'),
  ) ?? undefined
  return {
    provider,
    apiKey,
    model: primary,
    fallbackModel: fallback,
    visionModel: vision,
    visionFallbackModel,
  }
}

if (import.meta.main) {
  Deno.serve(serveAppAgent)
}
