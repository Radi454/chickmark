import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert'

import {
  handlePasgarTurn,
  type PasgarContextResolver,
  type PasgarConversationDependencies,
  type PasgarIntakeSession,
  type PasgarIntakeStore,
  type PasgarIntakeTurn,
  type PasgarTurnInput,
  type PasgarTurnInterpretation,
  type PasgarValueUpdate,
  tryHandlePasgarConversation,
} from './pasgar_conversation.ts'

function turn(text: string, updateId = 'update-1'): PasgarTurnInput {
  return {
    staffLinkId: 'staff-1',
    chatId: 'chat-1',
    updateId,
    messageId: `message-${updateId}`,
    text,
    receivedAt: '2026-07-28T10:00:00.000Z',
  }
}

function collectingSession(
  values: PasgarIntakeSession['workingValues'] = {},
): PasgarIntakeSession {
  return {
    id: 'intake-1',
    staffLinkId: 'staff-1',
    chatId: 'chat-1',
    schemaKey: 'chicks.pasgar',
    schemaVersion: 1,
    state: 'collecting',
    language: 'en',
    context: {
      customerId: 'customer-1',
      customerName: 'Customer One',
      flockId: 'flock-1',
      flockName: 'Flock One',
      hatcheryId: 'hatchery-1',
      hatcheryName: 'Hatchery One',
      auditDate: '2026-07-28',
      scope: 'pool',
      setterIdentity: null,
      hatcherIdentity: null,
    },
    workingValues: values,
    pendingClarification: null,
    summaryVersion: 0,
    summarySnapshot: null,
    userConfirmedAt: null,
    createdAt: '2026-07-28T10:00:00.000Z',
    updatedAt: '2026-07-28T10:00:00.000Z',
  }
}

function completeValues(): PasgarIntakeSession['workingValues'] {
  return {
    pasgarSampleSize: 40,
    pasgarReflexesCount: 2,
    pasgarBeakCount: 1,
    pasgarNavelCount: 0,
    pasgarBellyCount: 1,
    pasgarLegCount: 2,
    pasgarFeatherDevCount: 3,
  }
}

class InMemoryStore implements PasgarIntakeStore {
  sessions = new Map<string, PasgarIntakeSession>()
  inboundUpdateIds = new Set<string>()
  inboundTurns: PasgarIntakeTurn[] = []
  outboundTurns: PasgarIntakeTurn[] = []
  valueUpdates: PasgarValueUpdate[] = []

  constructor(session?: PasgarIntakeSession) {
    if (session) this.sessions.set(session.id, structuredClone(session))
  }

  findActiveSession(
    staffLinkId: string,
    chatId: string,
  ): Promise<PasgarIntakeSession | null> {
    const session = [...this.sessions.values()].find((candidate) =>
      candidate.staffLinkId === staffLinkId &&
      candidate.chatId === chatId &&
      !['approved', 'rejected', 'cancelled'].includes(candidate.state)
    )
    return Promise.resolve(session ? structuredClone(session) : null)
  }

  createSession(session: PasgarIntakeSession): Promise<void> {
    this.sessions.set(session.id, structuredClone(session))
    return Promise.resolve()
  }

  saveInboundTurn(
    turnRecord: PasgarIntakeTurn,
  ): Promise<'inserted' | 'duplicate'> {
    if (this.inboundUpdateIds.has(turnRecord.updateId!)) {
      return Promise.resolve('duplicate')
    }
    this.inboundUpdateIds.add(turnRecord.updateId!)
    this.inboundTurns.push(structuredClone(turnRecord))
    return Promise.resolve('inserted')
  }

  saveOutboundTurn(turnRecord: PasgarIntakeTurn): Promise<void> {
    this.outboundTurns.push(structuredClone(turnRecord))
    return Promise.resolve()
  }

  saveValues(
    _sessionId: string,
    values: PasgarValueUpdate[],
  ): Promise<void> {
    this.valueUpdates.push(...structuredClone(values))
    return Promise.resolve()
  }

  updateSession(
    sessionId: string,
    patch: Partial<PasgarIntakeSession>,
  ): Promise<void> {
    const current = this.sessions.get(sessionId)
    if (!current) throw new Error('missing test session')
    this.sessions.set(sessionId, {
      ...current,
      ...structuredClone(patch),
    })
    return Promise.resolve()
  }
}

function deps(
  store: InMemoryStore,
  interpretation: PasgarTurnInterpretation,
): PasgarConversationDependencies {
  return {
    store,
    createId: () => 'created-intake',
    interpretTurn: () => Promise.resolve(structuredClone(interpretation)),
  }
}

Deno.test('ordinary chat does not create a Pasgar session', async () => {
  const store = new InMemoryStore()
  const result = await tryHandlePasgarConversation(
    turn('What is your name?'),
    deps(store, {
      intent: 'mission_chat',
      language: 'en',
      candidates: [],
      allRemainingZero: false,
      summaryVersion: null,
      clarification: null,
    }),
  )

  assertEquals(result, null)
  assertEquals(store.sessions.size, 0)
})

Deno.test('starting Pasgar loads accessible customers and asks for a safe choice', async () => {
  const store = new InMemoryStore()
  const contextResolver: PasgarContextResolver = {
    listCustomers: () =>
      Promise.resolve([
        { id: 'customer-1', label: 'Customer One' },
        { id: 'customer-2', label: 'Customer Two' },
      ]),
    listFlocks: () => Promise.resolve([]),
    listHatcheries: () => Promise.resolve([]),
    listSetters: () => Promise.resolve([]),
    listHatchers: () => Promise.resolve([]),
  }
  const result = await tryHandlePasgarConversation(
    turn('I want to enter Pasgar'),
    {
      ...deps(store, {
        intent: 'start_pasgar',
        language: 'en',
        candidates: [],
        contextCandidates: [],
        allRemainingZero: false,
        summaryVersion: null,
        clarification: null,
      }),
      contextResolver,
    },
  )

  assert(result)
  assertEquals(result.nextContextField, 'customer')
  assertStringIncludes(result.reply!, '1. Customer One')
  assertStringIncludes(result.reply!, '2. Customer Two')
  assertEquals(result.reply!.includes('sample'), false)
})

Deno.test('a numbered customer choice is linked before asking for its flock', async () => {
  const session = collectingSession()
  session.context = {
    ...session.context,
    customerId: null,
    customerName: null,
    flockId: null,
    flockName: null,
    hatcheryId: null,
    hatcheryName: null,
    scope: null,
  }
  const store = new InMemoryStore(session)
  const contextResolver: PasgarContextResolver = {
    listCustomers: () =>
      Promise.resolve([
        { id: 'customer-1', label: 'Customer One' },
        { id: 'customer-2', label: 'Customer Two' },
      ]),
    listFlocks: (_staffLinkId, customerId) => {
      assertEquals(customerId, 'customer-2')
      return Promise.resolve([{ id: 'flock-2', label: 'Flock Two' }])
    },
    listHatcheries: () => Promise.resolve([]),
    listSetters: () => Promise.resolve([]),
    listHatchers: () => Promise.resolve([]),
  }

  const result = await handlePasgarTurn(turn('2'), {
    ...deps(store, {
      intent: 'provide_data',
      language: 'en',
      candidates: [],
      contextCandidates: [{
        fieldKey: 'customer',
        value: '2',
        confidence: 1,
        sourcePhrase: '2',
      }],
      allRemainingZero: false,
      summaryVersion: null,
      clarification: null,
    }),
    contextResolver,
  })

  assertEquals(result.nextContextField, 'flock')
  assertStringIncludes(result.reply!, 'Flock Two')
  assertEquals(
    store.sessions.get('intake-1')!.context.customerId,
    'customer-2',
  )
})

Deno.test('several valid values save silently and ask only for the next missing field', async () => {
  const store = new InMemoryStore(collectingSession())
  const result = await handlePasgarTurn(
    turn('Sample 40, reflex 2, beak 1'),
    deps(store, {
      intent: 'provide_data',
      language: 'en',
      candidates: [
        {
          fieldKey: 'pasgarSampleSize',
          value: 40,
          confidence: 0.99,
          sourcePhrase: 'Sample 40',
        },
        {
          fieldKey: 'pasgarReflexesCount',
          value: 2,
          confidence: 0.99,
          sourcePhrase: 'reflex 2',
        },
        {
          fieldKey: 'pasgarBeakCount',
          value: 1,
          confidence: 0.99,
          sourcePhrase: 'beak 1',
        },
      ],
      allRemainingZero: false,
      summaryVersion: null,
      clarification: null,
    }),
  )

  assertEquals(result.state, 'collecting')
  assertEquals(result.nextFieldKey, 'pasgarNavelCount')
  assertStringIncludes(result.reply!, 'navel')
  assertEquals(result.reply!.toLowerCase().includes('correct'), false)
  assertEquals(store.valueUpdates.length, 3)
})

Deno.test('all remaining zero produces one versioned final summary', async () => {
  const store = new InMemoryStore(collectingSession({
    pasgarSampleSize: 40,
    pasgarReflexesCount: 2,
    pasgarBeakCount: 1,
  }))
  const result = await handlePasgarTurn(
    turn('all remaining are zero'),
    deps(store, {
      intent: 'provide_data',
      language: 'en',
      candidates: [],
      allRemainingZero: true,
      summaryVersion: null,
      clarification: null,
    }),
  )

  assertEquals(result.state, 'awaiting_user_confirmation')
  assertEquals(result.summaryVersion, 1)
  assertStringIncludes(result.reply!, 'Pasgar score')
  assertStringIncludes(result.reply!, 'Is this complete summary correct?')
  assertEquals(store.valueUpdates.length, 4)
})

Deno.test('a correction invalidates and regenerates the summary snapshot', async () => {
  const session = collectingSession(completeValues())
  session.state = 'awaiting_user_confirmation'
  session.summaryVersion = 1
  session.summarySnapshot = {
    version: 1,
    values: completeValues(),
    generatedAt: '2026-07-28T10:00:00.000Z',
  }
  const store = new InMemoryStore(session)

  const result = await handlePasgarTurn(
    turn('change navel to 3'),
    deps(store, {
      intent: 'correct',
      language: 'en',
      candidates: [{
        fieldKey: 'pasgarNavelCount',
        value: 3,
        confidence: 0.98,
        sourcePhrase: 'navel to 3',
      }],
      allRemainingZero: false,
      summaryVersion: 1,
      clarification: null,
    }),
  )

  assertEquals(result.state, 'awaiting_user_confirmation')
  assertEquals(result.summaryVersion, 2)
  assertStringIncludes(result.reply!, 'Navel: 3')
})

Deno.test('yes confirms only the current summary and sends it to admin review', async () => {
  const session = collectingSession(completeValues())
  session.state = 'awaiting_user_confirmation'
  session.summaryVersion = 2
  session.summarySnapshot = {
    version: 2,
    values: completeValues(),
    generatedAt: '2026-07-28T10:00:00.000Z',
  }
  const store = new InMemoryStore(session)

  const result = await handlePasgarTurn(
    turn('yes'),
    deps(store, {
      intent: 'confirm_summary',
      language: 'en',
      candidates: [],
      allRemainingZero: false,
      summaryVersion: 2,
      clarification: null,
    }),
  )

  assertEquals(result.state, 'awaiting_admin_review')
  assertStringIncludes(result.reply!, 'sent for review')
  assert(store.sessions.get('intake-1')!.userConfirmedAt)
})

Deno.test('an invalid count keeps valid values and asks one focused clarification', async () => {
  const store = new InMemoryStore(collectingSession())
  const result = await handlePasgarTurn(
    turn('sample 40 reflex 2 belly 41'),
    deps(store, {
      intent: 'provide_data',
      language: 'en',
      candidates: [
        {
          fieldKey: 'pasgarSampleSize',
          value: 40,
          confidence: 0.99,
          sourcePhrase: 'sample 40',
        },
        {
          fieldKey: 'pasgarReflexesCount',
          value: 2,
          confidence: 0.99,
          sourcePhrase: 'reflex 2',
        },
        {
          fieldKey: 'pasgarBellyCount',
          value: 41,
          confidence: 0.99,
          sourcePhrase: 'belly 41',
        },
      ],
      allRemainingZero: false,
      summaryVersion: null,
      clarification: null,
    }),
  )

  assertEquals(result.state, 'awaiting_clarification')
  assertEquals(store.valueUpdates.length, 2)
  assertStringIncludes(result.reply!, 'sample of 40')
})

Deno.test('a duplicate Telegram update performs no second write or reply', async () => {
  const store = new InMemoryStore(collectingSession())
  const interpretation: PasgarTurnInterpretation = {
    intent: 'provide_data',
    language: 'en',
    candidates: [{
      fieldKey: 'pasgarSampleSize',
      value: 40,
      confidence: 0.99,
      sourcePhrase: 'sample 40',
    }],
    allRemainingZero: false,
    summaryVersion: null,
    clarification: null,
  }

  await handlePasgarTurn(turn('sample 40'), deps(store, interpretation))
  const duplicate = await handlePasgarTurn(
    turn('sample 40'),
    deps(store, interpretation),
  )

  assertEquals(duplicate.duplicate, true)
  assertEquals(duplicate.reply, null)
  assertEquals(store.valueUpdates.length, 1)
})
