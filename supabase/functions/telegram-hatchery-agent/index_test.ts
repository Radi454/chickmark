import { assertEquals, assertMatch } from '@std/assert'

import { handleTelegramUpdate } from './index.ts'

Deno.test('runtime constructs the audit store and registers its handlers', async () => {
  const indexSource = await Deno.readTextFile(
    new URL('./index.ts', import.meta.url),
  )

  assertMatch(
    indexSource,
    /const auditStore = createSupabaseAgentAuditStore\(\s*adminClient as unknown as AgentAuditClient,\s*\)/,
  )
  assertMatch(
    indexSource,
    /const handlers = \{[\s\S]*?\.\.\.createAgentAuditToolHandlers\(auditStore\),/,
  )
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
