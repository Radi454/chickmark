import { assert, assertEquals } from '@std/assert'

import {
  type AgentConversation,
  type AgentIntakeContext,
  MemoryAgentIntakeStore,
} from './agent_intake_store.ts'
import {
  type AgentIntakeContextResolver,
  createAgentIntakeToolHandlers,
} from './agent_intake_tools.ts'
import type { AgentToolResult } from './agent_protocol.ts'
import { executeAgentTool } from './agent_tools.ts'

const scope = {
  staffLinkId: 'staff-a',
  accessRole: 'customer' as const,
  allowedCustomerIds: ['customer-a'],
}
const baseTime = new Date('2026-07-28T12:00:00.000Z')

function harness() {
  const store = new MemoryAgentIntakeStore()
  const conversation: AgentConversation = {
    id: 'conversation-a',
    staffLinkId: 'staff-a',
    telegramChatId: 'chat-a',
    stateVersion: 1,
    pendingAction: null,
    activeVisitId: null,
    createdAt: baseTime.toISOString(),
    updatedAt: baseTime.toISOString(),
  }
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
  let currentTime = baseTime
  let id = 0
  const handlers = createAgentIntakeToolHandlers({
    store,
    contextResolver: resolver,
    now: () => currentTime,
    createId: () => `generated-${++id}`,
  })

  async function call(
    name: string,
    args: Record<string, unknown>,
    turnIndex: number,
  ): Promise<AgentToolResult> {
    return executeAgentTool(
      {
        id: `tool-${turnIndex}-${name}`,
        name,
        arguments: args,
      },
      {
        scope,
        conversationId: conversation.id,
        activeVisitId:
          (await store.loadConversation(conversation.id))?.activeVisitId ??
            null,
        conversationTurnId: `turn-${turnIndex}`,
        conversationTurnIndex: turnIndex,
        evidence: { record: () => undefined },
        handlers,
      },
    )
  }

  return {
    store,
    conversation,
    call,
    setTime(value: Date) {
      currentTime = value
    },
  }
}

Deno.test('station catalog is resolved from the authorized flock sector', async () => {
  const test = harness()
  await test.store.createConversation(test.conversation)

  const catalog = await test.call(
    'list_applicable_stations',
    { customerId: 'customer-a', flockId: 'flock-a' },
    1,
  )
  assert(catalog.ok)
  assertEquals(catalog.data!.sectorKey, 'breeder')
  assertEquals(
    (catalog.data!.stations as unknown[]).length,
    18,
  )
  const stations = catalog.data!.stations as Array<Record<string, unknown>>
  const pasgar = stations.find((station) =>
    station.schemaKey === 'chicks.pasgar'
  )
  assertEquals(pasgar?.aliases, {
    en: ['pasgar', 'chick quality score'],
    ar: ['باسجار', 'جودة الكتكوت', 'جودة الكتاكيت'],
  })
  assertEquals(pasgar?.allowedLayers, ['pool', 'setter_hatcher'])
  assertEquals(
    await test.call(
      'list_applicable_stations',
      { customerId: 'customer-a', flockId: 'other-flock' },
      1,
    ),
    { ok: false, code: 'scope_denied', data: null },
  )
})

Deno.test('proposal requires a later confirmation turn before intake creation', async () => {
  const test = harness()
  await test.store.createConversation(test.conversation)

  const proposed = await test.call(
    'propose_intake',
    { customerId: 'customer-a' },
    1,
  )
  assert(proposed.ok)
  const pendingActionId = proposed.data!.pendingActionId as string
  assertEquals(await test.store.listSessions(), [])

  assertEquals(
    await test.call('start_intake', startArgs(pendingActionId), 1),
    { ok: false, code: 'confirmation_required', data: null },
  )
  const started = await test.call(
    'start_intake',
    startArgs(pendingActionId),
    2,
  )
  assert(started.ok)
  assertEquals(started.data!.rowVersion, 1)
  assertEquals((await test.store.listSessions()).length, 1)
})

Deno.test('proposal expires after five turns or fifteen minutes', async () => {
  const turnExpiry = harness()
  await turnExpiry.store.createConversation(turnExpiry.conversation)
  const first = await turnExpiry.call(
    'propose_intake',
    { customerId: 'customer-a' },
    1,
  )
  assertEquals(
    await turnExpiry.call(
      'start_intake',
      startArgs(first.data!.pendingActionId as string),
      7,
    ),
    { ok: false, code: 'pending_action_expired', data: null },
  )

  const timeExpiry = harness()
  await timeExpiry.store.createConversation(timeExpiry.conversation)
  const second = await timeExpiry.call(
    'propose_intake',
    { customerId: 'customer-a' },
    1,
  )
  timeExpiry.setTime(new Date('2026-07-28T12:15:01.000Z'))
  assertEquals(
    await timeExpiry.call(
      'start_intake',
      startArgs(second.data!.pendingActionId as string),
      2,
    ),
    { ok: false, code: 'pending_action_expired', data: null },
  )
})

Deno.test('one tool call records several fields and clarifies unsafe values', async () => {
  const test = harness()
  await test.store.createConversation(test.conversation)
  const intakeId = await startPasgar(test)

  const result = await test.call(
    'record_station_values',
    {
      intakeId,
      expectedRowVersion: 1,
      values: [
        candidate('pasgarNavelCount', 3, 'navel three'),
        candidate('pasgarSampleSize', 40, 'sample forty'),
        candidate('pasgarBeakCount', 0, 'beak zero'),
        candidate('pasgarBellyCount', 41, 'belly forty one'),
        candidate('pasgarLegCount', 2, 'maybe legs', 0.4),
      ],
    },
    3,
  )

  assertEquals(result.ok, true)
  assertEquals(result.data!.acceptedKeys, [
    'pasgarNavelCount',
    'pasgarSampleSize',
    'pasgarBeakCount',
  ])
  assertEquals(result.data!.rejected, [
    {
      fieldKey: 'pasgarBellyCount',
      sourcePhrase: 'belly forty one',
      reason: 'above_dynamic_maximum',
    },
    {
      fieldKey: 'pasgarLegCount',
      sourcePhrase: 'maybe legs',
      reason: 'low_confidence',
    },
  ])
  assertEquals(result.data!.rowVersion, 2)
  assertEquals(
    (await test.store.loadSession(intakeId))!.workingValues,
    {
      pasgarNavelCount: 3,
      pasgarSampleSize: 40,
      pasgarBeakCount: 0,
    },
  )
})

Deno.test('dynamic limits are independent of field order and retain clarification evidence', async () => {
  const test = harness()
  await test.store.createConversation(test.conversation)
  const intakeId = await startPasgar(test)

  const result = await test.call(
    'record_station_values',
    {
      intakeId,
      expectedRowVersion: 1,
      values: [
        candidate('pasgarBellyCount', 41, 'البطن واحد وأربعين'),
        candidate('pasgarSampleSize', 40, 'العينة أربعين'),
      ],
    },
    3,
  )

  assertEquals(result.data!.acceptedKeys, ['pasgarSampleSize'])
  assertEquals(result.data!.rejected, [{
    fieldKey: 'pasgarBellyCount',
    sourcePhrase: 'البطن واحد وأربعين',
    reason: 'above_dynamic_maximum',
  }])
  assertEquals(
    (await test.store.loadSession(intakeId))!.pendingClarification,
    {
      fieldKey: 'pasgarBellyCount',
      sourcePhrase: 'البطن واحد وأربعين',
      reason: 'above_dynamic_maximum',
    },
  )
})

Deno.test('summary is complete once, exact-version confirmed, then submitted', async () => {
  const test = harness()
  await test.store.createConversation(test.conversation)
  const intakeId = await startPasgar(test)
  const recorded = await test.call(
    'record_station_values',
    {
      intakeId,
      expectedRowVersion: 1,
      values: [
        candidate('pasgarSampleSize', 40, 'sample 40'),
        candidate('pasgarReflexesCount', 2, 'reflex 2'),
        candidate('pasgarBeakCount', 1, 'beak 1'),
        candidate('pasgarNavelCount', 3, 'navel 3'),
        candidate('pasgarBellyCount', 1, 'belly 1'),
        candidate('pasgarLegCount', 2, 'leg 2'),
        candidate('pasgarFeatherDevCount', 3, 'feather 3'),
      ],
    },
    3,
  )
  const summary = await test.call(
    'create_station_summary',
    { intakeId, expectedRowVersion: recorded.data!.rowVersion },
    3,
  )
  assert(summary.ok, JSON.stringify(summary))
  assertEquals(summary.data!.summaryVersion, 1)
  assertEquals(
    (summary.data!.summary as Record<string, unknown>).calculations,
    {
      pasgarFinalScore: 9.8,
      pasgarReflexesPct: 5,
      pasgarBeakPct: 2.5,
      pasgarNavelPct: 7.5,
      pasgarBellyPct: 2.5,
      pasgarLegPct: 5,
      pasgarFeatherDevPct: 7.5,
    },
  )
  assertEquals(
    await test.call(
      'confirm_station_summary',
      {
        intakeId,
        expectedRowVersion: summary.data!.rowVersion,
        summaryVersion: 2,
      },
      4,
    ),
    { ok: false, code: 'summary_version_mismatch', data: null },
  )
  const confirmed = await test.call(
    'confirm_station_summary',
    {
      intakeId,
      expectedRowVersion: summary.data!.rowVersion,
      summaryVersion: 1,
    },
    4,
  )
  const submitted = await test.call(
    'submit_station_for_review',
    {
      intakeId,
      expectedRowVersion: confirmed.data!.rowVersion,
    },
    4,
  )
  assertEquals(submitted.data!.state, 'awaiting_admin_review')
  assertEquals(await test.store.countOperationalRows(), 0)
})

Deno.test('correction invalidates summary and stale writes return state conflict', async () => {
  const test = harness()
  await test.store.createConversation(test.conversation)
  const intakeId = await startPasgar(test)
  const complete = await recordCompletePasgar(test, intakeId, 1)
  const summary = await test.call(
    'create_station_summary',
    { intakeId, expectedRowVersion: complete.data!.rowVersion },
    3,
  )
  assert(summary.ok, JSON.stringify(summary))
  const corrected = await test.call(
    'record_station_values',
    {
      intakeId,
      expectedRowVersion: summary.data!.rowVersion,
      values: [candidate('pasgarNavelCount', 4, 'correction navel 4')],
    },
    4,
  )
  assertEquals(corrected.data!.summaryInvalidated, true)
  assertEquals((await test.store.loadSession(intakeId))!.summarySnapshot, null)
  assertEquals(
    await test.call(
      'record_station_values',
      {
        intakeId,
        expectedRowVersion: summary.data!.rowVersion,
        values: [candidate('pasgarNavelCount', 5, 'stale correction')],
      },
      4,
    ),
    { ok: false, code: 'state_conflict', data: null },
  )
  assertEquals(
    (await test.store.loadSession(intakeId))!.workingValues.pasgarNavelCount,
    4,
  )
})

Deno.test('pause resume cancel preserve values and visits span stations', async () => {
  const test = harness()
  await test.store.createConversation(test.conversation)
  const firstIntake = await startPasgar(test)
  const recorded = await test.call(
    'record_station_values',
    {
      intakeId: firstIntake,
      expectedRowVersion: 1,
      values: [candidate('pasgarSampleSize', 40, 'sample 40')],
    },
    3,
  )
  const paused = await test.call(
    'pause_intake',
    {
      intakeId: firstIntake,
      expectedRowVersion: recorded.data!.rowVersion,
    },
    4,
  )
  const resumed = await test.call(
    'resume_intake',
    {
      intakeId: firstIntake,
      expectedRowVersion: paused.data!.rowVersion,
    },
    5,
  )
  const cancelled = await test.call(
    'cancel_intake',
    {
      intakeId: firstIntake,
      expectedRowVersion: resumed.data!.rowVersion,
    },
    6,
  )
  assertEquals(cancelled.data!.state, 'cancelled')
  assertEquals(
    (await test.store.loadSession(firstIntake))!.workingValues,
    { pasgarSampleSize: 40 },
  )

  const proposed = await test.call(
    'propose_intake',
    { customerId: 'customer-a' },
    7,
  )
  const second = await test.call(
    'start_intake',
    {
      ...startArgs(proposed.data!.pendingActionId as string),
      schemaKey: 'egg.storage_environment',
    },
    8,
  )
  assertEquals(
    second.data!.visitId,
    (await test.store.loadSession(firstIntake))!.visitId,
  )
})

async function startPasgar(test: ReturnType<typeof harness>): Promise<string> {
  const proposed = await test.call(
    'propose_intake',
    { customerId: 'customer-a' },
    1,
  )
  const started = await test.call(
    'start_intake',
    startArgs(proposed.data!.pendingActionId as string),
    2,
  )
  return started.data!.intakeId as string
}

function startArgs(pendingActionId: string) {
  return {
    pendingActionId,
    schemaKey: 'chicks.pasgar',
    schemaVersion: 1,
    customerId: 'customer-a',
    flockId: 'flock-a',
    hatcheryId: 'hatchery-a',
    auditDate: '2026-07-28',
    layer: 'pool',
  }
}

function candidate(
  fieldKey: string,
  value: unknown,
  sourcePhrase: string,
  confidence = 1,
) {
  return { fieldKey, value, sourcePhrase, confidence }
}

async function recordCompletePasgar(
  test: ReturnType<typeof harness>,
  intakeId: string,
  expectedRowVersion: number,
) {
  return test.call(
    'record_station_values',
    {
      intakeId,
      expectedRowVersion,
      values: [
        candidate('pasgarSampleSize', 40, 'sample 40'),
        candidate('pasgarReflexesCount', 2, 'reflex 2'),
        candidate('pasgarBeakCount', 1, 'beak 1'),
        candidate('pasgarNavelCount', 3, 'navel 3'),
        candidate('pasgarBellyCount', 1, 'belly 1'),
        candidate('pasgarLegCount', 2, 'leg 2'),
        candidate('pasgarFeatherDevCount', 3, 'feather 3'),
      ],
    },
    3,
  )
}

function context(): AgentIntakeContext {
  return {
    customerId: 'customer-a',
    customerName: 'Customer A',
    flockId: 'flock-a',
    flockName: 'Flock A',
    hatcheryId: 'hatchery-a',
    hatcheryName: 'Hatchery A',
    auditDate: '2026-07-28',
    layer: 'pool',
    setterIdentity: null,
    hatcherIdentity: null,
    sectorKey: 'breeder',
  }
}
