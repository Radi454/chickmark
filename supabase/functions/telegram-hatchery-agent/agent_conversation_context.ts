import type {
  AgentToolCall,
  AgentToolName,
  AgentToolResult,
} from './agent_protocol.ts'
import type { AgentConversationContextPort } from './agent_tools.ts'

export interface AgentConversationContext {
  conversationId: string
  stateVersion: number
  contextEpoch: number
  customerId: string | null
  flockId: string | null
  auditId: string | null
}

interface ContextDatabaseResult<T> {
  data: T | null
  error: { message: string } | null
}

interface ContextDatabaseQuery {
  select(columns: string): ContextDatabaseQuery
  eq(column: string, value: unknown): ContextDatabaseQuery
  maybeSingle(): Promise<ContextDatabaseResult<Record<string, unknown>>>
  update(values: Record<string, unknown>): ContextDatabaseQuery
  then<TResult1 = unknown, TResult2 = never>(
    onFulfilled?:
      | ((
        value: ContextDatabaseResult<unknown>,
      ) => TResult1 | PromiseLike<TResult1>)
      | null,
    onRejected?:
      | ((reason: unknown) => TResult2 | PromiseLike<TResult2>)
      | null,
  ): Promise<TResult1 | TResult2>
}

export interface AgentConversationContextClient {
  from(table: string): ContextDatabaseQuery
}

export interface AgentConversationContextStore
  extends AgentConversationContextPort {
  load(conversationId: string): Promise<AgentConversationContext | null>
}

export function createSupabaseAgentConversationContextStore(
  client: AgentConversationContextClient,
  now: () => Date = () => new Date(),
): AgentConversationContextStore {
  return {
    async load(conversationId) {
      const result = await client
        .from('agent_conversations')
        .select(
          'id, state_version, context_epoch, selected_customer_id, ' +
            'selected_flock_id, selected_audit_id',
        )
        .eq('id', conversationId)
        .maybeSingle()
      if (result.error || !result.data) return null
      const id = text(result.data.id)
      const stateVersion = positiveInteger(result.data.state_version)
      const contextEpoch = positiveInteger(result.data.context_epoch)
      if (!id || stateVersion === null || contextEpoch === null) return null
      return {
        conversationId: id,
        stateVersion,
        contextEpoch,
        customerId: text(result.data.selected_customer_id),
        flockId: text(result.data.selected_flock_id),
        auditId: text(result.data.selected_audit_id),
      }
    },
    async recordSuccessfulTool(
      call,
      result,
      conversationId,
      expectedContextEpoch,
    ) {
      if (!result.ok || result.code !== 'ok' || !record(result.data)) return
      if (positiveInteger(expectedContextEpoch) === null) {
        throw new Error('Could not update agent conversation context')
      }
      const current = await this.load(conversationId)
      if (!current) return
      if (current.contextEpoch !== expectedContextEpoch) {
        throw new Error('Could not update agent conversation context')
      }
      const transition = contextTransition(call.name as AgentToolName, result)
      if (!transition) return

      const customerChanged = transition.customerId !== current.customerId
      const flockChanged = transition.flockId !== current.flockId
      const nextAuditId = transition.kind === 'audit'
        ? transition.auditId
        : customerChanged || flockChanged
        ? null
        : current.auditId
      if (
        !customerChanged &&
        !flockChanged &&
        nextAuditId === current.auditId
      ) return

      const timestamp = now().toISOString()
      const update = await client
        .from('agent_conversations')
        .update({
          state_version: current.stateVersion + 1,
          selected_customer_id: transition.customerId,
          selected_flock_id: transition.flockId,
          selected_audit_id: nextAuditId,
          context_updated_at: timestamp,
          updated_at: timestamp,
        })
        .eq('id', conversationId)
        .eq('state_version', current.stateVersion)
        .eq('context_epoch', expectedContextEpoch)
        .select('id')
        .maybeSingle()
      if (update.error || !update.data) {
        throw new Error('Could not update agent conversation context')
      }
    },
  }
}

type ContextTransition =
  | {
    kind: 'operational'
    customerId: string
    flockId: string | null
  }
  | {
    kind: 'audit'
    customerId: string
    flockId: string | null
    auditId: string
  }

function contextTransition(
  toolName: AgentToolName,
  result: AgentToolResult,
): ContextTransition | null {
  const data = result.data
  if (!record(data)) return null
  if (toolName === 'resolve_customer_flock') {
    if (data.status !== 'resolved' || !record(data.customer)) return null
    const customerId = text(data.customer.id)
    const flockId = record(data.flock) ? text(data.flock.id) : null
    return customerId ? { kind: 'operational', customerId, flockId } : null
  }
  if (toolName === 'get_customer_context') {
    const customerId = text(data.id)
    return customerId
      ? { kind: 'operational', customerId, flockId: null }
      : null
  }
  if (toolName === 'get_flock_context') {
    const customerId = text(data.customerId)
    const flockId = text(data.id)
    return customerId && flockId
      ? { kind: 'operational', customerId, flockId }
      : null
  }
  if (
    toolName === 'list_customer_audits' ||
    toolName === 'list_applicable_stations'
  ) {
    const customerId = text(data.customerId)
    const flockId = text(data.flockId)
    return customerId ? { kind: 'operational', customerId, flockId } : null
  }
  if (toolName === 'select_audit_option') {
    const customerId = text(data.customerId)
    const flockId = text(data.flockId)
    const auditId = text(data.id)
    return customerId && auditId
      ? { kind: 'audit', customerId, flockId, auditId }
      : null
  }
  return null
}

function text(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const normalized = value.trim()
  return normalized && normalized.length <= 160 ? normalized : null
}

function positiveInteger(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) && value >= 1
    ? value
    : null
}

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
