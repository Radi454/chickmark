import { buildAgentInstructions } from './agent_prompt.ts'
import {
  AgentProviderError,
  type AgentModelInputItem,
  type AgentModelOutputItem,
  type AgentProvider,
  type AgentProviderTelemetry,
} from './agent_provider.ts'
import type {
  AgentScope,
  AgentToolCall,
  AgentToolResult,
} from './agent_protocol.ts'
import {
  AGENT_MODEL_TOOL_DEFINITIONS,
  AGENT_TOOL_DEFINITIONS,
  MAX_AGENT_TOOL_CALLS_PER_TURN,
} from './agent_tools.ts'

export interface AgentHistoryTurn {
  role: 'user' | 'assistant'
  text: string
}

export interface AgentTurnAttachment {
  kind: string
  fileName: string | null
  mimeType: string | null
  fileData: string | null
}

export type AgentTurnStatus =
  | 'replied'
  | 'provider_unavailable'
  | 'provider_timeout'
  | 'tool_limit_exceeded'
  | 'invalid_model_output'

/**
 * Cap on `modelsUsed` / `providerResponseIds` below.
 *
 * A turn's provider-call count is bounded by `MAX_AGENT_TOOL_CALLS_PER_TURN`
 * (5) tool-calling passes plus one final-answer pass — 6 calls in the
 * ordinary case, 7 when the tool-call BUDGET itself is what ends the turn
 * (one extra request that gets refused rather than executed; see the "five
 * serial tool calls" test in agent_runtime_test.ts). 20 is a defensive
 * multiple of that observed maximum, never expected to be hit in practice —
 * it exists so a future change to the tool-call budget cannot make this
 * array grow unboundedly.
 */
const MAX_TURN_TELEMETRY_ENTRIES = 20

/**
 * Turn-level observability, aggregated from every `respond()` call made
 * during the turn (a turn can make several: one per tool-calling pass, plus
 * the final-answer pass). A single call's `AgentProviderTelemetry` (see
 * agent_provider.ts) would misrepresent the turn once the provider's
 * "sticky fallback" behavior lets different calls within one turn land on
 * different models — this is the per-TURN picture, built from the per-call
 * ones.
 */
export interface AgentTurnTelemetry {
  /** From the first completed call. Null if no provider call ever completed. */
  provider: 'openai' | 'openrouter' | null
  /** The model configured as primary — from the first completed call's `requestedModel`. */
  primaryModel: string | null
  /** The fallback model actually observed in use this turn, if any call fell back. */
  fallbackModel: string | null
  /** One entry per provider call this turn, in order — each call's `actualModel`. Bounded, see `MAX_TURN_TELEMETRY_ENTRIES`. */
  modelsUsed: string[]
  totalCallCount: number
  fallbackCallCount: number
  /** True if ANY call this turn fell back (including sticky calls that skipped the primary). */
  fallbackOccurred: boolean
  /** Deduped reason codes seen this turn, in first-seen order. */
  fallbackReasons: string[]
  /** One entry per provider call this turn, in order. Bounded, see `MAX_TURN_TELEMETRY_ENTRIES`. */
  providerResponseIds: Array<string | null>
  /** Summed across every provider call this turn. */
  latencyMs: number
  toolCallCount: number
  status: AgentTurnStatus
}

function buildTurnTelemetry(
  calls: readonly AgentProviderTelemetry[],
  toolCallCount: number,
  status: AgentTurnStatus,
): AgentTurnTelemetry | null {
  if (calls.length === 0) return null
  const fallbackCall = calls.find((call) => call.fallbackOccurred)
  const fallbackReasons: string[] = []
  for (const call of calls) {
    if (call.fallbackReason && !fallbackReasons.includes(call.fallbackReason)) {
      fallbackReasons.push(call.fallbackReason)
    }
  }
  return {
    provider: calls[0].provider,
    primaryModel: calls[0].requestedModel,
    fallbackModel: fallbackCall ? fallbackCall.actualModel : null,
    modelsUsed: calls.map((call) => call.actualModel).slice(0, MAX_TURN_TELEMETRY_ENTRIES),
    totalCallCount: calls.length,
    fallbackCallCount: calls.filter((call) => call.fallbackOccurred).length,
    fallbackOccurred: fallbackCall !== undefined,
    fallbackReasons,
    providerResponseIds: calls.map((call) => call.providerResponseId).slice(
      0,
      MAX_TURN_TELEMETRY_ENTRIES,
    ),
    latencyMs: calls.reduce((sum, call) => sum + call.latencyMs, 0),
    toolCallCount,
    status,
  }
}

export interface AgentTurnInput {
  scope: AgentScope
  conversationId: string
  activeVisitId: string | null
  conversationTurnId: string
  conversationTurnIndex: number
  conversationContextEpoch: number
  text: string
  attachment?: AgentTurnAttachment | null
  recentTurns: readonly AgentHistoryTurn[]
  pendingAction: unknown
  activeIntake: unknown
}

export type AgentTurnResult =
  | {
    status: 'replied'
    reply: string
    providerResponseId: string
    provider?: string
    model?: string
    toolCallCount: number
    /**
     * Aggregated across every `respond()` call this turn made (see
     * `AgentTurnTelemetry`). Null only when no provider call ever completed
     * — not expected on a `replied` result, but the field stays defensive.
     */
    telemetry?: AgentTurnTelemetry | null
  }
  | {
    status:
      | 'provider_unavailable'
      | 'provider_timeout'
      | 'tool_limit_exceeded'
      | 'invalid_model_output'
    toolCallCount: number
    /**
     * A `provider_unavailable` / `provider_timeout` turn is exactly the one
     * most worth observing, so telemetry is carried out for every status,
     * not just `replied`. It is null when the failure happened before ANY
     * provider call in the turn ever completed — e.g. the runtime's OWN
     * deadline (`AgentRuntimeTimeoutError`) fired while the very first
     * provider call was still in flight, so there is nothing yet to report.
     */
    telemetry?: AgentTurnTelemetry | null
  }

export interface AgentRuntimeDependencies {
  provider: AgentProvider
  executeTool(call: AgentToolCall): Promise<AgentToolResult>
  maxTurnMs?: number
}

const MAX_HISTORY_TURNS = 20
const MAX_HISTORY_TEXT_CHARS = 4000
const MAX_CURRENT_TEXT_CHARS = 8000
const MAX_TOOL_OUTPUT_CHARS = 32_000
const MAX_REPLY_CHARS = 4000
/**
 * Slice of the turn budget held back for the final-answer pass.
 *
 * Sized for one provider inference with no tool round trip — the final pass
 * calls the model once and does nothing else. Held back from the TOOL passes
 * so that a turn which spends its whole budget gathering still has room to
 * say what it gathered, instead of timing out into a 502 the caller can only
 * retry into the same wall.
 */
const FINAL_PASS_RESERVE_MS = 4_000
const knownToolNames: ReadonlySet<string> = new Set(
  AGENT_TOOL_DEFINITIONS.map((definition) => definition.name),
)

export async function runAgentTurn(
  input: AgentTurnInput,
  dependencies: AgentRuntimeDependencies,
): Promise<AgentTurnResult> {
  const maxTurnMs = dependencies.maxTurnMs ?? 20_000
  const deadline = Date.now() + maxTurnMs
  const modelInput = buildInitialInput(input)
  const instructions = buildAgentInstructions({
    scope: input.scope,
    conversationId: input.conversationId,
    activeVisitId: input.activeVisitId,
    pendingAction: input.pendingAction,
    activeIntake: input.activeIntake,
  })
  let toolCallCount = 0
  // Every `respond()` call's own telemetry, in call order, across the whole
  // turn — a turn can make several calls (one per tool-calling pass, plus
  // the final-answer pass), and with the provider's "sticky fallback"
  // behavior different calls can land on different models. Aggregated into
  // an `AgentTurnTelemetry` (see `buildTurnTelemetry`) at every return
  // point, so the turn-level picture is what callers and the two
  // observability sinks (structured log line, `provider_telemetry_json`)
  // see — never a single call's.
  const callTelemetry: AgentProviderTelemetry[] = []
  // Set the moment the tool budget is spent. The NEXT provider call is then a
  // final-answer pass: the catalogue is withdrawn and tool calling is
  // forbidden, so the model has to answer from what it already collected.
  //
  // Before this existed, running out of tool budget returned
  // `tool_limit_exceeded`, which both doors map to a 502 "the assistant is
  // temporarily unavailable" — a dead end for the caller, who then retries and
  // spends the same budget on the same tools for the same non-answer. The
  // model had usually already gathered enough to answer; nothing ever asked it
  // to.
  //
  // Termination: `forcedFinal` is only ever set, never cleared, and the pass
  // it triggers cannot re-enter the tool branch, because a response that still
  // contains a function call while `forcedFinal` is set ends the turn instead
  // of being answered. So the loop runs at most one extra iteration, whatever
  // the model does.
  let forcedFinal = false

  while (true) {
    // The final pass gets a RESERVED slice of the turn budget. Without it, a
    // turn whose tool calls ate the whole 20s never reaches the final pass at
    // all and returns `provider_timeout` — the same 502 dead end the final
    // pass exists to remove, just arrived at a different way. Running out of
    // tool time is itself a reason to answer with what was gathered, so the
    // exhausted budget promotes the turn to its final pass rather than
    // failing it.
    const effectiveDeadline = forcedFinal
      ? deadline
      : deadline - FINAL_PASS_RESERVE_MS
    const remainingMs = effectiveDeadline - Date.now()
    if (remainingMs <= 0) {
      if (!forcedFinal) {
        forcedFinal = true
        continue
      }
      return {
        status: 'provider_timeout',
        toolCallCount,
        telemetry: buildTurnTelemetry(callTelemetry, toolCallCount, 'provider_timeout'),
      }
    }
    let response
    // A FRESH controller per await. Sharing one across the whole turn meant a
    // single timeout poisoned every later call: a tool that overran aborted
    // the provider request that was supposed to deliver the answer. Each
    // operation now owns its own cancellation.
    const providerAbort = new AbortController()
    try {
      response = await withTimeout(
        dependencies.provider.respond(
          {
            instructions,
            input: modelInput,
            // The CATALOGUE IS STILL SENT on the final pass. `tool_choice:
            // 'none'` is what forbids the call; withdrawing `tools` as well
            // would only save input tokens on one request per over-budget
            // turn, in exchange for an unproven request shape — and the
            // request already carries `function_call` items in `input` from
            // the passes that did run. Neither provider has been verified to
            // accept `tools: []` alongside those, and OpenRouter's
            // `/v1/responses` shim (see agent_provider.ts) is materially less
            // forgiving than OpenAI's. A 400 here would turn the recovery
            // path into a NEW failure, which is strictly worse than the
            // `tool_limit_exceeded` it exists to replace.
            tools: AGENT_MODEL_TOOL_DEFINITIONS,
            ...(forcedFinal ? { toolChoice: 'none' as const } : {}),
          },
          { signal: providerAbort.signal },
        ),
        remainingMs,
        providerAbort,
      )
    } catch (error) {
      if (error instanceof AgentRuntimeTimeoutError) {
        // The RUNTIME's own deadline fired while a provider call was still
        // in flight (aborted via `providerAbort`, above) — this is distinct
        // from the provider's internal per-attempt timeout
        // (`attempt_timeout` in agent_provider.ts), and that in-flight call
        // never returned telemetry. Whatever EARLIER calls this turn already
        // completed are still aggregated below.
        return {
          status: 'provider_timeout',
          toolCallCount,
          telemetry: buildTurnTelemetry(callTelemetry, toolCallCount, 'provider_timeout'),
        }
      }
      // `AgentProviderError` carries its own best-effort telemetry for THIS
      // call (see agent_provider.ts) so a total failure is still observable
      // — fold it into the turn's aggregate rather than discarding it.
      if (error instanceof AgentProviderError && error.telemetry) {
        callTelemetry.push(error.telemetry)
      }
      return {
        status: 'provider_unavailable',
        toolCallCount,
        telemetry: buildTurnTelemetry(callTelemetry, toolCallCount, 'provider_unavailable'),
      }
    }

    if (response.telemetry) callTelemetry.push(response.telemetry)

    const functionItems = response.output.filter((item) =>
      item.type === 'function_call'
    )
    if (functionItems.length === 0) {
      const reply = extractAssistantText(response.output)
      if (!reply) {
        const status = forcedFinal ? 'tool_limit_exceeded' : 'invalid_model_output'
        return {
          status,
          toolCallCount,
          telemetry: buildTurnTelemetry(callTelemetry, toolCallCount, status),
        }
      }
      return {
        status: 'replied',
        reply: normalizeTelegramReply(reply).slice(0, MAX_REPLY_CHARS),
        providerResponseId: response.id,
        provider: response.provider,
        model: response.model,
        toolCallCount,
        telemetry: buildTurnTelemetry(callTelemetry, toolCallCount, 'replied'),
      }
    }

    // A provider that called a tool anyway, on a request that withdrew the
    // catalogue and forbade tool calls. Nothing further is worth spending: the
    // turn ends here rather than looping.
    if (forcedFinal) {
      return {
        status: 'tool_limit_exceeded',
        toolCallCount,
        telemetry: buildTurnTelemetry(callTelemetry, toolCallCount, 'tool_limit_exceeded'),
      }
    }

    modelInput.push(...response.output.map((item) => structuredClone(item)))
    for (const item of functionItems) {
      let toolResult: AgentToolResult
      const parsed = parseToolCall(item)
      if (toolCallCount >= MAX_AGENT_TOOL_CALLS_PER_TURN) {
        // Refused, not executed — but still ANSWERED. Every `function_call`
        // in the model input needs a matching `function_call_output` or the
        // next provider request is rejected outright, and the refusal names
        // the limit so the final pass can say what it could not check.
        forcedFinal = true
        toolResult = {
          ok: false,
          code: 'tool_limit_reached',
          data: { limit: MAX_AGENT_TOOL_CALLS_PER_TURN },
        }
      } else {
        toolCallCount += 1
        if (!parsed) {
          toolResult = {
            ok: false,
            code: 'invalid_arguments',
            data: null,
          }
        } else if (!knownToolNames.has(parsed.call.name)) {
          toolResult = {
            ok: false,
            code: 'unknown_tool',
            data: null,
          }
        } else {
          const toolAbort = new AbortController()
          try {
            toolResult = await withTimeout(
              dependencies.executeTool({
                ...parsed.call,
                sequence: toolCallCount,
              }),
              // Bounded by the TOOL deadline, not the turn deadline, so a
              // slow tool cannot eat the slice reserved for the answer.
              Math.max(1, deadline - FINAL_PASS_RESERVE_MS - Date.now()),
              toolAbort,
            )
          } catch (error) {
            if (error instanceof AgentRuntimeTimeoutError) {
              // A slow tool used to END the turn — a 502 the caller could
              // only retry into the same slow tool. It is now just a tool
              // that did not answer: the model is told so, and the turn goes
              // straight to its final pass to say what it does have.
              forcedFinal = true
              toolResult = {
                ok: false,
                code: 'tool_timeout',
                data: {
                  toolName: parsed.call.name,
                  message: {
                    en:
                      'That lookup did not finish in time. Answer with what you already have and say which part you could not check.',
                    ar:
                      'لم يكتمل هذا الاستعلام في الوقت المتاح. أجب بما لديك واذكر الجزء الذي تعذّر التحقق منه.',
                  },
                },
              }
            } else {
              toolResult = { ok: false, code: 'tool_failed', data: null }
            }
          }
        }
      }
      modelInput.push({
        type: 'function_call_output',
        call_id: parsed?.callId ?? safeCallId(item),
        output: boundedJson(toolResult),
      })
    }
  }
}

function buildInitialInput(input: AgentTurnInput): AgentModelInputItem[] {
  const turns = input.recentTurns.slice(-MAX_HISTORY_TURNS)
  const items: AgentModelInputItem[] = turns.map((turn) => ({
    role: turn.role,
    content: turn.text.slice(-MAX_HISTORY_TEXT_CHARS),
  }))
  const currentContent: Record<string, unknown> = {
    role: 'user',
    content: currentMessageContent(input),
  }
  items.push(currentContent)
  return items
}

function currentMessageContent(input: AgentTurnInput): unknown {
  const text = input.text.slice(0, MAX_CURRENT_TEXT_CHARS)
  if (!input.attachment) return text
  const content: Array<Record<string, unknown>> = []
  if (text) content.push({ type: 'input_text', text })
  if (
    input.attachment.kind === 'image' &&
    input.attachment.fileData
  ) {
    content.push({
      type: 'input_image',
      image_url: input.attachment.fileData,
      detail: 'high',
    })
  } else if (input.attachment.fileData) {
    content.push({
      type: 'input_file',
      filename: input.attachment.fileName ?? 'telegram-upload',
      file_data: input.attachment.fileData,
    })
  } else {
    content.push({
      type: 'input_text',
      text: `Untrusted attachment metadata: ${
        JSON.stringify({
          kind: input.attachment.kind,
          fileName: input.attachment.fileName,
          mimeType: input.attachment.mimeType,
        })
      }`,
    })
  }
  return content
}

function parseToolCall(
  item: AgentModelOutputItem,
): { call: AgentToolCall; callId: string } | null {
  if (
    typeof item.name !== 'string' ||
    typeof item.arguments !== 'string'
  ) return null
  const callId = safeCallId(item)
  try {
    const args: unknown = JSON.parse(item.arguments)
    if (!isRecord(args)) return null
    return {
      call: {
        id: callId,
        name: item.name,
        arguments: args,
      },
      callId,
    }
  } catch (_) {
    return null
  }
}

function safeCallId(item: AgentModelOutputItem): string {
  if (
    typeof item.call_id === 'string' &&
    item.call_id.trim().length > 0 &&
    item.call_id.length <= 200
  ) return item.call_id
  if (
    typeof item.id === 'string' &&
    item.id.trim().length > 0 &&
    item.id.length <= 200
  ) return item.id
  return crypto.randomUUID()
}

function extractAssistantText(
  output: readonly AgentModelOutputItem[],
): string | null {
  const chunks: string[] = []
  for (const item of output) {
    if (
      item.type !== 'message' || item.role !== 'assistant' ||
      !Array.isArray(item.content)
    ) continue
    for (const content of item.content) {
      if (
        isRecord(content) && content.type === 'output_text' &&
        typeof content.text === 'string'
      ) {
        const text = content.text.trim()
        if (text) chunks.push(text)
      }
    }
  }
  return chunks.length === 0 ? null : chunks.join('\n')
}

function normalizeTelegramReply(value: string): string {
  return value
    .replaceAll('**', '')
    .replaceAll('__', '')
    .replace(/```(?:[a-z0-9_-]+)?\n?/gi, '')
    .replaceAll('```', '')
    .replaceAll('`', '')
    .trim()
}

function boundedJson(value: unknown): string {
  const encoded = JSON.stringify(value)
  return encoded.length <= MAX_TOOL_OUTPUT_CHARS ? encoded : JSON.stringify({
    ok: false,
    code: 'tool_output_too_large',
    data: null,
  })
}

function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  controller: AbortController,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      controller.abort()
      reject(new AgentRuntimeTimeoutError())
    }, timeoutMs)
    promise.then(
      (value) => {
        clearTimeout(timer)
        resolve(value)
      },
      (error) => {
        clearTimeout(timer)
        reject(error)
      },
    )
  })
}

class AgentRuntimeTimeoutError extends Error {}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
