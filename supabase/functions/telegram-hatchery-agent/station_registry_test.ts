import { assertEquals } from '@std/assert'

import {
  applicableStationSchemas,
  requireStationSchema,
} from '../_shared/station_registry.generated.ts'
import {
  fieldValuesFromLocalRow,
  localPersistenceValues,
} from './agent_station_adapter.ts'

Deno.test('Pasgar registry contract keeps explicit sample-bound observations', () => {
  const schema = requireStationSchema('chicks.pasgar', 1)
  const fields = schema.fields as ReadonlyArray<Record<string, unknown>>
  const completion = new Set(schema.completion.requiredFieldKeys)
  const expected = new Set([
    'pasgarSampleSize',
    'pasgarReflexesCount',
    'pasgarBeakCount',
    'pasgarNavelCount',
    'pasgarBellyCount',
    'pasgarLegCount',
    'pasgarFeatherDevCount',
  ])

  assertEquals(completion, expected)
  for (const field of fields) {
    if (field.fieldKey === 'pasgarSampleSize') continue
    assertEquals(field.explicitZero, true)
    assertEquals(
      (field.validation as Record<string, unknown>).maxFieldKey,
      'pasgarSampleSize',
    )
  }
  assertEquals(schema.persistence[0].remoteTable, 'chick_quality')
})

Deno.test('breeder catalog returns the registered hatchery modules only', () => {
  const breeder = applicableStationSchemas(['breeder'])
  const broiler = applicableStationSchemas(['broiler'])

  assertEquals(
    breeder.some((schema) => schema.schemaKey === 'chicks.pasgar'),
    true,
  )
  assertEquals(broiler.length, 0)
})

Deno.test('generated persistence mapping reads and writes local rows bidirectionally', () => {
  const schema = requireStationSchema('chicks.weights', 1)
  const values = fieldValuesFromLocalRow(schema, {
    weightsJson: '[41.0,43.0]',
    sampleSize: 2,
  })

  assertEquals(values, { weightsJson: [41, 43] })
  assertEquals(localPersistenceValues(schema, values), {
    weightsJson: '[41,43]',
    sampleSize: 2,
    avgWeight: 42,
    uniformityPct: 100,
    cvPct: 3.4,
  })
})
