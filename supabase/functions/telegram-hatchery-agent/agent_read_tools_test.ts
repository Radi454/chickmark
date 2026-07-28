import { assert, assertEquals } from '@std/assert'

import type { AgentScope, AgentToolResult } from './agent_protocol.ts'
import {
  type AgentReadStore,
  createAgentReadToolHandlers,
  type StationRecordQuery,
} from './agent_read_tools.ts'
import { executeAgentTool } from './agent_tools.ts'

const now = new Date('2026-07-28T12:00:00.000Z')
const scope = {
  staffLinkId: 'staff-a',
  accessRole: 'customer' as const,
  allowedCustomerIds: ['customer-a'],
}
const adminScope = {
  staffLinkId: 'staff-admin',
  accessRole: 'admin' as const,
  allowedCustomerIds: ['customer-a', 'customer-b'],
}

function fixtureStore(): AgentReadStore & { queries: StationRecordQuery[] } {
  const queries: StationRecordQuery[] = []
  const stationRows = Array.from({ length: 101 }, (_, index) => ({
    id: `record-${index.toString().padStart(3, '0')}`,
    customer_id: 'customer-a',
    flock_id: 'flock-a',
    hatchery_id: 'hatchery-a',
    date: new Date(Date.UTC(2026, 6, 28 - (index % 20)))
      .toISOString().slice(0, 10),
    scope_type: 'pool',
    setter: null,
    hatcher: null,
    pasgar_sample_size: index < 2 ? [40, 60][index] : 40,
    pasgar_reflexes_count: 0,
    pasgar_beak_count: 0,
    pasgar_navel_count: 0,
    pasgar_belly_count: 0,
    pasgar_leg_count: 0,
    pasgar_feather_dev_count: 0,
    pasgar_final_score: index < 2 ? [9.5, 8.5][index] : null,
    secret_notes: 'must never leave the store',
  }))
  stationRows.push({
    ...stationRows[0],
    id: 'other-customer-record',
    customer_id: 'customer-b',
    flock_id: 'flock-b',
    date: '2026-07-29',
  })
  return {
    queries,
    listCustomers: (customerIds) =>
      Promise.resolve([
        { id: 'customer-a', name: 'الغريب' },
        { id: 'customer-b', name: 'الغريب' },
        { id: 'customer-out-of-scope', name: 'Hidden' },
      ].filter((customer) => customerIds.includes(customer.id))),
    findCustomer: (customerId) =>
      Promise.resolve(
        customerId === 'customer-a'
          ? { id: customerId, name: 'Customer A' }
          : customerId === 'customer-b'
          ? { id: customerId, name: 'Customer B' }
          : null,
      ),
    listFlocks: (customerId) =>
      Promise.resolve([
        {
          id: customerId === 'customer-a' ? 'flock-a' : 'flock-b',
          customerId,
          name: customerId === 'customer-a' ? 'السلام' : 'Gh Sal Rs',
          status: 'active',
          breed: customerId === 'customer-a' ? 'Ross' : 'Cobb',
          entryDate: customerId === 'customer-a' ? '2026-01-01' : null,
          sectorKey: 'breeder',
        },
      ]),
    listHatcheries: (customerId) =>
      Promise.resolve([
        {
          id: customerId === 'customer-a' ? 'hatchery-a' : 'hatchery-b',
          customerId,
          name: customerId === 'customer-a' ? 'Main Hatchery' : 'Other',
        },
      ]),
    findFlock: (flockId) =>
      Promise.resolve(
        {
          'flock-a': {
            id: flockId,
            customerId: 'customer-a',
            name: 'السلام',
            status: 'active',
            breed: 'Ross',
            entryDate: '2026-01-01',
            sectorKey: 'breeder',
          },
          'flock-b': {
            id: flockId,
            customerId: 'customer-b',
            name: 'Gh Sal Rs',
            status: 'active',
            breed: 'Cobb',
            entryDate: null,
            sectorKey: 'breeder',
          },
        }[flockId] ?? null,
      ),
    queryStationRecords(query) {
      queries.push(query)
      return Promise.resolve(stationRows)
    },
    findStationRecord(query) {
      queries.push(query)
      if (query.recordId === 'missing') return Promise.resolve(null)
      return Promise.resolve(stationRows[0])
    },
  }
}

async function call(
  store: AgentReadStore,
  name: string,
  args: Record<string, unknown>,
  selectedScope: AgentScope = scope,
): Promise<AgentToolResult> {
  return executeAgentTool(
    { id: `call-${name}`, name, arguments: args },
    {
      scope: selectedScope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      evidence: { record: () => undefined },
      handlers: createAgentReadToolHandlers(store, { now: () => now }),
    },
  )
}

Deno.test('customer and flock names resolve without guessing duplicate IDs', async () => {
  const store = fixtureStore()
  assertEquals(
    await call(store, 'list_customers', {}, adminScope),
    {
      ok: true,
      code: 'ok',
      data: {
        customers: [
          { id: 'customer-a', name: 'الغريب' },
          { id: 'customer-b', name: 'الغريب' },
        ],
      },
    },
  )
  assertEquals(
    await call(store, 'resolve_customer_flock', {
      customerName: 'الغريب',
      flockName: 'السلام',
    }, adminScope),
    {
      ok: true,
      code: 'ok',
      data: {
        status: 'resolved',
        customer: { id: 'customer-a', name: 'الغريب' },
        flock: {
          id: 'flock-a',
          name: 'السلام',
          status: 'active',
          breed: 'Ross',
          entryDate: '2026-01-01',
          sectorKey: 'breeder',
        },
      },
    },
  )
})

Deno.test('flock tools return only enforced customer data and exact age context', async () => {
  const store = fixtureStore()
  assertEquals(
    await call(store, 'list_customer_flocks', {
      customerId: 'customer-a',
      limit: 20,
    }),
    {
      ok: true,
      code: 'ok',
      data: {
        customerId: 'customer-a',
        flocks: [{
          id: 'flock-a',
          name: 'السلام',
          status: 'active',
          breed: 'Ross',
          entryDate: '2026-01-01',
          sectorKey: 'breeder',
        }],
      },
    },
  )
  assertEquals(
    await call(store, 'get_flock_context', { flockId: 'flock-a' }),
    {
      ok: true,
      code: 'ok',
      data: {
        id: 'flock-a',
        customerId: 'customer-a',
        name: 'السلام',
        status: 'active',
        breed: 'Ross',
        entryDate: '2026-01-01',
        sectorKey: 'breeder',
        ageDays: 208,
        ageWeeks: 29,
        ageAsOfDate: '2026-07-28',
      },
    },
  )
  assertEquals(
    await call(store, 'get_flock_context', { flockId: 'flock-b' }),
    { ok: false, code: 'scope_denied', data: null },
  )
})

Deno.test('hatchery catalog returns only the enforced customer rows', async () => {
  const store = fixtureStore()
  assertEquals(
    await call(store, 'list_customer_hatcheries', {
      customerId: 'customer-a',
      limit: 20,
    }),
    {
      ok: true,
      code: 'ok',
      data: {
        customerId: 'customer-a',
        hatcheries: [{ id: 'hatchery-a', name: 'Main Hatchery' }],
      },
    },
  )
  assertEquals(
    await call(store, 'list_customer_hatcheries', {
      customerId: 'customer-b',
      limit: 20,
    }),
    { ok: false, code: 'scope_denied', data: null },
  )
})

Deno.test('station query uses registry allowlist and truncates deterministically', async () => {
  const store = fixtureStore()
  const result = await call(store, 'query_station_records', {
    customerId: 'customer-a',
    flockId: 'flock-a',
    schemaKey: 'chicks.pasgar',
    schemaVersion: 1,
    fromDate: '2026-01-01',
    toDate: '2026-07-28',
    limit: 100,
  })

  assert(result.ok)
  assertEquals((result.data!.records as unknown[]).length, 100)
  assertEquals(result.data!.truncated, true)
  assertEquals(store.queries[0].table, 'chick_quality')
  assertEquals(store.queries[0].customerId, 'customer-a')
  assertEquals(store.queries[0].flockId, 'flock-a')
  assert(store.queries[0].columns.includes('pasgar_final_score'))
  assert(!store.queries[0].columns.includes('secret_notes'))
  assert(!JSON.stringify(result).includes('must never leave the store'))
  assert(!JSON.stringify(result).includes('customer-b'))
})

Deno.test('metric comparison uses sample weighting from allowlisted records', async () => {
  const result = await call(fixtureStore(), 'compare_station_metrics', {
    customerId: 'customer-a',
    flockId: 'flock-a',
    schemaKey: 'chicks.pasgar',
    schemaVersion: 1,
    measureKey: 'pasgarFinalScore',
    fromDate: '2026-01-01',
    toDate: '2026-07-28',
  })
  assertEquals(result, {
    ok: true,
    code: 'ok',
    data: {
      schemaKey: 'chicks.pasgar',
      schemaVersion: 1,
      measureKey: 'pasgarFinalScore',
      aggregation: 'sample_weighted_mean',
      value: 8.9,
      observedRows: 2,
      sourceQueryAt: now.toISOString(),
    },
  })
})

Deno.test('record provenance reports fresh and missing without estimating values', async () => {
  const store = fixtureStore()
  assertEquals(
    await call(store, 'get_record_provenance', {
      schemaKey: 'chicks.pasgar',
      schemaVersion: 1,
      recordId: 'record-000',
    }),
    {
      ok: true,
      code: 'ok',
      data: {
        customerId: 'customer-a',
        flockId: 'flock-a',
        schemaKey: 'chicks.pasgar',
        schemaVersion: 1,
        recordId: 'record-000',
        recordDate: '2026-07-28',
        fetchedAt: now.toISOString(),
        freshness: 'fresh',
      },
    },
  )
  assertEquals(
    await call(store, 'get_record_provenance', {
      schemaKey: 'chicks.pasgar',
      schemaVersion: 1,
      recordId: 'missing',
    }),
    {
      ok: true,
      code: 'ok',
      data: {
        customerId: null,
        flockId: null,
        schemaKey: 'chicks.pasgar',
        schemaVersion: 1,
        recordId: 'missing',
        recordDate: null,
        fetchedAt: now.toISOString(),
        freshness: 'missing',
      },
    },
  )
})
