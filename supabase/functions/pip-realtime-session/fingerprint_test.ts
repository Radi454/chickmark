import { assertEquals, assertNotEquals } from '@std/assert'

import { computeAuthorizationFingerprint } from './fingerprint.ts'

const base = {
  staffLinkId: 'app-owner-1',
  accessRole: 'customer',
  allowedCustomerIds: ['cust-a', 'cust-b'],
  profileRole: 'customer',
  profileStatus: 'approved',
}

Deno.test('the fingerprint is deterministic and order independent', async () => {
  const first = await computeAuthorizationFingerprint(base)
  const second = await computeAuthorizationFingerprint({
    ...base,
    allowedCustomerIds: ['cust-b', 'cust-a'],
  })
  assertEquals(first, second)
  assertEquals(first.length, 64)
})

Deno.test('a demotion changes the fingerprint', async () => {
  const admin = await computeAuthorizationFingerprint({
    ...base,
    accessRole: 'admin',
    profileRole: 'admin',
  })
  const demoted = await computeAuthorizationFingerprint(base)
  assertNotEquals(admin, demoted)
})

Deno.test('a status change changes the fingerprint', async () => {
  const approved = await computeAuthorizationFingerprint(base)
  const revoked = await computeAuthorizationFingerprint({
    ...base,
    profileStatus: 'pending',
  })
  assertNotEquals(approved, revoked)
})

Deno.test('a changed allow-list changes the fingerprint', async () => {
  const before = await computeAuthorizationFingerprint(base)
  const after = await computeAuthorizationFingerprint({
    ...base,
    allowedCustomerIds: ['cust-a'],
  })
  assertNotEquals(before, after)
})

Deno.test('per-turn churn is deliberately excluded from the inputs', async () => {
  // conversationId / contextEpoch / stateVersion are not parameters at all, so
  // a normal conversation can never be mistaken for an authority change. This
  // test guards the SHAPE of the input type.
  const withExtras = await computeAuthorizationFingerprint({
    ...base,
    // deno-lint-ignore no-explicit-any
    ...({ conversationId: 'conv-9', contextEpoch: 7, stateVersion: 42 } as any),
  })
  assertEquals(withExtras, await computeAuthorizationFingerprint(base))
})
