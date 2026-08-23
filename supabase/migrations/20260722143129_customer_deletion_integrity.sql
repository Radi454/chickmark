-- 20260722143129 customer_deletion_integrity
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- Make customer deletion one authorized, atomic database operation.
-- Storage objects are removed by the authenticated client before this RPC;
-- every relational child is then removed by PostgreSQL foreign-key cascades.

do $$
declare
  target record;
  relation_oid regclass;
  existing_name text;
  existing_delete_action "char";
begin
  for target in
    select *
    from (values
      ('public.hatcheries', 'customer_id', 'hatcheries_customer_id_fkey'),
      ('public.flocks', 'customer_id', 'flocks_customer_id_fkey'),
      ('public.audit_sessions', 'customer_id', 'audit_sessions_customer_id_fkey'),
      ('public.govee_daily_captures', 'customer_id', 'govee_daily_captures_customer_id_fkey'),
      ('public.egg_storage', 'customer_id', 'egg_storage_customer_id_fkey'),
      ('public.egg_quality', 'customer_id', 'egg_quality_customer_id_fkey'),
      ('public.chick_quality', 'customer_id', 'chick_quality_customer_id_fkey'),
      ('public.chick_weights', 'customer_id', 'chick_weights_customer_id_fkey'),
      ('public.fresh_egg_breakout', 'customer_id', 'fresh_egg_breakout_customer_id_fkey'),
      ('public.candled_egg_breakout', 'customer_id', 'candled_egg_breakout_customer_id_fkey'),
      ('public.residue_breakout', 'customer_id', 'residue_breakout_customer_id_fkey'),
      ('public.setter_optimizing', 'customer_id', 'setter_optimizing_customer_id_fkey'),
      ('public.hatcher_optimizing', 'customer_id', 'hatcher_optimizing_customer_id_fkey'),
      ('public.dashboard_actions', 'customer_id', 'dashboard_actions_customer_id_fkey'),
      ('public.lab_analysis_reports', 'customer_id', 'lab_analysis_reports_customer_id_fkey'),
      ('public.lab_analysis_groups', 'customer_id', 'lab_analysis_groups_customer_id_fkey'),
      ('public.lab_analysis_rows', 'customer_id', 'lab_analysis_rows_customer_id_fkey')
    ) as targets(relation_name, column_name, constraint_name)
  loop
    relation_oid := to_regclass(target.relation_name);
    if relation_oid is null then
      continue;
    end if;

    existing_name := null;
    existing_delete_action := null;
    select constraint_row.conname, constraint_row.confdeltype
      into existing_name, existing_delete_action
      from pg_constraint as constraint_row
      join pg_attribute as column_row
        on column_row.attrelid = constraint_row.conrelid
       and column_row.attnum = constraint_row.conkey[1]
     where constraint_row.conrelid = relation_oid
       and constraint_row.contype = 'f'
       and constraint_row.confrelid = 'public.customers'::regclass
       and array_length(constraint_row.conkey, 1) = 1
       and column_row.attname = target.column_name
     limit 1;

    if existing_name is not null and existing_delete_action <> 'c' then
      execute format(
        'alter table %s drop constraint %I',
        target.relation_name,
        existing_name
      );
      existing_name := null;
    end if;

    if existing_name is null then
      execute format(
        'alter table %s add constraint %I foreign key (%I) references public.customers(id) on delete cascade',
        target.relation_name,
        target.constraint_name,
        target.column_name
      );
    end if;
  end loop;
end
$$;

-- Photos have no customer_id of their own, so their session edge is the final
-- required link in the customer cascade.
do $$
declare
  existing_name text;
  existing_delete_action "char";
begin
  select constraint_row.conname, constraint_row.confdeltype
    into existing_name, existing_delete_action
    from pg_constraint as constraint_row
    join pg_attribute as column_row
      on column_row.attrelid = constraint_row.conrelid
     and column_row.attnum = constraint_row.conkey[1]
   where constraint_row.conrelid = 'public.photos'::regclass
     and constraint_row.contype = 'f'
     and constraint_row.confrelid = 'public.audit_sessions'::regclass
     and array_length(constraint_row.conkey, 1) = 1
     and column_row.attname = 'session_id'
   limit 1;

  if existing_name is not null and existing_delete_action <> 'c' then
    execute format(
      'alter table public.photos drop constraint %I',
      existing_name
    );
    existing_name := null;
  end if;

  if existing_name is null then
    alter table public.photos
      add constraint photos_session_id_fkey
      foreign key (session_id)
      references public.audit_sessions(id)
      on delete cascade;
  end if;
end
$$;

create or replace function public.delete_customer_cascade(p_customer_id text)
  returns table (deleted_id text)
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authenticated identity required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.customers as customer
    where customer.id = p_customer_id
  ) then
    -- A retry after the database commit but before the device marked its local
    -- tombstone synced is successful only for the captured deletion audience.
    if exists (
      select 1
      from public.sync_tombstones as tombstone
      where tombstone.id = 'customers:' || p_customer_id
        and (
          tombstone.created_by = (select auth.uid())
          or (select auth.uid()) = any (tombstone.audience_user_ids)
          or chickmark_private.app_is_admin()
        )
    ) then
      return query select p_customer_id;
      return;
    end if;

    raise exception 'Customer not found'
      using errcode = 'P0002';
  end if;

  if not chickmark_private.app_can_write_customer(p_customer_id) then
    raise exception 'Customer delete is not permitted'
      using errcode = '42501';
  end if;

  insert into public.sync_tombstones (
    id,
    table_name,
    row_id,
    deleted_at,
    created_at
  ) values (
    'customers:' || p_customer_id,
    'customers',
    p_customer_id,
    now()::text,
    now()::text
  )
  on conflict (id) do nothing;

  return query
    delete from public.customers as customer
    where customer.id = p_customer_id
    returning customer.id;

  if not found then
    raise exception 'Customer delete did not affect a row'
      using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.delete_customer_cascade(text) from public, anon;
grant execute on function public.delete_customer_cascade(text) to authenticated, service_role;

