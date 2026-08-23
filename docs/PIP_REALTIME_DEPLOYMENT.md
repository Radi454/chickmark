# Pip Realtime V1 — Deployment Runbook

Everything in this feature is built and tested locally. Nothing is deployed.
This document is the gap: what must be provisioned, in what order, and which
behaviours **cannot** be verified until it is.

Read the "Honest status" section first. It says plainly what the green test
counts do and do not prove.

---

## Honest status

Every suite passes:

| Component | Tests |
|---|---|
| Flutter app | 1674 |
| `telegram-hatchery-agent` | 141 |
| `app-hatchery-agent` | 49 |
| `pip-realtime-session` | 59 |
| `pip-realtime-tool-broker` | 25 |
| `pip-realtime-sideband` | 124 |
| Migration replay (real PostgreSQL) | 18 assertions |

**What that proves:** each component honours its own contract against fakes
that enforce the real database constraints, and the migration replays cleanly
from an empty database.

**What it does not prove:** no test has exercised
Flutter → OpenAI → Cloud Run → PostgreSQL as one system. Every green test sits
on one side of a boundary. The client's fakes assert the API contract, not the
wire; the server's fakes assert its own store semantics. The wire contract
between them is pinned by literal shared frames
(`WIRE_CONTRACT.md`, asserted from both sides), which is the strongest guarantee
available without a deployment — but it is still an agreement about a format,
not evidence that traffic flows.

The single most important unverified claim is the security invariant:

> No microphone audio reaches the Realtime call before authoritative READY.

Unit tests prove the *API contract* (a null-track transceiver, `replaceTrack`
called exactly once and only after a validated READY). They cannot prove that a
null-track sender emits zero RTP on real libwebrtc and real browsers. **That
requires a device and a browser.** See "Device verification" below — treat it
as release-blocking.

---

## 0. Deployment log — 2026-08-17

What is actually deployed, verified at the time of writing.

**Supabase (`kgucchapksiiqxmiutsz`) — done**

- `20260816090000_profiles_username_column` applied. `handle_new_auth_user()`
  verified byte-identical to its pre-apply definition (md5
  `044bd4fcf09d341d9ff0bb17e6108cb7`), so account-type routing is untouched.
  This fixes the live signup break.
- `20260816120000_pip_realtime_v1_persistence` applied. 250 turns backfilled
  contiguously (188 `telegram` + 62 `app_text`), all 8 new tables present,
  `agent_realtime_runtime_control` seeded `enabled = true`, 89 tool events
  intact, `allocate_agent_turn_slot` and `realtime_now` service_role-only.
- Both were applied with `apply_migration`, which stamps a wall-clock version;
  both ledger rows were corrected back to their filename versions. Ledger is
  36 rows with **no local-only migrations**.
- Secret `PIP_REALTIME_BROKER_SECRET` set.
- `pip-realtime-tool-broker` v1 deployed with `verify_jwt = false`;
  `pip-realtime-session` v1 deployed with `verify_jwt = true`.
- Verified live: broker returns 401 with no secret AND with a wrong secret;
  session function returns 401 without a JWT.

**Google Cloud (`chickmark-ai-agent`, project number 604699737882) — partially done**

- APIs enabled: Run, Cloud Build, Secret Manager, Cloud Scheduler, Artifact
  Registry.
- Service accounts: `pip-realtime-sideband` (runtime),
  `pip-realtime-scheduler` (OIDC invoker).
- Secrets with accessor bindings for the runtime account:
  `pip-realtime-broker-secret`, `supabase-service-role-key`.
- Region chosen: `europe-west1` (nearest to Supabase `eu-west-1`).

**Google Cloud — deployed**

- `pip-realtime-sideband` revision `00001-xbx` serving at
  `https://pip-realtime-sideband-604699737882.europe-west1.run.app`,
  `--timeout=3600 --min-instances=1 --concurrency=80`, secrets pinned to
  version 1. Startup config validation passed (the service logs "Listening"
  only after every `PIP_REALTIME_*` value validates).
- Cloud Scheduler `pip-realtime-cleanup`, `* * * * *`, OIDC as
  `pip-realtime-scheduler`, with `roles/run.invoker`.
- The Cloud Build default compute account needed
  `cloudbuild.builds.builder`, `storage.objectViewer`,
  `artifactregistry.writer` and `logging.logWriter` before `--source`
  deploys worked.
- `PIP_REALTIME_CLOUD_RUN_URL` set on Supabase.

**Verified live in production**

- Cleanup: anonymous and bogus-bearer both 401; the scheduler's OIDC call
  returned 200.
- Signup: admin `createUser` returned 200 and produced a profile row — the
  path that previously raised `42703`. Confirmed with a throwaway user, since
  deleted.
- `start`: 200 with a real minted OpenAI client secret. Lifetimes measured
  against the returned `serverTime`: client secret +32s, binding token +60s,
  setup deadline +60s, session +600s — four distinct lifetimes, as designed.
- One-session invariant: a second `start` returned 409 `session_active`, and
  the refused attempt recorded `replaced`, which does not consume the
  rate-limit window.
- `register_call`: 200 advancing to `call_registered` and returning
  `"authority":"none"`; an identical repeat is idempotent; a different call id
  returns 409 `call_conflict`.
- Orphan sweeper: the never-bound generation reached `ended` with
  `setup_deadline_exceeded`, `hangup_state: failed` (correct — the id was
  synthetic, so OpenAI had nothing to hang up, and it terminalized anyway
  rather than sticking), session `cleanup_swept`.
- Usage: **zero** rows for a session that never reached READY. Reserved time
  is never charged.
- Preflight spike, finally run with a working key: `gpt-live-transcribe` is
  accepted on a normal `type: realtime` session together with
  `languages: ["ar","en"]` AND `prompt` — the model page claiming
  `v1/realtime` is unsupported is stale. `gpt-realtime-whisper` rejects
  `prompt`, confirming the trade-off. Tool-call events DO arrive on a
  server-side connection.

**Still outstanding**

1. The device RTP verification in §5 — the only release-blocking item left.

Until `PIP_REALTIME_CLOUD_RUN_URL` is set, `start` correctly reports
`realtime_unavailable` and nothing else is affected — typed Pip and recorded
voice are untouched by any of the above.

## 1. Prerequisites

- Supabase project `kgucchapksiiqxmiutsz`, already linked.
- A Google Cloud project with billing enabled. **Not yet created.**
- `OPENAI_API_KEY` — already a Supabase secret; must also be added to Google
  Secret Manager for Cloud Run.
- Database password, for applying migrations via `psql`.

---

## 2. Apply the pending migrations

Two migrations are written and replay-verified but **not applied to production**:

| Migration | What it does |
|---|---|
| `20260816090000_profiles_username_column.sql` | Fixes a live defect — see below |
| `20260816120000_pip_realtime_v1_persistence.sql` | The whole Realtime schema |

`supabase db push` must **not** be used (the ledger was reconciled by hand;
see the 2026-08-16 changelog entries). Apply each explicitly.

### 2a. The username hotfix is independent and urgent

`20260816090000` is not part of Realtime. It fixes a defect that is live right
now: `handle_new_auth_user()` still carries the legacy branch from the
never-applied `0009`, inserting a `username` column that does not exist. The
client sends no `account_type`, so **every self-serve signup falls into that
branch and raises `42703`**, aborting the `auth.users` insert — and the client
masks it as "Account created locally." `public.profiles` holds 2 rows, both
`internal`; no self-serve signup has ever succeeded. Admin → Users is also
broken, because `admin_repository.dart` selects `username`.

Apply it independently of Realtime. Do **not** apply
`migrations_unapplied/0009_customer_usernames.sql` — its
`create or replace function handle_new_auth_user()` would delete the
account-type routing added by `20260813172732`.

After applying, signup will *succeed* but land as `role='auditor',
status='pending'`, because the client still sends no `account_type`. Choosing
the intended self-serve account model is a separate product decision.

### 2b. Verify after applying

```sql
-- expect 1,1,1
select
  (select count(*) from information_schema.columns
    where table_schema='public' and table_name='profiles' and column_name='username'),
  (select count(*) from pg_indexes where indexname='profiles_username_lower_unique'),
  (select count(*) from pg_constraint where conname='profiles_username_format');

-- expect 8 new tables and both functions
select count(*) from information_schema.tables where table_schema='public'
  and table_name in ('agent_tool_call_claims','agent_conversation_summaries',
    'agent_memories','agent_realtime_sessions','agent_realtime_calls',
    'agent_realtime_usage_seconds','agent_realtime_start_attempts',
    'agent_realtime_runtime_control');
select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in ('allocate_agent_turn_slot','realtime_now');

-- the backfills must leave nothing null
select count(*) from public.agent_conversation_turns
  where conversation_seq is null or source_channel is null or completion_status is null;
```

Then confirm the ledger: `supabase migration list --linked` should show every
version matched except `20260418043712` (archived, pre-reset — expected).

---

## 3. Deploy the Edge Functions

```bash
supabase functions deploy pip-realtime-session
supabase functions deploy pip-realtime-tool-broker --no-verify-jwt
```

`pip-realtime-tool-broker` **must** use `--no-verify-jwt`: its caller is the
Cloud Run sideband, a server with no end-user JWT. It authenticates with a
shared secret instead, compared in constant time.

Secrets:

```bash
supabase secrets set PIP_REALTIME_BROKER_SECRET=<>=32 chars, random>
supabase secrets set PIP_REALTIME_CLOUD_RUN_URL=https://<service>.run.app
```

Until `PIP_REALTIME_CLOUD_RUN_URL` is set, `start` correctly reports
`realtime_unavailable` rather than half-starting a session.

`OPENAI_API_KEY` is already set. Realtime reads **only** that key — never
`OPENAI_VOICE_KEY` (legacy recorded voice) and never `OPENROUTER_API_KEY`.
A missing key makes Realtime unavailable; it never falls back.

---

## 4. Deploy Cloud Run

```bash
set -euo pipefail
PIP_POLICY_RENDER_JSON="$(deno run --allow-read services/pip-realtime-sideband/tools/render_agent_instructions.ts --json)"
PIP_REALTIME_INSTRUCTIONS="$(printf '%s' "$PIP_POLICY_RENDER_JSON" | jq -er '.PIP_REALTIME_INSTRUCTIONS')"
PIP_REALTIME_INSTRUCTIONS_VERSION="$(printf '%s' "$PIP_POLICY_RENDER_JSON" | jq -er '.PIP_REALTIME_INSTRUCTIONS_VERSION')"
[ -n "$PIP_REALTIME_INSTRUCTIONS" ] && [ -n "$PIP_REALTIME_INSTRUCTIONS_VERSION" ]

gcloud run deploy pip-realtime-sideband \
  --source services/pip-realtime-sideband \
  --region <region> \
  --timeout=3600 \
  --min-instances=1 \
  --concurrency=<peak concurrent voice sessions> \
  --set-secrets=OPENAI_API_KEY=openai-api-key:1,PIP_REALTIME_BROKER_SECRET=broker-secret:1 \
  --set-env-vars=SUPABASE_URL=...,PIP_REALTIME_TOOL_BROKER_URL=https://<project>.supabase.co/functions/v1/pip-realtime-tool-broker \
  --set-env-vars=PIP_REALTIME_TOOL_DEFINITIONS="$(deno run --allow-read services/pip-realtime-sideband/tools/render_tool_definitions.ts)" \
  --set-env-vars="^@^PIP_REALTIME_INSTRUCTIONS=$PIP_REALTIME_INSTRUCTIONS@PIP_REALTIME_INSTRUCTIONS_VERSION=$PIP_REALTIME_INSTRUCTIONS_VERSION"
```

`PIP_REALTIME_TOOL_DEFINITIONS` is **rendered, never hand-copied** — the
generator imports the versioned `AGENT_TOOL_CONTRACT` and emits the flat
Realtime shape. Cloud Run cannot import across deployments, so the catalogue
travels as config; startup validates it (non-empty, flat shape, unique names,
nested Chat-Completions shape rejected) and fails fast.

**Re-render it whenever `AGENT_TOOL_CONTRACT_VERSION` changes.** A stale value
means the model is offered tools the backend no longer honours.

`PIP_REALTIME_INSTRUCTIONS` and `PIP_REALTIME_INSTRUCTIONS_VERSION` are also
**rendered, never hand-copied**. Use `render_agent_instructions.ts` beside the
tool renderer and re-render both values whenever the policy version changes.
The Sideband refuses to start without nonblank values and logs the version only;
policy text must never be logged.

Size caveat: the rendered value is ~15 KB and Cloud Run caps *all* env vars at
32 KiB combined. If the catalogue grows, move it to a mounted secret or a
startup fetch.

Also set `PIP_REALTIME_BIND_DEADLINE_SECONDS` if the default of 5s does not
suit; it is validated to be strictly shorter than the setup deadline.

Four flags are not optional and each has a specific reason:

- **`--timeout=3600`** — the default is 300s, which would kill every voice
  session at 5 minutes. Sessions are capped at 600s plus cleanup headroom.
- **`--min-instances=1`** at *service* level — scale-to-zero is incompatible
  with long-lived WebSockets, and a cold start would sit in front of the first
  connection. This is a standing billed cost, not free-tier serverless.
- **`--concurrency`** — each held WebSocket occupies a slot for its entire
  600s life, so this is a hard ceiling on simultaneous voice users per instance.
- **Secret versions pinned** (`:1`, not `latest`) — with `latest`, a rotation
  leaves old and new instances disagreeing mid-fleet.

**SIGTERM grace is a fixed, non-configurable 10 seconds.** The drain path is
built to fit: one batched write marking owned generations `cleanup_pending`,
leases released, close frames pushed. OpenAI hangups are deliberately left to
the sweeper — they cannot fit in 10s.

### Cloud Scheduler

```bash
gcloud run services add-iam-policy-binding pip-realtime-sideband \
  --member=serviceAccount:<sa> --role=roles/run.invoker

gcloud scheduler jobs create http pip-realtime-cleanup \
  --schedule="* * * * *" \
  --uri=https://<service>.run.app/internal/cleanup \
  --http-method=POST \
  --oidc-service-account-email=<sa> \
  --oidc-token-audience=https://<service>.run.app
```

One minute is unix-cron's maximum frequency, which matches the design. The
audience must be the base service URL with no path or query.

---

## 4b. Environment inventory

Settings that exist on both sides use **identical names**, deliberately: the
session function enforces them, the sideband validates them at startup so a
misconfigured deployment fails immediately rather than mid-call. Setting one
side only is the classic way to get inconsistent behaviour, so set both.

### Supabase secrets (`supabase secrets set`)

| Name | Notes |
|---|---|
| `OPENAI_API_KEY` | Already set. The **only** credential Realtime may use |
| `PIP_REALTIME_BROKER_SECRET` | ≥32 random chars. Also set on Cloud Run |
| `PIP_REALTIME_CLOUD_RUN_URL` | https only. Until set, `start` reports `realtime_unavailable` |

Optional overrides, all defaulted in code: `PIP_REALTIME_ENABLED`,
`PIP_REALTIME_MAX_SESSION_SECONDS`, `PIP_REALTIME_SETUP_DEADLINE_SECONDS`,
`PIP_REALTIME_CLIENT_SECRET_TTL_SECONDS`, `PIP_REALTIME_BIND_TOKEN_TTL_SECONDS`,
`PIP_REALTIME_SESSION_START_LIMIT`, `PIP_REALTIME_SESSION_START_WINDOW_SECONDS`,
`PIP_REALTIME_DAILY_SECONDS_PER_PROFILE`, `PIP_REALTIME_DAILY_SECONDS_PER_TENANT`,
`PIP_REALTIME_TENANT_OVERAGE_FACTOR`, `PIP_REALTIME_MODEL`, `PIP_REALTIME_VOICE`,
`PIP_REALTIME_MAX_TOOL_CALLS_PER_INTERACTION`.

`OPENAI_VOICE_KEY` is **not** read by any Realtime component — it belongs to the
legacy recorded-voice path, and a test asserts Realtime ignores it.

### Cloud Run

Secrets (pin versions, never `latest`): `OPENAI_API_KEY`,
`PIP_REALTIME_BROKER_SECRET`.

Required env: `SUPABASE_URL`, `PIP_REALTIME_TOOL_BROKER_URL`,
`PIP_REALTIME_TOOL_DEFINITIONS`, `PIP_REALTIME_CLEANUP_AUDIENCE`,
`PIP_REALTIME_CLEANUP_SERVICE_ACCOUNTS`, `PIP_REALTIME_INSTRUCTIONS`,
`PIP_REALTIME_INSTRUCTIONS_VERSION`.

Sideband-only tuning: `PIP_REALTIME_BIND_DEADLINE_SECONDS` (default 5, must be
strictly shorter than the setup deadline), `PIP_REALTIME_HEARTBEAT_SECONDS`,
`PIP_REALTIME_LEASE_SECONDS` (heartbeat must be ≤ ½ lease),
`PIP_REALTIME_DRAIN_BUDGET_MS` (must be < the fixed 10s SIGTERM grace),
`PIP_REALTIME_TRANSCRIPTION_MODEL`, `PIP_REALTIME_TRANSCRIPTION_DELAY`,
`PIP_REALTIME_REASONING_EFFORT`, `PIP_REALTIME_OPENAI_REALTIME_URL`,
`PIP_REALTIME_TOOL_CONTRACT_VERSION`.

Every one of these is validated at startup and fails fast on a bad value —
nothing is silently clamped.

## 5. Device verification — release-blocking

These cannot be automated here and must be done before enabling for real users.

**The invariant.** On Web, in DevTools, with a session connected but before
READY:

```js
const stats = await pc.getStats();
[...stats.values()]
  .filter(s => s.type === 'outbound-rtp' && s.kind === 'audio')
  .map(s => ({ packetsSent: s.packetsSent, bytesSent: s.bytesSent }));
```

Expected: **an empty array, or `packetsSent === 0`**. An empty array is a pass —
with no track attached some stacks emit no report at all.

Do *not* verify this by checking `track.enabled`. A disabled track still sends
silence at roughly 40 kbps / 50 packets per second on Web; that is why the
implementation uses a null-track transceiver plus `replaceTrack` instead.

Repeat on iOS and Android via the plugin's `getStats`. Independently, confirm
server-side that no `input_audio_buffer.speech_started` arrives before READY —
that check holds on every platform and does not depend on the client being
honest.

**Also on device:**
- `track.stop()` actually clears the iOS mic indicator.
- The `AVAudioSession` gate holds with `record`, `audioplayers` and
  `flutter_webrtc` all present — "mic silently dead after an interruption" is a
  test case, not an edge case.
- Web autoplay: remote audio must start from within the user gesture that
  begins the session, or playback silently fails.
- `getUserMedia` needs a secure context — a LAN-IP dev server fails outright.
- Backgrounding and tab close release every track.

---

## 6. First-call checklist

1. `agent_realtime_runtime_control.enabled` is `true`.
2. Start a session; confirm a row appears in `agent_realtime_sessions` and a
   generation in `agent_realtime_calls` with `setup_state='provisioning'`.
3. Confirm the mic is silent until READY (section 5).
4. Confirm `setup_state` reaches `active` only after `session.updated`.
5. Ask a question that calls a tool. Confirm exactly one row in
   `agent_tool_call_claims` and one in `agent_tool_events`, with
   `conversation_turn_id` NULL initially and the claim's `inbound_turn_id`
   back-filled once the transcript finalizes.
6. End the session; confirm usage settles once in
   `agent_realtime_usage_seconds` and `usage_settled_at` is set.
7. Kill the client mid-setup; confirm the sweeper hangs up the orphaned call
   within ~2 minutes.
8. Deploy a new Cloud Run revision with a session active; confirm the client
   recovers and no OpenAI call is orphaned.

---

## 7. Rollback

- **Feature:** set `agent_realtime_runtime_control.enabled = false`. New
  sessions are refused; typed Pip and legacy recorded voice are unaffected. No
  deploy needed.
- **Emergency:** set `force_stop_at`; active sessions are fenced and terminated.
- **Schema:** the Realtime tables are additive and unused by any other path.
  `20260816090000` rolls back with
  `alter table public.profiles drop column username cascade;`.
- **Client:** legacy recorded voice is untouched and remains the fallback.

Legacy recorded voice is retained until **all** of: Realtime enabled on
Web/iOS/Android; canary green; 14 consecutive production days; no Sev-1/2
Realtime incident requiring fallback in that window; rollback validation green;
removal recorded in the changelog; and removal done as a separate approved task.

---

## 8. Known deployment-only unknowns

Each is handled defensively in code; none can be closed locally.

1. **`/v1/realtime/client_secrets` response shape** — the code tolerates both
   epoch-number and ISO-string `expires_at`, falling back to a locally computed
   expiry.
2. **Sideband auth header** — RESOLVED 2026-08-17. The subprotocol fallback
   (`openai-insecure-api-key.<KEY>`) turned out to be rejected outright by the
   attach endpoint for standard keys (HTTP 401 on every production bind), and
   Deno's header-capable `WebSocketStream` negotiates h2, which the endpoint
   answers with HTTP 400. The service now attaches with `npm:ws` over
   http/1.1 and a real `Authorization: Bearer` header, retries pre-open
   failures twice, and logs `sideband.attach_rejected` with HTTP status and a
   truncated body on a rejected handshake.
3. **`hangup` semantics for an already-closed call** — undocumented. Any
   non-2xx is treated as best-effort; hangup is idempotent our side.
4. **PostgREST CAS semantics** — `return=representation` row counts and 409 on
   partial unique indexes are assumed, not observed.
5. **Provider event ordering and redelivery** under production load.
6. **Google OIDC signature path** for the scheduler.
7. **`tool_sequence` retry budget** (5) under real concurrent load.
8. **Whether `channel.closeCode` surfaces private-range codes faithfully** on
   iOS/Android/web.

---

## 9. Deferred, explicitly not part of this work

- `migrations_unapplied/0017_performance_monitoring.sql` — 19 tables. Cannot
  apply as written: 9 `public.flocks` rows carry a `farm_id` with no `farms`
  row, so the FK fails immediately. Meanwhile 14 sync push tables have no cloud
  counterpart and fail **silently** — `SyncOutcome` has no `failed` field, so a
  user with unpushable data sees a successful sync. Adding that field is worth
  doing regardless; it will hide Realtime failures too.
- `migrations_unapplied/0009_customer_usernames.sql` — superseded, see §2a.
- The self-serve account model decision, see §2a.
