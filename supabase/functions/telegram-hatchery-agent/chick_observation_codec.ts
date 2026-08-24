import type { AgentStationSchema } from '../_shared/station_registry.generated.ts'

export interface ChickQualityObservation {
  readonly id: string
  readonly sampleId: string
  readonly customerId: string
  readonly sessionId: string
  readonly domain: string
  readonly kind: 'series' | 'tally' | 'ordinal'
  readonly observationKey: string
  readonly ordinal: number | null
  readonly numericValue: number | null
  readonly textValue: string | null
  readonly unit: string
  readonly qualityFlags: '[]'
  readonly source: string | null
  readonly observedAt: string
  readonly createdAt: string
  readonly updatedAt: string
}

interface ObservationContext {
  readonly sampleId: string
  readonly customerId: string
  readonly sessionId: string
  readonly observedAt: string
  readonly source?: string | null
}

export function canRoundTripChickObservations(
  schema: AgentStationSchema,
  values: Readonly<Record<string, unknown>>,
): boolean {
  const relevant: Record<string, unknown> = {}
  for (const rawField of schema.fields) {
    const field = rawField as Record<string, unknown>
    const fieldKey = field.fieldKey as string
    if (!asObjectOrNull(field.observation) || !(fieldKey in values)) continue
    if (values[fieldKey] === null) continue
    const normalized = normalizeFieldValue(field, values[fieldKey])
    if (normalized === invalidValue) return false
    relevant[fieldKey] = normalized
  }
  if (Object.keys(relevant).length === 0) return false
  const observations = extractChickObservations(
    schema,
    {
      sampleId: 'round-trip-probe',
      customerId: 'round-trip-probe',
      sessionId: 'round-trip-probe',
      observedAt: '2000-01-01T00:00:00.000Z',
    },
    relevant,
  )
  return JSON.stringify(
    reconstructChickObservationValues(schema, observations),
  ) ===
    JSON.stringify(relevant)
}

export function overlayReconstructedChickValues(
  schema: AgentStationSchema,
  contextual: Readonly<Record<string, unknown>>,
  reconstructed: Readonly<Record<string, unknown>>,
): Readonly<Record<string, unknown>> {
  const result: Record<string, unknown> = { ...contextual }
  for (const rawField of schema.fields) {
    const field = rawField as Record<string, unknown>
    const fieldKey = field.fieldKey as string
    if (!(fieldKey in reconstructed)) continue
    const rawValue = reconstructed[fieldKey]
    const descriptor = asObjectOrNull(field.observation)
    const ignored = Array.isArray(descriptor?.ignoredProperties)
      ? descriptor.ignoredProperties.filter((item): item is string =>
        typeof item === 'string'
      )
      : []
    const keyProperty = typeof descriptor?.keyProperty === 'string'
      ? descriptor.keyProperty
      : null
    if (!keyProperty || ignored.length === 0 || !Array.isArray(rawValue)) {
      result[fieldKey] = rawValue
      continue
    }
    const contextualByKey = new Map<string, Record<string, unknown>>()
    for (const rawItem of asList(contextual[fieldKey])) {
      const item = asObjectOrNull(rawItem)
      const itemKey = item?.[keyProperty]
      if (item && typeof itemKey === 'string') {
        contextualByKey.set(itemKey, item)
      }
    }
    result[fieldKey] = rawValue.flatMap((rawItem) => {
      const item = asObjectOrNull(rawItem)
      if (!item) return []
      const cached = contextualByKey.get(String(item[keyProperty] ?? ''))
      return [{
        ...Object.fromEntries(
          ignored.filter((key) => cached && key in cached).map((key) => [
            key,
            cached![key],
          ]),
        ),
        ...item,
      }]
    })
  }
  return result
}

export function extractChickObservations(
  schema: AgentStationSchema,
  context: ObservationContext,
  values: Readonly<Record<string, unknown>>,
): readonly ChickQualityObservation[] {
  const result: ChickQualityObservation[] = []
  for (const rawField of schema.fields) {
    const field = rawField as Record<string, unknown>
    const fieldKey = field.fieldKey as string
    const descriptor = asObjectOrNull(field.observation)
    if (!descriptor || !(fieldKey in values) || values[fieldKey] === null) {
      continue
    }
    const kind = descriptor.kind as ChickQualityObservation['kind']
    const unit = field.unit as string
    const add = (
      observationKey: string,
      ordinal: number | null,
      value: unknown,
    ) => {
      const numericValue = typeof value === 'number' && Number.isFinite(value)
        ? value
        : null
      const textValue = typeof value === 'string' ? value : null
      if (numericValue === null && textValue === null) return
      result.push({
        id: stableChickObservationId(
          context.sampleId,
          schema.schemaKey,
          kind,
          observationKey,
          ordinal,
        ),
        sampleId: context.sampleId,
        customerId: context.customerId,
        sessionId: context.sessionId,
        domain: schema.schemaKey,
        kind,
        observationKey,
        ordinal,
        numericValue,
        textValue,
        unit,
        qualityFlags: '[]',
        source: context.source ?? null,
        observedAt: context.observedAt,
        createdAt: context.observedAt,
        updatedAt: context.observedAt,
      })
    }

    const value = values[fieldKey]
    if (field.type === 'number_list') {
      asList(value).forEach((item, index) =>
        add(descriptor.key as string, index, item)
      )
      continue
    }
    if (field.type === 'object_list') {
      const properties = asObjectOrNull(descriptor.properties)
      if (properties) {
        asList(value).forEach((rawItem, index) => {
          const item = asObjectOrNull(rawItem)
          if (!item) return
          for (const [propertyKey, rawProperty] of Object.entries(properties)) {
            const property = asObject(rawProperty)
            add(property.key as string, index, item[propertyKey])
          }
        })
        continue
      }
      const keyProperty = descriptor.keyProperty as string
      const valueProperty = descriptor.valueProperty as string
      const prefix = descriptor.keyPrefix as string
      const presenceKey = descriptor.presenceKey as string | undefined
      if (presenceKey) add(presenceKey, null, 0)
      asList(value).forEach((rawItem, index) => {
        const item = asObjectOrNull(rawItem)
        const itemKey = item?.[keyProperty]
        if (!item || typeof itemKey !== 'string' || itemKey.length === 0) {
          return
        }
        add(`${prefix}${itemKey}`, index, item[valueProperty])
      })
      continue
    }
    add(descriptor.key as string, null, value)
  }
  return result.sort(compareObservations)
}

export function reconstructChickObservationValues(
  schema: AgentStationSchema,
  source: readonly ChickQualityObservation[],
): Readonly<Record<string, unknown>> {
  const observations = source
    .filter((item) => item.domain === schema.schemaKey)
    .slice()
    .sort(compareObservations)
  const result: Record<string, unknown> = {}
  for (const rawField of schema.fields) {
    const field = rawField as Record<string, unknown>
    const fieldKey = field.fieldKey as string
    const descriptor = asObjectOrNull(field.observation)
    if (!descriptor) continue
    const kind = descriptor.kind as string
    const matchingKind = observations.filter((item) =>
      item.kind === kind && matchesField(schema, field, item)
    )
    if (field.type === 'number_list') {
      const matching = matchingKind
        .filter((item) => item.observationKey === descriptor.key)
        .slice()
        .sort((left, right) => (left.ordinal ?? -1) - (right.ordinal ?? -1))
      if (
        hasDenseOrdinals(matching) &&
        matching.every((item) => item.numericValue !== null)
      ) {
        result[fieldKey] = matching.map((item) => item.numericValue)
      }
      continue
    }
    if (field.type === 'object_list') {
      const properties = asObjectOrNull(descriptor.properties)
      if (properties) {
        const byOrdinal = new Map<number, Record<string, unknown>>()
        for (const [propertyKey, rawProperty] of Object.entries(properties)) {
          const property = asObject(rawProperty)
          for (
            const item of matchingKind.filter((candidate) =>
              candidate.observationKey === property.key
            )
          ) {
            if (item.ordinal === null) continue
            const value = item.numericValue ?? item.textValue
            const row = byOrdinal.get(item.ordinal) ?? {}
            row[propertyKey] = value
            byOrdinal.set(item.ordinal, row)
          }
        }
        if (byOrdinal.size > 0) {
          const entries = [...byOrdinal.entries()].sort(([left], [right]) =>
            left - right
          )
          const requiredProperties = Object.keys(properties)
          if (
            isDense(entries.map(([ordinal]) => ordinal)) &&
            entries.every(([, item]) =>
              requiredProperties.every((property) => property in item)
            )
          ) {
            result[fieldKey] = entries.map(([, item]) => item)
          }
        }
        continue
      }
      const prefix = descriptor.keyPrefix as string
      const presenceKey = descriptor.presenceKey as string | undefined
      const keyProperty = descriptor.keyProperty as string
      const valueProperty = descriptor.valueProperty as string
      const validation = asObject(field.validation)
      const itemSchema = asObject(validation.itemSchema)
      const itemProperties = asObject(itemSchema.properties)
      const valueSchema = asObject(itemProperties[valueProperty])
      const keyed = matchingKind
        .filter((item) =>
          item.observationKey.startsWith(prefix) &&
          item.observationKey !== presenceKey
        )
        .slice()
        .sort((left, right) => (left.ordinal ?? -1) - (right.ordinal ?? -1))
      if (keyed.length > 0) {
        if (
          hasDenseOrdinals(keyed) &&
          keyed.every((item) =>
            item.numericValue !== null || item.textValue !== null
          )
        ) {
          result[fieldKey] = keyed.map((item) => ({
            [keyProperty]: item.observationKey.slice(prefix.length),
            [valueProperty]: valueSchema.type === 'integer'
              ? Math.trunc(item.numericValue!)
              : item.numericValue ?? item.textValue,
          }))
        }
      } else if (
        presenceKey &&
        matchingKind.some((item) => item.observationKey === presenceKey)
      ) {
        result[fieldKey] = []
      }
      continue
    }
    const item = matchingKind.find((candidate) =>
      candidate.observationKey === descriptor.key &&
      candidate.ordinal === null
    )
    if (!item) continue
    result[fieldKey] = field.type === 'string'
      ? item.textValue
      : field.type === 'integer'
      ? Math.trunc(item.numericValue!)
      : item.numericValue
  }
  return result
}

export function stableChickObservationId(
  sampleId: string,
  domain: string,
  kind: string,
  key: string,
  ordinal: number | null,
): string {
  const canonical = JSON.stringify([sampleId, domain, kind, key, ordinal])
  const bytes = new TextEncoder().encode(canonical)
  const binary = Array.from(bytes, (byte) => String.fromCharCode(byte)).join(
    '',
  )
  return `obs_${
    btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
  }`
}

function compareObservations(
  left: ChickQualityObservation,
  right: ChickQualityObservation,
): number {
  return compareCodeUnits(left.kind, right.kind) ||
    compareCodeUnits(left.observationKey, right.observationKey) ||
    (left.ordinal ?? -1) - (right.ordinal ?? -1)
}

function compareCodeUnits(left: string, right: string): number {
  if (left === right) return 0
  return left < right ? -1 : 1
}

function asObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('Expected object')
  }
  return value as Record<string, unknown>
}

function asObjectOrNull(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function asList(value: unknown): readonly unknown[] {
  if (Array.isArray(value)) return value
  if (typeof value !== 'string') return []
  try {
    const decoded = JSON.parse(value)
    return Array.isArray(decoded) ? decoded : []
  } catch (_) {
    return []
  }
}

const invalidValue = Symbol('invalid-value')

function normalizeFieldValue(
  field: Readonly<Record<string, unknown>>,
  value: unknown,
): unknown | typeof invalidValue {
  if (field.type === 'integer') {
    return typeof value === 'number' && Number.isInteger(value)
      ? value
      : invalidValue
  }
  if (field.type === 'number') {
    return typeof value === 'number' && Number.isFinite(value)
      ? value
      : invalidValue
  }
  if (field.type === 'string') {
    return typeof value === 'string' ? value : invalidValue
  }
  if (!Array.isArray(value) && typeof value !== 'string') return invalidValue
  const list = asList(value)
  if (field.type === 'number_list') {
    return list.every((item) =>
        typeof item === 'number' && Number.isFinite(item)
      )
      ? [...list]
      : invalidValue
  }
  if (field.type !== 'object_list') return invalidValue
  const validation = asObject(field.validation)
  const itemSchema = asObject(validation.itemSchema)
  const required = itemSchema.required as readonly string[]
  const properties = asObject(itemSchema.properties)
  const descriptor = asObject(field.observation)
  const ignored = new Set(
    Array.isArray(descriptor.ignoredProperties)
      ? descriptor.ignoredProperties.filter((item): item is string =>
        typeof item === 'string'
      )
      : [],
  )
  const normalized: Record<string, unknown>[] = []
  for (const rawItem of list) {
    const item = asObjectOrNull(rawItem)
    if (!item || required.some((key) => !(key in item))) return invalidValue
    if (
      Object.keys(item).some((key) => !(key in properties) && !ignored.has(key))
    ) return invalidValue
    const normalizedItem: Record<string, unknown> = {}
    for (const [propertyKey, rawDefinition] of Object.entries(properties)) {
      if (!(propertyKey in item)) continue
      const definition = asObject(rawDefinition)
      const propertyValue = item[propertyKey]
      if (
        definition.type === 'integer' &&
        typeof propertyValue === 'number' &&
        Number.isInteger(propertyValue)
      ) {
        normalizedItem[propertyKey] = propertyValue
      } else if (
        definition.type === 'number' &&
        typeof propertyValue === 'number' &&
        Number.isFinite(propertyValue)
      ) {
        normalizedItem[propertyKey] = propertyValue
      } else if (
        definition.type === 'string' && typeof propertyValue === 'string'
      ) {
        normalizedItem[propertyKey] = propertyValue
      } else {
        return invalidValue
      }
    }
    normalized.push(normalizedItem)
  }
  return normalized
}

function hasDenseOrdinals(
  items: readonly ChickQualityObservation[],
): boolean {
  return items.length > 0 &&
    items.every((item) => item.ordinal !== null) &&
    isDense(items.map((item) => item.ordinal!))
}

function isDense(ordinals: readonly number[]): boolean {
  return ordinals.length > 0 &&
    ordinals.every((ordinal, index) => ordinal === index)
}

function matchesField(
  schema: AgentStationSchema,
  field: Readonly<Record<string, unknown>>,
  item: ChickQualityObservation,
): boolean {
  const descriptor = asObjectOrNull(field.observation)
  if (
    !descriptor || item.domain !== schema.schemaKey ||
    item.kind !== descriptor.kind || item.unit !== field.unit ||
    item.id !== stableChickObservationId(
        item.sampleId,
        item.domain,
        item.kind,
        item.observationKey,
        item.ordinal,
      )
  ) return false
  const numeric = (integer = false) =>
    item.numericValue !== null && item.textValue === null &&
    (!integer || Number.isInteger(item.numericValue))
  const text = () => item.textValue !== null && item.numericValue === null

  if (field.type === 'number_list') {
    return item.observationKey === descriptor.key && item.ordinal !== null &&
      numeric()
  }
  if (field.type === 'object_list') {
    const properties = asObjectOrNull(descriptor.properties)
    if (properties) {
      for (const rawProperty of Object.values(properties)) {
        const property = asObject(rawProperty)
        if (
          item.observationKey === property.key && item.ordinal !== null
        ) return property.valueType === 'text' ? text() : numeric()
      }
      return false
    }
    const presenceKey = typeof descriptor.presenceKey === 'string'
      ? descriptor.presenceKey
      : null
    if (item.observationKey === presenceKey) {
      return item.ordinal === null && numeric() && item.numericValue === 0
    }
    const prefix = descriptor.keyPrefix as string
    if (
      !item.observationKey.startsWith(prefix) ||
      item.observationKey.length === prefix.length || item.ordinal === null
    ) return false
    const validation = asObject(field.validation)
    const itemSchema = asObject(validation.itemSchema)
    const itemProperties = asObject(itemSchema.properties)
    const valueSchema = asObject(
      itemProperties[descriptor.valueProperty as string],
    )
    return valueSchema.type === 'string'
      ? text()
      : numeric(valueSchema.type === 'integer')
  }
  if (item.observationKey !== descriptor.key || item.ordinal !== null) {
    return false
  }
  return field.type === 'string' ? text() : numeric(field.type === 'integer')
}
