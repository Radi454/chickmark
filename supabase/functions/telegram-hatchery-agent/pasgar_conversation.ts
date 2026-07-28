import {
  applyAllRemainingZero,
  calculatePasgarSummary,
  formatPasgarSummary,
  getPasgarFieldDefinition,
  missingPasgarFields,
  PASGAR_SCHEMA_KEY,
  PASGAR_SCHEMA_VERSION,
  type PasgarFieldKey,
  type PasgarLanguage,
  type PasgarWorkingValues,
  validatePasgarCandidate,
} from './pasgar_intake_schema.ts'

export type PasgarIntakeState =
  | 'collecting'
  | 'awaiting_clarification'
  | 'paused'
  | 'ready_for_summary'
  | 'awaiting_user_confirmation'
  | 'awaiting_admin_review'
  | 'approved'
  | 'rejected'
  | 'cancelled'

export type PasgarScope = 'pool' | 'setter_hatcher'
export type PasgarContextFieldKey =
  | 'customer'
  | 'flock'
  | 'hatchery'
  | 'scope'
  | 'setterIdentity'
  | 'hatcherIdentity'

export interface PasgarIntakeContext {
  customerId: string | null
  customerName: string | null
  flockId: string | null
  flockName: string | null
  hatcheryId: string | null
  hatcheryName: string | null
  auditDate: string
  scope: PasgarScope | null
  setterIdentity: string | null
  hatcherIdentity: string | null
}

export interface PasgarPendingClarification {
  fieldKey: PasgarFieldKey | PasgarContextFieldKey | null
  sourcePhrase: string | null
  messageEn: string
  messageAr: string
  options?: readonly PasgarContextChoice[]
}

export interface PasgarSummarySnapshot {
  version: number
  values: PasgarWorkingValues
  generatedAt: string
}

export interface PasgarIntakeSession {
  id: string
  staffLinkId: string
  chatId: string
  schemaKey: typeof PASGAR_SCHEMA_KEY
  schemaVersion: typeof PASGAR_SCHEMA_VERSION
  state: PasgarIntakeState
  language: PasgarLanguage
  context: PasgarIntakeContext
  workingValues: PasgarWorkingValues
  pendingClarification: PasgarPendingClarification | null
  summaryVersion: number
  summarySnapshot: PasgarSummarySnapshot | null
  userConfirmedAt: string | null
  createdAt: string
  updatedAt: string
}

export type PasgarTurnIntent =
  | 'start_pasgar'
  | 'provide_data'
  | 'correct'
  | 'confirm_summary'
  | 'pause'
  | 'resume'
  | 'cancel'
  | 'mission_chat'

export interface PasgarCandidate {
  fieldKey: PasgarFieldKey
  value: number
  confidence: number
  sourcePhrase: string
}

export interface PasgarContextCandidate {
  fieldKey: PasgarContextFieldKey
  value: string
  confidence: number
  sourcePhrase: string
}

export interface PasgarTurnInterpretation {
  intent: PasgarTurnIntent
  language: PasgarLanguage
  candidates: PasgarCandidate[]
  contextCandidates?: PasgarContextCandidate[]
  allRemainingZero: boolean
  summaryVersion: number | null
  clarification: {
    messageEn: string
    messageAr: string
    sourcePhrase: string | null
  } | null
}

export interface PasgarTurnInput {
  staffLinkId: string
  chatId: string
  updateId: string
  messageId: string
  text: string
  receivedAt: string
}

export interface PasgarIntakeTurn {
  id: string
  sessionId: string
  direction: 'inbound' | 'outbound'
  updateId: string | null
  messageId: string | null
  text: string
  language: PasgarLanguage
  intent: PasgarTurnIntent | null
  createdAt: string
}

export interface PasgarValueUpdate {
  fieldKey: PasgarFieldKey
  value: number
  sourcePhrase: string
  confidence: number
  updatedAt: string
}

export interface PasgarContextChoice {
  id: string
  label: string
}

export interface PasgarContextResolver {
  listCustomers(staffLinkId: string): Promise<readonly PasgarContextChoice[]>
  listFlocks(
    staffLinkId: string,
    customerId: string,
  ): Promise<readonly PasgarContextChoice[]>
  listHatcheries(
    staffLinkId: string,
    customerId: string,
  ): Promise<readonly PasgarContextChoice[]>
  listSetters(
    staffLinkId: string,
    customerId: string,
    hatcheryId: string,
  ): Promise<readonly PasgarContextChoice[]>
  listHatchers(
    staffLinkId: string,
    customerId: string,
    hatcheryId: string,
  ): Promise<readonly PasgarContextChoice[]>
}

export interface PasgarIntakeStore {
  findActiveSession(
    staffLinkId: string,
    chatId: string,
  ): Promise<PasgarIntakeSession | null>
  createSession(session: PasgarIntakeSession): Promise<void>
  saveInboundTurn(turn: PasgarIntakeTurn): Promise<'inserted' | 'duplicate'>
  saveOutboundTurn(turn: PasgarIntakeTurn): Promise<void>
  saveValues(sessionId: string, values: PasgarValueUpdate[]): Promise<void>
  updateSession(
    sessionId: string,
    patch: Partial<PasgarIntakeSession>,
  ): Promise<void>
}

export interface PasgarConversationDependencies {
  store: PasgarIntakeStore
  interpretTurn(input: {
    turn: PasgarTurnInput
    session: PasgarIntakeSession | null
  }): Promise<PasgarTurnInterpretation>
  createId(): string
  contextResolver?: PasgarContextResolver
}

export interface PasgarConversationResult {
  handled: true
  sessionId: string
  state: PasgarIntakeState
  reply: string | null
  nextFieldKey: PasgarFieldKey | null
  nextContextField: PasgarContextFieldKey | null
  summaryVersion: number
  duplicate: boolean
}

export async function tryHandlePasgarConversation(
  input: PasgarTurnInput,
  dependencies: PasgarConversationDependencies,
): Promise<PasgarConversationResult | null> {
  let session = await dependencies.store.findActiveSession(
    input.staffLinkId,
    input.chatId,
  )
  const interpretation = await dependencies.interpretTurn({
    turn: input,
    session,
  })

  if (!session && interpretation.intent !== 'start_pasgar') return null

  if (!session) {
    session = newPasgarSession(input, interpretation.language, dependencies)
    await dependencies.store.createSession(session)
  }

  return applyTurn(input, session, interpretation, dependencies)
}

export async function handlePasgarTurn(
  input: PasgarTurnInput,
  dependencies: PasgarConversationDependencies,
): Promise<PasgarConversationResult> {
  const result = await tryHandlePasgarConversation(input, dependencies)
  if (!result) {
    throw new Error('The turn is not part of a Pasgar conversation.')
  }
  return result
}

async function applyTurn(
  input: PasgarTurnInput,
  session: PasgarIntakeSession,
  interpretation: PasgarTurnInterpretation,
  dependencies: PasgarConversationDependencies,
): Promise<PasgarConversationResult> {
  const inbound: PasgarIntakeTurn = {
    id: dependencies.createId(),
    sessionId: session.id,
    direction: 'inbound',
    updateId: input.updateId,
    messageId: input.messageId,
    text: input.text,
    language: interpretation.language,
    intent: interpretation.intent,
    createdAt: input.receivedAt,
  }
  const receipt = await dependencies.store.saveInboundTurn(inbound)
  if (receipt === 'duplicate') {
    return resultFor(session, null, null, null, true)
  }

  const language = rememberLanguage(session.language, interpretation.language)
  if (interpretation.intent === 'cancel') {
    return persistStateAndReply({
      input,
      session,
      dependencies,
      patch: {
        state: 'cancelled',
        language,
        pendingClarification: null,
        updatedAt: input.receivedAt,
      },
      reply: localize(
        language,
        'Okay, I cancelled this Pasgar intake.',
        'حسنًا، ألغيت إدخال باسجار.',
      ),
    })
  }

  if (interpretation.intent === 'pause') {
    return persistStateAndReply({
      input,
      session,
      dependencies,
      patch: {
        state: 'paused',
        language,
        updatedAt: input.receivedAt,
      },
      reply: localize(
        language,
        'Paused. Send “continue” whenever you are ready.',
        'تم الإيقاف مؤقتًا. أرسل «متابعة» عندما تكون جاهزًا.',
      ),
    })
  }

  if (session.state === 'paused' && interpretation.intent !== 'resume') {
    return persistReply(
      input,
      session,
      dependencies,
      localize(
        language,
        'This Pasgar intake is paused. Send “continue” or “cancel”.',
        'إدخال باسجار متوقف مؤقتًا. أرسل «متابعة» أو «إلغاء».',
      ),
    )
  }

  if (
    interpretation.intent === 'confirm_summary' &&
    session.state === 'awaiting_user_confirmation' &&
    session.summarySnapshot !== null &&
    interpretation.summaryVersion === session.summaryVersion
  ) {
    return persistStateAndReply({
      input,
      session,
      dependencies,
      patch: {
        state: 'awaiting_admin_review',
        language,
        userConfirmedAt: input.receivedAt,
        pendingClarification: null,
        updatedAt: input.receivedAt,
      },
      reply: localize(
        language,
        'Thank you. The complete Pasgar record was sent for review.',
        'شكرًا. تم إرسال سجل باسجار الكامل للمراجعة.',
      ),
    })
  }

  const contextResult = await applyContextCandidates({
    input,
    session,
    interpretation,
    dependencies,
  })
  const context = contextResult.context
  if (contextResult.clarification) {
    return persistStateAndReply({
      input,
      session,
      dependencies,
      patch: {
        state: 'awaiting_clarification',
        language,
        context,
        pendingClarification: contextResult.clarification,
        updatedAt: input.receivedAt,
      },
      reply: localize(
        language,
        contextResult.clarification.messageEn,
        contextResult.clarification.messageAr,
      ),
      nextContextField: contextResult.clarification.fieldKey as
        | PasgarContextFieldKey
        | null,
    })
  }

  const workingValues = { ...session.workingValues }
  const accepted: PasgarValueUpdate[] = []
  let clarification: PasgarPendingClarification | null = null

  for (const candidate of orderCandidates(interpretation.candidates)) {
    if (candidate.confidence < 0.8) {
      clarification ??= {
        fieldKey: candidate.fieldKey,
        sourcePhrase: candidate.sourcePhrase,
        messageEn: `I am not sure what “${candidate.sourcePhrase}” means for ` +
          `${
            getPasgarFieldDefinition(candidate.fieldKey).labelEn
          }. Please clarify it.`,
        messageAr:
          `لست متأكدًا من معنى «${candidate.sourcePhrase}» بالنسبة إلى ` +
          `${
            getPasgarFieldDefinition(candidate.fieldKey).labelAr
          }. من فضلك وضّحها.`,
      }
      continue
    }

    const validation = validatePasgarCandidate(
      candidate.fieldKey,
      candidate.value,
      workingValues,
    )
    if (!validation.ok) {
      clarification ??= {
        fieldKey: candidate.fieldKey,
        sourcePhrase: candidate.sourcePhrase,
        messageEn: validation.messageEn,
        messageAr: validation.messageAr,
      }
      continue
    }

    workingValues[candidate.fieldKey] = validation.value
    accepted.push({
      fieldKey: candidate.fieldKey,
      value: validation.value,
      sourcePhrase: candidate.sourcePhrase,
      confidence: candidate.confidence,
      updatedAt: input.receivedAt,
    })
  }

  if (interpretation.allRemainingZero) {
    const zeroFilled = applyAllRemainingZero(workingValues)
    for (
      const fieldKey of missingPasgarFields(workingValues).filter((key) =>
        key !== 'pasgarSampleSize'
      )
    ) {
      workingValues[fieldKey] = zeroFilled[fieldKey]
      accepted.push({
        fieldKey,
        value: 0,
        sourcePhrase: input.text,
        confidence: 1,
        updatedAt: input.receivedAt,
      })
    }
  }

  if (accepted.length > 0) {
    await dependencies.store.saveValues(session.id, accepted)
  }

  if (interpretation.clarification) {
    clarification ??= {
      fieldKey: null,
      sourcePhrase: interpretation.clarification.sourcePhrase,
      messageEn: interpretation.clarification.messageEn,
      messageAr: interpretation.clarification.messageAr,
    }
  }

  if (clarification) {
    return persistStateAndReply({
      input,
      session,
      dependencies,
      patch: {
        state: 'awaiting_clarification',
        language,
        context,
        workingValues,
        pendingClarification: clarification,
        summarySnapshot: accepted.length > 0 ? null : session.summarySnapshot,
        updatedAt: input.receivedAt,
      },
      reply: localize(
        language,
        clarification.messageEn,
        clarification.messageAr,
      ),
    })
  }

  const nextContextField = missingContextField(context)
  if (nextContextField) {
    const contextPrompt = await buildContextPrompt({
      fieldKey: nextContextField,
      input,
      context,
      dependencies,
      language,
    })
    return persistStateAndReply({
      input,
      session,
      dependencies,
      patch: {
        state: 'collecting',
        language,
        context,
        workingValues,
        pendingClarification: null,
        summarySnapshot: accepted.length > 0 ? null : session.summarySnapshot,
        updatedAt: input.receivedAt,
      },
      reply: contextPrompt,
      nextContextField,
    })
  }

  const missing = missingPasgarFields(workingValues)
  if (missing.length > 0) {
    const nextFieldKey = missing[0]
    const definition = getPasgarFieldDefinition(nextFieldKey)
    return persistStateAndReply({
      input,
      session,
      dependencies,
      patch: {
        state: 'collecting',
        language,
        context,
        workingValues,
        pendingClarification: null,
        summarySnapshot: accepted.length > 0 ? null : session.summarySnapshot,
        updatedAt: input.receivedAt,
      },
      reply: localize(language, definition.questionEn, definition.questionAr),
      nextFieldKey,
    })
  }

  const summary = calculatePasgarSummary(workingValues)
  const summaryVersion = session.summaryVersion + 1
  const summarySnapshot: PasgarSummarySnapshot = {
    version: summaryVersion,
    values: { ...workingValues },
    generatedAt: input.receivedAt,
  }
  const confirmation = localize(
    language,
    'Is this complete summary correct?',
    'هل هذا الملخص الكامل صحيح؟',
  )
  return persistStateAndReply({
    input,
    session,
    dependencies,
    patch: {
      state: 'awaiting_user_confirmation',
      language,
      context,
      workingValues,
      pendingClarification: null,
      summaryVersion,
      summarySnapshot,
      userConfirmedAt: null,
      updatedAt: input.receivedAt,
    },
    reply: `${formatPasgarSummary(summary, language)}\n\n${confirmation}`,
  })
}

function newPasgarSession(
  input: PasgarTurnInput,
  language: PasgarLanguage,
  dependencies: PasgarConversationDependencies,
): PasgarIntakeSession {
  return {
    id: dependencies.createId(),
    staffLinkId: input.staffLinkId,
    chatId: input.chatId,
    schemaKey: PASGAR_SCHEMA_KEY,
    schemaVersion: PASGAR_SCHEMA_VERSION,
    state: 'collecting',
    language,
    context: {
      customerId: null,
      customerName: null,
      flockId: null,
      flockName: null,
      hatcheryId: null,
      hatcheryName: null,
      auditDate: input.receivedAt.slice(0, 10),
      scope: null,
      setterIdentity: null,
      hatcherIdentity: null,
    },
    workingValues: {},
    pendingClarification: null,
    summaryVersion: 0,
    summarySnapshot: null,
    userConfirmedAt: null,
    createdAt: input.receivedAt,
    updatedAt: input.receivedAt,
  }
}

async function persistStateAndReply(params: {
  input: PasgarTurnInput
  session: PasgarIntakeSession
  dependencies: PasgarConversationDependencies
  patch: Partial<PasgarIntakeSession>
  reply: string
  nextFieldKey?: PasgarFieldKey | null
  nextContextField?: PasgarContextFieldKey | null
}): Promise<PasgarConversationResult> {
  await params.dependencies.store.updateSession(params.session.id, params.patch)
  const nextSession = { ...params.session, ...params.patch }
  await saveOutbound(
    params.input,
    nextSession,
    params.dependencies,
    params.reply,
  )
  return resultFor(
    nextSession,
    params.reply,
    params.nextFieldKey ?? null,
    params.nextContextField ?? null,
    false,
  )
}

async function persistReply(
  input: PasgarTurnInput,
  session: PasgarIntakeSession,
  dependencies: PasgarConversationDependencies,
  reply: string,
): Promise<PasgarConversationResult> {
  await saveOutbound(input, session, dependencies, reply)
  return resultFor(session, reply, null, null, false)
}

async function saveOutbound(
  input: PasgarTurnInput,
  session: PasgarIntakeSession,
  dependencies: PasgarConversationDependencies,
  reply: string,
): Promise<void> {
  await dependencies.store.saveOutboundTurn({
    id: dependencies.createId(),
    sessionId: session.id,
    direction: 'outbound',
    updateId: null,
    messageId: null,
    text: reply,
    language: session.language,
    intent: null,
    createdAt: input.receivedAt,
  })
}

function resultFor(
  session: PasgarIntakeSession,
  reply: string | null,
  nextFieldKey: PasgarFieldKey | null,
  nextContextField: PasgarContextFieldKey | null,
  duplicate: boolean,
): PasgarConversationResult {
  return {
    handled: true,
    sessionId: session.id,
    state: session.state,
    reply,
    nextFieldKey,
    nextContextField,
    summaryVersion: session.summaryVersion,
    duplicate,
  }
}

async function applyContextCandidates(params: {
  input: PasgarTurnInput
  session: PasgarIntakeSession
  interpretation: PasgarTurnInterpretation
  dependencies: PasgarConversationDependencies
}): Promise<{
  context: PasgarIntakeContext
  clarification: PasgarPendingClarification | null
}> {
  const context = { ...params.session.context }
  for (const candidate of params.interpretation.contextCandidates ?? []) {
    if (candidate.confidence < 0.8) {
      return {
        context,
        clarification: {
          fieldKey: candidate.fieldKey,
          sourcePhrase: candidate.sourcePhrase,
          messageEn: `I am not sure which ${
            contextLabel(candidate.fieldKey, 'en')
          } you mean.`,
          messageAr: `لست متأكدًا من ${
            contextLabel(candidate.fieldKey, 'ar')
          } المقصود.`,
        },
      }
    }

    if (candidate.fieldKey === 'scope') {
      const scope = normalizeScope(candidate.value)
      if (!scope) {
        return {
          context,
          clarification: {
            fieldKey: 'scope',
            sourcePhrase: candidate.sourcePhrase,
            messageEn: 'Please choose Pool or Setter/Hatcher.',
            messageAr: 'من فضلك اختر مجمع أو سيتر/هاتشر.',
            options: scopeChoices,
          },
        }
      }
      context.scope = scope
      if (scope === 'pool') {
        context.setterIdentity = null
        context.hatcherIdentity = null
      }
      continue
    }

    const choices = await choicesForContextField(
      candidate.fieldKey,
      params.input.staffLinkId,
      context,
      params.dependencies.contextResolver,
    )
    const choice = resolveContextChoice(candidate.value, choices)
    if (!choice) {
      return {
        context,
        clarification: {
          fieldKey: candidate.fieldKey,
          sourcePhrase: candidate.sourcePhrase,
          messageEn:
            `I could not safely identify that ${
              contextLabel(candidate.fieldKey, 'en')
            }. ` +
            'Please choose one of these options:\n' + formatChoices(choices),
          messageAr:
            `لم أتمكن من تحديد ${
              contextLabel(candidate.fieldKey, 'ar')
            } بأمان. ` +
            'من فضلك اختر من هذه الخيارات:\n' + formatChoices(choices),
          options: choices,
        },
      }
    }
    applyContextChoice(context, candidate.fieldKey, choice)
  }
  return { context, clarification: null }
}

function missingContextField(
  context: PasgarIntakeContext,
): PasgarContextFieldKey | null {
  if (!context.customerId) return 'customer'
  if (!context.flockId) return 'flock'
  if (!context.hatcheryId) return 'hatchery'
  if (!context.scope) return 'scope'
  if (context.scope === 'setter_hatcher' && !context.setterIdentity) {
    return 'setterIdentity'
  }
  if (context.scope === 'setter_hatcher' && !context.hatcherIdentity) {
    return 'hatcherIdentity'
  }
  return null
}

async function buildContextPrompt(params: {
  fieldKey: PasgarContextFieldKey
  input: PasgarTurnInput
  context: PasgarIntakeContext
  dependencies: PasgarConversationDependencies
  language: PasgarLanguage
}): Promise<string> {
  const choices = params.fieldKey === 'scope'
    ? scopeChoices
    : await choicesForContextField(
      params.fieldKey,
      params.input.staffLinkId,
      params.context,
      params.dependencies.contextResolver,
    )
  const english = contextQuestion(params.fieldKey, 'en')
  const arabic = contextQuestion(params.fieldKey, 'ar')
  const options = formatChoices(choices)
  return `${localize(params.language, english, arabic)}\n${options}`
}

async function choicesForContextField(
  fieldKey: PasgarContextFieldKey,
  staffLinkId: string,
  context: PasgarIntakeContext,
  resolver?: PasgarContextResolver,
): Promise<readonly PasgarContextChoice[]> {
  if (!resolver) return []
  if (fieldKey === 'customer') return resolver.listCustomers(staffLinkId)
  if (fieldKey === 'flock' && context.customerId) {
    return resolver.listFlocks(staffLinkId, context.customerId)
  }
  if (fieldKey === 'hatchery' && context.customerId) {
    return resolver.listHatcheries(staffLinkId, context.customerId)
  }
  if (
    fieldKey === 'setterIdentity' && context.customerId &&
    context.hatcheryId
  ) {
    return resolver.listSetters(
      staffLinkId,
      context.customerId,
      context.hatcheryId,
    )
  }
  if (
    fieldKey === 'hatcherIdentity' && context.customerId &&
    context.hatcheryId
  ) {
    return resolver.listHatchers(
      staffLinkId,
      context.customerId,
      context.hatcheryId,
    )
  }
  return []
}

function resolveContextChoice(
  rawValue: string,
  choices: readonly PasgarContextChoice[],
): PasgarContextChoice | null {
  const trimmed = rawValue.trim()
  if (/^\d+$/.test(trimmed)) {
    return choices[Number(trimmed) - 1] ?? null
  }
  const normalized = normalizeText(trimmed)
  const matches = choices.filter((choice) =>
    choice.id === trimmed || normalizeText(choice.label) === normalized
  )
  return matches.length === 1 ? matches[0] : null
}

function applyContextChoice(
  context: PasgarIntakeContext,
  fieldKey: PasgarContextFieldKey,
  choice: PasgarContextChoice,
): void {
  if (fieldKey === 'customer') {
    context.customerId = choice.id
    context.customerName = choice.label
    context.flockId = null
    context.flockName = null
    context.hatcheryId = null
    context.hatcheryName = null
    return
  }
  if (fieldKey === 'flock') {
    context.flockId = choice.id
    context.flockName = choice.label
    return
  }
  if (fieldKey === 'hatchery') {
    context.hatcheryId = choice.id
    context.hatcheryName = choice.label
    context.setterIdentity = null
    context.hatcherIdentity = null
    return
  }
  if (fieldKey === 'setterIdentity') {
    context.setterIdentity = choice.id
    return
  }
  if (fieldKey === 'hatcherIdentity') {
    context.hatcherIdentity = choice.id
  }
}

function normalizeScope(value: string): PasgarScope | null {
  const normalized = normalizeText(value).replaceAll(' ', '_')
  if (['pool', 'مجمع', 'المجمع'].includes(normalized)) return 'pool'
  if (
    [
      'setter_hatcher',
      'setter/hatcher',
      'setter',
      'hatcher',
      'سيتر',
      'هاتشر',
    ].includes(normalized)
  ) return 'setter_hatcher'
  return null
}

function normalizeText(value: string): string {
  return value.trim().toLocaleLowerCase().replaceAll(/\s+/g, ' ')
}

function formatChoices(choices: readonly PasgarContextChoice[]): string {
  if (choices.length === 0) return '—'
  return choices.map((choice, index) => `${index + 1}. ${choice.label}`).join(
    '\n',
  )
}

function contextQuestion(
  fieldKey: PasgarContextFieldKey,
  language: 'en' | 'ar',
): string {
  const questions = {
    customer: ['Which customer is this for?', 'ما العميل الخاص بهذا السجل؟'],
    flock: ['Which flock is this for?', 'ما القطيع الخاص بهذا السجل؟'],
    hatchery: ['Which hatchery is this for?', 'ما المفرخ الخاص بهذا السجل؟'],
    scope: [
      'Is this a Pool or Setter/Hatcher sample?',
      'هل هذه عينة مجمع أم سيتر/هاتشر؟',
    ],
    setterIdentity: ['Which setter?', 'ما رقم السيتر؟'],
    hatcherIdentity: ['Which hatcher?', 'ما رقم الهاتشر؟'],
  } as const
  return questions[fieldKey][language === 'en' ? 0 : 1]
}

function contextLabel(
  fieldKey: PasgarContextFieldKey,
  language: 'en' | 'ar',
): string {
  const labels = {
    customer: ['customer', 'العميل'],
    flock: ['flock', 'القطيع'],
    hatchery: ['hatchery', 'المفرخ'],
    scope: ['scope', 'النطاق'],
    setterIdentity: ['setter', 'السيتر'],
    hatcherIdentity: ['hatcher', 'الهاتشر'],
  } as const
  return labels[fieldKey][language === 'en' ? 0 : 1]
}

const scopeChoices: readonly PasgarContextChoice[] = [
  { id: 'pool', label: 'Pool / مجمع' },
  { id: 'setter_hatcher', label: 'Setter/Hatcher / سيتر/هاتشر' },
]

function rememberLanguage(
  previous: PasgarLanguage,
  detected: PasgarLanguage,
): PasgarLanguage {
  if (detected === 'mixed') return 'mixed'
  if (detected === 'en' || detected === 'ar') return detected
  return previous
}

function localize(
  language: PasgarLanguage,
  english: string,
  arabic: string,
): string {
  if (language === 'ar') return arabic
  if (language === 'mixed') return `${english}\n${arabic}`
  return english
}

function orderCandidates(
  candidates: readonly PasgarCandidate[],
): PasgarCandidate[] {
  return [...candidates].sort((left, right) => {
    if (left.fieldKey === 'pasgarSampleSize') return -1
    if (right.fieldKey === 'pasgarSampleSize') return 1
    return 0
  })
}
