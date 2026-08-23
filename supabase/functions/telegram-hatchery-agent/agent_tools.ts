import {
  type AgentToolCall,
  type AgentToolExecutionInput,
  type AgentToolName,
  type AgentToolResult,
} from './agent_protocol.ts'
import { AgentScopeError, assertCustomerAllowed } from './agent_scope.ts'
import { requireStationSchema } from '../_shared/station_registry.generated.ts'
import {
  AGENT_TOOL_CONTRACT,
  type ArgumentRule,
  MAX_AGENT_READ_ROWS,
  modelFacingContract,
  type ObjectArguments,
} from './agent_tool_contract.ts'

export const MAX_AGENT_TOOL_CALLS_PER_TURN = 5
export { MAX_AGENT_READ_ROWS }
export const MAX_AGENT_READ_RANGE_DAYS = 366

export interface AgentToolDefinition {
  type: 'function'
  name: AgentToolName
  description: string
  parameters: ObjectArguments
}

export interface AgentToolEvidence {
  callId: string
  toolName: string
  arguments: Record<string, unknown>
  scope: {
    accessRole: AgentToolExecutionInput['scope']['accessRole']
    customerId: string | null
    allowedCustomerCount: number
  }
  result: AgentToolResult
  status: 'succeeded' | 'rejected' | 'failed'
  durationMs: number
  stateVersionBefore: number | null
  stateVersionAfter: number | null
  toolSequence?: number
}

export interface AgentToolEvidencePort {
  record(event: AgentToolEvidence): void | Promise<void>
}

export interface AgentConversationContextPort {
  recordSuccessfulTool(
    call: AgentToolCall,
    result: AgentToolResult,
    conversationId: string,
    expectedContextEpoch: number,
  ): void | Promise<void>
}

export type AgentToolHandler = (
  input: AgentToolExecutionInput,
) => Promise<AgentToolResult>

export interface AgentToolContext {
  scope: AgentToolExecutionInput['scope']
  conversationId: string
  activeVisitId: string | null
  conversationTurnId?: string
  conversationTurnIndex?: number
  conversationContextEpoch?: number
  evidence: AgentToolEvidencePort
  conversationContext?: AgentConversationContextPort
  handlers: Partial<Record<AgentToolName, AgentToolHandler>>
  now?: () => number
}

// Full-fidelity definitions. This is the VALIDATION surface: `executeAgentTool`
// enforces every `minLength`/`maxLength`/`enum` in here via `validArguments`,
// regardless of what was ever shown to a model. Keep this derived straight
// from `AGENT_TOOL_CONTRACT` with nothing stripped — weakening it weakens
// server-side enforcement.
export const AGENT_TOOL_DEFINITIONS: readonly AgentToolDefinition[] = Object
  .freeze(
    AGENT_TOOL_CONTRACT.map((tool) => ({
      type: 'function' as const,
      name: tool.name,
      description: tool.description,
      parameters: tool.parameters,
    })),
  )

// Model-facing definitions: the same tools, with `modelFacingParameters`
// stripping the parts of the schema (length bounds, most `schemaKey` enums)
// that cost prompt tokens on every inference but add no validation strength
// the server doesn't already enforce. This is what `agent_runtime.ts` sends
// to the text model's `tools:` field — NEVER what `executeAgentTool` validates
// against.
export const AGENT_MODEL_TOOL_DEFINITIONS: readonly AgentToolDefinition[] =
  Object.freeze(
    modelFacingContract().map((tool) => ({
      type: 'function' as const,
      name: tool.name,
      description: tool.description,
      parameters: tool.parameters,
    })),
  )

const definitionsByName = new Map(
  AGENT_TOOL_DEFINITIONS.map((item) => [item.name, item]),
)

export async function executeAgentTool(
  call: AgentToolCall,
  context: AgentToolContext,
): Promise<AgentToolResult> {
  const startedAt = (context.now ?? Date.now)()
  const definition = definitionsByName.get(call.name as AgentToolName)
  if (!definition) {
    return finish(
      call,
      context,
      startedAt,
      { ok: false, code: 'unknown_tool', data: null },
      'rejected',
    )
  }

  if (unsupportedStationReference(call.arguments)) {
    return finish(
      call,
      context,
      startedAt,
      unsupportedStationSchema(),
      'rejected',
    )
  }

  if (!validArguments(call.arguments, definition.parameters)) {
    return finish(
      call,
      context,
      startedAt,
      { ok: false, code: 'invalid_arguments', data: null },
      'rejected',
    )
  }

  try {
    enforceArgumentScope(context, call.arguments)
  } catch (error) {
    if (error instanceof AgentScopeError) {
      return finish(
        call,
        context,
        startedAt,
        { ok: false, code: 'scope_denied', data: null },
        'rejected',
      )
    }
    throw error
  }

  let result: AgentToolResult
  try {
    if (definition.name === 'get_user_scope') {
      result = {
        ok: true,
        code: 'ok',
        data: {
          accessRole: context.scope.accessRole,
          allowedCustomerCount: context.scope.allowedCustomerIds.length,
        },
      }
    } else {
      const handler = context.handlers[definition.name]
      result = handler
        ? await handler({
          scope: context.scope,
          conversationId: context.conversationId,
          activeVisitId: context.activeVisitId,
          ...(context.conversationTurnId === undefined
            ? {}
            : { conversationTurnId: context.conversationTurnId }),
          ...(context.conversationTurnIndex === undefined
            ? {}
            : { conversationTurnIndex: context.conversationTurnIndex }),
          ...(context.conversationContextEpoch === undefined
            ? {}
            : { conversationContextEpoch: context.conversationContextEpoch }),
          ...(call.sequence === undefined
            ? {}
            : { toolCallSequence: call.sequence }),
          toolCallId: call.id,
          arguments: Object.freeze({ ...call.arguments }),
        })
        : { ok: false, code: 'tool_unavailable', data: null }
    }
  } catch (_) {
    result = { ok: false, code: 'tool_failed', data: null }
  }

  return finish(
    call,
    context,
    startedAt,
    result,
    result.ok ? 'succeeded' : 'failed',
  )
}

function enforceArgumentScope(
  context: AgentToolContext,
  args: Record<string, unknown>,
): void {
  if (typeof args.customerId === 'string') {
    assertCustomerAllowed(context.scope, args.customerId)
  }
}

function validArguments(
  args: unknown,
  schema: ObjectArguments,
): args is Record<string, unknown> {
  if (!isRecord(args)) return false
  const keys = Object.keys(args)
  if (keys.some((key) => !(key in schema.properties))) return false
  if (schema.required.some((key) => !(key in args))) return false
  for (const [key, value] of Object.entries(args)) {
    if (!validValue(value, schema.properties[key])) return false
  }
  return validDateRange(args)
}

function validValue(value: unknown, rule: ArgumentRule): boolean {
  if (rule.type === 'string') {
    if (typeof value !== 'string') return false
    if (rule.minLength !== undefined && value.trim().length < rule.minLength) {
      return false
    }
    if (rule.maxLength !== undefined && value.length > rule.maxLength) {
      return false
    }
    if (rule.pattern && !(new RegExp(rule.pattern).test(value))) return false
  } else if (rule.type === 'integer') {
    if (!Number.isInteger(value)) return false
  } else if (rule.type === 'number') {
    if (typeof value !== 'number' || !Number.isFinite(value)) return false
  } else if (rule.type === 'boolean') {
    if (typeof value !== 'boolean') return false
  } else if (rule.type === 'object') {
    if (!isRecord(value)) return false
  } else if (rule.type === 'array') {
    if (!Array.isArray(value)) return false
  }

  if (
    typeof value === 'number' &&
    (rule.minimum !== undefined && value < rule.minimum ||
      rule.maximum !== undefined && value > rule.maximum)
  ) return false
  if (rule.enum && !rule.enum.includes(value as never)) return false
  return true
}

function validDateRange(args: Record<string, unknown>): boolean {
  if (args.fromDate === undefined && args.toDate === undefined) return true
  if (typeof args.fromDate !== 'string' || typeof args.toDate !== 'string') {
    return false
  }
  const from = Date.parse(`${args.fromDate}T00:00:00Z`)
  const to = Date.parse(`${args.toDate}T00:00:00Z`)
  if (!Number.isFinite(from) || !Number.isFinite(to) || to < from) return false
  return (to - from) / 86_400_000 <= MAX_AGENT_READ_RANGE_DAYS
}

async function finish(
  call: AgentToolCall,
  context: AgentToolContext,
  startedAt: number,
  result: AgentToolResult,
  status: AgentToolEvidence['status'],
): Promise<AgentToolResult> {
  const safeResult = sanitize(result) as unknown as AgentToolResult
  const customerId = typeof call.arguments.customerId === 'string' &&
      context.scope.allowedCustomerIds.includes(call.arguments.customerId)
    ? call.arguments.customerId
    : null
  const stateVersionBefore = positiveInteger(
    call.arguments.expectedRowVersion,
  )
  const stateVersionAfter = positiveInteger(safeResult.data?.rowVersion) ??
    (safeResult.ok ? stateVersionBefore : null)
  await context.evidence.record({
    callId: bounded(call.id, 160),
    toolName: bounded(call.name, 120),
    arguments: sanitize(call.arguments),
    scope: {
      accessRole: context.scope.accessRole,
      customerId,
      allowedCustomerCount: context.scope.allowedCustomerIds.length,
    },
    result: safeResult,
    status,
    durationMs: Math.max(0, (context.now ?? Date.now)() - startedAt),
    stateVersionBefore,
    stateVersionAfter,
    toolSequence: call.sequence,
  })
  if (safeResult.ok) {
    await context.conversationContext?.recordSuccessfulTool(
      call,
      safeResult,
      context.conversationId,
      context.conversationContextEpoch ?? 0,
    )
  }
  return safeResult
}

function unsupportedStationReference(
  args: Readonly<Record<string, unknown>>,
): boolean {
  if (
    typeof args.schemaKey !== 'string' ||
    typeof args.schemaVersion !== 'number'
  ) return false
  try {
    requireStationSchema(args.schemaKey, args.schemaVersion)
    return false
  } catch (_) {
    return true
  }
}

function unsupportedStationSchema(): AgentToolResult {
  return {
    ok: false,
    code: 'unsupported_station_schema',
    data: {
      message: {
        en:
          'This station schema is not supported. Choose a station from the available ChickMark station list.',
        ar:
          'مخطط هذه المحطة غير مدعوم. اختر محطة من قائمة محطات ChickMark المتاحة.',
      },
    },
  }
}

function sanitize(value: unknown): Record<string, unknown> {
  const sanitized = sanitizeValue(value)
  return isRecord(sanitized) ? sanitized : {}
}

function sanitizeValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sanitizeValue)
  if (!isRecord(value)) return value
  return Object.fromEntries(
    Object.entries(value).map(([key, child]) => [
      key,
      isSecretKey(key) ? '[redacted]' : sanitizeValue(child),
    ]),
  )
}

function isSecretKey(key: string): boolean {
  return /secret|token|password|authorization|api.?key|service.?role/i.test(key)
}

function bounded(value: unknown, maxLength: number): string {
  return value?.toString().slice(0, maxLength) ?? ''
}

function positiveInteger(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) && value >= 1
    ? value
    : null
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
