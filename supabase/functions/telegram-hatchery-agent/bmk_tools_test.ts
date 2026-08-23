import { assertEquals } from '@std/assert'

import type { AgentScope } from './agent_protocol.ts'
import type { AgentAuditStore } from './agent_audit_tools.ts'
import { type AgentBmkStore, createAgentBmkToolHandlers } from './bmk_tools.ts'

const scope: AgentScope = {
  staffLinkId: 'staff-a',
  accessRole: 'customer',
  allowedCustomerIds: ['customer-a'],
}

function fixtureStore(): AgentBmkStore {
  return {
    listBreedCoverage: () =>
      Promise.resolve([
        { breed: 'Ross308', ageWeek: 25 },
        { breed: 'Ross308', ageWeek: 35 },
        { breed: 'Ross308', ageWeek: 65 },
        { breed: 'Cobb500', ageWeek: 24 },
        { breed: 'Cobb500', ageWeek: 65 },
      ]),
    findBreedBenchmark: (breed, ageWeek) =>
      Promise.resolve(
        breed === 'Ross308' && ageWeek === 35
          ? {
            breed: 'Ross308',
            ageWeek: 35,
            hatchabilityPct: 90,
            fertilityPct: 95,
            hofPct: 86,
            productionPct: 83,
            eggWeightG: 67,
            chickWeightG: 48,
          }
          : null,
      ),
    listEggBreakoutWeeks: () => Promise.resolve([25, 35, 65]),
    findEggBreakoutBenchmark: (ageWeek) =>
      Promise.resolve(
        ageWeek === 35
          ? {
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
          }
          : null,
      ),
    findHatcheryCustomerId: (hatcheryId) =>
      Promise.resolve(
        hatcheryId === 'hatchery-a'
          ? 'customer-a'
          : hatcheryId === 'hatchery-b'
          ? 'customer-b'
          : null,
      ),
    listOperationalStandards: (hatcheryId) =>
      Promise.resolve(
        hatcheryId === null
          ? [
            {
              id: 'g-1',
              hatcheryId: null,
              stationKey: 'setter',
              sectorKey: 'incubation',
              metricKey: 'setter_temp',
              metricLabel: 'Setter temperature',
              unit: 'F',
              minValue: 99.0,
              maxValue: 100.5,
              targetValue: 99.8,
              source: 'Aviagen',
              notes: null,
              sortOrder: 1,
            },
            {
              id: 'g-2',
              hatcheryId: null,
              stationKey: 'hatcher',
              sectorKey: 'incubation',
              metricKey: 'hatcher_humidity',
              metricLabel: 'Hatcher humidity',
              unit: '%',
              minValue: 50,
              maxValue: 60,
              targetValue: 55,
              source: null,
              notes: null,
              sortOrder: 2,
            },
          ]
          : [
            {
              id: 'h-1',
              hatcheryId: 'hatchery-a',
              stationKey: 'setter',
              sectorKey: 'incubation',
              metricKey: 'setter_temp',
              metricLabel: 'Setter temperature',
              unit: 'F',
              minValue: 99.2,
              maxValue: 100.0,
              targetValue: 99.6,
              source: 'Site SOP',
              notes: 'House override',
              sortOrder: 1,
            },
          ],
      ),
  }
}

function call(
  name: string,
  args: Record<string, unknown>,
) {
  const handlers = createAgentBmkToolHandlers(fixtureStore())
  const handler = handlers[name as keyof typeof handlers]!
  return handler({
    scope,
    conversationId: 'conversation-a',
    activeVisitId: null,
    arguments: args,
  })
}

Deno.test(
  'get_breed_benchmark returns the standard for a resolved breed',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.breed, 'Ross308')
    assertEquals(result.data?.ageWeek, 35)
    assertEquals(result.data?.hatchabilityPct, 90)
  },
)

Deno.test(
  'get_breed_benchmark reports an unknown breed with the vocabulary',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'leghorn',
      ageWeek: 35,
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.status, 'breed_not_found')
    assertEquals(result.data?.availableBreeds, ['Cobb500', 'Ross308'])
  },
)

Deno.test(
  'get_breed_benchmark reports an out-of-range week with coverage',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'Ross308',
      ageWeek: 70,
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.status, 'week_out_of_range')
    assertEquals(result.data?.breed, 'Ross308')
    assertEquals(result.data?.coveredWeeks, { min: 25, max: 65 })
    // No substituted value.
    assertEquals(result.data?.hatchabilityPct, undefined)
  },
)

Deno.test('get_breed_benchmark reports coverage per breed', async () => {
  const result = await call('get_breed_benchmark', {
    breed: 'cobb',
    ageWeek: 70,
  })
  assertEquals(result.data?.coveredWeeks, { min: 24, max: 65 })
})

Deno.test(
  'get_breed_benchmark with metrics="production" returns only the requested metric plus context',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
      metrics: 'production',
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.breed, 'Ross308')
    assertEquals(result.data?.ageWeek, 35)
    assertEquals(result.data?.requested, [
      { metric: 'production', value: 83, unit: '%' },
    ])
    assertEquals(result.data?.context, {
      breed: 'Ross308',
      ageWeek: 35,
      hatchabilityPct: 90,
      fertilityPct: 95,
      hofPct: 86,
      productionPct: 83,
      eggWeightG: 67,
      chickWeightG: 48,
    })
  },
)

Deno.test(
  'get_breed_benchmark with metrics="fertility, hatchability" returns both in order',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
      metrics: 'fertility, hatchability',
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.requested, [
      { metric: 'fertility', value: 95, unit: '%' },
      { metric: 'hatchability', value: 90, unit: '%' },
    ])
  },
)

Deno.test(
  'get_breed_benchmark with an unknown metrics string returns requested:[] and unknownMetrics, not the flat row',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
      metrics: 'foo',
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.breed, 'Ross308')
    assertEquals(result.data?.ageWeek, 35)
    assertEquals(result.data?.requested, [])
    assertEquals(result.data?.unknownMetrics, ['foo'])
    assertEquals(result.data?.context, {
      breed: 'Ross308',
      ageWeek: 35,
      hatchabilityPct: 90,
      fertilityPct: 95,
      hofPct: 86,
      productionPct: 83,
      eggWeightG: 67,
      chickWeightG: 48,
    })
    // Not the flat shape: the top-level row fields are not present directly.
    assertEquals(result.data?.hatchabilityPct, undefined)
    assertEquals(result.data?.productionPct, undefined)
  },
)

Deno.test(
  'get_breed_benchmark with mixed known and unknown metrics keeps the known ones in requested AND surfaces the unknown ones',
  async () => {
    // Regression for the defect where a mixed metrics string silently
    // dropped the unresolved tokens: half the user's question (e.g.
    // "infertile and shell quality") would vanish with no signal that it
    // went unanswered.
    const result = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
      metrics: 'fertility, bogus',
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.requested, [
      { metric: 'fertility', value: 95, unit: '%' },
    ])
    assertEquals(result.data?.unknownMetrics, ['bogus'])
  },
)

Deno.test(
  'get_breed_benchmark with all-known metrics omits unknownMetrics entirely',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
      metrics: 'fertility, hatchability',
    })
    assertEquals(result.ok, true)
    assertEquals('unknownMetrics' in (result.data ?? {}), false)
  },
)

Deno.test(
  'get_breed_benchmark with a whitespace-only metrics string takes the shaped path, never the flat row',
  async () => {
    // metricsRule's minLength:1 rejects "" upstream, but " " passes
    // validation. The handler must still treat it as "metrics were
    // requested" so it can never fall through to the 11-field flat dump.
    const result = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
      metrics: ' ',
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.requested, [])
    assertEquals(result.data?.context, {
      breed: 'Ross308',
      ageWeek: 35,
      hatchabilityPct: 90,
      fertilityPct: 95,
      hofPct: 86,
      productionPct: 83,
      eggWeightG: 67,
      chickWeightG: 48,
    })
    // Anti-flat-dump: none of the row fields leak to the top level.
    assertEquals(result.data?.hatchabilityPct, undefined)
    assertEquals(result.data?.productionPct, undefined)
  },
)

Deno.test(
  'get_breed_benchmark with no metrics argument still returns the flat row',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
    })
    assertEquals(result.ok, true)
    assertEquals(result.data, {
      breed: 'Ross308',
      ageWeek: 35,
      hatchabilityPct: 90,
      fertilityPct: 95,
      hofPct: 86,
      productionPct: 83,
      eggWeightG: 67,
      chickWeightG: 48,
    })
  },
)

Deno.test(
  'get_breed_benchmark with a null row value returns value null, never a substitution',
  async () => {
    const store = fixtureStore()
    const nullProduction: AgentBmkStore = {
      ...store,
      findBreedBenchmark: (breed, ageWeek) =>
        store.findBreedBenchmark(breed, ageWeek).then((row) =>
          row ? { ...row, productionPct: null } : row
        ),
    }
    const handlers = createAgentBmkToolHandlers(nullProduction)
    const result = await handlers.get_breed_benchmark!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: { breed: 'ross', ageWeek: 35, metrics: 'production' },
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.requested, [
      { metric: 'production', value: null, unit: '%' },
    ])
    assertEquals(result.data?.unavailable, ['production'])
  },
)

Deno.test(
  'get_breed_benchmark flat shape names null metrics in unavailable',
  async () => {
    const store = fixtureStore()
    const nullProduction: AgentBmkStore = {
      ...store,
      findBreedBenchmark: (breed, ageWeek) =>
        store.findBreedBenchmark(breed, ageWeek).then((row) =>
          row ? { ...row, productionPct: null } : row
        ),
    }
    const handlers = createAgentBmkToolHandlers(nullProduction)
    const result = await handlers.get_breed_benchmark!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: { breed: 'ross', ageWeek: 35 },
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.productionPct, null)
    assertEquals(result.data?.unavailable, ['production'])
  },
)

Deno.test(
  'get_breed_benchmark flat shape omits unavailable when every metric is present',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.unavailable, undefined)
  },
)

Deno.test('get_egg_breakout_benchmark returns the defect targets', async () => {
  const result = await call('get_egg_breakout_benchmark', { ageWeek: 35 })
  assertEquals(result.ok, true)
  assertEquals(result.data?.ageWeek, 35)
  assertEquals(result.data?.infertilePct, 4)
  assertEquals(result.data?.contamPct, 0.5)
})

Deno.test(
  'get_egg_breakout_benchmark reports an out-of-range week',
  async () => {
    const result = await call('get_egg_breakout_benchmark', { ageWeek: 70 })
    assertEquals(result.data?.status, 'week_out_of_range')
    assertEquals(result.data?.coveredWeeks, { min: 25, max: 65 })
  },
)

Deno.test(
  'get_egg_breakout_benchmark with metrics="infertile" returns only the requested metric plus context',
  async () => {
    const result = await call('get_egg_breakout_benchmark', {
      ageWeek: 35,
      metrics: 'infertile',
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.ageWeek, 35)
    assertEquals(result.data?.requested, [
      { metric: 'infertile', value: 4, unit: '%' },
    ])
    assertEquals(result.data?.context, {
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
    })
  },
)

Deno.test(
  'get_egg_breakout_benchmark with metrics="cracked, contaminated" returns both in order',
  async () => {
    const result = await call('get_egg_breakout_benchmark', {
      ageWeek: 35,
      metrics: 'cracked, contaminated',
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.requested, [
      { metric: 'cracked', value: 1, unit: '%' },
      { metric: 'contaminated', value: 0.5, unit: '%' },
    ])
  },
)

Deno.test(
  'get_egg_breakout_benchmark with an unknown metrics string returns requested:[] and unknownMetrics, not the flat row',
  async () => {
    const result = await call('get_egg_breakout_benchmark', {
      ageWeek: 35,
      metrics: 'foo',
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.ageWeek, 35)
    assertEquals(result.data?.requested, [])
    assertEquals(result.data?.unknownMetrics, ['foo'])
    assertEquals(result.data?.context, {
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
    })
    // Not the flat shape: the top-level row fields are not present directly.
    // This is the anti-regression assertion -- an unmatched metrics arg must
    // never degrade to a flat 11-field dump.
    assertEquals(result.data?.infertilePct, undefined)
    assertEquals(result.data?.crackedPct, undefined)
    assertEquals(result.data?.contamPct, undefined)
    assertEquals(result.data?.early24hPct, undefined)
    assertEquals(result.data?.early48hPct, undefined)
    assertEquals(result.data?.bloodRingPct, undefined)
    assertEquals(result.data?.blackEyePct, undefined)
    assertEquals(result.data?.earlyDeadPct, undefined)
    assertEquals(result.data?.midDeadPct, undefined)
    assertEquals(result.data?.lateDeadPct, undefined)
    assertEquals(result.data?.externalPipPct, undefined)
  },
)

Deno.test(
  'get_egg_breakout_benchmark with mixed known and unknown metrics keeps the known ones in requested AND surfaces the unknown ones',
  async () => {
    // Mirrors get_breed_benchmark. This assertion used to pin `unknownMetrics
    // === undefined` for the mixed case, which encoded a defect: once at
    // least one token resolved, the unresolved tokens were silently
    // discarded, so the model would answer only the part of a mixed
    // question ("infertile and shell quality") it understood and treat the
    // rest as answered. Corrected to require unknownMetrics to still carry
    // the unresolved tokens alongside the resolved `requested` ones.
    const result = await call('get_egg_breakout_benchmark', {
      ageWeek: 35,
      metrics: 'infertile, bogus, cracked',
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.requested, [
      { metric: 'infertile', value: 4, unit: '%' },
      { metric: 'cracked', value: 1, unit: '%' },
    ])
    assertEquals(result.data?.unknownMetrics, ['bogus'])
  },
)

Deno.test(
  'get_egg_breakout_benchmark with all-known metrics omits unknownMetrics entirely',
  async () => {
    const result = await call('get_egg_breakout_benchmark', {
      ageWeek: 35,
      metrics: 'cracked, contaminated',
    })
    assertEquals(result.ok, true)
    assertEquals('unknownMetrics' in (result.data ?? {}), false)
  },
)

Deno.test(
  'get_egg_breakout_benchmark with a whitespace-only metrics string takes the shaped path, never the flat row',
  async () => {
    // metricsRule's minLength:1 rejects "" upstream, but " " passes
    // validation. The handler must still treat it as "metrics were
    // requested" so it can never fall through to the 11-field flat dump.
    const result = await call('get_egg_breakout_benchmark', {
      ageWeek: 35,
      metrics: ' ',
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.requested, [])
    assertEquals(result.data?.context, {
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
    })
    // Anti-flat-dump: none of the row fields leak to the top level.
    assertEquals(result.data?.infertilePct, undefined)
    assertEquals(result.data?.productionPct, undefined)
  },
)

Deno.test(
  'get_egg_breakout_benchmark with no metrics argument still returns the flat row',
  async () => {
    const result = await call('get_egg_breakout_benchmark', { ageWeek: 35 })
    assertEquals(result.ok, true)
    assertEquals(result.data, {
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
    })
  },
)

Deno.test(
  'get_egg_breakout_benchmark with a null row value returns value null, never a substitution',
  async () => {
    const store = fixtureStore()
    const nullContam: AgentBmkStore = {
      ...store,
      findEggBreakoutBenchmark: (ageWeek) =>
        store.findEggBreakoutBenchmark(ageWeek).then((row) =>
          row ? { ...row, contamPct: null } : row
        ),
    }
    const handlers = createAgentBmkToolHandlers(nullContam)
    const result = await handlers.get_egg_breakout_benchmark!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: { ageWeek: 35, metrics: 'contaminated' },
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.requested, [
      { metric: 'contaminated', value: null, unit: '%' },
    ])
    assertEquals(result.data?.unavailable, ['contaminated'])
  },
)

Deno.test(
  'get_egg_breakout_benchmark flat shape names null metrics in unavailable',
  async () => {
    const store = fixtureStore()
    const nullContam: AgentBmkStore = {
      ...store,
      findEggBreakoutBenchmark: (ageWeek) =>
        store.findEggBreakoutBenchmark(ageWeek).then((row) =>
          row ? { ...row, contamPct: null } : row
        ),
    }
    const handlers = createAgentBmkToolHandlers(nullContam)
    const result = await handlers.get_egg_breakout_benchmark!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: { ageWeek: 35 },
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.contamPct, null)
    assertEquals(result.data?.unavailable, ['contaminated'])
  },
)

Deno.test(
  'get_egg_breakout_benchmark flat shape omits unavailable when every metric is present',
  async () => {
    const result = await call('get_egg_breakout_benchmark', { ageWeek: 35 })
    assertEquals(result.ok, true)
    assertEquals(result.data?.unavailable, undefined)
  },
)

Deno.test(
  'get_egg_breakout_benchmark week_out_of_range is unaffected by a metrics arg',
  async () => {
    const result = await call('get_egg_breakout_benchmark', {
      ageWeek: 70,
      metrics: 'infertile',
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.status, 'week_out_of_range')
    assertEquals(result.data?.coveredWeeks, { min: 25, max: 65 })
    assertEquals(result.data?.requested, undefined)
  },
)

Deno.test(
  "get_breed_benchmark's output is unaffected by generalizing parseRequestedMetrics/nullMetricKeys for the breakout catalogue",
  async () => {
    const full = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
    })
    assertEquals(full.data, {
      breed: 'Ross308',
      ageWeek: 35,
      hatchabilityPct: 90,
      fertilityPct: 95,
      hofPct: 86,
      productionPct: 83,
      eggWeightG: 67,
      chickWeightG: 48,
    })
    const requested = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
      metrics: 'fertility, hatchability',
    })
    assertEquals(requested.data?.requested, [
      { metric: 'fertility', value: 95, unit: '%' },
      { metric: 'hatchability', value: 90, unit: '%' },
    ])
    const unknown = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
      metrics: 'foo',
    })
    assertEquals(unknown.data?.requested, [])
    assertEquals(unknown.data?.unknownMetrics, ['foo'])
  },
)

Deno.test(
  'get_operational_standards returns global rows when unscoped',
  async () => {
    const result = await call('get_operational_standards', {})
    assertEquals(result.ok, true)
    const standards = result.data?.standards as Record<string, unknown>[]
    assertEquals(standards.length, 2)
    assertEquals(standards[0].metricKey, 'setter_temp')
    assertEquals(standards[0].targetValue, 99.8)
  },
)

Deno.test('hatchery rows override global rows on metricKey', async () => {
  const result = await call('get_operational_standards', {
    hatcheryId: 'hatchery-a',
  })
  const standards = result.data?.standards as Record<string, unknown>[]
  assertEquals(standards.length, 2)
  assertEquals(standards[0].metricKey, 'setter_temp')
  // Overridden by the hatchery row.
  assertEquals(standards[0].targetValue, 99.6)
  assertEquals(standards[0].hatcheryId, 'hatchery-a')
  // Untouched global row still present.
  assertEquals(standards[1].metricKey, 'hatcher_humidity')
  assertEquals(standards[1].targetValue, 55)
})

Deno.test('stationKey filters the merged result', async () => {
  const result = await call('get_operational_standards', {
    hatcheryId: 'hatchery-a',
    stationKey: 'hatcher',
  })
  const standards = result.data?.standards as Record<string, unknown>[]
  assertEquals(standards.length, 1)
  assertEquals(standards[0].metricKey, 'hatcher_humidity')
})

Deno.test(
  'a hatchery outside scope is rejected, not returned empty',
  async () => {
    const result = await call('get_operational_standards', {
      hatcheryId: 'hatchery-b',
    })
    assertEquals(result.ok, false)
    assertEquals(result.code, 'scope_denied')
  },
)

Deno.test('an unknown hatchery is rejected', async () => {
  const result = await call('get_operational_standards', {
    hatcheryId: 'hatchery-zzz',
  })
  assertEquals(result.ok, false)
  assertEquals(result.code, 'scope_denied')
})

function fixtureAuditStore(): AgentAuditStore {
  const audit = {
    id: 'audit-1',
    customerId: 'customer-a',
    flockId: 'flock-a',
    hatcheryId: 'hatchery-a',
    date: '2026-08-01',
    status: 'completed',
    customerName: 'Customer A',
    flockName: 'Flock A',
    hatcheryName: 'Hatchery A',
    selectedStationKeys: null,
    stationsCompleted: null,
    createdAt: null,
    completedAt: null,
    breed: 'Ross308',
    flockAgeWeeks: 35,
    findings: null,
    scorecard: null,
    notes: null,
  }
  return {
    findFlockCustomerId: () => Promise.resolve('customer-a'),
    findLatestAuditListResult: () => Promise.resolve(null),
    findLatestSelectedAuditResult: () => Promise.resolve(null),
    loadConversationContext: () =>
      Promise.resolve({
        customerId: 'customer-a',
        flockId: 'flock-a',
        auditId: 'audit-1',
      }),
    findAudit: () => Promise.resolve(audit),
    listAudits: () => Promise.resolve({ rows: [audit], truncated: false }),
    listAuditBreakouts: () =>
      Promise.resolve({
        rows: [
          {
            breakoutType: 'fresh' as const,
            id: 'b-1',
            sessionId: 'audit-1',
            customerId: 'customer-a',
            flockId: 'flock-a',
            hatcheryId: 'hatchery-a',
            date: '2026-08-01',
            house: null,
            setter: null,
            hatcher: null,
            trolley: null,
            tray: null,
            position: null,
            traySize: 100,
            infertileCount: null,
            infertilePct: 6,
            early24hPct: 1,
            early48hPct: 1,
            bloodRingPct: 0.5,
            blackEyePct: 0.5,
            earlyDeadPct: 2,
            midDeadPct: 1,
            lateDeadPct: 2,
            externalPipPct: 0.5,
            crackedPct: 1,
            contaminatedPct: 1.5,
            hatchabilityPct: 86,
            fertilityPct: 94,
            hofPct: 84,
            culledPct: null,
            deadPct: null,
          },
        ],
        truncated: false,
      }),
  } as unknown as AgentAuditStore
}

Deno.test(
  'compare_selected_audit_to_benchmark returns per-metric deltas',
  async () => {
    const handlers = createAgentBmkToolHandlers(
      fixtureStore(),
      fixtureAuditStore(),
    )
    const result = await handlers.compare_selected_audit_to_benchmark!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: {},
    })

    assertEquals(result.ok, true)
    assertEquals(result.data?.breed, 'Ross308')
    assertEquals(result.data?.ageWeek, 35)

    const rows = result.data?.comparisons as Record<string, unknown>[]
    const byKey = new Map(rows.map((row) => [row.metricKey, row]))

    assertEquals(byKey.get('hatchabilityPct')?.actual, 86)
    assertEquals(byKey.get('hatchabilityPct')?.standard, 90)
    assertEquals(byKey.get('hatchabilityPct')?.delta, -4)

    // Audit contaminatedPct maps onto benchmark contamPct.
    assertEquals(byKey.get('contamPct')?.actual, 1.5)
    assertEquals(byKey.get('contamPct')?.standard, 0.5)
    assertEquals(byKey.get('contamPct')?.delta, 1)

    // No actual exists for these on a breakout row -- reported, not dropped.
    assertEquals(byKey.get('eggWeightG')?.reason, 'no_actual')
    assertEquals(byKey.get('productionPct')?.reason, 'no_actual')
  },
)

Deno.test(
  'compare reports a missing benchmark rather than dropping metrics',
  async () => {
    const store = fixtureStore()
    const emptyBenchmarks: AgentBmkStore = {
      ...store,
      findBreedBenchmark: () => Promise.resolve(null),
      findEggBreakoutBenchmark: () => Promise.resolve(null),
    }
    const handlers = createAgentBmkToolHandlers(
      emptyBenchmarks,
      fixtureAuditStore(),
    )
    const result = await handlers.compare_selected_audit_to_benchmark!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: {},
    })

    assertEquals(result.data?.status, 'week_out_of_range')
    assertEquals(result.data?.breed, 'Ross308')
  },
)

Deno.test(
  'compare requires a selected audit, same contract as the sibling tools',
  async () => {
    const auditStore = {
      ...fixtureAuditStore(),
      loadConversationContext: () => Promise.resolve(null),
    } as unknown as AgentAuditStore
    const handlers = createAgentBmkToolHandlers(fixtureStore(), auditStore)
    const result = await handlers.compare_selected_audit_to_benchmark!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: {},
    })
    assertEquals(result.ok, false)
    assertEquals(result.code, 'fresh_audit_selection_required')
    assertEquals(result.data, {
      selectedCustomerId: null,
      selectedFlockId: null,
    })
  },
)

Deno.test(
  'compare treats a stale flockId in context as a fresh selection required',
  async () => {
    const auditStore = {
      ...fixtureAuditStore(),
      loadConversationContext: () =>
        Promise.resolve({
          customerId: 'customer-a',
          // The conversation still points at a flock that no longer
          // matches the fetched audit's flock -- e.g. the customer
          // selected a different flock after this audit was chosen.
          flockId: 'flock-b',
          auditId: 'audit-1',
        }),
    } as unknown as AgentAuditStore
    const handlers = createAgentBmkToolHandlers(fixtureStore(), auditStore)
    const result = await handlers.compare_selected_audit_to_benchmark!({
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      arguments: {},
    })
    assertEquals(result.ok, false)
    assertEquals(result.code, 'fresh_audit_selection_required')
    assertEquals(result.data, {
      selectedCustomerId: 'customer-a',
      selectedFlockId: 'flock-b',
    })
  },
)
