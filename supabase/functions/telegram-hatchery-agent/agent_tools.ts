import {
  type AgentToolCall,
  type AgentToolExecutionInput,
  type AgentToolName,
  type AgentToolResult,
} from './agent_protocol.ts'
import { AgentScopeError, assertCustomerAllowed } from './agent_scope.ts'

export const MAX_AGENT_TOOL_CALLS_PER_TURN = 5
export const MAX_AGENT_READ_ROWS = 100
export const MAX_AGENT_READ_RANGE_DAYS = 366

type JsonType = 'string' | 'integer' | 'number' | 'boolean' | 'object' | 'array'

interface ArgumentRule {
  type: JsonType
  minLength?: number
  maxLength?: number
  minimum?: number
  maximum?: number
  enum?: readonly (string | number | boolean)[]
  pattern?: string
}

interface ObjectArguments {
  type: 'object'
  properties: Readonly<Record<string, ArgumentRule>>
  required: readonly string[]
  additionalProperties: false
}

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
}

export interface AgentToolEvidencePort {
  record(event: AgentToolEvidence): void | Promise<void>
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
  evidence: AgentToolEvidencePort
  handlers: Partial<Record<AgentToolName, AgentToolHandler>>
  now?: () => number
}

const idRule: ArgumentRule = {
  type: 'string',
  minLength: 1,
  maxLength: 160,
}
const schemaKeyRule: ArgumentRule = {
  type: 'string',
  minLength: 1,
  maxLength: 120,
}
const dateRule: ArgumentRule = {
  type: 'string',
  pattern: '^\\d{4}-\\d{2}-\\d{2}$',
}
const limitRule: ArgumentRule = {
  type: 'integer',
  minimum: 1,
  maximum: MAX_AGENT_READ_ROWS,
}
const auditLimitRule: ArgumentRule = {
  type: 'integer',
  minimum: 1,
  maximum: 20,
}
const versionRule: ArgumentRule = {
  type: 'integer',
  minimum: 1,
  maximum: 1000,
}

function definition(
  name: AgentToolName,
  description: string,
  properties: Record<string, ArgumentRule> = {},
  required: readonly string[] = [],
): AgentToolDefinition {
  return {
    type: 'function',
    name,
    description,
    parameters: {
      type: 'object',
      properties,
      required,
      additionalProperties: false,
    },
  }
}

export const AGENT_TOOL_DEFINITIONS: readonly AgentToolDefinition[] = Object
  .freeze([
    definition(
      'get_user_scope',
      'Return the customer access already enforced for this Telegram user.',
    ),
    definition(
      'list_customers',
      'List customers inside the server-enforced scope. Use this instead of guessing from raw customer IDs.',
    ),
    definition(
      'resolve_customer_flock',
      'Resolve an allowed customer name and optional flock name together using exact normalized names. Use this before ID-based tools when the user supplies names.',
      {
        customerName: idRule,
        flockName: idRule,
      },
      ['customerName'],
    ),
    definition(
      'get_customer_context',
      'Load an allowed customer context.',
      { customerId: idRule },
      ['customerId'],
    ),
    definition(
      'list_customer_flocks',
      'List flocks for an allowed customer.',
      { customerId: idRule, limit: limitRule },
      ['customerId'],
    ),
    definition(
      'list_customer_hatcheries',
      'List hatcheries for an allowed customer.',
      { customerId: idRule, limit: limitRule },
      ['customerId'],
    ),
    definition(
      'list_customer_audits',
      'List all recent audit options for an allowed customer and optional flock so the user can choose one.',
      { customerId: idRule, flockId: idRule, limit: auditLimitRule },
      ['customerId'],
    ),
    definition(
      'get_audit_summary',
      'Load the verified summary of one selected authorized audit.',
      { auditId: idRule },
      ['auditId'],
    ),
    definition(
      'get_flock_context',
      'Load one authorized flock and its operational context.',
      { flockId: idRule },
      ['flockId'],
    ),
    definition(
      'query_station_records',
      'Read allowlisted station records in a bounded date range.',
      {
        customerId: idRule,
        flockId: idRule,
        schemaKey: schemaKeyRule,
        schemaVersion: versionRule,
        fromDate: dateRule,
        toDate: dateRule,
        limit: limitRule,
      },
      ['customerId', 'schemaKey', 'schemaVersion', 'fromDate', 'toDate'],
    ),
    definition(
      'compare_station_metrics',
      'Compare deterministic station metrics from authorized records.',
      {
        customerId: idRule,
        flockId: idRule,
        schemaKey: schemaKeyRule,
        schemaVersion: versionRule,
        measureKey: schemaKeyRule,
        fromDate: dateRule,
        toDate: dateRule,
      },
      [
        'customerId',
        'schemaKey',
        'schemaVersion',
        'measureKey',
        'fromDate',
        'toDate',
      ],
    ),
    definition(
      'get_record_provenance',
      'Load the source context and freshness of an authorized record.',
      {
        schemaKey: schemaKeyRule,
        schemaVersion: versionRule,
        recordId: idRule,
      },
      ['schemaKey', 'schemaVersion', 'recordId'],
    ),
    definition(
      'list_applicable_stations',
      'List station modules applicable to an authorized flock sector.',
      { customerId: idRule, flockId: idRule },
      ['customerId', 'flockId'],
    ),
    definition(
      'load_station_schema',
      'Load fields and validation for one versioned station module.',
      { schemaKey: schemaKeyRule, schemaVersion: versionRule },
      ['schemaKey', 'schemaVersion'],
    ),
    definition(
      'propose_intake',
      'Record a proposed data-entry action for user confirmation.',
      {
        customerId: idRule,
      },
      ['customerId'],
    ),
    definition(
      'start_intake',
      'Start intake only from a recently confirmed proposal.',
      {
        pendingActionId: idRule,
        schemaKey: schemaKeyRule,
        schemaVersion: versionRule,
        customerId: idRule,
        flockId: idRule,
        hatcheryId: idRule,
        auditDate: dateRule,
        layer: {
          type: 'string',
          enum: [
            'pool',
            'house',
            'setter',
            'hatcher',
            'setter_hatcher',
            'trolley',
            'tray',
          ],
        },
        setterIdentity: idRule,
        hatcherIdentity: idRule,
      },
      [
        'pendingActionId',
        'schemaKey',
        'schemaVersion',
        'customerId',
        'flockId',
        'hatcheryId',
        'auditDate',
        'layer',
      ],
    ),
    definition(
      'record_station_values',
      'Validate and record explicit station values without finalizing them.',
      {
        intakeId: idRule,
        expectedRowVersion: versionRule,
        values: { type: 'array' },
      },
      ['intakeId', 'expectedRowVersion', 'values'],
    ),
    definition(
      'get_intake_status',
      'Return accepted values, missing fields, and unresolved clarifications.',
      { intakeId: idRule },
      ['intakeId'],
    ),
    definition(
      'create_station_summary',
      'Create one versioned summary after all required values are valid.',
      { intakeId: idRule, expectedRowVersion: versionRule },
      ['intakeId', 'expectedRowVersion'],
    ),
    definition(
      'confirm_station_summary',
      'Confirm the exact current station summary version.',
      {
        intakeId: idRule,
        expectedRowVersion: versionRule,
        summaryVersion: versionRule,
      },
      ['intakeId', 'expectedRowVersion', 'summaryVersion'],
    ),
    definition(
      'submit_station_for_review',
      'Submit a confirmed station intake for administrator review.',
      { intakeId: idRule, expectedRowVersion: versionRule },
      ['intakeId', 'expectedRowVersion'],
    ),
    definition(
      'pause_intake',
      'Pause an active intake.',
      { intakeId: idRule, expectedRowVersion: versionRule },
      [
        'intakeId',
        'expectedRowVersion',
      ],
    ),
    definition(
      'resume_intake',
      'Resume a paused intake.',
      { intakeId: idRule, expectedRowVersion: versionRule },
      [
        'intakeId',
        'expectedRowVersion',
      ],
    ),
    definition(
      'cancel_intake',
      'Cancel an intake.',
      { intakeId: idRule, expectedRowVersion: versionRule },
      ['intakeId', 'expectedRowVersion'],
    ),
    definition(
      'list_legacy_draft_questions',
      'List unresolved questions from an authorized legacy draft.',
      { submissionId: idRule },
      ['submissionId'],
    ),
    definition(
      'answer_legacy_draft_question',
      'Record an answer to one unresolved authorized legacy draft question.',
      {
        submissionId: idRule,
        questionId: idRule,
        answer: { type: 'string', minLength: 1, maxLength: 2000 },
      },
      ['submissionId', 'questionId', 'answer'],
    ),
  ])

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
  })
  return safeResult
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
