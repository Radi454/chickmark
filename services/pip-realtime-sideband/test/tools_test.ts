import { assertEquals } from '@std/assert'

import { brokeredToolRegistry, pipRealtimeToolBrokerExecutor } from '../src/tools.ts'
import type { ToolExecutionContext } from '../src/claims.ts'

const CONTEXT: ToolExecutionContext = {
  sessionId: 'sess-1',
  generation: 2,
  interactionId: 'int-7',
  toolCallId: 'call_abc',
  toolName: 'get_customer_context',
  authorizationFingerprint: 'fingerprint-abc',
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  })
}

Deno.test('the broker request carries the resolved session context, not client input', async () => {
  let seen: { url: string; init: RequestInit } | null = null
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://edge.test/pip-realtime-tool-broker',
    brokerSecret: 'shared-secret',
    fetchImpl: ((url: string, init: RequestInit) => {
      seen = { url, init }
      return Promise.resolve(
        jsonResponse(200, { status: 'succeeded', result: { ok: true } }),
      )
    }) as unknown as typeof fetch,
  })

  const outcome = await executor({ customerId: 'cust-1' }, CONTEXT)
  assertEquals(outcome.status, 'succeeded')

  const request = seen as unknown as { url: string; init: RequestInit }
  assertEquals(request.url, 'https://edge.test/pip-realtime-tool-broker')
  const headers = request.init.headers as Record<string, string>
  assertEquals(headers['x-pip-broker-secret'], 'shared-secret')
  assertEquals(JSON.parse(request.init.body as string), {
    session_id: 'sess-1',
    generation: 2,
    tool_call_id: 'call_abc',
    tool_name: 'get_customer_context',
    arguments: { customerId: 'cust-1' },
    interaction_id: 'int-7',
    authorization_fingerprint: 'fingerprint-abc',
  })
})

Deno.test('a broker refusal surfaces its code and never looks like success', async () => {
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://edge.test/broker',
    brokerSecret: 'shared-secret',
    fetchImpl: (() =>
      Promise.resolve(
        jsonResponse(409, {
          code: 'authorization_changed',
          error: 'Authorization changed.',
        }),
      )) as unknown as typeof fetch,
  })

  const outcome = await executor({}, CONTEXT)
  assertEquals(outcome.status, 'rejected')
  assertEquals(outcome.result, { ok: false, error: 'authorization_changed' })
})

Deno.test('an unreachable broker fails rather than throwing into the tool loop', async () => {
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://edge.test/broker',
    brokerSecret: 'shared-secret',
    fetchImpl: (() =>
      Promise.reject(new TypeError('network'))) as unknown as typeof fetch,
  })

  const outcome = await executor({}, CONTEXT)
  assertEquals(outcome.status, 'failed')
  assertEquals(outcome.result, { ok: false, error: 'broker_unreachable' })
})

Deno.test('a duplicate replay is reported with the recorded status', async () => {
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://edge.test/broker',
    brokerSecret: 'shared-secret',
    fetchImpl: (() =>
      Promise.resolve(
        jsonResponse(200, {
          status: 'succeeded',
          disposition: 'duplicate',
          result: { ok: true, code: 'ok', data: null },
        }),
      )) as unknown as typeof fetch,
  })

  const outcome = await executor({}, CONTEXT)
  assertEquals(outcome.status, 'succeeded')
  assertEquals(outcome.result, { ok: true, code: 'ok', data: null })
})

Deno.test('every tool definition maps to the one broker executor', () => {
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://edge.test/broker',
    brokerSecret: 'shared-secret',
  })
  const registry = brokeredToolRegistry(
    [
      { type: 'function', name: 'a', description: '', parameters: {} },
      { type: 'function', name: 'b', description: '', parameters: {} },
    ],
    executor,
  )
  assertEquals(registry.ownership.ledger, 'broker')
  assertEquals([...registry.ownership.executors.keys()], ['a', 'b'])
  assertEquals(registry.ownership.executors.get('a'), executor)
})

// ---------------------------------------------------------------------------
// BROKER FAILURE, HONESTLY. Every branch below must produce a real, negative
// tool result: never an invented success, never a throw into the tool loop
// (which would leave the `function_call_output` unsent and hang the call).
// ---------------------------------------------------------------------------

Deno.test('a broker 5xx is a failure, not a refusal', async () => {
  // A refusal tells the model its request was the problem and invites a
  // rephrase. A broken broker is not the model's fault and rephrasing will not
  // help, so the two are reported differently.
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://edge.test/broker',
    brokerSecret: 'shared-secret',
    fetchImpl: (() =>
      Promise.resolve(
        jsonResponse(500, { code: 'server_error', error: 'boom' }),
      )) as unknown as typeof fetch,
  })

  const outcome = await executor({}, CONTEXT)
  assertEquals(outcome.status, 'failed')
  assertEquals(outcome.result, { ok: false, error: 'server_error' })
})

Deno.test('a broker error with no parseable body still names the status', async () => {
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://edge.test/broker',
    brokerSecret: 'shared-secret',
    fetchImpl: (() =>
      Promise.resolve(
        new Response('<html>gateway</html>', { status: 502 }),
      )) as unknown as typeof fetch,
  })

  const outcome = await executor({}, CONTEXT)
  assertEquals(outcome.status, 'failed')
  assertEquals(outcome.result, { ok: false, error: 'broker_502' })
})

Deno.test('a 200 with an unusable body is a failure, NOT a silent success', async () => {
  for (const body of ['not json at all', JSON.stringify({ hello: 'world' })]) {
    const executor = pipRealtimeToolBrokerExecutor({
      url: 'https://edge.test/broker',
      brokerSecret: 'shared-secret',
      fetchImpl: (() =>
        Promise.resolve(
          new Response(body, {
            status: 200,
            headers: { 'content-type': 'application/json' },
          }),
        )) as unknown as typeof fetch,
    })

    const outcome = await executor({}, CONTEXT)
    assertEquals(outcome.status, 'failed')
    assertEquals(outcome.result, { ok: false, error: 'broker_malformed_response' })
  }
})

Deno.test('a broker failure never throws out of the executor', async () => {
  // The caller must always get a resolved outcome to answer the model with.
  const throwing = pipRealtimeToolBrokerExecutor({
    url: 'https://edge.test/broker',
    brokerSecret: 'shared-secret',
    fetchImpl: (() => {
      throw new Error('connection refused')
    }) as unknown as typeof fetch,
  })

  const outcome = await throwing({}, CONTEXT)
  assertEquals(outcome.status, 'failed')
  assertEquals(outcome.result, { ok: false, error: 'broker_unreachable' })
})

Deno.test('the broker secret travels in the header only, never in the body or URL', async () => {
  let seen: { url: string; init: RequestInit } | null = null
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://edge.test/broker',
    brokerSecret: 'shared-secret',
    fetchImpl: ((url: string, init: RequestInit) => {
      seen = { url, init }
      return Promise.resolve(jsonResponse(200, { status: 'succeeded', result: {} }))
    }) as unknown as typeof fetch,
  })
  await executor({ customerId: 'cust-1' }, CONTEXT)

  const request = seen as unknown as { url: string; init: RequestInit }
  assertEquals(request.url.includes('shared-secret'), false)
  assertEquals((request.init.body as string).includes('shared-secret'), false)
})

Deno.test('a duplicate replay is flagged so the coordinator can report it', async () => {
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://edge.test/broker',
    brokerSecret: 'shared-secret',
    fetchImpl: (() =>
      Promise.resolve(
        jsonResponse(200, {
          status: 'succeeded',
          disposition: 'duplicate',
          result: { ok: true, code: 'ok', data: null },
        }),
      )) as unknown as typeof fetch,
  })

  const outcome = await executor({}, CONTEXT)
  assertEquals(outcome.duplicate, true)
})

Deno.test('an indeterminate mutation is refused and is NOT replayed as success', async () => {
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://edge.test/broker',
    brokerSecret: 'shared-secret',
    fetchImpl: (() =>
      Promise.resolve(
        jsonResponse(409, {
          code: 'indeterminate_not_replayable',
          error: 'A previous attempt did not settle.',
        }),
      )) as unknown as typeof fetch,
  })

  const outcome = await executor({}, CONTEXT)
  assertEquals(outcome.status, 'rejected')
  assertEquals(outcome.result, {
    ok: false,
    error: 'indeterminate_not_replayable',
  })
  assertEquals(outcome.duplicate, undefined)
})

Deno.test('a broker that HANGS is reported as a timeout, not left to wedge the session', async () => {
  // `fetch` has no default timeout. Without this bound the promise never
  // settles, so the `function_call_output` is never sent (the caller hears
  // nothing) AND every later tool call queues behind it forever, because
  // `#onOutputItemDone` runs on a serialized chain. A hang is strictly worse
  // than a failure; this converts one into the other.
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://example.test/broker',
    brokerSecret: 'secret',
    timeoutMs: 20,
    fetchImpl: (_input, init) =>
      new Promise((_resolve, reject) => {
        const signal = (init as RequestInit | undefined)?.signal
        signal?.addEventListener('abort', () => reject(new Error('aborted')))
      }),
  })

  const outcome = await executor({}, {
    sessionId: 'sess_1',
    generation: 1,
    interactionId: 'item:item_1',
    toolCallId: 'call_1',
    toolName: 'lookup_flock',
    authorizationFingerprint: 'admin:all',
  })

  assertEquals(outcome.status, 'failed')
  assertEquals(
    (outcome.result as Record<string, unknown>).error,
    'broker_timeout',
  )
})

Deno.test('an unreachable broker is still reported as unreachable, not as a timeout', async () => {
  const executor = pipRealtimeToolBrokerExecutor({
    url: 'https://example.test/broker',
    brokerSecret: 'secret',
    fetchImpl: () => Promise.reject(new TypeError('dns')),
  })

  const outcome = await executor({}, {
    sessionId: 'sess_1',
    generation: 1,
    interactionId: 'item:item_1',
    toolCallId: 'call_1',
    toolName: 'lookup_flock',
    authorizationFingerprint: 'admin:all',
  })

  assertEquals(outcome.status, 'failed')
  assertEquals(
    (outcome.result as Record<string, unknown>).error,
    'broker_unreachable',
  )
})
