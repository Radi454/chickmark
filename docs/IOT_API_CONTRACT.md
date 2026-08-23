# ChickMark IoT Platform — Architecture & Firmware Contract

Status: **design, not yet implemented.** Nothing in this document exists in the
codebase today. It is the agreed target so firmware and backend can be built in
parallel.

Audience: backend team (sections 1-11), firmware engineer (section 12 onward —
that section is self-contained and can be sent on its own).

---

## 0. Decisions at a glance

| Question | Decision | Why |
|---|---|---|
| Where does the API live? | **Supabase Edge Function** `iot-gateway`, deployed `--no-verify-jwt`, internally path-routed | Deploy path, secrets, Postgres proximity and a `--no-verify-jwt` shared-secret precedent all already exist. No new infrastructure. |
| Cloud Run? | **Not for v1.** Reserved for a future MQTT bridge | Cloud Run is already used for `pip-realtime-sideband`, but only because that needs sticky WebSockets. Plain HTTPS ingest does not. |
| Device auth | **Long-lived device secret → short-lived bearer token** | Simple for ESP32 (plain TLS POST, no request signing), instant revocation, 24 h blast radius. |
| Request signing (HMAC) | **No** | TLS already protects the wire. Canonicalisation bugs are the single biggest source of firmware integration pain. Not worth it here. |
| mTLS / client certs | **No** | ESP32 can do it; the PKI operations burden on a small team cannot. |
| Timestamps on the wire | **Unix epoch seconds, integer, UTC** | No `strftime` on device, no timezone class of bugs, smaller payload. |
| Sensor identity on the wire | **Hardware `sensor_uid`** (ESP-NOW MAC), never a server-assigned id | Hub stores nothing it has to keep in sync with the server. |
| Server → Hub commands | **Piggy-backed on the heartbeat response** | Zero extra requests, no persistent connection, ≤60 s latency. |
| MQTT / WebSocket | **Not for v1**, migration path documented | Both need new infra plus a second auth system. The command table is transport-agnostic. |
| Telemetry storage | **Raw partitioned table + hourly/daily rollups** | Rollups match the shape the dashboard already consumes (`govee_daily_captures`). |
| Threshold evaluation | **Server-side only** | Matches how ChickMark already works — all severity logic lives outside the sensor. |
| Tenant on the wire | **Never sent by the device** | Server resolves `customer_id` from the hub registration. Cross-tenant leakage becomes structurally impossible. |
| API versioning | `/v1/` in the path; **base URL is device configuration** | The host can move to a vanity domain later with zero firmware change. |

---

## 1. What already exists

Findings from reading the live database, all 39 migrations, every Edge Function
and the Flutter sensor surface.

### 1.1 Tenancy

The tenant root is **`public.customers`**, keyed by `id text` (app-generated
string UUID stored as `text`, not a Postgres `uuid`). Every tenant-owned table
carries a denormalised `customer_id text references public.customers(id) on
delete cascade` — even when the parent chain could derive it.

`public.organizations` is **not** a tenant root above `customers`. It is a 1:1
named wrapper around exactly one customer row that exists so several employee
`profiles` can self-register against that customer using an 8-character join
code. No data-table RLS policy anywhere references `organization_id`.

Physical hierarchy in the **cloud** stops at:

```
customers ──&gt; hatcheries
```

`farms`, `houses` and `flock_placements` exist **only in local SQLite** and have
never been mirrored to Postgres. An IoT design must not depend on them.

Below `hatcheries`, physical location is expressed as three free-text labels
already used by `govee_daily_captures`:

- `station_key` — `egg` | `chicks` | `setters` | `hatchers`
- `place` — `outsideHatchery`, `eggStorageRoom`, `chickHoldingArea`,
  `setterRoom`, `insideSetter`, `hatcherRoom`, `insideHatcher`
- `machine_id` — free text, e.g. `S1`, `H2`. **There is no machine table.**

### 1.2 Authorisation

RLS helpers live in the locked-down `chickmark_private` schema, all
`security definer` with `set search_path = ''`:

```
chickmark_private.app_role() / app_status() / app_customer_id()
chickmark_private.app_is_admin() / app_is_staff()
chickmark_private.app_can_read_customer(cid text)
chickmark_private.app_can_write_customer(cid text)
```

The universal policy idiom, applied to every tenant table:

```sql
create policy foo_select on public.foo for select to authenticated
  using (chickmark_private.app_can_read_customer(customer_id));
create policy foo_write on public.foo for all to authenticated
  using (chickmark_private.app_can_write_customer(customer_id))
  with check (chickmark_private.app_can_write_customer(customer_id));
```

Policies are scoped `to authenticated` only. `anon` is hard-revoked from all
tables, sequences and functions, including via `alter default privileges` so the
revoke applies to future objects. Read access requires
`profiles.status = 'approved'`.

### 1.3 Edge Function conventions

- One flat Deno module per function. No framework, no router.
- Testable core `handleXRequest(request, deps)` + wiring `serveX(request)` +
  `if (import.meta.main) Deno.serve(serveX)`.
- Dispatch is on a `body.action` string, because one Supabase function is one
  route. (This design uses path routing instead — see §4.2.)
- Errors are `{ error, code }` with short `snake_case` codes.
- Admin client is always
  `createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } })`.
- **Precedent for device-style auth already exists**: `pip-realtime-tool-broker`
  is deployed `--no-verify-jwt` and authenticates a constant-time shared secret
  in the `x-pip-broker-secret` header, failing closed when the secret is
  unconfigured. `telegram-hatchery-agent` does the same with
  `X-Telegram-Bot-Api-Secret-Token` (though with a non-constant-time compare).
- Idempotency precedent exists: `app-hatchery-agent` namespaces a client-supplied
  id into `app:<clientMessageId>`, stores it on a uniquely-indexed column, and
  replays the stored result on a repeat — catching the unique-violation race
  and re-reading the winning row.

### 1.4 Existing sensor surface

Exactly one device-shaped table exists: **`public.govee_daily_captures`**. It is
a pre-aggregated **daily summary**, not a time series:

```
id, customer_id, hatchery_id, station_key, place, machine_id, capture_date,
started_at, ended_at, device_id, device_name, status,
temp_avg/min/max/sd/cv_pct, rh_avg/min/max/sd/cv_pct,
reading_count, chart_points_json, created_at, updated_at
```

All individual readings are compressed into `chart_points_json` on the parent
row. There is no per-reading table and no device registry — device identity
lives inline on each capture.

Crucially, **the whole Govee path is client-side**: the Flutter app talks BLE
directly to the sensor (`lib/services/govee/govee_service.dart`), writes rows to
local SQLite, and those rows reach Postgres through the ordinary sync push. **No
backend endpoint receives sensor data today.**

### 1.5 Existing alerting

All threshold evaluation is client-side Dart, at render time:

- `ScopeSeverity { pool, good, warn, err }` — `lib/features/dashboard/scope/scope_models.dart:6`
- `severityFor()` grades against a BMK benchmark, or against
  `ScopeParam.absoluteLimit` when there is none — `scope_severity.dart:36`
- Govee bands are hardcoded per place in `_GoveeTarget` —
  `govee_triage_builder.dart:13`
- `AlarmTriageFeed` renders `err` → Critical, `warn` → Watch, `good` → collapsed

There is no server-side rule engine and no push-alerting path.

### 1.6 Infrastructure

- **Cloud Run is already in use**: `services/pip-realtime-sideband` (Deno,
  `gcloud run deploy`, `--min-instances=1`, session affinity, Cloud Scheduler
  hitting `/internal/cleanup`). Precedent exists, but it is there specifically
  because it holds stateful WebSockets.
- **No CI.** No `.github/`. Deploys are manual `supabase functions deploy` and
  `gcloud run deploy`.
- A pre-commit hook runs `scripts/check_supabase_secrets.sh` to block key leaks.
- `scripts/test_supabase_security_hardening.sh` replays every migration against a
  scratch Postgres and asserts RLS invariants — any new migration must pass it.
- Extensions: `pgcrypto` and `uuid-ossp` installed. `pg_cron`, `pg_net`,
  `pg_partman` available but **not** installed.
- No table partitioning and no retention DDL anywhere in the schema today.

---

## 2. Gaps

| # | Gap |
|---|---|
| G1 | No server-side ingestion endpoint of any kind. |
| G2 | No device registry, no device identity, no device credentials. |
| G3 | No raw time-series storage; the only sensor table is a daily summary blob. |
| G4 | No server-side threshold evaluation, so no alerting without an app in the foreground. |
| G5 | No machine/room entity in the cloud — only free-text labels. |
| G6 | No partitioning, no retention, no rollup jobs, and `pg_cron` is not enabled. |
| G7 | No non-user authentication principal. Every RLS predicate assumes `auth.uid()` maps to a `profiles` row. |
| G8 | No command/config/OTA concept anywhere in the product. |

G7 is the important one. It forces a decision: a device is **not** a Supabase
auth user, and must never be one. See §4.3.

---

## 3. Threat model at the device boundary

Assume the Hub is physically accessible to farm staff, contractors and thieves,
that its flash can be dumped, and that farm Wi-Fi is shared and hostile.

| # | Threat | Control |
|---|---|---|
| T1 | Flash dump yields credentials → attacker impersonates a hub | Secret is per-device and only mints 24 h tokens. Instant server-side revoke. Recommend ESP32 flash encryption + NVS encryption on production units. |
| T2 | Attacker writes telemetry into another tenant | Device never transmits `customer_id`. Server derives it from the hub row. Structurally impossible. |
| T3 | Hub reports readings for sensors it does not own | Server rejects `sensor_uid`s not bound to that hub, per reading, and raises an event. |
| T4 | Replay of a captured batch | `(hub_id, batch_id)` unique + `(sensor_id, measured_at)` primary key with a merging upsert. Replay is a no-op; a re-split retry merges rather than losing data. |
| T5 | Forged future/past timestamps to poison charts | Server clamps: reject `measured_at` &gt; 5 min in the future or &gt; 90 days in the past. |
| T6 | Garbage values from a failing sensor | Range-checked against `iot_metric_registry`; stored but flagged `quality='suspect'` rather than dropped — a broken sensor is itself signal. |
| T7 | Volumetric abuse / runaway firmware loop | Per-hub rate limits, batch size caps, `413` and `429` with `retry_after_s`. |
| T8 | Service-role key extraction from a device | The key never leaves the Edge Function. Devices hold only a device secret. |
| T9 | Malicious/forged OTA image | Ed25519 signature verified on-device against a public key compiled into firmware. Unsigned images are never accepted. |
| T10 | Command injection → remote code execution | Commands are a **closed enum**. There is no "run this" command. Unknown command types are acked as `unsupported`. |
| T11 | Rogue ESP-NOW sensor from a neighbouring site | ESP-NOW uses a per-hub encryption key delivered in server config; hub only accepts sensors added during an explicit pairing window. |
| T12 | Stolen hub keeps reporting from an unknown location | Revoke marks the hub `revoked`; all endpoints return `403 DEVICE_REVOKED`. |
| T13 | Attacker floods provisioning with guessed serials | `factory_secret` is 32 random bytes, compared constant-time; provisioning is rate-limited per serial and per IP. |

---

## 4. Architecture decisions

### 4.1 Placement — Supabase Edge Function, not Cloud Run

Choose **one new Edge Function, `iot-gateway`**, deployed `--no-verify-jwt`.

Reasons:

1. Every dependency is already there — deploy tooling, secret management,
   service-role client idiom, Deno test harness.
2. It sits next to Postgres. Cloud Run would add a network hop plus egress cost
   for what is a pure write path.
3. The `--no-verify-jwt` + shared-secret pattern is already proven in production
   by `pip-realtime-tool-broker`.
4. HTTPS request/response is all v1 needs. Nothing here requires a persistent
   connection, which is the only thing Cloud Run buys over Edge Functions.

**When to revisit:** if per-hub message rate rises above roughly 1 message every
10 s, or the fleet exceeds a few thousand hubs, or sub-second command latency
becomes a product requirement. At that point add an MQTT broker fronted by a
Cloud Run bridge that writes through the *same* internal ingest module. HTTP
firmware keeps working unchanged.

### 4.2 One function, path-routed

Supabase serves anything under `/functions/v1/iot-gateway/**` to the same
function, so the sub-path is available on `new URL(request.url).pathname`. Use
it. One function means one deploy, one auth middleware, one cold start and one
set of shared helpers — instead of ten near-identical functions.

This deviates from the repo's `body.action` idiom deliberately: a REST path
surface is what a firmware engineer expects, is trivially inspectable with
`curl`, and keeps the version in the URL where the contract belongs.

**Base URL is device configuration, not contract.** Firmware stores a
`base_url` string in NVS. Today:

```
https://<project-ref>.supabase.co/functions/v1/iot-gateway
```

Later this can become `https://iot.chickmark.app/api` with no firmware change.
Every path in §12 is relative to that base.

### 4.3 A device is not a Supabase auth user

Devices get their own principal, resolved inside the Edge Function, never in
`auth.users`. All device writes happen through the service-role client with
`customer_id` injected server-side from the hub row.

Consequence: **RLS is not the control for device writes** — the Edge Function
is. RLS remains the control for everything the app and staff read. Device-facing
credential tables get RLS enabled with **no policies at all**, so only
`service_role` can touch them.

### 4.4 App-side operations reuse existing patterns

The app does not need a second Edge Function. Claiming a hub is a
`security definer` RPC in the style of the existing org RPCs; everything else
(listing hubs, binding a sensor to a place, queueing a command, editing config)
is an ordinary RLS-protected table operation through PostgREST.

---

## 5. Identity and provisioning

### 5.1 Identifiers

| Identifier | Who mints it | Lives where | Format |
|---|---|---|---|
| `hub_serial` | Manufacturing | Printed on the case + QR, burned into NVS | `CMH-<8 hex>` e.g. `CMH-4F2A9C01` |
| `factory_secret` | Manufacturing | Hub NVS only; **hash** in the backend | 32 random bytes as **64 lowercase hex chars** |
| `claim_code` | Manufacturing | Printed on the QR; **hash** in the backend. Never on the device. | **16 chars** from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` |
| `hub_id` | Backend at provisioning | Hub NVS after provisioning | UUID, canonical lowercase 36-char form |
| `device_secret` | Backend at provisioning | Hub NVS; **hash** in the backend | 32 random bytes as **64 lowercase hex chars** |
| `device_token` | Backend at each token exchange | Hub RAM (may be cached in NVS) | **opaque string**, ≤128 chars, `[A-Za-z0-9._-]` only. The device never decodes it. 24 h TTL. |
| `sensor_uid` | Sensor hardware | Sensor + reported by hub | ESP-NOW MAC as **12 uppercase hex chars**, no separators, e.g. `A4CF12B93D07` |
| `sensor_id` | Backend on first sight | Server only — **never sent to the hub** | UUID |
| `customer_id` | Existing ChickMark data | Server only — **never sent to the hub** | `text` |

The hub therefore stores exactly four things: `base_url`, `hub_serial`,
`factory_secret`, and (after provisioning) `hub_id` + `device_secret`.

**Encoding is hex, not base64url, on purpose.** Hex has a fixed 2:1 ratio, no
padding, no alphabet variants, and encode/decode is a dozen lines of C. base64url
saves 25 % of a field that is sent a handful of times per day — not a trade worth
one ambiguity bug.

### 5.2 Provisioning flow

```
Manufacturing
  └─ generates (hub_serial, factory_secret)
     ├─ burns both into hub NVS, prints hub_serial + claim QR on the case
     └─ uploads (hub_serial, sha256(factory_secret), hardware_model) to
        iot_hub_registry   ← operator-only, service-role, never customer-visible

Installation
  1. Installer powers the Hub. It has no hub_id yet, so it calls
     POST /v1/provision every 60 s and receives 409 DEVICE_NOT_CLAIMED.
  2. Installer, signed into the ChickMark app as an approved staff user,
     scans the QR and picks customer + hatchery.
     App calls RPC public.iot_claim_hub(serial, claim_code, hatchery_id).
     The RPC writes an iot_hubs row bound to the caller's customer_id.
  3. Hub's next POST /v1/provision succeeds and returns {hub_id, device_secret}.
     The Hub persists both and moves to normal operation.
```

Three properties worth stating explicitly:

- **No secret is ever embedded in the mobile app.** The app sends a claim; it
  never sees or carries a device credential.
- **A claim alone is not enough to impersonate a hub.** The attacker would also
  need the `factory_secret`, which is only in the device's flash.
- **The `factory_secret` alone is not enough either.** An unclaimed serial gets
  `409` forever, so a stolen-in-transit hub is inert until someone with an
  approved ChickMark account claims it.

`claim_code` is a second value on the same QR, distinct from `factory_secret`.
It exists so the app can prove physical presence without ever handling the real
device credential.

**It must be 16 characters** from the 32-symbol alphabet already used by
`generate_organization_code()` (uppercase alphanumerics excluding `I`, `O`, `0`,
`1`) — roughly 80 bits. It is scanned from a QR and never typed, so length costs
nothing, and the claim RPC is reachable directly through PostgREST where none of
the gateway's per-hub rate limits apply. See §9.6.

### 5.3 Re-provisioning, rotation, revocation

- **Rotation (routine):** `POST /v1/auth/token` may return
  `rotate_secret: true`. The hub then calls `POST /v1/provision` again with its
  `factory_secret`; the server issues a fresh `device_secret` and marks the old
  one dead. Recommended cadence: every 180 days, and unconditionally after a
  firmware update that changes the credential store.
- **Re-provisioning (recovery):** triggered by `404 UNKNOWN_HUB` or by a
  `reprovision` command. Same call, same `factory_secret`. This is why the
  `factory_secret` must survive on the device permanently.
- **Revocation (lost/stolen):** staff mark the hub revoked in the app. Every
  endpoint immediately returns `403 DEVICE_REVOKED` and all live tokens are
  killed. The hub **must not** wipe its own credentials on `403` — a server-side
  mistake would otherwise brick a fleet. It stops uploading, keeps its queued
  data, retries hourly, and shows a distinct LED pattern.
- **Un-revoking** is a staff action and requires re-claiming.

---

## 6. Authentication

Two tiers.

**Tier 1 — device secret.** Used only against `POST /v1/auth/token`. Long-lived,
never sent to any other endpoint.

**Tier 2 — device token.** `Authorization: Bearer <device_token>` on every other
endpoint. Opaque, 24 h TTL, stored server-side as a SHA-256 hash.

Why not a single static API key: a leaked static key is valid until someone
notices. Why not signed requests: TLS already protects the wire, and HMAC
canonicalisation is the classic source of firmware/backend disagreement — the
constraint here is *keep firmware logic simple*. Why not mTLS: the PKI operations
burden is disproportionate.

**Storage on device.** `device_secret` and `hub_id` in NVS. For production
hardware, enable ESP32 flash encryption and NVS encryption; without them a flash
dump yields the secret. This is a hardware-configuration requirement, not a
protocol one.

**Token handling in firmware.** Fetch on boot; refresh when
`expires_in` is within 10 % of running out, or immediately on a `401`. On a
second consecutive `401` after a successful refresh, fall back to
`POST /v1/provision`. Never retry a `401` in a tight loop.

---

## 7. Time

All wire timestamps are **integer Unix epoch seconds, UTC**. No strings, no
offsets, no local time anywhere in the protocol. The `place`/site timezone is a
presentation concern and lives in server config only.

**Every response body from every endpoint carries `server_time`.** That gives
the hub a free clock correction on every request and removes any hard dependency
on reaching an NTP server through a restrictive farm firewall.

### 7.1 The cold-boot bootstrap problem

TLS certificate validation checks the certificate's `notBefore` / `notAfter`
against the local clock. An ESP32 with no RTC boots with its clock near epoch 0,
so **the very first HTTPS connection fails cert validation, and the device can
never receive the `server_time` that was supposed to fix its clock.** This must
be resolved explicitly or firmware cannot be written.

Resolution, in priority order:

1. **Fit a battery-backed RTC (recommended, and a BOM decision).** A DS3231 or
   equivalent costs about a dollar and removes this entire failure class,
   including after a long power-off. This is the preferred answer.
2. **Without an RTC:** on boot, attempt SNTP first, with a 15 s timeout. SNTP is
   plain UDP/123 and needs no valid clock. If it succeeds, proceed normally.
3. **If SNTP fails** (a farm firewall blocking UDP/123 is common), make the
   bootstrap HTTPS request with certificate **time** validation disabled and
   chain/hostname validation still **fully enforced** — in ESP-IDF, keep the cert
   bundle and set `skip_cert_common_name_check = false`, disabling only the
   validity-period check. Adopt `server_time` from the response, step the clock,
   then re-enable time validation for every subsequent connection.

The residual risk in step 3 is bounded and worth stating plainly: an attacker
would need a certificate that chains to a real public CA for our exact hostname
and is merely expired or not-yet-valid. Signature and hostname checks still
apply. This is standard practice for RTC-less embedded devices and is why step 1
is the recommendation.

### 7.2 Firmware rules

1. On boot, start SNTP against the servers in config (default `pool.ntp.org`).
2. Regardless of SNTP, adopt `server_time` whenever
   `|server_time − local_time| > 60 s`, by stepping the clock.
3. Until the clock is valid, timestamp readings from the monotonic uptime
   counter and record the boot instant. On first sync, rewrite the buffered
   timestamps and set `"t_est": true` on each affected reading so the server
   knows they were derived.
4. With a battery-backed RTC, seed from the RTC at boot and treat it as valid;
   still correct from `server_time`.
5. Without an RTC and with no network at boot, readings taken before the first
   successful sync are uploaded with `"t_est": true`. The server stores them with
   `quality = 'estimated'` and the dashboard can visually distinguish them.
6. **Backward steps must never reuse a timestamp.** If the clock steps backward
   while readings are already queued, a new reading can otherwise land on a
   `measured_at` already used for that sensor — and the server's
   `on conflict do nothing` would silently discard a genuine reading as a
   duplicate. Keep a per-sensor `last_emitted_measured_at` in RAM. If a new
   reading would be `<=` it, emit `last_emitted_measured_at + 1` instead and set
   `"t_est": true`. Also emit a `clock_stepped` event recording the delta.

Server rules: reject individual readings whose `measured_at` is more than 300 s
in the future (`FUTURE_TIMESTAMP`) or more than 90 days in the past
(`STALE_TIMESTAMP`). Store both `measured_at` (device time) and `ingested_at`
(server `now()`) on every row — they are never conflated.

---

## 8. Offline-first behaviour

This is the section that matters most in a hatchery.

### 8.1 Local queue

- Persistent ring buffer on flash (LittleFS) or SD card. **Never** an in-RAM
  queue — a brown-out must not lose a day.
- Store readings **packed binary**, not JSON. JSON is built only at upload time,
  one batch at a time. This is the difference between a 24 h buffer and a 7 day
  buffer on the same flash.
- Sizing guidance, at 20 sensors × 6 metrics × 1 sample/min:
  - ≈ 7 200 readings/hour ≈ 173 k readings/day
  - at ~40 bytes packed ≈ **7 MB/day**
  - internal flash (1–4 MB free) ≈ **6–12 hours**
  - a 4 GB SD card ≈ **months**
  - **Recommendation: fit an SD card, or a dedicated ≥8 MB flash partition, if
    the site can be offline for more than a working day.**
- **Overflow policy: drop oldest.** Recent data is worth more than old data, and
  the operator needs to know: emit a `queue_overflow` event with the number of
  readings dropped, once per overflow episode — not once per reading.

### 8.2 Upload behaviour

- Default upload interval **300 s**. Each batch carries every reading buffered
  since the last success.
- **Max 64 readings per batch, max 32 KB body.** A 64-reading batch with three
  metrics each is roughly 8 KB; the worst case allowed by the caps (16 metrics
  each) is about 24 KB. Size the send buffer for 32 KB, not more.
- Deep backlog: drain FIFO, oldest first, one batch per HTTP request, up to
  10 batches per minute so a long backlog cannot starve the connection.
- **Recommended refinement:** on the first successful upload after a
  reconnection, send the *newest* batch first, then switch to FIFO. Dashboards go
  live immediately instead of after the backlog drains. One boolean of firmware
  state; well worth it.
- On any `2xx`, delete the batch from the queue — `accepted` and `duplicate`
  both mean the server has the data.

### 8.3 Retry and backoff

- Exponential: 1 s, 2 s, 4 s, 8 s … capped at **300 s**, with **±20 % jitter**.
  Jitter is not optional: a site-wide power restoration will otherwise bring
  every hub back in lockstep.
- `429` → honour `retry_after_s` exactly; do not apply your own backoff on top.
- `5xx`, TLS failure, DNS failure, timeout → back off and retry, keep the batch.
- `400` → **drop the batch** and emit a `malformed_batch` event. A payload the
  server cannot parse will never parse. Retrying it forever is how a fleet wedges.
- `413` → halve the batch size for this and subsequent uploads (floor 8), retry.
- `401` → refresh the token once, retry once.
- `403` → stop uploading, keep the queue, retry hourly.

### 8.4 Idempotency

Two independent layers, because they fail differently:

1. **Batch level.** Every batch carries `batch_id`, a monotonic counter stored in
   NVS, formatted `<hub_serial>-<seq>`. A unique index on `(hub_id, batch_id)`
   makes a whole-batch replay a no-op; the server replies `duplicate: true`.
2. **Reading level.** The primary key `(sensor_id, measured_at)` with a
   **merging** upsert (`metrics = metrics || excluded.metrics`, see §9.3). This
   catches the case where a retry re-splits the same readings across different
   batches — which happens whenever the batch size changes after a `413`. Merging
   rather than discarding matters: a re-split can deliver a partial metric set
   first, and a plain `do nothing` would silently drop the fuller row that
   follows while §8.5 tells the device to delete it.

The counter must survive reboot. If it is ever lost, the reading-level layer
still holds, so a reset counter degrades cleanly rather than duplicating data.

### 8.5 Acknowledgement semantics

`POST /v1/telemetry` returns `202` with counts and a per-reading rejection list.
A `202` means *durably written*, not *queued for later processing* — the server
commits before responding. The hub can therefore delete on `202` without any
second confirmation step.

---

## 9. Database model

New tables only. Everything reuses `customers`, `hatcheries` and the existing
`station_key` / `place` / `machine_id` labels.

Conventions followed: denormalised `customer_id text` on every tenant-facing
table, `idx_<table>_<purpose>` index naming, `text` + `CHECK` instead of native
enums, indexes on every FK column, `chickmark_private.app_can_*_customer()` in
every policy, policies `to authenticated` only.

Conventions deliberately **not** followed, with reasons:

- **`timestamptz`, not `text`, for time columns.** These tables are server-only
  and need real time arithmetic (token expiry, command expiry, partition bounds,
  rollup windows). This matches the precedent already set by the
  `agent_realtime_*` tables.
- **`uuid` primary keys.** These rows are minted by the server, never by an
  offline Flutter client, so there is no reason for the `text`-UUID convention.
- **Not registered in the Flutter sync layer.** The app reads IoT data live from
  Postgres, or via a rollup projection. Pushing a time series through the
  offline sync engine would be a mistake.

### 9.1 Registry and identity

Two rules govern this whole section, and both were learned the expensive way:

1. **A device credential never lives on a tenant-writable table.** RLS cannot
   restrict columns, so a table staff can `UPDATE` is a table where staff can
   overwrite a password hash.
2. **Every child row is tied to its hub by a composite foreign key**, not by a
   denormalised `customer_id` alone. Checking only `customer_id` lets a user who
   legitimately owns customer A attach a row to customer B's hub.

```sql
-- Operator-only. Never customer-visible.
create table public.iot_hub_registry (
  hub_serial           text primary key,
  factory_secret_hash  text not null,          -- sha256 hex of 32 random bytes
  claim_code_hash      text not null,          -- sha256 hex of the QR claim code
  hardware_model       text not null,
  manufactured_at      timestamptz not null default now(),
  claimed_at           timestamptz,
  claim_attempts       integer not null default 0,
  claim_locked_until   timestamptz,
  notes                text
);
alter table public.iot_hub_registry enable row level security;
alter table public.iot_hub_registry force  row level security;
revoke all on public.iot_hub_registry from anon, authenticated;

create table public.iot_hubs (
  id                 uuid primary key default gen_random_uuid(),
  hub_serial         text not null references public.iot_hub_registry(hub_serial),
  customer_id        text not null references public.customers(id) on delete cascade,
  hatchery_id        text references public.hatcheries(id) on delete set null,
  name               text not null default '',
  hardware_model     text not null,
  firmware_version   text,
  status             text not null default 'active'
                       check (status in ('active','revoked','retired')),
  config_version     integer not null default 1,
  topology_hash      text,
  last_seen_at       timestamptz,
  last_telemetry_at  timestamptz,
  claimed_by         uuid references public.profiles(id) on delete set null,
  claimed_at         timestamptz not null default now(),
  revoked_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  -- the anchor every child composite FK points at
  constraint iot_hubs_id_customer_uk unique (id, customer_id)
);
-- Serial is unique among LIVE hubs only, so a retired hub can be re-claimed.
create unique index idx_iot_hubs_serial_live
  on public.iot_hubs (hub_serial) where status <> 'retired';
create index idx_iot_hubs_customer on public.iot_hubs(customer_id, hatchery_id);
create index idx_iot_hubs_hatchery_fk on public.iot_hubs(hatchery_id) where hatchery_id is not null;

-- Credentials live OUT of the tenant table, in the locked-down private schema.
create table chickmark_private.iot_hub_secrets (
  hub_id             uuid primary key references public.iot_hubs(id) on delete cascade,
  device_secret_hash text,
  secret_rotated_at  timestamptz,
  updated_at         timestamptz not null default now()
);
alter table chickmark_private.iot_hub_secrets enable row level security;
alter table chickmark_private.iot_hub_secrets force  row level security;
revoke all on chickmark_private.iot_hub_secrets from anon, authenticated;

create table chickmark_private.iot_device_tokens (
  token_hash text primary key,
  hub_id     uuid not null references public.iot_hubs(id) on delete cascade,
  issued_at  timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz
);
alter table chickmark_private.iot_device_tokens enable row level security;
alter table chickmark_private.iot_device_tokens force  row level security;
revoke all on chickmark_private.iot_device_tokens from anon, authenticated;
create index idx_iot_device_tokens_hub on chickmark_private.iot_device_tokens(hub_id);
create index idx_iot_device_tokens_expiry
  on chickmark_private.iot_device_tokens(expires_at) where revoked_at is null;
```

`iot_hubs` is the only one of these that staff ever see, and even there the
**column** grants matter more than the policies, because RLS has no column
granularity:

```sql
revoke all on public.iot_hubs from authenticated;
grant select (id, hub_serial, customer_id, hatchery_id, name, hardware_model,
              firmware_version, status, config_version, topology_hash,
              last_seen_at, last_telemetry_at, claimed_by, claimed_at, revoked_at)
  on public.iot_hubs to authenticated;
grant update (name, hatchery_id, status) on public.iot_hubs to authenticated;
```

Without that `grant update (...)` narrowing, a staff user could flip a revoked
hub back to `active` by editing any column they liked — which is exactly the
revocation bypass §5.3 is meant to prevent.

### 9.2 Sensors and capabilities

```sql
create table public.iot_sensors (
  id               uuid primary key default gen_random_uuid(),
  hub_id           uuid not null,
  customer_id      text not null references public.customers(id) on delete cascade,
  sensor_uid       text not null,
  model            text,
  firmware_version text,
  capabilities     jsonb not null default '[]'::jsonb,  -- ["temperature_c","humidity_rh"]
  -- binding to the existing ChickMark physical vocabulary; set by staff in-app
  hatchery_id      text references public.hatcheries(id) on delete set null,
  station_key      text not null default '',
  place            text not null default '',
  machine_id       text not null default '',
  label            text not null default '',
  status           text not null default 'unassigned'
                     check (status in ('unassigned','active','offline','retired')),
  battery_percent  integer,
  last_rssi        integer,
  first_seen_at    timestamptz not null default now(),
  last_seen_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (hub_id, sensor_uid),
  constraint iot_sensors_id_customer_uk unique (id, customer_id),
  -- the composite FK: a sensor cannot be attached to another tenant's hub
  constraint iot_sensors_hub_customer_fk
    foreign key (hub_id, customer_id)
    references public.iot_hubs(id, customer_id) on delete cascade
);
create index idx_iot_sensors_customer on public.iot_sensors(customer_id, hatchery_id, station_key);
create index idx_iot_sensors_hub on public.iot_sensors(hub_id);

-- Canonical metric vocabulary. Adding a metric is a data insert, not a deploy.
create table public.iot_metric_registry (
  metric_key    text primary key,          -- 'temperature_c'
  unit          text not null,             -- 'degC'
  display_name  text not null,
  category      text not null,             -- 'climate' | 'gas' | 'airflow' | 'power' | ...
  min_plausible double precision,
  max_plausible double precision,
  is_active     boolean not null default true
);
alter table public.iot_metric_registry enable row level security;
create policy iot_metric_registry_read on public.iot_metric_registry
  for select to authenticated using (true);
create policy iot_metric_registry_admin_write on public.iot_metric_registry
  for all to authenticated
  using (chickmark_private.app_is_admin())
  with check (chickmark_private.app_is_admin());
```

The admin-only write policy is not decoration. Ingestion range-checks every
reading against `min_plausible` / `max_plausible`, so a tenant able to edit this
table could flag the entire fleet's data as suspect.

Seed vocabulary. The units are baked into the key name on purpose — ChickMark
already has real unit-ambiguity pain (°C for egg storage, °F for setters, °F for
Govee) and a self-describing key removes an entire class of bug:

```
temperature_c, humidity_rh, co2_ppm, nh3_ppm, pressure_pa, differential_pressure_pa,
air_velocity_mps, light_lux, water_flow_lpm, water_pressure_kpa,
battery_percent, power_w, door_state, vibration_g
```

**Unknown metric keys are stored, not rejected.** A key with no registry row
simply skips the range check and is written with `quality = 'ok'`. A new sensor
type can therefore ship and start recording before any backend deploy; only
charting it needs a registry row.

### 9.3 Telemetry

Raw, partitioned monthly, one row per (sensor, instant):

```sql
create table public.iot_telemetry (
  customer_id text not null,
  hub_id      uuid not null,
  sensor_id   uuid not null,
  measured_at timestamptz not null,
  ingested_at timestamptz not null default now(),
  batch_id    text not null,
  metrics     jsonb not null,      -- {"temperature_c":27.4,"humidity_rh":61.2}
  quality     text not null default 'ok'
                check (quality in ('ok','suspect','estimated')),
  battery_percent integer,
  rssi        integer,
  primary key (sensor_id, measured_at),
  constraint iot_telemetry_sensor_customer_fk
    foreign key (sensor_id, customer_id) references public.iot_sensors(id, customer_id)
) partition by range (measured_at);

create index idx_iot_telemetry_scope
  on public.iot_telemetry (customer_id, sensor_id, measured_at desc);
```

Three things about that DDL are deliberate:

- **There is no surrogate `id`.** The primary key *is* the dedup key. A synthetic
  `bigint identity` would add a sequence `nextval` to the hottest insert path and
  a second unique index to every partition, to support an access pattern nothing
  in this design ever uses.
- **The PK includes `measured_at`** because a primary key on a partitioned table
  must contain every partition key column.
- **The composite FK to `iot_sensors(id, customer_id)`** is what actually makes
  "a hub cannot write a row carrying another tenant's `customer_id`" true. Left
  to application code alone, that invariant holds only as long as every future
  handler remembers it.

Batch-level idempotency, in the private schema because the device-facing counter
is guessable (`<hub_serial>-<seq>`) and a tenant able to pre-insert rows there
could make a victim hub's real uploads answer `duplicate: true` — which, per
§8.5, makes the device delete them without them ever being stored:

```sql
create table chickmark_private.iot_telemetry_batches (
  hub_id      uuid not null references public.iot_hubs(id) on delete cascade,
  batch_id    text not null,
  received_at timestamptz not null default now(),
  reading_count integer not null,
  primary key (hub_id, batch_id)
);
alter table chickmark_private.iot_telemetry_batches enable row level security;
alter table chickmark_private.iot_telemetry_batches force row level security;
revoke all on chickmark_private.iot_telemetry_batches from anon, authenticated;
```

**Partitions need their own RLS.** This is the single easiest way to build a
silent cross-tenant leak: `CREATE TABLE ... PARTITION OF` does **not** inherit
`relrowsecurity` and does **not** copy the parent's policies, and a query that
names a partition directly is checked against that partition, not the parent. A
partition sitting in `public` with default grants is fully readable by any
logged-in user through PostgREST, while every query through the parent keeps
behaving perfectly. Create partitions with a helper that cannot forget:

```sql
create or replace function chickmark_private.iot_add_telemetry_partition(p_month date)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_name text := 'iot_telemetry_' || to_char(p_month, 'YYYY_MM');
begin
  execute format(
    'create table if not exists public.%I partition of public.iot_telemetry
       for values from (%L) to (%L)',
    v_name, p_month, (p_month + interval '1 month')::date);
  execute format('alter table public.%I enable row level security', v_name);
  execute format('alter table public.%I force  row level security', v_name);
  execute format('revoke all on public.%I from anon', v_name);
end $$;
```

Also create a **default partition**, so a missed maintenance run degrades to
"rows landed in the wrong place" instead of a fleet-wide ingest outage:

```sql
create table public.iot_telemetry_default partition of public.iot_telemetry default;
alter table public.iot_telemetry_default enable row level security;
alter table public.iot_telemetry_default force  row level security;
```

Caveat to carry into operations: while the default partition holds rows for a
range you later want to add, creating that range's partition fails until the
default is drained. Alert on a non-zero row count there.

**Insert semantics — merge, do not drop.** A naive
`on conflict do nothing` loses data: a retry that re-splits readings (which §8.3
guarantees whenever a `413` shrinks the batch) can deliver a *partial* metric set
first, and the fuller row that follows would be silently discarded while §8.5
tells the device to delete it. Merge instead:

```sql
insert into public.iot_telemetry (...) values (...)
on conflict (sensor_id, measured_at) do update
  set metrics = public.iot_telemetry.metrics || excluded.metrics
  where public.iot_telemetry.metrics
        is distinct from (public.iot_telemetry.metrics || excluded.metrics);
```

The `where` clause makes an exact replay a true no-op rather than a pointless
write.

Rollups — these are what the app and the AI agent actually read:

```sql
create table public.iot_telemetry_hourly (
  customer_id text not null,
  sensor_id   uuid not null references public.iot_sensors(id) on delete cascade,
  metric_key  text not null,
  bucket_start timestamptz not null,
  avg_value double precision, min_value double precision, max_value double precision,
  sd_value  double precision, cv_pct double precision,
  sample_count integer not null,
  primary key (sensor_id, metric_key, bucket_start)
);
create index idx_iot_telemetry_hourly_scope
  on public.iot_telemetry_hourly (customer_id, bucket_start desc);

create table public.iot_telemetry_daily (
  customer_id text not null,
  hatchery_id text,
  sensor_id   uuid not null references public.iot_sensors(id) on delete cascade,
  station_key text not null default '',
  place       text not null default '',
  machine_id  text not null default '',
  metric_key  text not null,
  day         date not null,
  avg_value double precision, min_value double precision, max_value double precision,
  sd_value  double precision, cv_pct double precision,
  sample_count integer not null,
  primary key (sensor_id, metric_key, day)
);
create index idx_iot_telemetry_daily_dashboard
  on public.iot_telemetry_daily (customer_id, hatchery_id, day desc, station_key);
```

`iot_telemetry_daily` deliberately mirrors the `govee_daily_captures` column
shape (`avg / min / max / sd / cv_pct` + scope labels) so the existing dashboard
widgets and triage builders can consume it with minimal change.

**Retention.** Raw: 90 days, enforced by dropping monthly partitions. Hourly:
13 months. Daily: indefinite — it is small and it is the audit record.

### 9.4 Events, commands, config, firmware

Note the composite FKs throughout. Every one of these tables is reachable by a
staff user's `INSERT`, so `customer_id` alone is not a sufficient check —
without the composite FK, a user with write scope on customer A can queue a
`reboot` against customer B's hub simply by supplying B's `hub_id` alongside
their own `customer_id`.

```sql
create table public.iot_device_events (
  id          uuid primary key default gen_random_uuid(),
  customer_id text not null references public.customers(id) on delete cascade,
  hub_id      uuid not null,
  sensor_id   uuid references public.iot_sensors(id) on delete set null,
  event_id    text not null,               -- device-supplied, for idempotency
  event_type  text not null,
  severity    text not null default 'info'
                check (severity in ('info','warning','critical')),
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  detail      jsonb not null default '{}'::jsonb,
  acknowledged_at timestamptz,
  acknowledged_by uuid references public.profiles(id) on delete set null,
  unique (hub_id, event_id),
  constraint iot_device_events_hub_customer_fk
    foreign key (hub_id, customer_id)
    references public.iot_hubs(id, customer_id) on delete cascade
);
create index idx_iot_device_events_scope
  on public.iot_device_events (customer_id, severity, occurred_at desc);

create table public.iot_commands (
  id           uuid primary key default gen_random_uuid(),
  customer_id  text not null references public.customers(id) on delete cascade,
  hub_id       uuid not null,
  command_type text not null,
  params       jsonb not null default '{}'::jsonb,
  status       text not null default 'pending'
                 check (status in ('pending','delivered','acked','succeeded','failed','expired','cancelled')),
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default (now() + interval '1 hour'),
  delivered_at timestamptz,
  acked_at     timestamptz,
  completed_at timestamptz,
  result       jsonb,
  error_code   text,
  error_message text,
  attempt_count integer not null default 0,
  constraint iot_commands_hub_customer_fk
    foreign key (hub_id, customer_id)
    references public.iot_hubs(id, customer_id) on delete cascade
);
create index idx_iot_commands_pending
  on public.iot_commands (hub_id, created_at)
  where status in ('pending','delivered');
create index idx_iot_commands_scope
  on public.iot_commands (customer_id, created_at desc);

create table public.iot_hub_config (
  hub_id      uuid primary key,
  customer_id text not null references public.customers(id) on delete cascade,
  version     integer not null default 1,
  doc         jsonb not null default '{}'::jsonb,
  updated_by  uuid references public.profiles(id) on delete set null,
  updated_at  timestamptz not null default now(),
  constraint iot_hub_config_hub_customer_fk
    foreign key (hub_id, customer_id)
    references public.iot_hubs(id, customer_id) on delete cascade
);

-- Fleet-wide defaults layer, resolved server-side. The hub only ever sees the
-- flattened result, never the layers. Service-role only: a 'global' row here
-- reconfigures every customer's hardware.
create table chickmark_private.iot_config_defaults (
  id             uuid primary key default gen_random_uuid(),
  scope_kind     text not null check (scope_kind in ('global','hardware_model','customer','hatchery')),
  scope_value    text,
  doc            jsonb not null default '{}'::jsonb,
  priority       integer not null default 0,
  updated_at     timestamptz not null default now(),
  check ((scope_kind = 'global') = (scope_value is null)),
  unique (scope_kind, scope_value)
);
alter table chickmark_private.iot_config_defaults enable row level security;
alter table chickmark_private.iot_config_defaults force row level security;
revoke all on chickmark_private.iot_config_defaults from anon, authenticated;

create table public.iot_firmware_releases (
  id              uuid primary key default gen_random_uuid(),
  hardware_model  text not null,
  target          text not null default 'hub' check (target in ('hub','sensor')),
  version         text not null,
  channel         text not null default 'stable' check (channel in ('dev','beta','stable')),
  storage_path    text not null,           -- Supabase Storage object path
  size_bytes      bigint not null,
  sha256          text not null,           -- hex, lowercase
  signature       text not null,           -- Ed25519 over the 32 raw sha256 bytes
  min_from_version text,
  rollout_percent integer not null default 0 check (rollout_percent between 0 and 100),
  is_active       boolean not null default false,
  release_notes   text,
  created_at      timestamptz not null default now(),
  unique (hardware_model, target, version, channel)
);
alter table public.iot_firmware_releases enable row level security;
alter table public.iot_firmware_releases force  row level security;
revoke all on public.iot_firmware_releases from anon, authenticated;

create table public.iot_firmware_updates (
  id          uuid primary key default gen_random_uuid(),
  customer_id text not null references public.customers(id) on delete cascade,
  hub_id      uuid not null,
  release_id  uuid not null references public.iot_firmware_releases(id) on delete cascade,
  target      text not null default 'hub',
  sensor_id   uuid references public.iot_sensors(id) on delete set null,
  status      text not null default 'offered'
                check (status in ('offered','downloading','verifying','applying','succeeded','failed','rolled_back')),
  from_version text,
  to_version   text not null,
  error_code   text,
  error_message text,
  offered_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint iot_firmware_updates_hub_customer_fk
    foreign key (hub_id, customer_id)
    references public.iot_hubs(id, customer_id) on delete cascade
);
create index idx_iot_firmware_updates_hub on public.iot_firmware_updates(hub_id, offered_at desc);
```

### 9.5 RLS

Complete table-by-table disposition. No table may be left off this list — three
of them were, in an earlier draft, and every one was a cross-tenant hole.

| Table | Schema | RLS | Policies for `authenticated` |
|---|---|---|---|
| `iot_hubs` | public | on | select + update **(column-granted, see §9.1)**. No insert, no delete. |
| `iot_sensors` | public | on | select + all-write, standard idiom |
| `iot_telemetry` (parent) | public | on + force | **select only** |
| `iot_telemetry_*` (each partition) | public | on + force | none needed — but RLS **must** be enabled per partition |
| `iot_telemetry_hourly` / `_daily` | public | on + force | **select only** |
| `iot_device_events` | public | on | select + all-write |
| `iot_commands` | public | on | select + all-write |
| `iot_hub_config` | public | on | select + all-write |
| `iot_firmware_updates` | public | on | **select only** |
| `iot_metric_registry` | public | on | select to all; write to admins (§9.2) |
| `iot_firmware_releases` | public | on + force | **none** — service role only |
| `iot_hub_registry` | public | on + force | **none** — service role only |
| `iot_hub_secrets` | chickmark_private | on + force | **none** — service role only |
| `iot_device_tokens` | chickmark_private | on + force | **none** — service role only |
| `iot_telemetry_batches` | chickmark_private | on + force | **none** — service role only |
| `iot_config_defaults` | chickmark_private | on + force | **none** — service role only |

The standard idiom, unchanged from the rest of the repo:

```sql
alter table public.iot_sensors enable row level security;
create policy iot_sensors_select on public.iot_sensors for select to authenticated
  using (chickmark_private.app_can_read_customer(customer_id));
create policy iot_sensors_write on public.iot_sensors for all to authenticated
  using (chickmark_private.app_can_write_customer(customer_id))
  with check (chickmark_private.app_can_write_customer(customer_id));
```

Four things worth stating explicitly, because each is a trap:

- **"RLS on, no policies" really does block `authenticated`.** Supabase's stock
  default privileges grant `authenticated` full DML on new `public` tables, and
  `0007_security_hardening.sql` revoked those defaults only from `anon`. RLS is
  therefore the only barrier — and it is default-deny, so zero policies means
  zero rows. Add `force row level security` anyway, because the table owner
  (`postgres`) otherwise bypasses RLS entirely, and `revoke all ... from
  authenticated` so the table does not even appear in the PostgREST schema.
- **Telemetry is select-only for users.** Only the gateway (service role) writes
  readings. There is no legitimate reason for a browser session to insert one.
- **`iot_hubs` has no insert and no delete policy.** Hubs are created by the
  claim RPC and retired by a status change, so a client can never conjure or
  destroy a hub row.
- **Do not name any new private helper `chickmark_private.app_*`.**
  `scripts/test_supabase_security_hardening.sh` asserts that exactly nine such
  functions exist; a tenth fails the build.

### 9.6 Claim RPC

```sql
create or replace function public.iot_claim_hub(
  p_hub_serial  text,
  p_claim_code  text,
  p_hatchery_id text,
  p_name        text default ''
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_customer_id text;
  v_reg         public.iot_hub_registry%rowtype;
  v_hub_id      uuid;
  v_code_hash   text;
begin
  -- Resolve the hatchery and the caller's authority over it in ONE branch, so a
  -- non-existent hatchery is indistinguishable from an unauthorised one.
  select h.customer_id into v_customer_id
    from public.hatcheries h where h.id = p_hatchery_id;
  if v_customer_id is null
     or not chickmark_private.app_can_write_customer(v_customer_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  -- Lock the registry row: makes check-then-insert atomic and serialises
  -- concurrent claims of the same serial behind one another.
  select * into v_reg from public.iot_hub_registry r
    where r.hub_serial = p_hub_serial for update;

  if v_reg.claim_locked_until is not null and v_reg.claim_locked_until > now() then
    raise exception 'claim_locked' using errcode = '55P03';
  end if;

  -- sha256/convert_to/encode are all pg_catalog, so they resolve under an empty
  -- search_path and need no extension. Do NOT use pgcrypto's digest() here:
  -- it lives in the extensions schema (unresolvable at search_path = '') and is
  -- absent from the migration-replay harness.
  v_code_hash := encode(sha256(convert_to(upper(trim(p_claim_code)), 'UTF8')), 'hex');

  -- One indistinguishable branch for "no such serial" and "wrong code", so this
  -- cannot be used as an oracle to enumerate serials.
  if v_reg.hub_serial is null or v_reg.claim_code_hash is distinct from v_code_hash then
    update public.iot_hub_registry
       set claim_attempts     = claim_attempts + 1,
           claim_locked_until = case when claim_attempts + 1 >= 5
                                     then now() + interval '15 minutes' end
     where hub_serial = p_hub_serial;
    raise exception 'invalid_claim' using errcode = '22023';
  end if;

  insert into public.iot_hubs (hub_serial, customer_id, hatchery_id, name,
                               hardware_model, claimed_by)
  values (p_hub_serial, v_customer_id, p_hatchery_id, coalesce(p_name, ''),
          v_reg.hardware_model, (select auth.uid()))
  returning id into v_hub_id;

  update public.iot_hub_registry
     set claimed_at = now(), claim_attempts = 0, claim_locked_until = null
   where hub_serial = p_hub_serial;

  insert into chickmark_private.iot_hub_secrets (hub_id) values (v_hub_id);
  insert into public.iot_hub_config (hub_id, customer_id) values (v_hub_id, v_customer_id);
  return v_hub_id;
exception
  when unique_violation then
    raise exception 'already_claimed' using errcode = '23505';
end $$;

revoke execute on function public.iot_claim_hub(text,text,text,text) from public, anon;
grant  execute on function public.iot_claim_hub(text,text,text,text) to authenticated;
```

**The claim code must be long.** This RPC is reachable directly through
PostgREST by any authenticated user, so none of the per-hub rate limits in the
gateway apply to it — the lockout counter above is the only throttle. And
`hub_serial` is `CMH-<8 hex>` minted sequentially, so it is guessable; the claim
code is carrying the whole weight. A 6-character code is not enough: it is
brute-forceable, and its unsalted hash is precomputable in full if the registry
table ever leaks.

Since the code is scanned from a QR and never typed, **length is free**. Use
**16 characters from the 32-symbol alphabet already used by
`generate_organization_code()`** (uppercase alphanumerics excluding `I`, `O`,
`0`, `1`) — about 80 bits, which retires the entire question.

## 10. Versioning and compatibility

Firmware in a hatchery may stay on one version for a year. The contract is built
around that.

**Rules the backend commits to:**

1. `/v1/` changes only for a breaking change. A breaking change is: removing a
   field, renaming a field, narrowing a type, tightening validation on an
   existing field, or changing the meaning of an existing value.
2. Adding a response field, adding an optional request field, adding an enum
   value in a field documented as open, and adding a metric key are all
   **non-breaking** and ship without a version bump.
3. When `/v2/` ships, `/v1/` stays live for a **minimum of 24 months** from the
   date the last `/v1/` hub is deployed.
4. Every response carries `server_time`; every response *may* carry
   `config_version` and `commands_pending`. Firmware must tolerate their absence.

**Rules firmware commits to:**

1. **Ignore unknown JSON fields.** Never fail a parse because a field appeared.
   This is the single most important compatibility rule in the document.
2. Never depend on field order or on absence of whitespace.
3. Treat an unknown `command_type` as `unsupported` and ack it — do not error, do
   not retry, do not ignore it silently (it would be redelivered forever).
4. Treat an unknown `error.code` by falling back to the `retryable` boolean and
   the HTTP status class.
5. Send `X-Device-Firmware: <version>` on every request so the server can apply
   per-version workarounds without a protocol change.

---

## 11. Error contract

```json
{
  "error": {
    "code": "DEVICE_UNAUTHORIZED",
    "message": "Device token is expired or unknown.",
    "retryable": false,
    "retry_after_s": null
  },
  "server_time": 1786000000
}
```

This nests the error object, unlike the flat `{ error, code }` used elsewhere in
the repo. That is intentional: firmware needs `retryable` as a machine-readable
field, and `SCREAMING_SNAKE` codes are visually distinct from the app-facing
`snake_case` ones. The device contract is versioned independently of the app API,
so the divergence costs nothing.

### 11.1 Firmware decision table

`retryable` means **"resending this exact request unchanged may succeed."** It is
`false` for every code that requires a corrective action first (refresh the token,
re-provision, shrink the batch) even though those flows do end in a retry. The
column below gives the literal value the server sends.

| HTTP | `code` | `retryable` | Firmware action |
|---|---|---|---|
| 400 | `BAD_REQUEST` | `false` | Drop the payload. Emit `malformed_batch`. Log locally. Never retry. |
| 401 | `DEVICE_UNAUTHORIZED` | `false` | Refresh token via `/v1/auth/token`, retry once. If that retry also returns 401 → `POST /v1/provision`, then retry. |
| 403 | `DEVICE_REVOKED` | `false` | Stop uploading. **Keep** the queue and credentials. Retry hourly. Distinct LED. |
| 404 | `UNKNOWN_HUB` | `false` | `hub_id` is not recognised. Run `POST /v1/provision`, then retry. |
| 404 | `NOT_FOUND` | `false` | No such endpoint. A firmware bug — fix the path. Never retry. |
| 405 | `METHOD_NOT_ALLOWED` | `false` | Wrong HTTP method. Deliberately **not** a `400`, so a misrouted or proxy-mangled request is not mistaken for a bad payload and does not cause you to drop a batch. |
| 409 | `DEVICE_NOT_CLAIMED` | `true`, `retry_after_s: 60` | Provisioning only. Normal state for a hub awaiting installation. Not an error condition. |
| 409 | `SECRET_ROTATION_REQUIRED` | `false` | Run `POST /v1/provision` to collect a new secret, then retry. |
| 413 | `PAYLOAD_TOO_LARGE` | `false` | Halve batch size (floor 8), retry with the smaller batch. Persist the reduced size. |
| 422 | `UNPROCESSABLE` | `false` | Structurally valid but semantically rejected. Drop, emit an event. |
| 429 | `RATE_LIMITED` | `true`, `retry_after_s` set | Sleep exactly `retry_after_s`. Do **not** add your own backoff. |
| 500 502 503 504 | `SERVER_ERROR`, `UPSTREAM_ERROR`, `SERVICE_UNAVAILABLE` | `true` | Exponential backoff + jitter, cap 300 s. Keep the payload. |
| — | network / TLS / DNS / timeout | n/a | Same as 5xx. |

For an **unknown** `code`, fall back to `retryable`, then to the HTTP status
class.

Rule of thumb for firmware: **4xx other than 401/409/413/429 means the payload is
the problem — dropping it is correct. 5xx and network errors mean the server is
the problem — keeping it is correct.**

### 11.2 Partial success is not an error

`POST /v1/telemetry` and `POST /v1/events` never fail the whole batch because one
item is bad. They return `202` with a `rejected[]` array. A hub that treated
per-item rejection as a batch failure would retry a poison reading forever.

---

# 12. Firmware Integration Contract v1

> **This section is self-contained. It can be sent to the firmware engineer on
> its own.** Everything above is backend rationale.

## 12.0 Quick start

**Base URL** is a configuration string stored in NVS. It will be supplied before
integration testing and has the shape:

```
https://<project-ref>.supabase.co/functions/v1/iot-gateway
```

Every path below is relative to it. `POST /v1/telemetry` means
`POST {base_url}/v1/telemetry`.

**Do not hard-code the host.** It will change when we move to a vanity domain,
and firmware must survive that with a config update rather than a reflash.

**Global rules**

| Rule | Value |
|---|---|
| Transport | HTTPS only, TLS 1.2+. Verify the server certificate — see §12.0.2 for the CA strategy. |
| Content type | `application/json; charset=utf-8` on every request with a body |
| Timestamps | Integer **Unix epoch seconds, UTC**. Never strings, never local time. |
| Auth | `Authorization: Bearer <device_token>` on everything except `/v1/provision` and `/v1/auth/token` |
| Unknown JSON fields | **Must be ignored.** New fields will appear without a version bump. |
| Every response | Contains `server_time` (epoch seconds). Use it to correct the clock. |
| No Supabase key | You do **not** send an `apikey` or `anon` header. There is no Supabase credential on the device. |

**Required request headers on every call**

```
Content-Type: application/json
X-Device-Firmware: 1.4.2          ; your firmware version
X-Device-Serial: CMH-4F2A9C01     ; hub serial, present even before provisioning
```

`X-Device-Firmware` is consumed: it lets the server apply per-version
workarounds without a protocol change, and it is what a staged OTA rollout keys
off. `X-Device-Serial` is used for diagnostics and log correlation, and it is the
only device identifier available on the pre-provisioning calls. Neither header is
a credential — never treat them as one.

### 12.0.1 What the Hub stores permanently (NVS)

```
base_url         string    set at manufacture; updatable via config (§12.8)
hub_serial       string    burned at manufacture
factory_secret   64 hex    burned at manufacture, NEVER erased
hub_id           uuid      written at provisioning
device_secret    64 hex    written at provisioning, rotatable
batch_seq        uint64    monotonic; best-effort persistence (see below)
event_seq        uint64    monotonic; persisted eagerly (see below)
config_version   int       last APPLIED config version
config_doc       blob      last applied config, for offline boot
last_command_id  uuid      last executed command, for replay protection
max_batch        int       current batch size, reduced by 413
espnow_channel   int       install-time radio channel
wifi creds       —         see §12.0.4
```

**`batch_seq` persistence — do not fsync every batch.** Writing a counter to NVS
on every upload is roughly 300 writes/day, which is real flash wear for no
benefit: §8.4 already establishes that a lost or reset `batch_seq` degrades
safely, because the reading-level dedup key still prevents duplicates. Persist
every 64 batches, and on boot resume from `persisted_value + 64`. That gaps the
sequence, which is fine — the server never assumes it is contiguous.

**`event_seq` persistence is different — persist it eagerly.** Event dedup has
only one layer, `(hub_id, event_id)`. A reset counter produces colliding
`event_id`s and the server will silently discard genuine events — precisely
during the unstable-boot conditions when `queue_overflow` and `ota_failed` matter
most. Events are rare (a handful per day), so eager persistence costs nothing.

Enable ESP32 flash encryption and NVS encryption on production units.

### 12.0.2 TLS

Use the **full ESP-IDF certificate bundle** (`esp_crt_bundle`, ~130 KB flash).

Do **not** pin a leaf or intermediate certificate. The base URL is expected to
move to a vanity domain, and the certificate chain will change with it; a pinned
fleet would go dark at that moment. The bundle survives it.

Time validation: see §7.1 for the one bounded exception during cold-boot
bootstrap.

### 12.0.3 Wire limits

Size buffers against these, not against imagination:

| Limit | Value |
|---|---|
| Max request body | **32 KB** |
| Max readings per telemetry batch | 64 |
| Max metric keys per reading | 16 |
| Realistic worst-case telemetry body | ~24 KB (64 × 16 metrics) |
| Typical telemetry body | ~8 KB (64 × 3 metrics) |
| Max events per batch | 32 |
| Max acks per request | 32 |
| Max sensors per topology snapshot | 256 |
| Max commands per heartbeat response | 10 |
| `metric_key`, `command_type`, `event_type` | ≤64 chars, `[a-z0-9_]` |
| `error_message`, `release_notes` | ≤512 chars |
| `detail`, `params`, `result` objects | ≤4 KB serialised |
| `device_token` | ≤128 chars |

Anything the server sends beyond a documented cap may be truncated by firmware
without it being an error. Anything the device sends beyond a cap gets `413`.

### 12.0.4 Heap budget

Indicative, for an ESP32 with ~200–250 KB usable heap after Wi-Fi init:

| Consumer | Approx. |
|---|---|
| mbedTLS session (one connection at a time) | 40–50 KB |
| HTTP client buffers | 8 KB |
| Outgoing JSON build buffer | 24 KB worst case, 8 KB typical |
| Incoming JSON parse (config is the largest response) | 8 KB |
| ESP-NOW peer table, 256 peers | ~10 KB |
| Ring-buffer working set | 8 KB |
| **Target free-heap floor** | **≥40 KB** |

Two rules that follow from this: **never hold two TLS connections open at once**,
and **stream the OTA image to flash rather than buffering it** (see §12.10).

### 12.0.5 Network provisioning (getting onto the farm Wi-Fi)

Out of protocol scope, but it must exist before `/v1/provision` is reachable, so
it is specified here rather than left implicit.

- **Primary: SoftAP captive portal.** On boot with no stored credentials, the hub
  raises an AP named `ChickMark-<hub_serial>` with a WPA2 password printed on the
  case. The installer connects, gets a captive-portal page, picks an SSID, enters
  the password. Credentials go to NVS. No app dependency, works on any phone or
  laptop, and works when the ChickMark app is not installed.
- **Fallback trigger:** hold the hub button for 10 s to clear credentials and
  return to AP mode. Also re-enter AP mode automatically after 15 consecutive
  minutes of failed association, so a changed farm Wi-Fi password is recoverable
  without a site visit by an engineer.
- **Ethernet, if the hardware has a port:** takes precedence over Wi-Fi when a
  link is up. Recommended for hatcheries with structured cabling — it removes the
  single most common support call.
- Store Wi-Fi credentials in encrypted NVS. Never log the password, never include
  it in an event `detail`, never expose it through the portal after it is set.

---

## 12.1 `POST /v1/provision`

**Purpose.** Exchange the factory credential for a hub identity and a device
secret. Called on first boot, and again for recovery (`404 UNKNOWN_HUB`) or
rotation (`409 SECRET_ROTATION_REQUIRED`).

**Authentication.** None (no bearer). The `factory_secret` in the body is the
credential.

**Headers.** `Content-Type`, `X-Device-Firmware`, `X-Device-Serial`.

**Request**

```json
{
  "hub_serial": "CMH-4F2A9C01",
  "factory_secret": "9f3c1a7e5b2d8f04a6c9e1b3d5f70268aa4c6e8092b4d6f81c3e5a70b9d24f68",
  "hardware_model": "chickmark-hub-v1",
  "firmware_version": "1.4.2",
  "mac_wifi": "3C:71:BF:12:9A:04",
  "boot_count": 1
}
```

**Response `200`**

```json
{
  "hub_id": "0f1c9e2a-77b4-4f31-9d0e-51c4f8a1d233",
  "device_secret": "b81f4c3a9e27d05f6118ca43be907d2fa5c86e14039b7d62e8f04a1c5b3d7e9a",
  "secret_expires_at": 1801552000,
  "server_time": 1786000000,
  "config_version": 1,
  "heartbeat_interval_s": 60,
  "telemetry_interval_s": 300,
  "espnow_pmk_rotated": false
}
```

`espnow_pmk_rotated` tells you whether this call minted a **new** ESP-NOW primary
key. It is `true` only on a hub's very first provisioning. **Re-provisioning
preserves the existing radio key**, because rotating it would strand every
already-paired, sleeping node with no recovery short of a physical visit to each
one — the same reasoning that keeps `espnow_channel` out of live config (§12.8).
If it ever comes back `true` on a hub that already had paired nodes, those nodes
need re-pairing.

`device_secret` is returned **exactly once**. If it is lost before it is
committed to NVS, call `/v1/provision` again — a fresh secret is issued and the
previous one is invalidated.

**Statuses**

| Status | Code | Meaning |
|---|---|---|
| 200 | — | Provisioned. Persist `hub_id` and `device_secret` **before** doing anything else. |
| 400 | `BAD_REQUEST` | Malformed body. Do not retry unchanged. |
| 401 | `INVALID_FACTORY_SECRET` | Secret does not match. Do not retry in a loop — retry every 15 min and light the fault LED. |
| 404 | `UNKNOWN_SERIAL` | Serial not in the factory registry. Manufacturing problem. Retry every 15 min. |
| 409 | `DEVICE_NOT_CLAIMED` | **Normal.** Nobody has claimed this hub yet. Retry every 60 s. |
| 429 | `RATE_LIMITED` | Honour `retry_after_s`. |
| 5xx | — | Backoff and retry. |

**Retry.** Yes, for `409` (60 s), `429` (as told), `5xx` and network errors.

**Idempotency.** Not idempotent — each success mints a **new** secret and kills
the old one. Only call it when you actually need a credential. Never call it on
every boot.

**Firmware notes**

- Persist `hub_id` and `device_secret` atomically. A power cut between the HTTP
  response and the NVS commit means calling `/v1/provision` again, which is safe.
- `409 DEVICE_NOT_CLAIMED` is the expected state of a brand-new hub sitting on a
  shelf. Show "waiting to be claimed" on the LED, not an error.
- Keep `factory_secret` forever. It is the only recovery path.

---

## 12.2 `POST /v1/auth/token`

**Purpose.** Exchange the long-lived `device_secret` for a 24 h bearer token.

**Authentication.** None (no bearer). The `device_secret` is the credential.

**Request**

```json
{
  "hub_id": "0f1c9e2a-77b4-4f31-9d0e-51c4f8a1d233",
  "device_secret": "b81f4c3a9e27d05f6118ca43be907d2fa5c86e14039b7d62e8f04a1c5b3d7e9a"
}
```

**Response `200`**

```json
{
  "device_token": "v1.7c2e9a41b8...f03d",
  "expires_in": 86400,
  "expires_at": 1786086400,
  "server_time": 1786000000,
  "rotate_secret": false
}
```

**Statuses**

| Status | Code | Firmware action |
|---|---|---|
| 200 | — | Cache the token in RAM. Refresh when &lt;10 % of `expires_in` remains. |
| 401 | `INVALID_DEVICE_SECRET` | Call `/v1/provision`. |
| 403 | `DEVICE_REVOKED` | Stop. Retry hourly. Do not wipe credentials. |
| 404 | `UNKNOWN_HUB` | Call `/v1/provision`. |
| 409 | `SECRET_ROTATION_REQUIRED` | Call `/v1/provision`, then retry this. |
| 429 / 5xx | — | Backoff. |

**Retry.** Yes for `429`/`5xx`/network. No for `401` (re-provision instead).

**Idempotency.** Safe to call repeatedly; each call issues an additional valid
token. Do not call more than once per hour in steady state.

**Firmware notes**

- If `rotate_secret` is `true`, finish what you are doing, then call
  `/v1/provision` at the next quiet moment. It is a hint, not an emergency.
- Caching the token in NVS across reboots is allowed and saves a round trip.
  Treat it as expired if the clock is not yet trusted.
- **The auth failure ladder, in full** — implement exactly this, it is the only
  loop that can otherwise run away:
  1. Any endpoint returns `401` → call `/v1/auth/token`, retry the request once.
  2. That retry also returns `401` → call `/v1/provision`, then `/v1/auth/token`,
     then retry the request once more.
  3. Still failing → back off to a 15 min retry cycle and light the fault LED.
     **Never** loop faster than this on an auth failure.

---

## 12.3 `POST /v1/telemetry`

**Purpose.** Upload one batch of sensor readings. This is the main data path.

**Authentication.** `Authorization: Bearer <device_token>`

**Request**

```json
{
  "batch_id": "CMH-4F2A9C01-000000000417",
  "sent_at": 1786000020,
  "readings": [
    {
      "sensor_uid": "A4CF12B93D07",
      "measured_at": 1786000000,
      "metrics": { "temperature_c": 27.4, "humidity_rh": 61.2, "co2_ppm": 1240 },
      "battery_percent": 87,
      "rssi": -68
    },
    {
      "sensor_uid": "A4CF12B93D07",
      "measured_at": 1786000060,
      "metrics": { "temperature_c": 27.5, "humidity_rh": 61.0, "co2_ppm": 1255 }
    },
    {
      "sensor_uid": "7C9E44A10B22",
      "measured_at": 1785999300,
      "metrics": { "temperature_c": 37.6, "humidity_rh": 54.8 },
      "battery_percent": 41,
      "rssi": -81,
      "t_est": true
    }
  ]
}
```

Field rules:

| Field | Required | Notes |
|---|---|---|
| `batch_id` | yes | `<hub_serial>-<seq>`, where `seq` is a `uint64` counter rendered as **exactly 12 zero-padded decimal digits**. Monotonic; gaps are fine (see §12.0.1). At one batch per 300 s, 10¹² is ~9 million years away — the width will not be exhausted. |
| `sent_at` | yes | When the hub built the batch. |
| `readings` | yes | 1–64 entries. |
| `sensor_uid` | yes | Hardware address, 12 uppercase hex chars, no separators. |
| `measured_at` | yes | When the **sensor** measured, not when the hub received. |
| `metrics` | yes | Object of `metric_key → number`. 1–16 keys. Unit is part of the key. |
| `battery_percent` | no | 0–100. Omit if unknown; do not send `0` or `-1`. |
| `rssi` | no | dBm, negative integer. |
| `t_est` | no | `true` only when the timestamp was derived from uptime because the clock was not yet synced. Omit otherwise. |

**Canonical metric keys** (send exactly these where they apply; unknown keys are
accepted and stored, but will not be charted until we add them):

```
temperature_c   humidity_rh    co2_ppm       nh3_ppm
pressure_pa     differential_pressure_pa     air_velocity_mps
light_lux       water_flow_lpm water_pressure_kpa
battery_percent power_w        door_state    vibration_g
```

Units are part of the key by design. **Never send Fahrenheit.** Convert on the
device, or better, read the sensor in Celsius natively.

**Response `202`**

```json
{
  "batch_id": "CMH-4F2A9C01-000000000417",
  "accepted": 2,
  "duplicates": 0,
  "rejected": [
    { "index": 2, "sensor_uid": "7C9E44A10B22", "reason": "UNKNOWN_SENSOR" }
  ],
  "flagged": [],
  "server_time": 1786000021,
  "config_version": 3,
  "commands_pending": false
}
```

Rejection reasons: `UNKNOWN_SENSOR`, `SENSOR_NOT_ON_HUB`, `FUTURE_TIMESTAMP`,
`STALE_TIMESTAMP`, `NO_VALID_METRICS`, `MALFORMED_READING`.

`MALFORMED_READING` covers a structurally bad reading — a `measured_at` that is
not an integer, more than 16 metric keys, or a reading that is not an object. It
is a per-reading rejection rather than a `400` for the whole batch, because
§11.2's rule holds: one bad item must never fail the batch.

`UNKNOWN_SENSOR` means the `sensor_uid` string itself is malformed (not 12
uppercase hex characters); the offending value is echoed back, truncated, in
`sensor_uid`. A genuinely unrecognised sensor is **not** rejected — it is
auto-created, per §12.7. `SENSOR_NOT_ON_HUB` is returned when the sensor exists
on this hub but has been retired by staff.

An implausible value is **not** a rejection. It is stored with
`quality = 'suspect'` and reported in a separate `flagged[]` array, because a
sensor reporting nonsense is itself the signal an operator needs. Firmware takes
no action on `flagged[]` — it is informational.

A duplicate batch returns `202` with `"duplicate": true` and
`accepted: 0`. That is a **success** — the server already has the data.

**Statuses**

| Status | Firmware action |
|---|---|
| 202 | Delete the batch from the queue. Always — including when `rejected` is non-empty. |
| 400 `BAD_REQUEST` | Drop the batch. Emit a `malformed_batch` event. |
| 401 | Refresh via `/v1/auth/token`, retry once. If the retry also 401s, run `POST /v1/provision`, then retry. |
| 403 | Stop uploading, keep the queue, retry hourly. |
| 404 `UNKNOWN_HUB` | Re-provision. |
| 413 `PAYLOAD_TOO_LARGE` | Halve batch size (floor 8) and retry. Persist the new size. |
| 429 | Sleep `retry_after_s` exactly. |
| 5xx / network | Backoff with jitter, keep the batch. |

**Retry.** Yes for `401` (once), `413`, `429`, `5xx`, network. No for `400`.

**Idempotency.** Fully idempotent on `(hub_id, batch_id)` and again on
`(sensor_uid, measured_at)`. Re-sending an identical batch is always safe. If a
`413` forces you to re-split readings across different `batch_id`s, the second
layer still prevents duplicates.

**Firmware notes**

- Default interval **300 s**; default max batch **64 readings**; hard cap
  **32 KB** body. Both intervals are overridable from `/v1/config`.
- Buffer readings **packed binary** on flash or SD; build JSON only at send time,
  one batch at a time. Peak JSON heap for a 64-reading batch is about 8 KB.
- On the first upload after a reconnection, send the **newest** batch first, then
  drain the backlog oldest-first. This makes the customer's dashboard go live
  immediately instead of after the backlog clears.
- Cap backlog drain at ~10 batches/minute so a week-old backlog does not starve
  live data.
- A reading with an empty `metrics` object must not be sent. Drop it locally.
- `202` means durably written. There is no second confirmation step.

---

## 12.4 `POST /v1/heartbeat`

**Purpose.** Report device health **and collect pending commands and config
changes.** This is the only polling loop the hub needs.

**Authentication.** `Authorization: Bearer <device_token>`

**Request**

```json
{
  "sent_at": 1786000080,
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
  "last_upload_at": 1786000020,
  "last_upload_ok": true,
  "config_version": 3,
  "topology_hash": "8a41c9f2"
}
```

`reset_reason` is an open enum: `power_on`, `software`, `panic`, `watchdog_int`,
`watchdog_task`, `deep_sleep`, `brownout`, `unknown`. Send what the SDK gives
you; the server stores unrecognised values verbatim.

**Omit** any field that is genuinely unavailable — e.g. `battery_percent` on a
mains-powered hub. Do not send `0`, `-1`, or `null`. This is the same rule as
telemetry (§12.3), deliberately: one serialisation helper, one behaviour.

**Response `200`**

```json
{
  "server_time": 1786000081,
  "config_version": 4,
  "topology_stale": false,
  "next_heartbeat_s": 60,
  "commands": [
    {
      "command_id": "b1d7e0c2-4a19-4c88-9f2e-3d0a7c611e45",
      "command_type": "identify_sensor",
      "params": { "sensor_uid": "A4CF12B93D07", "duration_s": 30 },
      "created_at": 1786000075,
      "expires_at": 1786003675
    }
  ]
}
```

**Statuses.** `200`; `401` refresh once; `403` stop; `404` re-provision; `429`
honour `retry_after_s`; `5xx`/network backoff.

**Retry.** Yes, but **never queue heartbeats.** A heartbeat is a snapshot of
*now*. If one fails, drop it and send a fresh one at the next interval.

**Idempotency.** Not applicable — heartbeats are not deduplicated and carry no
`batch_id`. Sending two is harmless.

**Firmware notes**

- Default interval **60 s**. Payload is ~400 bytes. This is deliberately more
  frequent than telemetry because it is also the command channel.
- **Honour `next_heartbeat_s`.** The server uses it to speed you up when a
  command is waiting or a technician is on site, and to slow you down on
  constrained links. Clamp it to the range 10–900 s and ignore values outside it.
- If `config_version` differs from your stored value, call `GET /v1/config`
  **after** finishing the current cycle. Do not block telemetry on it.
- If `topology_stale` is `true`, call `POST /v1/topology` with a full snapshot.
- `commands` is capped at 10 per response. If more are pending you will get the
  rest on the next heartbeat; combined with `next_heartbeat_s` this drains fast.

---

## 12.5 `POST /v1/commands/ack`

**Purpose.** Acknowledge receipt and report the outcome of commands. Batched:
one request covers every command you have news about.

> This replaces a per-command `POST /v1/commands/{id}/ack`. Batching means one
> request instead of N, which matters on a link that may be marginal.

**Authentication.** `Authorization: Bearer <device_token>`

**Request**

```json
{
  "sent_at": 1786000090,
  "acks": [
    {
      "command_id": "b1d7e0c2-4a19-4c88-9f2e-3d0a7c611e45",
      "status": "succeeded",
      "completed_at": 1786000089,
      "result": { "blinked_ms": 30000 }
    },
    {
      "command_id": "9f2a1b03-6c55-4a71-8e10-2b7d9c334f88",
      "status": "failed",
      "completed_at": 1786000088,
      "error_code": "SENSOR_NOT_FOUND",
      "error_message": "A4CF12B93D07 has not reported for 40 minutes"
    },
    {
      "command_id": "3c8d5e77-1f42-4b09-a6d3-7e5518c9b021",
      "status": "unsupported"
    }
  ]
}
```

`status` is one of `received`, `succeeded`, `failed`, `unsupported`, `expired`.

`completed_at` is **stored as you send it** (when it is a plausible epoch-second
value). That matters for `reboot`: the server records when the hub says it
finished, not when the message happened to arrive, which is what makes a
successful reboot distinguishable from a crash.

- `received` — accepted, will take a while (e.g. `run_diagnostic`). Send a second
  ack with the terminal status later.
- `unsupported` — you do not implement this `command_type`. **Always send this
  rather than ignoring an unknown command**, otherwise the server will redeliver
  it until it expires.

**Response `200`**

```json
{ "acknowledged": 3, "unknown": [], "server_time": 1786000091 }
```

**Statuses.** `200`; `400` drop; `401` refresh once; `403` stop; `429`/`5xx`
backoff.

**Retry.** Yes. Acks may be re-sent freely.

**Idempotency.** Idempotent on `command_id` + `status`. Re-sending the same
terminal ack is a no-op. A terminal status cannot be overwritten by a later
`received`.

**Firmware notes**

- Ack **before** executing anything disruptive. For `reboot`, send
  `status: "received"`, flush the ack, *then* reboot, and send
  `status: "succeeded"` after coming back up. Otherwise the server can never
  tell a successful reboot from a crash.
- Commands are a closed set. There is no command that executes arbitrary code,
  and there never will be. If you receive something unrecognised, ack it
  `unsupported`.

**v1 command types**

| `command_type` | Params | Expected behaviour | Idempotent? |
|---|---|---|---|
| `reboot` | `{ "delay_s": 5 }` | Ack `received`, flush, reboot, ack `succeeded` on return | Yes |
| `force_sync` | `{}` | Upload all queued batches immediately | Yes |
| `refresh_config` | `{}` | `GET /v1/config` now | Yes |
| `report_topology` | `{}` | `POST /v1/topology` with a full snapshot | Yes |
| `identify_sensor` | `{ "sensor_uid": "...", "duration_s": 30 }` | Blink/beep the named node | Yes |
| `identify_hub` | `{ "duration_s": 30 }` | Blink/beep the hub | Yes |
| `run_diagnostic` | `{ "scope": "radio" \| "sensors" \| "storage" }` | Ack `received`, run, ack terminal with `result` | Yes |
| `start_calibration` | `{ "sensor_uid": "...", "metric_key": "...", "reference_value": 0.0 }` | Begin the calibration workflow | **No** — see note |
| `pair_window_open` | `{ "duration_s": 120 }` | Accept new ESP-NOW nodes for the window | Yes |
| `forget_sensor` | `{ "sensor_uid": "..." }` | Remove the node from the local peer list | Yes |
| `check_firmware` | `{}` | `GET /v1/firmware` now | Yes |
| `reprovision` | `{}` | `POST /v1/provision` to rotate the device secret | Yes |

**Replay protection applies to every command, not just calibration.** Persist
`last_command_id` in NVS and refuse to execute the same `command_id` twice.

Two commands make this mandatory rather than tidy:

- `start_calibration` — applying an offset twice doubles it.
- `reboot` — if the `received` ack is lost in transit (which is exactly what a
  marginal farm link does, drop the outbound POST as the device resets), the
  server still has the command pending and redelivers it on the next heartbeat.
  Without the guard that is a boot loop, not a hypothetical. Write
  `last_command_id` **before** rebooting, and on boot treat a redelivered
  matching `command_id` as already-done: ack `succeeded` and do not reboot again.

The server also stops redelivering once it has any ack, so this is belt and
braces — but the device must not depend on the network to avoid a boot loop.

---

## 12.6 `GET /v1/commands` *(optional)*

**Purpose.** Fetch pending commands without a heartbeat. Provided for debugging
and for the case where you want a faster poll during a technician visit.

**Do not build your normal command loop on this.** The heartbeat already carries
commands; polling both doubles your request rate for no benefit.

**Authentication.** `Authorization: Bearer <device_token>`
**Request.** No body. Optional query `?limit=10`.
**Response `200`.** Same `commands` array shape as the heartbeat response, plus
`server_time`.
**Statuses.** `200`; `401`; `403`; `429`; `5xx`.
**Retry.** Yes. **Idempotency.** Safe — reading does not consume.

---

## 12.7 `POST /v1/topology`

**Purpose.** Tell the server which sensors this hub currently knows about.

**Full snapshot, not deltas.** Deltas require both sides to agree on a starting
state; snapshots are self-healing. The server diffs against what it has and
raises `sensor_added` / `sensor_removed` itself — you do not need to.

**Authentication.** `Authorization: Bearer <device_token>`

**When to send**

1. On boot, after the first successful auth.
2. Whenever the sensor set changes (pairing, or a node silent past its timeout).
3. Every 24 h as a safety net.
4. Whenever a heartbeat returns `topology_stale: true`.

Not more than once per 60 s, even if nodes are flapping.

**Request**

```json
{
  "sent_at": 1786000100,
  "topology_hash": "8a41c9f2",
  "hub": {
    "firmware_version": "1.4.2",
    "hardware_model": "chickmark-hub-v1",
    "radio": "esp-now",
    "channel": 6
  },
  "sensors": [
    {
      "sensor_uid": "A4CF12B93D07",
      "model": "chickmark-node-th-v1",
      "firmware_version": "0.9.3",
      "capabilities": ["temperature_c", "humidity_rh"],
      "state": "online",
      "last_seen_at": 1786000080,
      "battery_percent": 87,
      "rssi": -68
    },
    {
      "sensor_uid": "7C9E44A10B22",
      "model": "chickmark-node-air-v1",
      "firmware_version": "0.9.1",
      "capabilities": ["temperature_c", "humidity_rh", "co2_ppm", "nh3_ppm"],
      "state": "offline",
      "last_seen_at": 1785996100,
      "battery_percent": 41,
      "rssi": -81
    }
  ]
}
```

`state` is `online` | `offline` | `pairing`. `topology_hash` is any stable hash
you compute over the sorted `sensor_uid` + `state` + `firmware_version` set —
the algorithm is yours; the server only compares it for equality.

**Response `200`**

```json
{
  "accepted": 2,
  "topology_hash": "8a41c9f2",
  "server_time": 1786000101,
  "config_version": 4
}
```

**Statuses.** `200`; `400` drop; `401` refresh once; `403` stop; `413` — send
fewer sensors per call is not supported, so this means the fleet exceeded the cap
(256 sensors/hub); `429`/`5xx` backoff.

**Retry.** Yes. **Idempotency.** Fully idempotent — it is a snapshot. Sending the
same snapshot twice changes nothing.

**Firmware notes**

- A sensor that has not reported for 3× its expected interval is `offline`. Keep
  reporting it — a missing sensor and an offline sensor mean very different
  things to the customer. Only drop it from the snapshot after `forget_sensor`.
- Do **not** call the server when a sensor packet arrives. Local ESP-NOW receipt
  requires no server round trip. Topology is reported on change, not on traffic.
- A sensor may report telemetry before it appears in a topology snapshot. The
  server auto-creates it in an `unassigned` state and keeps the data; staff bind
  it to a room/machine in the app. Nothing is lost.

---

## 12.8 `GET /v1/config`

**Purpose.** Fetch the hub's operating configuration. Fully resolved and flat —
the server merges global, model, customer and hatchery defaults with the
per-hub overrides. **The hub does no merging.**

**Authentication.** `Authorization: Bearer <device_token>`

**Request.** No body. Send `If-None-Match: "<etag>"` if you have one.

**Response `200`**

```json
{
  "config_version": 4,
  "etag": "W/\"cfg-4-0f1c9e2a\"",
  "server_time": 1786000110,
  "config": {
    "measurement_interval_s": 60,
    "telemetry_interval_s": 300,
    "heartbeat_interval_s": 60,
    "max_batch_readings": 64,
    "topology_report_interval_s": 86400,
    "sensor_offline_after_s": 300,
    "enabled_metrics": ["temperature_c", "humidity_rh", "co2_ppm", "nh3_ppm"],
    "disabled_sensor_uids": [],
    "espnow_pmk": "3f9c1e77aa42b8d05e6134c7092fab18",
    "base_url": "https://<project-ref>.supabase.co/functions/v1/iot-gateway",
    "calibration": {
      "A4CF12B93D07": { "temperature_c": { "offset": -0.4 }, "humidity_rh": { "offset": 1.2 } }
    },
    "ntp_servers": ["pool.ntp.org", "time.cloudflare.com"],
    "timezone": "Africa/Cairo",
    "log_level": "info",
    "ota_channel": "stable",
    "ota_check_interval_s": 21600
  }
}
```

**Response `304`.** Body empty. Your cached config is current.

**Statuses.** `200`; `304`; `401` refresh once; `403` stop; `404` re-provision;
`429`/`5xx` backoff.

**Retry.** Yes. **Idempotency.** Safe — pure read.

**Firmware notes**

- **When to call:** at boot, and whenever a heartbeat or telemetry response
  reports a `config_version` different from your stored one. Never on a timer.
- Persist `config_version` and the applied config. On boot with no network, run
  from the persisted config.
- **Apply what you understand, ignore what you do not.** An unknown key is not an
  error. If a *known* key has an out-of-range value, clamp it to your supported
  range, keep running, and emit a `config_clamped` event.
- `timezone` is informational. **All protocol timestamps stay UTC.** Use it only
  for a local display, if the hub has one.
- `espnow_pmk` is the per-hub ESP-NOW primary key. Treat it as a secret: store it
  in NVS, never log it, never put it in an event payload.
- Only bump your stored `config_version` **after** the config is applied and
  persisted. A crash mid-apply must re-fetch, not skip.
- **`base_url` changes need a commit-on-success dance.** This is the one config
  key that can permanently orphan a hub if it is applied blindly. On receiving a
  new `base_url`: keep the old one, attempt `POST /v1/auth/token` against the new
  one, and only persist the new value after that succeeds. On failure, revert to
  the old URL, keep running, and emit a `config_clamped` event naming
  `base_url`. Never overwrite a working base URL with an untested one.
- **`espnow_channel` is deliberately not in the live config.** Changing the radio
  channel from a server would strand every already-paired, sleeping node, with no
  recovery short of a physical visit to each one. It is set at install time and
  stored in NVS. If it ever has to change, that is a `pair_window_open` plus a
  re-pair, driven by a technician who is on site — not a config push.

---

## 12.9 `POST /v1/events`

**Purpose.** Report **device-level** conditions. Batched.

**What belongs here:** things about the equipment. Sensor lost, battery low, hub
rebooted, storage nearly full, queue overflowed, OTA failed, calibration drifted.

**What does not belong here:** anything about the *poultry operation*. Do not
implement "temperature exceeded the setter limit". Production thresholds are
evaluated server-side against the customer's benchmark data, which changes per
customer, per breed, per flock age, and which firmware must never be responsible
for. Send the reading; the server decides whether it is alarming.

**Authentication.** `Authorization: Bearer <device_token>`

**Request**

```json
{
  "sent_at": 1786000120,
  "events": [
    {
      "event_id": "CMH-4F2A9C01-e-000000000091",
      "event_type": "sensor_disconnected",
      "severity": "warning",
      "occurred_at": 1786000050,
      "sensor_uid": "7C9E44A10B22",
      "detail": { "last_seen_at": 1785996100, "missed_intervals": 65 }
    },
    {
      "event_id": "CMH-4F2A9C01-e-000000000092",
      "event_type": "queue_overflow",
      "severity": "critical",
      "occurred_at": 1786000100,
      "detail": { "dropped_readings": 4210, "queue_bytes": 8388608 }
    }
  ]
}
```

`event_id` follows the same monotonic pattern as `batch_id`, with an `-e-`
segment so the two counters cannot collide.

**v1 event types**

| `event_type` | Typical severity |
|---|---|
| `hub_boot` | `info` |
| `hub_reboot_unexpected` | `warning` |
| `sensor_discovered` | `info` |
| `sensor_paired` | `info` |
| `sensor_disconnected` | `warning` |
| `sensor_reconnected` | `info` |
| `sensor_low_battery` | `warning` |
| `sensor_fault` | `warning` |
| `calibration_required` | `warning` |
| `storage_low` | `warning` |
| `queue_overflow` | `critical` |
| `malformed_batch` | `warning` |
| `config_clamped` | `info` |
| `clock_unsynced` | `warning` |
| `clock_stepped` | `info` |
| `ota_failed` | `critical` |
| `ota_rolled_back` | `critical` |
| `network_degraded` | `info` |

The list is open. An unrecognised `event_type` is stored verbatim with severity
`info` — it will not be dropped, but it will not drive an alert until we add it.

**Response `202`**

```json
{
  "accepted": 2,
  "duplicates": 0,
  "rejected": [],
  "server_time": 1786000121
}
```

**Statuses.** `202`; `400` drop; `401` refresh once; `403` stop; `413` split;
`429`/`5xx` backoff.

**Retry.** Yes for `401`/`413`/`429`/`5xx`/network. No for `400`.

**Idempotency.** Idempotent on `(hub_id, event_id)`.

**Firmware notes**

- Events queue and retry like telemetry, but on a **separate queue**, and events
  are sent **first** when both are pending. A hub that is failing should be able
  to say so even when its data backlog is huge.
- **Flush cadence.** `critical` events are sent **immediately**, not on the next
  telemetry tick — a `queue_overflow` that waits 300 s to be reported is 300 s an
  operator did not have. `warning` and `info` events ride the heartbeat cadence
  (60 s). Never hold an event for the telemetry interval.
- **Deduplicate locally.** A flapping sensor must not generate 500
  `sensor_disconnected` events. Emit once on state change, and at most once per
  hour while the state persists.
- Max 32 events per batch.
- Never put a secret in `detail` — no `device_secret`, no `espnow_pmk`, no Wi-Fi
  password.

---

## 12.10 `GET /v1/firmware`

**Purpose.** Ask whether an update is available for this hub.

**Authentication.** `Authorization: Bearer <device_token>`

**Request.** No body. Optional query `?target=hub|sensor&sensor_uid=...`.
Defaults to `target=hub`.

**Response `200` — update available**

```json
{
  "update_available": true,
  "update_id": "2b7e4f10-9a35-4c62-b8d1-06e4c93a7715",
  "target": "hub",
  "version": "1.5.0",
  "hardware_model": "chickmark-hub-v1",
  "size_bytes": 1384448,
  "sha256": "3f9c1e77aa42b8d05e6134c7092fab18c4e70a29b6d5138f4a0c7e21bb93d604",
  "signature": "9d41f0a7c8e21b6503fa7d94c1e08b276fa35d9017c4e8b23d605af197e2c40b8f1e73da2560c9b4718fe0325a6d1c47908b3ef25d7a4160cbe93482f5017d09",
  "signature_alg": "ed25519-sha256",
  "download_url": "https://<project-ref>.supabase.co/storage/v1/object/sign/firmware/...",
  "url_expires_at": 1786003710,
  "release_notes": "Improved ESP-NOW retry, fixes queue accounting",
  "server_time": 1786000110
}
```

**Response `200` — nothing to do**

```json
{ "update_available": false, "server_time": 1786000110 }
```

**Statuses.** `200`; `401` refresh once; `403` stop; `429`/`5xx` backoff.

**Retry.** Yes. **Idempotency.** Safe — pure read. Re-fetching returns the same
`update_id` until the update completes.

**Firmware notes — this is the security-critical endpoint**

1. Check at boot and every `ota_check_interval_s` (default 6 h), plus on a
   `check_firmware` command. Add jitter so a fleet does not stampede.
2. `download_url` is short-lived (~1 h). If it expires mid-download, call
   `GET /v1/firmware` again for a fresh one — do not cache it.
3. **Verify both — and note exactly what is signed.** A 1.3 MB image cannot be
   held in ESP32 RAM, so plain Ed25519 over the raw artifact is not
   implementable. The signature is therefore **Ed25519 over the 32 raw bytes of
   the artifact's SHA-256 digest** — `signature_alg: "ed25519-sha256"`. That makes
   verification streamable:
   1. Stream the download to the OTA partition, updating a SHA-256 context as
      you go. Never buffer the whole image.
   2. Finalise the digest and compare it to the `sha256` field (hex, lowercase).
   3. Verify the 64-byte `signature` (hex, lowercase) over those **32 digest
      bytes** — not over the hex string of the digest, and not over the image —
      using the Ed25519 public key **compiled into your firmware**.

   Fail either check → abort, erase the OTA partition, report `status: "failed"`
   with `error_code: "CHECKSUM_MISMATCH"` or `"SIGNATURE_INVALID"`, and emit
   `ota_failed`. **Never** flash an image that fails verification, whatever the
   server said. The backend will supply the public key and a worked
   sign-and-verify example alongside the first release artifact.
4. Use the ESP32 dual-OTA partition scheme. After the first successful boot on
   the new image, and only after one successful heartbeat, call
   `esp_ota_mark_app_valid_cancel_rollback()`. If the new image cannot heartbeat,
   let the bootloader roll back and report `ota_rolled_back`.
5. Do not update while the queue is deep or the link is unstable — finish
   uploading first. Data loss during an update is far worse than a late update.
6. Staged rollout is entirely server-side. If the server says there is no update,
   there is no update; do not second-guess it by comparing version strings.
7. `target: "sensor"` is defined in the contract but **not required for v1**. If
   your nodes cannot be updated over ESP-NOW, ignore it. When it does land, the
   hub downloads the artifact and relays it; the verification rules are identical.

---

## 12.11 `POST /v1/firmware/status`

**Purpose.** Report progress and outcome of an update.

> This replaces `POST /v1/firmware/{update_id}/status`. The `update_id` is in the
> body, which lets one request carry a hub result and a sensor result together.

**Authentication.** `Authorization: Bearer <device_token>`

**Request**

```json
{
  "sent_at": 1786000400,
  "reports": [
    {
      "update_id": "2b7e4f10-9a35-4c62-b8d1-06e4c93a7715",
      "status": "succeeded",
      "from_version": "1.4.2",
      "to_version": "1.5.0",
      "occurred_at": 1786000395
    }
  ]
}
```

`status` is `downloading` | `verifying` | `applying` | `succeeded` | `failed` |
`rolled_back`. On `failed` or `rolled_back`, include `error_code` and
`error_message`. Suggested codes: `DOWNLOAD_FAILED`, `CHECKSUM_MISMATCH`,
`SIGNATURE_INVALID`, `FLASH_WRITE_FAILED`, `INSUFFICIENT_SPACE`,
`INCOMPATIBLE_HARDWARE`, `BOOT_FAILED`.

**Response `200`**

```json
{ "accepted": 1, "server_time": 1786000401 }
```

**Statuses.** `200`; `400` drop; `401` refresh once; `403` stop; `429`/`5xx`
backoff.

**Retry.** Yes. **Idempotency.** Idempotent on `(update_id, status)`. A terminal
status cannot be overwritten by a non-terminal one.

**Firmware notes**

- Report `applying` **before** you reboot into the new image, and `succeeded`
  **after** the new image has authenticated and heartbeated once. That sequence
  is what lets the server distinguish a good update from a brick.
- Intermediate `downloading`/`verifying` reports are optional. Send them for a
  large image so the technician sees progress; skip them on a marginal link.

---

## 12.12 Sensor node → Hub (local link)

Not part of the server contract, but the design assumes:

- **ESP-NOW** with encryption enabled, using the per-hub `espnow_pmk` delivered in
  `/v1/config` and a per-peer LMK. This is what stops a neighbouring site's nodes
  from being absorbed.
- Nodes are added only during a `pair_window_open` window (server command, or a
  physical button on the hub). Outside the window, unknown peers are ignored and
  a `sensor_discovered` event is raised so staff can decide.
- A node packet carries: `sensor_uid` (its MAC), a monotonic sequence number, its
  metric values, `battery_percent`, and its own measurement timestamp if it has a
  usable clock (otherwise the hub stamps it on receipt).
- The hub ACKs at the link layer so the node can sleep immediately. **The hub must
  never wait for the server before ACKing a node.** Local receipt and server
  upload are fully decoupled.
- Nodes never talk to the internet. The hub is the only internet-facing device.

## 12.13 Recommended intervals

| Activity | Default | Range | Notes |
|---|---|---|---|
| Sensor measurement | 60 s | 10 s – 15 min | Set per deployment via config |
| Telemetry upload | 300 s | 60 s – 30 min | Batch of ~5 samples/sensor |
| Heartbeat | 60 s | 10 s – 15 min | Also the command channel; obey `next_heartbeat_s` |
| Topology report | 24 h | plus on change | Never more than once per 60 s |
| Config check | on `config_version` change | — | Never on a timer |
| Firmware check | 6 h | 1 h – 24 h | Add jitter |
| Token refresh | at 90 % of TTL | — | ~21.6 h at a 24 h TTL |

At these defaults a hub with 20 sensors generates roughly **1 700 requests/day**
and about **3 MB/day** of uplink. That is comfortable on a 2G/LTE fallback link.

## 12.14 Integration checklist

- [ ] Wi-Fi provisioning: SoftAP portal, 10 s button reset, auto re-entry after 15 min of failure
- [ ] TLS uses the full ESP-IDF cert bundle; no leaf pinning
- [ ] Cold-boot clock bootstrap resolved (RTC fitted, or SNTP-then-relaxed-time-check ladder)
- [ ] Base URL, `hub_serial` and `factory_secret` configurable and persisted
- [ ] Secrets are 64 lowercase hex chars everywhere; `sensor_uid` is 12 uppercase hex
- [ ] Flash + NVS encryption enabled on production units
- [ ] `/v1/provision` → persists `hub_id` + `device_secret` atomically
- [ ] `409 DEVICE_NOT_CLAIMED` handled as a normal waiting state, 60 s poll
- [ ] `/v1/auth/token` with refresh at 90 % TTL and single-retry on `401`
- [ ] Clock: SNTP + `server_time` correction + `t_est` on derived timestamps
- [ ] Persistent binary ring buffer survives power cut; drop-oldest on overflow
- [ ] `batch_id` counter monotonic across reboot, persisted every 64 (not every batch)
- [ ] `event_seq` persisted eagerly and separately from `batch_seq`
- [ ] Backward clock step never reuses a `measured_at` for the same sensor
- [ ] Telemetry batching ≤64 readings, ≤32 KB, `413` halving implemented
- [ ] Backoff is exponential, capped at 300 s, with ±20 % jitter
- [ ] `400` drops the payload; `5xx` keeps it
- [ ] Heartbeat never queued; `next_heartbeat_s` honoured and clamped
- [ ] Unknown `command_type` acked as `unsupported`
- [ ] `last_command_id` persisted; no command executes twice
- [ ] `reboot` acked `received` and `last_command_id` written **before** rebooting
- [ ] Topology is a full snapshot; offline sensors still listed
- [ ] Config applied leniently; `config_version` bumped only after persist
- [ ] Events deduplicated locally; events sent before telemetry; `critical` flushed immediately
- [ ] `base_url` change is commit-on-success, reverting on failure
- [ ] OTA streams to flash, verifies SHA-256 **and** Ed25519-over-digest before flashing; rollback wired up
- [ ] Unknown JSON fields ignored everywhere
- [ ] No secret ever appears in a log line or an event `detail`

---

# 13. Backend appendix — where alerting lives

*(Not part of the firmware contract. Included so the split is unambiguous.)*

The rule is: **firmware reports facts about equipment; the server decides what is
alarming about the poultry operation.**

| Concern | Evaluated by | Why |
|---|---|---|
| "Node A4CF has not reported in 40 min" | **Hub** | Only the hub can know this. Emits `sensor_disconnected`. |
| "Node battery is at 9 %" | **Hub** | Local fact, no context needed. |
| "The queue overflowed" | **Hub** | Local fact. |
| "Setter 3 is at 38.9 °C, which is above the CVT band" | **Server** | Needs the BMK benchmark, the flock, the breed and the flock age. All of that changes without a firmware update. |
| "CO₂ in the setter room exceeded 3 000 ppm" | **Server** | `AppThresholds.co2Max` already lives in the app; the same limit belongs server-side, not burned into a sensor. |
| "Egg storage has drifted outside 16–21 °C for 4 hours" | **Server** | Duration-based, and the target depends on planned storage length. |

This mirrors how ChickMark already works. `severityFor()`,
`ScopeParam.absoluteLimit` and the `_GoveeTarget` bands are all evaluated outside
the sensor today. IoT does not change the model; it just moves that evaluation
from the phone to the server so it can run when nobody has the app open.

**Consequence for the backend:** a rule engine is needed, but it is *not* part of
the firmware contract and does not block firmware work. It reads
`iot_telemetry_hourly` / `iot_telemetry`, applies the same band logic already
implemented in Dart, and writes to a server-side alert table. Ship ingestion
first; ship alerting second.

# 14. Backend appendix — fitting into the existing product

- **Dashboard.** `iot_telemetry_daily` deliberately carries the same
  `avg / min / max / sd / cv_pct` columns and the same `station_key` / `place` /
  `machine_id` labels as `govee_daily_captures`, so the existing environmental
  section and triage builders can render IoT data with minimal change.
- **Govee is not replaced.** Manual BLE captures stay. They are a spot check by
  an auditor on a visit; IoT is continuous monitoring. Both feed the same
  dashboard vocabulary.
- **Pip (the AI agent).** IoT ingestion does not need to touch the agent to be
  useful. If the agent should answer "what was the setter room overnight?", add
  one read-only tool to the shared tool contract in
  `telegram-hatchery-agent/agent_tools.ts` — it is automatically available to all
  three doors (Telegram, app text, Pip Live). Do this after ingestion works.
- **Offline sync.** IoT tables are **not** registered in the Flutter sync layer.
  Pushing a time series through the offline sync engine would be a mistake. The
  app reads rollups live and caches what it needs for its own offline view.

# 15. Backend appendix — deliberately out of scope for v1

Recorded so nobody has to re-litigate them:

- MQTT / WebSocket / long polling. Heartbeat-carried commands cover v1. The
  command table is transport-agnostic, so a broker can be added later without a
  firmware contract change.
- mTLS and per-device certificates.
- Sensor-node OTA. The contract reserves `target: "sensor"`; the implementation
  can wait.
- Per-tenant rate-limit tuning. One global per-hub limit is enough at v1 scale.
- Edge/local buffering *on the server side* (write-ahead to storage before
  Postgres). Not needed until ingest volume threatens the database.
- A machine/room registry in the cloud. Free-text `machine_id` matches what the
  product already does; introducing a proper entity is a separate, larger change
  that should be driven by product need, not by IoT.
