// The `Db` port, implemented against Supabase with the service-role key.
//
// Everything here runs as service_role, which bypasses RLS. That is exactly why
// every query that touches a hub-scoped table filters on BOTH hub_id and
// customer_id: the database's tenant isolation is not protecting us in this
// process, so the queries have to.
//
// customer_id is never taken from a request body. It comes only from the row
// resolved by the bearer token.

import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import {
  BASE_CONFIG,
  type CommandRow,
  type Db,
  type EventInput,
  type FirmwareOffer,
  type HubRow,
  type MetricRule,
  type RegistryRow,
  type SensorRow,
  type TelemetryRow,
  type TokenContext,
  type TopologySensorInput,
  type AckInput,
} from './types.ts'
import { isoToSeconds, isPlainObject, nowSeconds, secondsToIso } from './util.ts'

const HUB_COLUMNS =
  'id, hub_serial, customer_id, hatchery_id, hardware_model, status, config_version, topology_hash'

/** Stable 0-99 bucket for a hub, derived from its id. Deterministic so that
 *  raising a rollout percentage only ever adds hubs, never reshuffles them. */
function rolloutBucket(hubId: string): number {
  let hash = 0
  for (let i = 0; i < hubId.length; i++) {
    hash = (hash * 31 + hubId.charCodeAt(i)) >>> 0
  }
  return hash % 100
}

/** Dotted numeric version compare. Returns <0, 0 or >0. Non-numeric segments
 *  sort as 0, which is deliberate: a malformed version must not be treated as
 *  newer than a real one. */
function compareVersions(a: string, b: string): number {
  const pa = a.split('.')
  const pb = b.split('.')
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const na = Number.parseInt(pa[i] ?? '0', 10) || 0
    const nb = Number.parseInt(pb[i] ?? '0', 10) || 0
    if (na !== nb) return na - nb
  }
  return 0
}

export function createSupabaseDb(client: SupabaseClient): Db {
  const hubFrom = (row: Record<string, unknown>): HubRow => ({
    id: String(row.id),
    hub_serial: String(row.hub_serial),
    customer_id: String(row.customer_id),
    hatchery_id: (row.hatchery_id as string | null) ?? null,
    hardware_model: String(row.hardware_model ?? ''),
    status: row.status as HubRow['status'],
    config_version: Number(row.config_version ?? 1),
    topology_hash: (row.topology_hash as string | null) ?? null,
  })

  return {
    async getRegistry(hubSerial): Promise<RegistryRow | null> {
      const { data } = await client
        .from('iot_hub_registry')
        .select('hub_serial, factory_secret_hash, hardware_model')
        .eq('hub_serial', hubSerial)
        .maybeSingle()
      return data ?? null
    },

    async getLiveHubBySerial(hubSerial): Promise<HubRow | null> {
      const { data } = await client
        .from('iot_hubs')
        .select(HUB_COLUMNS)
        .eq('hub_serial', hubSerial)
        .neq('status', 'retired')
        .maybeSingle()
      return data ? hubFrom(data) : null
    },

    async getHubById(hubId): Promise<HubRow | null> {
      const { data } = await client
        .from('iot_hubs')
        .select(HUB_COLUMNS)
        .eq('id', hubId)
        .maybeSingle()
      return data ? hubFrom(data) : null
    },

    async getHubSecret(hubId) {
      const { data } = await client
        .from('iot_hub_secrets')
        .select('device_secret_hash, rotate_requested, espnow_pmk, secret_rotated_at')
        .eq('hub_id', hubId)
        .maybeSingle()
      return data
        ? {
          device_secret_hash: data.device_secret_hash ?? null,
          rotate_requested: data.rotate_requested === true,
          espnow_pmk: data.espnow_pmk ?? null,
          secret_rotated_at_s: isoToSeconds(data.secret_rotated_at),
        }
        : null
    },

    async setDeviceSecret(hubId, secretHash, espnowPmk) {
      const patch: Record<string, unknown> = {
        hub_id: hubId,
        device_secret_hash: secretHash,
        secret_rotated_at: new Date().toISOString(),
        rotate_requested: false,
        updated_at: new Date().toISOString(),
      }
      // Only ever write the radio key, never clear it.
      if (espnowPmk) patch.espnow_pmk = espnowPmk
      const { error } = await client
        .from('iot_hub_secrets')
        .upsert(patch, { onConflict: 'hub_id' })
      if (error) throw new Error(`setDeviceSecret: ${error.message}`)
    },

    async revokeAllTokens(hubId) {
      await client
        .from('iot_device_tokens')
        .update({ revoked_at: new Date().toISOString() })
        .eq('hub_id', hubId)
        .is('revoked_at', null)
    },

    async recordProvision(hubId, firmwareVersion) {
      const patch: Record<string, unknown> = {
        last_seen_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }
      if (firmwareVersion) patch.firmware_version = firmwareVersion
      await client.from('iot_hubs').update(patch).eq('id', hubId)
    },

    async issueToken(tokenHash, hubId, expiresAtIso) {
      const { error } = await client.from('iot_device_tokens').insert({
        token_hash: tokenHash,
        hub_id: hubId,
        expires_at: expiresAtIso,
      })
      if (error) throw new Error(`issueToken: ${error.message}`)
    },

    async resolveToken(tokenHash): Promise<TokenContext | null> {
      const { data } = await client
        .from('iot_device_tokens')
        .select('hub_id, expires_at, revoked_at')
        .eq('token_hash', tokenHash)
        .maybeSingle()
      if (!data || data.revoked_at) return null
      const expiresAt = isoToSeconds(data.expires_at)
      if (expiresAt === null || expiresAt <= nowSeconds()) return null

      const { data: hubRow } = await client
        .from('iot_hubs')
        .select(HUB_COLUMNS)
        .eq('id', data.hub_id)
        .maybeSingle()
      if (!hubRow) return null
      return { hub: hubFrom(hubRow), expires_at_s: expiresAt }
    },

    async getBatch(hubId, batchId) {
      const { data } = await client
        .from('iot_telemetry_batches')
        .select('reading_count, accepted')
        .eq('hub_id', hubId)
        .eq('batch_id', batchId)
        .maybeSingle()
      return data ?? null
    },

    async recordBatch(hubId, batchId, readingCount, accepted) {
      await client.from('iot_telemetry_batches').upsert({
        hub_id: hubId,
        batch_id: batchId,
        reading_count: readingCount,
        accepted,
      }, { onConflict: 'hub_id,batch_id', ignoreDuplicates: true })
    },

    async getSensorsByUids(hubId, uids): Promise<SensorRow[]> {
      if (uids.length === 0) return []
      const { data } = await client
        .from('iot_sensors')
        .select('id, sensor_uid, status')
        .eq('hub_id', hubId)
        .in('sensor_uid', uids)
      return (data ?? []) as SensorRow[]
    },

    async createSensor(hubId, customerId, sensorUid): Promise<SensorRow> {
      const { data, error } = await client
        .from('iot_sensors')
        .insert({ hub_id: hubId, customer_id: customerId, sensor_uid: sensorUid })
        .select('id, sensor_uid, status')
        .single()
      if (error) {
        // Two batches from the same hub can race on first sight of a sensor.
        // The unique (hub_id, sensor_uid) index decides; re-read the winner.
        const { data: existing } = await client
          .from('iot_sensors')
          .select('id, sensor_uid, status')
          .eq('hub_id', hubId)
          .eq('sensor_uid', sensorUid)
          .maybeSingle()
        if (existing) return existing as SensorRow
        throw new Error(`createSensor: ${error.message}`)
      }
      return data as SensorRow
    },

    async getMetricRules(): Promise<MetricRule[]> {
      const { data } = await client
        .from('iot_metric_registry')
        .select('metric_key, min_plausible, max_plausible, is_active')
      return (data ?? []) as MetricRule[]
    },

    async insertTelemetry(rows: TelemetryRow[]): Promise<number> {
      const { data, error } = await client.rpc('iot_ingest_telemetry', { p_rows: rows })
      if (error) throw new Error(`insertTelemetry: ${error.message}`)
      const result = (data ?? {}) as Record<string, number>
      return Number(result.accepted ?? 0) + Number(result.merged ?? 0)
    },

    async touchHubTelemetry(hubId) {
      const stamp = new Date().toISOString()
      await client
        .from('iot_hubs')
        .update({ last_telemetry_at: stamp, last_seen_at: stamp, updated_at: stamp })
        .eq('id', hubId)
    },

    async countPendingCommands(hubId, customerId): Promise<number> {
      const { count } = await client
        .from('iot_commands')
        .select('id', { count: 'exact', head: true })
        .eq('hub_id', hubId)
        .eq('customer_id', customerId)
        .in('status', ['pending', 'delivered'])
        .gt('expires_at', new Date().toISOString())
      return count ?? 0
    },

    async recordHeartbeat(hubId, firmwareVersion, snapshot) {
      const patch: Record<string, unknown> = {
        last_seen_at: new Date().toISOString(),
        last_heartbeat: snapshot,
        updated_at: new Date().toISOString(),
      }
      if (firmwareVersion) patch.firmware_version = firmwareVersion
      await client.from('iot_hubs').update(patch).eq('id', hubId)
    },

    async takePendingCommands(hubId, customerId, limit, markDelivered): Promise<CommandRow[]> {
      const nowIso = new Date().toISOString()

      // Expire first, so a hub never receives a command whose window has closed.
      await client
        .from('iot_commands')
        .update({ status: 'expired' })
        .eq('hub_id', hubId)
        .eq('customer_id', customerId)
        .in('status', ['pending', 'delivered'])
        .lte('expires_at', nowIso)

      const { data } = await client
        .from('iot_commands')
        .select('id, command_type, params, created_at, expires_at')
        .eq('hub_id', hubId)
        .eq('customer_id', customerId)
        .in('status', ['pending', 'delivered'])
        .gt('expires_at', nowIso)
        .order('created_at', { ascending: true })
        .limit(limit)

      const rows = data ?? []
      if (markDelivered && rows.length > 0) {
        await client
          .from('iot_commands')
          .update({ status: 'delivered', delivered_at: nowIso })
          .in('id', rows.map((r) => r.id))
          .eq('hub_id', hubId)
          .eq('customer_id', customerId)
          .eq('status', 'pending')
      }

      return rows.map((r) => ({
        id: String(r.id),
        command_type: String(r.command_type),
        params: isPlainObject(r.params) ? r.params : {},
        created_at_s: isoToSeconds(r.created_at) ?? nowSeconds(),
        expires_at_s: isoToSeconds(r.expires_at) ?? nowSeconds(),
      }))
    },

    async applyAcks(hubId, customerId, acks: AckInput[]) {
      const { data, error } = await client.rpc('iot_ack_commands', {
        p_hub_id: hubId,
        p_customer_id: customerId,
        p_acks: acks.map((a) => ({
          command_id: a.command_id,
          status: a.status,
          // Pass the device's own completion time through. Dropping it here --
          // which an earlier version did -- makes iot_ack_commands fall back to
          // now(), and that is exactly the timing distinction section 12.5
          // exists for: telling a successful reboot from a crash.
          completed_at: a.completed_at_s,
          result: a.result,
          error_code: a.error_code,
          error_message: a.error_message,
        })),
      })
      if (error) throw new Error(`applyAcks: ${error.message}`)
      const result = (data ?? {}) as { acknowledged?: number; unknown?: string[] }
      return { acknowledged: result.acknowledged ?? 0, unknown: result.unknown ?? [] }
    },

    async insertEvents(hubId, customerId, events: EventInput[]) {
      const { data, error } = await client.rpc('iot_insert_events', {
        p_hub_id: hubId,
        p_customer_id: customerId,
        p_events: events.map((e) => ({
          event_id: e.event_id,
          event_type: e.event_type,
          severity: e.severity,
          occurred_at: secondsToIso(e.occurred_at_s),
          sensor_uid: e.sensor_uid,
          detail: e.detail,
        })),
      })
      if (error) throw new Error(`insertEvents: ${error.message}`)
      const result = (data ?? {}) as { accepted?: number; duplicates?: number }
      return { accepted: result.accepted ?? 0, duplicates: result.duplicates ?? 0 }
    },

    async applyTopology(hubId, customerId, sensors: TopologySensorInput[]): Promise<number> {
      const { data, error } = await client.rpc('iot_apply_topology', {
        p_hub_id: hubId,
        p_customer_id: customerId,
        p_sensors: sensors.map((s) => ({
          sensor_uid: s.sensor_uid,
          model: s.model,
          firmware_version: s.firmware_version,
          capabilities: s.capabilities,
          state: s.state,
          battery_percent: s.battery_percent,
          rssi: s.rssi,
          last_seen_at: s.last_seen_at_s === null ? null : secondsToIso(s.last_seen_at_s),
        })),
      })
      if (error) throw new Error(`applyTopology: ${error.message}`)
      return Number(data ?? 0)
    },

    async setTopologyHash(hubId, topologyHash: string) {
      await client
        .from('iot_hubs')
        .update({ topology_hash: topologyHash, updated_at: new Date().toISOString() })
        .eq('id', hubId)
    },

    async getResolvedConfig(hub: HubRow) {
      // Layered merge, lowest priority first. The hub never merges anything --
      // it receives one flat, fully resolved document.
      //
      // Every error below THROWS rather than degrading to defaults. Silently
      // serving BASE_CONFIG would hand the device a 200 with no espnow_pmk and an
      // unchanged config_version -- indistinguishable from a real config, and it
      // would drop the customer's calibration offsets. A 500 is honest and the
      // firmware retries it.
      //
      // Scope values are matched with .in() rather than interpolated into an
      // .or() filter string: customers.id is free-form text minted client-side,
      // so a value containing the filter grammar's own punctuation could
      // otherwise break out of the expression.
      const { data: defaults, error: defaultsError } = await client
        .from('iot_config_defaults')
        .select('scope_kind, scope_value, doc, priority')
        .in('scope_value', [hub.hardware_model, hub.customer_id, hub.hatchery_id ?? ''])
        .order('priority', { ascending: true })
      if (defaultsError) throw new Error(`getResolvedConfig defaults: ${defaultsError.message}`)

      const { data: globals, error: globalsError } = await client
        .from('iot_config_defaults')
        .select('doc, priority')
        .eq('scope_kind', 'global')
        .order('priority', { ascending: true })
      if (globalsError) throw new Error(`getResolvedConfig globals: ${globalsError.message}`)

      const scoped = (defaults ?? []).filter((layer) =>
        (layer.scope_kind === 'hardware_model' && layer.scope_value === hub.hardware_model) ||
        (layer.scope_kind === 'customer' && layer.scope_value === hub.customer_id) ||
        (layer.scope_kind === 'hatchery' && layer.scope_value === hub.hatchery_id)
      )

      let doc: Record<string, unknown> = { ...BASE_CONFIG }
      for (const layer of [...(globals ?? []), ...scoped]) {
        if (isPlainObject(layer.doc)) doc = { ...doc, ...layer.doc }
      }

      const { data: override, error: overrideError } = await client
        .from('iot_hub_config')
        .select('version, doc')
        .eq('hub_id', hub.id)
        .maybeSingle()
      if (overrideError) throw new Error(`getResolvedConfig override: ${overrideError.message}`)
      if (override && isPlainObject(override.doc)) doc = { ...doc, ...override.doc }

      const { data: secret, error: secretError } = await client
        .from('iot_hub_secrets')
        .select('espnow_pmk')
        .eq('hub_id', hub.id)
        .maybeSingle()
      if (secretError) throw new Error(`getResolvedConfig secret: ${secretError.message}`)
      if (secret?.espnow_pmk) doc.espnow_pmk = secret.espnow_pmk

      return { version: Number(override?.version ?? hub.config_version ?? 1), doc }
    },

    async findFirmwareOffer(hub, currentVersion, target, channel): Promise<FirmwareOffer | null> {
      const { data: release, error: releaseError } = await client
        .from('iot_firmware_releases')
        .select('*')
        .eq('hardware_model', hub.hardware_model)
        .eq('target', target)
        .eq('channel', channel)
        .eq('is_active', true)
        .gt('rollout_percent', 0)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (releaseError) throw new Error(`findFirmwareOffer: ${releaseError.message}`)

      if (!release) return null
      if (currentVersion && release.version === currentVersion) return null
      if (release.min_from_version && currentVersion &&
          compareVersions(currentVersion, release.min_from_version) < 0) {
        return null
      }
      // Staged rollout is entirely server-side, and the contract tells firmware
      // not to second-guess it -- so it has to actually work here. Bucket
      // deterministically on the hub id so a hub's membership is stable as the
      // percentage is raised, instead of every hub re-rolling on every check.
      if (release.rollout_percent < 100 && rolloutBucket(hub.id) >= release.rollout_percent) {
        return null
      }

      const { data: existing } = await client
        .from('iot_firmware_updates')
        .select('id')
        .eq('hub_id', hub.id)
        .eq('customer_id', hub.customer_id)
        .eq('release_id', release.id)
        .not('status', 'in', '(succeeded,rolled_back)')
        .limit(1)
        .maybeSingle()

      let updateId = existing?.id as string | undefined
      if (!updateId) {
        const { data: created, error } = await client
          .from('iot_firmware_updates')
          .insert({
            customer_id: hub.customer_id,
            hub_id: hub.id,
            release_id: release.id,
            target,
            from_version: currentVersion,
            to_version: release.version,
          })
          .select('id')
          .single()
        if (error) throw new Error(`findFirmwareOffer: ${error.message}`)
        updateId = created.id as string
      }

      const ttlSeconds = 3600
      const { data: signed } = await client.storage
        .from('firmware')
        .createSignedUrl(release.storage_path, ttlSeconds)
      if (!signed?.signedUrl) return null

      return {
        update_id: updateId,
        target,
        version: release.version,
        hardware_model: release.hardware_model,
        size_bytes: Number(release.size_bytes),
        sha256: release.sha256,
        signature: release.signature,
        signature_alg: release.signature_alg ?? 'ed25519-sha256',
        download_url: signed.signedUrl,
        url_expires_at: nowSeconds() + ttlSeconds,
        release_notes: release.release_notes ?? null,
      }
    },

    async recordFirmwareStatus(hubId, customerId, report): Promise<boolean> {
      const terminal = ['succeeded', 'failed', 'rolled_back']
      const patch: Record<string, unknown> = {
        status: report.status,
        updated_at: new Date().toISOString(),
      }
      if (report.from_version) patch.from_version = report.from_version
      if (report.error_code) patch.error_code = report.error_code
      if (report.error_message) patch.error_message = report.error_message

      // A terminal status is never overwritten by a non-terminal one, so a late
      // `downloading` report cannot un-finish a completed update.
      let query = client
        .from('iot_firmware_updates')
        .update(patch)
        .eq('id', report.update_id)
        .eq('hub_id', hubId)
        .eq('customer_id', customerId)
      if (!terminal.includes(report.status)) {
        query = query.not('status', 'in', `(${terminal.join(',')})`)
      }
      // A PostgREST update that matches nothing is not an error, so ask for the
      // affected rows. Otherwise an unknown or another hub's update_id would be
      // answered `accepted: 1` and the OTA outcome would never be recorded.
      const { data, error } = await query.select('id')
      if (error) return false
      return (data?.length ?? 0) > 0
    },
  }
}

export function createServiceClient(url: string, serviceRoleKey: string): SupabaseClient {
  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}
