// Standalone probe: does `language:'ar'` actually IMPROVE Egyptian-Arabic
// transcription, and does it BREAK English or mixed-language speech?
//
// NOT part of the runtime service. Run manually:
//   OPENAI_API_KEY="$(gcloud secrets versions access latest \
//     --secret=openai-api-key --project=chickmark-ai-agent)" \
//     deno run --allow-net --allow-env --allow-read \
//     tools/probe_transcription_quality.ts
//
// WHY THIS EXISTS. `tools/probe_session_knobs.ts` proved the provider ACCEPTS
// `language:'ar'` for gpt-4o-mini-transcribe. Acceptance is not quality. The
// open question this probe answers is the one that actually decides the
// default: production speech is Egyptian Arabic with English hatchery terms
// mixed in, and a hard Arabic hint could plausibly wreck a pure-English
// caller. That risk was otherwise only checkable on a real device call.
//
// METHOD. Caller audio is SYNTHESIZED with the OpenAI speech endpoint as raw
// pcm16 / 24 kHz mono — exactly the format the Realtime input buffer expects —
// then pushed through `input_audio_buffer.append` + `.commit` on a real
// Realtime session, with `turn_detection: null` so nothing auto-responds and
// the ONLY thing measured is the transcription path. Each utterance is run
// through every config variant so the transcripts are directly comparable.
//
// LIMITS, stated honestly: TTS speech is cleaner than a real caller on a
// phone in a hatchery — no background noise, no room, a synthetic accent.
// This probe is therefore good evidence about LANGUAGE BIAS (does an Arabic
// hint mangle English?) and weak evidence about robustness to real-world
// audio. It narrows the real-device checklist; it does not replace it.
//
// It never prints the API key.
//
// RECORDED RESULT — run 2026-08-19. Copied from the probe's own output:
//
//   arabic-report-request  "إيه آخر تقرير بريك أوت موجود عندك؟"
//     OLD prod (english prompt, no language)  أي آخر تقرير بريك آوت موجود عندك؟
//     bilingual prompt only                   إيه آخر تقرير breakout موجود عندك؟
//     NEW default (bilingual + language:ar)   إيه آخر تقرير breakout موجود عندك؟
//
//   mixed-arabic-english  "عايز أعرف الـ hatchability بتاعة قطيع روس ..."
//     OLD prod   عايز أعرف الهاتشابيلتي بتاعت قطيع روس في الأسبوع 35.
//     bilingual  عايز أعرف الhatchability بتاعة قطيع روس في الأسبوع 35.
//     NEW        عايز أعرف الhatchability بتاعت قطيع روس في الأسبوع 35.
//
//   english-only  "What is the fertility benchmark for Ross at week forty?"
//     ALL THREE VARIANTS IDENTICAL:
//     What is the fertility benchmark for Ross at week 40?
//
// THREE CONCLUSIONS.
//
//   1. The feared regression does NOT occur. `language:'ar'` left a
//      pure-English utterance transcribed perfectly, byte-identical to the
//      no-hint variants. Arabic-first does not cost English callers.
//   2. The BILINGUAL PROMPT is the change carrying the real win, and it is
//      bigger than "nicer text": the old all-English prompt transliterated
//      the English technical term into Arabic script ("الهاتشابيلتي"), and a
//      transliterated term is exactly what silently poisons a tool argument.
//      The bilingual prompt keeps `hatchability` and `breakout` in Latin
//      script.
//   3. What this probe did NOT reproduce: the "Hello, world." / "In Tamil"
//      hallucinations. Clean synthesized speech never triggers them — that
//      failure mode belongs to short, noisy, low-energy real segments. So
//      `language:'ar'` remains a REASONED mitigation for those, now shown to
//      be free of downside, rather than a demonstrated cure. Confirming the
//      cure still needs a real-device call.

import { WebSocket as NodeWebSocket } from 'ws'
import { TRANSCRIPTION_PROMPT } from '../src/session_config.ts'

const MODEL = 'gpt-realtime-2.1-mini'
const TRANSCRIPTION_MODEL = 'gpt-4o-mini-transcribe'
const URL = `wss://api.openai.com/v1/realtime?model=${MODEL}`
const SPEECH_URL = 'https://api.openai.com/v1/audio/speech'
const TIMEOUT_MS = 45_000

// The prompt production used BEFORE this change: all-English hatchery
// vocabulary. Kept here so the probe can show what it was actually costing.
const ENGLISH_ONLY_PROMPT = [
  'ChickMark hatchery operations.',
  'Terms: hatchery, setter, hatcher, incubation, candling, transfer, pull,',
  'flock, breed, Ross, Cobb, Hubbard, Arbor Acres, Indian River,',
  'egg storage, CVT, Govee, BMK, Pasgar, hatchability, fertility,',
  'early dead, mid dead, late dead, contaminated, cull, chick quality.',
].join(' ')

interface Utterance {
  readonly id: string
  readonly text: string
  /** Substrings a good transcript should contain (case-insensitive). */
  readonly expect: readonly string[]
}

const UTTERANCES: readonly Utterance[] = [
  {
    id: 'arabic-report-request',
    // The exact shape of the production failure.
    text: 'إيه آخر تقرير بريك أوت موجود عندك؟',
    expect: ['تقرير'],
  },
  {
    id: 'arabic-benchmark-request',
    text: 'الخصوبة المفروض تكون كام في الأسبوع أربعين؟',
    expect: ['الخصوبة', 'أربعين'],
  },
  {
    id: 'mixed-arabic-english',
    text: 'عايز أعرف الـ hatchability بتاعة قطيع روس في الأسبوع خمسة وثلاثين',
    expect: ['hatchability'],
  },
  {
    id: 'english-only',
    // The regression risk: does an Arabic hint mangle a pure-English caller?
    text: 'What is the fertility benchmark for Ross at week forty?',
    expect: ['fertility', 'Ross'],
  },
]

interface Variant {
  readonly id: string
  readonly prompt: string
  readonly language: string | null
}

const VARIANTS: readonly Variant[] = [
  { id: 'OLD prod (english prompt, no language)', prompt: ENGLISH_ONLY_PROMPT, language: null },
  { id: 'bilingual prompt only', prompt: TRANSCRIPTION_PROMPT, language: null },
  { id: 'NEW default (bilingual + language:ar)', prompt: TRANSCRIPTION_PROMPT, language: 'ar' },
]

/** Synthesize one utterance as raw pcm16 24 kHz mono. */
async function synthesize(apiKey: string, text: string): Promise<Uint8Array> {
  const response = await fetch(SPEECH_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini-tts',
      voice: 'alloy',
      input: text,
      response_format: 'pcm',
    }),
  })
  if (!response.ok) {
    throw new Error(`speech synthesis failed: ${response.status}`)
  }
  return new Uint8Array(await response.arrayBuffer())
}

function toBase64(bytes: Uint8Array): string {
  let binary = ''
  const CHUNK = 0x8000
  for (let index = 0; index < bytes.length; index += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(index, index + CHUNK))
  }
  return btoa(binary)
}

function sessionFor(variant: Variant): Record<string, unknown> {
  const transcription: Record<string, unknown> = {
    model: TRANSCRIPTION_MODEL,
    prompt: variant.prompt,
  }
  if (variant.language !== null) transcription.language = variant.language
  return {
    type: 'realtime',
    output_modalities: ['audio'],
    audio: {
      input: {
        noise_reduction: { type: 'near_field' },
        transcription,
        // No auto turn detection: this probe measures ONLY the transcription
        // path, and nothing should generate a reply.
        turn_detection: null,
      },
      output: { voice: 'cedar' },
    },
    tool_choice: 'none',
    tools: [],
  }
}

/** Push one pcm16 buffer through a session and return the transcript. */
function transcribe(
  apiKey: string,
  variant: Variant,
  audio: Uint8Array,
): Promise<string> {
  return new Promise((resolve) => {
    const socket = new NodeWebSocket(URL, {
      headers: { Authorization: `Bearer ${apiKey}` },
    })
    let settled = false
    const finish = (value: string) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      try {
        socket.close()
      } catch {
        // ignore
      }
      resolve(value)
    }
    const timer = setTimeout(() => finish('<TIMEOUT>'), TIMEOUT_MS)

    socket.on('open', () => {
      socket.send(JSON.stringify({
        type: 'session.update',
        session: sessionFor(variant),
      }))
    })

    socket.on('message', (data: unknown) => {
      let text: string
      if (typeof data === 'string') text = data
      else if (data instanceof Uint8Array) text = new TextDecoder().decode(data)
      else return
      let event: Record<string, unknown>
      try {
        event = JSON.parse(text)
      } catch {
        return
      }
      switch (event.type) {
        case 'session.updated': {
          // Append in ~32 KB slices, then commit.
          const base64 = toBase64(audio)
          const CHUNK = 32_000
          for (let index = 0; index < base64.length; index += CHUNK) {
            socket.send(JSON.stringify({
              type: 'input_audio_buffer.append',
              audio: base64.slice(index, index + CHUNK),
            }))
          }
          socket.send(JSON.stringify({ type: 'input_audio_buffer.commit' }))
          return
        }
        case 'conversation.item.input_audio_transcription.completed':
          finish(String(event.transcript ?? '').trim())
          return
        case 'conversation.item.input_audio_transcription.failed':
          finish('<TRANSCRIPTION_FAILED>')
          return
        case 'error': {
          const err = (event.error ?? {}) as Record<string, unknown>
          finish(`<ERROR ${String(err.code ?? '')}: ${String(err.message ?? '').slice(0, 120)}>`)
          return
        }
      }
    })

    socket.on('error', () => finish('<CONNECT_ERROR>'))
    socket.on('close', () => finish('<CLOSED_EARLY>'))
  })
}

function hits(transcript: string, expect: readonly string[]): string {
  const lower = transcript.toLowerCase()
  const found = expect.filter((term) => lower.includes(term.toLowerCase()))
  return `${found.length}/${expect.length}`
}

async function main() {
  const apiKey = Deno.env.get('OPENAI_API_KEY')
  if (!apiKey) {
    console.error('OPENAI_API_KEY is not set')
    Deno.exit(1)
  }

  for (const utterance of UTTERANCES) {
    console.log(`\n=== ${utterance.id}`)
    console.log(`  said: ${utterance.text}`)
    let audio: Uint8Array
    try {
      audio = await synthesize(apiKey, utterance.text)
    } catch (error) {
      console.log(`  synthesis failed: ${String(error)}`)
      continue
    }
    console.log(`  (${audio.length} bytes pcm16 24kHz)`)
    for (const variant of VARIANTS) {
      const transcript = await transcribe(apiKey, variant, audio)
      console.log(
        `  [${hits(transcript, utterance.expect)}] ${variant.id.padEnd(38)} ${transcript}`,
      )
      await new Promise((resolve) => setTimeout(resolve, 2500))
    }
  }
}

await main()
