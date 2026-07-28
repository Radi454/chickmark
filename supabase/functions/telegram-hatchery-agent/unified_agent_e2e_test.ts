import { assertEquals } from '@std/assert'

import type { AgentTurnInput, AgentTurnResult } from './agent_runtime.ts'
import { handleTelegramUpdate } from './index.ts'

type Row = Record<string, unknown>

class FakeAdmin {
  readonly inserts: Record<string, unknown[]> = {}
  readonly updates: Record<string, unknown[]> = {}

  constructor(
    readonly staff: Row | null = {
      id: 'staff-a',
      status: 'allowed',
      telegram_user_id: '456',
    },
    readonly tables: Record<string, Row[]> = {},
  ) {}

  from(table: string) {
    const filters: Record<string, unknown> = {}
    const orderings: Array<{ column: string; ascending: boolean }> = []
    const matching = () => {
      const source = table === 'telegram_staff_links'
        ? this.staff ? [this.staff] : []
        : this.tables[table] ?? []
      const rows = source.filter((row) =>
        Object.entries(filters).every(([key, value]) => row[key] === value)
      )
      rows.sort((left, right) => {
        for (const ordering of orderings) {
          const comparison = String(left[ordering.column] ?? '').localeCompare(
            String(right[ordering.column] ?? ''),
          )
          if (comparison !== 0) {
            return ordering.ascending ? comparison : -comparison
          }
        }
        return 0
      })
      return rows
    }
    const query = {
      select(_columns: string) {
        return query
      },
      eq(column: string, value: unknown) {
        filters[column] = value
        return query
      },
      lt(_column: string, _value: unknown) {
        return query
      },
      lte(_column: string, _value: unknown) {
        return query
      },
      gte(_column: string, _value: unknown) {
        return query
      },
      not(_column: string, _operator: string, _value: unknown) {
        return query
      },
      order(column: string, options: { ascending: boolean }) {
        orderings.push({ column, ascending: options.ascending })
        return query
      },
      limit(count: number) {
        return Promise.resolve({
          data: matching().slice(0, count),
          error: null,
        })
      },
      maybeSingle() {
        if (table === 'agent_settings') {
          return Promise.resolve({
            data: {
              telegram_enabled: 1,
              minimum_ready_confidence_pct: 85,
              hatchability_warning_threshold_points: 3,
            },
            error: null,
          })
        }
        const rows = matching()
        return Promise.resolve({
          data: rows.length === 1 ? rows[0] : null,
          error: rows.length > 1 ? { message: 'multiple' } : null,
        })
      },
      insert: (values: unknown) => {
        this.inserts[table] ??= []
        this.inserts[table].push(values)
        return Promise.resolve({ data: null, error: null })
      },
      update: (values: unknown) => ({
        eq: (_column: string, _value: unknown) => {
          this.updates[table] ??= []
          this.updates[table].push(values)
          return Promise.resolve({ data: null, error: null })
        },
      }),
      then<TResult1 = unknown, TResult2 = never>(
        onFulfilled?:
          | ((
            value: { data: Row[]; error: null },
          ) => TResult1 | PromiseLike<TResult1>)
          | null,
        onRejected?:
          | ((reason: unknown) => TResult2 | PromiseLike<TResult2>)
          | null,
      ) {
        return Promise.resolve({ data: matching(), error: null }).then(
          onFulfilled,
          onRejected,
        )
      },
    }
    return query
  }
}

function request(text: string, updateId = 100): Request {
  return new Request('https://example.test', {
    method: 'POST',
    headers: { 'X-Telegram-Bot-Api-Secret-Token': 'secret' },
    body: JSON.stringify({
      update_id: updateId,
      message: {
        message_id: updateId + 1,
        date: 1784890000,
        chat: { id: 123 },
        from: { id: 456, first_name: 'Staff' },
        text,
      },
    }),
  })
}

function dependencies(params: {
  client?: FakeAdmin
  run: (input: AgentTurnInput) => Promise<AgentTurnResult>
  messages?: string[]
}) {
  const messages = params.messages ?? []
  return {
    expectedTelegramSecret: 'secret',
    adminClient: params.client ?? new FakeAdmin(),
    resolveScope: () =>
      Promise.resolve({
        staffLinkId: 'staff-a',
        accessRole: 'customer' as const,
        allowedCustomerIds: ['customer-a'],
      }),
    runAgentTurn: params.run,
    sendTelegramMessage: (_chatId: string, text: string) => {
      messages.push(text)
      return Promise.resolve()
    },
    newId: (() => {
      let value = 0
      return () => `generated-${++value}`
    })(),
    now: () => new Date('2026-07-28T12:00:00.000Z'),
  }
}

Deno.test('every authorized text reaches the same runtime', async () => {
  for (
    const [index, text] of [
      'صباح الورد يا كبير',
      'pasgr entri plz',
      'what happened to flock A?',
      'العينة 40 reflex 2',
    ].entries()
  ) {
    const turns: AgentTurnInput[] = []
    const messages: string[] = []
    const response = await handleTelegramUpdate(
      request(text, 200 + index),
      dependencies({
        messages,
        run: (input) => {
          turns.push(input)
          return Promise.resolve({
            status: 'replied',
            reply: `model:${text}`,
            providerResponseId: 'response-a',
            toolCallCount: 0,
          })
        },
      }),
    )

    assertEquals((await response.json()).agent, true)
    assertEquals(turns.length, 1)
    assertEquals(turns[0].text, text)
    assertEquals(messages, [`model:${text}`])
  }
})

Deno.test('authorized text persists one unified conversation evidence chain', async () => {
  const client = new FakeAdmin()
  const response = await handleTelegramUpdate(
    request('سجل لي ملاحظة', 250),
    dependencies({
      client,
      run: () =>
        Promise.resolve({
          status: 'replied',
          reply: 'تم حفظ ملاحظتك في المحادثة.',
          providerResponseId: 'response-persisted',
          toolCallCount: 0,
        }),
    }),
  )

  assertEquals((await response.json()).agent, true)
  assertEquals(client.inserts.agent_conversations?.length, 1)
  assertEquals(
    (client.inserts.agent_conversation_turns as Row[]).map((turn) => ({
      direction: turn.direction,
      text: turn.text,
      deliveryStatus: turn.delivery_status,
    })),
    [
      {
        direction: 'inbound',
        text: 'سجل لي ملاحظة',
        deliveryStatus: 'received',
      },
      {
        direction: 'outbound',
        text: 'تم حفظ ملاحظتك في المحادثة.',
        deliveryStatus: 'pending',
      },
    ],
  )
  assertEquals(client.inserts.telegram_agent_update_receipts?.length, 1)
  assertEquals(client.inserts.agent_submissions, undefined)
})

Deno.test('active intake and legacy open questions still reach the unified runtime', async () => {
  let calls = 0
  const client = new FakeAdmin(undefined, {
    agent_conversations: [{
      id: 'conversation-a',
      staff_link_id: 'staff-a',
      telegram_chat_id: '123',
      state_version: 3,
      pending_action_json: null,
      active_visit_id: 'visit-a',
      created_at: '2026-07-28T10:00:00.000Z',
      updated_at: '2026-07-28T11:00:00.000Z',
    }],
    agent_intake_sessions: [{
      id: 'intake-a',
      visit_id: 'visit-a',
      state: 'collecting',
      schema_key: 'chicks.pasgar',
      row_version: 2,
      working_values_json: { pasgarSampleSize: 40 },
      pending_clarification_json: null,
      summary_version: 0,
      summary_snapshot_json: null,
      user_confirmed_at: null,
      updated_at: '2026-07-28T11:00:00.000Z',
    }],
    agent_questions: [{ id: 'legacy-question', status: 'open' }],
  })

  await handleTelegramUpdate(
    request('والسرة 3', 301),
    dependencies({
      client,
      run: (input) => {
        calls += 1
        assertEquals(
          (input.activeIntake as Row).working_values_json,
          { pasgarSampleSize: 40 },
        )
        return Promise.resolve({
          status: 'replied',
          reply: 'تمام، سجلت السرة ضمن الجلسة الحالية.',
          providerResponseId: 'response-b',
          toolCallCount: 1,
        })
      },
    }),
  )

  assertEquals(calls, 1)
  assertEquals(client.inserts.agent_submissions, undefined)
})

Deno.test('a duplicate unified turn produces no model call, reply, or write', async () => {
  let modelCalls = 0
  const messages: string[] = []
  const client = new FakeAdmin(undefined, {
    agent_conversation_turns: [{
      id: 'turn-old',
      telegram_update_id: '400',
    }],
  })

  const response = await handleTelegramUpdate(
    request('hello again', 400),
    dependencies({
      client,
      messages,
      run: () => {
        modelCalls += 1
        return Promise.resolve({
          status: 'replied',
          reply: 'should not happen',
          providerResponseId: 'response-c',
          toolCallCount: 0,
        })
      },
    }),
  )

  assertEquals(await response.json(), {
    accepted: true,
    duplicate: true,
  })
  assertEquals(modelCalls, 0)
  assertEquals(messages, [])
  assertEquals(client.inserts, {})
  assertEquals(client.updates, {})
})

Deno.test('pending and revoked staff never invoke the model', async () => {
  for (const status of ['pending', 'revoked']) {
    let modelCalls = 0
    const messages: string[] = []
    const client = new FakeAdmin({
      id: 'staff-a',
      status,
      telegram_user_id: '456',
    })
    await handleTelegramUpdate(
      request('hello', status === 'pending' ? 501 : 502),
      dependencies({
        client,
        messages,
        run: () => {
          modelCalls += 1
          return Promise.resolve({
            status: 'invalid_model_output',
            toolCallCount: 0,
          })
        },
      }),
    )
    assertEquals(modelCalls, 0)
    assertEquals(client.inserts, {})
    assertEquals(messages.length, 1)
  }
})

Deno.test('provider failure sends only the bounded infrastructure retry', async () => {
  const messages: string[] = []
  const response = await handleTelegramUpdate(
    request('مرحبا', 600),
    dependencies({
      messages,
      run: () =>
        Promise.resolve({
          status: 'provider_unavailable',
          toolCallCount: 0,
        }),
    }),
  )

  assertEquals((await response.json()).status, 'provider_unavailable')
  assertEquals(messages.length, 1)
  assertEquals(messages[0].includes('تعذر الاتصال'), true)
})

Deno.test('attachment bytes and metadata reach the runtime and model reply is unchanged', async () => {
  const messages: string[] = []
  let invocation: AgentTurnInput | null = null
  const deps = dependencies({
    messages,
    run: (input) => {
      invocation = input
      return Promise.resolve({
        status: 'replied',
        reply: 'هذا هو الرد كما كتبه النموذج.',
        providerResponseId: 'response-d',
        toolCallCount: 0,
      })
    },
  })
  const response = await handleTelegramUpdate(
    new Request('https://example.test', {
      method: 'POST',
      headers: { 'X-Telegram-Bot-Api-Secret-Token': 'secret' },
      body: JSON.stringify({
        update_id: 700,
        message: {
          message_id: 701,
          chat: { id: 123 },
          from: { id: 456 },
          caption: 'اقرأ الملف',
          document: {
            file_id: 'telegram-file',
            file_name: 'pasgar.pdf',
            mime_type: 'application/pdf',
          },
        },
      }),
    }),
    {
      ...deps,
      loadTelegramFile: () =>
        Promise.resolve({
          fileData: 'data:application/pdf;base64,AA==',
          mimeType: 'application/pdf',
        }),
    },
  )

  assertEquals((await response.json()).agent, true)
  assertEquals(invocation!.attachment, {
    kind: 'pdf',
    fileName: 'pasgar.pdf',
    mimeType: 'application/pdf',
    fileData: 'data:application/pdf;base64,AA==',
  })
  assertEquals(messages, ['هذا هو الرد كما كتبه النموذج.'])
})

Deno.test('largest Telegram photo reaches the unified runtime without legacy submission writes', async () => {
  const client = new FakeAdmin()
  const downloadedFileIds: string[] = []
  let invocation: AgentTurnInput | null = null
  const deps = dependencies({
    client,
    run: (input) => {
      invocation = input
      return Promise.resolve({
        status: 'replied',
        reply: 'تمت قراءة الصورة.',
        providerResponseId: 'response-photo',
        toolCallCount: 0,
      })
    },
  })

  const response = await handleTelegramUpdate(
    new Request('https://example.test', {
      method: 'POST',
      headers: { 'X-Telegram-Bot-Api-Secret-Token': 'secret' },
      body: JSON.stringify({
        update_id: 750,
        message: {
          message_id: 751,
          chat: { id: 123 },
          from: { id: 456 },
          caption: 'راجع الصورة',
          photo: [
            { file_id: 'photo-small' },
            { file_id: 'photo-largest' },
          ],
        },
      }),
    }),
    {
      ...deps,
      loadTelegramFile: ({ fileId, mimeType }) => {
        downloadedFileIds.push(fileId)
        assertEquals(mimeType, 'image/jpeg')
        return Promise.resolve({
          fileData: 'data:image/jpeg;base64,PHOTO',
          mimeType,
        })
      },
    },
  )

  assertEquals((await response.json()).agent, true)
  assertEquals(downloadedFileIds, ['photo-largest'])
  assertEquals(invocation!.attachment, {
    kind: 'image',
    fileName: 'telegram-photo.jpg',
    mimeType: 'image/jpeg',
    fileData: 'data:image/jpeg;base64,PHOTO',
  })
  assertEquals(client.inserts.agent_submissions, undefined)
  assertEquals(client.inserts.hatchery_draft_batches, undefined)
})

Deno.test('delivery failure is recorded without rerunning the model', async () => {
  let modelCalls = 0
  const client = new FakeAdmin()
  const deps = dependencies({
    client,
    run: () => {
      modelCalls += 1
      return Promise.resolve({
        status: 'replied',
        reply: 'one generated reply',
        providerResponseId: 'response-delivery',
        toolCallCount: 0,
      })
    },
  })
  deps.sendTelegramMessage = () => Promise.reject(new Error('offline'))

  const first = await handleTelegramUpdate(
    request('hello', 800),
    deps,
  )

  assertEquals((await first.json()).status, 'delivery_failed')
  assertEquals(modelCalls, 1)
  assertEquals(
    client.updates.agent_conversation_turns,
    [{ delivery_status: 'failed' }],
  )

  const retryClient = new FakeAdmin(undefined, {
    agent_conversation_turns: [{
      id: 'stored-inbound',
      telegram_update_id: '800',
    }],
  })
  const retry = await handleTelegramUpdate(
    request('hello', 800),
    dependencies({
      client: retryClient,
      run: () => {
        modelCalls += 1
        return Promise.resolve({
          status: 'replied',
          reply: 'must not run',
          providerResponseId: 'response-duplicate',
          toolCallCount: 0,
        })
      },
    }),
  )

  assertEquals(await retry.json(), { accepted: true, duplicate: true })
  assertEquals(modelCalls, 1)
})
