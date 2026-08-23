// ChickMark text-agent MODEL-VS-MODEL COST/QUALITY COMPARISON runner.
//
// Runs the IDENTICAL `comparison_scenarios.ts` suite against every candidate
// model in `models.ts`, over the REAL OpenRouter `/v1/responses` endpoint,
// using the REAL system prompt and tool catalogue (`agent_client.ts`), to
// decide which is the cheapest OpenRouter model that still meets our
// reliability bar. This is a SEPARATE tool from `run_evals.ts` (single-model
// acceptance) and costs real money -- it is NOT part of `deno test`.
//
//   deno run --allow-net --allow-env --allow-read --allow-write=/tmp \
//     evals/run_comparison.ts --models openai/gpt-oss-20b --repeats 1 \
//     --filter brevity --max-cost 0.10 --json /tmp/comparison.json
//
// Options:
//   --models a,b,c        Comma-separated OpenRouter model ids. Default: all
//                          five candidates in `models.ts` (CANDIDATE_MODELS).
//   --repeats N            How many times to run EACH scenario per model.
//                          Default 3 -- temperature 0 does not guarantee
//                          determinism across providers/models in practice
//                          (observed: the same model chose different tools
//                          across runs at temperature 0), so a single sample
//                          cannot distinguish a genuine defect from noise.
//   --filter <substring>   Only run scenarios whose id, title, or dimension
//                          key contains the substring (case-insensitive).
//   --json <path>          Write full per-run machine-readable detail here
//                          (never the API key) so the run can be re-analysed
//                          without re-spending. Needs a matching --allow-write.
//   --max-cost <usd>       Abort cleanly with a partial report once
//                          cumulative REPORTED OpenRouter cost reaches this.
//                          Default 2.00 (account has ~$4.80 total).
//
// Determinism / fairness: every model gets the identical temperature (0),
// seed (20260819), max_output_tokens (2400, from agent_client.ts, matching
// production), tool catalogue, and instructions. `reasoning_effort` is
// NEVER set by this runner for ANY model, even for a candidate whose live
// catalogue entry advertises support for it -- the task is explicit that
// setting it for some models and not others would be an unfair asymmetry,
// and this suite has no principled per-model "correct" effort level to pick.
// Which candidates COULD take that knob (and therefore run this suite with
// it deliberately left on the table) is printed at startup and is exactly
// the asymmetry the task requires documenting -- see the
// "Fairness note:" line printed after model re-verification, below.
//
// Retries: a transient transport error (network failure, 429, or 5xx) is
// retried with exponential backoff, capped at MAX_TRANSIENT_RETRIES. A
// scenario-repeat that still cannot complete is marked INCONCLUSIVE and
// EXCLUDED from every pass-rate metric -- it is reported separately so it is
// never misread as a model defect (this is exactly what happened with an
// earlier free-tier run: empty replies from 429s looked like model
// failures). A 404, or a 400 that looks like it is rejecting the request
// shape itself, is an ARCHITECTURE finding (see `describeHttpFailure` in
// `agent_client.ts`) and is never retried.
//
// Budget guard: cumulative REAL reported `cost` (from `/v1/responses`'s own
// `usage.cost`, never estimated) is checked before every scenario-repeat
// starts. Once it would exceed `--max-cost`, the run stops cleanly and
// prints whatever partial report it already has.
//
// See README.md's "Comparison suite" section for the full picture, and
// `docs/LIVING_SPEC.md`'s entry on this suite for how it relates to
// `run_evals.ts`.

import {
  AGENT_MODEL_TOOL_DEFINITIONS,
  buildEvalInstructions,
  createSession,
  type RoundUsage,
  runTurn,
  sumUsage,
  type TurnResult,
  validateToolArguments,
  ZERO_ROUND_USAGE,
} from './agent_client.ts'
import { requireOpenRouterApiKey } from './env.ts'
import {
  type CandidateModel,
  defaultModelIds,
  findCandidateModel,
  type ModelVerificationIssue,
  PRICING_VERIFIED_AT,
  verifyModelsAgainstOpenRouter,
} from './models.ts'
import {
  type AssertionOutcome,
  COMPARISON_DIMENSIONS,
  COMPARISON_SCENARIOS,
  type ComparisonDimension,
  type ComparisonScenario,
  expectedToolsFor,
} from './comparison_scenarios.ts'

const DEFAULT_SEED = 20260819
const DEFAULT_REPEATS = 3
const DEFAULT_MAX_COST_USD = 2.00
const MAX_TRANSIENT_RETRIES = 3
const RETRY_BACKOFF_BASE_MS = 1500
const INTER_ATTEMPT_DELAY_MS = 400

/**
 * Dimensions whose failing assertions constitute a "serious tool-call or
 * hallucination failure" per the task's hard gate. `tool_selection` and
 * `tool_arguments` are direct tool-call correctness; `hallucination_grounding`
 * is direct grounding correctness; `multi_turn` and `degradation_under_load`
 * scenarios in THIS suite are themselves built almost entirely out of
 * tool-call/grounding assertions (see comparison_scenarios.ts), so a failure
 * there is the same class of problem at depth, not a separate concern.
 */
const GATE_DIMENSIONS: ReadonlySet<ComparisonDimension> = new Set([
  'tool_selection',
  'tool_arguments',
  'hallucination_grounding',
  'multi_turn',
  'degradation_under_load',
])

/** Which weighted-score bucket each dimension's pass rate feeds. Documented
 * explicitly here (rather than left implicit) because the task's 5-bucket
 * formula names buckets, not dimensions, and this suite has 9 dimensions --
 * this is the one place that mapping is decided. */
const SCORE_BUCKET_OF: Record<ComparisonDimension, ScoreBucket> = {
  tool_selection: 'toolCorrectness',
  tool_arguments: 'toolCorrectness',
  multi_turn: 'toolCorrectness',
  degradation_under_load: 'toolCorrectness',
  hallucination_grounding: 'grounding',
  arabic_understanding: 'arabic',
  progressive_disclosure: 'scopeAndBrevity',
  brevity: 'scopeAndBrevity',
  tool_result_reasoning: 'scopeAndBrevity',
}

type ScoreBucket =
  | 'toolCorrectness'
  | 'grounding'
  | 'arabic'
  | 'scopeAndBrevity'

const SCORE_WEIGHTS: Record<ScoreBucket | 'latency' | 'cost', number> = {
  toolCorrectness: 0.30,
  grounding: 0.20,
  arabic: 0.20,
  scopeAndBrevity: 0.15,
  latency: 0.10,
  cost: 0.05,
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

interface CliArgs {
  readonly models: readonly string[]
  readonly repeats: number
  readonly filter?: string
  readonly jsonPath?: string
  readonly maxCostUsd: number
}

function parseArgs(argv: readonly string[]): CliArgs {
  let models: readonly string[] = defaultModelIds()
  let repeats = DEFAULT_REPEATS
  let filter: string | undefined
  let jsonPath: string | undefined
  let maxCostUsd = DEFAULT_MAX_COST_USD

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--models') models = splitCsv(argv[++i])
    else if (arg.startsWith('--models=')) {
      models = splitCsv(arg.slice('--models='.length))
    } else if (arg === '--repeats') repeats = Number(argv[++i])
    else if (arg.startsWith('--repeats=')) {
      repeats = Number(arg.slice('--repeats='.length))
    } else if (arg === '--filter') filter = argv[++i]
    else if (arg.startsWith('--filter=')) {
      filter = arg.slice('--filter='.length)
    } else if (arg === '--json') jsonPath = argv[++i]
    else if (arg.startsWith('--json=')) jsonPath = arg.slice('--json='.length)
    else if (arg === '--max-cost') maxCostUsd = Number(argv[++i])
    else if (arg.startsWith('--max-cost=')) {
      maxCostUsd = Number(arg.slice('--max-cost='.length))
    }
  }

  if (models.length === 0) {
    console.error('No models given. Example: --models openai/gpt-oss-20b')
    Deno.exit(1)
  }
  if (!Number.isFinite(repeats) || repeats < 1) {
    console.error(
      `Invalid --repeats "${repeats}" -- must be a positive integer.`,
    )
    Deno.exit(1)
  }
  if (!Number.isFinite(maxCostUsd) || maxCostUsd <= 0) {
    console.error(
      `Invalid --max-cost "${maxCostUsd}" -- must be a positive number.`,
    )
    Deno.exit(1)
  }
  return { models, repeats, filter, jsonPath, maxCostUsd }
}

function splitCsv(text: string | undefined): readonly string[] {
  return (text ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0)
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function matchesFilter(scenario: ComparisonScenario, filter?: string): boolean {
  if (!filter) return true
  const needle = filter.toLowerCase()
  return scenario.id.toLowerCase().includes(needle) ||
    scenario.title.toLowerCase().includes(needle) ||
    scenario.dimension.toLowerCase().includes(needle)
}

// ---------------------------------------------------------------------------
// Per-attempt run detail
// ---------------------------------------------------------------------------

interface TurnRunDetail {
  readonly label: string
  readonly userText: string
  readonly replyText: string
  readonly toolCalls: ReadonlyArray<
    { name: string; arguments: Record<string, unknown> }
  >
  readonly malformedToolCalls: readonly string[]
  readonly unnecessaryToolCalls: readonly string[]
  readonly assertionResults: readonly AssertionOutcome[]
  readonly usage: RoundUsage
  readonly latencyMs: number
  readonly questionMarkCount: number
  readonly charCount: number
}

interface ScenarioAttempt {
  readonly scenarioId: string
  readonly dimension: ComparisonDimension
  readonly repeatIndex: number
  readonly status: 'completed' | 'inconclusive'
  readonly inconclusiveReason?: string
  readonly turns: readonly TurnRunDetail[]
  /** Every assertion in every turn passed. Meaningless (and always false)
   * when `status !== 'completed'`. */
  readonly allAssertionsPassed: boolean
}

const QUESTION_MARK_PATTERN = /[?؟]/g

async function runOneAttempt(
  apiKey: string,
  model: string,
  scenario: ComparisonScenario,
  repeatIndex: number,
  architectureFindings: string[],
): Promise<ScenarioAttempt> {
  for (let attempt = 1; attempt <= MAX_TRANSIENT_RETRIES + 1; attempt++) {
    const instructions = buildEvalInstructions()
    const session = createSession({
      apiKey,
      model,
      instructions,
      tools: AGENT_MODEL_TOOL_DEFINITIONS,
      temperature: 0,
      seed: DEFAULT_SEED,
      // Deliberately never set: see "Determinism / fairness" in the file
      // header. Every model, every scenario, every repeat gets the same
      // omission.
    })

    const turns: TurnRunDetail[] = []
    let transientDetail: string | null = null

    for (const turnSpec of scenario.turns) {
      const startedAt = performance.now()
      const result: TurnResult = await runTurn(
        session,
        turnSpec.userText,
        turnSpec.toolStubs ?? [],
      )
      const latencyMs = performance.now() - startedAt

      if (result.status === 'transport_error') {
        if (result.transportKind === 'architecture') {
          architectureFindings.push(
            `${model} / ${scenario.id} / ${
              turnSpec.label ?? `turn ${turns.length + 1}`
            }: ${result.transportDetail ?? '(no detail)'}`,
          )
          return {
            scenarioId: scenario.id,
            dimension: scenario.dimension,
            repeatIndex,
            status: 'inconclusive',
            inconclusiveReason: `architecture: ${result.transportDetail ?? ''}`,
            turns,
            allAssertionsPassed: false,
          }
        }
        // `'rejected'` (a non-2xx that is neither 429/5xx nor a
        // structural/architecture shape -- e.g. a genuine 400 unrelated to
        // request shape) is NOT retried: per the task, only 429/5xx/transport
        // errors get backoff retries. Retrying a rejection that will not
        // change on retry would just waste calls and money. It is marked
        // inconclusive immediately, distinctly from a transient exhaustion.
        if (result.transportKind !== 'transient') {
          return {
            scenarioId: scenario.id,
            dimension: scenario.dimension,
            repeatIndex,
            status: 'inconclusive',
            inconclusiveReason: `rejected (not retried): ${
              result.transportDetail ?? ''
            }`,
            turns,
            allAssertionsPassed: false,
          }
        }
        transientDetail = `${result.transportKind}: ${
          result.transportDetail ?? ''
        }`
        break
      }

      const text = result.finalReply
      const allowed = expectedToolsFor(scenario)
      const malformed = result.allToolCalls
        .filter((call) =>
          !validateToolArguments(call.name, call.arguments).valid
        )
        .map((call) => call.name)
      const unnecessary = allowed
        ? result.allToolCalls
          .filter((call) => !allowed.includes(call.name))
          .map((call) => call.name)
        : []

      const assertionResults = turnSpec.assertions.map((assertion) =>
        assertion(result)
      )
      // Same convention as run_evals.ts: an empty/invalid reply would
      // trivially satisfy a mustNotMatch/maxChars assertion, silently
      // misreporting a model failure as a pass -- surface it as its own
      // (scored) outcome.
      const repliedOutcome: AssertionOutcome = {
        pass: result.status === 'replied' && text.trim().length > 0,
        label: 'modelReplied',
        detail: result.status === 'replied'
          ? 'ok'
          : `status="${result.status}"`,
      }

      turns.push({
        label: turnSpec.label ?? `turn ${turns.length + 1}`,
        userText: turnSpec.userText,
        replyText: text,
        toolCalls: result.allToolCalls.map((c) => ({
          name: c.name,
          arguments: c.arguments,
        })),
        malformedToolCalls: malformed,
        unnecessaryToolCalls: unnecessary,
        assertionResults: [repliedOutcome, ...assertionResults],
        usage: result.usage,
        latencyMs,
        questionMarkCount: (text.match(QUESTION_MARK_PATTERN) ?? []).length,
        charCount: text.length,
      })
    }

    if (transientDetail === null) {
      const allPassed = turns.every((t) =>
        t.assertionResults.every((r) => r.pass)
      )
      return {
        scenarioId: scenario.id,
        dimension: scenario.dimension,
        repeatIndex,
        status: 'completed',
        turns,
        allAssertionsPassed: allPassed,
      }
    }

    if (attempt <= MAX_TRANSIENT_RETRIES) {
      const backoff = RETRY_BACKOFF_BASE_MS * 2 ** (attempt - 1)
      console.error(
        `[warn] ${model} / ${scenario.id} (repeat ${
          repeatIndex + 1
        }): transient error on attempt ${attempt} (${transientDetail}), retrying in ${backoff}ms...`,
      )
      await sleep(backoff)
      continue
    }
    return {
      scenarioId: scenario.id,
      dimension: scenario.dimension,
      repeatIndex,
      status: 'inconclusive',
      inconclusiveReason:
        `transient, exhausted ${MAX_TRANSIENT_RETRIES} retries: ${transientDetail}`,
      turns,
      allAssertionsPassed: false,
    }
  }
  // Unreachable -- the loop above always returns.
  throw new Error('unreachable')
}

function attemptCost(attempt: ScenarioAttempt): number {
  return attempt.turns.reduce((sum, t) => sum + (t.usage.costUsd ?? 0), 0)
}

// ---------------------------------------------------------------------------
// Per-model metrics
// ---------------------------------------------------------------------------

interface DimensionMetric {
  readonly dimension: ComparisonDimension
  readonly assertionsPassed: number
  readonly assertionsTotal: number
  readonly passRate: number
  readonly scenariosFlapping: number
}

interface ModelMetrics {
  readonly model: string
  readonly scenariosRun: number
  readonly scenariosCompleted: number
  readonly scenariosInconclusive: number
  readonly repeatsCompleted: number
  /** Excluded from `overallPassRate` and every dimension's `passRate` --
   * reported separately per the task ("mark it INCONCLUSIVE and exclude it
   * from pass rates -- report the count separately"). */
  readonly repeatsInconclusive: number
  readonly inconclusiveReasons: readonly string[]
  readonly repeatsAllPassed: number
  readonly overallPassRate: number
  readonly dimensions: readonly DimensionMetric[]
  readonly toolArgumentGlobalValidityRate: number
  readonly malformedToolCallCount: number
  readonly unnecessaryToolCallCount: number
  readonly totalToolCalls: number
  readonly hallucinationFailureCount: number
  readonly latenciesMs: readonly number[]
  readonly meanLatencyMs: number
  readonly p50LatencyMs: number
  readonly p95LatencyMs: number
  readonly totalInputTokens: number
  readonly totalOutputTokens: number
  readonly totalReasoningTokens: number
  readonly totalCachedTokens: number
  readonly totalCostUsd: number
  readonly totalTurns: number
  readonly totalRounds: number
  readonly roundsPerTurnRatio: number
  readonly costPer1000Turns: number
  readonly gatePassed: boolean
  readonly gateFailureExamples: readonly string[]
}

function percentile(sorted: readonly number[], p: number): number {
  if (sorted.length === 0) return 0
  const index = Math.min(
    sorted.length - 1,
    Math.floor((p / 100) * sorted.length),
  )
  return sorted[index]
}

function computeModelMetrics(
  model: string,
  attempts: readonly ScenarioAttempt[],
): ModelMetrics {
  const completed = attempts.filter((a) => a.status === 'completed')
  const inconclusive = attempts.filter((a) => a.status === 'inconclusive')
  const scenarioIds = new Set(attempts.map((a) => a.scenarioId))

  const dimensions: DimensionMetric[] = COMPARISON_DIMENSIONS.map((
    { key },
  ) => {
    const dimAttempts = completed.filter((a) => a.dimension === key)
    const scored = dimAttempts.flatMap((a) =>
      a.turns.flatMap((t) =>
        t.assertionResults.filter((r) => r.label !== 'modelReplied')
      )
    )
    const passed = scored.filter((r) => r.pass).length
    // Flapping: a scenario in this dimension whose per-repeat
    // allAssertionsPassed rate is neither 0 nor 1 -- a genuine defect fails
    // every time; noise flips between attempts.
    const byScenario = new Map<string, ScenarioAttempt[]>()
    for (const a of dimAttempts) {
      const list = byScenario.get(a.scenarioId) ?? []
      list.push(a)
      byScenario.set(a.scenarioId, list)
    }
    let flapping = 0
    for (const list of byScenario.values()) {
      const passRate = list.filter((a) => a.allAssertionsPassed).length /
        list.length
      if (passRate > 0 && passRate < 1) flapping++
    }
    return {
      dimension: key,
      assertionsPassed: passed,
      assertionsTotal: scored.length,
      passRate: scored.length === 0 ? 0 : passed / scored.length,
      scenariosFlapping: flapping,
    }
  })

  const allScoredAssertions = completed.flatMap((a) =>
    a.turns.flatMap((t) =>
      t.assertionResults.filter((r) => r.label !== 'modelReplied')
    )
  )
  const overallPassed = allScoredAssertions.filter((r) => r.pass).length

  const allToolCalls = completed.flatMap((a) =>
    a.turns.flatMap((t) => t.toolCalls)
  )
  const malformedCount =
    completed.flatMap((a) => a.turns.flatMap((t) => t.malformedToolCalls))
      .length
  const unnecessaryCount =
    completed.flatMap((a) => a.turns.flatMap((t) => t.unnecessaryToolCalls))
      .length

  const hallucinationFailures = completed
    .filter((a) => a.dimension === 'hallucination_grounding')
    .flatMap((a) =>
      a.turns.flatMap((t) =>
        t.assertionResults.filter((r) => r.label !== 'modelReplied' && !r.pass)
      )
    ).length

  const latencies = completed.flatMap((a) => a.turns.map((t) => t.latencyMs))
    .sort((x, y) => x - y)
  const meanLatency = latencies.length === 0
    ? 0
    : latencies.reduce((s, v) => s + v, 0) / latencies.length

  const usages = completed.flatMap((a) => a.turns.map((t) => t.usage))
  const summedUsage = sumUsage(usages)
  const totalTurns = completed.reduce((s, a) => s + a.turns.length, 0)
  // A "round" is one /v1/responses request/response pair. agent_client.ts
  // does not expose a round count directly on TurnResult's public surface
  // used here beyond `usage`, so the ratio is approximated from tool-call
  // volume: every tool call implies at least one extra round beyond the
  // turn's first, and every turn has exactly one first round.
  const totalRounds = totalTurns +
    completed.reduce(
      (s, a) => s + a.turns.reduce((ts, t) => ts + t.toolCalls.length, 0),
      0,
    )
  const roundsPerTurnRatio = totalTurns === 0 ? 1 : totalRounds / totalTurns
  const totalCost = summedUsage.costUsd ?? 0
  const avgCostPerRound = totalRounds === 0 ? 0 : totalCost / totalRounds
  const costPer1000Turns = avgCostPerRound * roundsPerTurnRatio * 1000

  const gateFailures = completed
    .filter((a) => GATE_DIMENSIONS.has(a.dimension) && !a.allAssertionsPassed)
  const gateFailureExamples = gateFailures.slice(0, 5).map((a) =>
    `${a.scenarioId} (repeat ${a.repeatIndex + 1})`
  )

  return {
    model,
    scenariosRun: scenarioIds.size,
    scenariosCompleted: new Set(completed.map((a) => a.scenarioId)).size,
    scenariosInconclusive: new Set(inconclusive.map((a) => a.scenarioId)).size,
    repeatsCompleted: completed.length,
    repeatsInconclusive: inconclusive.length,
    inconclusiveReasons: inconclusive
      .slice(0, 10)
      .map((a) =>
        `${a.scenarioId} (repeat ${a.repeatIndex + 1}): ${
          a.inconclusiveReason ?? 'unknown'
        }`
      ),
    repeatsAllPassed: completed.filter((a) => a.allAssertionsPassed).length,
    overallPassRate: allScoredAssertions.length === 0
      ? 0
      : overallPassed / allScoredAssertions.length,
    dimensions,
    toolArgumentGlobalValidityRate: allToolCalls.length === 0
      ? 1
      : 1 - malformedCount / allToolCalls.length,
    malformedToolCallCount: malformedCount,
    unnecessaryToolCallCount: unnecessaryCount,
    totalToolCalls: allToolCalls.length,
    hallucinationFailureCount: hallucinationFailures,
    latenciesMs: latencies,
    meanLatencyMs: meanLatency,
    p50LatencyMs: percentile(latencies, 50),
    p95LatencyMs: percentile(latencies, 95),
    totalInputTokens: summedUsage.inputTokens ?? 0,
    totalOutputTokens: summedUsage.outputTokens ?? 0,
    totalReasoningTokens: summedUsage.reasoningTokens ?? 0,
    totalCachedTokens: summedUsage.cachedTokens ?? 0,
    totalCostUsd: totalCost,
    totalTurns,
    totalRounds,
    roundsPerTurnRatio,
    costPer1000Turns,
    gatePassed: gateFailures.length === 0,
    gateFailureExamples,
  }
}

function dimensionRate(
  metrics: ModelMetrics,
  dimension: ComparisonDimension,
): number {
  return metrics.dimensions.find((d) => d.dimension === dimension)
    ?.passRate ?? 0
}

function bucketRate(metrics: ModelMetrics, bucket: ScoreBucket): number {
  const dims = (Object.keys(SCORE_BUCKET_OF) as ComparisonDimension[])
    .filter((d) => SCORE_BUCKET_OF[d] === bucket)
  const rates = dims.map((d) => dimensionRate(metrics, d))
  return rates.length === 0
    ? 0
    : rates.reduce((s, r) => s + r, 0) / rates.length
}

interface ScoredModel {
  readonly metrics: ModelMetrics
  readonly weightedScore: number
  readonly bucketScores: Record<ScoreBucket | 'latency' | 'cost', number>
}

/** Cross-model normalization for latency and cost: the fastest/cheapest
 * model in THIS run scores 1.0 on that axis, others scaled down
 * proportionally. Computed only across models that actually completed at
 * least one scenario (a model with zero data cannot anchor or be scored on
 * these axes meaningfully). */
function scoreModels(allMetrics: readonly ModelMetrics[]): ScoredModel[] {
  const withData = allMetrics.filter((m) => m.repeatsCompleted > 0)
  const minLatency = Math.min(
    ...withData.map((m) => m.meanLatencyMs || Infinity),
  )
  const minCost = Math.min(
    ...withData.map((m) => m.costPer1000Turns || Infinity),
  )

  return allMetrics.map((metrics) => {
    const toolCorrectness = bucketRate(metrics, 'toolCorrectness')
    const grounding = bucketRate(metrics, 'grounding')
    const arabic = bucketRate(metrics, 'arabic')
    const scopeAndBrevity = bucketRate(metrics, 'scopeAndBrevity')
    const latencyScore =
      metrics.meanLatencyMs > 0 && Number.isFinite(minLatency)
        ? Math.min(1, minLatency / metrics.meanLatencyMs)
        : 0
    const costScore = metrics.costPer1000Turns > 0 && Number.isFinite(minCost)
      ? Math.min(1, minCost / metrics.costPer1000Turns)
      : 0
    const bucketScores: Record<ScoreBucket | 'latency' | 'cost', number> = {
      toolCorrectness,
      grounding,
      arabic,
      scopeAndBrevity,
      latency: latencyScore,
      cost: costScore,
    }
    const weightedScore = (Object.keys(bucketScores) as Array<
      ScoreBucket | 'latency' | 'cost'
    >)
      .reduce(
        (sum, bucket) => sum + bucketScores[bucket] * SCORE_WEIGHTS[bucket],
        0,
      )
    return { metrics, weightedScore, bucketScores }
  })
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

function money(n: number): string {
  return `$${n.toFixed(4)}`
}

function pct(n: number): string {
  return `${(n * 100).toFixed(1)}%`
}

function printModelTable(scored: readonly ScoredModel[]): void {
  console.log('')
  console.log('='.repeat(120))
  console.log('COMPARISON TABLE')
  console.log('='.repeat(120))
  const header = 'MODEL'.padEnd(38) + 'GATE'.padEnd(6) + 'SCORE'.padEnd(8) +
    'PASS%'.padEnd(8) + 'ARABIC%'.padEnd(9) + 'GROUND%'.padEnd(9) +
    'MEAN_MS'.padEnd(9) + 'P95_MS'.padEnd(9) + '$/1000turns'.padEnd(13) +
    'TOTAL$'.padEnd(10) + 'INCONCL'
  console.log(header)
  for (
    const { metrics, weightedScore, bucketScores } of [...scored].sort((
      a,
      b,
    ) => b.weightedScore - a.weightedScore)
  ) {
    const gate = metrics.gatePassed ? 'PASS' : 'FAIL'
    console.log(
      metrics.model.padEnd(38) +
        gate.padEnd(6) +
        weightedScore.toFixed(3).padEnd(8) +
        pct(metrics.overallPassRate).padEnd(8) +
        pct(bucketScores.arabic).padEnd(9) +
        pct(bucketScores.grounding).padEnd(9) +
        metrics.meanLatencyMs.toFixed(0).padEnd(9) +
        metrics.p95LatencyMs.toFixed(0).padEnd(9) +
        money(metrics.costPer1000Turns).padEnd(13) +
        money(metrics.totalCostUsd).padEnd(10) +
        `${metrics.repeatsInconclusive} run(s) / ${metrics.scenariosInconclusive} scenario(s)`,
    )
  }
  console.log('')
  console.log(
    'GATE FAIL means at least one FAILED (not inconclusive) assertion in a gate ' +
      'dimension (tool_selection, tool_arguments, hallucination_grounding, multi_turn, ' +
      'degradation_under_load) -- this DISQUALIFIES the model regardless of SCORE.',
  )
  console.log(
    'INCONCL counts scenario-repeats that could not complete (transient transport ' +
      'failure exhausted its retries, or a rejected/architecture response) -- these are ' +
      'EXCLUDED from PASS%, GATE, and every dimension rate above, never counted as a ' +
      'model failure. See "INCONCLUSIVE DETAIL" below for reasons.',
  )
}

function printInconclusiveDetail(scored: readonly ScoredModel[]): void {
  const withInconclusive = scored.filter((s) =>
    s.metrics.repeatsInconclusive > 0
  )
  if (withInconclusive.length === 0) return
  console.log('')
  console.log('='.repeat(120))
  console.log('INCONCLUSIVE DETAIL (excluded from all pass-rate metrics above)')
  console.log('='.repeat(120))
  for (const { metrics } of withInconclusive) {
    console.log('')
    console.log(
      `${metrics.model}: ${metrics.repeatsInconclusive} scenario-repeat(s) inconclusive ` +
        `across ${metrics.scenariosInconclusive} distinct scenario(s):`,
    )
    for (const reason of metrics.inconclusiveReasons) {
      console.log(`  - ${reason}`)
    }
  }
}

function printDimensionBreakdown(scored: readonly ScoredModel[]): void {
  console.log('')
  console.log('='.repeat(120))
  console.log('PER-DIMENSION PASS RATES')
  console.log('='.repeat(120))
  for (const { metrics } of scored) {
    console.log('')
    console.log(`${metrics.model}:`)
    for (const dim of metrics.dimensions) {
      const flapNote = dim.scenariosFlapping > 0
        ? ` (${dim.scenariosFlapping} scenario(s) flapping across repeats)`
        : ''
      console.log(
        `  ${dim.dimension.padEnd(24)} ${
          `${dim.assertionsPassed}/${dim.assertionsTotal}`.padStart(9)
        }  ${pct(dim.passRate)}${flapNote}`,
      )
    }
  }
}

function printFailureExamples(
  attemptsByModel: ReadonlyMap<string, readonly ScenarioAttempt[]>,
): void {
  console.log('')
  console.log('='.repeat(120))
  console.log('REPRESENTATIVE FAILURE EXAMPLES (up to 3 per model)')
  console.log('='.repeat(120))
  for (const [model, attempts] of attemptsByModel) {
    const failing = attempts.filter((a) =>
      a.status === 'completed' && !a.allAssertionsPassed
    )
    console.log('')
    console.log(`${model}:`)
    if (failing.length === 0) {
      console.log('  (no failing scenario-repeats)')
      continue
    }
    for (const attempt of failing.slice(0, 3)) {
      console.log(
        `  --- ${attempt.scenarioId} (repeat ${attempt.repeatIndex + 1}) ---`,
      )
      for (const turn of attempt.turns) {
        console.log(`  prompt: ${turn.userText}`)
        console.log(
          `  tool calls: ${
            turn.toolCalls.length === 0
              ? '(none)'
              : turn.toolCalls.map((c) =>
                `${c.name}(${JSON.stringify(c.arguments)})`
              ).join(', ')
          }`,
        )
        console.log(`  reply: ${turn.replyText || '(empty)'}`)
        for (const outcome of turn.assertionResults) {
          if (!outcome.pass) {
            console.log(`    FAIL ${outcome.label}: ${outcome.detail ?? ''}`)
          }
        }
      }
    }
  }
}

interface JsonOutput {
  readonly ranAt: string
  readonly pricingVerifiedAt: string
  readonly cliArgs: CliArgs
  readonly scenarioCount: number
  readonly turnsPerRun: number
  readonly aborted: { readonly reason: string } | null
  readonly architectureFindings: readonly string[]
  readonly models: ReadonlyArray<{
    readonly model: string
    readonly metrics: ModelMetrics
    readonly weightedScore: number
    readonly bucketScores: Record<ScoreBucket | 'latency' | 'cost', number>
    readonly attempts: readonly ScenarioAttempt[]
  }>
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const args = parseArgs(Deno.args)
  const apiKey = await requireOpenRouterApiKey()

  const scenarios = COMPARISON_SCENARIOS.filter((s) =>
    matchesFilter(s, args.filter)
  )
  if (scenarios.length === 0) {
    console.error(`No scenario matched filter "${args.filter}".`)
    Deno.exit(1)
  }
  const turnsPerRun = scenarios.reduce((s, sc) => s + sc.turns.length, 0)

  console.log('ChickMark text-agent model comparison')
  console.log(`Models: ${args.models.join(', ')}`)
  console.log(
    `Repeats per scenario: ${args.repeats}. Scenarios matched: ${scenarios.length} ` +
      `(${turnsPerRun} turns each pass).`,
  )
  console.log(`Max cost: ${money(args.maxCostUsd)}`)
  console.log(
    `Fairness: temperature=0, seed=${DEFAULT_SEED}, max_output_tokens=2400 (from ` +
      'agent_client.ts, matching production), identical tool catalogue and ' +
      'instructions for every model. reasoning_effort is NEVER set for ANY model in ' +
      'this run -- see "Determinism / fairness" in run_comparison.ts\'s header.',
  )
  console.log('')

  // ---- Model catalogue re-verification (fail loudly, before spending) ----
  const candidates: CandidateModel[] = []
  for (const id of args.models) {
    const found = findCandidateModel(id)
    if (!found) {
      console.error(
        `"${id}" is not in models.ts's CANDIDATE_MODELS list. Add it there first ` +
          '(with pricing verified against https://openrouter.ai/api/v1/models) so ' +
          'this runner has cost metadata for it.',
      )
      Deno.exit(1)
    }
    candidates.push(found)
  }

  console.log(
    `Re-verifying ${candidates.length} candidate(s) against OpenRouter's live model ` +
      `catalogue (pricing table last hand-verified ${PRICING_VERIFIED_AT})...`,
  )
  let issues: readonly ModelVerificationIssue[]
  let reasoningEffortSupportedIds: readonly string[]
  try {
    const report = await verifyModelsAgainstOpenRouter(candidates, apiKey)
    issues = report.issues
    reasoningEffortSupportedIds = report.reasoningEffortSupportedIds
  } catch (error) {
    console.error(`Could not re-verify models against OpenRouter: ${error}`)
    Deno.exit(1)
  }
  if (issues.length > 0) {
    console.log('')
    console.log('!'.repeat(120))
    console.log(
      'MODEL VERIFICATION FAILED -- a candidate id has vanished, no longer supports ' +
        "tools, or its live pricing has drifted from models.ts's table. Aborting " +
        'BEFORE spending anything. Fix models.ts (or drop the affected id from --models) ' +
        'and re-run. Details:',
    )
    for (const issue of issues) {
      console.log(`  - [${issue.kind}] ${issue.modelId}: ${issue.detail}`)
    }
    console.log('!'.repeat(120))
    Deno.exit(1)
  }
  console.log('All candidates verified OK against the live catalogue.')
  if (reasoningEffortSupportedIds.length > 0) {
    console.log(
      `Fairness note: ${
        reasoningEffortSupportedIds.join(', ')
      } advertise(s) reasoning_effort support on the live catalogue. ` +
        'reasoning_effort is NOT set for ANY model in this run (see header) -- this is ' +
        'the asymmetry the task requires documenting: those models COULD take that knob, ' +
        'it is deliberately left unset here for cross-model fairness.',
    )
  } else {
    console.log(
      'None of the selected candidates advertise reasoning_effort support -- no asymmetry to document.',
    )
  }
  console.log('')

  // ---- Run ----
  let cumulativeCost = 0
  let aborted: { reason: string } | null = null
  const architectureFindings: string[] = []
  const attemptsByModel = new Map<string, ScenarioAttempt[]>()

  outer: for (const model of args.models) {
    const modelAttempts: ScenarioAttempt[] = []
    attemptsByModel.set(model, modelAttempts)
    console.log(`=== ${model} ===`)

    for (const scenario of scenarios) {
      for (let repeatIndex = 0; repeatIndex < args.repeats; repeatIndex++) {
        if (cumulativeCost >= args.maxCostUsd) {
          aborted = {
            reason:
              `cumulative cost ${money(cumulativeCost)} reached --max-cost ` +
              `${money(args.maxCostUsd)} before ${model} / ${scenario.id} ` +
              `(repeat ${repeatIndex + 1}) could run`,
          }
          console.log('')
          console.log(`[budget] ABORTING: ${aborted.reason}`)
          break outer
        }
        const attempt = await runOneAttempt(
          apiKey,
          model,
          scenario,
          repeatIndex,
          architectureFindings,
        )
        modelAttempts.push(attempt)
        cumulativeCost += attemptCost(attempt)
        const statusTag = attempt.status === 'inconclusive'
          ? 'INCONCLUSIVE'
          : (attempt.allAssertionsPassed ? 'PASS' : 'FAIL')
        console.log(
          `  ${statusTag.padEnd(13)} ${scenario.id} (repeat ${
            repeatIndex + 1
          }/${args.repeats})  [running cost: ${money(cumulativeCost)}]`,
        )
        await sleep(INTER_ATTEMPT_DELAY_MS)
      }
    }
  }

  if (architectureFindings.length > 0) {
    console.log('')
    console.log('!'.repeat(120))
    console.log(
      'ARCHITECTURE FINDING: /v1/responses rejected a request with a structural-looking ' +
        'status (404, or a request-shape 400) for at least one model. This is a BLOCKING ' +
        'finding about that model/endpoint pairing, not scenario signal. Details:',
    )
    for (const finding of architectureFindings) console.log(`  - ${finding}`)
    console.log('!'.repeat(120))
  }

  // ---- Metrics + scoring ----
  const allMetrics = args.models.map((model) =>
    computeModelMetrics(model, attemptsByModel.get(model) ?? [])
  )
  const scored = scoreModels(allMetrics)

  printModelTable(scored)
  printInconclusiveDetail(scored)
  printDimensionBreakdown(scored)
  printFailureExamples(attemptsByModel)

  console.log('')
  console.log('='.repeat(120))
  console.log('COST DERIVATION')
  console.log('='.repeat(120))
  for (const { metrics } of scored) {
    console.log(
      `${metrics.model}: ${metrics.totalTurns} turns measured, ` +
        `${metrics.totalRounds} /v1/responses calls (${
          metrics.roundsPerTurnRatio.toFixed(2)
        } calls/turn -- the turns-to-calls ratio used for the cost projection ` +
        `below), total real cost ${money(metrics.totalCostUsd)} => ` +
        `${money(metrics.costPer1000Turns)} per 1000 realistic Pip turns.`,
    )
  }
  console.log(
    'Caveat: this ratio and cost projection are specific to THIS scenario mix ' +
      '(a blend of single-lookup and multi-tool-chain turns across 9 dimensions) -- ' +
      'a production traffic mix with a different tool-chain-vs-lookup ratio will cost ' +
      'proportionally differently per 1000 turns.',
  )

  if (aborted) {
    console.log('')
    console.log(`RUN ABORTED (partial report above): ${aborted.reason}`)
  }

  if (args.jsonPath) {
    const jsonOutput: JsonOutput = {
      ranAt: new Date().toISOString(),
      pricingVerifiedAt: PRICING_VERIFIED_AT,
      cliArgs: args,
      scenarioCount: scenarios.length,
      turnsPerRun,
      aborted,
      architectureFindings,
      models: scored.map(({ metrics, weightedScore, bucketScores }) => ({
        model: metrics.model,
        metrics,
        weightedScore,
        bucketScores,
        attempts: attemptsByModel.get(metrics.model) ?? [],
      })),
    }
    await Deno.writeTextFile(
      args.jsonPath,
      JSON.stringify(jsonOutput, null, 2),
    )
    console.log('')
    console.log(`Wrote full machine-readable results to ${args.jsonPath}`)
  }

  const anyGateFail = allMetrics.some((m) =>
    m.repeatsCompleted > 0 && !m.gatePassed
  )
  Deno.exit(
    aborted || anyGateFail || architectureFindings.length > 0 ? 1 : 0,
  )
}

if (import.meta.main) {
  main()
}

// Re-exported for `--json` consumers and potential reuse -- kept at the
// bottom so the file reads top-down as CLI -> run -> metrics -> report.
export type { JsonOutput, ModelMetrics, ScenarioAttempt, ScoredModel }
export { ZERO_ROUND_USAGE }
