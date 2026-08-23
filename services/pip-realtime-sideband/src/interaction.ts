// Interaction attribution and the per-interaction tool budget.
//
// WHY THIS EXISTS
//
// The edge-function agent enforces MAX_AGENT_TOOL_CALLS_PER_TURN inside its own
// request loop. A direct Realtime caller does not run that loop, so it inherits
// nothing: the cap has to be enforced here or it does not exist.
//
// The unit the cap applies to is an INTERACTION, not a generation. A generation
// is a whole call leg — capping tools across it would let one long conversation
// starve its own later turns. An interaction is one user utterance and the
// entire response chain it provokes, INCLUDING the continuation responses the
// model produces after each `function_call_output`. Five tools per interaction,
// fresh budget for the next one.
//
// The provider gives us no field linking a continuation response back to the
// user input item that started it. `input_audio_buffer.committed` carries a
// stable `item_id` before transcription finalizes, and after that the chain is
// ours to track. That tracking is this module's entire job.

export const INTERACTION_FROM_ITEM = 'item'
export const INTERACTION_FROM_RESPONSE = 'resp'

/**
 * What the sideband should do with the response chain after answering one
 * tool call. See `InteractionTracker#tryConsumeContinuation`.
 *
 *  * `continue` — send a plain `response.create`; the model may call more
 *    tools.
 *  * `final`    — send `response.create` with `tool_choice: 'none'`. The
 *    provider CANNOT emit a function call in that response, so it cannot
 *    produce another `function_call_output`, so it cannot produce another
 *    continuation. This is the deterministic terminator of the chain, not a
 *    hope that the model stops asking.
 *  * `suppress` — send nothing. The chain is already terminated (a `final`
 *    went out) or this worker no longer owns the session.
 */
export type ContinuationDecision = 'continue' | 'final' | 'suppress'

export type ToolBudgetDecision =
  | {
    readonly allowed: true
    readonly interactionId: string
    readonly toolSequence: number
  }
  | {
    readonly allowed: false
    readonly interactionId: string
    readonly reason: 'interaction_tool_limit'
    readonly used: number
    readonly limit: number
  }

interface InteractionState {
  readonly id: string
  toolCalls: number
  /** `response.create` frames this sideband has sent for this interaction. */
  continuations: number
  /** A `tool_choice: 'none'` response has gone out; nothing may follow it. */
  finalForced: boolean
}

/**
 * Headroom over the tool budget for the continuation cap. The tool budget
 * already bounds SUCCESSFUL calls, but a REJECTED call (limit reached, not
 * live, unknown tool, argument conflict, duplicate delivery) is answered and
 * continued without ever spending tool budget — which is precisely how a
 * `tool -> error -> response.create -> same tool -> error` cycle used to run
 * unbounded. Two spare continuations cover the ordinary honest cases (one
 * duplicate redelivery, one forced final) without letting a rejection storm
 * run free.
 */
const CONTINUATION_HEADROOM = 2

/**
 * Upper bound on the per-session maps below.
 *
 * Both are keyed by ids the provider mints and neither had any eviction: on a
 * long call they only ever grew. That is now bounded from the outside too —
 * the cleanup sweep terminalizes a session past `active_expires_at` — but a
 * memory bound that depends on another component doing its job is not a
 * bound. Eviction is oldest-first, which is safe because attribution is only
 * ever read for a response that is still in flight or has just finished; an
 * interaction this far back cannot receive another tool call, and the budget
 * it would draw on is spent either way.
 *
 * Sized well above any real conversation: 512 interactions is hours of
 * continuous back-and-forth.
 */
const MAX_TRACKED_INTERACTIONS = 512

export class InteractionTracker {
  readonly #limit: number
  readonly #continuationLimit: number
  readonly #interactions = new Map<string, InteractionState>()
  /** response_id -> interaction id. The chain attribution the provider does not give us. */
  readonly #responseInteraction = new Map<string, string>()
  /** An interaction whose input has been committed but whose root response has not begun. */
  #pendingRootInteractionId: string | null = null
  /** Set when tool output is submitted: the NEXT new response continues that interaction. */
  #expectedContinuationId: string | null = null
  #toolSequence = 0

  constructor(limit: number, continuationLimit?: number) {
    if (!Number.isInteger(limit) || limit < 1) {
      throw new Error(`interaction tool limit must be a positive integer, got ${limit}`)
    }
    const continuations = continuationLimit ?? limit + CONTINUATION_HEADROOM
    if (!Number.isInteger(continuations) || continuations < 1) {
      throw new Error(
        `interaction continuation limit must be a positive integer, got ${continuations}`,
      )
    }
    this.#limit = limit
    this.#continuationLimit = continuations
  }

  get limit(): number {
    return this.#limit
  }

  get continuationLimit(): number {
    return this.#continuationLimit
  }

  /** Interactions seen so far — diagnostics only, never a budget input. */
  get interactionCount(): number {
    return this.#interactions.size
  }

  #ensure(id: string): InteractionState {
    let state = this.#interactions.get(id)
    if (!state) {
      state = { id, toolCalls: 0, continuations: 0, finalForced: false }
      this.#interactions.set(id, state)
      evictOldest(this.#interactions)
    }
    return state
  }

  /**
   * `input_audio_buffer.committed`. Opens a new interaction keyed on the stable
   * provider item id, which exists BEFORE the transcript finalizes — waiting for
   * the transcript would delay every tool call by a transcription round trip.
   *
   * A commit also ends any chain in flight: the user barged in, so continuation
   * responses now belong to the new utterance.
   */
  noteInputCommitted(itemId: string): string {
    const interactionId = `${INTERACTION_FROM_ITEM}:${itemId}`
    this.#ensure(interactionId)
    this.#pendingRootInteractionId = interactionId
    this.#expectedContinuationId = null
    return interactionId
  }

  /**
   * `response.created`. Resolution order matters:
   *   1. already attributed (redelivery) — keep the original answer;
   *   2. a continuation we ourselves triggered with a `function_call_output`;
   *   3. the interaction opened by the most recent committed input;
   *   4. no user input at all (a server-initiated response) — fall back to
   *      `resp:<root_response_id>` so evidence is still attributable.
   */
  noteResponseCreated(responseId: string): string {
    const existing = this.#responseInteraction.get(responseId)
    if (existing) return existing

    let interactionId: string
    if (this.#expectedContinuationId) {
      interactionId = this.#expectedContinuationId
      this.#expectedContinuationId = null
    } else if (this.#pendingRootInteractionId) {
      interactionId = this.#pendingRootInteractionId
      this.#pendingRootInteractionId = null
    } else {
      interactionId = `${INTERACTION_FROM_RESPONSE}:${responseId}`
    }

    this.#ensure(interactionId)
    this.#responseInteraction.set(responseId, interactionId)
    evictOldest(this.#responseInteraction)
    return interactionId
  }

  /**
   * Attribution for an event that carries a response id but arrived without a
   * preceding `response.created` (redelivery, or a truncated event stream).
   *
   * MINTS an interaction when `responseId` is unknown (delegates to
   * `noteResponseCreated`, which consumes `#pendingRootInteractionId`, calls
   * `#ensure`, and can evict). That is correct for callers that are handling
   * a real event needing budget/continuation attribution (e.g.
   * `tryConsumeToolBudget`, or a tool-call rejection in `claims.ts` that still
   * owes the caller an `interactionId`). It is WRONG for a pure telemetry
   * read — see `lookupInteractionForResponse` below, which is what
   * `#persistResponseUsage` uses instead.
   */
  interactionForResponse(responseId: string): string {
    return this.#responseInteraction.get(responseId) ??
      this.noteResponseCreated(responseId)
  }

  /**
   * Pure attribution lookup: never mints an interaction, never touches
   * `#pendingRootInteractionId` or `#expectedContinuationId`, never evicts.
   * Returns null when `responseId` has no recorded attribution (no preceding
   * `response.created` was ever observed for it — a redelivery or a
   * truncated event stream).
   *
   * This exists so telemetry can OBSERVE attribution without being able to
   * ALTER budget-tracking state. `#persistResponseUsage` in sideband.ts is a
   * read for a database column, not an event the tracker needs to react to —
   * using the minting `interactionForResponse` there would let telemetry
   * invent an interaction the tracker had otherwise never seen, silently
   * consuming `#pendingRootInteractionId` and polluting the very state this
   * class exists to protect (see `ResponseUsageInsert.interactionId` in
   * store.ts, which documents null as the honest answer here).
   */
  lookupInteractionForResponse(responseId: string): string | null {
    return this.#responseInteraction.get(responseId) ?? null
  }

  /**
   * Called after `function_call_output` + `response.create`: the next response
   * the provider opens is a continuation of the SAME interaction and must draw
   * from the same budget, otherwise a tool loop would reset its own cap.
   */
  noteToolOutputSubmitted(interactionId: string): void {
    this.#expectedContinuationId = interactionId
  }

  /** Budget check + allocation. Call BEFORE executing the tool, never after. */
  tryConsumeToolBudget(responseId: string): ToolBudgetDecision {
    const interactionId = this.interactionForResponse(responseId)
    const state = this.#ensure(interactionId)
    if (state.toolCalls >= this.#limit) {
      return {
        allowed: false,
        interactionId,
        reason: 'interaction_tool_limit',
        used: state.toolCalls,
        limit: this.#limit,
      }
    }
    state.toolCalls += 1
    this.#toolSequence += 1
    return { allowed: true, interactionId, toolSequence: this.#toolSequence }
  }

  toolCallsUsed(interactionId: string): number {
    return this.#interactions.get(interactionId)?.toolCalls ?? 0
  }

  continuationsUsed(interactionId: string): number {
    return this.#interactions.get(interactionId)?.continuations ?? 0
  }

  /**
   * Budget check + allocation for ONE `response.create` the sideband is about
   * to send after answering a tool call. Call immediately before the send,
   * never after, and honour the answer:
   *
   *   * once this returns `final`, the interaction is closed to further
   *     continuations forever — every later call for the same interaction
   *     returns `suppress`, including a `forceFinal` one;
   *   * `forceFinal` is for a rejection where another tool-calling response
   *     is provably useless (the tool budget is already spent, so the next
   *     call would be rejected identically). Spending an inference on it
   *     buys nothing but latency and another spoken turn.
   *
   * The cap is what makes termination independent of the model's behaviour:
   * even a model that calls a tool on every single continuation runs out of
   * continuations, and the last one it gets cannot contain a tool call.
   */
  tryConsumeContinuation(
    interactionId: string,
    options: { forceFinal?: boolean } = {},
  ): ContinuationDecision {
    const state = this.#ensure(interactionId)
    if (state.finalForced) return 'suppress'
    state.continuations += 1
    if (options.forceFinal === true || state.continuations >= this.#continuationLimit) {
      state.finalForced = true
      return 'final'
    }
    return 'continue'
  }

  /**
   * `response.done`. If the response produced no tool call we are not expecting a
   * continuation, so the chain closes here and a later server-initiated response
   * will open its own interaction.
   */
  noteResponseDone(responseId: string, producedToolCall: boolean): void {
    if (!producedToolCall) {
      const interactionId = this.#responseInteraction.get(responseId)
      if (interactionId && this.#expectedContinuationId === interactionId) {
        this.#expectedContinuationId = null
      }
    }
  }
}

/**
 * Drop insertion-oldest entries until the map is within bounds. `Map`
 * iterates in insertion order, so the first key is the oldest.
 */
function evictOldest(map: Map<string, unknown>): void {
  while (map.size > MAX_TRACKED_INTERACTIONS) {
    const oldest = map.keys().next()
    if (oldest.done) return
    map.delete(oldest.value)
  }
}
