// supabase/functions/app-hatchery-agent/voice_test.ts
import { assertEquals, assertRejects } from '@std/assert'

import {
  readVoiceConfig,
  synthesizeSpeech,
  transcribeAudio,
  VoiceProviderError,
} from './voice.ts'

function fakeFetch(
  handler: (input: string | URL | Request, init?: RequestInit) => Response,
): typeof fetch {
  return ((input: string | URL | Request, init?: RequestInit) =>
    Promise.resolve(handler(input, init))) as typeof fetch
}

Deno.test('readVoiceConfig prefers OPENAI_VOICE_KEY and trims it', () => {
  Deno.env.set('OPENAI_VOICE_KEY', '  sk-voice-123  ')
  Deno.env.set('OPENAI_API_KEY', 'sk-brain-456')
  try {
    assertEquals(readVoiceConfig(), { apiKey: 'sk-voice-123' })
  } finally {
    Deno.env.delete('OPENAI_VOICE_KEY')
    Deno.env.delete('OPENAI_API_KEY')
  }
})

Deno.test('readVoiceConfig falls back to OPENAI_API_KEY when no voice key is set', () => {
  Deno.env.delete('OPENAI_VOICE_KEY')
  Deno.env.set('OPENAI_API_KEY', '  sk-brain-456  ')
  try {
    assertEquals(readVoiceConfig(), { apiKey: 'sk-brain-456' })
  } finally {
    Deno.env.delete('OPENAI_API_KEY')
  }
})

Deno.test('readVoiceConfig returns null when neither key is set', () => {
  Deno.env.delete('OPENAI_VOICE_KEY')
  Deno.env.delete('OPENAI_API_KEY')
  assertEquals(readVoiceConfig(), null)
})

Deno.test('transcribeAudio posts multipart form and returns trimmed text', async () => {
  let sawAuth: string | null = null
  let model: FormDataEntryValue | null = null
  const fetchImpl = fakeFetch((_url, init) => {
    sawAuth = (init?.headers as Record<string, string>)['Authorization']
    model = (init?.body as FormData).get('model')
    return new Response(JSON.stringify({ text: '  what is the hatch rate?  ' }), {
      status: 200,
    })
  })
  const text = await transcribeAudio('aGVsbG8=', {
    apiKey: 'sk-test',
    fetchImpl,
  })
  assertEquals(text, 'what is the hatch rate?')
  assertEquals(sawAuth, 'Bearer sk-test')
  assertEquals(model, 'gpt-4o-mini-transcribe')
})

Deno.test('transcribeAudio rejects invalid base64', async () => {
  await assertRejects(
    () => transcribeAudio('not-base64!!!', { apiKey: 'sk-test', fetchImpl: fakeFetch(() => new Response()) }),
    VoiceProviderError,
  )
})

Deno.test('transcribeAudio throws on non-2xx response', async () => {
  const fetchImpl = fakeFetch(() => new Response('', { status: 500 }))
  await assertRejects(
    () => transcribeAudio('aGVsbG8=', { apiKey: 'sk-test', fetchImpl }),
    VoiceProviderError,
  )
})

Deno.test('transcribeAudio throws when text is empty', async () => {
  const fetchImpl = fakeFetch(() => new Response(JSON.stringify({ text: '   ' }), { status: 200 }))
  await assertRejects(
    () => transcribeAudio('aGVsbG8=', { apiKey: 'sk-test', fetchImpl }),
    VoiceProviderError,
  )
})

Deno.test('synthesizeSpeech returns base64 audio bytes round-trippably', async () => {
  const audioBytes = new Uint8Array([1, 2, 3, 4, 5])
  const fetchImpl = fakeFetch(() =>
    new Response(audioBytes, { status: 200 })
  )
  const base64 = await synthesizeSpeech('Hatch was 84%.', {
    apiKey: 'sk-test',
    fetchImpl,
  })
  const decoded = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))
  assertEquals(Array.from(decoded), Array.from(audioBytes))
})

Deno.test('synthesizeSpeech sends the new model/voice and per-language instructions', async () => {
  const bodies: Record<string, unknown>[] = []
  const fetchImpl = fakeFetch((_url, init) => {
    bodies.push(JSON.parse(init?.body as string))
    return new Response(new Uint8Array([1]), { status: 200 })
  })
  const config = { apiKey: 'sk-test', fetchImpl }

  await synthesizeSpeech('Hello.', config)
  await synthesizeSpeech('Hello.', config, 'en')
  await synthesizeSpeech('نسبة الفقس ٨٤٪', config, 'ar')
  await synthesizeSpeech('Hatch كان 84%', config, 'mixed')

  for (const body of bodies) {
    assertEquals(body.model, 'gpt-4o-mini-tts')
    // Same voice Pip Live uses, so the assistant does not change identity
    // between a recorded voice note and a live call.
    assertEquals(body.voice, 'cedar')
  }
  // No instructions unless the language needs steering.
  assertEquals('instructions' in bodies[0], false)
  assertEquals('instructions' in bodies[1], false)
  assertEquals(typeof bodies[2].instructions, 'string')
  assertEquals(typeof bodies[3].instructions, 'string')
  // Arabic steering must name the Egyptian dialect explicitly and rule out
  // MSA — "Egyptian Arabic" alone read as MSA in practice.
  const arabic = bodies[2].instructions as string
  assertEquals(arabic.includes('Egyptian Colloquial Arabic'), true)
  assertEquals(arabic.includes('NOT Modern Standard Arabic'), true)
})

Deno.test('synthesizeSpeech throws on non-2xx response', async () => {
  const fetchImpl = fakeFetch(() => new Response('', { status: 429 }))
  await assertRejects(
    () => synthesizeSpeech('hi', { apiKey: 'sk-test', fetchImpl }),
    VoiceProviderError,
  )
})

Deno.test('synthesizeSpeech throws on empty audio body', async () => {
  const fetchImpl = fakeFetch(() => new Response(new Uint8Array(0), { status: 200 }))
  await assertRejects(
    () => synthesizeSpeech('hi', { apiKey: 'sk-test', fetchImpl }),
    VoiceProviderError,
  )
})
