import {
  type PasgarCandidate,
  type PasgarContextCandidate,
  type PasgarContextFieldKey,
  type PasgarIntakeSession,
  type PasgarTurnIntent,
  type PasgarTurnInterpretation,
} from './pasgar_conversation.ts'
import {
  getPasgarFieldDefinition,
  type PasgarFieldKey,
  pasgarFieldOrder,
  type PasgarLanguage,
} from './pasgar_intake_schema.ts'

export type PasgarAiProvider = 'openai' | 'openrouter'

export interface PasgarAiConfig {
  provider: PasgarAiProvider
  apiKey: string
  model?: string
  fetchImpl?: typeof fetch
}

export interface PasgarInterpretationInput {
  text: string
  session: PasgarIntakeSession | null
}

const freeOpenRouterModel = 'openrouter/free'
const defaultOpenAiModel = 'gpt-4.1-mini'

const pasgarIntents = [
  'start_pasgar',
  'provide_data',
  'correct',
  'confirm_summary',
  'pause',
  'resume',
  'cancel',
  'mission_chat',
] as const satisfies readonly PasgarTurnIntent[]

const pasgarLanguages = [
  'en',
  'ar',
  'mixed',
] as const satisfies readonly PasgarLanguage[]

const pasgarContextFieldKeys = [
  'customer',
  'flock',
  'hatchery',
  'scope',
  'setterIdentity',
  'hatcherIdentity',
] as const satisfies readonly PasgarContextFieldKey[]

export const pasgarTurnInterpretationSchema = {
  type: 'object',
  additionalProperties: false,
  required: [
    'intent',
    'language',
    'candidates',
    'contextCandidates',
    'allRemainingZero',
    'summaryVersion',
    'clarification',
  ],
  properties: {
    intent: { type: 'string', enum: pasgarIntents },
    language: { type: 'string', enum: pasgarLanguages },
    candidates: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['fieldKey', 'value', 'confidence', 'sourcePhrase'],
        properties: {
          fieldKey: { type: 'string', enum: pasgarFieldOrder },
          value: { type: 'integer' },
          confidence: { type: 'number', minimum: 0, maximum: 1 },
          sourcePhrase: { type: 'string' },
        },
      },
    },
    contextCandidates: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['fieldKey', 'value', 'confidence', 'sourcePhrase'],
        properties: {
          fieldKey: { type: 'string', enum: pasgarContextFieldKeys },
          value: { type: 'string' },
          confidence: { type: 'number', minimum: 0, maximum: 1 },
          sourcePhrase: { type: 'string' },
        },
      },
    },
    allRemainingZero: { type: 'boolean' },
    summaryVersion: { type: ['integer', 'null'] },
    clarification: {
      type: ['object', 'null'],
      additionalProperties: false,
      required: ['messageEn', 'messageAr', 'sourcePhrase'],
      properties: {
        messageEn: { type: 'string' },
        messageAr: { type: 'string' },
        sourcePhrase: { type: ['string', 'null'] },
      },
    },
  },
} as const

const interpreterInstructions = [
  'Interpret one Telegram turn for the ChickMark Pasgar intake controller.',
  'Return only the strict structured result requested by the schema.',
  'Support Arabic, English, and mixed-language messages and common misspellings.',
  'Return only values explicitly stated by the user; never guess or invent zero.',
  'Set allRemainingZero only for an explicit phrase such as “all remaining are zero”.',
  'Inside an active Pasgar intake, “peak” may mean the Beak defect field.',
  'Use contextCandidates for customer, flock, hatchery, scope, setter, or hatcher choices.',
  'Copy the exact supporting words into sourcePhrase and include confidence for every candidate.',
  'If a phrase is ambiguous or conflicting, do not guess; return a focused bilingual clarification.',
  'Treat yes/no as summary confirmation only when state is awaiting_user_confirmation.',
  'A normal question, greeting, or unrelated message with no active data action is mission_chat.',
].join(' ')

export async function interpretPasgarTurn(
  input: PasgarInterpretationInput,
  config: PasgarAiConfig,
): Promise<PasgarTurnInterpretation> {
  const providerName = config.provider === 'openrouter'
    ? 'OpenRouter'
    : 'OpenAI'
  const endpoint = config.provider === 'openrouter'
    ? 'https://openrouter.ai/api/v1/responses'
    : 'https://api.openai.com/v1/responses'
  const requestedModel = config.model ??
    (config.provider === 'openrouter'
      ? freeOpenRouterModel
      : defaultOpenAiModel)
  const fetchImpl = config.fetchImpl ?? fetch
  const requestForModel = (model: string) =>
    fetchImpl(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${config.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        store: false,
        instructions: interpreterInstructions,
        input: [{
          role: 'user',
          content: [{
            type: 'input_text',
            text: JSON.stringify({
              message: input.text,
              session: publicSessionContext(input.session),
              measurementVocabulary: pasgarFieldOrder.map((fieldKey) => {
                const field = getPasgarFieldDefinition(fieldKey)
                return {
                  fieldKey,
                  labelEn: field.labelEn,
                  labelAr: field.labelAr,
                  aliasesEn: field.aliasesEn,
                  aliasesAr: field.aliasesAr,
                }
              }),
            }),
          }],
        }],
        text: {
          format: {
            type: 'json_schema',
            name: 'pasgar_turn_interpretation',
            strict: true,
            schema: pasgarTurnInterpretationSchema,
          },
        },
      }),
    })

  let response = await requestForModel(requestedModel)
  if (
    config.provider === 'openrouter' &&
    response.status === 402 &&
    requestedModel !== freeOpenRouterModel
  ) {
    response = await requestForModel(freeOpenRouterModel)
  }
  if (!response.ok) {
    throw new Error(
      `${providerName} Pasgar interpretation failed: ${response.status}`,
    )
  }

  const payload = await response.json() as Record<string, unknown>
  const outputText = responseOutputText(payload)
  if (!outputText) {
    throw new Error(`${providerName} Pasgar interpretation returned no output`)
  }

  let decoded: unknown
  try {
    decoded = JSON.parse(outputText)
  } catch (_) {
    throw new Error(
      `${providerName} Pasgar interpretation returned invalid JSON`,
    )
  }
  if (!isPasgarTurnInterpretation(decoded)) {
    throw new Error(
      `${providerName} Pasgar interpretation returned an invalid structure`,
    )
  }
  return decoded
}

function publicSessionContext(session: PasgarIntakeSession | null): unknown {
  if (!session) return null
  return {
    state: session.state,
    language: session.language,
    context: {
      customerName: session.context.customerName,
      flockName: session.context.flockName,
      hatcheryName: session.context.hatcheryName,
      auditDate: session.context.auditDate,
      scope: session.context.scope,
      setterIdentity: session.context.setterIdentity,
      hatcherIdentity: session.context.hatcherIdentity,
    },
    workingValues: session.workingValues,
    pendingClarification: session.pendingClarification
      ? {
        fieldKey: session.pendingClarification.fieldKey,
        options: session.pendingClarification.options?.map((option, index) => ({
          number: index + 1,
          label: option.label,
        })) ?? [],
      }
      : null,
    summaryVersion: session.summaryVersion,
  }
}

function isPasgarTurnInterpretation(
  value: unknown,
): value is PasgarTurnInterpretation & {
  contextCandidates: PasgarContextCandidate[]
} {
  if (!isRecord(value)) return false
  if (!pasgarIntents.includes(value.intent as PasgarTurnIntent)) return false
  if (!pasgarLanguages.includes(value.language as PasgarLanguage)) return false
  if (!Array.isArray(value.candidates)) return false
  if (!value.candidates.every(isPasgarCandidate)) return false
  if (!Array.isArray(value.contextCandidates)) return false
  if (!value.contextCandidates.every(isPasgarContextCandidate)) return false
  if (typeof value.allRemainingZero !== 'boolean') return false
  if (
    value.summaryVersion !== null &&
    (!Number.isInteger(value.summaryVersion) ||
      (value.summaryVersion as number) < 0)
  ) return false
  if (value.clarification !== null && !isClarification(value.clarification)) {
    return false
  }
  return true
}

function isPasgarCandidate(value: unknown): value is PasgarCandidate {
  if (!isRecord(value)) return false
  return pasgarFieldOrder.includes(value.fieldKey as PasgarFieldKey) &&
    Number.isInteger(value.value) &&
    validConfidence(value.confidence) &&
    nonEmptyString(value.sourcePhrase)
}

function isPasgarContextCandidate(
  value: unknown,
): value is PasgarContextCandidate {
  if (!isRecord(value)) return false
  return pasgarContextFieldKeys.includes(
    value.fieldKey as PasgarContextFieldKey,
  ) &&
    nonEmptyString(value.value) &&
    validConfidence(value.confidence) &&
    nonEmptyString(value.sourcePhrase)
}

function isClarification(value: unknown): boolean {
  if (!isRecord(value)) return false
  return nonEmptyString(value.messageEn) &&
    nonEmptyString(value.messageAr) &&
    (value.sourcePhrase === null || nonEmptyString(value.sourcePhrase))
}

function validConfidence(value: unknown): boolean {
  return typeof value === 'number' && Number.isFinite(value) &&
    value >= 0 && value <= 1
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function responseOutputText(payload: Record<string, unknown>): string | null {
  if (typeof payload.output_text === 'string') return payload.output_text
  if (!Array.isArray(payload.output)) return null
  for (const item of payload.output) {
    if (!isRecord(item) || !Array.isArray(item.content)) continue
    for (const content of item.content) {
      if (!isRecord(content)) continue
      if (typeof content.text === 'string') return content.text
    }
  }
  return null
}
