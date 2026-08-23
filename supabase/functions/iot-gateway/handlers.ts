// Endpoint handlers for the IoT gateway.
//
// Every handler is pure with respect to I/O: it takes a parsed body, an
// authenticated context, and the `Db` port. No Deno.env, no fetch, no
// supabase-js. index.ts does the wiring; the tests pass a fake Db.
//
// Contract: docs/IOT_API_CONTRACT.md section 12.

import { fail, ok } from './errors.ts'
import {
  asBoundedInt,
  asEpochSeconds,
  asFiniteNumber,
  asShortString,
  clamp,
  isPlainObject,
  nowSeconds,
  randomHex,
  secondsToIso,
  sha256Hex,
  timingSafeEqual,
  utf8Length,
} from './util.ts'
import {
  type AckInput,
  BASE_CONFIG,
  type Db,
  type EventInput,
  type HubRow,
  LIMITS,
  SECRET_LIFETIME_SECONDS,
  type TelemetryRow,
  TIME_WINDOW,
  TOKEN_TTL_SECONDS,
  type TopologySensorInput,
} from './types.ts'

const HEX64 = /^[0-9a-f]{64}$/
const SENSOR_UID = /^[0-9A-F]{12}$/
const KEY = /^[a-z0-9_]{1,64}$/
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export interface AuthContext {
  hub: HubRow
}

export interface HandlerDeps {
  db: Db
  baseUrl: string
}

// ---------------------------------------------------------------------------
// 12.1 POST /v1/provision
// ---------------------------------------------------------------------------

export async function handleProvision(body: unknown, deps: HandlerDeps): Promise<Response> {
  if (!isPlainObject(body)) return fail(400, 'BAD_REQUEST', 'Body must be a JSON object.')

  const hubSerial = asShortString(body.hub_serial, 64)
  const factorySecret = typeof body.factory_secret === 'string' ? body.factory_secret.trim() : ''
  if (!hubSerial || !HEX64.test(factorySecret)) {
    return fail(400, 'BAD_REQUEST', 'hub_serial and a 64-character hex factory_secret are required.')
  }

  const registry = await deps.db.getRegistry(hubSerial)
  const presentedHash = await sha256Hex(factorySecret)

  // Compare against a dummy hash when the serial is unknown, so both failure
  // paths do the same work. The statuses still differ -- the contract requires
  // firmware to tell a manufacturing problem from a bad secret -- but the timing
  // does not leak which one it was.
  const expectedHash = registry?.factory_secret_hash ?? (await sha256Hex(' absent'))
  const secretMatches = timingSafeEqual(presentedHash, expectedHash)

  if (!registry) return fail(404, 'UNKNOWN_SERIAL', 'This serial is not in the factory registry.')
  if (!secretMatches) return fail(401, 'INVALID_FACTORY_SECRET', 'Factory secret does not match.')

  const hub = await deps.db.getLiveHubBySerial(hubSerial)
  if (!hub) {
    return fail(409, 'DEVICE_NOT_CLAIMED', 'This hub has not been claimed yet.', 60)
  }
  if (hub.status === 'revoked') {
    return fail(403, 'DEVICE_REVOKED', 'This hub has been revoked.')
  }

  const deviceSecret = randomHex(32)
  // Mint an ESP-NOW key ONLY on first provisioning. Re-provisioning is the
  // documented recovery path (404 UNKNOWN_HUB, or a `reprovision` command), and
  // rotating the radio key there would silently strand every already-paired
  // sleeping node with no recovery short of a physical visit to each one. The
  // device secret and the radio key rotate independently.
  const existing = await deps.db.getHubSecret(hub.id)
  const espnowPmk = existing?.espnow_pmk ?? randomHex(16)
  await deps.db.setDeviceSecret(hub.id, await sha256Hex(deviceSecret), espnowPmk)
  // Every previously issued token dies with the old secret. Re-provisioning is
  // also the recovery path for a compromised device.
  await deps.db.revokeAllTokens(hub.id)
  await deps.db.recordProvision(hub.id, asShortString(body.firmware_version, 32))

  const config = await deps.db.getResolvedConfig(hub)
  return ok({
    hub_id: hub.id,
    device_secret: deviceSecret,
    secret_expires_at: nowSeconds() + SECRET_LIFETIME_SECONDS,
    espnow_pmk_rotated: existing?.espnow_pmk == null,
    config_version: config.version,
    heartbeat_interval_s: config.doc.heartbeat_interval_s ?? BASE_CONFIG.heartbeat_interval_s,
    telemetry_interval_s: config.doc.telemetry_interval_s ?? BASE_CONFIG.telemetry_interval_s,
  })
}

// ---------------------------------------------------------------------------
// 12.2 POST /v1/auth/token
// ---------------------------------------------------------------------------

export async function handleToken(body: unknown, deps: HandlerDeps): Promise<Response> {
  if (!isPlainObject(body)) return fail(400, 'BAD_REQUEST', 'Body must be a JSON object.')

  const hubId = asShortString(body.hub_id, 64)
  const deviceSecret = typeof body.device_secret === 'string' ? body.device_secret.trim() : ''
  if (!hubId || !UUID.test(hubId) || !HEX64.test(deviceSecret)) {
    return fail(400, 'BAD_REQUEST', 'hub_id and a 64-character hex device_secret are required.')
  }

  const hub = await deps.db.getHubById(hubId)
  if (!hub || hub.status === 'retired') {
    return fail(404, 'UNKNOWN_HUB', 'No such hub. Re-provision.')
  }
  if (hub.status === 'revoked') {
    return fail(403, 'DEVICE_REVOKED', 'This hub has been revoked.')
  }

  const secret = await deps.db.getHubSecret(hub.id)
  if (!secret?.device_secret_hash) {
    return fail(409, 'SECRET_ROTATION_REQUIRED', 'No device secret on file. Call /v1/provision.')
  }
  if (!timingSafeEqual(await sha256Hex(deviceSecret), secret.device_secret_hash)) {
    return fail(401, 'INVALID_DEVICE_SECRET', 'Device secret does not match.')
  }

  const token = `v1.${randomHex(32)}`
  const expiresAt = nowSeconds() + TOKEN_TTL_SECONDS
  await deps.db.issueToken(await sha256Hex(token), hub.id, secondsToIso(expiresAt))

  // rotate_secret is a hint, not an emergency: either an operator asked for it,
  // or the secret has passed its 180-day cadence. Without the age check the flag
  // could never become true on its own and the documented rotation would be
  // inert.
  const rotatedAt = secret.secret_rotated_at_s
  const secretIsOld = rotatedAt !== null &&
    nowSeconds() - rotatedAt > SECRET_LIFETIME_SECONDS

  return ok({
    device_token: token,
    expires_in: TOKEN_TTL_SECONDS,
    expires_at: expiresAt,
    rotate_secret: secret.rotate_requested === true || secretIsOld,
  })
}

// ---------------------------------------------------------------------------
// 12.3 POST /v1/telemetry
// ---------------------------------------------------------------------------

interface Rejection {
  index: number
  sensor_uid: string | null
  reason: string
}

export async function handleTelemetry(
  body: unknown,
  ctx: AuthContext,
  deps: HandlerDeps,
): Promise<Response> {
  if (!isPlainObject(body)) return fail(400, 'BAD_REQUEST', 'Body must be a JSON object.')

  const batchId = asShortString(body.batch_id, 128)
  const readings = body.readings
  if (!batchId || !Array.isArray(readings) || readings.length === 0) {
    return fail(400, 'BAD_REQUEST', 'batch_id and a non-empty readings array are required.')
  }
  if (readings.length > LIMITS.maxReadingsPerBatch) {
    return fail(
      413,
      'PAYLOAD_TOO_LARGE',
      `At most ${LIMITS.maxReadingsPerBatch} readings per batch. Halve the batch and retry.`,
    )
  }

  // Batch-level idempotency. A replay is a success, not an error -- the server
  // already has the data, so the device must delete it from its queue.
  const seen = await deps.db.getBatch(ctx.hub.id, batchId)
  if (seen) {
    const pending = await deps.db.countPendingCommands(ctx.hub.id, ctx.hub.customer_id)
    const cfg = await deps.db.getResolvedConfig(ctx.hub)
    return ok({
      batch_id: batchId,
      duplicate: true,
      accepted: 0,
      duplicates: seen.accepted,
      rejected: [],
      flagged: [],
      config_version: cfg.version,
      commands_pending: pending > 0,
    }, 202)
  }

  const now = nowSeconds()
  const rejected: Rejection[] = []
  const flagged: { index: number; sensor_uid: string; metric_key: string; value: number }[] = []
  const rules = new Map((await deps.db.getMetricRules()).map((r) => [r.metric_key, r]))

  interface Candidate {
    index: number
    sensorUid: string
    measuredAt: number
    metrics: Record<string, number>
    quality: 'ok' | 'suspect' | 'estimated'
    battery: number | null
    rssi: number | null
  }
  const candidates: Candidate[] = []

  // Pass 1: structural and semantic validation. No database work.
  for (let i = 0; i < readings.length; i++) {
    const r = readings[i]
    if (!isPlainObject(r)) {
      rejected.push({ index: i, sensor_uid: null, reason: 'MALFORMED_READING' })
      continue
    }
    const sensorUid = typeof r.sensor_uid === 'string' ? r.sensor_uid.trim().toUpperCase() : ''
    if (!SENSOR_UID.test(sensorUid)) {
      // Echo back whatever was sent, truncated. A null here would be useless for
      // diagnosis in exactly the case the firmware engineer needs it most.
      rejected.push({
        index: i,
        sensor_uid: sensorUid.slice(0, 32) || null,
        reason: 'UNKNOWN_SENSOR',
      })
      continue
    }
    const measuredAt = asEpochSeconds(r.measured_at)
    if (measuredAt === null) {
      rejected.push({ index: i, sensor_uid: sensorUid, reason: 'MALFORMED_READING' })
      continue
    }
    if (measuredAt > now + TIME_WINDOW.futureToleranceSeconds) {
      rejected.push({ index: i, sensor_uid: sensorUid, reason: 'FUTURE_TIMESTAMP' })
      continue
    }
    if (measuredAt < now - TIME_WINDOW.staleToleranceSeconds) {
      rejected.push({ index: i, sensor_uid: sensorUid, reason: 'STALE_TIMESTAMP' })
      continue
    }
    if (!isPlainObject(r.metrics)) {
      rejected.push({ index: i, sensor_uid: sensorUid, reason: 'NO_VALID_METRICS' })
      continue
    }

    const entries = Object.entries(r.metrics)
    if (entries.length > LIMITS.maxMetricsPerReading) {
      rejected.push({ index: i, sensor_uid: sensorUid, reason: 'MALFORMED_READING' })
      continue
    }

    const metrics: Record<string, number> = {}
    let suspect = false
    for (const [key, raw] of entries) {
      if (!KEY.test(key)) continue
      const value = asFiniteNumber(raw)
      if (value === null) continue
      metrics[key] = value
      const rule = rules.get(key)
      if (rule && rule.is_active) {
        const low = rule.min_plausible
        const high = rule.max_plausible
        if ((low !== null && value < low) || (high !== null && value > high)) {
          suspect = true
          flagged.push({ index: i, sensor_uid: sensorUid, metric_key: key, value })
        }
      }
    }
    if (Object.keys(metrics).length === 0) {
      rejected.push({ index: i, sensor_uid: sensorUid, reason: 'NO_VALID_METRICS' })
      continue
    }

    // An implausible value is stored, not dropped -- a sensor reporting nonsense
    // is itself the signal an operator needs. `suspect` outranks `estimated`.
    const quality = suspect ? 'suspect' : (r.t_est === true ? 'estimated' : 'ok')

    candidates.push({
      index: i,
      sensorUid,
      measuredAt,
      metrics,
      quality,
      battery: asBoundedInt(r.battery_percent, 0, 100),
      rssi: asBoundedInt(r.rssi, -127, 0),
    })
  }

  // Resolve sensors, auto-creating unknown ones. A sensor may report telemetry
  // before it appears in a topology snapshot; the data is kept and staff bind it
  // to a room later. Nothing is lost.
  const wantedUids = [...new Set(candidates.map((c) => c.sensorUid))]
  const known = new Map(
    (await deps.db.getSensorsByUids(ctx.hub.id, wantedUids)).map((s) => [s.sensor_uid, s]),
  )
  for (const uid of wantedUids) {
    if (!known.has(uid)) {
      known.set(uid, await deps.db.createSensor(ctx.hub.id, ctx.hub.customer_id, uid))
    }
  }

  // Deduplicate within the batch. ON CONFLICT DO UPDATE cannot touch the same
  // row twice in one statement, so a hub that repeats a (sensor, instant) inside
  // one payload would otherwise error the whole insert. Later metrics win.
  const byKey = new Map<string, TelemetryRow>()
  let intraBatchDuplicates = 0
  for (const c of candidates) {
    const sensor = known.get(c.sensorUid)
    if (!sensor) continue
    if (sensor.status === 'retired') {
      rejected.push({ index: c.index, sensor_uid: c.sensorUid, reason: 'SENSOR_NOT_ON_HUB' })
      continue
    }
    const key = `${sensor.id}|${c.measuredAt}`
    const existing = byKey.get(key)
    if (existing) {
      intraBatchDuplicates++
      existing.metrics = { ...existing.metrics, ...c.metrics }
      continue
    }
    byKey.set(key, {
      customer_id: ctx.hub.customer_id,
      hub_id: ctx.hub.id,
      sensor_id: sensor.id,
      measured_at: secondsToIso(c.measuredAt),
      batch_id: batchId,
      metrics: c.metrics,
      quality: c.quality,
      battery_percent: c.battery,
      rssi: c.rssi,
    })
  }

  const rows = [...byKey.values()]
  const accepted = rows.length > 0 ? await deps.db.insertTelemetry(rows) : 0
  await deps.db.recordBatch(ctx.hub.id, batchId, readings.length, accepted)
  if (accepted > 0) await deps.db.touchHubTelemetry(ctx.hub.id)

  const pending = await deps.db.countPendingCommands(ctx.hub.id, ctx.hub.customer_id)
  const cfg = await deps.db.getResolvedConfig(ctx.hub)

  return ok({
    batch_id: batchId,
    accepted,
    duplicates: rows.length - accepted + intraBatchDuplicates,
    rejected,
    flagged,
    config_version: cfg.version,
    commands_pending: pending > 0,
  }, 202)
}

// ---------------------------------------------------------------------------
// 12.4 POST /v1/heartbeat
// ---------------------------------------------------------------------------

const HEARTBEAT_NUMERIC_FIELDS = [
  'uptime_s',
  'boot_count',
  'free_heap_bytes',
  'min_free_heap_bytes',
  'fs_free_bytes',
  'wifi_rssi',
  'sensors_known',
  'sensors_online',
  'queue_depth',
  'queue_bytes',
  'dropped_readings_total',
  'last_upload_at',
  'config_version',
  'battery_percent',
]
const HEARTBEAT_STRING_FIELDS = [
  'reset_reason',
  'wifi_ssid',
  'ip_address',
  'power_source',
  'topology_hash',
  'firmware_version',
]

export async function handleHeartbeat(
  body: unknown,
  ctx: AuthContext,
  deps: HandlerDeps,
): Promise<Response> {
  if (!isPlainObject(body)) return fail(400, 'BAD_REQUEST', 'Body must be a JSON object.')

  // Whitelist the snapshot. A hub is a device on a farm network; it does not get
  // to write arbitrary JSON into our database.
  const snapshot: Record<string, unknown> = {}
  for (const key of HEARTBEAT_NUMERIC_FIELDS) {
    const value = asFiniteNumber(body[key])
    if (value !== null) snapshot[key] = value
  }
  for (const key of HEARTBEAT_STRING_FIELDS) {
    const value = asShortString(body[key], 128)
    if (value !== null) snapshot[key] = value
  }
  if (typeof body.last_upload_ok === 'boolean') snapshot.last_upload_ok = body.last_upload_ok
  snapshot.received_at = nowSeconds()

  await deps.db.recordHeartbeat(ctx.hub.id, asShortString(body.firmware_version, 32), snapshot)

  const commands = await deps.db.takePendingCommands(
    ctx.hub.id,
    ctx.hub.customer_id,
    LIMITS.maxCommandsPerHeartbeat,
    true,
  )
  const cfg = await deps.db.getResolvedConfig(ctx.hub)

  const reportedHash = asShortString(body.topology_hash, 64)
  const topologyStale = ctx.hub.topology_hash === null ||
    (reportedHash !== null && reportedHash !== ctx.hub.topology_hash)

  // Speed the hub up while work is queued, then let it settle back. Firmware
  // clamps this to 10..900 s and so do we.
  const configured = asFiniteNumber(cfg.doc.heartbeat_interval_s) ??
    (BASE_CONFIG.heartbeat_interval_s as number)
  const nextHeartbeat = commands.length > 0 ? 10 : clamp(Math.round(configured), 10, 900)

  return ok({
    config_version: cfg.version,
    topology_stale: topologyStale,
    next_heartbeat_s: nextHeartbeat,
    commands: commands.map((c) => ({
      command_id: c.id,
      command_type: c.command_type,
      params: c.params,
      created_at: c.created_at_s,
      expires_at: c.expires_at_s,
    })),
  })
}

// ---------------------------------------------------------------------------
// 12.5 POST /v1/commands/ack   +   12.6 GET /v1/commands
// ---------------------------------------------------------------------------

const ACK_STATUSES = new Set(['received', 'succeeded', 'failed', 'unsupported', 'expired'])

export async function handleCommandAck(
  body: unknown,
  ctx: AuthContext,
  deps: HandlerDeps,
): Promise<Response> {
  if (!isPlainObject(body) || !Array.isArray(body.acks)) {
    return fail(400, 'BAD_REQUEST', 'acks must be an array.')
  }
  if (body.acks.length > LIMITS.maxAcksPerRequest) {
    return fail(413, 'PAYLOAD_TOO_LARGE', `At most ${LIMITS.maxAcksPerRequest} acks per request.`)
  }

  const acks: AckInput[] = []
  for (const raw of body.acks) {
    if (!isPlainObject(raw)) continue
    const commandId = asShortString(raw.command_id, 64)
    const status = asShortString(raw.status, 32)
    if (!commandId || !UUID.test(commandId) || !status || !ACK_STATUSES.has(status)) continue
    acks.push({
      command_id: commandId,
      status,
      completed_at_s: asEpochSeconds(raw.completed_at),
      result: isPlainObject(raw.result) ? raw.result : null,
      error_code: asShortString(raw.error_code, 64),
      error_message: asShortString(raw.error_message, LIMITS.maxMessageChars),
    })
  }
  if (acks.length === 0) return ok({ acknowledged: 0, unknown: [] })

  const result = await deps.db.applyAcks(ctx.hub.id, ctx.hub.customer_id, acks)
  return ok({ acknowledged: result.acknowledged, unknown: result.unknown })
}

export async function handleListCommands(
  url: URL,
  ctx: AuthContext,
  deps: HandlerDeps,
): Promise<Response> {
  const requested = Number.parseInt(url.searchParams.get('limit') ?? '', 10)
  const limit = Number.isFinite(requested)
    ? clamp(requested, 1, LIMITS.maxCommandsPerHeartbeat)
    : LIMITS.maxCommandsPerHeartbeat
  // Section 12.6 promises "reading does not consume", so this must not mark
  // anything delivered. The heartbeat is the delivery path.
  const commands = await deps.db.takePendingCommands(
    ctx.hub.id,
    ctx.hub.customer_id,
    limit,
    false,
  )
  return ok({
    commands: commands.map((c) => ({
      command_id: c.id,
      command_type: c.command_type,
      params: c.params,
      created_at: c.created_at_s,
      expires_at: c.expires_at_s,
    })),
  })
}

// ---------------------------------------------------------------------------
// 12.7 POST /v1/topology
// ---------------------------------------------------------------------------

export async function handleTopology(
  body: unknown,
  ctx: AuthContext,
  deps: HandlerDeps,
): Promise<Response> {
  if (!isPlainObject(body) || !Array.isArray(body.sensors)) {
    return fail(400, 'BAD_REQUEST', 'sensors must be an array.')
  }
  if (body.sensors.length > LIMITS.maxSensorsPerTopology) {
    return fail(413, 'PAYLOAD_TOO_LARGE', `At most ${LIMITS.maxSensorsPerTopology} sensors per hub.`)
  }

  const sensors: TopologySensorInput[] = []
  const claimed = new Set<string>()
  for (const raw of body.sensors) {
    if (!isPlainObject(raw)) continue
    const uid = typeof raw.sensor_uid === 'string' ? raw.sensor_uid.trim().toUpperCase() : ''
    if (!SENSOR_UID.test(uid) || claimed.has(uid)) continue
    claimed.add(uid)
    const caps = Array.isArray(raw.capabilities)
      ? raw.capabilities.filter((c): c is string => typeof c === 'string' && KEY.test(c))
      : []
    const state = asShortString(raw.state, 16)
    sensors.push({
      sensor_uid: uid,
      model: asShortString(raw.model, 64),
      firmware_version: asShortString(raw.firmware_version, 32),
      capabilities: caps,
      state: state === 'online' || state === 'pairing' ? state : 'offline',
      battery_percent: asBoundedInt(raw.battery_percent, 0, 100),
      rssi: asBoundedInt(raw.rssi, -127, 0),
      last_seen_at_s: asEpochSeconds(raw.last_seen_at),
    })
  }

  const accepted = await deps.db.applyTopology(ctx.hub.id, ctx.hub.customer_id, sensors)

  // Only write a hash the device actually sent. Storing null would make every
  // subsequent heartbeat answer topology_stale: true, putting the hub in a
  // permanent full-snapshot loop.
  const topologyHash = asShortString(body.topology_hash, 64)
  if (topologyHash !== null) await deps.db.setTopologyHash(ctx.hub.id, topologyHash)

  const cfg = await deps.db.getResolvedConfig(ctx.hub)
  return ok({
    accepted,
    topology_hash: topologyHash ?? ctx.hub.topology_hash,
    config_version: cfg.version,
  })
}

// ---------------------------------------------------------------------------
// 12.8 GET /v1/config
// ---------------------------------------------------------------------------

export async function handleConfig(
  request: Request,
  ctx: AuthContext,
  deps: HandlerDeps,
): Promise<Response> {
  const cfg = await deps.db.getResolvedConfig(ctx.hub)
  const etag = `W/"cfg-${cfg.version}-${ctx.hub.id.slice(0, 8)}"`

  if (request.headers.get('If-None-Match') === etag) {
    return new Response(null, { status: 304, headers: { ETag: etag } })
  }

  const doc = { ...cfg.doc, base_url: deps.baseUrl }
  const body = JSON.stringify({
    config_version: cfg.version,
    etag,
    config: doc,
    server_time: nowSeconds(),
  })
  return new Response(body, {
    status: 200,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ETag: etag },
  })
}

// ---------------------------------------------------------------------------
// 12.9 POST /v1/events
// ---------------------------------------------------------------------------

const SEVERITIES = new Set(['info', 'warning', 'critical'])

export async function handleEvents(
  body: unknown,
  ctx: AuthContext,
  deps: HandlerDeps,
): Promise<Response> {
  if (!isPlainObject(body) || !Array.isArray(body.events)) {
    return fail(400, 'BAD_REQUEST', 'events must be an array.')
  }
  if (body.events.length > LIMITS.maxEventsPerBatch) {
    return fail(413, 'PAYLOAD_TOO_LARGE', `At most ${LIMITS.maxEventsPerBatch} events per batch.`)
  }

  const now = nowSeconds()
  const events: EventInput[] = []
  const rejected: { index: number; reason: string }[] = []

  for (let i = 0; i < body.events.length; i++) {
    const raw = body.events[i]
    if (!isPlainObject(raw)) {
      rejected.push({ index: i, reason: 'MALFORMED_EVENT' })
      continue
    }
    const eventId = asShortString(raw.event_id, 128)
    const eventType = asShortString(raw.event_type, LIMITS.maxKeyChars)
    const occurredAt = asEpochSeconds(raw.occurred_at)
    if (!eventId || !eventType || !KEY.test(eventType) || occurredAt === null) {
      rejected.push({ index: i, reason: 'MALFORMED_EVENT' })
      continue
    }
    const severity = asShortString(raw.severity, 16)
    let detail = isPlainObject(raw.detail) ? raw.detail : {}
    if (utf8Length(JSON.stringify(detail)) > LIMITS.maxDetailBytes) {
      detail = { truncated: true }
    }
    const uid = typeof raw.sensor_uid === 'string' ? raw.sensor_uid.trim().toUpperCase() : ''
    events.push({
      event_id: eventId,
      event_type: eventType,
      // An unrecognised severity is stored as info rather than rejected: the
      // event list is open by design.
      severity: (severity && SEVERITIES.has(severity) ? severity : 'info') as EventInput['severity'],
      occurred_at_s: clamp(occurredAt, now - TIME_WINDOW.staleToleranceSeconds, now + 300),
      sensor_uid: SENSOR_UID.test(uid) ? uid : null,
      detail,
    })
  }

  const result = events.length > 0
    ? await deps.db.insertEvents(ctx.hub.id, ctx.hub.customer_id, events)
    : { accepted: 0, duplicates: 0 }

  return ok({
    accepted: result.accepted,
    duplicates: result.duplicates,
    rejected,
  }, 202)
}

// ---------------------------------------------------------------------------
// 12.10 GET /v1/firmware   +   12.11 POST /v1/firmware/status
// ---------------------------------------------------------------------------

export async function handleFirmwareCheck(
  url: URL,
  ctx: AuthContext,
  deps: HandlerDeps,
  currentVersion: string | null,
): Promise<Response> {
  const target = url.searchParams.get('target') === 'sensor' ? 'sensor' : 'hub'
  // The channel is server-resolved config, never a device parameter: a hub must
  // not be able to opt itself into the dev channel.
  const cfg = await deps.db.getResolvedConfig(ctx.hub)
  const channel = typeof cfg.doc.ota_channel === 'string' ? cfg.doc.ota_channel : 'stable'
  const offer = await deps.db.findFirmwareOffer(ctx.hub, currentVersion, target, channel)
  if (!offer) return ok({ update_available: false })
  return ok({ update_available: true, ...offer })
}

const FIRMWARE_STATUSES = new Set([
  'downloading',
  'verifying',
  'applying',
  'succeeded',
  'failed',
  'rolled_back',
])

export async function handleFirmwareStatus(
  body: unknown,
  ctx: AuthContext,
  deps: HandlerDeps,
): Promise<Response> {
  if (!isPlainObject(body) || !Array.isArray(body.reports)) {
    return fail(400, 'BAD_REQUEST', 'reports must be an array.')
  }
  let accepted = 0
  for (const raw of body.reports.slice(0, LIMITS.maxAcksPerRequest)) {
    if (!isPlainObject(raw)) continue
    const updateId = asShortString(raw.update_id, 64)
    const status = asShortString(raw.status, 32)
    if (!updateId || !UUID.test(updateId) || !status || !FIRMWARE_STATUSES.has(status)) continue
    const done = await deps.db.recordFirmwareStatus(ctx.hub.id, ctx.hub.customer_id, {
      update_id: updateId,
      status,
      from_version: asShortString(raw.from_version, 32),
      to_version: asShortString(raw.to_version, 32),
      error_code: asShortString(raw.error_code, 64),
      error_message: asShortString(raw.error_message, LIMITS.maxMessageChars),
    })
    if (done) accepted++
  }
  return ok({ accepted })
}
