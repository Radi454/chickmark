// Wire limits, defaults, and the storage port the handlers depend on.
//
// Handlers never touch supabase-js directly. They talk to `Db`, which
// db_supabase.ts implements against the real database and the tests implement
// with plain objects. That is what makes every handler testable without a
// network or a database.

/** docs/IOT_API_CONTRACT.md section 12.0.3. Firmware sizes its buffers against
 *  these, so they are not free to drift. */
export const LIMITS = {
  maxBodyBytes: 32 * 1024,
  maxReadingsPerBatch: 64,
  maxMetricsPerReading: 16,
  maxEventsPerBatch: 32,
  maxAcksPerRequest: 32,
  maxSensorsPerTopology: 256,
  maxCommandsPerHeartbeat: 10,
  maxKeyChars: 64,
  maxMessageChars: 512,
  maxDetailBytes: 4 * 1024,
  maxTokenChars: 128,
} as const

/** Server-side validation window for measured_at, section 7.2. */
export const TIME_WINDOW = {
  futureToleranceSeconds: 300,
  staleToleranceSeconds: 90 * 24 * 60 * 60,
} as const

export const TOKEN_TTL_SECONDS = 24 * 60 * 60

/** Device secrets rotate on a 180-day cadence (contract section 5.3). Past this
 *  age /v1/auth/token starts answering rotate_secret: true. */
export const SECRET_LIFETIME_SECONDS = 180 * 24 * 60 * 60

/** Baseline config, merged under the fleet defaults and the per-hub override.
 *  espnow_channel is deliberately absent: changing the radio channel from a
 *  server would strand every already-paired sleeping node. */
export const BASE_CONFIG: Record<string, unknown> = {
  measurement_interval_s: 60,
  telemetry_interval_s: 300,
  heartbeat_interval_s: 60,
  max_batch_readings: 64,
  topology_report_interval_s: 86400,
  sensor_offline_after_s: 300,
  enabled_metrics: ['temperature_c', 'humidity_rh', 'co2_ppm', 'nh3_ppm'],
  disabled_sensor_uids: [],
  calibration: {},
  ntp_servers: ['pool.ntp.org', 'time.cloudflare.com'],
  timezone: 'UTC',
  log_level: 'info',
  ota_channel: 'stable',
  ota_check_interval_s: 21600,
}

export const COMMAND_TERMINAL_STATUSES = ['succeeded', 'failed', 'unsupported', 'expired'] as const

export interface RegistryRow {
  hub_serial: string
  factory_secret_hash: string
  hardware_model: string
}

export interface HubRow {
  id: string
  hub_serial: string
  customer_id: string
  hatchery_id: string | null
  hardware_model: string
  status: 'active' | 'revoked' | 'retired'
  config_version: number
  topology_hash: string | null
}

export interface TokenContext {
  hub: HubRow
  expires_at_s: number
}

export interface SensorRow {
  id: string
  sensor_uid: string
  status: string
}

export interface MetricRule {
  metric_key: string
  min_plausible: number | null
  max_plausible: number | null
  is_active: boolean
}

export interface TelemetryRow {
  customer_id: string
  hub_id: string
  sensor_id: string
  measured_at: string
  batch_id: string
  metrics: Record<string, number>
  quality: 'ok' | 'suspect' | 'estimated'
  battery_percent: number | null
  rssi: number | null
}

export interface CommandRow {
  id: string
  command_type: string
  params: Record<string, unknown>
  created_at_s: number
  expires_at_s: number
}

export interface AckInput {
  command_id: string
  status: string
  completed_at_s: number | null
  result: Record<string, unknown> | null
  error_code: string | null
  error_message: string | null
}

export interface EventInput {
  event_id: string
  event_type: string
  severity: 'info' | 'warning' | 'critical'
  occurred_at_s: number
  sensor_uid: string | null
  detail: Record<string, unknown>
}

export interface TopologySensorInput {
  sensor_uid: string
  model: string | null
  firmware_version: string | null
  capabilities: string[]
  state: string
  battery_percent: number | null
  rssi: number | null
  last_seen_at_s: number | null
}

export interface FirmwareOffer {
  update_id: string
  target: string
  version: string
  hardware_model: string
  size_bytes: number
  sha256: string
  signature: string
  signature_alg: string
  download_url: string
  url_expires_at: number
  release_notes: string | null
}

export interface Db {
  // provisioning + auth
  getRegistry(hubSerial: string): Promise<RegistryRow | null>
  getLiveHubBySerial(hubSerial: string): Promise<HubRow | null>
  getHubById(hubId: string): Promise<HubRow | null>
  getHubSecret(hubId: string): Promise<
    {
      device_secret_hash: string | null
      rotate_requested: boolean
      espnow_pmk: string | null
      secret_rotated_at_s: number | null
    } | null
  >
  setDeviceSecret(hubId: string, secretHash: string, espnowPmk: string | null): Promise<void>
  revokeAllTokens(hubId: string): Promise<void>
  recordProvision(hubId: string, firmwareVersion: string | null): Promise<void>
  issueToken(tokenHash: string, hubId: string, expiresAtIso: string): Promise<void>
  resolveToken(tokenHash: string): Promise<TokenContext | null>

  // telemetry
  getBatch(hubId: string, batchId: string): Promise<{ reading_count: number; accepted: number } | null>
  recordBatch(hubId: string, batchId: string, readingCount: number, accepted: number): Promise<void>
  getSensorsByUids(hubId: string, uids: string[]): Promise<SensorRow[]>
  createSensor(hubId: string, customerId: string, sensorUid: string): Promise<SensorRow>
  getMetricRules(): Promise<MetricRule[]>
  insertTelemetry(rows: TelemetryRow[]): Promise<number>
  touchHubTelemetry(hubId: string): Promise<void>
  countPendingCommands(hubId: string, customerId: string): Promise<number>

  // heartbeat + commands
  recordHeartbeat(hubId: string, firmwareVersion: string | null, snapshot: Record<string, unknown>): Promise<void>
  takePendingCommands(
    hubId: string,
    customerId: string,
    limit: number,
    markDelivered: boolean,
  ): Promise<CommandRow[]>
  applyAcks(hubId: string, customerId: string, acks: AckInput[]): Promise<{ acknowledged: number; unknown: string[] }>

  // events
  insertEvents(hubId: string, customerId: string, events: EventInput[]): Promise<{ accepted: number; duplicates: number }>

  // topology
  applyTopology(hubId: string, customerId: string, sensors: TopologySensorInput[]): Promise<number>
  setTopologyHash(hubId: string, topologyHash: string): Promise<void>

  // config
  getResolvedConfig(hub: HubRow): Promise<{ version: number; doc: Record<string, unknown> }>

  // firmware
  findFirmwareOffer(
    hub: HubRow,
    currentVersion: string | null,
    target: string,
    channel: string,
  ): Promise<FirmwareOffer | null>
  recordFirmwareStatus(
    hubId: string,
    customerId: string,
    report: { update_id: string; status: string; from_version: string | null; to_version: string | null; error_code: string | null; error_message: string | null },
  ): Promise<boolean>
}
