import { assertEquals, assertStringIncludes } from '@std/assert'

import { handleTelegramUpdate } from './index.ts'

const indexSource = await Deno.readTextFile(
  new URL('./index.ts', import.meta.url),
)
assertStringIncludes(indexSource, 'createSupabaseAgentAuditStore')
assertStringIncludes(indexSource, 'createAgentAuditToolHandlers')

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
