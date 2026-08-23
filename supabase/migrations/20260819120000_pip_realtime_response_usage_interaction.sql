-- 20260819120000 pip_realtime_response_usage_interaction
--
-- Additive: one nullable column on the per-response token ledger.
--
-- WHY. `agent_realtime_response_usage` records one row per provider response,
-- but nothing on it says which USER UTTERANCE that response belonged to. The
-- question a production incident actually asks — "how many assistant responses
-- did this one thing the caller said produce?" — was therefore not answerable
-- from the database at all. It is exactly the question behind the repetition
-- incident of 2026-08-19, where one utterance produced an unbounded chain of
-- responses, and the only evidence was log lines with a short retention.
--
-- `agent_tool_events.realtime_interaction_id` already carries the same key for
-- tool calls, so this column makes the two ledgers joinable on the unit the
-- budget is actually enforced against.
--
-- Nullable on purpose: a response that arrives without a preceding
-- `response.created` (a redelivery, a truncated event stream) has no
-- attribution to record, and inventing one would be worse than a null. Rows
-- written before this column existed keep their null too.
--
-- DEPLOY ORDER: this must land BEFORE the sideband revision that writes the
-- column. PostgREST rejects an insert naming an unknown column with a 400, and
-- `#persistResponseUsage` swallows every failure by design (telemetry must
-- never break a live call) — so a sideband deployed first would silently write
-- no telemetry at all.

begin;

alter table public.agent_realtime_response_usage
  add column if not exists interaction_id text;

comment on column public.agent_realtime_response_usage.interaction_id is
  'The interaction (one user utterance plus the whole response chain it '
  'provoked) this response belonged to. Joins to '
  'agent_tool_events.realtime_interaction_id. Null when the response arrived '
  'with no preceding response.created to attribute it.';

create index if not exists idx_agent_realtime_response_usage_interaction
  on public.agent_realtime_response_usage(session_id, interaction_id);

commit;
