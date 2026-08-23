-- 20260813175010 20260813093000_org_admin_rpcs_null_safe_authority
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- 20260813093000 org admin RPCs: null-safe authority checks
--
-- 20260813092500 made app_org_role() return NULL for a caller whose
-- status <> 'approved', intending that every consumer of app_org_role()
-- would then correctly deny access. That holds for the two WHERE/USING
-- consumers (list_org_members's WHERE clause, profiles_org_peer_read's
-- USING clause): "... AND app_org_role() IN (...)" evaluates to NULL when
-- app_org_role() is NULL, and a NULL predicate excludes the row -- correct
-- deny.
--
-- It does NOT hold for approve_org_member/promote_org_admin's plpgsql
-- "IF v_caller_org IS NULL OR v_caller_role NOT IN (...) THEN raise"
-- guards. Three-valued logic: NULL NOT IN (...) is NULL, and
-- FALSE OR NULL is NULL (not FALSE) -- and PL/pgSQL's IF-THEN treats a NULL
-- condition the same as FALSE, i.e. it *skips* the THEN branch. So when
-- v_caller_role is NULL (status <> 'approved') but v_caller_org is still
-- non-null (app_org_id() was never status-gated), the guard's condition
-- evaluates to NULL, the raise is skipped, and execution falls through to
-- the UPDATE -- which still succeeds because it only checks
-- organization_id = v_caller_org, not the caller's status. Confirmed live:
-- a profile with org_role='first_admin' forced to status='pending' could
-- still call approve_org_member successfully after 20260813092500 alone.
--
-- Fix: restate both guards so the "authorized" condition is wrapped in
-- coalesce(..., false) before negating, which forces NULL to a definite
-- "not authorized" rather than an indeterminate condition. This makes the
-- IF's condition always TRUE or FALSE, never NULL, for the unauthorized
-- case -- closing the gap while leaving every non-null-role case (the
-- normal first_admin/admin/member paths already verified in Step 2)
-- bit-for-bit unchanged.

create or replace function public.approve_org_member(p_user_id uuid)
  returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_caller_org  uuid := public.app_org_id();
  v_caller_role text := public.app_org_role();
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
  v_caller_org  uuid := public.app_org_id();
  v_caller_role text := public.app_org_role();
begin
  -- only the first admin may create admins; promoted admins cannot
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
