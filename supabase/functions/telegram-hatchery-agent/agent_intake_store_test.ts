import { assertEquals } from '@std/assert'

import {
  type AgentConversation,
  type AgentIntakeSession,
  conversationFromRemote,
  MemoryAgentIntakeStore,
  sessionFromRemote,
} from './agent_intake_store.ts'

const timestamp = '2026-07-28T12:00:00.000Z'

Deno.test('conversation pending action uses optimistic state versions', async () => {
  const store = new MemoryAgentIntakeStore()
  await store.createConversation(conversation())

  const updated = await store.updateConversation('conversation-a', 1, {
    pendingAction: {
      id: 'pending-a',
      kind: 'station_intake',
      customerId: 'customer-a',
      proposedAt: timestamp,
      proposedTurnId: 'turn-1',
      proposedTurnIndex: 1,
      expiresAt: '2026-07-28T12:15:00.000Z',
      expiresAfterTurnIndex: 6,
    },
    updatedAt: timestamp,
  })
  assertEquals(updated?.stateVersion, 2)
  assertEquals(
    await store.updateConversation('conversation-a', 1, {
      pendingAction: null,
    }),
    null,
  )
  assertEquals(
    (await store.loadConversation('conversation-a'))?.pendingAction?.id,
    'pending-a',
  )
})

Deno.test('session updates reject stale versions without losing values', async () => {
  const store = new MemoryAgentIntakeStore()
  await store.createSession(session())

  const updated = await store.updateSession('intake-a', 1, {
    workingValues: { pasgarSampleSize: 40 },
    updatedAt: timestamp,
  })
  assertEquals(updated?.rowVersion, 2)
  assertEquals(
    await store.updateSession('intake-a', 1, {
      workingValues: { pasgarSampleSize: 20 },
    }),
    null,
  )
  assertEquals(
    (await store.loadSession('intake-a'))?.workingValues,
    { pasgarSampleSize: 40 },
  )
})

Deno.test('durable row mappers preserve pending actions and intake snapshots', () => {
  const pendingAction = {
    id: 'pending-a',
    kind: 'station_intake' as const,
    customerId: 'customer-a',
    proposedAt: timestamp,
    proposedTurnId: 'turn-1',
    proposedTurnIndex: 1,
    expiresAt: '2026-07-28T12:15:00.000Z',
    expiresAfterTurnIndex: 6,
  }
  assertEquals(
    conversationFromRemote({
      id: 'conversation-a',
      staff_link_id: 'staff-a',
      telegram_chat_id: 'chat-a',
      state_version: 2,
      pending_action_json: JSON.stringify(pendingAction),
      active_visit_id: 'visit-a',
      created_at: timestamp,
      updated_at: timestamp,
    }),
    {
      ...conversation(),
      stateVersion: 2,
      pendingAction,
      activeVisitId: 'visit-a',
    },
  )

  const snapshot = {
    version: 1,
    schemaKey: 'chicks.pasgar',
    schemaVersion: 1,
    values: { pasgarSampleSize: 40 },
    calculations: { pasgarFinalScore: 10 },
    generatedAt: timestamp,
  }
  assertEquals(
    sessionFromRemote({
      id: 'intake-a',
      visit_id: 'visit-a',
      staff_link_id: 'staff-a',
      telegram_chat_id: 'chat-a',
      schema_key: 'chicks.pasgar',
      schema_version: 1,
      state: 'awaiting_user_confirmation',
      language: 'mixed',
      row_version: 4,
      customer_id: 'customer-a',
      customer_name: 'Customer A',
      flock_id: 'flock-a',
      flock_name: 'Flock A',
      hatchery_id: 'hatchery-a',
      hatchery_name: 'Hatchery A',
      audit_date: '2026-07-28',
      scope: 'pool',
      setter_identity: null,
      hatcher_identity: null,
      sector_key: 'breeder',
      working_values_json: JSON.stringify({ pasgarSampleSize: 40 }),
      pending_clarification_json: null,
      summary_version: 1,
      summary_snapshot_json: JSON.stringify(snapshot),
      user_confirmed_at: null,
      last_tool_event_id: 'tool-a',
      created_at: timestamp,
      updated_at: timestamp,
    }),
    {
      ...session(),
      language: 'mixed',
      state: 'awaiting_user_confirmation',
      rowVersion: 4,
      workingValues: { pasgarSampleSize: 40 },
      summaryVersion: 1,
      summarySnapshot: snapshot,
      lastToolEventId: 'tool-a',
    },
  )
})

function conversation(): AgentConversation {
  return {
    id: 'conversation-a',
    staffLinkId: 'staff-a',
    telegramChatId: 'chat-a',
    stateVersion: 1,
    pendingAction: null,
    activeVisitId: null,
    createdAt: timestamp,
    updatedAt: timestamp,
  }
}

function session(): AgentIntakeSession {
  return {
    id: 'intake-a',
    visitId: 'visit-a',
    staffLinkId: 'staff-a',
    telegramChatId: 'chat-a',
    schemaKey: 'chicks.pasgar',
    schemaVersion: 1,
    state: 'collecting',
    language: 'en',
    rowVersion: 1,
    context: {
      customerId: 'customer-a',
      customerName: 'Customer A',
      flockId: 'flock-a',
      flockName: 'Flock A',
      hatcheryId: 'hatchery-a',
      hatcheryName: 'Hatchery A',
      auditDate: '2026-07-28',
      layer: 'pool',
      houseIdentity: null,
      setterIdentity: null,
      hatcherIdentity: null,
      sectorKey: 'breeder',
    },
    workingValues: {},
    pendingClarification: null,
    summaryVersion: 0,
    summarySnapshot: null,
    userConfirmedAt: null,
    lastToolEventId: null,
    createdAt: timestamp,
    updatedAt: timestamp,
  }
}
