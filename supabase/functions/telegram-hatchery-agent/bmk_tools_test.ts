import { assertEquals } from '@std/assert'

import type { AgentScope } from './agent_protocol.ts'
import {
  type AgentBmkStore,
  createAgentBmkToolHandlers,
} from './bmk_tools.ts'

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

Deno.test('get_breed_benchmark returns the standard for a resolved breed',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'ross',
      ageWeek: 35,
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.breed, 'Ross308')
    assertEquals(result.data?.ageWeek, 35)
    assertEquals(result.data?.hatchabilityPct, 90)
  })

Deno.test('get_breed_benchmark reports an unknown breed with the vocabulary',
  async () => {
    const result = await call('get_breed_benchmark', {
      breed: 'leghorn',
      ageWeek: 35,
    })
    assertEquals(result.ok, true)
    assertEquals(result.data?.status, 'breed_not_found')
    assertEquals(result.data?.availableBreeds, ['Cobb500', 'Ross308'])
  })

Deno.test('get_breed_benchmark reports an out-of-range week with coverage',
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
  })

Deno.test('get_breed_benchmark reports coverage per breed', async () => {
  const result = await call('get_breed_benchmark', {
    breed: 'cobb',
    ageWeek: 70,
  })
  assertEquals(result.data?.coveredWeeks, { min: 24, max: 65 })
})

Deno.test('get_egg_breakout_benchmark returns the defect targets', async () => {
  const result = await call('get_egg_breakout_benchmark', { ageWeek: 35 })
  assertEquals(result.ok, true)
  assertEquals(result.data?.ageWeek, 35)
  assertEquals(result.data?.infertilePct, 4)
  assertEquals(result.data?.contamPct, 0.5)
})

Deno.test('get_egg_breakout_benchmark reports an out-of-range week',
  async () => {
    const result = await call('get_egg_breakout_benchmark', { ageWeek: 70 })
    assertEquals(result.data?.status, 'week_out_of_range')
    assertEquals(result.data?.coveredWeeks, { min: 25, max: 65 })
  })

Deno.test('get_operational_standards returns global rows when unscoped',
  async () => {
    const result = await call('get_operational_standards', {})
    assertEquals(result.ok, true)
    const standards = result.data?.standards as Record<string, unknown>[]
    assertEquals(standards.length, 2)
    assertEquals(standards[0].metricKey, 'setter_temp')
    assertEquals(standards[0].targetValue, 99.8)
  })

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

Deno.test('a hatchery outside scope is rejected, not returned empty',
  async () => {
    const result = await call('get_operational_standards', {
      hatcheryId: 'hatchery-b',
    })
    assertEquals(result.ok, false)
    assertEquals(result.code, 'scope_denied')
  })

Deno.test('an unknown hatchery is rejected', async () => {
  const result = await call('get_operational_standards', {
    hatcheryId: 'hatchery-zzz',
  })
  assertEquals(result.ok, false)
  assertEquals(result.code, 'scope_denied')
})
