export type AgentIntakeState =
  | 'collecting'
  | 'awaiting_clarification'
  | 'paused'
  | 'ready_for_summary'
  | 'awaiting_user_confirmation'
  | 'awaiting_admin_review'
  | 'approved'
  | 'rejected'
  | 'cancelled'

export type AgentVisitState =
  | 'selecting_station'
  | 'collecting'
  | 'awaiting_admin_review'
  | 'completed'
  | 'cancelled'

export interface AgentPendingAction {
  id: string
  kind: 'station_intake'
  customerId: string
  proposedAt: string
  proposedTurnId: string
  proposedTurnIndex: number
  expiresAt: string
  expiresAfterTurnIndex: number
}

export interface AgentConversation {
  id: string
  staffLinkId: string
  telegramChatId: string
  stateVersion: number
  pendingAction: AgentPendingAction | null
  activeVisitId: string | null
  createdAt: string
  updatedAt: string
}

export interface AgentIntakeContext {
  customerId: string
  customerName: string
  flockId: string
  flockName: string
  hatcheryId: string
  hatcheryName: string
  auditDate: string
  layer: string
  setterIdentity: string | null
  hatcherIdentity: string | null
  sectorKey: string
}

export interface AgentClarification {
  fieldKey: string
  sourcePhrase: string
  reason: string
}

export interface AgentSummarySnapshot {
  version: number
  schemaKey: string
  schemaVersion: number
  values: Readonly<Record<string, unknown>>
  calculations: Readonly<Record<string, unknown>>
  generatedAt: string
}

export interface AgentIntakeSession {
  id: string
  visitId: string
  staffLinkId: string
  telegramChatId: string
  schemaKey: string
  schemaVersion: number
  state: AgentIntakeState
  language: 'en' | 'ar' | 'mixed'
  rowVersion: number
  context: AgentIntakeContext
  workingValues: Readonly<Record<string, unknown>>
  pendingClarification: AgentClarification | null
  summaryVersion: number
  summarySnapshot: AgentSummarySnapshot | null
  userConfirmedAt: string | null
  lastToolEventId: string | null
  createdAt: string
  updatedAt: string
}

export interface AgentIntakeVisit {
  id: string
  conversationId: string
  customerId: string
  flockId: string
  hatcheryId: string
  auditDate: string
  state: AgentVisitState
  approvedSessionId: string | null
  createdAt: string
  updatedAt: string
}

export interface AgentIntakeValueUpdate {
  intakeSessionId: string
  fieldKey: string
  value: unknown
  sourcePhrase: string
  confidence: number
  clarificationReason: string | null
  toolCallId: string | null
  updatedAt: string
}

export interface AgentIntakeStore {
  createConversation(conversation: AgentConversation): Promise<void>
  loadConversation(conversationId: string): Promise<AgentConversation | null>
  loadConversationByStaffChat(
    staffLinkId: string,
    telegramChatId: string,
  ): Promise<AgentConversation | null>
  updateConversation(
    conversationId: string,
    expectedStateVersion: number,
    patch: Partial<AgentConversation>,
  ): Promise<AgentConversation | null>
  createVisit(visit: AgentIntakeVisit): Promise<void>
  loadVisit(visitId: string): Promise<AgentIntakeVisit | null>
  updateVisit(
    visitId: string,
    patch: Partial<AgentIntakeVisit>,
  ): Promise<AgentIntakeVisit | null>
  createSession(session: AgentIntakeSession): Promise<void>
  loadSession(intakeId: string): Promise<AgentIntakeSession | null>
  updateSession(
    intakeId: string,
    expectedRowVersion: number,
    patch: Partial<AgentIntakeSession>,
  ): Promise<AgentIntakeSession | null>
  upsertValues(values: readonly AgentIntakeValueUpdate[]): Promise<void>
}

interface IntakeDatabaseError {
  message: string
  code?: string
}

interface IntakeDatabaseResult<T = unknown> {
  data: T | null
  error: IntakeDatabaseError | null
}

interface IntakeDatabaseQuery {
  select(columns: string): IntakeDatabaseQuery
  eq(column: string, value: unknown): IntakeDatabaseQuery
  maybeSingle(): Promise<IntakeDatabaseResult<Record<string, unknown>>>
  insert(values: unknown): Promise<IntakeDatabaseResult>
  upsert(
    values: unknown,
    options?: { onConflict?: string },
  ): Promise<IntakeDatabaseResult>
  update(values: unknown): IntakeDatabaseQuery
}

export interface AgentIntakeClient {
  from(table: string): IntakeDatabaseQuery
}

export function createSupabaseAgentIntakeStore(
  client: AgentIntakeClient,
): AgentIntakeStore {
  return {
    async createConversation(conversation) {
      throwIfDatabaseError(
        await client.from('agent_conversations').insert(
          conversationToRemote(conversation),
        ),
      )
    },
    async loadConversation(conversationId) {
      const result = await client
        .from('agent_conversations')
        .select('*')
        .eq('id', conversationId)
        .maybeSingle()
      throwIfDatabaseError(result)
      return result.data ? conversationFromRemote(result.data) : null
    },
    async loadConversationByStaffChat(staffLinkId, telegramChatId) {
      const result = await client
        .from('agent_conversations')
        .select('*')
        .eq('staff_link_id', staffLinkId)
        .eq('telegram_chat_id', telegramChatId)
        .maybeSingle()
      throwIfDatabaseError(result)
      return result.data ? conversationFromRemote(result.data) : null
    },
    async updateConversation(conversationId, expectedStateVersion, patch) {
      const result = await client
        .from('agent_conversations')
        .update(conversationPatchToRemote(patch, expectedStateVersion + 1))
        .eq('id', conversationId)
        .eq('state_version', expectedStateVersion)
        .select('*')
        .maybeSingle()
      throwIfDatabaseError(result)
      return result.data ? conversationFromRemote(result.data) : null
    },
    async createVisit(visit) {
      throwIfDatabaseError(
        await client.from('agent_intake_visits').insert(visitToRemote(visit)),
      )
    },
    async loadVisit(visitId) {
      const result = await client
        .from('agent_intake_visits')
        .select('*')
        .eq('id', visitId)
        .maybeSingle()
      throwIfDatabaseError(result)
      return result.data ? visitFromRemote(result.data) : null
    },
    async updateVisit(visitId, patch) {
      const result = await client
        .from('agent_intake_visits')
        .update(visitPatchToRemote(patch))
        .eq('id', visitId)
        .select('*')
        .maybeSingle()
      throwIfDatabaseError(result)
      return result.data ? visitFromRemote(result.data) : null
    },
    async createSession(session) {
      throwIfDatabaseError(
        await client.from('agent_intake_sessions').insert(
          sessionToRemote(session),
        ),
      )
    },
    async loadSession(intakeId) {
      const result = await client
        .from('agent_intake_sessions')
        .select('*')
        .eq('id', intakeId)
        .maybeSingle()
      throwIfDatabaseError(result)
      return result.data ? sessionFromRemote(result.data) : null
    },
    async updateSession(intakeId, expectedRowVersion, patch) {
      const result = await client
        .from('agent_intake_sessions')
        .update(sessionPatchToRemote(patch, expectedRowVersion + 1))
        .eq('id', intakeId)
        .eq('row_version', expectedRowVersion)
        .select('*')
        .maybeSingle()
      throwIfDatabaseError(result)
      return result.data ? sessionFromRemote(result.data) : null
    },
    async upsertValues(values) {
      if (values.length === 0) return
      throwIfDatabaseError(
        await client.from('agent_intake_values').upsert(
          values.map(valueToRemote),
          { onConflict: 'intake_session_id,field_key' },
        ),
      )
    },
  }
}

export class MemoryAgentIntakeStore implements AgentIntakeStore {
  private readonly conversations = new Map<string, AgentConversation>()
  private readonly visits = new Map<string, AgentIntakeVisit>()
  private readonly sessions = new Map<string, AgentIntakeSession>()
  private readonly values = new Map<string, AgentIntakeValueUpdate>()

  createConversation(conversation: AgentConversation): Promise<void> {
    if (this.conversations.has(conversation.id)) {
      throw new Error('Conversation already exists')
    }
    this.conversations.set(conversation.id, clone(conversation))
    return Promise.resolve()
  }

  loadConversation(conversationId: string): Promise<AgentConversation | null> {
    return Promise.resolve(cloneOrNull(this.conversations.get(conversationId)))
  }

  loadConversationByStaffChat(
    staffLinkId: string,
    telegramChatId: string,
  ): Promise<AgentConversation | null> {
    const match = [...this.conversations.values()].find((conversation) =>
      conversation.staffLinkId === staffLinkId &&
      conversation.telegramChatId === telegramChatId
    )
    return Promise.resolve(cloneOrNull(match))
  }

  updateConversation(
    conversationId: string,
    expectedStateVersion: number,
    patch: Partial<AgentConversation>,
  ): Promise<AgentConversation | null> {
    const current = this.conversations.get(conversationId)
    if (!current || current.stateVersion !== expectedStateVersion) {
      return Promise.resolve(null)
    }
    const next = clone({
      ...current,
      ...patch,
      id: current.id,
      stateVersion: expectedStateVersion + 1,
    })
    this.conversations.set(conversationId, next)
    return Promise.resolve(clone(next))
  }

  createVisit(visit: AgentIntakeVisit): Promise<void> {
    if (this.visits.has(visit.id)) throw new Error('Visit already exists')
    this.visits.set(visit.id, clone(visit))
    return Promise.resolve()
  }

  loadVisit(visitId: string): Promise<AgentIntakeVisit | null> {
    return Promise.resolve(cloneOrNull(this.visits.get(visitId)))
  }

  updateVisit(
    visitId: string,
    patch: Partial<AgentIntakeVisit>,
  ): Promise<AgentIntakeVisit | null> {
    const current = this.visits.get(visitId)
    if (!current) return Promise.resolve(null)
    const next = clone({ ...current, ...patch, id: current.id })
    this.visits.set(visitId, next)
    return Promise.resolve(clone(next))
  }

  createSession(session: AgentIntakeSession): Promise<void> {
    if (this.sessions.has(session.id)) throw new Error('Session already exists')
    const active = [...this.sessions.values()].some((candidate) =>
      candidate.visitId === session.visitId &&
      activeStates.has(candidate.state)
    )
    if (active) throw new Error('Visit already has an active intake')
    this.sessions.set(session.id, clone(session))
    return Promise.resolve()
  }

  loadSession(intakeId: string): Promise<AgentIntakeSession | null> {
    return Promise.resolve(cloneOrNull(this.sessions.get(intakeId)))
  }

  updateSession(
    intakeId: string,
    expectedRowVersion: number,
    patch: Partial<AgentIntakeSession>,
  ): Promise<AgentIntakeSession | null> {
    const current = this.sessions.get(intakeId)
    if (!current || current.rowVersion !== expectedRowVersion) {
      return Promise.resolve(null)
    }
    const next = clone({
      ...current,
      ...patch,
      id: current.id,
      rowVersion: expectedRowVersion + 1,
    })
    this.sessions.set(intakeId, next)
    return Promise.resolve(clone(next))
  }

  upsertValues(values: readonly AgentIntakeValueUpdate[]): Promise<void> {
    for (const value of values) {
      this.values.set(
        `${value.intakeSessionId}:${value.fieldKey}`,
        clone(value),
      )
    }
    return Promise.resolve()
  }

  listSessions(): Promise<AgentIntakeSession[]> {
    return Promise.resolve(
      [...this.sessions.values()].map((value) => clone(value)),
    )
  }

  listValues(): Promise<AgentIntakeValueUpdate[]> {
    return Promise.resolve(
      [...this.values.values()].map((value) => clone(value)),
    )
  }

  countOperationalRows(): Promise<number> {
    return Promise.resolve(0)
  }
}

const activeStates = new Set<AgentIntakeState>([
  'collecting',
  'awaiting_clarification',
  'paused',
  'ready_for_summary',
  'awaiting_user_confirmation',
])

export function conversationFromRemote(
  row: Record<string, unknown>,
): AgentConversation {
  return {
    id: requiredText(row.id),
    staffLinkId: requiredText(row.staff_link_id),
    telegramChatId: requiredText(row.telegram_chat_id),
    stateVersion: requiredInteger(row.state_version),
    pendingAction: nullableObject(row.pending_action_json) as
      | AgentPendingAction
      | null,
    activeVisitId: optionalText(row.active_visit_id),
    createdAt: requiredText(row.created_at),
    updatedAt: requiredText(row.updated_at),
  }
}

export function sessionFromRemote(
  row: Record<string, unknown>,
): AgentIntakeSession {
  return {
    id: requiredText(row.id),
    visitId: requiredText(row.visit_id),
    staffLinkId: requiredText(row.staff_link_id),
    telegramChatId: requiredText(row.telegram_chat_id),
    schemaKey: requiredText(row.schema_key),
    schemaVersion: requiredInteger(row.schema_version),
    state: requiredText(row.state) as AgentIntakeState,
    language: requiredText(row.language) as AgentIntakeSession['language'],
    rowVersion: requiredInteger(row.row_version),
    context: {
      customerId: requiredText(row.customer_id),
      customerName: requiredText(row.customer_name),
      flockId: requiredText(row.flock_id),
      flockName: requiredText(row.flock_name),
      hatcheryId: requiredText(row.hatchery_id),
      hatcheryName: requiredText(row.hatchery_name),
      auditDate: requiredText(row.audit_date),
      layer: requiredText(row.scope),
      setterIdentity: optionalText(row.setter_identity),
      hatcherIdentity: optionalText(row.hatcher_identity),
      sectorKey: optionalText(row.sector_key) ?? 'breeder',
    },
    workingValues: objectValue(row.working_values_json),
    pendingClarification: nullableObject(row.pending_clarification_json) as
      | AgentClarification
      | null,
    summaryVersion: requiredInteger(row.summary_version),
    summarySnapshot: nullableObject(row.summary_snapshot_json) as
      | AgentSummarySnapshot
      | null,
    userConfirmedAt: optionalText(row.user_confirmed_at),
    lastToolEventId: optionalText(row.last_tool_event_id),
    createdAt: requiredText(row.created_at),
    updatedAt: requiredText(row.updated_at),
  }
}

function conversationToRemote(
  conversation: AgentConversation,
): Record<string, unknown> {
  return {
    id: conversation.id,
    staff_link_id: conversation.staffLinkId,
    telegram_chat_id: conversation.telegramChatId,
    state_version: conversation.stateVersion,
    pending_action_json: conversation.pendingAction,
    active_visit_id: conversation.activeVisitId,
    created_at: conversation.createdAt,
    updated_at: conversation.updatedAt,
  }
}

function conversationPatchToRemote(
  patch: Partial<AgentConversation>,
  nextVersion: number,
): Record<string, unknown> {
  const remote: Record<string, unknown> = { state_version: nextVersion }
  if ('pendingAction' in patch) {
    remote.pending_action_json = patch.pendingAction
  }
  if ('activeVisitId' in patch) remote.active_visit_id = patch.activeVisitId
  if (patch.updatedAt !== undefined) remote.updated_at = patch.updatedAt
  return remote
}

function visitToRemote(visit: AgentIntakeVisit): Record<string, unknown> {
  return {
    id: visit.id,
    conversation_id: visit.conversationId,
    customer_id: visit.customerId,
    flock_id: visit.flockId,
    hatchery_id: visit.hatcheryId,
    audit_date: visit.auditDate,
    state: visit.state,
    approved_session_id: visit.approvedSessionId,
    created_at: visit.createdAt,
    updated_at: visit.updatedAt,
  }
}

function visitPatchToRemote(
  patch: Partial<AgentIntakeVisit>,
): Record<string, unknown> {
  const remote: Record<string, unknown> = {}
  if (patch.state !== undefined) remote.state = patch.state
  if ('approvedSessionId' in patch) {
    remote.approved_session_id = patch.approvedSessionId
  }
  if (patch.updatedAt !== undefined) remote.updated_at = patch.updatedAt
  return remote
}

function visitFromRemote(
  row: Record<string, unknown>,
): AgentIntakeVisit {
  return {
    id: requiredText(row.id),
    conversationId: requiredText(row.conversation_id),
    customerId: requiredText(row.customer_id),
    flockId: requiredText(row.flock_id),
    hatcheryId: requiredText(row.hatchery_id),
    auditDate: requiredText(row.audit_date),
    state: requiredText(row.state) as AgentVisitState,
    approvedSessionId: optionalText(row.approved_session_id),
    createdAt: requiredText(row.created_at),
    updatedAt: requiredText(row.updated_at),
  }
}

function sessionToRemote(
  session: AgentIntakeSession,
): Record<string, unknown> {
  return {
    id: session.id,
    visit_id: session.visitId,
    staff_link_id: session.staffLinkId,
    telegram_chat_id: session.telegramChatId,
    schema_key: session.schemaKey,
    schema_version: session.schemaVersion,
    state: session.state,
    language: session.language,
    customer_id: session.context.customerId,
    customer_name: session.context.customerName,
    flock_id: session.context.flockId,
    flock_name: session.context.flockName,
    hatchery_id: session.context.hatcheryId,
    hatchery_name: session.context.hatcheryName,
    audit_date: session.context.auditDate,
    scope: session.context.layer,
    setter_identity: session.context.setterIdentity,
    hatcher_identity: session.context.hatcherIdentity,
    working_values_json: session.workingValues,
    pending_clarification_json: session.pendingClarification,
    summary_version: session.summaryVersion,
    summary_snapshot_json: session.summarySnapshot,
    user_confirmed_at: session.userConfirmedAt,
    row_version: session.rowVersion,
    last_tool_event_id: null,
    created_at: session.createdAt,
    updated_at: session.updatedAt,
  }
}

function sessionPatchToRemote(
  patch: Partial<AgentIntakeSession>,
  nextVersion: number,
): Record<string, unknown> {
  const remote: Record<string, unknown> = { row_version: nextVersion }
  if (patch.state !== undefined) remote.state = patch.state
  if (patch.workingValues !== undefined) {
    remote.working_values_json = patch.workingValues
  }
  if ('pendingClarification' in patch) {
    remote.pending_clarification_json = patch.pendingClarification
  }
  if (patch.summaryVersion !== undefined) {
    remote.summary_version = patch.summaryVersion
  }
  if ('summarySnapshot' in patch) {
    remote.summary_snapshot_json = patch.summarySnapshot
  }
  if ('userConfirmedAt' in patch) {
    remote.user_confirmed_at = patch.userConfirmedAt
  }
  if (patch.updatedAt !== undefined) remote.updated_at = patch.updatedAt
  return remote
}

function valueToRemote(
  value: AgentIntakeValueUpdate,
): Record<string, unknown> {
  return {
    id: `${value.intakeSessionId}:${value.fieldKey}`,
    intake_session_id: value.intakeSessionId,
    field_key: value.fieldKey,
    value_json: value.value,
    source_phrase: value.sourcePhrase,
    confidence: value.confidence,
    clarification_reason: value.clarificationReason,
    created_at: value.updatedAt,
    updated_at: value.updatedAt,
  }
}

function throwIfDatabaseError(result: {
  error: IntakeDatabaseError | null
}): void {
  if (result.error) throw new Error('Agent intake persistence failed')
}

function objectValue(value: unknown): Record<string, unknown> {
  const object = nullableObject(value)
  return object ?? {}
}

function nullableObject(value: unknown): Record<string, unknown> | null {
  if (value === null || value === undefined) return null
  if (typeof value === 'string') {
    try {
      return nullableObject(JSON.parse(value))
    } catch (_) {
      return null
    }
  }
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function optionalText(value: unknown): string | null {
  const text = value?.toString().trim()
  return text ? text : null
}

function requiredText(value: unknown): string {
  const text = optionalText(value)
  if (!text) throw new Error('Agent intake row is invalid')
  return text
}

function requiredInteger(value: unknown): number {
  const number = typeof value === 'number'
    ? value
    : Number.parseInt(value?.toString() ?? '', 10)
  if (!Number.isInteger(number)) throw new Error('Agent intake row is invalid')
  return number
}

function clone<T>(value: T): T {
  return structuredClone(value)
}

function cloneOrNull<T>(value: T | undefined): T | null {
  return value === undefined ? null : clone(value)
}
