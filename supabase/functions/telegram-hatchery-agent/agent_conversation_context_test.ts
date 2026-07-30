import { assertEquals, assertRejects } from '@std/assert'

import {
  type AgentConversationContextClient,
  createSupabaseAgentConversationContextStore,
} from './agent_conversation_context.ts'

Deno.test('customer and flock changes invalidate the selected audit', async () => {
  const client = new FakeContextClient({
    id: 'conversation-a',
    state_version: 4,
    context_epoch: 2,
    selected_customer_id: 'customer-a',
    selected_flock_id: 'flock-a',
    selected_audit_id: 'audit-a',
  })
  const store = createSupabaseAgentConversationContextStore(
    client,
    () => new Date('2026-07-30T10:00:00.000Z'),
  )

  await store.recordSuccessfulTool(
    {
      id: 'call-1',
      name: 'get_flock_context',
      arguments: { flockId: 'flock-b' },
    },
    {
      ok: true,
      code: 'ok',
      data: { id: 'flock-b', customerId: 'customer-a' },
    },
    'conversation-a',
    2,
  )

  assertEquals(client.row, {
    id: 'conversation-a',
    state_version: 5,
    context_epoch: 2,
    selected_customer_id: 'customer-a',
    selected_flock_id: 'flock-b',
    selected_audit_id: null,
    context_updated_at: '2026-07-30T10:00:00.000Z',
    updated_at: '2026-07-30T10:00:00.000Z',
  })
})

Deno.test('a fresh audit selection is stored against its exact context', async () => {
  const client = new FakeContextClient({
    id: 'conversation-a',
    state_version: 5,
    context_epoch: 2,
    selected_customer_id: 'customer-a',
    selected_flock_id: 'flock-b',
    selected_audit_id: null,
  })
  const store = createSupabaseAgentConversationContextStore(client)

  await store.recordSuccessfulTool(
    {
      id: 'call-2',
      name: 'select_audit_option',
      arguments: { position: 1 },
    },
    {
      ok: true,
      code: 'ok',
      data: {
        id: 'audit-b',
        customerId: 'customer-a',
        flockId: 'flock-b',
      },
    },
    'conversation-a',
    2,
  )

  assertEquals(client.row.selected_customer_id, 'customer-a')
  assertEquals(client.row.selected_flock_id, 'flock-b')
  assertEquals(client.row.selected_audit_id, 'audit-b')
  assertEquals(client.row.state_version, 6)
})

Deno.test('the same customer and flock keep the selected audit', async () => {
  const client = new FakeContextClient({
    id: 'conversation-a',
    state_version: 6,
    context_epoch: 2,
    selected_customer_id: 'customer-a',
    selected_flock_id: 'flock-a',
    selected_audit_id: 'audit-a',
  })
  const store = createSupabaseAgentConversationContextStore(client)

  await store.recordSuccessfulTool(
    {
      id: 'call-3',
      name: 'get_flock_context',
      arguments: { flockId: 'flock-a' },
    },
    {
      ok: true,
      code: 'ok',
      data: { id: 'flock-a', customerId: 'customer-a' },
    },
    'conversation-a',
    2,
  )

  assertEquals(client.row.selected_audit_id, 'audit-a')
  assertEquals(client.row.state_version, 6)
})

Deno.test('a stale context write fails instead of silently retaining an audit', async () => {
  const client = new FakeContextClient(
    {
      id: 'conversation-a',
      state_version: 6,
      context_epoch: 2,
      selected_customer_id: 'customer-a',
      selected_flock_id: 'flock-a',
      selected_audit_id: 'audit-a',
    },
    true,
  )
  const store = createSupabaseAgentConversationContextStore(client)

  await assertRejects(
    async () => {
      await store.recordSuccessfulTool(
        {
          id: 'call-4',
          name: 'get_flock_context',
          arguments: { flockId: 'flock-b' },
        },
        {
          ok: true,
          code: 'ok',
          data: { id: 'flock-b', customerId: 'customer-a' },
        },
        'conversation-a',
        2,
      )
    },
    Error,
    'Could not update agent conversation context',
  )

  assertEquals(client.row.selected_audit_id, 'audit-a')
})

Deno.test('a tool from an older context epoch cannot write after reset', async () => {
  const client = new FakeContextClient({
    id: 'conversation-a',
    state_version: 8,
    context_epoch: 3,
    selected_customer_id: null,
    selected_flock_id: null,
    selected_audit_id: null,
  })
  const store = createSupabaseAgentConversationContextStore(client)

  await assertRejects(
    async () =>
      await store.recordSuccessfulTool(
        {
          id: 'call-before-reset',
          name: 'get_flock_context',
          arguments: { flockId: 'flock-a' },
        },
        {
          ok: true,
          code: 'ok',
          data: { id: 'flock-a', customerId: 'customer-a' },
        },
        'conversation-a',
        2,
      ),
    Error,
    'Could not update agent conversation context',
  )

  assertEquals(client.row, {
    id: 'conversation-a',
    state_version: 8,
    context_epoch: 3,
    selected_customer_id: null,
    selected_flock_id: null,
    selected_audit_id: null,
  })
})

class FakeContextClient implements AgentConversationContextClient {
  constructor(
    public row: Record<string, unknown>,
    public readonly conflictOnUpdate = false,
  ) {}

  from(_table: string): FakeContextQuery {
    return new FakeContextQuery(this)
  }
}

class FakeContextQuery {
  private equals: Record<string, unknown> = {}
  private updateValues: Record<string, unknown> | null = null

  constructor(private readonly client: FakeContextClient) {}

  select(_columns: string): FakeContextQuery {
    return this
  }

  eq(column: string, value: unknown): FakeContextQuery {
    this.equals[column] = value
    return this
  }

  update(values: Record<string, unknown>): FakeContextQuery {
    this.updateValues = values
    if (this.client.conflictOnUpdate) {
      this.client.row = {
        ...this.client.row,
        state_version: Number(this.client.row.state_version) + 1,
      }
    }
    return this
  }

  maybeSingle(): Promise<{
    data: Record<string, unknown> | null
    error: { message: string } | null
  }> {
    const matches = Object.entries(this.equals).every(([column, value]) =>
      this.client.row[column] === value
    )
    if (matches && this.updateValues) {
      this.client.row = { ...this.client.row, ...this.updateValues }
    }
    return Promise.resolve({
      data: matches ? { ...this.client.row } : null,
      error: null,
    })
  }

  then<TResult1 = unknown, TResult2 = never>(
    onFulfilled?:
      | ((
        value: {
          data: unknown
          error: { message: string } | null
        },
      ) => TResult1 | PromiseLike<TResult1>)
      | null,
    _onRejected?:
      | ((reason: unknown) => TResult2 | PromiseLike<TResult2>)
      | null,
  ): Promise<TResult1 | TResult2> {
    const matches = Object.entries(this.equals).every(([column, value]) =>
      this.client.row[column] === value
    )
    if (matches && this.updateValues) {
      this.client.row = { ...this.client.row, ...this.updateValues }
    }
    return Promise.resolve(
      onFulfilled?.({ data: null, error: null }) as TResult1,
    )
  }
}
