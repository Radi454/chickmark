// PostgREST implementation of the persistence port.
//
// No npm dependencies: the service role key is sent on plain `fetch` calls
// against Supabase's REST surface. Every compare-and-swap is expressed as a
// PATCH whose FILTER carries the expected state and which returns the affected
// rows — zero rows back means the swap lost, which is the signal the lease and
// settlement logic depends on.

import type {
  BindingConsumeResult,
  CallPatch,
  CallRow,
  CleanupCandidate,
  LeaseHandle,
  RealtimeStore,
  RecentTurn,
  ResponseUsageInsert,
  RuntimeControlRow,
  SessionPatch,
  SessionRow,
  ToolClaimInsert,
  ToolClaimRow,
  ToolClaimState,
  ToolEventInsert,
  TurnDirection,
  TurnInsert,
  TurnSlot,
  UsageSlice,
} from './store.ts'
import { timingSafeEqual } from './ids.ts'

const SETUP_IN_PROGRESS = [
  'provisioning',
  'call_registered',
  'binding',
  'sideband_connecting',
] as const

const LIVE_STATES = [...SETUP_IN_PROGRESS, 'active', 'ending'] as const

type Row = Record<string, unknown>

function str(row: Row, key: string): string {
  return String(row[key] ?? '')
}

function nullableStr(row: Row, key: string): string | null {
  const value = row[key]
  return value === null || value === undefined ? null : String(value)
}

function num(row: Row, key: string): number {
  return Number(row[key] ?? 0)
}

function bool(row: Row, key: string): boolean {
  return row[key] === true
}

function toSessionRow(row: Row): SessionRow {
  return {
    id: str(row, 'id'),
    conversationId: str(row, 'conversation_id'),
    contextEpoch: num(row, 'context_epoch'),
    authorizationFingerprint: str(row, 'authorization_fingerprint'),
    ownerProfileId: nullableStr(row, 'owner_profile_id'),
    ownerStaffLinkId: nullableStr(row, 'owner_staff_link_id'),
    tenantId: nullableStr(row, 'tenant_id'),
    activeGeneration: num(row, 'active_generation'),
    state: str(row, 'state') as SessionRow['state'],
    createdAt: str(row, 'created_at'),
    authoritativeReadyAt: nullableStr(row, 'authoritative_ready_at'),
    expiresAt: nullableStr(row, 'expires_at'),
    endedAt: nullableStr(row, 'ended_at'),
    usageSettledAt: nullableStr(row, 'usage_settled_at'),
  }
}

function toCallRow(row: Row): CallRow {
  return {
    id: str(row, 'id'),
    sessionId: str(row, 'session_id'),
    generation: num(row, 'generation'),
    openaiCallId: nullableStr(row, 'openai_call_id'),
    clientSecret: nullableStr(row, 'client_secret'),
    setupState: str(row, 'setup_state') as CallRow['setupState'],
    authorizationFingerprint: str(row, 'authorization_fingerprint'),
    setupDeadlineAt: str(row, 'setup_deadline_at'),
    webrtcHealthy: bool(row, 'webrtc_healthy'),
    dataChannelHealthy: bool(row, 'data_channel_healthy'),
    sidebandHealthy: bool(row, 'sideband_healthy'),
    leaseOwner: nullableStr(row, 'lease_owner'),
    leaseExpiresAt: nullableStr(row, 'lease_expires_at'),
    leaseHeartbeatAt: nullableStr(row, 'lease_heartbeat_at'),
    fencingToken: num(row, 'fencing_token'),
    bindingTokenHash: nullableStr(row, 'binding_token_hash'),
    bindingTokenExpiresAt: nullableStr(row, 'binding_token_expires_at'),
    bindingTokenConsumedAt: nullableStr(row, 'binding_token_consumed_at'),
    activeExpiresAt: nullableStr(row, 'active_expires_at'),
    endedAt: nullableStr(row, 'ended_at'),
    endReason: nullableStr(row, 'end_reason'),
    hangupState: nullableStr(row, 'hangup_state') as CallRow['hangupState'],
    cleanupAttempts: num(row, 'cleanup_attempts'),
  }
}

function callPatchToColumns(patch: CallPatch): Row {
  const columns: Row = {}
  const map: Record<keyof CallPatch, string> = {
    setupState: 'setup_state',
    webrtcHealthy: 'webrtc_healthy',
    dataChannelHealthy: 'data_channel_healthy',
    sidebandHealthy: 'sideband_healthy',
    callRegisteredAt: 'call_registered_at',
    bindingStartedAt: 'binding_started_at',
    sidebandConnectingAt: 'sideband_connecting_at',
    authoritativeReadyAt: 'authoritative_ready_at',
    activeExpiresAt: 'active_expires_at',
    endingAt: 'ending_at',
    endedAt: 'ended_at',
    endReason: 'end_reason',
    hangupState: 'hangup_state',
    openaiCallId: 'openai_call_id',
    leaseOwner: 'lease_owner',
    leaseExpiresAt: 'lease_expires_at',
    cleanupAttempts: 'cleanup_attempts',
    cleanupNextAttemptAt: 'cleanup_next_attempt_at',
  }
  for (const [key, column] of Object.entries(map)) {
    const value = patch[key as keyof CallPatch]
    if (value !== undefined) columns[column] = value
  }
  return columns
}

export class PostgrestStore implements RealtimeStore {
  readonly #baseUrl: string
  readonly #key: string
  readonly #fetch: typeof fetch

  constructor(options: {
    supabaseUrl: string
    serviceRoleKey: string
    fetchImpl?: typeof fetch
  }) {
    this.#baseUrl = `${options.supabaseUrl.replace(/\/+$/, '')}/rest/v1`
    this.#key = options.serviceRoleKey
    this.#fetch = options.fetchImpl ?? fetch
  }

  async #request(
    path: string,
    init: RequestInit & { prefer?: string } = {},
  ): Promise<{ status: number; rows: Row[] }> {
    const headers: Record<string, string> = {
      apikey: this.#key,
      authorization: `Bearer ${this.#key}`,
      'content-type': 'application/json',
      accept: 'application/json',
    }
    if (init.prefer) headers.prefer = init.prefer
    const response = await this.#fetch(`${this.#baseUrl}${path}`, {
      ...init,
      headers: { ...headers, ...(init.headers as Record<string, string> ?? {}) },
    })
    const text = await response.text()
    if (!response.ok && response.status !== 409) {
      // The body can echo the request, which for a turn insert means transcript
      // text. Only the status is surfaced.
      throw new Error(`postgrest_status_${response.status}`)
    }
    let rows: Row[] = []
    if (text.trim() !== '') {
      try {
        const parsed = JSON.parse(text)
        rows = Array.isArray(parsed) ? parsed as Row[] : [parsed as Row]
      } catch {
        rows = []
      }
    }
    return { status: response.status, rows }
  }

  #select(path: string): Promise<{ status: number; rows: Row[] }> {
    return this.#request(path, { method: 'GET' })
  }

  #patch(path: string, body: Row): Promise<{ status: number; rows: Row[] }> {
    return this.#request(path, {
      method: 'PATCH',
      body: JSON.stringify(body),
      prefer: 'return=representation',
    })
  }

  async loadRuntimeControl(): Promise<RuntimeControlRow> {
    const { rows } = await this.#select(
      '/agent_realtime_runtime_control?id=eq.1&select=*',
    )
    const row = rows[0] ?? {}
    return {
      enabled: row.enabled !== false,
      draining: row.draining === true,
      forceStopAt: nullableStr(row, 'force_stop_at'),
    }
  }

  async loadSession(sessionId: string): Promise<SessionRow | null> {
    const { rows } = await this.#select(
      `/agent_realtime_sessions?id=eq.${encodeURIComponent(sessionId)}&select=*&limit=1`,
    )
    return rows[0] ? toSessionRow(rows[0]) : null
  }

  async loadCall(sessionId: string, generation: number): Promise<CallRow | null> {
    const { rows } = await this.#select(
      `/agent_realtime_calls?session_id=eq.${encodeURIComponent(sessionId)}` +
        `&generation=eq.${generation}&select=*&limit=1`,
    )
    return rows[0] ? toCallRow(rows[0]) : null
  }

  async consumeBindingToken(input: {
    sessionId: string
    generation: number
    presentedHash: string
    now: string
  }): Promise<BindingConsumeResult> {
    const call = await this.loadCall(input.sessionId, input.generation)
    if (!call) return 'unknown_generation'
    if (!call.bindingTokenHash) return 'no_token_issued'
    if (call.bindingTokenConsumedAt) return 'already_consumed'
    if (call.bindingTokenExpiresAt && call.bindingTokenExpiresAt <= input.now) {
      return 'expired'
    }
    if (!timingSafeEqual(call.bindingTokenHash, input.presentedHash)) return 'mismatch'

    // Single-use is enforced by the DATABASE, not by the read above: the filter
    // `binding_token_consumed_at=is.null` makes two racing binds produce exactly
    // one affected row.
    const { rows } = await this.#patch(
      `/agent_realtime_calls?session_id=eq.${encodeURIComponent(input.sessionId)}` +
        `&generation=eq.${input.generation}` +
        `&binding_token_hash=eq.${encodeURIComponent(input.presentedHash)}` +
        `&binding_token_consumed_at=is.null`,
      {
        binding_token_consumed_at: input.now,
        setup_state: 'binding',
        binding_started_at: input.now,
      },
    )
    return rows.length === 1 ? 'consumed' : 'already_consumed'
  }

  async claimLease(input: {
    sessionId: string
    generation: number
    owner: string
    now: string
    expiresAt: string
  }): Promise<LeaseHandle | null> {
    const call = await this.loadCall(input.sessionId, input.generation)
    if (!call) return null
    const heldByOther = call.leaseOwner !== null &&
      call.leaseOwner !== input.owner &&
      call.leaseExpiresAt !== null &&
      call.leaseExpiresAt > input.now
    if (heldByOther) return null

    const nextFence = call.fencingToken + 1
    // The fence filter is the compare-and-swap: if another claimant bumped it
    // between the read and this write, zero rows come back and we lose cleanly.
    const { rows } = await this.#patch(
      `/agent_realtime_calls?session_id=eq.${encodeURIComponent(input.sessionId)}` +
        `&generation=eq.${input.generation}&fencing_token=eq.${call.fencingToken}`,
      {
        lease_owner: input.owner,
        lease_expires_at: input.expiresAt,
        lease_heartbeat_at: input.now,
        fencing_token: nextFence,
      },
    )
    if (rows.length !== 1) return null
    return {
      sessionId: input.sessionId,
      generation: input.generation,
      owner: input.owner,
      fencingToken: nextFence,
      expiresAt: input.expiresAt,
    }
  }

  async renewLease(lease: LeaseHandle, expiresAt: string, now: string): Promise<boolean> {
    const { rows } = await this.#patch(
      `/agent_realtime_calls?session_id=eq.${encodeURIComponent(lease.sessionId)}` +
        `&generation=eq.${lease.generation}` +
        `&lease_owner=eq.${encodeURIComponent(lease.owner)}` +
        `&fencing_token=eq.${lease.fencingToken}`,
      { lease_expires_at: expiresAt, lease_heartbeat_at: now },
    )
    return rows.length === 1
  }

  async releaseLease(lease: LeaseHandle, now: string): Promise<boolean> {
    const { rows } = await this.#patch(
      `/agent_realtime_calls?session_id=eq.${encodeURIComponent(lease.sessionId)}` +
        `&generation=eq.${lease.generation}` +
        `&lease_owner=eq.${encodeURIComponent(lease.owner)}` +
        `&fencing_token=eq.${lease.fencingToken}`,
      { lease_owner: null, lease_expires_at: null, lease_heartbeat_at: now },
    )
    return rows.length === 1
  }

  async updateCall(lease: LeaseHandle, patch: CallPatch): Promise<boolean> {
    const { rows } = await this.#patch(
      `/agent_realtime_calls?session_id=eq.${encodeURIComponent(lease.sessionId)}` +
        `&generation=eq.${lease.generation}` +
        `&fencing_token=eq.${lease.fencingToken}`,
      callPatchToColumns(patch),
    )
    return rows.length === 1
  }

  async updateSession(sessionId: string, patch: SessionPatch): Promise<boolean> {
    const columns: Row = {}
    if (patch.state !== undefined) columns.state = patch.state
    if (patch.authoritativeReadyAt !== undefined) {
      columns.authoritative_ready_at = patch.authoritativeReadyAt
    }
    if (patch.endingAt !== undefined) columns.ending_at = patch.endingAt
    if (patch.endedAt !== undefined) columns.ended_at = patch.endedAt
    if (patch.endReason !== undefined) columns.end_reason = patch.endReason
    if (patch.expiresAt !== undefined) columns.expires_at = patch.expiresAt
    if (Object.keys(columns).length === 0) return true
    const { rows } = await this.#patch(
      `/agent_realtime_sessions?id=eq.${encodeURIComponent(sessionId)}`,
      columns,
    )
    return rows.length === 1
  }

  async allocateTurnSlot(input: {
    conversationId: string
    contextEpoch: number
    direction: 'inbound' | 'outbound'
    turnIndexOverride: number | null
  }): Promise<TurnSlot> {
    // PostgREST does not expose `chickmark_private`, so the allocator is reached
    // through its SECURITY DEFINER wrapper in `public`.
    const { rows } = await this.#request('/rpc/allocate_agent_turn_slot', {
      method: 'POST',
      body: JSON.stringify({
        p_conversation_id: input.conversationId,
        p_context_epoch: input.contextEpoch,
        p_direction: input.direction,
        p_turn_index_override: input.turnIndexOverride,
      }),
    })
    const row = rows[0]
    if (!row) throw new Error('allocate_agent_turn_slot_returned_no_row')
    return {
      conversationSeq: num(row, 'conversation_seq'),
      turnIndex: num(row, 'turn_index'),
    }
  }

  async insertTurn(row: TurnInsert): Promise<void> {
    await this.#request('/agent_conversation_turns', {
      method: 'POST',
      prefer: 'return=minimal',
      body: JSON.stringify({
        id: row.id,
        conversation_id: row.conversationId,
        context_epoch: row.contextEpoch,
        direction: row.direction,
        conversation_seq: row.conversationSeq,
        turn_index: row.turnIndex,
        text: row.text,
        language: row.language,
        source_channel: row.sourceChannel,
        completion_status: row.completionStatus,
        realtime_session_id: row.realtimeSessionId,
        realtime_generation: row.realtimeGeneration,
        provider_item_id: row.providerItemId,
        authorization_fingerprint: row.authorizationFingerprint,
        customer_id: row.customerId,
        model: row.model,
        created_at: row.createdAt,
        finalized_at: row.finalizedAt,
        interrupted_at: row.interruptedAt,
      }),
    })
  }

  async insertToolEvent(row: ToolEventInsert): Promise<void> {
    await this.#request('/agent_tool_events', {
      method: 'POST',
      prefer: 'return=minimal',
      body: JSON.stringify({
        id: row.id,
        conversation_turn_id: null,
        tool_call_id: row.toolCallId,
        tool_name: row.toolName,
        arguments_json: row.argumentsJson,
        result_json: row.resultJson,
        status: row.status,
        tool_sequence: row.toolSequence,
        duration_ms: row.durationMs,
        realtime_session_id: row.realtimeSessionId,
        realtime_generation: row.realtimeGeneration,
        realtime_interaction_id: row.realtimeInteractionId,
        argument_hash: row.argumentHash,
        source_channel: row.sourceChannel,
        confirmation_state: row.confirmationState,
        started_at: row.startedAt,
        completed_at: row.completedAt,
        created_at: row.createdAt,
      }),
    })
  }

  async insertToolClaim(row: ToolClaimInsert): Promise<'claimed' | 'duplicate'> {
    const { status } = await this.#request('/agent_tool_call_claims', {
      method: 'POST',
      prefer: 'return=minimal',
      body: JSON.stringify({
        id: row.id,
        realtime_session_id: row.realtimeSessionId,
        realtime_generation: row.realtimeGeneration,
        realtime_interaction_id: row.realtimeInteractionId,
        openai_tool_call_id: row.openaiToolCallId,
        tool_name: row.toolName,
        argument_hash: row.argumentHash,
        state: row.state,
        lease_owner: row.leaseOwner,
        lease_expires_at: row.leaseExpiresAt,
        claimed_at: row.claimedAt,
      }),
    })
    // 409 is the partial unique index on (session, generation, tool_call_id)
    // firing: someone else already claimed this exact call.
    return status === 409 ? 'duplicate' : 'claimed'
  }

  async loadToolClaim(
    sessionId: string,
    generation: number,
    toolCallId: string,
  ): Promise<ToolClaimRow | null> {
    const { rows } = await this.#select(
      `/agent_tool_call_claims?realtime_session_id=eq.${encodeURIComponent(sessionId)}` +
        `&realtime_generation=eq.${generation}` +
        `&openai_tool_call_id=eq.${encodeURIComponent(toolCallId)}&select=*&limit=1`,
    )
    const row = rows[0]
    if (!row) return null
    return {
      id: str(row, 'id'),
      realtimeSessionId: str(row, 'realtime_session_id'),
      realtimeGeneration: num(row, 'realtime_generation'),
      realtimeInteractionId: str(row, 'realtime_interaction_id'),
      openaiToolCallId: str(row, 'openai_tool_call_id'),
      toolName: str(row, 'tool_name'),
      argumentHash: str(row, 'argument_hash'),
      state: str(row, 'state') as ToolClaimState,
      leaseOwner: str(row, 'lease_owner'),
      leaseExpiresAt: str(row, 'lease_expires_at'),
      claimedAt: str(row, 'claimed_at'),
      inboundTurnId: nullableStr(row, 'inbound_turn_id'),
      toolEventId: nullableStr(row, 'tool_event_id'),
      settledAt: nullableStr(row, 'settled_at'),
    }
  }

  async settleToolClaim(input: {
    claimId: string
    state: ToolClaimState
    toolEventId: string | null
    settledAt: string
  }): Promise<void> {
    await this.#patch(
      `/agent_tool_call_claims?id=eq.${encodeURIComponent(input.claimId)}`,
      {
        state: input.state,
        tool_event_id: input.toolEventId,
        settled_at: input.settledAt,
      },
    )
  }

  async backfillClaimInboundTurn(input: {
    sessionId: string
    generation: number
    interactionId: string
    inboundTurnId: string
  }): Promise<number> {
    const { rows } = await this.#patch(
      `/agent_tool_call_claims?realtime_session_id=eq.${
        encodeURIComponent(input.sessionId)
      }` +
        `&realtime_generation=eq.${input.generation}` +
        `&realtime_interaction_id=eq.${encodeURIComponent(input.interactionId)}` +
        `&inbound_turn_id=is.null`,
      { inbound_turn_id: input.inboundTurnId },
    )
    return rows.length
  }

  async insertUsageSlices(slices: readonly UsageSlice[]): Promise<void> {
    if (slices.length === 0) return
    await this.#request('/agent_realtime_usage_seconds', {
      method: 'POST',
      // ON CONFLICT DO NOTHING. Never an upsert: an upsert would overwrite a
      // correct settled slice with a recomputed one.
      prefer: 'resolution=ignore-duplicates,return=minimal',
      body: JSON.stringify(slices.map((slice) => ({
        session_id: slice.sessionId,
        usage_date: slice.usageDate,
        owner_profile_id: slice.ownerProfileId,
        tenant_id: slice.tenantId,
        seconds: slice.seconds,
      }))),
    })
  }

  async insertResponseUsage(row: ResponseUsageInsert): Promise<void> {
    await this.#request('/agent_realtime_response_usage', {
      method: 'POST',
      // ON CONFLICT DO NOTHING, same convention as insertUsageSlices: a
      // redelivered response.done must not overwrite an already-recorded row.
      prefer: 'resolution=ignore-duplicates,return=minimal',
      body: JSON.stringify({
        session_id: row.sessionId,
        response_id: row.responseId,
        interaction_id: row.interactionId,
        generation: row.generation,
        model: row.model,
        status: row.status,
        total_tokens: row.totalTokens,
        input_tokens: row.inputTokens,
        cached_input_tokens: row.cachedInputTokens,
        uncached_input_tokens: row.uncachedInputTokens,
        input_text_tokens: row.inputTextTokens,
        input_audio_tokens: row.inputAudioTokens,
        input_image_tokens: row.inputImageTokens,
        cached_text_tokens: row.cachedTextTokens,
        cached_audio_tokens: row.cachedAudioTokens,
        output_tokens: row.outputTokens,
        output_text_tokens: row.outputTextTokens,
        output_audio_tokens: row.outputAudioTokens,
        followed_tool_call: row.followedToolCall,
        tool_names: row.toolNames,
        owner_profile_id: row.ownerProfileId,
        tenant_id: row.tenantId,
      }),
    })
  }

  async markUsageSettled(sessionId: string, settledAt: string): Promise<boolean> {
    const { rows } = await this.#patch(
      `/agent_realtime_sessions?id=eq.${encodeURIComponent(sessionId)}` +
        `&usage_settled_at=is.null`,
      { usage_settled_at: settledAt },
    )
    return rows.length === 1
  }

  /**
   * Three kinds of generation need terminalizing, and the third was written
   * but never read.
   *
   *   1. `cleanup_pending` — handed over by a draining worker.
   *   2. A SETUP that stalled past `setup_deadline_at`.
   *   3. An ACTIVE call past `active_expires_at`. The provisioner has always
   *      stamped that column from `maxSessionSeconds`, and nothing anywhere
   *      selected on it — `SETUP_IN_PROGRESS` deliberately excludes `active`,
   *      so a live call was swept by nothing at all. The only real bound on a
   *      session was the client hanging up: every new utterance opens a fresh
   *      interaction with a fresh tool budget, so an echoing line or a caller
   *      talking over the model could drive unbounded tool and inference cost
   *      on one session with no server-side stop.
   */
  async findCleanupCandidates(now: string, limit: number): Promise<CleanupCandidate[]> {
    const setupList = SETUP_IN_PROGRESS.join(',')
    const filter = 'or=(' + [
      'setup_state.eq.cleanup_pending',
      `and(setup_state.in.(${setupList}),setup_deadline_at.lt.${now})`,
      `and(setup_state.eq.active,active_expires_at.lt.${now})`,
    ].join(',') + ')'
    const { rows } = await this.#select(
      `/agent_realtime_calls?${filter}&select=session_id,generation,openai_call_id,setup_state,fencing_token&limit=${limit}`,
    )
    return rows.map((row) => ({
      sessionId: str(row, 'session_id'),
      generation: num(row, 'generation'),
      openaiCallId: nullableStr(row, 'openai_call_id'),
      setupState: str(row, 'setup_state') as CleanupCandidate['setupState'],
      fencingToken: num(row, 'fencing_token'),
    }))
  }

  async claimCleanup(input: {
    sessionId: string
    generation: number
    owner: string
    expectedFence: number
    now: string
    expiresAt: string
  }): Promise<LeaseHandle | null> {
    const nextFence = input.expectedFence + 1
    const { rows } = await this.#patch(
      `/agent_realtime_calls?session_id=eq.${encodeURIComponent(input.sessionId)}` +
        `&generation=eq.${input.generation}&fencing_token=eq.${input.expectedFence}`,
      {
        lease_owner: input.owner,
        lease_expires_at: input.expiresAt,
        lease_heartbeat_at: input.now,
        fencing_token: nextFence,
      },
    )
    if (rows.length !== 1) return null
    return {
      sessionId: input.sessionId,
      generation: input.generation,
      owner: input.owner,
      fencingToken: nextFence,
      expiresAt: input.expiresAt,
    }
  }

  async findUnsettledSessions(limit: number): Promise<SessionRow[]> {
    const { rows } = await this.#select(
      `/agent_realtime_sessions?usage_settled_at=is.null&state=in.(ended,failed)` +
        `&select=*&limit=${limit}`,
    )
    return rows.map(toSessionRow)
  }

  async markGenerationsCleanupPending(input: {
    owner: string
    endReason: string
    now: string
  }): Promise<number> {
    // ONE statement for every generation this worker owns. The 10s SIGTERM
    // grace does not survive a per-generation round trip at real concurrency.
    const { rows } = await this.#patch(
      `/agent_realtime_calls?lease_owner=eq.${encodeURIComponent(input.owner)}` +
        `&setup_state=in.(${LIVE_STATES.join(',')})`,
      {
        setup_state: 'cleanup_pending',
        end_reason: input.endReason,
        ending_at: input.now,
        lease_owner: null,
        lease_expires_at: null,
        cleanup_next_attempt_at: input.now,
      },
    )
    return rows.length
  }

  async loadRecentTurns(input: {
    conversationId: string
    contextEpoch: number
    limit: number
  }): Promise<RecentTurn[]> {
    // Non-empty is expressed as `text=neq.` (compares against the empty
    // string) — the column is NOT NULL, so there is no null case to exclude.
    // direction/source_channel are constrained defensively: today every
    // finalized row already matches, but this guarantees a future row type
    // (e.g. an internal 'system' note) can never be replayed into a live
    // call as if the model or the caller said it.
    const { rows } = await this.#select(
      `/agent_conversation_turns?conversation_id=eq.${
        encodeURIComponent(input.conversationId)
      }` +
        `&context_epoch=eq.${input.contextEpoch}` +
        `&completion_status=eq.finalized` +
        `&direction=in.(inbound,outbound)` +
        `&source_channel=in.(app_text,realtime_voice,telegram)` +
        `&text=neq.` +
        `&select=direction,text&order=conversation_seq.desc&limit=${input.limit}`,
    )
    return rows.map((row) => ({
      direction: str(row, 'direction') as TurnDirection,
      text: str(row, 'text'),
    }))
  }

  /** Best-effort: failures are the caller's responsibility to swallow. */
  async touchConversation(conversationId: string, updatedAt: string): Promise<void> {
    await this.#patch(
      `/agent_conversations?id=eq.${encodeURIComponent(conversationId)}`,
      { updated_at: updatedAt },
    )
  }
}
