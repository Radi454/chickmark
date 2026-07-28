import { assertEquals } from '@std/assert'

import {
  agentStationRegistry,
  requireStationSchema,
} from '../_shared/station_registry.generated.ts'
import {
  deriveStationAdapter,
  validateStationValueSet,
} from './agent_station_adapter.ts'

interface StationFixture {
  values: Record<string, unknown>
  expectedCalculations: Record<string, unknown>
}

const fixtures: Record<string, StationFixture> = {
  'chicks.pasgar': {
    values: {
      pasgarSampleSize: 40,
      pasgarReflexesCount: 2,
      pasgarBeakCount: 1,
      pasgarNavelCount: 3,
      pasgarBellyCount: 1,
      pasgarLegCount: 2,
      pasgarFeatherDevCount: 3,
    },
    expectedCalculations: {
      pasgarReflexesPct: 5,
      pasgarBeakPct: 2.5,
      pasgarNavelPct: 7.5,
      pasgarBellyPct: 2.5,
      pasgarLegPct: 5,
      pasgarFeatherDevPct: 7.5,
      pasgarFinalScore: 9.8,
    },
  },
  'egg.storage_environment': {
    values: {
      storagePeriodDays: 4,
      turningTimes: 2,
      traySpacing: 'adequate',
      coolerProximity: 'clear',
      condensationPresent: false,
    },
    expectedCalculations: {},
  },
  'egg.shell_temperature': {
    values: { estReadingsJson: [19, 20, 21] },
    expectedCalculations: { estAvg: 20, estCvPct: 5 },
  },
  'egg.upside_down': {
    values: { upsideDownCount: 2 },
    expectedCalculations: {},
  },
  'egg.quality_uv': {
    values: {
      uvTrayEggCount: 100,
      uvCuticleDamageCount: 4,
      uvWashedCount: 3,
      uvDirtyCount: 2,
    },
    expectedCalculations: {
      uvCuticleDamagePct: 4,
      uvWashedPct: 3,
      uvDirtyPct: 2,
      uvAffectedCount: 9,
      uvAffectedPct: 9,
    },
  },
  'egg.weights': {
    values: { eggWeightsJson: [50, 55, 60] },
    expectedCalculations: {
      eggSampleSize: 3,
      eggAvgWeight: 55,
      eggUniformityPct: 100,
      eggCvPct: 9.1,
    },
  },
  'chicks.yfbm': {
    values: {
      yfbmEntriesJson: [
        { chickWeight: 40, yolkWeight: 4 },
        { chickWeight: 50, yolkWeight: 5 },
      ],
    },
    expectedCalculations: {
      yfbmEntryCount: 2,
      yfbmAvgPct: 10,
      yfbmCvPct: 0,
    },
  },
  'chicks.cvt': {
    values: { cvtReadingsJson: [103, 104, 105] },
    expectedCalculations: {
      cvtSampleSize: 3,
      cvtAvgTemp: 104,
      cvtCvPct: 1,
    },
  },
  'chicks.postmortem': {
    values: {
      pmSampleSize: 20,
      pmCollectionPoint: 'hatcher take-off',
      pmOmphalitisCount: 0,
      pmGaseousCecaCount: 0,
      pmGizzardErosionsCount: 0,
      pmAirSacCaseationsCount: 0,
      pmUrolithiasisCount: 0,
      pmNephritisCount: 0,
      pmGeneralSepticemiaCount: 0,
    },
    expectedCalculations: {},
  },
  'chicks.culled_analysis': {
    values: {
      culledChicksTotalEggSet: 100,
      culledChicksAnalysisJson: [
        { id: 'navel_open_unhealed', count: 2 },
      ],
    },
    expectedCalculations: {
      culledChicksAffectedPct: 2,
      culledChicksTopCategory: 'Navel',
      culledChicksTopSubtype: 'Open / unhealed navel',
    },
  },
  'chicks.weights': {
    values: { weightsJson: [40, 44, 48] },
    expectedCalculations: {
      sampleSize: 3,
      avgWeight: 44,
      uniformityPct: 100,
      cvPct: 9.1,
    },
  },
  'hatch_analysis.fresh_breakout': {
    values: {
      traySize: 100,
      infertileCount: 10,
      early24hCount: 2,
      early48hCount: 3,
      bloodRingCount: 5,
    },
    expectedCalculations: {
      infertilePct: 10,
      early24hPct: 2,
      early48hPct: 3,
      bloodRingPct: 5,
    },
  },
  'hatch_analysis.candled_breakout': {
    values: {
      candlingDay: 10,
      traySize: 100,
      infertileCount: 10,
      early24hCount: 2,
      early48hCount: 3,
      bloodRingCount: 5,
      blackEyeCount: 4,
    },
    expectedCalculations: {
      infertilePct: 10,
      early24hPct: 2,
      early48hPct: 3,
      bloodRingPct: 5,
      blackEyePct: 4,
    },
  },
  'hatch_analysis.residue_breakout': {
    values: {
      traySize: 100,
      infertileCount: 10,
      earlyDeadCount: 5,
      midDeadCount: 4,
      lateDeadCount: 3,
      externalPipCount: 2,
      crackedCount: 1,
      contaminatedCount: 1,
      totalEggsSet: 1000,
      hatchedCount: 850,
      culledCount: 20,
      deadCount: 10,
    },
    expectedCalculations: {
      infertilePct: 10,
      earlyDeadPct: 5,
      midDeadPct: 4,
      lateDeadPct: 3,
      externalPipPct: 2,
      crackedPct: 1,
      contaminatedPct: 1,
      hatchabilityPct: 85,
      fertilityPct: 90,
      hofPct: 94.4,
      culledPct: 2,
      deadPct: 1,
    },
  },
  'setters.environment': {
    values: {
      setpointF: 99.5,
      actualF: 99.7,
      setpointRh: 55,
      actualRh: 54,
      turningAngle: 45,
      co2Ppm: 2500,
      incubationAgeDays: 10,
      incubationHours: 4,
    },
    expectedCalculations: {},
  },
  'setters.shell_temperature': {
    values: { estReadingsJson: [100, 101] },
    expectedCalculations: {
      estSampleSize: 2,
      estAvg: 100.5,
      estCvPct: 0.7,
    },
  },
  'hatchers.environment': {
    values: {
      setpointF: 98.5,
      setpointRh: 55,
      incubationAgeDays: 19,
      incubationHours: 6,
      co2Ppm: 3000,
      chickPanting: false,
      meconium: 'none',
      transferDay: 18,
    },
    expectedCalculations: {},
  },
  'hatchers.cvt': {
    values: { cvtReadingsJson: [103, 104, 105] },
    expectedCalculations: {
      cvtSampleSize: 3,
      cvtAvg: 104,
      cvtCvPct: 1,
    },
  },
}

Deno.test('all 18 station schemas validate, derive, and map persistence', () => {
  assertEquals(Object.keys(fixtures).length, 18)
  assertEquals(agentStationRegistry.stations.length, 18)

  for (const [schemaKey, fixture] of Object.entries(fixtures)) {
    const schema = requireStationSchema(schemaKey, 1)
    const validation = validateStationValueSet(schema, fixture.values)
    assertEquals(
      validation,
      { valid: true, missing: [], issues: [] },
      schemaKey,
    )

    const adapter = deriveStationAdapter(schema, fixture.values)
    assertEquals(
      adapter.calculations,
      fixture.expectedCalculations,
      `${schemaKey} calculations`,
    )
    assertEquals(adapter.persistence.length, 1, `${schemaKey} mapping count`)
    assertEquals(
      adapter.persistence[0].remoteTable,
      schema.persistence[0].remoteTable,
      `${schemaKey} remote table`,
    )
    for (const field of schema.fields) {
      const key = field.fieldKey as string
      if (!(key in fixture.values)) continue
      const remoteColumn = (field.persistence as Record<string, unknown>)
        .remoteColumn as string
      assertEquals(
        remoteColumn in adapter.persistence[0].values,
        true,
        `${schemaKey}.${key} persistence`,
      )
    }
    for (const calculation of schema.calculations) {
      const key = calculation.fieldKey as string
      const remoteColumn = (calculation.persistence as Record<string, unknown>)
        .remoteColumn as string
      assertEquals(
        remoteColumn in adapter.persistence[0].values,
        true,
        `${schemaKey}.${key} calculation persistence`,
      )
    }
  }
})

Deno.test('every station reports missing required data and rejects a boundary', () => {
  for (const [schemaKey, fixture] of Object.entries(fixtures)) {
    const schema = requireStationSchema(schemaKey, 1)
    const requiredKey = schema.completion.requiredFieldKeys[0]
    const missingValues = { ...fixture.values }
    delete missingValues[requiredKey]
    const missing = validateStationValueSet(schema, missingValues)
    assertEquals(missing.valid, false, `${schemaKey} missing validity`)
    assertEquals(
      missing.missing.includes(requiredKey),
      true,
      `${schemaKey} missing ${requiredKey}`,
    )

    const firstField = schema.fields[0] as Record<string, unknown>
    const invalidValues = {
      ...fixture.values,
      [firstField.fieldKey as string]: invalidValueFor(firstField),
    }
    const invalid = validateStationValueSet(schema, invalidValues)
    assertEquals(invalid.valid, false, `${schemaKey} boundary validity`)
    assertEquals(invalid.issues.length > 0, true, `${schemaKey} boundary issue`)
  }
})

function invalidValueFor(field: Record<string, unknown>): unknown {
  const type = field.type
  const validation = field.validation as Record<string, unknown>
  if (type === 'integer' || type === 'number') {
    if (typeof validation.min === 'number') return validation.min - 1
    if (typeof validation.max === 'number') return validation.max + 1
    return 'not-a-number'
  }
  if (type === 'number_list') return ['not-a-number']
  if (type === 'object_list') return [{}]
  if (type === 'boolean') return 'not-a-boolean'
  return 42
}
