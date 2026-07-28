import { assertEquals } from '@std/assert'
import { agentStationRegistry } from '../_shared/station_registry.generated.ts'

import {
  configuredWarningDelta,
  cvPercent,
  fertility,
  hatchability,
  hof,
  pasgarScore,
  percentOf,
  ratioOfSums,
  sampleWeightedMean,
  uniformityPercent,
} from './agent_metrics.ts'

Deno.test('deterministic metric formulas match Flutter parity vectors', () => {
  const parity = agentStationRegistry.calculationParityVectors
  const percent = parity.percentOf[0]
  assertEquals(percentOf(percent.count, percent.total), percent.expected)
  assertEquals(percentOf(null, 40), null)
  assertEquals(percentOf(41, 40), null)
  const cv = parity.cvPercent[0]
  assertEquals(cvPercent(cv.values, { sample: cv.sample }), cv.expected)
  const uniformity = parity.uniformityPercent[0]
  assertEquals(
    uniformityPercent(
      uniformity.values,
      uniformity.minimum,
      uniformity.maximum,
    ),
    uniformity.expected,
  )
  const pasgar = parity.pasgarScore[0]
  assertEquals(
    pasgarScore(pasgar.sampleSize, pasgar.defectCounts),
    pasgar.expected,
  )
  const fertilityVector = parity.fertility[0]
  assertEquals(
    fertility(fertilityVector.fertile, fertilityVector.clear),
    fertilityVector.expected,
  )
  const hatchabilityVector = parity.hatchability[0]
  assertEquals(
    hatchability(hatchabilityVector.hatched, hatchabilityVector.total),
    hatchabilityVector.expected,
  )
  const hofVector = parity.hof[0]
  assertEquals(
    hof(hofVector.hatchability, hofVector.fertility),
    hofVector.expected,
  )
})

Deno.test('ratio and weighted aggregation preserve nulls and denominators', () => {
  const rows = [
    { defects: 2, sample: 40, score: 9.5 },
    { defects: 8, sample: 60, score: 8.5 },
    { defects: null, sample: 50, score: null },
  ]
  assertEquals(ratioOfSums(rows, 'defects', 'sample'), {
    value: 10,
    observedRows: 2,
    numerator: 10,
    denominator: 100,
  })
  assertEquals(sampleWeightedMean(rows, 'score', 'sample'), {
    value: 8.9,
    observedRows: 2,
    weight: 100,
  })
  assertEquals(ratioOfSums([{ defects: null }], 'defects', 'sample'), {
    value: null,
    observedRows: 0,
    numerator: null,
    denominator: null,
  })
})

Deno.test('configured warning threshold reports direction without inventing data', () => {
  assertEquals(configuredWarningDelta(83, 79, 3), {
    triggered: true,
    delta: 4,
    direction: 'increase',
  })
  assertEquals(configuredWarningDelta(null, 79, 3), {
    triggered: false,
    delta: null,
    direction: null,
  })
})
