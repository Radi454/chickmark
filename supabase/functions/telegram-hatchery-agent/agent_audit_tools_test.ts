import { assertEquals } from '@std/assert'

import type { AgentScope, AgentToolResult } from './agent_protocol.ts'
import {
  createAgentAuditToolHandlers,
  createSupabaseAgentAuditStore,
} from './agent_audit_tools.ts'
import { executeAgentTool } from './agent_tools.ts'

Deno.test('get_audit_summary attaches the matching benchmark', async () => {
  const store = fixtureStore()
  store.latestSelectedAuditResult = {
    ok: true,
    code: 'ok',
    data: {
      id: 'audit-completed',
      customerId: 'customer-a',
      flockId: 'flock-a',
    },
  }
  const handlers = createAgentAuditToolHandlers(store, {
    bmkStore: {
      listBreedCoverage: () =>
        Promise.resolve([{ breed: 'Ross308', ageWeek: 35 }]),
      findBreedBenchmark: () =>
        Promise.resolve({
          breed: 'Ross308',
          ageWeek: 35,
          hatchabilityPct: 90,
          fertilityPct: 95,
          hofPct: 86,
          productionPct: 83,
          eggWeightG: 67,
          chickWeightG: 48,
        }),
      listEggBreakoutWeeks: () => Promise.resolve([35]),
      findEggBreakoutBenchmark: () =>
        Promise.resolve({
          ageWeek: 35,
          infertilePct: 4,
          early24hPct: 1,
          early48hPct: 1,
          bloodRingPct: 0.5,
          blackEyePct: 0.5,
          earlyDeadPct: 2,
          midDeadPct: 1,
          lateDeadPct: 2,
          externalPipPct: 0.5,
          crackedPct: 1,
          contamPct: 0.5,
        }),
      findHatcheryCustomerId: () => Promise.resolve(null),
      listOperationalStandards: () => Promise.resolve([]),
    },
  })

  const result = await handlers.get_audit_summary!({
    scope,
    conversationId: 'conversation-a',
    activeVisitId: null,
    arguments: {},
  })

  const benchmark = result.data?.benchmark as Record<string, unknown>
  assertEquals(benchmark.status, 'ok')
  assertEquals(benchmark.breed, 'Ross308')
  assertEquals(benchmark.ageWeek, 35)
})

Deno.test('the benchmark block is present and explicit when unavailable',
  async () => {
    const store = fixtureStore()
    store.latestSelectedAuditResult = {
      ok: true,
      code: 'ok',
      data: {
        id: 'audit-completed',
        customerId: 'customer-a',
        flockId: 'flock-a',
      },
    }
    const handlers = createAgentAuditToolHandlers(store)
    const result = await handlers.get_audit_summary!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: {},
    })
    const benchmark = result.data?.benchmark as Record<string, unknown>
    assertEquals(benchmark.status, 'unavailable')
    assertEquals(benchmark.reason, 'benchmark_unavailable')
  })

Deno.test(
  'the auto-attached benchmark keeps availableBreeds on a breed miss',
  async () => {
    const store = fixtureStore()
    store.latestSelectedAuditResult = {
      ok: true,
      code: 'ok',
      data: {
        id: 'audit-completed',
        customerId: 'customer-a',
        flockId: 'flock-a',
      },
    }
    const handlers = createAgentAuditToolHandlers(store, {
      bmkStore: {
        // Coverage that does not contain the audit's breed (Ross308).
        listBreedCoverage: () =>
          Promise.resolve([{ breed: 'Cobb500', ageWeek: 35 }]),
        findBreedBenchmark: () => Promise.resolve(null),
        listEggBreakoutWeeks: () => Promise.resolve([35]),
        findEggBreakoutBenchmark: () => Promise.resolve(null),
        findHatcheryCustomerId: () => Promise.resolve(null),
        listOperationalStandards: () => Promise.resolve([]),
      },
    })

    const result = await handlers.get_audit_summary!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: {},
    })

    const benchmark = result.data?.benchmark as Record<string, unknown>
    assertEquals(benchmark.status, 'unavailable')
    assertEquals(benchmark.reason, 'breed_not_found')
    // The prompt tells the agent to say what IS covered and ask; the coverage
    // payload has to survive into the auto-attached block for that to work
    // without a second tool call.
    assertEquals(benchmark.availableBreeds, ['Cobb500'])
  },
)

Deno.test(
  'the auto-attached benchmark keeps coveredWeeks on a week miss',
  async () => {
    const store = fixtureStore()
    store.latestSelectedAuditResult = {
      ok: true,
      code: 'ok',
      data: {
        id: 'audit-completed',
        customerId: 'customer-a',
        flockId: 'flock-a',
      },
    }
    const handlers = createAgentAuditToolHandlers(store, {
      bmkStore: {
        // Breed is covered, the audit's age week (35) is not.
        listBreedCoverage: () =>
          Promise.resolve([
            { breed: 'Ross308', ageWeek: 40 },
            { breed: 'Ross308', ageWeek: 45 },
          ]),
        findBreedBenchmark: () => Promise.resolve(null),
        listEggBreakoutWeeks: () => Promise.resolve([40, 45]),
        findEggBreakoutBenchmark: () => Promise.resolve(null),
        findHatcheryCustomerId: () => Promise.resolve(null),
        listOperationalStandards: () => Promise.resolve([]),
      },
    })

    const result = await handlers.get_audit_summary!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: {},
    })

    const benchmark = result.data?.benchmark as Record<string, unknown>
    assertEquals(benchmark.status, 'unavailable')
    assertEquals(benchmark.reason, 'week_out_of_range')
    assertEquals(benchmark.breed, 'Ross308')
    assertEquals(benchmark.coveredWeeks, { min: 40, max: 45 })
  },
)

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
  findLatestAuditListResult(
    conversationId: string,
    contextEpoch: number | null,
  ): Promise<unknown | null>
  findLatestSelectedAuditResult(
    conversationId: string,
    contextEpoch: number | null,
  ): Promise<unknown | null>
  listAudits(input: {
    customerId: string
    flockId: string | null
    limit: number
  }): Promise<{ rows: readonly AuditRow[]; truncated: boolean }>
  findAudit(
    auditId: string,
    allowedCustomerIds: readonly string[],
  ): Promise<AuditRow | null>
  listAuditBreakouts(input: {
    auditId: string
    customerId: string
  }): Promise<AuditBreakoutPage>
  loadConversationContext?(
    conversationId: string,
  ): Promise<ConversationContext | null>
}

interface ConversationContext {
  customerId: string | null
  flockId: string | null
  auditId: string | null
}

interface AuditBreakoutRow {
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

interface AuditBreakoutPage {
  rows: readonly AuditBreakoutRow[]
  truncated: boolean
}

interface FixtureAuditStore extends AuditStore {
  latestAuditListResult: unknown | null
  latestSelectedAuditResult: unknown | null
  findLatestSelectedAuditResult(
    conversationId: string,
  ): Promise<unknown | null>
  listAuditBreakouts(input: {
    auditId: string
    customerId: string
  }): Promise<AuditBreakoutPage>
  listInputs: { customerId: string; flockId: string | null; limit: number }[]
  breakoutInputs: { auditId: string; customerId: string }[]
  rows: AuditRow[]
  breakoutRows: AuditBreakoutRow[]
  selectedAuditIds: string[]
  conversationContext: ConversationContext | null
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
    flockAgeWeeks: 35,
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
  const breakoutInputs: { auditId: string; customerId: string }[] = []
  const store: FixtureAuditStore = {
    latestAuditListResult: null,
    latestSelectedAuditResult: null,
    listInputs,
    breakoutInputs,
    rows,
    breakoutRows: [],
    selectedAuditIds,
    conversationContext: null,
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
    findLatestSelectedAuditResult: () =>
      Promise.resolve(store.latestSelectedAuditResult),
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
    listAuditBreakouts(input) {
      breakoutInputs.push(input)
      return Promise.resolve({
        rows: store.breakoutRows,
        truncated: false,
      })
    },
  }
  return store
}

function breakoutRow(
  overrides: Partial<AuditBreakoutRow> & Pick<AuditBreakoutRow, 'breakoutType'>,
): AuditBreakoutRow {
  const { breakoutType, ...rest } = overrides
  return {
    breakoutType,
    id: 'breakout-a',
    sessionId: 'audit-completed',
    customerId: 'customer-a',
    flockId: 'flock-a',
    hatcheryId: 'hatchery-a',
    date: '2026-07-28',
    house: 'H1',
    setter: 'S1',
    hatcher: 'H1',
    trolley: 'T1',
    tray: 'T1',
    position: 'top',
    traySize: 150,
    infertileCount: null,
    infertilePct: null,
    early24hPct: null,
    early48hPct: null,
    bloodRingPct: null,
    blackEyePct: null,
    earlyDeadPct: null,
    midDeadPct: null,
    lateDeadPct: null,
    externalPipPct: null,
    crackedPct: null,
    contaminatedPct: null,
    hatchabilityPct: null,
    fertilityPct: null,
    hofPct: null,
    culledPct: null,
    deadPct: null,
    ...rest,
  }
}

function publicBreakout(
  overrides: Record<string, unknown> & { breakoutType: string },
): Record<string, unknown> {
  const { breakoutType, ...rest } = overrides
  return Object.fromEntries(
    Object.entries({
      breakoutType,
      date: '2026-07-28',
      house: 'H1',
      setter: 'S1',
      hatcher: 'H1',
      trolley: 'T1',
      tray: 'T1',
      position: 'top',
      traySize: 150,
      infertileCount: null,
      infertilePct: null,
      early24hPct: null,
      early48hPct: null,
      bloodRingPct: null,
      blackEyePct: null,
      earlyDeadPct: null,
      midDeadPct: null,
      lateDeadPct: null,
      externalPipPct: null,
      crackedPct: null,
      contaminatedPct: null,
      hatchabilityPct: null,
      fertilityPct: null,
      hofPct: null,
      culledPct: null,
      deadPct: null,
      ...rest,
    }).filter((entry) => entry[1] !== null),
  )
}

async function call(
  store: AuditStore,
  name: string,
  arguments_: Record<string, unknown>,
  selectedScope: AgentScope = scope,
  options: { conversationId?: string; conversationContextEpoch?: number } = {},
): Promise<AgentToolResult> {
  return executeAgentTool(
    { id: `call-${name}`, name, arguments: arguments_ },
    {
      scope: selectedScope,
      conversationId: options.conversationId ?? 'conversation-a',
      activeVisitId: null,
      ...(options.conversationContextEpoch === undefined
        ? {}
        : { conversationContextEpoch: options.conversationContextEpoch }),
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

Deno.test('unknown and out-of-scope selected audits have indistinguishable denials', async () => {
  const unknownStore = fixtureStore()
  unknownStore.latestSelectedAuditResult = {
    ok: true,
    code: 'ok',
    data: {
      id: 'unknown',
      customerId: 'customer-a',
      flockId: 'flock-a',
    },
  }
  const customerBStore = fixtureStore()
  customerBStore.latestSelectedAuditResult = {
    ok: true,
    code: 'ok',
    data: {
      id: 'audit-customer-b',
      customerId: 'customer-a',
      flockId: 'flock-a',
    },
  }
  const unknown = await call(unknownStore, 'get_audit_summary', {})
  const customerB = await call(customerBStore, 'get_audit_summary', {})
  assertEquals(unknown, { ok: false, code: 'scope_denied', data: null })
  assertEquals(customerB, unknown)
})

Deno.test('audit summary loads the persisted selection without a model-supplied ID', async () => {
  const store = fixtureStore()
  store.latestSelectedAuditResult = {
    ok: true,
    code: 'ok',
    data: {
      id: 'audit-completed',
      customerId: 'customer-a',
      flockId: 'flock-a',
    },
  }
  assertEquals(
    await call(store, 'get_audit_summary', {}),
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
        flockAgeWeeks: 35,
        findings: { total: 3 },
        scorecard: { score: 91 },
        notes: 'reviewed',
        benchmark: { status: 'unavailable', reason: 'benchmark_unavailable' },
      },
    },
  )
})

Deno.test('selected audit breakouts return infertile rates from the exact audit session', async () => {
  const store = fixtureStore()
  store.latestSelectedAuditResult = {
    ok: true,
    code: 'ok',
    data: {
      id: 'audit-completed',
      customerId: 'customer-a',
    },
  }
  store.breakoutRows = [
    breakoutRow({
      breakoutType: 'fresh',
      id: 'fresh-a',
      infertileCount: 6,
      infertilePct: 4,
    }),
    breakoutRow({
      breakoutType: 'candled',
      id: 'candled-a',
      tray: 'T2',
      infertileCount: 12,
      infertilePct: 8,
    }),
    breakoutRow({
      breakoutType: 'residue',
      id: 'residue-a',
      tray: 'T3',
      infertileCount: 15,
      infertilePct: 10,
      hatchabilityPct: 88,
      fertilityPct: 90,
      hofPct: 97.8,
    }),
    breakoutRow({
      breakoutType: 'residue',
      id: 'foreign-session',
      sessionId: 'audit-new',
      infertileCount: 99,
      infertilePct: 66,
    }),
    breakoutRow({
      breakoutType: 'residue',
      id: 'foreign-customer',
      customerId: 'customer-b',
      infertileCount: 98,
      infertilePct: 65.3,
    }),
  ]

  assertEquals(
    await call(store, 'get_selected_audit_breakouts', {}),
    {
      ok: true,
      code: 'ok',
      data: {
        audit: {
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
        breakouts: [
          publicBreakout({
            breakoutType: 'fresh',
            tray: 'T1',
            infertileCount: 6,
            infertilePct: 4,
          }),
          publicBreakout({
            breakoutType: 'candled',
            tray: 'T2',
            infertileCount: 12,
            infertilePct: 8,
          }),
          publicBreakout({
            breakoutType: 'residue',
            tray: 'T3',
            infertileCount: 15,
            infertilePct: 10,
            hatchabilityPct: 88,
            fertilityPct: 90,
            hofPct: 97.8,
          }),
        ],
        truncated: false,
        benchmark: { status: 'unavailable', reason: 'benchmark_unavailable' },
      },
    },
  )
  assertEquals(store.selectedAuditIds.at(-1), 'audit-completed')
  assertEquals(store.breakoutInputs, [{
    auditId: 'audit-completed',
    customerId: 'customer-a',
  }])
})

Deno.test('selected audit breakout lookup fails closed without a scoped persisted selection', async () => {
  for (
    const snapshot of [
      null,
      {
        ok: true,
        code: 'ok',
        data: { id: 'audit-completed', customerId: 'customer-b' },
      },
      {
        ok: true,
        code: 'ok',
        data: { id: 'missing-audit', customerId: 'customer-a' },
      },
    ]
  ) {
    const store = fixtureStore()
    store.latestSelectedAuditResult = snapshot
    assertEquals(
      await call(store, 'get_selected_audit_breakouts', {}),
      { ok: false, code: 'scope_denied', data: null },
    )
  }
})

Deno.test('changing customer or flock context requires a fresh audit selection', async () => {
  const store = fixtureStore()
  store.latestSelectedAuditResult = {
    ok: true,
    code: 'ok',
    data: {
      id: 'audit-completed',
      customerId: 'customer-a',
      flockId: 'flock-a',
    },
  }
  store.conversationContext = {
    customerId: 'customer-a',
    flockId: 'flock-new',
    auditId: null,
  }
  store.loadConversationContext = () =>
    Promise.resolve(store.conversationContext)

  assertEquals(
    await call(store, 'get_selected_audit_breakouts', {}),
    {
      ok: false,
      code: 'fresh_audit_selection_required',
      data: {
        selectedCustomerId: 'customer-a',
        selectedFlockId: 'flock-new',
      },
    },
  )
  assertEquals(store.breakoutInputs, [])
})

Deno.test('audit summary requires matching customer flock and audit context', async () => {
  const store = fixtureStore()
  store.conversationContext = {
    customerId: 'customer-a',
    flockId: 'flock-new',
    auditId: 'audit-completed',
  }
  store.loadConversationContext = () =>
    Promise.resolve(store.conversationContext)

  assertEquals(
    await call(store, 'get_audit_summary', {}),
    {
      ok: false,
      code: 'fresh_audit_selection_required',
      data: {
        selectedCustomerId: 'customer-a',
        selectedFlockId: 'flock-new',
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

Deno.test('missing malformed and out-of-range audit snapshots fail closed, and say which', async () => {
  // Every one of these refuses to select an audit. What changed is that the
  // model can now tell WHY: "you never listed the options" and "that number
  // is off the end of the list" have different recoveries, and a null-payload
  // `scope_denied` for both left it nothing to do but ask the user again.
  const fixtures: Array<{
    snapshot: unknown | null
    position: number
    code: string
  }> = [
    { snapshot: null, position: 1, code: 'audit_options_required' },
    { snapshot: {}, position: 1, code: 'audit_options_required' },
    {
      snapshot: {
        ok: true,
        code: 'ok',
        data: { customerId: 'customer-a', audits: 'not-an-array' },
      },
      position: 1,
      code: 'audit_options_required',
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
      code: 'audit_options_required',
    },
    {
      snapshot: {
        ok: true,
        code: 'ok',
        data: { customerId: 'customer-a', audits: [{ id: 'audit-new' }] },
      },
      position: 2,
      code: 'audit_position_out_of_range',
    },
    {
      // A snapshot whose option ids are unusable. Nothing about the recovery
      // is safe to describe, so this stays an opaque refusal.
      snapshot: {
        ok: true,
        code: 'ok',
        data: { customerId: 'customer-a', audits: [{}] },
      },
      position: 1,
      code: 'scope_denied',
    },
  ]

  for (const fixture of fixtures) {
    const store = fixtureStore()
    store.latestAuditListResult = fixture.snapshot
    const result = await call(store, 'select_audit_option', {
      position: fixture.position,
    })
    assertEquals(result.ok, false)
    assertEquals(result.code, fixture.code)
    // Nothing was selected, whatever the code.
    assertEquals(store.selectedAuditIds.length, 0)
  }
})

Deno.test('an out-of-range position tells the model how many options there actually are', async () => {
  const store = fixtureStore()
  store.latestAuditListResult = {
    ok: true,
    code: 'ok',
    data: {
      customerId: 'customer-a',
      audits: [{ id: 'audit-1' }, { id: 'audit-2' }],
    },
  }
  const result = await call(store, 'select_audit_option', { position: 3 })
  assertEquals(result.code, 'audit_position_out_of_range')
  assertEquals(result.data?.optionCount, 2)
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

Deno.test('Supabase audit breakout reader uses the persisted selection and exact session rows', async () => {
  const client = new FakeAuditClient({
    agent_conversations: [{
      id: 'conversation-a',
      selected_customer_id: 'customer-a',
      selected_flock_id: 'flock-a',
      selected_audit_id: 'audit-latest',
    }],
    agent_conversation_turns: [{
      id: 'turn-selected',
      conversation_id: 'conversation-a',
      created_at: '2026-07-28T11:00:00Z',
    }],
    agent_tool_events: [{
      id: 'event-selected',
      conversation_turn_id: 'turn-selected',
      tool_name: 'select_audit_option',
      status: 'succeeded',
      result_json: {
        ok: true,
        code: 'ok',
        data: {
          id: 'audit-latest',
          customerId: 'customer-a',
        },
      },
      created_at: '2026-07-28T11:01:00Z',
    }],
    audit_sessions: [remoteAudit('audit-latest')],
    fresh_egg_breakout: [{
      id: 'fresh-a',
      session_id: 'audit-latest',
      customer_id: 'customer-a',
      flock_id: 'flock-a',
      hatchery_id: 'hatchery-a',
      date: '2026-07-28',
      house: 'H1',
      setter: 'S1',
      hatcher: 'H1',
      trolley: 'T1',
      tray: 'T1',
      position: 'top',
      tray_size: 30,
      infertile_count: 3,
      infertile_pct: 10,
      early24h_pct: 2,
      early48h_pct: 1,
      blood_ring_pct: 0,
    }],
    candled_egg_breakout: [],
    residue_breakout: [{
      id: 'residue-a',
      session_id: 'audit-latest',
      customer_id: 'customer-a',
      flock_id: 'flock-a',
      hatchery_id: 'hatchery-a',
      date: '2026-07-28',
      house: 'H1',
      setter: 'S1',
      hatcher: 'H1',
      trolley: 'T1',
      tray: 'T2',
      position: 'bottom',
      tray_size: 150,
      infertile_count: 15,
      infertile_pct: 10,
      early_dead_pct: 4,
      mid_dead_pct: 2,
      late_dead_pct: 1,
      external_pip_pct: 0.5,
      cracked_pct: 0,
      contaminated_pct: 0,
      hatchability_pct: 88,
      fertility_pct: 90,
      hof_pct: 97.8,
      culled_pct: 1,
      dead_pct: 0.5,
    }],
  })
  const store = createSupabaseAgentAuditStore(client)

  const result = await call(store, 'get_selected_audit_breakouts', {})

  assertEquals(result.ok, true)
  assertEquals(result.data?.breakouts, [
    publicBreakout({
      breakoutType: 'fresh',
      tray: 'T1',
      traySize: 30,
      infertileCount: 3,
      infertilePct: 10,
      early24hPct: 2,
      early48hPct: 1,
      bloodRingPct: 0,
    }),
    publicBreakout({
      breakoutType: 'residue',
      tray: 'T2',
      position: 'bottom',
      infertileCount: 15,
      infertilePct: 10,
      earlyDeadPct: 4,
      midDeadPct: 2,
      lateDeadPct: 1,
      externalPipPct: 0.5,
      crackedPct: 0,
      contaminatedPct: 0,
      hatchabilityPct: 88,
      fertilityPct: 90,
      hofPct: 97.8,
      culledPct: 1,
      deadPct: 0.5,
    }),
  ])
  for (
    const table of [
      'fresh_egg_breakout',
      'candled_egg_breakout',
      'residue_breakout',
    ]
  ) {
    const query = client.queries.find((candidate) => candidate.table === table)
    assertEquals(query?.equals.session_id, 'audit-latest')
    assertEquals(query?.equals.customer_id, 'customer-a')
    assertEquals(query?.selectedColumns?.includes('*'), false)
    assertEquals(query?.limit, 21)
  }
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

Deno.test('an option list produced on a LIVE CALL is selectable — realtime evidence carries no turn link', async () => {
  // The realtime broker writes `agent_tool_events` with
  // `conversation_turn_id` NULL on purpose (a voice transcript may never
  // finalize). Searching only turn-linked rows meant `select_audit_option`
  // answered a refusal to a user who had just been read the numbered options
  // aloud, and the model's only move was to ask again.
  const client = new FakeAuditClient({
    agent_conversation_turns: [],
    agent_realtime_sessions: [
      {
        id: 'rt-sess-1',
        conversation_id: 'conversation-a',
        created_at: '2026-07-28T11:00:00Z',
      },
      {
        id: 'rt-sess-other',
        conversation_id: 'conversation-b',
        created_at: '2026-07-28T12:00:00Z',
      },
    ],
    agent_tool_events: [
      {
        id: 'event-voice',
        conversation_turn_id: null,
        realtime_session_id: 'rt-sess-1',
        tool_name: 'list_customer_audits',
        status: 'succeeded',
        result_json: auditListResult('customer-a', ['audit-latest']),
        created_at: '2026-07-28T11:01:00Z',
      },
      {
        id: 'event-voice-other-thread',
        conversation_turn_id: null,
        realtime_session_id: 'rt-sess-other',
        tool_name: 'list_customer_audits',
        status: 'succeeded',
        result_json: auditListResult('customer-b', ['audit-other']),
        created_at: '2026-07-28T12:01:00Z',
      },
    ],
    audit_sessions: [
      remoteAudit('audit-latest'),
      remoteAudit('audit-other', 'customer-b'),
    ],
  })
  const store = createSupabaseAgentAuditStore(client)

  const selected = await call(store, 'select_audit_option', { position: 1 })

  assertEquals(selected.ok, true)
  assertEquals(selected.data?.id, 'audit-latest')
  // Sessions were looked up for THIS conversation only…
  const sessionQuery = client.queries.find((query) =>
    query.table === 'agent_realtime_sessions'
  )
  assertEquals(sessionQuery?.equals.conversation_id, 'conversation-a')
  // …and the evidence search was confined to those session ids, so a sibling
  // thread's live call can never supply this one's options.
  const realtimeEventQuery = client.queries.find((query) =>
    query.table === 'agent_tool_events' &&
    query.included.realtime_session_id !== undefined
  )
  assertEquals(
    [...(realtimeEventQuery?.included.realtime_session_id ?? [])],
    ['rt-sess-1'],
  )
})

Deno.test('the newest option list wins whichever door produced it', async () => {
  const client = new FakeAuditClient({
    agent_conversation_turns: [
      {
        id: 'turn-a',
        conversation_id: 'conversation-a',
        created_at: '2026-07-28T10:00:00Z',
      },
    ],
    agent_realtime_sessions: [
      {
        id: 'rt-sess-1',
        conversation_id: 'conversation-a',
        created_at: '2026-07-28T11:00:00Z',
      },
    ],
    agent_tool_events: [
      {
        id: 'event-typed-older',
        conversation_turn_id: 'turn-a',
        tool_name: 'list_customer_audits',
        status: 'succeeded',
        result_json: auditListResult('customer-a', ['audit-old']),
        created_at: '2026-07-28T10:01:00Z',
      },
      {
        id: 'event-voice-newer',
        conversation_turn_id: null,
        realtime_session_id: 'rt-sess-1',
        tool_name: 'list_customer_audits',
        status: 'succeeded',
        result_json: auditListResult('customer-a', ['audit-latest']),
        created_at: '2026-07-28T11:01:00Z',
      },
    ],
    audit_sessions: [remoteAudit('audit-old'), remoteAudit('audit-latest')],
  })
  const store = createSupabaseAgentAuditStore(client)

  const selected = await call(store, 'select_audit_option', { position: 1 })

  assertEquals(selected.ok, true)
  assertEquals(selected.data?.id, 'audit-latest')
})

Deno.test('a cleared conversation cannot select from the list it threw away', async () => {
  // `/new` (and the app's clear control) bumps `context_epoch` precisely so
  // "start over" means it. Reconstructing the pre-reset option list from
  // durable evidence would let the user's next number select an audit from a
  // conversation they explicitly ended.
  const client = new FakeAuditClient({
    agent_conversation_turns: [
      {
        id: 'turn-old',
        conversation_id: 'conversation-a',
        context_epoch: 1,
        conversation_seq: 4,
        created_at: '2026-07-28T10:00:00Z',
      },
    ],
    agent_realtime_sessions: [],
    agent_tool_events: [
      {
        id: 'event-old',
        conversation_turn_id: 'turn-old',
        tool_name: 'list_customer_audits',
        status: 'succeeded',
        result_json: auditListResult('customer-a', ['audit-old']),
        created_at: '2026-07-28T10:01:00Z',
      },
    ],
    audit_sessions: [remoteAudit('audit-old')],
  })
  const store = createSupabaseAgentAuditStore(client)

  const refused = await call(
    store,
    'select_audit_option',
    { position: 1 },
    scope,
    { conversationContextEpoch: 2 },
  )
  assertEquals(refused.ok, false)
  assertEquals(refused.code, 'audit_options_required')
  const turnQuery = client.queries.find((query) =>
    query.table === 'agent_conversation_turns'
  )
  assertEquals(turnQuery?.equals.context_epoch, 2)

  // Same conversation, same evidence, the epoch it was written in: selectable.
  const allowed = await call(
    store,
    'select_audit_option',
    { position: 1 },
    scope,
    { conversationContextEpoch: 1 },
  )
  assertEquals(allowed.ok, true)
  assertEquals(allowed.data?.id, 'audit-old')
})

Deno.test('the newest snapshot is chosen by plain string order, not ICU collation', async () => {
  // `localeCompare` treats punctuation as variable-weight and inverts on
  // timestamps whose fractional-second parts differ in length. `created_at`
  // is a TEXT column with nothing enforcing one rendering, so the shapes are
  // uniform only by convention — and getting this backwards resolves position
  // N against the OLDER list.
  const client = new FakeAuditClient({
    agent_conversation_turns: [
      {
        id: 'turn-a',
        conversation_id: 'conversation-a',
        conversation_seq: 1,
        created_at: '2026-07-28T10:00:00Z',
      },
    ],
    agent_realtime_sessions: [
      {
        id: 'rt-sess-1',
        conversation_id: 'conversation-a',
        created_at: '2026-07-28T10:00:00Z',
      },
    ],
    agent_tool_events: [
      {
        id: 'event-older',
        conversation_turn_id: 'turn-a',
        tool_name: 'list_customer_audits',
        status: 'succeeded',
        result_json: auditListResult('customer-a', ['audit-old']),
        created_at: '2026-07-28T12:34:56+00:00',
      },
      {
        id: 'event-newer',
        conversation_turn_id: null,
        realtime_session_id: 'rt-sess-1',
        tool_name: 'list_customer_audits',
        status: 'succeeded',
        result_json: auditListResult('customer-a', ['audit-latest']),
        // Half a second later. `localeCompare` calls this one OLDER.
        created_at: '2026-07-28T12:34:56.5+00:00',
      },
    ],
    audit_sessions: [remoteAudit('audit-old'), remoteAudit('audit-latest')],
  })
  const store = createSupabaseAgentAuditStore(client)

  const selected = await call(store, 'select_audit_option', { position: 1 })

  assertEquals(selected.ok, true)
  assertEquals(selected.data?.id, 'audit-latest')
})

Deno.test('a non-integer position is refused with a real code, never a null-payload denial', async () => {
  const store = fixtureStore()
  store.latestAuditListResult = {
    ok: true,
    code: 'ok',
    data: { customerId: 'customer-a', audits: [{ id: 'audit-1' }] },
  }
  // Bypasses executeAgentTool's own contract validation on purpose: this is
  // the defence-in-depth check, and NaN used to pass both comparisons and
  // fall through to `scope_denied`.
  const handlers = createAgentAuditToolHandlers(store)
  const result = await handlers.select_audit_option!({
    scope,
    conversationId: 'conversation-a',
    activeVisitId: null,
    toolCallId: 'tool-nan',
    arguments: Object.freeze({ position: undefined as unknown as number }),
  })
  assertEquals(result.ok, false)
  assertEquals(result.code, 'audit_position_out_of_range')
})
