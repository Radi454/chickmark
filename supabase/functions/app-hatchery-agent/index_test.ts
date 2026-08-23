import { assert, assertEquals } from '@std/assert'

import type { AgentScope } from '../telegram-hatchery-agent/agent_protocol.ts'
import type {
  AgentTurnInput,
  AgentTurnResult,
} from '../telegram-hatchery-agent/agent_runtime.ts'
import type { AgentProviderTelemetry } from '../telegram-hatchery-agent/agent_provider.ts'
import {
  type AppAgentAdminClient,
  type AppAgentDeps,
  handleAppAgentRequest,
  readAiConfig,
} from './index.ts'
import {
  createFakeAdminClient,
  createFakeDatabase,
  type FakeDatabase,
  sequentialIds,
} from './test_support.ts'
import { deriveConversationTitle } from './conversation_title.ts'

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

Deno.test('app conversation config uses OPENAI_TEXT_MODEL instead of extraction models', () => {
  const previous = new Map<string, string | undefined>([
    'AI_PROVIDER',
    'OPENROUTER_API_KEY',
    'OPENAI_API_KEY',
    'OPENAI_TEXT_MODEL',
    'OPENAI_MODEL',
    'AI_MODEL',
  ].map((name) => [name, Deno.env.get(name)]))
  Deno.env.set('AI_PROVIDER', 'openai')
  Deno.env.delete('OPENROUTER_API_KEY')
  Deno.env.set('OPENAI_API_KEY', 'test-openai-key')
  Deno.env.set('OPENAI_TEXT_MODEL', '  app-text-model  ')
  Deno.env.set('OPENAI_MODEL', 'extraction-model')
  Deno.env.set('AI_MODEL', 'legacy-shared-model')
  try {
    assertEquals(readAiConfig(), {
      provider: 'openai',
      apiKey: 'test-openai-key',
      model: 'app-text-model',
    })
  } finally {
    for (const [name, value] of previous) {
      if (value === undefined) Deno.env.delete(name)
      else Deno.env.set(name, value)
    }
  }
})

Deno.test('app conversation config resolves the OpenRouter primary and fallback models', () => {
  const previous = new Map<string, string | undefined>([
    'AI_PROVIDER',
    'OPENROUTER_API_KEY',
    'OPENAI_API_KEY',
    'OPENROUTER_MODEL',
    'OPENROUTER_FALLBACK_MODEL',
    'OPENROUTER_VISION_MODEL',
    'OPENROUTER_VISION_FALLBACK_MODEL',
    'AI_MODEL',
  ].map((name) => [name, Deno.env.get(name)]))
  Deno.env.set('AI_PROVIDER', 'openrouter')
  Deno.env.set('OPENROUTER_API_KEY', 'test-openrouter-key')
  Deno.env.delete('OPENAI_API_KEY')
  Deno.env.delete('OPENROUTER_MODEL')
  Deno.env.delete('OPENROUTER_FALLBACK_MODEL')
  Deno.env.delete('OPENROUTER_VISION_MODEL')
  Deno.env.delete('OPENROUTER_VISION_FALLBACK_MODEL')
  Deno.env.delete('AI_MODEL')
  try {
    assertEquals(readAiConfig(), {
      provider: 'openrouter',
      apiKey: 'test-openrouter-key',
      model: 'openai/gpt-oss-120b',
      fallbackModel: 'openai/gpt-oss-20b',
      visionModel: 'google/gemma-4-31b-it',
      visionFallbackModel: undefined,
    })

    Deno.env.set('OPENROUTER_MODEL', '  account/primary  ')
    Deno.env.set('OPENROUTER_FALLBACK_MODEL', '  account/fallback  ')
    Deno.env.set('OPENROUTER_VISION_MODEL', '  account/vision  ')
    Deno.env.set(
      'OPENROUTER_VISION_FALLBACK_MODEL',
      '  account/vision-fallback  ',
    )
    assertEquals(readAiConfig(), {
      provider: 'openrouter',
      apiKey: 'test-openrouter-key',
      model: 'account/primary',
      fallbackModel: 'account/fallback',
      visionModel: 'account/vision',
      visionFallbackModel: 'account/vision-fallback',
    })
  } finally {
    for (const [name, value] of previous) {
      if (value === undefined) Deno.env.delete(name)
      else Deno.env.set(name, value)
    }
  }
})

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
      conversation_seq: 1,
      text: 'stale question',
      language: 'en',
      created_at: '2026-08-14T09:00:00.000Z',
    },
    {
      id: 'new-2',
      conversation_id: 'conv-1',
      direction: 'outbound',
      context_epoch: 2,
      conversation_seq: 3,
      text: 'second',
      language: 'en',
      created_at: '2026-08-14T09:31:00.000Z',
    },
    {
      id: 'new-1',
      conversation_id: 'conv-1',
      direction: 'inbound',
      context_epoch: 2,
      conversation_seq: 2,
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

Deno.test('the model only receives finalized current-epoch history, in conversation_seq order', async () => {
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
  // The wall clocks deliberately disagree with conversation_seq: ordering by
  // created_at would hand the model the answer before the question.
  db.tables.agent_conversation_turns.push(
    {
      id: 'stale',
      conversation_id: 'conv-1',
      direction: 'inbound',
      context_epoch: 1,
      turn_index: 1,
      conversation_seq: 1,
      completion_status: 'finalized',
      text: 'stale',
      created_at: '2026-08-14T09:00:00.000Z',
    },
    {
      id: 'live-in',
      conversation_id: 'conv-1',
      direction: 'inbound',
      context_epoch: 2,
      turn_index: 1,
      conversation_seq: 2,
      completion_status: 'finalized',
      text: 'live question',
      created_at: '2026-08-14T09:31:00.000Z',
    },
    {
      id: 'live-out',
      conversation_id: 'conv-1',
      direction: 'outbound',
      context_epoch: 2,
      turn_index: 1,
      conversation_seq: 3,
      completion_status: 'finalized',
      text: 'live answer',
      created_at: '2026-08-14T09:30:00.000Z',
    },
    {
      id: 'live-pending',
      conversation_id: 'conv-1',
      direction: 'inbound',
      context_epoch: 2,
      turn_index: 2,
      conversation_seq: 4,
      completion_status: 'pending',
      text: 'half-heard voice turn',
      created_at: '2026-08-14T09:32:00.000Z',
    },
  )

  await handleAppAgentRequest(
    postRequest({ message: 'Follow up', clientMessageId: 'msg-2' }),
    harness.deps,
  )

  assertEquals(harness.turns.length, 1)
  assertEquals(harness.turns[0].conversationContextEpoch, 2)
  assertEquals(harness.turns[0].conversationTurnIndex, 3)
  assertEquals(
    harness.turns[0].recentTurns.map((turn) => turn.text),
    ['live question', 'live answer'],
  )
})

Deno.test('every stored app turn carries an allocated slot, channel and status', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })

  const response = await handleAppAgentRequest(
    postRequest({ message: 'Hello', clientMessageId: 'msg-slot' }),
    harness.deps,
  )

  assertEquals(response.status, 200)
  assertEquals(
    turnRows(harness.db).map((turn) => ({
      direction: turn.direction,
      turnIndex: turn.turn_index,
      conversationSeq: turn.conversation_seq,
      sourceChannel: turn.source_channel,
      completionStatus: turn.completion_status,
    })),
    [
      {
        direction: 'inbound',
        turnIndex: 1,
        conversationSeq: 1,
        sourceChannel: 'app_text',
        completionStatus: 'finalized',
      },
      {
        // The reply reuses its inbound turn_index and takes its own
        // conversation_seq.
        direction: 'outbound',
        turnIndex: 1,
        conversationSeq: 2,
        sourceChannel: 'app_text',
        completionStatus: 'finalized',
      },
    ],
  )
  assertEquals(
    harness.db.turnSlotCalls.map((call) => ({
      direction: call.p_direction,
      override: call.p_turn_index_override,
    })),
    [
      { direction: 'inbound', override: null },
      { direction: 'outbound', override: 1 },
    ],
  )
})

Deno.test('a failed turn-slot allocation stores nothing and never calls the model', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  harness.db.failing.add('allocate_agent_turn_slot')

  const response = await handleAppAgentRequest(
    postRequest({ message: 'Hello', clientMessageId: 'msg-slot-fail' }),
    harness.deps,
  )

  assertEquals(response.status, 500)
  assertEquals((await readJson(response)).code, 'server_error')
  assertEquals(harness.turns.length, 0)
  assertEquals(turnRows(harness.db).length, 0)
})

Deno.test('send with audioBase64 transcribes, stores the transcript, and returns audio', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.resolve('What is the hatch rate?'),
    synthesizeSpeech: (_text) => Promise.resolve('c3ludGhlc2l6ZWQ='),
  })
  const response = await handleAppAgentRequest(
    postRequest({
      action: 'send',
      audioBase64: 'aGVsbG8=',
      clientMessageId: 'voice-1',
    }),
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
    postRequest({
      action: 'send',
      audioBase64: 'aGVsbG8=',
      clientMessageId: 'voice-2',
    }),
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
    postRequest({
      action: 'send',
      audioBase64: 'aGVsbG8=',
      clientMessageId: 'voice-3',
    }),
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
    postRequest({
      action: 'send',
      audioBase64: '',
      clientMessageId: 'voice-4',
    }),
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
    postRequest({
      action: 'send',
      audioBase64: 'aGVsbG8=',
      clientMessageId: 'voice-5',
    }),
    harness.deps,
  )
  assertEquals(response.status, 502)
  const body = await response.json()
  assertEquals(body.code, 'agent_unavailable')
})

Deno.test('a voice send response matches the shared client/server contract fixture', async () => {
  // Both this suite and assistant_chat_service_test.dart (Dart) read the same
  // physical voice_contract_fixture.json, so a field rename on either side of
  // the wire without updating the fixture fails a test in that language too —
  // not a full drift guarantee, but it pins the field-name list to one source
  // of truth instead of two independently-maintained fakes agreeing by luck.
  const fixtureUrl = new URL('./voice_contract_fixture.json', import.meta.url)
  const fixture = JSON.parse(await Deno.readTextFile(fixtureUrl)) as {
    request: Record<string, unknown>
    response: Record<string, unknown>
  }

  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.resolve('What is the hatch rate?'),
    synthesizeSpeech: (_text) => Promise.resolve('c3ludGhlc2l6ZWQ='),
  })
  const response = await handleAppAgentRequest(
    postRequest({
      action: fixture.request.action as string,
      audioBase64: fixture.request.audioBase64 as string,
      clientMessageId: fixture.request.clientMessageId as string,
    }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  const body = await readJson(response)

  const expectedKeys = Object.keys(fixture.response).sort()
  const actualKeys = Object.keys(body).sort()
  assertEquals(actualKeys, expectedKeys)
})

Deno.test('replaying a voice send returns stored transcript and fresh audio without re-transcribing', async () => {
  const harness = createHarness({
    transcribeAudio: (_audio) => Promise.resolve('What is the hatch rate?'),
    synthesizeSpeech: (_text) => Promise.resolve('YXVkaW8x'),
  })
  const first = await handleAppAgentRequest(
    postRequest({
      action: 'send',
      audioBase64: 'aGVsbG8=',
      clientMessageId: 'voice-6',
    }),
    harness.deps,
  )
  assertEquals(first.status, 200)
  assertEquals(harness.transcribeCalls.length, 1)

  const second = await handleAppAgentRequest(
    postRequest({
      action: 'send',
      audioBase64: 'aGVsbG8=',
      clientMessageId: 'voice-6',
    }),
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

// --- Multi-conversation support -------------------------------------------

const VALID_CONVERSATION_KEY_A = 'app:11111111-1111-4111-8111-111111111111'
const VALID_CONVERSATION_KEY_B = 'app:22222222-2222-4222-8222-222222222222'

Deno.test('a missing conversationId resolves to the legacy app conversation', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'history' }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  const body = await readJson(response)
  assertEquals(body.conversationKey, 'app')
})

Deno.test('a well-formed app:<uuid v4> conversationId opens its own conversation row', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const response = await handleAppAgentRequest(
    postRequest({
      conversationId: VALID_CONVERSATION_KEY_A,
      message: 'hi',
      clientMessageId: 'valid-uuid',
    }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  const body = await readJson(response)
  assertEquals(body.conversationKey, VALID_CONVERSATION_KEY_A)
  assertEquals(harness.db.tables.agent_conversations.length, 1)
  assertEquals(
    harness.db.tables.agent_conversations[0].telegram_chat_id,
    VALID_CONVERSATION_KEY_A,
  )
})

Deno.test('an invalid conversationId is rejected on send, history, and reset', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const cases: Array<[string, Record<string, unknown>]> = [
    ['send', {
      action: 'send',
      conversationId: 'not-a-valid-key',
      message: 'hi',
      clientMessageId: 'bad-send',
    }],
    ['history', { action: 'history', conversationId: 'not-a-valid-key' }],
    ['reset', { action: 'reset', conversationId: 'not-a-valid-key' }],
  ]
  for (const [action, body] of cases) {
    const response = await handleAppAgentRequest(
      postRequest(body),
      harness.deps,
    )
    assertEquals(response.status, 400, action)
    const payload = await readJson(response)
    assertEquals(payload.code, 'invalid_request', action)
    assertEquals(payload.error, 'conversationId is invalid.', action)
  }
})

Deno.test('conversationId must be exactly "app" or a lowercase app:<uuid v4>', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const invalidKeys = [
    'app:33333333-3333-3333-8333-333333333333', // version nibble is not 4
    'app:33333333-3333-4333-0333-333333333333', // variant nibble not in 89ab
    'app:33333333-3333-4333-8333-33333333333', // too short
    'App', // wrong case
    'app:11111111-1111-4111-8111-111111111111'.toUpperCase(),
    'telegram:123',
  ]
  for (const conversationId of invalidKeys) {
    const response = await handleAppAgentRequest(
      postRequest({ action: 'history', conversationId }),
      harness.deps,
    )
    assertEquals(response.status, 400, conversationId)
  }
})

Deno.test('recentTurns and history do not leak across two app conversations for the same caller', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })

  await handleAppAgentRequest(
    postRequest({
      conversationId: VALID_CONVERSATION_KEY_A,
      message: 'Hello from A',
      clientMessageId: 'a-1',
    }),
    harness.deps,
  )
  await handleAppAgentRequest(
    postRequest({
      conversationId: VALID_CONVERSATION_KEY_B,
      message: 'Hello from B',
      clientMessageId: 'b-1',
    }),
    harness.deps,
  )

  // Two distinct conversation rows were used, and B's model context carries
  // nothing from A even though both belong to the same caller.
  assertEquals(harness.turns.length, 2)
  assertEquals(harness.turns[1].recentTurns, [])
  assert(harness.turns[0].conversationId !== harness.turns[1].conversationId)
  assertEquals(harness.db.tables.agent_conversations.length, 2)

  const historyA = await readJson(
    await handleAppAgentRequest(
      postRequest({
        action: 'history',
        conversationId: VALID_CONVERSATION_KEY_A,
      }),
      harness.deps,
    ),
  )
  const historyB = await readJson(
    await handleAppAgentRequest(
      postRequest({
        action: 'history',
        conversationId: VALID_CONVERSATION_KEY_B,
      }),
      harness.deps,
    ),
  )
  assertEquals(historyA.conversationKey, VALID_CONVERSATION_KEY_A)
  assertEquals(historyB.conversationKey, VALID_CONVERSATION_KEY_B)
  const textsA = (historyA.messages as Record<string, unknown>[]).map((m) =>
    m.text
  )
  const textsB = (historyB.messages as Record<string, unknown>[]).map((m) =>
    m.text
  )
  assert(textsA.includes('Hello from A'))
  assert(!textsA.includes('Hello from B'))
  assert(textsB.includes('Hello from B'))
  assert(!textsB.includes('Hello from A'))
})

Deno.test('history maps source_channel to a voice/text source field', async () => {
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
    id: 'conv-source',
    staff_link_id: 'app-user-customer',
    telegram_chat_id: 'app',
    state_version: 1,
    context_epoch: 1,
  })
  db.tables.agent_conversation_turns.push(
    {
      id: 'voice-turn',
      conversation_id: 'conv-source',
      direction: 'inbound',
      context_epoch: 1,
      conversation_seq: 1,
      text: 'spoken message',
      language: 'en',
      source_channel: 'realtime_voice',
      created_at: '2026-08-14T09:00:00.000Z',
    },
    {
      id: 'text-turn',
      conversation_id: 'conv-source',
      direction: 'inbound',
      context_epoch: 1,
      conversation_seq: 2,
      text: 'typed message',
      language: 'en',
      source_channel: 'app_text',
      created_at: '2026-08-14T09:01:00.000Z',
    },
    {
      id: 'unset-turn',
      conversation_id: 'conv-source',
      direction: 'inbound',
      context_epoch: 1,
      conversation_seq: 3,
      text: 'no channel recorded',
      language: 'en',
      created_at: '2026-08-14T09:02:00.000Z',
    },
  )

  const response = await handleAppAgentRequest(
    postRequest({ action: 'history' }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  const body = await readJson(response)
  const messages = body.messages as Record<string, unknown>[]
  assertEquals(messages.map((m) => m.source), ['voice', 'text', 'text'])
})

Deno.test('the first message sets the conversation title once and later messages do not overwrite it', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const firstMessage = '  How is the flock doing today?  '
  await handleAppAgentRequest(
    postRequest({ message: firstMessage, clientMessageId: 'title-1' }),
    harness.deps,
  )
  const expectedTitle = deriveConversationTitle(firstMessage)
  assertEquals(
    harness.db.tables.agent_conversations[0].title,
    expectedTitle,
  )

  await handleAppAgentRequest(
    postRequest({
      message: 'A completely different follow-up message',
      clientMessageId: 'title-2',
    }),
    harness.deps,
  )
  assertEquals(harness.db.tables.agent_conversations.length, 1)
  assertEquals(
    harness.db.tables.agent_conversations[0].title,
    expectedTitle,
  )
})

Deno.test('an Arabic first message derives an Arabic conversation title', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const arabicMessage = 'ما هي نسبة الفقس اليوم؟'
  await handleAppAgentRequest(
    postRequest({ message: arabicMessage, clientMessageId: 'title-ar' }),
    harness.deps,
  )
  assertEquals(
    harness.db.tables.agent_conversations[0].title,
    deriveConversationTitle(arabicMessage),
  )
})

Deno.test(
  "conversations lists the caller's own rows, sorted by updatedAt desc, omitting placeholders",
  async () => {
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
    db.tables.agent_conversations.push(
      {
        id: 'conv-app',
        staff_link_id: 'app-user-customer',
        telegram_chat_id: 'app',
        title: null,
        created_at: '2026-08-10T00:00:00.000Z',
        updated_at: '2026-08-10T00:00:00.000Z',
      },
      {
        id: 'conv-titled',
        staff_link_id: 'app-user-customer',
        telegram_chat_id: VALID_CONVERSATION_KEY_A,
        title: 'How is the flock',
        created_at: '2026-08-12T00:00:00.000Z',
        updated_at: '2026-08-15T00:00:00.000Z',
      },
      {
        // Opened but never used and never titled: omitted from the list.
        id: 'conv-placeholder',
        staff_link_id: 'app-user-customer',
        telegram_chat_id: VALID_CONVERSATION_KEY_B,
        title: null,
        created_at: '2026-08-13T00:00:00.000Z',
        updated_at: '2026-08-13T00:00:00.000Z',
      },
      {
        // A different caller entirely: never returned to this caller.
        id: 'conv-other-user',
        staff_link_id: 'someone-else',
        telegram_chat_id: 'app',
        title: 'Not mine',
        created_at: '2026-08-14T00:00:00.000Z',
        updated_at: '2026-08-16T00:00:00.000Z',
      },
    )
    db.tables.agent_conversation_turns.push({
      id: 'turn-titled-1',
      conversation_id: 'conv-titled',
      conversation_seq: 1,
      text: 'x'.repeat(160),
      created_at: '2026-08-15T00:00:00.000Z',
    })

    const response = await handleAppAgentRequest(
      postRequest({ action: 'conversations' }),
      harness.deps,
    )
    assertEquals(response.status, 200)
    const body = await readJson(response)
    const conversations = body.conversations as Record<string, unknown>[]
    assertEquals(
      conversations.map((c) => c.conversationKey),
      [VALID_CONVERSATION_KEY_A, 'app'],
    )

    const titled = conversations[0]
    assertEquals(titled.title, 'How is the flock')
    assertEquals((titled.lastMessageText as string).length, 140)
    assertEquals(titled.lastMessageAt, '2026-08-15T00:00:00.000Z')

    const legacy = conversations[1]
    assertEquals(legacy.title, null)
    assertEquals(legacy.lastMessageText, null)
    assertEquals(legacy.lastMessageAt, null)
  },
)

Deno.test('conversations validates the limit parameter and honors it', async () => {
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
  db.tables.agent_conversations.push(
    {
      id: 'conv-1',
      staff_link_id: 'app-user-customer',
      telegram_chat_id: 'app',
      title: 'First',
      created_at: '2026-08-10T00:00:00.000Z',
      updated_at: '2026-08-10T00:00:00.000Z',
    },
    {
      id: 'conv-2',
      staff_link_id: 'app-user-customer',
      telegram_chat_id: VALID_CONVERSATION_KEY_A,
      title: 'Second',
      created_at: '2026-08-11T00:00:00.000Z',
      updated_at: '2026-08-17T00:00:00.000Z',
    },
  )

  const tooLarge = await handleAppAgentRequest(
    postRequest({ action: 'conversations', limit: 101 }),
    harness.deps,
  )
  assertEquals(tooLarge.status, 400)
  assertEquals((await readJson(tooLarge)).code, 'invalid_request')

  const tooSmall = await handleAppAgentRequest(
    postRequest({ action: 'conversations', limit: 0 }),
    harness.deps,
  )
  assertEquals(tooSmall.status, 400)

  const nonInteger = await handleAppAgentRequest(
    postRequest({ action: 'conversations', limit: 1.5 }),
    harness.deps,
  )
  assertEquals(nonInteger.status, 400)

  const limited = await handleAppAgentRequest(
    postRequest({ action: 'conversations', limit: 1 }),
    harness.deps,
  )
  assertEquals(limited.status, 200)
  const limitedBody = await readJson(limited)
  const limitedConversations = limitedBody.conversations as Record<
    string,
    unknown
  >[]
  assertEquals(limitedConversations.length, 1)
  assertEquals(
    limitedConversations[0].conversationKey,
    VALID_CONVERSATION_KEY_A,
  )
})

// --- Reviewer findings regression tests ------------------------------------

// F1: only `send` may durably create a conversation row.

Deno.test('history for a conversation that was never sent to returns empty without creating a row', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const response = await handleAppAgentRequest(
    postRequest({
      action: 'history',
      conversationId: VALID_CONVERSATION_KEY_A,
    }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  const body = await readJson(response)
  assertEquals(body.conversationId, null)
  assertEquals(body.conversationKey, VALID_CONVERSATION_KEY_A)
  assertEquals(body.messages, [])
  assertEquals(harness.db.tables.agent_conversations.length, 0)
})

Deno.test('history still validates the limit even for a conversation that does not exist yet', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const response = await handleAppAgentRequest(
    postRequest({
      action: 'history',
      conversationId: VALID_CONVERSATION_KEY_A,
      limit: 500,
    }),
    harness.deps,
  )
  assertEquals(response.status, 400)
  assertEquals((await readJson(response)).code, 'invalid_request')
  assertEquals(harness.db.tables.agent_conversations.length, 0)
})

Deno.test('reset for a conversation that was never sent to is a no-op that creates no row', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'reset', conversationId: VALID_CONVERSATION_KEY_A }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  const body = await readJson(response)
  assertEquals(body, { cleared: true })
  assertEquals(harness.db.tables.agent_conversations.length, 0)
})

Deno.test('a missing conversationId resolving to history still creates no legacy row', async () => {
  // The regression this closes: opening the app (which always probes
  // `history` for the legacy 'app' conversation) used to durably create the
  // 'app' row on every cold start, even for a caller who never sent anything.
  const harness = createHarness({ authUserId: 'user-customer' })
  const response = await handleAppAgentRequest(
    postRequest({ action: 'history' }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  const body = await readJson(response)
  assertEquals(body.conversationId, null)
  assertEquals(body.conversationKey, 'app')
  assertEquals(harness.db.tables.agent_conversations.length, 0)
})

// F2: preview lookups must not be starved by one busy conversation.

Deno.test(
  'conversation previews are not starved when one conversation has far more turns than others',
  async () => {
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
    db.tables.agent_conversations.push(
      {
        id: 'conv-busy',
        staff_link_id: 'app-user-customer',
        telegram_chat_id: 'app',
        title: 'Busy',
        created_at: '2026-08-10T00:00:00.000Z',
        updated_at: '2026-08-17T00:00:00.000Z',
      },
      {
        id: 'conv-quiet',
        staff_link_id: 'app-user-customer',
        telegram_chat_id: VALID_CONVERSATION_KEY_A,
        title: 'Quiet',
        created_at: '2026-08-09T00:00:00.000Z',
        updated_at: '2026-08-16T00:00:00.000Z',
      },
    )
    // One long-running conversation's turns alone exceed the old global
    // `.limit(conversationIds.length * 10)` window (25 > 2 * 10): under the
    // old single-query-across-every-conversation approach, this conversation
    // fills the entire window and the quiet conversation's one turn never
    // gets fetched.
    for (let seq = 1; seq <= 25; seq += 1) {
      db.tables.agent_conversation_turns.push({
        id: `busy-${seq}`,
        conversation_id: 'conv-busy',
        conversation_seq: seq,
        text: `busy message ${seq}`,
        created_at: '2026-08-17T00:00:00.000Z',
      })
    }
    db.tables.agent_conversation_turns.push({
      id: 'quiet-1',
      conversation_id: 'conv-quiet',
      conversation_seq: 1,
      text: 'quiet single message',
      created_at: '2026-08-16T00:00:00.000Z',
    })

    const response = await handleAppAgentRequest(
      postRequest({ action: 'conversations' }),
      harness.deps,
    )
    assertEquals(response.status, 200)
    const body = await readJson(response)
    const conversations = body.conversations as Record<string, unknown>[]
    const quiet = conversations.find(
      (c) => c.conversationKey === VALID_CONVERSATION_KEY_A,
    )
    assert(quiet, 'the quiet conversation must still be listed')
    assertEquals(quiet.lastMessageText, 'quiet single message')
    assertEquals(quiet.lastMessageAt, '2026-08-16T00:00:00.000Z')
  },
)

// F3: a turn write must bump the conversation's updated_at.

Deno.test('sending a message bumps the conversation updated_at', async () => {
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
    created_at: '2026-08-10T00:00:00.000Z',
    updated_at: '2026-08-10T00:00:00.000Z',
  })

  const response = await handleAppAgentRequest(
    postRequest({ message: 'Hello', clientMessageId: 'touch-1' }),
    harness.deps,
  )
  assertEquals(response.status, 200)
  assertEquals(harness.db.tables.agent_conversations[0].updated_at, NOW)
})

// F4: the send-rate budget belongs to the caller, not to one conversation.

Deno.test(
  'the send-rate budget is shared across every app conversation the caller owns — opening a fresh one does not reset it',
  async () => {
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
    db.tables.agent_conversations.push(
      {
        id: 'conv-a',
        staff_link_id: 'app-user-customer',
        telegram_chat_id: 'app',
        state_version: 1,
        context_epoch: 1,
      },
      {
        id: 'conv-b',
        staff_link_id: 'app-user-customer',
        telegram_chat_id: VALID_CONVERSATION_KEY_A,
        state_version: 1,
        context_epoch: 1,
      },
    )
    for (let index = 0; index < 20; index += 1) {
      db.tables.agent_conversation_turns.push({
        id: `burst-${index}`,
        conversation_id: 'conv-a',
        direction: 'inbound',
        context_epoch: 1,
        text: 'burst',
        language: 'en',
        telegram_update_id: `app:burst-${index}`,
        created_at: '2026-08-14T09:58:00.000Z',
      })
    }

    const response = await handleAppAgentRequest(
      postRequest({
        conversationId: VALID_CONVERSATION_KEY_A,
        message: 'One more, from a brand-new conversation',
        clientMessageId: 'msg-over-fresh',
      }),
      harness.deps,
    )

    assertEquals(response.status, 429)
    assertEquals((await readJson(response)).code, 'rate_limited')
    assertEquals(harness.turns.length, 0)
  },
)

Deno.test(
  'sends in a second conversation still count once the caller has room in the shared budget',
  async () => {
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
      id: 'conv-a',
      staff_link_id: 'app-user-customer',
      telegram_chat_id: 'app',
      state_version: 1,
      context_epoch: 1,
    })
    for (let index = 0; index < 5; index += 1) {
      db.tables.agent_conversation_turns.push({
        id: `light-${index}`,
        conversation_id: 'conv-a',
        direction: 'inbound',
        context_epoch: 1,
        text: 'light',
        language: 'en',
        telegram_update_id: `app:light-${index}`,
        created_at: '2026-08-14T09:58:00.000Z',
      })
    }

    const response = await handleAppAgentRequest(
      postRequest({
        conversationId: VALID_CONVERSATION_KEY_A,
        message: 'Room left in the budget',
        clientMessageId: 'msg-room',
      }),
      harness.deps,
    )
    assertEquals(response.status, 200)
    assertEquals(harness.turns.length, 1)
  },
)

// F8: idempotency lookups must be scoped to the conversation in hand.

Deno.test(
  "idempotency lookups are scoped per conversation: reusing a clientMessageId across conversations never leaks the other conversation's reply",
  async () => {
    const harness = createHarness({ authUserId: 'user-customer' })
    const first = await handleAppAgentRequest(
      postRequest({
        conversationId: VALID_CONVERSATION_KEY_A,
        message: 'Hello from A',
        clientMessageId: 'reused-id',
      }),
      harness.deps,
    )
    assertEquals(first.status, 200)

    const second = await handleAppAgentRequest(
      postRequest({
        conversationId: VALID_CONVERSATION_KEY_B,
        message: 'Hello from B',
        clientMessageId: 'reused-id',
      }),
      harness.deps,
    )

    // B's request is never answered with A's turn or reply: the global
    // telegram_update_id collision now surfaces as a clean failure instead
    // of a silent cross-conversation leak.
    assertEquals(second.status, 500)
    assertEquals(harness.turns.length, 1)
    assertEquals(turnRows(harness.db).length, 2)
  },
)

// F10: history must order by the allocator-issued conversation_seq, not by
// a wall clock that can disagree across runtimes.

Deno.test(
  'history orders by conversation_seq, surviving clock skew between runtimes',
  async () => {
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
      id: 'conv-skew',
      staff_link_id: 'app-user-customer',
      telegram_chat_id: 'app',
      state_version: 1,
      context_epoch: 1,
    })
    // The realtime runtime's wall clock trails the app runtime's:
    // conversation_seq (the allocator-issued, authoritative order) says
    // turn-a came before turn-b, but created_at says the opposite.
    db.tables.agent_conversation_turns.push(
      {
        id: 'turn-b',
        conversation_id: 'conv-skew',
        direction: 'inbound',
        context_epoch: 1,
        conversation_seq: 2,
        text: 'second by seq, earlier by clock',
        language: 'en',
        created_at: '2026-08-14T09:00:00.000Z',
      },
      {
        id: 'turn-a',
        conversation_id: 'conv-skew',
        direction: 'outbound',
        context_epoch: 1,
        conversation_seq: 1,
        text: 'first by seq, later by clock',
        language: 'en',
        created_at: '2026-08-14T09:05:00.000Z',
      },
    )

    const response = await handleAppAgentRequest(
      postRequest({ action: 'history' }),
      harness.deps,
    )
    assertEquals(response.status, 200)
    const body = await readJson(response)
    const messages = body.messages as Record<string, unknown>[]
    assertEquals(messages.map((m) => m.id), ['turn-a', 'turn-b'])
  },
)

// F13: the app door's own conversation-create path must set owner_profile_id,
// matching pip-realtime-session's create path.

Deno.test('a newly created conversation records owner_profile_id', async () => {
  const harness = createHarness({ authUserId: 'user-customer' })
  await handleAppAgentRequest(
    postRequest({ message: 'Hello', clientMessageId: 'owner-1' }),
    harness.deps,
  )
  assertEquals(
    harness.db.tables.agent_conversations[0].owner_profile_id,
    'user-customer',
  )
})
