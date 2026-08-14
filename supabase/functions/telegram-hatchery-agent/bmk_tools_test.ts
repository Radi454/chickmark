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
