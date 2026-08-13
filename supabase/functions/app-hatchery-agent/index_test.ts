import { assert, assertEquals } from '@std/assert'

import type { AgentScope } from '../telegram-hatchery-agent/agent_protocol.ts'
import type {
  AgentTurnInput,
  AgentTurnResult,
} from '../telegram-hatchery-agent/agent_runtime.ts'
import {
  type AppAgentAdminClient,
  type AppAgentDeps,
  handleAppAgentRequest,
} from './index.ts'
import {
  createFakeAdminClient,
  createFakeDatabase,
  type FakeDatabase,
  sequentialIds,
} from './test_support.ts'

const NOW = '2026-08-14T10:00:00.000Z'

function seedDatabase(): FakeDatabase {
  return createFakeDatabase({
    profiles: [
      {
        id: 'user-customer',
        full_name: 'Customer One',
        email: 'customer@example.test',
        role: 'customer',
        status: 'approved',
        customer_id: 'cust-1',
      },
      {
        id: 'user-customer-nolink',
        full_name: 'Customer Without Customer',
        email: 'orphan@example.test',
        role: 'customer',
        status: 'approved',
        customer_id: null,
      },
      {
        id: 'user-pending',
        full_name: 'Pending',
        email: 'pending@example.test',
        role: 'auditor',
        status: 'pending',
        customer_id: null,
      },
      {
        id: 'user-disabled',
        full_name: 'Disabled',
        email: 'disabled@example.test',
        role: 'admin',
        status: 'disabled',
        customer_id: null,
      },
      {
        id: 'user-auditor',
        full_name: 'Auditor',
        email: 'auditor@example.test',
        role: 'auditor',
        status: 'approved',
        customer_id: null,
      },
      {
        id: 'user-auditor-empty',
        full_name: 'Unassigned Auditor',
        email: 'empty@example.test',
        role: 'auditor',
        status: 'approved',
        customer_id: null,
      },
      {
        id: 'user-admin',
        full_name: 'Admin',
        email: 'admin@example.test',
        role: 'admin',
        status: 'approved',
        customer_id: null,
      },
    ],
    customers: [{ id: 'cust-1' }, { id: 'cust-2' }, { id: 'cust-3' }],
    auditor_customers: [
      { auditor_id: 'user-auditor', customer_id: 'cust-3' },
      { auditor_id: 'user-auditor', customer_id: 'cust-1' },
    ],
    telegram_staff_links: [],
    agent_conversations: [],
    agent_conversation_turns: [],
    agent_tool_events: [],
  })
}

interface Harness {
  db: FakeDatabase
  deps: AppAgentDeps
  turns: AgentTurnInput[]
  scopes: AgentScope[]
  transcribeCalls: string[]
  synthesizeCalls: string[]
}

function createHarness(options: {
  db?: FakeDatabase
  turn?: (input: AgentTurnInput) => AgentTurnResult | Promise<AgentTurnResult>
  authUserId?: string | null
  now?: () => string
  transcribeAudio?: (audioBase64: string) => Promise<string>
  synthesizeSpeech?: (text: string) => Promise<string>
} = {}): Harness {
  const db = options.db ?? seedDatabase()
  const turns: AgentTurnInput[] = []
  const scopes: AgentScope[] = []
  const transcribeCalls: string[] = []
  const synthesizeCalls: string[] = []
  const deps: AppAgentDeps = {
    adminClient: createFakeAdminClient(db) as unknown as AppAgentAdminClient,
    authenticate: (_token) =>
      Promise.resolve(
        options.authUserId === null
          ? null
          : { id: options.authUserId ?? 'user-customer' },
      ),
    runAgentTurn: async (input) => {
      turns.push(input)
      scopes.push(input.scope)
      const handler = options.turn ??
        ((_: AgentTurnInput): AgentTurnResult => ({
          status: 'replied',
          reply: 'Hatchability is 84%.',
          providerResponseId: 'resp-1',
          provider: 'openai',
          model: 'gpt-4.1-mini',
          toolCallCount: 0,
        }))
      return await handler(input)
    },
    transcribeAudio: options.transcribeAudio
      ? (audioBase64) => {
        transcribeCalls.push(audioBase64)
        return options.transcribeAudio!(audioBase64)
      }
      : undefined,
    synthesizeSpeech: options.synthesizeSpeech
      ? (text) => {
        synthesizeCalls.push(text)
        return options.synthesizeSpeech!(text)
      }
      : undefined,
    newId: sequentialIds('id'),
    now: options.now ?? (() => NOW),
  }
  return { db, deps, turns, scopes, transcribeCalls, synthesizeCalls }
}

function postRequest(
  body: Record<string, unknown>,
  options: { token?: string | null } = {},
): Request {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  }
  const token = options.token === undefined ? 'token-abc' : options.token
  if (token !== null) headers['Authorization'] = `Bearer ${token}`
  return new Request('https://example.test/app-hatchery-agent', {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  })
}

async function readJson(response: Response): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>
}

function turnRows(db: FakeDatabase): Record<string, unknown>[] {
  return db.tables.agent_conversation_turns ?? []
}

Deno.test('CORS preflight is answered without touching the database', async () => {
  const harness = createHarness()
  harness.deps.adminClient = {
    from() {
      throw new Error('database must not be called for OPTIONS')
    },
  } as unknown as AppAgentAdminClient

  const response = await handleAppAgentRequest(
    new Request('https://example.test', { method: 'OPTIONS' }),
    harness.deps,
  )

  assertEquals(response.status, 200)
  assertEquals(response.headers.get('Access-Control-Allow-Origin'), '*')
  assertEquals(
    response.headers.get('Access-Control-Allow-Headers'),
    'authorization, x-client-info, apikey, content-type',
  )
  assertEquals(
    response.headers.get('Access-Control-Allow-Methods'),
    'POST, OPTIONS',
  )
})

Deno.test('non-POST methods are rejected with 405', async () => {
  const harness = createHarness()
  const response = await handleAppAgentRequest(
    new Request('https://example.test', { method: 'GET' }),
    harness.deps,
  )
  assertEquals(response.status, 405)
})

Deno.test('a missing bearer token is unauthenticated', async () => {
  const harness = createHarness()
  const response = await handleAppAgentRequest(
    postRequest({ action: 'history' }, { token: null }),
    harness.deps,
  )
  assertEquals(response.status, 401)
  assertEquals((await readJson(response)).code, 'unauthenticated')
})

Deno.test('an invalid bearer token is unauthenticated', async () => {
  const harness = createHarness({ authUserId: null })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'history' }),
    harness.deps,
  )
  assertEquals(response.status, 401)
  assertEquals((await readJson(response)).code, 'unauthenticated')
  assertEquals(harness.turns.length, 0)
})

Deno.test('a pending profile is not approved', async () => {
  const harness = createHarness({ authUserId: 'user-pending' })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'history' }),
    harness.deps,
  )
  assertEquals(response.status, 403)
  assertEquals((await readJson(response)).code, 'not_approved')
})

Deno.test('a disabled profile is not approved', async () => {
  const harness = createHarness({ authUserId: 'user-disabled' })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'history' }),
    harness.deps,
  )
  assertEquals(response.status, 403)
  assertEquals((await readJson(response)).code, 'not_approved')
})

Deno.test('a missing profile is not approved', async () => {
  const harness = createHarness({ authUserId: 'user-unknown' })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'history' }),
    harness.deps,
  )
  assertEquals(response.status, 403)
  assertEquals((await readJson(response)).code, 'not_approved')
})

Deno.test('a customer profile without a customer is not approved', async () => {
  const harness = createHarness({ authUserId: 'user-customer-nolink' })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'history' }),
    harness.deps,
  )
  assertEquals(response.status, 403)
  assertEquals((await readJson(response)).code, 'not_approved')
})

Deno.test('a customer caller only ever sees their own customer', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const response = await handleAppAgentRequest(
    postRequest({ message: 'Hi', clientMessageId: 'msg-1' }),
    harness.deps,
  )

  assertEquals(response.status, 200)
  assertEquals(harness.scopes.length, 1)
  assertEquals(harness.scopes[0].accessRole, 'customer')
  assertEquals([...harness.scopes[0].allowedCustomerIds], ['cust-1'])
})

Deno.test('an auditor caller is scoped to their auditor_customers list', async () => {
  const harness = createHarness({ authUserId: 'user-auditor' })
  const response = await handleAppAgentRequest(
    postRequest({ message: 'Hi', clientMessageId: 'msg-1' }),
    harness.deps,
  )

  assertEquals(response.status, 200)
  assertEquals(harness.scopes[0].accessRole, 'customer')
  assertEquals([...harness.scopes[0].allowedCustomerIds], ['cust-1', 'cust-3'])
})

Deno.test('an auditor with no mapped customers is not approved', async () => {
  const harness = createHarness({ authUserId: 'user-auditor-empty' })
  const response = await handleAppAgentRequest(
    postRequest({ message: 'Hi', clientMessageId: 'msg-1' }),
    harness.deps,
  )
  assertEquals(response.status, 403)
  assertEquals((await readJson(response)).code, 'not_approved')
  assertEquals(harness.turns.length, 0)
})

Deno.test('an admin caller is scoped to every customer', async () => {
  const harness = createHarness({ authUserId: 'user-admin' })
  const response = await handleAppAgentRequest(
    postRequest({ message: 'Hi', clientMessageId: 'msg-1' }),
    harness.deps,
  )

  assertEquals(response.status, 200)
  assertEquals(harness.scopes[0].accessRole, 'admin')
  assertEquals(
    [...harness.scopes[0].allowedCustomerIds],
    ['cust-1', 'cust-2', 'cust-3'],
  )
})

Deno.test('send returns the agent reply and persists both turns', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const response = await handleAppAgentRequest(
    postRequest({ message: '  How is the flock?  ', clientMessageId: 'msg-1' }),
    harness.deps,
  )

  assertEquals(response.status, 200)
  const payload = await readJson(response)
  assertEquals(payload.reply, 'Hatchability is 84%.')
  assertEquals(payload.language, 'en')
  assertEquals(payload.createdAt, NOW)
  assert(typeof payload.conversationId === 'string')
  assert(typeof payload.userTurnId === 'string')
  assert(typeof payload.replyTurnId === 'string')

  const rows = turnRows(harness.db)
  assertEquals(rows.length, 2)
  const inbound = rows.find((row) => row.direction === 'inbound')
  const outbound = rows.find((row) => row.direction === 'outbound')
  assertEquals(inbound?.text, 'How is the flock?')
  assertEquals(inbound?.telegram_update_id, 'app:msg-1')
  assertEquals(outbound?.text, 'Hatchability is 84%.')
  assertEquals(outbound?.reply_to_turn_id, inbound?.id)
  assertEquals(outbound?.provider_response_id, 'resp-1')

  // The app staff link and the single app conversation were created.
  assertEquals(harness.db.tables.telegram_staff_links.length, 1)
  assertEquals(harness.db.tables.telegram_staff_links[0].channel, 'app')
  assertEquals(
    harness.db.tables.telegram_staff_links[0].app_user_id,
    'user-customer',
  )
  assertEquals(harness.db.tables.agent_conversations.length, 1)
  assertEquals(
    harness.db.tables.agent_conversations[0].telegram_chat_id,
    'app',
  )
})

Deno.test('replaying the same clientMessageId does not call the model twice', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const first = await handleAppAgentRequest(
    postRequest({ message: 'Hello', clientMessageId: 'msg-dup' }),
    harness.deps,
  )
  const second = await handleAppAgentRequest(
    postRequest({ message: 'Hello', clientMessageId: 'msg-dup' }),
    harness.deps,
  )

  assertEquals(first.status, 200)
  assertEquals(second.status, 200)
  assertEquals(harness.turns.length, 1)
  const firstPayload = await readJson(first)
  const secondPayload = await readJson(second)
  assertEquals(secondPayload.replyTurnId, firstPayload.replyTurnId)
  assertEquals(secondPayload.userTurnId, firstPayload.userTurnId)
  assertEquals(secondPayload.reply, firstPayload.reply)
  assertEquals(turnRows(harness.db).length, 2)
})

Deno.test('history returns only current-epoch turns, oldest first', async () => {
  const db = seedDatabase()
  const harness = createHarness({ db, authUserId: 'user-customer' })
  db.tables.telegram_staff_links.push({
    id: 'app-user-customer',
    channel: 'app',
    app_user_id: 'user-customer',
    telegram_chat_id: 'app',
    status: 'allowed',
    access_role: 'customer',
    customer_id: 'cust-1',
  })
  db.tables.agent_conversations.push({
    id: 'conv-1',
    staff_link_id: 'app-user-customer',
    telegram_chat_id: 'app',
    state_version: 1,
    context_epoch: 2,
  })
  db.tables.agent_conversation_turns.push(
    {
      id: 'old-1',
      conversation_id: 'conv-1',
      direction: 'inbound',
      context_epoch: 1,
      text: 'stale question',
      language: 'en',
      created_at: '2026-08-14T09:00:00.000Z',
    },
    {
      id: 'new-2',
      conversation_id: 'conv-1',
      direction: 'outbound',
      context_epoch: 2,
      text: 'second',
      language: 'en',
      created_at: '2026-08-14T09:31:00.000Z',
    },
    {
      id: 'new-1',
      conversation_id: 'conv-1',
      direction: 'inbound',
      context_epoch: 2,
      text: 'first',
      language: 'en',
      created_at: '2026-08-14T09:30:00.000Z',
    },
  )

  const response = await handleAppAgentRequest(
    postRequest({ action: 'history' }),
    harness.deps,
  )

  assertEquals(response.status, 200)
  const payload = await readJson(response)
  assertEquals(payload.conversationId, 'conv-1')
  const messages = payload.messages as Record<string, unknown>[]
  assertEquals(messages.length, 2)
  assertEquals(messages[0].id, 'new-1')
  assertEquals(messages[0].role, 'user')
  assertEquals(messages[0].text, 'first')
  assertEquals(messages[1].id, 'new-2')
  assertEquals(messages[1].role, 'assistant')
})

Deno.test('history rejects an out-of-range limit', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'history', limit: 500 }),
    harness.deps,
  )
  assertEquals(response.status, 400)
  assertEquals((await readJson(response)).code, 'invalid_request')
})

Deno.test('reset bumps the context epoch and hides earlier turns', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  await handleAppAgentRequest(
    postRequest({ message: 'Hello', clientMessageId: 'msg-1' }),
    harness.deps,
  )

  const before = await handleAppAgentRequest(
    postRequest({ action: 'history' }),
    harness.deps,
  )
  assertEquals(((await readJson(before)).messages as unknown[]).length, 2)

  const reset = await handleAppAgentRequest(
    postRequest({ action: 'reset' }),
    harness.deps,
  )
  assertEquals(reset.status, 200)
  const resetPayload = await readJson(reset)
  assertEquals(resetPayload.cleared, true)
  assertEquals(harness.db.tables.agent_conversations[0].context_epoch, 2)
  assertEquals(
    harness.db.tables.agent_conversations[0].pending_action_json,
    null,
  )
  assertEquals(harness.db.tables.agent_conversations[0].active_visit_id, null)

  const after = await handleAppAgentRequest(
    postRequest({ action: 'history' }),
    harness.deps,
  )
  assertEquals(((await readJson(after)).messages as unknown[]).length, 0)
  // The prior turns are preserved in the database, only hidden.
  assertEquals(turnRows(harness.db).length, 2)
})

Deno.test('the 21st send inside the window is rate limited', async () => {
  const db = seedDatabase()
  const harness = createHarness({ db, authUserId: 'user-customer' })
  db.tables.telegram_staff_links.push({
    id: 'app-user-customer',
    channel: 'app',
    app_user_id: 'user-customer',
    telegram_chat_id: 'app',
    status: 'allowed',
    access_role: 'customer',
    customer_id: 'cust-1',
  })
  db.tables.agent_conversations.push({
    id: 'conv-1',
    staff_link_id: 'app-user-customer',
    telegram_chat_id: 'app',
    state_version: 1,
    context_epoch: 1,
  })
  for (let index = 0; index < 20; index += 1) {
    db.tables.agent_conversation_turns.push({
      id: `burst-${index}`,
      conversation_id: 'conv-1',
      direction: 'inbound',
      context_epoch: 1,
      text: 'burst',
      language: 'en',
      telegram_update_id: `app:burst-${index}`,
      created_at: '2026-08-14T09:58:00.000Z',
    })
  }

  const response = await handleAppAgentRequest(
    postRequest({ message: 'One more', clientMessageId: 'msg-over' }),
    harness.deps,
  )

  assertEquals(response.status, 429)
  assertEquals((await readJson(response)).code, 'rate_limited')
  assertEquals(harness.turns.length, 0)
})

Deno.test('sends older than the rate-limit window do not count', async () => {
  const db = seedDatabase()
  const harness = createHarness({ db, authUserId: 'user-customer' })
  db.tables.telegram_staff_links.push({
    id: 'app-user-customer',
    channel: 'app',
    app_user_id: 'user-customer',
    telegram_chat_id: 'app',
    status: 'allowed',
    access_role: 'customer',
    customer_id: 'cust-1',
  })
  db.tables.agent_conversations.push({
    id: 'conv-1',
    staff_link_id: 'app-user-customer',
    telegram_chat_id: 'app',
    state_version: 1,
    context_epoch: 1,
  })
  for (let index = 0; index < 20; index += 1) {
    db.tables.agent_conversation_turns.push({
      id: `old-${index}`,
      conversation_id: 'conv-1',
      direction: 'inbound',
      context_epoch: 1,
      text: 'old',
      language: 'en',
      telegram_update_id: `app:old-${index}`,
      created_at: '2026-08-14T09:00:00.000Z',
    })
  }

  const response = await handleAppAgentRequest(
    postRequest({ message: 'One more', clientMessageId: 'msg-ok' }),
    harness.deps,
  )

  assertEquals(response.status, 200)
  assertEquals(harness.turns.length, 1)
})

Deno.test('a provider failure maps to 502 agent_unavailable', async () => {
  const harness = createHarness({
    authUserId: 'user-customer',
    turn: () => ({ status: 'provider_unavailable', toolCallCount: 0 }),
  })
  const response = await handleAppAgentRequest(
    postRequest({ message: 'Hello', clientMessageId: 'msg-1' }),
    harness.deps,
  )

  assertEquals(response.status, 502)
  assertEquals((await readJson(response)).code, 'agent_unavailable')
  // The inbound turn is stored; no reply row exists.
  assertEquals(turnRows(harness.db).length, 1)
})

Deno.test('a thrown provider error maps to 502 agent_unavailable', async () => {
  const harness = createHarness({
    authUserId: 'user-customer',
    turn: () => {
      throw new Error('boom')
    },
  })
  const response = await handleAppAgentRequest(
    postRequest({ message: 'Hello', clientMessageId: 'msg-1' }),
    harness.deps,
  )
  assertEquals(response.status, 502)
  assertEquals((await readJson(response)).code, 'agent_unavailable')
})

Deno.test('a blank or oversized message is rejected', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const blank = await handleAppAgentRequest(
    postRequest({ message: '   ', clientMessageId: 'msg-1' }),
    harness.deps,
  )
  assertEquals(blank.status, 400)
  assertEquals((await readJson(blank)).code, 'invalid_request')

  const oversized = await handleAppAgentRequest(
    postRequest({ message: 'x'.repeat(4001), clientMessageId: 'msg-2' }),
    harness.deps,
  )
  assertEquals(oversized.status, 400)
  assertEquals(harness.turns.length, 0)
})

Deno.test('an unknown action is rejected', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'delete' }),
    harness.deps,
  )
  assertEquals(response.status, 400)
  assertEquals((await readJson(response)).code, 'invalid_request')
})

Deno.test('attachment and audio fields are rejected because the door is text only', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  for (const field of ['attachment', 'audio', 'photo', 'fileData']) {
    const response = await handleAppAgentRequest(
      postRequest({
        message: 'Hello',
        clientMessageId: 'msg-1',
        [field]: 'data',
      }),
      harness.deps,
    )
    assertEquals(response.status, 400)
    assertEquals((await readJson(response)).code, 'invalid_request')
  }
  assertEquals(harness.turns.length, 0)
})

Deno.test('malformed JSON is rejected before authentication work', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const response = await handleAppAgentRequest(
    new Request('https://example.test', {
      method: 'POST',
      headers: { Authorization: 'Bearer token-abc' },
      body: 'not-json',
    }),
    harness.deps,
  )
  assertEquals(response.status, 400)
  assertEquals((await readJson(response)).code, 'invalid_request')
})

Deno.test('the model only receives current-epoch history, oldest first', async () => {
  const db = seedDatabase()
  const harness = createHarness({ db, authUserId: 'user-customer' })
  db.tables.telegram_staff_links.push({
    id: 'app-user-customer',
    channel: 'app',
    app_user_id: 'user-customer',
    telegram_chat_id: 'app',
    status: 'allowed',
    access_role: 'customer',
    customer_id: 'cust-1',
  })
  db.tables.agent_conversations.push({
    id: 'conv-1',
    staff_link_id: 'app-user-customer',
    telegram_chat_id: 'app',
    state_version: 1,
    context_epoch: 2,
  })
  db.tables.agent_conversation_turns.push(
    {
      id: 'stale',
      conversation_id: 'conv-1',
      direction: 'inbound',
      context_epoch: 1,
      turn_index: 1,
      text: 'stale',
      created_at: '2026-08-14T09:00:00.000Z',
    },
    {
      id: 'live-in',
      conversation_id: 'conv-1',
      direction: 'inbound',
      context_epoch: 2,
      turn_index: 1,
      text: 'live question',
      created_at: '2026-08-14T09:30:00.000Z',
    },
    {
      id: 'live-out',
      conversation_id: 'conv-1',
      direction: 'outbound',
      context_epoch: 2,
      turn_index: 1,
      text: 'live answer',
      created_at: '2026-08-14T09:31:00.000Z',
    },
  )

  await handleAppAgentRequest(
    postRequest({ message: 'Follow up', clientMessageId: 'msg-2' }),
    harness.deps,
  )

  assertEquals(harness.turns.length, 1)
  assertEquals(harness.turns[0].conversationContextEpoch, 2)
  assertEquals(harness.turns[0].conversationTurnIndex, 2)
  assertEquals(
    harness.turns[0].recentTurns.map((turn) => turn.text),
    ['live question', 'live answer'],
  )
})

Deno.test('send with audioBase64 transcribes, stores the transcript, and returns audio', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.resolve('What is the hatch rate?'),
    synthesizeSpeech: (_text) => Promise.resolve('c3ludGhlc2l6ZWQ='),
  })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-1' }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  const body = await response.json()
  assertEquals(body.reply, 'Hatchability is 84%.')
  assertEquals(body.transcript, 'What is the hatch rate?')
  assertEquals(body.audioBase64, 'c3ludGhlc2l6ZWQ=')
  assertEquals(harness.transcribeCalls, ['aGVsbG8='])
  assertEquals(harness.synthesizeCalls, ['Hatchability is 84%.'])

  const stored = harness.db.tables.agent_conversation_turns.find(
    (turn) => turn.direction === 'inbound',
  )
  assertEquals(stored?.text, 'What is the hatch rate?')
})

Deno.test('send with audioBase64 returns text-only when TTS fails', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.resolve('Question'),
    synthesizeSpeech: (_text) => Promise.reject(new Error('tts down')),
  })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-2' }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  const body = await response.json()
  assertEquals(body.reply, 'Hatchability is 84%.')
  assert(!('audioBase64' in body))
})

Deno.test('send with audioBase64 fails when voice is not configured', async () => {
  const harness = createHarness()
  const response = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-3' }),
    harness.deps,
  )
  assertEquals(response.status, 502)
  const body = await response.json()
  assertEquals(body.code, 'agent_unavailable')
})

Deno.test('send rejects an empty audioBase64', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.resolve('unused'),
  })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: '', clientMessageId: 'voice-4' }),
    harness.deps,
  )
  assertEquals(response.status, 400)
  const body = await response.json()
  assertEquals(body.code, 'invalid_request')
  assertEquals(harness.transcribeCalls, [])
})

Deno.test('send with audioBase64 fails when transcription throws', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.reject(new Error('whisper down')),
  })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-5' }),
    harness.deps,
  )
  assertEquals(response.status, 502)
  const body = await response.json()
  assertEquals(body.code, 'agent_unavailable')
})

Deno.test('replaying a voice send returns stored transcript and fresh audio without re-transcribing', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.resolve('What is the hatch rate?'),
    synthesizeSpeech: (_text) => Promise.resolve('YXVkaW8x'),
  })
  const first = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-6' }),
    harness.deps,
  )
  assertEquals(first.status, 200)
  assertEquals(harness.transcribeCalls.length, 1)

  const second = await handleAppAgentRequest(
    postRequest({ action: 'send', audioBase64: 'aGVsbG8=', clientMessageId: 'voice-6' }),
    harness.deps,
  )
  assertEquals(second.status, 200)
  const body = await second.json()
  assertEquals(body.transcript, 'What is the hatch rate?')
  assertEquals(body.reply, 'Hatchability is 84%.')
  // No second transcription call — the replay short-circuits before Whisper.
  assertEquals(harness.transcribeCalls.length, 1)
  assertEquals(harness.synthesizeCalls.length, 2)
})
