-- Run as the database test administrator. Uses only transactional fixtures.
begin;
do $test$
declare
  sid text;
  hid text;
  admin_id text;
  expected_customer_id text;
  panel_key text := '__tombstone_scope_' || gen_random_uuid()::text;
  state_id text := gen_random_uuid()::text;
  node_id text := gen_random_uuid()::text;
  reservation_id text := gen_random_uuid()::text;
  machine_id text := gen_random_uuid()::text;
  state_tombstone text := gen_random_uuid()::text;
  node_tombstone text := gen_random_uuid()::text;
  reservation_tombstone text := gen_random_uuid()::text;
  machine_tombstone text := gen_random_uuid()::text;
  resolved text;
begin
  select s.id, s.hatchery_id, s.customer_id
    into sid, hid, expected_customer_id
    from public.audit_sessions s
   where s.hatchery_id is not null
   order by s.id limit 1;
  select p.id::text into admin_id
    from public.profiles p
   where p.status = 'approved' and p.role = 'admin'
   limit 1;
  if sid is null or hid is null or admin_id is null then
    raise exception 'Missing admin, audit session, or hatchery test context';
  end if;

  perform set_config('request.jwt.claim.sub', admin_id, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', admin_id, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.panel_sampling_states
    (id, session_id, panel_key, created_at, updated_at)
  values (state_id, sid, panel_key, now()::text, now()::text);
  insert into public.panel_sampling_nodes
    (id, session_id, panel_key, level, created_at, updated_at)
  values (node_id, sid, panel_key, 'tray', now()::text, now()::text);
  insert into public.panel_sample_serial_reservations
    (id, session_id, panel_key, sample_number, sample_id, created_at)
  values (reservation_id, sid, panel_key, 1, reservation_id, now()::text);
  insert into public.hatchery_machines
    (id, hatchery_id, kind, code, name, batch_size, trolley_capacity,
     tray_size, trolley_count, trays_per_trolley)
  values (machine_id, hid, 'setter', 'TOMB-' || left(machine_id, 8),
          'Tombstone test fixture', 1, 1, 1, 1, 1);

  insert into public.sync_tombstones (id, table_name, row_id, deleted_at, created_at)
  values
    (state_tombstone, 'panel_sampling_states', state_id, now()::text, now()::text),
    (node_tombstone, 'panel_sampling_nodes', node_id, now()::text, now()::text),
    (reservation_tombstone, 'panel_sample_serial_reservations', reservation_id, now()::text, now()::text),
    (machine_tombstone, 'hatchery_machines', machine_id, now()::text, now()::text);

  if exists (
    select 1 from public.sync_tombstones t
    where t.id in (state_tombstone, node_tombstone, reservation_tombstone)
      and t.customer_id is distinct from expected_customer_id
  ) then
    raise exception 'Sampling tombstone tenant scope mismatch';
  end if;
  select t.customer_id into resolved from public.sync_tombstones t where t.id = machine_tombstone;
  if resolved is distinct from expected_customer_id then
    raise exception 'Machine tombstone tenant scope mismatch';
  end if;

  -- Retry metadata updates cannot retarget or expand the stored event.
  update public.sync_tombstones
     set row_id = gen_random_uuid()::text,
         customer_id = gen_random_uuid()::text,
         audience_user_ids = '{}'::uuid[]
   where id = node_tombstone;
  select t.row_id into resolved from public.sync_tombstones t where t.id = node_tombstone;
  if resolved is distinct from node_id then
    raise exception 'Tombstone retry changed its target';
  end if;
  select t.customer_id into resolved from public.sync_tombstones t where t.id = node_tombstone;
  if resolved is distinct from expected_customer_id then
    raise exception 'Tombstone retry changed its customer';
  end if;
  if not exists (
    select 1 from public.sync_tombstones t
    where t.id = node_tombstone and admin_id::uuid = any(t.audience_user_ids)
  ) then
    raise exception 'Tombstone retry changed its audience';
  end if;
end;
$test$;
rollback;
