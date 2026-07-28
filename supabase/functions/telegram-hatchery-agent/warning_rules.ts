export type HatcheryWarningKind =
  | 'historicalChange'
  | 'bmkContext'
  | 'missingBmk'
  | 'missingFlockAge'

export type HatcheryWarningSeverity = 'info' | 'review' | 'critical'

export interface HatcheryRowWarning {
  kind: HatcheryWarningKind
  severity: HatcheryWarningSeverity
  messageEn: string
  messageAr: string
  previousPct: number | null
  currentPct: number | null
  bmkPct: number | null
  flockAgeWeeks: number | null
}

export function buildHistoricalWarning(params: {
  currentPct: number
  previousPct: number | null
  thresholdPoints?: number
}): HatcheryRowWarning | null {
  if (params.previousPct === null) return null

  const threshold = positiveNumber(params.thresholdPoints) ?? 3
  const absoluteChange = Math.abs(params.currentPct - params.previousPct)
  if (absoluteChange + percentagePointComparisonTolerance < threshold) {
    return null
  }

  return {
    kind: 'historicalChange',
    severity: 'review',
    messageEn: `Hatchability changed from ${pct(params.previousPct)}% to ` +
      `${pct(params.currentPct)}% ` +
      `(${pct(absoluteChange)} percentage points).`,
    messageAr: `تغيرت قابلية الفقس من ${pct(params.previousPct)}٪ إلى ` +
      `${pct(params.currentPct)}٪ ` +
      `(${pct(absoluteChange)} نقطة مئوية).`,
    previousPct: params.previousPct,
    currentPct: params.currentPct,
    bmkPct: null,
    flockAgeWeeks: null,
  }
}

export function buildBmkWarning(params: {
  currentPct: number
  previousPct: number | null
  bmkPct: number | null
  flockAgeWeeks: number | null
}): HatcheryRowWarning | null {
  const isRising = params.previousPct !== null &&
    params.currentPct > params.previousPct
  if (!isRising) return null

  if (positiveInteger(params.flockAgeWeeks) === null) {
    return {
      kind: 'missingFlockAge',
      severity: 'info',
      messageEn:
        'Flock age is needed to compare this rising hatchability result with BMK.',
      messageAr:
        'يلزم عمر القطيع لمقارنة نتيجة قابلية الفقس المرتفعة هذه بالمعيار.',
      previousPct: params.previousPct,
      currentPct: params.currentPct,
      bmkPct: null,
      flockAgeWeeks: null,
    }
  }

  if (params.bmkPct === null) {
    return {
      kind: 'missingBmk',
      severity: 'info',
      messageEn:
        'No hatchability BMK is available for this breed and flock age.',
      messageAr: 'لا يتوفر معيار قابلية فقس لهذه السلالة وعمر القطيع.',
      previousPct: params.previousPct,
      currentPct: params.currentPct,
      bmkPct: null,
      flockAgeWeeks: params.flockAgeWeeks,
    }
  }

  if (params.bmkPct < params.currentPct) return null

  return {
    kind: 'bmkContext',
    severity: 'info',
    messageEn: `The hatchability increase may be consistent with the BMK of ` +
      `${pct(params.bmkPct)}% at ${params.flockAgeWeeks} weeks.`,
    messageAr: `قد تكون زيادة قابلية الفقس متسقة مع المعيار البالغ ` +
      `${pct(params.bmkPct)}٪ عند عمر ${params.flockAgeWeeks} أسبوعًا.`,
    previousPct: params.previousPct,
    currentPct: params.currentPct,
    bmkPct: params.bmkPct,
    flockAgeWeeks: params.flockAgeWeeks,
  }
}

function pct(value: number): string {
  return value.toFixed(1)
}

function positiveNumber(value: number | undefined): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value > 0
    ? value
    : null
}

function positiveInteger(value: number | null): number | null {
  return Number.isInteger(value) && (value as number) > 0 ? value : null
}

const percentagePointComparisonTolerance = 1e-12
