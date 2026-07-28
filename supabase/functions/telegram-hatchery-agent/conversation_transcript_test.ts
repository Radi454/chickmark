import { assert, assertEquals } from '@std/assert'

import type {
  AgentModelRequest,
  AgentModelResponse,
  AgentProvider,
} from './agent_provider.ts'
import {
  type AgentConversation,
  type AgentIntakeContext,
  MemoryAgentIntakeStore,
} from './agent_intake_store.ts'
import {
  type AgentIntakeContextResolver,
  createAgentIntakeToolHandlers,
} from './agent_intake_tools.ts'
import { runAgentTurn } from './agent_runtime.ts'
import { executeAgentTool } from './agent_tools.ts'

const scope = {
  staffLinkId: 'staff-a',
  accessRole: 'customer' as const,
  allowedCustomerIds: ['customer-a'],
}
const startedAt = new Date('2026-07-28T12:00:00.000Z')

class TranscriptProvider implements AgentProvider {
  readonly requests: AgentModelRequest[] = []

  constructor(private readonly responses: AgentModelResponse[]) {}

  respond(request: AgentModelRequest): Promise<AgentModelResponse> {
    this.requests.push(structuredClone(request))
    const response = this.responses.shift()
    if (!response) throw new Error('Transcript response missing')
    return Promise.resolve(response)
  }
}

Deno.test('natural bilingual transcript completes two schemas in one visit', async () => {
  const store = new MemoryAgentIntakeStore()
  const conversation: AgentConversation = {
    id: 'conversation-a',
    staffLinkId: 'staff-a',
    telegramChatId: 'chat-a',
    stateVersion: 1,
    pendingAction: null,
    activeVisitId: null,
    createdAt: startedAt.toISOString(),
    updatedAt: startedAt.toISOString(),
  }
  await store.createConversation(conversation)
  const resolver: AgentIntakeContextResolver = {
    resolveFlockSector: (_scope, requested) =>
      Promise.resolve(
        requested.customerId === 'customer-a' &&
          requested.flockId === 'flock-a'
          ? 'breeder'
          : null,
      ),
    resolve: (_scope, requested) =>
      Promise.resolve(
        requested.customerId === 'customer-a' &&
          requested.flockId === 'flock-a' &&
          requested.hatcheryId === 'hatchery-a'
          ? context()
          : null,
      ),
  }
  let generated = 0
  const handlers = createAgentIntakeToolHandlers({
    store,
    contextResolver: resolver,
    now: () => startedAt,
    createId: () => `generated-${++generated}`,
  })
  const replies: string[] = []

  await turn({
    index: 1,
    text: 'عايز أسجل بيانات الفقس النهارده',
    responses: [
      tool('propose_intake', { customerId: 'customer-a' }, 1),
      message('أكيد. هل تريد أن نبدأ إدخال بيانات هذا القطيع الآن؟', 2),
    ],
    store,
    handlers,
    replies,
  })
  assertEquals(
    replies.at(-1),
    'أكيد. هل تريد أن نبدأ إدخال بيانات هذا القطيع الآن؟',
  )
  assertEquals((await store.listSessions()).length, 0)

  await turn({
    index: 2,
    text: 'أيوه، نبدأ',
    responses: [
      tool(
        'list_applicable_stations',
        { customerId: 'customer-a', flockId: 'flock-a' },
        3,
      ),
      message(
        'تمام. عندنا 18 محطة مناسبة للقطيع، منها باسجار، أوزان الكتاكيت، وكسر البيض. تختار أنهي واحدة؟',
        4,
      ),
    ],
    store,
    handlers,
    replies,
  })
  assert(
    replies.at(-1)!.includes('18 محطة'),
  )
  assertEquals((await store.listSessions()).length, 0)

  await turn({
    index: 3,
    text: 'Pasgar بتاع جودة الكتاكيت',
    responses: [
      tool(
        'load_station_schema',
        { schemaKey: 'chicks.pasgar', schemaVersion: 1 },
        5,
      ),
      tool('start_intake', {
        pendingActionId: 'generated-1',
        schemaKey: 'chicks.pasgar',
        schemaVersion: 1,
        customerId: 'customer-a',
        flockId: 'flock-a',
        hatcheryId: 'hatchery-a',
        auditDate: '2026-07-28',
        layer: 'pool',
      }, 6),
      message(
        'تمام، ابعت حجم العينة وأعداد reflexes, beak, navel, belly, legs وfeather development بأي ترتيب.',
        7,
      ),
    ],
    store,
    handlers,
    replies,
  })

  await turn({
    index: 4,
    text: 'sample 40، navel 3، reflexes 2، beak 1، belly 1، legs 2، feather 3',
    responses: [
      tool('record_station_values', {
        intakeId: 'generated-3',
        expectedRowVersion: 1,
        values: [
          candidate('pasgarNavelCount', 3, 'navel 3'),
          candidate('pasgarSampleSize', 40, 'sample 40'),
          candidate('pasgarReflexesCount', 2, 'reflexes 2'),
          candidate('pasgarBeakCount', 1, 'beak 1'),
          candidate('pasgarBellyCount', 1, 'belly 1'),
          candidate('pasgarLegCount', 2, 'legs 2'),
          candidate('pasgarFeatherDevCount', 3, 'feather 3'),
        ],
      }, 8),
      tool('create_station_summary', {
        intakeId: 'generated-3',
        expectedRowVersion: 2,
      }, 9),
      message(
        'ملخص باسجار: العينة 40، reflexes 2، beak 1، navel 3، belly 1، legs 2، feather 3، والنتيجة 9.8. هل الملخص صحيح؟',
        10,
      ),
    ],
    store,
    handlers,
    replies,
  })
  assert(replies.at(-1)!.includes('هل الملخص صحيح؟'))

  await turn({
    index: 5,
    text: 'navel should be 4, the rest is right',
    responses: [
      tool('record_station_values', {
        intakeId: 'generated-3',
        expectedRowVersion: 3,
        values: [candidate('pasgarNavelCount', 4, 'navel should be 4')],
      }, 11),
      tool('create_station_summary', {
        intakeId: 'generated-3',
        expectedRowVersion: 4,
      }, 12),
      message(
        'Updated: navel is 4 and the Pasgar score remains 9.8. Is this corrected summary right?',
        13,
      ),
    ],
    store,
    handlers,
    replies,
  })
  assertEquals(
    (await store.loadSession('generated-3'))!.summaryVersion,
    2,
  )

  await turn({
    index: 6,
    text: 'Yes, this summary is correct',
    responses: [
      tool('confirm_station_summary', {
        intakeId: 'generated-3',
        expectedRowVersion: 5,
        summaryVersion: 2,
      }, 14),
      tool('submit_station_for_review', {
        intakeId: 'generated-3',
        expectedRowVersion: 6,
      }, 15),
      message('Thanks — Pasgar is now waiting for administrator review.', 16),
    ],
    store,
    handlers,
    replies,
  })
  assertEquals(
    (await store.loadSession('generated-3'))!.state,
    'awaiting_admin_review',
  )

  await turn({
    index: 7,
    text: 'وكمان عايز أضيف أوزان الكتاكيت لنفس الزيارة',
    responses: [
      tool('propose_intake', { customerId: 'customer-a' }, 17),
      message('أكيد، أبدأ محطة أوزان الكتاكيت لنفس الزيارة؟', 18),
    ],
    store,
    handlers,
    replies,
  })
  await turn({
    index: 8,
    text: 'نعم ابدأ',
    responses: [
      tool(
        'load_station_schema',
        { schemaKey: 'chicks.weights', schemaVersion: 1 },
        19,
      ),
      tool('start_intake', {
        pendingActionId: 'generated-4',
        schemaKey: 'chicks.weights',
        schemaVersion: 1,
        customerId: 'customer-a',
        flockId: 'flock-a',
        hatcheryId: 'hatchery-a',
        auditDate: '2026-07-28',
        layer: 'pool',
      }, 20),
      message('تمام، ابعت أوزان الكتاكيت بالجرام.', 21),
    ],
    store,
    handlers,
    replies,
  })
  await turn({
    index: 9,
    text: '40, 44, 48 grams',
    responses: [
      tool('record_station_values', {
        intakeId: 'generated-5',
        expectedRowVersion: 1,
        values: [
          candidate('weightsJson', [40, 44, 48], '40, 44, 48 grams'),
        ],
      }, 22),
      tool('create_station_summary', {
        intakeId: 'generated-5',
        expectedRowVersion: 2,
      }, 23),
      message(
        'Weights summary: 40, 44, 48 g; average 44 g, CV 9.1%, uniformity 100%. Is that right?',
        24,
      ),
    ],
    store,
    handlers,
    replies,
  })
  await turn({
    index: 10,
    text: 'Correct',
    responses: [
      tool('confirm_station_summary', {
        intakeId: 'generated-5',
        expectedRowVersion: 3,
        summaryVersion: 1,
      }, 25),
      tool('submit_station_for_review', {
        intakeId: 'generated-5',
        expectedRowVersion: 4,
      }, 26),
      message('Both stations are organized and waiting for admin review.', 27),
    ],
    store,
    handlers,
    replies,
  })

  const sessions = await store.listSessions()
  assertEquals(sessions.length, 2)
  assertEquals(sessions.map((session) => session.visitId), [
    'generated-2',
    'generated-2',
  ])
  assertEquals(
    sessions.map((session) => session.state),
    ['awaiting_admin_review', 'awaiting_admin_review'],
  )
  assertEquals(await store.countOperationalRows(), 0)
})

async function turn(params: {
  index: number
  text: string
  responses: AgentModelResponse[]
  store: MemoryAgentIntakeStore
  handlers: ReturnType<typeof createAgentIntakeToolHandlers>
  replies: string[]
}): Promise<void> {
  const provider = new TranscriptProvider(params.responses)
  const conversation = (await params.store.loadConversation('conversation-a'))!
  const sessions = await params.store.listSessions()
  const active = sessions
    .filter((session) => session.visitId === conversation.activeVisitId)
    .at(-1) ?? null
  const result = await runAgentTurn(
    {
      scope,
      conversationId: conversation.id,
      activeVisitId: conversation.activeVisitId,
      conversationTurnId: `turn-${params.index}`,
      conversationTurnIndex: params.index,
      text: params.text,
      recentTurns: [],
      pendingAction: conversation.pendingAction,
      activeIntake: active,
    },
    {
      provider,
      executeTool: (call) =>
        executeAgentTool(call, {
          scope,
          conversationId: conversation.id,
          activeVisitId: conversation.activeVisitId,
          conversationTurnId: `turn-${params.index}`,
          conversationTurnIndex: params.index,
          evidence: { record: () => undefined },
          handlers: params.handlers,
        }),
    },
  )
  assertEquals(result.status, 'replied')
  if (result.status === 'replied') params.replies.push(result.reply)
}

function tool(
  name: string,
  args: Record<string, unknown>,
  sequence: number,
): AgentModelResponse {
  return {
    id: `response-${sequence}`,
    output: [{
      type: 'function_call',
      id: `function-${sequence}`,
      call_id: `call-${sequence}`,
      name,
      arguments: JSON.stringify(args),
    }],
  }
}

function message(text: string, sequence: number): AgentModelResponse {
  return {
    id: `response-${sequence}`,
    output: [{
      type: 'message',
      role: 'assistant',
      content: [{ type: 'output_text', text }],
    }],
  }
}

function candidate(
  fieldKey: string,
  value: unknown,
  sourcePhrase: string,
) {
  return { fieldKey, value, sourcePhrase, confidence: 0.99 }
}

function context(): AgentIntakeContext {
  return {
    customerId: 'customer-a',
    customerName: 'Customer A',
    flockId: 'flock-a',
    flockName: 'Ross 308',
    hatcheryId: 'hatchery-a',
    hatcheryName: 'Main Hatchery',
    auditDate: '2026-07-28',
    layer: 'pool',
    setterIdentity: null,
    hatcherIdentity: null,
    sectorKey: 'breeder',
  }
}
