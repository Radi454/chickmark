import type { AgentStationSchema } from '../_shared/station_registry.generated.ts'
import {
  cvPercent,
  pasgarScore,
  percentOf,
  roundTo,
  uniformityPercent,
} from './agent_metrics.ts'

export interface StationValueIssue {
  fieldKey: string
  code: string
  itemIndex?: number
  propertyKey?: string
}

export interface StationValueValidation {
  valid: boolean
  missing: string[]
  issues: StationValueIssue[]
}

export interface StationPersistencePayload {
  localTable: string
  remoteTable: string
  values: Record<string, unknown>
}

export interface DerivedStationAdapter {
  calculations: Record<string, unknown>
  persistence: StationPersistencePayload[]
}

export function validateStationValueSet(
  schema: AgentStationSchema,
  values: Readonly<Record<string, unknown>>,
): StationValueValidation {
  const fields = schema.fields as readonly Record<string, unknown>[]
  const fieldsByKey = new Map(
    fields.map((field) => [field.fieldKey as string, field]),
  )
  const missing = schema.completion.requiredFieldKeys.filter((fieldKey) =>
    values[fieldKey] === undefined || values[fieldKey] === null
  )
  for (const field of fields) {
    const validation = record(field.validation)
    const dependency = text(validation.requiredWhenPositiveFieldKey)
    if (
      dependency && positiveNumber(values[dependency]) &&
      (values[field.fieldKey as string] === undefined ||
        values[field.fieldKey as string] === null ||
        values[field.fieldKey as string] === '')
    ) {
      missing.push(field.fieldKey as string)
    }
  }

  const issues: StationValueIssue[] = []
  for (const [fieldKey, value] of Object.entries(values)) {
    const field = fieldsByKey.get(fieldKey)
    if (!field) {
      issues.push({ fieldKey, code: 'unknown_field' })
      continue
    }
    if (value === null || value === undefined) continue
    issues.push(...validateField(field, value, values))
  }

  return {
    valid: missing.length === 0 && issues.length === 0,
    missing: [...new Set(missing)],
    issues,
  }
}

export function deriveStationAdapter(
  schema: AgentStationSchema,
  values: Readonly<Record<string, unknown>>,
): DerivedStationAdapter {
  const validation = validateStationValueSet(schema, values)
  if (!validation.valid) {
    throw new Error('Station values are not valid')
  }
  const calculations = calculateStationValues(schema, values)
  const payloadValues: Record<string, unknown> = {}
  for (const field of schema.fields as readonly Record<string, unknown>[]) {
    const fieldKey = field.fieldKey as string
    if (!(fieldKey in values)) continue
    const remoteColumn = text(record(field.persistence).remoteColumn)
    if (!remoteColumn) continue
    payloadValues[remoteColumn] = encodePersistenceValue(
      field,
      values[fieldKey],
    )
  }
  for (
    const calculation of schema.calculations as readonly Record<
      string,
      unknown
    >[]
  ) {
    const fieldKey = calculation.fieldKey as string
    const remoteColumn = text(record(calculation.persistence).remoteColumn)
    if (!remoteColumn || !(fieldKey in calculations)) continue
    payloadValues[remoteColumn] = calculations[fieldKey]
  }
  return {
    calculations,
    persistence: schema.persistence.map((mapping) => ({
      localTable: mapping.localTable,
      remoteTable: mapping.remoteTable,
      values: structuredClone(payloadValues),
    })),
  }
}

export function calculateStationValues(
  schema: AgentStationSchema,
  values: Readonly<Record<string, unknown>>,
): Record<string, unknown> {
  const calculated: Record<string, unknown> = {}
  const available: Record<string, unknown> = { ...values }
  for (
    const calculation of schema.calculations as readonly Record<
      string,
      unknown
    >[]
  ) {
    const fieldKey = calculation.fieldKey as string
    const kind = calculation.kind as string
    const inputKeys = Array.isArray(calculation.inputFieldKeys)
      ? calculation.inputFieldKeys.filter((key): key is string =>
        typeof key === 'string'
      )
      : []
    const inputs = inputKeys.map((key) => available[key])
    const value = calculate(kind, inputs)
    calculated[fieldKey] = value
    available[fieldKey] = value
  }
  return calculated
}

function calculate(kind: string, inputs: readonly unknown[]): unknown {
  switch (kind) {
    case 'pasgar_score':
      return pasgarScore(
        inputs[0] as number,
        inputs.slice(1).map((value) => value as number),
      )
    case 'percent_of':
      return percentOf(inputs[0] as number, inputs[1] as number)
    case 'sum':
      return inputs.reduce<number>(
        (sum, value) => sum + (value as number),
        0,
      )
    case 'series_sample_size':
      return numberList(inputs[0]).length
    case 'series_average':
      return average(numberList(inputs[0]))
    case 'series_cv':
      return cvPercent(numberList(inputs[0]))
    case 'series_uniformity_10pct': {
      const values = numberList(inputs[0])
      const mean = rawAverage(values)
      return uniformityPercent(values, mean * 0.9, mean * 1.1)
    }
    case 'yfbm_entry_count':
      return objectList(inputs[0]).length
    case 'yfbm_average_pct': {
      const percentages = yfbmPercentages(inputs[0])
      return average(percentages)
    }
    case 'yfbm_cv_pct':
      return cvPercent(yfbmPercentages(inputs[0]))
    case 'culled_affected_pct': {
      const total = inputs[0] as number
      const affected = objectList(inputs[1]).reduce(
        (sum, item) => sum + (item.count as number),
        0,
      )
      return percentOf(affected, total)
    }
    case 'culled_top_category': {
      const top = topCulledDefect(inputs[0])
      return top?.category ?? null
    }
    case 'culled_top_subtype': {
      const top = topCulledDefect(inputs[0])
      return top?.subtype ?? null
    }
    case 'fertility_from_infertile': {
      const total = inputs[0] as number
      const infertile = inputs[1] as number
      return percentOf(total - infertile, total)
    }
    case 'hof':
      return percentOf(inputs[0] as number, inputs[1] as number, {
        allowAbove100: true,
      })
    default:
      throw new Error(`Unsupported station calculation kind: ${kind}`)
  }
}

function validateField(
  field: Record<string, unknown>,
  value: unknown,
  allValues: Readonly<Record<string, unknown>>,
): StationValueIssue[] {
  const fieldKey = field.fieldKey as string
  const type = field.type
  const validation = record(field.validation)
  const issues: StationValueIssue[] = []
  const issue = (code: string) => issues.push({ fieldKey, code })

  if (type === 'integer' && !Number.isInteger(value)) issue('invalid_type')
  if (
    type === 'number' &&
    (typeof value !== 'number' || !Number.isFinite(value))
  ) issue('invalid_type')
  if (type === 'string' && typeof value !== 'string') issue('invalid_type')
  if (type === 'boolean' && typeof value !== 'boolean') issue('invalid_type')
  if (
    type === 'number_list' &&
    (!Array.isArray(value) ||
      value.some((item) => typeof item !== 'number' || !Number.isFinite(item)))
  ) issue('invalid_type')
  if (
    type === 'object_list' &&
    (!Array.isArray(value) || value.some((item) => !isRecord(item)))
  ) issue('invalid_type')
  if (issues.length > 0) return issues

  if (value === 0 && field.explicitZero !== true) issue('zero_not_allowed')
  if (typeof value === 'number') {
    if (typeof validation.min === 'number' && value < validation.min) {
      issue('below_minimum')
    }
    if (typeof validation.max === 'number' && value > validation.max) {
      issue('above_maximum')
    }
    const maximumKey = text(validation.maxFieldKey)
    if (
      maximumKey && typeof allValues[maximumKey] === 'number' &&
      value > allValues[maximumKey]
    ) issue('above_dynamic_maximum')
  }
  if (typeof value === 'string') {
    if (
      typeof validation.minLength === 'number' &&
      value.trim().length < validation.minLength
    ) issue('too_short')
  }
  if (Array.isArray(value)) {
    if (
      typeof validation.minItems === 'number' &&
      value.length < validation.minItems
    ) issue('too_few_items')
    if (
      typeof validation.maxItems === 'number' &&
      value.length > validation.maxItems
    ) issue('too_many_items')
  }
  if (type === 'number_list' && Array.isArray(value)) {
    if (
      value.some((item) =>
        typeof validation.itemMin === 'number' && item < validation.itemMin ||
        typeof validation.itemMax === 'number' && item > validation.itemMax
      )
    ) issue('item_out_of_range')
  }
  if (type === 'object_list' && Array.isArray(value)) {
    issues.push(...validateObjectItems(fieldKey, value, validation, allValues))
  }
  if (
    Array.isArray(validation.choices) &&
    !validation.choices.includes(value)
  ) issue('invalid_choice')
  return issues
}

function validateObjectItems(
  fieldKey: string,
  items: unknown[],
  validation: Record<string, unknown>,
  allValues: Readonly<Record<string, unknown>>,
): StationValueIssue[] {
  const schema = record(validation.itemSchema)
  const required = Array.isArray(schema.required)
    ? schema.required.filter((item): item is string => typeof item === 'string')
    : []
  const properties = record(schema.properties)
  const issues: StationValueIssue[] = []
  for (let index = 0; index < items.length; index++) {
    const item = items[index] as Record<string, unknown>
    for (const propertyKey of required) {
      if (item[propertyKey] === undefined || item[propertyKey] === null) {
        issues.push({
          fieldKey,
          code: 'item_required',
          itemIndex: index,
          propertyKey,
        })
      }
    }
    for (const [propertyKey, value] of Object.entries(item)) {
      const rule = record(properties[propertyKey])
      if (Object.keys(rule).length === 0) {
        issues.push({
          fieldKey,
          code: 'unknown_item_property',
          itemIndex: index,
          propertyKey,
        })
        continue
      }
      const type = rule.type
      if (
        type === 'integer' && !Number.isInteger(value) ||
        type === 'number' &&
          (typeof value !== 'number' || !Number.isFinite(value)) ||
        type === 'string' && typeof value !== 'string'
      ) {
        issues.push({
          fieldKey,
          code: 'invalid_item_type',
          itemIndex: index,
          propertyKey,
        })
        continue
      }
      if (typeof value === 'number') {
        if (typeof rule.min === 'number' && value < rule.min) {
          issues.push({
            fieldKey,
            code: 'item_below_minimum',
            itemIndex: index,
            propertyKey,
          })
        }
        const maximumKey = text(rule.maxFieldKey)
        const maximumPropertyKey = text(rule.maxPropertyKey)
        const maximum = maximumKey
          ? allValues[maximumKey]
          : maximumPropertyKey
          ? item[maximumPropertyKey]
          : rule.max
        if (typeof maximum === 'number' && value > maximum) {
          issues.push({
            fieldKey,
            code: 'item_above_maximum',
            itemIndex: index,
            propertyKey,
          })
        }
      }
      if (Array.isArray(rule.choices) && !rule.choices.includes(value)) {
        issues.push({
          fieldKey,
          code: 'invalid_item_choice',
          itemIndex: index,
          propertyKey,
        })
      }
    }
  }
  return issues
}

function encodePersistenceValue(
  field: Record<string, unknown>,
  value: unknown,
): unknown {
  if (field.type === 'number_list' || field.type === 'object_list') {
    return JSON.stringify(value)
  }
  if (
    field.type === 'boolean' &&
    record(field.persistence).encoding === 'integer_boolean'
  ) return value ? 1 : 0
  return value
}

function numberList(value: unknown): number[] {
  return Array.isArray(value)
    ? value.filter((item): item is number =>
      typeof item === 'number' && Number.isFinite(item)
    )
    : []
}

function objectList(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter(isRecord) : []
}

function rawAverage(values: readonly number[]): number {
  return values.length === 0
    ? 0
    : values.reduce((sum, value) => sum + value, 0) / values.length
}

function average(values: readonly number[]): number {
  return roundTo(rawAverage(values))
}

function yfbmPercentages(value: unknown): number[] {
  return objectList(value).map((entry) =>
    percentOf(entry.yolkWeight as number, entry.chickWeight as number)
  ).filter((value): value is number => value !== null)
}

function topCulledDefect(value: unknown): CulledDefect | null {
  const entries = objectList(value)
  let top: { defect: CulledDefect; count: number } | null = null
  for (const entry of entries) {
    const defect = culledDefects.get(entry.id as string)
    const count = entry.count as number
    if (!defect || !Number.isFinite(count) || count <= 0) continue
    if (!top || count > top.count) top = { defect, count }
  }
  return top?.defect ?? null
}

interface CulledDefect {
  category: string
  subtype: string
}

const culledDefects = new Map<string, CulledDefect>([
  ['navel_open_unhealed', {
    category: 'Navel',
    subtype: 'Open / unhealed navel',
  }],
  ['navel_string', { category: 'Navel', subtype: 'String navel' }],
  ['navel_black_button', { category: 'Navel', subtype: 'Black button' }],
  ['navel_residual_yolk_large_abdomen', {
    category: 'Belly',
    subtype: 'Residual yolk / large abdomen',
  }],
  ['sticky_sticky_chick', { category: 'Sticky', subtype: 'Sticky chick' }],
  ['sticky_dehydrated_burned_chick', {
    category: 'Dehydrated',
    subtype: 'Dehydrated / burned chick',
  }],
  ['legs_spraddle_leg', { category: 'Legs', subtype: 'Spraddle leg' }],
  ['legs_curled_toes', { category: 'Legs', subtype: 'Curled toes' }],
  ['legs_twisted_legs_feet', {
    category: 'Legs',
    subtype: 'Twisted legs / feet',
  }],
  ['legs_red_hocks', { category: 'Legs', subtype: 'Red hocks' }],
  ['head_crossed_crooked_beak', {
    category: 'Head',
    subtype: 'Crossed beak / crooked beak',
  }],
  ['head_missing_eye_one_eye', {
    category: 'Head',
    subtype: 'Missing eye / one eye',
  }],
  ['head_exposed_brain', { category: 'Head', subtype: 'Exposed brain' }],
  ['neuro_stargazer_nervous_signs', {
    category: 'Neuro',
    subtype: 'Stargazer / nervous signs',
  }],
  ['neuro_wry_neck', { category: 'Neuro', subtype: 'Wry neck' }],
  ['small_weak_small_chick', {
    category: 'Small/Weak',
    subtype: 'Small chick',
  }],
  ['hair_chick_sparse_down', {
    category: 'Hair Chick',
    subtype: 'Hair chick / sparse down',
  }],
])

function positiveNumber(value: unknown): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value > 0
}

function record(value: unknown): Record<string, unknown> {
  return isRecord(value) ? value : {}
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value : null
}
