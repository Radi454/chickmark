// ChickMark text-agent model-acceptance eval suite.
//
// Talks to a REAL model over the REAL OpenRouter `/v1/responses` endpoint,
// using the REAL system prompt (`buildAgentInstructions`) and the REAL tool
// catalogue (`AGENT_MODEL_TOOL_DEFINITIONS`) -- see `agent_client.ts` for the
// exact request shape and why it is a faithful mirror of
// `createResponsesAgentProvider` in `agent_provider.ts`. This costs money and
// is NOT part of `deno test` -- run it on demand, once per candidate model:
//
//   export OPENROUTER_API_KEY="..."   # or place it in the repo's .env
//   deno run --allow-net --allow-env --allow-read evals/run_evals.ts \
//     --model google/gemma-4-31b-it:free
//   deno run --allow-net --allow-env --allow-read evals/run_evals.ts \
//     --model openai/gpt-oss-20b:free
//
// See README.md for the full picture: what each dimension means, how to
// read the scorecard, and why this suite is separate from `run_probe.ts`.
//
// Options:
//   --model <id>            REQUIRED. The OpenRouter model id to evaluate.
//   --filter <substring>    Only run scenarios whose id, title, or dimension
//                            key contains the substring (case-insensitive).
//   --debug                 Print each scenario's raw transport detail even
//                            on a pass, and the full session.input growth.
//   --json <path>            Also write the full machine-readable result set
//                            to this path, so it can be attached to a report.
//                            The API key is never written to this file.
//   --temperature <n>       Default 0 (deterministic).
//   --seed <n>               Default 20260819 (fixed, for models that honour it).
//   --reasoning-effort <low|medium|high>
//                            Only sent if given -- gpt-oss-20b:free supports
//                            it; gemma-4-31b-it:free does not accept it.
//
// A scenario turn that hits a transport error (network failure, or an HTTP
// status this harness treats as transient -- 429 or 5xx, see
// `isRetryableStatus` in agent_client.ts) is retried EXACTLY ONCE, and the
// retry is marked in the report so a flaky pass/fail is never silently
// indistinguishable from a clean one. A `404` or a request-shape-looking
// `400` is treated as an ARCHITECTURE finding instead (see
// `describeHttpFailure`) and is never retried -- retrying a structural
// rejection just wastes calls and time.

import {
  AGENT_MODEL_TOOL_DEFINITIONS,
  buildEvalInstructions,
  createSession,
  runTurn,
  type TurnResult,
} from './agent_client.ts'
import { requireOpenRouterApiKey } from './env.ts'
import {
  type AssertionOutcome,
  type Dimension,
  DIMENSIONS,
  finalText,
  SCENARIOS,
} from './scenarios.ts'

const DEFAULT_SEED = 20260819

interface CliArgs {
  readonly model: string
  readonly filter?: string
  readonly debug: boolean
  readonly jsonPath?: string
  readonly temperature: number
  readonly seed: number
  readonly reasoningEffort?: 'low' | 'medium' | 'high'
}

function parseArgs(argv: readonly string[]): CliArgs {
  let model: string | undefined
  let filter: string | undefined
  let debug = false
  let jsonPath: string | undefined
  let temperature = 0
  let seed = DEFAULT_SEED
  let reasoningEffort: 'low' | 'medium' | 'high' | undefined

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--model') {
      model = argv[++i]
    } else if (arg.startsWith('--model=')) {
      model = arg.slice('--model='.length)
    } else if (arg === '--filter') {
      filter = argv[++i]
    } else if (arg.startsWith('--filter=')) {
      filter = arg.slice('--filter='.length)
    } else if (arg === '--debug') {
      debug = true
    } else if (arg === '--json') {
      jsonPath = argv[++i]
    } else if (arg.startsWith('--json=')) {
      jsonPath = arg.slice('--json='.length)
    } else if (arg === '--temperature') {
      temperature = Number(argv[++i])
    } else if (arg.startsWith('--temperature=')) {
      temperature = Number(arg.slice('--temperature='.length))
    } else if (arg === '--seed') {
      seed = Number(argv[++i])
    } else if (arg.startsWith('--seed=')) {
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
      '  deno run --allow-net --allow-env --allow-read evals/run_evals.ts \\',
    )
    console.error('    --model google/gemma-4-31b-it:free')
    Deno.exit(1)
  }
  return { model, filter, debug, jsonPath, temperature, seed, reasoningEffort }
}

function matchesFilter(
  id: string,
  title: string,
  dimension: string,
  filter: string | undefined,
): boolean {
  if (!filter) return true
  const needle = filter.toLowerCase()
  return id.toLowerCase().includes(needle) ||
    title.toLowerCase().includes(needle) ||
    dimension.toLowerCase().includes(needle)
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

const INTER_SCENARIO_DELAY_MS = 1500

interface ReportRow {
  readonly scenarioId: string
  readonly dimension: Dimension
  readonly turnLabel: string
  readonly outcome: AssertionOutcome
  readonly replyText: string
  readonly retried: boolean
}

interface JsonResult {
  readonly model: string
  readonly ranAt: string
  readonly temperature: number
  readonly seed: number
  readonly reasoningEffort: string | null
  readonly toolCount: number
  readonly rows: ReadonlyArray<{
    scenarioId: string
    dimension: string
    turnLabel: string
    label: string
    pass: boolean
    detail: string | null
    replyText: string
    retried: boolean
  }>
  readonly dimensionSummary: ReadonlyArray<{
    dimension: string
    title: string
    passed: number
    total: number
  }>
  readonly totalPassed: number
  readonly totalAssertions: number
  readonly architectureFindings: readonly string[]
}

/**
 * Runs one scenario's turns in a single session (so context persists across
 * turns, same as a real conversation), retrying the WHOLE scenario exactly
 * once if any turn ends in a transient transport error. A retried scenario's
 * rows are all marked `retried: true` regardless of which turn actually
 * failed, since a partial retry would leave the session's `input` history in
 * an inconsistent state relative to a fresh run.
 */
async function runScenarioWithRetry(
  apiKey: string,
  args: CliArgs,
  scenario: (typeof SCENARIOS)[number],
  architectureFindings: string[],
): Promise<{ rows: ReportRow[]; retried: boolean }> {
  for (let attempt = 1; attempt <= 2; attempt++) {
    const instructions = buildEvalInstructions()
    const session = createSession({
      apiKey,
      model: args.model,
      instructions,
      tools: AGENT_MODEL_TOOL_DEFINITIONS,
      temperature: args.temperature,
      seed: args.seed,
      reasoningEffort: args.reasoningEffort,
    })

    const rows: ReportRow[] = []
    let transientFailure = false

    for (const turn of scenario.turns) {
      const result: TurnResult = await runTurn(
        session,
        turn.userText,
        turn.toolStubs ?? [],
      )
      const turnLabel = turn.label ?? `turn ${rows.length + 1}`

      if (result.status === 'transport_error') {
        if (result.transportKind === 'architecture') {
          architectureFindings.push(
            `${scenario.id} / ${turnLabel}: ${
              result.transportDetail ?? '(no detail)'
            }`,
          )
        }
        if (result.transportKind === 'transient' && attempt === 1) {
          transientFailure = true
          break
        }
        rows.push({
          scenarioId: scenario.id,
          dimension: scenario.dimension,
          turnLabel,
          outcome: {
            pass: false,
            label: 'transport',
            detail: `${result.transportKind ?? 'unknown'}: ${
              result.transportDetail ?? ''
            }`,
          },
          replyText: '',
          retried: attempt === 2,
        })
        // A transport failure means later turns in this scenario can't run
        // meaningfully either (the session's context is now missing a
        // reply), so stop the scenario here rather than compounding it.
        return { rows, retried: attempt === 2 }
      }

      const text = finalText(result)
      // An empty/invalid reply would trivially satisfy maxWords/mustNotMatch,
      // silently misreporting a model failure as a pass. Surface it as its
      // own row first, same convention as the pip-realtime-sideband harness.
      rows.push({
        scenarioId: scenario.id,
        dimension: scenario.dimension,
        turnLabel,
        outcome: {
          pass: result.status === 'replied' && text.trim().length > 0,
          label: 'modelReplied',
          detail: result.status === 'replied'
            ? 'ok'
            : `status="${result.status}" -- see DETAIL below`,
        },
        replyText: text,
        retried: attempt === 2,
      })

      for (const assertion of turn.assertions) {
        const outcome = assertion(result)
        rows.push({
          scenarioId: scenario.id,
          dimension: scenario.dimension,
          turnLabel,
          outcome,
          replyText: text,
          retried: attempt === 2,
        })
      }
    }

    if (!transientFailure) return { rows, retried: attempt === 2 }
    console.error(
      `[warn] ${scenario.id}: transient transport error on attempt ${attempt}, retrying once...`,
    )
    await sleep(2000)
  }
  // Unreachable in practice (the loop always returns on attempt 2), kept for
  // type-checking exhaustiveness.
  return { rows: [], retried: true }
}

function printScenarioTable(rows: readonly ReportRow[]): void {
  console.log('')
  console.log('='.repeat(100))
  console.log('RESULTS BY SCENARIO')
  console.log('='.repeat(100))
  const col1 = Math.max(8, ...rows.map((r) => r.scenarioId.length))
  const col2 = Math.max(4, ...rows.map((r) => r.turnLabel.length))
  for (const row of rows) {
    const status = row.outcome.pass ? 'PASS' : 'FAIL'
    const retriedTag = row.retried ? ' (retried)' : ''
    console.log(
      `${status.padEnd(5)} ${row.scenarioId.padEnd(col1)}  ${
        row.turnLabel.padEnd(col2)
      }  ${row.outcome.label}${retriedTag}`,
    )
  }

  console.log('')
  console.log('='.repeat(100))
  console.log('DETAIL (actual replies, failures only shown in full)')
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
}

function printDimensionScorecard(
  rows: readonly ReportRow[],
): ReadonlyArray<
  { dimension: string; title: string; passed: number; total: number }
> {
  console.log('')
  console.log('='.repeat(100))
  console.log('SCORECARD BY DIMENSION')
  console.log('='.repeat(100))
  const summary: Array<
    { dimension: string; title: string; passed: number; total: number }
  > = []
  for (const { key, title } of DIMENSIONS) {
    // Exclude the bookkeeping `modelReplied`/`transport` rows from the
    // per-dimension score -- those are infrastructure signal, not one of the
    // nine scored dimensions themselves.
    const dimensionRows = rows.filter((r) =>
      r.dimension === key && r.outcome.label !== 'modelReplied' &&
      r.outcome.label !== 'transport'
    )
    const passed = dimensionRows.filter((r) => r.outcome.pass).length
    const total = dimensionRows.length
    summary.push({ dimension: key, title, passed, total })
    const bar = total === 0 ? '(no scenarios ran)' : `${passed}/${total}`
    console.log(`  ${key.padEnd(28)} ${bar.padStart(7)}  ${title}`)
  }
  return summary
}

async function main(): Promise<void> {
  const args = parseArgs(Deno.args)
  const apiKey = await requireOpenRouterApiKey()

  console.log(`Model under test: ${args.model}`)
  console.log(
    `Temperature: ${args.temperature}, seed: ${args.seed}` +
      (args.reasoningEffort
        ? `, reasoning_effort: ${args.reasoningEffort}`
        : ''),
  )
  console.log(
    `Tool catalogue: ${AGENT_MODEL_TOOL_DEFINITIONS.length} tools (AGENT_MODEL_TOOL_DEFINITIONS)`,
  )
  if (args.filter) console.log(`Filter: "${args.filter}"`)
  console.log('')

  const scenariosToRun = SCENARIOS.filter((s) =>
    matchesFilter(s.id, s.title, s.dimension, args.filter)
  )
  if (scenariosToRun.length === 0) {
    console.error(`No scenario matched filter "${args.filter}".`)
    Deno.exit(1)
  }

  const rows: ReportRow[] = []
  const architectureFindings: string[] = []

  for (const [index, scenario] of scenariosToRun.entries()) {
    if (index > 0) await sleep(INTER_SCENARIO_DELAY_MS)
    console.log(
      `=== ${scenario.id} — ${scenario.title} [${scenario.dimension}] ===`,
    )
    if (scenario.note) console.log(`  note: ${scenario.note}`)
    const { rows: scenarioRows } = await runScenarioWithRetry(
      apiKey,
      args,
      scenario,
      architectureFindings,
    )
    rows.push(...scenarioRows)
    if (args.debug) {
      for (const row of scenarioRows) {
        console.log(
          `  [debug] ${row.turnLabel} / ${row.outcome.label}: ${
            row.outcome.pass ? 'PASS' : 'FAIL'
          }`,
        )
      }
    }
  }

  if (architectureFindings.length > 0) {
    console.log('')
    console.log('!'.repeat(100))
    console.log(
      'ARCHITECTURE FINDING: /v1/responses rejected a request with a structural-looking',
    )
    console.log(
      'status (404, or a request-shape 400). This is a BLOCKING finding, not a scenario',
    )
    console.log('failure -- see the task instructions. Details:')
    for (const finding of architectureFindings) console.log(`  - ${finding}`)
    console.log('!'.repeat(100))
  }

  printScenarioTable(rows)
  const dimensionSummary = printDimensionScorecard(rows)

  const scoredRows = rows.filter((r) => r.outcome.label !== 'modelReplied')
  const totalPassed = scoredRows.filter((r) => r.outcome.pass).length
  console.log('')
  console.log('='.repeat(100))
  console.log(
    `FINAL: ${totalPassed}/${scoredRows.length} assertions passed for ${args.model}`,
  )
  console.log('='.repeat(100))

  if (args.jsonPath) {
    const jsonResult: JsonResult = {
      model: args.model,
      ranAt: new Date().toISOString(),
      temperature: args.temperature,
      seed: args.seed,
      reasoningEffort: args.reasoningEffort ?? null,
      toolCount: AGENT_MODEL_TOOL_DEFINITIONS.length,
      rows: rows.map((row) => ({
        scenarioId: row.scenarioId,
        dimension: row.dimension,
        turnLabel: row.turnLabel,
        label: row.outcome.label,
        pass: row.outcome.pass,
        detail: row.outcome.detail ?? null,
        replyText: row.replyText,
        retried: row.retried,
      })),
      dimensionSummary,
      totalPassed,
      totalAssertions: scoredRows.length,
      architectureFindings,
    }
    await Deno.writeTextFile(args.jsonPath, JSON.stringify(jsonResult, null, 2))
    console.log(`Wrote machine-readable results to ${args.jsonPath}`)
  }

  const anyFail = rows.some((row) => !row.outcome.pass)
  Deno.exit(anyFail || architectureFindings.length > 0 ? 1 : 0)
}

if (import.meta.main) {
  main()
}
