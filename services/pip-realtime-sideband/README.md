# Pip Realtime sideband/control service

Checkpoint 4 of the Pip Realtime V1 plan. A Deno service that runs on Cloud Run and owns
the **server side** of a Realtime voice session:

- terminates the client's control WebSocket and binds it (Supabase JWT + one-time binding
  token, both in the first application frame);
- claims a fenced lease on exactly one `(session, generation)`;
- attaches to the live call as a **sideband** and applies the session configuration;
- announces `ready` only when every precondition holds;
- claims, caps, executes and evidences tool calls;
- persists finalized transcripts as durable turns;
- hands work off fast on SIGTERM, and sweeps the leftovers from a scheduled cleanup
  endpoint;
- settles usage exactly once, split across UTC days.

Audio never passes through this service. The browser/app holds the WebRTC leg with OpenAI
directly; this is the control plane beside it.

## Layout

| File                     | Responsibility                                               |
| ------------------------ | ------------------------------------------------------------ |
| `src/config.ts`          | `PIP_REALTIME_*` configuration; invalid values fail startup  |
| `src/jwt.ts`             | Supabase ES256 verification against the project JWKS         |
| `src/oidc.ts`            | Google OIDC verification for the scheduler endpoint          |
| `src/binding.ts`         | First-frame bind: identity, authorization, one-time token    |
| `src/lease.ts`           | Lease claim, heartbeat, fencing, stale-worker stop           |
| `src/interaction.ts`     | Interaction attribution and the per-interaction tool cap     |
| `src/claims.ts`          | Claim-before-execute, immutable evidence, claim back-fill    |
| `src/sideband.ts`        | Provider socket, `session.update`, READY gate, transcripts   |
| `src/usage.ts`           | UTC-day splitting and exactly-once settlement                |
| `src/cleanup.ts`         | The scheduled sweeper (hangups, terminalization, settlement) |
| `src/drain.ts`           | SIGTERM batched handoff inside the fixed 10s grace           |
| `src/server.ts`          | HTTP + WebSocket entry, `/internal/cleanup`, `/healthz`      |
| `src/store.ts`           | The persistence port                                         |
| `src/store_postgrest.ts` | PostgREST implementation (no npm dependencies)               |

## Client protocol

The authoritative version of this section — frames, ordering, close codes, and why
captions never travel here — is [`WIRE_CONTRACT.md`](WIRE_CONTRACT.md).

The client connects to `wss://<service>/v1/realtime` and **must** send a bind frame as its
first application frame:

```json
{
  "type": "bind",
  "session_id": "...",
  "generation": 1,
  "access_token": "<supabase access token>",
  "binding_token": "<one-time token issued at provisioning>"
}
```

Credentials never appear in the URL and are never logged. No other frame is accepted
before binding succeeds. Afterwards the client sends:

- `{"type":"health","webrtc":true,"data_channel":true}` — transport health; READY is gated
  on both being true.
- `{"type":"bye"}` — graceful close.

The server sends `{"type":"ready",...}`, `{"type":"error","code":...}` and
`{"type":"closing","reason":...}`.

Close codes: `4400` malformed, `4401` bind rejected, `4408` bind timeout, `4409` lease
lost/fence mismatch, `4500` internal, `4503` draining.

Captions never travel on this socket — the app receives transcript deltas on its own
WebRTC data channel, straight from OpenAI.

## Environment variables

Required (no defaults — startup fails without them):

| Variable                        | Meaning                                                         |
| ------------------------------- | --------------------------------------------------------------- |
| `SUPABASE_URL`                  | Project URL, https only. JWKS and PostgREST are derived from it |
| `SUPABASE_SERVICE_ROLE_KEY`     | Service-role key for all authoritative writes                   |
| `OPENAI_API_KEY`                | Realtime sideband attach and hangup                             |
| `PIP_REALTIME_TOOL_BROKER_URL`  | https URL of the `pip-realtime-tool-broker` edge function       |
| `PIP_REALTIME_BROKER_SECRET`    | Shared secret for that endpoint. Never logged                   |
| `PIP_REALTIME_TOOL_DEFINITIONS` | The model-facing catalogue, as JSON (see below)                 |

`PIP_REALTIME_TOOL_DEFINITIONS` is RENDERED from the versioned `AGENT_TOOL_CONTRACT`,
never hand-written:

```bash
deno run --allow-read tools/render_tool_definitions.ts --env
```

The contract lives in the Supabase edge-function deployment and this service is a separate
image whose build copies only `main.ts` and `src/`, so it cannot be imported — it crosses
the boundary as configuration instead. Re-render and redeploy whenever the contract
version changes; nothing at runtime can tell a stale rendering from a fresh one. Startup
fails on an absent, malformed, empty or non-flat catalogue, because a sideband with no
tools looks healthy and can do nothing. `PIP_REALTIME_TOOL_CONTRACT_VERSION` is optional
and only recorded in the startup log line.

The rendered catalogue is ~15 KB and Cloud Run caps ALL environment variables at 32 KiB
combined, so it is the one value worth watching as the contract grows. The broker secret
belongs in Secret Manager (`--set-secrets`), not in `--set-env-vars`.

Operational defaults (override only with a validated value; out-of-range values fail
startup and are **never** clamped):

| Variable                                      | Default                                               |
| --------------------------------------------- | ----------------------------------------------------- |
| `PIP_REALTIME_ENABLED`                        | `true`                                                |
| `PIP_REALTIME_MAX_SESSION_SECONDS`            | `600` (provider ceiling 3600)                         |
| `PIP_REALTIME_SETUP_DEADLINE_SECONDS`         | `60`                                                  |
| `PIP_REALTIME_CLIENT_SECRET_TTL_SECONDS`      | `30` (provider range 10–7200)                         |
| `PIP_REALTIME_BIND_TOKEN_TTL_SECONDS`         | `60`                                                  |
| `PIP_REALTIME_BIND_DEADLINE_SECONDS`          | `5` (must be shorter than the setup deadline)         |
| `PIP_REALTIME_SESSION_START_LIMIT`            | `5`                                                   |
| `PIP_REALTIME_SESSION_START_WINDOW_SECONDS`   | `300`                                                 |
| `PIP_REALTIME_DAILY_SECONDS_PER_PROFILE`      | `1800`                                                |
| `PIP_REALTIME_DAILY_SECONDS_PER_TENANT`       | `14400`                                               |
| `PIP_REALTIME_TENANT_OVERAGE_FACTOR`          | `1.25`                                                |
| `PIP_REALTIME_HEARTBEAT_SECONDS`              | `10` (must be ≤ half the lease)                       |
| `PIP_REALTIME_LEASE_SECONDS`                  | `30`                                                  |
| `PIP_REALTIME_MAX_TOOL_CALLS_PER_INTERACTION` | `5`                                                   |
| `PIP_REALTIME_MODEL`                          | `gpt-realtime-2.1-mini`                               |
| `PIP_REALTIME_INSTRUCTIONS`                   | Required rendered shared ChickMark policy             |
| `PIP_REALTIME_INSTRUCTIONS_VERSION`           | Required rendered policy version                      |
| `PIP_REALTIME_VOICE`                          | `cedar`                                               |
| `PIP_REALTIME_TRANSCRIPTION_MODEL`            | `gpt-4o-mini-transcribe`                              |
| `PIP_REALTIME_TRANSCRIPTION_DELAY`            | `low` (enum: minimal/low/medium/high/xhigh)           |
| `PIP_REALTIME_TRANSCRIPTION_LANGUAGE`         | `ar` (two-letter ISO-639-1; `''` omits the field)     |
| `PIP_REALTIME_MAX_OUTPUT_TOKENS`              | `1536` (range 200-4096)                               |
| `PIP_REALTIME_REASONING_EFFORT`               | `low`                                                 |
| `PIP_REALTIME_TURN_DETECTION`                 | `semantic_vad` (enum: semantic_vad/server_vad)        |
| `PIP_REALTIME_VAD_EAGERNESS`                  | `low` (enum: low/medium/high/auto; semantic_vad only) |
| `PIP_REALTIME_VAD_SILENCE_MS`                 | `800` (range 200-2000; server_vad only)               |
| `PIP_REALTIME_DRAIN_BUDGET_MS`                | `7000` (must stay under the 10s grace)                |
| `PIP_REALTIME_OPENAI_REALTIME_URL`            | `wss://api.openai.com/v1/realtime`                    |

`semantic_vad` was probed live against `PIP_REALTIME_MODEL`'s default
(gpt-realtime-2.1-mini) with `tools/probe_turn_detection.ts` (2026-08-18) and is acked
with `session.updated` at `eagerness:'low'`; that probe is why it is the default instead
of `server_vad`. It is meant to end the user's turn on natural completion instead of on a
fixed silence timeout, so short pauses mid-sentence don't get cut off.
`PIP_REALTIME_VAD_SILENCE_MS` only affects `server_vad` and was raised from the previous
hardcoded 500ms to 800ms for the same reason.

Independent of the configured default, `src/sideband.ts` arms a one-shot runtime fallback:
if the provider rejects the initial `session.update` naming `turn_detection` (provider
drift, account-level support change, etc.) before the config is ever acknowledged, the
sideband resends once with `server_vad` forced rather than leaving the session running
with no tools/instructions. It never retries a second time — a persistently broken config
still fails loud (`sideband.provider_error` stays logged, READY is never announced)
instead of looping.

Required for the scheduler endpoint (both must be set or every call is refused):

| Variable                                | Meaning                                      |
| --------------------------------------- | -------------------------------------------- |
| `PIP_REALTIME_CLEANUP_AUDIENCE`         | OIDC audience the scheduler mints tokens for |
| `PIP_REALTIME_CLEANUP_SERVICE_ACCOUNTS` | Comma-separated allowlist of caller emails   |

## Deploy

```bash
set -euo pipefail
PIP_POLICY_RENDER_JSON="$(deno run --allow-read tools/render_agent_instructions.ts --json)"
PIP_REALTIME_INSTRUCTIONS="$(printf '%s' "$PIP_POLICY_RENDER_JSON" | jq -er '.PIP_REALTIME_INSTRUCTIONS')"
PIP_REALTIME_INSTRUCTIONS_VERSION="$(printf '%s' "$PIP_POLICY_RENDER_JSON" | jq -er '.PIP_REALTIME_INSTRUCTIONS_VERSION')"
[ -n "$PIP_REALTIME_INSTRUCTIONS" ] && [ -n "$PIP_REALTIME_INSTRUCTIONS_VERSION" ]

gcloud run deploy pip-realtime-sideband \
  --source=services/pip-realtime-sideband \
  --region=<REGION> \
  --platform=managed \
  --allow-unauthenticated \
  --timeout=3600 \
  --min-instances=1 \
  --max-instances=10 \
  --concurrency=50 \
  --cpu=1 --memory=512Mi \
  --cpu-always-allocated \
  --session-affinity \
  --set-env-vars=PIP_REALTIME_ENABLED=true \
  --set-secrets=SUPABASE_SERVICE_ROLE_KEY=supabase-service-role-key:1,OPENAI_API_KEY=openai-api-key:1,PIP_REALTIME_BROKER_SECRET=pip-realtime-broker-secret:1 \
  --set-env-vars=PIP_REALTIME_TOOL_BROKER_URL=https://<project>.supabase.co/functions/v1/pip-realtime-tool-broker \
  --set-env-vars="^@^PIP_REALTIME_TOOL_DEFINITIONS=$(deno run --allow-read tools/render_tool_definitions.ts)" \
  --set-env-vars="^@^PIP_REALTIME_INSTRUCTIONS=$PIP_REALTIME_INSTRUCTIONS@PIP_REALTIME_INSTRUCTIONS_VERSION=$PIP_REALTIME_INSTRUCTIONS_VERSION" \
  --set-env-vars=SUPABASE_URL=https://<project>.supabase.co,PIP_REALTIME_CLEANUP_AUDIENCE=https://<service-url>/internal/cleanup,PIP_REALTIME_CLEANUP_SERVICE_ACCOUNTS=pip-realtime-scheduler@<project>.iam.gserviceaccount.com
```

Render the policy again and redeploy whenever its version changes. Policy text is
deployment configuration: it must never be written to startup or runtime logs.

### Required order when the tool contract or shared tool sources change

When a change touches `AGENT_TOOL_CONTRACT` or any shared tool source it renders
from (e.g. a new/changed argument on an existing tool), deploy in this order:

1. Deploy the Supabase edge functions FIRST — `pip-realtime-tool-broker`,
   `telegram-hatchery-agent`, `app-hatchery-agent` — they bundle the shared tool
   sources directly.
2. THEN re-render env (`tools/render_agent_instructions.ts --json` and
   `tools/render_tool_definitions.ts --env`) and redeploy the Cloud Run sideband.

Reason: doing Cloud Run first exposes the new tool definition (e.g. an added
argument) to the model while the still-old broker rejects that argument via
`additionalProperties:false` — every call to that tool fails until the edge
functions catch up. Edge-first is benign: the broker accepts the new shape
before any client is told to send it.

> **`--allow-unauthenticated` is load-bearing — do NOT "harden" it.**
> This README previously said `--no-allow-unauthenticated`, and deploying that
> on 2026-08-19 took Pip Live down: every client bind was rejected by the Cloud
> Run IAM layer with "The request was not authenticated. Empty Authorization
> header value." before it ever reached the container, surfacing in the app as
> `bind: RealtimeSidebandException`.
>
> The app does not send a Google IAM token. This service authenticates every
> request ITSELF — bind tokens (`src/binding.ts`), JWT verification
> (`src/jwt.ts`), and authority re-resolution (`src/authorization.ts`) — and the
> one privileged endpoint, `/internal/cleanup`, is separately restricted by OIDC
> audience plus the `PIP_REALTIME_CLEANUP_SERVICE_ACCOUNTS` allowlist. Public
> invocability at the edge with application-layer authn/authz is the DESIGN, not
> an oversight; the cleanup allowlist would be pointless otherwise.
>
> Recovery, if it is ever removed again:
>
> ```bash
> gcloud run services add-iam-policy-binding pip-realtime-sideband \
>   --region=europe-west1 --project=chickmark-ai-agent \
>   --member=allUsers --role=roles/run.invoker
> ```
>
> Verify with a raw upgrade — a healthy service answers `101 Switching
> Protocols`, a locked-out one answers a Google `403`.

Also note: this gcloud version rejects `--cpu-always-allocated`; the equivalent
flag is `--no-cpu-throttling`.

Non-negotiable flags:

- `--timeout=3600` — the maximum. The default of 300s silently kills every session at five
  minutes.
- `--min-instances=1` — scale-to-zero is incompatible with held WebSockets.
- `--cpu-always-allocated` — a throttled instance cannot heartbeat its leases.

Each held WebSocket occupies a concurrency slot for its whole life, so `--concurrency` is
the per-instance session ceiling, not a throughput knob.

### Cleanup scheduler

```bash
gcloud scheduler jobs create http pip-realtime-cleanup \
  --location=<REGION> \
  --schedule="* * * * *" \
  --uri=https://<service-url>/internal/cleanup \
  --http-method=POST \
  --oidc-service-account-email=pip-realtime-scheduler@<project>.iam.gserviceaccount.com \
  --oidc-token-audience=https://<service-url>/internal/cleanup
```

The sweeper is the only component that performs OpenAI hangups. The SIGTERM path
deliberately does not: Cloud Run's grace period is a fixed, non-configurable 10 seconds,
so the drain does one batched database handoff to `cleanup_pending` and pushes close
frames, and the sweeper finishes the job on its next pass.

## Tests

```bash
cd services/pip-realtime-sideband && deno test -A
```

Everything is unit-tested against in-memory doubles: no network, no wall clock, no
database.
