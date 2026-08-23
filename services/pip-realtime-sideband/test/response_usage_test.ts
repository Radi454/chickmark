import { assertEquals } from '@std/assert'
import { parseResponseUsage } from '../src/response_usage.ts'

// The exact shape measured live against production (gpt-realtime-2.1-mini),
// pasted verbatim into the task background this test module implements.
const REALISTIC_PAYLOAD = {
  id: 'resp_abc123',
  status: 'completed',
  usage: {
    total_tokens: 5516,
    input_tokens: 5453,
    output_tokens: 63,
    input_token_details: {
      text_tokens: 5453,
      audio_tokens: 0,
      image_tokens: 0,
      cached_tokens: 4864,
      cached_tokens_details: { text_tokens: 4864, audio_tokens: 0 },
    },
    output_token_details: { text_tokens: 29, audio_tokens: 34 },
  },
}

Deno.test('a full realistic payload maps every field, including the derived uncached count', () => {
  const usage = parseResponseUsage(REALISTIC_PAYLOAD)
  assertEquals(usage, {
    responseId: 'resp_abc123',
    status: 'completed',
    totalTokens: 5516,
    inputTokens: 5453,
    outputTokens: 63,
    cachedInputTokens: 4864,
    uncachedInputTokens: 589, // 5453 - 4864
    inputTextTokens: 5453,
    inputAudioTokens: 0,
    inputImageTokens: 0,
    cachedTextTokens: 4864,
    cachedAudioTokens: 0,
    outputTextTokens: 29,
    outputAudioTokens: 34,
  })
})

Deno.test('a response with no usage block at all still parses, all-zero', () => {
  const usage = parseResponseUsage({ id: 'resp_no_usage', status: 'failed' })
  assertEquals(usage, {
    responseId: 'resp_no_usage',
    status: 'failed',
    totalTokens: 0,
    inputTokens: 0,
    outputTokens: 0,
    cachedInputTokens: 0,
    uncachedInputTokens: 0,
    inputTextTokens: 0,
    inputAudioTokens: 0,
    inputImageTokens: 0,
    cachedTextTokens: 0,
    cachedAudioTokens: 0,
    outputTextTokens: 0,
    outputAudioTokens: 0,
  })
})

Deno.test('missing input_token_details defaults its fields to 0 without throwing', () => {
  const usage = parseResponseUsage({
    id: 'resp_1',
    usage: { total_tokens: 100, input_tokens: 80, output_tokens: 20 },
  })
  assertEquals(usage?.inputTextTokens, 0)
  assertEquals(usage?.inputAudioTokens, 0)
  assertEquals(usage?.inputImageTokens, 0)
  assertEquals(usage?.cachedInputTokens, 0)
  // No cache info at all means nothing to subtract: all of input is uncached.
  assertEquals(usage?.uncachedInputTokens, 80)
})

Deno.test('missing cached_tokens_details defaults its fields to 0 without throwing', () => {
  const usage = parseResponseUsage({
    id: 'resp_1',
    usage: {
      input_tokens: 100,
      input_token_details: { text_tokens: 100, cached_tokens: 40 },
    },
  })
  assertEquals(usage?.cachedInputTokens, 40)
  assertEquals(usage?.cachedTextTokens, 0)
  assertEquals(usage?.cachedAudioTokens, 0)
  assertEquals(usage?.uncachedInputTokens, 60)
})

Deno.test('non-numeric garbage in every numeric field becomes 0, not NaN or null', () => {
  const usage = parseResponseUsage({
    id: 'resp_garbage',
    usage: {
      total_tokens: 'a lot',
      input_tokens: null,
      output_tokens: { nested: true },
      input_token_details: {
        text_tokens: undefined,
        audio_tokens: [1, 2, 3],
        image_tokens: NaN,
        cached_tokens: 'forty',
        cached_tokens_details: { text_tokens: false, audio_tokens: 'x' },
      },
      output_token_details: { text_tokens: 'y', audio_tokens: {} },
    },
  })
  assertEquals(usage, {
    responseId: 'resp_garbage',
    status: 'completed',
    totalTokens: 0,
    inputTokens: 0,
    outputTokens: 0,
    cachedInputTokens: 0,
    uncachedInputTokens: 0,
    inputTextTokens: 0,
    inputAudioTokens: 0,
    inputImageTokens: 0,
    cachedTextTokens: 0,
    cachedAudioTokens: 0,
    outputTextTokens: 0,
    outputAudioTokens: 0,
  })
})

Deno.test('a zero-usage failed response is NOT dropped by the parser — the caller decides', () => {
  const usage = parseResponseUsage({
    id: 'resp_failed',
    status: 'failed',
    usage: {
      total_tokens: 0,
      input_tokens: 0,
      output_tokens: 0,
      input_token_details: {
        text_tokens: 0,
        audio_tokens: 0,
        image_tokens: 0,
        cached_tokens: 0,
        cached_tokens_details: { text_tokens: 0, audio_tokens: 0 },
      },
      output_token_details: { text_tokens: 0, audio_tokens: 0 },
    },
  })
  assertEquals(usage?.status, 'failed')
  assertEquals(usage?.totalTokens, 0)
})

Deno.test('a cancelled response passes its status through unchanged', () => {
  const usage = parseResponseUsage({ id: 'resp_cancelled', status: 'cancelled' })
  assertEquals(usage?.status, 'cancelled')
})

Deno.test('an absent response id returns null', () => {
  assertEquals(parseResponseUsage({ status: 'completed', usage: {} }), null)
})

Deno.test('a non-string response id returns null', () => {
  assertEquals(parseResponseUsage({ id: 12345 }), null)
})

Deno.test('an empty-string response id returns null', () => {
  assertEquals(parseResponseUsage({ id: '' }), null)
})

Deno.test('a missing status defaults to completed', () => {
  const usage = parseResponseUsage({ id: 'resp_1' })
  assertEquals(usage?.status, 'completed')
})

Deno.test('cached tokens greater than input tokens clamp the derived uncached count at 0', () => {
  const usage = parseResponseUsage({
    id: 'resp_1',
    usage: {
      input_tokens: 10,
      input_token_details: { cached_tokens: 50 },
    },
  })
  assertEquals(usage?.cachedInputTokens, 50)
  assertEquals(usage?.uncachedInputTokens, 0)
})
