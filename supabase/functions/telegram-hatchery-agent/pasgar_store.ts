// Legacy Pasgar persistence adapter retained while existing intake rows remain
// reviewable. New station intake writes use agent_intake_store.ts.
import {
  PASGAR_SCHEMA_KEY,
  PASGAR_SCHEMA_VERSION,
  type PasgarFieldKey,
  type PasgarLanguage,
  type PasgarWorkingValues,
} from './pasgar_intake_schema.ts'

export type PasgarIntakeState =
  | 'collecting'
  | 'awaiting_clarification'
  | 'paused'
  | 'ready_for_summary'
  | 'awaiting_user_confirmation'
  | 'awaiting_admin_review'
  | 'approved'
  | 'rejected'
  | 'cancelled'

export type PasgarScope = 'pool' | 'setter_hatcher'

export interface PasgarContextChoice {
  id: string
  label: string
}

export interface PasgarPendingClarification {
  fieldKey: string | null
  sourcePhrase: string | null
  messageEn: string
  messageAr: string
  options?: readonly PasgarContextChoice[]
}

export interface PasgarSummarySnapshot {
  version: number
  values: PasgarWorkingValues
  generatedAt: string
}

export interface PasgarIntakeSession {
  id: string
  staffLinkId: string
  chatId: string
  schemaKey: typeof PASGAR_SCHEMA_KEY
  schemaVersion: typeof PASGAR_SCHEMA_VERSION
  state: PasgarIntakeState
  language: PasgarLanguage
  context: {
    customerId: string | null
    customerName: string | null
    flockId: string | null
    flockName: string | null
    hatcheryId: string | null
    hatcheryName: string | null
    auditDate: string
    scope: PasgarScope | null
    setterIdentity: string | null
    hatcherIdentity: string | null
  }
  workingValues: PasgarWorkingValues
  pendingClarification: PasgarPendingClarification | null
  summaryVersion: number
  summarySnapshot: PasgarSummarySnapshot | null
  userConfirmedAt: string | null
  createdAt: string
  updatedAt: string
}

export interface PasgarIntakeTurn {
  id: string
  sessionId: string
  direction: 'inbound' | 'outbound'
  updateId: string | null
  messageId: string | null
  text: string
  language: PasgarLanguage
  intent: string | null
  createdAt: string
}

export interface PasgarValueUpdate {
  fieldKey: PasgarFieldKey
  value: number
  sourcePhrase: string
  confidence: number
  updatedAt: string
}

export interface PasgarIntakeStore {
  findActiveSession(
    staffLinkId: string,
    chatId: string,
  ): Promise<PasgarIntakeSession | null>
  createSession(session: PasgarIntakeSession): Promise<void>
  saveInboundTurn(turn: PasgarIntakeTurn): Promise<'inserted' | 'duplicate'>
  saveOutboundTurn(turn: PasgarIntakeTurn): Promise<void>
  saveValues(sessionId: string, values: PasgarValueUpdate[]): Promise<void>
  updateSession(
    sessionId: string,
    patch: Partial<PasgarIntakeSession>,
  ): Promise<void>
}

export interface PasgarContextResolver {
  listCustomers(staffLinkId: string): Promise<readonly PasgarContextChoice[]>
  listFlocks(
    staffLinkId: string,
    customerId: string,
  ): Promise<readonly PasgarContextChoice[]>
  listHatcheries(
    staffLinkId: string,
    customerId: string,
  ): Promise<readonly PasgarContextChoice[]>
  listSetters(
    staffLinkId: string,
    customerId: string,
    hatcheryId: string,
  ): Promise<readonly PasgarContextChoice[]>
  listHatchers(
    staffLinkId: string,
    customerId: string,
    hatcheryId: string,
  ): Promise<readonly PasgarContextChoice[]>
}

interface PasgarStoreError {
  message: string
  code?: string
}

interface PasgarStoreResult<T = unknown> {
  data: T | null
  error: PasgarStoreError | null
}

interface PasgarStoreUpdateFilter {
  eq(column: string, value: unknown): Promise<PasgarStoreResult>
}

export interface PasgarStoreQuery {
  select(columns: string): PasgarStoreQuery
  eq(column: string, value: unknown): PasgarStoreQuery
  in(column: string, values: readonly unknown[]): PasgarStoreQuery
  not(column: string, operator: string, value: unknown): PasgarStoreQuery
  order(column: string, options: { ascending: boolean }): PasgarStoreQuery
  limit(
    count: number,
  ): Promise<PasgarStoreResult<Record<string, unknown>[]>>
  maybeSingle(): Promise<PasgarStoreResult<Record<string, unknown>>>
  insert(values: unknown): Promise<PasgarStoreResult>
  upsert(
    values: unknown,
    options?: { onConflict?: string },
  ): Promise<PasgarStoreResult>
  update(values: unknown): PasgarStoreUpdateFilter
}

export interface PasgarStoreClient {
  from(table: string): PasgarStoreQuery
}

export function createSupabasePasgarIntakeStore(
  client: PasgarStoreClient,
): PasgarIntakeStore {
  return {
    async findActiveSession(staffLinkId, chatId) {
      const result = await client
        .from('agent_intake_sessions')
        .select('*')
        .eq('staff_link_id', staffLinkId)
        .eq('telegram_chat_id', chatId)
        .in('state', activeStates)
        .order('updated_at', { ascending: false })
        .limit(1)
      throwIfError(result, 'load active Pasgar intake')
      const row = result.data?.[0]
      return row ? sessionFromRemote(row) : null
    },

    async createSession(session) {
      const result = await client
        .from('agent_intake_sessions')
        .insert(sessionToRemote(session))
      throwIfError(result, 'create Pasgar intake')
    },

    async saveInboundTurn(turn) {
      const result = await client
        .from('agent_intake_turns')
        .insert(turnToRemote(turn))
      if (result.error?.code === '23505') return 'duplicate'
      throwIfError(result, 'save inbound Pasgar turn')
      return 'inserted'
    },

    async saveOutboundTurn(turn) {
      const result = await client
        .from('agent_intake_turns')
        .insert(turnToRemote(turn))
      throwIfError(result, 'save outbound Pasgar turn')
    },

    async saveValues(sessionId, values) {
      if (values.length === 0) return
      const result = await client
        .from('agent_intake_values')
        .upsert(
          values.map((value) => valueToRemote(sessionId, value)),
          { onConflict: 'intake_session_id,field_key' },
        )
      throwIfError(result, 'save Pasgar values')
    },

    async updateSession(sessionId, patch) {
      const result = await client
        .from('agent_intake_sessions')
        .update(sessionPatchToRemote(patch))
        .eq('id', sessionId)
      throwIfError(result, 'update Pasgar intake')
    },
  }

  function valueToRemote(
    sessionId: string,
    value: PasgarValueUpdate,
  ): Record<string, unknown> {
    return {
      id: `${sessionId}:${value.fieldKey}`,
      intake_session_id: sessionId,
      field_key: value.fieldKey,
      value_json: value.value,
      source_phrase: value.sourcePhrase,
      confidence: value.confidence,
      clarification_reason: null,
      created_at: value.updatedAt,
      updated_at: value.updatedAt,
    }
  }
}

export function createSupabasePasgarContextResolver(
  client: PasgarStoreClient,
): PasgarContextResolver {
  return {
    async listCustomers(_staffLinkId) {
      return loadChoices(
        client.from('customers').select('id, name').order('name', {
          ascending: true,
        }),
        'name',
        'load Pasgar customers',
      )
    },

    async listFlocks(_staffLinkId, customerId) {
      return loadChoices(
        client
          .from('flocks')
          .select('id, flock_id')
          .eq('customer_id', customerId)
          .order('flock_id', { ascending: true }),
        'flock_id',
        'load Pasgar flocks',
      )
    },

    async listHatcheries(_staffLinkId, customerId) {
      return loadChoices(
        client
          .from('hatcheries')
          .select('id, name')
          .eq('customer_id', customerId)
          .order('name', { ascending: true }),
        'name',
        'load Pasgar hatcheries',
      )
    },

    async listSetters(_staffLinkId, customerId, hatcheryId) {
      return loadDistinctMachineChoices(
        client,
        customerId,
        hatcheryId,
        'setter',
      )
    },

    async listHatchers(_staffLinkId, customerId, hatcheryId) {
      return loadDistinctMachineChoices(
        client,
        customerId,
        hatcheryId,
        'hatcher',
      )
    },
  }
}

async function loadChoices(
  query: PasgarStoreQuery,
  labelColumn: string,
  operation: string,
): Promise<PasgarContextChoice[]> {
  const result = await (query as unknown as Promise<
    PasgarStoreResult<Record<string, unknown>[]>
  >)
  throwIfError(result, operation)
  return (result.data ?? []).flatMap((row) => {
    const id = nonEmptyString(row.id)
    const label = nonEmptyString(row[labelColumn])
    return id && label ? [{ id, label }] : []
  })
}

async function loadDistinctMachineChoices(
  client: PasgarStoreClient,
  customerId: string,
  hatcheryId: string,
  column: 'setter' | 'hatcher',
): Promise<PasgarContextChoice[]> {
  const query = client
    .from('chick_quality')
    .select(column)
    .eq('customer_id', customerId)
    .eq('hatchery_id', hatcheryId)
    .not(column, 'is', null)
    .order(column, { ascending: true })
  const result = await (query as unknown as Promise<
    PasgarStoreResult<Record<string, unknown>[]>
  >)
  throwIfError(result, `load Pasgar ${column} choices`)
  const seen = new Set<string>()
  return (result.data ?? []).flatMap((row) => {
    const label = nonEmptyString(row[column])
    if (!label || seen.has(label)) return []
    seen.add(label)
    return [{ id: label, label }]
  })
}

function sessionFromRemote(row: Record<string, unknown>): PasgarIntakeSession {
  const schemaKey = nonEmptyString(row.schema_key)
  const schemaVersion = integer(row.schema_version)
  if (
    schemaKey !== PASGAR_SCHEMA_KEY ||
    schemaVersion !== PASGAR_SCHEMA_VERSION
  ) {
    throw new Error('Unsupported Pasgar intake schema row')
  }

  return {
    id: requiredString(row.id, 'id'),
    staffLinkId: requiredString(row.staff_link_id, 'staff_link_id'),
    chatId: requiredString(row.telegram_chat_id, 'telegram_chat_id'),
    schemaKey: PASGAR_SCHEMA_KEY,
    schemaVersion: PASGAR_SCHEMA_VERSION,
    state: requiredString(row.state, 'state') as PasgarIntakeState,
    language: requiredString(row.language, 'language') as PasgarLanguage,
    context: {
      customerId: nonEmptyString(row.customer_id),
      customerName: nonEmptyString(row.customer_name),
      flockId: nonEmptyString(row.flock_id),
      flockName: nonEmptyString(row.flock_name),
      hatcheryId: nonEmptyString(row.hatchery_id),
      hatcheryName: nonEmptyString(row.hatchery_name),
      auditDate: requiredString(row.audit_date, 'audit_date'),
      scope: nonEmptyString(row.scope) as PasgarScope | null,
      setterIdentity: nonEmptyString(row.setter_identity),
      hatcherIdentity: nonEmptyString(row.hatcher_identity),
    },
    workingValues: jsonObject(row.working_values_json) as PasgarWorkingValues,
    pendingClarification: nullableJsonObject(
      row.pending_clarification_json,
    ) as PasgarPendingClarification | null,
    summaryVersion: integer(row.summary_version) ?? 0,
    summarySnapshot: nullableJsonObject(
      row.summary_snapshot_json,
    ) as unknown as PasgarSummarySnapshot | null,
    userConfirmedAt: nonEmptyString(row.user_confirmed_at),
    createdAt: requiredString(row.created_at, 'created_at'),
    updatedAt: requiredString(row.updated_at, 'updated_at'),
  }
}

function sessionToRemote(
  session: PasgarIntakeSession,
): Record<string, unknown> {
  return {
    id: session.id,
    staff_link_id: session.staffLinkId,
    telegram_chat_id: session.chatId,
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
    scope: session.context.scope,
    setter_identity: session.context.setterIdentity,
    hatcher_identity: session.context.hatcherIdentity,
    working_values_json: session.workingValues,
    pending_clarification_json: session.pendingClarification,
    summary_version: session.summaryVersion,
    summary_snapshot_json: session.summarySnapshot,
    user_confirmed_at: session.userConfirmedAt,
    created_at: session.createdAt,
    updated_at: session.updatedAt,
  }
}

function sessionPatchToRemote(
  patch: Partial<PasgarIntakeSession>,
): Record<string, unknown> {
  const remote: Record<string, unknown> = {}
  if (patch.state !== undefined) remote.state = patch.state
  if (patch.language !== undefined) remote.language = patch.language
  if (patch.workingValues !== undefined) {
    remote.working_values_json = patch.workingValues
  }
  if (patch.pendingClarification !== undefined) {
    remote.pending_clarification_json = patch.pendingClarification
  }
  if (patch.summaryVersion !== undefined) {
    remote.summary_version = patch.summaryVersion
  }
  if (patch.summarySnapshot !== undefined) {
    remote.summary_snapshot_json = patch.summarySnapshot
  }
  if (patch.userConfirmedAt !== undefined) {
    remote.user_confirmed_at = patch.userConfirmedAt
  }
  if (patch.updatedAt !== undefined) remote.updated_at = patch.updatedAt
  if (patch.context !== undefined) {
    remote.customer_id = patch.context.customerId
    remote.customer_name = patch.context.customerName
    remote.flock_id = patch.context.flockId
    remote.flock_name = patch.context.flockName
    remote.hatchery_id = patch.context.hatcheryId
    remote.hatchery_name = patch.context.hatcheryName
    remote.audit_date = patch.context.auditDate
    remote.scope = patch.context.scope
    remote.setter_identity = patch.context.setterIdentity
    remote.hatcher_identity = patch.context.hatcherIdentity
  }
  return remote
}

function turnToRemote(turn: PasgarIntakeTurn): Record<string, unknown> {
  return {
    id: turn.id,
    intake_session_id: turn.sessionId,
    direction: turn.direction,
    telegram_update_id: turn.updateId,
    telegram_message_id: turn.messageId,
    text: turn.text,
    language: turn.language,
    intent: turn.intent,
    delivery_status: turn.direction === 'outbound' ? 'pending' : 'received',
    attachment_kind: null,
    attachment_file_name: null,
    attachment_mime_type: null,
    attachment_remote_path: null,
    created_at: turn.createdAt,
  }
}

function jsonObject(value: unknown): Record<string, unknown> {
  const decoded = decodeJson(value)
  if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) {
    throw new Error('Expected a JSON object')
  }
  return decoded as Record<string, unknown>
}

function nullableJsonObject(value: unknown): Record<string, unknown> | null {
  if (value === null || value === undefined) return null
  return jsonObject(value)
}

function decodeJson(value: unknown): unknown {
  if (typeof value !== 'string') return value
  try {
    return JSON.parse(value)
  } catch (_) {
    throw new Error('Invalid JSON from Pasgar intake storage')
  }
}

function throwIfError(
  result: PasgarStoreResult,
  operation: string,
): void {
  if (result.error) {
    throw new Error(`Could not ${operation}: ${result.error.message}`)
  }
}

function requiredString(value: unknown, field: string): string {
  const text = nonEmptyString(value)
  if (!text) throw new Error(`Missing Pasgar intake ${field}`)
  return text
}

function nonEmptyString(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : null
}

function integer(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) ? value : null
}

const activeStates: readonly PasgarIntakeState[] = [
  'collecting',
  'awaiting_clarification',
  'paused',
  'ready_for_summary',
  'awaiting_user_confirmation',
]
