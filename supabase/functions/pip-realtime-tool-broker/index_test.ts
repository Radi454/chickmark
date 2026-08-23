import { assert, assertEquals } from '@std/assert'

import {
  handleToolBrokerRequest,
  type ToolBrokerAdminClient,
  type ToolBrokerDeps,
} from './index.ts'
import { BROKER_SECRET_HEADER } from './config.ts'
import { computeAuthorizationFingerprint } from '../pip-realtime-session/fingerprint.ts'
import type { AgentToolHandler } from '../telegram-hatchery-agent/agent_tools.ts'
import type {
  AgentToolName,
  AgentToolResult,
} from '../telegram-hatchery-agent/agent_protocol.ts'
import {
  createFakeAdminClient,
  createFakeDatabase,
  type FakeDatabase,
  sequentialIds,
} from './test_support.ts'

const SECRET = 'broker-secret-0123456789abcdef0123456789'
const OWNER = 'user-1'
const SESSION = 'sess-1'
const CONVERSATION = 'conv-1'
const NOW = new Date('2026-08-16T10:00:00.000Z')

async function ownerFingerprint(
  overrides: { role?: string; status?: string; customers?: string[] } = {},
): Promise<string> {
  return await computeAuthorizationFingerprint({
    staffLinkId: `app-${OWNER}`,
    accessRole: 'customer',
    allowedCustomerIds: overrides.customers ?? ['cust-1'],
    profileRole: overrides.role ?? 'customer',
    profileStatus: overrides.status ?? 'approved',
  })
}

interface Harness {
  db: FakeDatabase
  deps: ToolBrokerDeps
  /** Every (tool, arguments) pair a handler actually saw. */
  executed: { tool: string; args: Record<string, unknown> }[]
  post(body: Record<string, unknown>, secret?: string): Promise<Response>
}

async function harness(options: {
  fingerprint?: string
  sessionState?: string
  setupState?: string
  activeGeneration?: number
  profile?: Record<string, unknown>
  results?: Partial<Record<AgentToolName, AgentToolResult>>
} = {}): Promise<Harness> {
  const fingerprint = options.fingerprint ?? await ownerFingerprint()
  const db = createFakeDatabase({
    profiles: [
      options.profile ?? {
        id: OWNER,
        role: 'customer',
        status: 'approved',
        customer_id: 'cust-1',
        full_name: 'Owner',
        email: 'owner@example.com',
      },
    ],
    agent_conversations: [
      {
        id: CONVERSATION,
        active_visit_id: null,
        state_version: 1,
        context_epoch: 1,
      },
    ],
    agent_realtime_sessions: [
      {
        id: SESSION,
        conversation_id: CONVERSATION,
        context_epoch: 1,
        authorization_fingerprint: fingerprint,
        owner_profile_id: OWNER,
        active_generation: options.activeGeneration ?? 1,
        state: options.sessionState ?? 'active',
      },
    ],
    agent_realtime_calls: [
      {
        id: 'call-1',
        session_id: SESSION,
        generation: 1,
        setup_state: options.setupState ?? 'active',
        authorization_fingerprint: fingerprint,
      },
    ],
    agent_tool_call_claims: [],
    agent_tool_events: [],
  })

  const executed: { tool: string; args: Record<string, unknown> }[] = []
  const handler = (name: AgentToolName): AgentToolHandler => (input) => {
    executed.push({ tool: name, args: { ...input.arguments } })
    return Promise.resolve(
      options.results?.[name] ??
        { ok: true, code: 'ok', data: { id: 'cust-1' } },
    )
  }

  const deps: ToolBrokerDeps = {
    adminClient: createFakeAdminClient(db) as unknown as ToolBrokerAdminClient,
    brokerSecret: SECRET,
    handlers: {
      get_customer_context: handler('get_customer_context'),
      pause_intake: handler('pause_intake'),
    },
    newId: sequentialIds('evt'),
    now: () => NOW,
  }

  return {
    db,
    deps,
    executed,
    post(body, secret = SECRET) {
      const headers: Record<string, string> = {
        'content-type': 'application/json',
      }
      if (secret) headers[BROKER_SECRET_HEADER] = secret
      return handleToolBrokerRequest(
        new Request('https://edge.test/pip-realtime-tool-broker', {
          method: 'POST',
          headers,
          body: JSON.stringify(body),
        }),
        deps,
      )
    },
  }
}

async function readTool(
  fingerprint: string,
  overrides: Record<string, unknown> = {},
): Promise<Record<string, unknown>> {
  return {
    session_id: SESSION,
    generation: 1,
    tool_call_id: 'call_abc',
    tool_name: 'get_customer_context',
    arguments: { customerId: 'cust-1' },
    interaction_id: 'int-1',
    authorization_fingerprint: fingerprint,
    ...overrides,
  }
}

function events(db: FakeDatabase): Record<string, unknown>[] {
  return db.tables.agent_tool_events ?? []
}

function claims(db: FakeDatabase): Record<string, unknown>[] {
  return db.tables.agent_tool_call_claims ?? []
}

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------

Deno.test('only POST is served', async () => {
  const h = await harness()
  const response = await handleToolBrokerRequest(
    new Request('https://edge.test/pip-realtime-tool-broker', {
      method: 'GET',
    }),
    h.deps,
  )
  assertEquals(response.status, 405)
})

Deno.test('a request without the broker secret is refused', async () => {
  const h = await harness()
  const response = await h.post(await readTool(await ownerFingerprint()), '')
  assertEquals(response.status, 401)
  assertEquals((await response.json()).code, 'unauthenticated')
  assertEquals(h.executed.length, 0)
})

Deno.test('a request with the wrong broker secret is refused', async () => {
  const h = await harness()
  const response = await h.post(
    await readTool(await ownerFingerprint()),
    'broker-secret-0123456789abcdef0123456780',
  )
  assertEquals(response.status, 401)
  assertEquals(h.executed.length, 0)
})

Deno.test('an unconfigured broker secret fails CLOSED, never open', async () => {
  const h = await harness()
  h.deps.brokerSecret = null
  const response = await h.post(await readTool(await ownerFingerprint()))
  assertEquals(response.status, 503)
  assertEquals((await response.json()).code, 'broker_not_configured')
  assertEquals(h.executed.length, 0)
  assertEquals(claims(h.db).length, 0)
})

Deno.test('a malformed body is refused before any lookup', async () => {
  const h = await harness()
  const response = await h.post({ session_id: SESSION })
  assertEquals(response.status, 400)
  assertEquals(h.executed.length, 0)
})

// ---------------------------------------------------------------------------
// Authorization is re-resolved server-side
// ---------------------------------------------------------------------------

Deno.test('a fingerprint the caller made up is refused', async () => {
  const h = await harness()
  const response = await h.post(
    await readTool('0'.repeat(64)),
  )
  assertEquals(response.status, 409)
  assertEquals((await response.json()).code, 'authorization_changed')
  assertEquals(h.executed.length, 0)
  assertEquals(claims(h.db).length, 0)
})

Deno.test('a scope change since provisioning is refused', async () => {
  // The session was stamped while the owner was still approved; the profile has
  // since been revoked, so the recomputed fingerprint no longer matches.
  const stamped = await ownerFingerprint()
  const h = await harness({ fingerprint: stamped })
  h.db.tables.profiles[0].customer_id = 'cust-9'
  const response = await h.post(await readTool(stamped))
  assertEquals(response.status, 409)
  assertEquals((await response.json()).code, 'authorization_changed')
  assertEquals(h.executed.length, 0)
})

Deno.test('an owner whose profile is no longer approved is refused', async () => {
  const stamped = await ownerFingerprint()
  const h = await harness({ fingerprint: stamped })
  h.db.tables.profiles[0].status = 'revoked'
  const response = await h.post(await readTool(stamped))
  assertEquals(response.status, 409)
  assertEquals((await response.json()).code, 'authorization_changed')
  assertEquals(h.executed.length, 0)
})

// ---------------------------------------------------------------------------
// Generation currency
// ---------------------------------------------------------------------------

Deno.test('a stale generation is refused', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint, activeGeneration: 2 })
  const response = await h.post(await readTool(fingerprint))
  assertEquals(response.status, 409)
  assertEquals((await response.json()).code, 'stale_generation')
  assertEquals(h.executed.length, 0)
})

Deno.test('a terminal generation is refused', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint, setupState: 'ended' })
  const response = await h.post(await readTool(fingerprint))
  assertEquals(response.status, 409)
  assertEquals((await response.json()).code, 'terminal_generation')
  assertEquals(h.executed.length, 0)
})

Deno.test('a session that is no longer active is refused', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint, sessionState: 'ended' })
  const response = await h.post(await readTool(fingerprint))
  assertEquals(response.status, 409)
  assertEquals((await response.json()).code, 'session_not_active')
  assertEquals(h.executed.length, 0)
})

Deno.test('an unknown session is refused', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint })
  const response = await h.post(
    await readTool(fingerprint, { session_id: 'sess-missing' }),
  )
  assertEquals(response.status, 404)
  assertEquals(h.executed.length, 0)
})

// ---------------------------------------------------------------------------
// Happy path and evidence
// ---------------------------------------------------------------------------

Deno.test('a valid call executes once and writes exactly one evidence row', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint })
  const response = await h.post(await readTool(fingerprint))

  assertEquals(response.status, 200)
  const payload = await response.json()
  assertEquals(payload.status, 'succeeded')
  assertEquals(payload.disposition, 'executed')
  assertEquals(payload.result.code, 'ok')

  assertEquals(h.executed.length, 1)
  assertEquals(h.executed[0].tool, 'get_customer_context')

  const written = events(h.db)
  assertEquals(written.length, 1)
  assertEquals(written[0].conversation_turn_id, null)
  assertEquals(written[0].realtime_session_id, SESSION)
  assertEquals(written[0].realtime_generation, 1)
  assertEquals(written[0].realtime_interaction_id, 'int-1')
  assertEquals(written[0].source_channel, 'realtime_voice')
  assertEquals(written[0].status, 'succeeded')
  assertEquals(written[0].tool_sequence, 1)
  assertEquals(written[0].tool_call_id, 'call_abc')
  assert(typeof written[0].argument_hash === 'string')

  const claimed = claims(h.db)
  assertEquals(claimed.length, 1)
  assertEquals(claimed[0].state, 'succeeded')
  assertEquals(claimed[0].tool_event_id, written[0].id)
  assertEquals(claimed[0].realtime_interaction_id, 'int-1')
  assert(claimed[0].settled_at !== null)
})

Deno.test('tool_sequence advances per session and generation', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint })
  await h.post(await readTool(fingerprint))
  await h.post(
    await readTool(fingerprint, {
      tool_call_id: 'call_def',
      interaction_id: 'int-2',
    }),
  )
  const written = events(h.db)
  assertEquals(written.length, 2)
  assertEquals(written.map((row) => row.tool_sequence), [1, 2])
})

// ---------------------------------------------------------------------------
// Idempotency
// ---------------------------------------------------------------------------

Deno.test('the same call id with the same arguments is not re-executed', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint })
  const first = await h.post(await readTool(fingerprint))
  assertEquals(first.status, 200)

  const second = await h.post(await readTool(fingerprint))
  assertEquals(second.status, 200)
  const payload = await second.json()
  assertEquals(payload.disposition, 'duplicate')
  assertEquals(payload.status, 'succeeded')
  // The recorded terminal result, not a freshly computed one.
  assertEquals(payload.result.code, 'ok')

  assertEquals(h.executed.length, 1)
  assertEquals(events(h.db).length, 1)
  assertEquals(claims(h.db).length, 1)
})

Deno.test('the same call id with different arguments is rejected', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint })
  await h.post(await readTool(fingerprint))

  const conflicting = await h.post(
    await readTool(fingerprint, {
      arguments: { customerId: 'cust-1', limit: 5 },
    }),
  )
  assertEquals(conflicting.status, 409)
  assertEquals((await conflicting.json()).code, 'argument_conflict')
  assertEquals(h.executed.length, 1)
  assertEquals(events(h.db).length, 1)
})

Deno.test('argument key order does not change the hash', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint })
  const first = await h.post(
    await readTool(fingerprint, {
      tool_name: 'list_customer_flocks',
      arguments: { customerId: 'cust-1', limit: 5 },
    }),
  )
  assertEquals(first.status, 200)
  // The SAME arguments serialized in the opposite key order. A redelivery must
  // not look like a conflict just because the provider reordered the JSON.
  const again = await h.post(
    await readTool(fingerprint, {
      tool_name: 'list_customer_flocks',
      arguments: { limit: 5, customerId: 'cust-1' },
    }),
  )
  assertEquals(again.status, 200)
  assertEquals((await again.json()).disposition, 'duplicate')
})

Deno.test('a mutation that ends indeterminate is never auto-replayed', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint })
  // The write lands, then the evidence insert fails with a non-unique error:
  // the row may or may not exist, which is exactly the indeterminate case.
  h.db.failingInserts.add('agent_tool_events')

  const body = await readTool(fingerprint, {
    tool_call_id: 'call_mut',
    tool_name: 'pause_intake',
    arguments: { intakeId: 'intake-1', expectedRowVersion: 1 },
  })
  const first = await h.post(body)
  assertEquals(first.status, 409)
  assertEquals((await first.json()).code, 'tool_indeterminate')
  assertEquals(h.executed.length, 1)

  const claimed = claims(h.db)
  assertEquals(claimed.length, 1)
  assertEquals(claimed[0].state, 'indeterminate')

  // The evidence writer is healthy again, but the claim still refuses to replay.
  h.db.failingInserts.delete('agent_tool_events')
  const retry = await h.post(body)
  assertEquals(retry.status, 409)
  assertEquals((await retry.json()).code, 'indeterminate_not_replayable')
  assertEquals(h.executed.length, 1)
  assertEquals(events(h.db).length, 0)
})

// ---------------------------------------------------------------------------
// Scope enforcement inside the shared runtime
// ---------------------------------------------------------------------------

Deno.test('a customer the caller may not access is refused by the runtime', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint })
  const response = await h.post(
    await readTool(fingerprint, {
      tool_call_id: 'call_scope',
      arguments: { customerId: 'cust-999' },
    }),
  )
  assertEquals(response.status, 200)
  const payload = await response.json()
  assertEquals(payload.status, 'rejected')
  assertEquals(payload.result.code, 'scope_denied')
  // The handler never ran — the refusal happened before it was reached.
  assertEquals(h.executed.length, 0)

  const written = events(h.db)
  assertEquals(written.length, 1)
  assertEquals(written[0].status, 'rejected')
  assertEquals(claims(h.db)[0].state, 'rejected')
})

Deno.test('an unknown tool name is rejected, and still evidenced', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint })
  const response = await h.post(
    await readTool(fingerprint, { tool_name: 'drop_all_tables' }),
  )
  assertEquals(response.status, 200)
  const payload = await response.json()
  assertEquals(payload.status, 'rejected')
  assertEquals(payload.result.code, 'unknown_tool')
  assertEquals(h.executed.length, 0)
  assertEquals(events(h.db).length, 1)
})

// ---------------------------------------------------------------------------
// The 5-call cap belongs to the sideband, not here
// ---------------------------------------------------------------------------

Deno.test('the broker imposes no per-interaction call cap of its own', async () => {
  const fingerprint = await ownerFingerprint()
  const h = await harness({ fingerprint })
  for (let index = 0; index < 8; index++) {
    const response = await h.post(
      await readTool(fingerprint, { tool_call_id: `call_${index}` }),
    )
    assertEquals(response.status, 200)
  }
  assertEquals(h.executed.length, 8)
  assertEquals(events(h.db).length, 8)
})
