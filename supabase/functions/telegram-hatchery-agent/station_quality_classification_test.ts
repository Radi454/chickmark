import { assertEquals } from 'jsr:@std/assert'
import {
  agentStationRegistry,
  requireStationSchema,
} from '../_shared/station_registry.generated.ts'
import { classifyStationQuality } from './agent_station_adapter.ts'

Deno.test('quality classification matches the canonical Dart tiers and codes', () => {
  const schema = requireStationSchema('chicks.pasgar', 1)
  const values = {
    pasgarSampleSize: 40,
    pasgarReflexesCount: 0,
    pasgarBeakCount: 41,
    pasgarNavelCount: 0,
    pasgarBellyCount: 0,
    pasgarLegCount: 0,
    pasgarFeatherDevCount: 0,
  }
  const result = classifyStationQuality(schema, values, {
    domain: 'chicks.pasgar',
    schemaVersion: 1,
    scopeType: 'pool',
    scopeKey: '{}',
    sampleKey: 'stable-key',
  })
  assertEquals(result.status, 'WARN')
  assertEquals(result.flags.map((flag) => flag.code), [
    'above_dynamic_maximum',
  ])
})

Deno.test('quality classification blocks structural scope failures', () => {
  const schema = requireStationSchema('chicks.weights', 1)
  const result = classifyStationQuality(schema, { weightsJson: [40] }, {
    domain: 'chicks.weights',
    schemaVersion: 1,
    scopeType: 'setter_hatcher',
    scopeKey: '{"setterId":"S","hatcherId":"H"}',
    sampleKey: 'stable-key',
  })
  assertEquals(result.status, 'BLOCK')
  assertEquals(result.flags.map((flag) => flag.code), ['scope_not_allowed'])
})

Deno.test('quality classification tolerates a partially completed derived schema', () => {
  const schema = requireStationSchema('chicks.pasgar', 1)
  const result = classifyStationQuality(
    schema,
    {
      pasgarSampleSize: 20,
      pasgarReflexesCount: 1,
      pasgarReflexesPct: 5,
    },
    {
      domain: 'chicks.pasgar',
      schemaVersion: 1,
      scopeType: 'pool',
      scopeKey: '{}',
      sampleKey: 'stable-key',
    },
  )

  assertEquals(result.status, 'FLAG')
  assertEquals(result.flags.map((flag) => flag.code), [
    'missing_required',
    'missing_required',
    'missing_required',
    'missing_required',
    'missing_required',
  ])
})

Deno.test('quality classification blocks malformed derived inputs without throwing', () => {
  const schema = requireStationSchema('chicks.pasgar', 1)
  const result = classifyStationQuality(
    schema,
    {
      pasgarSampleSize: 20,
      pasgarReflexesCount: 'not-a-number',
      pasgarReflexesPct: 5,
    },
    {
      domain: 'chicks.pasgar',
      schemaVersion: 1,
      scopeType: 'pool',
      scopeKey: '{}',
      sampleKey: 'stable-key',
    },
  )

  assertEquals(result.status, 'BLOCK')
  assertEquals(
    result.flags.map((flag) => flag.code).includes('invalid_type'),
    true,
  )
  assertEquals(
    result.flags.map((flag) => flag.code).includes('derived_cache_mismatch'),
    true,
  )
})

Deno.test('quality classification tolerates a derived object missing a required item', () => {
  const schema = requireStationSchema('chicks.culled_analysis', 1)
  const result = classifyStationQuality(
    schema,
    {
      culledChicksTotalEggSet: 100,
      culledChicksAnalysisJson: [{
        id: 'sticky_dehydrated_burned_chick',
      }],
      culledChicksAffectedPct: 1,
    },
    {
      domain: 'chicks.culled_analysis',
      schemaVersion: 1,
      scopeType: 'pool',
      scopeKey: '{}',
      sampleKey: 'stable-key',
    },
  )

  assertEquals(result.status, 'WARN')
  assertEquals(
    result.flags.map((flag) => flag.code).includes('item_required'),
    true,
  )
  assertEquals(
    result.flags.map((flag) => flag.code).includes('derived_cache_mismatch'),
    true,
  )
})

Deno.test('registry parity vectors pin canonical classification output', () => {
  const vectors = agentStationRegistry.qualityClassification.parityVectors
  for (const vector of vectors) {
    const result = classifyStationQuality(
      requireStationSchema(vector.schemaKey, vector.schemaVersion),
      vector.values,
      vector.context,
    )
    assertEquals(result.status, vector.expectedStatus)
    assertEquals(result.canonicalJson, JSON.stringify(vector.expectedFlags))
  }
})
