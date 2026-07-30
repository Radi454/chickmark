import { createClient } from '@supabase/supabase-js'

import {
  type ExtractedHatcheryRow,
  type HatcheryExtraction,
  hatcheryExtractionSchema,
  type MissingQuestion,
} from './extraction_schema.ts'
import type { AnswerRoutingAdminClient } from './answer_routing.ts'
import {
  downloadTelegramFile,
  sendTelegramMessage,
  type TelegramFileDownload,
} from './telegram.ts'
import {
  buildBmkWarning,
  buildHistoricalWarning,
  type HatcheryRowWarning,
} from './warning_rules.ts'
import { createResponsesAgentProvider } from './agent_provider.ts'
import type { AgentScope } from './agent_protocol.ts'
import {
  type AgentTurnInput,
  type AgentTurnResult,
  runAgentTurn,
} from './agent_runtime.ts'
import {
  type AgentScopeClient,
  createSupabaseAgentScopeStore,
  resolveAgentScope,
} from './agent_scope.ts'
import {
  type AgentIntakeClient,
  createSupabaseAgentIntakeStore,
} from './agent_intake_store.ts'
import {
  createAgentIntakeToolHandlers,
  createSupabaseAgentIntakeContextResolver,
} from './agent_intake_tools.ts'
import {
  type AgentReadClient,
  createAgentReadToolHandlers,
  createSupabaseAgentReadStore,
} from './agent_read_tools.ts'
import {
  createAgentLegacyToolHandlers,
  createSupabaseAgentLegacyQuestionStore,
} from './agent_legacy_tools.ts'
import {
  type AgentAuditClient,
  createAgentAuditToolHandlers,
  createSupabaseAgentAuditStore,
} from './agent_audit_tools.ts'
import { type AgentToolEvidence, executeAgentTool } from './agent_tools.ts'
import {
  type AgentConversationContextClient,
  createSupabaseAgentConversationContextStore,
} from './agent_conversation_context.ts'

type SourceKind = 'text' | 'image' | 'pdf' | 'spreadsheet' | 'file'

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
  lt(column: string, value: unknown): AdminQuery
  lte(column: string, value: unknown): AdminQuery
  gte(column: string, value: unknown): AdminQuery
  not(column: string, operator: string, value: unknown): AdminQuery
  order(
    column: string,
    options: { ascending: boolean },
  ): AdminQuery
  limit(
    count: number,
  ): Promise<DatabaseResult<Record<string, unknown>[]>>
  maybeSingle(): Promise<DatabaseResult<Record<string, unknown>>>
  insert(values: unknown): Promise<DatabaseResult>
  update(values: unknown): UpdateFilter
}

export interface AdminClient extends AnswerRoutingAdminClient {
  from(table: string): AdminQuery
}

export interface ExtractionInput {
  sourceKind: SourceKind
  text: string | null
  fileName: string | null
  mimeType: string | null
  fileData: string | null
}

export interface ExtractionDeps {
  apiKey?: string
  openAiApiKey?: string
  provider?: AiProvider
  fetchImpl?: typeof fetch
  model?: string
}

type AiProvider = 'openai' | 'openrouter'

interface AiExtractionConfig {
  provider: AiProvider
  apiKey: string
  model?: string
}

type HandlerExtractedRow = Partial<ExtractedHatcheryRow>

export interface DraftLinkCatalog {
  customers: DraftLinkCustomer[]
  flocks: DraftLinkFlock[]
  hatcheries: DraftLinkHatchery[]
}

interface DraftLinkCustomer {
  id: string
  name: string
}

interface DraftLinkFlock {
  id: string
  customerId: string
  name: string
  entryDate: string | null
}

interface DraftLinkHatchery {
  id: string
  customerId: string
  name: string
}

interface DraftIdentityWarning {
  kind: 'identityResolution'
  severity: 'info' | 'review'
  messageEn: string
  messageAr: string
}

export interface DraftLinkResolution {
  customerId: string | null
  flockId: string | null
  flockEntryDate: string | null
  hatcheryId: string | null
  warnings: DraftIdentityWarning[]
  questions: MissingQuestion[]
}

interface EnrichedHatcheryRow {
  row: ExtractedHatcheryRow
  links: DraftLinkResolution
  proposedFlockAgeWeeks: number | null
  warnings: Array<DraftIdentityWarning | HatcheryRowWarning>
}

interface LoadTelegramFileParams {
  fileId: string
  mimeType: string
}

export interface HandlerDeps {
  expectedTelegramSecret: string
  adminClient: AdminClient
  resolveScope(staffLinkId: string): Promise<AgentScope>
  runAgentTurn(input: AgentTurnInput): Promise<AgentTurnResult>
  sendTelegramMessage(chatId: string, text: string): Promise<void>
  loadTelegramFile?(
    params: LoadTelegramFileParams,
  ): Promise<TelegramFileDownload>
  now?: () => Date
  newId?: () => string
}

interface TelegramUser {
  id?: number | string
  first_name?: string
  last_name?: string
  username?: string
}

interface TelegramMessage {
  message_id?: number | string
  date?: number
  chat?: { id?: number | string }
  from?: TelegramUser
  text?: string
  caption?: string
  photo?: Array<{ file_id?: string }>
  document?: {
    file_id?: string
    file_name?: string
    mime_type?: string
  }
}

interface TelegramUpdate {
  update_id?: number | string
  message?: TelegramMessage
}

interface TelegramSource {
  sourceKind: SourceKind
  text: string | null
  fileId: string | null
  fileName: string | null
  mimeType: string | null
}

const telegramSecretHeader = 'X-Telegram-Bot-Api-Secret-Token'
const defaultOpenAiModel = 'gpt-4.1-mini'
const freeOpenRouterModel = 'openrouter/free'
const defaultOpenRouterModel = freeOpenRouterModel
const extractionPrompt = [
  'Extract only hatchery values that are visible or explicitly provided.',
  'Never guess customer, flock, station, or breed names.',
  'Support English, Arabic, and mixed-language free text and tables.',
  'Return null for every unknown row value.',
  'Preserve every visible row and assign rowOrdinal values starting at 1.',
  'When a required or flock-age value is missing or unclear, add a concise',
  'follow-up question in both English and Arabic.',
].join(' ')
export async function handleTelegramUpdate(
  request: Request,
  deps: HandlerDeps,
): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { status: 200 })
  }
  if (request.method !== 'POST') {
    return json(405, { error: 'Method not allowed.' })
  }

  const providedSecret = request.headers.get(telegramSecretHeader)
  if (
    !deps.expectedTelegramSecret ||
    !providedSecret ||
    providedSecret !== deps.expectedTelegramSecret
  ) {
    return json(401, { error: 'Unauthorized webhook.' })
  }

  let update: TelegramUpdate
  try {
    update = await request.json() as TelegramUpdate
  } catch (_) {
    return json(400, { error: 'Invalid Telegram update.' })
  }

  const message = update.message
  const updateId = idString(update.update_id)
  const messageId = idString(message?.message_id)
  const chatId = idString(message?.chat?.id)
  const telegramUserId = idString(message?.from?.id)
  if (!message || !updateId || !messageId || !chatId || !telegramUserId) {
    return json(400, { error: 'Unsupported Telegram update.' })
  }

  const now = deps.now ?? (() => new Date())
  const newId = deps.newId ?? (() => crypto.randomUUID())
  const timestamp = now().toISOString()

  const staffResult = await deps.adminClient
    .from('telegram_staff_links')
    .select('id, status')
    .eq('telegram_user_id', telegramUserId)
    .maybeSingle()
  if (staffResult.error) {
    return json(500, { error: 'Could not verify Telegram staff access.' })
  }
  const staffLink = staffResult.data
  if (!staffLink) {
    const pendingResult = await registerPendingStaffLink({
      deps,
      telegramUserId,
      chatId,
      user: message.from,
      timestamp,
      newId,
    })
    if (pendingResult.error) {
      return json(500, { error: 'Could not register Telegram staff request.' })
    }
    await sendPendingApprovalMessage(deps, chatId)
    return json(200, { accepted: false, pendingApproval: true })
  }
  if (staffLink.status === 'pending') {
    const pendingId = idString(staffLink.id)
    if (!pendingId) {
      return json(500, { error: 'Telegram staff link is invalid.' })
    }
    const pendingUpdate = await updateStaffMetadata({
      deps,
      staffLinkId: pendingId,
      chatId,
      user: message.from,
      timestamp,
    })
    if (pendingUpdate.error) {
      return json(500, { error: 'Could not update Telegram staff request.' })
    }
    await sendPendingApprovalMessage(deps, chatId)
    return json(200, { accepted: false, pendingApproval: true })
  }
  if (staffLink.status !== 'allowed') {
    await sendRejection(deps, chatId)
    return json(200, { accepted: false })
  }
  const staffLinkId = idString(staffLink.id)
  if (!staffLinkId) {
    return json(500, { error: 'Telegram staff link is invalid.' })
  }
  let resolvedScope: AgentScope
  try {
    resolvedScope = await deps.resolveScope(staffLinkId)
  } catch (_) {
    await sendRejection(deps, chatId)
    return json(200, { accepted: false })
  }

  const settingsResult = await deps.adminClient
    .from('agent_settings')
    .select(
      'telegram_enabled, minimum_ready_confidence_pct, ' +
        'hatchability_warning_threshold_points',
    )
    .eq('id', 1)
    .maybeSingle()
  if (settingsResult.error) {
    return json(500, { error: 'Could not load agent settings.' })
  }
  if (settingsResult.data?.telegram_enabled === 0) {
    await deps.sendTelegramMessage(
      chatId,
      'The hatchery agent is paused. / وكيل المفرخ متوقف مؤقتًا.',
    )
    return json(200, { accepted: false })
  }

  const answerDuplicateResult = await deps.adminClient
    .from('telegram_agent_update_receipts')
    .select('update_id')
    .eq('update_id', updateId)
    .maybeSingle()
  if (answerDuplicateResult.error) {
    return json(500, { error: 'Could not check Telegram answer update.' })
  }
  if (answerDuplicateResult.data) {
    return json(200, { accepted: true, duplicate: true })
  }

  const duplicateResult = await deps.adminClient
    .from('agent_submissions')
    .select('id')
    .eq('telegram_update_id', updateId)
    .maybeSingle()
  if (duplicateResult.error) {
    return json(500, { error: 'Could not check Telegram update.' })
  }
  if (duplicateResult.data) {
    return json(200, { accepted: true, duplicate: true })
  }

  const unifiedDuplicate = await deps.adminClient
    .from('agent_conversation_turns')
    .select('id')
    .eq('telegram_update_id', updateId)
    .maybeSingle()
  if (unifiedDuplicate.error) {
    return json(500, { error: 'Could not check unified agent update.' })
  }
  if (unifiedDuplicate.data) {
    return json(200, { accepted: true, duplicate: true })
  }

  const staffUpdate = await updateStaffMetadata({
    deps,
    staffLinkId,
    chatId,
    user: message.from,
    timestamp,
  })
  if (staffUpdate.error) {
    return json(500, { error: 'Could not update Telegram staff details.' })
  }

  return handleUnifiedAgentTurn({
    deps,
    scope: resolvedScope,
    staffLinkId,
    chatId,
    updateId,
    messageId,
    message,
    timestamp,
    newId,
  })
}

async function handleUnifiedAgentTurn(params: {
  deps: HandlerDeps
  scope: AgentScope
  staffLinkId: string
  chatId: string
  updateId: string
  messageId: string
  message: TelegramMessage
  timestamp: string
  newId: () => string
}): Promise<Response> {
  const source = describeSource(params.message)
  const text = source?.text ??
    nullableString(params.message.text ?? params.message.caption) ?? ''
  const resetRequested = isNewConversationCommand(text)
  let fileData: string | null = null
  let mimeType = source?.mimeType ?? null
  if (source?.fileId) {
    if (!params.deps.loadTelegramFile || !source.mimeType) {
      await sendUnifiedInfrastructureRetry(params.deps, params.chatId)
      return json(200, {
        accepted: true,
        conversational: true,
        agent: true,
        status: 'provider_unavailable',
      })
    }
    try {
      const download = await params.deps.loadTelegramFile({
        fileId: source.fileId,
        mimeType: source.mimeType,
      })
      fileData = download.fileData
      mimeType = download.mimeType
    } catch (_) {
      await sendUnifiedInfrastructureRetry(params.deps, params.chatId)
      return json(200, {
        accepted: true,
        conversational: true,
        agent: true,
        status: 'provider_unavailable',
      })
    }
  }

  let conversationResult = await params.deps.adminClient
    .from('agent_conversations')
    .select('*')
    .eq('staff_link_id', params.staffLinkId)
    .eq('telegram_chat_id', params.chatId)
    .maybeSingle()
  if (conversationResult.error) {
    return json(500, { error: 'Could not load agent conversation.' })
  }
  let conversation = conversationResult.data
  if (!conversation) {
    conversation = {
      id: params.newId(),
      staff_link_id: params.staffLinkId,
      telegram_chat_id: params.chatId,
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
    const created = await params.deps.adminClient
      .from('agent_conversations')
      .insert(conversation)
    if (created.error) {
      conversationResult = await params.deps.adminClient
        .from('agent_conversations')
        .select('*')
        .eq('staff_link_id', params.staffLinkId)
        .eq('telegram_chat_id', params.chatId)
        .maybeSingle()
      if (conversationResult.error || !conversationResult.data) {
        return json(500, { error: 'Could not create agent conversation.' })
      }
      conversation = conversationResult.data
    }
  }
  const conversationId = idString(conversation.id)
  if (!conversationId) {
    return json(500, { error: 'Agent conversation is invalid.' })
  }
  const previousContextEpoch = positiveInteger(conversation.context_epoch) ?? 1
  const contextEpoch = resetRequested
    ? previousContextEpoch + 1
    : previousContextEpoch

  const historyResult = await params.deps.adminClient
    .from('agent_conversation_turns')
    .select(
      'id, direction, text, turn_index, created_at',
    )
    .eq('conversation_id', conversationId)
    .eq('context_epoch', contextEpoch)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(40)
  if (historyResult.error) {
    return json(500, { error: 'Could not load agent conversation history.' })
  }
  const storedTurns = historyResult.data ?? []
  const latestInboundIndex = storedTurns.reduce((latest, turn) => {
    if (turn.direction !== 'inbound') return latest
    const value = integerValue(turn.turn_index)
    return value === null ? latest : Math.max(latest, value)
  }, 0)
  const turnIndex = latestInboundIndex + 1
  const inboundTurnId = params.newId()
  const inboundInsert = await params.deps.adminClient
    .from('agent_conversation_turns')
    .insert({
      id: inboundTurnId,
      conversation_id: conversationId,
      direction: 'inbound',
      turn_index: turnIndex,
      context_epoch: contextEpoch,
      telegram_update_id: params.updateId,
      telegram_message_id: params.messageId,
      text,
      language: detectAgentLanguage(text),
      model: null,
      attachment_json: source?.fileId
        ? {
          kind: source.sourceKind,
          fileName: source.fileName,
          mimeType,
          remotePath: `telegram:file_id:${source.fileId}`,
        }
        : null,
      delivery_status: 'received',
      created_at: params.timestamp,
    })
  if (inboundInsert.error) {
    const duplicate = await params.deps.adminClient
      .from('agent_conversation_turns')
      .select('id')
      .eq('telegram_update_id', params.updateId)
      .maybeSingle()
    if (duplicate.data) return json(200, { accepted: true, duplicate: true })
    return json(500, { error: 'Could not store agent turn.' })
  }

  const receipt = await params.deps.adminClient
    .from('telegram_agent_update_receipts')
    .insert({
      update_id: params.updateId,
      message_id: params.messageId,
      staff_link_id: params.staffLinkId,
      telegram_chat_id: params.chatId,
      submission_ids_json: '[]',
      created_at: params.timestamp,
    })
  if (receipt.error) {
    const duplicate = await params.deps.adminClient
      .from('telegram_agent_update_receipts')
      .select('update_id')
      .eq('update_id', params.updateId)
      .maybeSingle()
    if (!duplicate.data) {
      return json(500, { error: 'Could not store agent update receipt.' })
    }
  }

  if (resetRequested) {
    const nextStateVersion =
      (positiveInteger(conversation.state_version) ?? 1) + 1
    const resetUpdate = await params.deps.adminClient
      .from('agent_conversations')
      .update({
        context_epoch: contextEpoch,
        state_version: nextStateVersion,
        pending_action_json: null,
        active_visit_id: null,
        selected_customer_id: null,
        selected_flock_id: null,
        selected_audit_id: null,
        context_updated_at: params.timestamp,
        updated_at: params.timestamp,
      })
      .eq('id', conversationId)
    if (resetUpdate.error) {
      return json(500, { error: 'Could not reset agent conversation.' })
    }
    const reply = 'بدأت محادثة جديدة وحُفظ السجل السابق للمراجعة.\n' +
      'A new conversation has started. Previous evidence was preserved.'
    const outboundTurnId = params.newId()
    const outboundInsert = await params.deps.adminClient
      .from('agent_conversation_turns')
      .insert({
        id: outboundTurnId,
        conversation_id: conversationId,
        direction: 'outbound',
        turn_index: turnIndex,
        context_epoch: contextEpoch,
        reply_to_turn_id: inboundTurnId,
        telegram_update_id: null,
        telegram_message_id: null,
        text: reply,
        language: 'mixed',
        provider: null,
        model: null,
        provider_response_id: null,
        attachment_json: null,
        delivery_status: 'pending',
        created_at: params.timestamp,
      })
    if (outboundInsert.error) {
      return json(500, { error: 'Could not store agent reset reply.' })
    }
    try {
      await params.deps.sendTelegramMessage(params.chatId, reply)
    } catch (_) {
      await params.deps.adminClient
        .from('agent_conversation_turns')
        .update({ delivery_status: 'failed' })
        .eq('id', outboundTurnId)
      return json(200, {
        accepted: true,
        conversational: true,
        agent: true,
        status: 'delivery_failed',
      })
    }
    await params.deps.adminClient
      .from('agent_conversation_turns')
      .update({ delivery_status: 'delivered' })
      .eq('id', outboundTurnId)
    return json(200, {
      accepted: true,
      conversational: true,
      agent: true,
      status: 'conversation_reset',
    })
  }

  const activeVisitId = nullableString(conversation.active_visit_id)
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

  const result = await params.deps.runAgentTurn({
    scope: params.scope,
    conversationId,
    activeVisitId,
    conversationTurnId: inboundTurnId,
    conversationTurnIndex: turnIndex,
    conversationContextEpoch: contextEpoch,
    text,
    attachment: source?.fileId
      ? {
        kind: source.sourceKind,
        fileName: source.fileName,
        mimeType,
        fileData,
      }
      : null,
    recentTurns: storedTurns
      .slice()
      .reverse()
      .flatMap((turn) => {
        const role = turn.direction === 'inbound'
          ? 'user' as const
          : turn.direction === 'outbound'
          ? 'assistant' as const
          : null
        const turnText = nullableString(turn.text)
        return role && turnText ? [{ role, text: turnText }] : []
      })
      .slice(-20),
    pendingAction: jsonObjectOrNull(conversation.pending_action_json),
    activeIntake,
  })

  if (result.status !== 'replied') {
    await sendUnifiedInfrastructureRetry(params.deps, params.chatId)
    return json(200, {
      accepted: true,
      conversational: true,
      agent: true,
      status: result.status,
    })
  }

  const outboundTurnId = params.newId()
  const outboundInsert = await params.deps.adminClient
    .from('agent_conversation_turns')
    .insert({
      id: outboundTurnId,
      conversation_id: conversationId,
      direction: 'outbound',
      turn_index: turnIndex,
      context_epoch: contextEpoch,
      reply_to_turn_id: inboundTurnId,
      telegram_update_id: null,
      telegram_message_id: null,
      text: result.reply,
      language: detectAgentLanguage(result.reply),
      provider: result.provider ?? null,
      model: result.model ?? null,
      provider_response_id: result.providerResponseId,
      attachment_json: null,
      delivery_status: 'pending',
      created_at: params.timestamp,
    })
  if (outboundInsert.error) {
    return json(500, { error: 'Could not store agent reply.' })
  }
  try {
    await params.deps.sendTelegramMessage(params.chatId, result.reply)
  } catch (_) {
    await params.deps.adminClient
      .from('agent_conversation_turns')
      .update({ delivery_status: 'failed' })
      .eq('id', outboundTurnId)
    return json(200, {
      accepted: true,
      conversational: true,
      agent: true,
      status: 'delivery_failed',
    })
  }
  const deliveryUpdate = await params.deps.adminClient
    .from('agent_conversation_turns')
    .update({ delivery_status: 'delivered' })
    .eq('id', outboundTurnId)
  if (deliveryUpdate.error) {
    return json(500, { error: 'Could not record agent reply delivery.' })
  }
  return json(200, {
    accepted: true,
    conversational: true,
    agent: true,
    status: result.status,
  })
}

async function sendUnifiedInfrastructureRetry(
  deps: HandlerDeps,
  chatId: string,
): Promise<void> {
  await deps.sendTelegramMessage(
    chatId,
    'تعذر الاتصال بالمساعد الآن. حاول مرة أخرى بعد قليل.\n' +
      'The assistant is temporarily unavailable. Please try again shortly.',
  )
}

async function recordAgentToolEvidence(
  client: AdminClient,
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

function detectAgentLanguage(value: string): 'en' | 'ar' | 'mixed' {
  const arabic = /[\u0600-\u06ff]/u.test(value)
  const latin = /[A-Za-z]/u.test(value)
  return arabic && latin ? 'mixed' : arabic ? 'ar' : 'en'
}

function isNewConversationCommand(value: string): boolean {
  return /^\/(?:new|reset)(?:@[A-Za-z0-9_]{5,32})?$/i.test(value.trim())
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
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

export async function extractHatcheryRows(
  input: ExtractionInput,
  deps: ExtractionDeps,
): Promise<HatcheryExtraction> {
  const structuredTextExtraction = extractLabeledTextRows(input)
  if (structuredTextExtraction !== null) return structuredTextExtraction

  const provider = deps.provider ?? 'openai'
  const providerName = provider === 'openrouter' ? 'OpenRouter' : 'OpenAI'
  const apiKey = deps.apiKey ?? deps.openAiApiKey
  if (!apiKey) {
    throw new Error(`${providerName} extraction is not configured`)
  }

  const content: Array<Record<string, unknown>> = []
  if (input.text) {
    content.push({ type: 'input_text', text: input.text })
  }
  if (input.fileData && input.sourceKind === 'image') {
    content.push({
      type: 'input_image',
      image_url: input.fileData,
      detail: 'high',
    })
  } else if (input.fileData) {
    content.push({
      type: 'input_file',
      file_data: input.fileData,
      filename: input.fileName ?? 'telegram-upload',
    })
  }
  if (content.length === 0) {
    throw new Error('The Telegram submission has no readable content')
  }

  const fetchImpl = deps.fetchImpl ?? fetch
  const endpoint = provider === 'openrouter'
    ? 'https://openrouter.ai/api/v1/responses'
    : 'https://api.openai.com/v1/responses'
  const requestedModel = deps.model ??
    (provider === 'openrouter' ? defaultOpenRouterModel : defaultOpenAiModel)
  const requestForModel = (model: string) =>
    fetchImpl(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        store: false,
        instructions: extractionPrompt,
        input: [{ role: 'user', content }],
        text: {
          format: {
            type: 'json_schema',
            name: 'hatchery_extraction',
            strict: true,
            schema: hatcheryExtractionSchema,
          },
        },
      }),
    })

  let response = await requestForModel(requestedModel)
  if (
    provider === 'openrouter' &&
    response.status === 402 &&
    requestedModel !== freeOpenRouterModel
  ) {
    response = await requestForModel(freeOpenRouterModel)
  }
  if (!response.ok) {
    throw new Error(`${providerName} extraction failed: ${response.status}`)
  }

  const payload = await response.json() as Record<string, unknown>
  const outputText = responseOutputText(payload)
  if (!outputText) {
    throw new Error(`${providerName} extraction returned no structured output`)
  }

  let extraction: unknown
  try {
    extraction = JSON.parse(outputText)
  } catch (_) {
    throw new Error(`${providerName} extraction returned invalid JSON`)
  }
  if (!isHatcheryExtraction(extraction)) {
    throw new Error(`${providerName} extraction returned an invalid structure`)
  }
  return extraction
}

function extractLabeledTextRows(
  input: ExtractionInput,
): HatcheryExtraction | null {
  if (input.sourceKind !== 'text' || input.fileData !== null || !input.text) {
    return null
  }

  const row: ExtractedHatcheryRow = {
    rowOrdinal: 1,
    customerName: null,
    flockName: null,
    stationName: null,
    breed: null,
    flockAgeWeeks: null,
    eggsPlaced: null,
    productionDate: null,
    placementDate: null,
    eggWeightG: null,
    fertilityPct: null,
    transferWeightG: null,
    setterNumber: null,
    hatcherNumber: null,
    hatchDate: null,
    healthyChicks: null,
    secondGradeChicks: null,
    condemnedChicks: null,
    totalProduction: null,
    confidencePct: 92,
  }
  let recognizedFields = 0

  for (const rawLine of input.text.split(/\r?\n/)) {
    const match = rawLine.match(/^\s*([^:=：]+?)\s*[:=：]\s*(.+?)\s*$/u)
    if (!match) continue
    const label = normalizeLabel(match[1])
    const value = nullableString(match[2])
    if (!value) continue

    switch (label) {
      case 'customer':
      case 'customername':
      case 'العميل':
      case 'اسمالعميل':
        row.customerName = value
        recognizedFields += 1
        break
      case 'flock':
      case 'flockname':
      case 'flockid':
      case 'القطيع':
      case 'اسمالقطيع':
        row.flockName = value
        recognizedFields += 1
        break
      case 'station':
      case 'hatchery':
      case 'المحطة':
      case 'المفرخ':
        row.stationName = value
        recognizedFields += 1
        break
      case 'breed':
      case 'السلالة':
        row.breed = value
        recognizedFields += 1
        break
      case 'flockage':
      case 'flockageweeks':
      case 'age':
      case 'ageweeks':
      case 'عمرالقطيع':
        row.flockAgeWeeks = parseLabeledInteger(value)
        recognizedFields += 1
        break
      case 'eggsplaced':
      case 'eggsset':
      case 'eggs':
      case 'عددالبيضالمودع':
      case 'البيضالمودع':
        row.eggsPlaced = parseLabeledInteger(value)
        recognizedFields += 1
        break
      case 'productiondate':
      case 'تاريخالانتاج':
      case 'تاريخالإنتاج':
        row.productionDate = value
        recognizedFields += 1
        break
      case 'placementdate':
      case 'setdate':
      case 'settingdate':
      case 'تاريخالايداع':
      case 'تاريخالإيداع':
        row.placementDate = value
        recognizedFields += 1
        break
      case 'eggweight':
      case 'eggweightg':
      case 'وزنالبيضة':
      case 'وزنالبيضةعندالايداع':
      case 'وزنالبيضةعندالإيداع':
        row.eggWeightG = parseLabeledNumber(value)
        recognizedFields += 1
        break
      case 'fertility':
      case 'fertilitypct':
      case 'fertilitypercentage':
      case 'اخصاب':
      case 'الإخصاب':
      case 'الاخصاب':
        row.fertilityPct = parseLabeledNumber(value)
        recognizedFields += 1
        break
      case 'transferweight':
      case 'transferweightg':
      case 'الوزنعندالنقل':
        row.transferWeightG = parseLabeledNumber(value)
        recognizedFields += 1
        break
      case 'setter':
      case 'setternumber':
      case 'setterno':
      case 'رقمالحضانة':
        row.setterNumber = value
        recognizedFields += 1
        break
      case 'hatcher':
      case 'hatchernumber':
      case 'hatcherno':
      case 'رقمالمفرخ':
        row.hatcherNumber = value
        recognizedFields += 1
        break
      case 'hatchdate':
      case 'تاريخالفقس':
        row.hatchDate = value
        recognizedFields += 1
        break
      case 'healthychicks':
      case 'goodchicks':
      case 'saleablechicks':
      case 'كتاكيتسليمة':
        row.healthyChicks = parseLabeledInteger(value)
        recognizedFields += 1
        break
      case 'secondgradechicks':
      case 'secondgrade':
      case 'rejectedchicks':
      case 'rejects':
      case 'الفرزة':
        row.secondGradeChicks = parseLabeledInteger(value)
        recognizedFields += 1
        break
      case 'condemnedchicks':
      case 'condemned':
      case 'dead':
      case 'deadchicks':
      case 'المعدم':
        row.condemnedChicks = parseLabeledInteger(value)
        recognizedFields += 1
        break
      case 'totalproduction':
      case 'total':
      case 'اجماليالانتاج':
      case 'إجماليالإنتاج':
      case 'اجمالىالانتاج':
        row.totalProduction = parseLabeledInteger(value)
        recognizedFields += 1
        break
    }
  }

  if (
    recognizedFields < 4 ||
    row.eggsPlaced === null ||
    row.totalProduction === null
  ) {
    return null
  }
  return { rows: [row], missingQuestions: [] }
}

function normalizeLabel(label: string): string {
  return normalizeDigits(label)
    .toLowerCase()
    .replace(/[٪%]/g, 'pct')
    .replace(/[\s_\-\/()،,.\u0640]/g, '')
}

function parseLabeledInteger(value: string): number | null {
  const parsed = parseLabeledNumber(value)
  return parsed !== null && Number.isInteger(parsed) ? parsed : null
}

function parseLabeledNumber(value: string): number | null {
  let normalized = normalizeDigits(value)
    .replace(/[^\d.,+\-\u066b\u066c]/g, '')
    .replace(/[\u066c\s]/g, '')
    .replace(/\u066b/g, '.')
  if (normalized.includes(',') && !normalized.includes('.')) {
    normalized = /^\d{1,3}(,\d{3})+$/.test(normalized)
      ? normalized.replaceAll(',', '')
      : normalized.replace(',', '.')
  } else {
    normalized = normalized.replaceAll(',', '')
  }
  if (!/^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$/.test(normalized)) return null
  const parsed = Number(normalized)
  return Number.isFinite(parsed) ? parsed : null
}

function normalizeDigits(value: string): string {
  return [...value].map((character) => {
    const code = character.codePointAt(0) ?? 0
    if (code >= 0x0660 && code <= 0x0669) return String(code - 0x0660)
    if (code >= 0x06f0 && code <= 0x06f9) return String(code - 0x06f0)
    return character
  }).join('')
}

export function createUnifiedAgentToolHandlers(
  adminClient: AdminClient,
) {
  const intakeClient = adminClient as unknown as AgentIntakeClient
  const intakeStore = createSupabaseAgentIntakeStore(intakeClient)
  const readStore = createSupabaseAgentReadStore(
    adminClient as unknown as AgentReadClient,
  )
  const auditStore = createSupabaseAgentAuditStore(
    adminClient as unknown as AgentAuditClient,
  )
  return {
    ...createAgentReadToolHandlers(readStore),
    ...createAgentAuditToolHandlers(auditStore),
    ...createAgentIntakeToolHandlers({
      store: intakeStore,
      contextResolver: createSupabaseAgentIntakeContextResolver(intakeClient),
    }),
    ...createAgentLegacyToolHandlers(
      createSupabaseAgentLegacyQuestionStore(adminClient),
    ),
  }
}

export function serveTelegramWebhook(
  request: Request,
): Response | Promise<Response> {
  const expectedTelegramSecret = Deno.env.get('TELEGRAM_WEBHOOK_SECRET')
  const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN')
  const aiConfig = readAiExtractionConfig()
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (
    !expectedTelegramSecret ||
    !botToken ||
    !aiConfig ||
    !supabaseUrl ||
    !serviceRoleKey
  ) {
    return json(500, { error: 'Telegram hatchery agent is not configured.' })
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  }) as unknown as AdminClient
  const agentScopeStore = createSupabaseAgentScopeStore(
    adminClient as unknown as AgentScopeClient,
  )
  const handlers = createUnifiedAgentToolHandlers(adminClient)
  const provider = createResponsesAgentProvider(aiConfig)
  const conversationContext = createSupabaseAgentConversationContextStore(
    adminClient as unknown as AgentConversationContextClient,
  )
  return handleTelegramUpdate(request, {
    expectedTelegramSecret,
    adminClient,
    resolveScope: (staffLinkId) =>
      resolveAgentScope(agentScopeStore, staffLinkId),
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
    sendTelegramMessage: (chatId, text) =>
      sendTelegramMessage({ botToken, chatId, text }),
    loadTelegramFile: ({ fileId, mimeType }) =>
      downloadTelegramFile({
        botToken,
        fileId,
        fallbackMimeType: mimeType,
      }),
  })
}

function readAiExtractionConfig(): AiExtractionConfig | null {
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
    (openRouterApiKey ? 'openrouter' : 'openai')) as AiProvider
  const apiKey = provider === 'openrouter' ? openRouterApiKey : openAiApiKey
  if (!apiKey) return null

  const providerModel = provider === 'openrouter'
    ? nullableString(Deno.env.get('OPENROUTER_MODEL'))
    : nullableString(Deno.env.get('OPENAI_MODEL'))
  const model = providerModel ?? nullableString(Deno.env.get('AI_MODEL'))
  return model ? { provider, apiKey, model } : { provider, apiKey }
}

if (import.meta.main) {
  Deno.serve(serveTelegramWebhook)
}

function describeSource(message: TelegramMessage): TelegramSource | null {
  const text = nullableString(message.text ?? message.caption)
  const photos = message.photo ?? []
  const photoFileId = photos.length > 0
    ? nullableString(photos[photos.length - 1]?.file_id)
    : null
  if (photoFileId) {
    return {
      sourceKind: 'image',
      text,
      fileId: photoFileId,
      fileName: 'telegram-photo.jpg',
      mimeType: 'image/jpeg',
    }
  }

  const documentFileId = nullableString(message.document?.file_id)
  if (documentFileId) {
    const fileName = nullableString(message.document?.file_name)
    const mimeType = nullableString(message.document?.mime_type) ||
      'application/octet-stream'
    return {
      sourceKind: sourceKindForDocument(mimeType, fileName),
      text,
      fileId: documentFileId,
      fileName,
      mimeType,
    }
  }

  return text
    ? {
      sourceKind: 'text',
      text,
      fileId: null,
      fileName: null,
      mimeType: 'text/plain',
    }
    : null
}

function sourceKindForDocument(
  mimeType: string,
  fileName: string | null,
): SourceKind {
  if (mimeType.startsWith('image/')) return 'image'
  if (mimeType === 'application/pdf') return 'pdf'
  const normalizedName = fileName?.toLowerCase() ?? ''
  if (
    mimeType.includes('spreadsheet') ||
    mimeType.includes('excel') ||
    mimeType === 'text/csv' ||
    ['.csv', '.xls', '.xlsx', '.ods'].some((suffix) =>
      normalizedName.endsWith(suffix)
    )
  ) {
    return 'spreadsheet'
  }
  return 'file'
}

function normalizeRow(
  row: HandlerExtractedRow,
  index: number,
): ExtractedHatcheryRow {
  return {
    rowOrdinal: integerValue(row.rowOrdinal) ?? index + 1,
    customerName: nullableString(row.customerName),
    flockName: nullableString(row.flockName),
    stationName: nullableString(row.stationName),
    breed: nullableString(row.breed),
    flockAgeWeeks: integerValue(row.flockAgeWeeks),
    eggsPlaced: integerValue(row.eggsPlaced),
    productionDate: normalizeDate(row.productionDate),
    placementDate: normalizeDate(row.placementDate),
    eggWeightG: numberValue(row.eggWeightG),
    fertilityPct: numberValue(row.fertilityPct),
    transferWeightG: numberValue(row.transferWeightG),
    setterNumber: nullableString(row.setterNumber),
    hatcherNumber: nullableString(row.hatcherNumber),
    hatchDate: normalizeDate(row.hatchDate),
    healthyChicks: integerValue(row.healthyChicks),
    secondGradeChicks: integerValue(row.secondGradeChicks),
    condemnedChicks: integerValue(row.condemnedChicks),
    totalProduction: integerValue(row.totalProduction),
    confidencePct: numberValue(row.confidencePct) ?? 0,
  }
}

export function resolveDraftLinks(
  row: ExtractedHatcheryRow,
  catalog: DraftLinkCatalog,
): DraftLinkResolution {
  const warnings: DraftIdentityWarning[] = []
  const questions: MissingQuestion[] = []
  const customerName = matchText(row.customerName)
  const flockName = matchText(row.flockName)
  const customerMatches = customerName
    ? catalog.customers.filter((customer) =>
      matchText(customer.name) === customerName
    )
    : []
  let customer: DraftLinkCustomer | null = customerMatches.length === 1
    ? customerMatches[0]
    : null
  let flock: DraftLinkFlock | null = null

  if (customerMatches.length > 1 && flockName) {
    const customerIds = new Set(customerMatches.map((match) => match.id))
    const combinedMatches = catalog.flocks.filter((candidate) =>
      customerIds.has(candidate.customerId) &&
      matchText(candidate.name) === flockName
    )
    if (combinedMatches.length === 1) {
      flock = combinedMatches[0]
      customer = customerMatches.find(
        (candidate) => candidate.id === flock?.customerId,
      ) ?? null
    }
  } else if (!row.customerName && flockName) {
    const globalFlockMatches = catalog.flocks.filter((candidate) =>
      matchText(candidate.name) === flockName
    )
    if (globalFlockMatches.length === 1) {
      flock = globalFlockMatches[0]
      customer = catalog.customers.find(
        (candidate) => candidate.id === flock?.customerId,
      ) ?? null
    }
  }

  if (!customer) {
    const detail = row.customerName == null
      ? 'No customer name was provided.'
      : customerMatches.length === 0
      ? `No customer exactly matches "${row.customerName}".`
      : `More than one customer matches "${row.customerName}".`
    warnings.push(identityWarning(
      detail,
      row.customerName == null
        ? 'لم يتم توفير اسم العميل.'
        : customerMatches.length === 0
        ? `لا يوجد عميل يطابق "${row.customerName}" تمامًا.`
        : `يوجد أكثر من عميل يطابق "${row.customerName}".`,
    ))
    questions.push(identityQuestion(
      row.rowOrdinal,
      'customerName',
      'Which existing customer should this row use?',
      'أي عميل حالي يجب استخدامه لهذا الصف؟',
      customerMatches.map((candidate) => candidate.name),
    ))
  }

  if (customer && !flock) {
    const flockMatches = flockName
      ? catalog.flocks.filter((candidate) =>
        candidate.customerId === customer?.id &&
        matchText(candidate.name) === flockName
      )
      : []
    if (flockMatches.length === 1) {
      flock = flockMatches[0]
    } else {
      const detail = row.flockName == null
        ? 'No flock name was provided.'
        : flockMatches.length === 0
        ? `No flock named "${row.flockName}" belongs to ${customer.name}.`
        : `More than one flock named "${row.flockName}" belongs to ${customer.name}.`
      warnings.push(identityWarning(
        detail,
        row.flockName == null
          ? 'لم يتم توفير اسم القطيع.'
          : flockMatches.length === 0
          ? `لا يوجد قطيع باسم "${row.flockName}" تابع للعميل ${customer.name}.`
          : `يوجد أكثر من قطيع باسم "${row.flockName}" تابع للعميل ${customer.name}.`,
      ))
      questions.push(identityQuestion(
        row.rowOrdinal,
        'flockName',
        'Which existing flock should this row use?',
        'أي قطيع حالي يجب استخدامه لهذا الصف؟',
        catalog.flocks
          .filter((candidate) => candidate.customerId === customer?.id)
          .map((candidate) => candidate.name),
      ))
    }
  }

  let hatcheryId: string | null = null
  if (customer) {
    const hatcheries = catalog.hatcheries.filter(
      (candidate) => candidate.customerId === customer?.id,
    )
    if (hatcheries.length === 1) {
      hatcheryId = hatcheries[0].id
    } else if (hatcheries.length > 1) {
      warnings.push(identityWarning(
        `More than one hatchery belongs to ${customer.name}; an admin must select one.`,
        `يوجد أكثر من مفرخ تابع للعميل ${customer.name}؛ يجب على المسؤول اختيار أحدها.`,
      ))
      questions.push(identityQuestion(
        row.rowOrdinal,
        'hatcheryName',
        'Which existing hatchery should this row use?',
        'أي مفرخ حالي يجب استخدامه لهذا الصف؟',
        hatcheries.map((candidate) => candidate.name),
      ))
    }
  }

  return {
    customerId: customer?.id ?? null,
    flockId: flock?.id ?? null,
    flockEntryDate: flock?.entryDate ?? null,
    hatcheryId,
    warnings,
    questions,
  }
}

export async function loadDraftLinkCatalog(
  client: AdminClient,
): Promise<DraftLinkCatalog> {
  const [customerRows, flockRows, hatcheryRows] = await Promise.all([
    selectCatalogRows(client, 'customers', 'id, name'),
    selectCatalogRows(
      client,
      'flocks',
      'id, customer_id, flock_id, entry_date',
    ),
    selectCatalogRows(client, 'hatcheries', 'id, customer_id, name'),
  ])
  return {
    customers: customerRows.flatMap((row) => {
      const id = nullableString(row.id)
      const name = nullableString(row.name)
      return id && name ? [{ id, name }] : []
    }),
    flocks: flockRows.flatMap((row) => {
      const id = nullableString(row.id)
      const customerId = nullableString(row.customer_id)
      const name = nullableString(row.flock_id)
      const entryDate = nullableString(row.entry_date)
      return id && customerId && name
        ? [{ id, customerId, name, entryDate }]
        : []
    }),
    hatcheries: hatcheryRows.flatMap((row) => {
      const id = nullableString(row.id)
      const customerId = nullableString(row.customer_id)
      const name = nullableString(row.name)
      return id && customerId && name ? [{ id, customerId, name }] : []
    }),
  }
}

async function selectCatalogRows(
  client: AdminClient,
  table: string,
  columns: string,
): Promise<Record<string, unknown>[]> {
  const pending = client.from(table).select(columns)
  const result = await (pending as unknown as Promise<
    DatabaseResult<Record<string, unknown>[]>
  >)
  if (result.error) {
    throw new Error(`Could not load ${table} for draft identity resolution`)
  }
  return result.data ?? []
}

async function loadCatalogForResolution(
  load: () => Promise<DraftLinkCatalog>,
): Promise<{ catalog: DraftLinkCatalog; available: boolean }> {
  try {
    return { catalog: await load(), available: true }
  } catch (error) {
    console.warn('Draft identity lookup unavailable', safeErrorMessage(error))
    return {
      catalog: { customers: [], flocks: [], hatcheries: [] },
      available: false,
    }
  }
}

function unavailableDraftLinkResolution(
  row: ExtractedHatcheryRow,
): DraftLinkResolution {
  return {
    customerId: null,
    flockId: null,
    flockEntryDate: null,
    hatcheryId: null,
    warnings: [identityWarning(
      'The customer, flock, and hatchery lookup is unavailable. Verify the existing hierarchy links during admin review.',
      'البحث عن العميل والقطيع والمفرخ غير متاح. تحقق من روابط الهيكل الحالية أثناء مراجعة المسؤول.',
    )],
    questions: [identityQuestion(
      row.rowOrdinal,
      'identityResolution',
      'Which existing customer, flock, and hatchery should this row use?',
      'أي عميل وقطيع ومفرخ حالي يجب استخدامه لهذا الصف؟',
    )],
  }
}

function deduplicateQuestions(
  questions: MissingQuestion[],
): MissingQuestion[] {
  const seen = new Set<string>()
  return questions.filter((question) => {
    const key = `${question.rowOrdinal}:${question.fieldKey}`
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
}

function matchText(value: string | null): string | null {
  if (value == null) return null
  const normalized = value.normalize('NFKC').trim().replace(/\s+/gu, ' ')
    .toLowerCase()
  return normalized.length === 0 ? null : normalized
}

function identityWarning(
  messageEn: string,
  messageAr: string,
): DraftIdentityWarning {
  return {
    kind: 'identityResolution',
    severity: 'review',
    messageEn,
    messageAr,
  }
}

function identityQuestion(
  rowOrdinal: number,
  fieldKey: string,
  questionTextEn: string,
  questionTextAr: string,
  options: string[] = [],
): MissingQuestion {
  return {
    rowOrdinal,
    fieldKey,
    questionTextEn,
    questionTextAr: appendArabicOptions(questionTextAr, options),
  }
}

function appendArabicOptions(
  questionTextAr: string,
  options: string[],
): string {
  const uniqueOptions = uniqueNonEmptyStrings(options).slice(0, 8)
  if (uniqueOptions.length === 0) return questionTextAr
  return [
    questionTextAr,
    'الاختيارات:',
    ...uniqueOptions.map((option, index) => `${index + 1}) ${option}`),
    'إذا لم يكن الاختيار موجودًا، اكتب الاسم كاملًا.',
  ].join('\n')
}

function uniqueNonEmptyStrings(values: string[]): string[] {
  const seen = new Set<string>()
  const unique: string[] = []
  for (const value of values) {
    const normalized = nullableString(value)
    if (!normalized) continue
    const key = matchText(normalized)
    if (!key || seen.has(key)) continue
    seen.add(key)
    unique.push(normalized)
  }
  return unique
}

function draftRowRecord(params: {
  id: string
  batchId: string
  enriched: EnrichedHatcheryRow
  needsReview: boolean
  timestamp: string
}): Record<string, unknown> {
  const row = params.enriched.row
  const hatchabilityPct = calculateHatchabilityPct(row)
  const invalidCounts = hatchabilityPct === null
  return {
    id: params.id,
    batch_id: params.batchId,
    row_ordinal: row.rowOrdinal,
    status: params.needsReview || invalidCounts ? 'needs_review' : 'pending',
    customer_id: params.enriched.links.customerId,
    customer_name: row.customerName,
    flock_id: params.enriched.links.flockId,
    flock_name: row.flockName,
    hatchery_id: params.enriched.links.hatcheryId,
    station_name: row.stationName,
    breed: row.breed,
    eggs_placed: row.eggsPlaced,
    production_date: row.productionDate,
    placement_date: row.placementDate,
    egg_weight_g: row.eggWeightG,
    fertility_pct: row.fertilityPct,
    transfer_weight_g: row.transferWeightG,
    setter_number: row.setterNumber,
    hatcher_number: row.hatcherNumber,
    hatch_date: row.hatchDate,
    healthy_chicks: row.healthyChicks,
    second_grade_chicks: row.secondGradeChicks,
    condemned_chicks: row.condemnedChicks,
    total_production: row.totalProduction,
    hatchability_pct: hatchabilityPct,
    confidence_pct: row.confidencePct,
    extraction_json: JSON.stringify(row),
    warnings_json: JSON.stringify(params.enriched.warnings),
    proposed_flock_age_weeks: params.enriched.proposedFlockAgeWeeks,
    approved_record_id: null,
    reviewed_by: null,
    reviewed_at: null,
    created_at: params.timestamp,
    updated_at: params.timestamp,
  }
}

function calculateHatchabilityPct(row: ExtractedHatcheryRow): number | null {
  return calculateHatchabilityFromCounts(
    row.totalProduction,
    row.eggsPlaced,
  )
}

async function enrichDraftRow(params: {
  client: AdminClient
  row: ExtractedHatcheryRow
  links: DraftLinkResolution
  thresholdPoints: number
}): Promise<EnrichedHatcheryRow> {
  const proposedFlockAgeWeeks = positiveInteger(
    params.row.flockAgeWeeks,
  ) ?? deriveFlockAgeWeeks(params.links.flockEntryDate, params.row.hatchDate)
  const currentPct = calculateHatchabilityPct(params.row)
  const previousPct = currentPct === null
    ? null
    : await loadPreviousHatchabilityPct({
      client: params.client,
      customerId: params.links.customerId,
      flockId: params.links.flockId,
      stationName: params.row.stationName,
      breed: params.row.breed,
      hatchDate: params.row.hatchDate,
    })
  const warnings: Array<DraftIdentityWarning | HatcheryRowWarning> = [
    ...params.links.warnings,
  ]

  if (currentPct !== null) {
    const historicalWarning = buildHistoricalWarning({
      currentPct,
      previousPct,
      thresholdPoints: params.thresholdPoints,
    })
    if (historicalWarning !== null) warnings.push(historicalWarning)

    const isRising = previousPct !== null && currentPct > previousPct
    const nearestBmk = isRising &&
        proposedFlockAgeWeeks !== null &&
        params.row.breed !== null
      ? await loadNearestBreedBmk({
        client: params.client,
        breed: params.row.breed,
        flockAgeWeeks: proposedFlockAgeWeeks,
      })
      : null
    const bmkWarning = buildBmkWarning({
      currentPct,
      previousPct,
      bmkPct: nearestBmk?.hatchabilityPct ?? null,
      flockAgeWeeks: nearestBmk?.ageWeek ?? proposedFlockAgeWeeks,
    })
    if (bmkWarning !== null) warnings.push(bmkWarning)
  }

  return {
    row: params.row,
    links: params.links,
    proposedFlockAgeWeeks,
    warnings,
  }
}

async function loadPreviousHatchabilityPct(params: {
  client: AdminClient
  customerId: string | null
  flockId: string | null
  stationName: string | null
  breed: string | null
  hatchDate: string | null
}): Promise<number | null> {
  const hatchDateCutoff = normalizedDateKey(params.hatchDate)
  if (
    params.customerId === null ||
    params.flockId === null ||
    params.stationName === null ||
    params.breed === null ||
    hatchDateCutoff === null
  ) {
    return null
  }
  const result = await params.client
    .from('hatchery_daily_records')
    .select(
      'eggs_placed, total_production, hatchability_pct, hatch_date',
    )
    .eq('customer_id', params.customerId)
    .eq('flock_id', params.flockId)
    .eq('station_name', params.stationName)
    .eq('breed', params.breed)
    .lt('hatch_date', hatchDateCutoff)
    .order('hatch_date', { ascending: false })
    .limit(1)
  if (result.error) {
    throw new Error('Could not load hatchery comparison history')
  }
  const row = result.data?.[0]
  if (row === undefined) return null
  return calculateHatchabilityFromCounts(
    row.total_production,
    row.eggs_placed,
  ) ?? numberValue(row.hatchability_pct)
}

async function loadNearestBreedBmk(params: {
  client: AdminClient
  breed: string
  flockAgeWeeks: number
}): Promise<{ ageWeek: number; hatchabilityPct: number } | null> {
  const [lowerResult, upperResult] = await Promise.all([
    params.client
      .from('bmk_breeds')
      .select('id, age_week, hatchability_pct')
      .eq('breed', params.breed)
      .not('hatchability_pct', 'is', null)
      .lte('age_week', params.flockAgeWeeks)
      .order('age_week', { ascending: false })
      .order('id', { ascending: true })
      .limit(1),
    params.client
      .from('bmk_breeds')
      .select('id, age_week, hatchability_pct')
      .eq('breed', params.breed)
      .not('hatchability_pct', 'is', null)
      .gte('age_week', params.flockAgeWeeks)
      .order('age_week', { ascending: true })
      .order('id', { ascending: true })
      .limit(1),
  ])
  if (lowerResult.error || upperResult.error) {
    throw new Error('Could not load hatchery BMK context')
  }

  const candidates = [
    ...(lowerResult.data ?? []),
    ...(upperResult.data ?? []),
  ].flatMap((row) => {
    const ageWeek = positiveInteger(row.age_week)
    const hatchabilityPct = numberValue(row.hatchability_pct)
    return ageWeek === null || hatchabilityPct === null
      ? []
      : [{ ageWeek, hatchabilityPct }]
  })
  candidates.sort((left, right) => {
    const distance = Math.abs(left.ageWeek - params.flockAgeWeeks) -
      Math.abs(right.ageWeek - params.flockAgeWeeks)
    return distance === 0 ? left.ageWeek - right.ageWeek : distance
  })
  return candidates[0] ?? null
}

function mergeMissingAgeQuestions(
  extractedQuestions: MissingQuestion[],
  rows: EnrichedHatcheryRow[],
): MissingQuestion[] {
  const questions = [...extractedQuestions]
  for (const enriched of rows) {
    if (enriched.proposedFlockAgeWeeks !== null) continue
    const rowOrdinal = enriched.row.rowOrdinal
    const alreadyAsked = questions.some((question) =>
      question.fieldKey === 'flockAgeWeeks' &&
      question.rowOrdinal === rowOrdinal
    )
    if (alreadyAsked) continue
    questions.push({
      rowOrdinal,
      fieldKey: 'flockAgeWeeks',
      questionTextEn: `What is the flock age in weeks for row ${rowOrdinal}?`,
      questionTextAr: `ما عمر القطيع بالأسابيع للصف ${rowOrdinal}؟`,
    })
  }
  return questions
}

function deriveFlockAgeWeeks(
  entryDate: string | null,
  hatchDate: string | null,
): number | null {
  const entry = parseDate(entryDate)
  const hatch = parseDate(hatchDate)
  if (entry === null || hatch === null) return null
  const ageDays = Math.floor((hatch - entry) / millisecondsPerDay)
  if (ageDays <= 0) return null
  return positiveInteger(Math.floor(ageDays / 7))
}

function calculateHatchabilityFromCounts(
  totalProduction: unknown,
  eggsPlaced: unknown,
): number | null {
  const production = numberValue(totalProduction)
  const eggs = numberValue(eggsPlaced)
  if (production === null || production < 0 || eggs === null || eggs <= 0) {
    return null
  }
  return production / eggs * 100
}

function normalizeDate(value: unknown): string | null {
  const text = nullableString(value)
  const timestamp = parseDate(text)
  return timestamp === null ? text : new Date(timestamp).toISOString()
}

function normalizedDateKey(value: string | null): string | null {
  const timestamp = parseDate(value)
  return timestamp === null
    ? null
    : new Date(timestamp).toISOString().slice(0, 10)
}

function parseDate(value: string | null): number | null {
  if (value === null) return null
  const text = value.trim()
  const isoDate = /^(\d{4})-(\d{1,2})-(\d{1,2})(?:$|T)/.exec(text)
  if (isoDate !== null) {
    return validUtcDate(
      Number(isoDate[1]),
      Number(isoDate[2]),
      Number(isoDate[3]),
    )
  }

  const parsed = new Date(text)
  if (Number.isNaN(parsed.getTime())) return null
  const hasExplicitTimezone = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(text)
  return validUtcDate(
    hasExplicitTimezone ? parsed.getUTCFullYear() : parsed.getFullYear(),
    (hasExplicitTimezone ? parsed.getUTCMonth() : parsed.getMonth()) + 1,
    hasExplicitTimezone ? parsed.getUTCDate() : parsed.getDate(),
  )
}

function validUtcDate(
  year: number,
  month: number,
  day: number,
): number | null {
  const timestamp = Date.UTC(year, month - 1, day)
  const date = new Date(timestamp)
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null
  }
  return timestamp
}

async function insertOrThrow(
  client: AdminClient,
  table: string,
  values: unknown,
): Promise<void> {
  const result = await client.from(table).insert(values)
  if (result.error) {
    throw new Error(`Could not write ${table}`)
  }
}

async function updateSubmission(
  client: AdminClient,
  submissionId: string,
  values: Record<string, unknown>,
): Promise<void> {
  const result = await client
    .from('agent_submissions')
    .update(values)
    .eq('id', submissionId)
  if (result.error) {
    throw new Error('Could not update agent submission')
  }
}

async function registerPendingStaffLink({
  deps,
  telegramUserId,
  chatId,
  user,
  timestamp,
  newId,
}: {
  deps: HandlerDeps
  telegramUserId: string
  chatId: string
  user: TelegramUser | undefined
  timestamp: string
  newId: () => string
}): Promise<DatabaseResult> {
  return await deps.adminClient
    .from('telegram_staff_links')
    .insert({
      id: newId(),
      telegram_user_id: telegramUserId,
      telegram_chat_id: chatId,
      display_name: displayName(user),
      username: nullableString(user?.username),
      status: 'pending',
      invited_by: null,
      created_at: timestamp,
      updated_at: timestamp,
    })
}

function updateStaffMetadata({
  deps,
  staffLinkId,
  chatId,
  user,
  timestamp,
}: {
  deps: HandlerDeps
  staffLinkId: string
  chatId: string
  user: TelegramUser | undefined
  timestamp: string
}): Promise<DatabaseResult> {
  return deps.adminClient
    .from('telegram_staff_links')
    .update({
      telegram_chat_id: chatId,
      display_name: displayName(user),
      username: nullableString(user?.username),
      updated_at: timestamp,
    })
    .eq('id', staffLinkId)
}

async function sendPendingApprovalMessage(
  deps: HandlerDeps,
  chatId: string,
): Promise<void> {
  await deps.sendTelegramMessage(
    chatId,
    'تم إرسال طلب الدخول للمسؤول ✅\nبعد الموافقة، أعد إرسال بيانات المفرخ.',
  )
}

async function sendRejection(
  deps: HandlerDeps,
  chatId: string,
): Promise<void> {
  await deps.sendTelegramMessage(
    chatId,
    'غير مصرح لك بإرسال بيانات المفرخ.',
  )
}

function displayName(user: TelegramUser | undefined): string | null {
  return nullableString(
    [user?.first_name, user?.last_name].filter(Boolean).join(
      ' ',
    ),
  )
}

function idString(value: unknown): string | null {
  if (typeof value === 'string' && value.trim()) return value.trim()
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value.toString()
  }
  return null
}

function nullableString(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const normalized = value.trim()
  return normalized ? normalized : null
}

function numberValue(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function integerValue(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) ? value : null
}

function positiveInteger(value: unknown): number | null {
  const integer = integerValue(value)
  return integer !== null && integer > 0 ? integer : null
}

function positiveNumber(value: unknown): number | null {
  const number = numberValue(value)
  return number !== null && number > 0 ? number : null
}

function responseOutputText(payload: Record<string, unknown>): string | null {
  if (typeof payload.output_text === 'string') return payload.output_text
  if (!Array.isArray(payload.output)) return null
  for (const item of payload.output) {
    if (!item || typeof item !== 'object') continue
    const outputItem = item as Record<string, unknown>
    if (outputItem.type !== 'message') continue
    const content = outputItem.content
    if (!Array.isArray(content)) continue
    for (const part of content) {
      if (!part || typeof part !== 'object') continue
      const contentPart = part as Record<string, unknown>
      if (contentPart.type !== 'output_text') continue
      const text = contentPart.text
      if (typeof text === 'string') return text
    }
  }
  return null
}

function isHatcheryExtraction(value: unknown): value is HatcheryExtraction {
  if (!value || typeof value !== 'object') return false
  const candidate = value as Record<string, unknown>
  return Array.isArray(candidate.rows) &&
    Array.isArray(candidate.missingQuestions)
}

function safeErrorMessage(error: unknown): string {
  if (!(error instanceof Error)) return 'Unknown processing failure'
  return error.message.slice(0, 500)
}

const millisecondsPerDay = 24 * 60 * 60 * 1000

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
