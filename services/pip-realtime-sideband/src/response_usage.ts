// Pure parser for a `response.done` event's `response.usage` block.
//
// This module owns exactly one job: turn whatever OpenAI put in `usage` into a
// flat, all-numbers shape the store can insert directly. It never talks to the
// network or the store, and it never throws — a malformed or absent usage
// block is real production signal (a failed/rate-limited response arrives
// with `status: 'failed'` and `usage` all-zero or missing entirely), and
// losing that signal to an exception would be worse than recording zeros.

/** One response's token accounting, flattened for direct column insertion. */
export interface ResponseUsage {
  readonly responseId: string
  /** 'completed' | 'failed' | 'cancelled' | 'incomplete' | whatever the provider sends. */
  readonly status: string
  readonly totalTokens: number
  readonly inputTokens: number
  readonly outputTokens: number
  /** From `input_token_details.cached_tokens`. */
  readonly cachedInputTokens: number
  /** DERIVED: `max(0, inputTokens - cachedInputTokens)`, never negative even
   * if the provider ever reports cached > input. */
  readonly uncachedInputTokens: number
  readonly inputTextTokens: number
  readonly inputAudioTokens: number
  readonly inputImageTokens: number
  /** From `input_token_details.cached_tokens_details`. */
  readonly cachedTextTokens: number
  readonly cachedAudioTokens: number
  readonly outputTextTokens: number
  readonly outputAudioTokens: number
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' ? value as Record<string, unknown> : {}
}

/**
 * Missing or non-number fields become 0, never null/NaN — a malformed value is
 * not a reason to lose the rest of the row.
 *
 * The result is additionally coerced to a NON-NEGATIVE INTEGER, and that is
 * load-bearing rather than defensive tidiness: every token column in
 * `agent_realtime_response_usage` is `integer not null check (… >= 0)`, so a
 * float or a negative would be rejected by PostgREST with a 400 that
 * `#persistResponseUsage` catches and logs — the row would vanish silently,
 * which is the one outcome a telemetry table must never have. Truncating
 * toward zero (rather than rounding) keeps a token count from ever being
 * reported as higher than what the provider sent.
 */
function num(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 0
  return Math.max(0, Math.trunc(value))
}

/**
 * Parse a `response.done` event's `response` object into a durable usage row.
 *
 * Returns null only when there is no usable response id — every other field
 * defaults to 0/'completed' rather than aborting, because a zero-usage row
 * off a failed/rate-limited response IS the signal this table exists to
 * capture. The caller decides whether to persist; this function never drops
 * rows on its own judgement.
 */
export function parseResponseUsage(
  response: Record<string, unknown>,
): ResponseUsage | null {
  const responseId = typeof response.id === 'string' ? response.id : ''
  if (responseId === '') return null

  const status = typeof response.status === 'string' && response.status !== ''
    ? response.status
    : 'completed'

  const usage = asRecord(response.usage)
  const inputDetails = asRecord(usage.input_token_details)
  const cachedDetails = asRecord(inputDetails.cached_tokens_details)
  const outputDetails = asRecord(usage.output_token_details)

  const inputTokens = num(usage.input_tokens)
  const cachedInputTokens = num(inputDetails.cached_tokens)

  return {
    responseId,
    status,
    totalTokens: num(usage.total_tokens),
    inputTokens,
    outputTokens: num(usage.output_tokens),
    cachedInputTokens,
    uncachedInputTokens: Math.max(0, inputTokens - cachedInputTokens),
    inputTextTokens: num(inputDetails.text_tokens),
    inputAudioTokens: num(inputDetails.audio_tokens),
    inputImageTokens: num(inputDetails.image_tokens),
    cachedTextTokens: num(cachedDetails.text_tokens),
    cachedAudioTokens: num(cachedDetails.audio_tokens),
    outputTextTokens: num(outputDetails.text_tokens),
    outputAudioTokens: num(outputDetails.audio_tokens),
  }
}
