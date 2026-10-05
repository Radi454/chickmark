-- Sampling rows inherit their tenant from audit_sessions. Machine catalog rows
-- inherit their tenant from the owning hatchery. Keep the original tombstone
-- identity and audience rules unchanged for retries and existing table types.
create or replace function chickmark_private.prepare_sync_tombstone_scope()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  resolved_customer_id text;
begin
  if tg_op = 'UPDATE' then
    -- A retry may update sync metadata, but it cannot retarget a deletion event
    -- or expand the audience captured by the original insert.
    new.id := old.id;
    new.table_name := old.table_name;
    new.row_id := old.row_id;
    new.deleted_at := old.deleted_at;
    new.created_at := old.created_at;
    new.customer_id := old.customer_id;
    new.created_by := old.created_by;
    new.audience_user_ids := old.audience_user_ids;
    return new;
  end if;

  if new.table_name = 'customers' then
    resolved_customer_id := new.row_id;
  elsif new.table_name = 'photos' then
    select s.customer_id
      into resolved_customer_id
      from public.photos p
      join public.audit_sessions s on s.id = p.session_id
     where p.id = new.row_id;
  elsif new.table_name = any (array[
    'panel_sampling_states',
    'panel_sampling_nodes',
    'panel_sample_serial_reservations'
  ]) then
    execute format(
      'select s.customer_id from public.%I t join public.audit_sessions s on s.id = t.session_id where t.id = $1',
      new.table_name
    )
    into resolved_customer_id
    using new.row_id;
  elsif new.table_name = 'hatchery_machines' then
    select h.customer_id
      into resolved_customer_id
      from public.hatchery_machines m
      join public.hatcheries h on h.id = m.hatchery_id
     where m.id = new.row_id;
  elsif new.table_name = any (array[
    'hatcheries',
    'flocks',
    'audit_sessions',
    'govee_daily_captures',
    'dashboard_actions',
    'lab_analysis_reports',
    'lab_analysis_groups',
    'lab_analysis_rows',
    'egg_storage',
    'egg_quality',
    'chick_quality',
    'chick_weights',
    'fresh_egg_breakout',
    'candled_egg_breakout',
    'residue_breakout',
    'setter_optimizing',
    'hatcher_optimizing'
  ]) then
    execute format(
      'select t.customer_id from public.%I t where t.id = $1',
      new.table_name
    )
    into resolved_customer_id
    using new.row_id;
  else
    raise exception 'Unsupported tombstone target table'
      using errcode = '42501';
  end if;

  if resolved_customer_id is null then
    raise exception 'Tombstone target is missing or has no customer scope'
      using errcode = '42501';
  end if;

  new.customer_id := resolved_customer_id;
  new.created_by := (select auth.uid());

  if new.created_by is null
     and coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'Authenticated identity required for tombstone creation'
      using errcode = '42501';
  end if;

  select coalesce(array_agg(scoped.user_id), '{}'::uuid[])
    into new.audience_user_ids
    from (
      select p.id as user_id
      from public.profiles p
      where p.status = 'approved'
        and (
          p.role = 'admin'
          or (p.role = 'customer' and p.customer_id = resolved_customer_id)
          or (
            p.role = 'auditor'
            and exists (
              select 1
              from public.auditor_customers ac
              where ac.auditor_id = p.id
                and ac.customer_id = resolved_customer_id
            )
          )
        )
      union
      select new.created_by
    ) scoped
   where scoped.user_id is not null;

  return new;
end;
$$;

-- Preserve the function's existing execute boundary and trigger attachment.
revoke all on function chickmark_private.prepare_sync_tombstone_scope()
  from public, anon;
grant execute on function chickmark_private.prepare_sync_tombstone_scope()
  to authenticated, service_role;
