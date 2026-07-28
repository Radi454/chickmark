import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from 'jsr:@std/assert'

import type { PasgarIntakeSession } from './pasgar_conversation.ts'
import {
  interpretPasgarTurn,
  type PasgarAiConfig,
} from './pasgar_interpreter.ts'

type JsonRecord = Record<string, unknown>

function session(): PasgarIntakeSession {
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
    workingValues: {},
    pendingClarification: null,
    summaryVersion: 0,
    summarySnapshot: null,
    userConfirmedAt: null,
    createdAt: '2026-07-28T10:00:00.000Z',
    updatedAt: '2026-07-28T10:00:00.000Z',
  }
}

function interpretation(overrides: JsonRecord = {}): JsonRecord {
  return {
    intent: 'provide_data',
    language: 'en',
    candidates: [],
    contextCandidates: [],
    allRemainingZero: false,
    summaryVersion: null,
    clarification: null,
    ...overrides,
  }
}

function fakeConfig(
  outputs: Array<{ status?: number; body: JsonRecord }>,
  requests: Array<{ url: string; body: JsonRecord }>,
  overrides: Partial<PasgarAiConfig> = {},
): PasgarAiConfig {
  let index = 0
  const fetchImpl = ((
    input: string | URL | Request,
    init?: RequestInit,
  ) => {
    requests.push({
      url: String(input),
      body: JSON.parse(String(init?.body)) as JsonRecord,
    })
    const output = outputs[index++]
    return Promise.resolve(
      new Response(JSON.stringify(output.body), {
        status: output.status ?? 200,
      }),
    )
  }) as typeof fetch
  return {
    provider: 'openai',
    apiKey: 'test-key',
    model: 'test-model',
    fetchImpl,
    ...overrides,
  }
}

Deno.test('interpreter sends current state and a strict structured-output schema', async () => {
  const requests: Array<{ url: string; body: JsonRecord }> = []
  const result = await interpretPasgarTurn(
    {
      text: 'sample 40 reflex 2 peak 1',
      session: session(),
    },
    fakeConfig(
      [{
        body: {
          output_text: JSON.stringify(interpretation({
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
                fieldKey: 'pasgarBeakCount',
                value: 1,
                confidence: 0.94,
                sourcePhrase: 'peak 1',
              },
            ],
          })),
        },
      }],
      requests,
    ),
  )

  assertEquals(result.candidates.map((item) => item.fieldKey), [
    'pasgarSampleSize',
    'pasgarReflexesCount',
    'pasgarBeakCount',
  ])
  assertEquals(requests[0].url, 'https://api.openai.com/v1/responses')
  assertEquals(requests[0].body.store, false)
  const text = requests[0].body.text as JsonRecord
  const format = text.format as JsonRecord
  assertEquals(format.type, 'json_schema')
  assertEquals(format.strict, true)
  assertEquals(format.name, 'pasgar_turn_interpretation')
  const input = requests[0].body.input as JsonRecord[]
  const content = input[0].content as JsonRecord[]
  const promptPayload = JSON.parse(String(content[0].text)) as JsonRecord
  const promptSession = promptPayload.session as JsonRecord
  assertEquals(promptSession.state, 'collecting')
  assertStringIncludes(String(content[0].text), '"peak"')
})

Deno.test('interpreter accepts Arabic and mixed-language results', async () => {
  const requests: Array<{ url: string; body: JsonRecord }> = []
  const result = await interpretPasgarTurn(
    { text: 'العينة 40 و reflex 2', session: session() },
    fakeConfig(
      [{
        body: {
          output_text: JSON.stringify(interpretation({
            language: 'mixed',
            candidates: [{
              fieldKey: 'pasgarSampleSize',
              value: 40,
              confidence: 0.98,
              sourcePhrase: 'العينة 40',
            }],
          })),
        },
      }],
      requests,
    ),
  )

  assertEquals(result.language, 'mixed')
  assertEquals(result.candidates[0].value, 40)
})

Deno.test('interpreter keeps ordinary questions as mission chat', async () => {
  const requests: Array<{ url: string; body: JsonRecord }> = []
  const result = await interpretPasgarTurn(
    { text: 'What is yor name', session: null },
    fakeConfig(
      [{
        body: {
          output_text: JSON.stringify(interpretation({
            intent: 'mission_chat',
          })),
        },
      }],
      requests,
    ),
  )

  assertEquals(result.intent, 'mission_chat')
  assertEquals(result.candidates, [])
  assertEquals(result.contextCandidates, [])
})

Deno.test('interpreter retries an OpenRouter credit failure with the free router', async () => {
  const requests: Array<{ url: string; body: JsonRecord }> = []
  const result = await interpretPasgarTurn(
    { text: 'sample 40', session: session() },
    fakeConfig(
      [
        { status: 402, body: { error: 'credits' } },
        {
          body: {
            output_text: JSON.stringify(interpretation({
              candidates: [{
                fieldKey: 'pasgarSampleSize',
                value: 40,
                confidence: 0.99,
                sourcePhrase: 'sample 40',
              }],
            })),
          },
        },
      ],
      requests,
      {
        provider: 'openrouter',
        model: 'paid/model',
      },
    ),
  )

  assertEquals(result.candidates[0].value, 40)
  assertEquals(requests.length, 2)
  assertEquals(requests[0].body.model, 'paid/model')
  assertEquals(requests[1].body.model, 'openrouter/free')
})

Deno.test('interpreter rejects a structurally invalid candidate', async () => {
  const requests: Array<{ url: string; body: JsonRecord }> = []

  await assertRejects(
    () =>
      interpretPasgarTurn(
        { text: 'mystery 40', session: session() },
        fakeConfig(
          [{
            body: {
              output_text: JSON.stringify(interpretation({
                candidates: [{
                  fieldKey: 'unknownField',
                  value: 40,
                  confidence: 0.99,
                  sourcePhrase: 'mystery 40',
                }],
              })),
            },
          }],
          requests,
        ),
      ),
    Error,
    'invalid structure',
  )
})
