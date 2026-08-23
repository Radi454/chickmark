-- 20260813173535 20260813092000_org_admin_rpcs
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- 20260813092000 org admin RPCs
--
-- Authority tiers:
--   first_admin -> approve members AND promote members to admin
--   admin       -> approve members only
--   member      -> nothing
-- Approval/promotion go through SECURITY DEFINER functions so an org admin can
-- only ever move status pending->approved or org_role member->admin. role,
-- customer_id and organization_id are never writable by them.

create or replace function public.app_org_id()
  returns uuid language sql stable security definer set search_path = '' as $$
  select p.organization_id from public.profiles p where p.id = auth.uid();
$$;
revoke execute on function public.app_org_id() from public, anon;
grant execute on function public.app_org_id() to authenticated;

create or replace function public.app_org_role()
  returns text language sql stable security definer set search_path = '' as $$
  select p.org_role from public.profiles p where p.id = auth.uid();
$$;
revoke execute on function public.app_org_role() from public, anon;
grant execute on function public.app_org_role() to authenticated;

-- org admins can see their own org's roster
drop policy if exists profiles_org_peer_read on public.profiles;
create policy profiles_org_peer_read on public.profiles for select to authenticated
  using (
    organization_id is not null
    and organization_id = public.app_org_id()
    and public.app_org_role() in ('first_admin','admin')
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
     and p.organization_id = public.app_org_id()
     and public.app_org_role() in ('first_admin','admin')
   order by p.status, p.created_at;
$$;
revoke execute on function public.list_org_members() from public, anon;
grant execute on function public.list_org_members() to authenticated;

create or replace function public.approve_org_member(p_user_id uuid)
  returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_caller_org  uuid := public.app_org_id();
  v_caller_role text := public.app_org_role();
begin
  if v_caller_org is null or v_caller_role not in ('first_admin','admin') then
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
  v_caller_org  uuid := public.app_org_id();
  v_caller_role text := public.app_org_role();
begin
  -- only the first admin may create admins; promoted admins cannot
  if v_caller_org is null or v_caller_role <> 'first_admin' then
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
