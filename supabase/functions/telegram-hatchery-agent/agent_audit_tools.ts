import type {
  AgentToolExecutionInput,
  AgentToolName,
  AgentToolResult,
} from './agent_protocol.ts'
import type { AgentToolHandler } from './agent_tools.ts'
import {
  type AgentBmkStore,
  resolveBreedBenchmark,
  resolveEggBreakoutBenchmark,
} from './bmk_tools.ts'

export interface AgentAuditToolOptions {
  bmkStore?: AgentBmkStore
}

/**
 * The benchmark block for one audit. Always returned -- an unresolvable
 * benchmark is reported with a reason so the agent can say the standard is
 * unknown instead of quietly answering without one.
 */
async function auditBenchmark(
  audit: AgentAuditReadRow,
  bmkStore: AgentBmkStore | undefined,
): Promise<Record<string, unknown>> {
  if (!bmkStore) {
    return { status: 'unavailable', reason: 'benchmark_unavailable' }
  }
  if (!audit.breed) {
    return { status: 'unavailable', reason: 'missing_breed' }
  }
  if (audit.flockAgeWeeks === null) {
    return { status: 'unavailable', reason: 'missing_flock_age' }
  }
  const breed = await resolveBreedBenchmark(
    bmkStore,
    audit.breed,
    audit.flockAgeWeeks,
  )
  if (breed.status !== 'ok') {
    // Keep the coverage payload the miss variants carry (`availableBreeds` on
    // breed_not_found, `breed`/`coveredWeeks` on week_out_of_range) so the
    // agent can follow the prompt rule -- "say what is covered and ask" --
    // straight from the auto-attached block, with no second tool call.
    const { status: _status, ...coverage } = breed
    return { status: 'unavailable', reason: breed.status, ...coverage }
  }
  const breakout = await resolveEggBreakoutBenchmark(
    bmkStore,
    audit.flockAgeWeeks,
  )
  return {
    status: 'ok',
    breed: breed.row.breed,
    ageWeek: audit.flockAgeWeeks,
    breedStandard: breed.row,
    breakoutStandard: breakout.status === 'ok' ? breakout.row : null,
  }
}

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

export interface AgentAuditListPage {
  rows: readonly AgentAuditReadRow[]
  truncated: boolean
}

export interface AgentAuditBreakoutRow {
  breakoutType: 'fresh' | 'candled' | 'residue'
  id: string
  sessionId: string
  customerId: string
  flockId: string | null
  hatcheryId: string | null
  date: string | null
  house: string | null
  setter: string | null
  hatcher: string | null
  trolley: string | null
  tray: string | null
  position: string | null
  traySize: number | null
  infertileCount: number | null
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
  contaminatedPct: number | null
  hatchabilityPct: number | null
  fertilityPct: number | null
  hofPct: number | null
  culledPct: number | null
  deadPct: number | null
}

export interface AgentAuditBreakoutPage {
  rows: readonly AgentAuditBreakoutRow[]
  truncated: boolean
}

export interface AgentAuditStore {
  findFlockCustomerId(flockId: string): Promise<string | null>
  findLatestAuditListResult(conversationId: string): Promise<unknown | null>
  findLatestSelectedAuditResult(
    conversationId: string,
  ): Promise<unknown | null>
  loadConversationContext?(
    conversationId: string,
  ): Promise<
    {
      customerId: string | null
      flockId: string | null
      auditId: string | null
    } | null
  >
  listAudits(input: {
    customerId: string
    flockId: string | null
    limit: number
  }): Promise<AgentAuditListPage>
  findAudit(
    auditId: string,
    allowedCustomerIds: readonly string[],
  ): Promise<AgentAuditReadRow | null>
  listAuditBreakouts(input: {
    auditId: string
    customerId: string
  }): Promise<AgentAuditBreakoutPage>
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
  range(
    from: number,
    to: number,
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
const AUDIT_SCAN_PAGE_SIZE = 50
const MAX_SCANNED_AUDIT_ROWS = 500
const MAX_AUDIT_BREAKOUT_ROWS = 20

const BREAKOUT_COMMON_COLUMNS = [
  'id',
  'session_id',
  'customer_id',
  'flock_id',
  'hatchery_id',
  'date',
  'house',
  'setter',
  'hatcher',
  'trolley',
  'tray',
  'position',
  'tray_size',
  'infertile_count',
  'infertile_pct',
]

const BREAKOUT_TABLES = [
  {
    breakoutType: 'fresh' as const,
    table: 'fresh_egg_breakout',
    columns: [
      ...BREAKOUT_COMMON_COLUMNS,
      'early24h_pct',
      'early48h_pct',
      'blood_ring_pct',
    ],
  },
  {
    breakoutType: 'candled' as const,
    table: 'candled_egg_breakout',
    columns: [
      ...BREAKOUT_COMMON_COLUMNS,
      'early24h_pct',
      'early48h_pct',
      'blood_ring_pct',
      'black_eye_pct',
    ],
  },
  {
    breakoutType: 'residue' as const,
    table: 'residue_breakout',
    columns: [
      ...BREAKOUT_COMMON_COLUMNS,
      'early_dead_pct',
      'mid_dead_pct',
      'late_dead_pct',
      'external_pip_pct',
      'cracked_pct',
      'contaminated_pct',
      'hatchability_pct',
      'fertility_pct',
      'hof_pct',
      'culled_pct',
      'dead_pct',
    ],
  },
] as const

async function findLatestSuccessfulToolResult(
  client: AgentAuditClient,
  conversationId: string,
  toolNames: readonly AgentToolName[],
): Promise<unknown | null> {
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

  let eventsQuery = client
    .from('agent_tool_events')
    .select('result_json')
    .in('conversation_turn_id', turnIds)
  eventsQuery = toolNames.length === 1
    ? eventsQuery.eq('tool_name', toolNames[0])
    : eventsQuery.in('tool_name', toolNames)
  const eventsResult = await eventsQuery
    .eq('status', 'succeeded')
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(1)
  throwIfDatabaseError(eventsResult)
  return eventsResult.data?.[0]?.result_json ?? null
}

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
    findLatestAuditListResult: (conversationId) =>
      findLatestSuccessfulToolResult(
        client,
        conversationId,
        ['list_customer_audits'],
      ),
    findLatestSelectedAuditResult: (conversationId) =>
      findLatestSuccessfulToolResult(
        client,
        conversationId,
        ['select_audit_option', 'get_audit_summary'],
      ),
    async loadConversationContext(conversationId) {
      const result = await client
        .from('agent_conversations')
        .select(
          'selected_customer_id, selected_flock_id, selected_audit_id',
        )
        .eq('id', conversationId)
        .maybeSingle()
      throwIfDatabaseError(result)
      return result.data
        ? {
          customerId: optionalText(result.data.selected_customer_id),
          flockId: optionalText(result.data.selected_flock_id),
          auditId: optionalText(result.data.selected_audit_id),
        }
        : null
    },
    async listAudits(input) {
      const rows: AgentAuditReadRow[] = []
      let scanned = 0

      while (
        scanned < MAX_SCANNED_AUDIT_ROWS &&
        rows.length <= input.limit
      ) {
        let query = client
          .from('audit_sessions')
          .select(AUDIT_COLUMNS)
          .eq('customer_id', input.customerId)
        if (input.flockId) query = query.eq('flock_id', input.flockId)
        const result = await query
          .order('date', { ascending: false, nullsFirst: false })
          .order('created_at', { ascending: false, nullsFirst: false })
          .order('id', { ascending: false, nullsFirst: false })
          .range(scanned, scanned + AUDIT_SCAN_PAGE_SIZE - 1)
        throwIfDatabaseError(result)

        const page = result.data ?? []
        rows.push(
          ...page
            .map(auditFromRemote)
            .filter((audit): audit is AgentAuditReadRow => audit !== null),
        )
        scanned += page.length
        if (page.length < AUDIT_SCAN_PAGE_SIZE) {
          return {
            rows: rows.slice(0, input.limit + 1),
            truncated: rows.length > input.limit,
          }
        }
      }

      return {
        rows: rows.slice(0, input.limit + 1),
        truncated: rows.length > input.limit ||
          scanned >= MAX_SCANNED_AUDIT_ROWS,
      }
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
    async listAuditBreakouts(input) {
      const pages = await Promise.all(
        BREAKOUT_TABLES.map(async (source) => {
          const result = await client
            .from(source.table)
            .select(source.columns.join(', '))
            .eq('session_id', input.auditId)
            .eq('customer_id', input.customerId)
            .order('id', { ascending: true })
            .limit(MAX_AUDIT_BREAKOUT_ROWS + 1)
          throwIfDatabaseError(result)
          return {
            rawCount: result.data?.length ?? 0,
            rows: (result.data ?? [])
              .map((row) => breakoutFromRemote(source.breakoutType, row))
              .filter((row): row is AgentAuditBreakoutRow => row !== null),
          }
        }),
      )
      const rows = pages.flatMap((page) => page.rows)
        .sort(compareBreakoutRows)
      return {
        rows: rows.slice(0, MAX_AUDIT_BREAKOUT_ROWS),
        truncated: rows.length > MAX_AUDIT_BREAKOUT_ROWS ||
          pages.some((page) => page.rawCount > MAX_AUDIT_BREAKOUT_ROWS),
      }
    },
  }
}

export function createAgentAuditToolHandlers(
  store: AgentAuditStore,
  options?: AgentAuditToolOptions,
): Partial<Record<AgentToolName, AgentToolHandler>> {
  const bmkStore = options?.bmkStore
  return {
    list_customer_audits: (input) => listCustomerAudits(store, input),
    select_audit_option: (input) => selectAuditOption(store, input),
    get_audit_summary: (input) => getAuditSummary(store, input, bmkStore),
    get_selected_audit_breakouts: (input) =>
      getSelectedAuditBreakouts(store, input, bmkStore),
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
  const page = await store.listAudits({ customerId, flockId, limit })
  const rows = page.rows
    .filter((row) =>
      row.customerId === customerId &&
      (flockId === null || row.flockId === flockId)
    )
    .sort(compareAuditRows)
  return ok({
    customerId,
    flockId,
    audits: rows.slice(0, limit).map(publicAuditOption),
    truncated: page.truncated || rows.length > limit,
  })
}

async function getAuditSummary(
  store: AgentAuditStore,
  input: AgentToolExecutionInput,
  bmkStore: AgentBmkStore | undefined,
): Promise<AgentToolResult> {
  const context = store.loadConversationContext
    ? await store.loadConversationContext(input.conversationId)
    : null
  let selected: {
    customerId: string
    flockId: string | null
    auditId: string
  } | null
  if (store.loadConversationContext) {
    selected = context?.customerId && context.auditId &&
        input.scope.allowedCustomerIds.includes(context.customerId)
      ? {
        customerId: context.customerId,
        flockId: context.flockId,
        auditId: context.auditId,
      }
      : null
    if (!selected) return freshAuditSelectionRequired(context)
  } else {
    const snapshot = await store.findLatestSelectedAuditResult(
      input.conversationId,
    )
    selected = selectedAuditReference(
      snapshot,
      input.scope.allowedCustomerIds,
    )
    if (!selected) return scopeDenied()
  }

  const audit = await store.findAudit(
    selected.auditId,
    input.scope.allowedCustomerIds,
  )
  if (!audit || !input.scope.allowedCustomerIds.includes(audit.customerId)) {
    return scopeDenied()
  }
  if (
    audit.customerId !== selected.customerId ||
    audit.flockId !== selected.flockId
  ) {
    return store.loadConversationContext
      ? freshAuditSelectionRequired(context)
      : scopeDenied()
  }
  return ok({
    ...(auditSummary(audit).data ?? {}),
    benchmark: await auditBenchmark(audit, bmkStore),
  })
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
    (selected.flockId !== null && audit.flockId !== selected.flockId) ||
    !input.scope.allowedCustomerIds.includes(audit.customerId)
  ) {
    return scopeDenied()
  }
  return auditSummary(audit)
}

async function getSelectedAuditBreakouts(
  store: AgentAuditStore,
  input: AgentToolExecutionInput,
  bmkStore: AgentBmkStore | undefined,
): Promise<AgentToolResult> {
  const context = store.loadConversationContext
    ? await store.loadConversationContext(input.conversationId)
    : null
  let selected: {
    customerId: string
    flockId: string | null
    auditId: string
  } | null
  if (store.loadConversationContext) {
    selected = context?.customerId && context.auditId &&
        input.scope.allowedCustomerIds.includes(context.customerId)
      ? {
        customerId: context.customerId,
        flockId: context.flockId,
        auditId: context.auditId,
      }
      : null
    if (!selected) return freshAuditSelectionRequired(context)
  } else {
    const snapshot = await store.findLatestSelectedAuditResult(
      input.conversationId,
    )
    selected = selectedAuditReference(
      snapshot,
      input.scope.allowedCustomerIds,
    )
    if (!selected) return scopeDenied()
  }

  const audit = await store.findAudit(
    selected.auditId,
    input.scope.allowedCustomerIds,
  )
  if (
    !audit ||
    audit.customerId !== selected.customerId ||
    (selected.flockId !== null && audit.flockId !== selected.flockId) ||
    !input.scope.allowedCustomerIds.includes(audit.customerId)
  ) {
    return scopeDenied()
  }

  const page = await store.listAuditBreakouts({
    auditId: audit.id,
    customerId: audit.customerId,
  })
  const rows = page.rows
    .filter((row) =>
      row.sessionId === audit.id &&
      row.customerId === audit.customerId
    )
    .sort(compareBreakoutRows)
  return ok({
    audit: publicAuditOption(audit),
    breakouts: rows.slice(0, MAX_AUDIT_BREAKOUT_ROWS).map(publicBreakoutRow),
    truncated: page.truncated || rows.length > MAX_AUDIT_BREAKOUT_ROWS,
    benchmark: await auditBenchmark(audit, bmkStore),
  })
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

function selectedAuditReference(
  snapshot: unknown,
  allowedCustomerIds: readonly string[],
): {
  customerId: string
  flockId: string | null
  auditId: string
} | null {
  if (!isRecord(snapshot) || snapshot.ok !== true || snapshot.code !== 'ok') {
    return null
  }
  const data = snapshot.data
  if (!isRecord(data)) return null
  const customerId = boundedIdentifier(data.customerId)
  const flockId = data.flockId === null || data.flockId === undefined
    ? null
    : boundedIdentifier(data.flockId)
  const auditId = boundedIdentifier(data.id)
  return customerId && auditId &&
      (data.flockId === null || data.flockId === undefined || flockId) &&
      allowedCustomerIds.includes(customerId)
    ? { customerId, flockId, auditId }
    : null
}

function selectedAuditFromSnapshot(
  snapshot: unknown,
  position: number,
  allowedCustomerIds: readonly string[],
): {
  customerId: string
  flockId: string | null
  auditId: string
} | null {
  if (!isRecord(snapshot) || snapshot.ok !== true || snapshot.code !== 'ok') {
    return null
  }
  const data = snapshot.data
  if (!isRecord(data)) return null
  const customerId = boundedIdentifier(data.customerId)
  if (!customerId || !allowedCustomerIds.includes(customerId)) return null
  const flockId = data.flockId === null || data.flockId === undefined
    ? null
    : boundedIdentifier(data.flockId)
  if (data.flockId !== null && data.flockId !== undefined && !flockId) {
    return null
  }
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
  return auditId ? { customerId, flockId, auditId } : null
}

export function freshAuditSelectionRequired(
  context: {
    customerId: string | null
    flockId: string | null
    auditId: string | null
  } | null,
): AgentToolResult {
  return {
    ok: false,
    code: 'fresh_audit_selection_required',
    data: {
      selectedCustomerId: context?.customerId ?? null,
      selectedFlockId: context?.flockId ?? null,
    },
  }
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

function compareBreakoutRows(
  left: AgentAuditBreakoutRow,
  right: AgentAuditBreakoutRow,
): number {
  const typeOrder = { fresh: 0, candled: 1, residue: 2 }
  return typeOrder[left.breakoutType] - typeOrder[right.breakoutType] ||
    (left.date ?? '').localeCompare(right.date ?? '') ||
    left.id.localeCompare(right.id)
}

function publicBreakoutRow(
  row: AgentAuditBreakoutRow,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries({
      breakoutType: row.breakoutType,
      date: row.date,
      house: row.house,
      setter: row.setter,
      hatcher: row.hatcher,
      trolley: row.trolley,
      tray: row.tray,
      position: row.position,
      traySize: row.traySize,
      infertileCount: row.infertileCount,
      infertilePct: row.infertilePct,
      early24hPct: row.early24hPct,
      early48hPct: row.early48hPct,
      bloodRingPct: row.bloodRingPct,
      blackEyePct: row.blackEyePct,
      earlyDeadPct: row.earlyDeadPct,
      midDeadPct: row.midDeadPct,
      lateDeadPct: row.lateDeadPct,
      externalPipPct: row.externalPipPct,
      crackedPct: row.crackedPct,
      contaminatedPct: row.contaminatedPct,
      hatchabilityPct: row.hatchabilityPct,
      fertilityPct: row.fertilityPct,
      hofPct: row.hofPct,
      culledPct: row.culledPct,
      deadPct: row.deadPct,
    }).filter((entry) => entry[1] !== null),
  )
}

function breakoutFromRemote(
  breakoutType: AgentAuditBreakoutRow['breakoutType'],
  row: Record<string, unknown>,
): AgentAuditBreakoutRow | null {
  const id = boundedIdentifier(row.id)
  const sessionId = boundedIdentifier(row.session_id)
  const customerId = boundedIdentifier(row.customer_id)
  const flockId = row.flock_id === null ? null : boundedIdentifier(row.flock_id)
  const hatcheryId = row.hatchery_id === null
    ? null
    : boundedIdentifier(row.hatchery_id)
  if (
    !id ||
    !sessionId ||
    !customerId ||
    (row.flock_id !== null && !flockId) ||
    (row.hatchery_id !== null && !hatcheryId)
  ) return null

  return {
    breakoutType,
    id,
    sessionId,
    customerId,
    flockId,
    hatcheryId,
    date: optionalText(row.date),
    house: optionalText(row.house),
    setter: optionalText(row.setter),
    hatcher: optionalText(row.hatcher),
    trolley: optionalText(row.trolley),
    tray: optionalText(row.tray),
    position: optionalText(row.position),
    traySize: optionalNumber(row.tray_size),
    infertileCount: optionalNumber(row.infertile_count),
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
    contaminatedPct: optionalNumber(row.contaminated_pct),
    hatchabilityPct: optionalNumber(row.hatchability_pct),
    fertilityPct: optionalNumber(row.fertility_pct),
    hofPct: optionalNumber(row.hof_pct),
    culledPct: optionalNumber(row.culled_pct),
    deadPct: optionalNumber(row.dead_pct),
  }
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
