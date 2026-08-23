// Repeatable token-cost probe for the Pip Realtime production path.
//
// WHY THIS EXISTS
//
// Source-file size is not what the provider bills. The only number that means
// anything is `response.usage.input_tokens` reported back by the live endpoint
// for the EXACT payload a production session sends. This probe therefore
// builds the session with the same `buildSessionUpdate` the Cloud Run sideband
// uses, drives real turns, and prints what the provider actually charged.
//
// It is a deploy/diagnostic tool: it is never imported by `main.ts` and is not
// copied into the image (the Dockerfile takes only `main.ts` and `src/`).
//
//   export OPENAI_API_KEY="$(gcloud secrets versions access latest \
//     --secret=openai-api-key --project=chickmark-ai-agent)"
//
//   # what the repo would deploy today
//   deno run --allow-net --allow-env --allow-read tools/probe_token_cost.ts
//
//   # what a given Cloud Run revision is actually running, for a true
//   # before/after against production:
//   gcloud run revisions describe pip-realtime-sideband-00013-gpq \
//     --region=europe-west1 --format=json > /tmp/rev.json
//   # (extract the two env vars to files, then:)
//   deno run --allow-net --allow-env --allow-read tools/probe_token_cost.ts \
//     --instructions=/tmp/instructions.txt --tools=/tmp/tools.json
//
// Flags:
//   --instructions=<file>  override the instruction text (default: rendered)
//   --tools=<file>         override the tool catalogue JSON (default: rendered)
//   --catalogue=core|full  which catalogue to send (default: full)
//   --scenario=<id>        run one scenario instead of all
//   --pace=<ms>            delay between inferences (default 12000)
//
// ON PACING: the account's observed limit for gpt-realtime-2.1-mini is 40k
// TPM. At ~5k input tokens per inference that is ~8 inferences/minute, so an
// unpaced run gets `rate_limit_exceeded` responses that arrive as an empty
// `response.done` with zero usage — which looks exactly like a provider bug
// and is not one. The default pace keeps a full run under the cap.

import { buildSessionUpdate, type RealtimeToolDefinition } from '../src/session_config.ts'
import { testConfig } from '../src/config.ts'
import { renderRealtimeToolDefinitions } from './render_tool_definitions.ts'
import { renderRealtimeInstructions } from './render_agent_instructions.ts'
import { WebSocket as NodeWebSocket } from 'ws'

const MODEL = 'gpt-realtime-2.1-mini'
const REALTIME_URL = `wss://api.openai.com/v1/realtime?model=${MODEL}`
const EVENT_TIMEOUT_MS = 90_000

type Ev = Record<string, unknown>

function flag(name: string, fallback: string | null = null): string | null {
  const hit = Deno.args.find((arg) => arg.startsWith(`--${name}=`))
  return hit ? hit.slice(name.length + 3) : fallback
}

/**
 * The staged split lives beside `buildSessionUpdate` in `src/session_config.ts`.
 * It is read through a dynamic import so this probe still runs against a
 * checkout (or a rendered catalogue file) that predates staging.
 */
async function coreNames(): Promise<ReadonlySet<string> | null> {
  try {
    const mod = await import('../src/session_config.ts') as Record<string, unknown>
    const staged = mod['INTAKE_STAGED_TOOL_NAMES']
    if (Array.isArray(staged)) return new Set(staged.map(String))
  } catch {
    // no staging in this checkout
  }
  return null
}

async function loadTools(): Promise<readonly RealtimeToolDefinition[]> {
  const file = flag('tools')
  const all = file
    ? JSON.parse(await Deno.readTextFile(file)) as RealtimeToolDefinition[]
    : renderRealtimeToolDefinitions()
  if (flag('catalogue', 'full') !== 'core') return all
  const staged = await coreNames()
  if (!staged) {
    console.error('# --catalogue=core requested but no staged list found; using full')
    return all
  }
  return all.filter((tool) => !staged.has(tool.name))
}

async function loadInstructions(): Promise<string> {
  const file = flag('instructions')
  return file ? await Deno.readTextFile(file) : renderRealtimeInstructions()
}

class Probe {
  #queue: Ev[] = []
  #waiters: ((event: Ev) => void)[] = []

  private constructor(private readonly ws: NodeWebSocket) {
    ws.on('message', (data: Buffer | string) => {
      try {
        this.#push(JSON.parse(data.toString()))
      } catch {
        // non-JSON frame
      }
    })
    ws.on('close', (code: number) => this.#push({ type: '_closed', code }))
    ws.on(
      'error',
      (error: Error) => this.#push({ type: '_error', message: error.message }),
    )
  }

  static async connect(apiKey: string): Promise<Probe> {
    const ws = new NodeWebSocket(REALTIME_URL, {
      headers: { Authorization: `Bearer ${apiKey}` },
    })
    const probe = new Probe(ws)
    await new Promise<void>((resolve, reject) => {
      ws.once('open', () => resolve())
      ws.once('error', (error: Error) => reject(error))
    })
    return probe
  }

  #push(event: Ev): void {
    const waiter = this.#waiters.shift()
    if (waiter) waiter(event)
    else this.#queue.push(event)
  }

  next(): Promise<Ev> {
    const queued = this.#queue.shift()
    if (queued) return Promise.resolve(queued)
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error('probe timed out')),
        EVENT_TIMEOUT_MS,
      )
      this.#waiters.push((event) => {
        clearTimeout(timer)
        resolve(event)
      })
    })
  }

  async until(predicate: (event: Ev) => boolean): Promise<Ev> {
    for (;;) {
      const event = await this.next()
      if (event.type === '_error') throw new Error(`transport: ${event.message}`)
      if (event.type === '_closed') throw new Error(`socket closed (${event.code})`)
      if (event.type === 'error') throw new Error(`provider: ${JSON.stringify(event)}`)
      if (predicate(event)) return event
    }
  }

  send(payload: unknown): void {
    this.ws.send(JSON.stringify(payload))
  }

  close(): void {
    try {
      this.ws.close(1000, 'probe done')
    } catch {
      // already closed
    }
  }
}

interface Row {
  readonly scenario: string
  readonly step: string
  readonly input: number
  readonly cached: number
  readonly uncached: number
  readonly output: number
}

function usageRow(scenario: string, step: string, done: Ev): Row {
  const response = (done.response ?? {}) as Ev
  const usage = (response.usage ?? {}) as Ev
  const details = (usage.input_token_details ?? {}) as Ev
  const input = Number(usage.input_tokens ?? 0)
  const cached = Number(details.cached_tokens ?? 0)
  if (response.status !== 'completed') {
    const reason = JSON.stringify(response.status_details ?? response.status).slice(
      0,
      200,
    )
    console.error(`   !! ${step}: status=${response.status} ${reason}`)
  }
  return {
    scenario,
    step,
    input,
    cached,
    uncached: Math.max(0, input - cached),
    output: Number(usage.output_tokens ?? 0),
  }
}

// Realistic stand-ins for what the broker returns.
//
// `load_station_schema` matters more than the rest put together: its result
// stays in the model's context for the whole session, so it is what makes a
// later turn expensive. The RAW registry entry is the wrong thing to answer
// with — the broker never sends it, because `loadSchemaResult` strips
// `persistence`/`read`/`warnings` and reshapes the rest. Answering with the raw
// entry inflates every downstream row and, worse, inflates BOTH sides of a
// before/after equally, hiding the very change being measured.
//
// So the projected payload is supplied from outside via `--schema-result`,
// which is how a before/after on the projection itself is measured. Without
// the flag the probe falls back to the raw entry and says so, rather than
// silently reporting a number that overstates production.
const registry = JSON.parse(
  await Deno.readTextFile(
    new URL('../../../tool/agent_schema/station_registry.json', import.meta.url),
  ),
) as { stations: Record<string, unknown>[] }

const schemaResultOverride = flag('schema-result')
const schemaResult = schemaResultOverride
  ? JSON.parse(await Deno.readTextFile(schemaResultOverride))
  : null
if (!schemaResult) {
  console.error(
    '# NOTE: no --schema-result given; load_station_schema is answered with the RAW',
  )
  console.error(
    '#       registry entry, which is LARGER than what the broker actually returns.',
  )
}

function stubFor(name: string): unknown {
  switch (name) {
    case 'get_user_scope':
      return {
        ok: true,
        code: 'ok',
        data: { accessRole: 'auditor', allowedCustomerCount: 3 },
      }
    case 'list_customers':
      return {
        ok: true,
        code: 'ok',
        data: { customers: [{ id: 'c1', name: 'Rs-NileV' }] },
      }
    case 'resolve_customer_flock':
      return {
        ok: true,
        code: 'ok',
        data: { customerId: 'c1', flockId: 'f1', breed: 'Ross308', ageWeek: 40 },
      }
    case 'get_breed_benchmark':
      return {
        ok: true,
        code: 'ok',
        data: {
          breed: 'Hubbard',
          ageWeek: 40,
          hatchabilityPct: 90.2,
          fertilityPct: 96.5,
        },
      }
    case 'propose_intake':
      return { ok: true, code: 'ok', data: { pendingActionId: 'pa_1', customerId: 'c1' } }
    case 'load_station_schema': {
      if (schemaResult) return { ok: true, code: 'ok', data: schemaResult }
      const station = registry.stations.find((s) =>
        s.schemaKey === 'hatch_analysis.residue_breakout'
      )
      return { ok: true, code: 'ok', data: station }
    }
    default:
      return { ok: true, code: 'ok', data: {} }
  }
}

interface Scenario {
  readonly id: string
  readonly turns: readonly string[]
}

const SCENARIOS: readonly Scenario[] = [
  { id: 'fresh-hi', turns: ['Hi'] },
  {
    id: 'normal-lookup',
    turns: ['What is the hatchability benchmark for Hubbard at week 40?'],
  },
  {
    id: 'one-station-schema',
    turns: [
      'Call load_station_schema with schemaKey hatch_analysis.residue_breakout version 1.',
    ],
  },
  {
    id: 'two-station-schemas',
    turns: [
      'Call load_station_schema with schemaKey hatch_analysis.residue_breakout version 1.',
      'Now call load_station_schema with schemaKey chicks.postmortem version 1.',
    ],
  },
  {
    id: 'intake',
    turns: [
      'I want to record a residue breakout for customer Rs-NileV, flock 1.',
      'Yes, go ahead.',
    ],
  },
]

async function runScenario(
  apiKey: string,
  scenario: Scenario,
  tools: readonly RealtimeToolDefinition[],
  instructions: string,
  paceMs: number,
): Promise<Row[]> {
  const config = testConfig({
    model: MODEL,
    voice: 'cedar',
    transcriptionModel: 'gpt-4o-mini-transcribe',
    reasoningEffort: 'low',
    turnDetection: 'semantic_vad',
    vadEagerness: 'low',
  })
  const probe = await Probe.connect(apiKey)
  const rows: Row[] = []
  try {
    probe.send(buildSessionUpdate({ config, tools, instructions }))
    await probe.until((event) => event.type === 'session.updated')
    let turnIndex = 0
    for (const text of scenario.turns) {
      turnIndex += 1
      await new Promise((resolve) => setTimeout(resolve, paceMs))
      probe.send({
        type: 'conversation.item.create',
        item: { type: 'message', role: 'user', content: [{ type: 'input_text', text }] },
      })
      probe.send({ type: 'response.create' })
      for (let round = 0; round < 5; round++) {
        const done = await probe.until((event) => event.type === 'response.done')
        const label = round === 0
          ? `turn ${turnIndex}`
          : `turn ${turnIndex} +tool round ${round}`
        rows.push(usageRow(scenario.id, label, done))
        const output = ((done.response as Ev).output ?? []) as Ev[]
        const calls = output.filter((item) => item.type === 'function_call')
        if (calls.length === 0) break
        for (const call of calls) {
          probe.send({
            type: 'conversation.item.create',
            item: {
              type: 'function_call_output',
              call_id: call.call_id,
              output: JSON.stringify(stubFor(String(call.name))),
            },
          })
        }
        await new Promise((resolve) => setTimeout(resolve, paceMs))
        probe.send({ type: 'response.create' })
      }
    }
  } finally {
    probe.close()
  }
  return rows
}

if (import.meta.main) {
  const apiKey = Deno.env.get('OPENAI_API_KEY')
  if (!apiKey) {
    console.error('OPENAI_API_KEY is required')
    Deno.exit(2)
  }
  const tools = await loadTools()
  const instructions = await loadInstructions()
  const paceMs = Number(flag('pace', '12000'))
  const only = flag('scenario')
  const selected = only ? SCENARIOS.filter((s) => s.id === only) : SCENARIOS

  console.log(`# model=${MODEL}`)
  console.log(`# instructions_chars=${instructions.length}`)
  console.log(`# tool_count=${tools.length} tools_chars=${JSON.stringify(tools).length}`)
  console.log(`# catalogue=${flag('catalogue', 'full')} pace=${paceMs}ms`)

  const rows: Row[] = []
  for (const scenario of selected) {
    console.error(`# running ${scenario.id}`)
    rows.push(...await runScenario(apiKey, scenario, tools, instructions, paceMs))
  }

  console.log()
  console.log('| scenario | step | input | cached | uncached | output |')
  console.log('|---|---|---:|---:|---:|---:|')
  for (const row of rows) {
    console.log(
      `| ${row.scenario} | ${row.step} | ${row.input} | ${row.cached} | ${row.uncached} | ${row.output} |`,
    )
  }

  const first = rows.find((row) => row.scenario === 'fresh-hi')
  if (first && first.input > 0) {
    // The observed account cap for this model. Turns/minute is the number the
    // TPM ceiling actually translates into for a user mid-conversation.
    const tpm = 40_000
    console.log()
    console.log(`# static first-turn input: ${first.input} tokens`)
    console.log(
      `# inferences/minute under a ${tpm} TPM cap: ${(tpm / first.input).toFixed(1)}`,
    )
  }
}
