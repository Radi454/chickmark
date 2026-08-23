-- 20260819090000 pip_realtime_response_usage
--
-- Durable per-response token telemetry for the Pip Realtime production path.
--
-- `#onResponseDone` in the sideband (services/pip-realtime-sideband/src/
-- sideband.ts) already persists the assistant TURN off `response.done`, but
-- until now it threw away `event.response.usage` entirely — there was zero
-- token telemetry in production. This table is additive only: it does not
-- touch `agent_realtime_usage_seconds` (services/pip-realtime-sideband/src/
-- usage.ts), which keeps settling wall-clock seconds byte-identically.
--
-- Design constraints:
--
--   * Primary key (session_id, response_id) is the idempotency mechanism.
--     OpenAI's `response.done` can in principle be redelivered on the same
--     websocket reconnect/replay path the rest of this service already
--     defends against; a plain INSERT with this PK makes a duplicate insert
--     a no-op rather than a double-counted row, matching the
--     `resolution=ignore-duplicates` convention `insertUsageSlices` already
--     uses in store_postgrest.ts for the same reason.
--
--   * A failed or rate-limited response arrives with `status: 'failed'` and
--     `usage` all-zero or absent. That is itself signal we want recorded —
--     the row is written either way, never suppressed for being "empty".
--
--   * `owner_profile_id` / `tenant_id` are denormalized onto this table
--     exactly as `agent_realtime_usage_seconds` denormalizes them, so token
--     spend can be attributed and aggregated without a join back through
--     `agent_realtime_sessions` on every query.
--
--   * Every token column is `integer not null default 0 check (... >= 0)`:
--     the parser (`src/response_usage.ts`) never emits negative or non-
--     integer values, and the constraint is cheap insurance against a future
--     bug writing a bad row silently.
--
--   * RLS posture matches `agent_realtime_usage_seconds` exactly: enabled,
--     no policies at all. Every write path is service_role, which bypasses
--     RLS, and there is no plausible human diagnostic SELECT for a raw token
--     ledger the way there is for `agent_realtime_sessions`.

begin;

create table if not exists public.agent_realtime_response_usage (
  session_id text not null
    references public.agent_realtime_sessions(id) on delete cascade,
  response_id text not null,
  generation integer not null default 0,
  model text not null,
  status text not null,
  recorded_at timestamptz not null default now(),

  total_tokens integer not null default 0 check (total_tokens >= 0),
  input_tokens integer not null default 0 check (input_tokens >= 0),
  cached_input_tokens integer not null default 0 check (cached_input_tokens >= 0),
  uncached_input_tokens integer not null default 0
    check (uncached_input_tokens >= 0),
  input_text_tokens integer not null default 0 check (input_text_tokens >= 0),
  input_audio_tokens integer not null default 0 check (input_audio_tokens >= 0),
  input_image_tokens integer not null default 0 check (input_image_tokens >= 0),
  cached_text_tokens integer not null default 0 check (cached_text_tokens >= 0),
  cached_audio_tokens integer not null default 0 check (cached_audio_tokens >= 0),
  output_tokens integer not null default 0 check (output_tokens >= 0),
  output_text_tokens integer not null default 0 check (output_text_tokens >= 0),
  output_audio_tokens integer not null default 0 check (output_audio_tokens >= 0),

  followed_tool_call boolean not null default false,
  tool_names text[] not null default '{}',

  owner_profile_id uuid,
  tenant_id text,

  primary key (session_id, response_id)
);

create index if not exists idx_agent_realtime_response_usage_session
  on public.agent_realtime_response_usage(session_id);

create index if not exists idx_agent_realtime_response_usage_recorded
  on public.agent_realtime_response_usage(recorded_at desc);

create index if not exists idx_agent_realtime_response_usage_model
  on public.agent_realtime_response_usage(model, recorded_at desc);

alter table public.agent_realtime_response_usage enable row level security;

grant all on table public.agent_realtime_response_usage to service_role;

commit;
