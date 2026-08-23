// The persistence port.
//
// Every DB interaction the sideband needs is expressed here as an intention
// ("claim this lease", "consume this binding token") rather than as SQL, so the
// control logic can be unit-tested against an in-memory double and so each
// authoritative write can carry its generation + fencing token as a first-class
// argument instead of being bolted on at a call site.

export type SetupState =
  | 'provisioning'
  | 'call_registered'
  | 'binding'
  | 'sideband_connecting'
  | 'active'
  | 'failed'
  | 'ending'
  | 'cleanup_pending'
  | 'ended'

export type SessionState = 'provisioning' | 'active' | 'ending' | 'ended' | 'failed'

export type TurnDirection = 'inbound' | 'outbound'

export type CompletionStatus =
  | 'pending'
  | 'finalized'
  | 'interrupted'
  | 'unavailable'
  | 'failed'

export type ToolClaimState =
  | 'claimed'
  | 'succeeded'
  | 'rejected'
  | 'failed'
  | 'indeterminate'

export interface RuntimeControlRow {
  readonly enabled: boolean
  readonly draining: boolean
  readonly forceStopAt: string | null
}

export interface SessionRow {
  readonly id: string
  readonly conversationId: string
  readonly contextEpoch: number
  readonly authorizationFingerprint: string
  readonly ownerProfileId: string | null
  readonly ownerStaffLinkId: string | null
  readonly tenantId: string | null
  readonly activeGeneration: number
  readonly state: SessionState
  readonly createdAt: string
  readonly authoritativeReadyAt: string | null
  readonly expiresAt: string | null
  readonly endedAt: string | null
  readonly usageSettledAt: string | null
}

export interface CallRow {
  readonly id: string
  readonly sessionId: string
  readonly generation: number
  readonly openaiCallId: string | null
  /**
   * The ephemeral OpenAI client secret that minted this call. The sideband
   * attach REQUIRES it as the bearer — the provider rejects the standard API
   * key on `wss://…/v1/realtime?call_id=…` (proven live 2026-08-17, despite
   * documentation to the contrary). Null only for legacy rows.
   */
  readonly clientSecret: string | null
  readonly setupState: SetupState
  readonly authorizationFingerprint: string
  readonly setupDeadlineAt: string
  readonly webrtcHealthy: boolean
  readonly dataChannelHealthy: boolean
  readonly sidebandHealthy: boolean
  readonly leaseOwner: string | null
  readonly leaseExpiresAt: string | null
  readonly leaseHeartbeatAt: string | null
  readonly fencingToken: number
  readonly bindingTokenHash: string | null
  readonly bindingTokenExpiresAt: string | null
  readonly bindingTokenConsumedAt: string | null
  readonly activeExpiresAt: string | null
  readonly endedAt: string | null
  readonly endReason: string | null
  readonly hangupState: 'not_required' | 'pending' | 'succeeded' | 'failed' | null
  readonly cleanupAttempts: number
}

export interface CallPatch {
  setupState?: SetupState
  webrtcHealthy?: boolean
  dataChannelHealthy?: boolean
  sidebandHealthy?: boolean
  callRegisteredAt?: string
  bindingStartedAt?: string
  sidebandConnectingAt?: string
  authoritativeReadyAt?: string
  activeExpiresAt?: string
  endingAt?: string
  endedAt?: string
  endReason?: string
  hangupState?: 'not_required' | 'pending' | 'succeeded' | 'failed'
  openaiCallId?: string
  leaseOwner?: string | null
  leaseExpiresAt?: string | null
  cleanupAttempts?: number
  cleanupNextAttemptAt?: string | null
}

export interface SessionPatch {
  state?: SessionState
  authoritativeReadyAt?: string
  endingAt?: string
  endedAt?: string
  endReason?: string
  expiresAt?: string
}

/** A fenced write handle: proof this worker still owns (session, generation). */
export interface LeaseHandle {
  readonly sessionId: string
  readonly generation: number
  readonly owner: string
  readonly fencingToken: number
  readonly expiresAt: string
}

export type BindingConsumeResult =
  | 'consumed'
  | 'unknown_generation'
  | 'no_token_issued'
  | 'already_consumed'
  | 'expired'
  | 'mismatch'

export interface TurnSlot {
  readonly conversationSeq: number
  readonly turnIndex: number
}

export interface TurnInsert {
  readonly id: string
  readonly conversationId: string
  readonly contextEpoch: number
  readonly direction: TurnDirection
  readonly conversationSeq: number
  readonly turnIndex: number | null
  readonly text: string
  readonly language: 'en' | 'ar' | 'mixed'
  readonly sourceChannel: 'app_text' | 'realtime_voice' | 'telegram' | 'system'
  readonly completionStatus: CompletionStatus
  readonly realtimeSessionId: string
  readonly realtimeGeneration: number
  readonly providerItemId: string | null
  readonly authorizationFingerprint: string
  readonly customerId: string | null
  readonly model: string | null
  readonly createdAt: string
  readonly finalizedAt: string | null
  readonly interruptedAt: string | null
}

export interface ToolEventInsert {
  readonly id: string
  /** Always NULL for Realtime: the transcript may not have finalized yet. */
  readonly conversationTurnId: null
  readonly toolCallId: string
  readonly toolName: string
  readonly argumentsJson: unknown
  readonly resultJson: unknown
  readonly status: 'requested' | 'succeeded' | 'rejected' | 'failed'
  readonly toolSequence: number
  readonly durationMs: number | null
  readonly realtimeSessionId: string
  readonly realtimeGeneration: number
  readonly realtimeInteractionId: string
  readonly argumentHash: string
  readonly sourceChannel: 'realtime_voice'
  readonly confirmationState: string | null
  readonly startedAt: string
  readonly completedAt: string | null
  readonly createdAt: string
}

export interface ToolClaimInsert {
  readonly id: string
  readonly realtimeSessionId: string
  readonly realtimeGeneration: number
  readonly realtimeInteractionId: string
  readonly openaiToolCallId: string
  readonly toolName: string
  readonly argumentHash: string
  readonly state: ToolClaimState
  readonly leaseOwner: string
  readonly leaseExpiresAt: string
  readonly claimedAt: string
}

export interface ToolClaimRow extends ToolClaimInsert {
  readonly inboundTurnId: string | null
  readonly toolEventId: string | null
  readonly settledAt: string | null
}

export interface UsageSlice {
  readonly sessionId: string
  readonly usageDate: string
  readonly ownerProfileId: string | null
  readonly tenantId: string | null
  readonly seconds: number
}

/** One `response.done` event's token accounting, as written to
 * `agent_realtime_response_usage`. PK is (sessionId, responseId) — a
 * redelivered `response.done` must insert the identical row again, never
 * double-count. */
export interface ResponseUsageInsert {
  readonly sessionId: string
  readonly responseId: string
  /**
   * The interaction this response belonged to — one user utterance plus the
   * whole response chain it provoked. Null only when the response arrived
   * with no preceding `response.created` to attribute it. This is what makes
   * "how many responses did one thing the caller said produce?" answerable
   * from the database rather than from log lines with a short retention.
   */
  readonly interactionId: string | null
  readonly generation: number
  readonly model: string
  readonly status: string
  readonly totalTokens: number
  readonly inputTokens: number
  readonly cachedInputTokens: number
  readonly uncachedInputTokens: number
  readonly inputTextTokens: number
  readonly inputAudioTokens: number
  readonly inputImageTokens: number
  readonly cachedTextTokens: number
  readonly cachedAudioTokens: number
  readonly outputTokens: number
  readonly outputTextTokens: number
  readonly outputAudioTokens: number
  readonly followedToolCall: boolean
  readonly toolNames: readonly string[]
  readonly ownerProfileId: string | null
  readonly tenantId: string | null
}

export interface CleanupCandidate {
  readonly sessionId: string
  readonly generation: number
  readonly openaiCallId: string | null
  readonly setupState: SetupState
  readonly fencingToken: number
}

/** One durable turn, as read back for context injection into a new session. */
export interface RecentTurn {
  readonly direction: TurnDirection
  readonly text: string
}

export interface RealtimeStore {
  loadRuntimeControl(): Promise<RuntimeControlRow>
  loadSession(sessionId: string): Promise<SessionRow | null>
  loadCall(sessionId: string, generation: number): Promise<CallRow | null>

  /**
   * Single-use consumption of the one-time binding token. Must be atomic: two
   * clients racing with the same token produce exactly one `consumed`.
   */
  consumeBindingToken(input: {
    sessionId: string
    generation: number
    presentedHash: string
    now: string
  }): Promise<BindingConsumeResult>

  /**
   * Atomically take ownership of exactly (session, generation), bumping the
   * fencing token. Returns null when another live owner holds it.
   */
  claimLease(input: {
    sessionId: string
    generation: number
    owner: string
    now: string
    expiresAt: string
  }): Promise<LeaseHandle | null>

  /** Compare-and-swap renewal. False means the lease was lost — stop immediately. */
  renewLease(lease: LeaseHandle, expiresAt: string, now: string): Promise<boolean>

  releaseLease(lease: LeaseHandle, now: string): Promise<boolean>

  /** Every authoritative write is fenced. False means a newer owner exists. */
  updateCall(lease: LeaseHandle, patch: CallPatch): Promise<boolean>

  updateSession(sessionId: string, patch: SessionPatch): Promise<boolean>

  allocateTurnSlot(input: {
    conversationId: string
    contextEpoch: number
    direction: TurnDirection
    turnIndexOverride: number | null
  }): Promise<TurnSlot>

  insertTurn(row: TurnInsert): Promise<void>

  /** Evidence is immutable — insert only, never updated afterwards. */
  insertToolEvent(row: ToolEventInsert): Promise<void>

  /** `duplicate` when (session, generation, tool_call_id) already exists. */
  insertToolClaim(row: ToolClaimInsert): Promise<'claimed' | 'duplicate'>

  loadToolClaim(
    sessionId: string,
    generation: number,
    toolCallId: string,
  ): Promise<ToolClaimRow | null>

  settleToolClaim(input: {
    claimId: string
    state: ToolClaimState
    toolEventId: string | null
    settledAt: string
  }): Promise<void>

  /** Back-fill lives on the mutable CLAIM, never on the immutable evidence row. */
  backfillClaimInboundTurn(input: {
    sessionId: string
    generation: number
    interactionId: string
    inboundTurnId: string
  }): Promise<number>

  /** INSERT ... ON CONFLICT DO NOTHING. Never an upsert. */
  insertUsageSlices(slices: readonly UsageSlice[]): Promise<void>

  /**
   * INSERT ... ON CONFLICT DO NOTHING on (session_id, response_id). Never an
   * upsert, for the same reason `insertUsageSlices` isn't: a redelivered
   * `response.done` must not overwrite an already-recorded row with
   * recomputed numbers. Must never throw in a way that breaks the call —
   * callers wrap this in try/catch and log-and-continue on failure.
   */
  insertResponseUsage(row: ResponseUsageInsert): Promise<void>

  /** CAS on `usage_settled_at IS NULL`. False means someone already settled. */
  markUsageSettled(sessionId: string, settledAt: string): Promise<boolean>

  findCleanupCandidates(now: string, limit: number): Promise<CleanupCandidate[]>

  /** Atomically claim a cleanup slot, advancing the fence past any stale worker. */
  claimCleanup(input: {
    sessionId: string
    generation: number
    owner: string
    expectedFence: number
    now: string
    expiresAt: string
  }): Promise<LeaseHandle | null>

  findUnsettledSessions(limit: number): Promise<SessionRow[]>

  /** Batched drain handoff: one statement per generation set, not per generation. */
  markGenerationsCleanupPending(input: {
    owner: string
    endReason: string
    now: string
  }): Promise<number>

  /**
   * Recent finalized turns for a conversation, newest-first, for injecting
   * context into a fresh realtime session. Only `completion_status =
   * 'finalized'` turns with non-empty text are returned, scoped to the exact
   * `contextEpoch` the new session is starting under, and constrained to the
   * known inbound/outbound directions and known source channels — so a
   * future row type (e.g. an internal 'system' note) can never be injected
   * into a live call as if the model or the caller said it.
   */
  loadRecentTurns(input: {
    conversationId: string
    contextEpoch: number
    limit: number
  }): Promise<RecentTurn[]>

  /**
   * Best-effort: bump the parent conversation's `updated_at` right after a
   * turn write, so conversation-list ordering reflects real activity rather
   * than only creation time. Callers must treat failure as non-fatal — never
   * let this block or fail the turn write it follows.
   */
  touchConversation(conversationId: string, updatedAt: string): Promise<void>
}
