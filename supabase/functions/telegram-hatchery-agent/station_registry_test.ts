import { assertEquals } from '@std/assert'

import {
  applicableStationSchemas,
  requireStationSchema,
} from '../_shared/station_registry.generated.ts'

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
