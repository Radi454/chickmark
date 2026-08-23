// Shared OpenRouter Responses-API transport and multi-round tool loop for
// the text-agent model-acceptance harness (`run_probe.ts`, `run_evals.ts`).
//
// This is NOT a reimplementation of the production request shape -- it
// imports the real artefacts and mirrors the real transport byte-for-byte:
//
//   - Tool catalogue: `AGENT_MODEL_TOOL_DEFINITIONS` from
//     `../../telegram-hatchery-agent/agent_tools.ts` (same constant
//     `agent_runtime.ts` sends on every provider call).
//   - System prompt: `buildAgentInstructions` from
//     `../../telegram-hatchery-agent/agent_prompt.ts` (same function
//     `agent_runtime.ts` imports).
//   - Request body: POST `https://openrouter.ai/api/v1/responses`,
//     `Authorization: Bearer <key>`, body `{model, instructions, input,
//     tools (each with strict:false), tool_choice, parallel_tool_calls:false,
//     max_output_tokens:2400, store:false}` -- copied field-for-field from
//     `createResponsesAgentProvider`'s `send()` in
//     `../../telegram-hatchery-agent/agent_provider.ts`. Determinism knobs
//     (`temperature`, `seed`, `reasoning_effort`) are added on top; production
//     does not set them.
//   - Multi-round loop: push the model's own `output` items back into
//     `input` verbatim, then a `function_call_output` per `function_call`,
//     then ask again -- the same shape as `runAgentTurn` in
//     `../../telegram-hatchery-agent/agent_runtime.ts`. Tool rounds are
//     capped at the same `MAX_AGENT_TOOL_CALLS_PER_TURN` the runtime uses,
//     and a turn that hits the cap gets one final `tool_choice:'none'` pass
//     before ending, matching the runtime's forced-final behavior.
//
// If OpenRouter's `/v1/responses` ever turns out not to accept a given
// model's shape (a non-2xx that looks structural rather than transient --
// 404, or a 400 naming the endpoint/shape itself), `describeHttpFailure`
// labels it `architecture` so both entry points can surface it loudly rather
// than silently falling through to a generic failure.

import { buildAgentInstructions } from '../../telegram-hatchery-agent/agent_prompt.ts'
import type { AgentPromptContext } from '../../telegram-hatchery-agent/agent_prompt.ts'
import type { AgentScope } from '../../telegram-hatchery-agent/agent_protocol.ts'
import {
  AGENT_MODEL_TOOL_DEFINITIONS,
  type AgentToolDefinition,
  MAX_AGENT_TOOL_CALLS_PER_TURN,
} from '../../telegram-hatchery-agent/agent_tools.ts'
import {
  AGENT_TOOL_CONTRACT,
  type ArgumentRule,
} from '../../telegram-hatchery-agent/agent_tool_contract.ts'

export { AGENT_MODEL_TOOL_DEFINITIONS, MAX_AGENT_TOOL_CALLS_PER_TURN }
export type { AgentToolDefinition }

const OPENROUTER_RESPONSES_URL = 'https://openrouter.ai/api/v1/responses'

/**
 * Hard ceiling on a single `/v1/responses` call. Generous enough for the
 * slowest observed legitimate answer in this suite (deepseek's p95 was ~32s
 * on a multi-tool turn), while still bounding a dead connection so the
 * runner's existing retry/backoff can do its job.
 */
const REQUEST_TIMEOUT_MS = 90_000
const MAX_DIAGNOSTIC_BODY_CHARS = 800

// ---------------------------------------------------------------------------
// Instructions
// ---------------------------------------------------------------------------

export function defaultAgentScope(): AgentScope {
  return {
    staffLinkId: 'eval-staff-link',
    accessRole: 'admin',
    allowedCustomerIds: ['cust_eval_nile', 'cust_eval_delta'],
  }
}

export interface EvalInstructionsOptions {
  readonly scope?: AgentScope
  readonly conversationId?: string
  readonly activeVisitId?: string | null
  readonly pendingAction?: unknown
  readonly activeIntake?: unknown
  /**
   * Appended after the real, unmodified policy text. Used ONLY by
   * `run_probe.ts`'s instruction-following check, to see whether the model
   * honours a directive that lives in `instructions` rather than in a
   * message -- everything ahead of it is still the real
   * `CHICKMARK_AGENT_POLICY` plus its trusted-context JSON, byte for byte.
   */
  readonly extraDirective?: string
}

export function buildEvalInstructions(
  options: EvalInstructionsOptions = {},
): string {
  const context: AgentPromptContext = {
    scope: options.scope ?? defaultAgentScope(),
    conversationId: options.conversationId ?? 'eval-conversation',
    activeVisitId: options.activeVisitId ?? null,
    pendingAction: options.pendingAction ?? null,
    activeIntake: options.activeIntake ?? null,
  }
  const base = buildAgentInstructions(context)
  return options.extraDirective ? `${base}\n\n${options.extraDirective}` : base
}

// ---------------------------------------------------------------------------
// Wire types
// ---------------------------------------------------------------------------

export type AgentModelInputItem = Record<string, unknown>
export type AgentModelOutputItem = Record<string, unknown>

export interface EvalRequestOptions {
  readonly model: string
  readonly instructions: string
  readonly input: readonly AgentModelInputItem[]
  readonly tools: readonly AgentToolDefinition[]
  readonly toolChoice?: 'auto' | 'none'
  readonly temperature?: number
  readonly seed?: number
  readonly reasoningEffort?: 'low' | 'medium' | 'high'
}

export interface EvalHttpResponse {
  readonly status: number
  readonly ok: boolean
  readonly payload: unknown
}

export class AgentEvalTransportError extends Error {}

/**
 * Sends exactly the body `createResponsesAgentProvider`'s `send()` sends
 * (see the doc comment above), plus determinism knobs on top. Never throws
 * on a non-2xx HTTP status -- that is surfaced through `ok`/`status` so
 * callers can distinguish a transient failure from a structural one instead
 * of losing the status code to a thrown generic error.
 */
export async function sendResponsesRequest(
  apiKey: string,
  options: EvalRequestOptions,
): Promise<EvalHttpResponse> {
  const body: Record<string, unknown> = {
    model: options.model,
    instructions: options.instructions,
    input: options.input,
    tools: options.tools.map((tool) => ({ ...tool, strict: false })),
    tool_choice: options.toolChoice ?? 'auto',
    parallel_tool_calls: false,
    max_output_tokens: 2400,
    store: false,
  }
  if (options.temperature !== undefined) body.temperature = options.temperature
  if (options.seed !== undefined) body.seed = options.seed
  if (options.reasoningEffort !== undefined) {
    body.reasoning_effort = options.reasoningEffort
  }

  let response: Response
  try {
    response = await fetch(OPENROUTER_RESPONSES_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      // Without this the run can hang forever on a socket that died silently
      // (observed: the host slept mid-matrix and all five model runs stalled
      // indefinitely on an open connection, with OpenRouter itself healthy).
      // A dead socket must surface as a retryable transport error, not an
      // unbounded wait.
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    })
  } catch (error) {
    throw new AgentEvalTransportError(
      `network error calling ${OPENROUTER_RESPONSES_URL}: ${String(error)}`,
    )
  }

  let payload: unknown
  try {
    payload = await response.json()
  } catch {
    payload = null
  }
  return { status: response.status, ok: response.ok, payload }
}

/** `429` or `5xx` -- worth one retry. Anything else (401/402/404/400/...) is not. */
export function isRetryableStatus(status: number): boolean {
  return status === 429 || status >= 500
}

/**
 * `architecture` marks a failure shape that looks structural rather than
 * transient -- worth shouting about (per the task: "SAY SO LOUDLY") rather
 * than quietly treated as one more failed assertion. `404` means the
 * endpoint/model route itself was rejected; a `400` naming the request shape
 * (rather than a validation detail like a bad argument) is the same kind of
 * finding.
 */
export function describeHttpFailure(
  response: EvalHttpResponse,
): { kind: 'architecture' | 'transient' | 'rejected'; detail: string } {
  const bodyText = boundedJson(response.payload)
  const detail = `HTTP ${response.status}: ${bodyText}`
  if (response.status === 404) return { kind: 'architecture', detail }
  if (isRetryableStatus(response.status)) return { kind: 'transient', detail }
  return { kind: 'rejected', detail }
}

function boundedJson(value: unknown): string {
  const encoded = (() => {
    try {
      return JSON.stringify(value)
    } catch {
      return String(value)
    }
  })()
  return encoded.length <= MAX_DIAGNOSTIC_BODY_CHARS
    ? encoded
    : `${encoded.slice(0, MAX_DIAGNOSTIC_BODY_CHARS)}... (truncated)`
}

// ---------------------------------------------------------------------------
// Round / turn parsing
// ---------------------------------------------------------------------------

export interface FunctionCallItem {
  readonly type: 'function_call'
  readonly name: string
  readonly callId: string
  readonly arguments: Record<string, unknown>
  readonly rawArguments: string
}

export interface MessageItem {
  readonly type: 'message'
  readonly text: string
}

export interface OtherItem {
  readonly type: 'other'
  readonly raw: unknown
}

export type ParsedItem = FunctionCallItem | MessageItem | OtherItem

// ---------------------------------------------------------------------------
// Usage / cost (additive -- `run_evals.ts` and `run_probe.ts` never read
// these fields, so their existing destructuring of `Round`/`TurnResult`
// keeps working unchanged).
//
// `/v1/responses` returns a `usage` block per call, e.g.:
//   "usage":{"input_tokens":78,"input_tokens_details":{"cached_tokens":0},
//    "output_tokens":71,"output_tokens_details":{"reasoning_tokens":70},
//    "total_tokens":149,"cost":1.59e-05,
//    "cost_details":{"upstream_inference_cost":1.59e-05}}
// `cost` is OpenRouter's own REAL reported spend for that call -- this is
// what `run_comparison.ts`'s budget guard and per-model cost totals are
// built from. Never estimated from text length.
// ---------------------------------------------------------------------------

export interface RoundUsage {
  readonly inputTokens: number | null
  readonly cachedTokens: number | null
  readonly outputTokens: number | null
  readonly reasoningTokens: number | null
  readonly totalTokens: number | null
  readonly costUsd: number | null
}

/** All fields `null` -- distinguishable from "measured zero". */
export const ZERO_ROUND_USAGE: RoundUsage = {
  inputTokens: null,
  cachedTokens: null,
  outputTokens: null,
  reasoningTokens: null,
  totalTokens: null,
  costUsd: null,
}

function toNumberOrNull(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function parseUsage(payload: unknown): RoundUsage {
  const record = isRecord(payload) ? payload : {}
  const usage = isRecord(record.usage) ? record.usage : null
  if (!usage) return ZERO_ROUND_USAGE
  const inputDetails = isRecord(usage.input_tokens_details)
    ? usage.input_tokens_details
    : null
  const outputDetails = isRecord(usage.output_tokens_details)
    ? usage.output_tokens_details
    : null
  const costDetails = isRecord(usage.cost_details) ? usage.cost_details : null
  return {
    inputTokens: toNumberOrNull(usage.input_tokens),
    cachedTokens: toNumberOrNull(inputDetails?.cached_tokens),
    outputTokens: toNumberOrNull(usage.output_tokens),
    reasoningTokens: toNumberOrNull(outputDetails?.reasoning_tokens),
    totalTokens: toNumberOrNull(usage.total_tokens),
    costUsd: toNumberOrNull(usage.cost) ??
      toNumberOrNull(costDetails?.upstream_inference_cost),
  }
}

/**
 * Sums a list of `RoundUsage`. A field is `null` in the result only if it
 * was `null` in EVERY input (nothing measured anywhere) -- otherwise missing
 * values are treated as 0 so one round's absent field doesn't blank out a
 * total that other rounds did contribute to.
 */
export function sumUsage(items: readonly RoundUsage[]): RoundUsage {
  const has = (key: keyof RoundUsage) => items.some((u) => u[key] !== null)
  const sum = (key: keyof RoundUsage) =>
    has(key) ? items.reduce((acc, u) => acc + (u[key] ?? 0), 0) : null
  return {
    inputTokens: sum('inputTokens'),
    cachedTokens: sum('cachedTokens'),
    outputTokens: sum('outputTokens'),
    reasoningTokens: sum('reasoningTokens'),
    totalTokens: sum('totalTokens'),
    costUsd: sum('costUsd'),
  }
}

/** One `/responses` request/response round trip. */
export interface Round {
  readonly rawOutput: readonly AgentModelOutputItem[]
  readonly items: readonly ParsedItem[]
  readonly messages: readonly string[]
  readonly functionCalls: readonly FunctionCallItem[]
  readonly responseId: string | null
  /** Preamble text: any `message` item that appears BEFORE the first
   * `function_call` item in this round's own output order. Empty when the
   * round has no tool call, or the tool call came first. */
  readonly preambleBeforeFirstToolCall: string
  /** This round's own `usage` block, parsed. See "Usage / cost" above. */
  readonly usage: RoundUsage
}

function parseCallArguments(raw: unknown): Record<string, unknown> {
  if (typeof raw !== 'string') return {}
  try {
    const parsed = JSON.parse(raw)
    return isRecord(parsed) ? parsed : {}
  } catch {
    return {}
  }
}

function safeCallId(item: Record<string, unknown>): string {
  if (typeof item.call_id === 'string' && item.call_id.trim().length > 0) {
    return item.call_id
  }
  if (typeof item.id === 'string' && item.id.trim().length > 0) return item.id
  return `synthetic-${Math.random().toString(36).slice(2)}`
}

export function parseRound(payload: unknown): Round {
  const record = isRecord(payload) ? payload : {}
  const output = Array.isArray(record.output) ? record.output : []
  const items: ParsedItem[] = output.map((raw) => {
    const item = isRecord(raw) ? raw : {}
    if (item.type === 'message') {
      const content = Array.isArray(item.content) ? item.content : []
      const text = content
        .filter((part): part is Record<string, unknown> =>
          isRecord(part) && part.type === 'output_text' &&
          typeof part.text === 'string'
        )
        .map((part) => part.text as string)
        .join('')
      return { type: 'message', text } satisfies MessageItem
    }
    if (item.type === 'function_call') {
      const rawArguments = typeof item.arguments === 'string'
        ? item.arguments
        : ''
      return {
        type: 'function_call',
        name: typeof item.name === 'string' ? item.name : '',
        callId: safeCallId(item),
        arguments: parseCallArguments(item.arguments),
        rawArguments,
      } satisfies FunctionCallItem
    }
    return { type: 'other', raw: item } satisfies OtherItem
  })

  const functionCalls = items.filter((item): item is FunctionCallItem =>
    item.type === 'function_call'
  )
  const firstCallIndex = items.findIndex((item) =>
    item.type === 'function_call'
  )
  const preambleBeforeFirstToolCall = firstCallIndex < 0 ? '' : items
    .slice(0, firstCallIndex)
    .filter((item): item is MessageItem =>
      item.type === 'message' && item.text.trim() !== ''
    )
    .map((item) => item.text)
    .join(' ')
    .trim()

  return {
    rawOutput: output.filter(isRecord),
    items,
    messages: items.filter((item): item is MessageItem =>
      item.type === 'message'
    )
      .map((item) => item.text),
    functionCalls,
    responseId: typeof record.id === 'string' ? record.id : null,
    preambleBeforeFirstToolCall,
    usage: parseUsage(payload),
  }
}

// ---------------------------------------------------------------------------
// Tool stubs
// ---------------------------------------------------------------------------

export interface ToolStub {
  readonly name: string
  readonly output: unknown | ((args: Record<string, unknown>) => unknown)
  /** Optional predicate over the parsed call arguments; first match wins. */
  readonly matches?: (args: Record<string, unknown>) => boolean
}

function matchStub(
  stubs: readonly ToolStub[],
  call: FunctionCallItem,
): ToolStub | undefined {
  return stubs.find((stub) =>
    stub.name === call.name && (!stub.matches || stub.matches(call.arguments))
  )
}

function resolveStubOutput(stub: ToolStub, call: FunctionCallItem): unknown {
  return typeof stub.output === 'function'
    ? (stub.output as (args: Record<string, unknown>) => unknown)(
      call.arguments,
    )
    : stub.output
}

// ---------------------------------------------------------------------------
// Session + multi-round turn loop
// ---------------------------------------------------------------------------

export interface AgentEvalSession {
  readonly apiKey: string
  readonly model: string
  readonly instructions: string
  readonly tools: readonly AgentToolDefinition[]
  readonly temperature?: number
  readonly seed?: number
  readonly reasoningEffort?: 'low' | 'medium' | 'high'
  /** Mutable, grows across every `runTurn` call in this session -- this is
   * what makes multi-turn context (dimension 3 / probe check 7) real rather
   * than simulated: the same array the model's own prior output items were
   * pushed into is what the NEXT turn sends back. */
  readonly input: AgentModelInputItem[]
}

export interface CreateSessionOptions {
  readonly apiKey: string
  readonly model: string
  readonly instructions: string
  readonly tools?: readonly AgentToolDefinition[]
  readonly temperature?: number
  readonly seed?: number
  readonly reasoningEffort?: 'low' | 'medium' | 'high'
}

export function createSession(options: CreateSessionOptions): AgentEvalSession {
  return {
    apiKey: options.apiKey,
    model: options.model,
    instructions: options.instructions,
    tools: options.tools ?? AGENT_MODEL_TOOL_DEFINITIONS,
    temperature: options.temperature,
    seed: options.seed,
    reasoningEffort: options.reasoningEffort,
    input: [],
  }
}

export type TurnStatus =
  | 'replied'
  | 'invalid_model_output'
  | 'tool_limit_exceeded'
  | 'transport_error'

export interface TurnResult {
  readonly rounds: readonly Round[]
  readonly allToolCalls: readonly FunctionCallItem[]
  readonly status: TurnStatus
  readonly finalReply: string
  readonly transportDetail?: string
  readonly transportKind?: 'architecture' | 'transient' | 'rejected'
  /** Sum of every round's `usage` actually received in this turn (see
   * "Usage / cost" above `Round`). All-null when no round returned a usage
   * block at all (e.g. a turn that failed before any HTTP response). */
  readonly usage: RoundUsage
}

/** The text shown to the user for a turn: same convention as the pip-realtime
 * harness -- the LAST round's message text is the final answer. */
export function finalText(result: TurnResult): string {
  return result.finalReply
}

/**
 * Runs one user turn to completion against a session: sends the message,
 * then loops responding to any `function_call` with its scripted stub
 * output (or a synthetic `unstubbed_in_eval` failure so the session never
 * hangs on a call nothing scripted) until a round comes back with no more
 * tool calls, mirroring `runAgentTurn` in `agent_runtime.ts` -- including its
 * forced-final pass: once `MAX_AGENT_TOOL_CALLS_PER_TURN` calls have been
 * spent, the NEXT round is asked with `tool_choice:'none'` so the model must
 * answer from what it already has, and a model that calls a tool anyway on
 * that pass ends the turn as `tool_limit_exceeded` rather than looping.
 */
export async function runTurn(
  session: AgentEvalSession,
  userText: string,
  toolStubs: readonly ToolStub[],
): Promise<TurnResult> {
  session.input.push({ role: 'user', content: userText })

  const rounds: Round[] = []
  let toolCallCount = 0
  let forcedFinal = false

  for (;;) {
    let httpResponse: EvalHttpResponse
    try {
      httpResponse = await sendResponsesRequest(session.apiKey, {
        model: session.model,
        instructions: session.instructions,
        input: session.input,
        tools: session.tools,
        toolChoice: forcedFinal ? 'none' : 'auto',
        temperature: session.temperature,
        seed: session.seed,
        reasoningEffort: session.reasoningEffort,
      })
    } catch (error) {
      return {
        rounds,
        allToolCalls: rounds.flatMap((round) => round.functionCalls),
        status: 'transport_error',
        finalReply: '',
        transportDetail: String(error),
        transportKind: 'transient',
        usage: sumUsage(rounds.map((r) => r.usage)),
      }
    }

    if (!httpResponse.ok) {
      const failure = describeHttpFailure(httpResponse)
      return {
        rounds,
        allToolCalls: rounds.flatMap((round) => round.functionCalls),
        status: 'transport_error',
        finalReply: '',
        transportDetail: failure.detail,
        transportKind: failure.kind,
        usage: sumUsage(rounds.map((r) => r.usage)),
      }
    }

    const round = parseRound(httpResponse.payload)
    rounds.push(round)
    // Same as `modelInput.push(...response.output.map(structuredClone))` in
    // `agent_runtime.ts` -- the model's own output items become input items
    // for the next round, verbatim.
    session.input.push(...round.rawOutput.map((item) => structuredClone(item)))

    if (round.functionCalls.length === 0) {
      const reply = round.messages.join('\n').trim()
      if (!reply) {
        return {
          rounds,
          allToolCalls: rounds.flatMap((r) => r.functionCalls),
          status: 'invalid_model_output',
          finalReply: '',
          usage: sumUsage(rounds.map((r) => r.usage)),
        }
      }
      return {
        rounds,
        allToolCalls: rounds.flatMap((r) => r.functionCalls),
        status: 'replied',
        finalReply: reply,
        usage: sumUsage(rounds.map((r) => r.usage)),
      }
    }

    if (forcedFinal) {
      return {
        rounds,
        allToolCalls: rounds.flatMap((r) => r.functionCalls),
        status: 'tool_limit_exceeded',
        finalReply: round.messages.join('\n').trim(),
        usage: sumUsage(rounds.map((r) => r.usage)),
      }
    }

    for (const call of round.functionCalls) {
      let output: unknown
      if (toolCallCount >= MAX_AGENT_TOOL_CALLS_PER_TURN) {
        forcedFinal = true
        output = {
          ok: false,
          code: 'tool_limit_reached',
          data: { limit: MAX_AGENT_TOOL_CALLS_PER_TURN },
        }
      } else {
        toolCallCount += 1
        const stub = matchStub(toolStubs, call)
        output = stub ? resolveStubOutput(stub, call) : {
          ok: false,
          code: 'unstubbed_in_eval',
          tool: call.name,
          data: null,
        }
      }
      session.input.push({
        type: 'function_call_output',
        call_id: call.callId,
        output: JSON.stringify(output),
      })
    }
  }
}

// ---------------------------------------------------------------------------
// Structured-argument validation (mechanical, against the REAL contract)
// ---------------------------------------------------------------------------

export interface ArgumentValidationResult {
  readonly valid: boolean
  readonly problems: readonly string[]
}

/**
 * Validates a tool call's parsed `arguments` against the REAL declared
 * schema for that tool in `AGENT_TOOL_CONTRACT` -- required fields present,
 * correct JSON types, respected `enum`/`pattern`/length/range bounds, and no
 * invented keys (`additionalProperties: false`). This is a local
 * reimplementation of the same checks `executeAgentTool`'s private
 * `validArguments`/`validValue` perform in `agent_tools.ts` (not exported,
 * so not importable directly) -- kept mechanical for exactly the same
 * reason: "structured arguments" must be checked field by field, not by
 * eyeballing the JSON a model produced.
 */
export function validateToolArguments(
  toolName: string,
  args: Record<string, unknown>,
): ArgumentValidationResult {
  const contractEntry = AGENT_TOOL_CONTRACT.find((entry) =>
    entry.name === toolName
  )
  if (!contractEntry) {
    return {
      valid: false,
      problems: [
        `unknown tool name "${toolName}" -- not in AGENT_TOOL_CONTRACT`,
      ],
    }
  }
  const schema = contractEntry.parameters
  const problems: string[] = []

  for (const key of Object.keys(args)) {
    if (!(key in schema.properties)) {
      problems.push(`invented argument "${key}" is not in the declared schema`)
    }
  }
  for (const key of schema.required) {
    if (!(key in args)) problems.push(`missing required argument "${key}"`)
  }
  for (const [key, value] of Object.entries(args)) {
    const rule = schema.properties[key]
    if (!rule) continue
    // An explicit `null` on an OPTIONAL property is what production actually
    // does with an omitted value, so the eval must not score it as a schema
    // violation. Verified against the real handler for `query_station_records`
    // (agent_read_tools.ts): the argument is read as
    // `input.arguments.flockId as string | undefined` and then guarded by a
    // truthiness check `if (flockId) {...}`, so `null` skips the flock scope
    // check exactly as absence does; it is then normalised to
    // `flockId: flockId ?? null` and the query builder applies the filter only
    // `if (query.flockId)`. The internal query type even declares
    // `flockId?: string | null`. Without this carve-out the harness was
    // STRICTER THAN PRODUCTION and every model was penalised for a call the
    // real tool executes correctly.
    //
    // `null` on a REQUIRED property is still a violation: `required` is
    // enforced by the loop above on key presence, and a required field whose
    // value is null would reach the handler as a genuine missing value.
    if (value === null && !schema.required.includes(key)) continue
    const problem = describeRuleViolation(key, value, rule)
    if (problem) problems.push(problem)
  }
  return { valid: problems.length === 0, problems }
}

function describeRuleViolation(
  key: string,
  value: unknown,
  rule: ArgumentRule,
): string | null {
  if (rule.type === 'string') {
    if (typeof value !== 'string') {
      return `"${key}" should be a string, got ${typeof value}`
    }
    if (rule.minLength !== undefined && value.trim().length < rule.minLength) {
      return `"${key}" is shorter than minLength ${rule.minLength}`
    }
    if (rule.maxLength !== undefined && value.length > rule.maxLength) {
      return `"${key}" exceeds maxLength ${rule.maxLength}`
    }
    if (rule.pattern && !new RegExp(rule.pattern).test(value)) {
      return `"${key}" does not match required pattern ${rule.pattern}`
    }
  } else if (rule.type === 'integer') {
    if (!Number.isInteger(value)) {
      return `"${key}" should be an integer, got ${JSON.stringify(value)}`
    }
  } else if (rule.type === 'number') {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return `"${key}" should be a finite number, got ${JSON.stringify(value)}`
    }
  } else if (rule.type === 'boolean') {
    if (typeof value !== 'boolean') {
      return `"${key}" should be a boolean, got ${typeof value}`
    }
  } else if (rule.type === 'object') {
    if (!isRecord(value)) return `"${key}" should be an object`
  } else if (rule.type === 'array') {
    if (!Array.isArray(value)) return `"${key}" should be an array`
  }

  if (typeof value === 'number') {
    if (rule.minimum !== undefined && value < rule.minimum) {
      return `"${key}" value ${value} is below minimum ${rule.minimum}`
    }
    if (rule.maximum !== undefined && value > rule.maximum) {
      return `"${key}" value ${value} exceeds maximum ${rule.maximum}`
    }
  }
  if (rule.enum && !rule.enum.includes(value as never)) {
    return `"${key}" value ${
      JSON.stringify(value)
    } is not one of the declared enum values`
  }
  return null
}

// ---------------------------------------------------------------------------
// Small text helpers shared by both entry points
// ---------------------------------------------------------------------------

const ARABIC_SCRIPT_PATTERN = /[؀-ۿ]/

export function containsArabic(text: string): boolean {
  return ARABIC_SCRIPT_PATTERN.test(text)
}

export function wordCount(text: string): number {
  const trimmed = text.trim()
  return trimmed === '' ? 0 : trimmed.split(/\s+/).length
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
