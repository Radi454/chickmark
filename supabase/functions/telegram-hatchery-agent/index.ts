import { createClient } from '@supabase/supabase-js'

import {
  type ExtractedHatcheryRow,
  type HatcheryExtraction,
  hatcheryExtractionSchema,
  type MissingQuestion,
} from './extraction_schema.ts'
import {
  downloadTelegramFile,
  sendTelegramMessage,
  type TelegramFileDownload,
} from './telegram.ts'

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
  maybeSingle(): Promise<DatabaseResult<Record<string, unknown>>>
  insert(values: unknown): Promise<DatabaseResult>
  update(values: unknown): UpdateFilter
}

export interface AdminClient {
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
  openAiApiKey: string
  fetchImpl?: typeof fetch
  model?: string
}

type HandlerExtractedRow = Partial<ExtractedHatcheryRow>

interface HandlerExtraction {
  rows: HandlerExtractedRow[]
  missingQuestions: MissingQuestion[]
}

interface LoadTelegramFileParams {
  fileId: string
  mimeType: string
}

export interface HandlerDeps {
  expectedTelegramSecret: string
  adminClient: AdminClient
  extract(input: ExtractionInput): Promise<HandlerExtraction>
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
const defaultReadyConfidencePct = 85
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
  if (!staffLink || staffLink.status !== 'allowed') {
    await sendRejection(deps, chatId)
    return json(200, { accepted: false })
  }

  const staffUpdate = await deps.adminClient
    .from('telegram_staff_links')
    .update({
      telegram_chat_id: chatId,
      display_name: displayName(message.from),
      username: nullableString(message.from?.username),
      updated_at: timestamp,
    })
    .eq('id', staffLink.id)
  if (staffUpdate.error) {
    return json(500, { error: 'Could not update Telegram staff details.' })
  }

  const settingsResult = await deps.adminClient
    .from('agent_settings')
    .select('telegram_enabled, minimum_ready_confidence_pct')
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

  const source = describeSource(message)
  if (!source) {
    await deps.sendTelegramMessage(
      chatId,
      'Send hatchery text, a photo, PDF, spreadsheet, or file. / أرسل نص بيانات المفرخ أو صورة أو ملفًا.',
    )
    return json(200, { accepted: false })
  }

  const submissionId = newId()
  const submittedAt = telegramDate(message.date)?.toISOString() ?? timestamp
  const submissionInsert = await deps.adminClient
    .from('agent_submissions')
    .insert({
      id: submissionId,
      telegram_update_id: updateId,
      telegram_message_id: messageId,
      telegram_chat_id: chatId,
      telegram_user_id: telegramUserId,
      staff_link_id: staffLink.id,
      source_kind: source.sourceKind,
      source_text: source.text,
      source_file_name: source.fileName,
      source_mime_type: source.mimeType,
      source_remote_path: source.fileId
        ? `telegram:file_id:${source.fileId}`
        : null,
      status: 'received',
      error_message: null,
      submitted_at: submittedAt,
      processed_at: null,
      created_at: timestamp,
      updated_at: timestamp,
    })
  if (submissionInsert.error) {
    return json(500, { error: 'Could not store Telegram submission.' })
  }

  try {
    await updateSubmission(deps.adminClient, submissionId, {
      status: 'processing',
      updated_at: timestamp,
    })
    await deps.sendTelegramMessage(
      chatId,
      'Submission received and processing. / تم استلام البيانات وجارٍ معالجتها.',
    )

    let fileData: string | null = null
    let mimeType = source.mimeType
    if (source.fileId) {
      if (!deps.loadTelegramFile || !source.mimeType) {
        throw new Error('Telegram file loading is not configured')
      }
      const downloaded = await deps.loadTelegramFile({
        fileId: source.fileId,
        mimeType: source.mimeType,
      })
      fileData = downloaded.fileData
      mimeType = downloaded.mimeType
    }

    const extraction = await deps.extract({
      sourceKind: source.sourceKind,
      text: source.text,
      fileName: source.fileName,
      mimeType,
      fileData,
    })
    const rows = extraction.rows.map(normalizeRow)
    const questions = extraction.missingQuestions
    const minimumConfidence = numberValue(
      settingsResult.data?.minimum_ready_confidence_pct,
    ) ?? defaultReadyConfidencePct
    const hasLowConfidence = rows.length === 0 ||
      rows.some((row) => row.confidencePct < minimumConfidence)
    const hasInvalidHatchability = rows.some((row) =>
      calculateHatchabilityPct(row) === null
    )
    const finalStatus = questions.length > 0
      ? 'waiting_for_staff_answer'
      : hasLowConfidence || hasInvalidHatchability
      ? 'needs_admin_review'
      : 'draft_ready'
    const batchId = newId()

    await insertOrThrow(
      deps.adminClient,
      'hatchery_draft_batches',
      {
        id: batchId,
        submission_id: submissionId,
        status: finalStatus,
        source_summary: source.text,
        created_at: timestamp,
        updated_at: timestamp,
      },
    )

    if (rows.length > 0) {
      await insertOrThrow(
        deps.adminClient,
        'hatchery_draft_rows',
        rows.map((row) =>
          draftRowRecord({
            id: newId(),
            batchId,
            row,
            needsReview: finalStatus !== 'draft_ready',
            timestamp,
          })
        ),
      )
    }

    if (questions.length > 0) {
      await insertOrThrow(
        deps.adminClient,
        'agent_questions',
        questions.map((question) => ({
          id: newId(),
          submission_id: submissionId,
          row_ordinal: question.rowOrdinal,
          field_key: question.fieldKey,
          question_text_en: question.questionTextEn,
          question_text_ar: question.questionTextAr,
          status: 'open',
          answer_text: null,
          answered_at: null,
          created_at: timestamp,
          updated_at: timestamp,
        })),
      )
    }

    await updateSubmission(deps.adminClient, submissionId, {
      status: finalStatus,
      processed_at: timestamp,
      updated_at: timestamp,
    })

    if (questions.length > 0) {
      await deps.sendTelegramMessage(chatId, formatQuestions(questions))
    } else if (finalStatus === 'draft_ready') {
      await deps.sendTelegramMessage(
        chatId,
        'Draft sent for admin review. / تم إرسال المسودة لمراجعة المسؤول.',
      )
    } else {
      await deps.sendTelegramMessage(
        chatId,
        'Draft needs admin review. / تحتاج المسودة إلى مراجعة المسؤول.',
      )
    }
    return json(200, {
      accepted: true,
      submissionId,
      status: finalStatus,
    })
  } catch (error) {
    const errorMessage = safeErrorMessage(error)
    await updateSubmission(deps.adminClient, submissionId, {
      status: 'failed',
      error_message: errorMessage,
      processed_at: timestamp,
      updated_at: timestamp,
    })
    try {
      await deps.sendTelegramMessage(
        chatId,
        'The submission could not be processed. An admin can review it. / تعذرت معالجة البيانات ويمكن للمسؤول مراجعتها.',
      )
    } catch (_) {
      // The durable failed status is the source of truth if Telegram is down.
    }
    return json(200, { accepted: true, submissionId, status: 'failed' })
  }
}

export async function extractHatcheryRows(
  input: ExtractionInput,
  deps: ExtractionDeps,
): Promise<HatcheryExtraction> {
  if (!deps.openAiApiKey) {
    throw new Error('OpenAI extraction is not configured')
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

  const response = await (deps.fetchImpl ?? fetch)(
    'https://api.openai.com/v1/responses',
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${deps.openAiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: deps.model ?? 'gpt-4.1-mini',
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
    },
  )
  if (!response.ok) {
    throw new Error(`OpenAI extraction failed: ${response.status}`)
  }

  const payload = await response.json() as Record<string, unknown>
  const outputText = responseOutputText(payload)
  if (!outputText) {
    throw new Error('OpenAI extraction returned no structured output')
  }

  let extraction: unknown
  try {
    extraction = JSON.parse(outputText)
  } catch (_) {
    throw new Error('OpenAI extraction returned invalid JSON')
  }
  if (!isHatcheryExtraction(extraction)) {
    throw new Error('OpenAI extraction returned an invalid structure')
  }
  return extraction
}

export function serveTelegramWebhook(
  request: Request,
): Response | Promise<Response> {
  const expectedTelegramSecret = Deno.env.get('TELEGRAM_WEBHOOK_SECRET')
  const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN')
  const openAiApiKey = Deno.env.get('OPENAI_API_KEY')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (
    !expectedTelegramSecret ||
    !botToken ||
    !openAiApiKey ||
    !supabaseUrl ||
    !serviceRoleKey
  ) {
    return json(500, { error: 'Telegram hatchery agent is not configured.' })
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  }) as unknown as AdminClient
  return handleTelegramUpdate(request, {
    expectedTelegramSecret,
    adminClient,
    extract: (input) => extractHatcheryRows(input, { openAiApiKey }),
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
    eggsPlaced: integerValue(row.eggsPlaced),
    productionDate: nullableString(row.productionDate),
    placementDate: nullableString(row.placementDate),
    eggWeightG: numberValue(row.eggWeightG),
    fertilityPct: numberValue(row.fertilityPct),
    transferWeightG: numberValue(row.transferWeightG),
    setterNumber: nullableString(row.setterNumber),
    hatcherNumber: nullableString(row.hatcherNumber),
    hatchDate: nullableString(row.hatchDate),
    healthyChicks: integerValue(row.healthyChicks),
    secondGradeChicks: integerValue(row.secondGradeChicks),
    condemnedChicks: integerValue(row.condemnedChicks),
    totalProduction: integerValue(row.totalProduction),
    confidencePct: numberValue(row.confidencePct) ?? 0,
  }
}

function draftRowRecord(params: {
  id: string
  batchId: string
  row: ExtractedHatcheryRow
  needsReview: boolean
  timestamp: string
}): Record<string, unknown> {
  const row = params.row
  const hatchabilityPct = calculateHatchabilityPct(row)
  const invalidCounts = hatchabilityPct === null
  return {
    id: params.id,
    batch_id: params.batchId,
    row_ordinal: row.rowOrdinal,
    status: params.needsReview || invalidCounts ? 'needs_review' : 'pending',
    customer_id: null,
    customer_name: row.customerName,
    flock_id: null,
    flock_name: row.flockName,
    hatchery_id: null,
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
    warnings_json: JSON.stringify([]),
    proposed_flock_age_weeks: null,
    approved_record_id: null,
    reviewed_by: null,
    reviewed_at: null,
    created_at: params.timestamp,
    updated_at: params.timestamp,
  }
}

function calculateHatchabilityPct(row: ExtractedHatcheryRow): number | null {
  if (
    row.eggsPlaced === null ||
    row.eggsPlaced <= 0 ||
    row.totalProduction === null ||
    row.totalProduction < 0
  ) {
    return null
  }
  return row.totalProduction / row.eggsPlaced * 100
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

async function sendRejection(
  deps: HandlerDeps,
  chatId: string,
): Promise<void> {
  await deps.sendTelegramMessage(
    chatId,
    'You are not authorized to submit hatchery data. / غير مصرح لك بإرسال بيانات المفرخ.',
  )
}

function formatQuestions(questions: MissingQuestion[]): string {
  const lines = [
    'Please provide the missing details:',
    'يرجى تزويدنا بالبيانات الناقصة:',
  ]
  for (const [index, question] of questions.entries()) {
    lines.push(
      `${index + 1}. ${question.questionTextEn}`,
      `${index + 1}. ${question.questionTextAr}`,
    )
  }
  return lines.join('\n')
}

function displayName(user: TelegramUser | undefined): string | null {
  return nullableString(
    [user?.first_name, user?.last_name].filter(Boolean).join(
      ' ',
    ),
  )
}

function telegramDate(seconds: number | undefined): Date | null {
  if (!Number.isFinite(seconds)) return null
  const value = new Date((seconds as number) * 1000)
  return Number.isNaN(value.getTime()) ? null : value
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

function responseOutputText(payload: Record<string, unknown>): string | null {
  if (typeof payload.output_text === 'string') return payload.output_text
  if (!Array.isArray(payload.output)) return null
  for (const item of payload.output) {
    if (!item || typeof item !== 'object') continue
    const content = (item as Record<string, unknown>).content
    if (!Array.isArray(content)) continue
    for (const part of content) {
      if (!part || typeof part !== 'object') continue
      const text = (part as Record<string, unknown>).text
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

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
