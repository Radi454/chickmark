-- IoT core, part 2: RLS, claim RPC, metric vocabulary seed.
-- Applies on top of 20260819120000_iot_core_schema.sql. See docs/IOT_API_CONTRACT.md section 9.

-- ---------------------------------------------------------------------------
-- 5. RLS
--
-- Every table above appears exactly once below. Three were missing in an earlier
-- draft and every one of them was a cross-tenant hole, so the list is exhaustive
-- on purpose.
--
-- "RLS on, no policies" genuinely blocks authenticated: Supabase's stock default
-- privileges grant it full DML on new public tables, and 0007 revoked those
-- defaults only from anon -- so RLS is the only barrier, and it is default-deny.
-- force row level security is added anyway, because the table owner (postgres)
-- otherwise bypasses RLS entirely.
-- ---------------------------------------------------------------------------

-- iot_hubs: select + update only, and the COLUMN grant is what actually matters.
-- RLS has no column granularity, so without this a staff user could overwrite
-- status back to 'active' and undo a revocation, or edit any other column.
alter table public.iot_hubs enable row level security;
revoke all on public.iot_hubs from authenticated;
grant select (id, hub_serial, customer_id, hatchery_id, name, hardware_model,
              firmware_version, status, config_version, topology_hash,
              last_seen_at, last_telemetry_at, last_heartbeat, claimed_by,
              claimed_at, revoked_at, created_at, updated_at)
  on public.iot_hubs to authenticated;
grant update (name, hatchery_id, status) on public.iot_hubs to authenticated;

create policy iot_hubs_select on public.iot_hubs for select to authenticated
  using (chickmark_private.app_can_read_customer(customer_id));
create policy iot_hubs_update on public.iot_hubs for update to authenticated
  using (chickmark_private.app_can_write_customer(customer_id))
  with check (chickmark_private.app_can_write_customer(customer_id));

-- Standard tenant idiom.
do $$
declare t text;
begin
  foreach t in array array['iot_sensors','iot_device_events','iot_commands','iot_hub_config']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for select to authenticated
         using (chickmark_private.app_can_read_customer(customer_id))',
      t || '_select', t);
    execute format(
      'create policy %I on public.%I for all to authenticated
         using (chickmark_private.app_can_write_customer(customer_id))
         with check (chickmark_private.app_can_write_customer(customer_id))',
      t || '_write', t);
  end loop;
end $$;

-- Telemetry: readable by the tenant, written only by the gateway (service role).
alter table public.iot_telemetry enable row level security;
alter table public.iot_telemetry force  row level security;
create policy iot_telemetry_select on public.iot_telemetry for select to authenticated
  using (chickmark_private.app_can_read_customer(customer_id));

alter table public.iot_firmware_updates enable row level security;
create policy iot_firmware_updates_select on public.iot_firmware_updates
  for select to authenticated
  using (chickmark_private.app_can_read_customer(customer_id));

-- Metric vocabulary: world-readable, admin-writable. A tenant able to edit
-- min_plausible/max_plausible could flag the whole fleet's data as suspect.
create policy iot_metric_registry_read on public.iot_metric_registry
  for select to authenticated using (true);
create policy iot_metric_registry_admin_write on public.iot_metric_registry
  for all to authenticated
  using (chickmark_private.app_is_admin())
  with check (chickmark_private.app_is_admin());

-- ---------------------------------------------------------------------------
-- 6. Claim RPC
-- ---------------------------------------------------------------------------

create or replace function public.iot_claim_hub(
  p_hub_serial  text,
  p_claim_code  text,
  p_hatchery_id text,
  p_name        text default ''
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_customer_id text;
  v_reg         public.iot_hub_registry%rowtype;
  v_hub_id      uuid;
  v_code_hash   text;
begin
  -- Resolve the hatchery and the caller's authority over it in ONE branch, so a
  -- non-existent hatchery is indistinguishable from an unauthorised one and this
  -- cannot be used to enumerate hatchery ids across tenants.
  select h.customer_id into v_customer_id
    from public.hatcheries h where h.id = p_hatchery_id;
  if v_customer_id is null
     or not chickmark_private.app_can_write_customer(v_customer_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  -- Lock the registry row: makes check-then-insert atomic and serialises
  -- concurrent claims of the same serial behind one another.
  select * into v_reg from public.iot_hub_registry r
    where r.hub_serial = p_hub_serial for update;

  if v_reg.claim_locked_until is not null and v_reg.claim_locked_until > now() then
    raise exception 'claim_locked' using errcode = '55P03';
  end if;

  v_code_hash := encode(sha256(convert_to(upper(trim(coalesce(p_claim_code,''))), 'UTF8')), 'hex');

  -- One indistinguishable branch for "no such serial" and "wrong code".
  if v_reg.hub_serial is null or v_reg.claim_code_hash is distinct from v_code_hash then
    update public.iot_hub_registry
       set claim_attempts     = claim_attempts + 1,
           claim_locked_until = case when claim_attempts + 1 >= 5
                                     then now() + interval '15 minutes' end
     where hub_serial = p_hub_serial;
    raise exception 'invalid_claim' using errcode = '22023';
  end if;

  insert into public.iot_hubs (hub_serial, customer_id, hatchery_id, name,
                               hardware_model, claimed_by)
  values (p_hub_serial, v_customer_id, p_hatchery_id, coalesce(p_name, ''),
          v_reg.hardware_model, (select auth.uid()))
  returning id into v_hub_id;

  update public.iot_hub_registry
     set claimed_at = now(), claim_attempts = 0, claim_locked_until = null
   where hub_serial = p_hub_serial;

  insert into chickmark_private.iot_hub_secrets (hub_id)
    values (v_hub_id) on conflict (hub_id) do nothing;
  insert into public.iot_hub_config (hub_id, customer_id)
    values (v_hub_id, v_customer_id) on conflict (hub_id) do nothing;
  return v_hub_id;
exception
  when unique_violation then
    raise exception 'already_claimed' using errcode = '23505';
end $$;

revoke execute on function public.iot_claim_hub(text,text,text,text) from public, anon;
grant  execute on function public.iot_claim_hub(text,text,text,text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Metric vocabulary seed
--
-- The unit is part of the key on purpose. ChickMark already has real
-- unit-ambiguity pain (egg storage in C, setters in F, Govee in F) and a
-- self-describing key removes an entire class of bug.
-- ---------------------------------------------------------------------------

insert into public.iot_metric_registry
  (metric_key, unit, display_name, category, min_plausible, max_plausible)
values
  ('temperature_c',            'degC',  'Temperature',            'climate', -40,    85),
  ('humidity_rh',              '%RH',   'Relative humidity',      'climate',   0,   100),
  ('co2_ppm',                  'ppm',   'CO2',                    'gas',       0, 40000),
  ('nh3_ppm',                  'ppm',   'Ammonia',                'gas',       0,   500),
  ('pressure_pa',              'Pa',    'Pressure',               'climate', 80000,120000),
  ('differential_pressure_pa', 'Pa',    'Differential pressure',  'climate', -500,   500),
  ('air_velocity_mps',         'm/s',   'Air velocity',           'airflow',   0,    30),
  ('light_lux',                'lux',   'Light',                  'climate',   0,150000),
  ('water_flow_lpm',           'L/min', 'Water flow',             'water',     0,   500),
  ('water_pressure_kpa',       'kPa',   'Water pressure',         'water',     0,  1000),
  ('battery_percent',          '%',     'Battery',                'power',     0,   100),
  ('power_w',                  'W',     'Power',                  'power',     0, 50000),
  ('door_state',               'bool',  'Door state',             'status',    0,     1),
  ('vibration_g',              'g',     'Vibration',              'status',    0,    16)
on conflict (metric_key) do nothing;
