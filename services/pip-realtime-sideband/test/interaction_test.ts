import { assert, assertEquals, assertThrows } from '@std/assert'
import { InteractionTracker } from '../src/interaction.ts'
import './fakes.ts'

function consume(tracker: InteractionTracker, responseId: string, times: number): number {
  let allowed = 0
  for (let i = 0; i < times; i++) {
    if (tracker.tryConsumeToolBudget(responseId).allowed) allowed += 1
  }
  return allowed
}

Deno.test('interaction id comes from the committed input item, not the transcript', () => {
  const tracker = new InteractionTracker(5)
  const id = tracker.noteInputCommitted('item_abc')
  assertEquals(id, 'item:item_abc')
  assertEquals(tracker.noteResponseCreated('resp_1'), 'item:item_abc')
})

Deno.test('a response with no user input falls back to resp:<root_response_id>', () => {
  const tracker = new InteractionTracker(5)
  assertEquals(tracker.noteResponseCreated('resp_root'), 'resp:resp_root')
})

Deno.test('the 6th tool call in one interaction is rejected', () => {
  const tracker = new InteractionTracker(5)
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')

  assertEquals(consume(tracker, 'resp_1', 5), 5)
  const sixth = tracker.tryConsumeToolBudget('resp_1')
  assert(!sixth.allowed)
  assertEquals(sixth.reason, 'interaction_tool_limit')
  assertEquals(sixth.used, 5)
  assertEquals(sixth.limit, 5)
})

Deno.test('the cap follows the CHAIN: tool continuations share one budget', () => {
  const tracker = new InteractionTracker(5)
  tracker.noteInputCommitted('item_1')
  const interactionId = tracker.noteResponseCreated('resp_1')

  // Three tools in the first response, then a continuation response.
  assertEquals(consume(tracker, 'resp_1', 3), 3)
  tracker.noteToolOutputSubmitted(interactionId)
  assertEquals(tracker.noteResponseCreated('resp_1_cont'), interactionId)

  // The continuation inherits the SAME budget: only two calls remain.
  assertEquals(consume(tracker, 'resp_1_cont', 5), 2)
  assertEquals(tracker.toolCallsUsed(interactionId), 5)
})

Deno.test('a NEW interaction gets a fresh budget', () => {
  const tracker = new InteractionTracker(5)
  tracker.noteInputCommitted('item_1')
  tracker.noteResponseCreated('resp_1')
  assertEquals(consume(tracker, 'resp_1', 6), 5)

  tracker.noteInputCommitted('item_2')
  tracker.noteResponseCreated('resp_2')
  assertEquals(consume(tracker, 'resp_2', 5), 5)
  assertEquals(tracker.toolCallsUsed('item:item_2'), 5)
})

Deno.test('one generation with 3 interactions allows 15 tool calls, never 5', () => {
  const tracker = new InteractionTracker(5)
  let total = 0
  for (const suffix of ['a', 'b', 'c']) {
    tracker.noteInputCommitted(`item_${suffix}`)
    tracker.noteResponseCreated(`resp_${suffix}`)
    total += consume(tracker, `resp_${suffix}`, 8)
  }
  assertEquals(total, 15)
  assertEquals(tracker.interactionCount, 3)
})

Deno.test('barge-in re-roots the chain: the new utterance is a new interaction', () => {
  const tracker = new InteractionTracker(5)
  tracker.noteInputCommitted('item_1')
  const first = tracker.noteResponseCreated('resp_1')
  consume(tracker, 'resp_1', 5)
  tracker.noteToolOutputSubmitted(first)

  // The user speaks over the assistant before the continuation opens.
  tracker.noteInputCommitted('item_2')
  const second = tracker.noteResponseCreated('resp_2')
  assertEquals(second, 'item:item_2')
  assertEquals(consume(tracker, 'resp_2', 5), 5)
})

Deno.test('attribution is stable across redelivery of the same response id', () => {
  const tracker = new InteractionTracker(5)
  tracker.noteInputCommitted('item_1')
  const first = tracker.noteResponseCreated('resp_1')
  assertEquals(tracker.noteResponseCreated('resp_1'), first)
  assertEquals(tracker.interactionForResponse('resp_1'), first)
})

Deno.test('a response that produced no tool call closes its chain', () => {
  const tracker = new InteractionTracker(5)
  tracker.noteInputCommitted('item_1')
  const first = tracker.noteResponseCreated('resp_1')
  tracker.noteToolOutputSubmitted(first)
  tracker.noteResponseDone('resp_1', false)
  // With the chain closed, an unsolicited later response is its own interaction.
  assertEquals(tracker.noteResponseCreated('resp_later'), 'resp:resp_later')
})

Deno.test('lookupInteractionForResponse is a pure read: null for an unseen response, no minting', () => {
  const tracker = new InteractionTracker(5)
  tracker.noteInputCommitted('item_1')

  // 'resp_unseen' never had a 'response.created' (or any other event) note
  // it, unlike 'item_1' whose commit is still pending root attribution.
  assertEquals(tracker.lookupInteractionForResponse('resp_unseen'), null)
  // The pure lookup must not have consumed the pending root interaction or
  // otherwise minted anything: the interaction opened by noteInputCommitted
  // is the only one that exists, and it is still available to attribute to
  // the actual response that follows.
  assertEquals(tracker.interactionCount, 1)
  assertEquals(tracker.noteResponseCreated('resp_1'), 'item:item_1')
})

Deno.test('lookupInteractionForResponse returns the same answer as interactionForResponse once attributed', () => {
  const tracker = new InteractionTracker(5)
  tracker.noteInputCommitted('item_1')
  const id = tracker.noteResponseCreated('resp_1')
  assertEquals(tracker.lookupInteractionForResponse('resp_1'), id)
  assertEquals(tracker.interactionForResponse('resp_1'), id)
})

Deno.test('a nonsensical limit fails loudly at construction', () => {
  assertThrows(() => new InteractionTracker(0), Error, 'positive integer')
  assertThrows(() => new InteractionTracker(2.5), Error, 'positive integer')
})

Deno.test('the tracker maps are bounded, so a long call cannot grow them without limit', () => {
  const tracker = new InteractionTracker(5)
  for (let index = 0; index < 700; index++) {
    tracker.noteInputCommitted(`item_${index}`)
    tracker.noteResponseCreated(`resp_${index}`)
  }
  // Bounded — and the newest interaction is still fully attributed, which is
  // the only one a live turn can be using.
  assert(tracker.interactionCount <= 512)
  assertEquals(tracker.interactionForResponse('resp_699'), 'item:item_699')
  assertEquals(tracker.tryConsumeToolBudget('resp_699').allowed, true)
})
