import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert'

import {
  applyAllRemainingZero,
  calculatePasgarSummary,
  formatPasgarSummary,
  getPasgarFieldDefinition,
  missingPasgarFields,
  type PasgarWorkingValues,
  validatePasgarCandidate,
} from './pasgar_intake_schema.ts'
import { requireStationSchema } from '../_shared/station_registry.generated.ts'

function completePasgarValues(): PasgarWorkingValues {
  return {
    pasgarSampleSize: 40,
    pasgarReflexesCount: 2,
    pasgarBeakCount: 1,
    pasgarNavelCount: 0,
    pasgarBellyCount: 1,
    pasgarLegCount: 2,
    pasgarFeatherDevCount: 3,
  }
}

Deno.test('Pasgar completeness requires all six explicit defect counts', () => {
  const values = completePasgarValues()
  delete values.pasgarFeatherDevCount

  assertEquals(missingPasgarFields(values), ['pasgarFeatherDevCount'])
})

Deno.test('legacy Pasgar compatibility order matches the canonical registry', () => {
  const schema = requireStationSchema('chicks.pasgar', 1)
  assertEquals(
    schema.fields.map((field) => field.fieldKey),
    [
      'pasgarSampleSize',
      'pasgarReflexesCount',
      'pasgarBeakCount',
      'pasgarNavelCount',
      'pasgarBellyCount',
      'pasgarLegCount',
      'pasgarFeatherDevCount',
    ],
  )
})

Deno.test('all remaining zero fills missing defects without replacing supplied values', () => {
  assertEquals(
    applyAllRemainingZero({
      pasgarSampleSize: 40,
      pasgarReflexesCount: 2,
    }),
    {
      pasgarSampleSize: 40,
      pasgarReflexesCount: 2,
      pasgarBeakCount: 0,
      pasgarNavelCount: 0,
      pasgarBellyCount: 0,
      pasgarLegCount: 0,
      pasgarFeatherDevCount: 0,
    },
  )
})

Deno.test('sample size accepts 1 through 500 only', () => {
  assertEquals(validatePasgarCandidate('pasgarSampleSize', 1, {}).ok, true)
  assertEquals(validatePasgarCandidate('pasgarSampleSize', 500, {}).ok, true)
  assertEquals(validatePasgarCandidate('pasgarSampleSize', 0, {}).ok, false)
  assertEquals(validatePasgarCandidate('pasgarSampleSize', 501, {}).ok, false)
  assertEquals(validatePasgarCandidate('pasgarSampleSize', 4.5, {}).ok, false)
})

Deno.test('defect count cannot exceed the current sample size', () => {
  assertEquals(
    validatePasgarCandidate('pasgarNavelCount', 40, {
      pasgarSampleSize: 40,
    }).ok,
    true,
  )
  const invalid = validatePasgarCandidate('pasgarNavelCount', 41, {
    pasgarSampleSize: 40,
  })
  assertEquals(invalid.ok, false)
  if (!invalid.ok) {
    assertStringIncludes(invalid.messageEn, '40')
    assertStringIncludes(invalid.messageAr, '40')
  }
})

Deno.test('Pasgar score excludes feather development and matches Flutter parity', () => {
  const summary = calculatePasgarSummary({
    ...completePasgarValues(),
    pasgarFeatherDevCount: 40,
  })

  assertEquals(summary.score, 9.8)
  assertEquals(summary.percentages.pasgarReflexesCount, 5)
  assertEquals(summary.percentages.pasgarFeatherDevCount, 100)
})

Deno.test('Pasgar beak metadata recognizes the common peak spelling only as an alias', () => {
  const field = getPasgarFieldDefinition('pasgarBeakCount')

  assert(field.aliasesEn.includes('beak'))
  assert(field.aliasesEn.includes('peak'))
  assertEquals(field.labelAr, 'المنقار')
})

Deno.test('final summaries are complete and localized', () => {
  const summary = calculatePasgarSummary(completePasgarValues())
  const english = formatPasgarSummary(summary, 'en')
  const arabic = formatPasgarSummary(summary, 'ar')

  assertStringIncludes(english, 'Sample: 40 chicks')
  assertStringIncludes(english, 'Feather development: 3 (7.5%)')
  assertStringIncludes(english, 'Pasgar score: 9.8')
  assertStringIncludes(arabic, 'العينة: 40 كتكوت')
  assertStringIncludes(arabic, 'نمو الريش: 3 (7.5٪)')
  assertStringIncludes(arabic, 'درجة باسجار: 9.8')
})
