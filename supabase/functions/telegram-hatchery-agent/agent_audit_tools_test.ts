import { assertEquals } from '@std/assert'

import type { AgentScope, AgentToolResult } from './agent_protocol.ts'
import { createAgentAuditToolHandlers } from './agent_audit_tools.ts'
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
  listAudits(input: {
    customerId: string
    flockId: string | null
    limit: number
  }): Promise<readonly AuditRow[]>
  findAudit(
    auditId: string,
    allowedCustomerIds: readonly string[],
  ): Promise<AuditRow | null>
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

function fixtureStore(): AuditStore & {
  listInputs: { customerId: string; flockId: string | null; limit: number }[]
} {
  const listInputs: {
    customerId: string
    flockId: string | null
    limit: number
  }[] = []
  const rows = [
    ...auditRows,
    {
      ...auditRows[0],
      id: 'audit-customer-b',
      customerId: 'customer-b',
      flockId: 'flock-b',
    },
  ]
  return {
    listInputs,
    findFlockCustomerId: (flockId) =>
      Promise.resolve(
        flockId === 'flock-a'
          ? 'customer-a'
          : flockId === 'flock-b'
          ? 'customer-b'
          : null,
      ),
    listAudits(input) {
      listInputs.push(input)
      return Promise.resolve(rows)
    },
    findAudit(auditId, allowedCustomerIds) {
      return Promise.resolve(
        rows.find((row) =>
          row.id === auditId && allowedCustomerIds.includes(row.customerId)
        ) ?? null,
      )
    },
  }
}

async function call(
  store: AuditStore,
  name: string,
  arguments_: Record<string, unknown>,
): Promise<AgentToolResult> {
  return executeAgentTool(
    { id: `call-${name}`, name, arguments: arguments_ },
    {
      scope,
      conversationId: 'conversation-a',
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
