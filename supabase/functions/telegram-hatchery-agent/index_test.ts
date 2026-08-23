import { assertEquals } from '@std/assert'

import * as telegramAgent from './index.ts'
import {
  extractHatcheryRows,
  handleTelegramUpdate,
  readAiConfig,
  readAiExtractionConfig,
} from './index.ts'

async function withModelEnvironment<T>(run: () => T | Promise<T>): Promise<T> {
  const names = [
    'AI_PROVIDER',
    'OPENROUTER_API_KEY',
    'OPENAI_API_KEY',
    'OPENAI_TEXT_MODEL',
    'OPENAI_MODEL',
    'AI_MODEL',
  ]
  const previous = new Map(names.map((name) => [name, Deno.env.get(name)]))
  Deno.env.set('AI_PROVIDER', 'openai')
  Deno.env.delete('OPENROUTER_API_KEY')
  Deno.env.set('OPENAI_API_KEY', 'test-openai-key')
  Deno.env.set('OPENAI_TEXT_MODEL', '  telegram-text-model  ')
  Deno.env.set('OPENAI_MODEL', 'extraction-model')
  Deno.env.set('AI_MODEL', 'legacy-shared-model')
  try {
    return await run()
  } finally {
    for (const [name, value] of previous) {
      if (value === undefined) Deno.env.delete(name)
      else Deno.env.set(name, value)
    }
  }
}

Deno.test('Telegram conversation config uses OPENAI_TEXT_MODEL', async () => {
  await withModelEnvironment(() => {
    assertEquals(readAiConfig(), {
      provider: 'openai',
      apiKey: 'test-openai-key',
      model: 'telegram-text-model',
    })
  })
})

Deno.test('legacy compatibility extraction sends OPENAI_MODEL', async () => {
  await withModelEnvironment(async () => {
    const config = readAiExtractionConfig()
    if (!config) throw new Error('expected extraction config')
    let requestModel: string | null = null

    await extractHatcheryRows({
      sourceKind: 'text',
      text: 'Please extract this unstructured hatchery note',
      fileName: null,
      mimeType: null,
      fileData: null,
    }, {
      ...config,
      fetchImpl: async (_input, init) => {
        requestModel = JSON.parse(init!.body as string).model
        return Response.json({
          output: [{
            type: 'message',
            content: [{
              type: 'output_text',
              text: JSON.stringify({ rows: [], missingQuestions: [] }),
            }],
          }],
        })
      },
    })

    assertEquals(requestModel, 'extraction-model')
  })
})

Deno.test('production handler registry includes executable audit handlers', () => {
  const compose = (telegramAgent as unknown as {
    createUnifiedAgentToolHandlers?: (
      adminClient: unknown,
    ) => Record<string, unknown>
  }).createUnifiedAgentToolHandlers

  assertEquals(typeof compose, 'function')
  if (typeof compose !== 'function') return

  const handlers = compose({
    from() {
      throw new Error('store construction must not query the database')
    },
  })
  assertEquals(typeof handlers.list_customer_audits, 'function')
  assertEquals(typeof handlers.select_audit_option, 'function')
  assertEquals(typeof handlers.get_audit_summary, 'function')
})

Deno.test('webhook rejects a missing Telegram secret before invoking the agent', async () => {
  let agentCalls = 0
  const response = await handleTelegramUpdate(
    new Request('https://example.test', { method: 'POST', body: '{}' }),
    {
      expectedTelegramSecret: 'secret',
      adminClient: {
        from() {
          throw new Error('database should not be called')
        },
      },
      resolveScope: () => {
        throw new Error('scope should not be resolved')
      },
      runAgentTurn: () => {
        agentCalls += 1
        throw new Error('agent should not be called')
      },
      sendTelegramMessage: () => Promise.resolve(),
    },
  )

  assertEquals(response.status, 401)
  assertEquals(agentCalls, 0)
})

Deno.test('webhook rejects non-POST methods before invoking the agent', async () => {
  let agentCalls = 0
  const response = await handleTelegramUpdate(
    new Request('https://example.test', { method: 'GET' }),
    {
      expectedTelegramSecret: 'secret',
      adminClient: {
        from() {
          throw new Error('database should not be called')
        },
      },
      resolveScope: () => {
        throw new Error('scope should not be resolved')
      },
      runAgentTurn: () => {
        agentCalls += 1
        throw new Error('agent should not be called')
      },
      sendTelegramMessage: () => Promise.resolve(),
    },
  )

  assertEquals(response.status, 405)
  assertEquals(agentCalls, 0)
})
