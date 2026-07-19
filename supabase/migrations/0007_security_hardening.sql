-- 0007 security hardening
--
-- Keeps authorization helpers out of the exposed public API schema, requires
-- approved status for administrators, scopes deletion tombstones to the users
-- who were authorized at deletion time, and removes anonymous database grants.

-- ============================ private authorization helpers ============================
create schema if not exists chickmark_private;
revoke all on schema chickmark_private from public, anon;
grant usage on schema chickmark_private to authenticated, service_role;

create or replace function chickmark_private.app_role()
  returns text
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select p.role
  from public.profiles p
  where p.id = (select auth.uid());
$$;

create or replace function chickmark_private.app_status()
  returns text
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select p.status
  from public.profiles p
  where p.id = (select auth.uid());
$$;

create or replace function chickmark_private.app_customer_id()
  returns text
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select p.customer_id
  from public.profiles p
  where p.id = (select auth.uid());
$$;

create or replace function chickmark_private.app_is_admin()
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.status = 'approved'
  );
$$;

create or replace function chickmark_private.app_is_staff()
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role in ('admin', 'auditor')
      and p.status = 'approved'
  );
$$;

create or replace function chickmark_private.app_can_read_customer(cid text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.status = 'approved'
      and (
        p.role = 'admin'
        or (p.role = 'customer' and p.customer_id = cid)
        or (
          p.role = 'auditor'
          and exists (
            select 1
            from public.auditor_customers ac
            where ac.auditor_id = p.id
              and ac.customer_id = cid
          )
        )
      )
  );
$$;

create or replace function chickmark_private.app_can_write_customer(cid text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.status = 'approved'
      and (
        p.role = 'admin'
        or (
          p.role = 'auditor'
          and exists (
            select 1
            from public.auditor_customers ac
            where ac.auditor_id = p.id
              and ac.customer_id = cid
          )
        )
      )
  );
$$;

revoke all on all functions in schema chickmark_private from public, anon;
grant execute on all functions in schema chickmark_private
  to authenticated, service_role;

-- Trigger functions remain in public because their triggers already reference
-- them, but direct API roles cannot execute them.
create or replace function public.handle_new_auth_user()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email, role, status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email,
    'auditor',
    'pending'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.handle_new_customer()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if chickmark_private.app_role() = 'auditor' then
    insert into public.auditor_customers (auditor_id, customer_id)
    values ((select auth.uid()), new.id)
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create or replace function public.touch_updated_at()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================ tenant policies ============================
drop policy if exists profiles_select_self on public.profiles;
drop policy if exists profiles_admin_write on public.profiles;
create policy profiles_select_self on public.profiles for select to authenticated
  using (id = (select auth.uid()) or chickmark_private.app_is_admin());
create policy profiles_admin_write on public.profiles for all to authenticated
  using (chickmark_private.app_is_admin())
  with check (chickmark_private.app_is_admin());

drop policy if exists ac_admin_all on public.auditor_customers;
drop policy if exists ac_auditor_read on public.auditor_customers;
create policy ac_admin_all on public.auditor_customers for all to authenticated
  using (chickmark_private.app_is_admin())
  with check (chickmark_private.app_is_admin());
create policy ac_auditor_read on public.auditor_customers for select to authenticated
  using (
    auditor_id = (select auth.uid())
    and chickmark_private.app_status() = 'approved'
  );

do $$
declare
  t text;
begin
  foreach t in array array['bmk_breeds', 'bmk_egg_breakout'] loop
    execute format('drop policy if exists %I_read on public.%I', t, t);
    execute format('drop policy if exists %I_admin_write on public.%I', t, t);
    execute format(
      'create policy %I_read on public.%I for select to authenticated using (true)',
      t,
      t
    );
    execute format(
      'create policy %I_admin_write on public.%I for all to authenticated using (chickmark_private.app_is_admin()) with check (chickmark_private.app_is_admin())',
      t,
      t
    );
  end loop;
end
$$;

drop policy if exists customers_select on public.customers;
drop policy if exists customers_insert on public.customers;
drop policy if exists customers_update on public.customers;
drop policy if exists customers_delete on public.customers;
create policy customers_select on public.customers for select to authenticated
  using (chickmark_private.app_can_read_customer(id));
create policy customers_insert on public.customers for insert to authenticated
  with check (chickmark_private.app_is_staff());
create policy customers_update on public.customers for update to authenticated
  using (chickmark_private.app_can_write_customer(id))
  with check (chickmark_private.app_can_write_customer(id));
create policy customers_delete on public.customers for delete to authenticated
  using (chickmark_private.app_can_write_customer(id));

do $$
declare
  t text;
begin
  foreach t in array array[
    'hatcheries',
    'flocks',
    'audit_sessions',
    'govee_daily_captures',
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
    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format('drop policy if exists %I_write on public.%I', t, t);
    execute format(
      'create policy %I_select on public.%I for select to authenticated using (chickmark_private.app_can_read_customer(customer_id))',
      t,
      t
    );
    execute format(
      'create policy %I_write on public.%I for all to authenticated using (chickmark_private.app_can_write_customer(customer_id)) with check (chickmark_private.app_can_write_customer(customer_id))',
      t,
      t
    );
  end loop;
end
$$;

drop policy if exists photos_select on public.photos;
drop policy if exists photos_write on public.photos;
create policy photos_select on public.photos for select to authenticated
  using (
    exists (
      select 1
      from public.audit_sessions s
      where s.id = photos.session_id
        and chickmark_private.app_can_read_customer(s.customer_id)
    )
  );
create policy photos_write on public.photos for all to authenticated
  using (
    exists (
      select 1
      from public.audit_sessions s
      where s.id = photos.session_id
        and chickmark_private.app_can_write_customer(s.customer_id)
    )
  )
  with check (
    exists (
      select 1
      from public.audit_sessions s
      where s.id = photos.session_id
        and chickmark_private.app_can_write_customer(s.customer_id)
    )
  );

drop policy if exists dashboard_actions_read on public.dashboard_actions;
drop policy if exists dashboard_actions_write on public.dashboard_actions;
create policy dashboard_actions_read on public.dashboard_actions for select to authenticated
  using (chickmark_private.app_can_read_customer(customer_id));
create policy dashboard_actions_write on public.dashboard_actions for all to authenticated
  using (chickmark_private.app_can_write_customer(customer_id))
  with check (chickmark_private.app_can_write_customer(customer_id));

drop policy if exists lab_analysis_reports_read on public.lab_analysis_reports;
drop policy if exists lab_analysis_reports_write on public.lab_analysis_reports;
create policy lab_analysis_reports_read on public.lab_analysis_reports for select to authenticated
  using (chickmark_private.app_can_read_customer(customer_id));
create policy lab_analysis_reports_write on public.lab_analysis_reports for all to authenticated
  using (chickmark_private.app_can_write_customer(customer_id))
  with check (chickmark_private.app_can_write_customer(customer_id));

drop policy if exists lab_analysis_groups_read on public.lab_analysis_groups;
drop policy if exists lab_analysis_groups_write on public.lab_analysis_groups;
create policy lab_analysis_groups_read on public.lab_analysis_groups for select to authenticated
  using (chickmark_private.app_can_read_customer(customer_id));
create policy lab_analysis_groups_write on public.lab_analysis_groups for all to authenticated
  using (chickmark_private.app_can_write_customer(customer_id))
  with check (chickmark_private.app_can_write_customer(customer_id));

drop policy if exists lab_analysis_rows_read on public.lab_analysis_rows;
drop policy if exists lab_analysis_rows_write on public.lab_analysis_rows;
create policy lab_analysis_rows_read on public.lab_analysis_rows for select to authenticated
  using (chickmark_private.app_can_read_customer(customer_id));
create policy lab_analysis_rows_write on public.lab_analysis_rows for all to authenticated
  using (chickmark_private.app_can_write_customer(customer_id))
  with check (chickmark_private.app_can_write_customer(customer_id));

drop policy if exists photos_read on storage.objects;
drop policy if exists photos_write on storage.objects;
create policy photos_read on storage.objects for select to authenticated
  using (
    bucket_id = 'photos'
    and exists (
      select 1
      from public.audit_sessions s
      where s.id = split_part(name, '/', 1)
        and chickmark_private.app_can_read_customer(s.customer_id)
    )
  );
create policy photos_write on storage.objects for all to authenticated
  using (
    bucket_id = 'photos'
    and exists (
      select 1
      from public.audit_sessions s
      where s.id = split_part(name, '/', 1)
        and chickmark_private.app_can_write_customer(s.customer_id)
    )
  )
  with check (
    bucket_id = 'photos'
    and exists (
      select 1
      from public.audit_sessions s
      where s.id = split_part(name, '/', 1)
        and chickmark_private.app_can_write_customer(s.customer_id)
    )
  );

-- ============================ tenant-scoped deletion events ============================
alter table public.sync_tombstones
  add column if not exists customer_id text,
  add column if not exists created_by uuid,
  add column if not exists audience_user_ids uuid[] not null default '{}'::uuid[];

create index if not exists idx_sync_tombstones_customer
  on public.sync_tombstones(customer_id, deleted_at);

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

revoke all on function chickmark_private.prepare_sync_tombstone_scope()
  from public, anon;
grant execute on function chickmark_private.prepare_sync_tombstone_scope()
  to authenticated, service_role;

drop trigger if exists sync_tombstones_prepare_scope
  on public.sync_tombstones;
create trigger sync_tombstones_prepare_scope
  before insert or update on public.sync_tombstones
  for each row execute function chickmark_private.prepare_sync_tombstone_scope();

drop policy if exists authenticated_all on public.sync_tombstones;
drop policy if exists tombstones_staff on public.sync_tombstones;
drop policy if exists tombstones_select on public.sync_tombstones;
drop policy if exists tombstones_insert on public.sync_tombstones;
drop policy if exists tombstones_update on public.sync_tombstones;
drop policy if exists tombstones_delete on public.sync_tombstones;

create policy tombstones_select on public.sync_tombstones for select to authenticated
  using (
    chickmark_private.app_is_admin()
    or (select auth.uid()) = any (audience_user_ids)
  );
create policy tombstones_insert on public.sync_tombstones for insert to authenticated
  with check (
    chickmark_private.app_is_admin()
    or (
      created_by = (select auth.uid())
      and chickmark_private.app_can_write_customer(customer_id)
    )
  );
create policy tombstones_update on public.sync_tombstones for update to authenticated
  using (
    chickmark_private.app_is_admin()
    or created_by = (select auth.uid())
  )
  with check (
    chickmark_private.app_is_admin()
    or created_by = (select auth.uid())
  );
create policy tombstones_delete on public.sync_tombstones for delete to authenticated
  using (chickmark_private.app_is_admin());

-- ============================ remove exposed helper RPCs and anonymous grants ============================
drop function if exists public.app_can_read_customer(text);
drop function if exists public.app_can_write_customer(text);
drop function if exists public.app_is_staff();
drop function if exists public.app_is_admin();
drop function if exists public.app_customer_id();
drop function if exists public.app_status();
drop function if exists public.app_role();

revoke execute on all functions in schema public from public, anon;
revoke execute on function public.handle_new_auth_user()
  from authenticated;
revoke execute on function public.handle_new_customer()
  from authenticated;
revoke execute on function public.touch_updated_at()
  from authenticated;

do $$
begin
  if to_regprocedure('public.chickmark_keep_only_ghareeb_customers()') is not null then
    execute
      'revoke execute on function public.chickmark_keep_only_ghareeb_customers() from public, anon, authenticated';
  end if;
end
$$;

revoke all privileges on all tables in schema public from anon;
revoke all privileges on all sequences in schema public from anon;
revoke select, insert, update, delete on table storage.objects from anon;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all privileges on tables from anon;
alter default privileges for role postgres in schema public
  revoke all privileges on sequences from anon;
