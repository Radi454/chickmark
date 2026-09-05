// Benchmark (BMK) read tools.
//
// bmk_breeds and bmk_egg_breakout are global reference tables with
// read-all-authenticated policies, so they are read with no customer filter.
// Operational standards are scoped -- see get_operational_standards.

import type {
  AgentToolExecutionInput,
  AgentToolName,
  AgentToolResult,
} from './agent_protocol.ts'
import type { AgentToolHandler } from './agent_tools.ts'
import type { AgentAuditStore } from './agent_audit_tools.ts'
import { freshAuditSelectionRequired } from './agent_audit_tools.ts'
import { coverageFor, resolveBreedMatch } from './bmk_lookup.ts'
import { AgentScopeError, assertCustomerAllowed } from './agent_scope.ts'
import { roundTo, sampleWeightedMean } from './agent_metrics.ts'

export interface BmkBreedBenchmarkRow {
  breed: string
  ageWeek: number
  hatchabilityPct: number | null
  fertilityPct: number | null
  hofPct: number | null
  productionPct: number | null
  eggWeightG: number | null
  chickWeightG: number | null
}

export interface BmkEggBreakoutBenchmarkRow {
  ageWeek: number
  infertilePct: number | null
  early24hPct: number | null
  early48hPct: number | null
  bloodRingPct: number | null
  blackEyePct: number | null
  earlyDeadPct: number | null
  midDeadPct: number | null
  lateDeadPct: number | null
  externalPipPct: number | null
  crackedPct: number | null
  contamPct: number | null
}

export interface BmkOperationalStandardRow {
  id: string
  hatcheryId: string | null
  stationKey: string
  sectorKey: string
  metricKey: string
  metricLabel: string
  unit: string
  minValue: number | null
  maxValue: number | null
  targetValue: number | null
  source: string | null
  notes: string | null
  sortOrder: number
}

export interface AgentBmkStore {
  listBreedCoverage(): Promise<readonly { breed: string; ageWeek: number }[]>
  findBreedBenchmark(
    breed: string,
    ageWeek: number,
  ): Promise<BmkBreedBenchmarkRow | null>
  listEggBreakoutWeeks(): Promise<readonly number[]>
  findEggBreakoutBenchmark(
    ageWeek: number,
  ): Promise<BmkEggBreakoutBenchmarkRow | null>
  findHatcheryCustomerId(hatcheryId: string): Promise<string | null>
  listOperationalStandards(
    hatcheryId: string | null,
  ): Promise<readonly BmkOperationalStandardRow[]>
}

export function createAgentBmkToolHandlers(
  store: AgentBmkStore,
  auditStore?: AgentAuditStore,
): Partial<Record<AgentToolName, AgentToolHandler>> {
  const handlers: Partial<Record<AgentToolName, AgentToolHandler>> = {
    get_breed_benchmark: (input) => getBreedBenchmark(store, input),
    get_egg_breakout_benchmark: (input) =>
      getEggBreakoutBenchmark(store, input),
    get_operational_standards: (input) => getOperationalStandards(store, input),
  }
  if (auditStore) {
    handlers.compare_selected_audit_to_benchmark = (input) =>
      compareSelectedAuditToBenchmark(store, auditStore, input)
  }
  return handlers
}

/**
 * Resolve a requested breed name and age week against the table's own
 * vocabulary. Returns either the benchmark row or a structured miss -- never a
 * substituted or interpolated value.
 */
export async function resolveBreedBenchmark(
  store: AgentBmkStore,
  requestedBreed: string,
  ageWeek: number,
): Promise<
  | { status: 'ok'; row: BmkBreedBenchmarkRow }
  | { status: 'breed_not_found'; availableBreeds: string[] }
  | { status: 'breed_ambiguous'; candidateBreeds: string[] }
  | {
    status: 'week_out_of_range'
    breed: string
    coveredWeeks: { min: number; max: number }
  }
> {
  const coverage = await store.listBreedCoverage()
  const vocabulary = [...new Set(coverage.map((row) => row.breed))].sort()
  const match = resolveBreedMatch(requestedBreed, vocabulary)
  if (match.status === 'ambiguous') {
    // NOT `breed_not_found`. Reporting two real breeds as none made the agent
    // tell the user a breed it stocks does not exist; the useful question —
    // "Ross 308 or Ross 708?" — was already computed.
    return { status: 'breed_ambiguous', candidateBreeds: match.candidates }
  }
  if (match.status === 'unmatched') {
    return { status: 'breed_not_found', availableBreeds: vocabulary }
  }
  const breed = match.breed

  const row = await store.findBreedBenchmark(breed, ageWeek)
  if (row) return { status: 'ok', row }

  const range = coverageFor(breed, coverage)
  return {
    status: 'week_out_of_range',
    breed,
    coveredWeeks: range
      ? { min: range.minWeek, max: range.maxWeek }
      : { min: 0, max: 0 },
  }
}

/** Same contract as resolveBreedBenchmark, for the age-only breakout table. */
export async function resolveEggBreakoutBenchmark(
  store: AgentBmkStore,
  ageWeek: number,
): Promise<
  | { status: 'ok'; row: BmkEggBreakoutBenchmarkRow }
  | {
    status: 'week_out_of_range'
    coveredWeeks: { min: number; max: number }
  }
> {
  const row = await store.findEggBreakoutBenchmark(ageWeek)
  if (row) return { status: 'ok', row }
  const weeks = await store.listEggBreakoutWeeks()
  return {
    status: 'week_out_of_range',
    coveredWeeks: weeks.length === 0
      ? { min: 0, max: 0 }
      : { min: Math.min(...weeks), max: Math.max(...weeks) },
  }
}

/** One entry in a `metrics`-requestable catalogue, keyed by row field. */
interface RequestableMetric<TRow> {
  key: string
  field: keyof TRow
  unit: string
}

/** Metric keys the model may request via get_breed_benchmark's `metrics`. */
const BREED_REQUESTABLE_METRICS: readonly RequestableMetric<
  BmkBreedBenchmarkRow
>[] = [
  { key: 'production', field: 'productionPct', unit: '%' },
  { key: 'hatchability', field: 'hatchabilityPct', unit: '%' },
  { key: 'fertility', field: 'fertilityPct', unit: '%' },
  { key: 'hof', field: 'hofPct', unit: '%' },
  { key: 'egg_weight', field: 'eggWeightG', unit: 'g' },
  { key: 'chick_weight', field: 'chickWeightG', unit: 'g' },
]

/** Metric keys the model may request via get_egg_breakout_benchmark's `metrics`. */
const BREAKOUT_REQUESTABLE_METRICS: readonly RequestableMetric<
  BmkEggBreakoutBenchmarkRow
>[] = [
  { key: 'infertile', field: 'infertilePct', unit: '%' },
  { key: 'early_24h', field: 'early24hPct', unit: '%' },
  { key: 'early_48h', field: 'early48hPct', unit: '%' },
  { key: 'blood_ring', field: 'bloodRingPct', unit: '%' },
  { key: 'black_eye', field: 'blackEyePct', unit: '%' },
  { key: 'early_dead', field: 'earlyDeadPct', unit: '%' },
  { key: 'mid_dead', field: 'midDeadPct', unit: '%' },
  { key: 'late_dead', field: 'lateDeadPct', unit: '%' },
  { key: 'external_pip', field: 'externalPipPct', unit: '%' },
  { key: 'cracked', field: 'crackedPct', unit: '%' },
  // Deliberate name mismatch, same as BREAKOUT_METRIC_SOURCES below: the
  // model-facing key is `contaminated`, the row field is `contamPct`.
  { key: 'contaminated', field: 'contamPct', unit: '%' },
]

/**
 * Comma/space-separated request → known metric keys (order kept, deduped)
 * plus whatever tokens didn't match a known key (lowercased, order kept,
 * deduped) -- callers need both to distinguish "no metrics arg" from "a
 * metrics arg that didn't resolve to anything requestable".
 */
function parseRequestedMetrics<TRow>(
  raw: unknown,
  catalogue: readonly RequestableMetric<TRow>[],
): { keys: string[]; unknown: string[] } {
  if (typeof raw !== 'string') return { keys: [], unknown: [] }
  const known = new Set(catalogue.map((entry) => entry.key))
  const tokens = raw.toLowerCase().split(/[\s,]+/).filter((token) =>
    token.length > 0
  )
  return {
    keys: [...new Set(tokens.filter((token) => known.has(token)))],
    unknown: [...new Set(tokens.filter((token) => !known.has(token)))],
  }
}

/** Requestable metrics whose row value is null, in catalogue order. */
function nullMetricKeys<TRow>(
  row: TRow,
  catalogue: readonly RequestableMetric<TRow>[],
): string[] {
  return catalogue
    .filter((entry) => row[entry.field] === null)
    .map((entry) => entry.key)
}

async function getBreedBenchmark(
  store: AgentBmkStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const resolved = await resolveBreedBenchmark(
    store,
    input.arguments.breed as string,
    input.arguments.ageWeek as number,
  )
  if (resolved.status === 'ok') {
    // Null metrics are also NAMED in an `unavailable` list: a bare JSON null
    // is not salient enough for a small model, which otherwise
    // fills the gap with a value parroted from its calibration examples.
    const allUnavailable = nullMetricKeys(
      resolved.row,
      BREED_REQUESTABLE_METRICS,
    )
    const rawMetrics = input.arguments.metrics
    // Any non-empty string counts as "metrics were requested" -- including a
    // whitespace-only value. Trimming here (rather than just checking for a
    // non-empty string) would let " " fall through to the flat row below,
    // which is the exact full-dump this shaped path exists to prevent.
    const metricsRequested = typeof rawMetrics === 'string' &&
      rawMetrics.length > 0

    if (metricsRequested) {
      const { keys, unknown } = parseRequestedMetrics(
        rawMetrics,
        BREED_REQUESTABLE_METRICS,
      )
      if (keys.length > 0) {
        const unavailable = allUnavailable.filter((key) => keys.includes(key))
        return ok({
          breed: resolved.row.breed,
          ageWeek: resolved.row.ageWeek,
          requested: keys.map((key) => {
            const spec = BREED_REQUESTABLE_METRICS.find((entry) =>
              entry.key === key
            )!
            return {
              metric: key,
              value: resolved.row[spec.field],
              unit: spec.unit,
            }
          }),
          // Even though some tokens resolved, any unresolved tokens must
          // still surface: silently dropping them means the model answers
          // only the part it understood and treats the rest as answered,
          // per the voice policy's "requested list IS the answer" rule.
          ...(unknown.length > 0 ? { unknownMetrics: unknown } : {}),
          ...(unavailable.length > 0 ? { unavailable } : {}),
          context: { ...resolved.row },
        })
      }
      // A metrics arg was given but none of its tokens matched a known
      // metric key: never silently degrade to the full flat row -- that
      // would hand the model unrequested metrics it might read aloud. Return
      // the shaped payload with an empty `requested` and the raw tokens that
      // didn't resolve, so the caller can see what was misunderstood.
      return ok({
        breed: resolved.row.breed,
        ageWeek: resolved.row.ageWeek,
        requested: [],
        ...(unknown.length > 0 ? { unknownMetrics: unknown } : {}),
        ...(allUnavailable.length > 0 ? { unavailable: allUnavailable } : {}),
        context: { ...resolved.row },
      })
    }

    return ok(
      allUnavailable.length > 0
        ? { ...resolved.row, unavailable: allUnavailable }
        : { ...resolved.row },
    )
  }
  const { status, ...rest } = resolved
  return ok({ status, ...rest })
}

async function getEggBreakoutBenchmark(
  store: AgentBmkStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const resolved = await resolveEggBreakoutBenchmark(
    store,
    input.arguments.ageWeek as number,
  )
  if (resolved.status === 'ok') {
    // Null metrics are also NAMED in an `unavailable` list: a bare JSON null
    // is not salient enough for a small model, which otherwise
    // fills the gap with a value parroted from its calibration examples.
    const allUnavailable = nullMetricKeys(
      resolved.row,
      BREAKOUT_REQUESTABLE_METRICS,
    )
    const rawMetrics = input.arguments.metrics
    // Any non-empty string counts as "metrics were requested" -- including a
    // whitespace-only value. Trimming here (rather than just checking for a
    // non-empty string) would let " " fall through to the flat row below,
    // which is the exact full-dump this shaped path exists to prevent.
    const metricsRequested = typeof rawMetrics === 'string' &&
      rawMetrics.length > 0

    if (metricsRequested) {
      const { keys, unknown } = parseRequestedMetrics(
        rawMetrics,
        BREAKOUT_REQUESTABLE_METRICS,
      )
      if (keys.length > 0) {
        const unavailable = allUnavailable.filter((key) => keys.includes(key))
        return ok({
          ageWeek: resolved.row.ageWeek,
          requested: keys.map((key) => {
            const spec = BREAKOUT_REQUESTABLE_METRICS.find((entry) =>
              entry.key === key
            )!
            return {
              metric: key,
              value: resolved.row[spec.field],
              unit: spec.unit,
            }
          }),
          // Even though some tokens resolved, any unresolved tokens must
          // still surface: silently dropping them means the model answers
          // only the part it understood and treats the rest as answered,
          // per the voice policy's "requested list IS the answer" rule.
          ...(unknown.length > 0 ? { unknownMetrics: unknown } : {}),
          ...(unavailable.length > 0 ? { unavailable } : {}),
          context: { ...resolved.row },
        })
      }
      // A metrics arg was given but none of its tokens matched a known
      // metric key: never silently degrade to the full flat row -- that
      // would hand the model unrequested metrics it might read aloud. Return
      // the shaped payload with an empty `requested` and the raw tokens that
      // didn't resolve, so the caller can see what was misunderstood.
      return ok({
        ageWeek: resolved.row.ageWeek,
        requested: [],
        ...(unknown.length > 0 ? { unknownMetrics: unknown } : {}),
        ...(allUnavailable.length > 0 ? { unavailable: allUnavailable } : {}),
        context: { ...resolved.row },
      })
    }

    return ok(
      allUnavailable.length > 0
        ? { ...resolved.row, unavailable: allUnavailable }
        : { ...resolved.row },
    )
  }
  const { status, ...rest } = resolved
  return ok({ status, ...rest })
}

/**
 * Global standards overlaid by that hatchery's rows, keyed on metricKey --
 * the same precedence BmkRepository.getOperationalStandards implements in the
 * app, so the agent and the BMK screen never disagree.
 */
async function getOperationalStandards(
  store: AgentBmkStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const hatcheryId = optionalIdentifier(input.arguments.hatcheryId)
  if (hatcheryId) {
    const customerId = await store.findHatcheryCustomerId(hatcheryId)
    if (!customerId) return scopeDenied()
    try {
      assertCustomerAllowed(input.scope, customerId)
    } catch (error) {
      if (error instanceof AgentScopeError) return scopeDenied()
      throw error
    }
  }

  const merged = new Map<string, BmkOperationalStandardRow>()
  for (const row of await store.listOperationalStandards(null)) {
    merged.set(row.metricKey, row)
  }
  if (hatcheryId) {
    for (const row of await store.listOperationalStandards(hatcheryId)) {
      merged.set(row.metricKey, row)
    }
  }

  const stationKey = optionalIdentifier(input.arguments.stationKey)
  const sectorKey = optionalIdentifier(input.arguments.sectorKey)
  const standards = [...merged.values()]
    .filter((row) => !stationKey || row.stationKey === stationKey)
    .filter((row) => !sectorKey || row.sectorKey === sectorKey)
    .sort((left, right) =>
      left.sortOrder - right.sortOrder ||
      left.metricLabel.localeCompare(right.metricLabel)
    )

  return ok({ hatcheryId: hatcheryId ?? null, standards })
}

/** Breakout-row field -> breed-benchmark field. */
const BREED_METRIC_SOURCES: readonly {
  metricKey: keyof BmkBreedBenchmarkRow
  actualKey: string | null
  label: string
  unit: string
}[] = [
  {
    metricKey: 'hatchabilityPct',
    actualKey: 'hatchabilityPct',
    label: 'Hatchability',
    unit: '%',
  },
  {
    metricKey: 'fertilityPct',
    actualKey: 'fertilityPct',
    label: 'Fertility',
    unit: '%',
  },
  {
    metricKey: 'hofPct',
    actualKey: 'hofPct',
    label: 'Hatch of fertile',
    unit: '%',
  },
  {
    metricKey: 'productionPct',
    actualKey: null,
    label: 'Production',
    unit: '%',
  },
  { metricKey: 'eggWeightG', actualKey: null, label: 'Egg weight', unit: 'g' },
  {
    metricKey: 'chickWeightG',
    actualKey: null,
    label: 'Chick weight',
    unit: 'g',
  },
]

/**
 * Breakout-row field -> breakout-benchmark field. The audit column is
 * contaminatedPct while the benchmark column is contamPct, so the mapping is
 * explicit rather than by name.
 */
const BREAKOUT_METRIC_SOURCES: readonly {
  metricKey: keyof BmkEggBreakoutBenchmarkRow
  actualKey: string
  label: string
}[] = [
  { metricKey: 'infertilePct', actualKey: 'infertilePct', label: 'Infertile' },
  {
    metricKey: 'early24hPct',
    actualKey: 'early24hPct',
    label: 'Early dead 24h',
  },
  {
    metricKey: 'early48hPct',
    actualKey: 'early48hPct',
    label: 'Early dead 48h',
  },
  { metricKey: 'bloodRingPct', actualKey: 'bloodRingPct', label: 'Blood ring' },
  { metricKey: 'blackEyePct', actualKey: 'blackEyePct', label: 'Black eye' },
  { metricKey: 'earlyDeadPct', actualKey: 'earlyDeadPct', label: 'Early dead' },
  { metricKey: 'midDeadPct', actualKey: 'midDeadPct', label: 'Mid dead' },
  { metricKey: 'lateDeadPct', actualKey: 'lateDeadPct', label: 'Late dead' },
  {
    metricKey: 'externalPipPct',
    actualKey: 'externalPipPct',
    label: 'External pip',
  },
  { metricKey: 'crackedPct', actualKey: 'crackedPct', label: 'Cracked' },
  {
    metricKey: 'contamPct',
    actualKey: 'contaminatedPct',
    label: 'Contaminated',
  },
]

async function compareSelectedAuditToBenchmark(
  store: AgentBmkStore,
  auditStore: AgentAuditStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const context = auditStore.loadConversationContext
    ? await auditStore.loadConversationContext(input.conversationId)
    : null
  if (
    !context?.customerId || !context.auditId ||
    !input.scope.allowedCustomerIds.includes(context.customerId)
  ) {
    return freshAuditSelectionRequired(context)
  }

  const audit = await auditStore.findAudit(
    context.auditId,
    input.scope.allowedCustomerIds,
  )
  if (!audit || !input.scope.allowedCustomerIds.includes(audit.customerId)) {
    return scopeDenied()
  }
  if (
    audit.customerId !== context.customerId ||
    audit.flockId !== context.flockId
  ) {
    return freshAuditSelectionRequired(context)
  }

  const ageWeek = audit.flockAgeWeeks
  if (!audit.breed || ageWeek === null) {
    return ok({
      status: 'unavailable',
      reason: audit.breed ? 'missing_flock_age' : 'missing_breed',
      auditId: audit.id,
    })
  }

  const breedResult = await resolveBreedBenchmark(store, audit.breed, ageWeek)
  if (breedResult.status !== 'ok') {
    const { status, ...rest } = breedResult
    return ok({ status, auditId: audit.id, ageWeek, ...rest })
  }
  const breakoutResult = await resolveEggBreakoutBenchmark(store, ageWeek)

  const page = await auditStore.listAuditBreakouts({
    auditId: audit.id,
    customerId: audit.customerId,
  })
  const rows = page.rows.filter((row) =>
    row.sessionId === audit.id && row.customerId === audit.customerId
  ) as unknown as Record<string, unknown>[]

  const comparisons: Record<string, unknown>[] = []

  for (const metric of BREED_METRIC_SOURCES) {
    const standard = breedResult.row[metric.metricKey]
    comparisons.push(
      comparison({
        metricKey: metric.metricKey,
        label: metric.label,
        unit: metric.unit,
        standard: typeof standard === 'number' ? standard : null,
        aggregate: metric.actualKey === null
          ? { value: null, observedRows: 0, weight: null }
          : sampleWeightedMean(rows, metric.actualKey, 'traySize'),
      }),
    )
  }

  for (const metric of BREAKOUT_METRIC_SOURCES) {
    const standard = breakoutResult.status === 'ok'
      ? breakoutResult.row[metric.metricKey]
      : null
    comparisons.push(
      comparison({
        metricKey: metric.metricKey,
        label: metric.label,
        unit: '%',
        standard: typeof standard === 'number' ? standard : null,
        aggregate: sampleWeightedMean(rows, metric.actualKey, 'traySize'),
      }),
    )
  }

  return ok({
    auditId: audit.id,
    breed: breedResult.row.breed,
    ageWeek,
    breakoutBenchmarkAvailable: breakoutResult.status === 'ok',
    comparisons,
  })
}

function comparison(input: {
  metricKey: string
  label: string
  unit: string
  standard: number | null
  aggregate: { value: number | null; observedRows: number }
}): Record<string, unknown> {
  const actual = input.aggregate.value
  const base = {
    metricKey: input.metricKey,
    label: input.label,
    unit: input.unit,
    actual,
    standard: input.standard,
    observedRows: input.aggregate.observedRows,
  }
  if (actual === null) return { ...base, delta: null, reason: 'no_actual' }
  if (input.standard === null) {
    return { ...base, delta: null, reason: 'no_benchmark' }
  }
  return { ...base, delta: roundTo(actual - input.standard) }
}

function optionalIdentifier(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const text = value.trim()
  return text ? text : null
}

function scopeDenied(): AgentToolResult {
  return { ok: false, code: 'scope_denied', data: null }
}

function ok(data: Record<string, unknown>): AgentToolResult {
  return { ok: true, code: 'ok', data }
}

interface BmkDatabaseResult<T> {
  data: T | null
  error: { message: string } | null
}

interface BmkQuery {
  select(columns: string): BmkQuery
  eq(column: string, value: unknown): BmkQuery
  is(column: string, value: unknown): BmkQuery
  order(column: string, options: { ascending: boolean }): BmkQuery
  limit(count: number): Promise<BmkDatabaseResult<Record<string, unknown>[]>>
  maybeSingle(): Promise<BmkDatabaseResult<Record<string, unknown>>>
}

export interface AgentBmkClient {
  from(table: string): BmkQuery
}

const MAX_BMK_ROWS = 1000

export function createSupabaseAgentBmkStore(
  client: AgentBmkClient,
): AgentBmkStore {
  return {
    async listBreedCoverage() {
      const result = await client
        .from('bmk_breeds')
        .select('breed, age_week')
        .order('breed', { ascending: true })
        .limit(MAX_BMK_ROWS)
      throwIfBmkError(result)
      return (result.data ?? []).map((row) => ({
        breed: String(row.breed ?? ''),
        ageWeek: Number(row.age_week ?? 0),
      })).filter((row) => row.breed !== '' && Number.isFinite(row.ageWeek))
    },
    async findBreedBenchmark(breed, ageWeek) {
      const result = await client
        .from('bmk_breeds')
        .select(
          'breed, age_week, hatchability_pct, fertility_pct, hof_pct, ' +
            'production_pct, egg_weight_g, chick_weight_g',
        )
        .eq('breed', breed)
        .eq('age_week', ageWeek)
        .maybeSingle()
      throwIfBmkError(result)
      const row = result.data
      if (!row) return null
      return {
        breed: String(row.breed ?? breed),
        ageWeek: Number(row.age_week ?? ageWeek),
        hatchabilityPct: optionalNumber(row.hatchability_pct),
        fertilityPct: optionalNumber(row.fertility_pct),
        hofPct: optionalNumber(row.hof_pct),
        productionPct: optionalNumber(row.production_pct),
        eggWeightG: optionalNumber(row.egg_weight_g),
        chickWeightG: optionalNumber(row.chick_weight_g),
      }
    },
    async listEggBreakoutWeeks() {
      const result = await client
        .from('bmk_egg_breakout')
        .select('age_week')
        .order('age_week', { ascending: true })
        .limit(MAX_BMK_ROWS)
      throwIfBmkError(result)
      return (result.data ?? [])
        .map((row) => Number(row.age_week ?? 0))
        .filter((week) => Number.isFinite(week) && week > 0)
    },
    async findEggBreakoutBenchmark(ageWeek) {
      const result = await client
        .from('bmk_egg_breakout')
        .select(
          'age_week, infertile_pct, early24h_pct, early48h_pct, ' +
            'blood_ring_pct, black_eye_pct, early_dead_pct, mid_dead_pct, ' +
            'late_dead_pct, external_pip_pct, cracked_pct, contam_pct',
        )
        .eq('age_week', ageWeek)
        .maybeSingle()
      throwIfBmkError(result)
      const row = result.data
      if (!row) return null
      return {
        ageWeek: Number(row.age_week ?? ageWeek),
        infertilePct: optionalNumber(row.infertile_pct),
        early24hPct: optionalNumber(row.early24h_pct),
        early48hPct: optionalNumber(row.early48h_pct),
        bloodRingPct: optionalNumber(row.blood_ring_pct),
        blackEyePct: optionalNumber(row.black_eye_pct),
        earlyDeadPct: optionalNumber(row.early_dead_pct),
        midDeadPct: optionalNumber(row.mid_dead_pct),
        lateDeadPct: optionalNumber(row.late_dead_pct),
        externalPipPct: optionalNumber(row.external_pip_pct),
        crackedPct: optionalNumber(row.cracked_pct),
        contamPct: optionalNumber(row.contam_pct),
      }
    },
    async findHatcheryCustomerId(hatcheryId) {
      const result = await client
        .from('hatcheries')
        .select('id, customer_id')
        .eq('id', hatcheryId)
        .maybeSingle()
      throwIfBmkError(result)
      const customerId = result.data?.customer_id
      return typeof customerId === 'string' && customerId ? customerId : null
    },
    async listOperationalStandards(hatcheryId) {
      const base = client
        .from('bmk_operational_standards')
        .select(
          'id, hatchery_id, station_key, sector_key, metric_key, ' +
            'metric_label, unit, min_value, max_value, target_value, ' +
            'source, notes, sort_order',
        )
      const filtered = hatcheryId === null
        ? base.is('hatchery_id', null)
        : base.eq('hatchery_id', hatcheryId)
      const result = await filtered
        .order('sort_order', { ascending: true })
        .limit(MAX_BMK_ROWS)
      throwIfBmkError(result)
      return (result.data ?? []).map((row) => ({
        id: String(row.id ?? ''),
        hatcheryId: typeof row.hatchery_id === 'string'
          ? row.hatchery_id
          : null,
        stationKey: String(row.station_key ?? ''),
        sectorKey: String(row.sector_key ?? ''),
        metricKey: String(row.metric_key ?? ''),
        metricLabel: String(row.metric_label ?? ''),
        unit: String(row.unit ?? ''),
        minValue: optionalNumber(row.min_value),
        maxValue: optionalNumber(row.max_value),
        targetValue: optionalNumber(row.target_value),
        source: typeof row.source === 'string' ? row.source : null,
        notes: typeof row.notes === 'string' ? row.notes : null,
        sortOrder: Number(row.sort_order ?? 0),
      }))
    },
  }
}

function optionalNumber(value: unknown): number | null {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function throwIfBmkError(result: { error: { message: string } | null }) {
  if (result.error) throw new Error('Could not read benchmark data')
}
