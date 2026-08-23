-- Fix: egg_quality_defect_counts was created (20260823100000_egg_grading.sql)
-- with a blanket `authenticated_all using (true) with check (true)` policy.
-- That is looser than every other tenant-scoped table in the database:
-- egg_quality, egg_storage, chick_quality, and fresh_egg_breakout all use a
-- split select/write pair gated by chickmark_private.app_can_read_customer()
-- / app_can_write_customer(). Replace the blanket policy with that same
-- pair. Table has zero rows, so this is a pure tightening with no data
-- impact.

drop policy if exists authenticated_all on public.egg_quality_defect_counts;

create policy egg_quality_defect_counts_select
  on public.egg_quality_defect_counts
  for select to authenticated
  using (chickmark_private.app_can_read_customer(customer_id));

create policy egg_quality_defect_counts_write
  on public.egg_quality_defect_counts
  for all to authenticated
  using (chickmark_private.app_can_write_customer(customer_id))
  with check (chickmark_private.app_can_write_customer(customer_id));
