-- Service-role ingestion RPCs for the iot-gateway Edge Function.
--
-- These exist because each is a multi-step operation that must be atomic, and
-- because supabase-js cannot express the one that matters most: telemetry needs
-- `on conflict do update set metrics = metrics || excluded.metrics`, a MERGE. A
-- plain upsert would overwrite, and `do nothing` would silently drop data
-- whenever a 413 forces the hub to re-split a batch and a partial metric set
-- arrives first.
--
-- They live in `public` because PostgREST only exposes `public`, but they are
-- revoked from anon and authenticated -- service_role only. The gateway is the
-- only caller.

-- ---------------------------------------------------------------------------
-- Telemetry ingest. Returns {accepted, merged, duplicates}.
--
-- The (xmax = 0) trick distinguishes a fresh insert from an update in RETURNING.
-- Rows whose merge would be a no-op are filtered by the WHERE and never come
-- back at all, so they fall out as `duplicates`.
--
-- The caller MUST deduplicate (sensor_id, measured_at) within p_rows first --
-- ON CONFLICT DO UPDATE cannot affect the same row twice in one statement.
-- ---------------------------------------------------------------------------
create or replace function public.iot_ingest_telemetry(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_inserted integer;
  v_merged   integer;
  v_total    integer := coalesce(jsonb_array_length(p_rows), 0);
begin
  if v_total = 0 then
    return jsonb_build_object('accepted', 0, 'merged', 0, 'duplicates', 0);
  end if;

  with src as (
    select * from jsonb_to_recordset(p_rows) as x(
      customer_id     text,
      hub_id          uuid,
      sensor_id       uuid,
      measured_at     timestamptz,
      batch_id        text,
      metrics         jsonb,
      quality         text,
      battery_percent integer,
      rssi            integer)
  ), ins as (
    insert into public.iot_telemetry as t
      (customer_id, hub_id, sensor_id, measured_at, batch_id, metrics, quality,
       battery_percent, rssi)
    select customer_id, hub_id, sensor_id, measured_at, batch_id, metrics,
           coalesce(quality, 'ok'), battery_percent, rssi
      from src
    on conflict (sensor_id, measured_at) do update
      set metrics = t.metrics || excluded.metrics
      where t.metrics is distinct from (t.metrics || excluded.metrics)
    returning (xmax = 0) as was_insert
  )
  select count(*) filter (where was_insert),
         count(*) filter (where not was_insert)
    into v_inserted, v_merged
    from ins;

  return jsonb_build_object(
    'accepted',   coalesce(v_inserted, 0),
    'merged',     coalesce(v_merged, 0),
    'duplicates', v_total - coalesce(v_inserted, 0) - coalesce(v_merged, 0));
end $$;

-- ---------------------------------------------------------------------------
-- Command acknowledgement. Idempotent on (command_id, status); a terminal status
-- can never be overwritten by a later non-terminal one, which is what stops a
-- late `received` ack from resurrecting a finished command.
--
-- Scoped by BOTH hub_id and customer_id. Never by hub_id alone.
-- ---------------------------------------------------------------------------
create or replace function public.iot_ack_commands(
  p_hub_id uuid, p_customer_id text, p_acks jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_ack      jsonb;
  v_updated  integer := 0;
  v_unknown  text[] := array[]::text[];
  v_hit      integer;
  v_terminal boolean;
begin
  for v_ack in select * from jsonb_array_elements(p_acks) loop
    v_terminal := (v_ack->>'status') in ('succeeded','failed','unsupported','expired');

    update public.iot_commands c
       set status        = v_ack->>'status',
           acked_at      = coalesce(c.acked_at, now()),
           completed_at  = case when v_terminal then now() else c.completed_at end,
           result        = coalesce(v_ack->'result', c.result),
           error_code    = coalesce(v_ack->>'error_code', c.error_code),
           error_message = coalesce(left(v_ack->>'error_message', 512), c.error_message),
           attempt_count = c.attempt_count + 1
     where c.id::text     = v_ack->>'command_id'
       and c.hub_id       = p_hub_id
       and c.customer_id  = p_customer_id
       and (v_terminal or c.status not in ('succeeded','failed','unsupported','expired'));

    get diagnostics v_hit = row_count;
    if v_hit > 0 then
      v_updated := v_updated + 1;
    else
      -- Either no such command for this hub, or it already holds a terminal
      -- status. Both are reported back as acknowledged-but-not-changed rather
      -- than as an error: re-sending an ack must stay safe.
      if exists (select 1 from public.iot_commands c
                  where c.id::text = v_ack->>'command_id'
                    and c.hub_id = p_hub_id and c.customer_id = p_customer_id) then
        v_updated := v_updated + 1;
      else
        v_unknown := v_unknown || (v_ack->>'command_id');
      end if;
    end if;
  end loop;

  return jsonb_build_object('acknowledged', v_updated, 'unknown', to_jsonb(v_unknown));
end $$;

-- ---------------------------------------------------------------------------
-- Device events. Idempotent on (hub_id, event_id).
-- ---------------------------------------------------------------------------
create or replace function public.iot_insert_events(
  p_hub_id uuid, p_customer_id text, p_events jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_accepted integer;
  v_total    integer := coalesce(jsonb_array_length(p_events), 0);
begin
  if v_total = 0 then
    return jsonb_build_object('accepted', 0, 'duplicates', 0);
  end if;

  with src as (
    select * from jsonb_to_recordset(p_events) as x(
      event_id    text,
      event_type  text,
      severity    text,
      occurred_at timestamptz,
      sensor_uid  text,
      detail      jsonb)
  ), ins as (
    insert into public.iot_device_events
      (customer_id, hub_id, sensor_id, event_id, event_type, severity, occurred_at, detail)
    select p_customer_id, p_hub_id, s.id, src.event_id, src.event_type,
           coalesce(src.severity, 'info'), src.occurred_at, coalesce(src.detail, '{}'::jsonb)
      from src
      left join public.iot_sensors s
        on s.hub_id = p_hub_id and s.sensor_uid = src.sensor_uid
    on conflict (hub_id, event_id) do nothing
    returning 1
  )
  select count(*) into v_accepted from ins;

  return jsonb_build_object(
    'accepted', coalesce(v_accepted, 0),
    'duplicates', v_total - coalesce(v_accepted, 0));
end $$;

-- ---------------------------------------------------------------------------
-- Topology snapshot. Full snapshot, not deltas -- snapshots are self-healing.
--
-- Staff bindings (hatchery_id, station_key, place, machine_id, label) are never
-- touched here. The hub does not know where it is installed; only the app does.
-- ---------------------------------------------------------------------------
create or replace function public.iot_apply_topology(
  p_hub_id uuid, p_customer_id text, p_sensors jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_count integer := 0;
begin
  with src as (
    select * from jsonb_to_recordset(p_sensors) as x(
      sensor_uid       text,
      model            text,
      firmware_version text,
      capabilities     jsonb,
      state            text,
      battery_percent  integer,
      rssi             integer,
      last_seen_at     timestamptz)
  ), up as (
    insert into public.iot_sensors as s
      (hub_id, customer_id, sensor_uid, model, firmware_version, capabilities,
       battery_percent, last_rssi, last_seen_at, status)
    select p_hub_id, p_customer_id, src.sensor_uid, src.model, src.firmware_version,
           coalesce(src.capabilities, '[]'::jsonb), src.battery_percent, src.rssi,
           src.last_seen_at, 'unassigned'
      from src
    on conflict (hub_id, sensor_uid) do update
      set model            = coalesce(excluded.model, s.model),
          firmware_version = coalesce(excluded.firmware_version, s.firmware_version),
          capabilities     = case when excluded.capabilities = '[]'::jsonb
                                  then s.capabilities else excluded.capabilities end,
          battery_percent  = coalesce(excluded.battery_percent, s.battery_percent),
          last_rssi        = coalesce(excluded.last_rssi, s.last_rssi),
          last_seen_at     = greatest(coalesce(excluded.last_seen_at, s.last_seen_at),
                                      coalesce(s.last_seen_at, excluded.last_seen_at)),
          updated_at       = now()
    returning 1
  )
  select count(*) into v_count from up;

  -- Liveness, derived from the snapshot. A sensor with no staff binding stays
  -- 'unassigned' however healthy it is -- that is what surfaces it in the app as
  -- needing a room/machine.
  update public.iot_sensors s
     set status = case
           when s.station_key = '' and s.place = '' and s.machine_id = '' then 'unassigned'
           when coalesce(src.state, 'offline') = 'offline' then 'offline'
           else 'active' end,
         updated_at = now()
    from (select * from jsonb_to_recordset(p_sensors) as y(sensor_uid text, state text)) src
   where s.hub_id = p_hub_id and s.sensor_uid = src.sensor_uid
     and s.status <> 'retired';

  -- Anything this hub no longer reports is offline, not deleted. A missing
  -- sensor and an offline sensor mean very different things to the customer.
  update public.iot_sensors s
     set status = 'offline', updated_at = now()
   where s.hub_id = p_hub_id
     and s.status in ('active','offline')
     and not exists (
       select 1 from jsonb_to_recordset(p_sensors) as z(sensor_uid text)
        where z.sensor_uid = s.sensor_uid);

  return v_count;
end $$;

do $$
declare fn text;
begin
  foreach fn in array array[
    'public.iot_ingest_telemetry(jsonb)',
    'public.iot_ack_commands(uuid,text,jsonb)',
    'public.iot_insert_events(uuid,text,jsonb)',
    'public.iot_apply_topology(uuid,text,jsonb)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant  execute on function %s to service_role', fn);
  end loop;
end $$;
