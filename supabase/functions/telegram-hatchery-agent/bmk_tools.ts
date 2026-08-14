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
import { coverageFor, resolveBreed } from './bmk_lookup.ts'

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
}

export function createAgentBmkToolHandlers(
  store: AgentBmkStore,
): Partial<Record<AgentToolName, AgentToolHandler>> {
  return {
    get_breed_benchmark: (input) => getBreedBenchmark(store, input),
    get_egg_breakout_benchmark: (input) =>
      getEggBreakoutBenchmark(store, input),
  }
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
  | {
    status: 'week_out_of_range'
    breed: string
    coveredWeeks: { min: number; max: number }
  }
> {
  const coverage = await store.listBreedCoverage()
  const vocabulary = [...new Set(coverage.map((row) => row.breed))].sort()
  const breed = resolveBreed(requestedBreed, vocabulary)
  if (!breed) {
    return { status: 'breed_not_found', availableBreeds: vocabulary }
  }

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

async function getBreedBenchmark(
  store: AgentBmkStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const resolved = await resolveBreedBenchmark(
    store,
    input.arguments.breed as string,
    input.arguments.ageWeek as number,
  )
  if (resolved.status === 'ok') return ok({ ...resolved.row })
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
  if (resolved.status === 'ok') return ok({ ...resolved.row })
  const { status, ...rest } = resolved
  return ok({ status, ...rest })
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
  }
}

function optionalNumber(value: unknown): number | null {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function throwIfBmkError(result: { error: { message: string } | null }) {
  if (result.error) throw new Error('Could not read benchmark data')
}
