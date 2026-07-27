import { assertEquals } from '@std/assert'
import type { ExtractedHatcheryRow } from './extraction_schema.ts'
import { extractHatcheryRows, handleTelegramUpdate } from './index.ts'

type FakeRow = Partial<ExtractedHatcheryRow>
type FakeRecord = Record<string, unknown>

Deno.test('rejects request with missing Telegram secret', async () => {
  const response = await handleTelegramUpdate(
    new Request('https://example.test', { method: 'POST', body: '{}' }),
    {
      expectedTelegramSecret: 'secret',
      adminClient: fakeAdminClient(),
      extract: fakeExtract([]),
      sendTelegramMessage: async () => {},
    },
  )

  assertEquals(response.status, 401)
})

Deno.test('stores one submission and one draft batch for extracted rows', async () => {
  const calls: string[] = []
  const writes: FakeWrites = { inserts: {}, updates: {} }
  const response = await handleTelegramUpdate(
    new Request('https://example.test', {
      method: 'POST',
      headers: { 'X-Telegram-Bot-Api-Secret-Token': 'secret' },
      body: JSON.stringify({
        update_id: 100,
        message: {
          message_id: 10,
          date: 1784890000,
          chat: { id: 123 },
          from: { id: 456, first_name: 'Staff' },
          text: 'Customer A Ross flock eggs placed 19200 total 11518',
        },
      }),
    }),
    {
      expectedTelegramSecret: 'secret',
      adminClient: fakeAdminClient(calls, allowedStaffLink(), writes),
      extract: fakeExtract([
        extractedRow({
          customerName: 'Customer A',
          flockName: 'Ross flock',
          eggsPlaced: 19200,
          totalProduction: 11518,
        }),
      ]),
      sendTelegramMessage: async () => {},
    },
  )

  assertEquals(response.status, 200)
  assertEquals(calls.includes('agent_submissions.insert'), true)
  assertEquals(calls.includes('hatchery_draft_batches.insert'), true)
  assertEquals(calls.includes('hatchery_draft_rows.insert'), true)
  const insertedRows = writes.inserts.hatchery_draft_rows as FakeRecord[]
  assertEquals(insertedRows[0].hatchability_pct, 11518 / 19200 * 100)
})

Deno.test('rejects revoked staff without creating a submission', async () => {
  const calls: string[] = []
  const messages: string[] = []
  const response = await handleTelegramUpdate(
    telegramRequest({ text: 'eggs placed 100 total 80' }),
    {
      expectedTelegramSecret: 'secret',
      adminClient: fakeAdminClient(calls, {
        id: 'staff-link-1',
        status: 'revoked',
      }),
      extract: fakeExtract([]),
      sendTelegramMessage: (_chatId, text) => {
        messages.push(text)
        return Promise.resolve()
      },
    },
  )

  assertEquals(response.status, 200)
  assertEquals(calls.includes('agent_submissions.insert'), false)
  assertEquals(messages.length, 1)
})

Deno.test('stores bilingual missing questions and waits for staff', async () => {
  const calls: string[] = []
  const messages: string[] = []
  const response = await handleTelegramUpdate(
    telegramRequest({ text: 'Customer A, eggs placed 100' }),
    {
      expectedTelegramSecret: 'secret',
      adminClient: fakeAdminClient(calls),
      extract: () =>
        Promise.resolve({
          rows: [extractedRow({ eggsPlaced: 100 })],
          missingQuestions: [{
            rowOrdinal: 1,
            fieldKey: 'totalProduction',
            questionTextEn: 'What is total production?',
            questionTextAr: 'ما إجمالي الإنتاج؟',
          }],
        }),
      sendTelegramMessage: (_chatId, text) => {
        messages.push(text)
        return Promise.resolve()
      },
    },
  )

  assertEquals((await response.json()).status, 'waiting_for_staff_answer')
  assertEquals(calls.includes('agent_questions.insert'), true)
  assertEquals(messages.at(-1)?.includes('ما إجمالي الإنتاج؟'), true)
})

Deno.test('routes invalid hatchability inputs to admin review', async () => {
  const response = await handleTelegramUpdate(
    telegramRequest({ text: 'Customer A' }),
    {
      expectedTelegramSecret: 'secret',
      adminClient: fakeAdminClient(),
      extract: fakeExtract([extractedRow()]),
      sendTelegramMessage: () => Promise.resolve(),
    },
  )

  assertEquals((await response.json()).status, 'needs_admin_review')
})

Deno.test('sends image input and parses mixed-language multi-row output', async () => {
  const requestBodies: FakeRecord[] = []
  const responseRows = [
    extractedRow({ rowOrdinal: 1, customerName: 'Customer A' }),
    extractedRow({ rowOrdinal: 2, customerName: 'العميل ب' }),
  ]
  const fetchImpl = ((_input: string | URL | Request, init?: RequestInit) => {
    requestBodies.push(JSON.parse(String(init?.body)) as FakeRecord)
    return Promise.resolve(
      new Response(
        JSON.stringify({
          output: [{
            content: [{
              type: 'output_text',
              text: JSON.stringify({
                rows: responseRows,
                missingQuestions: [],
              }),
            }],
          }],
        }),
        { status: 200 },
      ),
    )
  }) as typeof fetch

  const extraction = await extractHatcheryRows(
    {
      sourceKind: 'image',
      text: 'صفان / two rows',
      fileName: 'table.jpg',
      mimeType: 'image/jpeg',
      fileData: 'data:image/jpeg;base64,AA==',
    },
    {
      openAiApiKey: 'test-openai-key',
      fetchImpl,
      model: 'test-model',
    },
  )

  assertEquals(extraction.rows.length, 2)
  assertEquals(extraction.rows[1].customerName, 'العميل ب')
  assertEquals(requestBodies.length, 1)
  const requestBody = requestBodies[0]
  const textFormat = (requestBody.text as FakeRecord).format as FakeRecord
  assertEquals(textFormat.type, 'json_schema')
  assertEquals(textFormat.strict, true)
  const input = requestBody.input as FakeRecord[]
  const content = input[0].content as FakeRecord[]
  assertEquals(content.map((item) => item.type), [
    'input_text',
    'input_image',
  ])
})

function fakeAdminClient(
  calls: string[] = [],
  staffLink: FakeRecord | null = allowedStaffLink(),
  writes: FakeWrites = { inserts: {}, updates: {} },
) {
  return {
    from(table: string) {
      const filters: Record<string, unknown> = {}
      const query = {
        select(_columns: string) {
          return query
        },
        eq(column: string, value: unknown) {
          filters[column] = value
          return query
        },
        maybeSingle() {
          calls.push(`${table}.maybeSingle`)
          if (table === 'telegram_staff_links') {
            return Promise.resolve({ data: staffLink, error: null })
          }
          if (table === 'agent_settings') {
            return Promise.resolve({
              data: {
                telegram_enabled: 1,
                minimum_ready_confidence_pct: 85,
              },
              error: null,
            })
          }
          return Promise.resolve({ data: null, error: null })
        },
        insert(_rows: unknown) {
          calls.push(`${table}.insert`)
          writes.inserts[table] = _rows
          return Promise.resolve({ data: null, error: null })
        },
        update(_values: unknown) {
          calls.push(`${table}.update`)
          writes.updates[table] = _values
          return {
            eq(_column: string, _value: unknown) {
              return Promise.resolve({ data: null, error: null })
            },
          }
        },
      }
      return query
    },
  }
}

interface FakeWrites {
  inserts: Record<string, unknown>
  updates: Record<string, unknown>
}

function allowedStaffLink(): FakeRecord {
  return {
    id: 'staff-link-1',
    status: 'allowed',
  }
}

function telegramRequest(message: FakeRecord): Request {
  return new Request('https://example.test', {
    method: 'POST',
    headers: { 'X-Telegram-Bot-Api-Secret-Token': 'secret' },
    body: JSON.stringify({
      update_id: 100,
      message: {
        message_id: 10,
        date: 1784890000,
        chat: { id: 123 },
        from: { id: 456, first_name: 'Staff' },
        ...message,
      },
    }),
  })
}

function fakeExtract(rows: FakeRow[]) {
  return () => Promise.resolve({ rows, missingQuestions: [] })
}

function extractedRow(overrides: FakeRow = {}): FakeRow {
  return {
    rowOrdinal: 1,
    customerName: null,
    flockName: null,
    stationName: null,
    breed: null,
    eggsPlaced: null,
    productionDate: null,
    placementDate: null,
    eggWeightG: null,
    fertilityPct: null,
    transferWeightG: null,
    setterNumber: null,
    hatcherNumber: null,
    hatchDate: null,
    healthyChicks: null,
    secondGradeChicks: null,
    condemnedChicks: null,
    totalProduction: null,
    confidencePct: 95,
    ...overrides,
  }
}
