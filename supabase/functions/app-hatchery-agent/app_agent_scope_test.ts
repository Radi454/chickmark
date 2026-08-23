import { assertEquals, assertRejects } from '@std/assert'

import {
  AppAgentScopeError,
  type AppScopeClient,
  appStaffLinkId,
  ensureAppStaffLink,
  loadAppProfile,
  resolveAppAgentScope,
} from './app_agent_scope.ts'
import { createFakeAdminClient, createFakeDatabase } from './test_support.ts'

function client(db: ReturnType<typeof createFakeDatabase>): AppScopeClient {
  return createFakeAdminClient(db) as unknown as AppScopeClient
}

Deno.test('an app staff link is created once and refreshed on every call', async () => {
  const db = createFakeDatabase({
    profiles: [],
    telegram_staff_links: [],
  })
  const scopeClient = client(db)

  const first = await ensureAppStaffLink(scopeClient, {
    id: 'user-1',
    role: 'customer',
    status: 'approved',
    customerId: 'cust-1',
    fullName: 'Customer One',
    email: 'customer@example.test',
  }, '2026-08-14T10:00:00.000Z')

  assertEquals(first, appStaffLinkId('user-1'))
  assertEquals(db.tables.telegram_staff_links.length, 1)
  const created = db.tables.telegram_staff_links[0]
  assertEquals(created.channel, 'app')
  assertEquals(created.app_user_id, 'user-1')
  assertEquals(created.telegram_user_id, null)
  assertEquals(created.status, 'allowed')
  assertEquals(created.access_role, 'customer')
  assertEquals(created.customer_id, 'cust-1')

  // A role change in profiles must take effect on the very next request.
  const second = await ensureAppStaffLink(scopeClient, {
    id: 'user-1',
    role: 'admin',
    status: 'approved',
    customerId: null,
    fullName: 'Customer One',
    email: 'customer@example.test',
  }, '2026-08-14T11:00:00.000Z')

  assertEquals(second, first)
  assertEquals(db.tables.telegram_staff_links.length, 1)
  assertEquals(db.tables.telegram_staff_links[0].access_role, 'admin')
  assertEquals(db.tables.telegram_staff_links[0].customer_id, null)
  assertEquals(
    db.tables.telegram_staff_links[0].updated_at,
    '2026-08-14T11:00:00.000Z',
  )
})

Deno.test('an app auditor staff link stores no customer, the scope carries it', async () => {
  const db = createFakeDatabase({
    profiles: [{
      id: 'user-auditor',
      role: 'auditor',
      status: 'approved',
      customer_id: null,
      full_name: 'Auditor',
      email: 'auditor@example.test',
    }],
    auditor_customers: [
      { auditor_id: 'user-auditor', customer_id: 'cust-2' },
      { auditor_id: 'user-auditor', customer_id: 'cust-1' },
      { auditor_id: 'other', customer_id: 'cust-9' },
    ],
    customers: [{ id: 'cust-1' }, { id: 'cust-2' }, { id: 'cust-9' }],
    telegram_staff_links: [],
  })
  const scopeClient = client(db)

  const profile = await loadAppProfile(scopeClient, 'user-auditor')
  const scope = await resolveAppAgentScope(scopeClient, 'user-auditor', profile)
  await ensureAppStaffLink(scopeClient, profile, '2026-08-14T10:00:00.000Z')

  assertEquals(scope.accessRole, 'customer')
  assertEquals([...scope.allowedCustomerIds], ['cust-1', 'cust-2'])
  assertEquals(scope.staffLinkId, appStaffLinkId('user-auditor'))
  assertEquals(db.tables.telegram_staff_links[0].customer_id, null)
  assertEquals(db.tables.telegram_staff_links[0].access_role, 'customer')
})

Deno.test('resolveAppAgentScope rejects unapproved and unmapped callers', async () => {
  const db = createFakeDatabase({
    profiles: [
      {
        id: 'user-pending',
        role: 'auditor',
        status: 'pending',
        customer_id: null,
      },
      {
        id: 'user-orphan',
        role: 'customer',
        status: 'approved',
        customer_id: null,
      },
      {
        id: 'user-unmapped',
        role: 'auditor',
        status: 'approved',
        customer_id: null,
      },
    ],
    auditor_customers: [],
    customers: [],
  })
  const scopeClient = client(db)

  for (
    const userId of ['user-pending', 'user-orphan', 'user-unmapped', 'nope']
  ) {
    await assertRejects(
      () => resolveAppAgentScope(scopeClient, userId),
      AppAgentScopeError,
    )
  }
})
