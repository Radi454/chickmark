import {
  type AgentStationSchema,
  requireStationSchema,
} from '../_shared/station_registry.generated.ts'
import type {
  AgentScope,
  AgentToolExecutionInput,
  AgentToolName,
  AgentToolResult,
} from './agent_protocol.ts'
import { ratioOfSums, sampleWeightedMean } from './agent_metrics.ts'
import { calculateStationValues } from './agent_station_adapter.ts'
import {
  type ChickQualityObservation,
  overlayReconstructedChickValues,
  reconstructChickObservationValues,
} from './chick_observation_codec.ts'
import { matchByName, strictOperationalKey } from './agent_name_match.ts'
import { MAX_AGENT_READ_ROWS } from './agent_tool_contract.ts'
import type { AgentToolHandler } from './agent_tools.ts'

export interface AgentCustomerReadRow {
  id: string
  name: string
}

export interface AgentFlockReadRow {
  id: string
  customerId: string
  name: string
  status: string | null
  breed: string | null
  entryDate: string | null
  sectorKey: string | null
}

export interface AgentHatcheryReadRow {
  id: string
  customerId: string
  name: string
}

export interface StationRecordQuery {
  table: string
  columns: readonly string[]
  customerId?: string
  allowedCustomerIds?: readonly string[]
  flockId?: string | null
  fromDate?: string
  toDate?: string
  limit?: number
  offset?: number
  recordId?: string
  chickDomain?: string
}

export interface AgentReadStore {
  listCustomers(
    customerIds: readonly string[],
    limit: number,
  ): Promise<readonly AgentCustomerReadRow[]>
  findCustomer(customerId: string): Promise<AgentCustomerReadRow | null>
  listFlocks(
    customerId: string,
    limit: number,
  ): Promise<readonly AgentFlockReadRow[]>
  listHatcheries(
    customerId: string,
    limit: number,
  ): Promise<readonly AgentHatcheryReadRow[]>
  findFlock(flockId: string): Promise<AgentFlockReadRow | null>
  queryStationRecords(
    query: StationRecordQuery,
  ): Promise<readonly Record<string, unknown>[]>
  findStationRecord(
    query: StationRecordQuery,
  ): Promise<Record<string, unknown> | null>
  queryChickObservations?(
    sampleIds: readonly string[],
    customerId: string,
  ): Promise<readonly Record<string, unknown>[]>
  queryChickHelpers?(
    query: StationRecordQuery,
    legacyIds: readonly string[],
  ): Promise<readonly Record<string, unknown>[]>
}

export interface AgentReadToolOptions {
  now?: () => Date
  freshWithinDays?: number
}

interface ReadDatabaseError {
  message: string
}

interface ReadDatabaseResult<T> {
  data: T | null
  error: ReadDatabaseError | null
}

interface ReadDatabaseQuery {
  select(columns: string): ReadDatabaseQuery
  eq(column: string, value: unknown): ReadDatabaseQuery
  in(column: string, values: readonly unknown[]): ReadDatabaseQuery
  or(filters: string): ReadDatabaseQuery
  gte(column: string, value: unknown): ReadDatabaseQuery
  lte(column: string, value: unknown): ReadDatabaseQuery
  order(
    column: string,
    options: { ascending: boolean },
  ): ReadDatabaseQuery
  limit(
    count: number,
  ): Promise<ReadDatabaseResult<Record<string, unknown>[]>>
  range(
    from: number,
    to: number,
  ): Promise<ReadDatabaseResult<Record<string, unknown>[]>>
  maybeSingle(): Promise<ReadDatabaseResult<Record<string, unknown>>>
}

export interface AgentReadClient {
  from(table: string): ReadDatabaseQuery
}

export function createSupabaseAgentReadStore(
  client: AgentReadClient,
): AgentReadStore {
  return {
    async listCustomers(customerIds, limit) {
      if (customerIds.length === 0) return []
      const result = await client
        .from('customers')
        .select('id, name')
        .in('id', customerIds)
        .order('name', { ascending: true })
        .limit(limit)
      throwIfReadError(result)
      return (result.data ?? []).map((row) => ({
        id: requiredText(row.id),
        name: requiredText(row.name),
      }))
    },
    async findCustomer(customerId) {
      const result = await client
        .from('customers')
        .select('id, name')
        .eq('id', customerId)
        .maybeSingle()
      throwIfReadError(result)
      const row = result.data
      return row
        ? {
          id: requiredText(row.id),
          name: requiredText(row.name),
        }
        : null
    },
    async listFlocks(customerId, limit) {
      const result = await client
        .from('flocks')
        .select(
          'id, customer_id, flock_id, status, breed, entry_date, sector_key',
        )
        .eq('customer_id', customerId)
        .order('flock_id', { ascending: true })
        .limit(limit)
      throwIfReadError(result)
      return (result.data ?? []).map(flockFromRemote)
    },
    async findFlock(flockId) {
      const result = await client
        .from('flocks')
        .select(
          'id, customer_id, flock_id, status, breed, entry_date, sector_key',
        )
        .eq('id', flockId)
        .maybeSingle()
      throwIfReadError(result)
      return result.data ? flockFromRemote(result.data) : null
    },
    async listHatcheries(customerId, limit) {
      const result = await client
        .from('hatcheries')
        .select('id, customer_id, name')
        .eq('customer_id', customerId)
        .order('name', { ascending: true })
        .limit(limit)
      throwIfReadError(result)
      return (result.data ?? []).map((row) => ({
        id: requiredText(row.id),
        customerId: requiredText(row.customer_id),
        name: requiredText(row.name),
      }))
    },
    async queryStationRecords(query) {
      let builder = client
        .from(query.table)
        .select(query.columns.join(', '))
      if (query.customerId) {
        builder = builder.eq('customer_id', query.customerId)
      } else if (query.allowedCustomerIds) {
        builder = builder.in('customer_id', query.allowedCustomerIds)
      }
      if (query.flockId) builder = builder.eq('flock_id', query.flockId)
      if (query.chickDomain) {
        builder = builder.or(
          `domain.eq.${query.chickDomain},domain.eq.chicks.legacy_combined,domain.is.null`,
        )
      }
      if (query.fromDate) builder = builder.gte('date', query.fromDate)
      if (query.toDate) builder = builder.lte('date', query.toDate)
      const result = await builder
        .order('date', { ascending: false })
        .order('id', { ascending: false })
        .range(
          query.offset ?? 0,
          (query.offset ?? 0) + (query.limit ?? 100) - 1,
        )
      throwIfReadError(result)
      return result.data ?? []
    },
    async findStationRecord(query) {
      let builder = client
        .from(query.table)
        .select(query.columns.join(', '))
      if (query.allowedCustomerIds) {
        if (query.allowedCustomerIds.length === 0) return null
        builder = builder.in('customer_id', query.allowedCustomerIds)
      }
      const result = await builder
        .eq('id', query.recordId ?? '')
        .maybeSingle()
      throwIfReadError(result)
      return result.data
    },
    async queryChickObservations(sampleIds, customerId) {
      if (sampleIds.length === 0) return []
      const rows: Record<string, unknown>[] = []
      const pageSize = 1000
      for (let offset = 0;; offset += pageSize) {
        const result = await client
          .from('chick_quality_observation')
          .select('*')
          .in('sample_id', sampleIds)
          .eq('customer_id', customerId)
          .order('sample_id', { ascending: true })
          .order('id', { ascending: true })
          .range(offset, offset + pageSize - 1)
        throwIfReadError(result)
        const page = result.data ?? []
        rows.push(...page)
        if (page.length < pageSize) break
      }
      return rows
    },
    async queryChickHelpers(query, legacyIds) {
      if (!query.customerId || !query.chickDomain || legacyIds.length === 0) {
        return []
      }
      const sourceRefs = legacyIds.map((id) =>
        `legacy-domain:${id}:${query.chickDomain}`
      )
      const result = await client
        .from(query.table)
        .select(query.columns.join(', '))
        .eq('customer_id', query.customerId)
        .eq('domain', query.chickDomain)
        .in('source_ref_id', sourceRefs)
        .limit(sourceRefs.length)
      throwIfReadError(result)
      return result.data ?? []
    },
  }
}

export function createAgentReadToolHandlers(
  store: AgentReadStore,
  options: AgentReadToolOptions = {},
): Partial<Record<AgentToolName, AgentToolHandler>> {
  const now = options.now ?? (() => new Date())
  const freshWithinDays = options.freshWithinDays ?? 30
  return {
    list_customers: (input) => listCustomers(store, input),
    resolve_customer_flock: (input) => resolveCustomerFlock(store, input),
    get_customer_context: (input) => getCustomerContext(store, input),
    list_customer_flocks: (input) => listCustomerFlocks(store, input),
    list_customer_hatcheries: (input) => listCustomerHatcheries(store, input),
    get_flock_context: (input) => getFlockContext(store, input, now),
    query_station_records: (input) => queryStationRecords(store, input, now),
    compare_station_metrics: (input) =>
      compareStationMetrics(store, input, now),
    get_record_provenance: (input) =>
      getRecordProvenance(store, input, now, freshWithinDays),
  }
}

async function listCustomers(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const scoped = await scopedCustomers(store, input.scope)
  return ok({
    customers: scoped.rows.map(({ id, name }) => ({ id, name })),
    // See `scopedCustomers`: without this the model states that a customer
    // past the alphabetical cap does not exist.
    truncated: scoped.truncated,
  })
}

// Cap on the flock roster `resolveCustomerFlock` will inline into a
// single-customer `resolved` result (see below). Below the cap, handing back
// the roster we already fetched saves the model a whole extra tool round
// trip for the extremely common "who is X" -> "what flocks does X have"
// follow-up; a round trip is a full additional model inference. Above the cap we omit the field instead of truncating it, because a
// customer with a roster this large is rare enough that the savings stop
// paying for the extra bytes on every other single-customer resolution, and
// a truncated list would look complete to the model and get answered from a
// partial roster instead of triggering `list_customer_flocks`.
const RESOLVE_INLINE_FLOCK_LIMIT = 25

/**
 * How many customers a miss or an ambiguity will name back to the model.
 *
 * Every non-resolved status carries CANDIDATES WITH IDS. That is the whole
 * point: a bare `customer_not_found` gives the model nothing it can act on
 * except asking the user the same question again, which is what a re-ask loop
 * is made of. With the roster in hand it can either pick the obvious entry or
 * ask ONE question naming real options.
 *
 * Bounded because the roster travels back through the model's context on the
 * voice path, where every token is spoken latency. Past the cap the list is
 * omitted and `truncated: true` says so, so the model reaches for
 * `list_customers` instead of answering from a partial roster it thinks is
 * complete.
 */
const RESOLVE_CANDIDATE_LIMIT = 25

/**
 * How many ambiguous customers get their flock roster fetched. Each roster is
 * its own `listFlocks` query, so an ambiguity across a large slice of a
 * tenant must not fan out into dozens of round trips; past this many
 * candidates the model gets ids and names only, which is still enough to ask
 * one good question.
 */
const AMBIGUOUS_ROSTER_LIMIT = 5

async function resolveCustomerFlock(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const requestedCustomerName = typeof input.arguments.customerName === 'string'
    ? input.arguments.customerName
    : ''
  const requestedFlockName = typeof input.arguments.flockName === 'string'
    ? input.arguments.flockName
    : null

  const scoped = await scopedCustomers(store, input.scope)
  const customerMatch = matchByName(
    requestedCustomerName,
    scoped.rows,
    (customer) => customer.name,
  )

  if (!customerMatch) {
    // Not a dead end: the caller learns which customers it MAY see, with
    // their ids, so the next move is a choice rather than another question.
    return ok({
      status: 'customer_not_found',
      customer: null,
      flock: null,
      ...candidateCustomerList(scoped),
    })
  }

  const customers = customerMatch.matches

  // TENANT GUARD. More than one customer matched, and the flock name is NOT
  // allowed to pick between them unless they genuinely carry the same name.
  //
  // "Exact tier" alone is not that evidence. The matcher folds hamza, alef
  // maqsura and ta-marbuta so a spoken name is findable at all, which means
  // `هانئ` and `هاني` — different people — collide at the exact tier. Letting
  // the flock name break that tie answers the caller about the wrong
  // operator's flock and PERSISTS it as the conversation's selection, with no
  // ambiguity signal anywhere. So the bypass additionally requires the
  // fold-free keys to agree: only then are these two rows really spelled the
  // same, and only then is telling them apart by a unique flock the only way
  // to answer at all.
  const sameWrittenName = customers.every((customer) =>
    strictOperationalKey(customer.name) ===
      strictOperationalKey(customers[0].name)
  )
  if (
    customers.length > 1 && !(customerMatch.tier === 'exact' && sameWrittenName)
  ) {
    return ok({
      status: 'ambiguous_customer',
      customer: null,
      flock: null,
      matchedBy: { customer: customerMatch.tier, flock: null },
      candidates: await customerCandidates(store, input, customers),
    })
  }

  const candidates = await Promise.all(customers.map(async (customer) => ({
    customer,
    flocks: scopedFlocks(
      await store.listFlocks(customer.id, MAX_AGENT_READ_ROWS),
      customer.id,
      input.scope,
    ),
  })))

  if (requestedFlockName === null) {
    if (candidates.length === 1) {
      const { customer, flocks } = candidates[0]
      return ok({
        status: 'resolved',
        customer,
        flock: null,
        matchedBy: { customer: customerMatch.tier, flock: null },
        // `flocks` was already fetched and scope-filtered above to build
        // `candidates`; returning it here (bounded by
        // RESOLVE_INLINE_FLOCK_LIMIT) means a caller that resolves a
        // customer and then immediately asks for its flocks never pays for
        // a second `list_customer_flocks` call that would just re-run the
        // identical `listFlocks` query.
        ...(flocks.length <= RESOLVE_INLINE_FLOCK_LIMIT
          ? { flocks: flocks.map(publicFlock) }
          : {}),
      })
    }
    return ok({
      status: 'ambiguous_customer',
      customer: null,
      flock: null,
      matchedBy: { customer: customerMatch.tier, flock: null },
      candidates: candidates.map(({ customer, flocks }) => ({
        customer,
        flocks: flocks.slice(0, RESOLVE_CANDIDATE_LIMIT).map(namedFlock),
        truncated: flocks.length > RESOLVE_CANDIDATE_LIMIT,
      })),
    })
  }

  // Flock matching runs over the flocks of the matched customers ONLY, which
  // are themselves already filtered to `allowedCustomerIds` — a flock can
  // never be matched out of a customer the caller cannot see.
  const flockPool = candidates.flatMap(({ customer, flocks }) =>
    flocks.map((flock) => ({ customer, flock }))
  )
  const flockMatch = matchByName(
    requestedFlockName,
    flockPool,
    (entry) => entry.flock.name,
  )

  if (flockMatch && flockMatch.matches.length === 1) {
    const [{ customer, flock }] = flockMatch.matches
    return ok({
      status: 'resolved',
      customer,
      flock: publicFlock(flock),
      // BOTH tiers, not just the flock's. A `contains`-tier customer hit that
      // happened to be unique, plus an `exact` flock hit, would otherwise be
      // reported as simply `exact` — erasing the one signal the model has
      // that the customer was GUESSED, in precisely the case where it was.
      matchedBy: { customer: customerMatch.tier, flock: flockMatch.tier },
    })
  }
  if (flockMatch) {
    return ok({
      status: 'ambiguous_flock',
      customer: null,
      flock: null,
      matchedBy: { customer: customerMatch.tier, flock: flockMatch.tier },
      candidates: flockMatch.matches
        .slice(0, RESOLVE_CANDIDATE_LIMIT)
        .map(({ customer, flock }) => ({
          customer,
          flock: publicFlock(flock),
        })),
    })
  }
  return ok({
    status: 'flock_not_found',
    customer: customers.length === 1 ? customers[0] : null,
    flock: null,
    candidates: candidates.map(({ customer, flocks }) => ({
      customer,
      flocks: flocks.slice(0, RESOLVE_CANDIDATE_LIMIT).map(namedFlock),
      truncated: flocks.length > RESOLVE_CANDIDATE_LIMIT,
    })),
  })
}

/** Scope-recheck a roster the store handed back for one customer. */
function scopedFlocks(
  rows: readonly AgentFlockReadRow[],
  customerId: string,
  scope: AgentScope,
): AgentFlockReadRow[] {
  return rows
    .filter((flock) =>
      flock.customerId === customerId &&
      scope.allowedCustomerIds.includes(flock.customerId)
    )
    .sort((left, right) =>
      left.name.localeCompare(right.name) || left.id.localeCompare(right.id)
    )
}

/**
 * The customer roster attached to a miss. Omitted past the cap rather than
 * truncated, for the same reason the inline flock roster is: a silently
 * shortened list reads as complete.
 */
function candidateCustomerList(
  scoped: { rows: readonly AgentCustomerReadRow[]; truncated: boolean },
): Record<string, unknown> {
  // `truncated` covers BOTH reasons the list can be incomplete: more
  // candidates than are worth spending tokens on, and a scope larger than the
  // read cap. The model needs the same answer either way — do not tell the
  // user this customer does not exist.
  return scoped.rows.length <= RESOLVE_CANDIDATE_LIMIT && !scoped.truncated
    ? {
      candidates: scoped.rows.map(({ id, name }) => ({ id, name })),
      truncated: false,
    }
    : { truncated: true }
}

/** Ambiguous customers, each with its roster while the fan-out stays cheap. */
async function customerCandidates(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
  customers: readonly AgentCustomerReadRow[],
): Promise<Record<string, unknown>[]> {
  const listed = customers.slice(0, RESOLVE_CANDIDATE_LIMIT)
  if (listed.length > AMBIGUOUS_ROSTER_LIMIT) {
    return listed.map((customer) => ({ customer }))
  }
  return await Promise.all(listed.map(async (customer) => {
    const flocks = scopedFlocks(
      await store.listFlocks(customer.id, MAX_AGENT_READ_ROWS),
      customer.id,
      input.scope,
    )
    return {
      customer,
      flocks: flocks.slice(0, RESOLVE_CANDIDATE_LIMIT).map(namedFlock),
      truncated: flocks.length > RESOLVE_CANDIDATE_LIMIT,
    }
  }))
}

/**
 * A candidate flock as the model needs it: the ID it must pass to every
 * ID-based tool, plus the name a human can be asked about. Deliberately not
 * `publicFlock` — a candidate list is for CHOOSING, and status/breed/entry
 * date/sector are answered by `get_flock_context` once a choice is made.
 */
function namedFlock(flock: AgentFlockReadRow): { id: string; name: string } {
  return { id: flock.id, name: flock.name }
}

/**
 * The customers this caller may see, name-ordered, capped at
 * `MAX_AGENT_READ_ROWS`.
 *
 * `truncated` is not decoration. An `admin` staff link is scoped to EVERY
 * customer, so a tenant past the cap is invisible to every name-based tool —
 * and without this flag the honest answer ("I can only see the first 100")
 * came out as the confident and wrong one ("there is no such customer"),
 * which is the original incident's symptom reached by a different route. The
 * cap is alphabetical, so who falls off it is arbitrary from the caller's
 * point of view.
 */
async function scopedCustomers(
  store: AgentReadStore,
  scope: AgentScope,
): Promise<{ rows: AgentCustomerReadRow[]; truncated: boolean }> {
  const allowedIds = new Set(scope.allowedCustomerIds)
  const rows = (await store.listCustomers(
    scope.allowedCustomerIds,
    MAX_AGENT_READ_ROWS + 1,
  ))
    .filter((customer) => allowedIds.has(customer.id))
    .sort((left, right) =>
      left.name.localeCompare(right.name) || left.id.localeCompare(right.id)
    )
  return {
    rows: rows.slice(0, MAX_AGENT_READ_ROWS),
    truncated: rows.length > MAX_AGENT_READ_ROWS ||
      scope.allowedCustomerIds.length > MAX_AGENT_READ_ROWS,
  }
}

async function getCustomerContext(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const customerId = input.arguments.customerId as string
  if (!input.scope.allowedCustomerIds.includes(customerId)) {
    return scopeDenied()
  }
  const customer = await store.findCustomer(customerId)
  return customer?.id === customerId
    ? ok({ id: customer.id, name: customer.name })
    : scopeDenied()
}

async function listCustomerFlocks(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const customerId = input.arguments.customerId as string
  if (!input.scope.allowedCustomerIds.includes(customerId)) {
    return scopeDenied()
  }
  const limit = (input.arguments.limit as number | undefined) ?? 100
  const rows = (await store.listFlocks(customerId, limit))
    .filter((flock) => flock.customerId === customerId)
    .sort((left, right) =>
      left.name.localeCompare(right.name) || left.id.localeCompare(right.id)
    )
    .slice(0, limit)
  return ok({
    customerId,
    flocks: rows.map(publicFlock),
  })
}

async function getFlockContext(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
  now: () => Date,
): Promise<AgentToolResult> {
  const flock = await store.findFlock(input.arguments.flockId as string)
  if (!flock || !input.scope.allowedCustomerIds.includes(flock.customerId)) {
    return scopeDenied()
  }
  const asOf = dayText(now())
  const ageDays = flock.entryDate === null
    ? null
    : wholeDays(flock.entryDate, asOf)
  return ok({
    ...publicFlock(flock),
    customerId: flock.customerId,
    ageDays,
    ageWeeks: ageDays === null ? null : Math.floor(ageDays / 7),
    ageAsOfDate: ageDays === null ? null : asOf,
  })
}

async function listCustomerHatcheries(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const customerId = input.arguments.customerId as string
  if (!input.scope.allowedCustomerIds.includes(customerId)) {
    return scopeDenied()
  }
  const limit = (input.arguments.limit as number | undefined) ?? 100
  const rows = (await store.listHatcheries(customerId, limit))
    .filter((hatchery) => hatchery.customerId === customerId)
    .sort((left, right) =>
      left.name.localeCompare(right.name) || left.id.localeCompare(right.id)
    )
    .slice(0, limit)
  return ok({
    customerId,
    hatcheries: rows.map(({ id, name }) => ({ id, name })),
  })
}

async function queryStationRecords(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
  now: () => Date,
): Promise<AgentToolResult> {
  const prepared = await prepareStationQuery(store, input)
  if ('result' in prepared) return prepared.result
  const limit = (input.arguments.limit as number | undefined) ?? 100
  const rows = await observationFirstRows(
    store,
    prepared.schema,
    stableRows(chickDomainRows(
      prepared.schema,
      authorizedRows(
        await loadRawStationRows(store, prepared, limit),
        prepared.query.customerId!,
        prepared.query.flockId,
      ),
    )),
    prepared.query.customerId!,
  )
  const truncated = rows.length > limit
  return ok({
    schemaKey: prepared.schema.schemaKey,
    schemaVersion: prepared.schema.version,
    sourceQueryAt: now().toISOString(),
    truncated,
    records: rows.slice(0, limit).map((row) =>
      publicStationRow(row, prepared.columns)
    ),
  })
}

async function compareStationMetrics(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
  now: () => Date,
): Promise<AgentToolResult> {
  const prepared = await prepareStationQuery(store, input)
  if ('result' in prepared) return prepared.result
  const measureKey = input.arguments.measureKey as string
  if (!prepared.schema.read.measures.includes(measureKey)) {
    return { ok: false, code: 'unsupported_metric', data: null }
  }
  const policy = metricPolicy(prepared.schema.schemaKey, measureKey)
  if (!policy) return { ok: false, code: 'unsupported_metric', data: null }
  const rows = (await observationFirstRows(
    store,
    prepared.schema,
    stableRows(chickDomainRows(
      prepared.schema,
      authorizedRows(
        await loadRawStationRows(store, prepared, 100),
        prepared.query.customerId!,
        prepared.query.flockId,
      ),
    )),
    prepared.query.customerId!,
  )).slice(0, 100)
  const remoteRows = rows.map((row) => publicStationRow(row, prepared.columns))

  if (policy.kind === 'sample_weighted_mean') {
    const aggregate = sampleWeightedMean(
      remoteRows,
      measureKey,
      policy.weightKey,
    )
    return ok({
      schemaKey: prepared.schema.schemaKey,
      schemaVersion: prepared.schema.version,
      measureKey,
      aggregation: policy.kind,
      value: aggregate.value,
      observedRows: aggregate.observedRows,
      sourceQueryAt: now().toISOString(),
    })
  }
  const aggregate = ratioOfSums(
    remoteRows,
    policy.numeratorKey,
    policy.denominatorKey,
  )
  return ok({
    schemaKey: prepared.schema.schemaKey,
    schemaVersion: prepared.schema.version,
    measureKey,
    aggregation: policy.kind,
    value: aggregate.value,
    observedRows: aggregate.observedRows,
    sourceQueryAt: now().toISOString(),
  })
}

async function loadRawStationRows(
  store: AgentReadStore,
  prepared: {
    schema: AgentStationSchema
    query: StationRecordQuery
  },
  logicalLimit: number,
): Promise<readonly Record<string, unknown>[]> {
  if (!prepared.schema.schemaKey.startsWith('chicks.')) {
    return await store.queryStationRecords({
      ...prepared.query,
      limit: logicalLimit + 1,
    })
  }
  const pageSize = Math.max(200, logicalLimit * 2)
  const rows: Record<string, unknown>[] = []
  const fingerprints = new Set<string>()
  for (let offset = 0;; offset += pageSize) {
    const page = await store.queryStationRecords({
      ...prepared.query,
      limit: pageSize,
      offset,
    })
    if (page.length === 0) break
    const fingerprint = page.map((row) => optionalText(row.id) ?? '').join('|')
    if (fingerprints.has(fingerprint)) {
      throw new Error('Agent read pagination did not advance')
    }
    fingerprints.add(fingerprint)
    rows.push(...page)
    const logical = chickDomainRows(
      prepared.schema,
      stableRows(authorizedRows(
        rows,
        prepared.query.customerId!,
        prepared.query.flockId,
      )),
    )
    if (logical.length > logicalLimit || page.length < pageSize) break
  }
  if (store.queryChickHelpers) {
    const logical = chickDomainRows(
      prepared.schema,
      stableRows(authorizedRows(
        rows,
        prepared.query.customerId!,
        prepared.query.flockId,
      )),
    ).slice(0, logicalLimit + 1)
    const legacyIds = logical
      .filter((row) =>
        !optionalText(row.domain) || row.domain === 'chicks.legacy_combined'
      )
      .map((row) => optionalText(row.id))
      .filter((id): id is string => id !== null)
    const helpers = await store.queryChickHelpers(prepared.query, legacyIds)
    const existingIds = new Set(rows.map((row) => optionalText(row.id)))
    rows.push(
      ...helpers.filter((row) => !existingIds.has(optionalText(row.id))),
    )
  }
  return rows
}

async function getRecordProvenance(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
  now: () => Date,
  freshWithinDays: number,
): Promise<AgentToolResult> {
  const schema = loadSchema(input.arguments)
  if (!schema) return { ok: false, code: 'unknown_schema', data: null }
  const columns = stationColumns(schema)
  const recordId = input.arguments.recordId as string
  const fetchedAt = now()
  const row = await store.findStationRecord({
    table: schema.persistence[0].remoteTable,
    columns: [...columns.remote],
    allowedCustomerIds: input.scope.allowedCustomerIds,
    recordId,
  })
  if (!row) {
    return ok({
      customerId: null,
      flockId: null,
      schemaKey: schema.schemaKey,
      schemaVersion: schema.version,
      recordId,
      recordDate: null,
      fetchedAt: fetchedAt.toISOString(),
      freshness: 'missing',
    })
  }
  const customerId = optionalText(row.customer_id)
  if (!customerId || !input.scope.allowedCustomerIds.includes(customerId)) {
    return ok({
      customerId: null,
      flockId: null,
      schemaKey: schema.schemaKey,
      schemaVersion: schema.version,
      recordId,
      recordDate: null,
      fetchedAt: fetchedAt.toISOString(),
      freshness: 'missing',
    })
  }
  const recordDate = optionalText(row.date)
  const ageDays = recordDate ? wholeDays(recordDate, dayText(fetchedAt)) : null
  return ok({
    customerId,
    flockId: optionalText(row.flock_id),
    schemaKey: schema.schemaKey,
    schemaVersion: schema.version,
    recordId,
    recordDate,
    fetchedAt: fetchedAt.toISOString(),
    freshness: ageDays === null
      ? 'missing'
      : ageDays <= freshWithinDays
      ? 'fresh'
      : 'stale',
  })
}

async function prepareStationQuery(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
): Promise<
  | {
    schema: AgentStationSchema
    columns: StationColumns
    query: StationRecordQuery
  }
  | { result: AgentToolResult }
> {
  const customerId = input.arguments.customerId as string
  if (!input.scope.allowedCustomerIds.includes(customerId)) {
    return { result: scopeDenied() }
  }
  const flockId = input.arguments.flockId as string | undefined
  if (flockId) {
    const flock = await store.findFlock(flockId)
    if (!flock || flock.customerId !== customerId) {
      return { result: scopeDenied() }
    }
  }
  const schema = loadSchema(input.arguments)
  if (!schema) {
    return {
      result: { ok: false, code: 'unknown_schema', data: null },
    }
  }
  const columns = stationColumns(schema)
  return {
    schema,
    columns,
    query: {
      table: schema.persistence[0].remoteTable,
      columns: [...columns.remote],
      customerId,
      flockId: flockId ?? null,
      fromDate: input.arguments.fromDate as string,
      toDate: input.arguments.toDate as string,
      chickDomain: schema.schemaKey.startsWith('chicks.')
        ? schema.schemaKey
        : undefined,
    },
  }
}

interface StationColumns {
  remote: Set<string>
  logicalByRemote: Map<string, string>
}

function stationColumns(schema: AgentStationSchema): StationColumns {
  const logicalByRemote = new Map<string, string>([
    ['id', 'id'],
    ['customer_id', 'customerId'],
    ['flock_id', 'flockId'],
    ['hatchery_id', 'hatcheryId'],
    ['date', 'date'],
  ])
  const readable = [...schema.read.dimensions, ...schema.read.measures]
  const remote = new Set(logicalByRemote.keys())
  if (schema.schemaKey.startsWith('chicks.')) {
    remote.add('domain')
    remote.add('source_ref_id')
  }
  for (const logical of readable) {
    const column = remoteColumn(schema, logical)
    remote.add(column)
    logicalByRemote.set(column, logical)
  }
  return {
    remote,
    logicalByRemote,
  }
}

function publicStationRow(
  row: Record<string, unknown>,
  columns: StationColumns,
): Record<string, unknown> {
  return Object.fromEntries(
    [...columns.logicalByRemote].map(([remote, logical]) => [
      logical,
      row[remote] ?? null,
    ]),
  )
}

async function observationFirstRows(
  store: AgentReadStore,
  schema: AgentStationSchema,
  rows: readonly Record<string, unknown>[],
  customerId: string,
): Promise<readonly Record<string, unknown>[]> {
  if (
    !schema.schemaKey.startsWith('chicks.') || !store.queryChickObservations
  ) {
    return rows
  }
  const sampleIds = rows.map((row) =>
    optionalText(row._observation_sample_id) ?? optionalText(row.id)
  ).filter(
    (id): id is string => id !== null,
  )
  const remote = await store.queryChickObservations(sampleIds, customerId)
  const bySample = new Map<string, ChickQualityObservation[]>()
  for (const row of remote) {
    const observation = observationFromRemote(row)
    if (!observation || observation.customerId !== customerId) continue
    const values = bySample.get(observation.sampleId) ?? []
    values.push(observation)
    bySample.set(observation.sampleId, values)
  }
  return rows.map((row) => {
    const sampleId = optionalText(row._observation_sample_id) ??
      optionalText(row.id)
    const observations = sampleId ? bySample.get(sampleId) : null
    if (!observations?.length) return row
    const contextualValues = Object.fromEntries(schema.fields.map((field) => [
      field.fieldKey,
      row[(field.persistence as { remoteColumn: string }).remoteColumn],
    ]))
    const values = overlayReconstructedChickValues(
      schema,
      contextualValues,
      reconstructChickObservationValues(schema, observations),
    )
    let calculated: Readonly<Record<string, unknown>> = {}
    try {
      calculated = calculateStationValues(schema, values)
    } catch (_) {
      // Partial field-work evidence still replaces raw caches. Derived values
      // remain absent until all of their inputs exist.
    }
    const overlaid = { ...row }
    for (const rawField of [...schema.fields, ...schema.calculations]) {
      const field = rawField as Record<string, unknown>
      const fieldKey = field.fieldKey as string
      const persistence = field.persistence as Record<string, unknown>
      const remoteColumn = persistence.remoteColumn as string
      overlaid[remoteColumn] = null
      const value = fieldKey in values ? values[fieldKey] : calculated[fieldKey]
      if (value === undefined) continue
      overlaid[remoteColumn] = Array.isArray(value)
        ? JSON.stringify(value)
        : value
    }
    return overlaid
  })
}

function chickDomainRows(
  schema: AgentStationSchema,
  rows: readonly Record<string, unknown>[],
): readonly Record<string, unknown>[] {
  if (!schema.schemaKey.startsWith('chicks.')) return rows
  const legacyById = new Map<string, Record<string, unknown>>()
  const helpersByLegacy = new Map<string, Record<string, unknown>>()
  const standalone: Record<string, unknown>[] = []
  for (const row of rows) {
    const domain = optionalText(row.domain)
    const id = optionalText(row.id)
    if (!id) continue
    if (!domain || domain === 'chicks.legacy_combined') {
      legacyById.set(id, row)
      continue
    }
    if (domain !== schema.schemaKey) continue
    const sourceRef = optionalText(row.source_ref_id)
    const prefix = 'legacy-domain:'
    const suffix = `:${schema.schemaKey}`
    if (sourceRef?.startsWith(prefix) && sourceRef.endsWith(suffix)) {
      helpersByLegacy.set(sourceRef.slice(prefix.length, -suffix.length), row)
    } else {
      standalone.push(row)
    }
  }
  return [
    ...[...legacyById].map(([legacyId, row]) => {
      const helper = helpersByLegacy.get(legacyId)
      return helper ? { ...row, _observation_sample_id: helper.id } : row
    }),
    ...standalone,
  ]
}

function observationFromRemote(
  row: Record<string, unknown>,
): ChickQualityObservation | null {
  const id = optionalText(row.id)
  const sampleId = optionalText(row.sample_id)
  const customerId = optionalText(row.customer_id)
  const sessionId = optionalText(row.session_id)
  const domain = optionalText(row.domain)
  const kind = optionalText(row.kind)
  const observationKey = optionalText(row.observation_key)
  const unit = optionalText(row.unit)
  const observedAt = optionalText(row.observed_at)
  const createdAt = optionalText(row.created_at)
  const updatedAt = optionalText(row.updated_at)
  if (
    !id || !sampleId || !customerId || !sessionId || !domain ||
    !observationKey || !unit || !observedAt || !createdAt || !updatedAt ||
    (kind !== 'series' && kind !== 'tally' && kind !== 'ordinal')
  ) return null
  return {
    id,
    sampleId,
    customerId,
    sessionId,
    domain,
    kind,
    observationKey,
    ordinal: typeof row.ordinal === 'number' ? row.ordinal : null,
    numericValue: typeof row.numeric_value === 'number'
      ? row.numeric_value
      : null,
    textValue: typeof row.text_value === 'string' ? row.text_value : null,
    unit,
    qualityFlags: '[]',
    source: optionalText(row.source),
    observedAt,
    createdAt,
    updatedAt,
  }
}

function remoteColumn(schema: AgentStationSchema, logical: string): string {
  for (const candidate of [...schema.fields, ...schema.calculations]) {
    if (candidate.fieldKey !== logical) continue
    const persistence = isRecord(candidate.persistence)
      ? candidate.persistence
      : null
    if (typeof persistence?.remoteColumn === 'string') {
      return persistence.remoteColumn
    }
  }
  return logical.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)
}

function loadSchema(args: Readonly<Record<string, unknown>>) {
  try {
    return requireStationSchema(
      args.schemaKey as string,
      args.schemaVersion as number,
    )
  } catch (_) {
    return null
  }
}

type MetricPolicy =
  | {
    kind: 'sample_weighted_mean'
    weightKey: string
  }
  | {
    kind: 'ratio_of_sums'
    numeratorKey: string
    denominatorKey: string
  }

function metricPolicy(
  schemaKey: string,
  measureKey: string,
): MetricPolicy | null {
  if (schemaKey === 'chicks.pasgar') {
    if (measureKey === 'pasgarFinalScore') {
      return {
        kind: 'sample_weighted_mean',
        weightKey: 'pasgarSampleSize',
      }
    }
    if (/^pasgar.+Pct$/.test(measureKey)) {
      const stem = measureKey.slice(0, -3)
      return {
        kind: 'ratio_of_sums',
        numeratorKey: `${stem}Count`,
        denominatorKey: 'pasgarSampleSize',
      }
    }
  }
  return null
}

function publicFlock(flock: AgentFlockReadRow) {
  return {
    id: flock.id,
    name: flock.name,
    status: flock.status,
    breed: flock.breed,
    entryDate: flock.entryDate,
    sectorKey: flock.sectorKey,
  }
}

function stableRows(
  rows: readonly Record<string, unknown>[],
): Record<string, unknown>[] {
  return [...rows].sort((left, right) => {
    const dateOrder = (optionalText(right.date) ?? '').localeCompare(
      optionalText(left.date) ?? '',
    )
    if (dateOrder !== 0) return dateOrder
    return (optionalText(right.id) ?? '').localeCompare(
      optionalText(left.id) ?? '',
    )
  })
}

function authorizedRows(
  rows: readonly Record<string, unknown>[],
  customerId: string,
  flockId?: string | null,
): Record<string, unknown>[] {
  return rows.filter((row) =>
    optionalText(row.customer_id) === customerId &&
    (!flockId || optionalText(row.flock_id) === flockId)
  )
}

function wholeDays(fromDay: string, toDay: string): number | null {
  const from = Date.parse(`${fromDay.slice(0, 10)}T00:00:00Z`)
  const to = Date.parse(`${toDay.slice(0, 10)}T00:00:00Z`)
  if (!Number.isFinite(from) || !Number.isFinite(to) || to < from) return null
  return Math.floor((to - from) / 86_400_000)
}

function dayText(value: Date): string {
  return value.toISOString().slice(0, 10)
}

function flockFromRemote(row: Record<string, unknown>): AgentFlockReadRow {
  return {
    id: requiredText(row.id),
    customerId: requiredText(row.customer_id),
    name: requiredText(row.flock_id),
    status: optionalText(row.status),
    breed: optionalText(row.breed),
    entryDate: optionalText(row.entry_date),
    sectorKey: optionalText(row.sector_key),
  }
}

function ok(data: Record<string, unknown>): AgentToolResult {
  return { ok: true, code: 'ok', data }
}

function scopeDenied(): AgentToolResult {
  return { ok: false, code: 'scope_denied', data: null }
}

function throwIfReadError(result: { error: ReadDatabaseError | null }): void {
  if (result.error) throw new Error('Agent read failed')
}

function requiredText(value: unknown): string {
  const text = optionalText(value)
  if (!text) throw new Error('Agent read row is invalid')
  return text
}

function optionalText(value: unknown): string | null {
  const text = value?.toString().trim()
  return text ? text : null
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
