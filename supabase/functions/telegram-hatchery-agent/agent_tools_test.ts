import { assert, assertEquals, assertStringIncludes } from '@std/assert'

import type {
  AgentToolExecutionInput,
  AgentToolResult,
} from './agent_protocol.ts'
import {
  AGENT_TOOL_DEFINITIONS,
  type AgentToolEvidence,
  executeAgentTool,
  MAX_AGENT_TOOL_CALLS_PER_TURN,
} from './agent_tools.ts'

const scope = {
  staffLinkId: 'staff-a',
  accessRole: 'customer' as const,
  allowedCustomerIds: ['customer-a'],
}

Deno.test('tool definitions expose typed capabilities without database internals', () => {
  const json = JSON.stringify(AGENT_TOOL_DEFINITIONS)
  assertStringIncludes(json, 'list_customers')
  assertStringIncludes(json, 'resolve_customer_flock')
  assertStringIncludes(json, 'list_customer_flocks')
  assertStringIncludes(json, 'list_customer_audits')
  assertStringIncludes(json, 'select_audit_option')
  assertStringIncludes(json, 'get_audit_summary')
  const auditCatalog = AGENT_TOOL_DEFINITIONS.find(
    (tool) => tool.name === 'list_customer_audits',
  )
  assertEquals(auditCatalog?.parameters.properties.limit.maximum, 20)
  const selectionCatalog = AGENT_TOOL_DEFINITIONS.find(
    (tool) => tool.name === 'select_audit_option',
  )
  assertEquals(selectionCatalog?.parameters.required, ['position'])
  assertEquals(selectionCatalog?.parameters.properties.position, {
    type: 'integer',
    minimum: 1,
    maximum: 20,
  })
  for (
    const forbidden of [
      'service_role',
      'SUPABASE_SERVICE_ROLE_KEY',
      'public.',
      'chick_quality',
      'agent_intake_sessions',
    ]
  ) {
    assert(!json.includes(forbidden), `tool JSON leaked ${forbidden}`)
  }
  assertEquals(MAX_AGENT_TOOL_CALLS_PER_TURN, 5)
})

Deno.test('gateway rejects unknown tools and unexpected arguments', async () => {
  const evidence: AgentToolEvidence[] = []
  const context = {
    scope,
    conversationId: 'conversation-a',
    activeVisitId: null,
    evidence: {
      record(event: AgentToolEvidence) {
        evidence.push(event)
      },
    },
    handlers: {},
  }

  assertEquals(
    await executeAgentTool(
      { id: 'call-1', name: 'drop_database', arguments: {} },
      context,
    ),
    { ok: false, code: 'unknown_tool', data: null },
  )
  assertEquals(
    await executeAgentTool(
      {
        id: 'call-2',
        name: 'get_user_scope',
        arguments: { customerId: 'customer-b' },
      },
      context,
    ),
    { ok: false, code: 'invalid_arguments', data: null },
  )
  assertEquals(evidence.map((event) => event.status), ['rejected', 'rejected'])

  assertEquals(
    await executeAgentTool(
      {
        id: 'call-audit-name',
        name: 'list_customer_audits',
        arguments: { customerId: 'الغريب' },
      },
      context,
    ),
    { ok: false, code: 'scope_denied', data: null },
  )
})

Deno.test('gateway injects enforced scope and validates bounded read arguments', async () => {
  const received: Array<Record<string, unknown>> = []
  const result = await executeAgentTool(
    {
      id: 'call-3',
      name: 'list_customer_flocks',
      arguments: { customerId: 'customer-a', limit: 20 },
    },
    {
      scope,
      conversationId: 'conversation-a',
      activeVisitId: 'visit-a',
      evidence: { record: () => undefined },
      handlers: {
        list_customer_flocks(input): Promise<AgentToolResult> {
          received.push({
            scope: input.scope,
            conversationId: input.conversationId,
            activeVisitId: input.activeVisitId,
            toolCallId: input.toolCallId,
            arguments: input.arguments,
          })
          return Promise.resolve({
            ok: true,
            code: 'ok',
            data: { flocks: [] },
          })
        },
      },
    },
  )

  assertEquals(result, { ok: true, code: 'ok', data: { flocks: [] } })
  assertEquals(received, [{
    scope,
    conversationId: 'conversation-a',
    activeVisitId: 'visit-a',
    toolCallId: 'call-3',
    arguments: { customerId: 'customer-a', limit: 20 },
  }])

  assertEquals(
    await executeAgentTool(
      {
        id: 'call-4',
        name: 'list_customer_flocks',
        arguments: { customerId: 'customer-a', limit: 101 },
      },
      {
        scope,
        conversationId: 'conversation-a',
        activeVisitId: null,
        evidence: { record: () => undefined },
        handlers: {},
      },
    ),
    { ok: false, code: 'invalid_arguments', data: null },
  )
})

Deno.test('audit option selection accepts only integer positions one through twenty', async () => {
  const positions: unknown[] = []
  const selectionHandler = (
    input: AgentToolExecutionInput,
  ): Promise<AgentToolResult> => {
    positions.push(input.arguments.position)
    return Promise.resolve({ ok: true, code: 'ok', data: { selected: true } })
  }
  const context = {
    scope,
    conversationId: 'conversation-a',
    activeVisitId: null,
    evidence: { record: () => undefined },
    handlers: {
      select_audit_option: selectionHandler,
    },
  }

  for (const position of [0, 21, 1.5, '2']) {
    assertEquals(
      await executeAgentTool(
        {
          id: `call-invalid-${position}`,
          name: 'select_audit_option',
          arguments: { position },
        },
        context,
      ),
      { ok: false, code: 'invalid_arguments', data: null },
    )
  }
  for (const position of [1, 20]) {
    assertEquals(
      await executeAgentTool(
        {
          id: `call-valid-${position}`,
          name: 'select_audit_option',
          arguments: { position },
        },
        context,
      ),
      { ok: true, code: 'ok', data: { selected: true } },
    )
  }
  assertEquals(positions, [1, 20])
})

Deno.test('tool evidence strips secret-shaped arguments and results', async () => {
  const evidence: AgentToolEvidence[] = []
  await executeAgentTool(
    {
      id: 'call-5',
      name: 'get_customer_context',
      arguments: { customerId: 'customer-a' },
    },
    {
      scope,
      conversationId: 'conversation-a',
      activeVisitId: null,
      evidence: {
        record(event) {
          evidence.push(event)
        },
      },
      handlers: {
        get_customer_context: () =>
          Promise.resolve({
            ok: true,
            code: 'ok',
            data: {
              id: 'customer-a',
              serviceRoleKey: 'must-not-be-recorded',
            },
          }),
      },
    },
  )

  assertEquals(evidence.length, 1)
  assert(!JSON.stringify(evidence[0]).includes('must-not-be-recorded'))
  assertEquals(evidence[0].scope, {
    accessRole: 'customer',
    customerId: 'customer-a',
    allowedCustomerCount: 1,
  })
  assertEquals(evidence[0].stateVersionBefore, null)
  assertEquals(evidence[0].stateVersionAfter, null)
  assertEquals(evidence[0].result, {
    ok: true,
    code: 'ok',
    data: { id: 'customer-a', serviceRoleKey: '[redacted]' },
  })
})

Deno.test('tool evidence records optimistic state versions', async () => {
  const evidence: AgentToolEvidence[] = []
  await executeAgentTool(
    {
      id: 'call-version',
      name: 'get_intake_status',
      arguments: { intakeId: 'intake-a' },
    },
    {
      scope,
      conversationId: 'conversation-a',
      activeVisitId: 'visit-a',
      evidence: {
        record(event) {
          evidence.push(event)
        },
      },
      handlers: {
        get_intake_status: () =>
          Promise.resolve({
            ok: true,
            code: 'ok',
            data: { rowVersion: 7 },
          }),
      },
    },
  )

  assertEquals(evidence[0].stateVersionBefore, null)
  assertEquals(evidence[0].stateVersionAfter, 7)
})
