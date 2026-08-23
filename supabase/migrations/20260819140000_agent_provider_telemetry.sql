-- 20260819140000 agent_provider_telemetry
--
-- Adds a nullable column for the text agent's per-turn provider telemetry
-- (see `AgentTurnTelemetry` in
-- supabase/functions/telegram-hatchery-agent/agent_runtime.ts): provider,
-- primary/fallback model, whether a fallback occurred and why, provider
-- response ids, latency, and call counts, aggregated across every
-- `respond()` call the turn made. Written on the outbound turn insert in
-- both doors (app-hatchery-agent/index.ts, telegram-hatchery-agent/index.ts).
--
-- Nullable, no backfill, no default, no RLS change: existing rows and the
-- existing agent_conversation_turns_admin_select policy are untouched. A
-- failed turn never writes an outbound row at all (see the structured
-- agent_turn_telemetry log line for that case instead), so this column is
-- expected to stay null on inbound rows and on any outbound row written
-- before this migration.

begin;

alter table public.agent_conversation_turns
  add column if not exists provider_telemetry_json jsonb;

commit;
