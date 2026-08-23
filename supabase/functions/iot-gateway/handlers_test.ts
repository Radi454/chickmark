import { assert, assertEquals } from '@std/assert'
import { handleGatewayRequest, routePath } from './index.ts'
import type { Db, HubRow, SensorRow, TelemetryRow } from './types.ts'
import { sha256Hex } from './util.ts'

const HUB_A: HubRow = {
  id: '0f1c9e2a-77b4-4f31-9d0e-51c4f8a1d233',
  hub_serial: 'CMH-4F2A9C01',
  customer_id: 'customer-a',
  hatchery_id: 'hatchery-a',
  hardware_model: 'chickmark-hub-v1',
  status: 'active',
  config_version: 3,
  topology_hash: '8a41c9f2',
}

const FACTORY_SECRET = 'a'.repeat(64)
const DEVICE_SECRET = 'b'.repeat(64)
const TOKEN = 'v1.' + 'c'.repeat(64)

interface FakeState {
  hub: HubRow
  registryExists: boolean
  claimed: boolean
  deviceSecretHash: string | null
  rotateRequested: boolean
  espnowPmk: string | null
  deliveredMarked: number
  topologyHashWrites: string[]
  batches: Map<string, { reading_count: number; accepted: number }>
  sensors: Map<string, SensorRow>
  inserted: TelemetryRow[]
  commands: { id: string; command_type: string; params: Record<string, unknown> }[]
  events: unknown[]
  acks: unknown[]
  topology: unknown[]
  heartbeats: Record<string, unknown>[]
  tokenValid: boolean
}

function freshState(overrides: Partial<FakeState> = {}): FakeState {
  return {
    hub: { ...HUB_A },
    registryExists: true,
    claimed: true,
    deviceSecretHash: null,
    rotateRequested: false,
    espnowPmk: null,
    deliveredMarked: 0,
    topologyHashWrites: [],
    batches: new Map(),
    sensors: new Map(),
    inserted: [],
    commands: [],
    events: [],
    acks: [],
    topology: [],
    heartbeats: [],
    tokenValid: true,
    ...overrides,
  }
}

function fakeDb(state: FakeState): Db {
  let sensorSeq = 0
  return {
    getRegistry: (serial) =>
      Promise.resolve(
        state.registryExists
          ? {
            hub_serial: serial,
            factory_secret_hash: '__set_by_test__',
            hardware_model: 'chickmark-hub-v1',
          }
          : null,
      ),
    getLiveHubBySerial: () => Promise.resolve(state.claimed ? state.hub : null),
    getHubById: (id) => Promise.resolve(id === state.hub.id ? state.hub : null),
    getHubSecret: () =>
      Promise.resolve({
        device_secret_hash: state.deviceSecretHash,
        rotate_requested: state.rotateRequested,
        espnow_pmk: state.espnowPmk,
        secret_rotated_at_s: null,
      }),
    setDeviceSecret: (_h, hash, pmk) => {
      state.deviceSecretHash = hash
      if (pmk) state.espnowPmk = pmk
      return Promise.resolve()
    },
    revokeAllTokens: () => Promise.resolve(),
    recordProvision: () => Promise.resolve(),
    issueToken: () => Promise.resolve(),
    resolveToken: () =>
      Promise.resolve(
        state.tokenValid ? { hub: state.hub, expires_at_s: 4_000_000_000 } : null,
      ),
    getBatch: (_h, batchId) => Promise.resolve(state.batches.get(batchId) ?? null),
    recordBatch: (_h, batchId, count, accepted) => {
      state.batches.set(batchId, { reading_count: count, accepted })
      return Promise.resolve()
    },
    getSensorsByUids: (_h, uids) =>
      Promise.resolve(uids.map((u) => state.sensors.get(u)).filter((s): s is SensorRow => !!s)),
    createSensor: (_h, _c, uid) => {
      const row: SensorRow = { id: `sensor-${++sensorSeq}`, sensor_uid: uid, status: 'unassigned' }
      state.sensors.set(uid, row)
      return Promise.resolve(row)
    },
    getMetricRules: () =>
      Promise.resolve([
        { metric_key: 'temperature_c', min_plausible: -40, max_plausible: 85, is_active: true },
        { metric_key: 'humidity_rh', min_plausible: 0, max_plausible: 100, is_active: true },
      ]),
    insertTelemetry: (rows) => {
      state.inserted.push(...rows)
      return Promise.resolve(rows.length)
    },
    touchHubTelemetry: () => Promise.resolve(),
    countPendingCommands: () => Promise.resolve(state.commands.length),
    recordHeartbeat: (_h, _f, snapshot) => {
      state.heartbeats.push(snapshot)
      return Promise.resolve()
    },
    takePendingCommands: (_h, _c, limit, markDelivered) => {
      if (markDelivered) state.deliveredMarked++
      return Promise.resolve(
        state.commands.slice(0, limit).map((c) => ({
          id: c.id,
          command_type: c.command_type,
          params: c.params,
          created_at_s: 1786000075,
          expires_at_s: 1786003675,
        })),
      )
    },
    applyAcks: (_h, _c, acks) => {
      state.acks.push(...acks)
      return Promise.resolve({ acknowledged: acks.length, unknown: [] })
    },
    insertEvents: (_h, _c, events) => {
      state.events.push(...events)
      return Promise.resolve({ accepted: events.length, duplicates: 0 })
    },
    applyTopology: (_h, _c, sensors) => {
      state.topology.push(...sensors)
      return Promise.resolve(sensors.length)
    },
    setTopologyHash: (_h, hash) => {
      state.topologyHashWrites.push(hash)
      return Promise.resolve()
    },
    getResolvedConfig: () =>
      Promise.resolve({
        version: 4,
        doc: { heartbeat_interval_s: 60, telemetry_interval_s: 300, espnow_pmk: 'deadbeef' },
      }),
    findFirmwareOffer: () => Promise.resolve(null),
    recordFirmwareStatus: () => Promise.resolve(true),
  }
}

function deps(state: FakeState) {
  return { db: fakeDb(state), baseUrl: 'https://example.test/functions/v1/iot-gateway' }
}

function post(path: string, body: unknown, token?: string): Request {
  return new Request(`https://example.test/iot-gateway${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Device-Serial': 'CMH-4F2A9C01',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  })
}

function get(path: string, token?: string, headers: Record<string, string> = {}): Request {
  return new Request(`https://example.test/iot-gateway${path}`, {
    method: 'GET',
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
  })
}

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

Deno.test('routePath anchors on the last /v1/ segment', () => {
  assertEquals(routePath('/functions/v1/iot-gateway/v1/telemetry'), '/v1/telemetry')
  assertEquals(routePath('/iot-gateway/v1/commands/ack'), '/v1/commands/ack')
  assertEquals(routePath('/v1/heartbeat'), '/v1/heartbeat')
  assertEquals(routePath('/iot-gateway/v1/firmware/status'), '/v1/firmware/status')
})

Deno.test('health needs no credential', async () => {
  const response = await handleGatewayRequest(get('/v1/health'), deps(freshState()))
  assertEquals(response.status, 200)
  const body = await response.json()
  assertEquals(body.status, 'ok')
  assert(typeof body.server_time === 'number')
})

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------

Deno.test('a request with no bearer token is 401 DEVICE_UNAUTHORIZED', async () => {
  const response = await handleGatewayRequest(post('/v1/heartbeat', {}), deps(freshState()))
  assertEquals(response.status, 401)
  const body = await response.json()
  assertEquals(body.error.code, 'DEVICE_UNAUTHORIZED')
  assertEquals(body.error.retryable, false)
})

Deno.test('an unknown token is 401, not 403', async () => {
  const state = freshState({ tokenValid: false })
  const response = await handleGatewayRequest(post('/v1/heartbeat', {}, TOKEN), deps(state))
  assertEquals(response.status, 401)
})

Deno.test('a revoked hub is 403 DEVICE_REVOKED on an authenticated endpoint', async () => {
  const state = freshState()
  state.hub = { ...HUB_A, status: 'revoked' }
  const response = await handleGatewayRequest(post('/v1/heartbeat', {}, TOKEN), deps(state))
  assertEquals(response.status, 403)
  assertEquals((await response.json()).error.code, 'DEVICE_REVOKED')
})

Deno.test('an unknown path under a valid token is 404', async () => {
  const response = await handleGatewayRequest(post('/v1/nope', {}, TOKEN), deps(freshState()))
  assertEquals(response.status, 404)
})

// ---------------------------------------------------------------------------
// 12.1 provision
// ---------------------------------------------------------------------------

Deno.test('provision: unknown serial is 404 UNKNOWN_SERIAL', async () => {
  const state = freshState({ registryExists: false })
  const response = await handleGatewayRequest(
    post('/v1/provision', { hub_serial: 'CMH-NOPE', factory_secret: FACTORY_SECRET }),
    deps(state),
  )
  assertEquals(response.status, 404)
  assertEquals((await response.json()).error.code, 'UNKNOWN_SERIAL')
})

Deno.test('provision: wrong factory secret is 401', async () => {
  const state = freshState()
  const d = deps(state)
  const response = await handleGatewayRequest(
    post('/v1/provision', { hub_serial: HUB_A.hub_serial, factory_secret: FACTORY_SECRET }),
    d,
  )
  assertEquals(response.status, 401)
  assertEquals((await response.json()).error.code, 'INVALID_FACTORY_SECRET')
})

Deno.test('provision: an unclaimed hub is 409 DEVICE_NOT_CLAIMED and is retryable', async () => {
  const state = freshState({ claimed: false })
  const d = deps(state)
  // Make the factory secret match so we reach the claim check.
  const realDb = d.db
  d.db = {
    ...realDb,
    getRegistry: async (serial: string) => ({
      hub_serial: serial,
      factory_secret_hash: await sha256Hex(FACTORY_SECRET),
      hardware_model: 'chickmark-hub-v1',
    }),
  }
  const response = await handleGatewayRequest(
    post('/v1/provision', { hub_serial: HUB_A.hub_serial, factory_secret: FACTORY_SECRET }),
    d,
  )
  assertEquals(response.status, 409)
  const body = await response.json()
  assertEquals(body.error.code, 'DEVICE_NOT_CLAIMED')
  assertEquals(body.error.retryable, true)
  assertEquals(body.error.retry_after_s, 60)
})

Deno.test('provision: a claimed hub gets a 64-hex device secret exactly once', async () => {
  const state = freshState()
  const d = deps(state)
  const realDb = d.db
  d.db = {
    ...realDb,
    getRegistry: async (serial: string) => ({
      hub_serial: serial,
      factory_secret_hash: await sha256Hex(FACTORY_SECRET),
      hardware_model: 'chickmark-hub-v1',
    }),
  }
  const response = await handleGatewayRequest(
    post('/v1/provision', { hub_serial: HUB_A.hub_serial, factory_secret: FACTORY_SECRET }),
    d,
  )
  assertEquals(response.status, 200)
  const body = await response.json()
  assertEquals(body.hub_id, HUB_A.id)
  assert(/^[0-9a-f]{64}$/.test(body.device_secret), 'device_secret must be 64 lowercase hex chars')
  assertEquals(body.heartbeat_interval_s, 60)
  assertEquals(body.telemetry_interval_s, 300)
})

// ---------------------------------------------------------------------------
// 12.2 auth/token
// ---------------------------------------------------------------------------

Deno.test('token: no secret on file yet is 409 SECRET_ROTATION_REQUIRED', async () => {
  const state = freshState()
  const response = await handleGatewayRequest(
    post('/v1/auth/token', { hub_id: HUB_A.id, device_secret: DEVICE_SECRET }),
    deps(state),
  )
  assertEquals(response.status, 409)
  assertEquals((await response.json()).error.code, 'SECRET_ROTATION_REQUIRED')
})

Deno.test('token: a wrong device secret is 401 INVALID_DEVICE_SECRET', async () => {
  const state = freshState({ deviceSecretHash: await sha256Hex('d'.repeat(64)) })
  const response = await handleGatewayRequest(
    post('/v1/auth/token', { hub_id: HUB_A.id, device_secret: DEVICE_SECRET }),
    deps(state),
  )
  assertEquals(response.status, 401)
  assertEquals((await response.json()).error.code, 'INVALID_DEVICE_SECRET')
})

Deno.test('token: the right secret mints a 24 h opaque token', async () => {
  const state = freshState({ deviceSecretHash: await sha256Hex(DEVICE_SECRET) })
  const response = await handleGatewayRequest(
    post('/v1/auth/token', { hub_id: HUB_A.id, device_secret: DEVICE_SECRET }),
    deps(state),
  )
  assertEquals(response.status, 200)
  const body = await response.json()
  assertEquals(body.expires_in, 86400)
  assertEquals(body.rotate_secret, false)
  assert(body.device_token.length <= 128)
  assert(/^[A-Za-z0-9._-]+$/.test(body.device_token))
})

Deno.test('token: an unknown hub_id is 404 UNKNOWN_HUB', async () => {
  const response = await handleGatewayRequest(
    post('/v1/auth/token', {
      hub_id: '11111111-2222-3333-4444-555555555555',
      device_secret: DEVICE_SECRET,
    }),
    deps(freshState()),
  )
  assertEquals(response.status, 404)
  assertEquals((await response.json()).error.code, 'UNKNOWN_HUB')
})

// ---------------------------------------------------------------------------
// 12.3 telemetry
// ---------------------------------------------------------------------------

function reading(overrides: Record<string, unknown> = {}) {
  return {
    sensor_uid: 'A4CF12B93D07',
    measured_at: Math.floor(Date.now() / 1000) - 60,
    metrics: { temperature_c: 27.4, humidity_rh: 61.2 },
    ...overrides,
  }
}

Deno.test('telemetry: a good batch is 202 and auto-creates the sensor', async () => {
  const state = freshState()
  const response = await handleGatewayRequest(
    post('/v1/telemetry', { batch_id: 'CMH-4F2A9C01-000000000417', readings: [reading()] }, TOKEN),
    deps(state),
  )
  assertEquals(response.status, 202)
  const body = await response.json()
  assertEquals(body.accepted, 1)
  assertEquals(body.rejected.length, 0)
  assertEquals(state.inserted.length, 1)
  assertEquals(state.inserted[0].customer_id, 'customer-a')
  assertEquals(state.inserted[0].quality, 'ok')
})

Deno.test('telemetry: customer_id always comes from the token, never the body', async () => {
  const state = freshState()
  await handleGatewayRequest(
    post('/v1/telemetry', {
      batch_id: 'b1',
      customer_id: 'customer-VICTIM',
      readings: [reading()],
    }, TOKEN),
    deps(state),
  )
  assertEquals(state.inserted[0].customer_id, 'customer-a')
})

Deno.test('telemetry: a replayed batch_id is a 202 duplicate, not an error', async () => {
  const state = freshState()
  const d = deps(state)
  const payload = { batch_id: 'dup-1', readings: [reading()] }
  await handleGatewayRequest(post('/v1/telemetry', payload, TOKEN), d)
  const second = await handleGatewayRequest(post('/v1/telemetry', payload, TOKEN), d)
  assertEquals(second.status, 202)
  const body = await second.json()
  assertEquals(body.duplicate, true)
  assertEquals(body.accepted, 0)
  assertEquals(state.inserted.length, 1)
})

Deno.test('telemetry: more than 64 readings is 413', async () => {
  const state = freshState()
  const response = await handleGatewayRequest(
    post('/v1/telemetry', {
      batch_id: 'big',
      readings: Array.from({ length: 65 }, () => reading()),
    }, TOKEN),
    deps(state),
  )
  assertEquals(response.status, 413)
  assertEquals((await response.json()).error.code, 'PAYLOAD_TOO_LARGE')
})

Deno.test('telemetry: per-reading problems are rejected without failing the batch', async () => {
  const state = freshState()
  const now = Math.floor(Date.now() / 1000)
  const response = await handleGatewayRequest(
    post('/v1/telemetry', {
      batch_id: 'mixed',
      readings: [
        reading(),
        reading({ sensor_uid: 'nothex' }),
        reading({ measured_at: now + 4000 }),
        reading({ measured_at: now - 200 * 24 * 3600 }),
        reading({ metrics: {} }),
      ],
    }, TOKEN),
    deps(state),
  )
  assertEquals(response.status, 202)
  const body = await response.json()
  assertEquals(body.accepted, 1)
  const reasons = body.rejected.map((r: { reason: string }) => r.reason)
  assertEquals(reasons, [
    'UNKNOWN_SENSOR',
    'FUTURE_TIMESTAMP',
    'STALE_TIMESTAMP',
    'NO_VALID_METRICS',
  ])
})

Deno.test('telemetry: an implausible value is stored as suspect and flagged, not dropped', async () => {
  const state = freshState()
  const response = await handleGatewayRequest(
    post('/v1/telemetry', {
      batch_id: 'flagme',
      readings: [reading({ metrics: { temperature_c: 900 } })],
    }, TOKEN),
    deps(state),
  )
  const body = await response.json()
  assertEquals(body.accepted, 1)
  assertEquals(body.flagged.length, 1)
  assertEquals(body.flagged[0].metric_key, 'temperature_c')
  assertEquals(state.inserted[0].quality, 'suspect')
})

Deno.test('telemetry: t_est marks the row estimated', async () => {
  const state = freshState()
  await handleGatewayRequest(
    post('/v1/telemetry', { batch_id: 'est', readings: [reading({ t_est: true })] }, TOKEN),
    deps(state),
  )
  assertEquals(state.inserted[0].quality, 'estimated')
})

Deno.test('telemetry: duplicate (sensor, instant) inside one batch is merged, not sent twice', async () => {
  const state = freshState()
  const at = Math.floor(Date.now() / 1000) - 30
  const response = await handleGatewayRequest(
    post('/v1/telemetry', {
      batch_id: 'intra',
      readings: [
        reading({ measured_at: at, metrics: { temperature_c: 27.4 } }),
        reading({ measured_at: at, metrics: { humidity_rh: 61.2 } }),
      ],
    }, TOKEN),
    deps(state),
  )
  assertEquals(response.status, 202)
  assertEquals(state.inserted.length, 1)
  assertEquals(state.inserted[0].metrics, { temperature_c: 27.4, humidity_rh: 61.2 })
})

Deno.test('telemetry: a body over 32 KB is 413', async () => {
  const state = freshState()
  const request = new Request('https://example.test/iot-gateway/v1/telemetry', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${TOKEN}` },
    body: JSON.stringify({ batch_id: 'x', pad: 'p'.repeat(40_000), readings: [reading()] }),
  })
  const response = await handleGatewayRequest(request, deps(state))
  assertEquals(response.status, 413)
})

// ---------------------------------------------------------------------------
// 12.4 / 12.5 heartbeat and commands
// ---------------------------------------------------------------------------

Deno.test('heartbeat: returns config version, commands, and a clamped interval', async () => {
  const state = freshState()
  state.commands = [{ id: 'b1d7e0c2-4a19-4c88-9f2e-3d0a7c611e45', command_type: 'identify_hub', params: { duration_s: 30 } }]
  const response = await handleGatewayRequest(
    post('/v1/heartbeat', { uptime_s: 864210, topology_hash: '8a41c9f2' }, TOKEN),
    deps(state),
  )
  assertEquals(response.status, 200)
  const body = await response.json()
  assertEquals(body.config_version, 4)
  assertEquals(body.commands.length, 1)
  assertEquals(body.commands[0].command_type, 'identify_hub')
  // A pending command speeds the hub up.
  assertEquals(body.next_heartbeat_s, 10)
  assertEquals(body.topology_stale, false)
})

Deno.test('heartbeat: only whitelisted fields are stored', async () => {
  const state = freshState()
  await handleGatewayRequest(
    post('/v1/heartbeat', { uptime_s: 12, evil_field: 'drop me', wifi_ssid: 'ops' }, TOKEN),
    deps(state),
  )
  const snapshot = state.heartbeats[0]
  assertEquals(snapshot.uptime_s, 12)
  assertEquals(snapshot.wifi_ssid, 'ops')
  assertEquals('evil_field' in snapshot, false)
})

Deno.test('heartbeat: a changed topology hash marks topology stale', async () => {
  const state = freshState()
  const response = await handleGatewayRequest(
    post('/v1/heartbeat', { topology_hash: 'ffffffff' }, TOKEN),
    deps(state),
  )
  assertEquals((await response.json()).topology_stale, true)
})

Deno.test('commands/ack: well-formed acks pass through, malformed ones are ignored', async () => {
  const state = freshState()
  const response = await handleGatewayRequest(
    post('/v1/commands/ack', {
      acks: [
        { command_id: 'b1d7e0c2-4a19-4c88-9f2e-3d0a7c611e45', status: 'succeeded' },
        { command_id: 'not-a-uuid', status: 'succeeded' },
        { command_id: '9f2a1b03-6c55-4a71-8e10-2b7d9c334f88', status: 'bogus_status' },
      ],
    }, TOKEN),
    deps(state),
  )
  assertEquals(response.status, 200)
  assertEquals((await response.json()).acknowledged, 1)
  assertEquals(state.acks.length, 1)
})

// ---------------------------------------------------------------------------
// 12.7 / 12.8 / 12.9
// ---------------------------------------------------------------------------

Deno.test('topology: a snapshot is accepted and normalised', async () => {
  const state = freshState()
  const response = await handleGatewayRequest(
    post('/v1/topology', {
      topology_hash: '8a41c9f2',
      sensors: [
        { sensor_uid: 'a4cf12b93d07', state: 'online', capabilities: ['temperature_c'] },
        { sensor_uid: 'A4CF12B93D07', state: 'offline' },
        { sensor_uid: 'bad' },
      ],
    }, TOKEN),
    deps(state),
  )
  assertEquals(response.status, 200)
  // Lower-cased uid is normalised, the repeat is dropped, the malformed one skipped.
  assertEquals(state.topology.length, 1)
  assertEquals((await response.json()).accepted, 1)
})

Deno.test('config: returns a flat resolved doc with base_url, and honours If-None-Match', async () => {
  const state = freshState()
  const d = deps(state)
  const first = await handleGatewayRequest(get('/v1/config', TOKEN), d)
  assertEquals(first.status, 200)
  const etag = first.headers.get('ETag')
  assert(etag)
  const body = await first.json()
  assertEquals(body.config_version, 4)
  assertEquals(body.config.base_url, 'https://example.test/functions/v1/iot-gateway')
  assertEquals(body.config.espnow_pmk, 'deadbeef')

  const second = await handleGatewayRequest(
    get('/v1/config', TOKEN, { 'If-None-Match': etag }),
    d,
  )
  assertEquals(second.status, 304)
})

Deno.test('events: a batch is accepted and an unknown severity degrades to info', async () => {
  const state = freshState()
  const response = await handleGatewayRequest(
    post('/v1/events', {
      events: [
        {
          event_id: 'CMH-4F2A9C01-e-000000000091',
          event_type: 'sensor_disconnected',
          severity: 'warning',
          occurred_at: Math.floor(Date.now() / 1000),
        },
        {
          event_id: 'CMH-4F2A9C01-e-000000000092',
          event_type: 'brand_new_thing',
          severity: 'apocalyptic',
          occurred_at: Math.floor(Date.now() / 1000),
        },
      ],
    }, TOKEN),
    deps(state),
  )
  assertEquals(response.status, 202)
  assertEquals((await response.json()).accepted, 2)
  assertEquals((state.events[1] as { severity: string }).severity, 'info')
})

Deno.test('firmware: no active release means update_available false', async () => {
  const response = await handleGatewayRequest(get('/v1/firmware', TOKEN), deps(freshState()))
  assertEquals(response.status, 200)
  assertEquals((await response.json()).update_available, false)
})

Deno.test('every response carries server_time', async () => {
  const state = freshState()
  const d = deps(state)
  for (const request of [
    get('/v1/health'),
    post('/v1/heartbeat', {}, TOKEN),
    post('/v1/telemetry', { batch_id: 'st', readings: [reading()] }, TOKEN),
    get('/v1/config', TOKEN),
    post('/v1/events', { events: [] }, TOKEN),
  ]) {
    const response = await handleGatewayRequest(request, d)
    const body = await response.json()
    assert(typeof body.server_time === 'number', `server_time missing on ${request.url}`)
  }
})

// ---------------------------------------------------------------------------
// Regressions found by the adversarial review of the deployed implementation
// ---------------------------------------------------------------------------

Deno.test('provision: re-provisioning does NOT rotate the ESP-NOW key', async () => {
  const state = freshState({ espnowPmk: 'existingpmk0000000000000000000000' })
  const d = deps(state)
  const realDb = d.db
  d.db = {
    ...realDb,
    getRegistry: async (serial: string) => ({
      hub_serial: serial,
      factory_secret_hash: await sha256Hex(FACTORY_SECRET),
      hardware_model: 'chickmark-hub-v1',
    }),
  }
  const response = await handleGatewayRequest(
    post('/v1/provision', { hub_serial: HUB_A.hub_serial, factory_secret: FACTORY_SECRET }),
    d,
  )
  assertEquals(response.status, 200)
  // Rotating it here would strand every already-paired sleeping sensor node.
  assertEquals(state.espnowPmk, 'existingpmk0000000000000000000000')
  assertEquals((await response.json()).espnow_pmk_rotated, false)
})

Deno.test('provision: a first-time hub does get a fresh ESP-NOW key', async () => {
  const state = freshState({ espnowPmk: null })
  const d = deps(state)
  const realDb = d.db
  d.db = {
    ...realDb,
    getRegistry: async (serial: string) => ({
      hub_serial: serial,
      factory_secret_hash: await sha256Hex(FACTORY_SECRET),
      hardware_model: 'chickmark-hub-v1',
    }),
  }
  const response = await handleGatewayRequest(
    post('/v1/provision', { hub_serial: HUB_A.hub_serial, factory_secret: FACTORY_SECRET }),
    d,
  )
  assertEquals((await response.json()).espnow_pmk_rotated, true)
  assert(/^[0-9a-f]{32}$/.test(state.espnowPmk ?? ''))
})

Deno.test('topology: omitting topology_hash must not wipe the stored one', async () => {
  const state = freshState()
  const response = await handleGatewayRequest(
    post('/v1/topology', { sensors: [{ sensor_uid: 'A4CF12B93D07', state: 'online' }] }, TOKEN),
    deps(state),
  )
  assertEquals(response.status, 200)
  // Writing null here would make every later heartbeat answer topology_stale:
  // true, putting the hub in a permanent full-snapshot loop.
  assertEquals(state.topologyHashWrites.length, 0)
  assertEquals((await response.json()).topology_hash, HUB_A.topology_hash)
})

Deno.test('GET /v1/commands does not consume: reading never marks delivered', async () => {
  const state = freshState()
  state.commands = [{ id: 'b1d7e0c2-4a19-4c88-9f2e-3d0a7c611e45', command_type: 'force_sync', params: {} }]
  const d = deps(state)
  await handleGatewayRequest(get('/v1/commands', TOKEN), d)
  assertEquals(state.deliveredMarked, 0)
  await handleGatewayRequest(post('/v1/heartbeat', {}, TOKEN), d)
  assertEquals(state.deliveredMarked, 1)
})

Deno.test('a wrong HTTP method is 405, never 400', async () => {
  // 400 tells firmware to DROP the payload. A misrouted request must not look
  // like a bad payload.
  const state = freshState()
  const bootstrap = await handleGatewayRequest(
    new Request('https://example.test/iot-gateway/v1/provision', { method: 'PUT' }),
    deps(state),
  )
  assertEquals(bootstrap.status, 405)
  assertEquals((await bootstrap.json()).error.code, 'METHOD_NOT_ALLOWED')

  const authed = await handleGatewayRequest(
    new Request('https://example.test/iot-gateway/v1/telemetry', {
      method: 'PUT',
      headers: { Authorization: `Bearer ${TOKEN}` },
    }),
    deps(state),
  )
  assertEquals(authed.status, 405)
})

Deno.test('telemetry: a malformed sensor_uid is echoed back, not nulled', async () => {
  const state = freshState()
  const response = await handleGatewayRequest(
    post('/v1/telemetry', {
      batch_id: 'echo',
      readings: [reading({ sensor_uid: 'nothex' })],
    }, TOKEN),
    deps(state),
  )
  const body = await response.json()
  assertEquals(body.rejected[0].sensor_uid, 'NOTHEX')
  assertEquals(body.rejected[0].reason, 'UNKNOWN_SENSOR')
})

Deno.test('token: an aged secret asks for rotation on its own', async () => {
  const state = freshState({ deviceSecretHash: await sha256Hex(DEVICE_SECRET) })
  const d = deps(state)
  const realDb = d.db
  d.db = {
    ...realDb,
    getHubSecret: () =>
      Promise.resolve({
        device_secret_hash: state.deviceSecretHash,
        rotate_requested: false,
        espnow_pmk: null,
        // 200 days old, past the 180-day cadence.
        secret_rotated_at_s: Math.floor(Date.now() / 1000) - 200 * 24 * 3600,
      }),
  }
  const response = await handleGatewayRequest(
    post('/v1/auth/token', { hub_id: HUB_A.id, device_secret: DEVICE_SECRET }),
    d,
  )
  assertEquals((await response.json()).rotate_secret, true)
})

Deno.test('commands/ack: the device completed_at reaches the storage layer', async () => {
  const state = freshState()
  const when = Math.floor(Date.now() / 1000) - 120
  await handleGatewayRequest(
    post('/v1/commands/ack', {
      acks: [{
        command_id: 'b1d7e0c2-4a19-4c88-9f2e-3d0a7c611e45',
        status: 'succeeded',
        completed_at: when,
      }],
    }, TOKEN),
    deps(state),
  )
  assertEquals((state.acks[0] as { completed_at_s: number | null }).completed_at_s, when)
})
