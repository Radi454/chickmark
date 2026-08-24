import {
  assertEquals,
  assertNotEquals,
  assertThrows,
} from 'jsr:@std/assert@1.0.14'

import { buildSampleKey, buildScopeKey } from './chick_sample_identity.ts'

Deno.test('TypeScript Chick identity matches the Dart canonical vector', () => {
  const scopeKey = buildScopeKey('house', { house: 'House A' })
  assertEquals(scopeKey, '{"house":"House A"}')
  assertEquals(
    buildSampleKey('chicks.weights', 'session-1', 'house', scopeKey, 1),
    'WyJjaGlja3Mud2VpZ2h0cyIsInNlc3Npb24tMSIsImhvdXNlIiwie1wiaG91c2VcIjpcIkhvdXNlIEFcIn0iLDFd',
  )
})

Deno.test('identity rejects blank non-pool scope and delimiter collisions', () => {
  assertThrows(() => buildScopeKey('house', {}), Error)
  const first = buildSampleKey(
    'chicks.weights',
    'session|house',
    'house',
    '{"house":"A"}',
    1,
  )
  const second = buildSampleKey(
    'chicks.weights|session',
    'house',
    'house',
    '{"house":"A"}',
    1,
  )
  assertNotEquals(first, second)
})
