# ChickMark IoT — Firmware Integration Handoff

**Status: the API is live and working.** Every endpoint and every example below
was executed against the deployed server before this document was written. You
can start integrating today.

- **Full contract:** `docs/IOT_API_CONTRACT.md`, **section 12** — that section is
  self-contained and is the authoritative specification. This document is the
  quick start plus what is actually deployed right now.
- **Contract version:** `v1`

---

## 1. Base URL

```
https://kgucchapksiiqxmiutsz.supabase.co/functions/v1/iot-gateway
```

Every path below is relative to it: `POST /v1/telemetry` means
`POST https://kgucchapksiiqxmiutsz.supabase.co/functions/v1/iot-gateway/v1/telemetry`.

**Store this in NVS as `base_url`. Do not hard-code the host.** It will move to a
vanity domain later, and firmware must survive that with a config change rather
than a reflash. The server also returns the current `base_url` in
`GET /v1/config` — see the commit-on-success rule in §12.8 of the contract before
you apply a new one.

Quick check that you can reach it — no credentials needed:

```bash
curl https://kgucchapksiiqxmiutsz.supabase.co/functions/v1/iot-gateway/v1/health
# {"status":"ok","service":"iot-gateway","contract_version":"v1","server_time":1787150003}
```

`/v1/health` is unauthenticated and exists for exactly this: confirming URL,
DNS, TLS and clock before you have any credentials.

---

## 2. Test hardware credentials

Two dev hubs are registered for you. These are **real credentials on the real
server**, scoped to a throwaway test customer. They are safe to put in dev
firmware. Do not use them on customer hardware.

### Hub 1 — claimed and ready. Use this one.

```
hub_serial      CMH-DEV00001
factory_secret  7bd90a0449246207b6142522470a41b9268328070637ce20876685bbc3030a37
hardware_model  chickmark-hub-v1
```

Already claimed to a test hatchery, so `POST /v1/provision` succeeds immediately
and returns a `hub_id` and `device_secret`.

### Hub 2 — deliberately left unclaimed. Use it to test the waiting state.

```
hub_serial      CMH-DEV00002
factory_secret  ebc7fac9b0d53be29df2fac4358720883ccdac348d5369805a73768d7a242ef5
hardware_model  chickmark-hub-v1
```

This one returns `409 DEVICE_NOT_CLAIMED` forever. That is the normal state of a
brand-new hub sitting on a shelf before an installer claims it in the app — your
LED should show "waiting to be claimed", not a fault.

**Note on `/v1/provision`:** each success mints a *new* `device_secret` and kills
the previous one, along with every token issued from it. Call it on first boot,
on `404 UNKNOWN_HUB`, or on `409 SECRET_ROTATION_REQUIRED` — **never on every
boot**.

There is no `claim_code` in this handoff. That value is scanned from the QR by
the installer in the ChickMark app and never touches the device.

---

## 3. Required headers

On every request:

```
Content-Type: application/json; charset=utf-8
X-Device-Firmware: 1.4.2          ; your firmware version
X-Device-Serial: CMH-DEV00001     ; hub serial, present even before provisioning
```

On everything except `/v1/provision`, `/v1/auth/token` and `/v1/health`:

```
Authorization: Bearer <device_token>
```

**There is no Supabase key and no `apikey` header.** If you find yourself needing
one, something is wrong — tell me rather than working around it.

Neither `X-Device-Firmware` nor `X-Device-Serial` is a credential. They are used
for diagnostics, log correlation, and later for staged OTA rollout.

---

## 4. Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET  | `/v1/health` | Reachability + clock. No auth. |
| POST | `/v1/provision` | Factory secret → `hub_id` + `device_secret`. No bearer. |
| POST | `/v1/auth/token` | `device_secret` → 24 h bearer token. No bearer. |
| POST | `/v1/telemetry` | Batch sensor readings. **Main data path.** |
| POST | `/v1/heartbeat` | Health **and** command collection. Your only polling loop. |
| POST | `/v1/commands/ack` | Acknowledge and report command outcomes. Batched. |
| GET  | `/v1/commands` | Optional. Debug only — do not build your loop on it. |
| POST | `/v1/topology` | Full sensor-set snapshot. |
| GET  | `/v1/config` | Fully resolved flat config. Supports `If-None-Match`. |
| POST | `/v1/events` | Device-level events. Separate queue from telemetry. |
| GET  | `/v1/firmware` | OTA check. Returns `update_available:false` today. |
| POST | `/v1/firmware/status` | OTA progress/outcome reporting. |

---

## 5. Conventions

**Timestamps.** Integer Unix epoch **seconds, UTC**. Never strings, never
milliseconds, never local time. A non-integer or string timestamp is rejected.

**Every response carries `server_time`** (epoch seconds). Use it to correct your
clock on every request — you have no hard dependency on reaching an NTP server
through a farm firewall. See §7.1 of the contract for the cold-boot chicken-and-egg
problem (TLS validation needs a clock, and the clock arrives over TLS): fit an
RTC if you can, otherwise follow the documented SNTP-then-relaxed-validity
bootstrap.

**Units are part of the metric key.** `temperature_c`, `humidity_rh`, `co2_ppm`,
`nh3_ppm`, `pressure_pa`, `differential_pressure_pa`, `air_velocity_mps`,
`light_lux`, `water_flow_lpm`, `water_pressure_kpa`, `battery_percent`,
`power_w`, `door_state`, `vibration_g`.

**Never send Fahrenheit.** Convert on the device, or read the sensor in Celsius
natively. Unknown metric keys are accepted and stored — they just will not be
charted until we add them, so a new sensor type can ship before any backend work.

**Omit any field you do not have.** Do not send `0`, `-1` or `null` for a missing
`battery_percent`. Same rule on every endpoint, deliberately: one serialisation
helper, one behaviour.

**Wire limits** (size your buffers to these, they are enforced):

| Limit | Value |
|---|---|
| Max request body | **32 KB** → `413` |
| Max readings per telemetry batch | 64 → `413` |
| Max metric keys per reading | 16 |
| Max events per batch | 32 |
| Max acks per request | 32 |
| Max sensors per topology snapshot | 256 |
| Max commands per heartbeat response | 10 |
| `metric_key` / `event_type` | ≤64 chars, `[a-z0-9_]` |
| `device_token` | ≤128 chars, `[A-Za-z0-9._-]`, opaque — never parse it |

Realistic worst-case telemetry body is ~24 KB (64 readings × 16 metrics);
typical is ~8 KB. Peak JSON heap for a batch is about 8 KB — build the JSON at
send time from a packed binary buffer, one batch at a time.

---

## 6. Bootstrap, end to end

Copy-pasteable and verified against the live server.

### 6.1 `POST /v1/provision`

```json
{
  "hub_serial": "CMH-DEV00001",
  "factory_secret": "7bd90a0449246207b6142522470a41b9268328070637ce20876685bbc3030a37",
  "hardware_model": "chickmark-hub-v1",
  "firmware_version": "1.4.2",
  "mac_wifi": "3C:71:BF:12:9A:04",
  "boot_count": 1
}
```

`200`:

```json
{
  "hub_id": "77e7eac8-1fc4-47ec-90d9-26d959026e10",
  "device_secret": "<64 lowercase hex chars>",
  "secret_expires_at": 1802702000,
  "config_version": 3,
  "heartbeat_interval_s": 60,
  "telemetry_interval_s": 300,
  "espnow_pmk_rotated": false,
  "server_time": 1787150010
}
```

`espnow_pmk_rotated` is `true` only on a hub's **first** provisioning.
Re-provisioning deliberately **keeps** the existing ESP-NOW key, so recovering a
hub does not de-pair the sensor nodes around it. If you ever see `true` on a hub
that already had paired nodes, those nodes need re-pairing.

Persist `hub_id` and `device_secret` to NVS **before doing anything else**. The
secret is returned exactly once. A power cut between the response and the NVS
commit means calling `/v1/provision` again, which is safe.

Statuses: `400` malformed · `401 INVALID_FACTORY_SECRET` (retry every 15 min,
fault LED) · `404 UNKNOWN_SERIAL` (manufacturing problem, retry every 15 min) ·
`409 DEVICE_NOT_CLAIMED` (**normal**, retry every 60 s) · `429` · `5xx`.

### 6.2 `POST /v1/auth/token`

```json
{
  "hub_id": "77e7eac8-1fc4-47ec-90d9-26d959026e10",
  "device_secret": "<the 64 hex chars from provision>"
}
```

`200`:

```json
{
  "device_token": "v1.<64 hex chars>",
  "expires_in": 86400,
  "expires_at": 1787236410,
  "rotate_secret": false,
  "server_time": 1787150010
}
```

Cache in RAM. Refresh when under 10 % of `expires_in` remains, or immediately on
a `401`. If `rotate_secret` is `true`, call `/v1/provision` at the next quiet
moment — it is a hint, not an emergency.

Statuses: `401 INVALID_DEVICE_SECRET` → re-provision · `403 DEVICE_REVOKED` →
stop, retry hourly, **keep your credentials** · `404 UNKNOWN_HUB` →
re-provision · `409 SECRET_ROTATION_REQUIRED` → re-provision then retry.

### 6.3 The auth failure ladder — implement exactly this

1. Any endpoint returns `401` → call `/v1/auth/token`, retry the request once.
2. That retry also `401`s → `/v1/provision`, then `/v1/auth/token`, then retry once more.
3. Still failing → back off to a **15 min** cycle and light the fault LED.

**Never loop faster than this on an auth failure.** It is the only loop that can
otherwise run away.

---

## 7. Telemetry

`POST /v1/telemetry`

```json
{
  "batch_id": "CMH-DEV00001-000000000417",
  "sent_at": 1787150020,
  "readings": [
    {
      "sensor_uid": "A4CF12B93D07",
      "measured_at": 1787150000,
      "metrics": { "temperature_c": 27.4, "humidity_rh": 61.2, "co2_ppm": 1240 },
      "battery_percent": 87,
      "rssi": -68
    },
    {
      "sensor_uid": "7C9E44A10B22",
      "measured_at": 1787149990,
      "metrics": { "temperature_c": 37.6 },
      "t_est": true
    }
  ]
}
```

- `batch_id` = `<hub_serial>-<seq>`, `seq` as **exactly 12 zero-padded decimal
  digits**. Monotonic; gaps are fine.
- `sensor_uid` = ESP-NOW MAC, **12 uppercase hex chars, no separators**.
- `measured_at` = when the **sensor** measured, not when the hub received.
- `t_est: true` only when the timestamp came from uptime because the clock was
  not yet synced. Omit otherwise.

`202`:

```json
{
  "batch_id": "CMH-DEV00001-000000000417",
  "accepted": 2,
  "duplicates": 0,
  "rejected": [],
  "flagged": [],
  "config_version": 3,
  "commands_pending": false,
  "server_time": 1787150021
}
```

**`202` means durably written. Delete the batch from your queue — always,
including when `rejected` is non-empty.** There is no second confirmation step.

`rejected[]` entries carry `index`, `sensor_uid` and `reason`, one of
`UNKNOWN_SENSOR`, `SENSOR_NOT_ON_HUB`, `FUTURE_TIMESTAMP`, `STALE_TIMESTAMP`,
`NO_VALID_METRICS`, `MALFORMED_READING`. Treat the list as open — handle an
unrecognised reason as "dropped, log it locally", never as a batch failure.

`MALFORMED_READING` means the reading was structurally bad: a `measured_at` that
is not an integer, more than 16 metric keys, or a non-object entry.
`UNKNOWN_SENSOR` means the `sensor_uid` string itself was malformed (it is echoed
back so you can see what was sent) — an unrecognised-but-valid sensor is
auto-created instead, never rejected.

`flagged[]` is **informational — take no action on it.** An implausible value is
stored (marked `suspect`), not dropped, because a sensor reporting nonsense is
itself the signal an operator needs.

A replayed `batch_id` returns `202` with `"duplicate": true` and `accepted: 0`.
That is a **success** — the server already has the data.

Server-side time window: `measured_at` more than **300 s in the future** is
`FUTURE_TIMESTAMP`; more than **90 days old** is `STALE_TIMESTAMP`.

**Idempotency is two-layer:** on `(hub_id, batch_id)`, and again on
`(sensor_uid, measured_at)`. Re-sending an identical batch is always safe, and if
a `413` forces you to re-split readings across different `batch_id`s the second
layer still prevents duplicates. Metrics for the same instant are **merged**, not
overwritten.

**A sensor does not need to be registered first.** Send telemetry for a new
`sensor_uid` and the server creates it automatically in an `unassigned` state;
staff bind it to a room/machine in the app later. Nothing is lost.

Offline behaviour: default interval **300 s**, max batch **64**. On reconnect
send the **newest** batch first, then drain the backlog oldest-first, capped at
about 10 batches/minute so a week-old backlog does not starve live data.

---

## 8. Heartbeat — and how commands arrive

`POST /v1/heartbeat`, default every **60 s**. This is deliberately more frequent
than telemetry because **it is also the command channel**. It is the only polling
loop you need.

```json
{
  "sent_at": 1787150080,
  "firmware_version": "1.4.2",
  "uptime_s": 864210,
  "boot_count": 14,
  "reset_reason": "power_on",
  "free_heap_bytes": 118432,
  "min_free_heap_bytes": 91008,
  "fs_free_bytes": 3221225472,
  "wifi_rssi": -57,
  "wifi_ssid": "hatchery-ops",
  "ip_address": "10.20.4.31",
  "power_source": "mains",
  "sensors_known": 12,
  "sensors_online": 11,
  "queue_depth": 0,
  "queue_bytes": 0,
  "dropped_readings_total": 0,
  "last_upload_at": 1787150020,
  "last_upload_ok": true,
  "config_version": 3,
  "topology_hash": "8a41c9f2"
}
```

`200`:

```json
{
  "config_version": 3,
  "topology_stale": false,
  "next_heartbeat_s": 60,
  "commands": [
    {
      "command_id": "a0a38346-8569-40bf-9797-7b3de760a004",
      "command_type": "identify_sensor",
      "params": { "sensor_uid": "A4CF12B93D07", "duration_s": 30 },
      "created_at": 1787150075,
      "expires_at": 1787153675
    }
  ],
  "server_time": 1787150081
}
```

- **Honour `next_heartbeat_s`.** The server drops it to `10` while a command is
  waiting and returns to `60` when the queue drains. Clamp to 10–900 s and ignore
  anything outside that.
- If `config_version` differs from your stored value → call `GET /v1/config`
  **after** the current cycle. Do not block telemetry on it.
- If `topology_stale` is `true` → send a full `POST /v1/topology` snapshot.
- **Never queue heartbeats.** A heartbeat is a snapshot of *now*. If one fails,
  drop it and send a fresh one next interval.

### Acknowledging commands — `POST /v1/commands/ack`

```json
{
  "sent_at": 1787150090,
  "acks": [
    {
      "command_id": "a0a38346-8569-40bf-9797-7b3de760a004",
      "status": "succeeded",
      "completed_at": 1787150089,
      "result": { "blinked_ms": 30000 }
    }
  ]
}
```

`200`: `{ "acknowledged": 1, "unknown": [], "server_time": 1787150091 }`

`status` ∈ `received` | `succeeded` | `failed` | `unsupported` | `expired`.
On `failed`, add `error_code` and `error_message` (≤512 chars).

`completed_at` is stored **as you send it**, not as the time your message
arrived. That is what makes a successful reboot distinguishable from a crash, so
send it.

- `received` = accepted, will take a while. Send a terminal ack later.
- **Always ack an unrecognised `command_type` as `unsupported`** rather than
  ignoring it, or the server redelivers it until it expires.
- Acks are idempotent on `(command_id, status)`. A terminal status is never
  overwritten by a later non-terminal one, so re-sending is always safe.

**v1 command types:** `reboot`, `force_sync`, `refresh_config`,
`report_topology`, `identify_sensor`, `identify_hub`, `run_diagnostic`,
`start_calibration`, `pair_window_open`, `forget_sensor`, `check_firmware`,
`reprovision`. Closed set — nothing executes arbitrary code, and nothing ever
will.

**Replay protection is mandatory for every command, not just calibration.**
Persist `last_command_id` in NVS and refuse to execute the same `command_id`
twice. Two cases make this load-bearing:

- `start_calibration` — applying an offset twice doubles it.
- `reboot` — ack `received`, flush the ack, write `last_command_id` to NVS,
  *then* reboot, and ack `succeeded` after coming back up. If that first ack is
  lost in transit (exactly what a marginal farm link does — drops the outbound
  POST as the device resets) the server still has the command pending and
  redelivers it. Without the NVS guard that is a boot loop, not a hypothetical.

---

## 9. Config

`GET /v1/config`, with `If-None-Match: "<etag>"` if you have one.

`200`:

```json
{
  "config_version": 3,
  "etag": "W/\"cfg-3-77e7eac8\"",
  "config": {
    "measurement_interval_s": 60,
    "telemetry_interval_s": 300,
    "heartbeat_interval_s": 60,
    "max_batch_readings": 64,
    "topology_report_interval_s": 86400,
    "sensor_offline_after_s": 300,
    "enabled_metrics": ["temperature_c", "humidity_rh", "co2_ppm", "nh3_ppm"],
    "disabled_sensor_uids": [],
    "calibration": {},
    "ntp_servers": ["pool.ntp.org", "time.cloudflare.com"],
    "timezone": "UTC",
    "log_level": "info",
    "ota_channel": "stable",
    "ota_check_interval_s": 21600,
    "espnow_pmk": "<32 hex chars, per-hub>",
    "base_url": "https://kgucchapksiiqxmiutsz.supabase.co/functions/v1/iot-gateway"
  },
  "server_time": 1787150110
}
```

`304` with an empty body means your cached config is current.

- **The document is fully resolved and flat. The hub does no merging.**
- **Call it at boot, and only when a `config_version` you receive differs from
  your stored one. Never on a timer.**
- Apply what you understand, **ignore unknown keys** — new keys will appear
  without a version bump. If a *known* key is out of your supported range, clamp
  it, keep running, and emit a `config_clamped` event.
- Bump your stored `config_version` **only after** the config is applied and
  persisted. A crash mid-apply must re-fetch, not skip.
- `espnow_pmk` is a secret: NVS only, never logged, never in an event payload.
- `timezone` is informational. **All protocol timestamps stay UTC.**
- `base_url` needs the commit-on-success dance in §12.8 — test the new URL with
  `/v1/auth/token` before persisting it, and revert on failure. This is the one
  key that can permanently orphan a hub if applied blindly.
- **`espnow_channel` is deliberately not in the config.** Changing the radio
  channel from a server would strand every already-paired sleeping node. It is
  set at install time and lives in NVS.

---

## 10. Topology

`POST /v1/topology` — **full snapshot, not deltas.** Snapshots are self-healing;
the server diffs and raises sensor added/removed itself.

```json
{
  "sent_at": 1787150100,
  "topology_hash": "8a41c9f2",
  "hub": { "firmware_version": "1.4.2", "hardware_model": "chickmark-hub-v1", "radio": "esp-now", "channel": 6 },
  "sensors": [
    {
      "sensor_uid": "A4CF12B93D07",
      "model": "chickmark-node-th-v1",
      "firmware_version": "0.9.3",
      "capabilities": ["temperature_c", "humidity_rh"],
      "state": "online",
      "last_seen_at": 1787150080,
      "battery_percent": 87,
      "rssi": -68
    }
  ]
}
```

`200`: `{ "accepted": 1, "topology_hash": "8a41c9f2", "config_version": 3, "server_time": 1787150101 }`

Send it: on boot after first auth; whenever the sensor set changes; every 24 h;
and whenever a heartbeat says `topology_stale: true`. **Not more than once per
60 s**, even if nodes are flapping.

`state` ∈ `online` | `offline` | `pairing`. `topology_hash` is any stable hash
you compute over the sorted set — the algorithm is yours, the server only
compares it for equality.

**Do not call the server when a sensor packet arrives.** Local ESP-NOW receipt
needs no round trip. Keep reporting offline sensors — a missing sensor and an
offline sensor mean very different things to the customer. Drop one from the
snapshot only after `forget_sensor`.

---

## 11. Events

`POST /v1/events`. **Device-level conditions only.**

```json
{
  "sent_at": 1787150120,
  "events": [
    {
      "event_id": "CMH-DEV00001-e-000000000091",
      "event_type": "sensor_disconnected",
      "severity": "warning",
      "occurred_at": 1787150050,
      "sensor_uid": "7C9E44A10B22",
      "detail": { "last_seen_at": 1787146100, "missed_intervals": 65 }
    }
  ]
}
```

`202`: `{ "accepted": 1, "duplicates": 0, "rejected": [], "server_time": 1787150121 }`

Idempotent on `(hub_id, event_id)`. Use a **separate monotonic counter** from
`batch_seq`, with the `-e-` segment as shown, and **persist it eagerly** — event
dedup has only this one layer, and a counter that resets after a crash produces
colliding ids exactly when `queue_overflow` and `ota_failed` matter most.
(`batch_seq` is the opposite: persist it lazily, every 64 batches, and resume
from `persisted + 64`. A lost `batch_seq` degrades safely.)

Types: `hub_boot`, `hub_reboot_unexpected`, `sensor_discovered`, `sensor_paired`,
`sensor_disconnected`, `sensor_reconnected`, `sensor_low_battery`, `sensor_fault`,
`calibration_required`, `storage_low`, `queue_overflow`, `malformed_batch`,
`config_clamped`, `clock_unsynced`, `clock_stepped`, `ota_failed`,
`ota_rolled_back`, `network_degraded`. The list is open — an unknown type is
stored verbatim at severity `info`.

- **Events ride a separate queue from telemetry and are sent first when both are
  pending.** A hub that is failing must be able to say so even when its data
  backlog is huge.
- **`critical` events go immediately**, not on the next telemetry tick. `warning`
  and `info` ride the 60 s heartbeat cadence.
- **Deduplicate locally.** A flapping sensor must not generate 500
  `sensor_disconnected` events — emit once on state change, then at most hourly
  while the state persists.
- **Never put a secret in `detail`** — no `device_secret`, no `espnow_pmk`, no
  Wi-Fi password.

**What does NOT belong here:** anything about the poultry operation. Do not
implement "temperature exceeded the setter limit". Production thresholds are
evaluated server-side against each customer's benchmark data, which varies by
customer, breed and flock age. Send the reading; the server decides whether it is
alarming.

---

## 12. Errors

Every error looks like this:

```json
{
  "error": {
    "code": "DEVICE_UNAUTHORIZED",
    "message": "Device token is expired or unknown.",
    "retryable": false,
    "retry_after_s": null
  },
  "server_time": 1787150004
}
```

`retryable` means **"resending this exact request unchanged may succeed."** It is
`false` for anything needing a corrective action first, even though those flows
do end in a retry.

| HTTP | `code` | `retryable` | What you do |
|---|---|---|---|
| 400 | `BAD_REQUEST` | false | Drop the payload. Emit `malformed_batch`. Never retry. |
| 401 | `DEVICE_UNAUTHORIZED` | false | Auth ladder, §6.3. |
| 401 | `INVALID_FACTORY_SECRET` | false | Retry every 15 min. Fault LED. |
| 401 | `INVALID_DEVICE_SECRET` | false | `POST /v1/provision`. |
| 403 | `DEVICE_REVOKED` | false | Stop uploading. **Keep** queue and credentials. Retry hourly. Distinct LED. |
| 404 | `UNKNOWN_HUB` | false | `POST /v1/provision`, then retry. |
| 404 | `UNKNOWN_SERIAL` | false | Manufacturing problem. Retry every 15 min. |
| 404 | `NOT_FOUND` | false | Wrong path. Fix the firmware. |
| 405 | `METHOD_NOT_ALLOWED` | false | Wrong HTTP method. Deliberately not a `400`, so a misrouted request never makes you drop a batch. |
| 409 | `DEVICE_NOT_CLAIMED` | **true**, `retry_after_s: 60` | Normal pre-install state. Not an error. |
| 409 | `SECRET_ROTATION_REQUIRED` | false | `POST /v1/provision`, then retry. |
| 413 | `PAYLOAD_TOO_LARGE` | false | Halve batch size (floor 8), retry. Persist the new size. |
| 422 | `UNPROCESSABLE` | false | Drop, emit an event. |
| 429 | `RATE_LIMITED` | **true**, `retry_after_s` set | Sleep exactly `retry_after_s`. Add no backoff of your own. |
| 5xx | `SERVER_ERROR` | **true** | Exponential backoff + jitter, cap 300 s. **Keep the payload.** |
| — | network / TLS / DNS / timeout | n/a | Same as 5xx. |

For an **unknown** `code`, fall back to `retryable`, then to the HTTP status class.

**Rule of thumb:** 4xx other than 401/409/413/429 means the payload is the
problem — dropping it is correct. 5xx and network errors mean the server is the
problem — keeping it is correct.

`POST /v1/telemetry` and `POST /v1/events` never fail a whole batch because one
item is bad. They return `202` with a `rejected[]` array.

**Never wipe your credentials on a `403`.** A server-side mistake would otherwise
brick an entire fleet.

---

## 13. TLS

Use the **full ESP-IDF certificate bundle** (`esp_crt_bundle`, ~130 KB flash).

**Do not pin a leaf or intermediate certificate.** The base URL is expected to
move to a vanity domain and the chain will change with it; a pinned fleet would
go dark at that moment.

For the cold-boot clock problem see §7.1 of the contract. Short version: fit a
battery-backed RTC if you can (this is a BOM decision and it is the recommended
answer); otherwise try SNTP first with a 15 s timeout, and only if that fails
make the single bootstrap request with certificate **validity-period** checking
disabled while keeping chain and hostname validation fully enforced — then adopt
`server_time` and re-enable it.

---

## 14. Current limitations — read before planning your sprint

1. **OTA is not live.** `GET /v1/firmware` is deployed and always answers
   `{"update_available": false}`. Wire the call and the 6-hourly check now; the
   download/verify path cannot be tested end-to-end until we publish a signed
   artifact. When it lands, the signature is **Ed25519 over the 32 raw bytes of
   the artifact's SHA-256 digest** (`signature_alg: "ed25519-sha256"`), which is
   what makes verification streamable on an ESP32 — you never buffer the image.
   We will supply the public key and a worked sign-and-verify example with the
   first artifact.
2. **`target=sensor` firmware is contract-only.** Not required for v1.
3. **Sensor→hub link is out of scope of this API.** ESP-NOW pairing, the pair
   window, and the local protocol are yours; see §12.12 of the contract for the
   constraints the server assumes.
4. **Wi-Fi provisioning is yours** — SoftAP captive portal is the agreed
   approach, §12.0.5. It must exist before `/v1/provision` is reachable.
5. **Rate limiting is deliberately loose** (about 240 requests/minute per hub) and
   is a runaway-device brake, not something a healthy hub on its documented
   cadence will ever meet. Still honour `429` + `retry_after_s`.
6. **`GET /v1/commands` works but is discouraged.** The heartbeat already carries
   commands; polling both doubles your request rate for nothing. I would skip it
   in v1.
7. The two dev hubs point at a **test customer**. Data you send is visible in the
   app under that test tenant — treat it as throwaway.

---

## 15. Suggested integration order

1. `GET /v1/health` — URL, DNS, TLS, clock.
2. `POST /v1/provision` with `CMH-DEV00002` — confirm you handle `409` as a
   waiting state, not a fault.
3. `POST /v1/provision` with `CMH-DEV00001` → persist `hub_id` + `device_secret`.
4. `POST /v1/auth/token` → token caching and the refresh threshold.
5. `POST /v1/telemetry` with one hard-coded reading → confirm `202`.
6. Re-send the identical batch → confirm `duplicate: true`, and that your queue
   deletes it.
7. `POST /v1/heartbeat` on a 60 s loop → confirm you honour `next_heartbeat_s`.
8. `POST /v1/topology` on boot and on change.
9. `GET /v1/config` on boot and on `config_version` change, with `If-None-Match`.
10. `POST /v1/events` for `hub_boot`, then a real `sensor_disconnected`.
11. The auth ladder: deliberately corrupt your token and confirm you recover
    without a tight loop.
12. Offline: pull the network for an hour, confirm the backlog drains
    newest-first with no duplicates and original timestamps preserved.

Ask me to queue a command against your hub whenever you want to exercise the
command path — I can push a `identify_hub` or `run_diagnostic` on request, and
you should see it on the next heartbeat with `next_heartbeat_s` dropping to 10.
