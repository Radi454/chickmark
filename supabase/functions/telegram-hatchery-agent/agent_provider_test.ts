import { assert, assertEquals, assertRejects } from '@std/assert'

import {
  AgentProviderError,
  createResponsesAgentProvider,
} from './agent_provider.ts'

Deno.test('Responses provider sends bounded function tools and parses output', async () => {
  const requests: Record<string, unknown>[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openai',
    apiKey: 'test-key',
    model: 'test-model',
    fetchImpl: async (_input, init) => {
      requests.push(JSON.parse(init!.body as string))
      return Response.json({
        id: 'response-a',
        output: [{
          type: 'message',
          role: 'assistant',
          content: [{ type: 'output_text', text: 'أهلاً، كيف أساعدك؟' }],
        }],
      })
    },
  })

  const result = await provider.respond({
    instructions: 'policy',
    input: [{ role: 'user', content: 'مرحبا' }],
    tools: [{
      type: 'function',
      name: 'get_user_scope',
      description: 'Get scope',
      parameters: {
        type: 'object',
        properties: {},
        required: [],
        additionalProperties: false,
      },
    }],
  })

  assertEquals(result.id, 'response-a')
  assertEquals(result.output.length, 1)
  assertEquals(requests[0].parallel_tool_calls, false)
  assertEquals(requests[0].store, false)
  assertEquals(
    (requests[0].tools as Record<string, unknown>[])[0].strict,
    false,
  )
})

Deno.test('OpenRouter 402 retries once with its free model', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'paid/model',
    fetchImpl: async (_input, init) => {
      const request = JSON.parse(init!.body as string)
      models.push(request.model)
      return models.length === 1
        ? new Response('payment required', { status: 402 })
        : Response.json({ id: 'response-b', output: [] })
    },
  })

  await provider.respond({
    instructions: 'policy',
    input: [],
    tools: [],
  })

  assertEquals(models, ['paid/model', 'openrouter/free'])
})

Deno.test('provider errors are bounded and do not expose response bodies', async () => {
  const provider = createResponsesAgentProvider({
    provider: 'openai',
    apiKey: 'test-key',
    fetchImpl: () =>
      Promise.resolve(
        new Response('secret upstream body', { status: 500 }),
      ),
  })

  const error = await assertRejects(
    () =>
      provider.respond({
        instructions: 'policy',
        input: [],
        tools: [],
      }),
    AgentProviderError,
  )
  assert(error.message.includes('500'))
  assertEquals(error.message.includes('secret upstream body'), false)
})
