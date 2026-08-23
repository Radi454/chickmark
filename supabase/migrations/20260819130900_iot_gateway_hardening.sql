-- Hardening pass on the IoT gateway, from an adversarial review of the deployed
-- implementation against docs/IOT_API_CONTRACT.md.
--
-- 1. Commands had no producer at all. Twelve command types are specified and a
--    whole firmware state machine hangs off them, with nothing anywhere able to
--    enqueue one. Adds iot_enqueue_command, which also enforces the closed
--    command set server-side.
-- 2. iot_ack_commands discarded the device's completed_at and stamped now().
--    That defeats the one timing distinction section 12.5 exists for: telling a
--    successful reboot from a crash.
-- 3. iot_apply_topology's trailing UPDATEs scoped on hub_id alone, breaking the
--    rule the rest of the file follows. Not exploitable, but it is the one place
--    the invariant was not held.
-- 4. Telemetry partitions only ran to 2026-11, while section 7.2 accepts
--    measured_at up to 90 days old. A hub draining a long backlog already writes
--    into the default partition, and once a month's rows land there, creating
--    that month's partition later fails outright.

-- ---------------------------------------------------------------------------
-- 1. Command producer
-- ---------------------------------------------------------------------------

create or replace function public.iot_enqueue_command(
  p_hub_id       uuid,
  p_command_type text,
  p_params       jsonb default '{}'::jsonb,
  p_ttl_seconds  integer default 3600
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_customer_id text;
  v_id          uuid;
begin
  select h.customer_id into v_customer_id
    from public.iot_hubs h
   where h.id = p_hub_id and h.status = 'active';

  -- Unknown hub and unauthorised hub collapse into one answer, so this cannot
  -- be used to probe which hub ids exist.
  if v_customer_id is null
     or not chickmark_private.app_can_write_customer(v_customer_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  -- The command set is closed by design: there is no command that executes
  -- arbitrary code, and there never will be. Enforcing that here means a
  -- compromised app session still cannot invent one.
  if p_command_type not in (
    'reboot','force_sync','refresh_config','report_topology','identify_sensor',
    'identify_hub','run_diagnostic','start_calibration','pair_window_open',
    'forget_sensor','check_firmware','reprovision'
  ) then
    raise exception 'unknown_command_type' using errcode = '22023';
  end if;

  insert into public.iot_commands
    (customer_id, hub_id, command_type, params, created_by, expires_at)
  values
    (v_customer_id, p_hub_id, p_command_type, coalesce(p_params, '{}'::jsonb),
     (select auth.uid()),
     now() + make_interval(secs => greatest(60, least(coalesce(p_ttl_seconds, 3600), 86400))))
  returning id into v_id;

  return v_id;
end $$;

revoke execute on function public.iot_enqueue_command(uuid,text,jsonb,integer) from public, anon;
grant  execute on function public.iot_enqueue_command(uuid,text,jsonb,integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Honour the device's completed_at
-- ---------------------------------------------------------------------------

create or replace function public.iot_ack_commands(
  p_hub_id uuid, p_customer_id text, p_acks jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_ack       jsonb;
  v_updated   integer := 0;
  v_unknown   text[] := array[]::text[];
  v_hit       integer;
  v_terminal  boolean;
  v_status    text;
  v_completed timestamptz;
begin
  for v_ack in select * from jsonb_array_elements(p_acks) loop
    v_status := case v_ack->>'status'
                  when 'received'    then 'acked'
                  when 'succeeded'   then 'succeeded'
                  when 'failed'      then 'failed'
                  when 'unsupported' then 'unsupported'
                  when 'expired'     then 'expired'
                  else null
                end;
    if v_status is null then
      continue;
    end if;

    v_terminal := v_status in ('succeeded','failed','unsupported','expired');

    -- The device's own completion time, when it sent one. A hub that acks a
    -- reboot after coming back up must be able to say when it finished, not be
    -- stamped with the moment its message happened to arrive. Ignore a value
    -- that is implausible (more than 5 minutes ahead of the server).
    v_completed := null;
    if v_ack ? 'completed_at' and jsonb_typeof(v_ack->'completed_at') = 'number' then
      v_completed := to_timestamp((v_ack->>'completed_at')::double precision);
      if v_completed > now() + interval '5 minutes'
         or v_completed < now() - interval '90 days' then
        v_completed := null;
      end if;
    end if;

    update public.iot_commands c
       set status        = v_status,
           acked_at      = coalesce(c.acked_at, now()),
           completed_at  = case when v_terminal
                                then coalesce(v_completed, now())
                                else c.completed_at end,
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

revoke execute on function public.iot_ack_commands(uuid,text,jsonb) from public, anon, authenticated;
grant  execute on function public.iot_ack_commands(uuid,text,jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Scope the topology UPDATEs on customer_id too
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

  update public.iot_sensors s
     set status = case
           when s.station_key = '' and s.place = '' and s.machine_id = '' then 'unassigned'
           when coalesce(src.state, 'offline') = 'offline' then 'offline'
           else 'active' end,
         updated_at = now()
    from (select * from jsonb_to_recordset(p_sensors) as y(sensor_uid text, state text)) src
   where s.hub_id = p_hub_id and s.customer_id = p_customer_id
     and s.sensor_uid = src.sensor_uid
     and s.status <> 'retired';

  update public.iot_sensors s
     set status = 'offline', updated_at = now()
   where s.hub_id = p_hub_id and s.customer_id = p_customer_id
     and s.status in ('active','offline')
     and not exists (
       select 1 from jsonb_to_recordset(p_sensors) as z(sensor_uid text)
        where z.sensor_uid = s.sensor_uid);

  return v_count;
end $$;

revoke execute on function public.iot_apply_topology(uuid,text,jsonb) from public, anon, authenticated;
grant  execute on function public.iot_apply_topology(uuid,text,jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 4. Widen partition coverage: 5 months back (the 90-day backlog window plus
--    slack) and 12 months forward.
-- ---------------------------------------------------------------------------

do $$
declare i integer;
begin
  for i in -5..12 loop
    perform chickmark_private.iot_add_telemetry_partition(
      (date_trunc('month', now()) + (i || ' month')::interval)::date);
  end loop;
end $$;
