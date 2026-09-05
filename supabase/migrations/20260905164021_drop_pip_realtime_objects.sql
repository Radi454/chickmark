-- Forward-only cleanup: the Pip Live realtime voice path (OpenAI Realtime via
-- a Cloud Run sideband + the `pip-realtime-session` / `pip-realtime-tool-broker`
-- Edge Functions) has been removed from ChickMark. This drops the database
-- objects that existed solely for that path.
--
-- Deliberately NOT dropped:
--   * the columns added to the shared tables (`agent_conversation_turns`,
--     `agent_tool_events`, `agent_tool_call_claims`): historical rows written by
--     the live-voice channel still carry `source_channel = 'realtime_voice'`,
--     `realtime_session_id`, etc., and the text agent reads those rows as
--     durable conversation history. The columns are nullable and harmless.
--   * `allocate_agent_turn_slot`, `agent_conversation_summaries`,
--     `agent_memories`, `agent_tool_call_claims`: shared agent infrastructure
--     still used by the text doors.
--
-- Safe to re-run; every statement is `if exists`.

drop index if exists public.idx_agent_tool_events_realtime_call;
drop index if exists public.idx_agent_tool_events_realtime_sequence;
drop index if exists public.idx_agent_tool_events_interaction;
drop index if exists public.idx_agent_tool_call_claims_realtime_key;
drop index if exists public.idx_agent_tool_call_claims_interaction;
drop index if exists public.idx_agent_conversation_turns_realtime;

drop table if exists public.agent_realtime_response_usage;
drop table if exists public.agent_realtime_runtime_control;
drop table if exists public.agent_realtime_start_attempts;
drop table if exists public.agent_realtime_usage_seconds;
drop table if exists public.agent_realtime_calls;
drop table if exists public.agent_realtime_sessions;

drop function if exists public.realtime_now();
