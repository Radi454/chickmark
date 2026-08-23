// Bind-time authority resolution.
//
// The sideband re-asks the database who the caller is on every bind and
// re-derives the authorization fingerprint the session was provisioned with.
// The derivation MUST stay byte-identical to the provisioner's
// (supabase/functions/pip-realtime-session/fingerprint.ts +
// app-hatchery-agent/app_agent_scope.ts): same inputs, same canonical JSON,
// same digest. A previous version of this check used a legacy
// `role:customerId` string here while the provisioner stamped a SHA-256, so
// EVERY bind failed as `fingerprint_changed` → unauthorized. Parity is now
// pinned by test/authorization_parity_test.ts, which imports the provisioner's
// module and asserts identical digests.
//
// The Docker image only ships main.ts + src/ (see Dockerfile), so this file
// cannot import the edge function's module at runtime — the copy is
// deliberate, the parity test is what keeps it honest.

import { sha256Hex } from './ids.ts'
import { log } from './log.ts'

export interface ResolvedBindAuthority {
  readonly authorized: boolean
  /** `app-<profileId>` — the provisioner's deterministic staff-link id. */
  readonly staffLinkId: string
  /** Empty string when not authorized. */
  readonly fingerprint: string
}

/**
 * Same shape and canonicalization as the provisioner's
 * computeAuthorizationFingerprint. Key order in the JSON literal is part of
 * the contract.
 */
export async function computeAuthorizationFingerprint(input: {
  readonly staffLinkId: string
  readonly accessRole: string
  readonly allowedCustomerIds: readonly string[]
  readonly profileRole: string
  readonly profileStatus: string
}): Promise<string> {
  const canonical = JSON.stringify({
    v: 1,
    staffLinkId: input.staffLinkId,
    accessRole: input.accessRole,
    allowedCustomerIds: [...input.allowedCustomerIds].sort(),
    profileRole: input.profileRole,
    profileStatus: input.profileStatus,
  })
  return await sha256Hex(canonical)
}

type FetchLike = (
  input: string,
  init?: RequestInit,
) => Promise<Response>

/**
 * Mirrors loadAppProfile + resolveAppAgentScope from the app agent door:
 * profiles is the authorization record (approved status, role), customers /
 * auditor_customers give the allow-list, and the staff-link id is derived —
 * never queried — because the provisioner writes it deterministically.
 */
export async function resolveBindAuthority(opts: {
  readonly supabaseUrl: string
  readonly serviceRoleKey: string
  readonly profileId: string
  readonly fetchImpl?: FetchLike
}): Promise<ResolvedBindAuthority> {
  const doFetch: FetchLike = opts.fetchImpl ?? fetch
  const staffLinkId = `app-${opts.profileId}`
  const denied: ResolvedBindAuthority = {
    authorized: false,
    staffLinkId,
    fingerprint: '',
  }

  const profileRows = await selectRows(doFetch, opts, {
    path: `profiles?id=eq.${encodeURIComponent(opts.profileId)}` +
      '&select=role,status,customer_id&limit=1',
  })
  if (profileRows === null) return denied
  const profile = profileRows[0]
  if (!profile) return denied

  const role = nonEmpty(profile.role)
  const status = nonEmpty(profile.status)
  if (status !== 'approved') return denied
  if (role !== 'admin' && role !== 'auditor' && role !== 'customer') {
    return denied
  }

  let accessRole: string
  let allowedCustomerIds: string[]
  if (role === 'admin') {
    const rows = await selectRows(doFetch, opts, {
      path: 'customers?select=id&order=id.asc',
    })
    if (rows === null) return denied
    accessRole = 'admin'
    allowedCustomerIds = uniqueSorted(rows.map((row) => nonEmpty(row.id)))
  } else if (role === 'customer') {
    const customerId = nonEmpty(profile.customer_id)
    if (!customerId) return denied
    accessRole = 'customer'
    allowedCustomerIds = [customerId]
  } else {
    const rows = await selectRows(doFetch, opts, {
      path: 'auditor_customers' +
        `?auditor_id=eq.${encodeURIComponent(opts.profileId)}` +
        '&select=customer_id&order=customer_id.asc',
    })
    if (rows === null) return denied
    accessRole = 'customer'
    allowedCustomerIds = uniqueSorted(
      rows.map((row) => nonEmpty(row.customer_id)),
    )
    if (allowedCustomerIds.length === 0) return denied
  }

  const fingerprint = await computeAuthorizationFingerprint({
    staffLinkId,
    accessRole,
    allowedCustomerIds,
    profileRole: role,
    profileStatus: status,
  })
  return { authorized: true, staffLinkId, fingerprint }
}

async function selectRows(
  doFetch: FetchLike,
  opts: { readonly supabaseUrl: string; readonly serviceRoleKey: string },
  query: { readonly path: string },
): Promise<Record<string, unknown>[] | null> {
  let response: Response
  try {
    response = await doFetch(`${opts.supabaseUrl}/rest/v1/${query.path}`, {
      headers: {
        apikey: opts.serviceRoleKey,
        authorization: `Bearer ${opts.serviceRoleKey}`,
      },
    })
  } catch {
    log.warn('authority.query_failed', { path: query.path.split('?')[0] })
    return null
  }
  if (!response.ok) {
    log.warn('authority.query_failed', {
      path: query.path.split('?')[0],
      status: response.status,
    })
    return null
  }
  const body = await response.json()
  return Array.isArray(body) ? body as Record<string, unknown>[] : null
}

function uniqueSorted(values: readonly (string | null)[]): string[] {
  return [...new Set(values.filter((value): value is string => value !== null))]
    .sort()
}

function nonEmpty(value: unknown): string | null {
  const text = value?.toString().trim()
  return text ? text : null
}
