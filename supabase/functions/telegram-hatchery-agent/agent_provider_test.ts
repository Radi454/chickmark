import { assert, assertEquals, assertRejects } from '@std/assert'

import {
  AgentProviderError,
  classifyProviderFailure,
  createResponsesAgentProvider,
  type ProviderFailureClassification,
  type ProviderFailureSignal,
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

Deno.test('OpenAI provider defaults conversation requests to the Pip text model', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openai',
    apiKey: 'test-key',
    fetchImpl: async (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return Response.json({
        id: 'response-default',
        output: [{ type: 'message' }],
      })
    },
  })

  await provider.respond({ instructions: 'policy', input: [], tools: [] })

  assertEquals(models, ['gpt-5-nano'])
})

Deno.test('OpenRouter provider defaults conversation requests to the OpenRouter Pip text model', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    fetchImpl: async (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return Response.json({
        id: 'response-default',
        output: [{ type: 'message' }],
      })
    },
  })

  await provider.respond({ instructions: 'policy', input: [], tools: [] })

  assertEquals(models, ['openai/gpt-oss-120b'])
})

Deno.test('provider diagnostics use bounded IDs and returned model metadata', async () => {
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'openrouter/free',
    fetchImpl: () =>
      Promise.resolve(Response.json({
        id: `response-${'x'.repeat(300)}`,
        model: 'vendor/concrete-model',
        output: [{ type: 'message' }],
      })),
  })

  const result = await provider.respond({
    instructions: 'policy',
    input: [],
    tools: [],
  })

  assertEquals(result.id.length, 160)
  assertEquals(result.model, 'vendor/concrete-model')
  assertEquals(result.telemetry?.actualModel, 'vendor/concrete-model')
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
  assertEquals(error.reason, 'http_5xx_provider_error')
  assertEquals(error.terminal, true)
})

// --- classifyProviderFailure: every branch of the documented table -------

Deno.test('classifyProviderFailure implements the documented reason table', () => {
  const cases: Array<[ProviderFailureSignal, ProviderFailureClassification]> = [
    [{ kind: 'caller_aborted' }, { eligible: false, reason: null }],
    [{ kind: 'transport_error' }, {
      eligible: true,
      reason: 'provider_transport_error',
    }],
    [{ kind: 'attempt_timeout' }, {
      eligible: true,
      reason: 'attempt_timeout',
    }],
    [{ kind: 'http_status', status: 400 }, {
      eligible: true,
      reason: 'http_400_request_rejected',
    }],
    [{ kind: 'http_status', status: 402 }, {
      eligible: true,
      reason: 'http_402_payment_required',
    }],
    [{ kind: 'http_status', status: 404 }, {
      eligible: true,
      reason: 'http_404_model_unavailable',
    }],
    [{ kind: 'http_status', status: 408 }, {
      eligible: true,
      reason: 'http_408_request_timeout',
    }],
    [{ kind: 'http_status', status: 429 }, {
      eligible: true,
      reason: 'http_429_rate_limited',
    }],
    [{ kind: 'http_status', status: 500 }, {
      eligible: true,
      reason: 'http_5xx_provider_error',
    }],
    [{ kind: 'http_status', status: 502 }, {
      eligible: true,
      reason: 'http_5xx_provider_error',
    }],
    [{ kind: 'http_status', status: 503 }, {
      eligible: true,
      reason: 'http_5xx_provider_error',
    }],
    [{ kind: 'http_status', status: 504 }, {
      eligible: true,
      reason: 'http_5xx_provider_error',
    }],
    [{ kind: 'http_status', status: 599 }, {
      eligible: true,
      reason: 'http_5xx_provider_error',
    }],
    [{ kind: 'http_status', status: 401 }, { eligible: false, reason: null }],
    [{ kind: 'http_status', status: 403 }, { eligible: false, reason: null }],
    [{ kind: 'http_status', status: 413 }, { eligible: false, reason: null }],
    [{ kind: 'http_status', status: 418 }, { eligible: false, reason: null }],
    [{ kind: 'http_status', status: 301 }, { eligible: false, reason: null }],
    [{ kind: 'error_envelope' }, {
      eligible: true,
      reason: 'provider_error_envelope',
    }],
    [{ kind: 'malformed_response' }, {
      eligible: true,
      reason: 'malformed_response',
    }],
    [{ kind: 'empty_output' }, { eligible: true, reason: 'empty_output' }],
  ]
  for (const [signal, expected] of cases) {
    assertEquals(
      classifyProviderFailure(signal),
      expected,
      JSON.stringify(signal),
    )
  }
})

// --- Fallback ladder: eligible failures retry once on the fallback -------

function fallbackProvider(
  firstAttempt: (init: RequestInit) => Response | Promise<Response>,
  overrides: Partial<Parameters<typeof createResponsesAgentProvider>[0]> = {},
) {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'fallback/model',
    fetchImpl: async (_input, init) => {
      const model = JSON.parse(init!.body as string).model
      models.push(model)
      if (models.length === 1) return firstAttempt(init!)
      return Response.json({
        id: 'response-fallback',
        output: [{ type: 'message' }],
      })
    },
    ...overrides,
  })
  return { provider, models }
}

async function assertFallsBackOnce(
  firstAttempt: (init: RequestInit) => Response | Promise<Response>,
  expectedReason: string,
) {
  const { provider, models } = fallbackProvider(firstAttempt)
  const result = await provider.respond({
    instructions: 'p',
    input: [],
    tools: [],
  })
  assertEquals(models, ['primary/model', 'fallback/model'])
  assertEquals(result.telemetry?.fallbackOccurred, true)
  assertEquals(result.telemetry?.fallbackReason, expectedReason)
  assertEquals(result.telemetry?.actualModel, 'fallback/model')
  assertEquals(result.telemetry?.requestedModel, 'primary/model')
  assertEquals(result.telemetry?.attempts, 2)
  assertEquals(result.telemetry?.provider, 'openrouter')
  assert(typeof result.telemetry?.latencyMs === 'number')
}

Deno.test('HTTP 400 falls back once to the configured model', async () => {
  await assertFallsBackOnce(
    () => new Response('bad request', { status: 400 }),
    'http_400_request_rejected',
  )
})

Deno.test('HTTP 402 falls back once to the configured model', async () => {
  await assertFallsBackOnce(
    () => new Response('payment required', { status: 402 }),
    'http_402_payment_required',
  )
})

Deno.test('HTTP 404 falls back once to the configured model', async () => {
  await assertFallsBackOnce(
    () => new Response('not found', { status: 404 }),
    'http_404_model_unavailable',
  )
})

Deno.test('HTTP 408 falls back once to the configured model', async () => {
  await assertFallsBackOnce(
    () => new Response('timeout', { status: 408 }),
    'http_408_request_timeout',
  )
})

Deno.test('HTTP 429 falls back once to the configured model', async () => {
  await assertFallsBackOnce(
    () => new Response('rate limited', { status: 429 }),
    'http_429_rate_limited',
  )
})

Deno.test('HTTP 5xx falls back once to the configured model', async () => {
  await assertFallsBackOnce(
    () => new Response('upstream error', { status: 502 }),
    'http_5xx_provider_error',
  )
})

Deno.test('a 200 response carrying an error envelope falls back once', async () => {
  await assertFallsBackOnce(
    () => Response.json({ error: { message: 'nope' } }),
    'provider_error_envelope',
  )
})

Deno.test('a non-JSON body falls back once as malformed_response', async () => {
  await assertFallsBackOnce(
    () => new Response('not json', { status: 200 }),
    'malformed_response',
  )
})

Deno.test('a body missing a string id falls back once as malformed_response', async () => {
  await assertFallsBackOnce(
    () => Response.json({ output: [{ type: 'message' }] }),
    'malformed_response',
  )
})

Deno.test('output that is not an array falls back once as malformed_response', async () => {
  await assertFallsBackOnce(
    () => Response.json({ id: 'response-a', output: 'nope' }),
    'malformed_response',
  )
})

Deno.test('an empty output array falls back once as empty_output', async () => {
  await assertFallsBackOnce(
    () => Response.json({ id: 'response-a', output: [] }),
    'empty_output',
  )
})

Deno.test('a rejected fetch (not an abort) falls back once as provider_transport_error', async () => {
  await assertFallsBackOnce(
    () => {
      throw new Error('DNS lookup failed')
    },
    'provider_transport_error',
  )
})

Deno.test('a hung primary attempt falls back once as attempt_timeout', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'fallback/model',
    // Small override so the test does not wait out the real 8s default.
    attemptTimeoutMs: 15,
    fetchImpl: (_input, init) => {
      const model = JSON.parse(init!.body as string).model
      models.push(model)
      if (models.length > 1) {
        return Promise.resolve(
          Response.json({
            id: 'response-fallback',
            output: [{ type: 'message' }],
          }),
        )
      }
      // Simulate a hung request: only settle when the signal aborts, just
      // like a real fetch would.
      return new Promise((_resolve, reject) => {
        const signal = init?.signal
        const abort = () =>
          reject(signal?.reason ?? new DOMException('Aborted', 'AbortError'))
        if (signal?.aborted) abort()
        else signal?.addEventListener('abort', abort)
      })
    },
  })

  const result = await provider.respond({
    instructions: 'p',
    input: [],
    tools: [],
  })
  assertEquals(models, ['primary/model', 'fallback/model'])
  assertEquals(result.telemetry?.fallbackOccurred, true)
  assertEquals(result.telemetry?.fallbackReason, 'attempt_timeout')
})

// --- Non-eligible failures: no fallback attempt, error thrown ------------

Deno.test('HTTP 401 throws immediately with zero fallback attempts', async () => {
  const { provider, models } = fallbackProvider(
    () => new Response('unauthorized', { status: 401 }),
  )
  const error = await assertRejects(
    () => provider.respond({ instructions: 'p', input: [], tools: [] }),
    AgentProviderError,
  )
  assertEquals(models, ['primary/model'])
  assertEquals(error.reason, null)
  assertEquals(error.terminal, true)
  assertEquals(error.telemetry?.fallbackOccurred, false)
})

Deno.test('HTTP 403 throws immediately with zero fallback attempts', async () => {
  const { provider, models } = fallbackProvider(
    () => new Response('forbidden', { status: 403 }),
  )
  await assertRejects(
    () => provider.respond({ instructions: 'p', input: [], tools: [] }),
    AgentProviderError,
  )
  assertEquals(models, ['primary/model'])
})

Deno.test('HTTP 413 throws immediately with zero fallback attempts — the fallback has a smaller context window', async () => {
  const { provider, models } = fallbackProvider(
    () => new Response('payload too large', { status: 413 }),
  )
  await assertRejects(
    () => provider.respond({ instructions: 'p', input: [], tools: [] }),
    AgentProviderError,
  )
  assertEquals(models, ['primary/model'])
})

Deno.test('an equal primary and fallback model never falls back', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'same/model',
    fallbackModel: 'same/model',
    fetchImpl: async (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return new Response('rate limited', { status: 429 })
    },
  })
  const error = await assertRejects(
    () => provider.respond({ instructions: 'p', input: [], tools: [] }),
    AgentProviderError,
  )
  assertEquals(models, ['same/model'])
  assertEquals(error.reason, 'http_429_rate_limited')
  assertEquals(error.telemetry?.fallbackOccurred, false)
})

Deno.test('an absent fallback model never falls back', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'primary/model',
    fetchImpl: async (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return new Response('payment required', { status: 402 })
    },
  })
  await assertRejects(
    () => provider.respond({ instructions: 'p', input: [], tools: [] }),
    AgentProviderError,
  )
  assertEquals(models, ['primary/model'])
})

Deno.test('a fallback model is never used for the openai provider, even if configured', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openai',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'fallback/model',
    fetchImpl: async (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return new Response('rate limited', { status: 429 })
    },
  })
  await assertRejects(
    () => provider.respond({ instructions: 'p', input: [], tools: [] }),
    AgentProviderError,
  )
  assertEquals(models, ['primary/model'])
})

Deno.test('a second (fallback) attempt that also fails throws — only ever one fallback attempt', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'fallback/model',
    fetchImpl: async (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return new Response('rate limited', { status: 429 })
    },
  })
  const error = await assertRejects(
    () => provider.respond({ instructions: 'p', input: [], tools: [] }),
    AgentProviderError,
  )
  assertEquals(models, ['primary/model', 'fallback/model'])
  assertEquals(error.reason, 'http_429_rate_limited')
  assertEquals(error.telemetry?.fallbackOccurred, true)
  assertEquals(error.telemetry?.attempts, 2)
})

// --- Caller abort: rethrown untouched, never classified, never falls back ---

Deno.test('an already-aborted caller signal is rethrown untouched with zero attempts made', async () => {
  const controller = new AbortController()
  controller.abort()
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'fallback/model',
    fetchImpl: (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      const signal = init?.signal
      if (signal?.aborted) {
        return Promise.reject(
          signal.reason ?? new DOMException('Aborted', 'AbortError'),
        )
      }
      return Promise.resolve(
        Response.json({ id: 'x', output: [{ type: 'message' }] }),
      )
    },
  })

  await assertRejects(
    () =>
      provider.respond(
        { instructions: 'p', input: [], tools: [] },
        { signal: controller.signal },
      ),
    DOMException,
  )
  assertEquals(models, ['primary/model'])
})

Deno.test('a caller signal that aborts mid-flight is rethrown untouched, no fallback attempted', async () => {
  const controller = new AbortController()
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'fallback/model',
    fetchImpl: (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return new Promise((_resolve, reject) => {
        const signal = init?.signal
        const abort = () =>
          reject(signal?.reason ?? new DOMException('Aborted', 'AbortError'))
        if (signal?.aborted) abort()
        else signal?.addEventListener('abort', abort)
      })
    },
  })

  const pending = provider.respond(
    { instructions: 'p', input: [], tools: [] },
    { signal: controller.signal },
  )
  queueMicrotask(() => controller.abort())

  await assertRejects(() => pending, DOMException)
  assertEquals(models, ['primary/model'])
})

// --- Sticky fallback: within one provider instance (one turn) ------------

Deno.test('after the primary fails eligibly once, a later call on the SAME instance skips the primary entirely', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'fallback/model',
    fetchImpl: async (_input, init) => {
      const model = JSON.parse(init!.body as string).model
      models.push(model)
      // Call 1's primary attempt (models[0]) fails 429. Every other call
      // (the fallback in call 1, and call 2 entirely) succeeds.
      if (models.length === 1) {
        return new Response('rate limited', { status: 429 })
      }
      return Response.json({
        id: `response-${models.length}`,
        output: [{ type: 'message' }],
      })
    },
  })

  const first = await provider.respond({
    instructions: 'p',
    input: [],
    tools: [],
  })
  assertEquals(models, ['primary/model', 'fallback/model'])
  assertEquals(first.telemetry?.sticky, false)
  assertEquals(first.telemetry?.fallbackOccurred, true)
  assertEquals(first.telemetry?.attempts, 2)

  const second = await provider.respond({
    instructions: 'p',
    input: [],
    tools: [],
  })
  // The SECOND call issues exactly ONE fetch — straight to the fallback
  // model, no doomed primary attempt.
  assertEquals(models, ['primary/model', 'fallback/model', 'fallback/model'])
  assertEquals(second.telemetry?.sticky, true)
  assertEquals(second.telemetry?.fallbackOccurred, true)
  assertEquals(second.telemetry?.fallbackReason, 'http_429_rate_limited')
  assertEquals(second.telemetry?.actualModel, 'fallback/model')
  assertEquals(second.telemetry?.attempts, 1)
})

Deno.test('stickiness does not engage across two separate provider instances (two turns)', async () => {
  const modelsA: string[] = []
  const providerA = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'fallback/model',
    fetchImpl: async (_input, init) => {
      const model = JSON.parse(init!.body as string).model
      modelsA.push(model)
      if (modelsA.length === 1) {
        return new Response('rate limited', { status: 429 })
      }
      return Response.json({ id: 'response-a', output: [{ type: 'message' }] })
    },
  })
  await providerA.respond({ instructions: 'p', input: [], tools: [] })
  assertEquals(modelsA, ['primary/model', 'fallback/model'])

  // A brand-new provider instance (a new turn, per the door's per-request
  // construction) starts with no memory of providerA's sticky state.
  const modelsB: string[] = []
  const providerB = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'fallback/model',
    fetchImpl: async (_input, init) => {
      const model = JSON.parse(init!.body as string).model
      modelsB.push(model)
      return Response.json({ id: 'response-b', output: [{ type: 'message' }] })
    },
  })
  const result = await providerB.respond({
    instructions: 'p',
    input: [],
    tools: [],
  })
  assertEquals(modelsB, ['primary/model'])
  assertEquals(result.telemetry?.fallbackOccurred, false)
  assertEquals(result.telemetry?.sticky, false)
})

Deno.test('a sticky call that also fails throws, without re-attempting the primary', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'fallback/model',
    fetchImpl: async (_input, init) => {
      const model = JSON.parse(init!.body as string).model
      models.push(model)
      return new Response('rate limited', { status: 429 })
    },
  })

  await assertRejects(
    () => provider.respond({ instructions: 'p', input: [], tools: [] }),
    AgentProviderError,
  )
  assertEquals(models, ['primary/model', 'fallback/model'])

  const error = await assertRejects(
    () => provider.respond({ instructions: 'p', input: [], tools: [] }),
    AgentProviderError,
  )
  // Sticky call 2: exactly one fetch, straight to the fallback model.
  assertEquals(models, ['primary/model', 'fallback/model', 'fallback/model'])
  assertEquals(error.telemetry?.sticky, true)
  assertEquals(error.telemetry?.attempts, 1)
})

Deno.test('stickiness never engages when no fallback model is configured', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'primary/model',
    fetchImpl: async (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return new Response('rate limited', { status: 429 })
    },
  })

  await assertRejects(
    () => provider.respond({ instructions: 'p', input: [], tools: [] }),
    AgentProviderError,
  )
  await assertRejects(
    () => provider.respond({ instructions: 'p', input: [], tools: [] }),
    AgentProviderError,
  )

  assertEquals(models, ['primary/model', 'primary/model'])
})

// --- Vision routing --------------------------------------------------------

Deno.test('an input_image in the request routes to the configured vision model', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'openai/gpt-oss-120b',
    fallbackModel: 'openai/gpt-oss-20b',
    visionModel: 'google/gemma-4-31b-it',
    fetchImpl: (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return Promise.resolve(Response.json({
        id: 'response-vision',
        output: [{ type: 'message' }],
      }))
    },
  })

  const result = await provider.respond({
    instructions: 'p',
    input: [{
      role: 'user',
      content: [
        { type: 'input_text', text: 'What does this look like?' },
        {
          type: 'input_image',
          image_url: 'data:image/jpeg;base64,AAAA',
          detail: 'high',
        },
      ],
    }],
    tools: [],
  })

  assertEquals(models, ['google/gemma-4-31b-it'])
  assertEquals(result.telemetry?.visionRouted, true)
  assertEquals(result.telemetry?.requestedModel, 'google/gemma-4-31b-it')
  assertEquals(result.telemetry?.actualModel, 'google/gemma-4-31b-it')
})

Deno.test('normal text never invokes the vision model', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'openai/gpt-oss-120b',
    fallbackModel: 'openai/gpt-oss-20b',
    visionModel: 'google/gemma-4-31b-it',
    fetchImpl: (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return Promise.resolve(Response.json({
        id: 'response-text',
        output: [{ type: 'message' }],
      }))
    },
  })

  const result = await provider.respond({
    instructions: 'p',
    input: [{ role: 'user', content: 'مرحبا، عايز أعرف إنتاج القطيع' }],
    tools: [],
  })

  assertEquals(models, ['openai/gpt-oss-120b'])
  assert(!models.includes('google/gemma-4-31b-it'))
  assertEquals(result.telemetry?.visionRouted, false)
})

Deno.test('an input_file whose filename indicates an image or video also routes to the vision model', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'openai/gpt-oss-120b',
    visionModel: 'google/gemma-4-31b-it',
    fetchImpl: (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return Promise.resolve(Response.json({
        id: 'response-video',
        output: [{ type: 'message' }],
      }))
    },
  })

  const result = await provider.respond({
    instructions: 'p',
    input: [{
      role: 'user',
      content: [
        {
          type: 'input_file',
          filename: 'flock-clip.mp4',
          file_data: 'data:video/mp4;base64,AAAA',
        },
      ],
    }],
    tools: [],
  })

  assertEquals(models, ['google/gemma-4-31b-it'])
  assertEquals(result.telemetry?.visionRouted, true)
})

Deno.test('a vision call does not fall back to the text fallback model when no vision fallback is configured', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'openai/gpt-oss-120b',
    fallbackModel: 'openai/gpt-oss-20b',
    visionModel: 'google/gemma-4-31b-it',
    // visionFallbackModel deliberately absent.
    fetchImpl: (_input, init) => {
      models.push(JSON.parse(init!.body as string).model)
      return Promise.resolve(new Response('rate limited', { status: 429 }))
    },
  })

  const error = await assertRejects(
    () =>
      provider.respond({
        instructions: 'p',
        input: [{
          role: 'user',
          content: [{
            type: 'input_image',
            image_url: 'data:image/jpeg;base64,AAAA',
          }],
        }],
        tools: [],
      }),
    AgentProviderError,
  )

  // Exactly one fetch: the vision primary. Never the text fallback model.
  assertEquals(models, ['google/gemma-4-31b-it'])
  assert(!models.includes('openai/gpt-oss-20b'))
  assertEquals(error.telemetry?.fallbackOccurred, false)
  assertEquals(error.telemetry?.visionRouted, true)
  assertEquals(error.telemetry?.attempts, 1)
})

Deno.test('a vision call DOES fall back when an explicit vision fallback model is configured', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'openai/gpt-oss-120b',
    fallbackModel: 'openai/gpt-oss-20b',
    visionModel: 'google/gemma-4-31b-it',
    visionFallbackModel: 'vendor/other-vision-model',
    fetchImpl: (_input, init) => {
      const model = JSON.parse(init!.body as string).model
      models.push(model)
      if (models.length === 1) {
        return Promise.resolve(new Response('rate limited', { status: 429 }))
      }
      return Promise.resolve(Response.json({
        id: 'response-vision-fallback',
        output: [{ type: 'message' }],
      }))
    },
  })

  const result = await provider.respond({
    instructions: 'p',
    input: [{
      role: 'user',
      content: [{
        type: 'input_image',
        image_url: 'data:image/jpeg;base64,AAAA',
      }],
    }],
    tools: [],
  })

  // Never falls back to the text fallback model, only to the configured
  // vision-specific fallback.
  assertEquals(models, ['google/gemma-4-31b-it', 'vendor/other-vision-model'])
  assert(!models.includes('openai/gpt-oss-20b'))
  assertEquals(result.telemetry?.fallbackOccurred, true)
  assertEquals(result.telemetry?.visionRouted, true)
  assertEquals(result.telemetry?.actualModel, 'vendor/other-vision-model')
})

Deno.test('sticky text fallback does not force a later vision call onto a text model', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'openai/gpt-oss-120b',
    fallbackModel: 'openai/gpt-oss-20b',
    visionModel: 'google/gemma-4-31b-it',
    fetchImpl: (_input, init) => {
      const model = JSON.parse(init!.body as string).model
      models.push(model)
      // The text primary fails once (call 1), engaging text-route
      // stickiness. Every other request succeeds.
      if (models.length === 1) {
        return Promise.resolve(new Response('rate limited', { status: 429 }))
      }
      return Promise.resolve(Response.json({
        id: `response-${models.length}`,
        output: [{ type: 'message' }],
      }))
    },
  })

  // Call 1: plain text. Primary fails, falls back, engages STICKY TEXT
  // fallback for the rest of this provider instance's text calls.
  const first = await provider.respond({
    instructions: 'p',
    input: [{ role: 'user', content: 'إنتاج هبرد أسبوع 35 كام؟' }],
    tools: [],
  })
  assertEquals(models, ['openai/gpt-oss-120b', 'openai/gpt-oss-20b'])
  assertEquals(first.telemetry?.sticky, false)
  assertEquals(first.telemetry?.visionRouted, false)

  // Call 2: a vision call in the SAME turn (same provider instance). Sticky
  // TEXT fallback must not leak onto it — it must go straight to the vision
  // primary, never to the text fallback model that call 1's stickiness
  // engaged.
  const second = await provider.respond({
    instructions: 'p',
    input: [{
      role: 'user',
      content: [{
        type: 'input_image',
        image_url: 'data:image/jpeg;base64,AAAA',
      }],
    }],
    tools: [],
  })
  assertEquals(models, [
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'google/gemma-4-31b-it',
  ])
  assertEquals(second.telemetry?.visionRouted, true)
  assertEquals(second.telemetry?.sticky, false)
  assertEquals(second.telemetry?.actualModel, 'google/gemma-4-31b-it')

  // Call 3: another plain text call. Text stickiness from call 1 is still
  // in effect for the TEXT route — it skips straight to the text fallback,
  // one fetch only.
  const third = await provider.respond({
    instructions: 'p',
    input: [{ role: 'user', content: 'والفقس؟' }],
    tools: [],
  })
  assertEquals(models, [
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'google/gemma-4-31b-it',
    'openai/gpt-oss-20b',
  ])
  assertEquals(third.telemetry?.sticky, true)
  assertEquals(third.telemetry?.visionRouted, false)
})

Deno.test('sticky vision fallback does not force a later text call onto the vision model', async () => {
  const models: string[] = []
  const provider = createResponsesAgentProvider({
    provider: 'openrouter',
    apiKey: 'test-key',
    model: 'openai/gpt-oss-120b',
    fallbackModel: 'openai/gpt-oss-20b',
    visionModel: 'google/gemma-4-31b-it',
    visionFallbackModel: 'vendor/other-vision-model',
    fetchImpl: (_input, init) => {
      const model = JSON.parse(init!.body as string).model
      models.push(model)
      // The vision primary fails once (call 1), engaging vision-route
      // stickiness. Every other request succeeds.
      if (models.length === 1) {
        return Promise.resolve(new Response('rate limited', { status: 429 }))
      }
      return Promise.resolve(Response.json({
        id: `response-${models.length}`,
        output: [{ type: 'message' }],
      }))
    },
  })

  const first = await provider.respond({
    instructions: 'p',
    input: [{
      role: 'user',
      content: [{
        type: 'input_image',
        image_url: 'data:image/jpeg;base64,AAAA',
      }],
    }],
    tools: [],
  })
  assertEquals(models, ['google/gemma-4-31b-it', 'vendor/other-vision-model'])
  assertEquals(first.telemetry?.sticky, false)

  // A plain text call right after must go to the text primary, never to
  // either vision model that just went sticky.
  const second = await provider.respond({
    instructions: 'p',
    input: [{ role: 'user', content: 'إنتاج هبرد أسبوع 35 كام؟' }],
    tools: [],
  })
  assertEquals(models, [
    'google/gemma-4-31b-it',
    'vendor/other-vision-model',
    'openai/gpt-oss-120b',
  ])
  assertEquals(second.telemetry?.visionRouted, false)
  assertEquals(second.telemetry?.sticky, false)
  assertEquals(second.telemetry?.actualModel, 'openai/gpt-oss-120b')
})
