-- The sideband's attach WebSocket (wss://api.openai.com/v1/realtime?call_id=…)
-- rejects the standard API key with 404 call_id_not_found and accepts only the
-- ephemeral client secret that minted the call (proven against a live call,
-- 2026-08-17). The provisioner therefore persists the secret value on the call
-- row so the sideband can present it as the attach bearer.
--
-- Safety: agent_realtime_calls has row-level security enabled with ZERO client
-- policies — only the service role can read it — and the secret expires on its
-- own short TTL regardless.
alter table public.agent_realtime_calls
  add column if not exists client_secret text;

comment on column public.agent_realtime_calls.client_secret is
  'Ephemeral OpenAI client secret that minted this call. Required as the '
  'sideband attach bearer (the standard API key is rejected by the provider). '
  'Service-role-only; expires on its own TTL.';
