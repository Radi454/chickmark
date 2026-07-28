import { assertEquals } from '@std/assert'

import type { AgentScope, AgentToolResult } from './agent_protocol.ts'
import {
  createAgentAuditToolHandlers,
  createSupabaseAgentAuditStore,
} from './agent_audit_tools.ts'
import { executeAgentTool } from './agent_tools.ts'

interface AuditRow {
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

interface AuditStore {
  findFlockCustomerId(flockId: string): Promise<string | null>
  findLatestAuditListResult(conversationId: string): Promise<unknown | null>
  listAudits(input: {
    customerId: string
    flockId: string | null
    limit: number
  }): Promise<{ rows: readonly AuditRow[]; truncated: boolean }>
  findAudit(
    auditId: string,
    allowedCustomerIds: readonly string[],
  ): Promise<AuditRow | null>
}

interface FixtureAuditStore extends AuditStore {
  latestAuditListResult: unknown | null
  listInputs: { customerId: string; flockId: string | null; limit: number }[]
  rows: AuditRow[]
  selectedAuditIds: string[]
}

const scope: AgentScope = {
  staffLinkId: 'staff-a',
  accessRole: 'customer',
  allowedCustomerIds: ['customer-a'],
}

const auditRows: readonly AuditRow[] = [
  {
    id: 'audit-new',
    customerId: 'customer-a',
    flockId: 'flock-a',
    hatcheryId: 'hatchery-a',
    date: '2026-07-28',
    status: 'in_progress',
    customerName: 'الغريب',
    flockName: 'السلام',
    hatcheryName: 'الغريب',
    selectedStationKeys: ['egg', 'chicks'],
    stationsCompleted: ['egg'],
    createdAt: '2026-07-28T12:00:00Z',
    completedAt: null,
    breed: 'Ross308',
    flockAgeWeeks: 38,
    findings: null,
    scorecard: null,
    notes: null,
  },
  {
    id: 'audit-completed',
    customerId: 'customer-a',
    flockId: 'flock-a',
    hatcheryId: 'hatchery-a',
    date: '2026-06-23',
    status: 'completed',
    customerName: 'الغريب',
    flockName: 'السلام',
    hatcheryName: 'الغريب',
    selectedStationKeys: ['egg', 'chicks', 'hatch_analysis_egg_breakouts'],
    stationsCompleted: ['egg', 'chicks', 'hatch_analysis_egg_breakouts'],
    createdAt: '2026-06-23T13:04:26Z',
    completedAt: '2026-06-23T18:07:00Z',
    breed: 'Ross308',
    flockAgeWeeks: 33,
    findings: { total: 3 },
    scorecard: { score: 91 },
    notes: 'reviewed',
  },
]

function fixtureStore(): FixtureAuditStore {
  const listInputs: {
    customerId: string
    flockId: string | null
    limit: number
  }[] = []
  const rows: AuditRow[] = [
    ...auditRows,
    {
      ...auditRows[0],
      id: 'audit-customer-b',
      customerId: 'customer-b',
      flockId: 'flock-b',
    },
  ]
  const selectedAuditIds: string[] = []
  const store: FixtureAuditStore = {
    latestAuditListResult: null,
    listInputs,
    rows,
    selectedAuditIds,
    findFlockCustomerId: (flockId) =>
      Promise.resolve(
        flockId === 'flock-a'
          ? 'customer-a'
          : flockId === 'flock-b'
          ? 'customer-b'
          : null,
      ),
    findLatestAuditListResult: () =>
      Promise.resolve(store.latestAuditListResult),
    listAudits(input) {
      listInputs.push(input)
      return Promise.resolve({ rows: store.rows, truncated: false })
    },
    findAudit(auditId, allowedCustomerIds) {
      selectedAuditIds.push(auditId)
      return Promise.resolve(
        store.rows.find((row) =>
          row.id === auditId && allowedCustomerIds.includes(row.customerId)
        ) ?? null,
      )
    },
  }
  return store
}

async function call(
  store: AuditStore,
  name: string,
  arguments_: Record<string, unknown>,
  selectedScope: AgentScope = scope,
  conversationId = 'conversation-a',
): Promise<AgentToolResult> {
  return executeAgentTool(
    { id: `call-${name}`, name, arguments: arguments_ },
    {
      scope: selectedScope,
      conversationId,
      activeVisitId: null,
      evidence: { record: () => undefined },
      handlers: createAgentAuditToolHandlers(store),
    },
  )
}

Deno.test('audit list includes every status newest first and defaults to ten', async () => {
  const store = fixtureStore()
  assertEquals(
    await call(store, 'list_customer_audits', { customerId: 'customer-a' }),
    {
      ok: true,
      code: 'ok',
      data: {
        customerId: 'customer-a',
        flockId: null,
        audits: [
          {
            id: 'audit-new',
            date: '2026-07-28',
            status: 'in_progress',
            customerName: 'الغريب',
            flockName: 'السلام',
            hatcheryName: 'الغريب',
            selectedStationKeys: ['egg', 'chicks'],
            stationsCompleted: ['egg'],
            createdAt: '2026-07-28T12:00:00Z',
            completedAt: null,
          },
          {
            id: 'audit-completed',
            date: '2026-06-23',
            status: 'completed',
            customerName: 'الغريب',
            flockName: 'السلام',
            hatcheryName: 'الغريب',
            selectedStationKeys: [
              'egg',
              'chicks',
              'hatch_analysis_egg_breakouts',
            ],
            stationsCompleted: [
              'egg',
              'chicks',
              'hatch_analysis_egg_breakouts',
            ],
            createdAt: '2026-06-23T13:04:26Z',
            completedAt: '2026-06-23T18:07:00Z',
          },
        ],
        truncated: false,
      },
    },
  )
  assertEquals(store.listInputs, [{
    customerId: 'customer-a',
    flockId: null,
    limit: 10,
  }])
})

Deno.test('audit list honors its limit and reports truncation', async () => {
  const store = fixtureStore()
  assertEquals(
    await call(store, 'list_customer_audits', {
      customerId: 'customer-a',
      limit: 1,
    }),
    {
      ok: true,
      code: 'ok',
      data: {
        customerId: 'customer-a',
        flockId: null,
        audits: [{
          id: 'audit-new',
          date: '2026-07-28',
          status: 'in_progress',
          customerName: 'الغريب',
          flockName: 'السلام',
          hatcheryName: 'الغريب',
          selectedStationKeys: ['egg', 'chicks'],
          stationsCompleted: ['egg'],
          createdAt: '2026-07-28T12:00:00Z',
          completedAt: null,
        }],
        truncated: true,
      },
    },
  )
  assertEquals(store.listInputs[0].limit, 1)
})

Deno.test('audit list denies a flock outside the requested customer', async () => {
  assertEquals(
    await call(fixtureStore(), 'list_customer_audits', {
      customerId: 'customer-a',
      flockId: 'flock-b',
    }),
    { ok: false, code: 'scope_denied', data: null },
  )
})

Deno.test('unknown and out-of-scope audit IDs have indistinguishable denials', async () => {
  const store = fixtureStore()
  const unknown = await call(store, 'get_audit_summary', { auditId: 'unknown' })
  const customerB = await call(store, 'get_audit_summary', {
    auditId: 'audit-customer-b',
  })
  assertEquals(unknown, { ok: false, code: 'scope_denied', data: null })
  assertEquals(customerB, unknown)
})

Deno.test('audit summary returns verified identity and decoded detail', async () => {
  assertEquals(
    await call(fixtureStore(), 'get_audit_summary', {
      auditId: 'audit-completed',
    }),
    {
      ok: true,
      code: 'ok',
      data: {
        id: 'audit-completed',
        customerId: 'customer-a',
        flockId: 'flock-a',
        hatcheryId: 'hatchery-a',
        date: '2026-06-23',
        status: 'completed',
        customerName: 'الغريب',
        flockName: 'السلام',
        hatcheryName: 'الغريب',
        selectedStationKeys: ['egg', 'chicks', 'hatch_analysis_egg_breakouts'],
        stationsCompleted: ['egg', 'chicks', 'hatch_analysis_egg_breakouts'],
        createdAt: '2026-06-23T13:04:26Z',
        completedAt: '2026-06-23T18:07:00Z',
        breed: 'Ross308',
        flockAgeWeeks: 33,
        findings: { total: 3 },
        scorecard: { score: 91 },
        notes: 'reviewed',
      },
    },
  )
})

Deno.test('persisted audit options keep their ordinal after a newer audit is inserted', async () => {
  const store = fixtureStore()
  const persistedList = await call(store, 'list_customer_audits', {
    customerId: 'customer-a',
  })
  store.latestAuditListResult = persistedList
  store.rows.unshift({
    ...auditRows[0],
    id: 'audit-inserted-later',
    date: '2026-07-29',
    createdAt: '2026-07-29T12:00:00Z',
  })

  const selected = await call(store, 'select_audit_option', { position: 2 })

  assertEquals(selected.ok, true)
  assertEquals(selected.data?.id, 'audit-completed')
  assertEquals(store.listInputs.length, 1)
  assertEquals(store.selectedAuditIds.at(-1), 'audit-completed')
})

Deno.test('missing malformed and out-of-range audit snapshots fail closed', async () => {
  const malformedSnapshots: Array<{
    snapshot: unknown | null
    position: number
  }> = [
    { snapshot: null, position: 1 },
    { snapshot: {}, position: 1 },
    {
      snapshot: {
        ok: true,
        code: 'ok',
        data: { customerId: 'customer-a', audits: 'not-an-array' },
      },
      position: 1,
    },
    {
      snapshot: {
        ok: true,
        code: 'ok',
        data: {
          customerId: 'customer-a',
          audits: Array.from({ length: 21 }, (_, index) => ({
            id: `audit-${index}`,
          })),
        },
      },
      position: 1,
    },
    {
      snapshot: {
        ok: true,
        code: 'ok',
        data: { customerId: 'customer-a', audits: [{ id: 'audit-new' }] },
      },
      position: 2,
    },
    {
      snapshot: {
        ok: true,
        code: 'ok',
        data: { customerId: 'customer-a', audits: [{}] },
      },
      position: 1,
    },
  ]

  for (const fixture of malformedSnapshots) {
    const store = fixtureStore()
    store.latestAuditListResult = fixture.snapshot
    assertEquals(
      await call(store, 'select_audit_option', {
        position: fixture.position,
      }),
      { ok: false, code: 'scope_denied', data: null },
    )
  }
})

Deno.test('changed scope unknown audits and unauthorized audits fail identically', async () => {
  const snapshot = (customerId: string, auditId: string) => ({
    ok: true,
    code: 'ok',
    data: { customerId, audits: [{ id: auditId }] },
  })

  const changedScopeStore = fixtureStore()
  changedScopeStore.latestAuditListResult = snapshot(
    'customer-a',
    'audit-new',
  )
  assertEquals(
    await call(
      changedScopeStore,
      'select_audit_option',
      { position: 1 },
      {
        staffLinkId: 'staff-b',
        accessRole: 'customer',
        allowedCustomerIds: ['customer-b'],
      },
    ),
    { ok: false, code: 'scope_denied', data: null },
  )

  for (const auditId of ['missing-audit', 'audit-customer-b']) {
    const store = fixtureStore()
    store.latestAuditListResult = snapshot('customer-a', auditId)
    assertEquals(
      await call(store, 'select_audit_option', { position: 1 }),
      { ok: false, code: 'scope_denied', data: null },
    )
  }
})

interface RecordedAuditQuery {
  table: string
  selectedColumns: string | null
  equals: Record<string, unknown>
  included: Record<string, readonly unknown[]>
  orders: Array<{
    column: string
    ascending: boolean
    nullsFirst?: boolean
  }>
  limit: number | null
  range: { from: number; to: number } | null
}

class FakeAuditClient {
  readonly queries: RecordedAuditQuery[] = []

  constructor(readonly tables: Record<string, Record<string, unknown>[]>) {}

  from(table: string) {
    const recorded: RecordedAuditQuery = {
      table,
      selectedColumns: null,
      equals: {},
      included: {},
      orders: [],
      limit: null,
      range: null,
    }
    this.queries.push(recorded)
    const matching = () => {
      const rows = (this.tables[table] ?? []).filter((row) =>
        Object.entries(recorded.equals).every(([column, value]) =>
          row[column] === value
        ) &&
        Object.entries(recorded.included).every(([column, values]) =>
          values.includes(row[column])
        )
      )
      return rows.slice().sort((left, right) => {
        for (const order of recorded.orders) {
          const leftValue = left[order.column]
          const rightValue = right[order.column]
          if (leftValue === rightValue) continue
          if (leftValue === null || leftValue === undefined) {
            return order.nullsFirst === true ? -1 : 1
          }
          if (rightValue === null || rightValue === undefined) {
            return order.nullsFirst === true ? 1 : -1
          }
          const comparison = String(leftValue).localeCompare(String(rightValue))
          if (comparison !== 0) {
            return order.ascending ? comparison : -comparison
          }
        }
        return 0
      })
    }
    const query = {
      select(columns: string) {
        recorded.selectedColumns = columns
        return query
      },
      eq(column: string, value: unknown) {
        recorded.equals[column] = value
        return query
      },
      in(column: string, values: readonly unknown[]) {
        recorded.included[column] = [...values]
        return query
      },
      order(
        column: string,
        options: { ascending: boolean; nullsFirst?: boolean },
      ) {
        recorded.orders.push({ column, ...options })
        return query
      },
      limit(count: number) {
        recorded.limit = count
        return Promise.resolve({
          data: matching().slice(0, count),
          error: null,
        })
      },
      range(from: number, to: number) {
        recorded.range = { from, to }
        return Promise.resolve({
          data: matching().slice(from, to + 1),
          error: null,
        })
      },
      maybeSingle() {
        const rows = matching()
        return Promise.resolve({
          data: rows.length === 1 ? rows[0] : null,
          error: rows.length > 1 ? { message: 'multiple rows' } : null,
        })
      },
    }
    return query
  }
}

function remoteAudit(
  id: string,
  customerId = 'customer-a',
): Record<string, unknown> {
  const suffix = customerId === 'customer-a' ? 'a' : 'b'
  return {
    id,
    customer_id: customerId,
    flock_id: `flock-${suffix}`,
    hatchery_id: `hatchery-${suffix}`,
    date: '2026-07-28',
    breed: 'Ross308',
    flock_age_weeks: 38,
    status: 'completed',
    selected_station_keys: '["egg"]',
    stations_completed: '["egg"]',
    findings_json: '{"total":3}',
    scorecard_json: '{"score":91}',
    notes: 'reviewed',
    created_at: '2026-07-28T12:00:00Z',
    completed_at: '2026-07-28T13:00:00Z',
    customer: { id: customerId, name: `Customer ${suffix}` },
    flock: {
      id: `flock-${suffix}`,
      customer_id: customerId,
      flock_id: `Flock ${suffix}`,
    },
    hatchery: {
      id: `hatchery-${suffix}`,
      customer_id: customerId,
      name: `Hatchery ${suffix}`,
    },
  }
}

function auditListResult(customerId: string, auditIds: string[]) {
  return {
    ok: true,
    code: 'ok',
    data: {
      customerId,
      audits: auditIds.map((id) => ({ id })),
      truncated: false,
    },
  }
}

Deno.test('selection uses the latest successful list event from only its conversation', async () => {
  const client = new FakeAuditClient({
    agent_conversation_turns: [
      {
        id: 'turn-a-old',
        conversation_id: 'conversation-a',
        created_at: '2026-07-28T10:00:00Z',
      },
      {
        id: 'turn-a-latest',
        conversation_id: 'conversation-a',
        created_at: '2026-07-28T11:00:00Z',
      },
      {
        id: 'turn-b-latest',
        conversation_id: 'conversation-b',
        created_at: '2026-07-28T12:00:00Z',
      },
    ],
    agent_tool_events: [
      {
        id: 'event-a-old',
        conversation_turn_id: 'turn-a-old',
        tool_name: 'list_customer_audits',
        status: 'succeeded',
        result_json: auditListResult('customer-a', ['audit-old']),
        created_at: '2026-07-28T10:01:00Z',
      },
      {
        id: 'event-a-failed',
        conversation_turn_id: 'turn-a-latest',
        tool_name: 'list_customer_audits',
        status: 'failed',
        result_json: auditListResult('customer-a', ['audit-failed']),
        created_at: '2026-07-28T11:02:00Z',
      },
      {
        id: 'event-a-latest',
        conversation_turn_id: 'turn-a-latest',
        tool_name: 'list_customer_audits',
        status: 'succeeded',
        result_json: auditListResult('customer-a', ['audit-latest']),
        created_at: '2026-07-28T11:01:00Z',
      },
      {
        id: 'event-b-newer',
        conversation_turn_id: 'turn-b-latest',
        tool_name: 'list_customer_audits',
        status: 'succeeded',
        result_json: auditListResult('customer-b', ['audit-other']),
        created_at: '2026-07-28T12:01:00Z',
      },
    ],
    audit_sessions: [
      remoteAudit('audit-old'),
      remoteAudit('audit-latest'),
      remoteAudit('audit-failed'),
      remoteAudit('audit-other', 'customer-b'),
    ],
  })
  const store = createSupabaseAgentAuditStore(client)

  const selected = await call(
    store,
    'select_audit_option',
    { position: 1 },
  )

  assertEquals(selected.ok, true)
  assertEquals(selected.data?.id, 'audit-latest')
  const turnQuery = client.queries.find((query) =>
    query.table === 'agent_conversation_turns'
  )
  assertEquals(turnQuery?.equals.conversation_id, 'conversation-a')
  const eventQuery = client.queries.find((query) =>
    query.table === 'agent_tool_events'
  )
  assertEquals(
    [...(eventQuery?.included.conversation_turn_id ?? [])].sort(),
    ['turn-a-latest', 'turn-a-old'],
  )
  assertEquals(eventQuery?.equals, {
    tool_name: 'list_customer_audits',
    status: 'succeeded',
  })
})

Deno.test('audit adapter decodes only bounded JSON arrays or objects', async () => {
  const oversizedArray = `["${'x'.repeat(100_000)}"]`
  const client = new FakeAuditClient({
    audit_sessions: [
      {
        ...remoteAudit('audit-array'),
        findings_json: '[{"kind":"finding"},2]',
        scorecard_json: '["pass",{"score":91}]',
      },
      {
        ...remoteAudit('audit-object'),
        findings_json: '{"total":3}',
        scorecard_json: '{"score":91}',
      },
      {
        ...remoteAudit('audit-malformed'),
        findings_json: '[}',
        scorecard_json: '{not-json',
      },
      {
        ...remoteAudit('audit-scalar'),
        findings_json: '42',
        scorecard_json: '"score"',
      },
      {
        ...remoteAudit('audit-oversized'),
        findings_json: oversizedArray,
        scorecard_json: oversizedArray,
      },
    ],
  })
  const store = createSupabaseAgentAuditStore(client)

  const decoded = await Promise.all(
    [
      'audit-array',
      'audit-object',
      'audit-malformed',
      'audit-scalar',
      'audit-oversized',
    ].map((id) => store.findAudit(id, ['customer-a'])),
  )

  assertEquals(
    decoded.map((audit) => ({
      findings: audit?.findings,
      scorecard: audit?.scorecard,
    })),
    [
      {
        findings: [{ kind: 'finding' }, 2],
        scorecard: ['pass', { score: 91 }],
      },
      { findings: { total: 3 }, scorecard: { score: 91 } },
      { findings: null, scorecard: null },
      { findings: null, scorecard: null },
      { findings: null, scorecard: null },
    ],
  )
})

function malformedRelationAudits(): Record<string, unknown>[] {
  return [
    {
      ...remoteAudit('audit-customer-relation-mismatch'),
      customer: { id: 'customer-b', name: 'FOREIGN CUSTOMER' },
    },
    {
      ...remoteAudit('audit-flock-id-mismatch'),
      flock: {
        id: 'flock-b',
        customer_id: 'customer-a',
        flock_id: 'FOREIGN FLOCK ID',
      },
    },
    {
      ...remoteAudit('audit-flock-owner-mismatch'),
      flock: {
        id: 'flock-a',
        customer_id: 'customer-b',
        flock_id: 'FOREIGN FLOCK OWNER',
      },
    },
    {
      ...remoteAudit('audit-hatchery-id-mismatch'),
      hatchery: {
        id: 'hatchery-b',
        customer_id: 'customer-a',
        name: 'FOREIGN HATCHERY ID',
      },
    },
    {
      ...remoteAudit('audit-hatchery-owner-mismatch'),
      hatchery: {
        id: 'hatchery-a',
        customer_id: 'customer-b',
        name: 'FOREIGN HATCHERY OWNER',
      },
    },
  ]
}

Deno.test('audit list discards rows with mismatched or cross-customer relations', async () => {
  const client = new FakeAuditClient({
    audit_sessions: [
      remoteAudit('audit-valid'),
      ...malformedRelationAudits(),
    ],
  })
  const store = createSupabaseAgentAuditStore(client)

  const audits = await store.listAudits({
    customerId: 'customer-a',
    flockId: null,
    limit: 20,
  })

  assertEquals(audits.rows.map((audit) => audit.id), ['audit-valid'])
  assertEquals(JSON.stringify(audits.rows).includes('FOREIGN'), false)
  const query = client.queries.find((item) => item.table === 'audit_sessions')
  assertEquals(
    query?.selectedColumns?.includes(
      'customer:customers(id,name)',
    ),
    true,
  )
  assertEquals(
    query?.selectedColumns?.includes(
      'flock:flocks(id,customer_id,flock_id)',
    ),
    true,
  )
  assertEquals(
    query?.selectedColumns?.includes(
      'hatchery:hatcheries(id,customer_id,name)',
    ),
    true,
  )
})

Deno.test('audit detail fails closed for mismatched or cross-customer relations', async () => {
  const malformed = malformedRelationAudits()
  const store = createSupabaseAgentAuditStore(
    new FakeAuditClient({ audit_sessions: malformed }),
  )

  for (const row of malformed) {
    assertEquals(
      await store.findAudit(row.id as string, ['customer-a']),
      null,
      row.id as string,
    )
  }
})

Deno.test('audit list sends descending date and identity ordering with nulls last', async () => {
  const client = new FakeAuditClient({
    audit_sessions: [remoteAudit('audit-valid')],
  })
  const store = createSupabaseAgentAuditStore(client)

  await store.listAudits({
    customerId: 'customer-a',
    flockId: null,
    limit: 10,
  })

  const query = client.queries.find((item) => item.table === 'audit_sessions')
  assertEquals(query?.orders, [
    { column: 'date', ascending: false, nullsFirst: false },
    { column: 'created_at', ascending: false, nullsFirst: false },
    { column: 'id', ascending: false, nullsFirst: false },
  ])
})

Deno.test(
  'audit list scans past malformed leading rows to fill the valid page',
  async () => {
    const malformedRows = Array.from({ length: 50 }, (_, index) => ({
      ...remoteAudit(`aa-malformed-${String(index).padStart(2, '0')}`),
      date: '2026-07-29',
      customer: { id: 'customer-b', name: 'FOREIGN CUSTOMER' },
    }))
    const client = new FakeAuditClient({
      audit_sessions: [
        ...malformedRows,
        remoteAudit('aa-valid-new'),
        { ...remoteAudit('aa-valid-old'), date: '2026-07-27' },
      ],
    })
    const store = createSupabaseAgentAuditStore(client)

    const result = await call(store, 'list_customer_audits', {
      customerId: 'customer-a',
      limit: 1,
    })
    assertEquals(
      result,
      {
        ok: true,
        code: 'ok',
        data: {
          customerId: 'customer-a',
          flockId: null,
          audits: [{
            id: 'aa-valid-new',
            date: '2026-07-28',
            status: 'completed',
            customerName: 'Customer a',
            flockName: 'Flock a',
            hatcheryName: 'Hatchery a',
            selectedStationKeys: ['egg'],
            stationsCompleted: ['egg'],
            createdAt: '2026-07-28T12:00:00Z',
            completedAt: '2026-07-28T13:00:00Z',
          }],
          truncated: true,
        },
      },
    )
    const ranges = client.queries
      .filter((query) => query.table === 'audit_sessions')
      .map((query) => query.range)
    assertEquals(ranges, [{ from: 0, to: 49 }, { from: 50, to: 99 }])
    assertEquals(JSON.stringify(result).includes('FOREIGN CUSTOMER'), false)
  },
)

Deno.test(
  'audit list reports truncation when invalid rows exhaust the scan cap',
  async () => {
    const client = new FakeAuditClient({
      audit_sessions: Array.from({ length: 500 }, (_, index) => ({
        ...remoteAudit(`aa-malformed-${String(index).padStart(3, '0')}`),
        customer: { id: 'customer-b', name: 'FOREIGN CUSTOMER' },
      })),
    })
    const store = createSupabaseAgentAuditStore(client)

    assertEquals(
      await call(store, 'list_customer_audits', {
        customerId: 'customer-a',
        limit: 10,
      }),
      {
        ok: true,
        code: 'ok',
        data: {
          customerId: 'customer-a',
          flockId: null,
          audits: [],
          truncated: true,
        },
      },
    )
    const ranges = client.queries
      .filter((query) => query.table === 'audit_sessions')
      .map((query) => query.range)
    assertEquals(
      ranges,
      Array.from(
        { length: 10 },
        (_, index) => ({ from: index * 50, to: index * 50 + 49 }),
      ),
    )
  },
)
