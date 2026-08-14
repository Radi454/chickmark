import { assertEquals } from '@std/assert'

import {
  coverageFor,
  normalizeBreedKey,
  resolveBreed,
} from './bmk_lookup.ts'

const vocabulary = ['Ross308', 'Arbo', 'Avian', 'Cobb500', 'Hubbard', 'IR']

Deno.test('normalizeBreedKey strips case, spaces, hyphens and dots', () => {
  assertEquals(normalizeBreedKey('Ross 308'), 'ross308')
  assertEquals(normalizeBreedKey('ROSS-308'), 'ross308')
  assertEquals(normalizeBreedKey('  cobb.500 '), 'cobb500')
})

Deno.test('resolveBreed matches exactly after normalization', () => {
  assertEquals(resolveBreed('Ross308', vocabulary), 'Ross308')
  assertEquals(resolveBreed('ross 308', vocabulary), 'Ross308')
  assertEquals(resolveBreed('ir', vocabulary), 'IR')
})

Deno.test('resolveBreed accepts a unique prefix', () => {
  assertEquals(resolveBreed('ross', vocabulary), 'Ross308')
  assertEquals(resolveBreed('cobb', vocabulary), 'Cobb500')
})

Deno.test('resolveBreed refuses an ambiguous prefix', () => {
  assertEquals(resolveBreed('a', vocabulary), null)
})

Deno.test('resolveBreed refuses an unknown breed', () => {
  assertEquals(resolveBreed('leghorn', vocabulary), null)
  assertEquals(resolveBreed('', vocabulary), null)
})

Deno.test('coverageFor reports the per-breed week range', () => {
  const rows = [
    { breed: 'Ross308', ageWeek: 25 },
    { breed: 'Ross308', ageWeek: 65 },
    { breed: 'Cobb500', ageWeek: 24 },
    { breed: 'Cobb500', ageWeek: 65 },
  ]
  assertEquals(coverageFor('Ross308', rows), {
    breed: 'Ross308',
    minWeek: 25,
    maxWeek: 65,
  })
  assertEquals(coverageFor('Cobb500', rows), {
    breed: 'Cobb500',
    minWeek: 24,
    maxWeek: 65,
  })
  assertEquals(coverageFor('Hubbard', rows), null)
})
