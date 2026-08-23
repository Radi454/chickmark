// Standalone probe: how many OUTPUT tokens does a spoken Pip reply actually
// cost, for each answer size the voice policy allows?
//
// NOT part of the runtime service. Run manually:
//   OPENAI_API_KEY="$(gcloud secrets versions access latest \
//     --secret=openai-api-key --project=chickmark-ai-agent)" \
//     deno run --allow-net --allow-env --allow-read tools/probe_output_tokens.ts
//
// WHY THIS EXISTS. `max_output_tokens` is the ceiling on a spoken reply, and
// picking it by intuition is how you either fail to stop a monologue or
// truncate a legitimate answer mid-word. The only number that means anything
// is `response.usage.output_tokens` the provider reports for the EXACT
// production session payload — so this drives real turns through the same
// `buildSessionUpdate` the sideband uses, in audio modality, and prints what
// each answer size actually cost.
//
// The cases are chosen to bracket the decision:
//   * `greeting` and `single-metric` are the common short replies — the
//     ceiling must sit far above these or normal conversation gets cut off.
//   * `explicit-full-summary` is the LONGEST LEGITIMATE reply the policy
//     permits (the user explicitly asked for a summary). The ceiling must
//     clear this with real headroom.
//   * `eleven-metric-dump` reproduces the 2026-08-19 incident shape: the flat
//     11-metric breakout payload read aloud in full, the ~25-second monologue
//     the ceiling exists to stop.
//
// It never prints the API key.
//
// RECORDED RESULT — run 2026-08-19, gpt-realtime-2.1-mini, production
// session payload, reasoning effort low. Copied from the probe's own output:
//
//     66 tokens     2 words  greeting                ("صباح النور.")
//     60 tokens     4 words  single-metric           ("الإنتاج 80 في المية.")
//    145 tokens     8 words  two-metric
//    488 tokens    35 words  explicit-full-summary   <- longest LEGITIMATE
//    761 tokens    67 words  eleven-metric-dump      <- the incident shape
//
// HOW THE CEILING WAS CHOSEN. The longest reply the voice policy actually
// permits — a summary the user explicitly asked for — costs 488 output
// tokens. A ceiling has to clear that with enough headroom that run-to-run
// variance can never truncate a legitimate answer mid-word, because
// `max_output_tokens` truncation is not graceful: the response simply stops
// and comes back `incomplete`.
//
// The ceiling is therefore NOT sized to cut the 761-token dump. That dump is
// cured at its source — by report-vs-benchmark routing and by the shaped
// `requested`/`context` payload, which stop 11 metrics from ever reaching the
// model as an answer in the first place. The ceiling is a BACKSTOP against an
// unbounded monologue from some payload nobody has thought of yet, and a
// backstop that truncates real answers is worse than no backstop.

import { buildSessionUpdate } from '../src/session_config.ts'
import { testConfig } from '../src/config.ts'
import { renderRealtimeToolDefinitions } from './render_tool_definitions.ts'
import { renderRealtimeInstructions } from './render_agent_instructions.ts'
import { WebSocket as NodeWebSocket } from 'ws'

const MODEL = 'gpt-realtime-2.1-mini'
const URL = `wss://api.openai.com/v1/realtime?model=${MODEL}`
const EVENT_TIMEOUT_MS = 90_000
// The account's observed cap is 40k TPM at ~5k input tokens per inference;
// an unpaced run gets rate-limited responses that look like provider bugs.
const PACE_MS = 12_000

const FULL_BREAKOUT_ROW = {
  ok: true,
  code: 'ok',
  data: {
    ageWeek: 40,
    infertilePct: 6.2,
    early24hPct: 1.4,
    early48hPct: 1.1,
    bloodRingPct: 0.8,
    blackEyePct: 0.6,
    earlyDeadPct: 2.3,
    midDeadPct: 1.2,
    lateDeadPct: 3.1,
    externalPipPct: 1.7,
    crackedPct: 0.9,
    contamPct: 0.5,
  },
}

const FULL_BENCHMARK_ROW = {
  ok: true,
  code: 'ok',
  data: {
    breed: 'Hubbard',
    ageWeek: 40,
    hatchabilityPct: 90.2,
    fertilityPct: 96.5,
    hofPct: 93.47,
    productionPct: 80,
    eggWeightG: 65.3,
    chickWeightG: 46,
  },
}

interface Case {
  readonly id: string
  readonly userText: string
  readonly stub?: { readonly name: string; readonly output: unknown }
  /** What this case is evidence FOR, printed with the result. */
  readonly meaning: string
}

const CASES: readonly Case[] = [
  {
    id: 'greeting',
    userText: 'صباح الفل',
    meaning: 'shortest normal reply — ceiling must be far above this',
  },
  {
    id: 'single-metric',
    userText: 'إنتاج Hubbard في الأسبوع 40 كام؟',
    stub: { name: 'get_breed_benchmark', output: FULL_BENCHMARK_ROW },
    meaning: 'the common short data answer',
  },
  {
    id: 'two-metric',
    userText: 'قولي الخصوبة ونسبة الفقس لهبرد في الأسبوع 40',
    stub: { name: 'get_breed_benchmark', output: FULL_BENCHMARK_ROW },
    meaning: 'two requested values',
  },
  {
    id: 'explicit-full-summary',
    userText: 'إديني ملخص أداء Hubbard كامل في الأسبوع 40',
    stub: { name: 'get_breed_benchmark', output: FULL_BENCHMARK_ROW },
    meaning: 'LONGEST LEGITIMATE reply — ceiling must clear this with headroom',
  },
  {
    id: 'eleven-metric-dump',
    userText: 'إديني كل أرقام الـ breakout كاملة للأسبوع 40 واحدة واحدة بالتفصيل',
    stub: { name: 'get_egg_breakout_benchmark', output: FULL_BREAKOUT_ROW },
    meaning: 'reproduces the 2026-08-19 ~25s monologue the ceiling must stop',
  },
]

interface Turn {
  readonly transcript: string
  readonly outputTokens: number
  readonly outputAudioTokens: number
  readonly outputTextTokens: number
  readonly rounds: number
}

function connect(apiKey: string): Promise<InstanceType<typeof NodeWebSocket>> {
  return new Promise((resolve, reject) => {
    const socket = new NodeWebSocket(URL, {
      headers: { Authorization: `Bearer ${apiKey}` },
    })
    socket.on('open', () => resolve(socket))
    socket.on('error', reject)
  })
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object'
    ? value as Record<string, unknown>
    : {}
}

/** Collect one response.done, replying to any tool call with the stub. */
function runCase(
  socket: InstanceType<typeof NodeWebSocket>,
  testCase: Case,
): Promise<Turn> {
  return new Promise((resolve, reject) => {
    let rounds = 0
    let transcript = ''
    const timer = setTimeout(
      () => reject(new Error(`timeout on ${testCase.id}`)),
      EVENT_TIMEOUT_MS,
    )

    const onMessage = (data: unknown) => {
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
      if (event.type === 'error') {
        clearTimeout(timer)
        reject(new Error(JSON.stringify(asRecord(event.error).message)))
        return
      }
      if (event.type !== 'response.done') return

      rounds += 1
      const response = asRecord(event.response)
      const output = Array.isArray(response.output) ? response.output : []

      // Accumulate whatever the model SPOKE this round.
      for (const raw of output) {
        const item = asRecord(raw)
        if (item.type !== 'message') continue
        for (const rawContent of (Array.isArray(item.content) ? item.content : [])) {
          const content = asRecord(rawContent)
          const spoken = content.transcript ?? content.text
          if (typeof spoken === 'string') transcript += spoken
        }
      }

      const call = output
        .map(asRecord)
        .find((item) => item.type === 'function_call')

      if (call && testCase.stub && rounds < 4) {
        socket.send(JSON.stringify({
          type: 'conversation.item.create',
          item: {
            type: 'function_call_output',
            call_id: String(call.call_id ?? ''),
            output: JSON.stringify(testCase.stub.output),
          },
        }))
        socket.send(JSON.stringify({ type: 'response.create' }))
        return
      }

      clearTimeout(timer)
      socket.off('message', onMessage)
      const usage = asRecord(response.usage)
      const details = asRecord(usage.output_token_details)
      resolve({
        transcript: transcript.trim(),
        outputTokens: Number(usage.output_tokens ?? 0),
        outputAudioTokens: Number(details.audio_tokens ?? 0),
        outputTextTokens: Number(details.text_tokens ?? 0),
        rounds,
      })
    }

    socket.on('message', onMessage)
    socket.send(JSON.stringify({
      type: 'conversation.item.create',
      item: {
        type: 'message',
        role: 'user',
        content: [{ type: 'input_text', text: testCase.userText }],
      },
    }))
    socket.send(JSON.stringify({ type: 'response.create' }))
  })
}

async function main() {
  const apiKey = Deno.env.get('OPENAI_API_KEY')
  if (!apiKey) {
    console.error('OPENAI_API_KEY is not set')
    Deno.exit(1)
  }
  const tools = renderRealtimeToolDefinitions()
  const instructions = renderRealtimeInstructions()

  const rows: string[] = []
  for (const testCase of CASES) {
    const socket = await connect(apiKey)
    socket.send(JSON.stringify(
      buildSessionUpdate({ config: testConfig(), tools, instructions }),
    ))
    // Let session.updated land before driving a turn.
    await new Promise((resolve) => setTimeout(resolve, 1500))
    try {
      const turn = await runCase(socket, testCase)
      const words = turn.transcript.split(/\s+/).filter(Boolean).length
      console.log(`\n=== ${testCase.id} — ${testCase.meaning}`)
      console.log(`  spoke (${words} words): ${turn.transcript.slice(0, 300)}`)
      console.log(
        `  output_tokens=${turn.outputTokens} ` +
          `(audio=${turn.outputAudioTokens} text=${turn.outputTextTokens}) ` +
          `rounds=${turn.rounds}`,
      )
      rows.push(
        `${String(turn.outputTokens).padStart(6)} tokens  ` +
          `${String(words).padStart(4)} words  ${testCase.id}`,
      )
    } catch (error) {
      console.log(`\n=== ${testCase.id}: FAILED ${String(error)}`)
      rows.push(`  FAILED  ${testCase.id}`)
    }
    try {
      socket.close()
    } catch {
      // ignore
    }
    await new Promise((resolve) => setTimeout(resolve, PACE_MS))
  }

  console.log('\n=== SUMMARY (output tokens per answer size)')
  for (const row of rows) console.log(row)
}

await main()
