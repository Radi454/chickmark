// Conversation integrity across reconnects and across threads.
//
// Two failures this pins against, both of which would look to a caller like
// Pip repeating itself:
//
//  1. RECONNECT REPLAY. A dropped call reconnects on a new generation and the
//     sideband injects the conversation's recent finalized turns. Injection
//     must add CONTEXT and nothing else — if it ever also asked the provider
//     for a response, every reconnect would re-speak the answer the caller
//     already heard.
//  2. CROSS-THREAD BLEED. Pip is conversation-centric: one caller has many
//     threads and each has its own history. A live call injects the turns of
//     ITS conversation and epoch only; pulling another thread's turns would
//     have the model answer a question that was asked somewhere else.

import { assert, assertEquals } from '@std/assert'
import { SidebandSession } from '../src/sideband.ts'
import { LeaseKeeper } from '../src/lease.ts'
import { testConfig } from '../src/config.ts'
import type { RealtimeToolDefinition } from '../src/session_config.ts'
import { FakeClock, FakeSidebandSocket, FakeStore } from './fakes.ts'
import type { ClientNotice } from '../src/sideband.ts'
import type { TurnInsert } from '../src/store.ts'

const TOOLS: readonly RealtimeToolDefinition[] = [{
  type: 'function',
  name: 'lookup_flock',
  description: 'Look up a flock',
  parameters: { type: 'object', properties: {} },
}]

async function build(
  options: { conversationId?: string; contextEpoch?: number; generation?: number } = {},
) {
  const conversationId = options.conversationId ?? 'conv_1'
  const contextEpoch = options.contextEpoch ?? 1
  const generation = options.generation ?? 1
  const store = new FakeStore({
    session: { conversationId, contextEpoch, activeGeneration: generation },
  })
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
  await lease.claim('sess_1', generation)
  const notices: ClientNotice[] = []
  const session = new SidebandSession({
    config: testConfig(),
    store,
    socket,
    lease,
    session: (await store.loadSession('sess_1'))!,
    generation,
    leaseOwner: 'worker_a',
    tools: TOOLS,
    ownership: { ledger: 'sideband', executors: new Map() },
    notifyClient: (notice) => notices.push(notice),
    now: clock.now,
    instructions: 'You are ChickMark.',
  })
  const feed = (event: Record<string, unknown>) => session.handleEvent(event)
  return { store, socket, session, notices, feed }
}

function seedTurn(
  store: FakeStore,
  overrides: {
    conversationId?: string
    contextEpoch?: number
    conversationSeq: number
    direction: 'inbound' | 'outbound'
    text: string
    completionStatus?: TurnInsert['completionStatus']
  },
): void {
  store.addTurn({
    id: `turn_${overrides.conversationId ?? 'conv_1'}_${overrides.conversationSeq}`,
    conversationId: overrides.conversationId ?? 'conv_1',
    contextEpoch: overrides.contextEpoch ?? 1,
    direction: overrides.direction,
    conversationSeq: overrides.conversationSeq,
    turnIndex: overrides.conversationSeq,
    text: overrides.text,
    language: 'en',
    sourceChannel: 'realtime_voice',
    completionStatus: overrides.completionStatus ?? 'finalized',
    realtimeSessionId: 'sess_1',
    realtimeGeneration: 1,
    providerItemId: null,
    authorizationFingerprint: 'admin:all',
    customerId: null,
    model: null,
    createdAt: '2026-08-16T09:59:30.000Z',
    finalizedAt: null,
    interruptedAt: null,
  })
}

Deno.test('a reconnect injects history as context and never asks for a response', async () => {
  // Generation 2: the caller dropped and dialled back into the same thread.
  const { store, socket, session, feed } = await build({ generation: 2 })
  seedTurn(store, { conversationSeq: 1, direction: 'inbound', text: 'How is Badr doing?' })
  seedTurn(store, {
    conversationSeq: 2,
    direction: 'outbound',
    text: 'Badr hatched 84 percent last week.',
  })

  const configured = session.attachAndConfigure()
  await session.contextInjectionPromise
  await feed({ type: 'session.updated' })
  await configured

  // Both turns went in as conversation items…
  const items = socket.sentOfType('conversation.item.create')
  assertEquals(items.length, 2)
  // …oldest first, with the roles the model needs to read them as a dialogue.
  const roles = items.map((frame) => (frame.item as Record<string, unknown>).role)
  assertEquals(roles, ['user', 'assistant'])
  // And NOTHING asked the provider to speak. A reconnect that replayed the
  // last answer would be indistinguishable, to the caller, from Pip repeating
  // itself.
  assertEquals(socket.sentOfType('response.create').length, 0)
})

Deno.test('a live call injects only its OWN conversation, never a sibling thread', async () => {
  const { store, socket, session, feed } = await build({ conversationId: 'conv_live' })
  seedTurn(store, {
    conversationId: 'conv_live',
    conversationSeq: 1,
    direction: 'inbound',
    text: 'mine',
  })
  seedTurn(store, {
    conversationId: 'conv_other',
    conversationSeq: 1,
    direction: 'inbound',
    text: 'a different thread entirely',
  })

  const configured = session.attachAndConfigure()
  await session.contextInjectionPromise
  await feed({ type: 'session.updated' })
  await configured

  const texts = socket.sentOfType('conversation.item.create').map((frame) => {
    const content = (frame.item as Record<string, unknown>).content as
      Record<string, unknown>[]
    return content[0].text
  })
  assertEquals(texts, ['mine'])
})

Deno.test('a cleared conversation (a newer context epoch) never replays the old epoch', async () => {
  // `reset` bumps context_epoch. Turns from the previous epoch are durable
  // evidence but must never be handed back to the model as live context.
  const { store, socket, session, feed } = await build({ contextEpoch: 2 })
  seedTurn(store, {
    contextEpoch: 1,
    conversationSeq: 1,
    direction: 'outbound',
    text: 'an answer from before the user cleared the thread',
  })
  seedTurn(store, {
    contextEpoch: 2,
    conversationSeq: 2,
    direction: 'inbound',
    text: 'after the reset',
  })

  const configured = session.attachAndConfigure()
  await session.contextInjectionPromise
  await feed({ type: 'session.updated' })
  await configured

  const texts = socket.sentOfType('conversation.item.create').map((frame) => {
    const content = (frame.item as Record<string, unknown>).content as
      Record<string, unknown>[]
    return content[0].text
  })
  assertEquals(texts, ['after the reset'])
})

Deno.test('an interrupted assistant turn is not injected as a finalized answer', async () => {
  const { store, socket, session, feed } = await build()
  seedTurn(store, {
    conversationSeq: 1,
    direction: 'outbound',
    text: 'half a sentence before the caller barged',
    completionStatus: 'interrupted',
  })
  seedTurn(store, { conversationSeq: 2, direction: 'inbound', text: 'never mind' })

  const configured = session.attachAndConfigure()
  await session.contextInjectionPromise
  await feed({ type: 'session.updated' })
  await configured

  const texts = socket.sentOfType('conversation.item.create').map((frame) => {
    const content = (frame.item as Record<string, unknown>).content as
      Record<string, unknown>[]
    return content[0].text
  })
  assertEquals(texts, ['never mind'])
})

Deno.test('a barge-in mid tool chain opens a fresh interaction rather than extending the old one', async () => {
  const { session, feed } = await build()
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_1' })
  await feed({ type: 'response.created', response: { id: 'resp_1' } })
  assertEquals(session.tracker.interactionForResponse('resp_1'), 'item:item_1')

  // The caller speaks over the assistant. Whatever the provider opens next
  // belongs to the NEW utterance and draws on its own budget.
  await feed({ type: 'input_audio_buffer.committed', item_id: 'item_2' })
  await feed({ type: 'response.created', response: { id: 'resp_2' } })
  assertEquals(session.tracker.interactionForResponse('resp_2'), 'item:item_2')
  assert(
    session.tracker.interactionForResponse('resp_1') !==
      session.tracker.interactionForResponse('resp_2'),
  )
})
