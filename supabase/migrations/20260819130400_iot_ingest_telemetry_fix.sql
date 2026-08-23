-- Fix iot_ingest_telemetry: it raised 0A000 on every call.
--
-- The original used `returning (xmax = 0)` to tell a fresh insert from a merge.
-- That trick works on an ordinary table but NOT on a partitioned one --
-- "cannot retrieve a system column in this context" -- and iot_telemetry is
-- partitioned by month. The function applied cleanly and only failed when a real
-- batch arrived, which is exactly the kind of bug that gets past a migration
-- replay and shows up in an end-to-end test.
--
-- Replacement: count the keys that already exist BEFORE inserting, then use
-- row_count (which counts inserted + updated) to derive the split. No system
-- columns involved.

create or replace function public.iot_ingest_telemetry(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_total    integer := coalesce(jsonb_array_length(p_rows), 0);
  v_existing integer := 0;
  v_affected integer := 0;
  v_inserted integer;
  v_merged   integer;
begin
  if v_total = 0 then
    return jsonb_build_object('accepted', 0, 'merged', 0, 'duplicates', 0);
  end if;

  -- How many of these (sensor, instant) keys do we already hold? The caller has
  -- already deduplicated within the batch, so this is exactly the set that will
  -- take the ON CONFLICT path.
  select count(*)
    into v_existing
    from jsonb_to_recordset(p_rows) as x(sensor_id uuid, measured_at timestamptz)
    join public.iot_telemetry t
      on t.sensor_id = x.sensor_id
     and t.measured_at = x.measured_at;

  insert into public.iot_telemetry as t
    (customer_id, hub_id, sensor_id, measured_at, batch_id, metrics, quality,
     battery_percent, rssi)
  select x.customer_id, x.hub_id, x.sensor_id, x.measured_at, x.batch_id, x.metrics,
         coalesce(x.quality, 'ok'), x.battery_percent, x.rssi
    from jsonb_to_recordset(p_rows) as x(
      customer_id     text,
      hub_id          uuid,
      sensor_id       uuid,
      measured_at     timestamptz,
      batch_id        text,
      metrics         jsonb,
      quality         text,
      battery_percent integer,
      rssi            integer)
  on conflict (sensor_id, measured_at) do update
    set metrics = t.metrics || excluded.metrics
    where t.metrics is distinct from (t.metrics || excluded.metrics);

  get diagnostics v_affected = row_count;

  v_inserted := v_total - v_existing;
  v_merged   := greatest(v_affected - v_inserted, 0);

  return jsonb_build_object(
    'accepted',   v_inserted,
    'merged',     v_merged,
    'duplicates', v_total - v_inserted - v_merged);
end $$;

revoke execute on function public.iot_ingest_telemetry(jsonb) from public, anon, authenticated;
grant  execute on function public.iot_ingest_telemetry(jsonb) to service_role;
