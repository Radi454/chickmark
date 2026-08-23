# ChickMark IoT — Backend Implementation Plan

Companion to `docs/IOT_API_CONTRACT.md`. That document is the contract; this one
is the build order.

Guiding constraint: **the firmware engineer must never be blocked.** Phase 0
exists purely so they can start integrating on day one against something real.

---

## Phase 0 — Unblock firmware (target: first)

Goal: a reachable endpoint that speaks the exact v1 contract, so firmware work
starts before any of the real backend exists.

1. Create the Edge Function `supabase/functions/iot-gateway/` following the house
   idiom: `handleIotRequest(request, deps)` + `serveIot(request)` +
   `if (import.meta.main) Deno.serve(serveIot)`.
2. Implement the internal path router over
   `new URL(request.url).pathname`, stripping the
   `/functions/v1/iot-gateway` prefix, dispatching on `/v1/<endpoint>`.
3. Implement **every** endpoint in §12 as a schema-validating stub: full request
   validation, correct status codes, correct response shapes, correct error
   envelope — but writes go to a single scratch table, and provisioning accepts
   any serial present in a seeded fixture list.
4. Deploy: `supabase functions deploy iot-gateway --no-verify-jwt`.
5. Hand over: the base URL, two test hub serials with their factory secrets
   (64 lowercase hex chars each), and `docs/IOT_API_CONTRACT.md` §12.
6. Generate the OTA Ed25519 keypair now, not in Phase 6, and hand the **public**
   key plus a worked sign-and-verify example to the firmware engineer. It has to
   be compiled into firmware, so it is on the critical path even though OTA
   itself is not. The private key stays offline — never in the repo, never in
   Supabase secrets.

Acceptance: `curl` walks provision → token → telemetry → heartbeat → ack end to
end and gets contract-correct responses. Validation rejects a malformed batch
with `400` and an oversized one with `413`.

**Deliverable that matters here is the mock, not the storage.** Do not let
Phase 1 delay Phase 0.

---

## Phase 1 — Schema

1. One migration, `supabase/migrations/<ts>_iot_core.sql`, creating everything in
   §9: registry, hubs, hub secrets, tokens, sensors, metric registry, telemetry
   (+partitions), rollups, events, commands, config, firmware tables.
2. Seed `iot_metric_registry` with the canonical keys and plausible ranges.
3. RLS exactly as the §9.5 disposition table — **every** table on that list, with
   `force row level security` and `revoke all ... from authenticated` on the
   service-role-only ones.
4. **Composite `(hub_id, customer_id)` foreign keys** on `iot_sensors`,
   `iot_commands`, `iot_device_events`, `iot_hub_config` and
   `iot_firmware_updates`, plus `(sensor_id, customer_id)` on `iot_telemetry`.
   These make tenant isolation a database property instead of a convention every
   future handler has to remember.
5. Column-level grants on `iot_hubs` — RLS has no column granularity, and an
   unrestricted `UPDATE` would let staff un-revoke a hub.
6. `public.iot_claim_hub(...)` RPC, `security definer`, `search_path = ''`,
   revoked from `public`/`anon`, granted to `authenticated`.
7. Partition maintenance: `chickmark_private.iot_add_telemetry_partition()`, the
   next 3 monthly partitions, and the default partition.

Four traps this migration must avoid. Each was found in review, and each fails
silently rather than loudly:

- **Never call pgcrypto's `digest()`.** It resolves to nothing under
  `search_path = ''` (it lives in `extensions`), and it is absent from the
  bare-Postgres replay harness. Use `encode(sha256(convert_to(x,'UTF8')),'hex')`
  — all `pg_catalog`, no extension, correct in both places. Adding
  `create extension ... with schema extensions` instead would fail the replay
  script outright.
- **Enable RLS on every partition, not just the parent.** `CREATE TABLE ...
  PARTITION OF` inherits neither `relrowsecurity` nor the parent's policies, and
  a query naming a partition directly bypasses the parent entirely. Queries
  through the parent keep working perfectly, which is what makes this so easy to
  miss.
- **Do not name a new private helper `chickmark_private.app_*`.** The hardening
  script asserts exactly nine such functions exist; a tenth fails the build.
- **Confirm the replay harness runs Postgres ≥13**, since nine of the new tables
  default to `gen_random_uuid()`.

Acceptance:
- `scripts/test_supabase_security_hardening.sh` passes — this replays every
  migration from empty and asserts the RLS invariants. Non-negotiable.
- A test asserting that an `authenticated` session for customer A reads zero rows
  of customer B's telemetry, sensors, events and commands — **and that it reads
  zero rows when naming a telemetry partition directly.**
- A negative test asserting customer A cannot insert an `iot_commands` row
  carrying its own `customer_id` and customer B's `hub_id`.
- A test asserting `anon` gets zero rows from every new table.

---

## Phase 2 — Real ingestion

1. `POST /v1/provision` — constant-time compare of `factory_secret` against
   `iot_hub_registry.factory_secret_hash`; `409 DEVICE_NOT_CLAIMED` when no
   `iot_hubs` row exists; mint + hash `device_secret` on success.
2. `POST /v1/auth/token` — constant-time compare, mint opaque token, store
   SHA-256 hash with a 24 h expiry.
3. Auth middleware — resolve `Bearer` → `chickmark_private.iot_device_tokens` →
   `iot_hubs`, reject expired/revoked, load `customer_id`. **`customer_id` comes
   only from here.** Every subsequent query in the request filters on the
   resolved `(hub_id, customer_id)` pair, never on `hub_id` alone — including the
   pending-command selection in step 5.
4. `POST /v1/telemetry` —
   - dedup on `(hub_id, batch_id)` via `chickmark_private.iot_telemetry_batches`
     (private, because the device-facing counter is guessable), catching the
     unique-violation race the way `app-hatchery-agent` already does;
   - resolve each `sensor_uid` against `iot_sensors` scoped to this hub;
     auto-create unknown ones as `status='unassigned'`;
   - clamp timestamps, range-check against `iot_metric_registry`, flag
     `quality='suspect'` rather than dropping;
   - bulk insert with the **merging** upsert from §9.3
     (`metrics = metrics || excluded.metrics`), never `do nothing` — a re-split
     retry can deliver a partial metric set first, and dropping the fuller row
     that follows is silent data loss;
   - return `202` with `accepted` / `duplicates` / `rejected[]`.
5. `POST /v1/heartbeat` — update `iot_hubs` liveness columns, return
   `config_version`, `topology_stale`, `next_heartbeat_s`, and up to 10 pending
   commands (marking them `delivered`).
6. `POST /v1/events` and `POST /v1/topology` — including the server-side diff
   that raises `sensor_added` / `sensor_removed` itself.
7. Rate limiting per hub, in the DB-row-counting style already used by
   `app-hatchery-agent` and `pip-realtime-session`.

Acceptance: replaying an identical batch twice inserts once; a batch containing
one foreign `sensor_uid` still stores the good readings and reports the bad one;
a hub bound to customer A cannot write a row carrying customer B under any input.

---

## Phase 3 — Rollups and retention

1. Enable `pg_cron` (not currently installed).
2. Hourly job: fold the last complete hour into `iot_telemetry_hourly`.
3. Daily job: fold into `iot_telemetry_daily`, denormalising `hatchery_id` /
   `station_key` / `place` / `machine_id` from `iot_sensors` at fold time.
4. Monthly job: create next month's partition **via
   `chickmark_private.iot_add_telemetry_partition()`, so RLS is never
   forgotten**, drop partitions older than 90 days, prune
   `iot_telemetry_hourly` past 13 months. Alert on a non-zero row count in the
   default partition — rows landing there mean a maintenance run was missed or a
   device clock is wrong.
5. Backfill helper for a rollup gap after an outage.

Acceptance: rollup output for a synthetic day matches a direct aggregate over the
raw rows; dropping an old partition does not touch the rollups.

---

## Phase 4 — App surface

1. Hub claim screen: scan QR → `iot_claim_hub` RPC.
2. Device list: hubs with last-seen, sensors with binding and battery.
3. Sensor binding UI: assign `hatchery_id` / `station_key` / `place` /
   `machine_id` / `label` to an `unassigned` sensor. This is what turns raw data
   into dashboard data.
4. Command buttons (identify, reboot, force sync) writing `iot_commands` rows —
   plain RLS-protected inserts, no Edge Function needed.
5. Live environmental view reading `iot_telemetry_hourly` / `_daily`, reusing the
   existing Govee dashboard widgets.

---

## Phase 5 — Server-side alerting

1. Alert-rule table, seeded from the bands already hardcoded in Dart
   (`_GoveeTarget`, `AppThresholds.co2Max`, `SeverityThresholds`).
2. Evaluator on a `pg_cron` schedule, writing to a server-side alert table using
   the same `good` / `warn` / `err` vocabulary as `ScopeSeverity`.
3. Notification delivery — Telegram first, since `telegram_staff_links` already
   exists and is the shortest path to a farm manager's phone.
4. Only after the above: consider moving the Dart-side severity logic to read
   server alerts, so there is one implementation rather than two.

---

## Phase 6 — OTA

1. Firmware bucket in Supabase Storage, service-role write, no public read.
2. Signing: Ed25519 keypair, private key **offline** and never in the repo or in
   Supabase secrets; the public key is compiled into firmware.
3. Release upload tool: computes SHA-256, signs, inserts `iot_firmware_releases`.
4. `GET /v1/firmware` — cohort selection by `rollout_percent` (stable hash of
   `hub_id`, so a hub does not flap in and out of a cohort), returning a signed
   URL with a ~1 h TTL.
5. `POST /v1/firmware/status` — drive `iot_firmware_updates`, and auto-halt a
   rollout when the failure rate over the last N attempts crosses a threshold.

---

## Cross-cutting requirements

- **Deploy order.** Migration first, then `iot-gateway`. Never the reverse — the
  function will 500 against a schema that lacks its tables.
- **Secrets.** No new provider secrets. The function needs only `SUPABASE_URL` and
  `SUPABASE_SERVICE_ROLE_KEY`, both already present.
- **Logging.** Follow the Cloud Run service's discipline: stable event names and
  scalar fields only. Never log a `device_secret`, a `device_token`, an
  `espnow_pmk`, or a signed download URL.
- **Tests.** Deno tests colocated as `<module>_test.ts`, with injected fake deps,
  matching the existing pattern. Run:
  ```bash
  cd supabase/functions/iot-gateway && deno test --allow-env .
  ```
- **Docs.** Per `CLAUDE.md`, the commit that lands each phase must also update
  `docs/LIVING_SPEC.md` to describe the behaviour that now exists, and add a
  dated entry to `docs/CHANGELOG.md`.
- **No CI exists.** These checks are manual. Run the migration replay script
  before every schema push.

## Effort shape

| Phase | Rough size | Blocks firmware? |
|---|---|---|
| 0 — mock gateway | small | **Unblocks it. Do first.** |
| 1 — schema + RLS | medium | no |
| 2 — real ingestion | large | no |
| 3 — rollups/retention | medium | no |
| 4 — app surface | medium | no |
| 5 — alerting | large | no |
| 6 — OTA | medium | only OTA testing |

Phases 1–3 can run in parallel with all firmware work. Phase 4 needs Phase 2.
Phase 5 needs Phase 3.

## Open decisions for the product owner

These are hardware/product calls, not engineering ones. The first two need
answering **before the hub PCB is finalised**.

1. **Battery-backed RTC on the Hub? (recommend yes.)** About a dollar of BOM.
   Without it there is a genuine cold-boot problem: TLS certificate validation
   needs a roughly-correct clock, but the clock is set from the server over TLS.
   §7.1 of the contract documents a safe workaround, but the workaround relaxes
   certificate validity checking on exactly one bootstrap request. An RTC deletes
   the problem instead of managing it.
2. **SD card on the Hub? (recommend yes.)** Without one, an offline site buffers
   6–12 hours. With one, months. A hatchery that loses a weekend of environmental
   data because the DSL was down is the failure mode this whole system exists to
   prevent.
3. **Ethernet port on the Hub?** Optional, but it removes the single most common
   class of support call for sites with structured cabling.
4. **Sensor sampling interval.** 60 s is assumed throughout. Faster costs battery
   life and storage; slower risks missing short excursions that matter in a
   setter.
5. **Raw retention.** 90 days assumed. Longer is possible but the raw table is
   the bulk of the storage cost.
6. **Alert delivery channel.** Telegram is the shortest path because
   `telegram_staff_links` already exists. Push notifications would need new app
   plumbing.
