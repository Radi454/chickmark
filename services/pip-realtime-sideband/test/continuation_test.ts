// Regression coverage for the RESPONSE-CHAIN termination guarantees.
//
// The incident these exist for: every `function_call_output` used to be
// followed by an unconditional `response.create`, including the output that
// says `tool_limit_reached`. A model that answered that refusal by calling the
// same tool again produced
//
//   tool -> reject -> response.create -> tool -> reject -> response.create -> …
//
// with nothing in this service bounding it. The per-interaction TOOL budget
// stopped the tools from running; it never stopped the RESPONSES from being
// generated, so the caller heard the same sentence over and over and the only
// thing that ever ended it was the model losing interest.
//
// What these tests pin is that termination no longer depends on the model:
// the last continuation an interaction is ever granted carries
// `tool_choice: 'none'`, which the provider cannot answer with a function
// call, and anything after that is dropped on the floor.

import { assert, assertEquals } from '@std/assert'
import { SidebandSession } from '../src/sideband.ts'
import { InteractionTracker } from '../src/interaction.ts'
import { LeaseKeeper } from '../src/lease.ts'
import { testConfig } from '../src/config.ts'
import type { RealtimeToolDefinition } from '../src/session_config.ts'
import type { ToolExecutor } from '../src/claims.ts'
import { captureLogs, FakeClock, FakeSidebandSocket, FakeStore } from './fakes.ts'

function toolDefinition(name: string): RealtimeToolDefinition {
  return {
    type: 'function',
    name,
    description: `Call ${name}`,
    parameters: { type: 'object', properties: {} },
  }
}

const TOOLS: readonly RealtimeToolDefinition[] = [
  toolDefinition('lookup_flock'),
  // Named because `#maybeUpgradeToolCatalogue` gates the intake catalogue on
  // this exact tool being CALLED; the ordering test below depends on it.
  toolDefinition('propose_intake'),
]

async function build(
  options: {
    executor?: ToolExecutor
    /** Overrides the whole executor map. Needed for multi-tool ordering. */
    executors?: Record<string, ToolExecutor>
    intakeUpgradeAckTimeoutMs?: number
    onNotice?: (code: string) => void
  } = {},
) {
  const store = new FakeStore()
  const clock = new FakeClock()
  const socket = new FakeSidebandSocket()
  const lease = new LeaseKeeper({
    store,
    owner: 'worker_a',
    leaseSeconds: 30,
    heartbeatSeconds: 10,
    now: clock.now,
    setTimer: () => 0,
    clearTimer: () => {},
  })
  await lease.claim('sess_1', 1)
  const session = new SidebandSession({
    config: testConfig(),
    store,
    socket,
    lease,
    session: (await store.loadSession('sess_1'))!,
    generation: 1,
    leaseOwner: 'worker_a',
    tools: TOOLS,
    ownership: {
      ledger: 'sideband',
      executors: options.executors
        ? new Map(Object.entries(options.executors))
        : new Map(TOOLS.map((tool) => [
          tool.name,
          options.executor ??
            (() => Promise.resolve({ status: 'succeeded' as const, result: { ok: true } })),
        ])),
    },
    notifyClient: (notice) => {
      if (notice.type === 'error') options.onNotice?.(notice.code)
    },
    now: clock.now,
    instructions: 'You are ChickMark.',
    intakeUpgradeAckTimeoutMs: options.intakeUpgradeAckTimeoutMs,
  })
  const feed = (event: Record<string, unknown>) => session.handleEvent(event)
  return { store, socket, session, lease, feed }
}

/** One `function_call` delivered on `responseId`. */
function toolCall(
  responseId: string,
  callId: string,
  name = 'lookup_flock',
): Record<string, unknown> {
  return {
    type: 'response.output_item.done',
    response_id: responseId,
    item: {
      type: 'function_call',
      call_id: callId,
      name,
      arguments: '{}',
    },
  }
}

/** The `response.create` frames the sideband sent, in order. */
function creates(socket: FakeSidebandSocket): Record<string, unknown>[] {
  return socket.sentOfType('response.create') as Record<string, unknown>[]
}

function toolChoiceOf(frame: Record<string, unknown>): unknown {
  const response = frame.response as Record<string, unknown> | undefined
  return response?.tool_choice
}

/**
 * Drive one interaction to its tool budget, then keep calling. `extraCalls`
 * is how many calls arrive AFTER the budget is spent — every one of them is
 * answered `tool_limit_reached`.
 */
async function exhaustBudget(
  feed: (event: Record<string, unknown>) => Promise<void>,
  limit: number,
  extraCalls: number,
): Promise<void> {
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  for (let index = 1; index <= limit; index++) {
    await feed(toolCall(index === 1 ? 'resp_1' : `resp_cont_${index - 1}`, `call_${index}`))
    await feed({ type: 'response.created', response: { id: `resp_cont_${index}` } })
  }
  for (let index = 1; index <= extraCalls; index++) {
    await feed(toolCall(`resp_cont_${limit}`, `over_${index}`))
  }
}

Deno.test('tool_limit_reached produces exactly one more response, and that response cannot call a tool', async () => {
  const { feed, socket } = await build()
  const limit = testConfig().maxToolCallsPerInteraction
  await exhaustBudget(feed, limit, 1)

  // One continuation per successful tool, plus the single forced final.
  const sent = creates(socket)
  assertEquals(sent.length, limit + 1)
  for (const frame of sent.slice(0, limit)) {
    assertEquals(toolChoiceOf(frame), undefined, 'a normal continuation must not pin tool_choice')
  }
  // `tool_choice: 'none'` is the terminator: the provider may not emit a
  // function call in this response, so it cannot produce another
  // function_call_output, so it cannot produce another continuation.
  assertEquals(toolChoiceOf(sent[limit]), 'none')
})

Deno.test('repeated rejected calls after the limit generate no further responses at all', async () => {
  const { feed, socket, store } = await build()
  const limit = testConfig().maxToolCallsPerInteraction
  await exhaustBudget(feed, limit, 12)

  // Twelve refusals arrived; exactly one response was generated for the first
  // of them and nothing at all for the other eleven. Termination is
  // deterministic — it does not depend on the model choosing to stop.
  assertEquals(creates(socket).length, limit + 1)
  // Every one of the twelve was still ANSWERED: an unanswered function call
  // wedges the provider's chain.
  assertEquals(socket.sentOfType('conversation.item.create').length, limit + 12)
  // And none of them executed.
  assertEquals(store.toolEvents.length, limit)
})

Deno.test('a suppressed continuation is logged with the interaction and the cap', async () => {
  const capture = captureLogs()
  try {
    const { feed } = await build()
    const limit = testConfig().maxToolCallsPerInteraction
    await exhaustBudget(feed, limit, 2)
    const lines = capture.lines.map((line) => JSON.parse(line))
    const suppressed = lines.filter((line) => line.event === 'sideband.continuation_suppressed')
    assertEquals(suppressed.length, 1)
    assertEquals(suppressed[0].interaction_id, 'item:item_1')
    assertEquals(suppressed[0].disposition, 'rejected_tool_limit')
    assertEquals(suppressed[0].limit, limit + 2)
    const final = lines.filter((line) => line.event === 'sideband.continuation_final')
    assertEquals(final.length, 1)
  } finally {
    capture.restore()
  }
})

Deno.test('a successful multi-tool interaction still completes normally', async () => {
  const { feed, socket, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed(toolCall('resp_1', 'call_1'))
  await feed({ type: 'response.created', response: { id: 'resp_cont_1' } })
  await feed(toolCall('resp_cont_1', 'call_2'))
  await feed({ type: 'response.created', response: { id: 'resp_cont_2' } })
  await feed(toolCall('resp_cont_2', 'call_3'))

  assertEquals(store.toolEvents.length, 3)
  const sent = creates(socket)
  assertEquals(sent.length, 3)
  // Nothing was force-finalized: three ordinary continuations, each free to
  // call another tool.
  assertEquals(sent.every((frame) => toolChoiceOf(frame) === undefined), true)
})

Deno.test('a fresh user utterance gets a fresh continuation budget', async () => {
  const { feed, socket } = await build()
  const limit = testConfig().maxToolCallsPerInteraction
  await exhaustBudget(feed, limit, 3)
  const afterFirst = creates(socket).length

  // The user speaks again. A new interaction, so the previous interaction's
  // exhausted budget must not silence it.
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_2' })
  await feed({ type: 'response.created', response: { id: 'resp_2' } })
  await feed(toolCall('resp_2', 'fresh_1'))

  const sent = creates(socket)
  assertEquals(sent.length, afterFirst + 1)
  assertEquals(toolChoiceOf(sent[sent.length - 1]), undefined)
})

Deno.test('a worker that lost its lease answers the model but never drives another response', async () => {
  const capture = captureLogs()
  try {
    const { feed, socket, lease, store } = await build()
    await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
    await feed({ type: 'response.created', response: { id: 'resp_1' } })
    await lease.release()

    await feed(toolCall('resp_1', 'call_1'))

    // Answered — an unanswered call wedges the chain whoever owns the session.
    const outputs = socket.sentOfType('conversation.item.create')
    assertEquals(outputs.length, 1)
    const output = JSON.parse((outputs[0].item as Record<string, string>).output)
    assertEquals(output.error, 'session_not_live')
    // But NOT driven: another worker owns this conversation now, and two
    // workers issuing response.create is two assistants talking over one user.
    assertEquals(creates(socket).length, 0)
    assertEquals(store.toolEvents.length, 0)
    const skipped = capture.lines
      .map((line) => JSON.parse(line))
      .filter((line) => line.event === 'sideband.continuation_skipped_not_live')
    assertEquals(skipped.length, 1)
  } finally {
    capture.restore()
  }
})

Deno.test('a suppressed continuation does not leave a tool name queued for an unrelated response', async () => {
  const { feed, store } = await build()
  const limit = testConfig().maxToolCallsPerInteraction
  await exhaustBudget(feed, limit, 1)
  // The forced final opens, and drains the queued name onto ITSELF.
  await feed({ type: 'response.created', response: { id: 'resp_final' } })

  // A provider that ignored `tool_choice: 'none'` and called a tool anyway.
  // The sideband still answers it, but sends nothing — and must not queue the
  // name, or it would be pinned onto whatever response opens next.
  await feed(toolCall('resp_final', 'over_2'))

  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_2' })
  await feed({ type: 'response.created', response: { id: 'resp_next' } })
  await feed({
    type: 'response.done',
    response: { id: 'resp_next', status: 'completed', object: 'realtime.response' },
  })
  const usage = [...store.responseUsage.values()]
    .find((row) => row.responseId === 'resp_next')
  assert(usage, 'the next response must still record usage')
  assertEquals(usage.followedToolCall, false)
  assertEquals(usage.toolNames, [])
})

// ---------------------------------------------------------------------------
// The cap itself, in isolation.
// ---------------------------------------------------------------------------

Deno.test('the continuation cap terminates a chain even if no rejection ever force-finalizes it', () => {
  const tracker = new InteractionTracker(5)
  assertEquals(tracker.continuationLimit, 7)
  const decisions = Array.from(
    { length: 10 },
    () => tracker.tryConsumeContinuation('item:x'),
  )
  assertEquals(decisions.slice(0, 6), Array(6).fill('continue'))
  assertEquals(decisions[6], 'final')
  // Everything after the forced final is dropped, forever.
  assertEquals(decisions.slice(7), Array(3).fill('suppress'))
})

Deno.test('a forced final closes the interaction even when it arrives on the first continuation', () => {
  const tracker = new InteractionTracker(5)
  assertEquals(tracker.tryConsumeContinuation('item:x', { forceFinal: true }), 'final')
  assertEquals(tracker.tryConsumeContinuation('item:x'), 'suppress')
  assertEquals(tracker.tryConsumeContinuation('item:x', { forceFinal: true }), 'suppress')
  // A different interaction is unaffected: one bad utterance must not mute the
  // rest of the call.
  assertEquals(tracker.tryConsumeContinuation('item:y'), 'continue')
})

Deno.test('the continuation limit is configurable and validated', () => {
  assertEquals(new InteractionTracker(5, 1).continuationLimit, 1)
  assertEquals(new InteractionTracker(5, 1).tryConsumeContinuation('item:x'), 'final')
  let threw = false
  try {
    new InteractionTracker(5, 0)
  } catch {
    threw = true
  }
  assertEquals(threw, true)
})

// ---------------------------------------------------------------------------
// Observability: responses per interaction.
// ---------------------------------------------------------------------------

Deno.test('every response records the interaction it belonged to, so a chain is countable after the fact', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed(toolCall('resp_1', 'call_1'))
  await feed({ type: 'response.created', response: { id: 'resp_cont_1' } })
  for (const responseId of ['resp_1', 'resp_cont_1']) {
    await feed({
      type: 'response.done',
      response: { id: responseId, status: 'completed', object: 'realtime.response' },
    })
  }

  // Both responses belong to the ONE thing the caller said. That is the join
  // key an incident needs — "how many assistant responses did this utterance
  // produce?" — and until this column existed the answer lived only in log
  // lines with a short retention.
  const rows = [...store.responseUsage.values()]
  assertEquals(rows.length, 2)
  assertEquals(
    rows.map((row) => row.interactionId),
    ['item:item_1', 'item:item_1'],
  )

  // A second utterance is a second interaction, so the two never merge.
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_2' })
  await feed({ type: 'response.created', response: { id: 'resp_2' } })
  await feed({
    type: 'response.done',
    response: { id: 'resp_2', status: 'completed', object: 'realtime.response' },
  })
  const second = [...store.responseUsage.values()]
    .find((row) => row.responseId === 'resp_2')
  assert(second)
  assertEquals(second.interactionId, 'item:item_2')
})

// ---------------------------------------------------------------------------
// Ordering across concurrent tool events.
//
// `socket.onMessage((event) => void this.handleEvent(event))` is fire-and-
// forget, so two `response.output_item.done` events from ONE response run
// concurrently and each awaits a broker round trip. `#serializeToolOutput`
// chains them, which is what keeps the intake `session.update` from landing
// AFTER a later tool's `response.create` — the ordering that decides whether
// the model answers a data-entry request with the tools it needs.
// ---------------------------------------------------------------------------

/** The frame types the sideband sent, in the order it sent them. */
function sentTypes(socket: FakeSidebandSocket): string[] {
  return socket.sent.map((frame) =>
    String((frame as Record<string, unknown>).type ?? '')
  )
}

Deno.test('two tool calls in one response are answered strictly in arrival order', async () => {
  // `propose_intake` resolves LAST despite arriving FIRST. Without the chain
  // its `session.update` would land after `lookup_flock`'s `response.create`,
  // and the model would answer the data-entry request with the core
  // catalogue it started the call with.
  let releaseSlow: (() => void) | null = null
  const slow = new Promise<void>((resolve) => {
    releaseSlow = resolve
  })
  const { feed, socket, session } = await build({
    // The upgrade's `session.updated` ack cannot be fed from inside the
    // chained handler, so let it hit its (here, tiny) bounded timeout rather
    // than making the test wait out the production one.
    intakeUpgradeAckTimeoutMs: 5,
    executors: {
      propose_intake: async () => {
        await slow
        return { status: 'succeeded' as const, result: { ok: true } }
      },
      lookup_flock: () =>
        Promise.resolve({ status: 'succeeded' as const, result: { ok: true } }),
    },
  })
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })

  const first = feed(toolCall('resp_1', 'call_intake', 'propose_intake'))
  const second = feed(toolCall('resp_1', 'call_lookup', 'lookup_flock'))
  // Nothing may have gone out for the second call while the first is stuck.
  assertEquals(creates(socket).length, 0)

  releaseSlow!()
  await first
  await second

  const order = sentTypes(socket)
  const intakeOutput = order.indexOf('conversation.item.create')
  const upgrade = order.indexOf('session.update')
  const firstCreate = order.indexOf('response.create')
  assert(intakeOutput >= 0 && upgrade >= 0 && firstCreate >= 0)
  // The intake output, then its catalogue upgrade, then any response.create.
  assert(
    intakeOutput < upgrade && upgrade < firstCreate,
    `expected output -> session.update -> response.create, got ${order.join(', ')}`,
  )
  assertEquals(session.stopped, false)
})

Deno.test('both tool names from one response land on the SINGLE follow-up telemetry row', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed(toolCall('resp_1', 'call_a', 'lookup_flock'))
  await feed(toolCall('resp_1', 'call_b', 'lookup_flock'))
  // One response follows both outputs.
  await feed({ type: 'response.created', response: { id: 'resp_cont' } })
  await feed({
    type: 'response.done',
    response: { id: 'resp_cont', status: 'completed', object: 'realtime.response' },
  })

  const usage = [...store.responseUsage.values()]
    .find((row) => row.responseId === 'resp_cont')
  assert(usage)
  assertEquals(usage.followedToolCall, true)
  // Both names on ONE row — not split across two, where the second would be
  // falsely recorded as having followed no tool at all.
  assertEquals(usage.toolNames, ['lookup_flock', 'lookup_flock'])
})

Deno.test('a barge-in drops tool names still waiting for a response that never came', async () => {
  const { feed, store } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed(toolCall('resp_1', 'call_a'))

  // The caller interrupts before the follow-up response ever opens. Those
  // queued names belong to an utterance that is over; stamping them onto the
  // next utterance's response would misattribute the telemetry.
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_2' })
  await feed({ type: 'response.created', response: { id: 'resp_2' } })
  await feed({
    type: 'response.done',
    response: { id: 'resp_2', status: 'completed', object: 'realtime.response' },
  })

  const usage = [...store.responseUsage.values()]
    .find((row) => row.responseId === 'resp_2')
  assert(usage)
  assertEquals(usage.followedToolCall, false)
  assertEquals(usage.toolNames, [])
  assertEquals(usage.interactionId, 'item:item_2')
})

// ---------------------------------------------------------------------------
// A refused `response.create` must not become silence.
// ---------------------------------------------------------------------------

/** The `error` event the provider sends when it refuses a frame. */
function providerError(
  eventId: string,
  code: string,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    type: 'error',
    error: { type: 'invalid_request_error', code, event_id: eventId, ...extra },
  }
}

/** The `event_id` the sideband stamped on its most recent `response.create`. */
function lastCreateEventId(socket: FakeSidebandSocket): string {
  const sent = creates(socket)
  return String(sent[sent.length - 1].event_id ?? '')
}

Deno.test('a refused forced final is retried once, plainly, so the caller still gets an answer', async () => {
  const capture = captureLogs()
  try {
    const { feed, socket } = await build()
    const limit = testConfig().maxToolCallsPerInteraction
    await exhaustBudget(feed, limit, 1)

    const final = creates(socket)[limit]
    assertEquals(toolChoiceOf(final), 'none')
    // The provider refuses the per-response override. Nothing is generated:
    // without a fallback the caller sits in silence at the exact moment they
    // were owed the final answer, and the interaction is already closed to
    // further continuations.
    await feed(providerError(lastCreateEventId(socket), 'invalid_value', {
      param: 'response.tool_choice',
    }))

    const sent = creates(socket)
    assertEquals(sent.length, limit + 2)
    // Retried WITHOUT the override — answering plainly beats not answering.
    assertEquals(toolChoiceOf(sent[limit + 1]), undefined)
    const logged = capture.lines
      .map((line) => JSON.parse(line))
      .filter((line) => line.event === 'sideband.final_response_fallback')
    assertEquals(logged.length, 1)
    assertEquals(logged[0].interaction_id, 'item:item_1')
  } finally {
    capture.restore()
  }
})

Deno.test('the forced-final fallback fires at most once per interaction', async () => {
  const { feed, socket } = await build()
  const limit = testConfig().maxToolCallsPerInteraction
  await exhaustBudget(feed, limit, 1)

  await feed(providerError(lastCreateEventId(socket), 'invalid_value'))
  const afterFirst = creates(socket).length
  // The retry is refused too. There is no third attempt — a provider that
  // will not open a response is not going to be argued into it.
  await feed(providerError(lastCreateEventId(socket), 'invalid_value'))
  assertEquals(creates(socket).length, afterFirst)
})

Deno.test('an active-response refusal is not silence and triggers no retry', async () => {
  const { feed, socket, session } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed(toolCall('resp_1', 'call_1'))
  const before = creates(socket).length

  // The routine barge-in outcome: a response is already in flight and WILL
  // speak. Retrying would be the duplicate answer, not the fix.
  await feed(
    providerError(
      lastCreateEventId(socket),
      'conversation_already_has_active_response',
    ),
  )
  assertEquals(creates(socket).length, before)
  assertEquals(session.stopped, false)
})

Deno.test('a refused ordinary continuation tells the client rather than dying quietly', async () => {
  const notices: string[] = []
  const { feed, socket } = await build({ onNotice: (code) => notices.push(code) })
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed(toolCall('resp_1', 'call_1'))
  const before = creates(socket).length

  await feed(providerError(lastCreateEventId(socket), 'server_error'))

  // No retry for an ordinary continuation — but the app is told, so it can
  // show something instead of leaving the caller staring at dead air.
  assertEquals(creates(socket).length, before)
  assertEquals(notices, ['response_create_rejected'])
})

Deno.test('an error naming a different frame never touches the outstanding response', async () => {
  const { feed, socket } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  await feed(toolCall('resp_1', 'call_1'))
  const before = creates(socket).length

  await feed(providerError('evt_something_else', 'invalid_value'))
  assertEquals(creates(socket).length, before)

  // …and once the response actually opens, a late unrelated error cannot
  // resurrect a frame that is no longer outstanding.
  await feed({ type: 'response.created', response: { id: 'resp_cont_1' } })
  await feed(providerError(lastCreateEventId(socket), 'invalid_value'))
  assertEquals(creates(socket).length, before)
})
