-- Move the four gateway-only IoT tables from chickmark_private into public.
--
-- Why: PostgREST only exposes `public`, so supabase-js -- which the iot-gateway
-- Edge Function uses with the service-role key -- cannot reach a table in
-- chickmark_private at all. The alternative was a SECURITY DEFINER wrapper RPC
-- per table, which is a lot of machinery for no additional safety.
--
-- The security guarantee is unchanged, and rests on three things rather than on
-- the schema name:
--   1. RLS enabled AND forced, with zero policies. RLS is default-deny, so
--      `authenticated` selects zero rows. Forcing it means even the table owner
--      (postgres) does not bypass.
--   2. All privileges revoked from anon and authenticated, so PostgREST refuses
--      the request outright rather than returning an empty set.
--   3. service_role keeps its grants and bypasses RLS. The gateway is the only
--      caller.
--
-- What matters for `iot_hub_secrets` specifically was never the schema: it was
-- keeping device_secret_hash off `iot_hubs`, which staff CAN update. That still
-- holds -- it is a separate table with no policies, so no staff session can read
-- or write it.

alter table chickmark_private.iot_hub_secrets      set schema public;
alter table chickmark_private.iot_device_tokens    set schema public;
alter table chickmark_private.iot_telemetry_batches set schema public;
alter table chickmark_private.iot_config_defaults  set schema public;

-- SET SCHEMA carries RLS flags and grants over, but re-assert both rather than
-- trusting that: a table in `public` with a missing revoke is a data leak, and
-- these four hold device credentials, bearer tokens and fleet-wide config.
do $$
declare t text;
begin
  foreach t in array array[
    'iot_hub_secrets', 'iot_device_tokens', 'iot_telemetry_batches', 'iot_config_defaults'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force  row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;
