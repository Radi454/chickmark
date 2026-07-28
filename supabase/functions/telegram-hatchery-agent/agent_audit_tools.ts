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
  findLatestAuditListResult(conversationId: string): Promise<unknown | null>
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
    options: { ascending: boolean; nullsFirst?: boolean },
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
  'customer:customers(id,name)',
  'flock:flocks(id,customer_id,flock_id)',
  'hatchery:hatcheries(id,customer_id,name)',
].join(', ')

const MAX_AUDIT_JSON_CHARS = 100_000
const MAX_AUDIT_OPTIONS = 20
const MAX_RECENT_CONVERSATION_TURNS = 40

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
    async findLatestAuditListResult(conversationId) {
      const turnsResult = await client
        .from('agent_conversation_turns')
        .select('id')
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .limit(MAX_RECENT_CONVERSATION_TURNS)
      throwIfDatabaseError(turnsResult)
      const turnIds = (turnsResult.data ?? [])
        .map((row) => boundedIdentifier(row.id))
        .filter((id): id is string => id !== null)
      if (turnIds.length === 0) return null

      const eventsResult = await client
        .from('agent_tool_events')
        .select('result_json')
        .in('conversation_turn_id', turnIds)
        .eq('tool_name', 'list_customer_audits')
        .eq('status', 'succeeded')
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .limit(1)
      throwIfDatabaseError(eventsResult)
      return eventsResult.data?.[0]?.result_json ?? null
    },
    async listAudits(input) {
      let query = client
        .from('audit_sessions')
        .select(AUDIT_COLUMNS)
        .eq('customer_id', input.customerId)
      if (input.flockId) query = query.eq('flock_id', input.flockId)
      const result = await query
        .order('date', { ascending: false, nullsFirst: false })
        .order('created_at', { ascending: false, nullsFirst: false })
        .order('id', { ascending: false, nullsFirst: false })
        .limit(input.limit + 1)
      throwIfDatabaseError(result)
      return (result.data ?? [])
        .map(auditFromRemote)
        .filter((audit): audit is AgentAuditReadRow => audit !== null)
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
    select_audit_option: (input) => selectAuditOption(store, input),
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
  return auditSummary(audit)
}

async function selectAuditOption(
  store: AgentAuditStore,
  input: AgentToolExecutionInput,
): Promise<AgentToolResult> {
  const snapshot = await store.findLatestAuditListResult(input.conversationId)
  const selected = selectedAuditFromSnapshot(
    snapshot,
    input.arguments.position as number,
    input.scope.allowedCustomerIds,
  )
  if (!selected) return scopeDenied()

  const audit = await store.findAudit(
    selected.auditId,
    input.scope.allowedCustomerIds,
  )
  if (
    !audit ||
    audit.customerId !== selected.customerId ||
    !input.scope.allowedCustomerIds.includes(audit.customerId)
  ) {
    return scopeDenied()
  }
  return auditSummary(audit)
}

function auditSummary(audit: AgentAuditReadRow): AgentToolResult {
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

function selectedAuditFromSnapshot(
  snapshot: unknown,
  position: number,
  allowedCustomerIds: readonly string[],
): { customerId: string; auditId: string } | null {
  if (!isRecord(snapshot) || snapshot.ok !== true || snapshot.code !== 'ok') {
    return null
  }
  const data = snapshot.data
  if (!isRecord(data)) return null
  const customerId = boundedIdentifier(data.customerId)
  if (!customerId || !allowedCustomerIds.includes(customerId)) return null
  const audits = data.audits
  if (
    !Array.isArray(audits) ||
    audits.length === 0 ||
    audits.length > MAX_AUDIT_OPTIONS
  ) return null

  const auditIds = audits.map((audit) =>
    isRecord(audit) ? boundedIdentifier(audit.id) : null
  )
  if (auditIds.some((auditId) => auditId === null)) return null
  const auditId = auditIds[position - 1]
  return auditId ? { customerId, auditId } : null
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

function auditFromRemote(
  row: Record<string, unknown>,
): AgentAuditReadRow | null {
  const id = boundedIdentifier(row.id)
  const customerId = boundedIdentifier(row.customer_id)
  const flockId = row.flock_id === null ? null : boundedIdentifier(row.flock_id)
  const hatcheryId = row.hatchery_id === null
    ? null
    : boundedIdentifier(row.hatchery_id)
  if (
    !id ||
    !customerId ||
    (row.flock_id !== null && !flockId) ||
    (row.hatchery_id !== null && !hatcheryId) ||
    !matchesCustomerRelation(row.customer, customerId) ||
    !matchesOwnedRelation(row.flock, flockId, customerId) ||
    !matchesOwnedRelation(row.hatchery, hatcheryId, customerId)
  ) return null

  return {
    id,
    customerId,
    flockId,
    hatcheryId,
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
    findings: jsonContainer(row.findings_json),
    scorecard: jsonContainer(row.scorecard_json),
    notes: optionalText(row.notes),
  }
}

function matchesCustomerRelation(
  value: unknown,
  customerId: string,
): boolean {
  return isRecord(value) && boundedIdentifier(value.id) === customerId
}

function matchesOwnedRelation(
  value: unknown,
  relationId: string | null,
  customerId: string,
): boolean {
  if (relationId === null) return value === null || value === undefined
  return isRecord(value) &&
    boundedIdentifier(value.id) === relationId &&
    boundedIdentifier(value.customer_id) === customerId
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

function jsonContainer(
  value: unknown,
): Record<string, unknown> | unknown[] | null {
  const parsed = parseJson(value)
  return isRecord(parsed) || Array.isArray(parsed) ? parsed : null
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

function optionalText(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null
}

function boundedIdentifier(value: unknown): string | null {
  const text = optionalText(value)
  return text !== null && text.length <= 160 && text.trim().length > 0
    ? text
    : null
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
