import type { MissingQuestion } from './extraction_schema.ts'

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

export interface AnswerRoutingAdminClient {
  from(table: string): AdminQuery
}

export interface LegacyDraftQuestion {
  id: string
  submissionId: string
  rowOrdinal: number | null
  fieldKey: string
  questionTextEn: string
  questionTextAr: string
  submittedAt: string
}

type OpenQuestion = LegacyDraftQuestion

interface RoutedAnswer {
  question: OpenQuestion
  answerText: string
}

interface DraftRowState {
  id: string
  values: Record<string, unknown>
}

interface DraftRowMutation {
  rowId: string
  values: Record<string, unknown>
}

interface ParsedDraftValue {
  column: string
  value: unknown
}

interface QuestionGroup {
  submissionId: string
  submittedAt?: string
  questions: OpenQuestion[]
}

export interface AnswerRoutingResult extends Record<string, unknown> {
  accepted: true
  answered: boolean
  answeredCount?: number
  clarificationRequired?: boolean
  submissionIds?: string[]
  status: 'waiting_for_staff_answer' | 'needs_admin_review'
}

const answerableTextFields = new Map<string, string>([
  ['customerName', 'customer_name'],
  ['flockName', 'flock_name'],
  ['stationName', 'station_name'],
  ['breed', 'breed'],
  ['setterNumber', 'setter_number'],
  ['hatcherNumber', 'hatcher_number'],
])
const answerableIntegerFields = new Map<string, string>([
  ['eggsPlaced', 'eggs_placed'],
  ['healthyChicks', 'healthy_chicks'],
  ['secondGradeChicks', 'second_grade_chicks'],
  ['condemnedChicks', 'condemned_chicks'],
  ['totalProduction', 'total_production'],
  ['flockAgeWeeks', 'proposed_flock_age_weeks'],
  ['proposedFlockAgeWeeks', 'proposed_flock_age_weeks'],
])
const answerableNumberFields = new Map<string, string>([
  ['eggWeightG', 'egg_weight_g'],
  ['fertilityPct', 'fertility_pct'],
  ['transferWeightG', 'transfer_weight_g'],
])
const answerableDateFields = new Map<string, string>([
  ['productionDate', 'production_date'],
  ['placementDate', 'placement_date'],
  ['hatchDate', 'hatch_date'],
])

export async function tryHandleQuestionAnswer(params: {
  client: AnswerRoutingAdminClient
  replyText: string | null | undefined
  sendTelegramMessage(chatId: string, text: string): Promise<void>
  staffLinkId: string
  chatId: string
  updateId: string
  messageId: string
  timestamp: string
}): Promise<AnswerRoutingResult | null> {
  const replyText = nullableString(params.replyText)
  if (!replyText) return null

  const questions = await loadOpenDraftQuestions(
    params.client,
    params.staffLinkId,
    params.chatId,
  )
  if (questions.length === 0) return null

  const groups = groupOpenQuestions(questions)
  const answers = parseRoutedAnswers(replyText, groups)
  if (!answers) {
    await sendAnswerClarification(
      params.sendTelegramMessage,
      params.chatId,
      groups,
      false,
      isCasualMissionReply(replyText),
    )
    return {
      accepted: true,
      answered: false,
      clarificationRequired: true,
      status: 'waiting_for_staff_answer',
    }
  }

  const prepared = await prepareDraftMutations(
    params.client,
    answers,
    params.timestamp,
  )
  if (!prepared) {
    await sendAnswerClarification(
      params.sendTelegramMessage,
      params.chatId,
      groups,
      true,
      false,
    )
    return {
      accepted: true,
      answered: false,
      clarificationRequired: true,
      status: 'waiting_for_staff_answer',
    }
  }

  for (const mutation of prepared.rowMutations) {
    await updateRecordOrThrow(
      params.client,
      'hatchery_draft_rows',
      mutation.rowId,
      mutation.values,
    )
  }
  for (const answer of answers) {
    await updateRecordOrThrow(
      params.client,
      'agent_questions',
      answer.question.id,
      {
        status: 'answered',
        answer_text: answer.answerText,
        answered_at: params.timestamp,
        updated_at: params.timestamp,
      },
    )
  }

  const answeredIds = new Set(answers.map((answer) => answer.question.id))
  const answeredSubmissionIds = new Set(
    answers.map((answer) => answer.question.submissionId),
  )
  for (const group of groups) {
    if (!answeredSubmissionIds.has(group.submissionId)) continue
    if (group.questions.some((question) => !answeredIds.has(question.id))) {
      continue
    }
    const batchId = prepared.batchIds.get(group.submissionId)
    if (!batchId) throw new Error('Draft batch is missing')
    await updateRecordOrThrow(
      params.client,
      'hatchery_draft_batches',
      batchId,
      {
        status: 'needs_admin_review',
        updated_at: params.timestamp,
      },
    )
    await updateRecordOrThrow(
      params.client,
      'agent_submissions',
      group.submissionId,
      {
        status: 'needs_admin_review',
        updated_at: params.timestamp,
      },
    )
  }

  await insertAnswerReceipt({
    client: params.client,
    updateId: params.updateId,
    messageId: params.messageId,
    staffLinkId: params.staffLinkId,
    chatId: params.chatId,
    submissionIds: [...answeredSubmissionIds],
    timestamp: params.timestamp,
  })

  const remainingGroups = groups
    .map((group) => ({
      ...group,
      questions: group.questions.filter((question) =>
        !answeredIds.has(question.id)
      ),
    }))
    .filter((group) => group.questions.length > 0)
  try {
    if (remainingGroups.length > 0) {
      await sendAnswerClarification(
        params.sendTelegramMessage,
        params.chatId,
        remainingGroups,
        false,
        false,
      )
    } else {
      await params.sendTelegramMessage(
        params.chatId,
        'تم حفظ الإجابات ✅\nستظهر المسودة للمسؤول للمراجعة.',
      )
    }
  } catch (_) {
    // Persisted answers remain authoritative if Telegram delivery is down.
  }

  return {
    accepted: true,
    answered: true,
    answeredCount: answers.length,
    submissionIds: [...answeredSubmissionIds],
    status: remainingGroups.length > 0
      ? 'waiting_for_staff_answer'
      : 'needs_admin_review',
  }
}

export function formatQuestions(
  questions: MissingQuestion[],
  _submissionId: string,
): string {
  const lines = [
    'تم تجهيز مسودة من البيانات ✅',
    'نحتاج منك استكمال الآتي:',
  ]
  lines.push(...questionLines(questions))
  lines.push(
    'أرسل الإجابات بهذا الشكل:',
    ...answerExampleLines(questions),
    'إذا ظهرت اختيارات، اكتب رقم الاختيار فقط.',
  )
  return lines.join('\n')
}

async function insertAnswerReceipt(params: {
  client: AnswerRoutingAdminClient
  updateId: string
  messageId: string
  staffLinkId: string
  chatId: string
  submissionIds: string[]
  timestamp: string
}): Promise<void> {
  const result = await params.client
    .from('telegram_agent_update_receipts')
    .insert({
      update_id: params.updateId,
      message_id: params.messageId,
      staff_link_id: params.staffLinkId,
      telegram_chat_id: params.chatId,
      submission_ids_json: JSON.stringify(params.submissionIds),
      created_at: params.timestamp,
    })
  if (!result.error) return

  const duplicateResult = await params.client
    .from('telegram_agent_update_receipts')
    .select('update_id')
    .eq('update_id', params.updateId)
    .maybeSingle()
  if (duplicateResult.error || !duplicateResult.data) {
    throw new Error('Could not store Telegram answer update receipt')
  }
}

export async function loadOpenDraftQuestions(
  client: AnswerRoutingAdminClient,
  staffLinkId: string,
  chatId: string,
  submissionId?: string,
): Promise<LegacyDraftQuestion[]> {
  let query = client
    .from('agent_questions')
    .select(
      'id, submission_id, row_ordinal, field_key, question_text_en, question_text_ar, agent_submissions!inner(id, staff_link_id, telegram_chat_id, status, submitted_at)',
    )
    .eq('status', 'open')
    .eq('agent_submissions.staff_link_id', staffLinkId)
    .eq('agent_submissions.telegram_chat_id', chatId)
    .eq('agent_submissions.status', 'waiting_for_staff_answer')
  if (submissionId !== undefined) {
    query = query.eq('submission_id', submissionId)
  }
  const result = await (query as unknown as Promise<
    DatabaseResult<Record<string, unknown>[]>
  >)
  if (result.error) throw new Error('Could not load open agent questions')

  return (result.data ?? []).map((row) => {
    const submission = relatedRecord(row.agent_submissions)
    const id = idString(row.id)
    const submissionId = idString(row.submission_id ?? submission?.id)
    const fieldKey = nullableString(row.field_key)
    const questionTextEn = nullableString(row.question_text_en)
    const questionTextAr = nullableString(row.question_text_ar)
    if (
      !submission ||
      !id ||
      !submissionId ||
      !fieldKey ||
      !questionTextEn ||
      !questionTextAr
    ) {
      throw new Error('Open agent question is invalid')
    }
    return {
      id,
      submissionId,
      rowOrdinal: integerValue(row.row_ordinal),
      fieldKey,
      questionTextEn,
      questionTextAr,
      submittedAt: nullableString(submission.submitted_at) ?? '',
    }
  }).filter((question) =>
    submissionId === undefined || question.submissionId === submissionId
  )
}

export async function answerOpenDraftQuestion(params: {
  client: AnswerRoutingAdminClient
  staffLinkId: string
  chatId: string
  submissionId: string
  questionId: string
  answerText: string
  timestamp: string
}): Promise<
  | {
    questionId: string
    submissionId: string
    remainingCount: number
    status: 'waiting_for_staff_answer' | 'needs_admin_review'
  }
  | null
> {
  const questions = await loadOpenDraftQuestions(
    params.client,
    params.staffLinkId,
    params.chatId,
    params.submissionId,
  )
  const question = questions.find((candidate) =>
    candidate.id === params.questionId
  )
  if (!question) return null
  const answerText = nullableString(params.answerText)
  if (!answerText || isCasualMissionReply(answerText)) return null
  const answer = { question, answerText }
  const prepared = await prepareDraftMutations(
    params.client,
    [answer],
    params.timestamp,
  )
  if (!prepared) return null

  for (const mutation of prepared.rowMutations) {
    await updateRecordOrThrow(
      params.client,
      'hatchery_draft_rows',
      mutation.rowId,
      mutation.values,
    )
  }
  await updateRecordOrThrow(
    params.client,
    'agent_questions',
    question.id,
    {
      status: 'answered',
      answer_text: answerText,
      answered_at: params.timestamp,
      updated_at: params.timestamp,
    },
  )

  const remainingCount =
    questions.filter((candidate) => candidate.id !== question.id).length
  const status = remainingCount > 0
    ? 'waiting_for_staff_answer' as const
    : 'needs_admin_review' as const
  if (remainingCount === 0) {
    const batchId = prepared.batchIds.get(params.submissionId)
    if (!batchId) throw new Error('Draft batch is missing')
    await updateRecordOrThrow(
      params.client,
      'hatchery_draft_batches',
      batchId,
      { status, updated_at: params.timestamp },
    )
    await updateRecordOrThrow(
      params.client,
      'agent_submissions',
      params.submissionId,
      { status, updated_at: params.timestamp },
    )
  }
  return {
    questionId: question.id,
    submissionId: question.submissionId,
    remainingCount,
    status,
  }
}

function groupOpenQuestions(questions: OpenQuestion[]): QuestionGroup[] {
  const bySubmission = new Map<string, OpenQuestion[]>()
  for (const question of questions) {
    const current = bySubmission.get(question.submissionId) ?? []
    current.push(question)
    bySubmission.set(question.submissionId, current)
  }
  return [...bySubmission.entries()]
    .map(([submissionId, groupedQuestions]) => ({
      submissionId,
      submittedAt: groupedQuestions[0]?.submittedAt ?? '',
      questions: groupedQuestions.sort(compareQuestions),
    }))
    .sort((left, right) =>
      (right.submittedAt ?? '').localeCompare(left.submittedAt ?? '') ||
      left.submissionId.localeCompare(right.submissionId)
    )
}

function parseRoutedAnswers(
  replyText: string,
  groups: QuestionGroup[],
): RoutedAnswer[] | null {
  const lines = replyText
    .split(/\r?\n|;/)
    .map((line) => line.trim())
    .filter(Boolean)
  if (lines.length === 0) return null

  if (groups.length === 1 && groups[0].questions.length === 1) {
    if (lines.length !== 1) return null
    if (isCasualMissionReply(lines[0])) return null
    const targeted = parseQuestionLine(lines[0], groups[0].questions)
    if (targeted) return [targeted]
    return [{
      question: groups[0].questions[0],
      answerText: lines[0],
    }]
  }

  const answers: RoutedAnswer[] = []
  for (const line of lines) {
    let group = groups.length === 1 ? groups[0] : null
    let questionLine = line
    if (!group) {
      const groupMatch = line.match(
        /^(?:(?:طلب|الطلب|مجموعة|المجموعة)\s*)?([0-9\u0660-\u0669\u06f0-\u06f9]+)\s+(.+)$/u,
      )
      if (groupMatch) {
        const groupNumber = parseLocalizedInteger(groupMatch[1])
        if (groupNumber && groupNumber >= 1 && groupNumber <= groups.length) {
          group = groups[groupNumber - 1]
          questionLine = groupMatch[2]
        }
      }
    }
    if (!group) {
      const draftMatch = line.match(
        /^(?:(?:draft|مسودة|المسودة)\s+)?([A-Za-z0-9_-]{4,})\s+(.+)$/iu,
      )
      if (!draftMatch) return null
      const draftToken = draftMatch[1].toLowerCase()
      const matchingGroups = groups.filter((candidate) =>
        candidate.submissionId.toLowerCase().startsWith(draftToken) ||
        draftReference(candidate.submissionId).toLowerCase() === draftToken
      )
      if (matchingGroups.length !== 1) return null
      group = matchingGroups[0]
      questionLine = draftMatch[2]
    }

    const answer = parseQuestionLine(questionLine, group.questions)
    if (
      !answer || answers.some((item) => item.question.id === answer.question.id)
    ) {
      return null
    }
    answers.push(answer)
  }
  return answers.length > 0 ? answers : null
}

function parseQuestionLine(
  line: string,
  questions: OpenQuestion[],
): RoutedAnswer | null {
  const numbered = line.match(
    /^\s*#?([0-9\u0660-\u0669\u06f0-\u06f9]+)(?:\s*[\.):=]\s*|\s+)(.+)$/u,
  )
  if (numbered) {
    const number = parseLocalizedInteger(numbered[1])
    const answerText = nullableString(numbered[2])
    if (!number || !answerText || number > questions.length) return null
    return { question: questions[number - 1], answerText }
  }

  const rowReference = line.match(
    /^(?:row|صف|الصف|السطر)\s*([0-9\u0660-\u0669\u06f0-\u06f9]+)(?:\s+([A-Za-z][A-Za-z0-9_]*))?\s*[:=]\s*(.+)$/iu,
  )
  if (rowReference) {
    const rowOrdinal = parseLocalizedInteger(rowReference[1])
    const fieldKey = nullableString(rowReference[2])?.toLowerCase()
    const answerText = nullableString(rowReference[3])
    const matches = questions.filter((question) =>
      question.rowOrdinal === rowOrdinal &&
      (!fieldKey || question.fieldKey.toLowerCase() === fieldKey)
    )
    if (matches.length !== 1 || !answerText) return null
    return { question: matches[0], answerText }
  }

  const fieldReference = line.match(
    /^([A-Za-z][A-Za-z0-9_]*)\s*[:=]\s*(.+)$/u,
  )
  if (fieldReference) {
    const fieldKey = fieldReference[1].toLowerCase()
    const answerText = nullableString(fieldReference[2])
    const matches = questions.filter((question) =>
      question.fieldKey.toLowerCase() === fieldKey
    )
    if (matches.length !== 1 || !answerText) return null
    return { question: matches[0], answerText }
  }
  return null
}

async function prepareDraftMutations(
  client: AnswerRoutingAdminClient,
  answers: RoutedAnswer[],
  timestamp: string,
): Promise<
  {
    rowMutations: DraftRowMutation[]
    batchIds: Map<string, string>
  } | null
> {
  const batchIds = new Map<string, string>()
  const rowStates = new Map<string, DraftRowState | null>()
  const mutations = new Map<string, DraftRowMutation>()

  for (const answer of answers) {
    const parsed = parseDraftValue(
      answer.question.fieldKey,
      answer.answerText,
      answer.question,
    )
    if (parsed === null) return null

    let batchId = batchIds.get(answer.question.submissionId)
    if (!batchId) {
      const batchResult = await client
        .from('hatchery_draft_batches')
        .select('id')
        .eq('submission_id', answer.question.submissionId)
        .maybeSingle()
      if (batchResult.error) throw new Error('Could not load draft batch')
      batchId = idString(batchResult.data?.id) ?? undefined
      if (!batchId) throw new Error('Draft batch is missing')
      batchIds.set(answer.question.submissionId, batchId)
    }

    if (!parsed || answer.question.rowOrdinal === null) continue
    const rowKey = `${batchId}:${answer.question.rowOrdinal}`
    let rowState = rowStates.get(rowKey)
    if (rowState === undefined) {
      const rowResult = await client
        .from('hatchery_draft_rows')
        .select('id, eggs_placed, total_production')
        .eq('batch_id', batchId)
        .eq('row_ordinal', answer.question.rowOrdinal)
        .maybeSingle()
      if (rowResult.error) throw new Error('Could not load draft row')
      const rowId = idString(rowResult.data?.id)
      rowState = rowId ? { id: rowId, values: { ...rowResult.data } } : null
      rowStates.set(rowKey, rowState)
    }
    if (!rowState) continue

    rowState.values[parsed.column] = parsed.value
    const mutation = mutations.get(rowState.id) ?? {
      rowId: rowState.id,
      values: {
        status: 'needs_review',
        updated_at: timestamp,
      },
    }
    mutation.values[parsed.column] = parsed.value
    if (
      parsed.column === 'eggs_placed' ||
      parsed.column === 'total_production'
    ) {
      const eggsPlaced = numberValue(rowState.values.eggs_placed)
      const totalProduction = numberValue(rowState.values.total_production)
      mutation.values.hatchability_pct = eggsPlaced !== null &&
          eggsPlaced > 0 &&
          totalProduction !== null &&
          totalProduction >= 0
        ? totalProduction / eggsPlaced * 100
        : null
    }
    mutations.set(rowState.id, mutation)
  }

  return { rowMutations: [...mutations.values()], batchIds }
}

function parseDraftValue(
  fieldKey: string,
  answerText: string,
  question?: OpenQuestion,
): ParsedDraftValue | null | undefined {
  const textColumn = answerableTextFields.get(fieldKey)
  if (textColumn) {
    return {
      column: textColumn,
      value: parseQuestionOptionAnswer(question, answerText) ?? answerText,
    }
  }

  const integerColumn = answerableIntegerFields.get(fieldKey)
  if (integerColumn) {
    const value = parseLocalizedNumber(answerText)
    const requiresPositive = fieldKey === 'eggsPlaced' ||
      fieldKey === 'flockAgeWeeks' ||
      fieldKey === 'proposedFlockAgeWeeks'
    if (
      value === null ||
      !Number.isInteger(value) ||
      (requiresPositive ? value <= 0 : value < 0)
    ) {
      return null
    }
    return { column: integerColumn, value }
  }

  const numberColumn = answerableNumberFields.get(fieldKey)
  if (numberColumn) {
    const value = parseLocalizedNumber(answerText)
    const isPercentage = fieldKey === 'fertilityPct'
    if (
      value === null ||
      (isPercentage ? value < 0 || value > 100 : value <= 0)
    ) {
      return null
    }
    return { column: numberColumn, value }
  }

  const dateColumn = answerableDateFields.get(fieldKey)
  if (dateColumn) {
    const value = parseAnswerDate(answerText)
    return value ? { column: dateColumn, value } : null
  }
  return undefined
}

function parseLocalizedInteger(value: string): number | null {
  const parsed = Number(normalizeDigits(value))
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : null
}

function parseLocalizedNumber(value: string): number | null {
  let normalized = normalizeDigits(value)
    .replace(/[\u066c\s]/g, '')
    .replace(/\u066b/g, '.')
    .replace(/[%٪]$/u, '')
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

function parseAnswerDate(value: string): string | null {
  const normalized = normalizeDigits(value.trim())
  const iso = normalized.match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (iso) return validIsoDate(iso[1], iso[2], iso[3])
  const dayFirst = normalized.match(
    /^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{4})$/,
  )
  if (!dayFirst) return null
  return validIsoDate(
    dayFirst[3],
    dayFirst[2].padStart(2, '0'),
    dayFirst[1].padStart(2, '0'),
  )
}

function validIsoDate(year: string, month: string, day: string): string | null {
  const iso = `${year}-${month}-${day}`
  const parsed = new Date(`${iso}T00:00:00.000Z`)
  return !Number.isNaN(parsed.getTime()) &&
      parsed.toISOString().slice(0, 10) === iso
    ? iso
    : null
}

function normalizeDigits(value: string): string {
  return [...value].map((character) => {
    const code = character.codePointAt(0) ?? 0
    if (code >= 0x0660 && code <= 0x0669) {
      return String(code - 0x0660)
    }
    if (code >= 0x06f0 && code <= 0x06f9) {
      return String(code - 0x06f0)
    }
    return character
  }).join('')
}

async function sendAnswerClarification(
  sendTelegramMessage: (chatId: string, text: string) => Promise<void>,
  chatId: string,
  groups: QuestionGroup[],
  invalidValue: boolean,
  casualReply: boolean,
): Promise<void> {
  const lines = casualReply
    ? [
      'أهلًا 👋',
      'ما زالت هناك بيانات ناقصة لهذه المسودة.',
      'أرسل كل إجابة برقمها حتى أجهزها للمسؤول.',
    ]
    : invalidValue
    ? [
      'القيمة غير صحيحة.',
      'أرسل قيمة مناسبة للسؤال المطلوب.',
    ]
    : [
      'لم أستطع ربط الرد بالسؤال بأمان.',
      'أرسل كل إجابة برقمها.',
    ]
  lines.push(formatOpenQuestionGroups(groups))
  await sendTelegramMessage(chatId, lines.join('\n'))
}

function isCasualMissionReply(value: string): boolean {
  const normalized = normalizeDigits(value)
    .toLowerCase()
    .replace(/[؟?!.،,]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  const compact = normalized.replace(/\s+/g, '')
  return [
    'hi',
    'hello',
    'hey',
    'هاي',
    'هلا',
    'اهلا',
    'أهلا',
    'مرحبا',
    'السلامعليكم',
    'سلام',
  ].includes(compact)
}

function formatOpenQuestionGroups(groups: QuestionGroup[]): string {
  const multipleDrafts = groups.length > 1
  const lines: string[] = []
  for (const [index, group] of groups.entries()) {
    if (multipleDrafts) lines.push(`طلب ${index + 1}`)
    lines.push(...questionLines(group.questions))
  }
  lines.push(
    multipleDrafts
      ? 'أرسل الرد بهذا الشكل: 1 1: القيمة'
      : 'أرسل الرد بهذا الشكل: 1: القيمة',
    'إذا ظهرت اختيارات، اكتب رقم الاختيار فقط.',
  )
  return lines.join('\n')
}

function questionLines(
  questions: Array<{
    rowOrdinal: number | null
    fieldKey: string
    questionTextEn: string
    questionTextAr: string
  }>,
): string[] {
  const lines: string[] = []
  for (
    const [index, question] of [...questions].sort(compareQuestions).entries()
  ) {
    const questionText = cleanArabicQuestionText(question)
    const rowPrefix = question.rowOrdinal === null
      ? ''
      : `الصف ${question.rowOrdinal}: `
    lines.push(`${index + 1}) ${rowPrefix}${questionText}`)
  }
  return lines
}

function cleanArabicQuestionText(question: {
  fieldKey: string
  questionTextAr: string
}): string {
  return nullableString(question.questionTextAr) ??
    fallbackArabicQuestion(question.fieldKey)
}

function fallbackArabicQuestion(fieldKey: string): string {
  const labels = new Map<string, string>([
    ['customerName', 'ما اسم العميل؟'],
    ['flockName', 'ما اسم القطيع؟'],
    ['stationName', 'ما اسم المحطة؟'],
    ['breed', 'ما السلالة؟'],
    ['eggsPlaced', 'ما عدد البيض الموضوع؟'],
    ['productionDate', 'ما تاريخ الإنتاج؟'],
    ['placementDate', 'ما تاريخ الإيداع؟'],
    ['eggWeightG', 'ما وزن البيضة؟'],
    ['fertilityPct', 'ما نسبة الخصوبة؟'],
    ['transferWeightG', 'ما الوزن عند النقل؟'],
    ['setterNumber', 'ما رقم المفرخ؟'],
    ['hatcherNumber', 'ما رقم الفقاسة؟'],
    ['hatchDate', 'ما تاريخ الفقس؟'],
    ['healthyChicks', 'ما عدد الكتاكيت السليمة؟'],
    ['secondGradeChicks', 'ما عدد الفرزة/الكتاكيت الدرجة الثانية؟'],
    ['condemnedChicks', 'ما عدد المعدوم؟'],
    ['totalProduction', 'ما إجمالي الإنتاج؟'],
    ['flockAgeWeeks', 'ما عمر القطيع بالأسابيع؟'],
    ['proposedFlockAgeWeeks', 'ما عمر القطيع بالأسابيع؟'],
  ])
  return labels.get(fieldKey) ?? 'ما القيمة الصحيحة لهذا الحقل؟'
}

function answerExampleLines(questions: MissingQuestion[]): string[] {
  const sorted = [...questions].sort(compareQuestions)
  if (sorted.length === 0) return ['1: القيمة']
  return sorted.map((question, index) => {
    const value = exampleValueForQuestion(question)
    return `${index + 1}: ${value}`
  })
}

function exampleValueForQuestion(question: MissingQuestion): string {
  if (question.fieldKey === 'flockAgeWeeks') return '30'
  if (hasNumberedOptions(question.questionTextAr)) return '1'
  return 'القيمة'
}

function hasNumberedOptions(value: string): boolean {
  return extractNumberedOptions(value).size > 0
}

function parseQuestionOptionAnswer(
  question: OpenQuestion | undefined,
  answerText: string,
): string | null {
  if (!question) return null
  const optionNumber = parseLocalizedInteger(answerText.trim())
  if (!optionNumber || optionNumber <= 0) return null
  const options = new Map([
    ...extractNumberedOptions(question.questionTextAr),
    ...extractNumberedOptions(question.questionTextEn),
  ])
  return options.get(optionNumber) ?? null
}

function extractNumberedOptions(value: string): Map<number, string> {
  const options = new Map<number, string>()
  for (const line of value.split(/\r?\n/)) {
    const match = line.match(
      /^\s*([0-9\u0660-\u0669\u06f0-\u06f9]+)\s*[\).:-]\s*(.+?)\s*$/u,
    )
    if (!match) continue
    const number = parseLocalizedInteger(match[1])
    const option = nullableString(match[2])
    if (!number || !option) continue
    options.set(number, option)
  }
  return options
}

function compareQuestions(
  left: {
    rowOrdinal: number | null
    fieldKey: string
    questionTextEn: string
  },
  right: {
    rowOrdinal: number | null
    fieldKey: string
    questionTextEn: string
  },
): number {
  return (left.rowOrdinal ?? Number.MAX_SAFE_INTEGER) -
      (right.rowOrdinal ?? Number.MAX_SAFE_INTEGER) ||
    left.fieldKey.localeCompare(right.fieldKey) ||
    left.questionTextEn.localeCompare(right.questionTextEn)
}

function draftReference(submissionId: string): string {
  return submissionId.replaceAll('-', '').slice(0, 8)
}

function relatedRecord(value: unknown): Record<string, unknown> | null {
  if (Array.isArray(value)) {
    return value.length === 1 && value[0] && typeof value[0] === 'object'
      ? value[0] as Record<string, unknown>
      : null
  }
  return value && typeof value === 'object'
    ? value as Record<string, unknown>
    : null
}

async function updateRecordOrThrow(
  client: AnswerRoutingAdminClient,
  table: string,
  id: string,
  values: Record<string, unknown>,
): Promise<void> {
  const result = await client.from(table).update(values).eq('id', id)
  if (result.error) throw new Error(`Could not update ${table}`)
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
