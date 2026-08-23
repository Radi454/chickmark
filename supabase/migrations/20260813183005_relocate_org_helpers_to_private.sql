-- 20260813183005 20260813094000_relocate_org_helpers_to_private
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- 20260813094000 relocate org auth helpers to chickmark_private
--
-- scripts/test_supabase_security_hardening.sh enforces that every app_*
-- authorization helper lives exclusively in chickmark_private (never public)
-- and is granted only to authenticated + service_role, never anon/PUBLIC.
-- app_org_id() and app_org_role() from 20260813092000 were mistakenly left
-- in public; this migration relocates them without changing behavior.

create or replace function chickmark_private.app_org_id()
  returns uuid language sql stable security definer set search_path = '' as $$
  select p.organization_id from public.profiles p where p.id = auth.uid();
$$;

create or replace function chickmark_private.app_org_role()
  returns text language sql stable security definer set search_path = '' as $$
  select p.org_role from public.profiles p where p.id = auth.uid() and p.status = 'approved';
$$;

revoke all on function chickmark_private.app_org_id() from public, anon;
grant execute on function chickmark_private.app_org_id() to authenticated, service_role;

revoke all on function chickmark_private.app_org_role() from public, anon;
grant execute on function chickmark_private.app_org_role() to authenticated, service_role;

-- repoint every consumer at the private versions
drop policy if exists profiles_org_peer_read on public.profiles;
create policy profiles_org_peer_read on public.profiles for select to authenticated
  using (
    organization_id is not null
    and organization_id = chickmark_private.app_org_id()
    and chickmark_private.app_org_role() in ('first_admin','admin')
  );

create or replace function public.list_org_members()
  returns table (
    id uuid, full_name text, email text,
    status text, org_role text, created_at timestamptz
  )
  language sql stable security definer set search_path = '' as $$
  select p.id, p.full_name, p.email, p.status, p.org_role, p.created_at
    from public.profiles p
   where p.organization_id is not null
     and p.organization_id = chickmark_private.app_org_id()
     and chickmark_private.app_org_role() in ('first_admin','admin')
   order by p.status, p.created_at;
$$;
revoke execute on function public.list_org_members() from public, anon;
grant execute on function public.list_org_members() to authenticated;

create or replace function public.approve_org_member(p_user_id uuid)
  returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_caller_org  uuid := chickmark_private.app_org_id();
  v_caller_role text := chickmark_private.app_org_role();
begin
  if v_caller_org is null
     or not coalesce(v_caller_role in ('first_admin','admin'), false) then
    raise exception 'NOT_ORG_ADMIN';
  end if;
  update public.profiles
     set status = 'approved'
   where id = p_user_id
     and organization_id = v_caller_org
     and status = 'pending';
  if not found then
    raise exception 'MEMBER_NOT_PENDING_IN_ORG';
  end if;
end;
$$;
revoke execute on function public.approve_org_member(uuid) from public, anon;
grant execute on function public.approve_org_member(uuid) to authenticated;

create or replace function public.promote_org_admin(p_user_id uuid)
  returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_caller_org  uuid := chickmark_private.app_org_id();
  v_caller_role text := chickmark_private.app_org_role();
begin
  if v_caller_org is null
     or not coalesce(v_caller_role = 'first_admin', false) then
    raise exception 'NOT_FIRST_ADMIN';
  end if;
  update public.profiles
     set org_role = 'admin'
   where id = p_user_id
     and organization_id = v_caller_org
     and org_role = 'member'
     and status = 'approved';
  if not found then
    raise exception 'MEMBER_NOT_PROMOTABLE';
  end if;
end;
$$;
revoke execute on function public.promote_org_admin(uuid) from public, anon;
grant execute on function public.promote_org_admin(uuid) to authenticated;

-- drop the mistakenly-public originals now that nothing references them
drop function if exists public.app_org_id();
drop function if exists public.app_org_role();
