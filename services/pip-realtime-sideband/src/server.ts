// HTTP + WebSocket entry point.

import type { RealtimeConfig } from './config.ts'
import { errorShape, log } from './log.ts'
import { newId } from './ids.ts'
import type { RealtimeStore, SessionRow } from './store.ts'
import type { TokenVerifier } from './jwt.ts'
import { type AuthorizationCheck, bindConnection, parseBindFrame } from './binding.ts'
import { LeaseKeeper } from './lease.ts'
import {
  type ClientNotice,
  connectSideband,
  SidebandSession,
  type SidebandSocket,
} from './sideband.ts'
import type { RealtimeToolDefinition } from './session_config.ts'
import type { ToolLedgerOwnership } from './claims.ts'
import { ConnectionRegistry, drain, type DrainableConnection } from './drain.ts'
import { type HangupFn, makeHangup, runCleanupSweep } from './cleanup.ts'
import { verifyGoogleOidc } from './oidc.ts'

/**
 * Close codes in the private range, so a client can distinguish causes.
 * Documented, with the frames, in ../WIRE_CONTRACT.md.
 */
export const CLOSE_BIND_TIMEOUT = 4408
export const CLOSE_BIND_REJECTED = 4401
export const CLOSE_LEASE_LOST = 4409
export const CLOSE_MALFORMED = 4400
export const CLOSE_DRAINING = 4503
export const CLOSE_INTERNAL = 4500

export interface ServerDeps {
  readonly config: RealtimeConfig
  readonly store: RealtimeStore
  readonly verifier: TokenVerifier
  readonly authorize: AuthorizationCheck
  readonly tools: readonly RealtimeToolDefinition[]
  /** Executors PLUS the ledger owner for their calls. See ToolLedgerOwnership. */
  readonly ownership: ToolLedgerOwnership
  readonly now?: () => Date
  /**
   * Test seam for the provider socket. `connectSideband` (the production
   * default below) now retries internally and so is async; the union keeps
   * every existing synchronous test double valid without edits, since
   * `await` on a plain value resolves immediately.
   */
  readonly openSidebandSocket?: (
    callId: string,
    clientSecret: string | null,
  ) => SidebandSocket | Promise<SidebandSocket>
  readonly hangup?: HangupFn
  readonly instructions: string
  /** Test seam for the heartbeat timer, so tests never depend on wall-clock. */
  readonly setTimer?: (fn: () => void, ms: number) => number
  readonly clearTimer?: (handle: number) => void
}

export interface ClientSocket {
  send(data: string): void
  close(code: number, reason?: string): void
}

export class RealtimeServer {
  readonly #deps: ServerDeps
  readonly #now: () => Date
  readonly #hangup: HangupFn
  readonly registry = new ConnectionRegistry()
  readonly workerId = newId('worker')
  #draining = false

  constructor(deps: ServerDeps) {
    this.#deps = deps
    this.#now = deps.now ?? (() => new Date())
    this.#hangup = deps.hangup ?? makeHangup(deps.config)
  }

  get draining(): boolean {
    return this.#draining
  }

  async handle(request: Request): Promise<Response> {
    const url = new URL(request.url)

    if (request.method === 'GET' && url.pathname === '/healthz') {
      return new Response(this.#draining ? 'draining' : 'ok', {
        status: this.#draining ? 503 : 200,
      })
    }

    if (request.method === 'POST' && url.pathname === '/internal/cleanup') {
      return await this.#handleCleanup(request)
    }

    if (
      url.pathname === '/v1/realtime' && request.headers.get('upgrade') === 'websocket'
    ) {
      if (this.#draining) {
        return new Response('draining', { status: 503 })
      }
      // Nothing sensitive may travel in the URL: credentials arrive in the first
      // application frame, which is why there is no query-string handling here.
      const { socket, response } = Deno.upgradeWebSocket(request)
      const client = wrapClientSocket(socket)
      const connection = this.attachClient(client)
      // Frames are only useful once someone reads them, and the bind deadline
      // below assumes they are being read.
      client.onMessage((data) => void connection.handleClientMessage(data))
      client.onClose(() => void connection.close('client_socket_closed'))
      return response
    }

    return new Response('not found', { status: 404 })
  }

  async #handleCleanup(request: Request): Promise<Response> {
    const header = request.headers.get('authorization') ?? ''
    const token = header.toLowerCase().startsWith('bearer ') ? header.slice(7).trim() : ''
    const verified = await verifyGoogleOidc(token, {
      audience: this.#deps.config.cleanupAudience,
      allowedEmails: this.#deps.config.cleanupServiceAccounts,
      now: this.#now,
    })
    if (!verified.ok) {
      log.warn('cleanup.unauthorized', { reason: verified.reason })
      return new Response('unauthorized', { status: 401 })
    }

    try {
      const report = await runCleanupSweep({
        store: this.#deps.store,
        config: this.#deps.config,
        hangup: this.#hangup,
        now: this.#now,
      })
      return Response.json(report)
    } catch (error) {
      log.error('cleanup.failed', { detail: errorShape(error) })
      return new Response('cleanup_failed', { status: 500 })
    }
  }

  /**
   * Drives one client connection through: bind -> lease -> attach -> configure
   * -> READY. Exposed directly so tests can run the whole handshake with a fake
   * socket and no HTTP server.
   */
  attachClient(client: ClientSocket): ClientConnection {
    const connection = new ClientConnection({
      client,
      deps: this.#deps,
      now: this.#now,
      workerId: this.workerId,
      registry: this.registry,
      openSidebandSocket: this.#deps.openSidebandSocket ??
        ((callId, clientSecret) => connectSideband(this.#deps.config, callId, clientSecret)),
    })
    // Started HERE rather than on first frame: the failure being bounded is a
    // client that opens the socket and then says nothing at all.
    connection.startBindDeadline()
    return connection
  }

  /** SIGTERM path. Must complete inside Cloud Run's fixed 10s grace. */
  async drainNow(): Promise<
    ReturnType<typeof drain> extends Promise<infer T> ? T : never
  > {
    this.#draining = true
    return await drain({
      store: this.#deps.store,
      config: this.#deps.config,
      registry: this.registry,
      owner: this.workerId,
      now: this.#now,
    })
  }
}

function wrapClientSocket(socket: WebSocket): ClientSocket & {
  onMessage(handler: (data: string) => void): void
  onClose(handler: () => void): void
} {
  return {
    send: (data) => {
      if (socket.readyState === WebSocket.OPEN) socket.send(data)
    },
    close: (code, reason) => {
      try {
        socket.close(code, reason)
      } catch { /* already closing */ }
    },
    onMessage: (handler) =>
      socket.addEventListener('message', (event) => {
        const data = (event as MessageEvent).data
        if (typeof data === 'string') handler(data)
      }),
    onClose: (handler) => socket.addEventListener('close', () => handler()),
  }
}

export class ClientConnection implements DrainableConnection {
  readonly #client: ClientSocket
  readonly #deps: ServerDeps
  readonly #now: () => Date
  readonly #workerId: string
  readonly #registry: ConnectionRegistry
  readonly #openSidebandSocket: (
    callId: string,
    clientSecret: string | null,
  ) => SidebandSocket | Promise<SidebandSocket>
  #bound = false
  #closed = false
  /** Serializes inbound frames — see [handleClientMessage]. */
  #inbox: Promise<void> = Promise.resolve()
  #bindTimer: number | null = null
  #lease: LeaseKeeper | null = null
  #sideband: SidebandSession | null = null
  #session: SessionRow | null = null
  #generation = 0

  constructor(options: {
    client: ClientSocket
    deps: ServerDeps
    now: () => Date
    workerId: string
    registry: ConnectionRegistry
    openSidebandSocket: (
      callId: string,
      clientSecret: string | null,
    ) => SidebandSocket | Promise<SidebandSocket>
  }) {
    this.#client = options.client
    this.#deps = options.deps
    this.#now = options.now
    this.#workerId = options.workerId
    this.#registry = options.registry
    this.#openSidebandSocket = options.openSidebandSocket
  }

  get sessionId(): string {
    return this.#session?.id ?? ''
  }

  get generation(): number {
    return this.#generation
  }

  get sideband(): SidebandSession | null {
    return this.#sideband
  }

  get bound(): boolean {
    return this.#bound
  }

  /**
   * BIND DEADLINE. An upgraded socket that never sends a valid bind frame holds
   * a Cloud Run concurrency slot for its whole life, and this service runs with
   * held WebSockets and a small max-instance count — so an idle, unauthenticated
   * socket is an availability cost, not untidiness. It is closed with
   * CLOSE_BIND_TIMEOUT (4408), which the client already understands.
   *
   * Nothing has been claimed at this point: no lease, no generation, no session
   * row. The close is therefore purely local, and cannot strand durable state.
   */
  startBindDeadline(): void {
    if (this.#bound || this.#closed) return
    const setTimer = this.#deps.setTimer ??
      ((fn: () => void, ms: number) => setTimeout(fn, ms) as unknown as number)
    this.#bindTimer = setTimer(() => {
      this.#bindTimer = null
      if (this.#bound || this.#closed) return
      log.warn('client.bind_timeout', {
        seconds: this.#deps.config.bindDeadlineSeconds,
      })
      this.#fail(CLOSE_BIND_TIMEOUT, 'bind_timeout')
    }, this.#deps.config.bindDeadlineSeconds * 1000)
  }

  /**
   * Cleared the moment bind succeeds. A healthy session lives for minutes; a
   * deadline left armed would close it mid-conversation.
   */
  #clearBindDeadline(): void {
    if (this.#bindTimer === null) return
    const clearTimer = this.#deps.clearTimer ??
      ((handle: number) => clearTimeout(handle))
    clearTimer(this.#bindTimer)
    this.#bindTimer = null
  }

  notify(notice: ClientNotice): void {
    this.#client.send(JSON.stringify(notice))
  }

  /**
   * Frames are handled strictly in arrival order: the socket delivers them
   * fire-and-forget, and processing the bind frame awaits the database, so an
   * un-serialized health frame sent right behind the bind would be inspected
   * while the connection is still unbound and mistaken for a bad bind
   * (observed live as 4400 `bind_frame_required` on every call).
   */
  handleClientMessage(raw: string): Promise<void> {
    const next = this.#inbox.then(() => this.#handleFrame(raw))
    this.#inbox = next.catch(() => {})
    return next
  }

  /**
   * The FIRST application frame must be the bind frame. It is parsed and then
   * dropped — never logged, never echoed, never stored — because it carries both
   * the access token and the one-time binding token.
   */
  async #handleFrame(raw: string): Promise<void> {
    if (this.#closed) return

    if (!this.#bound) {
      const frame = parseBindFrame(raw)
      if (!frame) {
        this.#fail(CLOSE_MALFORMED, 'bind_frame_required')
        return
      }
      await this.#bind(frame)
      return
    }

    let parsed: Record<string, unknown>
    try {
      parsed = JSON.parse(raw) as Record<string, unknown>
    } catch {
      this.#fail(CLOSE_MALFORMED, 'malformed_frame')
      return
    }

    switch (parsed.type) {
      case 'health':
        await this.#onHealth(parsed)
        return
      case 'bye':
        await this.close('client_bye')
        return
      default:
        // Unknown control frames are ignored rather than fatal: a newer client
        // may send frames this revision does not know about.
        return
    }
  }

  async #bind(frame: NonNullable<ReturnType<typeof parseBindFrame>>): Promise<void> {
    const result = await bindConnection({
      frame,
      store: this.#deps.store,
      verifier: this.#deps.verifier,
      authorize: this.#deps.authorize,
      now: this.#now(),
    })
    if (!result.ok) {
      this.#fail(
        result.reason === 'malformed_frame' ? CLOSE_MALFORMED : CLOSE_BIND_REJECTED,
        result.reason,
      )
      return
    }
    // The client can drop the socket while the database work above is in
    // flight; a connection that is already closed must not claim a lease it
    // can never release.
    if (this.#closed) return

    this.#bound = true
    this.#clearBindDeadline()
    this.#session = result.session
    this.#generation = result.generation

    const lease = new LeaseKeeper({
      store: this.#deps.store,
      owner: this.#workerId,
      leaseSeconds: this.#deps.config.leaseSeconds,
      heartbeatSeconds: this.#deps.config.heartbeatSeconds,
      now: this.#now,
      setTimer: this.#deps.setTimer,
      clearTimer: this.#deps.clearTimer,
    })
    const handle = await lease.claim(result.session.id, result.generation)
    if (!handle) {
      this.#fail(CLOSE_LEASE_LOST, 'lease_unavailable')
      return
    }
    // Same race one await later: close() has already run and released nothing
    // (this.#lease was still null), so the fresh claim is ours to hand back.
    if (this.#closed) {
      await lease.release().catch(() => {})
      return
    }
    // A stale worker that later notices a fence mismatch stops dead: no reclaim,
    // no retry, and the client is told so it can start a new generation.
    lease.onLost(() => {
      this.#sideband?.stop('fence_lost')
      this.#fail(CLOSE_LEASE_LOST, 'fence_lost')
    })
    lease.startHeartbeat()
    this.#lease = lease
    this.#registry.add(this)

    const call = await this.#deps.store.loadCall(result.session.id, result.generation)
    if (!call || !call.openaiCallId) {
      this.#fail(CLOSE_BIND_REJECTED, 'call_not_registered')
      return
    }

    // The production factory (connectSideband) retries internally and is
    // therefore async; `await` on a synchronous test double's plain return
    // value resolves on the spot, so this line works for both.
    // The call's own ephemeral secret is the REQUIRED attach bearer — the
    // provider rejects the standard API key on the call-attach endpoint
    // (proven live 2026-08-17); connectSideband falls back to the standard
    // key only for legacy rows minted before the secret was persisted.
    const socket = await this.#openSidebandSocket(call.openaiCallId, call.clientSecret)
    const sideband = new SidebandSession({
      config: this.#deps.config,
      store: this.#deps.store,
      socket,
      lease,
      session: result.session,
      generation: result.generation,
      leaseOwner: this.#workerId,
      tools: this.#deps.tools,
      ownership: this.#deps.ownership,
      notifyClient: (notice) => this.notify(notice),
      now: this.#now,
      instructions: this.#deps.instructions,
      // The provider socket is this worker's ONLY authority over the call.
      // Losing it is not a degradation the session can ride out: the caller's
      // WebRTC leg to OpenAI is separate and still live, so the model keeps
      // talking while nothing here can execute a tool, persist a turn, or
      // drive a response. Fail the client so it starts a new generation,
      // rather than leaving it connected to a session that only looks alive.
      onSidebandClosed: (code) => {
        log.warn('client.sideband_lost', { code })
        this.#fail(CLOSE_INTERNAL, 'sideband_lost')
      },
    })
    this.#sideband = sideband

    // Preconditions established by this point in the handshake. WebRTC and the
    // data channel are the client's to report, and READY waits for them.
    sideband.gate.mark('bindingValid')
    sideband.gate.mark('leaseHeld')
    sideband.gate.mark('authorizationRevalidated')
    sideband.gate.mark('callRegistered')
    if (call.webrtcHealthy) sideband.gate.mark('webrtcHealthy')
    if (call.dataChannelHealthy) sideband.gate.mark('dataChannelHealthy')

    await lease.fencedUpdate({ setupState: 'sideband_connecting' })
    await sideband.attachAndConfigure()
    await sideband.maybeAnnounceReady()
  }

  async #onHealth(frame: Record<string, unknown>): Promise<void> {
    const sideband = this.#sideband
    const lease = this.#lease
    if (!sideband || !lease) return

    if (frame.webrtc === true) sideband.gate.mark('webrtcHealthy')
    if (frame.webrtc === false) sideband.gate.clear('webrtcHealthy')
    if (frame.data_channel === true) sideband.gate.mark('dataChannelHealthy')
    if (frame.data_channel === false) sideband.gate.clear('dataChannelHealthy')

    try {
      await lease.fencedUpdate({
        webrtcHealthy: sideband.gate.has('webrtcHealthy'),
        dataChannelHealthy: sideband.gate.has('dataChannelHealthy'),
      })
      await sideband.maybeAnnounceReady()
    } catch (error) {
      log.warn('client.health_update_failed', { detail: errorShape(error) })
    }
  }

  #fail(code: number, reason: string): void {
    if (this.#closed) return
    this.notify({ type: 'error', code: reason })
    void this.close(reason, code)
  }

  async close(reason: string, code = 1000): Promise<void> {
    if (this.#closed) return
    this.#closed = true
    this.#clearBindDeadline()
    this.#registry.remove(this)
    this.#sideband?.stop(reason)
    try {
      if (this.#lease?.held) {
        await this.#lease.fencedUpdate({
          setupState: 'cleanup_pending',
          endReason: reason,
          endingAt: this.#now().toISOString(),
        })
      }
    } catch (error) {
      log.warn('client.close_update_failed', { detail: errorShape(error) })
    }
    await this.#lease?.release().catch(() => {})
    this.#client.close(code, reason)
    log.info('client.closed', { session_id: this.sessionId, reason })
  }

  /** Drain path: no DB work here — the batched handoff already ran. */
  closeForDrain(): void {
    if (this.#closed) return
    this.#closed = true
    this.#clearBindDeadline()
    this.#sideband?.stop('server_drain')
    this.#lease?.stopHeartbeat()
    this.notify({ type: 'closing', reason: 'server_drain' })
    this.#client.close(CLOSE_DRAINING, 'server_drain')
  }
}
