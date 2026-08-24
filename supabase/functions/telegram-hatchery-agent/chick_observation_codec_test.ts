import { assertEquals } from '@std/assert'

import { requireStationSchema } from '../_shared/station_registry.generated.ts'
import {
  canRoundTripChickObservations,
  extractChickObservations,
  reconstructChickObservationValues,
} from './chick_observation_codec.ts'

const context = {
  sampleId: '018f0f00-0000-7000-8000-000000000001',
  customerId: 'customer-a',
  sessionId: 'session-a',
  observedAt: '2026-08-24T05:00:00.000Z',
}

Deno.test('TypeScript observation extraction preserves zero and stable ids', () => {
  const schema = requireStationSchema('chicks.weights', 1)
  const observations = extractChickObservations(schema, context, {
    weightsJson: [41, 0, 43.5],
  })

  assertEquals(
    observations.map((item) => [
      item.kind,
      item.observationKey,
      item.ordinal,
      item.numericValue,
      item.textValue,
      item.unit,
    ]),
    [
      ['series', 'weightsJson', 0, 41, null, 'grams'],
      ['series', 'weightsJson', 1, 0, null, 'grams'],
      ['series', 'weightsJson', 2, 43.5, null, 'grams'],
    ],
  )
  assertEquals(
    extractChickObservations(schema, context, {
      weightsJson: [41, 0, 43.5],
    }).map((item) => item.id),
    observations.map((item) => item.id),
  )
  assertEquals(reconstructChickObservationValues(schema, observations), {
    weightsJson: [41, 0, 43.5],
  })
})

Deno.test('TypeScript keyed culled tallies round-trip Unicode keys', () => {
  const schema = requireStationSchema('chicks.culled_analysis', 1)
  const observations = extractChickObservations(schema, context, {
    culledChicksTotalEggSet: 100,
    culledChicksAnalysisJson: [
      { id: 'sticky/جاف', count: 0 },
      { id: 'weak', count: 3 },
    ],
  })

  assertEquals(reconstructChickObservationValues(schema, observations), {
    culledChicksTotalEggSet: 100,
    culledChicksAnalysisJson: [
      { id: 'sticky/جاف', count: 0 },
      { id: 'weak', count: 3 },
    ],
  })
})

Deno.test('TypeScript preserves an explicit empty culled list', () => {
  const schema = requireStationSchema('chicks.culled_analysis', 1)
  const observations = extractChickObservations(schema, context, {
    culledChicksTotalEggSet: 100,
    culledChicksAnalysisJson: [],
  })
  assertEquals(reconstructChickObservationValues(schema, observations), {
    culledChicksTotalEggSet: 100,
    culledChicksAnalysisJson: [],
  })
})

Deno.test('TypeScript property order and ignored cache fields are lossless', () => {
  assertEquals(
    canRoundTripChickObservations(
      requireStationSchema('chicks.yfbm', 1),
      { yfbmEntriesJson: [{ yolkWeight: 4.5, chickWeight: 42 }] },
    ),
    true,
  )
  assertEquals(
    canRoundTripChickObservations(
      requireStationSchema('chicks.culled_analysis', 1),
      {
        culledChicksAnalysisJson: [{
          pct: 0.5,
          sourceRefs: [],
          commonCauses: [],
          description: 'derived label',
          subtype: 'derived subtype',
          category: 'derived category',
          count: 5,
          id: 'weak',
        }],
      },
    ),
    true,
  )
})

Deno.test('TypeScript omits sparse and incomplete series', () => {
  const weights = requireStationSchema('chicks.weights', 1)
  const weightRows = extractChickObservations(weights, context, {
    weightsJson: [40, 41, 42],
  }).filter((item) => item.ordinal !== 1)
  assertEquals(reconstructChickObservationValues(weights, weightRows), {})

  const yfbm = requireStationSchema('chicks.yfbm', 1)
  const yfbmRows = extractChickObservations(yfbm, context, {
    yfbmEntriesJson: [{ chickWeight: 42, yolkWeight: 4.5 }],
  }).filter((item) => item.observationKey !== 'yfbm:yolkWeight')
  assertEquals(reconstructChickObservationValues(yfbm, yfbmRows), {})

  const culled = requireStationSchema('chicks.culled_analysis', 1)
  const culledRows = extractChickObservations(culled, context, {
    culledChicksAnalysisJson: [
      { id: 'weak', count: 1 },
      { id: 'small', count: 2 },
    ],
  }).filter((item) => item.ordinal !== 0)
  assertEquals(reconstructChickObservationValues(culled, culledRows), {})
})

Deno.test('TypeScript omits wrong-unit and wrong-value-shape observations', () => {
  const schema = requireStationSchema('chicks.pasgar', 1)
  const valid = extractChickObservations(schema, context, {
    pasgarSampleSize: 10,
  })[0]
  assertEquals(
    reconstructChickObservationValues(schema, [{ ...valid, unit: 'grams' }]),
    {},
  )
  assertEquals(
    reconstructChickObservationValues(schema, [{
      ...valid,
      numericValue: null,
      textValue: 'bad',
    }]),
    {},
  )
})
