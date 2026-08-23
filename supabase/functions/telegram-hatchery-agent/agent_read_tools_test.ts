import { assert, assertEquals } from '@std/assert'

import type { AgentScope, AgentToolResult } from './agent_protocol.ts'
import {
  type AgentCustomerReadRow,
  type AgentFlockReadRow,
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
        truncated: false,
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
        matchedBy: { customer: 'exact', flock: 'exact' },
      },
    },
  )
})

// Dedicated store for exercising the single-customer `resolved` branch of
// `resolve_customer_flock`, which now inlines the flock roster it already
// fetched. Kept separate from `fixtureStore` so each scenario controls the
// exact roster returned by `listFlocks` without disturbing the station-query
// fixtures other tests depend on.
function singleCustomerResolveStore(
  flocksByCustomer: Record<string, readonly AgentFlockReadRow[]>,
): AgentReadStore {
  const customers: AgentCustomerReadRow[] = [
    { id: 'customer-only', name: 'Unique Farm' },
  ]
  return {
    listCustomers: (customerIds) =>
      Promise.resolve(
        customers.filter((customer) => customerIds.includes(customer.id)),
      ),
    findCustomer: (customerId) =>
      Promise.resolve(
        customers.find((customer) => customer.id === customerId) ?? null,
      ),
    listFlocks: (customerId) =>
      Promise.resolve(flocksByCustomer[customerId] ?? []),
    listHatcheries: () => Promise.resolve([]),
    findFlock: () => Promise.resolve(null),
    queryStationRecords: () => Promise.resolve([]),
    findStationRecord: () => Promise.resolve(null),
  }
}

function flockRow(
  id: string,
  customerId: string,
  name: string,
): AgentFlockReadRow {
  return {
    id,
    customerId,
    name,
    status: 'active',
    breed: 'Ross',
    entryDate: '2026-01-01',
    sectorKey: 'breeder',
  }
}

const resolveScope: AgentScope = {
  staffLinkId: 'staff-resolve',
  accessRole: 'customer',
  allowedCustomerIds: ['customer-only'],
}

Deno.test('resolving a single customer inlines its already-fetched flocks in publicFlock shape and sort order', async () => {
  const store = singleCustomerResolveStore({
    'customer-only': [
      flockRow('flock-z', 'customer-only', 'زد'),
      flockRow('flock-a', 'customer-only', 'اول'),
    ],
  })
  assertEquals(
    await call(store, 'resolve_customer_flock', {
      customerName: 'Unique Farm',
    }, resolveScope),
    {
      ok: true,
      code: 'ok',
      data: {
        status: 'resolved',
        customer: { id: 'customer-only', name: 'Unique Farm' },
        flock: null,
        matchedBy: { customer: 'exact', flock: null },
        flocks: [
          {
            id: 'flock-a',
            name: 'اول',
            status: 'active',
            breed: 'Ross',
            entryDate: '2026-01-01',
            sectorKey: 'breeder',
          },
          {
            id: 'flock-z',
            name: 'زد',
            status: 'active',
            breed: 'Ross',
            entryDate: '2026-01-01',
            sectorKey: 'breeder',
          },
        ],
      },
    },
  )
})

Deno.test('resolving a single customer never inlines flocks belonging to a customer outside allowedCustomerIds', async () => {
  const store = singleCustomerResolveStore({
    // A leaky store returning rows for a customer that is not in scope
    // should not be trusted just because it was returned from
    // `listFlocks(customer.id)` — the handler re-checks both the row's own
    // customerId and the caller's allowedCustomerIds before inlining.
    'customer-only': [
      flockRow('flock-mine', 'customer-only', 'Mine'),
      flockRow('flock-other', 'customer-out-of-scope', 'Not Mine'),
    ],
  })
  const result = await call(store, 'resolve_customer_flock', {
    customerName: 'Unique Farm',
  }, resolveScope)
  assert(result.ok)
  assertEquals(result.data!.flocks, [
    {
      id: 'flock-mine',
      name: 'Mine',
      status: 'active',
      breed: 'Ross',
      entryDate: '2026-01-01',
      sectorKey: 'breeder',
    },
  ])
})

Deno.test('resolving a single customer omits the flocks key entirely past RESOLVE_INLINE_FLOCK_LIMIT', async () => {
  const bigRoster = Array.from(
    { length: 26 },
    (_, index) =>
      flockRow(
        `flock-${index.toString().padStart(2, '0')}`,
        'customer-only',
        `Flock ${index.toString().padStart(2, '0')}`,
      ),
  )
  const store = singleCustomerResolveStore({ 'customer-only': bigRoster })
  const result = await call(store, 'resolve_customer_flock', {
    customerName: 'Unique Farm',
  }, resolveScope)
  assert(result.ok)
  assertEquals('flocks' in result.data!, false)
})

Deno.test('resolving a single customer with zero flocks inlines an explicit empty list', async () => {
  const store = singleCustomerResolveStore({ 'customer-only': [] })
  assertEquals(
    await call(store, 'resolve_customer_flock', {
      customerName: 'Unique Farm',
    }, resolveScope),
    {
      ok: true,
      code: 'ok',
      data: {
        status: 'resolved',
        customer: { id: 'customer-only', name: 'Unique Farm' },
        flock: null,
        matchedBy: { customer: 'exact', flock: null },
        flocks: [],
      },
    },
  )
})

Deno.test('resolve_customer_flock ambiguous_customer candidates carry flock IDs, not just names', async () => {
  const store = fixtureStore()
  assertEquals(
    await call(store, 'resolve_customer_flock', {
      customerName: 'الغريب',
    }, adminScope),
    {
      ok: true,
      code: 'ok',
      data: {
        status: 'ambiguous_customer',
        customer: null,
        flock: null,
        matchedBy: { customer: 'exact', flock: null },
        candidates: [
          {
            customer: { id: 'customer-a', name: 'الغريب' },
            flocks: [{ id: 'flock-a', name: 'السلام' }],
            truncated: false,
          },
          {
            customer: { id: 'customer-b', name: 'الغريب' },
            flocks: [{ id: 'flock-b', name: 'Gh Sal Rs' }],
            truncated: false,
          },
        ],
      },
    },
  )
})

Deno.test('resolve_customer_flock customer_not_found names the customers the caller may see', async () => {
  const store = fixtureStore()
  assertEquals(
    await call(store, 'resolve_customer_flock', {
      customerName: 'No Such Customer',
    }, adminScope),
    {
      ok: true,
      code: 'ok',
      data: {
        status: 'customer_not_found',
        customer: null,
        flock: null,
        candidates: [
          { id: 'customer-a', name: 'الغريب' },
          { id: 'customer-b', name: 'الغريب' },
        ],
        truncated: false,
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

// ---------------------------------------------------------------------------
// Natural-name resolution.
//
// Stored names are DECORATED: a flock lands in ChickMark as
// `بدر - 25 Oct 2025 - Avian` — the operator's short name, plus the entry
// date, plus the breed. Nobody says that. They say `بدر`. Before the matching
// ladder existed this tool compared the two with `===` after normalization, so
// every natural utterance answered `flock_not_found` with no candidates, and
// the model had nothing to do but re-ask the same question. These tests are
// the regression wall for that incident and for the guesses the fix must
// still refuse to make.
// ---------------------------------------------------------------------------

const naturalScope: AgentScope = {
  staffLinkId: 'staff-natural',
  accessRole: 'admin',
  allowedCustomerIds: ['cust-badr', 'cust-delta'],
}

/**
 * A roster shaped like production: decorated flock names, two customers, and
 * a third customer the caller may not see.
 */
function naturalStore(
  overrides: { flocks?: Record<string, readonly AgentFlockReadRow[]> } = {},
): AgentReadStore {
  const customers: AgentCustomerReadRow[] = [
    { id: 'cust-badr', name: 'مزرعة بدر' },
    { id: 'cust-delta', name: 'Delta Poultry' },
    { id: 'cust-hidden', name: 'Hidden Farm' },
  ]
  const flocks: Record<string, readonly AgentFlockReadRow[]> = overrides.flocks ?? {
    'cust-badr': [
      flockRow('flock-badr', 'cust-badr', 'بدر - 25 Oct 2025 - Avian'),
      flockRow('flock-salam', 'cust-badr', 'السلام - 1 Jan 2026 - Ross'),
    ],
    'cust-delta': [
      flockRow('flock-delta', 'cust-delta', 'بدر - 4 Mar 2026 - Cobb'),
    ],
    'cust-hidden': [
      flockRow('flock-hidden', 'cust-hidden', 'بدر - 9 Sep 2025 - Ross'),
    ],
  }
  return {
    listCustomers: (customerIds) =>
      Promise.resolve(
        customers.filter((customer) => customerIds.includes(customer.id)),
      ),
    findCustomer: (customerId) =>
      Promise.resolve(
        customers.find((customer) => customer.id === customerId) ?? null,
      ),
    listFlocks: (customerId) => Promise.resolve(flocks[customerId] ?? []),
    listHatcheries: () => Promise.resolve([]),
    findFlock: () => Promise.resolve(null),
    queryStationRecords: () => Promise.resolve([]),
    findStationRecord: () => Promise.resolve(null),
  }
}

const badrOnlyScope: AgentScope = {
  staffLinkId: 'staff-badr',
  accessRole: 'customer',
  allowedCustomerIds: ['cust-badr'],
}

Deno.test('THE INCIDENT: the short flock name the user says resolves the decorated stored name', async () => {
  const result = await call(naturalStore(), 'resolve_customer_flock', {
    customerName: 'بدر',
    flockName: 'بدر',
  }, badrOnlyScope)
  assert(result.ok)
  assertEquals(result.data!.status, 'resolved')
  // Both tiers are reported. The customer was reached by a CONTAINED word
  // (`بدر` inside `مزرعة بدر`) and the flock by its leading word, and the
  // model needs to see the weaker of the two to know whether to confirm.
  assertEquals(result.data!.matchedBy, { customer: 'contains', flock: 'prefix' })
  assertEquals(
    (result.data!.flock as Record<string, unknown>).id,
    'flock-badr',
  )
  assertEquals(
    (result.data!.flock as Record<string, unknown>).name,
    'بدر - 25 Oct 2025 - Avian',
  )
})

Deno.test('a customer named by a leading word resolves and inlines its roster with IDs', async () => {
  const result = await call(naturalStore(), 'resolve_customer_flock', {
    customerName: 'Delta',
  }, naturalScope)
  assert(result.ok)
  assertEquals(result.data!.status, 'resolved')
  assertEquals(result.data!.matchedBy, { customer: 'prefix', flock: null })
  assertEquals(
    (result.data!.customer as Record<string, unknown>).id,
    'cust-delta',
  )
  assertEquals(result.data!.flocks, [{
    id: 'flock-delta',
    name: 'بدر - 4 Mar 2026 - Cobb',
    status: 'active',
    breed: 'Ross',
    entryDate: '2026-01-01',
    sectorKey: 'breeder',
  }])
})

Deno.test('TENANT GUARD: a fuzzy customer match spanning two customers is refused, never settled by the flock name', async () => {
  // `بدر` prefixes one customer name and appears inside neither other — but
  // BOTH allowed customers own a flock whose name starts with `بدر`. If the
  // flock name were allowed to pick the customer, a partial name plus a
  // common flock name would silently select a different operator's records.
  const store = naturalStore({
    flocks: {
      'cust-badr': [flockRow('flock-badr', 'cust-badr', 'بدر - 25 Oct 2025 - Avian')],
      'cust-delta': [flockRow('flock-delta', 'cust-delta', 'بدر - 4 Mar 2026 - Cobb')],
    },
  })
  const ambiguousCustomers: AgentScope = {
    staffLinkId: 'staff-two',
    accessRole: 'admin',
    allowedCustomerIds: ['cust-badr', 'cust-delta'],
  }
  const twoMatching = await call(
    {
      ...store,
      listCustomers: (customerIds) =>
        Promise.resolve(
          [
            { id: 'cust-badr', name: 'مزرعة بدر الشمالية' },
            { id: 'cust-delta', name: 'مزرعة بدر الجنوبية' },
          ].filter((customer) => customerIds.includes(customer.id)),
        ),
    },
    'resolve_customer_flock',
    { customerName: 'مزرعة بدر', flockName: 'بدر' },
    ambiguousCustomers,
  )
  assert(twoMatching.ok)
  assertEquals(twoMatching.data!.status, 'ambiguous_customer')
  assertEquals(twoMatching.data!.matchedBy, { customer: 'prefix', flock: null })
  // Refused — and every candidate carries the ID the model needs next.
  // Sorted by display name, so the southern farm leads.
  assertEquals(twoMatching.data!.candidates, [
    {
      customer: { id: 'cust-delta', name: 'مزرعة بدر الجنوبية' },
      flocks: [{ id: 'flock-delta', name: 'بدر - 4 Mar 2026 - Cobb' }],
      truncated: false,
    },
    {
      customer: { id: 'cust-badr', name: 'مزرعة بدر الشمالية' },
      flocks: [{ id: 'flock-badr', name: 'بدر - 25 Oct 2025 - Avian' }],
      truncated: false,
    },
  ])
})

Deno.test('SCOPE: a flock outside allowedCustomerIds is never matched, however well the name fits', async () => {
  // `cust-hidden` owns `بدر - 9 Sep 2025 - Ross`, a better-looking match than
  // anything in scope. It must not appear anywhere in the answer.
  const result = await call(naturalStore(), 'resolve_customer_flock', {
    customerName: 'مزرعة بدر',
    flockName: 'بدر',
  }, badrOnlyScope)
  assert(result.ok)
  assertEquals(result.data!.status, 'resolved')
  assertEquals(
    (result.data!.flock as Record<string, unknown>).id,
    'flock-badr',
  )
  assert(!JSON.stringify(result.data).includes('cust-hidden'))
  assert(!JSON.stringify(result.data).includes('flock-hidden'))
})

Deno.test('an ambiguous flock is refused with every candidate ID and name', async () => {
  const store = naturalStore({
    flocks: {
      'cust-badr': [
        flockRow('flock-1', 'cust-badr', 'بدر - 25 Oct 2025 - Avian'),
        flockRow('flock-2', 'cust-badr', 'بدر - 3 Mar 2026 - Ross'),
      ],
    },
  })
  const result = await call(store, 'resolve_customer_flock', {
    customerName: 'مزرعة بدر',
    flockName: 'بدر',
  }, badrOnlyScope)
  assert(result.ok)
  assertEquals(result.data!.status, 'ambiguous_flock')
  const candidates = result.data!.candidates as Record<string, unknown>[]
  assertEquals(candidates.length, 2)
  assertEquals(
    candidates.map((entry) => (entry.flock as Record<string, unknown>).id),
    ['flock-1', 'flock-2'],
  )
})

Deno.test('RECOVERY PATH: an unmatched flock name returns the roster with IDs, not a bare miss', async () => {
  const result = await call(naturalStore(), 'resolve_customer_flock', {
    customerName: 'مزرعة بدر',
    flockName: 'قطيع لا وجود له',
  }, badrOnlyScope)
  assert(result.ok)
  assertEquals(result.data!.status, 'flock_not_found')
  assertEquals(result.data!.customer, { id: 'cust-badr', name: 'مزرعة بدر' })
  assertEquals(result.data!.candidates, [{
    customer: { id: 'cust-badr', name: 'مزرعة بدر' },
    flocks: [
      { id: 'flock-salam', name: 'السلام - 1 Jan 2026 - Ross' },
      { id: 'flock-badr', name: 'بدر - 25 Oct 2025 - Avian' },
    ],
    truncated: false,
  }])
})

Deno.test('RECOVERY PATH: an unmatched customer name names the customers the caller may see', async () => {
  const result = await call(naturalStore(), 'resolve_customer_flock', {
    customerName: 'شركة غير موجودة',
  }, naturalScope)
  assert(result.ok)
  assertEquals(result.data!.status, 'customer_not_found')
  assertEquals(result.data!.truncated, false)
  assertEquals(result.data!.candidates, [
    { id: 'cust-delta', name: 'Delta Poultry' },
    { id: 'cust-badr', name: 'مزرعة بدر' },
  ])
  // And never one outside scope.
  assert(!JSON.stringify(result.data).includes('cust-hidden'))
})

Deno.test('a customer roster past the candidate cap is omitted, not silently truncated', async () => {
  const many = Array.from({ length: 26 }, (_, index) => ({
    id: `cust-${index.toString().padStart(2, '0')}`,
    name: `Farm ${index.toString().padStart(2, '0')}`,
  }))
  const store: AgentReadStore = {
    ...naturalStore(),
    listCustomers: (customerIds) =>
      Promise.resolve(many.filter((customer) => customerIds.includes(customer.id))),
  }
  const result = await call(store, 'resolve_customer_flock', {
    customerName: 'Nothing Like This',
  }, {
    staffLinkId: 'staff-many',
    accessRole: 'admin',
    allowedCustomerIds: many.map((customer) => customer.id),
  })
  assert(result.ok)
  assertEquals(result.data!.status, 'customer_not_found')
  assertEquals(result.data!.truncated, true)
  assertEquals('candidates' in result.data!, false)
})

Deno.test('a single-character customer name never fuzzy-matches its way into a farm', async () => {
  const result = await call(naturalStore(), 'resolve_customer_flock', {
    customerName: 'ب',
  }, naturalScope)
  assert(result.ok)
  assertEquals(result.data!.status, 'customer_not_found')
})

Deno.test('TENANT GUARD: two customers that only LOOK identical after folding are never told apart by the flock', async () => {
  // هانئ and هاني are different people. The matcher folds ئ to ي so a spoken
  // name is findable at all, which means they collide at the exact tier —
  // and the old guard read "exact tier" as "these really are the same name"
  // and let the flock name break the tie. That answers the caller about the
  // wrong operator's flock and persists it as the conversation's selection.
  const store: AgentReadStore = {
    listCustomers: (customerIds) =>
      Promise.resolve(
        [
          { id: 'cust-hani-hamza', name: 'هانئ' },
          { id: 'cust-hani-plain', name: 'هاني' },
        ].filter((customer) => customerIds.includes(customer.id)),
      ),
    findCustomer: () => Promise.resolve(null),
    listFlocks: (customerId) =>
      Promise.resolve(
        customerId === 'cust-hani-plain'
          ? [flockRow('flock-only', 'cust-hani-plain', 'بدر - 25 Oct 2025 - Avian')]
          : [],
      ),
    listHatcheries: () => Promise.resolve([]),
    findFlock: () => Promise.resolve(null),
    queryStationRecords: () => Promise.resolve([]),
    findStationRecord: () => Promise.resolve(null),
  }
  const result = await call(store, 'resolve_customer_flock', {
    customerName: 'هانئ',
    flockName: 'بدر',
  }, {
    staffLinkId: 'staff-hani',
    accessRole: 'admin',
    allowedCustomerIds: ['cust-hani-hamza', 'cust-hani-plain'],
  })

  assert(result.ok)
  assertEquals(result.data!.status, 'ambiguous_customer')
  const candidates = result.data!.candidates as Record<string, unknown>[]
  assertEquals(
    candidates.map((entry) => (entry.customer as Record<string, unknown>).id),
    ['cust-hani-hamza', 'cust-hani-plain'],
  )
})

Deno.test('TENANT GUARD: two customers genuinely spelled the same ARE still told apart by a unique flock', async () => {
  // The bypass survives for the case it was built for: identical display
  // names, where the flock is the only way to answer at all.
  const store: AgentReadStore = {
    listCustomers: (customerIds) =>
      Promise.resolve(
        [
          { id: 'cust-a', name: 'الغريب' },
          { id: 'cust-b', name: 'الغريب' },
        ].filter((customer) => customerIds.includes(customer.id)),
      ),
    findCustomer: () => Promise.resolve(null),
    listFlocks: (customerId) =>
      Promise.resolve(
        customerId === 'cust-b'
          ? [flockRow('flock-b', 'cust-b', 'السلام - 1 Jan 2026 - Ross')]
          : [flockRow('flock-a', 'cust-a', 'بدر - 25 Oct 2025 - Avian')],
      ),
    listHatcheries: () => Promise.resolve([]),
    findFlock: () => Promise.resolve(null),
    queryStationRecords: () => Promise.resolve([]),
    findStationRecord: () => Promise.resolve(null),
  }
  const result = await call(store, 'resolve_customer_flock', {
    customerName: 'الغريب',
    flockName: 'السلام',
  }, {
    staffLinkId: 'staff-two',
    accessRole: 'admin',
    allowedCustomerIds: ['cust-a', 'cust-b'],
  })

  assert(result.ok)
  assertEquals(result.data!.status, 'resolved')
  assertEquals((result.data!.customer as Record<string, unknown>).id, 'cust-b')
})

Deno.test('a scope larger than the read cap is reported as truncated, never as "no such customer"', async () => {
  // An admin staff link is scoped to EVERY customer. Past the cap the roster
  // is alphabetical, so who falls off it is arbitrary — and the honest answer
  // ("I can only see the first 100") used to come out as the confident wrong
  // one ("there is no such customer"), which is the original incident's
  // symptom reached by a different route.
  const many = Array.from({ length: 140 }, (_, index) => ({
    id: `cust-${index.toString().padStart(3, '0')}`,
    name: `Farm ${index.toString().padStart(3, '0')}`,
  }))
  const store: AgentReadStore = {
    listCustomers: (customerIds, limit) =>
      Promise.resolve(
        many.filter((customer) => customerIds.includes(customer.id))
          .slice(0, limit),
      ),
    findCustomer: () => Promise.resolve(null),
    listFlocks: () => Promise.resolve([]),
    listHatcheries: () => Promise.resolve([]),
    findFlock: () => Promise.resolve(null),
    queryStationRecords: () => Promise.resolve([]),
    findStationRecord: () => Promise.resolve(null),
  }
  const wideScope: AgentScope = {
    staffLinkId: 'staff-admin-wide',
    accessRole: 'admin',
    allowedCustomerIds: many.map((customer) => customer.id),
  }

  const listed = await call(store, 'list_customers', {}, wideScope)
  assert(listed.ok)
  assertEquals((listed.data!.customers as unknown[]).length, 100)
  assertEquals(listed.data!.truncated, true)

  const missed = await call(store, 'resolve_customer_flock', {
    customerName: 'Farm 139',
  }, wideScope)
  assert(missed.ok)
  assertEquals(missed.data!.status, 'customer_not_found')
  assertEquals(missed.data!.truncated, true)
  // No partial roster is offered as if it were the whole one.
  assertEquals('candidates' in missed.data!, false)
})

Deno.test('a candidate flock roster past the cap says so instead of looking complete', async () => {
  const roster = Array.from(
    { length: 30 },
    (_, index) =>
      flockRow(
        `flock-${index.toString().padStart(2, '0')}`,
        'cust-one',
        `Flock ${index.toString().padStart(2, '0')}`,
      ),
  )
  const store: AgentReadStore = {
    listCustomers: (customerIds) =>
      Promise.resolve(
        [{ id: 'cust-one', name: 'Only Farm' }].filter((customer) =>
          customerIds.includes(customer.id)
        ),
      ),
    findCustomer: () => Promise.resolve(null),
    listFlocks: () => Promise.resolve(roster),
    listHatcheries: () => Promise.resolve([]),
    findFlock: () => Promise.resolve(null),
    queryStationRecords: () => Promise.resolve([]),
    findStationRecord: () => Promise.resolve(null),
  }
  const result = await call(store, 'resolve_customer_flock', {
    customerName: 'Only Farm',
    flockName: 'No Such Flock Here',
  }, {
    staffLinkId: 'staff-one',
    accessRole: 'customer',
    allowedCustomerIds: ['cust-one'],
  })
  assert(result.ok)
  assertEquals(result.data!.status, 'flock_not_found')
  const candidates = result.data!.candidates as Record<string, unknown>[]
  assertEquals((candidates[0].flocks as unknown[]).length, 25)
  assertEquals(candidates[0].truncated, true)
})
