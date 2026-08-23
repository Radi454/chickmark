// Standalone probe: which `audio.input.transcription` fields does
// `gpt-4o-mini-transcribe` actually accept in the Realtime `session.update`,
// and is `max_output_tokens` accepted at session level?
//
// NOT part of the runtime service. Run manually:
//   OPENAI_API_KEY="$(gcloud secrets versions access latest \
//     --secret=openai-api-key --project=chickmark-ai-agent)" \
//     deno run --allow-net --allow-env tools/probe_session_knobs.ts
//
// WHY THIS EXISTS. `src/session_config.ts` records that `languages` (plural)
// and `delay` are rejected for every model except `gpt-live-transcribe`, but
// nothing in this repo established whether the SINGULAR `language` field is
// accepted for `gpt-4o-mini-transcribe`. A wrong guess there is not a
// degraded transcript — the provider rejects the ENTIRE `session.update`, so
// the session runs with no tools and no instructions while sounding healthy.
// Each case below is probed on its own socket so one rejection cannot mask
// another.
//
// It prints only provider-generated diagnostic fields (code/param/message)
// and NEVER the API key.
//
// RECORDED RESULT — run 2026-08-19 against gpt-realtime-2.1-mini /
// gpt-4o-mini-transcribe. Every line below is copied from the probe's own
// output, not inferred:
//
//   baseline (model+prompt)            ACCEPTED  echoed language:null,
//                                                max_output_tokens:"inf"
//   languages:['ar','en']              REJECTED  invalid_parameter,
//                                                param=session.audio.input.
//                                                transcription.languages,
//                                                "The 'languages' parameter is
//                                                not supported for this model."
//   language:'ar'                      ACCEPTED  echoed language:"ar"
//   language:'ar' + bilingual prompt   ACCEPTED  echoed language:"ar"
//   bilingual prompt only              ACCEPTED  echoed language:null
//   max_output_tokens:200              ACCEPTED  echoed max_output_tokens:200
//
// Two conclusions this repo did not previously have:
//
//   1. The SINGULAR `language` IS supported for gpt-4o-mini-transcribe even
//      though the PLURAL `languages` is not. The rejection recorded in
//      `src/session_config.ts` is specific to `languages`/`delay` and must not
//      be read as covering `language`.
//   2. Session `max_output_tokens` defaults to "inf" — the production session
//      has never had ANY output ceiling.

import { WebSocket as NodeWebSocket } from 'ws'

const MODEL = 'gpt-realtime-2.1-mini'
const TRANSCRIPTION_MODEL = 'gpt-4o-mini-transcribe'
const URL = `wss://api.openai.com/v1/realtime?model=${MODEL}`
const TIMEOUT_MS = 15_000

const ENGLISH_PROMPT = [
  'ChickMark hatchery operations.',
  'Terms: hatchery, setter, hatcher, incubation, candling, transfer, pull,',
  'flock, breed, Ross, Cobb, Hubbard, Arbor Acres, Indian River,',
  'egg storage, CVT, Govee, BMK, Pasgar, hatchability, fertility,',
  'early dead, mid dead, late dead, contaminated, cull, chick quality.',
].join(' ')

const BILINGUAL_PROMPT = [
  'محادثة بالعامية المصرية عن تشغيل المفرخات، وقد تتخلط بكلمات إنجليزية.',
  'مصطلحات: مفرخ، ماكينة تحضين، قطيع، سلالة، خصوبة، فقس، تقرير، تفقيس.',
  'ChickMark hatchery operations. Egyptian Arabic with English terms mixed in.',
  'Terms: hatchery, setter, hatcher, incubation, candling, transfer, pull,',
  'flock, breed, Ross, Cobb, Hubbard, Arbor Acres, Indian River,',
  'egg storage, CVT, Govee, BMK, Pasgar, hatchability, fertility,',
  'early dead, mid dead, late dead, contaminated, cull, chick quality.',
].join(' ')

interface Case {
  readonly label: string
  readonly session: Record<string, unknown>
  /** What we expect, so a surprise is visible in the summary. */
  readonly expect: 'accepted' | 'rejected'
}

function withTranscription(
  transcription: Record<string, unknown>,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    type: 'realtime',
    output_modalities: ['audio'],
    audio: {
      input: {
        noise_reduction: { type: 'near_field' },
        transcription,
        turn_detection: {
          type: 'semantic_vad',
          eagerness: 'low',
          create_response: true,
          interrupt_response: true,
        },
      },
      output: { voice: 'cedar' },
    },
    reasoning: { effort: 'low' },
    tool_choice: 'auto',
    tools: [],
    ...extra,
  }
}

const CASES: readonly Case[] = [
  {
    label: 'baseline (model+prompt, today\'s production shape)',
    session: withTranscription({
      model: TRANSCRIPTION_MODEL,
      prompt: ENGLISH_PROMPT,
    }),
    expect: 'accepted',
  },
  {
    label: 'CONTROL languages:[ar,en] (repo records this as rejected)',
    session: withTranscription({
      model: TRANSCRIPTION_MODEL,
      prompt: ENGLISH_PROMPT,
      languages: ['ar', 'en'],
    }),
    expect: 'rejected',
  },
  {
    label: 'language:"ar" (THE OPEN QUESTION)',
    session: withTranscription({
      model: TRANSCRIPTION_MODEL,
      prompt: ENGLISH_PROMPT,
      language: 'ar',
    }),
    expect: 'accepted',
  },
  {
    label: 'language:"ar" + bilingual prompt (the candidate fix)',
    session: withTranscription({
      model: TRANSCRIPTION_MODEL,
      prompt: BILINGUAL_PROMPT,
      language: 'ar',
    }),
    expect: 'accepted',
  },
  {
    label: 'bilingual prompt only, no language hint (the safe fallback)',
    session: withTranscription({
      model: TRANSCRIPTION_MODEL,
      prompt: BILINGUAL_PROMPT,
    }),
    expect: 'accepted',
  },
  {
    label: 'max_output_tokens:200 at session level',
    session: withTranscription(
      { model: TRANSCRIPTION_MODEL, prompt: ENGLISH_PROMPT },
      { max_output_tokens: 200 },
    ),
    expect: 'accepted',
  },
]

interface ProbeResult {
  outcome: 'accepted' | 'rejected' | 'timeout' | 'connect_error'
  detail?: Record<string, unknown>
  /** What the provider says the transcription block ended up as. */
  echoed?: unknown
}

function probe(testCase: Case): Promise<ProbeResult> {
  return new Promise((resolve) => {
    const apiKey = Deno.env.get('OPENAI_API_KEY')
    if (!apiKey) {
      console.error('OPENAI_API_KEY is not set')
      resolve({ outcome: 'connect_error' })
      return
    }
    const socket = new NodeWebSocket(URL, {
      headers: { Authorization: `Bearer ${apiKey}` },
    })
    let settled = false
    const finish = (result: ProbeResult) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      try {
        socket.close()
      } catch {
        // ignore
      }
      resolve(result)
    }

    const timer = setTimeout(() => finish({ outcome: 'timeout' }), TIMEOUT_MS)

    socket.on('open', () => {
      socket.send(
        JSON.stringify({ type: 'session.update', session: testCase.session }),
      )
    })

    socket.on('message', (data: unknown) => {
      let text: string
      if (typeof data === 'string') text = data
      else if (data instanceof Uint8Array) text = new TextDecoder().decode(data)
      else return
      let parsed: Record<string, unknown>
      try {
        parsed = JSON.parse(text)
      } catch {
        return
      }
      if (parsed.type === 'session.updated') {
        const session = (parsed.session ?? {}) as Record<string, unknown>
        const audio = (session.audio ?? {}) as Record<string, unknown>
        const input = (audio.input ?? {}) as Record<string, unknown>
        finish({
          outcome: 'accepted',
          echoed: {
            transcription: input.transcription,
            max_output_tokens: session.max_output_tokens,
          },
        })
      } else if (parsed.type === 'error') {
        finish({
          outcome: 'rejected',
          detail: (parsed.error ?? {}) as Record<string, unknown>,
        })
      }
    })

    socket.on(
      'unexpected-response',
      (_req: unknown, res: { statusCode?: number }) => {
        console.log(`  http status=${res.statusCode}`)
        finish({ outcome: 'connect_error' })
      },
    )
    socket.on('error', (error: unknown) => {
      console.log(
        `  connect error: ${
          error instanceof Error ? error.message : String(error)
        }`,
      )
      finish({ outcome: 'connect_error' })
    })
    socket.on('close', () => finish({ outcome: 'connect_error' }))
  })
}

async function main() {
  const summary: string[] = []
  for (const testCase of CASES) {
    console.log(`\n=== ${testCase.label}`)
    const result = await probe(testCase)
    if (result.outcome === 'accepted') {
      console.log(`  ACCEPTED. echoed: ${JSON.stringify(result.echoed)}`)
    } else if (result.outcome === 'rejected') {
      const err = result.detail ?? {}
      console.log(
        `  REJECTED code=${JSON.stringify(err.code)} param=${
          JSON.stringify(err.param)
        } message=${JSON.stringify(String(err.message ?? '').slice(0, 240))}`,
      )
    } else {
      console.log(`  ${result.outcome.toUpperCase()}`)
    }
    const surprise = result.outcome !== testCase.expect ? '  <-- SURPRISE' : ''
    summary.push(
      `${result.outcome.padEnd(14)} (expected ${testCase.expect.padEnd(8)}) ${testCase.label}${surprise}`,
    )
    // Back-to-back fresh sessions on this account get throttled; space them.
    await new Promise((resolve) => setTimeout(resolve, 2000))
  }
  console.log('\n=== SUMMARY')
  for (const line of summary) console.log(line)
}

await main()
