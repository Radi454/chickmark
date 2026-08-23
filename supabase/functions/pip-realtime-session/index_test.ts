import { assert, assertEquals, assertNotEquals } from '@std/assert'

import { readPipRealtimeConfig } from './config.ts'
import { hashBindingToken } from './binding_token.ts'
import {
  handlePipRealtimeRequest,
  type PipRealtimeAdminClient,
  type PipRealtimeDeps,
} from './index.ts'
import {
  createFakeAdminClient,
  createFakeDatabase,
  type FakeDatabase,
  sequentialIds,
} from './test_support.ts'

const OWNER = 'owner-1'
const OTHER_OWNER = 'owner-2'
const ORG = 'org-1'
const CLOUD_RUN_URL = 'https://pip-sideband.example.run.app'
const START_AT = '2026-08-16T12:00:00.000Z'

const CONFIG = readPipRealtimeConfig((name) =>
  name === 'PIP_REALTIME_CLOUD_RUN_URL' ? CLOUD_RUN_URL : undefined
)

interface HarnessOptions {
  tables?: Record<string, Record<string, unknown>[]>
  profile?: Record<string, unknown>
  openAiApiKey?: string | null
  now?: string
  authUserId?: string | null
  mintFails?: boolean
  clockFails?: boolean
}

interface Harness {
  db: FakeDatabase
  deps: PipRealtimeDeps
  advanceSeconds(seconds: number): void
  post(
    body: Record<string, unknown>,
    options?: { token?: string | null },
  ): Promise<{ status: number; body: Record<string, unknown> }>
  mintCount(): number
  clockReads(): number
}

function createHarness(options: HarnessOptions = {}): Harness {
  const profile = {
    id: OWNER,
    role: 'customer',
    status: 'approved',
    customer_id: 'cust-1',
    organization_id: null,
    full_name: 'Test User',
    email: 'test@example.com',
    ...(options.profile ?? {}),
  }
  const db = createFakeDatabase({
    profiles: [profile],
    customers: [{ id: 'cust-1' }],
    auditor_customers: [],
    telegram_staff_links: [],
    agent_conversations: [],
    agent_realtime_runtime_control: [
      { id: 1, enabled: true, draining: false, force_stop_at: null },
    ],
    agent_realtime_sessions: [],
    agent_realtime_calls: [],
    agent_realtime_usage_seconds: [],
    agent_realtime_start_attempts: [],
    ...(options.tables ?? {}),
  })

  let current = new Date(options.now ?? START_AT)
  let mintCount = 0
  let clockReads = 0
  const authUserId = options.authUserId === undefined
    ? OWNER
    : options.authUserId

  const deps: PipRealtimeDeps = {
    adminClient: createFakeAdminClient(db, {
      // Every test drives the real code path: `now` is read from the database
      // clock via public.realtime_now(), not from the Edge Function's clock.
      realtime_now: () => {
        clockReads += 1
        if (options.clockFails) {
          return { data: null, error: { message: 'rpc failed', code: '57014' } }
        }
        return { data: current.toISOString(), error: null }
      },
    }) as unknown as PipRealtimeAdminClient,
    authenticate: (token) =>
      Promise.resolve(
        token === 'good-token' && authUserId ? { id: authUserId } : null,
      ),
    config: CONFIG,
    openAiApiKey: options.openAiApiKey === undefined
      ? 'sk-test'
      : options.openAiApiKey,
    mintClientSecret: (params) => {
      mintCount += 1
      if (options.mintFails) return Promise.reject(new Error('provider down'))
      assertEquals(params.apiKey, 'sk-test')
      return Promise.resolve({
        value: 'ek_ephemeral_value',
        expiresAt: new Date(
          current.getTime() + params.ttlSeconds * 1000,
        ).toISOString(),
      })
    },
    newId: sequentialIds('id'),
  }

  return {
    db,
    deps,
    advanceSeconds: (seconds) => {
      current = new Date(current.getTime() + seconds * 1000)
    },
    mintCount: () => mintCount,
    clockReads: () => clockReads,
    post: async (body, postOptions) => {
      const token = postOptions?.token === undefined
        ? 'good-token'
        : postOptions.token
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
      }
      if (token) headers.Authorization = `Bearer ${token}`
      const response = await handlePipRealtimeRequest(
        new Request('https://edge.test/pip-realtime-session', {
          method: 'POST',
          headers,
          body: JSON.stringify(body),
        }),
        deps,
      )
      const text = await response.text()
      return {
        status: response.status,
        body: text ? JSON.parse(text) as Record<string, unknown> : {},
      }
    },
  }
}

/** Frees the one-session slot so a test can start again without a new profile. */
function terminateSessions(db: FakeDatabase): void {
  for (const row of db.tables.agent_realtime_sessions ?? []) {
    row.state = 'ended'
    row.ended_at = START_AT
  }
}

function sessionRows(db: FakeDatabase): Record<string, unknown>[] {
  return db.tables.agent_realtime_sessions ?? []
}

function callRows(db: FakeDatabase): Record<string, unknown>[] {
  return db.tables.agent_realtime_calls ?? []
}

function attemptOutcomes(db: FakeDatabase): string[] {
  return (db.tables.agent_realtime_start_attempts ?? []).map((row) =>
    String(row.outcome)
  )
}

// ---------------------------------------------------------------------------
// Transport and identity
// ---------------------------------------------------------------------------

Deno.test('an unauthenticated caller is rejected', async () => {
  const harness = createHarness()
  const missing = await harness.post({ action: 'start' }, { token: null })
  assertEquals(missing.status, 401)
  assertEquals(missing.body.code, 'unauthenticated')

  const bad = await harness.post({ action: 'start' }, { token: 'stale-token' })
  assertEquals(bad.status, 401)
  assertEquals(bad.body.code, 'unauthenticated')
  assertEquals(sessionRows(harness.db).length, 0)
})

Deno.test('an unapproved caller is rejected', async () => {
  const harness = createHarness({ profile: { status: 'pending' } })
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 403)
  assertEquals(result.body.code, 'not_approved')
  assertEquals(sessionRows(harness.db).length, 0)
})

Deno.test('an unknown action is rejected before anything is written', async () => {
  const harness = createHarness()
  const result = await harness.post({ action: 'launch_missiles' })
  assertEquals(result.status, 400)
  assertEquals(attemptOutcomes(harness.db).length, 0)
})

Deno.test('Realtime is unavailable with no OPENAI_API_KEY, never a fallback', async () => {
  const harness = createHarness({ openAiApiKey: null })
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 503)
  assertEquals(result.body.code, 'realtime_unavailable')
  assertEquals(harness.mintCount(), 0)
  assertEquals(sessionRows(harness.db).length, 0)
})

// ---------------------------------------------------------------------------
// start: kill switch
// ---------------------------------------------------------------------------

Deno.test('the kill switch refuses new starts and records the attempt', async () => {
  const harness = createHarness({
    tables: {
      agent_realtime_runtime_control: [
        { id: 1, enabled: false, draining: false, force_stop_at: null },
      ],
    },
  })
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 503)
  assertEquals(result.body.code, 'kill_switch')
  assertEquals(attemptOutcomes(harness.db), ['kill_switch'])

  // Nothing Realtime was provisioned, and the shared conversation tables that
  // typed Pip (app-hatchery-agent) uses were never touched — typed Pip does not
  // read agent_realtime_runtime_control at all, so it keeps working.
  assertEquals(sessionRows(harness.db).length, 0)
  assertEquals(callRows(harness.db).length, 0)
  assertEquals(harness.db.tables.agent_conversations.length, 0)
  assertEquals(harness.mintCount(), 0)
})

Deno.test('draining refuses new starts', async () => {
  const harness = createHarness({
    tables: {
      agent_realtime_runtime_control: [
        { id: 1, enabled: true, draining: true, force_stop_at: null },
      ],
    },
  })
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 503)
  assertEquals(result.body.code, 'kill_switch')
})

Deno.test('a force_stop_at in the past refuses new starts', async () => {
  const harness = createHarness({
    tables: {
      agent_realtime_runtime_control: [
        {
          id: 1,
          enabled: true,
          draining: false,
          force_stop_at: '2026-08-16T11:00:00.000Z',
        },
      ],
    },
  })
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 503)
  assertEquals(result.body.code, 'kill_switch')
})

// ---------------------------------------------------------------------------
// start: happy path
// ---------------------------------------------------------------------------

Deno.test('start provisions a session, generation 1 and an ephemeral secret', async () => {
  const harness = createHarness()
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 200)

  assertEquals(result.body.generation, 1)
  assertEquals(result.body.sidebandUrl, CLOUD_RUN_URL)
  assertEquals(result.body.maxSessionSeconds, 600)
  assertEquals(result.body.setupDeadlineAt, '2026-08-16T12:01:00.000Z')
  assertEquals(result.body.sessionExpiresAt, '2026-08-16T12:10:00.000Z')
  const secret = result.body.clientSecret as Record<string, unknown>
  assertEquals(secret.value, 'ek_ephemeral_value')
  assertEquals(secret.expiresAt, '2026-08-16T12:01:00.000Z')

  const sessions = sessionRows(harness.db)
  assertEquals(sessions.length, 1)
  assertEquals(sessions[0].state, 'provisioning')
  assertEquals(sessions[0].owner_profile_id, OWNER)
  assertEquals(sessions[0].owner_staff_link_id, `app-${OWNER}`)
  assertEquals(sessions[0].active_generation, 1)
  assertEquals(sessions[0].authoritative_ready_at, undefined)

  const calls = callRows(harness.db)
  assertEquals(calls.length, 1)
  assertEquals(calls[0].generation, 1)
  assertEquals(calls[0].setup_state, 'provisioning')
  assertEquals(calls[0].openai_call_id, null)
  assertEquals(calls[0].setup_deadline_at, '2026-08-16T12:01:00.000Z')
  assertEquals(calls[0].fencing_token, 0)
  assertEquals(calls[0].lease_owner, undefined)

  assertEquals(attemptOutcomes(harness.db), ['accepted'])
  // The session shares the app user's single agent conversation.
  assertEquals(harness.db.tables.agent_conversations.length, 1)
  assertEquals(result.body.contextEpoch, 1)
})

Deno.test('a provider failure fails the session instead of leaking a half-start', async () => {
  const harness = createHarness({ mintFails: true })
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 502)
  assertEquals(result.body.code, 'provider_unavailable')
  assertEquals(sessionRows(harness.db)[0].state, 'failed')
  // The slot is released, so the user can retry.
  assertEquals(callRows(harness.db).length, 0)
})

// ---------------------------------------------------------------------------
// start: conversationId
// ---------------------------------------------------------------------------

const OTHER_CONVERSATION_ID = 'app:c0ffee00-0000-4000-8000-000000000001'

Deno.test('start with no conversationId defaults to the legacy app conversation', async () => {
  const harness = createHarness()
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 200)
  const conversations = harness.db.tables.agent_conversations
  assertEquals(conversations.length, 1)
  assertEquals(conversations[0].telegram_chat_id, 'app')
  assertEquals(conversations[0].id, result.body.conversationId)
})

Deno.test('start with conversationId "app" behaves exactly like the default', async () => {
  const harness = createHarness()
  const result = await harness.post({ action: 'start', conversationId: 'app' })
  assertEquals(result.status, 200)
  const conversations = harness.db.tables.agent_conversations
  assertEquals(conversations.length, 1)
  assertEquals(conversations[0].telegram_chat_id, 'app')
})

Deno.test('start with a valid app:<uuid v4> conversationId creates that conversation', async () => {
  const harness = createHarness()
  const result = await harness.post({
    action: 'start',
    conversationId: OTHER_CONVERSATION_ID,
  })
  assertEquals(result.status, 200)
  const conversations = harness.db.tables.agent_conversations
  assertEquals(conversations.length, 1)
  assertEquals(conversations[0].telegram_chat_id, OTHER_CONVERSATION_ID)
  assertEquals(conversations[0].id, result.body.conversationId)
})

Deno.test('start threads the conversationId key into an existing conversation lookup', async () => {
  const harness = createHarness({
    tables: {
      agent_conversations: [
        {
          id: 'existing-convo',
          staff_link_id: `app-${OWNER}`,
          telegram_chat_id: OTHER_CONVERSATION_ID,
          context_epoch: 3,
        },
      ],
    },
  })
  const result = await harness.post({
    action: 'start',
    conversationId: OTHER_CONVERSATION_ID,
  })
  assertEquals(result.status, 200)
  assertEquals(result.body.conversationId, 'existing-convo')
  assertEquals(result.body.contextEpoch, 3)
  // No new row was created for the already-existing conversation.
  assertEquals(harness.db.tables.agent_conversations.length, 1)
})

Deno.test('different conversationId keys resolve to different conversations for the same caller', async () => {
  const harness = createHarness()
  const first = await harness.post({ action: 'start' })
  assertEquals(first.status, 200)
  terminateSessions(harness.db)

  const second = await harness.post({
    action: 'start',
    conversationId: OTHER_CONVERSATION_ID,
  })
  assertEquals(second.status, 200)
  assertNotEquals(first.body.conversationId, second.body.conversationId)
  assertEquals(harness.db.tables.agent_conversations.length, 2)
})

Deno.test('an invalid conversationId is refused before any DB work', async () => {
  const harness = createHarness()
  const cases = [
    'not-a-valid-key',
    'app:not-a-uuid',
    // Wrong UUID version nibble (not v4).
    'app:c0ffee00-0000-1000-8000-000000000001',
    // Wrong variant nibble (not 8/9/a/b).
    'app:c0ffee00-0000-4000-c000-000000000001',
    // Uppercase is not accepted — the spec requires lowercase.
    'APP:C0FFEE00-0000-4000-8000-000000000001',
    '',
    123,
    { nested: true },
  ]
  for (const conversationId of cases) {
    const result = await harness.post({ action: 'start', conversationId })
    assertEquals(
      result.status,
      400,
      `conversationId ${JSON.stringify(conversationId)} should be refused`,
    )
    assertEquals(result.body.code, 'invalid_request')
  }
  assertEquals(sessionRows(harness.db).length, 0)
  assertEquals(harness.db.tables.agent_conversations.length, 0)
  assertEquals(attemptOutcomes(harness.db).length, 0)
})

// ---------------------------------------------------------------------------
// start: rate limit
// ---------------------------------------------------------------------------

Deno.test('the start rate limit allows 5 then rejects, and the window resets', async () => {
  const harness = createHarness()
  for (let attempt = 1; attempt <= 5; attempt++) {
    const accepted = await harness.post({ action: 'start' })
    assertEquals(accepted.status, 200, `attempt ${attempt} should be accepted`)
    // Free the one-session slot so this test isolates the rate limiter.
    terminateSessions(harness.db)
    harness.advanceSeconds(1)
  }

  const sixth = await harness.post({ action: 'start' })
  assertEquals(sixth.status, 429)
  assertEquals(sixth.body.code, 'rate_limited')
  // A refused attempt is recorded as refused, so it never eats a later slot.
  assertEquals(
    attemptOutcomes(harness.db).filter((o) => o === 'accepted').length,
    5,
  )
  assertEquals(
    attemptOutcomes(harness.db).filter((o) => o === 'rate_limited').length,
    1,
  )
  assertEquals(
    sessionRows(harness.db).filter((r) => r.state !== 'ended').length,
    0,
  )

  // Past the 300s window the earlier attempts no longer count.
  harness.advanceSeconds(301)
  const afterWindow = await harness.post({ action: 'start' })
  assertEquals(afterWindow.status, 200)
})

// ---------------------------------------------------------------------------
// start: budgets
// ---------------------------------------------------------------------------

Deno.test('the budget refuses when SETTLED seconds alone are enough', async () => {
  const harness = createHarness({
    tables: {
      agent_realtime_usage_seconds: [{
        session_id: 'old-session',
        usage_date: '2026-08-16',
        owner_profile_id: OWNER,
        tenant_id: null,
        seconds: 1800,
      }],
    },
  })
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 429)
  assertEquals(result.body.code, 'budget_exhausted')
  assertEquals(attemptOutcomes(harness.db), ['budget_exhausted'])
  assertEquals(harness.mintCount(), 0)
})

Deno.test('settled seconds below the line still allow a start', async () => {
  const harness = createHarness({
    tables: {
      agent_realtime_usage_seconds: [{
        session_id: 'old-session',
        usage_date: '2026-08-16',
        owner_profile_id: OWNER,
        tenant_id: null,
        seconds: 1500,
      }],
    },
  })
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 200)
})

Deno.test('the budget counts IN-FLIGHT seconds, not settled seconds alone', async () => {
  // Settled alone (1500) is under the 1800s daily limit — the previous test
  // proves that start succeeds. Adding a live session that became READY 400s
  // ago crosses the line, and that difference is the whole point of live
  // accounting: usage settles only when a session ends, so a caller who never
  // ends one would otherwise never accrue anything.
  const harness = createHarness({
    tables: {
      agent_realtime_usage_seconds: [{
        session_id: 'old-session',
        usage_date: '2026-08-16',
        owner_profile_id: OWNER,
        tenant_id: null,
        seconds: 1500,
      }],
      agent_realtime_sessions: [{
        id: 'live-session',
        conversation_id: 'conv-1',
        context_epoch: 1,
        authorization_fingerprint: 'fp',
        owner_profile_id: OWNER,
        owner_staff_link_id: `app-${OWNER}`,
        tenant_id: null,
        active_generation: 1,
        state: 'active',
        authoritative_ready_at: '2026-08-16T11:53:20.000Z', // 400s before now
      }],
    },
  })
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 429)
  assertEquals(result.body.code, 'budget_exhausted')
})

Deno.test('a live session that never reached READY contributes zero in-flight', async () => {
  const harness = createHarness({
    tables: {
      agent_realtime_usage_seconds: [{
        session_id: 'old-session',
        usage_date: '2026-08-16',
        owner_profile_id: OWNER,
        tenant_id: null,
        seconds: 1500,
      }],
      agent_realtime_sessions: [{
        id: 'live-session',
        conversation_id: 'conv-1',
        context_epoch: 1,
        authorization_fingerprint: 'fp',
        owner_profile_id: OWNER,
        owner_staff_link_id: `app-${OWNER}`,
        tenant_id: null,
        active_generation: 1,
        state: 'provisioning',
        authoritative_ready_at: null,
      }],
    },
  })
  const result = await harness.post({ action: 'start' })
  // The never-ready session added ZERO in-flight seconds — with 1500s settled
  // that leaves the 1800s budget intact, so the start is admitted and the
  // lingering session is REPLACED per the plan's race table (a budget bug
  // would have produced 429 budget_exhausted before replacement could run).
  assertEquals(result.status, 200)
  const old = sessionRows(harness.db).find((row) => row.id === 'live-session')
  assertEquals(old?.state, 'ended')
  assertEquals(old?.end_reason, 'replaced')
})

Deno.test('in-flight seconds are capped at ready + MAX_SESSION_SECONDS', async () => {
  const harness = createHarness({
    tables: {
      agent_realtime_usage_seconds: [{
        session_id: 'old-session',
        usage_date: '2026-08-16',
        owner_profile_id: OWNER,
        tenant_id: null,
        seconds: 1100,
      }],
      agent_realtime_sessions: [{
        id: 'orphan-session',
        conversation_id: 'conv-1',
        context_epoch: 1,
        authorization_fingerprint: 'fp',
        owner_profile_id: OWNER,
        owner_staff_link_id: `app-${OWNER}`,
        tenant_id: null,
        active_generation: 1,
        state: 'active',
        // READY 11 hours ago. Uncapped this would be ~39600s and would exhaust
        // every budget forever; capped it is exactly 600s, so 1100 + 600 = 1700
        // stays under the 1800s limit.
        authoritative_ready_at: '2026-08-16T01:00:00.000Z',
      }],
    },
  })
  const result = await harness.post({ action: 'start' })
  // 1100 settled + capped 600 in-flight = 1700 < 1800: admitted. Uncapped
  // in-flight would have been ~39600s and 429'd long before the replacement
  // step. The stale active session is displaced, not fought.
  assertEquals(result.status, 200)
  const orphan = sessionRows(harness.db).find((row) =>
    row.id === 'orphan-session'
  )
  assertEquals(orphan?.state, 'ended')
  assertEquals(orphan?.end_reason, 'replaced')
})

Deno.test('the tenant budget counts other members and carries the overage factor', async () => {
  // Tenant limit is 14400 * 1.25 = 18000. Settled 17_500 alone passes; a
  // colleague's session that has been live for 600s pushes it over.
  const tables = (readyAt: string | null) => ({
    profiles: [{
      id: OWNER,
      role: 'customer',
      status: 'approved',
      customer_id: 'cust-1',
      organization_id: ORG,
      full_name: 'Test User',
      email: 'test@example.com',
    }],
    agent_realtime_usage_seconds: [{
      session_id: 'old-session',
      usage_date: '2026-08-16',
      owner_profile_id: OTHER_OWNER,
      tenant_id: ORG,
      seconds: 17_500,
    }],
    agent_realtime_sessions: readyAt
      ? [{
        id: 'colleague-session',
        conversation_id: 'conv-9',
        context_epoch: 1,
        authorization_fingerprint: 'fp',
        owner_profile_id: OTHER_OWNER,
        owner_staff_link_id: `app-${OTHER_OWNER}`,
        tenant_id: ORG,
        active_generation: 1,
        state: 'active',
        authoritative_ready_at: readyAt,
      }]
      : [],
  })

  const settledOnly = createHarness({
    profile: { organization_id: ORG },
    tables: tables(null),
  })
  assertEquals((await settledOnly.post({ action: 'start' })).status, 200)

  const withInFlight = createHarness({
    profile: { organization_id: ORG },
    tables: tables('2026-08-16T11:50:00.000Z'), // 600s before now
  })
  const refused = await withInFlight.post({ action: 'start' })
  assertEquals(refused.status, 429)
  assertEquals(refused.body.code, 'budget_exhausted')
})

// ---------------------------------------------------------------------------
// start: one-session invariant
// ---------------------------------------------------------------------------

Deno.test('a second start replaces the live session instead of refusing', async () => {
  // The plan's race table: "Second session starts → lock profile, clean old
  // active or orphaned generation, then provision replacement." A refusal
  // would strand the user for up to the 60s setup deadline after any failed
  // attempt.
  const harness = createHarness()
  const first = await harness.post({ action: 'start' })
  assertEquals(first.status, 200)
  const firstId = String(first.body.sessionId)
  // Give the first session a registered call, so the hangup obligation is real.
  await harness.post({
    action: 'register_call',
    sessionId: firstId,
    generation: 1,
    openaiCallId: 'rtc_first_call',
  })

  const second = await harness.post({ action: 'start' })
  assertEquals(second.status, 200)
  assertEquals(sessionRows(harness.db).length, 2)

  const old = sessionRows(harness.db).find((row) => row.id === firstId)
  assertEquals(old?.state, 'ended')
  assertEquals(old?.end_reason, 'replaced')
  // The old call is handed to the sweeper — the hangup is never dropped.
  const oldCall = harness.db.tables.agent_realtime_calls.find((row) =>
    row.session_id === firstId
  )
  assertEquals(oldCall?.setup_state, 'cleanup_pending')
  assertEquals(oldCall?.hangup_state, 'pending')
  // Exactly one session still holds the one-per-profile slot.
  const live = sessionRows(harness.db).filter((row) =>
    row.state === 'provisioning' || row.state === 'active' ||
    row.state === 'ending'
  )
  assertEquals(live.length, 1)
  // Both starts were real admissions; both count against the rate window.
  assertEquals(attemptOutcomes(harness.db), ['accepted', 'accepted'])
})

Deno.test('concurrent starts leave exactly one live session', async () => {
  // Two legal interleavings under replacement semantics:
  //   * both pre-checks read empty → both insert → the index 409s the loser
  //   * the later start SEES the earlier insert → replaces it → both get 200
  // Either way the invariant is the same: exactly one session holds the slot,
  // and every displaced session is terminal with its hangup handed over.
  const harness = createHarness()
  const [first, second] = await Promise.all([
    harness.post({ action: 'start' }),
    harness.post({ action: 'start' }),
  ])
  const statuses = [first.status, second.status]
  for (const status of statuses) {
    assertEquals(status === 200 || status === 409, true, `got ${status}`)
  }
  assertEquals(statuses.includes(200), true)
  const live = sessionRows(harness.db).filter((row) =>
    row.state === 'provisioning' || row.state === 'active' ||
    row.state === 'ending'
  )
  assertEquals(live.length, 1)
  for (const row of sessionRows(harness.db)) {
    if (row === live[0]) continue
    assertEquals(row.state, 'ended')
    assertEquals(row.end_reason, 'replaced')
  }
})

Deno.test('the partial unique index, not the pre-check, decides a true race', async () => {
  // The pre-check is a courtesy: under real concurrency both requests can read
  // an empty result before either INSERT commits. This harness reproduces
  // exactly that — every "is a session already live?" read returns nothing —
  // so the only thing left standing between two starts is
  // idx_agent_realtime_sessions_one_active.
  const harness = createHarness()
  const realClient = harness.deps.adminClient
  harness.deps.adminClient = {
    from(table: string) {
      const query = realClient.from(table)
      if (table !== 'agent_realtime_sessions') return query
      return new Proxy(query, {
        get(target, property, receiver) {
          if (property === 'limit') {
            // Blind the one-session pre-check and the in-flight budget scan.
            return () => Promise.resolve({ data: [], error: null })
          }
          return Reflect.get(target, property, receiver)
        },
      })
    },
    rpc: (fn: string, args?: Record<string, unknown>) =>
      realClient.rpc(fn, args),
  } as PipRealtimeAdminClient

  const first = await harness.post({ action: 'start' })
  const second = await harness.post({ action: 'start' })
  assertEquals(first.status, 200)
  assertEquals(second.status, 409)
  assertEquals(second.body.code, 'session_active')
  assertEquals(sessionRows(harness.db).length, 1)
  // The loser burned no client secret beyond its own mint attempt and left no
  // orphan generation behind.
  assertEquals(callRows(harness.db).length, 1)
  assertEquals(attemptOutcomes(harness.db), ['accepted', 'replaced'])
})

// ---------------------------------------------------------------------------
// register_call
// ---------------------------------------------------------------------------

async function startedHarness(
  options: HarnessOptions = {},
): Promise<{ harness: Harness; sessionId: string; bindingToken: string }> {
  const harness = createHarness(options)
  const started = await harness.post({ action: 'start' })
  assertEquals(started.status, 200)
  return {
    harness,
    sessionId: String(started.body.sessionId),
    bindingToken: String(started.body.bindingToken),
  }
}

Deno.test('register_call writes the call id onto the pre-provisioned generation', async () => {
  const { harness, sessionId } = await startedHarness()
  const before = callRows(harness.db).length

  const result = await harness.post({
    action: 'register_call',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_abc',
  })
  assertEquals(result.status, 200)
  assertEquals(result.body.setupState, 'call_registered')

  // No NEW row: registration mutates the row `start` provisioned.
  assertEquals(callRows(harness.db).length, before)
  const call = callRows(harness.db)[0]
  assertEquals(call.openai_call_id, 'rtc_abc')
  assertEquals(call.call_registered_at, '2026-08-16T12:00:00.000Z')
  assertEquals(call.setup_state, 'call_registered')
})

Deno.test('register_call is idempotent for an identical repeat', async () => {
  const { harness, sessionId } = await startedHarness()
  const first = await harness.post({
    action: 'register_call',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_abc',
  })
  harness.advanceSeconds(5)
  const second = await harness.post({
    action: 'register_call',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_abc',
  })
  assertEquals(first.status, 200)
  assertEquals(second.status, 200)
  // The first registration timestamp stands; a retry does not rewrite history.
  assertEquals(second.body.registeredAt, first.body.registeredAt)
  assertEquals(callRows(harness.db).length, 1)
})

Deno.test('register_call refuses a DIFFERENT call id once one is registered', async () => {
  const { harness, sessionId } = await startedHarness()
  await harness.post({
    action: 'register_call',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_abc',
  })
  const conflict = await harness.post({
    action: 'register_call',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_other',
  })
  assertEquals(conflict.status, 409)
  assertEquals(conflict.body.code, 'call_conflict')
  assertEquals(callRows(harness.db)[0].openai_call_id, 'rtc_abc')
})

Deno.test('register_call grants no sideband authority', async () => {
  const { harness, sessionId, bindingToken } = await startedHarness()
  const result = await harness.post({
    action: 'register_call',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_abc',
  })
  assertEquals(result.status, 200)
  assertEquals(result.body.authority, 'none')

  // Nothing in the response can be mistaken for a credential.
  const serialized = JSON.stringify(result.body)
  assertEquals(serialized.includes(bindingToken), false)
  assertEquals(serialized.includes('ek_ephemeral_value'), false)
  assertEquals(result.body.bindingToken, undefined)
  assertEquals(result.body.clientSecret, undefined)
  assertEquals(result.body.leaseOwner, undefined)
  assertEquals(result.body.fencingToken, undefined)

  // And nothing in the row: the token is unconsumed, no lease is held, the
  // fencing token has not advanced, and the call is NOT active.
  const call = callRows(harness.db)[0]
  assertEquals(call.binding_token_consumed_at, undefined)
  assertEquals(call.lease_owner, undefined)
  assertEquals(call.lease_expires_at, undefined)
  assertEquals(call.fencing_token, 0)
  assertNotEquals(call.setup_state, 'active')
  assertEquals(call.sideband_healthy, false)
  assertEquals(sessionRows(harness.db)[0].state, 'provisioning')
  assertEquals(sessionRows(harness.db)[0].authoritative_ready_at, undefined)
})

Deno.test('register_call rejects an expired setup deadline', async () => {
  const { harness, sessionId } = await startedHarness()
  harness.advanceSeconds(61)
  const result = await harness.post({
    action: 'register_call',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_abc',
  })
  assertEquals(result.status, 409)
  assertEquals(result.body.code, 'setup_expired')
  assertEquals(callRows(harness.db)[0].openai_call_id, null)
})

Deno.test('register_call rejects a stale generation', async () => {
  const { harness, sessionId } = await startedHarness()
  const result = await harness.post({
    action: 'register_call',
    sessionId,
    generation: 2,
    openaiCallId: 'rtc_abc',
  })
  assertEquals(result.status, 409)
  assertEquals(result.body.code, 'stale_generation')
})

Deno.test('register_call rejects a session that belongs to somebody else', async () => {
  const { harness, sessionId } = await startedHarness()
  sessionRows(harness.db)[0].owner_profile_id = OTHER_OWNER
  const result = await harness.post({
    action: 'register_call',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_abc',
  })
  assertEquals(result.status, 404)
  assertEquals(result.body.code, 'unknown_session')
})

Deno.test('register_call rejects a caller demoted since start', async () => {
  const { harness, sessionId } = await startedHarness({
    profile: { role: 'admin', customer_id: null },
  })
  // Admin -> customer between start and register_call. The token is still
  // valid; the authorization behind it is not.
  harness.db.tables.profiles[0].role = 'customer'
  harness.db.tables.profiles[0].customer_id = 'cust-1'

  const result = await harness.post({
    action: 'register_call',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_abc',
  })
  assertEquals(result.status, 403)
  assertEquals(result.body.code, 'authorization_changed')
  assertEquals(callRows(harness.db)[0].openai_call_id, null)
})

Deno.test('register_call rejects a caller whose approval was revoked', async () => {
  const { harness, sessionId } = await startedHarness()
  harness.db.tables.profiles[0].status = 'pending'
  const result = await harness.post({
    action: 'register_call',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_abc',
  })
  assertEquals(result.status, 403)
  assertEquals(result.body.code, 'not_approved')
})

// ---------------------------------------------------------------------------
// abort_setup
// ---------------------------------------------------------------------------

Deno.test('abort_setup records the call id and marks the generation cleanup_pending', async () => {
  const { harness, sessionId } = await startedHarness()
  const result = await harness.post({
    action: 'abort_setup',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_orphan',
  })
  assertEquals(result.status, 200)
  assertEquals(result.body.setupState, 'cleanup_pending')
  assertEquals(result.body.authority, 'none')

  const call = callRows(harness.db)[0]
  assertEquals(call.setup_state, 'cleanup_pending')
  assertEquals(call.openai_call_id, 'rtc_orphan')
  assertEquals(call.hangup_state, 'pending')
  assertEquals(call.cleanup_next_attempt_at, '2026-08-16T12:00:00.000Z')
  assertEquals(call.end_reason, 'setup_aborted')
  // No authority was granted on the way out.
  assertEquals(call.lease_owner, undefined)
  assertEquals(call.binding_token_consumed_at, undefined)
  assertEquals(sessionRows(harness.db)[0].state, 'ending')
})

Deno.test('abort_setup with no call id needs no provider hangup', async () => {
  const { harness, sessionId } = await startedHarness()
  const result = await harness.post({
    action: 'abort_setup',
    sessionId,
    generation: 1,
  })
  assertEquals(result.status, 200)
  assertEquals(callRows(harness.db)[0].hangup_state, 'not_required')
})

Deno.test('abort_setup still works after the setup deadline has passed', async () => {
  const { harness, sessionId } = await startedHarness()
  harness.advanceSeconds(61)
  const result = await harness.post({
    action: 'abort_setup',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_orphan',
  })
  assertEquals(result.status, 200)
  assertEquals(callRows(harness.db)[0].setup_state, 'cleanup_pending')
})

// ---------------------------------------------------------------------------
// end
// ---------------------------------------------------------------------------

Deno.test('end marks the session ending and hands the generation to the sweeper', async () => {
  const { harness, sessionId } = await startedHarness()
  await harness.post({
    action: 'register_call',
    sessionId,
    generation: 1,
    openaiCallId: 'rtc_abc',
  })
  const result = await harness.post({ action: 'end', sessionId })
  assertEquals(result.status, 200)
  assertEquals(result.body.state, 'ending')

  const session = sessionRows(harness.db)[0]
  assertEquals(session.state, 'ending')
  assertEquals(session.end_reason, 'user_ended')
  assertEquals(session.ending_at, '2026-08-16T12:00:00.000Z')

  const call = callRows(harness.db)[0]
  assertEquals(call.setup_state, 'cleanup_pending')
  // The hangup itself is the sweeper's job, never this request's.
  assertEquals(call.hangup_state, 'pending')
  assertEquals(call.ended_at, undefined)
})

Deno.test('end is idempotent once the session is terminal', async () => {
  const { harness, sessionId } = await startedHarness()
  await harness.post({ action: 'end', sessionId })
  sessionRows(harness.db)[0].state = 'ended'
  const again = await harness.post({ action: 'end', sessionId })
  assertEquals(again.status, 200)
  assertEquals(again.body.alreadyEnded, true)
})

Deno.test("end refuses somebody else's session", async () => {
  const { harness, sessionId } = await startedHarness()
  sessionRows(harness.db)[0].owner_profile_id = OTHER_OWNER
  const result = await harness.post({ action: 'end', sessionId })
  assertEquals(result.status, 404)
})

// ---------------------------------------------------------------------------
// Binding token secrecy
// ---------------------------------------------------------------------------

Deno.test('the binding token is returned once, stored only as a hash, never logged', async () => {
  const logged: string[] = []
  const originalLog = console.log
  const originalError = console.error
  const originalWarn = console.warn
  console.log = (...args: unknown[]) => logged.push(args.map(String).join(' '))
  console.error = (...args: unknown[]) =>
    logged.push(args.map(String).join(' '))
  console.warn = (...args: unknown[]) => logged.push(args.map(String).join(' '))

  try {
    const harness = createHarness()
    const started = await harness.post({ action: 'start' })
    const token = String(started.body.bindingToken)
    assert(token.length >= 43, 'the token must carry >= 256 bits of entropy')

    // Stored as a hash only — a database read cannot recover a usable token.
    const call = callRows(harness.db)[0]
    assertEquals(call.binding_token_hash, await hashBindingToken(token))
    assertNotEquals(call.binding_token_hash, token)
    assertEquals(
      JSON.stringify(harness.db.tables).includes(token),
      false,
      'the raw token must never reach the database',
    )

    // Every later action must refuse to echo it back.
    const sessionId = String(started.body.sessionId)
    const later = [
      await harness.post({
        action: 'register_call',
        sessionId,
        generation: 1,
        openaiCallId: 'rtc_abc',
      }),
      await harness.post({
        action: 'abort_setup',
        sessionId,
        generation: 1,
        openaiCallId: 'rtc_abc',
      }),
      await harness.post({ action: 'end', sessionId }),
    ]
    for (const response of later) {
      assertEquals(JSON.stringify(response.body).includes(token), false)
    }

    assertEquals(logged.join('\n').includes(token), false)
    assertEquals(logged.join('\n').includes('ek_ephemeral_value'), false)
    assertEquals(logged.join('\n').includes('sk-test'), false)
  } finally {
    console.log = originalLog
    console.error = originalError
    console.warn = originalWarn
  }
})

Deno.test('two starts never mint the same binding token', async () => {
  const harness = createHarness()
  const first = await harness.post({ action: 'start' })
  terminateSessions(harness.db)
  harness.advanceSeconds(1)
  const second = await harness.post({ action: 'start' })
  assertNotEquals(first.body.bindingToken, second.body.bindingToken)
})

Deno.test('end refuses a free-text end reason from the client', async () => {
  const { harness, sessionId } = await startedHarness()
  const result = await harness.post({
    action: 'end',
    sessionId,
    reason: 'DROP TABLE agent_realtime_sessions',
  })
  assertEquals(result.status, 200)
  // end_reason is an audit column; an unknown reason falls back to the default
  // rather than letting the client write arbitrary text into it.
  assertEquals(result.body.endReason, 'user_ended')
  assertEquals(sessionRows(harness.db)[0].end_reason, 'user_ended')

  const known = await startedHarness()
  const named = await known.harness.post({
    action: 'end',
    sessionId: known.sessionId,
    reason: 'network_lost',
  })
  assertEquals(named.body.endReason, 'network_lost')
})

// ---------------------------------------------------------------------------
// The server clock
// ---------------------------------------------------------------------------

Deno.test('every persisted instant is seeded from the database clock', async () => {
  // The database clock is deliberately hours away from any plausible local
  // clock, so a fallback to `new Date()` could not produce these timestamps.
  const harness = createHarness({ now: '2031-03-04T05:06:07.000Z' })
  const result = await harness.post({ action: 'start' })
  assertEquals(result.status, 200)

  assertEquals(result.body.serverTime, '2031-03-04T05:06:07.000Z')
  assertEquals(result.body.setupDeadlineAt, '2031-03-04T05:07:07.000Z')
  assertEquals(result.body.sessionExpiresAt, '2031-03-04T05:16:07.000Z')
  assertEquals(
    sessionRows(harness.db)[0].created_at,
    '2031-03-04T05:06:07.000Z',
  )
  assertEquals(
    callRows(harness.db)[0].setup_deadline_at,
    '2031-03-04T05:07:07.000Z',
  )
})

Deno.test('the clock is read ONCE per request and threaded through it', async () => {
  // One request must not straddle two readings: the deadline it writes has to
  // be anchored to the same instant as the row it writes it on.
  const harness = createHarness()
  await harness.post({ action: 'start' })
  assertEquals(harness.clockReads(), 1)

  const session = sessionRows(harness.db)[0]
  const call = callRows(harness.db)[0]
  assertEquals(session.created_at, call.provisioned_at)
  assertEquals(session.created_at, call.client_secret_issued_at)
})

Deno.test('a failing clock refuses the request instead of using the local clock', async () => {
  const harness = createHarness({ clockFails: true })
  for (const action of ['start', 'register_call', 'abort_setup', 'end']) {
    const result = await harness.post({
      action,
      sessionId: 'sess-1',
      generation: 1,
      openaiCallId: 'rtc_abc',
    })
    assertEquals(result.status, 503, `${action} must refuse`)
    assertEquals(result.body.code, 'clock_unavailable')
  }
  // A wrong clock silently moves deadlines for the sideband and the sweeper,
  // so nothing at all is written.
  assertEquals(sessionRows(harness.db).length, 0)
  assertEquals(callRows(harness.db).length, 0)
  assertEquals(attemptOutcomes(harness.db).length, 0)
  assertEquals(harness.mintCount(), 0)
})

// ---------------------------------------------------------------------------
// Insert failures are not conflicts
// ---------------------------------------------------------------------------

Deno.test('a non-unique session insert failure surfaces as an error, not a 409', async () => {
  const harness = createHarness()
  harness.db.failingInserts.add('agent_realtime_sessions')
  const result = await harness.post({ action: 'start' })
  // A 409 would tell the client "you already have a session open" — a lie that
  // hides an outage behind a plausible-looking conflict.
  assertEquals(result.status, 500)
  assertEquals(result.body.code, 'server_error')
  assertEquals(harness.mintCount(), 0)
})
