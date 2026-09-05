-- 0014 breeder customer-scoped access and role-gated approval
-- (breeder-flock-performance ticket 16, carried over from ticket 07;
-- design doc docs/superpowers/specs/2026-08-27-breeder-flock-performance-design.md
-- sections 5.3 and 13)
--
-- This file does three things, additively, on top of 0011-0013:
--
-- 1. Makes `production_manager` a real, assignable `profiles.role` value and
--    gives it the same customer-scoping mechanism `auditor` already has
--    (the `auditor_customers` assignment table, via the admin "User Access"
--    screen at lib/features/admin/screens/admin_users_screen.dart). Ticket
--    07 added `BreederApprovalRole.productionManager` client-side, but no
--    user could ever hold that role because `profiles_role_check` rejected
--    it and nothing assigned it. This closes both gaps: the constraint is
--    widened, and `chickmark_private.app_can_read_customer` /
--    `app_can_write_customer` are redefined (CREATE OR REPLACE, same
--    signature, so every existing caller — flocks, houses, all of 0012's
--    tables, etc. — picks up the change with no other file touched) to
--    treat `production_manager` exactly like `auditor`: scoped to whatever
--    customers `auditor_customers` assigns them.
--
-- 2. Adds `chickmark_private.app_can_approve_breeder_report()`, the ONE
--    enumerated, documented set of roles permitted to approve a breeder
--    daily report. This must be kept byte-for-byte in sync with
--    `BreederApprovalRole.permitted` in
--    lib/services/breeder/breeder_bird_ledger_service.dart (currently
--    `['production_manager', 'admin']`) — the two lists are the client and
--    cloud halves of one single-sourced enumeration, and
--    test/security/breeder_approval_rls_test.dart asserts they still match
--    literally. If you change one, change the other in the same commit.
--
--    A BEFORE INSERT OR UPDATE trigger on `breeder_daily_reports` enforces
--    this at the only place the design doc cares about: the transition INTO
--    `approved`. This is deliberately a trigger, not just a WITH CHECK
--    clause, because RLS's own USING/WITH CHECK pair cannot compare OLD and
--    NEW state in one expression, and — critically — because
--    `push_breeder_daily_report_aggregate` (0013) is SECURITY DEFINER and
--    bypasses RLS entirely by design. A trigger on the underlying table
--    fires for every write path that reaches the table, RLS-gated or not
--    (including the RPC's `insert ... on conflict do update`), so this is
--    the one place that actually closes the hole 0013's own header comment
--    flagged as "ticket 16's, not this one's": a modified or offline client
--    cannot get an unpermitted approval through by calling the RPC directly
--    any more than by writing the row itself.
--
-- 3. Makes benchmark immutability explicit at the grant level, not just by
--    omission of a write policy. 0011 already enables RLS on
--    `breeder_metric_definitions` / `breeder_benchmark_profiles` /
--    `breeder_benchmark_values` with only a SELECT policy, which already
--    denies INSERT/UPDATE/DELETE to `authenticated`/`anon` by RLS default-
--    deny; the explicit REVOKE below (and the same for 0012's
--    `breeder_egg_grade_definitions` reference table) is defense in depth so
--    a hand-crafted request is refused by table privilege before RLS is
--    even evaluated, and so this is trivially visible to anyone reading
--    grants rather than having to reason about "no policy = deny".
--
-- This file is deliberately NOT applied by this change — see
-- supabase/migrations_unapplied/README.md. Apply after 0011, 0012, and
-- 0013 (it redefines a function 0012 depends on and adds a trigger to a
-- table 0012/0013 create).

-- ============================ 1. production_manager role ============================
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('admin', 'auditor', 'customer', 'personal', 'production_manager'));

-- Same shape as chickmark_private.app_can_read_customer in
-- 20260719131203_0007_security_hardening.sql, with production_manager added
-- to the auditor branch (identical scoping mechanism: an assignment row in
-- auditor_customers). Signature is unchanged so every existing caller
-- (public.flocks/houses/etc. policies, and 0012's app_can_read_flock) picks
-- this up automatically.
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
          p.role in ('auditor', 'production_manager')
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
          p.role in ('auditor', 'production_manager')
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

-- ============================ 2. role-gated approval transition ============================
-- Single source of truth for the cloud half of the enumerated approval-role
-- set (design section 5.3: "the permitted approval roles are an enumerated,
-- documented set rather than an open string"). Mirrors
-- BreederApprovalRole.permitted = ['production_manager', 'admin'] in
-- lib/services/breeder/breeder_bird_ledger_service.dart byte-for-byte as a
-- set; keep both lists in sync.
create or replace function chickmark_private.app_can_approve_breeder_report()
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select coalesce(
    (
      select p.status = 'approved' and p.role in ('admin', 'production_manager')
      from public.profiles p
      where p.id = (select auth.uid())
    ),
    false
  );
$$;

revoke all on function chickmark_private.app_can_approve_breeder_report() from public, anon;
grant execute on function chickmark_private.app_can_approve_breeder_report()
  to authenticated, service_role;

-- Fires on every write that reaches the table, including
-- push_breeder_daily_report_aggregate's `insert ... on conflict do update`
-- (Postgres fires the UPDATE trigger for the conflicting-row branch of an
-- ON CONFLICT DO UPDATE, same as a plain UPDATE) and the defense-in-depth
-- `breeder_daily_reports_write` RLS policy's own plain-UPDATE path. A
-- report can only ever enter 'approved' this way; state cannot go directly
-- from 'draft'/'submitted' to 'approved' without passing through this
-- check, and re-saving an already-approved row (state stays 'approved')
-- does not re-check, matching approve() being a one-way gated transition
-- rather than a property of the row at rest.
create or replace function chickmark_private.enforce_breeder_report_approval_role()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if new.state = 'approved'
     and (tg_op = 'INSERT' or old.state is distinct from 'approved')
     and not chickmark_private.app_can_approve_breeder_report()
  then
    raise exception
      'role "%" is not permitted to approve a breeder daily report',
      chickmark_private.app_role()
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists breeder_daily_reports_approval_role on public.breeder_daily_reports;
create trigger breeder_daily_reports_approval_role
  before insert or update on public.breeder_daily_reports
  for each row execute function chickmark_private.enforce_breeder_report_approval_role();

-- ============================ 3. explicit benchmark/reference immutability ============================
-- Belt-and-suspenders alongside 0011/0012's RLS-by-omission: no client role
-- can ever write these reference tables even if RLS were misconfigured or
-- disabled by accident.
revoke insert, update, delete on public.breeder_metric_definitions from authenticated, anon;
revoke insert, update, delete on public.breeder_benchmark_profiles from authenticated, anon;
revoke insert, update, delete on public.breeder_benchmark_values from authenticated, anon;
revoke insert, update, delete on public.breeder_egg_grade_definitions from authenticated, anon;
