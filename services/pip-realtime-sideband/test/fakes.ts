// In-memory doubles. No network, no timers, no clock.

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
  TurnInsert,
  TurnSlot,
  UsageSlice,
} from '../src/store.ts'
import type { SidebandSocket } from '../src/sideband.ts'
import { setLogSink } from '../src/log.ts'

// Telemetry is silenced by default so test output stays readable. Tests that
// assert on log content capture it explicitly.
setLogSink(() => {})

/** Collect emitted log lines for the duration of a test. */
export function captureLogs(): { lines: string[]; restore: () => void } {
  const lines: string[] = []
  setLogSink((line) => lines.push(line))
  return { lines, restore: () => setLogSink(() => {}) }
}

export class FakeClock {
  #now: Date
  constructor(iso = '2026-08-16T10:00:00.000Z') {
    this.#now = new Date(iso)
  }
  now = (): Date => new Date(this.#now)
  advance(ms: number): void {
    this.#now = new Date(this.#now.getTime() + ms)
  }
  set(iso: string): void {
    this.#now = new Date(iso)
  }
}

export interface FakeStoreSeed {
  session?: Partial<SessionRow>
  call?: Partial<CallRow>
  runtimeControl?: Partial<RuntimeControlRow>
}

const BASE_SESSION: SessionRow = {
  id: 'sess_1',
  conversationId: 'conv_1',
  contextEpoch: 1,
  authorizationFingerprint: 'admin:all',
  ownerProfileId: 'profile_1',
  ownerStaffLinkId: 'link_1',
  tenantId: 'tenant_1',
  activeGeneration: 1,
  state: 'provisioning',
  createdAt: '2026-08-16T09:59:00.000Z',
  authoritativeReadyAt: null,
  expiresAt: null,
  endedAt: null,
  usageSettledAt: null,
}

const BASE_CALL: CallRow = {
  id: 'call_row_1',
  sessionId: 'sess_1',
  generation: 1,
  openaiCallId: 'rtc_abc',
  clientSecret: 'ek_test_secret',
  setupState: 'call_registered',
  authorizationFingerprint: 'admin:all',
  setupDeadlineAt: '2026-08-16T10:01:00.000Z',
  webrtcHealthy: false,
  dataChannelHealthy: false,
  sidebandHealthy: false,
  leaseOwner: null,
  leaseExpiresAt: null,
  leaseHeartbeatAt: null,
  fencingToken: 0,
  bindingTokenHash: null,
  bindingTokenExpiresAt: '2026-08-16T10:01:00.000Z',
  bindingTokenConsumedAt: null,
  activeExpiresAt: null,
  endedAt: null,
  endReason: null,
  hangupState: null,
  cleanupAttempts: 0,
}

export class FakeStore implements RealtimeStore {
  runtimeControl: RuntimeControlRow = {
    enabled: true,
    draining: false,
    forceStopAt: null,
  }
  sessions = new Map<string, SessionRow>()
  calls = new Map<string, CallRow>()
  turns: TurnInsert[] = []
  toolEvents: ToolEventInsert[] = []
  claims = new Map<string, ToolClaimRow>()
  usage = new Map<string, UsageSlice>()
  /** Keyed by `${sessionId}:${responseId}`, mirroring the real PK — inserting
   * the same key twice is a no-op, matching ON CONFLICT DO NOTHING. */
  responseUsage = new Map<string, ResponseUsageInsert>()
  allocated: TurnSlot[] = []
  /** Every attempted mutation of an already-written evidence row. Must stay empty. */
  evidenceMutationAttempts = 0
  handoffCalls = 0
  /** Test seam: make loadRecentTurns reject, simulating a fetch failure. */
  failRecentTurns = false
  /** Every touchConversation call, in order, for assertions. */
  conversationTouches: { conversationId: string; updatedAt: string }[] = []
  /** Test seam: make touchConversation reject, simulating a PATCH failure. */
  failTouchConversation = false
  /** Test seam: make insertResponseUsage reject, simulating a POST failure. */
  failInsertResponseUsage = false
  #seq = new Map<string, number>()
  #turnIndex = new Map<string, number>()

  constructor(seed: FakeStoreSeed = {}) {
    const session = { ...BASE_SESSION, ...seed.session }
    const call = { ...BASE_CALL, sessionId: session.id, ...seed.call }
    this.sessions.set(session.id, session)
    this.calls.set(`${call.sessionId}:${call.generation}`, call)
    if (seed.runtimeControl) {
      this.runtimeControl = { ...this.runtimeControl, ...seed.runtimeControl }
    }
  }

  #callKey(sessionId: string, generation: number): string {
    return `${sessionId}:${generation}`
  }

  setCall(sessionId: string, generation: number, patch: Partial<CallRow>): void {
    const key = this.#callKey(sessionId, generation)
    const existing = this.calls.get(key)
    if (!existing) throw new Error('no such call')
    this.calls.set(key, { ...existing, ...patch })
  }

  addCall(call: Partial<CallRow> & { sessionId: string; generation: number }): void {
    this.calls.set(this.#callKey(call.sessionId, call.generation), {
      ...BASE_CALL,
      ...call,
    })
  }

  addSession(session: Partial<SessionRow> & { id: string }): void {
    this.sessions.set(session.id, { ...BASE_SESSION, ...session })
  }

  loadRuntimeControl(): Promise<RuntimeControlRow> {
    return Promise.resolve(this.runtimeControl)
  }

  loadSession(sessionId: string): Promise<SessionRow | null> {
    return Promise.resolve(this.sessions.get(sessionId) ?? null)
  }

  loadCall(sessionId: string, generation: number): Promise<CallRow | null> {
    return Promise.resolve(this.calls.get(this.#callKey(sessionId, generation)) ?? null)
  }

  consumeBindingToken(input: {
    sessionId: string
    generation: number
    presentedHash: string
    now: string
  }): Promise<BindingConsumeResult> {
    const key = this.#callKey(input.sessionId, input.generation)
    const call = this.calls.get(key)
    if (!call) return Promise.resolve('unknown_generation')
    if (!call.bindingTokenHash) return Promise.resolve('no_token_issued')
    if (call.bindingTokenConsumedAt) return Promise.resolve('already_consumed')
    if (call.bindingTokenExpiresAt && call.bindingTokenExpiresAt <= input.now) {
      return Promise.resolve('expired')
    }
    if (call.bindingTokenHash !== input.presentedHash) return Promise.resolve('mismatch')
    this.calls.set(key, {
      ...call,
      bindingTokenConsumedAt: input.now,
      setupState: 'binding',
    })
    return Promise.resolve('consumed')
  }

  claimLease(input: {
    sessionId: string
    generation: number
    owner: string
    now: string
    expiresAt: string
  }): Promise<LeaseHandle | null> {
    const key = this.#callKey(input.sessionId, input.generation)
    const call = this.calls.get(key)
    if (!call) return Promise.resolve(null)
    const heldByOther = call.leaseOwner !== null &&
      call.leaseOwner !== input.owner &&
      call.leaseExpiresAt !== null &&
      call.leaseExpiresAt > input.now
    if (heldByOther) return Promise.resolve(null)
    const fencingToken = call.fencingToken + 1
    this.calls.set(key, {
      ...call,
      leaseOwner: input.owner,
      leaseExpiresAt: input.expiresAt,
      leaseHeartbeatAt: input.now,
      fencingToken,
    })
    return Promise.resolve({
      sessionId: input.sessionId,
      generation: input.generation,
      owner: input.owner,
      fencingToken,
      expiresAt: input.expiresAt,
    })
  }

  #fenceOk(lease: LeaseHandle): CallRow | null {
    const call = this.calls.get(this.#callKey(lease.sessionId, lease.generation))
    if (!call) return null
    if (call.fencingToken !== lease.fencingToken) return null
    return call
  }

  renewLease(lease: LeaseHandle, expiresAt: string, now: string): Promise<boolean> {
    const call = this.#fenceOk(lease)
    if (!call || call.leaseOwner !== lease.owner) return Promise.resolve(false)
    this.calls.set(this.#callKey(lease.sessionId, lease.generation), {
      ...call,
      leaseExpiresAt: expiresAt,
      leaseHeartbeatAt: now,
    })
    return Promise.resolve(true)
  }

  releaseLease(lease: LeaseHandle, now: string): Promise<boolean> {
    const call = this.#fenceOk(lease)
    if (!call || call.leaseOwner !== lease.owner) return Promise.resolve(false)
    this.calls.set(this.#callKey(lease.sessionId, lease.generation), {
      ...call,
      leaseOwner: null,
      leaseExpiresAt: null,
      leaseHeartbeatAt: now,
    })
    return Promise.resolve(true)
  }

  updateCall(lease: LeaseHandle, patch: CallPatch): Promise<boolean> {
    const call = this.#fenceOk(lease)
    if (!call) return Promise.resolve(false)
    this.calls.set(this.#callKey(lease.sessionId, lease.generation), {
      ...call,
      ...(patch.setupState !== undefined ? { setupState: patch.setupState } : {}),
      ...(patch.webrtcHealthy !== undefined
        ? { webrtcHealthy: patch.webrtcHealthy }
        : {}),
      ...(patch.dataChannelHealthy !== undefined
        ? { dataChannelHealthy: patch.dataChannelHealthy }
        : {}),
      ...(patch.sidebandHealthy !== undefined
        ? { sidebandHealthy: patch.sidebandHealthy }
        : {}),
      ...(patch.activeExpiresAt !== undefined
        ? { activeExpiresAt: patch.activeExpiresAt }
        : {}),
      ...(patch.endedAt !== undefined ? { endedAt: patch.endedAt } : {}),
      ...(patch.endReason !== undefined ? { endReason: patch.endReason } : {}),
      ...(patch.hangupState !== undefined ? { hangupState: patch.hangupState } : {}),
      ...(patch.leaseOwner !== undefined ? { leaseOwner: patch.leaseOwner } : {}),
      ...(patch.leaseExpiresAt !== undefined
        ? { leaseExpiresAt: patch.leaseExpiresAt }
        : {}),
    })
    return Promise.resolve(true)
  }

  updateSession(sessionId: string, patch: SessionPatch): Promise<boolean> {
    const session = this.sessions.get(sessionId)
    if (!session) return Promise.resolve(false)
    this.sessions.set(sessionId, {
      ...session,
      ...(patch.state !== undefined ? { state: patch.state } : {}),
      ...(patch.authoritativeReadyAt !== undefined
        ? { authoritativeReadyAt: patch.authoritativeReadyAt }
        : {}),
      ...(patch.endedAt !== undefined ? { endedAt: patch.endedAt } : {}),
      ...(patch.expiresAt !== undefined ? { expiresAt: patch.expiresAt } : {}),
    })
    return Promise.resolve(true)
  }

  allocateTurnSlot(input: {
    conversationId: string
    contextEpoch: number
    direction: 'inbound' | 'outbound'
    turnIndexOverride: number | null
  }): Promise<TurnSlot> {
    const seq = (this.#seq.get(input.conversationId) ?? 0) + 1
    this.#seq.set(input.conversationId, seq)
    const indexKey = `${input.conversationId}:${input.contextEpoch}:${input.direction}`
    const turnIndex = input.turnIndexOverride ?? (this.#turnIndex.get(indexKey) ?? 0) + 1
    this.#turnIndex.set(indexKey, turnIndex)
    const slot = { conversationSeq: seq, turnIndex }
    this.allocated.push(slot)
    return Promise.resolve(slot)
  }

  insertTurn(row: TurnInsert): Promise<void> {
    this.turns.push(row)
    return Promise.resolve()
  }

  insertToolEvent(row: ToolEventInsert): Promise<void> {
    if (this.toolEvents.some((event) => event.id === row.id)) {
      throw new Error('duplicate evidence id')
    }
    this.toolEvents.push(Object.freeze({ ...row }))
    return Promise.resolve()
  }

  insertToolClaim(row: ToolClaimInsert): Promise<'claimed' | 'duplicate'> {
    const key =
      `${row.realtimeSessionId}:${row.realtimeGeneration}:${row.openaiToolCallId}`
    if (this.claims.has(key)) return Promise.resolve('duplicate')
    this.claims.set(key, {
      ...row,
      inboundTurnId: null,
      toolEventId: null,
      settledAt: null,
    })
    return Promise.resolve('claimed')
  }

  loadToolClaim(
    sessionId: string,
    generation: number,
    toolCallId: string,
  ): Promise<ToolClaimRow | null> {
    return Promise.resolve(
      this.claims.get(`${sessionId}:${generation}:${toolCallId}`) ?? null,
    )
  }

  settleToolClaim(input: {
    claimId: string
    state: ToolClaimState
    toolEventId: string | null
    settledAt: string
  }): Promise<void> {
    for (const [key, claim] of this.claims) {
      if (claim.id !== input.claimId) continue
      this.claims.set(key, {
        ...claim,
        state: input.state,
        toolEventId: input.toolEventId,
        settledAt: input.settledAt,
      })
    }
    return Promise.resolve()
  }

  backfillClaimInboundTurn(input: {
    sessionId: string
    generation: number
    interactionId: string
    inboundTurnId: string
  }): Promise<number> {
    let linked = 0
    for (const [key, claim] of this.claims) {
      if (claim.realtimeSessionId !== input.sessionId) continue
      if (claim.realtimeGeneration !== input.generation) continue
      if (claim.realtimeInteractionId !== input.interactionId) continue
      if (claim.inboundTurnId !== null) continue
      this.claims.set(key, { ...claim, inboundTurnId: input.inboundTurnId })
      linked += 1
    }
    return Promise.resolve(linked)
  }

  insertUsageSlices(slices: readonly UsageSlice[]): Promise<void> {
    for (const slice of slices) {
      const key = `${slice.sessionId}:${slice.usageDate}`
      // ON CONFLICT DO NOTHING.
      if (!this.usage.has(key)) this.usage.set(key, slice)
    }
    return Promise.resolve()
  }

  insertResponseUsage(row: ResponseUsageInsert): Promise<void> {
    if (this.failInsertResponseUsage) {
      return Promise.reject(new Error('fake_insert_response_usage_failed'))
    }
    const key = `${row.sessionId}:${row.responseId}`
    // ON CONFLICT DO NOTHING.
    if (!this.responseUsage.has(key)) this.responseUsage.set(key, row)
    return Promise.resolve()
  }

  markUsageSettled(sessionId: string, settledAt: string): Promise<boolean> {
    const session = this.sessions.get(sessionId)
    if (!session || session.usageSettledAt !== null) return Promise.resolve(false)
    this.sessions.set(sessionId, { ...session, usageSettledAt: settledAt })
    return Promise.resolve(true)
  }

  findCleanupCandidates(now: string, limit: number): Promise<CleanupCandidate[]> {
    const setupStates = new Set([
      'provisioning',
      'call_registered',
      'binding',
      'sideband_connecting',
    ])
    const out: CleanupCandidate[] = []
    for (const call of this.calls.values()) {
      const expiredSetup = setupStates.has(call.setupState) && call.setupDeadlineAt < now
      if (call.setupState !== 'cleanup_pending' && !expiredSetup) continue
      out.push({
        sessionId: call.sessionId,
        generation: call.generation,
        openaiCallId: call.openaiCallId,
        setupState: call.setupState,
        fencingToken: call.fencingToken,
      })
      if (out.length >= limit) break
    }
    return Promise.resolve(out)
  }

  claimCleanup(input: {
    sessionId: string
    generation: number
    owner: string
    expectedFence: number
    now: string
    expiresAt: string
  }): Promise<LeaseHandle | null> {
    const key = this.#callKey(input.sessionId, input.generation)
    const call = this.calls.get(key)
    if (!call || call.fencingToken !== input.expectedFence) return Promise.resolve(null)
    const fencingToken = input.expectedFence + 1
    this.calls.set(key, {
      ...call,
      leaseOwner: input.owner,
      leaseExpiresAt: input.expiresAt,
      fencingToken,
    })
    return Promise.resolve({
      sessionId: input.sessionId,
      generation: input.generation,
      owner: input.owner,
      fencingToken,
      expiresAt: input.expiresAt,
    })
  }

  findUnsettledSessions(limit: number): Promise<SessionRow[]> {
    const out: SessionRow[] = []
    for (const session of this.sessions.values()) {
      if (session.usageSettledAt !== null) continue
      if (session.state !== 'ended' && session.state !== 'failed') continue
      out.push(session)
      if (out.length >= limit) break
    }
    return Promise.resolve(out)
  }

  markGenerationsCleanupPending(input: {
    owner: string
    endReason: string
    now: string
  }): Promise<number> {
    this.handoffCalls += 1
    const live = new Set([
      'provisioning',
      'call_registered',
      'binding',
      'sideband_connecting',
      'active',
      'ending',
    ])
    let count = 0
    for (const [key, call] of this.calls) {
      if (call.leaseOwner !== input.owner) continue
      if (!live.has(call.setupState)) continue
      this.calls.set(key, {
        ...call,
        setupState: 'cleanup_pending',
        endReason: input.endReason,
        leaseOwner: null,
        leaseExpiresAt: null,
      })
      count += 1
    }
    return Promise.resolve(count)
  }

  /** Seed a durable turn directly, bypassing insertTurn's slot allocation. */
  addTurn(turn: TurnInsert): void {
    this.turns.push(turn)
  }

  loadRecentTurns(input: {
    conversationId: string
    contextEpoch: number
    limit: number
  }): Promise<RecentTurn[]> {
    if (this.failRecentTurns) {
      return Promise.reject(new Error('fake_load_recent_turns_failed'))
    }
    const matches = this.turns
      .filter((turn) =>
        turn.conversationId === input.conversationId &&
        turn.contextEpoch === input.contextEpoch &&
        turn.completionStatus === 'finalized' &&
        turn.text.trim() !== ''
      )
      .sort((a, b) => b.conversationSeq - a.conversationSeq)
      .slice(0, input.limit)
      .map((turn) => ({ direction: turn.direction, text: turn.text }))
    return Promise.resolve(matches)
  }

  touchConversation(conversationId: string, updatedAt: string): Promise<void> {
    if (this.failTouchConversation) {
      return Promise.reject(new Error('fake_touch_conversation_failed'))
    }
    this.conversationTouches.push({ conversationId, updatedAt })
    return Promise.resolve()
  }
}

export class FakeSidebandSocket implements SidebandSocket {
  sent: Record<string, unknown>[] = []
  closed = false
  isOpen = true
  #messageHandlers: ((event: Record<string, unknown>) => void)[] = []
  #closeHandlers: ((code: number) => void)[] = []
  #errorHandlers: ((error: unknown) => void)[] = []

  send(payload: unknown): void {
    this.sent.push(payload as Record<string, unknown>)
  }

  close(): void {
    this.closed = true
    this.isOpen = false
    for (const handler of this.#closeHandlers) handler(1000)
  }

  onMessage(handler: (event: Record<string, unknown>) => void): void {
    this.#messageHandlers.push(handler)
  }

  onClose(handler: (code: number) => void): void {
    this.#closeHandlers.push(handler)
  }

  onError(handler: (error: unknown) => void): void {
    this.#errorHandlers.push(handler)
  }

  /** Deliver a provider event synchronously and await every handler. */
  async emit(event: Record<string, unknown>): Promise<void> {
    for (const handler of this.#messageHandlers) await handler(event)
  }

  sentOfType(type: string): Record<string, unknown>[] {
    return this.sent.filter((frame) => frame.type === type)
  }
}

export class FakeClientSocket {
  sent: string[] = []
  closedWith: { code: number; reason?: string } | null = null

  send(data: string): void {
    this.sent.push(data)
  }

  close(code: number, reason?: string): void {
    if (!this.closedWith) this.closedWith = { code, reason }
  }

  notices(): Record<string, unknown>[] {
    return this.sent.map((line) => JSON.parse(line) as Record<string, unknown>)
  }

  noticeTypes(): string[] {
    return this.notices().map((notice) => String(notice.type))
  }
}
