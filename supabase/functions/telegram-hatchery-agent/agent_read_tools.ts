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
  recordId?: string
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
  gte(column: string, value: unknown): ReadDatabaseQuery
  lte(column: string, value: unknown): ReadDatabaseQuery
  order(
    column: string,
    options: { ascending: boolean },
  ): ReadDatabaseQuery
  limit(
    count: number,
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
      if (query.fromDate) builder = builder.gte('date', query.fromDate)
      if (query.toDate) builder = builder.lte('date', query.toDate)
      const result = await builder
        .order('date', { ascending: false })
        .order('id', { ascending: false })
        .limit((query.limit ?? 100) + 1)
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
  const rows = await scopedCustomers(store, input.scope)
  return ok({
    customers: rows.map(({ id, name }) => ({ id, name })),
  })
}

async function resolveCustomerFlock(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const requestedCustomerName = normalizeOperationalName(
    input.arguments.customerName as string,
  )
  const requestedFlockName = typeof input.arguments.flockName === 'string'
    ? normalizeOperationalName(input.arguments.flockName)
    : null
  const customers = (await scopedCustomers(store, input.scope))
    .filter((customer) =>
      normalizeOperationalName(customer.name) === requestedCustomerName
    )

  if (customers.length === 0) {
    return ok({
      status: 'customer_not_found',
      customer: null,
      flock: null,
    })
  }

  const candidates = await Promise.all(customers.map(async (customer) => ({
    customer,
    flocks: (await store.listFlocks(customer.id, 100))
      .filter((flock) =>
        flock.customerId === customer.id &&
        input.scope.allowedCustomerIds.includes(flock.customerId)
      )
      .sort((left, right) =>
        left.name.localeCompare(right.name) || left.id.localeCompare(right.id)
      ),
  })))

  if (requestedFlockName === null) {
    if (candidates.length === 1) {
      return ok({
        status: 'resolved',
        customer: candidates[0].customer,
        flock: null,
      })
    }
    return ok({
      status: 'ambiguous_customer',
      customer: null,
      flock: null,
      candidates: candidates.map(({ customer, flocks }) => ({
        customer,
        flockNames: flocks.map((flock) => flock.name),
      })),
    })
  }

  const matches = candidates.flatMap(({ customer, flocks }) =>
    flocks
      .filter((flock) =>
        normalizeOperationalName(flock.name) === requestedFlockName
      )
      .map((flock) => ({ customer, flock }))
  )
  if (matches.length === 1) {
    return ok({
      status: 'resolved',
      customer: matches[0].customer,
      flock: publicFlock(matches[0].flock),
    })
  }
  if (matches.length > 1) {
    return ok({
      status: 'ambiguous_flock',
      customer: null,
      flock: null,
      candidates: matches.map(({ customer, flock }) => ({
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
      flockNames: flocks.map((flock) => flock.name),
    })),
  })
}

async function scopedCustomers(
  store: AgentReadStore,
  scope: AgentScope,
): Promise<AgentCustomerReadRow[]> {
  const allowedIds = new Set(scope.allowedCustomerIds)
  return (await store.listCustomers(scope.allowedCustomerIds, 100))
    .filter((customer) => allowedIds.has(customer.id))
    .sort((left, right) =>
      left.name.localeCompare(right.name) || left.id.localeCompare(right.id)
    )
    .slice(0, 100)
}

async function getCustomerContext(
  store: AgentReadStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const customerId = input.arguments.customerId as string
  if (!input.scope.allowedCustomerIds.includes(customerId)) return scopeDenied()
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
  if (!input.scope.allowedCustomerIds.includes(customerId)) return scopeDenied()
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
  if (!input.scope.allowedCustomerIds.includes(customerId)) return scopeDenied()
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
  const rows = stableRows(authorizedRows(
    await store.queryStationRecords({ ...prepared.query, limit }),
    prepared.query.customerId!,
    prepared.query.flockId,
  ))
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
  const rows = stableRows(authorizedRows(
    await store.queryStationRecords({ ...prepared.query, limit: 100 }),
    prepared.query.customerId!,
    prepared.query.flockId,
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
  for (const logical of readable) {
    const remote = remoteColumn(schema, logical)
    logicalByRemote.set(remote, logical)
  }
  return {
    remote: new Set(logicalByRemote.keys()),
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

function normalizeOperationalName(value: string): string {
  return value
    .normalize('NFKC')
    .replace(/[\u064B-\u065F\u0670]/g, '')
    .replace(/\u0640/g, '')
    .replace(/[أإآ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .trim()
    .replace(/\s+/g, ' ')
    .toLocaleLowerCase('ar')
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
