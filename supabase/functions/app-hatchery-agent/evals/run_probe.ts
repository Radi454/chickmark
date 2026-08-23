// ChickMark text-agent tool-calling COMPATIBILITY PROBE.
//
// A small, fast pass/fail gate answering one question: "can this model drive
// our agent at all?" -- before spending the time and money on the full
// `run_evals.ts` acceptance suite. One check per capability, each printed as
// PASS/FAIL with the observed evidence. Talks to the REAL model over the
// REAL OpenRouter `/v1/responses` endpoint, using the REAL system prompt and
// tool catalogue -- see `agent_client.ts`. This costs money and is NOT part
// of `deno test`.
//
//   export OPENROUTER_API_KEY="..."   # or place it in the repo's .env
//   deno run --allow-net --allow-env --allow-read evals/run_probe.ts \
//     --model google/gemma-4-31b-it:free
//   deno run --allow-net --allow-env --allow-read evals/run_probe.ts \
//     --model openai/gpt-oss-20b:free
//
// Options: --model <id> (required), --filter <substring>, --debug,
// --temperature <n> (default 0), --seed <n> (default 20260819),
// --reasoning-effort <low|medium|high> (only sent if given).
//
// See README.md for what each check means and how it differs from the
// scenario-driven acceptance suite in run_evals.ts.

import {
  AGENT_MODEL_TOOL_DEFINITIONS,
  buildEvalInstructions,
  containsArabic,
  createSession,
  runTurn,
  type ToolStub,
  type TurnResult,
  validateToolArguments,
} from './agent_client.ts'
import { requireOpenRouterApiKey } from './env.ts'

interface CliArgs {
  readonly model: string
  readonly filter?: string
  readonly debug: boolean
  readonly temperature: number
  readonly seed: number
  readonly reasoningEffort?: 'low' | 'medium' | 'high'
}

const DEFAULT_SEED = 20260819

function parseArgs(argv: readonly string[]): CliArgs {
  let model: string | undefined
  let filter: string | undefined
  let debug = false
  let temperature = 0
  let seed = DEFAULT_SEED
  let reasoningEffort: 'low' | 'medium' | 'high' | undefined

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--model') model = argv[++i]
    else if (arg.startsWith('--model=')) model = arg.slice('--model='.length)
    else if (arg === '--filter') filter = argv[++i]
    else if (arg.startsWith('--filter=')) filter = arg.slice('--filter='.length)
    else if (arg === '--debug') debug = true
    else if (arg === '--temperature') temperature = Number(argv[++i])
    else if (arg.startsWith('--temperature=')) {
      temperature = Number(arg.slice('--temperature='.length))
    } else if (arg === '--seed') seed = Number(argv[++i])
    else if (arg.startsWith('--seed=')) {
      seed = Number(arg.slice('--seed='.length))
    } else if (arg === '--reasoning-effort') {
      reasoningEffort = argv[++i] as 'low' | 'medium' | 'high'
    } else if (arg.startsWith('--reasoning-effort=')) {
      reasoningEffort = arg.slice('--reasoning-effort='.length) as
        | 'low'
        | 'medium'
        | 'high'
    }
  }

  if (!model) {
    console.error('Missing required --model <openrouter-model-id>. Example:')
    console.error(
      '  deno run --allow-net --allow-env --allow-read evals/run_probe.ts \\',
    )
    console.error('    --model google/gemma-4-31b-it:free')
    Deno.exit(1)
  }
  return { model, filter, debug, temperature, seed, reasoningEffort }
}

// ---------------------------------------------------------------------------
// Real result shapes (see scenarios.ts's header comment for provenance --
// taken from agent_read_tools.ts / bmk_tools.ts after reading them).
// ---------------------------------------------------------------------------

const RESOLVE_NILE_OK: ToolStub = {
  name: 'resolve_customer_flock',
  output: {
    ok: true,
    code: 'ok',
    data: {
      status: 'ok',
      customer: { id: 'cust_probe_nile', name: 'عميل النيل' },
      flock: null,
    },
  },
}

const LIST_NILE_FLOCKS: ToolStub = {
  name: 'list_customer_flocks',
  output: {
    ok: true,
    code: 'ok',
    data: {
      flocks: [
        { id: 'flock_1', name: 'قطيع 1', ageWeeks: 20 },
        { id: 'flock_2', name: 'قطيع 2', ageWeeks: 32 },
        { id: 'flock_3', name: 'قطيع 3', ageWeeks: 46 },
      ],
      truncated: false,
    },
  },
}

const GET_FLOCK_3_CONTEXT: ToolStub = {
  name: 'get_flock_context',
  output: {
    ok: true,
    code: 'ok',
    data: { id: 'flock_3', name: 'قطيع 3', ageWeeks: 46 },
  },
}

const RESOLVE_DELTA_OK: ToolStub = {
  name: 'resolve_customer_flock',
  output: {
    ok: true,
    code: 'ok',
    data: {
      status: 'ok',
      customer: { id: 'cust_probe_delta', name: 'عميل الدلتا' },
      flock: null,
    },
  },
}

const LIST_DELTA_FLOCKS: ToolStub = {
  name: 'list_customer_flocks',
  output: {
    ok: true,
    code: 'ok',
    data: {
      flocks: [{ id: 'd1', name: 'قطيع دلتا 1', ageWeeks: 12 }],
      truncated: false,
    },
  },
}

const HUBBARD_WK40_FULL: ToolStub = {
  name: 'get_breed_benchmark',
  output: {
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
      unavailable: [],
    },
  },
}

// ---------------------------------------------------------------------------
// Check plumbing
// ---------------------------------------------------------------------------

interface CheckResult {
  readonly name: string
  readonly pass: boolean
  readonly evidence: string
}

interface RunTurnOnceOptions {
  readonly model: string
  readonly apiKey: string
  readonly temperature: number
  readonly seed: number
  readonly reasoningEffort?: 'low' | 'medium' | 'high'
  readonly extraDirective?: string
}

/** Runs a single retry-once turn against a fresh session, so a transient
 * transport hiccup on the free-tier endpoint doesn't fail a whole check. */
async function runProbeTurn(
  options: RunTurnOnceOptions,
  turns: ReadonlyArray<{ userText: string; toolStubs?: readonly ToolStub[] }>,
): Promise<{ results: TurnResult[]; retried: boolean }> {
  for (let attempt = 1; attempt <= 2; attempt++) {
    const session = createSession({
      apiKey: options.apiKey,
      model: options.model,
      instructions: buildEvalInstructions({
        extraDirective: options.extraDirective,
      }),
      tools: AGENT_MODEL_TOOL_DEFINITIONS,
      temperature: options.temperature,
      seed: options.seed,
      reasoningEffort: options.reasoningEffort,
    })
    const results: TurnResult[] = []
    let transient = false
    for (const turn of turns) {
      const result = await runTurn(session, turn.userText, turn.toolStubs ?? [])
      if (
        result.status === 'transport_error' &&
        result.transportKind === 'transient' && attempt === 1
      ) {
        transient = true
        break
      }
      results.push(result)
    }
    if (!transient) return { results, retried: attempt === 2 }
    console.error(`  [warn] transient transport error, retrying once...`)
    await new Promise((resolve) => setTimeout(resolve, 2000))
  }
  return { results: [], retried: true }
}

const KNOWN_TOOL_NAMES: ReadonlySet<string> = new Set(
  AGENT_MODEL_TOOL_DEFINITIONS.map((tool) => tool.name as string),
)

// ---------------------------------------------------------------------------
// The seven checks
// ---------------------------------------------------------------------------

async function check1InstructionHandling(
  options: RunTurnOnceOptions,
): Promise<CheckResult> {
  const marker = 'PROBE-MARKER-7F3Q'
  const { results } = await runProbeTurn(
    {
      ...options,
      extraDirective:
        `For this evaluation only, end every reply you send with the exact text: ${marker}. ` +
        `Include this marker even in a short casual reply, as the very last thing you write.`,
    },
    [{ userText: 'إزيك، عامل إيه؟' }],
  )
  const reply = results[0]?.finalReply ?? ''
  const pass = results[0]?.status === 'replied' && reply.includes(marker)
  return {
    name:
      '1. system/instruction handling (directive placed in `instructions`, not a message)',
    pass,
    evidence: `reply: "${reply}"`,
  }
}

async function check2ToolDefinitions(
  options: RunTurnOnceOptions,
): Promise<CheckResult> {
  const { results } = await runProbeTurn(options, [{
    userText: 'عميل النيل عنده كام flock؟',
    toolStubs: [RESOLVE_NILE_OK, LIST_NILE_FLOCKS],
  }])
  const calls = results[0]?.allToolCalls ?? []
  const wellFormed = calls.length > 0 &&
    calls.every((call) =>
      KNOWN_TOOL_NAMES.has(call.name) && call.rawArguments.trim().length > 0
    )
  return {
    name:
      '2. function/tool definitions (emits a well-formed function_call for our catalogue)',
    pass: wellFormed,
    evidence: calls.length === 0
      ? 'no function_call was emitted at all'
      : `calls: ${calls.map((c) => `${c.name}(${c.rawArguments})`).join(', ')}`,
  }
}

async function check3SequentialToolCalls(
  options: RunTurnOnceOptions,
): Promise<CheckResult> {
  const { results } = await runProbeTurn(options, [{
    userText: 'عميل النيل عنده كام flock واكبر واحد فيهم عمره كام؟',
    toolStubs: [RESOLVE_NILE_OK, LIST_NILE_FLOCKS, GET_FLOCK_3_CONTEXT],
  }])
  const calls = results[0]?.allToolCalls ?? []
  const resolveCall = calls.find((c) => c.name === 'resolve_customer_flock')
  const listCall = calls.find((c) => c.name === 'list_customer_flocks')
  const pass = Boolean(resolveCall) && Boolean(listCall) &&
    listCall!.arguments.customerId === 'cust_probe_nile'
  return {
    name:
      "3. multiple sequential tool calls (tool A, then tool B using A's result)",
    pass,
    evidence: `calls: ${
      calls.map((c) => `${c.name}(${JSON.stringify(c.arguments)})`).join(
        ', ',
      ) || 'none'
    }`,
  }
}

async function check4Synthesis(
  options: RunTurnOnceOptions,
): Promise<CheckResult> {
  const { results } = await runProbeTurn(options, [{
    userText: 'إنتاج هبرد في الأسبوع 40 كام؟',
    toolStubs: [HUBBARD_WK40_FULL],
  }])
  const result = results[0]
  const finalRound = result?.rounds[result.rounds.length - 1]
  const productionCallCount = (result?.allToolCalls ?? [])
    .filter((c) => c.name === 'get_breed_benchmark').length
  const groundedInStub = /80|٨٠/.test(result?.finalReply ?? '')
  const pass = result?.status === 'replied' &&
    (finalRound?.functionCalls.length ?? 1) === 0 &&
    productionCallCount === 1 &&
    groundedInStub
  return {
    name:
      '4. tool result → synthesis (final text grounded in the stub, not a re-call)',
    pass,
    evidence:
      `status=${result?.status}, get_breed_benchmark calls=${productionCallCount}, ` +
      `reply: "${result?.finalReply ?? ''}"`,
  }
}

async function check5StructuredArguments(
  options: RunTurnOnceOptions,
): Promise<CheckResult> {
  const { results } = await runProbeTurn(options, [{
    userText: 'الإنتاج بس لسلالة هبرد في الأسبوع 40 كام؟',
    toolStubs: [HUBBARD_WK40_FULL],
  }])
  const calls = results[0]?.allToolCalls ?? []
  if (calls.length === 0) {
    return {
      name:
        '5. structured arguments (valid JSON matching the declared schema, mechanically checked)',
      pass: false,
      evidence: 'no function_call was emitted',
    }
  }
  const problems = calls.flatMap((call) => {
    const validation = validateToolArguments(call.name, call.arguments)
    return validation.problems.map((p) => `${call.name}: ${p}`)
  })
  return {
    name:
      '5. structured arguments (valid JSON matching the declared schema, mechanically checked)',
    pass: problems.length === 0,
    evidence: problems.length === 0
      ? `all ${calls.length} call(s) valid: ${
        calls.map((c) => c.rawArguments).join(', ')
      }`
      : problems.join('; '),
  }
}

async function check6Arabic(options: RunTurnOnceOptions): Promise<CheckResult> {
  const { results } = await runProbeTurn(options, [{
    userText: 'عميل الدلتا عندهم كام قطيع؟',
    toolStubs: [RESOLVE_DELTA_OK, LIST_DELTA_FLOCKS],
  }])
  const result = results[0]
  const calls = result?.allToolCalls ?? []
  const correctTool = calls.some((c) =>
    c.name === 'resolve_customer_flock' || c.name === 'list_customer_flocks'
  )
  const arabicReply = containsArabic(result?.finalReply ?? '')
  return {
    name:
      '6. Arabic / Egyptian Arabic (correct tool selection AND an Arabic reply)',
    pass: correctTool && arabicReply,
    evidence:
      `tools called: ${calls.map((c) => c.name).join(', ') || 'none'}; ` +
      `reply: "${result?.finalReply ?? ''}"`,
  }
}

async function check7MultiTurnContext(
  options: RunTurnOnceOptions,
): Promise<CheckResult> {
  const { results } = await runProbeTurn(options, [
    {
      userText: 'عميل النيل عنده كام flock؟',
      toolStubs: [RESOLVE_NILE_OK, LIST_NILE_FLOCKS],
    },
    { userText: 'تخزين البيض فترة طويلة بيأثر إزاي على الفقس؟' },
    {
      userText: 'طيب أكبر واحد فيهم عمره كام؟',
      toolStubs: [LIST_NILE_FLOCKS, GET_FLOCK_3_CONTEXT],
    },
  ])
  const turn3 = results[2]
  const statesAge = /46|٤٦/.test(turn3?.finalReply ?? '')
  const reAsksForCustomer = /أي عميل|لأي عميل|which customer|اسم العميل/i.test(
    turn3?.finalReply ?? '',
  )
  const pass = results.length === 3 && statesAge && !reAsksForCustomer
  return {
    name:
      "7. multi-turn context (turn 1's fact used in turn 3, without re-asking)",
    pass,
    evidence: `turns completed: ${results.length}/3; turn 3 reply: "${
      turn3?.finalReply ?? ''
    }"`,
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const args = parseArgs(Deno.args)
  const apiKey = await requireOpenRouterApiKey()

  const options: RunTurnOnceOptions = {
    model: args.model,
    apiKey,
    temperature: args.temperature,
    seed: args.seed,
    reasoningEffort: args.reasoningEffort,
  }

  console.log(`Model under probe: ${args.model}`)
  console.log(
    `Temperature: ${args.temperature}, seed: ${args.seed}` +
      (args.reasoningEffort
        ? `, reasoning_effort: ${args.reasoningEffort}`
        : ''),
  )
  console.log(
    `Tool catalogue: ${AGENT_MODEL_TOOL_DEFINITIONS.length} tools (AGENT_MODEL_TOOL_DEFINITIONS)`,
  )
  console.log('')

  const allChecks: ReadonlyArray<
    { key: string; run: (options: RunTurnOnceOptions) => Promise<CheckResult> }
  > = [
    { key: 'instructions', run: check1InstructionHandling },
    { key: 'tool-definitions', run: check2ToolDefinitions },
    { key: 'sequential-tools', run: check3SequentialToolCalls },
    { key: 'synthesis', run: check4Synthesis },
    { key: 'structured-arguments', run: check5StructuredArguments },
    { key: 'arabic', run: check6Arabic },
    { key: 'multi-turn-context', run: check7MultiTurnContext },
  ]

  const checksToRun = args.filter
    ? allChecks.filter((c) => c.key.includes(args.filter!.toLowerCase()))
    : allChecks

  if (checksToRun.length === 0) {
    console.error(`No check matched filter "${args.filter}".`)
    Deno.exit(1)
  }

  const results: CheckResult[] = []
  for (const check of checksToRun) {
    const result = await check.run(options)
    results.push(result)
    console.log(`${result.pass ? 'PASS' : 'FAIL'}  ${result.name}`)
    console.log(`      evidence: ${result.evidence}`)
    console.log('')
  }

  const passed = results.filter((r) => r.pass).length
  console.log('='.repeat(100))
  console.log(
    `${passed}/${results.length} compatibility checks passed for ${args.model}`,
  )
  console.log('='.repeat(100))

  Deno.exit(results.every((r) => r.pass) ? 0 : 1)
}

if (import.meta.main) {
  main()
}
