// Pins the sideband's authorization fingerprint to the provisioner's.
//
// The Docker image cannot import the edge function's module at runtime, so
// src/authorization.ts carries a copy of the derivation. THIS test is the
// guard: it imports the provisioner's real source across the repo and asserts
// identical digests. If either side changes canonicalization, this fails
// before a deploy turns every bind into `fingerprint_changed` again.

import { assertEquals } from 'jsr:@std/assert'
import { computeAuthorizationFingerprint as provisionerFingerprint } from '../../../supabase/functions/pip-realtime-session/fingerprint.ts'
import {
  computeAuthorizationFingerprint as sidebandFingerprint,
  resolveBindAuthority,
} from '../src/authorization.ts'

const CASES = [
  {
    name: 'admin with several customers, unsorted input',
    input: {
      staffLinkId: 'app-4c72e560-1cf5-4dc0-a397-2ba934c78a19',
      accessRole: 'admin',
      allowedCustomerIds: ['c-30', 'c-2', 'c-10'],
      profileRole: 'admin',
      profileStatus: 'approved',
    },
  },
  {
    name: 'single-customer scope',
    input: {
      staffLinkId: 'app-9e107d9d-372b-4b6f-b7a9-cde2d7f78d10',
      accessRole: 'customer',
      allowedCustomerIds: ['rs-nile-v'],
      profileRole: 'customer',
      profileStatus: 'approved',
    },
  },
  {
    name: 'auditor allow-list with unicode ids',
    input: {
      staffLinkId: 'app-x',
      accessRole: 'customer',
      allowedCustomerIds: ['الغريب', 'c-1'],
      profileRole: 'auditor',
      profileStatus: 'approved',
    },
  },
  {
    name: 'empty allow-list still canonicalizes identically',
    input: {
      staffLinkId: 'app-y',
      accessRole: 'admin',
      allowedCustomerIds: [] as string[],
      profileRole: 'admin',
      profileStatus: 'approved',
    },
  },
]

for (const { name, input } of CASES) {
  Deno.test(`fingerprint parity: ${name}`, async () => {
    assertEquals(
      await sidebandFingerprint(input),
      await provisionerFingerprint(input),
    )
  })
}

// ---------------------------------------------------------------------------
// resolveBindAuthority against a stubbed PostgREST
// ---------------------------------------------------------------------------

type Stub = Record<string, unknown[] | number>

function fetchStub(routes: Stub): (input: string) => Promise<Response> {
  return (input: string) => {
    const table = new URL(input).pathname.split('/').pop() ?? ''
    const route = routes[table]
    if (route === undefined) {
      return Promise.resolve(new Response('[]', { status: 200 }))
    }
    if (typeof route === 'number') {
      return Promise.resolve(new Response('err', { status: route }))
    }
    return Promise.resolve(
      new Response(JSON.stringify(route), { status: 200 }),
    )
  }
}

const BASE = {
  supabaseUrl: 'https://example.supabase.co',
  serviceRoleKey: 'srk',
  profileId: 'p-1',
}

Deno.test('admin resolves the full customer list and the admin role', async () => {
  const authority = await resolveBindAuthority({
    ...BASE,
    fetchImpl: fetchStub({
      profiles: [{ role: 'admin', status: 'approved', customer_id: null }],
      customers: [{ id: 'c-2' }, { id: 'c-1' }, { id: 'c-2' }],
    }),
  })
  assertEquals(authority.authorized, true)
  assertEquals(authority.staffLinkId, 'app-p-1')
  assertEquals(
    authority.fingerprint,
    await provisionerFingerprint({
      staffLinkId: 'app-p-1',
      accessRole: 'admin',
      allowedCustomerIds: ['c-1', 'c-2'],
      profileRole: 'admin',
      profileStatus: 'approved',
    }),
  )
})

Deno.test('customer resolves their single id', async () => {
  const authority = await resolveBindAuthority({
    ...BASE,
    fetchImpl: fetchStub({
      profiles: [{ role: 'customer', status: 'approved', customer_id: 'c-9' }],
    }),
  })
  assertEquals(authority.authorized, true)
  assertEquals(
    authority.fingerprint,
    await provisionerFingerprint({
      staffLinkId: 'app-p-1',
      accessRole: 'customer',
      allowedCustomerIds: ['c-9'],
      profileRole: 'customer',
      profileStatus: 'approved',
    }),
  )
})

Deno.test('auditor resolves the mapping table as accessRole customer', async () => {
  const authority = await resolveBindAuthority({
    ...BASE,
    fetchImpl: fetchStub({
      profiles: [{ role: 'auditor', status: 'approved', customer_id: null }],
      auditor_customers: [{ customer_id: 'c-3' }, { customer_id: 'c-3' }],
    }),
  })
  assertEquals(authority.authorized, true)
  assertEquals(
    authority.fingerprint,
    await provisionerFingerprint({
      staffLinkId: 'app-p-1',
      accessRole: 'customer',
      allowedCustomerIds: ['c-3'],
      profileRole: 'auditor',
      profileStatus: 'approved',
    }),
  )
})

Deno.test('unapproved, unknown, and empty-scope callers are denied', async () => {
  for (const routes of [
    { profiles: [{ role: 'admin', status: 'revoked', customer_id: null }] },
    { profiles: [] as unknown[] },
    { profiles: [{ role: 'auditor', status: 'approved', customer_id: null }], auditor_customers: [] as unknown[] },
    { profiles: [{ role: 'customer', status: 'approved', customer_id: null }] },
    { profiles: 500 },
  ] as Stub[]) {
    const authority = await resolveBindAuthority({
      ...BASE,
      fetchImpl: fetchStub(routes),
    })
    assertEquals(authority.authorized, false)
    assertEquals(authority.fingerprint, '')
  }
})
