import { assertEquals, assertRejects } from '@std/assert'

import {
  AgentScopeError,
  type AgentScopeStore,
  resolveAgentScope,
  resolveAuthorizedFlock,
  resolveAuthorizedHatchery,
} from './agent_scope.ts'

const store: AgentScopeStore = {
  async findStaffLink(staffLinkId) {
    return {
      'customer-link': {
        id: staffLinkId,
        status: 'allowed',
        accessRole: 'customer',
        customerId: 'customer-a',
      },
      'admin-link': {
        id: staffLinkId,
        status: 'allowed',
        accessRole: 'admin',
        customerId: null,
      },
      'broken-link': {
        id: staffLinkId,
        status: 'allowed',
        accessRole: 'customer',
        customerId: null,
      },
    }[staffLinkId] ?? null
  },
  async listCustomerIds() {
    return ['customer-b', 'customer-a', 'customer-a']
  },
  async findFlock(flockId) {
    return {
      'flock-a': { id: flockId, customerId: 'customer-a' },
      'flock-b': { id: flockId, customerId: 'customer-b' },
    }[flockId] ?? null
  },
  async findHatchery(hatcheryId) {
    return {
      'hatchery-a': { id: hatcheryId, customerId: 'customer-a' },
      'hatchery-b': { id: hatcheryId, customerId: 'customer-b' },
    }[hatcheryId] ?? null
  },
}

Deno.test('assigned Telegram user resolves to exactly one customer', async () => {
  assertEquals(await resolveAgentScope(store, 'customer-link'), {
    staffLinkId: 'customer-link',
    accessRole: 'customer',
    allowedCustomerIds: ['customer-a'],
  })
})

Deno.test('explicit agent admin resolves all customers deterministically', async () => {
  assertEquals(await resolveAgentScope(store, 'admin-link'), {
    staffLinkId: 'admin-link',
    accessRole: 'admin',
    allowedCustomerIds: ['customer-a', 'customer-b'],
  })
})

Deno.test('allowed customer link without an assignment fails closed', async () => {
  const error = await assertRejects(
    () => resolveAgentScope(store, 'broken-link'),
    AgentScopeError,
  )
  assertEquals(error.code, 'scope_denied')
})

Deno.test('unknown and out-of-scope flock IDs are indistinguishable', async () => {
  const scope = await resolveAgentScope(store, 'customer-link')
  assertEquals(
    await resolveAuthorizedFlock(store, scope, 'flock-b'),
    { ok: false, code: 'scope_denied', data: null },
  )
  assertEquals(
    await resolveAuthorizedFlock(store, scope, 'missing-flock'),
    { ok: false, code: 'scope_denied', data: null },
  )
})

Deno.test('unknown and out-of-scope hatchery IDs are indistinguishable', async () => {
  const scope = await resolveAgentScope(store, 'customer-link')
  assertEquals(
    await resolveAuthorizedHatchery(store, scope, 'hatchery-b'),
    { ok: false, code: 'scope_denied', data: null },
  )
  assertEquals(
    await resolveAuthorizedHatchery(store, scope, 'missing-hatchery'),
    { ok: false, code: 'scope_denied', data: null },
  )
})
