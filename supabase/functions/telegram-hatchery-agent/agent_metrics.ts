export interface RatioAggregate {
  value: number | null
  observedRows: number
  numerator: number | null
  denominator: number | null
}

export interface WeightedAggregate {
  value: number | null
  observedRows: number
  weight: number | null
}

export function roundTo(value: number, decimalPlaces = 1): number {
  return Number(value.toFixed(decimalPlaces))
}

export function percentOf(
  count: number | null | undefined,
  total: number | null | undefined,
  options: { decimalPlaces?: number; allowAbove100?: boolean } = {},
): number | null {
  if (
    count === null || count === undefined || total === null ||
    total === undefined
  ) {
    return null
  }
  if (
    !Number.isFinite(count) || !Number.isFinite(total) || count < 0 ||
    total <= 0
  ) {
    return null
  }
  const percent = count / total * 100
  if (!options.allowAbove100 && percent > 100) return null
  return roundTo(percent, options.decimalPlaces ?? 1)
}

export function ratioOfSums(
  rows: readonly Record<string, unknown>[],
  numeratorKey: string,
  denominatorKey: string,
): RatioAggregate {
  let numerator = 0
  let denominator = 0
  let observedRows = 0
  for (const row of rows) {
    const nextNumerator = finiteNumber(row[numeratorKey])
    const nextDenominator = finiteNumber(row[denominatorKey])
    if (
      nextNumerator === null || nextNumerator < 0 ||
      nextDenominator === null || nextDenominator <= 0
    ) continue
    numerator += nextNumerator
    denominator += nextDenominator
    observedRows += 1
  }
  if (observedRows === 0 || denominator <= 0) {
    return {
      value: null,
      observedRows: 0,
      numerator: null,
      denominator: null,
    }
  }
  return {
    value: percentOf(numerator, denominator, { allowAbove100: true }),
    observedRows,
    numerator,
    denominator,
  }
}

export function sampleWeightedMean(
  rows: readonly Record<string, unknown>[],
  valueKey: string,
  weightKey: string,
): WeightedAggregate {
  let weightedTotal = 0
  let weight = 0
  let observedRows = 0
  for (const row of rows) {
    const value = finiteNumber(row[valueKey])
    const nextWeight = finiteNumber(row[weightKey])
    if (value === null || nextWeight === null || nextWeight <= 0) continue
    weightedTotal += value * nextWeight
    weight += nextWeight
    observedRows += 1
  }
  if (observedRows === 0 || weight <= 0) {
    return { value: null, observedRows: 0, weight: null }
  }
  return {
    value: roundTo(weightedTotal / weight),
    observedRows,
    weight,
  }
}

export function cvPercent(
  values: readonly number[],
  options: { decimalPlaces?: number; sample?: boolean } = {},
): number {
  if (values.length < 2) return 0
  const average = values.reduce((sum, value) => sum + value, 0) / values.length
  if (average === 0) return 0
  const sample = options.sample ?? true
  if (sample && values.length < 2) return 0
  const denominator = sample ? values.length - 1 : values.length
  const variance = values.reduce(
    (sum, value) => sum + Math.pow(value - average, 2),
    0,
  ) / denominator
  return roundTo(
    Math.sqrt(variance) / average * 100,
    options.decimalPlaces ?? 1,
  )
}

export function uniformityPercent(
  values: readonly number[],
  minimum: number,
  maximum: number,
): number {
  if (values.length === 0) return 0
  const inRange =
    values.filter((value) => value >= minimum && value <= maximum).length
  return percentOf(inRange, values.length) ?? 0
}

export function pasgarScore(
  sampleSize: number,
  defectCounts: readonly number[],
): number {
  if (sampleSize <= 0) return 0
  const defects = defectCounts.slice(0, 5).reduce(
    (sum, count) => sum + Math.min(sampleSize, Math.max(0, count)),
    0,
  )
  const score = (sampleSize * 10 - defects) / sampleSize
  return roundTo(Math.min(10, Math.max(5, score)))
}

export function fertility(fertile: number, clear: number): number {
  const total = fertile + clear
  if (total === 0) return 100
  return percentOf(fertile, total) ?? 0
}

export function hatchability(hatched: number, total: number): number {
  if (total === 0) return 0
  return percentOf(hatched, total) ?? 0
}

export function hof(hatchabilityValue: number, fertilityValue: number): number {
  if (fertilityValue === 0) return 0
  return percentOf(hatchabilityValue, fertilityValue, {
    allowAbove100: true,
  }) ?? 0
}

export function configuredWarningDelta(
  current: number | null | undefined,
  previous: number | null | undefined,
  threshold: number,
): {
  triggered: boolean
  delta: number | null
  direction: 'increase' | 'decrease' | null
} {
  if (
    finiteNumber(current) === null || finiteNumber(previous) === null ||
    !Number.isFinite(threshold) || threshold < 0
  ) {
    return { triggered: false, delta: null, direction: null }
  }
  const delta = roundTo(current! - previous!)
  return {
    triggered: Math.abs(delta) >= threshold,
    delta,
    direction: delta > 0 ? 'increase' : delta < 0 ? 'decrease' : null,
  }
}

function finiteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}
