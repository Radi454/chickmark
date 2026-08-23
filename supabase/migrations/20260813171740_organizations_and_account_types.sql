-- 20260813171740 20260813090000_organizations_and_account_types
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- 20260813090000 organizations + account types
--
-- Additive only. Existing roles, policies and helper functions are untouched:
-- 'personal' is a NEW role value that no existing predicate matches, so a
-- personal account inherits zero write scope (app_is_staff stays admin/auditor).

-- ============================ organizations ============================
create table if not exists public.organizations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  code        text not null,
  customer_id text not null references public.customers(id) on delete restrict,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists organizations_code_upper_unique
  on public.organizations (upper(code));
alter table public.organizations
  drop constraint if exists organizations_code_format;
alter table public.organizations
  add constraint organizations_code_format check (code ~ '^[A-Z0-9]{8}$');
alter table public.organizations enable row level security;

drop trigger if exists organizations_touch on public.organizations;
create trigger organizations_touch before update on public.organizations
  for each row execute function public.touch_updated_at();

-- ============================ profile columns ============================
alter table public.profiles
  add column if not exists account_type text not null default 'internal';
alter table public.profiles
  add column if not exists organization_id uuid references public.organizations(id) on delete set null;
alter table public.profiles
  add column if not exists org_role text;

alter table public.profiles drop constraint if exists profiles_account_type_check;
alter table public.profiles add constraint profiles_account_type_check
  check (account_type in ('internal','personal','organization'));

alter table public.profiles drop constraint if exists profiles_org_role_check;
alter table public.profiles add constraint profiles_org_role_check
  check (org_role is null or org_role in ('first_admin','admin','member'));

-- org membership is only meaningful for organization accounts
alter table public.profiles drop constraint if exists profiles_org_consistency;
alter table public.profiles add constraint profiles_org_consistency check (
  (account_type = 'organization' and organization_id is not null and org_role is not null)
  or (account_type <> 'organization' and organization_id is null and org_role is null)
);

-- widen role: 'personal' is new and matches no existing policy predicate
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in ('admin','auditor','customer','personal'));

create index if not exists idx_profiles_organization on public.profiles(organization_id);

-- ============================ code generation ============================
create or replace function public.generate_organization_code()
  returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no I/O/0/1
  candidate text;
  attempt int := 0;
begin
  loop
    attempt := attempt + 1;
    candidate := '';
    for _i in 1..8 loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.organizations o where upper(o.code) = candidate);
    if attempt > 50 then
      raise exception 'Could not allocate a unique organization code.';
    end if;
  end loop;
  return candidate;
end;
$$;
revoke execute on function public.generate_organization_code() from public, anon, authenticated;
grant execute on function public.generate_organization_code() to service_role;

-- ============================ anonymous code lookup ============================
-- Returns only the organization NAME so the registration screen can confirm the
-- code before signup. The code is not a secret (every employee holds it) and no
-- other column is exposed.
create or replace function public.lookup_organization_by_code(p_code text)
  returns text language sql stable security definer set search_path = '' as $$
  select o.name from public.organizations o
   where upper(o.code) = upper(trim(p_code))
   limit 1;
$$;
revoke execute on function public.lookup_organization_by_code(text) from public;
grant execute on function public.lookup_organization_by_code(text) to anon, authenticated;

-- ============================ organizations policies ============================
-- Zoetis super-admin manages orgs. Members may read only their own org row.
drop policy if exists organizations_admin_all on public.organizations;
create policy organizations_admin_all on public.organizations for all to authenticated
  using (chickmark_private.app_is_admin()) with check (chickmark_private.app_is_admin());

drop policy if exists organizations_member_read on public.organizations;
create policy organizations_member_read on public.organizations for select to authenticated
  using (id = (select p.organization_id from public.profiles p where p.id = auth.uid()));
