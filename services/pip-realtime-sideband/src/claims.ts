// Tool-call claiming, execution and evidence.
//
// INVARIANTS THIS FILE OWNS
//
//  1. Claim BEFORE executing. The claim ledger — keyed (session, generation,
//     tool_call_id) for Realtime — is what makes a redelivered tool call
//     idempotent. Executing first and recording after would let a reconnect
//     double-apply a write.
//
//  2. Never wait for the transcript. Transcription finalizes asynchronously and
//     may never finalize at all; blocking tool execution on it would stall the
//     conversation on the provider's ASR latency.
//
//  3. Evidence is IMMUTABLE. `agent_tool_events` has a trigger that raises on
//     UPDATE and DELETE, so the row is written once, with
//     `conversation_turn_id = NULL` and the interaction id set. The turn link is
//     back-filled later on the MUTABLE CLAIM instead. No placeholder turn is
//     ever fabricated to satisfy a foreign key.
//
//  4. The argument hash is part of the identity. Same call id with different
//     arguments is not a redelivery — it is a conflict, and it is rejected
//     rather than silently executed against the newer arguments.
//
//  5. EXACTLY ONE component owns the ledger for a given call. Invariants 1–4
//     describe the SELF-OWNED mode, where this service is that component. When
//     the executor is the `pip-realtime-tool-broker`, the broker owns the claim
//     and the evidence instead: it is the only component that re-resolves
//     authorization, enforces argument scope and knows the terminal result, and
//     both tables carry partial unique indexes on the Realtime key, so a second
//     writer is a unique violation rather than a duplicate row. The mode is a
//     REQUIRED, discriminated constructor argument (`ToolLedgerOwnership`) —
//     there is no default, because the wrong default is a wedged voice session.
//
//  What stays here in BOTH modes: the per-interaction tool budget, the
//  fence/lease and generation liveness guard, and the guarantee that the model
//  always receives a real `function_call_output`.

import { argumentHash, isoAt, newId, timingSafeEqual } from './ids.ts'
import { log } from './log.ts'
import type { RealtimeStore, ToolClaimState } from './store.ts'
import type { InteractionTracker } from './interaction.ts'

export interface ToolExecutionContext {
  readonly sessionId: string
  readonly generation: number
  readonly interactionId: string
  readonly toolCallId: string
  readonly toolName: string
  /**
   * The fingerprint STAMPED on this session when it was provisioned. Carried in
   * the context rather than captured in a closure because it is per session,
   * while the executor is built once per process. A remote executor forwards it
   * as a claim to be re-derived and compared, never as an authority.
   */
  readonly authorizationFingerprint: string
}

export interface ToolOutcome {
  readonly status: 'succeeded' | 'rejected' | 'failed'
  readonly result: unknown
  /**
   * Set by a LEDGER-OWNING executor when its answer is a replay of a claim it
   * had already recorded. The sideband cannot detect this itself in brokered
   * mode — it keeps no claim of its own — so the broker's word is authoritative.
   */
  readonly duplicate?: boolean
}

export type ToolExecutor = (
  args: unknown,
  context: ToolExecutionContext,
) => Promise<ToolOutcome>

export type ToolCallDisposition =
  | 'executed'
  | 'duplicate'
  | 'rejected_tool_limit'
  | 'rejected_argument_mismatch'
  | 'rejected_unknown_tool'
  | 'rejected_not_live'
  | 'failed'

/**
 * WHO OWNS THE DURABLE LEDGER (`agent_tool_call_claims` + `agent_tool_events`)
 * for the calls this coordinator runs. Discriminated and required: a boolean
 * with a default would make "both components write" — the failure this type
 * exists to prevent — the thing you get by forgetting to say anything.
 *
 *  * `'sideband'` — this service claims before executing, writes the immutable
 *    evidence row, and settles the claim. Correct for an in-process executor
 *    that touches nothing durable of its own.
 *
 *  * `'broker'` — `pip-realtime-tool-broker` does all of that, inside the same
 *    transaction boundary as the tool it executes. This service writes NEITHER
 *    table for the call and treats the broker's answer, including its duplicate
 *    replay, as authoritative.
 */
export type ToolLedgerOwnership =
  | {
    readonly ledger: 'sideband'
    readonly executors: ReadonlyMap<string, ToolExecutor>
  }
  | {
    readonly ledger: 'broker'
    readonly executors: ReadonlyMap<string, ToolExecutor>
  }

/**
 * Guard consulted immediately before a tool call is budgeted or executed.
 * Returns a reason code when this worker may no longer act for the
 * (session, generation) — a lost fence, a released lease, a superseded
 * generation — or null when it may. Enforced in BOTH ownership modes: it is the
 * sideband's own authority to check, not the broker's.
 */
export type LivenessCheck = () => string | null

export interface ToolCallResult {
  readonly disposition: ToolCallDisposition
  readonly interactionId: string
  /** The payload sent back as `function_call_output`. Always a real value. */
  readonly output: unknown
}

export interface ToolCallCoordinatorOptions {
  readonly store: RealtimeStore
  readonly tracker: InteractionTracker
  readonly sessionId: string
  readonly generation: number
  readonly leaseOwner: string
  readonly leaseSeconds: number
  /** Stamped on the session at provisioning; forwarded to a remote executor. */
  readonly authorizationFingerprint: string
  readonly now: () => Date
  /** REQUIRED. See ToolLedgerOwnership — there is deliberately no default. */
  readonly ownership: ToolLedgerOwnership
  /** Optional in tests; wired to the lease + generation in production. */
  readonly liveness?: LivenessCheck
}

function errorOutput(code: string, detail: string): Record<string, unknown> {
  return { ok: false, error: code, detail }
}

export class ToolCallCoordinator {
  readonly #options: ToolCallCoordinatorOptions

  constructor(options: ToolCallCoordinatorOptions) {
    this.#options = options
  }

  /**
   * Full round trip for one `response.output_item.done` of type `function_call`.
   * Always resolves with an output to send: a tool call left unanswered wedges
   * the model, so even a rejection produces a real `function_call_output`.
   */
  async handleToolCall(input: {
    responseId: string
    toolCallId: string
    toolName: string
    args: unknown
  }): Promise<ToolCallResult> {
    const { store, tracker, sessionId, generation } = this.#options
    const brokered = this.#options.ownership.ledger === 'broker'

    // Liveness first. A worker that lost its fence must not spend budget, must
    // not claim, and must not execute — in either ownership mode.
    const notLive = this.#options.liveness?.() ?? null
    if (notLive) {
      log.warn('tool.rejected_not_live', {
        session_id: sessionId,
        generation,
        tool_name: input.toolName,
        reason: notLive,
      })
      return {
        disposition: 'rejected_not_live',
        interactionId: tracker.interactionForResponse(input.responseId),
        output: errorOutput(
          'session_not_live',
          'This voice session is no longer the live one. Nothing was done.',
        ),
      }
    }

    const decision = tracker.tryConsumeToolBudget(input.responseId)
    if (!decision.allowed) {
      log.warn('tool.rejected_interaction_limit', {
        session_id: sessionId,
        generation,
        interaction_id: decision.interactionId,
        tool_name: input.toolName,
        used: decision.used,
        limit: decision.limit,
      })
      return {
        disposition: 'rejected_tool_limit',
        interactionId: decision.interactionId,
        output: errorOutput(
          'tool_limit_reached',
          `This turn already used its ${decision.limit} tool calls. ` +
            'Answer with what you have, or ask the user to continue.',
        ),
      }
    }

    const interactionId = decision.interactionId
    const hash = await argumentHash(input.args)
    const executor = this.#options.ownership.executors.get(input.toolName)

    // Identity check first: an existing claim decides whether this is a
    // redelivery (return the settled answer, do not re-run) or a conflict.
    // Skipped when the broker owns the ledger — reading a row it may be writing
    // in the same instant would only produce a second, staler opinion of a
    // decision that is already the broker's to make.
    const existing = brokered
      ? null
      : await store.loadToolClaim(sessionId, generation, input.toolCallId)
    if (existing) {
      if (!timingSafeEqual(existing.argumentHash, hash)) {
        log.warn('tool.argument_hash_mismatch', {
          session_id: sessionId,
          generation,
          interaction_id: interactionId,
          tool_name: input.toolName,
        })
        return {
          disposition: 'rejected_argument_mismatch',
          interactionId,
          output: errorOutput(
            'argument_conflict',
            'This tool call id was already claimed with different arguments.',
          ),
        }
      }
      log.info('tool.duplicate_claim', {
        session_id: sessionId,
        generation,
        interaction_id: interactionId,
        tool_name: input.toolName,
        claim_state: existing.state,
      })
      return {
        disposition: 'duplicate',
        interactionId,
        output: existing.state === 'succeeded'
          ? { ok: true, duplicate: true }
          : errorOutput('duplicate_call', `Already ${existing.state}.`),
      }
    }

    if (!executor) {
      return {
        disposition: 'rejected_unknown_tool',
        interactionId,
        output: errorOutput('unknown_tool', 'No such tool is available.'),
      }
    }

    const startedAt = this.#options.now()

    if (brokered) {
      return await this.#runBrokered(input, executor, interactionId, startedAt)
    }

    const claimId = newId('rtclaim')
    const inserted = await store.insertToolClaim({
      id: claimId,
      realtimeSessionId: sessionId,
      realtimeGeneration: generation,
      realtimeInteractionId: interactionId,
      openaiToolCallId: input.toolCallId,
      toolName: input.toolName,
      argumentHash: hash,
      state: 'claimed',
      leaseOwner: this.#options.leaseOwner,
      leaseExpiresAt: new Date(
        startedAt.getTime() + this.#options.leaseSeconds * 1000,
      ).toISOString(),
      claimedAt: startedAt.toISOString(),
    })

    if (inserted === 'duplicate') {
      // Lost a race against a concurrent delivery of the same call id. The other
      // path owns execution; this one must not run the side effect again.
      return {
        disposition: 'duplicate',
        interactionId,
        output: { ok: true, duplicate: true },
      }
    }

    const outcome = await this.#execute(executor, input, interactionId)

    const completedAt = this.#options.now()
    const eventId = newId('rtevt')

    // Written exactly once. Never updated — the trigger would raise.
    await store.insertToolEvent({
      id: eventId,
      conversationTurnId: null,
      toolCallId: input.toolCallId,
      toolName: input.toolName,
      argumentsJson: input.args ?? {},
      resultJson: outcome.result ?? null,
      status: outcome.status === 'succeeded'
        ? 'succeeded'
        : outcome.status === 'rejected'
        ? 'rejected'
        : 'failed',
      toolSequence: decision.toolSequence,
      durationMs: Math.max(0, completedAt.getTime() - startedAt.getTime()),
      realtimeSessionId: sessionId,
      realtimeGeneration: generation,
      realtimeInteractionId: interactionId,
      argumentHash: hash,
      sourceChannel: 'realtime_voice',
      confirmationState: null,
      startedAt: isoAt(startedAt),
      completedAt: isoAt(completedAt),
      createdAt: isoAt(completedAt),
    })

    const claimState: ToolClaimState = outcome.status === 'succeeded'
      ? 'succeeded'
      : outcome.status === 'rejected'
      ? 'rejected'
      : 'failed'

    await store.settleToolClaim({
      claimId,
      state: claimState,
      toolEventId: eventId,
      settledAt: isoAt(completedAt),
    })

    log.info('tool.executed', {
      session_id: sessionId,
      generation,
      interaction_id: interactionId,
      tool_name: input.toolName,
      status: outcome.status,
      duration_ms: completedAt.getTime() - startedAt.getTime(),
    })

    return {
      disposition: outcome.status === 'succeeded' ? 'executed' : 'failed',
      interactionId,
      output: outcome.result ?? { ok: outcome.status === 'succeeded' },
    }
  }

  /**
   * BROKERED path. No claim insert, no evidence insert, no settle — the broker
   * wrote all three around the tool it executed, and both tables carry partial
   * unique indexes on the Realtime key, so writing them here would raise instead
   * of duplicating. What remains is exactly what the model needs: a real answer.
   *
   * The broker's own idempotency is authoritative, including its replay of an
   * already-recorded claim, which arrives as `duplicate: true`.
   */
  async #runBrokered(
    input: { toolCallId: string; toolName: string; args: unknown },
    executor: ToolExecutor,
    interactionId: string,
    startedAt: Date,
  ): Promise<ToolCallResult> {
    const outcome = await this.#execute(executor, input, interactionId)
    const completedAt = this.#options.now()

    log.info('tool.executed', {
      session_id: this.#options.sessionId,
      generation: this.#options.generation,
      interaction_id: interactionId,
      tool_name: input.toolName,
      status: outcome.status,
      ledger: 'broker',
      duplicate: outcome.duplicate === true,
      duration_ms: completedAt.getTime() - startedAt.getTime(),
    })

    return {
      disposition: outcome.duplicate === true
        ? 'duplicate'
        : outcome.status === 'succeeded'
        ? 'executed'
        : 'failed',
      interactionId,
      // The broker's payload verbatim. An error from it is a real tool error the
      // model must see — never smoothed into a success, never swallowed.
      output: outcome.result ?? { ok: outcome.status === 'succeeded' },
    }
  }

  /**
   * Runs the executor and converts a THROW into a failed outcome. An executor
   * that throws must never propagate: the caller still has to send a
   * `function_call_output`, and an unanswered call wedges the response chain.
   */
  async #execute(
    executor: ToolExecutor,
    input: { toolCallId: string; toolName: string; args: unknown },
    interactionId: string,
  ): Promise<ToolOutcome> {
    try {
      return await executor(input.args, {
        sessionId: this.#options.sessionId,
        generation: this.#options.generation,
        interactionId,
        toolCallId: input.toolCallId,
        toolName: input.toolName,
        authorizationFingerprint: this.#options.authorizationFingerprint,
      })
    } catch (error) {
      log.warn('tool.executor_threw', {
        session_id: this.#options.sessionId,
        generation: this.#options.generation,
        interaction_id: interactionId,
        tool_name: input.toolName,
        detail: error instanceof Error ? error.name : 'error',
      })
      return {
        status: 'failed',
        result: errorOutput('tool_failed', error instanceof Error ? error.name : 'error'),
      }
    }
  }

  /**
   * Called when the inbound transcript for an interaction finally becomes a
   * durable turn. Links the claims to that turn; the evidence rows keep their
   * NULL, because they are immutable and the claim is the mutable side of the
   * pair by design.
   *
   * This runs in BOTH ownership modes, and is the one claim write the sideband
   * keeps when the broker owns the ledger. It is not a second opinion about the
   * call: `inbound_turn_id` is a column the broker never writes (it inserts NULL
   * and settles without touching it) and cannot write, because only this service
   * ever learns that the transcript finalized. The broker's own source says so —
   * "the turn link is back-filled on the mutable CLAIM". A conditional update of
   * a column with exactly one writer cannot collide with the unique indexes that
   * caused the double-write defect.
   */
  async backfillInboundTurn(
    interactionId: string,
    inboundTurnId: string,
  ): Promise<number> {
    const linked = await this.#options.store.backfillClaimInboundTurn({
      sessionId: this.#options.sessionId,
      generation: this.#options.generation,
      interactionId,
      inboundTurnId,
    })
    if (linked > 0) {
      log.info('tool.claims_backfilled', {
        session_id: this.#options.sessionId,
        generation: this.#options.generation,
        interaction_id: interactionId,
        linked,
      })
    }
    return linked
  }
}
