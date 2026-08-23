// iot-gateway -- the device-facing API for ChickMark IoT hubs.
//
// DEPLOYMENT NOTE: deploy with `--no-verify-jwt`. There is no Supabase
// credential on an ESP32, so the platform's JWT gate would reject every device
// request. Authentication is the device bearer token checked in `authenticate()`
// below, backed by a per-hub secret. Nothing here trusts a header for identity.
//
// No CORS headers: this function is called by hardware, never by a browser. The
// ChickMark app talks to the database directly through PostgREST and the
// iot_claim_hub RPC, not through this function.
//
// Contract: docs/IOT_API_CONTRACT.md section 12.

import { fail, ok } from './errors.ts'
import { isPlainObject, nowSeconds, sha256Hex } from './util.ts'
import { type Db, LIMITS } from './types.ts'
import {
  type AuthContext,
  handleCommandAck,
  handleConfig,
  handleEvents,
  handleFirmwareCheck,
  handleFirmwareStatus,
  handleHeartbeat,
  handleListCommands,
  handleProvision,
  handleTelemetry,
  handleToken,
  handleTopology,
  type HandlerDeps,
} from './handlers.ts'
import { createServiceClient, createSupabaseDb } from './db_supabase.ts'

// ---------------------------------------------------------------------------
// Rate limiting
//
// Best-effort, per isolate. Edge Functions run several instances, so the real
// ceiling is this limit times the instance count. It is a runaway-device brake,
// not a security control -- authentication is what keeps strangers out. A hub on
// its documented cadence uses about 2 requests a minute, so these are loose
// enough never to bite a healthy device.
// ---------------------------------------------------------------------------

interface Bucket {
  count: number
  resetAt: number
}
const buckets = new Map<string, Bucket>()

function rateLimit(key: string, limit: number, windowSeconds: number): number | null {
  const now = nowSeconds()
  const bucket = buckets.get(key)
  if (!bucket || bucket.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + windowSeconds })
    if (buckets.size > 10_000) {
      for (const [k, v] of buckets) if (v.resetAt <= now) buckets.delete(k)
    }
    return null
  }
  bucket.count++
  if (bucket.count > limit) return Math.max(1, bucket.resetAt - now)
  return null
}

// ---------------------------------------------------------------------------
// Request plumbing
// ---------------------------------------------------------------------------

function readBearer(request: Request): string | null {
  const header = request.headers.get('Authorization') ?? request.headers.get('authorization')
  if (!header) return null
  const match = /^Bearer\s+(.+)$/i.exec(header.trim())
  const token = match?.[1]?.trim()
  if (!token || token.length > LIMITS.maxTokenChars) return null
  return token
}

/** Maps the deployed path onto the contract path. Supabase serves this function
 *  at /functions/v1/iot-gateway, and local `supabase functions serve` at
 *  /iot-gateway, so anchor on the LAST /v1/ segment rather than a fixed prefix. */
export function routePath(pathname: string): string {
  const idx = pathname.lastIndexOf('/v1/')
  return idx >= 0 ? pathname.slice(idx) : pathname
}

type BodyResult = { ok: true; value: unknown } | { ok: false; response: Response }

async function readJsonBody(request: Request): Promise<BodyResult> {
  const declared = Number.parseInt(request.headers.get('content-length') ?? '', 10)
  if (Number.isFinite(declared) && declared > LIMITS.maxBodyBytes) {
    return {
      ok: false,
      response: fail(413, 'PAYLOAD_TOO_LARGE', `Body exceeds ${LIMITS.maxBodyBytes} bytes.`),
    }
  }
  let raw: string
  try {
    raw = await request.text()
  } catch {
    return { ok: false, response: fail(400, 'BAD_REQUEST', 'Body could not be read.') }
  }
  // Content-Length can lie or be absent under chunked transfer, so check again
  // against what actually arrived.
  if (new TextEncoder().encode(raw).length > LIMITS.maxBodyBytes) {
    return {
      ok: false,
      response: fail(413, 'PAYLOAD_TOO_LARGE', `Body exceeds ${LIMITS.maxBodyBytes} bytes.`),
    }
  }
  if (!raw.trim()) return { ok: true, value: {} }
  try {
    return { ok: true, value: JSON.parse(raw) }
  } catch {
    return { ok: false, response: fail(400, 'BAD_REQUEST', 'Body is not valid JSON.') }
  }
}

export interface GatewayDeps extends HandlerDeps {
  db: Db
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

export async function handleGatewayRequest(
  request: Request,
  deps: GatewayDeps,
): Promise<Response> {
  const url = new URL(request.url)
  const path = routePath(url.pathname)
  const method = request.method.toUpperCase()

  if (path === '/v1/health') {
    return ok({ status: 'ok', service: 'iot-gateway', contract_version: 'v1' })
  }

  // --- unauthenticated: the two bootstrap endpoints ------------------------
  if (path === '/v1/provision' || path === '/v1/auth/token') {
    // 405, not 400: the contract tells firmware to DROP the payload on a 400,
    // so a misrouted or proxy-mangled request must not look like a bad payload.
    if (method !== 'POST') return fail(405, 'METHOD_NOT_ALLOWED', 'Use POST.')
    const body = await readJsonBody(request)
    if (!body.ok) return body.response

    // Keyed on the identity being attacked (the serial or hub id in the body),
    // falling back to the header. The header is caller-controlled and explicitly
    // not a credential, so keying on it alone would let an attacker sidestep the
    // limit just by varying it.
    const claimed = isPlainObject(body.value)
      ? (typeof body.value.hub_serial === 'string'
        ? body.value.hub_serial
        : typeof body.value.hub_id === 'string'
        ? body.value.hub_id
        : null)
      : null
    const who = (claimed ?? request.headers.get('X-Device-Serial') ?? 'unknown').slice(0, 64)
    const retryAfter = rateLimit(`boot:${path}:${who}`, 30, 600)
    if (retryAfter !== null) {
      return fail(429, 'RATE_LIMITED', 'Too many bootstrap attempts.', retryAfter)
    }

    return path === '/v1/provision'
      ? await handleProvision(body.value, deps)
      : await handleToken(body.value, deps)
  }

  // --- everything else needs a device token --------------------------------
  const token = readBearer(request)
  if (!token) {
    return fail(401, 'DEVICE_UNAUTHORIZED', 'A device bearer token is required.')
  }
  const context = await deps.db.resolveToken(await sha256Hex(token))
  if (!context) {
    return fail(401, 'DEVICE_UNAUTHORIZED', 'Device token is expired or unknown.')
  }
  if (context.hub.status === 'revoked') {
    // Firmware must NOT wipe its credentials on this. A server-side mistake
    // would otherwise brick a fleet.
    return fail(403, 'DEVICE_REVOKED', 'This hub has been revoked.')
  }
  if (context.hub.status === 'retired') {
    return fail(404, 'UNKNOWN_HUB', 'This hub is retired. Re-provision.')
  }

  const retryAfter = rateLimit(`hub:${context.hub.id}`, 240, 60)
  if (retryAfter !== null) {
    return fail(429, 'RATE_LIMITED', 'Too many requests from this hub.', retryAfter)
  }

  const ctx: AuthContext = { hub: context.hub }
  const firmwareHeader = request.headers.get('X-Device-Firmware')

  if (method === 'GET') {
    switch (path) {
      case '/v1/config':
        return await handleConfig(request, ctx, deps)
      case '/v1/commands':
        return await handleListCommands(url, ctx, deps)
      case '/v1/firmware':
        return await handleFirmwareCheck(url, ctx, deps, firmwareHeader)
      default:
        return fail(404, 'NOT_FOUND', `No such endpoint: ${path}`)
    }
  }

  if (method !== 'POST') return fail(405, 'METHOD_NOT_ALLOWED', 'Use POST.')

  const body = await readJsonBody(request)
  if (!body.ok) return body.response

  switch (path) {
    case '/v1/telemetry':
      return await handleTelemetry(body.value, ctx, deps)
    case '/v1/heartbeat':
      return await handleHeartbeat(body.value, ctx, deps)
    case '/v1/events':
      return await handleEvents(body.value, ctx, deps)
    case '/v1/topology':
      return await handleTopology(body.value, ctx, deps)
    case '/v1/commands/ack':
      return await handleCommandAck(body.value, ctx, deps)
    case '/v1/firmware/status':
      return await handleFirmwareStatus(body.value, ctx, deps)
    default:
      return fail(404, 'NOT_FOUND', `No such endpoint: ${path}`)
  }
}

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

export async function serveGateway(request: Request): Promise<Response> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceRoleKey) {
    console.error('iot-gateway: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not configured')
    return fail(503, 'SERVER_ERROR', 'The gateway is not configured.')
  }

  const baseUrl = Deno.env.get('IOT_GATEWAY_BASE_URL') ??
    `${supabaseUrl.replace(/\/$/, '')}/functions/v1/iot-gateway`

  const db = createSupabaseDb(createServiceClient(supabaseUrl, serviceRoleKey))

  try {
    return await handleGatewayRequest(request, { db, baseUrl })
  } catch (error) {
    // Log the shape of the failure, never the payload -- telemetry bodies and
    // credentials must not reach a log line.
    console.error('iot-gateway: unhandled error', {
      message: error instanceof Error ? error.message : 'unknown',
    })
    return fail(500, 'SERVER_ERROR', 'Unexpected server error.')
  }
}

if (import.meta.main) {
  Deno.serve(serveGateway)
}
