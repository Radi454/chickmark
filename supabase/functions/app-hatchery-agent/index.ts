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
  APP_CHANNEL_CHAT_ID,
  type AppAgentProfile,
  AppAgentScopeError,
  type AppScopeClient,
  ensureAppStaffLink,
  loadAppProfile,
  resolveAppAgentScope,
} from './app_agent_scope.ts'

const MAX_MESSAGE_CHARS = 4000
const DEFAULT_HISTORY_LIMIT = 50
const MAX_HISTORY_LIMIT = 100
const HISTORY_FETCH_LIMIT = 40
const MODEL_HISTORY_TURNS = 20
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

type AppAction = 'send' | 'history' | 'reset'

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

  const conversation = await loadOrCreateConversation({
    adminClient: deps.adminClient,
    staffLinkId,
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

  if (action === 'history') {
    return await handleHistory({
      deps,
      conversationId,
      contextEpoch,
      limit: readHistoryLimit(body.limit),
    })
  }
  if (action === 'reset') {
    return await handleReset({
      deps,
      conversation,
      conversationId,
      contextEpoch,
      timestamp: now(),
    })
  }
  return await handleSend({
    deps,
    scope,
    conversation,
    conversationId,
    contextEpoch,
    body,
    newId,
    now,
  })
}

async function handleHistory(params: {
  deps: AppAgentDeps
  conversationId: string
  contextEpoch: number
  limit: number | null
}): Promise<Response> {
  if (params.limit === null) {
    return failure(400, 'invalid_request', 'limit must be between 1 and 100.')
  }
  const result = await params.deps.adminClient
    .from('agent_conversation_turns')
    .select('id, direction, text, language, created_at')
    .eq('conversation_id', params.conversationId)
    .eq('context_epoch', params.contextEpoch)
    .order('created_at', { ascending: false })
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
        createdAt: nullableString(turn.created_at) ?? '',
      }]
    })
  return success({ conversationId: params.conversationId, messages })
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

async function handleSend(params: {
  deps: AppAgentDeps
  scope: AgentScope
  conversation: Record<string, unknown>
  conversationId: string
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
  const existingInbound = await params.deps.adminClient
    .from('agent_conversation_turns')
    .select('id, turn_index, context_epoch, text')
    .eq('telegram_update_id', idempotencyKey)
    .maybeSingle()
  if (existingInbound.error) {
    return failure(500, 'server_error', 'Could not check the message.')
  }
  const replayInboundId = existingInbound.data
    ? nullableString(existingInbound.data.id)
    : null
  if (replayInboundId) {
    const storedReply = await loadStoredReply(params.deps, replayInboundId)
    if (storedReply.error) {
      return failure(500, 'server_error', 'Could not load the stored reply.')
    }
    if (storedReply.reply) {
      const payload: Record<string, unknown> = {
        conversationId: params.conversationId,
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
      return failure(502, 'agent_unavailable', 'Voice is not available right now.')
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
      params.conversationId,
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

  const historyResult = await params.deps.adminClient
    .from('agent_conversation_turns')
    .select('id, direction, text, turn_index, created_at')
    .eq('conversation_id', params.conversationId)
    .eq('context_epoch', params.contextEpoch)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(HISTORY_FETCH_LIMIT)
  if (historyResult.error) {
    return failure(500, 'server_error', 'Could not load the conversation.')
  }
  const storedTurns = historyResult.data ?? []

  let inboundTurnId = replayInboundId
  let turnIndex = replayInboundId && existingInbound.data
    ? integerValue(existingInbound.data.turn_index) ?? 1
    : 0
  if (!inboundTurnId) {
    const latestInboundIndex = storedTurns.reduce((latest, turn) => {
      if (turn.direction !== 'inbound') return latest
      const value = integerValue(turn.turn_index)
      return value === null ? latest : Math.max(latest, value)
    }, 0)
    turnIndex = latestInboundIndex + 1
    inboundTurnId = params.newId()
    const inboundInsert = await params.deps.adminClient
      .from('agent_conversation_turns')
      .insert({
        id: inboundTurnId,
        conversation_id: params.conversationId,
        direction: 'inbound',
        turn_index: turnIndex,
        context_epoch: params.contextEpoch,
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
      const stored = await loadStoredReplyByKey(params.deps, idempotencyKey)
      if (stored) {
        return success({ conversationId: params.conversationId, ...stored })
      }
      return failure(500, 'server_error', 'Could not store the message.')
    }
  }

  const activeVisitId = nullableString(params.conversation.active_visit_id)
  let activeIntake: Record<string, unknown> | null = null
  if (activeVisitId) {
    const activeResult = await params.deps.adminClient
      .from('agent_intake_sessions')
      .select(
        'id, visit_id, state, schema_key, schema_version, row_version, ' +
          'working_values_json, pending_clarification_json, summary_version, ' +
          'summary_snapshot_json, user_confirmed_at, updated_at',
      )
      .eq('visit_id', activeVisitId)
      .order('updated_at', { ascending: false })
      .order('id', { ascending: false })
      .limit(1)
    if (!activeResult.error) activeIntake = activeResult.data?.[0] ?? null
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
      recentTurns: storedTurns
        .slice()
        .reverse()
        .flatMap((turn) => {
          const role = directionToRole(turn.direction)
          const turnText = nullableString(turn.text)
          return role && turnText ? [{ role, text: turnText }] : []
        })
        .slice(-MODEL_HISTORY_TURNS),
      pendingAction: jsonObjectOrNull(params.conversation.pending_action_json),
      activeIntake,
    })
  } catch (_) {
    console.error('app-hatchery-agent: agent turn threw')
    return failure(
      502,
      'agent_unavailable',
      'The assistant is temporarily unavailable. Please try again shortly.',
    )
  }

  if (result.status !== 'replied') {
    console.error(`app-hatchery-agent: agent turn status ${result.status}`)
    return failure(
      502,
      'agent_unavailable',
      'The assistant is temporarily unavailable. Please try again shortly.',
    )
  }

  const replyTimestamp = params.now()
  const outboundTurnId = params.newId()
  const language = detectAgentLanguage(result.reply)
  const outboundInsert = await params.deps.adminClient
    .from('agent_conversation_turns')
    .insert({
      id: outboundTurnId,
      conversation_id: params.conversationId,
      direction: 'outbound',
      turn_index: turnIndex,
      context_epoch: params.contextEpoch,
      reply_to_turn_id: inboundTurnId,
      telegram_update_id: null,
      telegram_message_id: null,
      text: result.reply,
      language,
      provider: result.provider ?? null,
      model: result.model ?? null,
      provider_response_id: result.providerResponseId,
      attachment_json: null,
      delivery_status: 'delivered',
      created_at: replyTimestamp,
    })
  if (outboundInsert.error) {
    return failure(500, 'server_error', 'Could not store the reply.')
  }

  const replyPayload: Record<string, unknown> = {
    conversationId: params.conversationId,
    userTurnId: inboundTurnId,
    replyTurnId: outboundTurnId,
    reply: result.reply,
    language,
    createdAt: replyTimestamp,
  }
  if (audioProvided) {
    replyPayload.transcript = message
    const audio = await synthesizeReplyAudio(params.deps, result.reply, language)
    if (audio) replyPayload.audioBase64 = audio
  }
  return success(replyPayload)
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
  newId: () => string
  timestamp: string
}): Promise<Record<string, unknown> | null> {
  // 'app' is the app channel's chat id; with the app staff-link id it keys the
  // single conversation per app user under unique(staff_link_id, chat id).
  const load = () =>
    params.adminClient
      .from('agent_conversations')
      .select('*')
      .eq('staff_link_id', params.staffLinkId)
      .eq('telegram_chat_id', APP_CHANNEL_CHAT_ID)
      .maybeSingle()

  const existing = await load()
  if (existing.error) return null
  if (existing.data) return existing.data

  const conversation = {
    id: params.newId(),
    staff_link_id: params.staffLinkId,
    telegram_chat_id: APP_CHANNEL_CHAT_ID,
    state_version: 1,
    context_epoch: 1,
    pending_action_json: null,
    active_visit_id: null,
    selected_customer_id: null,
    selected_flock_id: null,
    selected_audit_id: null,
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

interface StoredReply {
  id: string
  text: string
  language: 'en' | 'ar' | 'mixed'
  createdAt: string
}

async function loadStoredReply(
  deps: AppAgentDeps,
  inboundTurnId: string,
): Promise<{ reply: StoredReply | null; error: boolean }> {
  const result = await deps.adminClient
    .from('agent_conversation_turns')
    .select('id, text, language, created_at')
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
  idempotencyKey: string,
): Promise<Record<string, unknown> | null> {
  const inbound = await deps.adminClient
    .from('agent_conversation_turns')
    .select('id')
    .eq('telegram_update_id', idempotencyKey)
    .maybeSingle()
  const inboundId = inbound.data ? nullableString(inbound.data.id) : null
  if (!inboundId) return null
  const stored = await loadStoredReply(deps, inboundId)
  if (!stored.reply) return null
  return {
    userTurnId: inboundId,
    replyTurnId: stored.reply.id,
    reply: stored.reply.text,
    language: stored.reply.language,
    createdAt: stored.reply.createdAt,
  }
}

async function isRateLimited(
  deps: AppAgentDeps,
  conversationId: string,
  timestamp: string,
): Promise<boolean | null> {
  const nowMs = Date.parse(timestamp)
  const cutoff = new Date(
    (Number.isFinite(nowMs) ? nowMs : Date.now()) - RATE_LIMIT_WINDOW_MS,
  ).toISOString()
  const result = await deps.adminClient
    .from('agent_conversation_turns')
    .select('id')
    .eq('conversation_id', conversationId)
    .eq('direction', 'inbound')
    .gte('created_at', cutoff)
    .limit(RATE_LIMIT_SENDS + 1)
  if (result.error) return null
  return (result.data ?? []).length >= RATE_LIMIT_SENDS
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
  if (text === 'send' || text === 'history' || text === 'reset') return text
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
  if (trimmed.length === 0 || trimmed.length > MAX_AUDIO_BASE64_CHARS) return null
  return trimmed
}

function readHistoryLimit(value: unknown): number | null {
  if (value === undefined || value === null) return DEFAULT_HISTORY_LIMIT
  if (typeof value !== 'number' || !Number.isInteger(value)) return null
  if (value < 1 || value > MAX_HISTORY_LIMIT) return null
  return value
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
}

function readAiConfig(): AppAiConfig | null {
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

  const providerModel = provider === 'openrouter'
    ? nullableString(Deno.env.get('OPENROUTER_MODEL'))
    : nullableString(Deno.env.get('OPENAI_MODEL'))
  const model = providerModel ?? nullableString(Deno.env.get('AI_MODEL'))
  return model ? { provider, apiKey, model } : { provider, apiKey }
}

if (import.meta.main) {
  Deno.serve(serveAppAgent)
}
