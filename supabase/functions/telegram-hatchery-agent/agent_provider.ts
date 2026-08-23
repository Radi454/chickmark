import type { AgentToolDefinition } from './agent_tools.ts'
import { PIP_MODEL_DEFAULTS } from '../_shared/pip_model_routing.ts'

export type AgentModelInputItem = Record<string, unknown>
export type AgentModelOutputItem = Record<string, unknown>

export interface AgentModelRequest {
  instructions: string
  input: AgentModelInputItem[]
  tools: readonly AgentToolDefinition[]
  /**
   * Defaults to `'auto'`. `'none'` is the runtime's FINAL-ANSWER pass: the
   * turn has spent its tool budget, so the model is asked once more with the
   * catalogue withdrawn and tool calling forbidden, and must answer from what
   * it already has. Without it, a turn that runs out of tool budget has
   * nothing to return but a failure — see `runAgentTurn`.
   */
  toolChoice?: 'auto' | 'none'
}

/** One reason code from the fallback-eligibility table in `classifyProviderFailure`. */
export type ProviderFailureReason =
  | 'provider_transport_error'
  | 'attempt_timeout'
  | 'http_400_request_rejected'
  | 'http_402_payment_required'
  | 'http_404_model_unavailable'
  | 'http_408_request_timeout'
  | 'http_429_rate_limited'
  | 'http_5xx_provider_error'
  | 'provider_error_envelope'
  | 'malformed_response'
  | 'empty_output'

export interface AgentProviderTelemetry {
  provider: AgentProviderName
  /** What we asked for first. */
  requestedModel: string
  /** What actually answered: the reported model, else the id we sent. */
  actualModel: string
  fallbackOccurred: boolean
  /** One of the `ProviderFailureReason` codes above, or null if no fallback happened. */
  fallbackReason: string | null
  providerResponseId: string | null
  /** Wall clock across all attempts (primary, and the fallback if one ran). */
  latencyMs: number
  attempts: number
  /**
   * True when this call skipped the primary attempt entirely because a
   * PRIOR call on the same provider instance already saw the primary fail
   * for an eligible reason — see "sticky fallback" in
   * `createResponsesAgentProvider`. `fallbackReason` still names the
   * ORIGINAL reason that first engaged stickiness, not a re-classification
   * of this call (there was no primary attempt this call to classify).
   */
  sticky: boolean
  /**
   * True when this call's `input` was detected to carry visual content (see
   * `requestIsVisual`) and was therefore routed to `visionModel` instead of
   * the text `model`/`fallbackModel` pair. `requestedModel`/`actualModel`
   * report the vision model on this path, never the text primary.
   */
  visionRouted: boolean
}

export interface AgentModelResponse {
  id: string
  output: AgentModelOutputItem[]
  provider?: AgentProviderName
  model?: string
  telemetry?: AgentProviderTelemetry
}

export interface AgentProvider {
  respond(
    request: AgentModelRequest,
    options?: { signal?: AbortSignal },
  ): Promise<AgentModelResponse>
}

export type AgentProviderName = 'openai' | 'openrouter'

export interface ResponsesAgentProviderConfig {
  provider: AgentProviderName
  apiKey: string
  model?: string
  /**
   * The one-step fallback model. Only ever consulted when
   * `provider === 'openrouter'` — the fallback stays on OpenRouter by
   * design (see `resolveOpenRouterTextModels` in
   * `_shared/pip_model_routing.ts`); this phase never falls back to the
   * paid OpenAI API. Never used when absent, blank, or equal to `model`.
   */
  fallbackModel?: string
  /**
   * The vision-capable model a call is routed to when its `input` carries
   * visual content — see `requestIsVisual` below. When absent, a visual
   * request falls through to the ordinary text `model`/`fallbackModel`
   * routing exactly as if this field never existed (e.g. the OpenAI-provider
   * doors, which never populate this field today).
   */
  visionModel?: string
  /**
   * CRITICAL — read before touching vision fallback behavior: the text
   * fallback (`fallbackModel`, e.g. `openai/gpt-oss-20b`) is a text->text
   * model and CANNOT accept image/video input. Falling a failed vision call
   * back onto it would not retry the request, it would guarantee a SECOND
   * failure (the provider would reject the image content outright). So the
   * vision route never, under any circumstance, falls back to
   * `fallbackModel`.
   *
   * This field is the vision route's OWN, entirely independent, OPTIONAL
   * fallback. It defaults to unset, meaning "no fallback on the vision
   * path": when a vision call fails and this is absent, blank, or equal to
   * `visionModel`, `respond()` throws `AgentProviderError` as that call's
   * terminal outcome (with telemetry intact) after exactly one attempt —
   * there is nothing safe to retry onto. Only ever consulted when
   * `provider === 'openrouter'`, mirroring `fallbackModel`.
   */
  visionFallbackModel?: string
  fetchImpl?: typeof fetch
  /**
   * Test-only override for `PRIMARY_ATTEMPT_TIMEOUT_MS`. Production callers
   * should never set this — see that constant's comment for why 8s is the
   * right default. Exists so tests can exercise the `attempt_timeout`
   * fallback branch without a real multi-second wait.
   */
  attemptTimeoutMs?: number
}

export class AgentProviderError extends Error {
  constructor(
    message: string,
    readonly status: number | null = null,
    /** Null when the failure is not in the fallback-eligible table (e.g. 401/403/413). */
    readonly reason: ProviderFailureReason | null = null,
    /** Always true when thrown: throwing IS this call's terminal outcome. */
    readonly terminal: boolean = true,
    /** Best-effort telemetry for the failed call, for observability. */
    readonly telemetry: AgentProviderTelemetry | null = null,
  ) {
    super(message)
    this.name = 'AgentProviderError'
  }
}

const OPENAI_ENDPOINT = 'https://api.openai.com/v1/responses'
const OPENROUTER_ENDPOINT = 'https://openrouter.ai/api/v1/responses'
const MAX_DIAGNOSTIC_METADATA_CHARS = 160

/**
 * Per-attempt timeout INTERNAL to the provider — separate from, and smaller
 * than, the caller's turn-deadline signal.
 *
 * `agent_runtime.ts` reserves `FINAL_PASS_RESERVE_MS` (4_000ms) for the
 * turn's final-answer pass and otherwise gives each tool-calling pass
 * whatever remains of the `maxTurnMs` (20_000ms default) turn budget — so
 * the FIRST tool-calling pass gets roughly `20_000 - 4_000 = 16_000ms`, and
 * later passes get less as the turn's budget is spent.
 *
 * 8_000ms is half of that first-pass budget. If the primary hangs, roughly
 * half of the pass's remaining time is still available for exactly one
 * fallback attempt plus response parsing — real room, not a sliver.
 *
 * On the final pass, whose entire budget IS the 4_000ms reserve, this
 * 8_000ms timer can never fire first: the runtime's own outer AbortSignal
 * (driven by ITS `remainingMs`, via `withTimeout` in agent_runtime.ts) aborts
 * the combined signal before this timer would. `respond()` then takes the
 * "caller already aborted" branch and skips the fallback, rather than
 * starting an attempt with no time left to finish it — a turn that is
 * already this close to its deadline has no room for a fallback regardless
 * of what this constant says, so failing to attempt one there is correct,
 * not a bug.
 */
const PRIMARY_ATTEMPT_TIMEOUT_MS = 8_000

export type ProviderFailureSignal =
  | { kind: 'caller_aborted' }
  | { kind: 'transport_error' }
  | { kind: 'attempt_timeout' }
  | { kind: 'http_status'; status: number }
  | { kind: 'error_envelope' }
  | { kind: 'malformed_response' }
  | { kind: 'empty_output' }

export interface ProviderFailureClassification {
  eligible: boolean
  reason: ProviderFailureReason | null
}

/**
 * The documented fallback-eligibility table, as code. Every branch here is
 * unit-tested directly — this function is the source of truth the docs
 * quote, not the other way around.
 *
 * FALLBACK-ELIGIBLE (retry once on the fallback model):
 *   provider_transport_error, attempt_timeout, http_400_request_rejected,
 *   http_402_payment_required, http_404_model_unavailable,
 *   http_408_request_timeout, http_429_rate_limited,
 *   http_5xx_provider_error, provider_error_envelope, malformed_response,
 *   empty_output.
 *
 * NOT ELIGIBLE (no fallback — the caller throws `AgentProviderError`
 * immediately, or rethrows the caller's own abort untouched):
 *   HTTP 401/403 (bad/blocked key — a second model cannot fix that),
 *   HTTP 413 (payload too large — the fallback has a SMALLER context
 *   window, so retrying only makes it worse), any other HTTP status, and
 *   `caller_aborted` (the turn deadline has already passed).
 */
export function classifyProviderFailure(
  signal: ProviderFailureSignal,
): ProviderFailureClassification {
  switch (signal.kind) {
    case 'caller_aborted':
      return { eligible: false, reason: null }
    case 'transport_error':
      return { eligible: true, reason: 'provider_transport_error' }
    case 'attempt_timeout':
      return { eligible: true, reason: 'attempt_timeout' }
    case 'error_envelope':
      return { eligible: true, reason: 'provider_error_envelope' }
    case 'malformed_response':
      return { eligible: true, reason: 'malformed_response' }
    case 'empty_output':
      return { eligible: true, reason: 'empty_output' }
    case 'http_status':
      return classifyHttpStatus(signal.status)
  }
}

function classifyHttpStatus(status: number): ProviderFailureClassification {
  switch (status) {
    case 400:
      return { eligible: true, reason: 'http_400_request_rejected' }
    case 402:
      return { eligible: true, reason: 'http_402_payment_required' }
    case 404:
      return { eligible: true, reason: 'http_404_model_unavailable' }
    case 408:
      return { eligible: true, reason: 'http_408_request_timeout' }
    case 429:
      return { eligible: true, reason: 'http_429_rate_limited' }
    default:
      if (status >= 500 && status <= 599) {
        return { eligible: true, reason: 'http_5xx_provider_error' }
      }
      // 401, 403, 413, and anything else (redirects, other 4xx) are not in
      // the eligible table — see the doc comment on classifyProviderFailure.
      return { eligible: false, reason: null }
  }
}

type AttemptOutcome =
  | { ok: true; payload: Record<string, unknown>; httpStatus: number }
  | { ok: false; callerAborted: true; rawError: unknown }
  | {
    ok: false
    callerAborted: false
    classification: ProviderFailureClassification
    httpStatus: number | null
  }

export function createResponsesAgentProvider(
  config: ResponsesAgentProviderConfig,
): AgentProvider {
  const endpoint = config.provider === 'openrouter'
    ? OPENROUTER_ENDPOINT
    : OPENAI_ENDPOINT
  // --- Text route -----------------------------------------------------
  const textRequestedModel = config.model ??
    (config.provider === 'openrouter'
      ? PIP_MODEL_DEFAULTS.textOpenRouter
      : PIP_MODEL_DEFAULTS.text)
  const textFallbackModel = resolveFallbackModel(config, textRequestedModel)
  // --- Vision route -----------------------------------------------------
  // Absent unless a door explicitly configures `visionModel` (today, only
  // the OpenRouter branch of each door's `readAiConfig()` does, from
  // `resolveOpenRouterTextModels(...).vision`). When absent, `respond()`
  // never routes to it — a visual request just takes the text route above,
  // unchanged from before this field existed.
  const visionRequestedModel = nonEmptyTrimmed(config.visionModel)
  // CRITICAL: see the doc comment on `visionFallbackModel` in
  // `ResponsesAgentProviderConfig` above. `textFallbackModel` is
  // text->text and cannot accept image/video input, so the vision route
  // gets its OWN fallback resolution, entirely independent of the text
  // one — never derived from or falling through to `textFallbackModel`.
  // `resolveVisionFallbackModel` returns `undefined` (no fallback at all)
  // unless a door explicitly configures `visionFallbackModel`.
  const visionFallbackModel = resolveVisionFallbackModel(
    config,
    visionRequestedModel,
  )
  const fetchImpl = config.fetchImpl ?? fetch
  const attemptTimeoutMs = config.attemptTimeoutMs ?? PRIMARY_ATTEMPT_TIMEOUT_MS

  // --- Sticky fallback, scoped to THIS provider instance, PER ROUTE -------
  //
  // `createResponsesAgentProvider` is called once per turn by both doors
  // (`serveTelegramWebhook` / `serveAppAgent` construct a fresh provider on
  // every incoming request, and `runAgentTurn`'s tool loop reuses that same
  // instance — and therefore this same closure — for every `respond()` call
  // within the turn). So these variables' lifetime IS the turn's lifetime:
  // both start `null` on every new turn and are never reset mid-turn.
  //
  // Once a route's primary has failed for a fallback-eligible reason, later
  // calls on that SAME route within the SAME turn are overwhelmingly likely
  // to fail the same way (a rate-limited or unavailable model does not
  // usually recover mid-turn). Paying that primary's doomed attempt (up to
  // `attemptTimeoutMs`) again on every subsequent call burns turn budget for
  // nothing, so once a route's sticky reason is set, later calls on THAT
  // route skip its primary and go straight to its fallback model.
  //
  // Kept as two SEPARATE variables, one per route, deliberately: a text call
  // going sticky must never force a later vision call in the same turn onto
  // a text model (and vice versa) — the two routes use different models
  // entirely, so stickiness observed on one says nothing about the other.
  //
  // Deliberately NOT reset back to primary later in the turn (no
  // "recover-to-primary" probe) and NEVER carried across turns — a fresh
  // provider instance next turn starts both at `null` again.
  let stickyTextFallbackReason: ProviderFailureReason | null = null
  let stickyVisionFallbackReason: ProviderFailureReason | null = null

  return {
    async respond(request, options) {
      const callerSignal = options?.signal
      const startedAt = Date.now()

      // --- Route detection --------------------------------------------
      // Decide BEFORE choosing a model whether this call's input carries
      // visual content (see `requestIsVisual`). Only actually routes to
      // `visionRequestedModel` when a door has configured one; otherwise
      // this always evaluates to `false` and behavior is identical to
      // before vision routing existed.
      const visionRouted = visionRequestedModel !== undefined &&
        requestIsVisual(request.input)
      const activeRequestedModel = visionRouted
        ? visionRequestedModel
        : textRequestedModel
      const activeFallbackModel = visionRouted
        ? visionFallbackModel
        : textFallbackModel

      const requestBody = (model: string) =>
        JSON.stringify({
          model,
          instructions: request.instructions,
          input: request.input,
          tools: request.tools.map((tool) => ({
            ...tool,
            strict: false,
          })),
          tool_choice: request.toolChoice ?? 'auto',
          parallel_tool_calls: false,
          max_output_tokens: 2400,
          store: false,
        })

      const attempt = async (model: string): Promise<AttemptOutcome> => {
        // Combine the caller's turn-deadline signal with our OWN, smaller,
        // per-attempt timer. Whichever fires first aborts the fetch; we then
        // inspect which one it was to tell "the turn ran out of time"
        // (rethrow untouched) apart from "this attempt hung" (fallback-eligible).
        const ownTimeoutSignal = AbortSignal.timeout(attemptTimeoutMs)
        const combinedSignal = callerSignal
          ? AbortSignal.any([callerSignal, ownTimeoutSignal])
          : ownTimeoutSignal

        let response: Response
        try {
          response = await fetchImpl(endpoint, {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${config.apiKey}`,
              'Content-Type': 'application/json',
            },
            signal: combinedSignal,
            body: requestBody(model),
          })
        } catch (error) {
          if (callerSignal?.aborted) {
            return { ok: false, callerAborted: true, rawError: error }
          }
          const kind = ownTimeoutSignal.aborted
            ? 'attempt_timeout'
            : 'transport_error'
          return {
            ok: false,
            callerAborted: false,
            classification: classifyProviderFailure({ kind }),
            httpStatus: null,
          }
        }

        if (!response.ok) {
          return {
            ok: false,
            callerAborted: false,
            classification: classifyProviderFailure({
              kind: 'http_status',
              status: response.status,
            }),
            httpStatus: response.status,
          }
        }

        let payload: unknown
        try {
          payload = await response.json()
        } catch (_) {
          return {
            ok: false,
            callerAborted: false,
            classification: classifyProviderFailure({
              kind: 'malformed_response',
            }),
            httpStatus: response.status,
          }
        }
        if (!isRecord(payload)) {
          return {
            ok: false,
            callerAborted: false,
            classification: classifyProviderFailure({
              kind: 'malformed_response',
            }),
            httpStatus: response.status,
          }
        }
        if (isRecord(payload.error)) {
          return {
            ok: false,
            callerAborted: false,
            classification: classifyProviderFailure({ kind: 'error_envelope' }),
            httpStatus: response.status,
          }
        }
        if (typeof payload.id !== 'string') {
          return {
            ok: false,
            callerAborted: false,
            classification: classifyProviderFailure({
              kind: 'malformed_response',
            }),
            httpStatus: response.status,
          }
        }
        if (!Array.isArray(payload.output) || !payload.output.every(isRecord)) {
          return {
            ok: false,
            callerAborted: false,
            classification: classifyProviderFailure({
              kind: 'malformed_response',
            }),
            httpStatus: response.status,
          }
        }
        if (payload.output.length === 0) {
          return {
            ok: false,
            callerAborted: false,
            classification: classifyProviderFailure({ kind: 'empty_output' }),
            httpStatus: response.status,
          }
        }
        return { ok: true, payload, httpStatus: response.status }
      }

      // --- Sticky short-circuit ------------------------------------------
      // A prior call on this SAME provider instance, on this SAME route
      // (text or vision — see `visionRouted` above), already saw its
      // primary fail for an eligible reason (see the doc comment on
      // `stickyTextFallbackReason`/`stickyVisionFallbackReason` above). Skip
      // the doomed primary attempt entirely: exactly one attempt, straight
      // to that route's fallback model.
      const activeStickyReason = visionRouted
        ? stickyVisionFallbackReason
        : stickyTextFallbackReason
      if (activeStickyReason !== null && activeFallbackModel !== undefined) {
        const outcome = await attempt(activeFallbackModel)
        if (outcome.ok) {
          const parsed = parseResponse(
            outcome.payload,
            config.provider,
            activeFallbackModel,
          )
          const telemetry: AgentProviderTelemetry = {
            provider: config.provider,
            requestedModel: activeRequestedModel,
            actualModel: parsed.model ?? activeFallbackModel,
            fallbackOccurred: true,
            fallbackReason: activeStickyReason,
            providerResponseId: parsed.id,
            latencyMs: Date.now() - startedAt,
            attempts: 1,
            sticky: true,
            visionRouted,
          }
          return { ...parsed, telemetry }
        }
        if (outcome.callerAborted) throw outcome.rawError
        const telemetry: AgentProviderTelemetry = {
          provider: config.provider,
          requestedModel: activeRequestedModel,
          actualModel: activeFallbackModel,
          fallbackOccurred: true,
          fallbackReason: activeStickyReason,
          providerResponseId: null,
          latencyMs: Date.now() - startedAt,
          attempts: 1,
          sticky: true,
          visionRouted,
        }
        throw new AgentProviderError(
          describeFailure(outcome),
          outcome.httpStatus,
          outcome.classification.reason,
          true,
          telemetry,
        )
      }

      let currentModel = activeRequestedModel
      let attempts = 0
      let fallbackOccurred = false
      let fallbackReason: ProviderFailureReason | null = null

      while (true) {
        attempts += 1
        const outcome = await attempt(currentModel)

        if (outcome.ok) {
          const parsed = parseResponse(
            outcome.payload,
            config.provider,
            currentModel,
          )
          const telemetry: AgentProviderTelemetry = {
            provider: config.provider,
            requestedModel: activeRequestedModel,
            actualModel: parsed.model ?? currentModel,
            fallbackOccurred,
            fallbackReason,
            providerResponseId: parsed.id,
            latencyMs: Date.now() - startedAt,
            attempts,
            sticky: false,
            visionRouted,
          }
          return { ...parsed, telemetry }
        }

        if (outcome.callerAborted) {
          // The turn deadline has passed. This is not a provider failure to
          // classify or fall back from — the caller has already stopped
          // waiting, so hand the abort back untouched.
          throw outcome.rawError
        }

        // --- Fallback ladder --------------------------------------------
        //
        // Idempotency, audited: `runAgentTurn` (agent_runtime.ts) executes
        // `respond()` and tool execution strictly sequentially inside one
        // `while (true)` loop. It bulk-pushes the previous `response.output`
        // into `modelInput` (agent_runtime.ts:205) and appends each tool's
        // `function_call_output` synchronously with no intervening await
        // (agent_runtime.ts:273-277) before the NEXT `respond()` call is
        // ever made. So whenever THIS fallback swap happens, every
        // `function_call` the model has emitted so far already has its
        // matching `function_call_output` sitting in `request.input` — the
        // fallback model sees a complete, self-consistent history, never a
        // call waiting on a result that never arrived. This fallback only
        // ever fires BEFORE this inference's own tool calls are known, so
        // there is nothing yet for a model swap to duplicate.
        //
        // Defence in depth already exists independently at the store layer,
        // untouched by this change: every state-mutating tool CASes on
        // `row_version` / `state_version` (`agent_intake_store.ts:250-259`,
        // `agent_conversation_context.ts:108-122`) or a turn-index +
        // consumed-`pendingAction` check (`agent_intake_tools.ts:257-266`,
        // `378-387`); `answer_legacy_draft_question` re-checks
        // `status='open'` (`answer_routing.ts:321`, `388-391`). A model swap
        // mid-turn cannot double-apply a mutation those guards already
        // refuse to accept twice, so no new claim/idempotency machinery is
        // added here.
        const canFallBack = !fallbackOccurred &&
          outcome.classification.eligible &&
          activeFallbackModel !== undefined
        if (canFallBack) {
          fallbackOccurred = true
          fallbackReason = outcome.classification.reason
          // Engage stickiness for the REST of this provider instance's
          // calls on THIS SAME route (i.e. the rest of this turn's text
          // calls, or the rest of this turn's vision calls — never both;
          // see the doc comment on `stickyTextFallbackReason`/
          // `stickyVisionFallbackReason` above). Set as soon as the primary
          // is KNOWN to have failed eligibly, regardless of how the
          // fallback attempt about to be made below turns out.
          if (visionRouted) {
            stickyVisionFallbackReason = outcome.classification.reason
          } else {
            stickyTextFallbackReason = outcome.classification.reason
          }
          currentModel = activeFallbackModel
          continue
        }

        const telemetry: AgentProviderTelemetry = {
          provider: config.provider,
          requestedModel: activeRequestedModel,
          actualModel: currentModel,
          fallbackOccurred,
          fallbackReason,
          providerResponseId: null,
          latencyMs: Date.now() - startedAt,
          attempts,
          sticky: false,
          visionRouted,
        }
        throw new AgentProviderError(
          describeFailure(outcome),
          outcome.httpStatus,
          outcome.classification.reason,
          true,
          telemetry,
        )
      }
    },
  }
}

function resolveFallbackModel(
  config: ResponsesAgentProviderConfig,
  requestedModel: string,
): string | undefined {
  if (config.provider !== 'openrouter') return undefined
  const trimmed = config.fallbackModel?.trim()
  if (!trimmed) return undefined
  if (trimmed === requestedModel) return undefined
  return trimmed
}

/**
 * Resolves the vision route's OWN fallback model — see the CRITICAL doc
 * comment on `visionFallbackModel` in `ResponsesAgentProviderConfig`. NEVER
 * derived from, or falls through to, `textFallbackModel`/`fallbackModel`:
 * that model is text->text and cannot accept the image/video content a
 * vision call sends. Mirrors `resolveFallbackModel`'s blank/self-equal
 * handling, but reads `config.visionFallbackModel` and compares against the
 * vision route's own requested model. Returns `undefined` (no fallback at
 * all) when `requestedModel` itself is `undefined` (no vision route
 * configured), the provider isn't `openrouter`, the value is blank, or it
 * equals the vision requested model.
 */
function resolveVisionFallbackModel(
  config: ResponsesAgentProviderConfig,
  requestedModel: string | undefined,
): string | undefined {
  if (config.provider !== 'openrouter') return undefined
  if (!requestedModel) return undefined
  const trimmed = config.visionFallbackModel?.trim()
  if (!trimmed) return undefined
  if (trimmed === requestedModel) return undefined
  return trimmed
}

function nonEmptyTrimmed(value: string | undefined): string | undefined {
  const trimmed = value?.trim()
  return trimmed ? trimmed : undefined
}

/**
 * File extensions that unambiguously mark visual content when an
 * `input_file` part carries no usable MIME type (see the comment on
 * `requestIsVisual` below for why that is the common case here).
 */
const VISUAL_FILE_EXTENSIONS = [
  // Image
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.heic',
  '.heif',
  '.tif',
  '.tiff',
  // Video
  '.mp4',
  '.mov',
  '.webm',
  '.avi',
  '.mkv',
  '.m4v',
  '.3gp',
]

/**
 * Detects whether a `respond()` call's `input` carries visual content, so it
 * can be routed to `visionModel` instead of the text primary/fallback pair.
 *
 * Two signals, matching the task's explicit detection rule:
 *   1. Any content part with `type === 'input_image'` — always visual (this
 *      is exactly what `agent_runtime.ts`'s `currentMessageContent()` emits
 *      for a Telegram photo attachment).
 *   2. Any content part with `type === 'input_file'` whose filename or MIME
 *      type indicates an image or video.
 *
 * CAVEAT, read before trusting signal 2 for video: `currentMessageContent()`
 * builds an `input_file` part as `{ type, filename, file_data }` ONLY — it
 * never carries the original attachment's `mimeType` into the model request
 * (see `agent_runtime.ts:454-459`). So in practice, for every call site that
 * exists today, an `input_file`'s MIME is never present and this function's
 * MIME check on it is dead code; only the filename extension can ever match.
 * That still lets an image or video sent to Telegram as a generic document
 * (mime `video/mp4`, filename `clip.mp4`) reach vision routing today,
 * because Telegram document uploads carry `document.file_name` through to
 * `attachment.fileName` and then to this `filename`.
 *
 * A SEPARATE, more fundamental gap (documented at the Telegram door, not
 * fixed here — out of scope for this change): `TelegramMessage` in
 * `telegram-hatchery-agent/index.ts` has no `video` field at all, so a
 * native Telegram video message (sent via the video attach button, not
 * re-sent as a document) is never captured as an attachment in the first
 * place — `describeSource()` only reads `.photo` and `.document`. Such a
 * video never reaches `agent_runtime.ts`, so it can never reach this
 * detector regardless of what this function checks.
 */
function requestIsVisual(input: readonly AgentModelInputItem[]): boolean {
  for (const item of input) {
    const content = item.content
    if (!Array.isArray(content)) continue
    for (const part of content) {
      if (!isRecord(part)) continue
      if (part.type === 'input_image') return true
      if (part.type === 'input_file' && inputFilePartLooksVisual(part)) {
        return true
      }
    }
  }
  return false
}

function inputFilePartLooksVisual(part: Record<string, unknown>): boolean {
  const mime = firstNonEmptyString(part.mime_type, part.mimeType)
    .toLowerCase()
  if (mime.startsWith('image/') || mime.startsWith('video/')) return true
  const filename = firstNonEmptyString(part.filename, part.file_name)
    .toLowerCase()
  return VISUAL_FILE_EXTENSIONS.some((ext) => filename.endsWith(ext))
}

function firstNonEmptyString(...values: unknown[]): string {
  for (const value of values) {
    if (typeof value === 'string' && value.length > 0) return value
  }
  return ''
}

function describeFailure(
  outcome: Extract<AttemptOutcome, { ok: false; callerAborted: false }>,
): string {
  switch (outcome.classification.reason) {
    case 'attempt_timeout':
      return 'Agent provider attempt timed out'
    case 'provider_transport_error':
      return 'Agent provider request failed'
    case 'provider_error_envelope':
      return 'Agent provider returned an error envelope'
    case 'malformed_response':
      return 'Agent provider response is malformed'
    case 'empty_output':
      return 'Agent provider output is empty'
    default:
      return outcome.httpStatus !== null
        ? `Agent provider returned HTTP ${outcome.httpStatus}`
        : 'Agent provider request failed'
  }
}

function parseResponse(
  payload: Record<string, unknown>,
  provider: AgentProviderName,
  model: string,
): AgentModelResponse {
  const output = payload.output as Record<string, unknown>[]
  return {
    id: boundedMetadata(payload.id as string),
    output: output.map((item) => structuredClone(item)),
    provider,
    model: typeof payload.model === 'string' && payload.model.trim().length > 0
      ? boundedMetadata(payload.model.trim())
      : boundedMetadata(model),
  }
}

function boundedMetadata(value: string): string {
  return value.slice(0, MAX_DIAGNOSTIC_METADATA_CHARS)
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
