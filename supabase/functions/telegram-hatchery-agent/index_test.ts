import { assertEquals } from '@std/assert'

import * as telegramAgent from './index.ts'
import { handleTelegramUpdate } from './index.ts'

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
