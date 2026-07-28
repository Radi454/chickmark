import { assertEquals } from 'jsr:@std/assert'

import {
  createSupabasePasgarContextResolver,
  createSupabasePasgarIntakeStore,
  type PasgarIntakeSession,
  type PasgarIntakeTurn,
  type PasgarStoreClient,
} from './pasgar_store.ts'

type JsonRecord = Record<string, unknown>

class FakeClient {
  inserts: Record<string, unknown[]> = {}
  upserts: Record<string, { rows: unknown; onConflict: string | undefined }> =
    {}
  updates: Record<string, JsonRecord[]> = {}
  duplicateUpdateIds = new Set<string>()

  constructor(readonly tables: Record<string, JsonRecord[]> = {}) {}

  from(table: string) {
    const filters: Record<string, unknown> = {}
    const inFilters: Record<string, readonly unknown[]> = {}
    let limitCount: number | null = null
    const matchingRows = () => {
      let rows = [...(this.tables[table] ?? [])]
      rows = rows.filter((row) =>
        Object.entries(filters).every(([key, value]) => row[key] === value)
      )
      rows = rows.filter((row) =>
        Object.entries(inFilters).every(([key, values]) =>
          values.includes(row[key])
        )
      )
      return limitCount === null ? rows : rows.slice(0, limitCount)
    }
    const query = {
      select(_columns: string) {
        return query
      },
      eq(column: string, value: unknown) {
        filters[column] = value
        return query
      },
      in(column: string, values: readonly unknown[]) {
        inFilters[column] = values
        return query
      },
      not(_column: string, _operator: string, _value: unknown) {
        return query
      },
      order(_column: string, _options: { ascending: boolean }) {
        return query
      },
      limit(count: number) {
        limitCount = count
        return Promise.resolve({ data: matchingRows(), error: null })
      },
      maybeSingle() {
        const rows = matchingRows()
        return Promise.resolve({
          data: rows.length === 1 ? rows[0] : null,
          error: rows.length > 1 ? { message: 'multiple' } : null,
        })
      },
      insert: (rows: unknown) => {
        const records = Array.isArray(rows) ? rows : [rows]
        const updateId = (records[0] as JsonRecord).telegram_update_id
        if (
          table === 'agent_intake_turns' &&
          typeof updateId === 'string' &&
          this.duplicateUpdateIds.has(updateId)
        ) {
          return Promise.resolve({
            data: null,
            error: { message: 'duplicate', code: '23505' },
          })
        }
        this.inserts[table] ??= []
        this.inserts[table].push(...records)
        return Promise.resolve({ data: null, error: null })
      },
      upsert: (
        rows: unknown,
        options?: { onConflict?: string },
      ) => {
        this.upserts[table] = {
          rows,
          onConflict: options?.onConflict,
        }
        return Promise.resolve({ data: null, error: null })
      },
      update: (values: JsonRecord) => ({
        eq: (column: string, value: unknown) => {
          this.updates[table] ??= []
          this.updates[table].push({ ...values, [`where_${column}`]: value })
          return Promise.resolve({ data: null, error: null })
        },
      }),
      then<TResult1 = unknown, TResult2 = never>(
        onFulfilled?:
          | ((
            value: { data: JsonRecord[]; error: null },
          ) => TResult1 | PromiseLike<TResult1>)
          | null,
        onRejected?:
          | ((reason: unknown) => TResult2 | PromiseLike<TResult2>)
          | null,
      ) {
        return Promise.resolve({ data: matchingRows(), error: null }).then(
          onFulfilled,
          onRejected,
        )
      },
    }
    return query
  }
}

function remoteSessionRow(): JsonRecord {
  return {
    id: 'intake-1',
    staff_link_id: 'staff-1',
    telegram_chat_id: 'chat-1',
    schema_key: 'chicks.pasgar',
    schema_version: 1,
    state: 'collecting',
    language: 'en',
    customer_id: 'customer-1',
    customer_name: 'Customer One',
    flock_id: 'flock-1',
    flock_name: 'Flock One',
    hatchery_id: 'hatchery-1',
    hatchery_name: 'Hatchery One',
    audit_date: '2026-07-28',
    scope: 'pool',
    setter_identity: null,
    hatcher_identity: null,
    working_values_json: { pasgarSampleSize: 40 },
    pending_clarification_json: null,
    summary_version: 0,
    summary_snapshot_json: null,
    user_confirmed_at: null,
    approved_session_id: null,
    approved_panel_row_id: null,
    reviewed_by: null,
    reviewed_at: null,
    rejection_reason: null,
    created_at: '2026-07-28T10:00:00.000Z',
    updated_at: '2026-07-28T10:00:00.000Z',
  }
}

function session(): PasgarIntakeSession {
  return {
    id: 'intake-1',
    staffLinkId: 'staff-1',
    chatId: 'chat-1',
    schemaKey: 'chicks.pasgar',
    schemaVersion: 1,
    state: 'collecting',
    language: 'en',
    context: {
      customerId: 'customer-1',
      customerName: 'Customer One',
      flockId: 'flock-1',
      flockName: 'Flock One',
      hatcheryId: 'hatchery-1',
      hatcheryName: 'Hatchery One',
      auditDate: '2026-07-28',
      scope: 'pool',
      setterIdentity: null,
      hatcherIdentity: null,
    },
    workingValues: { pasgarSampleSize: 40 },
    pendingClarification: null,
    summaryVersion: 0,
    summarySnapshot: null,
    userConfirmedAt: null,
    createdAt: '2026-07-28T10:00:00.000Z',
    updatedAt: '2026-07-28T10:00:00.000Z',
  }
}

Deno.test('Supabase store maps the active snake-case session', async () => {
  const client = new FakeClient({
    agent_intake_sessions: [remoteSessionRow()],
  })
  const store = createSupabasePasgarIntakeStore(
    client as unknown as PasgarStoreClient,
  )

  const active = await store.findActiveSession('staff-1', 'chat-1')

  assertEquals(active, session())
})

Deno.test('Supabase store creates a durable versioned session row', async () => {
  const client = new FakeClient()
  const store = createSupabasePasgarIntakeStore(
    client as unknown as PasgarStoreClient,
  )

  await store.createSession(session())

  const expected = remoteSessionRow()
  delete expected.approved_session_id
  delete expected.approved_panel_row_id
  delete expected.reviewed_by
  delete expected.reviewed_at
  delete expected.rejection_reason
  assertEquals(client.inserts.agent_intake_sessions, [expected])
})

Deno.test('Supabase store upserts normalized values by session and field', async () => {
  const client = new FakeClient()
  const store = createSupabasePasgarIntakeStore(
    client as unknown as PasgarStoreClient,
  )

  await store.saveValues('intake-1', [
    {
      fieldKey: 'pasgarSampleSize',
      value: 40,
      sourcePhrase: 'sample 40',
      confidence: 0.99,
      updatedAt: '2026-07-28T10:00:00.000Z',
    },
    {
      fieldKey: 'pasgarReflexesCount',
      value: 2,
      sourcePhrase: 'reflex 2',
      confidence: 0.98,
      updatedAt: '2026-07-28T10:00:00.000Z',
    },
  ])

  assertEquals(
    client.upserts.agent_intake_values.onConflict,
    'intake_session_id,field_key',
  )
  const rows = client.upserts.agent_intake_values.rows as JsonRecord[]
  assertEquals(rows.map((row) => row.value_json), [40, 2])
})

Deno.test('Supabase store treats a duplicate inbound update as idempotent', async () => {
  const client = new FakeClient()
  client.duplicateUpdateIds.add('update-1')
  const store = createSupabasePasgarIntakeStore(
    client as unknown as PasgarStoreClient,
  )
  const turn: PasgarIntakeTurn = {
    id: 'turn-1',
    sessionId: 'intake-1',
    direction: 'inbound',
    updateId: 'update-1',
    messageId: 'message-1',
    text: 'sample 40',
    language: 'en',
    intent: 'provide_data',
    createdAt: '2026-07-28T10:00:00.000Z',
  }

  assertEquals(await store.saveInboundTurn(turn), 'duplicate')
})

Deno.test('context resolver scopes flocks and hatcheries to the selected customer', async () => {
  const client = new FakeClient({
    customers: [
      { id: 'customer-1', name: 'Customer One' },
      { id: 'customer-2', name: 'Customer Two' },
    ],
    flocks: [
      { id: 'flock-1', customer_id: 'customer-1', flock_id: 'Flock One' },
      { id: 'flock-2', customer_id: 'customer-2', flock_id: 'Flock Two' },
    ],
    hatcheries: [
      {
        id: 'hatchery-1',
        customer_id: 'customer-1',
        name: 'Hatchery One',
      },
      {
        id: 'hatchery-2',
        customer_id: 'customer-2',
        name: 'Hatchery Two',
      },
    ],
  })
  const resolver = createSupabasePasgarContextResolver(
    client as unknown as PasgarStoreClient,
  )

  assertEquals(await resolver.listCustomers('staff-1'), [
    { id: 'customer-1', label: 'Customer One' },
    { id: 'customer-2', label: 'Customer Two' },
  ])
  assertEquals(await resolver.listFlocks('staff-1', 'customer-2'), [
    { id: 'flock-2', label: 'Flock Two' },
  ])
  assertEquals(await resolver.listHatcheries('staff-1', 'customer-1'), [
    { id: 'hatchery-1', label: 'Hatchery One' },
  ])
})
