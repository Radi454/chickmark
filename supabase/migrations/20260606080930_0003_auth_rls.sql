-- 0003 auth + per-tenant RLS
--
-- Replaces the first-pass `authenticated_all (using true)` policies from 0001/0002 with
-- real isolation. Three roles:
--   * admin    -> everything
--   * auditor  -> only customers mapped in auditor_customers; read + write
--   * customer -> only own profiles.customer_id; READ ONLY (dashboards + bmk)
--
-- Identity source of truth = public.profiles (keyed by auth.uid()).
-- Auditor scope = public.auditor_customers (many-to-many).
-- All scope checks are SECURITY DEFINER helpers so policies never recurse and never
-- depend on the caller being able to read profiles/mapping directly.

-- ============================ identity tables ============================
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  email       text,
  role        text not null default 'auditor'  check (role   in ('admin','auditor','customer')),
  status      text not null default 'pending'  check (status in ('pending','approved','disabled')),
  customer_id text references public.customers(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.profiles enable row level security;

create table if not exists public.auditor_customers (
  auditor_id  uuid not null references auth.users(id)     on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (auditor_id, customer_id)
);
create index if not exists idx_auditor_customers_customer on public.auditor_customers(customer_id);
alter table public.auditor_customers enable row level security;

-- ============================ scope helpers (SECURITY DEFINER) ============================
create or replace function public.app_role()
  returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.app_status()
  returns text language sql stable security definer set search_path = public as $$
  select status from public.profiles where id = auth.uid();
$$;

create or replace function public.app_customer_id()
  returns text language sql stable security definer set search_path = public as $$
  select customer_id from public.profiles where id = auth.uid();
$$;

create or replace function public.app_is_admin()
  returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.app_role() = 'admin', false);
$$;

-- approved staff = admin or auditor
create or replace function public.app_is_staff()
  returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.app_role() in ('admin','auditor') and public.app_status() = 'approved', false);
$$;

create or replace function public.app_can_read_customer(cid text)
  returns boolean language sql stable security definer set search_path = public as $$
  select public.app_is_admin()
      or (public.app_role() = 'auditor'  and public.app_status() = 'approved'
          and exists (select 1 from public.auditor_customers ac
                      where ac.auditor_id = auth.uid() and ac.customer_id = cid))
      or (public.app_role() = 'customer' and public.app_status() = 'approved'
          and public.app_customer_id() = cid);
$$;

create or replace function public.app_can_write_customer(cid text)
  returns boolean language sql stable security definer set search_path = public as $$
  select public.app_is_admin()
      or (public.app_role() = 'auditor' and public.app_status() = 'approved'
          and exists (select 1 from public.auditor_customers ac
                      where ac.auditor_id = auth.uid() and ac.customer_id = cid));
$$;

-- ============================ triggers ============================
-- Auto-create a profile for every new auth user (defaults: auditor / pending -> admin approves).
create or replace function public.handle_new_auth_user()
  returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email, role, status)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'full_name', new.email),
          new.email, 'auditor', 'pending')
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- When an auditor creates a customer, auto-map them so they can read/write it afterwards.
create or replace function public.handle_new_customer()
  returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.app_role() = 'auditor' then
    insert into public.auditor_customers (auditor_id, customer_id)
    values (auth.uid(), new.id)
    on conflict do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists on_customer_created on public.customers;
create trigger on_customer_created after insert on public.customers
  for each row execute function public.handle_new_customer();

-- keep profiles.updated_at fresh
create or replace function public.touch_updated_at()
  returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end;
$$;
drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ============================ identity-table policies ============================
drop policy if exists authenticated_all   on public.profiles;
drop policy if exists profiles_select_self on public.profiles;
drop policy if exists profiles_admin_write on public.profiles;
create policy profiles_select_self on public.profiles for select to authenticated
  using (id = auth.uid() or public.app_is_admin());
-- only admin mutates roles/status/links; self-update of own role is impossible (no self policy)
create policy profiles_admin_write on public.profiles for all to authenticated
  using (public.app_is_admin()) with check (public.app_is_admin());

drop policy if exists ac_admin_all   on public.auditor_customers;
drop policy if exists ac_auditor_read on public.auditor_customers;
create policy ac_admin_all on public.auditor_customers for all to authenticated
  using (public.app_is_admin()) with check (public.app_is_admin());
create policy ac_auditor_read on public.auditor_customers for select to authenticated
  using (auditor_id = auth.uid());

-- ============================ reference data: bmk (read all, write admin) ============================
do $$
declare t text;
begin
  foreach t in array array['bmk_breeds','bmk_egg_breakout'] loop
    execute format('drop policy if exists authenticated_all on public.%I', t);
    execute format('drop policy if exists %I_read on public.%I', t, t);
    execute format('drop policy if exists %I_admin_write on public.%I', t, t);
    execute format('create policy %I_read on public.%I for select to authenticated using (true)', t, t);
    execute format('create policy %I_admin_write on public.%I for all to authenticated using (public.app_is_admin()) with check (public.app_is_admin())', t, t);
  end loop;
end $$;

-- ============================ customers (scoped) ============================
drop policy if exists authenticated_all  on public.customers;
drop policy if exists customers_select    on public.customers;
drop policy if exists customers_insert    on public.customers;
drop policy if exists customers_update    on public.customers;
drop policy if exists customers_delete    on public.customers;
create policy customers_select on public.customers for select to authenticated
  using (public.app_can_read_customer(id));
create policy customers_insert on public.customers for insert to authenticated
  with check (public.app_is_staff());
create policy customers_update on public.customers for update to authenticated
  using (public.app_can_write_customer(id)) with check (public.app_can_write_customer(id));
create policy customers_delete on public.customers for delete to authenticated
  using (public.app_can_write_customer(id));

-- ============================ tenant tables with a customer_id column ============================
do $$
declare t text;
begin
  foreach t in array array[
    'hatcheries','flocks','audit_sessions','govee_daily_captures',
    'egg_storage','egg_quality','chick_quality','chick_weights',
    'fresh_egg_breakout','candled_egg_breakout','residue_breakout',
    'setter_optimizing','hatcher_optimizing'
  ] loop
    execute format('drop policy if exists authenticated_all on public.%I', t);
    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format('drop policy if exists %I_write  on public.%I', t, t);
    execute format(
      'create policy %I_select on public.%I for select to authenticated using (public.app_can_read_customer(customer_id))', t, t);
    execute format(
      'create policy %I_write on public.%I for all to authenticated using (public.app_can_write_customer(customer_id)) with check (public.app_can_write_customer(customer_id))', t, t);
  end loop;
end $$;

-- ============================ photos (scoped via parent audit_session) ============================
drop policy if exists authenticated_all on public.photos;
drop policy if exists photos_select     on public.photos;
drop policy if exists photos_write      on public.photos;
create policy photos_select on public.photos for select to authenticated using (
  exists (select 1 from public.audit_sessions s
          where s.id = photos.session_id and public.app_can_read_customer(s.customer_id)));
create policy photos_write on public.photos for all to authenticated using (
  exists (select 1 from public.audit_sessions s
          where s.id = photos.session_id and public.app_can_write_customer(s.customer_id)))
  with check (
  exists (select 1 from public.audit_sessions s
          where s.id = photos.session_id and public.app_can_write_customer(s.customer_id)));

-- ============================ sync tombstones (staff only; customer is read-only) ============================
drop policy if exists authenticated_all on public.sync_tombstones;
drop policy if exists tombstones_staff  on public.sync_tombstones;
create policy tombstones_staff on public.sync_tombstones for all to authenticated
  using (public.app_is_staff()) with check (public.app_is_staff());

-- ============================ storage: photos bucket (scoped via path = <sessionId>/...) ============================
drop policy if exists photos_authenticated_all on storage.objects;
drop policy if exists photos_read  on storage.objects;
drop policy if exists photos_write on storage.objects;
create policy photos_read on storage.objects for select to authenticated using (
  bucket_id = 'photos' and exists (
    select 1 from public.audit_sessions s
    where s.id = split_part(name, '/', 1) and public.app_can_read_customer(s.customer_id)));
create policy photos_write on storage.objects for all to authenticated using (
  bucket_id = 'photos' and exists (
    select 1 from public.audit_sessions s
    where s.id = split_part(name, '/', 1) and public.app_can_write_customer(s.customer_id)))
  with check (
  bucket_id = 'photos' and exists (
    select 1 from public.audit_sessions s
    where s.id = split_part(name, '/', 1) and public.app_can_write_customer(s.customer_id)));

-- ============================ backfill: keep existing users working (no lockout) ============================
-- Every current auth user -> approved auditor; mapped to every existing customer.
insert into public.profiles (id, full_name, email, role, status)
select u.id, coalesce(u.raw_user_meta_data->>'full_name', u.email), u.email, 'auditor', 'approved'
from auth.users u
on conflict (id) do nothing;

insert into public.auditor_customers (auditor_id, customer_id)
select p.id, c.id
from public.profiles p cross join public.customers c
where p.role = 'auditor'
on conflict do nothing;
