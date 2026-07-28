export const PASGAR_SCHEMA_KEY = 'chicks.pasgar'
export const PASGAR_SCHEMA_VERSION = 1

export const pasgarFieldOrder = [
  'pasgarSampleSize',
  'pasgarReflexesCount',
  'pasgarBeakCount',
  'pasgarNavelCount',
  'pasgarBellyCount',
  'pasgarLegCount',
  'pasgarFeatherDevCount',
] as const

export type PasgarFieldKey = typeof pasgarFieldOrder[number]
export type PasgarDefectFieldKey = Exclude<
  PasgarFieldKey,
  'pasgarSampleSize'
>
export type PasgarLanguage = 'en' | 'ar' | 'mixed'
export type PasgarWorkingValues = Partial<Record<PasgarFieldKey, number>>

export interface PasgarFieldDefinition {
  key: PasgarFieldKey
  labelEn: string
  labelAr: string
  aliasesEn: readonly string[]
  aliasesAr: readonly string[]
  questionEn: string
  questionAr: string
}

export type PasgarCandidateValidation =
  | { ok: true; value: number }
  | { ok: false; messageEn: string; messageAr: string }

export interface PasgarSummary {
  schemaKey: typeof PASGAR_SCHEMA_KEY
  schemaVersion: typeof PASGAR_SCHEMA_VERSION
  sampleSize: number
  counts: Record<PasgarDefectFieldKey, number>
  percentages: Record<PasgarDefectFieldKey, number>
  score: number
}

const defectFieldOrder = pasgarFieldOrder.slice(1) as PasgarDefectFieldKey[]

const fieldDefinitions: Record<PasgarFieldKey, PasgarFieldDefinition> = {
  pasgarSampleSize: {
    key: 'pasgarSampleSize',
    labelEn: 'Sample',
    labelAr: 'العينة',
    aliasesEn: ['sample', 'sample size', 'chicks sampled'],
    aliasesAr: ['العينة', 'حجم العينة', 'عدد الكتاكيت'],
    questionEn: 'How many chicks were sampled?',
    questionAr: 'كم عدد الكتاكيت في العينة؟',
  },
  pasgarReflexesCount: {
    key: 'pasgarReflexesCount',
    labelEn: 'Reflexes',
    labelAr: 'ردود الفعل',
    aliasesEn: ['reflex', 'reflexes', 'activity'],
    aliasesAr: ['رد الفعل', 'ردود الفعل', 'النشاط'],
    questionEn: 'How many chicks had a reflex defect?',
    questionAr: 'كم كتكوتًا لديه مشكلة في ردود الفعل؟',
  },
  pasgarBeakCount: {
    key: 'pasgarBeakCount',
    labelEn: 'Beak',
    labelAr: 'المنقار',
    aliasesEn: ['beak', 'peak'],
    aliasesAr: ['المنقار', 'منقار'],
    questionEn: 'How many chicks had a beak defect?',
    questionAr: 'كم كتكوتًا لديه مشكلة في المنقار؟',
  },
  pasgarNavelCount: {
    key: 'pasgarNavelCount',
    labelEn: 'Navel',
    labelAr: 'السرة',
    aliasesEn: ['navel', 'umbilicus'],
    aliasesAr: ['السرة', 'سرة'],
    questionEn: 'How many chicks had a navel defect?',
    questionAr: 'كم كتكوتًا لديه مشكلة في السرة؟',
  },
  pasgarBellyCount: {
    key: 'pasgarBellyCount',
    labelEn: 'Belly',
    labelAr: 'البطن',
    aliasesEn: ['belly', 'abdomen'],
    aliasesAr: ['البطن', 'بطن'],
    questionEn: 'How many chicks had a belly defect?',
    questionAr: 'كم كتكوتًا لديه مشكلة في البطن؟',
  },
  pasgarLegCount: {
    key: 'pasgarLegCount',
    labelEn: 'Legs',
    labelAr: 'الأرجل',
    aliasesEn: ['leg', 'legs'],
    aliasesAr: ['الرجل', 'الأرجل', 'رجل'],
    questionEn: 'How many chicks had a leg defect?',
    questionAr: 'كم كتكوتًا لديه مشكلة في الأرجل؟',
  },
  pasgarFeatherDevCount: {
    key: 'pasgarFeatherDevCount',
    labelEn: 'Feather development',
    labelAr: 'نمو الريش',
    aliasesEn: [
      'feather',
      'feathers',
      'feather development',
      'feather dev',
    ],
    aliasesAr: ['الريش', 'نمو الريش', 'تطور الريش'],
    questionEn: 'How many chicks had a feather-development defect?',
    questionAr: 'كم كتكوتًا لديه مشكلة في نمو الريش؟',
  },
}

export function getPasgarFieldDefinition(
  key: PasgarFieldKey,
): PasgarFieldDefinition {
  return fieldDefinitions[key]
}

export function validatePasgarCandidate(
  fieldKey: PasgarFieldKey,
  value: number,
  currentValues: PasgarWorkingValues,
): PasgarCandidateValidation {
  if (!Number.isInteger(value)) {
    return {
      ok: false,
      messageEn: 'Please send a whole number.',
      messageAr: 'من فضلك أرسل عددًا صحيحًا.',
    }
  }

  if (fieldKey === 'pasgarSampleSize') {
    if (value < 1 || value > 500) {
      return {
        ok: false,
        messageEn: 'The sample size must be between 1 and 500 chicks.',
        messageAr: 'يجب أن يكون حجم العينة بين 1 و500 كتكوت.',
      }
    }

    const incompatibleCount = defectFieldOrder.find((key) => {
      const count = currentValues[key]
      return count !== undefined && count > value
    })
    if (incompatibleCount) {
      const field = fieldDefinitions[incompatibleCount]
      return {
        ok: false,
        messageEn:
          `The sample cannot be ${value} because ${field.labelEn} is ` +
          `${currentValues[incompatibleCount]}.`,
        messageAr:
          `لا يمكن أن تكون العينة ${value} لأن قيمة ${field.labelAr} هي ` +
          `${currentValues[incompatibleCount]}.`,
      }
    }

    return { ok: true, value }
  }

  if (value < 0) {
    return {
      ok: false,
      messageEn: 'A defect count cannot be negative.',
      messageAr: 'لا يمكن أن يكون عدد العيوب سالبًا.',
    }
  }

  const sampleSize = currentValues.pasgarSampleSize
  if (sampleSize !== undefined && value > sampleSize) {
    return {
      ok: false,
      messageEn:
        `The defect count cannot be greater than the sample of ${sampleSize}.`,
      messageAr: `لا يمكن أن يزيد عدد العيوب عن حجم العينة ${sampleSize}.`,
    }
  }

  return { ok: true, value }
}

export function applyAllRemainingZero(
  currentValues: PasgarWorkingValues,
): PasgarWorkingValues {
  const next = { ...currentValues }
  for (const fieldKey of defectFieldOrder) {
    if (next[fieldKey] === undefined) next[fieldKey] = 0
  }
  return next
}

export function missingPasgarFields(
  values: PasgarWorkingValues,
): PasgarFieldKey[] {
  return pasgarFieldOrder.filter((fieldKey) => values[fieldKey] === undefined)
}

export function calculatePasgarSummary(
  values: PasgarWorkingValues,
): PasgarSummary {
  const missing = missingPasgarFields(values)
  if (missing.length > 0) {
    throw new Error(`Incomplete Pasgar values: ${missing.join(', ')}`)
  }

  const sampleSize = values.pasgarSampleSize as number
  const sampleValidation = validatePasgarCandidate(
    'pasgarSampleSize',
    sampleSize,
    values,
  )
  if (!sampleValidation.ok) throw new Error(sampleValidation.messageEn)

  const counts = {} as Record<PasgarDefectFieldKey, number>
  const percentages = {} as Record<PasgarDefectFieldKey, number>
  for (const fieldKey of defectFieldOrder) {
    const count = values[fieldKey] as number
    const validation = validatePasgarCandidate(fieldKey, count, values)
    if (!validation.ok) throw new Error(validation.messageEn)
    counts[fieldKey] = count
    percentages[fieldKey] = roundOne((count / sampleSize) * 100)
  }

  const scoredCount = [
    counts.pasgarReflexesCount,
    counts.pasgarBeakCount,
    counts.pasgarNavelCount,
    counts.pasgarBellyCount,
    counts.pasgarLegCount,
  ].reduce((sum, count) => sum + count, 0)
  const rawScore = ((sampleSize * 10) - scoredCount) / sampleSize

  return {
    schemaKey: PASGAR_SCHEMA_KEY,
    schemaVersion: PASGAR_SCHEMA_VERSION,
    sampleSize,
    counts,
    percentages,
    score: roundOne(Math.max(5, Math.min(10, rawScore))),
  }
}

export function formatPasgarSummary(
  summary: PasgarSummary,
  language: PasgarLanguage,
): string {
  if (language === 'mixed') {
    return `${formatPasgarSummary(summary, 'en')}\n\n` +
      formatPasgarSummary(summary, 'ar')
  }

  const isArabic = language === 'ar'
  const percentMark = isArabic ? '٪' : '%'
  const lines = [
    isArabic
      ? `العينة: ${summary.sampleSize} كتكوت`
      : `Sample: ${summary.sampleSize} chicks`,
  ]

  for (const fieldKey of defectFieldOrder) {
    const field = fieldDefinitions[fieldKey]
    const label = isArabic ? field.labelAr : field.labelEn
    lines.push(
      `${label}: ${summary.counts[fieldKey]} ` +
        `(${summary.percentages[fieldKey].toFixed(1)}${percentMark})`,
    )
  }

  lines.push(
    isArabic
      ? `درجة باسجار: ${summary.score.toFixed(1)}`
      : `Pasgar score: ${summary.score.toFixed(1)}`,
  )
  return lines.join('\n')
}

function roundOne(value: number): number {
  return Number(value.toFixed(1))
}
