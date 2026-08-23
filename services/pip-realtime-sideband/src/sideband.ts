// The sideband: attach to a live call, configure it, gate READY, and own every
// authoritative consequence of the conversation.

import { WebSocket as NodeWebSocket } from 'ws'
import type { RealtimeConfig } from './config.ts'
import { isoAt, newId } from './ids.ts'
import { errorShape, log } from './log.ts'
import type { LeaseKeeper } from './lease.ts'
import { InteractionTracker } from './interaction.ts'
import { ToolCallCoordinator, type ToolLedgerOwnership } from './claims.ts'
import { parseResponseUsage } from './response_usage.ts'
import {
  buildSessionUpdate,
  partitionToolCatalogue,
  type RealtimeToolDefinition,
} from './session_config.ts'
import type {
  CompletionStatus,
  RealtimeStore,
  RecentTurn,
  SessionRow,
  TurnDirection,
} from './store.ts'

// ---------------------------------------------------------------------------
// Transport
// ---------------------------------------------------------------------------

export interface SidebandSocket {
  send(payload: unknown): void
  close(code?: number, reason?: string): void
  onMessage(handler: (event: Record<string, unknown>) => void): void
  onClose(handler: (code: number) => void): void
  onError(handler: (error: unknown) => void): void
  readonly isOpen: boolean
}

/**
 * Attach to an in-progress call.
 *
 * THREE transports were tried against the live endpoint before this one; the
 * other two are recorded here so nobody reintroduces them:
 *
 * 1. Deno's built-in `WebSocket` cannot set arbitrary request headers, so the
 *    first attempt sent the key as the `openai-insecure-api-key.<KEY>`
 *    subprotocol (`new WebSocket(url, ['realtime', 'openai-insecure-api-key.
 *    <KEY>'])`). curl-proven against the real endpoint: OpenAI answers with
 *    HTTP 401 "You didn't provide an API key" — this endpoint does not accept
 *    a standard `sk-` key over that subprotocol, whatever the docs for the
 *    ephemeral-key flow imply.
 * 2. Deno's `WebSocketStream` (which DOES support a `headers` option)
 *    negotiates over h2 by default, and OpenAI's realtime attach endpoint
 *    responds to an h2 upgrade with a flat 400 before the socket ever opens.
 * 3. `npm:ws` with `{ headers: { Authorization: 'Bearer <key>' } }` and NO
 *    subprotocols, forced onto http/1.1 (`ws`'s default): this is the one
 *    verified end to end. A fake-call probe against the live endpoint reached
 *    the auth layer and came back with OpenAI's own JSON 404
 *    `call_id_not_found` — proof the request cleared authorization and failed
 *    only on the (expected, in the probe) missing call.
 *
 * So: `ws`, header auth, no subprotocols, http/1.1. `NodeWebSocket` is the
 * transport for real traffic; `wrapNodeWs` below adapts it to the internal
 * `SidebandSocket` interface tests already speak.
 *
 * A connection that never reaches `open` — auth rejection, TLS failure,
 * anything before the handshake completes — is retried a few times with a
 * short pause, since a single blip here strands a live call with nobody
 * listening. Once a socket has opened, failures are the existing
 * onError/onClose teardown path's problem, not a reason to dial again.
 */
const ATTACH_MAX_RETRIES = 2
const ATTACH_RETRY_DELAY_MS = 750

function defaultSleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

/**
 * Wrap an already-constructed raw socket and resolve only once it reaches
 * `open`; reject on whatever happens first instead (auth rejection, TLS
 * failure, an immediate close). The `settled` guard is the mechanism behind
 * "post-open failures do not retry": once `open` (or a pre-open failure) has
 * settled this promise, later `error`/`close` events still reach any handler
 * a caller separately registered via the returned `SidebandSocket` — they
 * just no longer affect an already-settled attach attempt.
 *
 * Split out from `attemptAttach` (below) purely so tests can drive it with a
 * fake `NodeWsLike` instead of a real `ws` socket — this function never
 * touches the network itself, `NodeWebSocket` construction does.
 */
export function awaitSidebandOpen(raw: NodeWsLike): Promise<SidebandSocket> {
  return new Promise((resolve, reject) => {
    let settled = false
    const socket = wrapNodeWs(raw, () => {
      if (settled) return
      settled = true
      resolve(socket)
    })
    // `unexpected-response` already logged the forensic line inside
    // wrapNodeWs; here it is just another reason this attempt failed to open.
    socket.onError((error) => {
      if (settled) return
      settled = true
      reject(error instanceof Error ? error : new Error(errorShape(error)))
    })
    socket.onClose((code) => {
      if (settled) return
      settled = true
      reject(new Error(`sideband_closed_before_open:${code}`))
    })
  })
}

/**
 * Dial once and resolve only on `open`; reject on anything that happens
 * first. Kept separate from the retry loop so each attempt is a clean,
 * independently-awaitable unit.
 */
function attemptAttach(url: string, bearer: string): Promise<SidebandSocket> {
  const raw = new NodeWebSocket(url, { headers: { Authorization: `Bearer ${bearer}` } })
  return awaitSidebandOpen(raw)
}

/**
 * Retry wrapper around a single dial attempt. `dial` and `sleep` are seams so
 * tests can exercise the retry/backoff behavior with a fake dialer and no
 * real timers, never touching the network.
 */
export async function attachWithRetry(
  dial: () => Promise<SidebandSocket>,
  options: {
    retries?: number
    delayMs?: number
    sleep?: (ms: number) => Promise<void>
  } = {},
): Promise<SidebandSocket> {
  const retries = options.retries ?? ATTACH_MAX_RETRIES
  const delayMs = options.delayMs ?? ATTACH_RETRY_DELAY_MS
  const sleep = options.sleep ?? defaultSleep
  let lastError: unknown = new Error('sideband_attach_failed')
  for (let attempt = 1; attempt <= retries + 1; attempt++) {
    try {
      return await dial()
    } catch (error) {
      lastError = error
      if (attempt > retries) break
      log.warn('sideband.attach_retry', { attempt: attempt + 1 })
      await sleep(delayMs)
    }
  }
  throw lastError instanceof Error ? lastError : new Error(String(lastError))
}

export function connectSideband(
  config: RealtimeConfig,
  callId: string,
  clientSecret?: string | null,
): Promise<SidebandSocket> {
  const url = `${config.openAiRealtimeUrl}?call_id=${encodeURIComponent(callId)}`
  // The attach bearer must be the EPHEMERAL client secret that minted the
  // call. Proven on a live call 2026-08-17: a standard `sk-` key — which the
  // provider's own docs show — is answered with 404 `call_id_not_found`,
  // while the call's `ek_` secret attaches and acks session.update. The
  // standard key remains only as a fallback for legacy call rows that were
  // provisioned before the secret was persisted.
  const bearer = clientSecret ?? config.openAiApiKey
  return attachWithRetry(() => attemptAttach(url, bearer))
}

/**
 * The minimal slice of the `ws` package's `WebSocket` this module depends on,
 * factored out so tests can supply a fake event emitter instead of a real
 * socket. `res` on `unexpected-response` is Node's `http.IncomingMessage`
 * shape, likewise narrowed to what is actually read.
 */
export interface NodeWsLike {
  readyState: number
  send(data: string): void
  close(code?: number, reason?: string): void
  on(event: 'open', listener: () => void): void
  on(event: 'message', listener: (data: unknown) => void): void
  on(event: 'close', listener: (code: number) => void): void
  on(event: 'error', listener: (error: unknown) => void): void
  on(
    event: 'unexpected-response',
    listener: (request: unknown, response: NodeWsResponseLike) => void,
  ): void
}

export interface NodeWsResponseLike {
  statusCode?: number
  on(event: 'data', listener: (chunk: unknown) => void): void
  on(event: 'end', listener: () => void): void
}

/** `ws`'s readyState values are numerically identical to the DOM WebSocket's. */
const NODE_WS_OPEN = 1

/** Frame bodies this diagnostic line is allowed to keep, per FORBIDDEN_KEYS. */
const ATTACH_REJECTED_BODY_MAX_CHARS = 140

/**
 * Adapt an `npm:ws` socket to the `SidebandSocket` interface the rest of this
 * module speaks. `onOpen` is a second seam (beyond the returned
 * `SidebandSocket`) so `attemptAttach` can observe the open transition
 * directly, without also having to expose it on the public interface.
 */
export function wrapNodeWs(socket: NodeWsLike, onOpen?: () => void): SidebandSocket {
  const queue: unknown[] = []
  const messageHandlers: ((event: Record<string, unknown>) => void)[] = []
  const closeHandlers: ((code: number) => void)[] = []
  const errorHandlers: ((error: unknown) => void)[] = []

  socket.on('open', () => {
    for (const payload of queue.splice(0)) socket.send(JSON.stringify(payload))
    onOpen?.()
  })

  socket.on('message', (data) => {
    // `ws` hands back a Buffer (or, for fragmented/binary frames, an
    // ArrayBuffer/Buffer[]) — never a string the way the browser WebSocket
    // does. Realtime only ever sends text JSON frames over this socket, so
    // decoding via Buffer/Uint8Array's own utf8 `toString` is always correct;
    // anything that is neither a string nor bytes falls through to the
    // unparseable-frame path below rather than being guessed at.
    let text: string
    if (typeof data === 'string') {
      text = data
    } else if (data instanceof Uint8Array) {
      text = new TextDecoder().decode(data)
    } else {
      log.warn('sideband.unparseable_frame')
      return
    }
    try {
      const parsed = JSON.parse(text) as Record<string, unknown>
      for (const handler of messageHandlers) handler(parsed)
    } catch {
      log.warn('sideband.unparseable_frame')
    }
  })

  socket.on('close', (code) => {
    for (const handler of closeHandlers) handler(code)
  })

  socket.on('error', (error) => {
    for (const handler of errorHandlers) handler(error)
  })

  // MANDATORY diagnosability: an attach rejection (bad auth, wrong URL shape,
  // provider outage) otherwise surfaces as a bare socket close with no reason
  // anywhere in the logs, which is exactly the failure mode this transport
  // swap exists to stop repeating. This is the line that tells us why the
  // FIRST real call after deploy failed to attach.
  socket.on('unexpected-response', (_request, response) => {
    let body = ''
    response.on('data', (chunk) => {
      body += typeof chunk === 'string' ? chunk : String(chunk)
    })
    response.on('end', () => {
      log.warn('sideband.attach_rejected', {
        status: response.statusCode ?? 0,
        body: body.slice(0, ATTACH_REJECTED_BODY_MAX_CHARS),
      })
      // `ws` does not close the socket on our behalf for this event, and does
      // not itself emit 'error' or 'close' either — so both are raised here,
      // deliberately, to route into the same teardown path every other
      // attach failure uses. Close code 0 is not a real WebSocket close code;
      // it just means "never got far enough to have one."
      for (const handler of errorHandlers) handler(new Error('attach_rejected'))
      for (const handler of closeHandlers) handler(0)
    })
  })

  return {
    get isOpen() {
      return socket.readyState === NODE_WS_OPEN
    },
    send(payload) {
      if (socket.readyState === NODE_WS_OPEN) socket.send(JSON.stringify(payload))
      else queue.push(payload)
    },
    close(code, reason) {
      try {
        socket.close(code, reason)
      } catch {
        // Already closing; closing twice is not an error worth propagating.
      }
    },
    onMessage(handler) {
      messageHandlers.push(handler)
    },
    onClose(handler) {
      closeHandlers.push(handler)
    },
    onError(handler) {
      errorHandlers.push(handler)
    },
  }
}

// ---------------------------------------------------------------------------
// Readiness
// ---------------------------------------------------------------------------

export const READINESS_PRECONDITIONS = [
  'webrtcHealthy',
  'dataChannelHealthy',
  'callRegistered',
  'bindingValid',
  'leaseHeld',
  'sidebandAttached',
  'authorizationRevalidated',
  'configAcknowledged',
  // Marked once conversation-context injection SETTLES — successfully, on
  // failure, or on its bounded timeout (see CONTEXT_INJECTION_TIMEOUT_MS).
  // Never marked before that, so a slow context fetch cannot let READY (and
  // the caller's first live utterance) race ahead of the history it was
  // meant to prime the model with.
  'contextInjected',
] as const

export type ReadinessPrecondition = typeof READINESS_PRECONDITIONS[number]

/**
 * READY is an all-or-nothing claim: it tells the client the assistant can hear
 * it AND that anything it says will be acted on under a valid authorization.
 * Emitting it while any leg is unproven produces a session that looks alive and
 * silently drops or misattributes work, so the gate is conjunctive with no
 * "probably fine" cases.
 */
export class ReadinessGate {
  readonly #met = new Set<ReadinessPrecondition>()
  #announced = false

  mark(precondition: ReadinessPrecondition): void {
    this.#met.add(precondition)
  }

  clear(precondition: ReadinessPrecondition): void {
    this.#met.delete(precondition)
    this.#announced = false
  }

  has(precondition: ReadinessPrecondition): boolean {
    return this.#met.has(precondition)
  }

  get missing(): ReadinessPrecondition[] {
    return READINESS_PRECONDITIONS.filter((item) => !this.#met.has(item))
  }

  get satisfied(): boolean {
    return this.missing.length === 0
  }

  /** True exactly once, on the transition into a fully satisfied state. */
  shouldAnnounce(): boolean {
    if (!this.satisfied || this.#announced) return false
    this.#announced = true
    return true
  }
}

// ---------------------------------------------------------------------------
// Conversation context injection
// ---------------------------------------------------------------------------

/** Recent finalized turns considered for injection into a fresh session. */
const CONTEXT_TURN_LIMIT = 12
/** Per-turn text is tail-truncated (keep the END, drop the start) at this length. */
const CONTEXT_PER_TURN_CHAR_CAP = 600
/** Total injected text across every item. Oldest turns are dropped first to fit. */
const CONTEXT_TOTAL_CHAR_CAP = 4000
/**
 * Upper bound on how long the store fetch may hold up READY. Injection is
 * still worth gating READY on (a slow-but-fast-enough fetch should still land
 * before the caller's first utterance), but it must never be able to hang a
 * call — a store outage degrades to "no history injected", not "no READY".
 */
const CONTEXT_INJECTION_TIMEOUT_MS = 500

/** See `#maybeUpgradeToolCatalogue`'s catch block for why 2s. */
const INTAKE_UPGRADE_ACK_TIMEOUT_MS = 2000
/** One retry only: a second `propose_intake` may resend a rejected upgrade,
 * after which the session settles for the core catalogue rather than spending
 * more of a live turn on session.update round trips. */
const MAX_INTAKE_UPGRADE_ATTEMPTS = 2

/** Rejects with `reason` if `promise` has not settled within `timeoutMs`. The
 * loser keeps running in the background and is simply ignored. */
function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  reason: string,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(reason)), timeoutMs)
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

interface ContextItem {
  readonly role: 'user' | 'assistant'
  readonly contentType: 'input_text' | 'text'
  readonly text: string
}

/**
 * Turn the newest-first recent turns into the oldest-first set of items to
 * inject, applying the per-turn and total character caps. The total cap is
 * enforced by walking newest-first and stopping the moment the next turn
 * would overflow the budget, which is exactly "drop the oldest turns first":
 * whatever is left unvisited when the walk stops is older than everything
 * already kept.
 */
function buildContextItems(turnsNewestFirst: readonly RecentTurn[]): ContextItem[] {
  const kept: ContextItem[] = []
  let total = 0
  for (const turn of turnsNewestFirst) {
    const truncated = turn.text.length > CONTEXT_PER_TURN_CHAR_CAP
      ? turn.text.slice(-CONTEXT_PER_TURN_CHAR_CAP)
      : turn.text
    if (truncated.length === 0) continue
    if (total + truncated.length > CONTEXT_TOTAL_CHAR_CAP) break
    kept.push({
      role: turn.direction === 'inbound' ? 'user' : 'assistant',
      contentType: turn.direction === 'inbound' ? 'input_text' : 'text',
      text: truncated,
    })
    total += truncated.length
  }
  return kept.reverse()
}

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

/**
 * Everything this service ever says to the client. See ../WIRE_CONTRACT.md.
 *
 * Note what is absent: captions and turn states. Transcript deltas reach the app
 * over its own WebRTC data channel straight from OpenAI; the transcripts
 * accumulated here exist only to persist durable turns.
 */
export type ClientNotice =
  | { type: 'ready'; session_id: string; generation: number }
  | { type: 'error'; code: string }
  | { type: 'closing'; reason: string }

export interface SidebandSessionOptions {
  readonly config: RealtimeConfig
  readonly store: RealtimeStore
  readonly socket: SidebandSocket
  readonly lease: LeaseKeeper
  readonly session: SessionRow
  readonly generation: number
  readonly leaseOwner: string
  readonly tools: readonly RealtimeToolDefinition[]
  /** Executors PLUS who owns the durable ledger for their calls. Required. */
  readonly ownership: ToolLedgerOwnership
  readonly notifyClient: (notice: ClientNotice) => void
  readonly now: () => Date
  readonly instructions: string
  /** Overrides CONTEXT_INJECTION_TIMEOUT_MS. Test seam only. */
  readonly contextInjectionTimeoutMs?: number
  /** Overrides INTAKE_UPGRADE_ACK_TIMEOUT_MS. Test seam only. */
  readonly intakeUpgradeAckTimeoutMs?: number
  /**
   * The provider socket went away mid-call. The session has already stopped
   * itself by the time this runs; the owner's job is to tell the CLIENT, so
   * it can fail over into a new generation instead of talking to a session
   * with no authority left behind it.
   */
  readonly onSidebandClosed?: (code: number) => void
}

interface PendingAssistantItem {
  readonly responseId: string
  text: string
  completed: boolean
}

function detectLanguage(text: string): 'en' | 'ar' | 'mixed' {
  const hasArabic = /[؀-ۿ]/.test(text)
  const hasLatin = /[A-Za-z]/.test(text)
  if (hasArabic && hasLatin) return 'mixed'
  if (hasArabic) return 'ar'
  return 'en'
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' ? value as Record<string, unknown> : {}
}

/** SHA-256 hex of arbitrary text. Used to fingerprint instructions in logs
 * without ever logging the text itself (log.ts forbids `instructions`). */
export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

/** Cloud Run stamps K_REVISION on every instance. Absent locally and in tests. */
function cloudRunRevision(): string {
  try {
    return Deno.env.get('K_REVISION') ?? 'unknown'
  } catch (_) {
    return 'unknown'
  }
}

export class SidebandSession {
  readonly #options: SidebandSessionOptions
  readonly #tracker: InteractionTracker
  readonly #coordinator: ToolCallCoordinator
  readonly gate = new ReadinessGate()

  /** item_id -> accumulating assistant transcript. Deltas live here and nowhere else. */
  readonly #assistantItems = new Map<string, PendingAssistantItem>()
  /** response_id -> whether it produced a tool call (drives chain attribution). */
  readonly #responseProducedTool = new Set<string>()
  /**
   * Tool names submitted (via `function_call_output`) out of ONE originating
   * response, waiting to be attributed to whichever response the sideband's
   * own follow-up `response.create` produces.
   *
   * The invariant, and why it is keyed by origin rather than being a bare FIFO
   * queue: every name here came from the same originating response, so when
   * that response emitted TWO function calls both names belong to the SINGLE
   * follow-up they jointly caused — they must land on one row together, not be
   * split across two rows where the second is falsely `followed_tool_call:
   * false`. `#pendingFollowupOrigin` is what enforces "same origin": a push
   * from a different response replaces the pending set rather than appending
   * to it.
   *
   * The pending set is ALSO cleared when a new user utterance is committed
   * (see `input_audio_buffer.committed`). Without that, a barge-in — where the
   * user interrupts and our follow-up `response.create` is superseded or
   * rejected with `conversation_already_has_active_response`, so no
   * `response.created` ever consumes these names — would leave them to be
   * stamped onto some unrelated response one or more turns later. This table
   * exists to answer "are tool-following inferences the TPM cost driver", so
   * an attribution that drifts across turns is worse than none.
   */
  #pendingFollowupToolNames: string[] = []
  /** Originating response id for `#pendingFollowupToolNames`; see above. */
  #pendingFollowupOrigin: string | null = null
  /**
   * Serialises `#onOutputItemDone` across handler invocations.
   *
   * `socket.onMessage((event) => void this.handleEvent(event))` fires and
   * forgets, so two `response.output_item.done` events from the SAME response
   * run concurrently, and each one awaits a broker round trip. Without this
   * chain, a response carrying `propose_intake` plus one other tool can
   * interleave so that the other tool's `response.create` goes out while
   * `propose_intake` is still in flight — the intake `session.update` then
   * lands AFTER it, and the model answers the user's data-entry request with
   * the core catalogue it started the call with.
   *
   * The ordering guarantee this buys spans handlers, not just one handler
   * body: tool outputs are submitted, the catalogue is upgraded, and
   * `response.create` is sent, strictly in arrival order. Only this one event
   * type is serialised — transcripts, deltas and `response.done` still run
   * immediately, so a slow broker call cannot stall unrelated work.
   */
  #toolOutputChain: Promise<void> = Promise.resolve()
  /** response_id -> tool names it followed, for the one telemetry row this
   * response's `response.done` will write. Consumed (deleted) in
   * `#onResponseDone`, so a response id is never attributed twice. */
  readonly #responseFollowedTool = new Map<string, readonly string[]>()
  #configAckResolve: (() => void) | null = null
  /**
   * The intake tool family this session was constructed with, split once at
   * construction time (see `partitionToolCatalogue`). `#activeTools` is
   * whichever of the two is currently advertised to the model — `#coreTools`
   * until `propose_intake` is CALLED, `#fullTools` forever after (see
   * `#maybeUpgradeToolCatalogue`). `#sendSessionConfig` is the ONLY reader of
   * `#activeTools`, so every `session.update` this session ever sends —
   * initial, `vad_fallback`, or `intake_upgrade` — automatically carries
   * whichever catalogue is current instead of each call site having to
   * remember which one applies.
   */
  readonly #coreTools: readonly RealtimeToolDefinition[]
  readonly #fullTools: readonly RealtimeToolDefinition[]
  #activeTools: readonly RealtimeToolDefinition[]
  #toolsUpgraded = false
  /** Upgrade sends made this session; bounded by MAX_INTAKE_UPGRADE_ATTEMPTS. */
  #upgradeAttempts = 0
  /** Resolved by the next `session.updated` after an `intake_upgrade` send.
   * Distinct from `#configAckResolve` (the initial handshake's resolver) so
   * neither can consume the other's ack: by the time an upgrade can fire, the
   * initial resolver has already been nulled out by its own ack, but keeping
   * them as separate fields means that stays true by construction rather than
   * by timing luck. */
  #upgradeAckResolve: (() => void) | null = null
  /**
   * Mirrors whichever `turn_detection` shape was last actually SENT, so an
   * `intake_upgrade` resend after a `vad_fallback` re-sends `server_vad`
   * rather than silently reverting the call to the configured default.
   * Updated only at the `vad_fallback` send site below.
   */
  #activeTurnDetection: 'semantic_vad' | 'server_vad'
  #stopped = false
  /**
   * Per-session `insertResponseUsage` accounting, purely for log escalation —
   * never read by any control-flow decision, so a bug here cannot affect the
   * call. `#responseUsageAttempts` counts every `response.done` that carried
   * parseable usage (i.e. every time `#persistResponseUsage` actually called
   * the store); `#responseUsageFailures` counts how many of those threw.
   * `#responseUsageFirstFailureLogged` gates the one-time louder log line so
   * a long call with a persistently broken store logs one loud event and then
   * quiet ones, never a loud line per response.
   */
  #responseUsageAttempts = 0
  #responseUsageFailures = 0
  #responseUsageFirstFailureLogged = false
  /** Fingerprint of the instructions THIS session sends. Resolved off-path so
   * the config send itself stays synchronous (tests and the attach sequence
   * rely on the frame leaving before any await). */
  #instructionsShaPromise: Promise<string> | null = null
  /** Count of session.update frames this session has sent (fingerprint evidence). */
  #updateSeq = 0
  /** Count of session.updated acks received from the provider. */
  #ackSeq = 0
  /**
   * One-shot guard for the `turn_detection` fallback below: a provider
   * `error` naming `turn_detection` before the config is ever acknowledged
   * triggers exactly one resend with `server_vad` forced. This is cheap
   * insurance against provider drift on `semantic_vad` support — the
   * fallback is armed regardless of the configured default, but it can only
   * ever fire once per session so a persistently broken config still fails
   * loud instead of looping.
   */
  #vadFallbackAttempted = false
  /**
   * The `response.create` this sideband sent and has not yet seen open.
   *
   * A rejected `response.create` is answered by the provider with an `error`
   * event and NOTHING ELSE — no response is generated. On the forced-final
   * path that is the worst possible moment for it: the interaction is already
   * closed to further continuations, so the caller is left in silence at the
   * exact point they were owed an answer. Remembering which frame is
   * outstanding is what lets the `error` handler tell "the response I just
   * asked for was refused" from every other provider error.
   *
   * `event_id` is echoed back on the corresponding error, so it is the join
   * key; the interaction and the forced-final flag ride along because the
   * recovery differs between the two cases.
   */
  #pendingResponseCreate:
    | { eventId: string; interactionId: string; forcedFinal: boolean }
    | null = null
  /**
   * Interactions whose forced final was rejected and retried plainly. One
   * retry each, ever — the retry itself is not pinned to `tool_choice:'none'`,
   * so it could in principle produce another tool call, and the tracker's
   * sticky `finalForced` is what stops that becoming a chain.
   */
  readonly #finalFallbackInteractions = new Set<string>()
  /**
   * The conversation-context injection kicked off right after the initial
   * `session.update` send. Never awaited on the readiness path — injection
   * must not delay or fail a call — but exposed so tests can await it
   * deterministically instead of racing microtask timing.
   */
  #contextInjectionPromise: Promise<void> = Promise.resolve()

  constructor(options: SidebandSessionOptions) {
    this.#options = options
    const partition = partitionToolCatalogue(options.tools)
    this.#coreTools = partition.core
    this.#fullTools = partition.full
    this.#activeTools = this.#coreTools
    this.#activeTurnDetection = options.config.turnDetection
    this.#tracker = new InteractionTracker(options.config.maxToolCallsPerInteraction)
    this.#coordinator = new ToolCallCoordinator({
      store: options.store,
      tracker: this.#tracker,
      sessionId: options.session.id,
      generation: options.generation,
      leaseOwner: options.leaseOwner,
      leaseSeconds: options.config.leaseSeconds,
      authorizationFingerprint: options.session.authorizationFingerprint,
      now: options.now,
      ownership: options.ownership,
      // A tool call is refused outright once this worker stops being the live
      // one for the generation: a stopped session or a lost/released lease means
      // someone else now owns these consequences.
      liveness: () => {
        if (this.#stopped) return 'session_stopped'
        if (!options.lease.held) return 'fence_lost'
        const handle = options.lease.handle
        if (handle && handle.generation !== options.generation) return 'stale_generation'
        return null
      },
    })
  }

  get tracker(): InteractionTracker {
    return this.#tracker
  }

  get stopped(): boolean {
    return this.#stopped
  }

  /** Test/observability seam: settles once context injection has run (or given up). */
  get contextInjectionPromise(): Promise<void> {
    return this.#contextInjectionPromise
  }

  /**
   * Send the full configuration and wait for `session.updated`, which is the
   * provider's acknowledgement that it was APPLIED. Treating the send as success
   * would let a session run with default VAD, default voice and no tools.
   */
  async attachAndConfigure(): Promise<void> {
    // `.catch`, not `void`. `handleEvent` re-throws after logging (see its
    // catch) so a caller that awaits it can react, but THIS dispatch does not
    // await — and Deno kills the process on an unhandled rejection. A single
    // transient PostgREST 5xx inside `#persistTurn`, or a `FenceLostError`
    // out of `maybeAnnounceReady`, would therefore take down every other
    // concurrent call on the instance, not just this one. `main.ts` carries a
    // second, process-level guard for the same reason: this class of bug is
    // one missing `.catch` away at all times.
    this.#options.socket.onMessage((event) =>
      void this.handleEvent(event).catch((error) =>
        log.error('sideband.event_unhandled', {
          session_id: this.#options.session.id,
          generation: this.#options.generation,
          detail: errorShape(error),
        })
      )
    )
    this.#options.socket.onError((error) =>
      log.warn('sideband.socket_error', { detail: errorShape(error) })
    )
    this.#options.socket.onClose((code) => {
      this.gate.clear('sidebandAttached')
      log.info('sideband.socket_closed', { code })
      // Clearing the gate is not enough on its own. READY has usually already
      // been announced by this point, so nothing re-checks the preconditions,
      // and the caller's own WebRTC leg to OpenAI is a SEPARATE connection
      // that is still up — the model keeps talking while this service can no
      // longer execute a tool, persist a turn, or drive a response. Left
      // alone the session reports healthy, keeps heartbeating its lease, and
      // silently queues every frame it tries to send into a socket that will
      // never open again. Stopping refuses further tool work outright (see
      // the liveness guard), and the callback lets the owner close the client
      // so it can start a fresh generation.
      const alreadyStopped = this.#stopped
      this.stop('sideband_socket_closed')
      if (!alreadyStopped) this.#options.onSidebandClosed?.(code)
    })

    this.gate.mark('sidebandAttached')
    const acknowledged = new Promise<void>((resolve) => {
      this.#configAckResolve = resolve
    })
    this.#sendSessionConfig('initial', this.#activeTurnDetection)
    // Same socket immediately after session.update, so wire ordering is
    // preserved. NOT awaited here — attachAndConfigure() itself must not
    // block on it — but READY is still gated on it via the 'contextInjected'
    // precondition (marked at the end of #injectRecentContext, bounded by
    // CONTEXT_INJECTION_TIMEOUT_MS): a fast fetch lands its history before
    // the caller's first live utterance; a slow or hung one degrades to no
    // history rather than delaying READY past the timeout.
    this.#contextInjectionPromise = this.#injectRecentContext()
    await acknowledged
  }

  /**
   * Best-effort: hand the model the recent finalized turns of this
   * conversation so the caller can pick a typed/voice conversation back up.
   * Any failure here — the store fetch, a timeout, or a send — is swallowed
   * after a content-free warning log; READY still requires this to have
   * SETTLED (see the 'contextInjected' precondition) but never waits past
   * CONTEXT_INJECTION_TIMEOUT_MS for it.
   */
  async #injectRecentContext(): Promise<void> {
    const { session, socket } = this.#options
    try {
      const timeoutMs = this.#options.contextInjectionTimeoutMs ??
        CONTEXT_INJECTION_TIMEOUT_MS
      const turnsNewestFirst = await withTimeout(
        this.#options.store.loadRecentTurns({
          conversationId: session.conversationId,
          contextEpoch: session.contextEpoch,
          limit: CONTEXT_TURN_LIMIT,
        }),
        timeoutMs,
        'context_injection_timeout',
      )
      if (turnsNewestFirst.length === 0) return
      const items = buildContextItems(turnsNewestFirst)
      for (const item of items) {
        socket.send({
          type: 'conversation.item.create',
          item: {
            type: 'message',
            role: item.role,
            content: [{ type: item.contentType, text: item.text }],
          },
        })
      }
      log.info('context_injection.sent', {
        session_id: session.id,
        generation: this.#options.generation,
        fetched: turnsNewestFirst.length,
        sent: items.length,
      })
    } catch (error) {
      // Never the turn text itself — errorShape only surfaces transport/
      // protocol-level detail (see log.ts). Covers both a store failure and
      // the withTimeout race firing — either way, injection did not land.
      log.warn('context_injection.failed', {
        session_id: session.id,
        generation: this.#options.generation,
        detail: errorShape(error),
      })
    } finally {
      // Settled — successfully, on failure, or on timeout. Either way READY
      // may now proceed as far as this precondition is concerned; a losing
      // store fetch keeps running in the background and is simply ignored.
      this.gate.mark('contextInjected')
      await this.maybeAnnounceReady()
    }
  }

  /** Digest of the catalogue THIS send carries — core and full differ, so a
   * log line proves which one the model was actually offered. */
  #toolsSha(): Promise<string> {
    return sha256Hex(JSON.stringify(this.#activeTools)).then((sha) => sha.slice(0, 16))
  }

  #instructionsSha(): Promise<string> {
    this.#instructionsShaPromise ??= sha256Hex(this.#options.instructions)
    return this.#instructionsShaPromise
  }

  /**
   * The ONLY place a `session.update` leaves this service. Every send is
   * logged with a sequence number and the instructions fingerprint so a later
   * overwrite — from any source — is visible in production logs, and so the
   * effective Harness identity of a real session can be proven after the
   * fact. Hash + version + length only; policy text never reaches a log line.
   */
  #sendSessionConfig(
    source: 'initial' | 'vad_fallback' | 'intake_upgrade',
    turnDetection: 'semantic_vad' | 'server_vad',
  ): void {
    const config = turnDetection === this.#options.config.turnDetection
      ? this.#options.config
      : { ...this.#options.config, turnDetection }
    this.#updateSeq += 1
    const seq = this.#updateSeq
    this.#options.socket.send(
      buildSessionUpdate({
        config,
        tools: this.#activeTools,
        instructions: this.#options.instructions,
      }),
    )
    // Logged off-path: the frame above must leave synchronously, and the log
    // line is evidence, not control flow.
    void Promise.all([this.#instructionsSha(), this.#toolsSha()]).then((
      [sha, toolsSha],
    ) =>
      log.info('session_config.sent', {
        session_id: this.#options.session.id,
        generation: this.#options.generation,
        seq,
        source,
        revision: cloudRunRevision(),
        harness_version: this.#options.config.instructionVersion,
        instructions_sha256: sha,
        instructions_chars: this.#options.instructions.length,
        model: this.#options.config.model,
        voice: this.#options.config.voice,
        tool_count: this.#activeTools.length,
        // Which rendered catalogue this session actually ran, so a session can
        // be traced to the exact env var the revision was deployed with. The
        // contract version does not move for a projection-only change, so it
        // cannot answer this on its own.
        tool_definitions_sha256: toolsSha,
        turn_detection: turnDetection,
        eagerness: turnDetection === 'semantic_vad'
          ? this.#options.config.vadEagerness
          : null,
        reasoning_effort: this.#options.config.reasoningEffort,
      })
    )
  }

  /** Re-evaluate the gate and emit READY at most once, when everything holds. */
  async maybeAnnounceReady(): Promise<void> {
    if (!this.gate.satisfied) {
      log.debug('ready.blocked', { missing: this.gate.missing.join(',') })
      return
    }
    if (!this.gate.shouldAnnounce()) return

    const readyAt = this.#options.now()
    await this.#options.lease.fencedUpdate({
      setupState: 'active',
      sidebandHealthy: true,
      authoritativeReadyAt: isoAt(readyAt),
      activeExpiresAt: new Date(
        readyAt.getTime() + this.#options.config.maxSessionSeconds * 1000,
      ).toISOString(),
    })
    await this.#options.store.updateSession(this.#options.session.id, {
      state: 'active',
      authoritativeReadyAt: isoAt(readyAt),
    })
    this.#options.notifyClient({
      type: 'ready',
      session_id: this.#options.session.id,
      generation: this.#options.generation,
    })
    log.info('ready.announced', {
      session_id: this.#options.session.id,
      generation: this.#options.generation,
    })
  }

  async handleEvent(event: Record<string, unknown>): Promise<void> {
    if (this.#stopped) return
    const type = typeof event.type === 'string' ? event.type : ''
    try {
      switch (type) {
        case 'session.updated': {
          this.#ackSeq += 1
          // The provider echoes the EFFECTIVE session state. Hashing the echoed
          // instructions proves what the session is actually running — sending
          // alone proves nothing (a rejected update is dropped whole).
          const applied = asRecord(event.session)
          const appliedInstructions = typeof applied.instructions === 'string'
            ? applied.instructions
            : null
          const appliedSha = appliedInstructions === null
            ? null
            : await sha256Hex(appliedInstructions)
          const sentSha = await this.#instructionsSha()
          const appliedTurnDetection = asRecord(
            asRecord(asRecord(applied.audio).input).turn_detection,
          )
          log.info('session_config.acked', {
            session_id: this.#options.session.id,
            generation: this.#options.generation,
            ack_seq: this.#ackSeq,
            sent_seq: this.#updateSeq,
            revision: cloudRunRevision(),
            harness_version: this.#options.config.instructionVersion,
            sent_instructions_sha256: sentSha,
            applied_instructions_sha256: appliedSha,
            applied_instructions_chars: appliedInstructions?.length ?? null,
            instructions_match: appliedSha === null ? null : appliedSha === sentSha,
            applied_model: typeof applied.model === 'string' ? applied.model : null,
            applied_tool_count: Array.isArray(applied.tools)
              ? applied.tools.length
              : null,
            applied_turn_detection: typeof appliedTurnDetection.type === 'string'
              ? appliedTurnDetection.type
              : null,
            applied_eagerness: typeof appliedTurnDetection.eagerness === 'string'
              ? appliedTurnDetection.eagerness
              : null,
          })
          this.gate.mark('configAcknowledged')
          this.#configAckResolve?.()
          this.#configAckResolve = null
          // A DIFFERENT resolver than the one above: this is only ever armed
          // by `#maybeUpgradeToolCatalogue`, well after the initial handshake
          // has already resolved (and nulled) `#configAckResolve`. Resolving
          // it unconditionally here is safe in either ordering — it is a
          // no-op when nothing is waiting.
          this.#upgradeAckResolve?.()
          this.#upgradeAckResolve = null
          await this.maybeAnnounceReady()
          return
        }
        case 'input_audio_buffer.committed':
          // A new user utterance ends any tool attribution still waiting from
          // the previous turn. If our follow-up `response.create` never
          // produced a response — the barge-in case — these names would
          // otherwise be stamped onto a later, unrelated response.
          this.#pendingFollowupToolNames = []
          this.#pendingFollowupOrigin = null
          this.#onInputCommitted(event)
          return
        case 'conversation.item.input_audio_transcription.completed':
          await this.#onInputTranscript(event, 'finalized')
          return
        case 'conversation.item.input_audio_transcription.failed':
          await this.#onInputTranscript(event, 'unavailable')
          return
        case 'response.created': {
          const responseId = String(asRecord(event.response).id ?? '')
          // Whatever we asked for has opened; there is nothing outstanding to
          // recover. Cleared unconditionally rather than by id match, because
          // a response opening at all means the provider is generating.
          this.#pendingResponseCreate = null
          this.#tracker.noteResponseCreated(responseId)
          // This new response is the "NEXT response" any queued tool names were
          // waiting for: it is the one the sideband's own `response.create`
          // (sent right after the `function_call_output`) actually produced.
          if (this.#pendingFollowupToolNames.length > 0) {
            this.#responseFollowedTool.set(responseId, [
              ...this.#pendingFollowupToolNames,
            ])
            this.#pendingFollowupToolNames = []
            this.#pendingFollowupOrigin = null
          }
          return
        }
        case 'response.output_item.added':
          this.#onOutputItemAdded(event)
          return
        case 'response.output_audio_transcript.delta':
          this.#onAssistantDelta(event)
          return
        case 'response.output_audio_transcript.done':
          this.#onAssistantTranscriptDone(event)
          return
        case 'response.output_item.done':
          await this.#serializeToolOutput(() => this.#onOutputItemDone(event))
          return
        case 'response.done':
          await this.#onResponseDone(event)
          return
        case 'error': {
          // The param + message are what turn "invalid_value" into a fix: the
          // provider names the exact rejected field. Both are provider-
          // generated strings, never user content, and the scrubber's length
          // cap still applies.
          const providerError = asRecord(event.error)
          const param = String(providerError.param ?? '')
          log.warn('sideband.provider_error', {
            code: String(providerError.code ?? 'unknown'),
            param,
            provider_message: String(providerError.message ?? '').slice(0, 120),
          })
          this.#onResponseCreateRejected(event, providerError)
          // A rejected session.update is dropped WHOLE by the provider — the
          // session is left with default VAD and NO tools/instructions, still
          // looking perfectly healthy. If the rejection names
          // `turn_detection` and this arrived before the config was ever
          // acknowledged, resend once with `server_vad` forced instead of
          // leaving the session unconfigured for the rest of the call.
          if (
            !this.gate.has('configAcknowledged') &&
            !this.#vadFallbackAttempted &&
            param.includes('turn_detection')
          ) {
            this.#vadFallbackAttempted = true
            this.#activeTurnDetection = 'server_vad'
            log.warn('sideband.vad_fallback', { rejected_param: param })
            this.#sendSessionConfig('vad_fallback', 'server_vad')
          }
          return
        }
        default:
          return
      }
    } catch (error) {
      log.error('sideband.event_failed', { event_type: type, detail: errorShape(error) })
      throw error
    }
  }

  /**
   * Recover a `response.create` the provider REFUSED.
   *
   * A refusal produces an `error` event and no response at all, so on the
   * forced-final path the caller is left in silence at the exact moment they
   * were owed an answer — and the interaction is already closed to further
   * continuations, so nothing else will ever speak for it. The `vad_fallback`
   * block below is the precedent for why this matters: a silently dropped
   * frame is indistinguishable from a healthy session.
   *
   * Three outcomes, in order of how much they matter:
   *
   *   * `conversation_already_has_active_response` — NOT silence. A response
   *     is already in flight (an ordinary barge-in outcome), and it will
   *     speak. Drop the pending frame and do nothing.
   *   * a rejected FORCED FINAL — retry ONCE with a bare `response.create`.
   *     `tool_choice: 'none'` is a per-response override this service has not
   *     proven against the live endpoint, so it is the most likely thing to be
   *     rejected here, and answering without it is far better than not
   *     answering. Bounded by `#finalFallbackInteractions`, and the tracker's
   *     sticky `finalForced` still refuses every continuation after it, so the
   *     retry cannot start a chain even if the model calls a tool in it.
   *   * anything else — tell the CLIENT. Dead air with no explanation is the
   *     one outcome worth spending a user-visible error on.
   */
  #onResponseCreateRejected(
    event: Record<string, unknown>,
    providerError: Record<string, unknown>,
  ): void {
    const pending = this.#pendingResponseCreate
    if (!pending) return
    // The provider echoes the offending frame's `event_id`. When it is absent
    // (or the error is unattributed) the outstanding frame is still the only
    // response we are waiting on, so treat it as the subject rather than
    // leaving a real silence unrecovered.
    const echoed = String(providerError.event_id ?? event.event_id ?? '')
    if (echoed !== '' && echoed !== pending.eventId) return
    this.#pendingResponseCreate = null

    const code = String(providerError.code ?? '')
    if (code === 'conversation_already_has_active_response') return

    if (
      pending.forcedFinal && !this.#finalFallbackInteractions.has(pending.interactionId)
    ) {
      this.#finalFallbackInteractions.add(pending.interactionId)
      log.warn('sideband.final_response_fallback', {
        session_id: this.#options.session.id,
        generation: this.#options.generation,
        interaction_id: pending.interactionId,
        rejected_code: code === '' ? 'unknown' : code,
      })
      this.#sendResponseCreate(pending.interactionId, false)
      return
    }

    log.error('sideband.response_create_rejected', {
      session_id: this.#options.session.id,
      generation: this.#options.generation,
      interaction_id: pending.interactionId,
      forced_final: pending.forcedFinal,
      rejected_code: code === '' ? 'unknown' : code,
    })
    this.#options.notifyClient({ type: 'error', code: 'response_create_rejected' })
  }

  /**
   * The ONLY place a `response.create` leaves this service. Stamping an
   * `event_id` is what makes a later rejection attributable — see
   * `#onResponseCreateRejected`.
   */
  #sendResponseCreate(interactionId: string, forcedFinal: boolean): void {
    const eventId = newId('rc')
    this.#pendingResponseCreate = { eventId, interactionId, forcedFinal }
    this.#options.socket.send({
      type: 'response.create',
      event_id: eventId,
      // `tool_choice: 'none'` is the whole mechanism behind the forced final:
      // the provider may not emit a function call in that response, so it
      // cannot produce another `function_call_output`, so it cannot produce
      // another continuation.
      ...(forcedFinal ? { response: { tool_choice: 'none' } } : {}),
    })
  }

  #onInputCommitted(event: Record<string, unknown>): void {
    const itemId = typeof event.item_id === 'string' ? event.item_id : null
    if (!itemId) return
    const interactionId = this.#tracker.noteInputCommitted(itemId)
    log.debug('interaction.opened', {
      session_id: this.#options.session.id,
      interaction_id: interactionId,
    })
  }

  async #onInputTranscript(
    event: Record<string, unknown>,
    status: 'finalized' | 'unavailable',
  ): Promise<void> {
    const itemId = typeof event.item_id === 'string' ? event.item_id : null
    if (!itemId) return
    // Transcription that never arrived is recorded as `unavailable` with empty
    // content. Substituting a guess here would put words in the user's mouth in
    // the durable record and in every later summary built from it.
    const text = status === 'finalized' && typeof event.transcript === 'string'
      ? event.transcript
      : ''
    const turnId = await this.#persistTurn({
      direction: 'inbound',
      text,
      completionStatus: status,
      providerItemId: itemId,
    })
    const interactionId = `item:${itemId}`
    // Tools that already ran under this interaction get their turn link now —
    // on the CLAIM, because the evidence rows are immutable.
    await this.#coordinator.backfillInboundTurn(interactionId, turnId)
  }

  #onOutputItemAdded(event: Record<string, unknown>): void {
    const item = asRecord(event.item)
    const responseId = String(event.response_id ?? '')
    const itemId = typeof item.id === 'string' ? item.id : null
    if (item.type === 'function_call') {
      this.#responseProducedTool.add(responseId)
      return
    }
    // A single response can carry BOTH audio and a tool call, so an assistant
    // item is tracked regardless of what else the response contains.
    if (itemId) {
      this.#assistantItems.set(itemId, { responseId, text: '', completed: false })
    }
  }

  #onAssistantDelta(event: Record<string, unknown>): void {
    const itemId = typeof event.item_id === 'string' ? event.item_id : null
    const delta = typeof event.delta === 'string' ? event.delta : ''
    if (!itemId || delta === '') return
    const pending = this.#assistantItems.get(itemId) ??
      { responseId: String(event.response_id ?? ''), text: '', completed: false }
    pending.text += delta
    this.#assistantItems.set(itemId, pending)
    // Deltas are accumulated in memory only. They are never written: a partial
    // transcript persisted mid-stream becomes a durable turn the user never
    // finished saying.
  }

  #onAssistantTranscriptDone(event: Record<string, unknown>): void {
    const itemId = typeof event.item_id === 'string' ? event.item_id : null
    if (!itemId) return
    const pending = this.#assistantItems.get(itemId)
    const text = typeof event.transcript === 'string'
      ? event.transcript
      : pending?.text ?? ''
    this.#assistantItems.set(itemId, {
      responseId: pending?.responseId ?? String(event.response_id ?? ''),
      text,
      completed: true,
    })
  }

  /**
   * Runs `work` after every previously queued tool-output handler has
   * finished. A throw is absorbed into the returned promise only — the chain
   * itself is always left resolved, so one failing tool cannot wedge every
   * later tool call on the session.
   */
  #serializeToolOutput(work: () => Promise<void>): Promise<void> {
    const queued = this.#toolOutputChain.then(work)
    this.#toolOutputChain = queued.catch(() => {})
    return queued
  }

  async #onOutputItemDone(event: Record<string, unknown>): Promise<void> {
    const item = asRecord(event.item)
    if (item.type !== 'function_call') return

    const responseId = String(event.response_id ?? '')
    const callId = typeof item.call_id === 'string' ? item.call_id : null
    const name = typeof item.name === 'string' ? item.name : null
    if (!callId || !name) return

    let args: unknown = {}
    if (typeof item.arguments === 'string' && item.arguments.trim() !== '') {
      try {
        args = JSON.parse(item.arguments)
      } catch {
        args = {}
      }
    }

    const result = await this.#coordinator.handleToolCall({
      responseId,
      toolCallId: callId,
      toolName: name,
      args,
    })

    // The model is always answered. An unanswered function call leaves the
    // response chain open and the user hearing silence.
    this.#options.socket.send({
      type: 'conversation.item.create',
      item: {
        type: 'function_call_output',
        call_id: callId,
        output: JSON.stringify(result.output),
      },
    })
    // NOT LIVE. The output above still goes out — an unanswered function call
    // wedges the provider's chain whoever owns the session — but a worker that
    // has lost its fence, its lease or its generation must not DRIVE the
    // conversation. Another worker owns these consequences now, and two
    // workers issuing `response.create` on one call is two assistants talking
    // over each other.
    if (result.disposition === 'rejected_not_live') {
      log.warn('sideband.continuation_skipped_not_live', {
        session_id: this.#options.session.id,
        generation: this.#options.generation,
        interaction_id: result.interactionId,
        tool_name: name,
      })
      return
    }

    // THE TERMINATION DECISION. Before this existed, every tool answer — a
    // success, a scope denial, an unknown tool, a duplicate, and above all a
    // `tool_limit_reached` — was followed by an unconditional
    // `response.create`. A model that answered each rejection by calling the
    // same tool again produced `tool -> reject -> response.create -> tool ->
    // reject -> ...` with no bound anywhere in this service: the interaction
    // tool BUDGET stopped the tools from executing but not the responses from
    // being generated, so the user heard the same sentence over and over and
    // the only thing that ever ended it was the model losing interest.
    //
    // `tool_limit_reached` force-finalizes because another tool-calling
    // response is provably useless: the budget it would need is already spent,
    // so the next call is rejected identically. Everything else is bounded by
    // the continuation cap, whose last grant is a `tool_choice: 'none'`
    // response the provider cannot answer with a tool call.
    const continuation = this.#tracker.tryConsumeContinuation(result.interactionId, {
      forceFinal: result.disposition === 'rejected_tool_limit',
    })
    if (continuation === 'suppress') {
      log.warn('sideband.continuation_suppressed', {
        session_id: this.#options.session.id,
        generation: this.#options.generation,
        interaction_id: result.interactionId,
        tool_name: name,
        disposition: result.disposition,
        continuations: this.#tracker.continuationsUsed(result.interactionId),
        limit: this.#tracker.continuationLimit,
      })
      return
    }

    // Armed only now, alongside the queued tool name and for the same reason:
    // both describe a continuation that is actually going to be sent. Arming
    // it before the disposition checks above left `#expectedContinuationId`
    // pointing at a chain this worker had already decided not to continue.
    this.#tracker.noteToolOutputSubmitted(result.interactionId)

    // Queue the name so whichever response this response.create produces next
    // can be flagged `followed_tool_call` — see `#responseFollowedTool` and the
    // `response.created` handler above. Queued only once the continuation is
    // certain to be SENT: pushing it on a suppressed path would leave the name
    // waiting to be misattributed to whatever unrelated response the provider
    // opens next, on a later user turn.
    // Names accumulate per ORIGINATING response: two function calls in one
    // response share a single follow-up and must share a single telemetry row.
    // A push from a different origin means the previous origin's follow-up
    // never materialised, so its names are dropped rather than carried over.
    if (this.#pendingFollowupOrigin !== responseId) {
      this.#pendingFollowupOrigin = responseId
      this.#pendingFollowupToolNames = []
    }
    this.#pendingFollowupToolNames.push(name)

    // MUST run before `response.create` below: if this call just upgraded the
    // catalogue, the model's next response has to be generated with the full
    // tool set already applied, or it answers the user's data-entry request
    // with the same tools it started the call with.
    await this.#maybeUpgradeToolCatalogue(name)

    if (continuation === 'final') {
      log.info('sideband.continuation_final', {
        session_id: this.#options.session.id,
        generation: this.#options.generation,
        interaction_id: result.interactionId,
        tool_name: name,
        disposition: result.disposition,
        continuations: this.#tracker.continuationsUsed(result.interactionId),
        limit: this.#tracker.continuationLimit,
      })
      this.#sendResponseCreate(result.interactionId, true)
      return
    }

    this.#sendResponseCreate(result.interactionId, false)
  }

  /**
   * One-shot, one-way transition: the model ATTEMPTING `propose_intake`
   * upgrades this session from the core catalogue to the full one for the
   * rest of its lifetime. See `INTAKE_STAGED_TOOL_NAMES` in session_config.ts
   * for why gating on this one tool is safe — every staged tool needs an id
   * only `propose_intake` (or something downstream of it) can produce in this
   * session, and the realtime instructions are STATIC, so no id can ever
   * arrive from injected server context either. No tool other than
   * `propose_intake` can therefore serve as this gate: it is the only one
   * whose call is itself the model's signal of data-entry intent, before any
   * id exists at all.
   *
   * GATED ON THE ATTEMPT, NOT THE RESULT — deliberately, not an oversight.
   * `result.ok` would be the tighter check, but as of this writing
   * `propose_intake` returns `{ok: false, code: 'turn_context_required'}` on
   * EVERY realtime call: the broker's call into `executeAgentTool` omits
   * `conversationTurnId`/`conversationTurnIndex` on purpose (realtime
   * evidence may never get a finalized transcript to link — see
   * `pip-realtime-tool-broker/index.ts`), and `agent_intake_tools.ts`'s
   * `requiredTurn()` refuses without one. That is a pre-existing, separate
   * bug in the intake pipeline (NOT fixed here — it needs its own design and
   * review), but this gate must not be built on top of it: a success-gated
   * upgrade would never fire while that bug stands, silently making voice
   * intake permanently unreachable even after the bug is fixed elsewhere and
   * this session's tools were never re-derived. Gating on the attempt is also
   * simply more robust on its own terms — a scope denial, a state conflict,
   * or a store hiccup on `propose_intake` is not a reason to strand a user
   * who has already signalled data-entry intent without the tools to act on
   * it. The failure mode of upgrading too eagerly is bounded and harmless:
   * one session pays today's full-catalogue token cost early; no capability
   * is gained or lost, and no other session is affected.
   *
   * NEVER downgrades: `#toolsUpgraded` is only ever set, never cleared, so a
   * later `propose_intake` attempt — successful or not — cannot un-advertise
   * the intake tools out from under an intake already in progress.
   */
  async #maybeUpgradeToolCatalogue(toolName: string): Promise<void> {
    if (this.#toolsUpgraded || toolName !== 'propose_intake') return
    // A provider that REJECTS a session.update drops it WHOLE, so an un-acked
    // upgrade may mean the session is still running the core catalogue.
    // Treating the send itself as durably done would strand it there for the
    // rest of the call with no retry and no way to tell from the logs, so
    // `#toolsUpgraded` is set only once an ack is actually observed (below).
    // The attempt counter is what stops that from becoming an unbounded
    // resend loop.
    if (this.#upgradeAttempts >= MAX_INTAKE_UPGRADE_ATTEMPTS) return
    this.#upgradeAttempts += 1

    this.#activeTools = this.#fullTools

    const acknowledged = new Promise<void>((resolve) => {
      this.#upgradeAckResolve = resolve
    })
    this.#sendSessionConfig('intake_upgrade', this.#activeTurnDetection)
    try {
      await withTimeout(
        acknowledged,
        this.#options.intakeUpgradeAckTimeoutMs ?? INTAKE_UPGRADE_ACK_TIMEOUT_MS,
        'intake_upgrade_ack_timeout',
      )
      this.#toolsUpgraded = true
    } catch {
      // The upgrade was already sent — the provider almost certainly still
      // applies it even without a prompt ack. What must never happen is this
      // call hanging on a slow or lost ack: a live user is mid-turn, and
      // `response.create` below is what lets the assistant answer them at
      // all. 2s is a few multiples of CONTEXT_INJECTION_TIMEOUT_MS's 500ms —
      // long enough to absorb ordinary jitter on a channel that just proved
      // itself live (the initial config ack already landed to reach this code
      // path), short enough that it cannot itself become the dead air.
      log.warn('sideband.intake_upgrade_ack_timeout', {
        session_id: this.#options.session.id,
        generation: this.#options.generation,
        attempt: this.#upgradeAttempts,
        max_attempts: MAX_INTAKE_UPGRADE_ATTEMPTS,
        // Distinguishes "the ack was merely slow" from "the update was
        // rejected and this session is STILL on the core catalogue". Without
        // it the two are indistinguishable in production logs, and only the
        // second one is a problem.
        catalogue_unconfirmed: true,
        retry_available: this.#upgradeAttempts < MAX_INTAKE_UPGRADE_ATTEMPTS,
      })
    } finally {
      this.#upgradeAckResolve = null
    }
  }

  async #onResponseDone(event: Record<string, unknown>): Promise<void> {
    const response = asRecord(event.response)
    const responseId = String(response.id ?? '')
    const status = typeof response.status === 'string' ? response.status : 'completed'
    const producedTool = this.#responseProducedTool.has(responseId)
    this.#tracker.noteResponseDone(responseId, producedTool)
    this.#responseProducedTool.delete(responseId)

    // Consumed here, not peeked: this response's own `response.done` is the
    // only place this attribution is ever read, so it must never survive to
    // be (mis)applied to a later, unrelated response id.
    const followedToolNames = this.#responseFollowedTool.get(responseId)
    this.#responseFollowedTool.delete(responseId)

    // Barge-in cancels a response mid-sentence. Only the text the assistant
    // actually produced is stored, flagged `interrupted` — never the text it was
    // going to say.
    const completionStatus: CompletionStatus =
      status === 'cancelled' || status === 'incomplete'
        ? 'interrupted'
        : status === 'failed'
        ? 'failed'
        : 'finalized'

    for (const [itemId, pending] of [...this.#assistantItems]) {
      if (pending.responseId !== responseId) continue
      this.#assistantItems.delete(itemId)
      if (pending.text.trim() === '' && completionStatus !== 'finalized') continue
      await this.#persistTurn({
        direction: 'outbound',
        text: pending.text,
        completionStatus: pending.completed ? completionStatus : 'interrupted',
        providerItemId: itemId,
      })
    }

    await this.#persistResponseUsage(
      response,
      followedToolNames !== undefined,
      followedToolNames ?? [],
    )
  }

  /**
   * Parse and persist `response.usage` off a `response.done` event. Telemetry
   * only: this must never be allowed to break the call, so every failure —
   * store outage, malformed row, anything — is caught, logged content-free
   * (never the token counts themselves, which is fine per log.ts, but never
   * anything shaped like the error's own message body) and swallowed. The
   * catch never throws, retries, or awaits anything new that could hang — a
   * live call must never notice its telemetry sink is broken.
   *
   * Escalated to `error` (was `warn`): a production incident showed 100% of
   * these silently failing for days with nothing louder than a `warn` line to
   * surface it. The FIRST failure this session instance sees logs a distinct
   * `response_usage.persist_failed_first` line so a broken store is loud
   * immediately; every failure after that (same session, same broken store)
   * keeps logging the quieter `response_usage.failed` so a long call cannot
   * spam logs with the same fact once per response.
   */
  async #persistResponseUsage(
    response: Record<string, unknown>,
    followedToolCall: boolean,
    toolNames: readonly string[],
  ): Promise<void> {
    const usage = parseResponseUsage(response)
    if (!usage) return
    const { session, config } = this.#options
    this.#responseUsageAttempts += 1
    try {
      await this.#options.store.insertResponseUsage({
        sessionId: session.id,
        responseId: usage.responseId,
        // Attribution the provider does not give us: the tracker already
        // resolved this response to its interaction when `response.created`
        // arrived, so this is a lookup, not a guess. PURE lookup —
        // `lookupInteractionForResponse`, not `interactionForResponse` — so a
        // telemetry read can never mint an interaction or otherwise mutate
        // budget-tracking state. Null (not invented) when the tracker never
        // saw a `response.created` for this response id; see
        // `ResponseUsageInsert.interactionId` in store.ts.
        interactionId: this.#tracker.lookupInteractionForResponse(usage.responseId),
        generation: this.#options.generation,
        model: config.model,
        status: usage.status,
        totalTokens: usage.totalTokens,
        inputTokens: usage.inputTokens,
        cachedInputTokens: usage.cachedInputTokens,
        uncachedInputTokens: usage.uncachedInputTokens,
        inputTextTokens: usage.inputTextTokens,
        inputAudioTokens: usage.inputAudioTokens,
        inputImageTokens: usage.inputImageTokens,
        cachedTextTokens: usage.cachedTextTokens,
        cachedAudioTokens: usage.cachedAudioTokens,
        outputTokens: usage.outputTokens,
        outputTextTokens: usage.outputTextTokens,
        outputAudioTokens: usage.outputAudioTokens,
        followedToolCall,
        toolNames,
        ownerProfileId: session.ownerProfileId,
        tenantId: session.tenantId,
      })
    } catch (error) {
      this.#responseUsageFailures += 1
      if (!this.#responseUsageFirstFailureLogged) {
        this.#responseUsageFirstFailureLogged = true
        log.error('response_usage.persist_failed_first', {
          session_id: session.id,
          detail: errorShape(error),
        })
      } else {
        log.error('response_usage.failed', {
          session_id: session.id,
          detail: errorShape(error),
        })
      }
    }
  }

  async #persistTurn(input: {
    direction: TurnDirection
    text: string
    completionStatus: CompletionStatus
    providerItemId: string
  }): Promise<string> {
    const { session, config } = this.#options
    // Realtime always passes a NULL turn_index override. Barge-in breaks the
    // 1:1 inbound/outbound pairing the text channels rely on, so indexes are
    // allocated independently in each direction.
    const slot = await this.#options.store.allocateTurnSlot({
      conversationId: session.conversationId,
      contextEpoch: session.contextEpoch,
      direction: input.direction,
      turnIndexOverride: null,
    })
    const now = this.#options.now()
    const turnId = newId('rtturn')
    await this.#options.store.insertTurn({
      id: turnId,
      conversationId: session.conversationId,
      contextEpoch: session.contextEpoch,
      direction: input.direction,
      conversationSeq: slot.conversationSeq,
      turnIndex: slot.turnIndex,
      text: input.text,
      language: detectLanguage(input.text),
      sourceChannel: 'realtime_voice',
      completionStatus: input.completionStatus,
      realtimeSessionId: session.id,
      realtimeGeneration: this.#options.generation,
      providerItemId: input.providerItemId,
      authorizationFingerprint: session.authorizationFingerprint,
      customerId: null,
      model: input.direction === 'outbound' ? config.model : null,
      createdAt: isoAt(now),
      finalizedAt: input.completionStatus === 'finalized' ? isoAt(now) : null,
      interruptedAt: input.completionStatus === 'interrupted' ? isoAt(now) : null,
    })
    log.debug('turn.persisted', {
      session_id: session.id,
      direction: input.direction,
      conversation_seq: slot.conversationSeq,
      completion_status: input.completionStatus,
    })
    // Best-effort, never fatal: the turn is already durably stored above.
    // Nothing about this call carries turn text — only a timestamp.
    try {
      await this.#options.store.touchConversation(session.conversationId, isoAt(now))
    } catch (error) {
      log.warn('conversation.touch_failed', {
        session_id: session.id,
        detail: errorShape(error),
      })
    }
    return turnId
  }

  /** Stop processing. Used on fence loss and on drain. */
  stop(reason: string): void {
    if (this.#stopped) return
    this.#stopped = true
    log.info('sideband.stopped', { session_id: this.#options.session.id, reason })
    // Terminal escalation: every `insertResponseUsage` this session ever
    // attempted failed. One line, not one per response — the per-failure
    // logging above already covers the individual failures; this is the
    // "the whole call produced zero usable telemetry" fact, which is only
    // knowable once no more response.done events are coming.
    if (
      this.#responseUsageAttempts > 0 &&
      this.#responseUsageFailures === this.#responseUsageAttempts
    ) {
      log.error('response_usage.all_failed', {
        session_id: this.#options.session.id,
        attempts: this.#responseUsageAttempts,
      })
    }
  }
}
