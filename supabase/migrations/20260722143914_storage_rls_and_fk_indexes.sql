-- 20260722143914 storage_rls_and_fk_indexes
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- Harden storage authorization and index every foreign-key access path.
--
-- Lab Analysis object ownership is derived from the canonical object path:
--   lab_analysis_reports/<customerId>/...
-- A report row is intentionally not accepted as an alternate authorization
-- source because a tenant-scoped row could otherwise point at another
-- customer's object. BMK citation photos are shared reference material:
-- approved users may read them, while only approved staff may mutate them.

drop policy if exists photos_read on storage.objects;
drop policy if exists photos_write on storage.objects;

create policy photos_read on storage.objects for select to authenticated
  using (
    bucket_id = 'photos'
    and (
      exists (
        select 1
        from public.audit_sessions s
        where s.id = split_part(name, '/', 1)
          and chickmark_private.app_can_read_customer(s.customer_id)
      )
      or (
        split_part(name, '/', 1) = 'lab_analysis_reports'
        and chickmark_private.app_can_read_customer(
          split_part(name, '/', 2)
        )
      )
      or (
        split_part(name, '/', 1) = 'bmk_operational_sources'
        and chickmark_private.app_status() = 'approved'
      )
    )
  );

create policy photos_write on storage.objects for all to authenticated
  using (
    bucket_id = 'photos'
    and (
      exists (
        select 1
        from public.audit_sessions s
        where s.id = split_part(name, '/', 1)
          and chickmark_private.app_can_write_customer(s.customer_id)
      )
      or (
        split_part(name, '/', 1) = 'lab_analysis_reports'
        and chickmark_private.app_can_write_customer(
          split_part(name, '/', 2)
        )
      )
      or (
        split_part(name, '/', 1) = 'bmk_operational_sources'
        and chickmark_private.app_is_staff()
      )
    )
  )
  with check (
    bucket_id = 'photos'
    and (
      exists (
        select 1
        from public.audit_sessions s
        where s.id = split_part(name, '/', 1)
          and chickmark_private.app_can_write_customer(s.customer_id)
      )
      or (
        split_part(name, '/', 1) = 'lab_analysis_reports'
        and chickmark_private.app_can_write_customer(
          split_part(name, '/', 2)
        )
      )
      or (
        split_part(name, '/', 1) = 'bmk_operational_sources'
        and chickmark_private.app_is_staff()
      )
    )
  );

-- PostgreSQL does not automatically index foreign-key columns. Existing
-- dashboard indexes already lead with customer_id, and session/report indexes
-- cover those parent relationships. These indexes cover the remaining FK
-- lookups and ON DELETE actions without duplicating the useful leading keys.

create index if not exists idx_profiles_customer_fk
  on public.profiles(customer_id)
  where customer_id is not null;

create index if not exists idx_audit_sessions_hatchery_fk
  on public.audit_sessions(hatchery_id);
create index if not exists idx_govee_daily_captures_hatchery_fk
  on public.govee_daily_captures(hatchery_id);

create index if not exists idx_egg_storage_flock_fk
  on public.egg_storage(flock_id) where flock_id is not null;
create index if not exists idx_egg_storage_hatchery_fk
  on public.egg_storage(hatchery_id) where hatchery_id is not null;
create index if not exists idx_egg_quality_flock_fk
  on public.egg_quality(flock_id) where flock_id is not null;
create index if not exists idx_egg_quality_hatchery_fk
  on public.egg_quality(hatchery_id) where hatchery_id is not null;
create index if not exists idx_chick_quality_flock_fk
  on public.chick_quality(flock_id) where flock_id is not null;
create index if not exists idx_chick_quality_hatchery_fk
  on public.chick_quality(hatchery_id) where hatchery_id is not null;
create index if not exists idx_chick_weights_flock_fk
  on public.chick_weights(flock_id) where flock_id is not null;
create index if not exists idx_chick_weights_hatchery_fk
  on public.chick_weights(hatchery_id) where hatchery_id is not null;
create index if not exists idx_fresh_egg_breakout_flock_fk
  on public.fresh_egg_breakout(flock_id) where flock_id is not null;
create index if not exists idx_fresh_egg_breakout_hatchery_fk
  on public.fresh_egg_breakout(hatchery_id) where hatchery_id is not null;
create index if not exists idx_candled_egg_breakout_flock_fk
  on public.candled_egg_breakout(flock_id) where flock_id is not null;
create index if not exists idx_candled_egg_breakout_hatchery_fk
  on public.candled_egg_breakout(hatchery_id) where hatchery_id is not null;
create index if not exists idx_residue_breakout_flock_fk
  on public.residue_breakout(flock_id) where flock_id is not null;
create index if not exists idx_residue_breakout_hatchery_fk
  on public.residue_breakout(hatchery_id) where hatchery_id is not null;
create index if not exists idx_setter_optimizing_flock_fk
  on public.setter_optimizing(flock_id) where flock_id is not null;
create index if not exists idx_setter_optimizing_hatchery_fk
  on public.setter_optimizing(hatchery_id) where hatchery_id is not null;
create index if not exists idx_hatcher_optimizing_flock_fk
  on public.hatcher_optimizing(flock_id) where flock_id is not null;
create index if not exists idx_hatcher_optimizing_hatchery_fk
  on public.hatcher_optimizing(hatchery_id) where hatchery_id is not null;

create index if not exists idx_dashboard_actions_hatchery_fk
  on public.dashboard_actions(hatchery_id);
create index if not exists idx_dashboard_actions_flock_fk
  on public.dashboard_actions(flock_id) where flock_id is not null;
create index if not exists idx_dashboard_actions_session_fk
  on public.dashboard_actions(session_id) where session_id is not null;

create index if not exists idx_lab_analysis_reports_flock_fk
  on public.lab_analysis_reports(flock_id);
create index if not exists idx_lab_analysis_groups_flock_fk
  on public.lab_analysis_groups(flock_id);
create index if not exists idx_lab_analysis_rows_report_fk
  on public.lab_analysis_rows(report_id);
create index if not exists idx_lab_analysis_rows_flock_fk
  on public.lab_analysis_rows(flock_id);
