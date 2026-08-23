-- 20260813174559 20260813092500_org_role_requires_approved_status
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- 20260813092500 org_role requires approved status
--
-- Defense-in-depth: app_org_role() previously trusted profiles.org_role
-- regardless of profiles.status. Every code path that currently sets
-- org_role to 'first_admin'/'admin' also sets status='approved' at the same
-- time, but that invariant lives in *other* code (the super-admin edge
-- function, promote_org_admin's own target guard), not in this function. If
-- anything ever set org_role without status='approved' -- a future feature,
-- a manual DB fix, a bug elsewhere -- app_org_id()/app_org_role() consumers
-- (approve_org_member, promote_org_admin, list_org_members,
-- profiles_org_peer_read) would silently trust it.
--
-- Single choke point fix: app_org_role() now also requires
-- status = 'approved'. A not-approved caller gets NULL back, and every
-- comparison against NULL ('= first_admin', 'in (first_admin, admin)',
-- '<> first_admin') evaluates to false/NOT true, so all four consumers fall
-- through to their raise exception branch or the policy's using clause
-- simply excludes the row. Purely additive: create or replace on an
-- existing function, no policy or table touched.

create or replace function public.app_org_role()
  returns text language sql stable security definer set search_path = '' as $$
  select p.org_role from public.profiles p where p.id = auth.uid() and p.status = 'approved';
$$;
revoke execute on function public.app_org_role() from public, anon;
grant execute on function public.app_org_role() to authenticated;
