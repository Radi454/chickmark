// Scope resolution for the in-app agent door.
//
// The Telegram door resolves an AgentScope from a telegram_staff_links row.
// The app door resolves it from the signed-in Supabase user instead:
// public.profiles gives the role, and auditor_customers gives an auditor's
// allow-list. The staff-link row is only an identity anchor so the shared
// agent_conversations FK still resolves - it is never the authorization
// record. Authorization is recomputed on every request.

import type { AgentScope } from '../telegram-hatchery-agent/agent_protocol.ts'

export type AppProfileRole = 'admin' | 'auditor' | 'customer'

export interface AppAgentProfile {
  id: string
  role: AppProfileRole
  status: string
  customerId: string | null
  fullName: string | null
  email: string | null
}

export class AppAgentScopeError extends Error {
  constructor(readonly code: string = 'not_approved') {
    super(code)
    this.name = 'AppAgentScopeError'
  }
}

interface AppScopeDatabaseError {
  message: string
}

interface AppScopeResult<T = unknown> {
  data: T | null
  error: AppScopeDatabaseError | null
}

interface AppScopeUpdateFilter {
  eq(column: string, value: unknown): Promise<AppScopeResult>
}

interface AppScopeQuery {
  select(columns: string): AppScopeQuery
  eq(column: string, value: unknown): AppScopeQuery
  order(column: string, options: { ascending: boolean }): AppScopeQuery
  maybeSingle(): Promise<AppScopeResult<Record<string, unknown>>>
  insert(values: unknown): Promise<AppScopeResult>
  update(values: unknown): AppScopeUpdateFilter
}

export interface AppScopeClient {
  from(table: string): AppScopeQuery
}

/** Deterministic staff-link id for an app user, so no lookup table is needed. */
export function appStaffLinkId(authUserId: string): string {
  return `app-${authUserId}`
}

export async function loadAppProfile(
  adminClient: AppScopeClient,
  authUserId: string,
): Promise<AppAgentProfile> {
  const userId = nonEmpty(authUserId)
  if (!userId) throw new AppAgentScopeError()

  const result = await adminClient
    .from('profiles')
    .select('id, full_name, email, role, status, customer_id')
    .eq('id', userId)
    .maybeSingle()
  if (result.error) throw new Error('Could not load app agent profile')
  const row = result.data
  if (!row) throw new AppAgentScopeError()

  const status = nonEmpty(row.status)
  if (status !== 'approved') throw new AppAgentScopeError()

  const role = nonEmpty(row.role)
  if (role !== 'admin' && role !== 'auditor' && role !== 'customer') {
    throw new AppAgentScopeError()
  }

  return {
    id: userId,
    role,
    status,
    customerId: nonEmpty(row.customer_id),
    fullName: nonEmpty(row.full_name),
    email: nonEmpty(row.email),
  }
}

export async function resolveAppAgentScope(
  adminClient: AppScopeClient,
  authUserId: string,
  loadedProfile?: AppAgentProfile,
): Promise<AgentScope> {
  const profile = loadedProfile ??
    await loadAppProfile(adminClient, authUserId)
  if (profile.id !== nonEmpty(authUserId)) throw new AppAgentScopeError()
  const staffLinkId = appStaffLinkId(profile.id)

  if (profile.role === 'admin') {
    const customerIds = await listAllCustomerIds(adminClient)
    return {
      staffLinkId,
      accessRole: 'admin',
      allowedCustomerIds: Object.freeze(customerIds),
    }
  }

  if (profile.role === 'customer') {
    if (!profile.customerId) throw new AppAgentScopeError()
    return {
      staffLinkId,
      accessRole: 'customer',
      allowedCustomerIds: Object.freeze([profile.customerId]),
    }
  }

  // auditor: allow-list comes from the many-to-many mapping table.
  const auditorCustomerIds = await listAuditorCustomerIds(
    adminClient,
    profile.id,
  )
  if (auditorCustomerIds.length === 0) throw new AppAgentScopeError()
  return {
    staffLinkId,
    accessRole: 'customer',
    allowedCustomerIds: Object.freeze(auditorCustomerIds),
  }
}

/**
 * Create or refresh the channel='app' staff-link row for this profile and
 * return its id. Role and customer assignment are rewritten on every call so a
 * demotion in `profiles` takes effect on the very next request.
 */
export async function ensureAppStaffLink(
  adminClient: AppScopeClient,
  profile: AppAgentProfile,
  now: string = new Date().toISOString(),
): Promise<string> {
  const staffLinkId = appStaffLinkId(profile.id)
  const accessRole = profile.role === 'admin' ? 'admin' : 'customer'
  // Only a Telegram row stores its allowed customer here; an app row keeps its
  // real allow-list out of the table (see the migration header).
  const customerId = profile.role === 'customer' ? profile.customerId : null
  const displayName = profile.fullName ?? profile.email ?? 'App user'

  const mutable = {
    channel: 'app',
    app_user_id: profile.id,
    telegram_user_id: null,
    telegram_chat_id: APP_CHANNEL_CHAT_ID,
    status: 'allowed',
    access_role: accessRole,
    customer_id: customerId,
    display_name: displayName,
    updated_at: now,
  }

  const existing = await adminClient
    .from('telegram_staff_links')
    .select('id')
    .eq('id', staffLinkId)
    .maybeSingle()
  if (existing.error) throw new Error('Could not load app staff link')

  if (existing.data) {
    const updated = await adminClient
      .from('telegram_staff_links')
      .update(mutable)
      .eq('id', staffLinkId)
    if (updated.error) throw new Error('Could not refresh app staff link')
    return staffLinkId
  }

  const inserted = await adminClient
    .from('telegram_staff_links')
    .insert({
      id: staffLinkId,
      username: null,
      invited_by: null,
      created_at: now,
      ...mutable,
    })
  if (inserted.error) {
    // Lost a race with a concurrent request; refresh the winner instead.
    const updated = await adminClient
      .from('telegram_staff_links')
      .update(mutable)
      .eq('id', staffLinkId)
    if (updated.error) throw new Error('Could not create app staff link')
  }
  return staffLinkId
}

/**
 * The app channel has no Telegram chat, but `agent_conversations` requires a
 * NOT NULL `telegram_chat_id`. This literal is the app channel's chat id, and
 * combined with the app staff-link id it yields exactly one conversation per
 * app user under the existing unique(staff_link_id, telegram_chat_id).
 */
export const APP_CHANNEL_CHAT_ID = 'app'

async function listAllCustomerIds(
  adminClient: AppScopeClient,
): Promise<string[]> {
  const pending = adminClient
    .from('customers')
    .select('id')
    .order('id', { ascending: true })
  const result = await (pending as unknown as Promise<
    AppScopeResult<Record<string, unknown>[]>
  >)
  if (result.error) throw new Error('Could not list customers')
  return uniqueSorted(
    (result.data ?? []).map((row) => nonEmpty(row.id)),
  )
}

async function listAuditorCustomerIds(
  adminClient: AppScopeClient,
  auditorId: string,
): Promise<string[]> {
  const pending = adminClient
    .from('auditor_customers')
    .select('customer_id')
    .eq('auditor_id', auditorId)
    .order('customer_id', { ascending: true })
  const result = await (pending as unknown as Promise<
    AppScopeResult<Record<string, unknown>[]>
  >)
  if (result.error) throw new Error('Could not list auditor customers')
  return uniqueSorted(
    (result.data ?? []).map((row) => nonEmpty(row.customer_id)),
  )
}

function uniqueSorted(values: readonly (string | null)[]): string[] {
  return [...new Set(values.filter(isString))].sort()
}

function isString(value: string | null): value is string {
  return value !== null
}

function nonEmpty(value: unknown): string | null {
  const text = value?.toString().trim()
  return text ? text : null
}
