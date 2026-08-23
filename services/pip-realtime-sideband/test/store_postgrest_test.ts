// Focused coverage for PostgrestStore query construction. This is not a full
// exercise of every RealtimeStore method (the in-memory FakeStore double in
// fakes.ts covers behavior against the rest of the codebase) — it exists
// specifically to prove the exact PostgREST query strings this store sends
// for the two things that cannot be verified through the in-memory double:
// the loadRecentTurns filter hardening, and the touchConversation PATCH.

import { assert, assertEquals } from '@std/assert'
import { PostgrestStore } from '../src/store_postgrest.ts'

interface CapturedRequest {
  url: string
  method: string
  body: unknown
}

function fakeFetch(
  requests: CapturedRequest[],
  respond: (req: CapturedRequest) => { status: number; body: unknown } = () => ({
    status: 200,
    body: [],
  }),
): typeof fetch {
  return (async (input, init) => {
    const url = typeof input === 'string' ? input : input.toString()
    const method = init?.method ?? 'GET'
    const body = typeof init?.body === 'string' ? JSON.parse(init.body) : undefined
    const request: CapturedRequest = { url, method, body }
    requests.push(request)
    const { status, body: responseBody } = respond(request)
    return new Response(JSON.stringify(responseBody), { status })
  }) as typeof fetch
}

function buildStore(requests: CapturedRequest[], respond?: Parameters<typeof fakeFetch>[1]) {
  return new PostgrestStore({
    supabaseUrl: 'https://example.test',
    serviceRoleKey: 'test-service-role-key',
    fetchImpl: fakeFetch(requests, respond),
  })
}

Deno.test(
  'loadRecentTurns constrains direction and source_channel so a future row type can never be injected as assistant speech',
  async () => {
    const requests: CapturedRequest[] = []
    const store = buildStore(requests)

    await store.loadRecentTurns({
      conversationId: 'conv-1',
      contextEpoch: 3,
      limit: 12,
    })

    assertEquals(requests.length, 1)
    const { url, method } = requests[0]
    assertEquals(method, 'GET')
    assert(url.startsWith('https://example.test/rest/v1/agent_conversation_turns?'))
    assert(url.includes('conversation_id=eq.conv-1'))
    assert(url.includes('context_epoch=eq.3'))
    assert(url.includes('completion_status=eq.finalized'))
    assert(url.includes('direction=in.(inbound,outbound)'))
    assert(url.includes('source_channel=in.(app_text,realtime_voice,telegram)'))
    assert(url.includes('text=neq.'))
    assert(url.includes('limit=12'))
  },
)

Deno.test('loadRecentTurns maps rows to {direction, text} only', async () => {
  const requests: CapturedRequest[] = []
  const store = buildStore(requests, () => ({
    status: 200,
    body: [
      { direction: 'outbound', text: 'Hatch rate is 84 percent.' },
      { direction: 'inbound', text: 'What is the hatch rate?' },
    ],
  }))

  const turns = await store.loadRecentTurns({
    conversationId: 'conv-1',
    contextEpoch: 1,
    limit: 12,
  })

  assertEquals(turns, [
    { direction: 'outbound', text: 'Hatch rate is 84 percent.' },
    { direction: 'inbound', text: 'What is the hatch rate?' },
  ])
})

Deno.test('touchConversation PATCHes updated_at scoped to the one conversation', async () => {
  const requests: CapturedRequest[] = []
  const store = buildStore(requests)

  await store.touchConversation('conv-1', '2026-08-18T00:00:00.000Z')

  assertEquals(requests.length, 1)
  const { url, method, body } = requests[0]
  assertEquals(method, 'PATCH')
  assert(url.startsWith('https://example.test/rest/v1/agent_conversations?'))
  assert(url.includes('id=eq.conv-1'))
  assertEquals(body, { updated_at: '2026-08-18T00:00:00.000Z' })
})

Deno.test('touchConversation never throws when zero rows match (a raced/deleted conversation)', async () => {
  const requests: CapturedRequest[] = []
  const store = buildStore(requests, () => ({ status: 200, body: [] }))

  // Must resolve, not reject: callers (sideband.ts) treat this as fire-and
  // forget best-effort and only need real transport/HTTP failures to throw.
  await store.touchConversation('missing-conversation', '2026-08-18T00:00:00.000Z')
  assertEquals(requests.length, 1)
})

Deno.test('touchConversation propagates a real PostgREST failure so the caller can log it (never the row content)', async () => {
  const requests: CapturedRequest[] = []
  const store = buildStore(requests, () => ({ status: 500, body: { message: 'boom' } }))

  let threw = false
  try {
    await store.touchConversation('conv-1', '2026-08-18T00:00:00.000Z')
  } catch (error) {
    threw = true
    assert(error instanceof Error)
    // Only the status code, never the response body, reaches the message.
    assertEquals(error.message, 'postgrest_status_500')
  }
  assert(threw, 'a real PostgREST failure must propagate')
})
