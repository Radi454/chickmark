// Candidate OpenRouter models for the Pip text-agent COST/QUALITY
// COMPARISON suite (`comparison_scenarios.ts` + `run_comparison.ts`).
//
// This is a separate, on-demand suite from the single-model acceptance
// harness (`scenarios.ts` + `run_evals.ts` + `run_probe.ts`) already in this
// directory. That harness already answered "is a specific model fit to be
// the default at all"; this suite answers a different question -- "of
// several PAID candidates that all pass the basic bar, which is the
// cheapest one that still meets our reliability bar" -- by running the
// IDENTICAL scenario set against every candidate and diffing the result.
//
// Pricing below (USD per 1,000,000 tokens, as OpenRouter itself reports it)
// was VERIFIED BY HAND against https://openrouter.ai/api/v1/models on
// 2026-08-19. All five ids are non-free variants (no ":free" suffix) and
// each advertised "tools" in its `supported_parameters` at that time, i.e.
// each can in principle drive `AGENT_MODEL_TOOL_DEFINITIONS`'s
// function-calling shape (`agent_client.ts` still owns the ACTUAL /v1/responses
// transport this suite drives -- this file is metadata only, never a second
// implementation of the request shape).
//
// This table is a SNAPSHOT, not a source of truth held to be permanently
// accurate: models get repriced or deprecated. `run_comparison.ts` calls
// `verifyModelsAgainstOpenRouter` at startup and ABORTS LOUDLY (before
// spending a cent) if a candidate id has vanished from the live endpoint, no
// longer advertises "tools", or its live pricing has drifted from this table
// by more than `PRICE_TOLERANCE_RATIO`.

export interface CandidateModel {
  readonly id: string
  readonly label: string
  readonly contextTokens: number
  readonly usdPerMillionInput: number
  readonly usdPerMillionOutput: number
  readonly usdPerMillionCacheRead: number
  /** `google/gemma-4-31b-it` -- the model already live in production
   * (`resolveOpenRouterTextModels` in `_shared/pip_model_routing.ts`),
   * included here as the point of comparison, not because it is cheapest. */
  readonly isBaseline?: boolean
}

export const PRICING_VERIFIED_AT = '2026-08-19'
export const OPENROUTER_MODELS_ENDPOINT = 'https://openrouter.ai/api/v1/models'

export const CANDIDATE_MODELS: readonly CandidateModel[] = [
  {
    id: 'openai/gpt-oss-20b',
    label: 'gpt-oss-20b',
    contextTokens: 131_072,
    usdPerMillionInput: 0.030,
    usdPerMillionOutput: 0.130,
    usdPerMillionCacheRead: 0.030,
  },
  {
    id: 'openai/gpt-oss-120b',
    label: 'gpt-oss-120b',
    contextTokens: 131_072,
    usdPerMillionInput: 0.030,
    usdPerMillionOutput: 0.170,
    usdPerMillionCacheRead: 0.030,
  },
  {
    id: 'qwen/qwen3-30b-a3b-instruct-2507',
    label: 'qwen3-30b-a3b-instruct',
    contextTokens: 262_144,
    usdPerMillionInput: 0.048,
    usdPerMillionOutput: 0.193,
    usdPerMillionCacheRead: 0.000,
  },
  {
    id: 'deepseek/deepseek-v4-flash-0731',
    label: 'deepseek-v4-flash',
    contextTokens: 1_310_720,
    usdPerMillionInput: 0.140,
    usdPerMillionOutput: 0.280,
    usdPerMillionCacheRead: 0.028,
  },
  {
    id: 'google/gemma-4-31b-it',
    label: 'gemma-4-31b-it (production baseline)',
    contextTokens: 262_144,
    // Re-verified against the live catalogue on 2026-08-20: OpenRouter raised
    // this model's input price 0.09 -> 0.10 $/M and DOUBLED its cache-read
    // price 0.05 -> 0.10 $/M since the 2026-08-19 snapshot. The cache-read
    // rise matters more than it looks: this suite reads ~1.4M cached input
    // tokens per full run, so the baseline's real cost per 1000 Pip turns
    // moves up, not down. Left as the baseline; the number is simply worse.
    usdPerMillionInput: 0.100,
    usdPerMillionOutput: 0.340,
    usdPerMillionCacheRead: 0.100,
    isBaseline: true,
  },
]

export function defaultModelIds(): readonly string[] {
  return CANDIDATE_MODELS.map((model) => model.id)
}

export function findCandidateModel(id: string): CandidateModel | undefined {
  return CANDIDATE_MODELS.find((model) => model.id === id)
}

// ---------------------------------------------------------------------------
// Live re-verification
// ---------------------------------------------------------------------------

export interface ModelVerificationIssue {
  readonly modelId: string
  readonly kind: 'missing' | 'pricing_or_capability_mismatch'
  readonly detail: string
}

interface OpenRouterModelsResponse {
  readonly data?: ReadonlyArray<{
    readonly id?: string
    readonly pricing?: {
      readonly prompt?: string
      readonly completion?: string
      readonly input_cache_read?: string
    }
    readonly supported_parameters?: readonly string[]
  }>
}

/**
 * Relative tolerance for comparing this table's USD-per-million prices
 * against OpenRouter's live USD-per-TOKEN pricing strings (e.g.
 * "0.00000003" for $0.030/M). 1% absorbs float/string round-trip noise
 * without masking a genuine reprice.
 */
const PRICE_TOLERANCE_RATIO = 0.01

/**
 * Fetches the live OpenRouter model catalogue and checks every entry in
 * `models` against it: does the id still exist, does it still advertise
 * "tools", and does its live pricing still match this table within
 * tolerance. Returns one issue per problem found (empty = everything still
 * matches). Throws only on a transport/HTTP failure talking to the models
 * endpoint itself -- a per-model mismatch is a returned issue, not a thrown
 * error, so the caller can decide whether to abort or just warn.
 */
export interface ModelVerificationReport {
  readonly issues: readonly ModelVerificationIssue[]
  /**
   * Ids (from `models`) whose live `supported_parameters` include
   * `reasoning_effort`. `run_comparison.ts` NEVER sets `reasoning_effort` for
   * ANY model (see its header's "Fairness" section) -- this list exists so
   * that asymmetry ("some of these models COULD take a reasoning_effort knob
   * we chose not to use") is stated explicitly in the report, per the task's
   * "DOCUMENT the asymmetry prominently" requirement, rather than silently
   * true of some models and not others.
   */
  readonly reasoningEffortSupportedIds: readonly string[]
}

export async function verifyModelsAgainstOpenRouter(
  models: readonly CandidateModel[],
  apiKey: string,
): Promise<ModelVerificationReport> {
  const response = await fetch(OPENROUTER_MODELS_ENDPOINT, {
    headers: { 'Authorization': `Bearer ${apiKey}` },
  })
  if (!response.ok) {
    throw new Error(
      `GET ${OPENROUTER_MODELS_ENDPOINT} failed: HTTP ${response.status}`,
    )
  }
  const payload = await response.json() as OpenRouterModelsResponse
  const byId = new Map(
    (payload.data ?? [])
      .filter((model): model is { id: string } & typeof model =>
        typeof model.id === 'string'
      )
      .map((model) => [model.id, model]),
  )

  const issues: ModelVerificationIssue[] = []
  const reasoningEffortSupportedIds: string[] = []
  for (const model of models) {
    const live = byId.get(model.id)
    if (!live) {
      issues.push({
        modelId: model.id,
        kind: 'missing',
        detail:
          `"${model.id}" was not found in the current ${OPENROUTER_MODELS_ENDPOINT} listing -- it may have been renamed, removed, or made free-only.`,
      })
      continue
    }
    const problems: string[] = []
    comparePricing(
      'input',
      toPerMillion(live.pricing?.prompt),
      model.usdPerMillionInput,
      problems,
    )
    comparePricing(
      'output',
      toPerMillion(live.pricing?.completion),
      model.usdPerMillionOutput,
      problems,
    )
    comparePricing(
      'cache-read',
      toPerMillion(live.pricing?.input_cache_read),
      model.usdPerMillionCacheRead,
      problems,
    )
    if (
      live.supported_parameters !== undefined &&
      !live.supported_parameters.includes('tools')
    ) {
      problems.push('no longer advertises "tools" in supported_parameters')
    }
    if (live.supported_parameters?.includes('reasoning_effort')) {
      reasoningEffortSupportedIds.push(model.id)
    }
    if (problems.length > 0) {
      issues.push({
        modelId: model.id,
        kind: 'pricing_or_capability_mismatch',
        detail: problems.join('; '),
      })
    }
  }
  return { issues, reasoningEffortSupportedIds }
}

function comparePricing(
  label: string,
  live: number | null,
  table: number,
  problems: string[],
): void {
  if (live === null) return
  if (withinTolerance(live, table)) return
  problems.push(`${label} $/M: table=${table} live=${live}`)
}

function toPerMillion(perTokenText: string | undefined): number | null {
  if (perTokenText === undefined) return null
  const perToken = Number(perTokenText)
  if (!Number.isFinite(perToken)) return null
  return perToken * 1_000_000
}

function withinTolerance(live: number, table: number): boolean {
  if (table === 0) return Math.abs(live) < 1e-9
  return Math.abs(live - table) / table <= PRICE_TOLERANCE_RATIO
}
