import type {
  AgentToolExecutionInput,
  AgentToolName,
  AgentToolResult,
} from './agent_protocol.ts'
import type { AgentToolHandler } from './agent_tools.ts'

export interface AgentAuditReadRow {
  id: string
  customerId: string
  flockId: string | null
  hatcheryId: string | null
  date: string | null
  status: string | null
  customerName: string | null
  flockName: string | null
  hatcheryName: string | null
  selectedStationKeys: readonly string[] | null
  stationsCompleted: readonly string[] | null
  createdAt: string | null
  completedAt: string | null
  breed: string | null
  flockAgeWeeks: number | null
  findings: unknown
  scorecard: unknown
  notes: string | null
}

export interface AgentAuditStore {
  findFlockCustomerId(flockId: string): Promise<string | null>
  listAudits(input: {
    customerId: string
    flockId: string | null
    limit: number
  }): Promise<readonly AgentAuditReadRow[]>
  findAudit(
    auditId: string,
    allowedCustomerIds: readonly string[],
  ): Promise<AgentAuditReadRow | null>
}

interface AuditDatabaseQuery {
  select(columns: string): AuditDatabaseQuery
  eq(column: string, value: unknown): AuditDatabaseQuery
  in(column: string, values: readonly unknown[]): AuditDatabaseQuery
  order(
    column: string,
    options: { ascending: boolean },
  ): AuditDatabaseQuery
  limit(
    count: number,
  ): Promise<{
    data: Record<string, unknown>[] | null
    error: { message: string } | null
  }>
  maybeSingle(): Promise<{
    data: Record<string, unknown> | null
    error: { message: string } | null
  }>
}

export interface AgentAuditClient {
  from(table: string): AuditDatabaseQuery
}

const AUDIT_COLUMNS = [
  'id',
  'customer_id',
  'flock_id',
  'hatchery_id',
  'date',
  'breed',
  'flock_age_weeks',
  'status',
  'selected_station_keys',
  'stations_completed',
  'findings_json',
  'scorecard_json',
  'notes',
  'created_at',
  'completed_at',
  'customer:customers(name)',
  'flock:flocks(flock_id)',
  'hatchery:hatcheries(name)',
].join(', ')

const MAX_AUDIT_JSON_CHARS = 100_000

export function createSupabaseAgentAuditStore(
  client: AgentAuditClient,
): AgentAuditStore {
  return {
    async findFlockCustomerId(flockId) {
      const result = await client
        .from('flocks')
        .select('customer_id')
        .eq('id', flockId)
        .maybeSingle()
      throwIfDatabaseError(result)
      return optionalText(result.data?.customer_id)
    },
    async listAudits(input) {
      let query = client
        .from('audit_sessions')
        .select(AUDIT_COLUMNS)
        .eq('customer_id', input.customerId)
      if (input.flockId) query = query.eq('flock_id', input.flockId)
      const result = await query
        .order('date', { ascending: false })
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .limit(input.limit + 1)
      throwIfDatabaseError(result)
      return (result.data ?? []).map(auditFromRemote)
    },
    async findAudit(auditId, allowedCustomerIds) {
      if (allowedCustomerIds.length === 0) return null
      const result = await client
        .from('audit_sessions')
        .select(AUDIT_COLUMNS)
        .in('customer_id', allowedCustomerIds)
        .eq('id', auditId)
        .maybeSingle()
      throwIfDatabaseError(result)
      return result.data ? auditFromRemote(result.data) : null
    },
  }
}

export function createAgentAuditToolHandlers(
  store: AgentAuditStore,
): Partial<Record<AgentToolName, AgentToolHandler>> {
  return {
    list_customer_audits: (input) => listCustomerAudits(store, input),
    get_audit_summary: (input) => getAuditSummary(store, input),
  }
}

async function listCustomerAudits(
  store: AgentAuditStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const customerId = input.arguments.customerId as string
  if (!input.scope.allowedCustomerIds.includes(customerId)) return scopeDenied()

  const flockId = (input.arguments.flockId as string | undefined) ?? null
  if (flockId && await store.findFlockCustomerId(flockId) !== customerId) {
    return scopeDenied()
  }

  const limit = (input.arguments.limit as number | undefined) ?? 10
  const rows = (await store.listAudits({ customerId, flockId, limit }))
    .filter((row) =>
      row.customerId === customerId &&
      (flockId === null || row.flockId === flockId)
    )
    .sort(compareAuditRows)
  return ok({
    customerId,
    flockId,
    audits: rows.slice(0, limit).map(publicAuditOption),
    truncated: rows.length > limit,
  })
}

async function getAuditSummary(
  store: AgentAuditStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const auditId = input.arguments.auditId as string
  const audit = await store.findAudit(auditId, input.scope.allowedCustomerIds)
  if (
    !audit || !input.scope.allowedCustomerIds.includes(audit.customerId)
  ) {
    return scopeDenied()
  }
  return ok({
    ...publicAuditOption(audit),
    customerId: audit.customerId,
    flockId: audit.flockId,
    hatcheryId: audit.hatcheryId,
    breed: audit.breed,
    flockAgeWeeks: audit.flockAgeWeeks,
    findings: audit.findings,
    scorecard: audit.scorecard,
    notes: audit.notes,
  })
}

function publicAuditOption(row: AgentAuditReadRow): Record<string, unknown> {
  return {
    id: row.id,
    date: row.date,
    status: row.status,
    customerName: row.customerName,
    flockName: row.flockName,
    hatcheryName: row.hatcheryName,
    selectedStationKeys: row.selectedStationKeys,
    stationsCompleted: row.stationsCompleted,
    createdAt: row.createdAt,
    completedAt: row.completedAt,
  }
}

function compareAuditRows(
  left: AgentAuditReadRow,
  right: AgentAuditReadRow,
): number {
  return (right.date ?? '').localeCompare(left.date ?? '') ||
    (right.createdAt ?? '').localeCompare(left.createdAt ?? '') ||
    right.id.localeCompare(left.id)
}

function auditFromRemote(row: Record<string, unknown>): AgentAuditReadRow {
  return {
    id: requiredText(row.id),
    customerId: requiredText(row.customer_id),
    flockId: optionalText(row.flock_id),
    hatcheryId: optionalText(row.hatchery_id),
    date: optionalText(row.date),
    status: optionalText(row.status),
    customerName: relationText(row.customer, 'name'),
    flockName: relationText(row.flock, 'flock_id'),
    hatcheryName: relationText(row.hatchery, 'name'),
    selectedStationKeys: jsonStringArray(row.selected_station_keys),
    stationsCompleted: jsonStringArray(row.stations_completed),
    createdAt: optionalText(row.created_at),
    completedAt: optionalText(row.completed_at),
    breed: optionalText(row.breed),
    flockAgeWeeks: optionalNumber(row.flock_age_weeks),
    findings: jsonObject(row.findings_json),
    scorecard: jsonObject(row.scorecard_json),
    notes: optionalText(row.notes),
  }
}

function relationText(value: unknown, field: string): string | null {
  return isRecord(value) ? optionalText(value[field]) : null
}

function jsonStringArray(value: unknown): string[] | null {
  const parsed = parseJson(value)
  return Array.isArray(parsed) &&
      parsed.every((item) => typeof item === 'string')
    ? parsed
    : null
}

function jsonObject(value: unknown): Record<string, unknown> | null {
  const parsed = parseJson(value)
  return isRecord(parsed) ? parsed : null
}

function parseJson(value: unknown): unknown {
  if (typeof value !== 'string' || value.length > MAX_AUDIT_JSON_CHARS) {
    return null
  }
  try {
    return JSON.parse(value)
  } catch (_) {
    return null
  }
}

function requiredText(value: unknown): string {
  const text = optionalText(value)
  if (text === null) throw new Error('Expected required audit field')
  return text
}

function optionalText(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null
}

function optionalNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function throwIfDatabaseError(result: { error: { message: string } | null }) {
  if (result.error) throw new Error(result.error.message)
}

function ok(data: Record<string, unknown>): AgentToolResult {
  return { ok: true, code: 'ok', data }
}

function scopeDenied(): AgentToolResult {
  return { ok: false, code: 'scope_denied', data: null }
}
