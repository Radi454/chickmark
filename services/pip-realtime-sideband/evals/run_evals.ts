// Conversation-behavior eval runner for the Pip Realtime agent.
//
// Talks to the REAL model over the OpenAI Realtime WebSocket, in TEXT mode,
// using the scenarios scripted in `scenarios.ts`. This costs money and is
// NOT part of `deno test` — run it on demand:
//
//   export OPENAI_API_KEY="$(gcloud secrets versions access latest \
//     --secret=openai-api-key --project=chickmark-ai-agent)"
//   deno run --allow-net --allow-env evals/run_evals.ts [--filter substring] [--debug]
//
// See README.md in this directory for the full picture, including why the
// instructions renderer is imported dynamically at runtime rather than
// statically at the top of this file.
//
// Wire shape (verified against the live endpoint before this file was
// written; see WIRE_CONTRACT.md and src/sideband.ts for the sibling
// production transport):
//   wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1-mini via `ws`,
//   header `Authorization: Bearer <key>`, no subprotocols.
//   session.update: {type:'realtime', output_modalities:['text'],
//     instructions, tools, tool_choice:'auto'} — text modality, so no audio
//     config is needed and none is sent.
//   User turn: conversation.item.create {type:'message', role:'user',
//     content:[{type:'input_text', text}]} then response.create.
//   Text arrives batched on response.done (response.output[].content[]
//     where item.type === 'message'); this runner does not need the
//     response.output_text.delta stream since response.done already carries
//     the complete text.
//   Tool calls arrive as response.output[] entries with
//     item.type === 'function_call' ({name, call_id, arguments}); reply with
//     conversation.item.create {type:'function_call_output', call_id, output}
//     then response.create again.

import { WebSocket as NodeWebSocket } from 'ws'

import {
  AGGREGATE_CHECKS,
  type AggregateEntry,
  type Assertion,
  type AssertionOutcome,
  DEFAULT_TOOL_STUBS,
  DERIVED_CHECKS,
  finalText,
  type FunctionCallItem,
  type MessageItem,
  type OutputItem,
  type Round,
  type Scenario,
  SCENARIOS,
  type ToolStub,
  type TurnResult,
  type TurnSpec,
} from './scenarios.ts'

const OPENAI_REALTIME_URL = 'wss://api.openai.com/v1/realtime'
const MODEL = 'gpt-realtime-2.1-mini'
const MAX_TOOL_ROUNDS = 6
const EVENT_TIMEOUT_MS = 45_000

// ---------------------------------------------------------------------------
// Instructions + tools: loaded dynamically at runtime
// ---------------------------------------------------------------------------

interface FlatToolDefinition {
  readonly type: 'function'
  readonly name: string
  readonly description: string
  readonly parameters: Record<string, unknown>
}

/**
 * `tools/render_agent_instructions.ts` is being edited by another agent
 * concurrently, to export a new realtime policy. This is a DYNAMIC import
 * (resolved when `main()` runs, not when this module is parsed) so this eval
 * always picks up whatever that file currently exports, and so a mid-edit
 * file doesn't fail this module's own static analysis. Whatever the render
 * function returns is used as-is — the eval does not interpret its content,
 * only its behavior on the wire.
 */
async function loadInstructions(): Promise<{ text: string; version: string }> {
  const mod = await import('../tools/render_agent_instructions.ts') as Record<
    string,
    unknown
  >
  const candidateFnNames = [
    'renderRealtimeInstructions',
    'renderRealtimePolicy',
    'renderInstructions',
  ]
  for (const name of candidateFnNames) {
    const fn = mod[name]
    if (typeof fn === 'function') {
      const text = String(await (fn as () => string | Promise<string>)())
      const versionKey = Object.keys(mod).find(
        (key) => /VERSION/i.test(key) && typeof mod[key] === 'string',
      )
      const version = versionKey ? String(mod[versionKey]) : 'unknown'
      return { text, version }
    }
  }
  throw new Error(
    `tools/render_agent_instructions.ts exports no recognizable render function. ` +
      `Looked for: ${candidateFnNames.join(', ')}. Actual exports: ${
        Object.keys(mod).join(', ') || '(none)'
      }`,
  )
}

/**
 * Minimal hand-written fallback, used ONLY if `render_tool_definitions.ts`
 * stops exporting a render function. Matches the real schemas in
 * `agent_tool_contract.ts` for `resolve_customer_flock`, `get_breed_benchmark`,
 * and one flock/customer data tool (`list_customer_flocks`).
 */
const FALLBACK_TOOL_DEFINITIONS: readonly FlatToolDefinition[] = [
  {
    type: 'function',
    name: 'resolve_customer_flock',
    description:
      'Resolve an allowed customer name and optional flock name together using exact ' +
      'normalized names. Use this before ID-based tools when the user supplies names.',
    parameters: {
      type: 'object',
      properties: {
        customerName: { type: 'string', minLength: 1, maxLength: 160 },
        flockName: { type: 'string', minLength: 1, maxLength: 160 },
      },
      required: ['customerName'],
      additionalProperties: false,
    },
  },
  {
    type: 'function',
    name: 'get_breed_benchmark',
    description:
      'Look up the published breed standard (hatchability, fertility, HOF, production, ' +
      'egg weight, chick weight) for one breed at one flock age in weeks. Always use this ' +
      'instead of stating a benchmark from memory.',
    parameters: {
      type: 'object',
      properties: {
        breed: { type: 'string', minLength: 1, maxLength: 60 },
        ageWeek: { type: 'integer', minimum: 1, maximum: 120 },
      },
      required: ['breed', 'ageWeek'],
      additionalProperties: false,
    },
  },
  {
    type: 'function',
    name: 'list_customer_flocks',
    description: 'List flocks for an allowed customer.',
    parameters: {
      type: 'object',
      properties: {
        customerId: { type: 'string', minLength: 1, maxLength: 160 },
        limit: { type: 'integer', minimum: 1, maximum: 100 },
      },
      required: ['customerId'],
      additionalProperties: false,
    },
  },
]

async function loadTools(): Promise<readonly FlatToolDefinition[]> {
  const mod = await import('../tools/render_tool_definitions.ts') as Record<
    string,
    unknown
  >
  const fn = mod['renderRealtimeToolDefinitions']
  if (typeof fn === 'function') {
    return (fn as () => readonly FlatToolDefinition[])()
  }
  console.error(
    '[warn] tools/render_tool_definitions.ts has no renderRealtimeToolDefinitions() export; ' +
      'falling back to the minimal hand-written subset (resolve_customer_flock, ' +
      'get_breed_benchmark, list_customer_flocks).',
  )
  return FALLBACK_TOOL_DEFINITIONS
}

// ---------------------------------------------------------------------------
// Transport
// ---------------------------------------------------------------------------

class EvalTransportError extends Error {}

interface RealtimeEvent {
  readonly type: string
  readonly [key: string]: unknown
}

/** Event types this runner has actually observed on the wire. Anything else
 * is logged under --debug so a wire-shape change is visible immediately. */
const KNOWN_EVENT_TYPES = new Set([
  'session.created',
  'session.updated',
  'conversation.item.created',
  'conversation.item.added',
  'conversation.item.done',
  'response.created',
  'response.output_item.added',
  'response.output_item.done',
  'response.content_part.added',
  'response.content_part.done',
  'response.output_text.delta',
  'response.output_text.done',
  'response.function_call_arguments.delta',
  'response.function_call_arguments.done',
  'response.done',
  'rate_limits.updated',
  'error',
])

class RealtimeSession {
  private readonly queue: RealtimeEvent[] = []
  private readonly waiters: Array<(event: RealtimeEvent) => void> = []
  private closed = false

  private constructor(
    private readonly ws: NodeWebSocket,
    private readonly debug: boolean,
  ) {
    ws.on('message', (data: Buffer | string) => {
      let parsed: RealtimeEvent
      try {
        parsed = JSON.parse(data.toString())
      } catch {
        return
      }
      if (this.debug && !KNOWN_EVENT_TYPES.has(parsed.type)) {
        console.error(
          `[debug] unknown event type: ${parsed.type}`,
          JSON.stringify(parsed),
        )
      }
      this.push(parsed)
    })
    ws.on('close', (code: number, reason: Buffer) => {
      this.closed = true
      this.push({ type: '_transport_closed', code, reason: reason?.toString() ?? '' })
    })
    ws.on('error', (err: Error) => {
      this.push({ type: '_transport_error', message: err.message })
    })
  }

  /** Attaches the message handler BEFORE awaiting `open`, so an event sent
   * immediately on connect (e.g. `session.created`) is never dropped. */
  static async connect(apiKey: string, debug: boolean): Promise<RealtimeSession> {
    const ws = new NodeWebSocket(`${OPENAI_REALTIME_URL}?model=${MODEL}`, {
      headers: { Authorization: `Bearer ${apiKey}` },
    })
    const session = new RealtimeSession(ws, debug)
    await new Promise<void>((resolve, reject) => {
      ws.once('open', () => resolve())
      ws.once(
        'error',
        (err: Error) => reject(new EvalTransportError(`connect failed: ${err.message}`)),
      )
    })
    return session
  }

  private push(event: RealtimeEvent): void {
    const waiter = this.waiters.shift()
    if (waiter) waiter(event)
    else this.queue.push(event)
  }

  next(timeoutMs = EVENT_TIMEOUT_MS): Promise<RealtimeEvent> {
    const queued = this.queue.shift()
    if (queued) return Promise.resolve(queued)
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const index = this.waiters.indexOf(wrapped)
        if (index >= 0) this.waiters.splice(index, 1)
        reject(
          new EvalTransportError(`timed out waiting for next event after ${timeoutMs}ms`),
        )
      }, timeoutMs)
      const wrapped = (event: RealtimeEvent) => {
        clearTimeout(timer)
        resolve(event)
      }
      this.waiters.push(wrapped)
    })
  }

  send(payload: unknown): void {
    this.ws.send(JSON.stringify(payload))
  }

  close(): void {
    if (this.closed) return
    try {
      this.ws.close(1000, 'eval done')
    } catch {
      // already closing/closed — nothing to do
    }
  }
}

async function awaitEvent(
  session: RealtimeSession,
  predicate: (event: RealtimeEvent) => boolean,
): Promise<RealtimeEvent> {
  for (;;) {
    const event = await session.next()
    if (event.type === '_transport_error') {
      throw new EvalTransportError(`transport error: ${String(event.message)}`)
    }
    if (event.type === '_transport_closed') {
      throw new EvalTransportError(
        `socket closed unexpectedly (code ${String(event.code)}, reason ${
          String(event.reason)
        })`,
      )
    }
    if (event.type === 'error') {
      throw new EvalTransportError(`provider error: ${JSON.stringify(event)}`)
    }
    if (predicate(event)) return event
  }
}

async function updateSession(
  session: RealtimeSession,
  instructions: string,
  tools: readonly FlatToolDefinition[],
): Promise<void> {
  session.send({
    type: 'session.update',
    session: {
      type: 'realtime',
      output_modalities: ['text'],
      instructions,
      tools,
      tool_choice: 'auto',
    },
  })
  await awaitEvent(session, (event) => event.type === 'session.updated')
}

function sendUserTurn(session: RealtimeSession, text: string): void {
  session.send({
    type: 'conversation.item.create',
    item: { type: 'message', role: 'user', content: [{ type: 'input_text', text }] },
  })
  session.send({ type: 'response.create' })
}

function parseRound(doneEvent: RealtimeEvent): Round {
  const response = doneEvent.response as Record<string, unknown> | undefined
  const output = (response?.output as unknown[] | undefined) ?? []
  const items: OutputItem[] = output.map((raw) => {
    const item = raw as Record<string, unknown>
    if (item.type === 'message') {
      const content = (item.content as Array<Record<string, unknown>> | undefined) ?? []
      const text = content
        .filter((part) => part.type === 'output_text' && typeof part.text === 'string')
        .map((part) => part.text as string)
        .join('')
      return { type: 'message', text } satisfies MessageItem
    }
    if (item.type === 'function_call') {
      let args: Record<string, unknown> = {}
      try {
        args = JSON.parse((item.arguments as string) ?? '{}')
      } catch {
        // leave args empty — a malformed-arguments call is still worth
        // recording as "called", the stub lookup just won't get real args.
      }
      return {
        type: 'function_call',
        name: String(item.name),
        callId: String(item.call_id),
        arguments: args,
      } satisfies FunctionCallItem
    }
    return { type: 'other', raw: item }
  })
  return {
    items,
    messages: items.filter((item): item is MessageItem => item.type === 'message').map((
      item,
    ) => item.text),
    functionCalls: items.filter((item): item is FunctionCallItem =>
      item.type === 'function_call'
    ),
    status: String(response?.status ?? 'unknown'),
  }
}

function matchStub(
  stubs: readonly ToolStub[],
  call: FunctionCallItem,
): ToolStub | undefined {
  return stubs.find((stub) =>
    stub.name === call.name && (!stub.matches || stub.matches(call.arguments))
  )
}

/** A turn-specific stub always wins; `DEFAULT_TOOL_STUBS` is only a fallback
 * for bootstrap tools (see its doc comment in scenarios.ts). */
function findStub(
  stubs: readonly ToolStub[] | undefined,
  call: FunctionCallItem,
): ToolStub | undefined {
  return (stubs && matchStub(stubs, call)) ?? matchStub(DEFAULT_TOOL_STUBS, call)
}

const MAX_EMPTY_RETRIES = 3
const EMPTY_RETRY_BASE_DELAY_MS = 4000

/**
 * Awaits one `response.done` and retries `response.create` (never resending
 * the user message or a tool output — so this is always side-effect-free) if
 * the round comes back with literally zero output items, backing off
 * linearly (4s, 8s, 12s) between attempts.
 *
 * This is a REAL, observed transport hiccup, not a parsing bug: probed
 * directly against the live endpoint with a trivial single-turn, zero-tool
 * session repeated back-to-back, `response.done.response.output` itself
 * comes back `[]` around the 6th-8th rapid successive session on this
 * account — the provider's own payload is empty, before any of this
 * runner's parsing touches it. Retrying the same pending response is the
 * same recovery a real client would perform. If it still comes back empty
 * after every retry, `runTurn` surfaces that explicitly via the
 * `providerReturnedContent` check rather than letting an empty string
 * silently satisfy a maxWords/mustNotMatch assertion.
 */
async function awaitResponseWithRetry(session: RealtimeSession): Promise<Round> {
  let round = parseRound(
    await awaitEvent(session, (event) => event.type === 'response.done'),
  )
  let retries = 0
  while (round.items.length === 0 && retries < MAX_EMPTY_RETRIES) {
    retries += 1
    const delayMs = EMPTY_RETRY_BASE_DELAY_MS * retries
    console.error(
      `[warn] response.done carried zero output items (known transient Realtime API ` +
        `hiccup under rapid successive sessions) — retrying response.create in ` +
        `${delayMs}ms (${retries}/${MAX_EMPTY_RETRIES})`,
    )
    await sleep(delayMs)
    session.send({ type: 'response.create' })
    round = parseRound(
      await awaitEvent(session, (event) => event.type === 'response.done'),
    )
  }
  return round
}

/**
 * Runs one user turn to completion: sends the user message, then loops
 * responding to any function calls with their scripted stub output (or a
 * synthetic failure if the turn didn't script one, so the session never
 * hangs on an unstubbed call) until a round comes back with no more tool
 * calls, or `MAX_TOOL_ROUNDS` is hit.
 */
async function runTurn(session: RealtimeSession, turn: TurnSpec): Promise<TurnResult> {
  sendUserTurn(session, turn.userText)
  const rounds: Round[] = []
  let round = await awaitResponseWithRetry(session)
  rounds.push(round)

  let iterations = 0
  while (round.functionCalls.length > 0 && iterations < MAX_TOOL_ROUNDS) {
    iterations += 1
    for (const call of round.functionCalls) {
      const stub = findStub(turn.toolStubs, call)
      const output = stub
        ? stub.output
        : { ok: false, code: 'unstubbed_in_eval', tool: call.name, data: null }
      session.send({
        type: 'conversation.item.create',
        item: {
          type: 'function_call_output',
          call_id: call.callId,
          output: JSON.stringify(output),
        },
      })
    }
    session.send({ type: 'response.create' })
    round = await awaitResponseWithRetry(session)
    rounds.push(round)
  }

  return { rounds, allToolCalls: rounds.flatMap((r) => r.functionCalls) }
}

// ---------------------------------------------------------------------------
// CLI + reporting
// ---------------------------------------------------------------------------

interface CliArgs {
  readonly filter?: string
  readonly debug: boolean
}

function parseArgs(argv: readonly string[]): CliArgs {
  let filter: string | undefined
  let debug = false
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--debug') {
      debug = true
      continue
    }
    if (arg === '--filter') {
      filter = argv[i + 1]
      i++
      continue
    }
    if (arg.startsWith('--filter=')) {
      filter = arg.slice('--filter='.length)
    }
  }
  return { filter, debug }
}

function matchesFilter(id: string, title: string, filter: string | undefined): boolean {
  if (!filter) return true
  const needle = filter.toLowerCase()
  return id.toLowerCase().includes(needle) || title.toLowerCase().includes(needle)
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

/** A short pause between scenarios (each of which opens a fresh session and
 * fires several reasoning-heavy requests) to stay clear of the provider's
 * per-minute rate limit. Observed live: running the full suite back-to-back
 * with no pause causes later scenarios in the same process to come back with
 * genuinely empty `response.done` output — a real throttling artifact, not a
 * parsing bug (confirmed by re-running the same scenarios in isolation). */
const INTER_SCENARIO_DELAY_MS = 4000

interface ReportRow {
  readonly scenarioId: string
  readonly turnLabel: string
  readonly outcome: AssertionOutcome
  readonly replyText: string
}

function printTable(rows: readonly ReportRow[]): void {
  console.log('')
  console.log('='.repeat(100))
  console.log('RESULTS')
  console.log('='.repeat(100))
  const col1 = Math.max(8, ...rows.map((r) => r.scenarioId.length))
  const col2 = Math.max(4, ...rows.map((r) => r.turnLabel.length))
  for (const row of rows) {
    const status = row.outcome.pass ? 'PASS' : 'FAIL'
    console.log(
      `${status.padEnd(5)} ${row.scenarioId.padEnd(col1)}  ${
        row.turnLabel.padEnd(col2)
      }  ${row.outcome.label}`,
    )
  }

  console.log('')
  console.log('='.repeat(100))
  console.log('DETAIL (actual replies)')
  console.log('='.repeat(100))
  let lastKey = ''
  for (const row of rows) {
    const key = `${row.scenarioId}/${row.turnLabel}`
    if (key !== lastKey) {
      console.log('')
      console.log(`--- ${key} ---`)
      console.log(`reply: ${row.replyText || '(empty)'}`)
      lastKey = key
    }
    if (!row.outcome.pass) {
      console.log(`  FAIL ${row.outcome.label}: ${row.outcome.detail ?? ''}`)
    }
  }

  const failCount = rows.filter((r) => !r.outcome.pass).length
  console.log('')
  console.log(`${rows.length - failCount}/${rows.length} assertions passed.`)
}

async function main(): Promise<void> {
  const args = parseArgs(Deno.args)

  const apiKey = Deno.env.get('OPENAI_API_KEY')
  if (!apiKey) {
    console.error('OPENAI_API_KEY is not set. Example:')
    console.error(
      '  export OPENAI_API_KEY="$(gcloud secrets versions access latest ' +
        '--secret=openai-api-key --project=chickmark-ai-agent)"',
    )
    Deno.exit(1)
  }

  const { text: instructions, version: instructionsVersion } = await loadInstructions()
  const tools = await loadTools()

  console.log(`Model: ${MODEL}`)
  console.log(`Instructions version: ${instructionsVersion}`)
  console.log(`Loaded ${tools.length} tool definitions`)
  if (args.filter) console.log(`Filter: "${args.filter}"`)
  console.log('')

  const scenariosToRun = SCENARIOS.filter((s: Scenario) =>
    matchesFilter(s.id, s.title, args.filter)
  )
  if (scenariosToRun.length === 0) {
    console.error(`No scenario matched filter "${args.filter}".`)
    Deno.exit(1)
  }

  const rows: ReportRow[] = []
  const capturedResults = new Map<string, readonly TurnResult[]>()
  const allFinalTexts: AggregateEntry[] = []

  for (const [scenarioIndex, scenario] of scenariosToRun.entries()) {
    if (scenarioIndex > 0) await sleep(INTER_SCENARIO_DELAY_MS)

    console.log(
      `=== ${scenario.id} — ${scenario.title} (spec #${
        scenario.specNumbers.join(', ')
      }) ===`,
    )
    if (scenario.note) console.log(`  note: ${scenario.note}`)

    let session: RealtimeSession | undefined
    const turnResults: TurnResult[] = []
    try {
      session = await RealtimeSession.connect(apiKey, args.debug)
      await updateSession(session, instructions, tools)

      for (let turnIndex = 0; turnIndex < scenario.turns.length; turnIndex++) {
        const turn = scenario.turns[turnIndex]
        const result = await runTurn(session, turn)
        turnResults.push(result)
        const text = finalText(result)
        allFinalTexts.push({ scenarioId: scenario.id, turnIndex, text })
        const turnLabel = turn.label ?? `turn ${turnIndex + 1}`
        // An empty reply trivially satisfies maxWords/mustNotMatch, which would
        // silently misreport a transport hiccup as a pass. Surface it explicitly
        // as its own row instead, ahead of the scripted assertions.
        rows.push({
          scenarioId: scenario.id,
          turnLabel,
          outcome: {
            pass: text.trim().length > 0,
            label: 'providerReturnedContent',
            detail: text.trim().length > 0
              ? 'ok'
              : 'response.done carried empty output even after retries — see [warn] lines above',
          },
          replyText: text,
        })
        for (const assertion of turn.assertions as readonly Assertion[]) {
          const outcome = assertion(result)
          rows.push({ scenarioId: scenario.id, turnLabel, outcome, replyText: text })
        }
      }
      capturedResults.set(scenario.id, turnResults)
    } catch (err) {
      rows.push({
        scenarioId: scenario.id,
        turnLabel: 'transport',
        outcome: { pass: false, label: 'transport', detail: String(err) },
        replyText: '',
      })
    } finally {
      session?.close()
    }
  }

  for (const derived of DERIVED_CHECKS) {
    if (!matchesFilter(derived.id, derived.title, args.filter)) continue
    const source = capturedResults.get(derived.fromScenarioId)
    if (!source) {
      rows.push({
        scenarioId: derived.id,
        turnLabel: 'derived',
        outcome: {
          pass: false,
          label: 'skipped',
          detail:
            `source scenario "${derived.fromScenarioId}" was not run (filtered out?)`,
        },
        replyText: '',
      })
      continue
    }
    const turnResult = source[derived.turnIndex]
    const turnLabel = `derived from ${derived.fromScenarioId}#${derived.turnIndex}`
    for (const assertion of derived.assertions) {
      const outcome = assertion(turnResult)
      rows.push({
        scenarioId: derived.id,
        turnLabel,
        outcome,
        replyText: finalText(turnResult),
      })
    }
  }

  for (const aggregate of AGGREGATE_CHECKS) {
    if (!matchesFilter(aggregate.id, aggregate.title, args.filter)) continue
    const outcome = aggregate.assertion(allFinalTexts)
    rows.push({
      scenarioId: aggregate.id,
      turnLabel: 'aggregate',
      outcome,
      replyText: '',
    })
  }

  printTable(rows)
  const anyFail = rows.some((row) => !row.outcome.pass)
  Deno.exit(anyFail ? 1 : 0)
}

if (import.meta.main) {
  main()
}
