import type { AgentScope, AgentToolResult } from './agent_protocol.ts'

export interface AgentStaffLinkScopeRow {
  id: string
  status: string
  accessRole: string
  customerId: string | null
}

export interface AgentScopedEntity {
  id: string
  customerId: string
}

export interface AgentScopeStore {
  findStaffLink(staffLinkId: string): Promise<AgentStaffLinkScopeRow | null>
  listCustomerIds(): Promise<readonly string[]>
  findFlock(flockId: string): Promise<AgentScopedEntity | null>
  findHatchery(hatcheryId: string): Promise<AgentScopedEntity | null>
}

interface ScopeDatabaseError {
  message: string
}

interface ScopeDatabaseResult<T> {
  data: T | null
  error: ScopeDatabaseError | null
}

interface ScopeDatabaseQuery {
  select(columns: string): ScopeDatabaseQuery
  eq(column: string, value: unknown): ScopeDatabaseQuery
  order(
    column: string,
    options: { ascending: boolean },
  ): ScopeDatabaseQuery
  maybeSingle(): Promise<ScopeDatabaseResult<Record<string, unknown>>>
}

export interface AgentScopeClient {
  from(table: string): ScopeDatabaseQuery
}

export class AgentScopeError extends Error {
  constructor(readonly code = 'scope_denied') {
    super(code)
    this.name = 'AgentScopeError'
  }
}

export function createSupabaseAgentScopeStore(
  client: AgentScopeClient,
): AgentScopeStore {
  return {
    async findStaffLink(staffLinkId) {
      const result = await client
        .from('telegram_staff_links')
        .select('id, status, access_role, customer_id')
        .eq('id', staffLinkId)
        .maybeSingle()
      throwIfDatabaseError(result)
      const row = result.data
      if (!row) return null
      return {
        id: requiredText(row.id),
        status: requiredText(row.status),
        accessRole: requiredText(row.access_role),
        customerId: optionalText(row.customer_id),
      }
    },
    async listCustomerIds() {
      const pending = client
        .from('customers')
        .select('id')
        .order('id', { ascending: true })
      const result = await (pending as unknown as Promise<
        ScopeDatabaseResult<Record<string, unknown>[]>
      >)
      throwIfDatabaseError(result)
      return (result.data ?? []).flatMap((row) => {
        const id = optionalText(row.id)
        return id ? [id] : []
      })
    },
    async findFlock(flockId) {
      return findScopedEntity(client, 'flocks', flockId)
    },
    async findHatchery(hatcheryId) {
      return findScopedEntity(client, 'hatcheries', hatcheryId)
    },
  }
}

export async function resolveAgentScope(
  store: AgentScopeStore,
  staffLinkId: string,
): Promise<AgentScope> {
  const normalizedId = nonEmpty(staffLinkId)
  if (!normalizedId) throw new AgentScopeError()

  const link = await store.findStaffLink(normalizedId)
  if (!link || link.status !== 'allowed' || link.id !== normalizedId) {
    throw new AgentScopeError()
  }

  if (link.accessRole === 'customer') {
    const customerId = nonEmpty(link.customerId)
    if (!customerId) throw new AgentScopeError()
    return {
      staffLinkId: normalizedId,
      accessRole: 'customer',
      allowedCustomerIds: Object.freeze([customerId]),
    }
  }

  if (link.accessRole === 'admin' && link.customerId === null) {
    const customerIds = [
      ...new Set(
        (await store.listCustomerIds()).map(nonEmpty).filter(isString),
      ),
    ].sort()
    return {
      staffLinkId: normalizedId,
      accessRole: 'admin',
      allowedCustomerIds: Object.freeze(customerIds),
    }
  }

  throw new AgentScopeError()
}

export function assertCustomerAllowed(
  scope: AgentScope,
  customerId: string,
): void {
  const normalizedId = nonEmpty(customerId)
  if (!normalizedId || !scope.allowedCustomerIds.includes(normalizedId)) {
    throw new AgentScopeError()
  }
}

export async function resolveAuthorizedFlock(
  store: AgentScopeStore,
  scope: AgentScope,
  flockId: string,
): Promise<AgentToolResult> {
  return resolveAuthorizedEntity(() => store.findFlock(flockId), scope)
}

export async function resolveAuthorizedHatchery(
  store: AgentScopeStore,
  scope: AgentScope,
  hatcheryId: string,
): Promise<AgentToolResult> {
  return resolveAuthorizedEntity(() => store.findHatchery(hatcheryId), scope)
}

async function resolveAuthorizedEntity(
  load: () => Promise<AgentScopedEntity | null>,
  scope: AgentScope,
): Promise<AgentToolResult> {
  const entity = await load()
  try {
    if (!entity) throw new AgentScopeError()
    assertCustomerAllowed(scope, entity.customerId)
    return {
      ok: true,
      code: 'ok',
      data: { id: entity.id, customerId: entity.customerId },
    }
  } catch (error) {
    if (error instanceof AgentScopeError) return scopeDenied()
    throw error
  }
}

export function scopeDenied(): AgentToolResult {
  return { ok: false, code: 'scope_denied', data: null }
}

async function findScopedEntity(
  client: AgentScopeClient,
  table: 'flocks' | 'hatcheries',
  id: string,
): Promise<AgentScopedEntity | null> {
  const result = await client
    .from(table)
    .select('id, customer_id')
    .eq('id', id)
    .maybeSingle()
  throwIfDatabaseError(result)
  const row = result.data
  if (!row) return null
  return {
    id: requiredText(row.id),
    customerId: requiredText(row.customer_id),
  }
}

function throwIfDatabaseError(result: {
  error: ScopeDatabaseError | null
}): void {
  if (result.error) throw new Error('Agent scope lookup failed')
}

function requiredText(value: unknown): string {
  const text = nonEmpty(value)
  if (!text) throw new Error('Agent scope row is invalid')
  return text
}

function optionalText(value: unknown): string | null {
  return nonEmpty(value)
}

function nonEmpty(value: unknown): string | null {
  const text = value?.toString().trim()
  return text ? text : null
}

function isString(value: string | null): value is string {
  return value !== null
}
