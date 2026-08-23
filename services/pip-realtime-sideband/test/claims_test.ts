import { assert, assertEquals } from '@std/assert'
import { ToolCallCoordinator, type ToolExecutor } from '../src/claims.ts'
import { InteractionTracker } from '../src/interaction.ts'
import { argumentHash } from '../src/ids.ts'
import { FakeClock, FakeStore } from './fakes.ts'

function build(
  options: {
    executor?: ToolExecutor
    limit?: number
    ledger?: 'sideband' | 'broker'
    liveness?: () => string | null
  } = {},
) {
  const store = new FakeStore()
  const clock = new FakeClock()
  const tracker = new InteractionTracker(options.limit ?? 5)
  const calls: unknown[] = []
  const executor: ToolExecutor = options.executor ?? ((args) => {
    calls.push(args)
    return Promise.resolve({ status: 'succeeded', result: { ok: true } })
  })
  const coordinator = new ToolCallCoordinator({
    store,
    tracker,
    sessionId: 'sess_1',
    generation: 1,
    leaseOwner: 'worker_a',
    leaseSeconds: 30,
    authorizationFingerprint: 'admin:all',
    now: clock.now,
    ownership: {
      ledger: options.ledger ?? 'sideband',
      executors: new Map([['lookup_flock', executor]]),
    },
    liveness: options.liveness,
  })
  return { store, clock, tracker, coordinator, calls }
}

function toolCall(overrides: Record<string, unknown> = {}) {
  return {
    responseId: 'resp_1',
    toolCallId: 'call_1',
    toolName: 'lookup_flock',
    args: { flock_id: 'flock_1' },
    ...overrides,
  }
}

Deno.test('a tool is claimed before it executes, then evidenced and settled', async () => {
  const { store, coordinator, tracker, calls } = build()
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  const result = await coordinator.handleToolCall(toolCall())
  assertEquals(result.disposition, 'executed')
  assertEquals(calls.length, 1)

  const claim = await store.loadToolClaim('sess_1', 1, 'call_1')
  assert(claim)
  assertEquals(claim.state, 'succeeded')
  assertEquals(claim.realtimeInteractionId, 'item:item_1')

  assertEquals(store.toolEvents.length, 1)
  assertEquals(store.toolEvents[0].realtimeInteractionId, 'item:item_1')
  assertEquals(store.toolEvents[0].toolSequence, 1)
})

Deno.test('a repeated tool_call_id is idempotent: the side effect runs once', async () => {
  const { coordinator, tracker, calls, store } = build()
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  const first = await coordinator.handleToolCall(toolCall())
  const second = await coordinator.handleToolCall(toolCall())

  assertEquals(first.disposition, 'executed')
  assertEquals(second.disposition, 'duplicate')
  assertEquals(calls.length, 1)
  assertEquals(store.toolEvents.length, 1)
  // A duplicate still answers the model, or the response chain would hang.
  assert(second.output !== undefined)
})

Deno.test('the same call id with different arguments is rejected, not executed', async () => {
  const { coordinator, tracker, calls } = build()
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  await coordinator.handleToolCall(toolCall())
  const conflicting = await coordinator.handleToolCall(
    toolCall({ args: { flock_id: 'flock_DIFFERENT' } }),
  )

  assertEquals(conflicting.disposition, 'rejected_argument_mismatch')
  assertEquals(calls.length, 1)
})

Deno.test('argument hashing ignores key order so a reorder is still a duplicate', async () => {
  const a = await argumentHash({ b: 2, a: 1 })
  const b = await argumentHash({ a: 1, b: 2 })
  assertEquals(a, b)
  const different = await argumentHash({ a: 1, b: 3 })
  assert(a !== different)
})

Deno.test('the 6th call of an interaction is rejected without executing or claiming', async () => {
  const { coordinator, tracker, calls, store } = build()
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  for (let i = 1; i <= 5; i++) {
    await coordinator.handleToolCall(toolCall({ toolCallId: `call_${i}` }))
  }
  const sixth = await coordinator.handleToolCall(toolCall({ toolCallId: 'call_6' }))

  assertEquals(sixth.disposition, 'rejected_tool_limit')
  assertEquals(calls.length, 5)
  assertEquals(store.toolEvents.length, 5)
  assertEquals(await store.loadToolClaim('sess_1', 1, 'call_6'), null)
})

Deno.test('a tool runs with NO inbound turn, and the CLAIM is back-filled later', async () => {
  const { coordinator, store, tracker } = build()
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  // The transcript has not finalized — and may never. The tool still runs.
  await coordinator.handleToolCall(toolCall())
  const beforeClaim = await store.loadToolClaim('sess_1', 1, 'call_1')
  assertEquals(beforeClaim?.inboundTurnId, null)
  assertEquals(store.toolEvents[0].conversationTurnId, null)

  const linked = await coordinator.backfillInboundTurn('item:item_1', 'turn_99')
  assertEquals(linked, 1)

  const afterClaim = await store.loadToolClaim('sess_1', 1, 'call_1')
  assertEquals(afterClaim?.inboundTurnId, 'turn_99')
  // Evidence is immutable: the event row still carries NULL, by design.
  assertEquals(store.toolEvents[0].conversationTurnId, null)
  assertEquals(store.toolEvents.length, 1)
})

Deno.test('back-fill is idempotent and never rewrites an existing link', async () => {
  const { coordinator, store, tracker } = build()
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')
  await coordinator.handleToolCall(toolCall())

  assertEquals(await coordinator.backfillInboundTurn('item:item_1', 'turn_99'), 1)
  assertEquals(await coordinator.backfillInboundTurn('item:item_1', 'turn_OTHER'), 0)
  const claim = await store.loadToolClaim('sess_1', 1, 'call_1')
  assertEquals(claim?.inboundTurnId, 'turn_99')
})

Deno.test('evidence rows are written once and never mutated', async () => {
  const { coordinator, store, tracker } = build()
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')
  await coordinator.handleToolCall(toolCall())
  const snapshot = { ...store.toolEvents[0] }

  await coordinator.handleToolCall(toolCall())
  await coordinator.backfillInboundTurn('item:item_1', 'turn_99')

  assertEquals(store.toolEvents.length, 1)
  assertEquals(store.toolEvents[0], snapshot)
  assertEquals(store.evidenceMutationAttempts, 0)
})

Deno.test('a failing tool still answers the model and records failed evidence', async () => {
  const { coordinator, store, tracker } = build({
    executor: () => Promise.reject(new Error('boom')),
  })
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  const result = await coordinator.handleToolCall(toolCall())
  assertEquals(result.disposition, 'failed')
  assertEquals(store.toolEvents[0].status, 'failed')
  const claim = await store.loadToolClaim('sess_1', 1, 'call_1')
  assertEquals(claim?.state, 'failed')
  assert(result.output !== undefined)
})

Deno.test('an unknown tool is rejected without a claim', async () => {
  const { coordinator, store, tracker } = build()
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')
  const result = await coordinator.handleToolCall(
    toolCall({ toolName: 'delete_everything' }),
  )
  assertEquals(result.disposition, 'rejected_unknown_tool')
  assertEquals(store.claims.size, 0)
})

// ---------------------------------------------------------------------------
// BROKERED ownership. The broker wrote the claim and the evidence around the
// tool it executed; both tables carry partial unique indexes on the Realtime
// key, so a second write from here would RAISE — and a throw inside the tool
// path would leave the model's `function_call_output` unsent and the call
// hanging. Nothing below may touch either table.
// ---------------------------------------------------------------------------

Deno.test('brokered: no claim and no evidence are written, and the model is answered', async () => {
  const { coordinator, store, tracker, calls } = build({ ledger: 'broker' })
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  const result = await coordinator.handleToolCall(toolCall())

  assertEquals(result.disposition, 'executed')
  assertEquals(calls.length, 1)
  assertEquals(store.claims.size, 0)
  assertEquals(store.toolEvents.length, 0)
  assertEquals(result.output, { ok: true })
})

Deno.test('brokered: the per-interaction budget is still spent and still enforced', async () => {
  const { coordinator, tracker, calls, store } = build({ ledger: 'broker' })
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  for (let i = 1; i <= 5; i++) {
    await coordinator.handleToolCall(toolCall({ toolCallId: `call_${i}` }))
  }
  const sixth = await coordinator.handleToolCall(toolCall({ toolCallId: 'call_6' }))

  assertEquals(sixth.disposition, 'rejected_tool_limit')
  assertEquals(calls.length, 5)
  // The cap is the sideband's, not the broker's: it is spent before the network.
  assertEquals(store.claims.size, 0)
  assertEquals(store.toolEvents.length, 0)
})

Deno.test('brokered: a duplicate the broker replays is reported as a duplicate', async () => {
  const { coordinator, store, tracker } = build({
    ledger: 'broker',
    executor: () =>
      Promise.resolve({
        status: 'succeeded',
        result: { ok: true, code: 'ok', data: null },
        duplicate: true,
      }),
  })
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  const result = await coordinator.handleToolCall(toolCall())

  // The sideband keeps no claim of its own, so the broker's word decides — and
  // its recorded result is forwarded verbatim, not replaced with a stub.
  assertEquals(result.disposition, 'duplicate')
  assertEquals(result.output, { ok: true, code: 'ok', data: null })
  assertEquals(store.claims.size, 0)
  assertEquals(store.toolEvents.length, 0)
})

Deno.test('brokered: a redelivered call id is NOT deduplicated locally', async () => {
  // Local dedup would need a local claim, and the local claim is what caused the
  // unique violation. The broker is the only component that may decide this.
  const { coordinator, tracker, calls } = build({ ledger: 'broker' })
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  await coordinator.handleToolCall(toolCall())
  await coordinator.handleToolCall(toolCall())

  assertEquals(calls.length, 2)
})

Deno.test('brokered: a broker error is surfaced as a real error, never as success', async () => {
  const { coordinator, store, tracker } = build({
    ledger: 'broker',
    executor: () =>
      Promise.resolve({
        status: 'failed',
        result: { ok: false, error: 'broker_unreachable' },
      }),
  })
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  const result = await coordinator.handleToolCall(toolCall())

  assertEquals(result.disposition, 'failed')
  assertEquals(result.output, { ok: false, error: 'broker_unreachable' })
  assertEquals(store.toolEvents.length, 0)
})

Deno.test('brokered: an executor that THROWS still answers the model', async () => {
  const { coordinator, store, tracker } = build({
    ledger: 'broker',
    executor: () => Promise.reject(new TypeError('network')),
  })
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  const result = await coordinator.handleToolCall(toolCall())

  assertEquals(result.disposition, 'failed')
  assertEquals(result.output, {
    ok: false,
    error: 'tool_failed',
    detail: 'TypeError',
  })
  assertEquals(store.claims.size, 0)
  assertEquals(store.toolEvents.length, 0)
})

Deno.test('brokered: an unknown tool is refused without reaching the broker', async () => {
  const { coordinator, calls, tracker } = build({ ledger: 'broker' })
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  const result = await coordinator.handleToolCall(
    toolCall({ toolName: 'delete_everything' }),
  )

  assertEquals(result.disposition, 'rejected_unknown_tool')
  assertEquals(calls.length, 0)
})

Deno.test('a lost fence refuses the call before budget, claim or execution', async () => {
  for (const ledger of ['sideband', 'broker'] as const) {
    const { coordinator, store, tracker, calls } = build({
      ledger,
      liveness: () => 'fence_lost',
    })
    tracker.noteInputCommitted('item_1')
    tracker.noteResponseCreated('resp_1')

    const result = await coordinator.handleToolCall(toolCall())

    assertEquals(result.disposition, 'rejected_not_live')
    assertEquals(calls.length, 0)
    assertEquals(store.claims.size, 0)
    assertEquals(store.toolEvents.length, 0)
    // Budget is untouched: a refused call must not cost the next owner a slot.
    assertEquals(tracker.toolCallsUsed('item:item_1'), 0)
    // And the model still gets a real answer rather than silence.
    assert(result.output !== undefined)
  }
})
