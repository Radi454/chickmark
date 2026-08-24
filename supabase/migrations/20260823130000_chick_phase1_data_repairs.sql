-- Chick Quality Phase 1 data repairs.
--
-- 1. Chick CVT readings are canonical Fahrenheit. Convert only payloads whose
--    own stored unit tag explicitly says Celsius; Fahrenheit and untagged rows
--    are intentionally untouched.
-- 2. A panel row belongs to its audit session's local calendar date. Repair
--    only rows whose date provably disagrees with that parent session.

do $repair_chick_cvt$
declare
  source_row record;
  payload jsonb;
  raw_readings jsonb;
  converted_readings jsonb;
  stored_unit text;
begin
  for source_row in
    select
      id,
      cvt_readings_json,
      cvt_top_temp,
      cvt_middle_temp,
      cvt_bottom_temp,
      cvt_avg_temp
    from public.chick_quality
    where cvt_readings_json is not null
      and btrim(cvt_readings_json) <> ''
  loop
    begin
      payload := source_row.cvt_readings_json::jsonb;
    exception
      when invalid_text_representation then
        continue;
    end;

    if jsonb_typeof(payload) <> 'object' then
      continue;
    end if;
    stored_unit := lower(btrim(payload ->> 'unit'));
    if stored_unit not in ('c', '°c', 'celsius') then
      continue;
    end if;

    raw_readings := payload -> 'readings';
    if jsonb_typeof(raw_readings) = 'object' then
      select jsonb_object_agg(
        reading.key,
        case
          when jsonb_typeof(reading.value) = 'number' then
            to_jsonb((((reading.value #>> '{}')::numeric * 9 / 5) + 32))
          when jsonb_typeof(reading.value) = 'string'
               and (reading.value #>> '{}') ~ '^[+-]?[0-9]+([.][0-9]+)?$' then
            to_jsonb(((((reading.value #>> '{}')::numeric * 9 / 5) + 32)))
          else reading.value
        end
      )
      into converted_readings
      from jsonb_each(raw_readings) as reading;
    elsif jsonb_typeof(raw_readings) = 'array' then
      select jsonb_agg(
        case
          when jsonb_typeof(reading.value) = 'number' then
            to_jsonb((((reading.value #>> '{}')::numeric * 9 / 5) + 32))
          when jsonb_typeof(reading.value) = 'string'
               and (reading.value #>> '{}') ~ '^[+-]?[0-9]+([.][0-9]+)?$' then
            to_jsonb(((((reading.value #>> '{}')::numeric * 9 / 5) + 32)))
          else reading.value
        end
        order by reading.ordinality
      )
      into converted_readings
      from jsonb_array_elements(raw_readings) with ordinality as reading(value, ordinality);
    else
      continue;
    end if;

    update public.chick_quality
    set cvt_readings_json = jsonb_set(
          payload,
          '{readings}',
          coalesce(converted_readings, raw_readings)
        )::text,
        cvt_top_temp = case
          when source_row.cvt_top_temp is null then null
          else (source_row.cvt_top_temp * 9 / 5) + 32
        end,
        cvt_middle_temp = case
          when source_row.cvt_middle_temp is null then null
          else (source_row.cvt_middle_temp * 9 / 5) + 32
        end,
        cvt_bottom_temp = case
          when source_row.cvt_bottom_temp is null then null
          else (source_row.cvt_bottom_temp * 9 / 5) + 32
        end,
        cvt_avg_temp = case
          when source_row.cvt_avg_temp is null then null
          else (source_row.cvt_avg_temp * 9 / 5) + 32
        end,
        updated_at = now()
    where id = source_row.id;
  end loop;
end
$repair_chick_cvt$;

do $repair_panel_dates$
declare
  panel_table text;
begin
  foreach panel_table in array array[
    'egg_storage',
    'egg_quality',
    'chick_quality',
    'chick_weights',
    'fresh_egg_breakout',
    'candled_egg_breakout',
    'residue_breakout',
    'setter_optimizing',
    'hatcher_optimizing'
  ] loop
    execute format($sql$
      update public.%I as panel
      set date = session.date,
          updated_at = now()
      from public.audit_sessions as session
      where session.id = panel.session_id
        and panel.date is distinct from session.date
    $sql$, panel_table);
  end loop;
end
$repair_panel_dates$;

do $repair_photo_row_ids$
declare
  panel_table text;
  unresolved_count integer;
begin
  foreach panel_table in array array[
    'egg_storage',
    'egg_quality',
    'chick_quality',
    'chick_weights',
    'fresh_egg_breakout',
    'candled_egg_breakout',
    'residue_breakout',
    'setter_optimizing',
    'hatcher_optimizing'
  ] loop
    execute format($sql$
      update public.photos as photo
      set panel_row_id = (
        select min(panel.id)
        from public.%I as panel
        where panel.session_id = photo.session_id
          and left(panel.id, length(photo.panel_row_id) + 1) = photo.panel_row_id || ':'
      )
      where photo.panel_name = %L
        and not exists (
          select 1 from public.%I as exact_row
          where exact_row.id = photo.panel_row_id
        )
        and 1 = (
          select count(*)
          from public.%I as candidate
          where candidate.session_id = photo.session_id
            and left(candidate.id, length(photo.panel_row_id) + 1) = photo.panel_row_id || ':'
        )
    $sql$, panel_table, panel_table, panel_table, panel_table);

    execute format($sql$
      select count(*)
      from public.photos as photo
      where photo.panel_name = %L
        and not exists (
          select 1 from public.%I as exact_row
          where exact_row.id = photo.panel_row_id
        )
    $sql$, panel_table, panel_table)
    into unresolved_count;
    if unresolved_count > 0 then
      raise warning 'chickmark: left % public.photos row(s) unresolved for panel % because no unambiguous panel row matched',
        unresolved_count, panel_table;
    end if;
  end loop;
end
$repair_photo_row_ids$;
