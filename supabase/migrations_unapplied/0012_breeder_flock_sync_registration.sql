-- 0012 breeder flock sync registration (breeder-flock-performance ticket 15)
--
-- Tickets 01-14 built the whole breeder-flock-performance feature locally
-- and left every one of its tables unregistered with Supabase: no cloud
-- table, no RLS, no push/pull wiring. This ticket (design doc
-- docs/superpowers/specs/2026-08-27-breeder-flock-performance-design.md,
-- section 13) closes that gap for every table except the daily-report sync
-- aggregate (`breeder_daily_reports` and its four child tables), which is
-- handled separately by 0013's `push_breeder_daily_report_aggregate`
-- transaction — see that file's header for why a plain per-row mirror is
-- unsafe for those five tables.
--
-- Conventions follow the existing operational tables (see
-- `20260726100000_telegram_hatchery_agent.sql` for `hatchery_draft_batches`
-- etc., and `20260716082919_0005_lab_analysis.sql` for the
-- customer/flock-scoped RLS shape): snake_case columns, text ids, text/ISO
-- timestamps, integer booleans (matching SQLite's 0/1), and RLS policies
-- built on the `chickmark_private` authorization helpers from
-- `20260719131203_0007_security_hardening.sql`. This app's generic sync
-- path (`PerformanceSyncRepository`/`toSupabaseUpsertPayload`) camelCase<->
-- snake_case-converts column names automatically, so no per-table mapping
-- is required on the Dart side once these tables are registered in
-- `lib/data/repositories/performance_sync_repository.dart`.
--
-- Verified against the live project with mcp__supabase__list_tables before
-- writing this file: none of `houses`, `breeder_*`, or `egg_batches`/
-- `egg_shipments`/`egg_shipment_batches`/`egg_batch_receipts`/
-- `egg_batch_house_sources` exist remotely yet, and `public.flocks` still
-- carries `farm_id` (0010, also unapplied, drops it) — this file's
-- `flock_id` foreign keys target `public.flocks(id)` and do not touch
-- `farm_id`, so it is consistent whether 0010 has been applied yet or not.
--
-- This file is deliberately NOT applied by this change — see
-- supabase/migrations_unapplied/README.md. Apply together with, or after,
-- 0011 (breeder benchmark foundation), local migration v79, and this
-- ticket's 0013.

-- ============================ flock-scoped authorization helpers ============================
-- Every breeder/egg table below is scoped to a flock rather than directly to
-- a customer_id column (design section 12: "customer ownership traceable for
-- every operational row" — traceable via flocks.customer_id, one join away).
create or replace function chickmark_private.app_can_read_flock(fid text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.flocks f
    where f.id = fid
      and chickmark_private.app_can_read_customer(f.customer_id)
  );
$$;

create or replace function chickmark_private.app_can_write_flock(fid text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.flocks f
    where f.id = fid
      and chickmark_private.app_can_write_customer(f.customer_id)
  );
$$;

revoke all on function chickmark_private.app_can_read_flock(text) from public, anon;
revoke all on function chickmark_private.app_can_write_flock(text) from public, anon;
grant execute on function chickmark_private.app_can_read_flock(text) to authenticated, service_role;
grant execute on function chickmark_private.app_can_write_flock(text) to authenticated, service_role;

-- ============================ houses (reshape, ticket 02) ============================
create table public.houses (
  id text primary key,
  flock_id text not null references public.flocks(id) on delete cascade,
  name text not null,
  code text,
  capacity integer,
  opening_females integer not null default 0 check (opening_females >= 0),
  opening_males integer not null default 0 check (opening_males >= 0),
  notes text,
  is_active integer not null default 1 check (is_active in (0, 1)),
  created_by text,
  created_at text,
  updated_at text
);
create unique index idx_houses_flock_name on public.houses (flock_id, name);
create unique index idx_houses_flock_code on public.houses (flock_id, code)
  where code is not null and code <> '';
create index idx_houses_flock on public.houses (flock_id);

alter table public.houses enable row level security;
create policy houses_read on public.houses for select to authenticated
  using (chickmark_private.app_can_read_flock(flock_id));
create policy houses_write on public.houses for all to authenticated
  using (chickmark_private.app_can_write_flock(flock_id))
  with check (chickmark_private.app_can_write_flock(flock_id));

-- ============================ breeder_flock_milestones (ticket 06) ============================
create table public.breeder_flock_milestones (
  id text primary key,
  flock_id text not null references public.flocks(id) on delete cascade,
  event_type text not null check (event_type in (
    'grading', 'physical_transfer', 'light_stimulation', 'first_egg',
    'five_percent_production', 'fifty_percent_production', 'peak_production',
    'partial_depletion', 'start_of_depletion', 'final_depletion'
  )),
  event_date text not null,
  notes text,
  created_at text not null,
  updated_at text not null
);
create unique index idx_breeder_flock_milestones_unique
  on public.breeder_flock_milestones (flock_id, event_type);
create index idx_breeder_flock_milestones_flock
  on public.breeder_flock_milestones (flock_id);

alter table public.breeder_flock_milestones enable row level security;
create policy breeder_flock_milestones_read on public.breeder_flock_milestones for select to authenticated
  using (chickmark_private.app_can_read_flock(flock_id));
create policy breeder_flock_milestones_write on public.breeder_flock_milestones for all to authenticated
  using (chickmark_private.app_can_write_flock(flock_id))
  with check (chickmark_private.app_can_write_flock(flock_id));

-- ============================ breeder_isolation_areas (ticket 08) ============================
create table public.breeder_isolation_areas (
  id text primary key,
  flock_id text not null references public.flocks(id) on delete cascade,
  name text not null,
  notes text,
  is_active integer not null default 1 check (is_active in (0, 1)),
  created_by text,
  created_at text not null,
  updated_at text not null
);
create unique index idx_breeder_isolation_areas_unique_name
  on public.breeder_isolation_areas (flock_id, lower(name));
create index idx_breeder_isolation_areas_flock
  on public.breeder_isolation_areas (flock_id);

alter table public.breeder_isolation_areas enable row level security;
create policy breeder_isolation_areas_read on public.breeder_isolation_areas for select to authenticated
  using (chickmark_private.app_can_read_flock(flock_id));
create policy breeder_isolation_areas_write on public.breeder_isolation_areas for all to authenticated
  using (chickmark_private.app_can_write_flock(flock_id))
  with check (chickmark_private.app_can_write_flock(flock_id));

-- ============================ breeder_egg_grade_definitions (ticket 10) ============================
-- System-defined reference data, like breeder_metric_definitions /
-- breeder_benchmark_profiles / breeder_benchmark_values in 0011: seeded here
-- from the same values `breeder_egg_grade_definition_seeds.dart` inserts
-- locally, read-only to every authenticated client, never pushed up.
create table public.breeder_egg_grade_definitions (
  id text primary key,
  code text not null unique,
  name text not null,
  priority integer not null check (priority > 0),
  is_active integer not null default 1 check (is_active in (0, 1)),
  created_at text not null,
  updated_at text not null
);
create unique index idx_breeder_egg_grade_definitions_active_priority
  on public.breeder_egg_grade_definitions (priority) where is_active = 1;

alter table public.breeder_egg_grade_definitions enable row level security;
create policy breeder_egg_grade_definitions_read on public.breeder_egg_grade_definitions
  for select to authenticated using (true);

insert into public.breeder_egg_grade_definitions (id, code, name, priority, is_active, created_at, updated_at) values
  ('breeder-egg-grade-damaged', 'damaged', 'Damaged', 1, 1, now()::text, now()::text),
  ('breeder-egg-grade-cracked', 'cracked', 'Cracked', 2, 1, now()::text, now()::text),
  ('breeder-egg-grade-double-yolk', 'double_yolk', 'Double yolk', 3, 1, now()::text, now()::text),
  ('breeder-egg-grade-sort-reject', 'sort_reject', 'Sort/Reject', 4, 1, now()::text, now()::text),
  ('breeder-egg-grade-second-grade', 'second_grade', 'Second grade', 5, 1, now()::text, now()::text),
  ('breeder-egg-grade-first-grade', 'first_grade', 'First grade', 6, 1, now()::text, now()::text)
on conflict (id) do nothing;

-- ============================ breeder_daily_reports + children (tickets 07/09/10/11/15) ============================
-- These five tables are the sync aggregate (design section 13.1). They are
-- created here with full RLS like every other table, but they are pushed
-- exclusively through 0013's `push_breeder_daily_report_aggregate` function
-- — never through a plain per-row upsert — so the "write" RLS policy below
-- exists for defense in depth (and for the RPC's own security-definer
-- authorization check) rather than as the normal write path. `state` does
-- not list `sync_conflict`: that state is local-only bookkeeping (see local
-- migration v79) and is never written to this column.
--
-- `sync_token` is a SEPARATE counter from `revision` and must never be
-- conflated with it. `revision` is ticket 12's user-facing audit counter —
-- it advances only on a state transition or a post-approval correction,
-- and its value is meaningful to a human reading revision history.
-- `sync_token` is an opaque optimistic-concurrency counter that 0013's RPC
-- alone increments, exactly once per successful aggregate push, regardless
-- of whether that push changed `revision` at all. Two devices editing
-- different child rows of the same report at the same `revision` (neither
-- a transition nor a correction) would otherwise both present the same
-- `base_revision` and both "match" against a `revision`-based check, so the
-- second push would silently delete-and-reinsert over the first device's
-- already-accepted children with no conflict ever raised. Gating on a
-- token that moves on every accepted write closes that hole: the first
-- push advances `sync_token`, and the second push's stale token no longer
-- matches. See 0013's header comment for the full mechanics.
create table public.breeder_daily_reports (
  id text primary key,
  flock_id text not null references public.flocks(id) on delete cascade,
  report_date text not null,
  inside_temperature double precision,
  outside_temperature double precision,
  light_hours double precision,
  notes text,
  state text not null default 'draft' check (state in ('draft', 'submitted', 'approved')),
  revision integer not null default 1 check (revision >= 1),
  sync_token integer not null default 1 check (sync_token >= 1),
  created_by text,
  submitted_by text,
  submitted_at text,
  approved_by text,
  approved_at text,
  egg_production_denominator_females integer,
  benchmark_profile_version_at_approval text,
  comparison_axis_at_approval text,
  created_at text not null,
  updated_at text not null
);
create unique index idx_breeder_daily_reports_unique
  on public.breeder_daily_reports (flock_id, report_date);
create index idx_breeder_daily_reports_flock on public.breeder_daily_reports (flock_id);

alter table public.breeder_daily_reports enable row level security;
create policy breeder_daily_reports_read on public.breeder_daily_reports for select to authenticated
  using (chickmark_private.app_can_read_flock(flock_id));
create policy breeder_daily_reports_write on public.breeder_daily_reports for all to authenticated
  using (chickmark_private.app_can_write_flock(flock_id))
  with check (chickmark_private.app_can_write_flock(flock_id));

create table public.breeder_bird_movements (
  id text primary key,
  report_id text not null references public.breeder_daily_reports(id) on delete cascade,
  house_id text references public.houses(id),
  isolation_area_id text references public.breeder_isolation_areas(id),
  sex text not null check (sex in ('female', 'male')),
  opening integer not null default 0,
  mortality integer not null default 0,
  culls integer not null default 0,
  sale integer not null default 0,
  kitchen_removal integer not null default 0,
  euthanasia integer not null default 0,
  transfer_in integer not null default 0,
  transfer_out integer not null default 0,
  closing integer not null default 0,
  created_at text not null,
  updated_at text not null
);
create index idx_breeder_bird_movements_report on public.breeder_bird_movements (report_id);
create index idx_breeder_bird_movements_house on public.breeder_bird_movements (house_id);
create index idx_breeder_bird_movements_isolation on public.breeder_bird_movements (isolation_area_id);

alter table public.breeder_bird_movements enable row level security;
create policy breeder_bird_movements_read on public.breeder_bird_movements for select to authenticated
  using (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_bird_movements.report_id
      and chickmark_private.app_can_read_flock(r.flock_id)
  ));
create policy breeder_bird_movements_write on public.breeder_bird_movements for all to authenticated
  using (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_bird_movements.report_id
      and chickmark_private.app_can_write_flock(r.flock_id)
  ))
  with check (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_bird_movements.report_id
      and chickmark_private.app_can_write_flock(r.flock_id)
  ));

create table public.breeder_feed_entries (
  id text primary key,
  report_id text not null references public.breeder_daily_reports(id) on delete cascade,
  house_id text references public.houses(id),
  isolation_area_id text references public.breeder_isolation_areas(id),
  sex text not null check (sex in ('female', 'male')),
  feed_kg double precision not null default 0,
  created_at text not null,
  updated_at text not null
);
create index idx_breeder_feed_entries_report on public.breeder_feed_entries (report_id);
create index idx_breeder_feed_entries_house on public.breeder_feed_entries (house_id);
create index idx_breeder_feed_entries_isolation on public.breeder_feed_entries (isolation_area_id);

alter table public.breeder_feed_entries enable row level security;
create policy breeder_feed_entries_read on public.breeder_feed_entries for select to authenticated
  using (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_feed_entries.report_id
      and chickmark_private.app_can_read_flock(r.flock_id)
  ));
create policy breeder_feed_entries_write on public.breeder_feed_entries for all to authenticated
  using (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_feed_entries.report_id
      and chickmark_private.app_can_write_flock(r.flock_id)
  ))
  with check (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_feed_entries.report_id
      and chickmark_private.app_can_write_flock(r.flock_id)
  ));

create table public.breeder_egg_production_entries (
  id text primary key,
  report_id text not null references public.breeder_daily_reports(id) on delete cascade,
  house_id text references public.houses(id),
  isolation_area_id text references public.breeder_isolation_areas(id),
  grade_id text not null references public.breeder_egg_grade_definitions(id),
  count integer not null default 0,
  egg_weight_grams double precision,
  created_at text not null,
  updated_at text not null
);
create index idx_breeder_egg_production_entries_report on public.breeder_egg_production_entries (report_id);
create index idx_breeder_egg_production_entries_house on public.breeder_egg_production_entries (house_id);
create index idx_breeder_egg_production_entries_isolation on public.breeder_egg_production_entries (isolation_area_id);
create index idx_breeder_egg_production_entries_grade on public.breeder_egg_production_entries (grade_id);

alter table public.breeder_egg_production_entries enable row level security;
create policy breeder_egg_production_entries_read on public.breeder_egg_production_entries for select to authenticated
  using (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_egg_production_entries.report_id
      and chickmark_private.app_can_read_flock(r.flock_id)
  ));
create policy breeder_egg_production_entries_write on public.breeder_egg_production_entries for all to authenticated
  using (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_egg_production_entries.report_id
      and chickmark_private.app_can_write_flock(r.flock_id)
  ))
  with check (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_egg_production_entries.report_id
      and chickmark_private.app_can_write_flock(r.flock_id)
  ));

create table public.breeder_egg_inventory_movements (
  id text primary key,
  report_id text not null references public.breeder_daily_reports(id) on delete cascade,
  grade_id text not null references public.breeder_egg_grade_definitions(id),
  kind text not null check (kind in ('hatchery_dispatch', 'sale', 'kitchen', 'gift', 'adjustment')),
  quantity integer not null default 0,
  adjustment_direction text check (adjustment_direction is null or adjustment_direction in ('increase', 'decrease')),
  reason text,
  actor_user_id text,
  occurred_at text,
  reversed_movement_id text references public.breeder_egg_inventory_movements(id),
  created_at text not null,
  updated_at text not null
);
create index idx_breeder_egg_inventory_movements_report on public.breeder_egg_inventory_movements (report_id);
create index idx_breeder_egg_inventory_movements_grade on public.breeder_egg_inventory_movements (grade_id);
create index idx_breeder_egg_inventory_movements_reversed on public.breeder_egg_inventory_movements (reversed_movement_id);

alter table public.breeder_egg_inventory_movements enable row level security;
create policy breeder_egg_inventory_movements_read on public.breeder_egg_inventory_movements for select to authenticated
  using (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_egg_inventory_movements.report_id
      and chickmark_private.app_can_read_flock(r.flock_id)
  ));
create policy breeder_egg_inventory_movements_write on public.breeder_egg_inventory_movements for all to authenticated
  using (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_egg_inventory_movements.report_id
      and chickmark_private.app_can_write_flock(r.flock_id)
  ))
  with check (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_egg_inventory_movements.report_id
      and chickmark_private.app_can_write_flock(r.flock_id)
  ));

-- ============================ breeder_report_revisions (ticket 12) ============================
-- Commercial audit history: syncs normally through the generic per-row path
-- (registered in `PerformanceSyncRepository.postAggregatePushOrder`, pushed
-- only after its report's aggregate has landed so the FK below is
-- satisfiable), unlike its four sibling child tables above.
create table public.breeder_report_revisions (
  id text primary key,
  report_id text not null references public.breeder_daily_reports(id) on delete cascade,
  table_name text not null,
  row_id text not null,
  field_name text not null,
  old_value text,
  new_value text,
  reason text not null,
  actor_user_id text not null,
  revision_after integer not null,
  changed_at text not null,
  created_at text not null,
  updated_at text not null
);
create index idx_breeder_report_revisions_report on public.breeder_report_revisions (report_id);
create index idx_breeder_report_revisions_report_revision
  on public.breeder_report_revisions (report_id, revision_after);

alter table public.breeder_report_revisions enable row level security;
create policy breeder_report_revisions_read on public.breeder_report_revisions for select to authenticated
  using (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_report_revisions.report_id
      and chickmark_private.app_can_read_flock(r.flock_id)
  ));
create policy breeder_report_revisions_write on public.breeder_report_revisions for all to authenticated
  using (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_report_revisions.report_id
      and chickmark_private.app_can_write_flock(r.flock_id)
  ))
  with check (exists (
    select 1 from public.breeder_daily_reports r
    where r.id = breeder_report_revisions.report_id
      and chickmark_private.app_can_write_flock(r.flock_id)
  ));

-- ============================ breeder_weighing_sessions + samples (ticket 13) ============================
create table public.breeder_weighing_sessions (
  id text primary key,
  flock_id text not null references public.flocks(id) on delete cascade,
  house_id text not null references public.houses(id),
  session_date text not null,
  sex text not null check (sex in ('female', 'male')),
  method text not null,
  sample_size integer not null,
  notes text,
  derived_mean_weight_g double precision,
  derived_uniformity_pct double precision,
  derived_cv_pct double precision,
  comparison_profile_id text references public.breeder_benchmark_profiles(id),
  comparison_profile_guide_version text,
  comparison_axis_kind text check (comparison_axis_kind is null or comparison_axis_kind in ('official', 'milestoneAligned')),
  comparison_axis_offset_weeks integer,
  comparison_target_weight_g double precision,
  created_at text not null,
  updated_at text not null
);
create index idx_breeder_weighing_sessions_flock on public.breeder_weighing_sessions (flock_id, session_date);
create index idx_breeder_weighing_sessions_house on public.breeder_weighing_sessions (house_id);

alter table public.breeder_weighing_sessions enable row level security;
create policy breeder_weighing_sessions_read on public.breeder_weighing_sessions for select to authenticated
  using (chickmark_private.app_can_read_flock(flock_id));
create policy breeder_weighing_sessions_write on public.breeder_weighing_sessions for all to authenticated
  using (chickmark_private.app_can_write_flock(flock_id))
  with check (chickmark_private.app_can_write_flock(flock_id));

create table public.breeder_weighing_samples (
  id text primary key,
  session_id text not null references public.breeder_weighing_sessions(id) on delete cascade,
  weight_grams double precision not null,
  created_at text not null,
  updated_at text not null
);
create index idx_breeder_weighing_samples_session on public.breeder_weighing_samples (session_id);

alter table public.breeder_weighing_samples enable row level security;
create policy breeder_weighing_samples_read on public.breeder_weighing_samples for select to authenticated
  using (exists (
    select 1 from public.breeder_weighing_sessions s
    where s.id = breeder_weighing_samples.session_id
      and chickmark_private.app_can_read_flock(s.flock_id)
  ));
create policy breeder_weighing_samples_write on public.breeder_weighing_samples for all to authenticated
  using (exists (
    select 1 from public.breeder_weighing_sessions s
    where s.id = breeder_weighing_samples.session_id
      and chickmark_private.app_can_write_flock(s.flock_id)
  ))
  with check (exists (
    select 1 from public.breeder_weighing_sessions s
    where s.id = breeder_weighing_samples.session_id
      and chickmark_private.app_can_write_flock(s.flock_id)
  ));

-- ============================ egg batches, shipments, receipts (ticket 14) ============================
create table public.egg_batches (
  id text primary key,
  flock_id text not null references public.flocks(id) on delete cascade,
  collection_date text not null,
  grade_id text not null references public.breeder_egg_grade_definitions(id),
  egg_count integer not null default 0,
  notes text,
  created_at text not null,
  updated_at text not null
);
create unique index idx_egg_batches_flock_date_grade on public.egg_batches (flock_id, collection_date, grade_id);
create index idx_egg_batches_flock on public.egg_batches (flock_id);
create index idx_egg_batches_grade on public.egg_batches (grade_id);

alter table public.egg_batches enable row level security;
create policy egg_batches_read on public.egg_batches for select to authenticated
  using (chickmark_private.app_can_read_flock(flock_id));
create policy egg_batches_write on public.egg_batches for all to authenticated
  using (chickmark_private.app_can_write_flock(flock_id))
  with check (chickmark_private.app_can_write_flock(flock_id));

create table public.egg_batch_house_sources (
  id text primary key,
  batch_id text not null references public.egg_batches(id) on delete cascade,
  house_id text not null references public.houses(id),
  egg_count integer not null default 0,
  created_at text not null,
  updated_at text not null
);
create unique index idx_egg_batch_house_sources_unique on public.egg_batch_house_sources (batch_id, house_id);
create index idx_egg_batch_house_sources_house on public.egg_batch_house_sources (house_id);

alter table public.egg_batch_house_sources enable row level security;
create policy egg_batch_house_sources_read on public.egg_batch_house_sources for select to authenticated
  using (exists (
    select 1 from public.egg_batches b
    where b.id = egg_batch_house_sources.batch_id
      and chickmark_private.app_can_read_flock(b.flock_id)
  ));
create policy egg_batch_house_sources_write on public.egg_batch_house_sources for all to authenticated
  using (exists (
    select 1 from public.egg_batches b
    where b.id = egg_batch_house_sources.batch_id
      and chickmark_private.app_can_write_flock(b.flock_id)
  ))
  with check (exists (
    select 1 from public.egg_batches b
    where b.id = egg_batch_house_sources.batch_id
      and chickmark_private.app_can_write_flock(b.flock_id)
  ));

create table public.egg_shipments (
  id text primary key,
  flock_id text not null references public.flocks(id) on delete cascade,
  hatchery_id text not null references public.hatcheries(id),
  grade_id text not null references public.breeder_egg_grade_definitions(id),
  shipment_date text not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'cancelled')),
  notes text,
  report_id text references public.breeder_daily_reports(id),
  inventory_movement_id text references public.breeder_egg_inventory_movements(id),
  approved_by text,
  approved_at text,
  reversal_movement_id text references public.breeder_egg_inventory_movements(id),
  cancelled_by text,
  cancelled_at text,
  cancel_reason text,
  created_at text not null,
  updated_at text not null
);
create index idx_egg_shipments_flock on public.egg_shipments (flock_id, shipment_date);
create index idx_egg_shipments_hatchery on public.egg_shipments (hatchery_id);
create index idx_egg_shipments_status on public.egg_shipments (status);

alter table public.egg_shipments enable row level security;
create policy egg_shipments_read on public.egg_shipments for select to authenticated
  using (chickmark_private.app_can_read_flock(flock_id));
create policy egg_shipments_write on public.egg_shipments for all to authenticated
  using (chickmark_private.app_can_write_flock(flock_id))
  with check (chickmark_private.app_can_write_flock(flock_id));

create table public.egg_shipment_batches (
  id text primary key,
  shipment_id text not null references public.egg_shipments(id) on delete cascade,
  batch_id text not null references public.egg_batches(id),
  quantity integer not null default 0,
  created_at text not null,
  updated_at text not null
);
create unique index idx_egg_shipment_batches_unique on public.egg_shipment_batches (shipment_id, batch_id);
create index idx_egg_shipment_batches_shipment on public.egg_shipment_batches (shipment_id);
create index idx_egg_shipment_batches_batch on public.egg_shipment_batches (batch_id);

alter table public.egg_shipment_batches enable row level security;
create policy egg_shipment_batches_read on public.egg_shipment_batches for select to authenticated
  using (exists (
    select 1 from public.egg_shipments s
    where s.id = egg_shipment_batches.shipment_id
      and chickmark_private.app_can_read_flock(s.flock_id)
  ));
create policy egg_shipment_batches_write on public.egg_shipment_batches for all to authenticated
  using (exists (
    select 1 from public.egg_shipments s
    where s.id = egg_shipment_batches.shipment_id
      and chickmark_private.app_can_write_flock(s.flock_id)
  ))
  with check (exists (
    select 1 from public.egg_shipments s
    where s.id = egg_shipment_batches.shipment_id
      and chickmark_private.app_can_write_flock(s.flock_id)
  ));

create table public.egg_batch_receipts (
  id text primary key,
  shipment_batch_id text not null references public.egg_shipment_batches(id) on delete cascade,
  received_quantity integer not null default 0,
  variance integer not null default 0,
  recorded_by text,
  recorded_at text,
  notes text,
  created_at text not null,
  updated_at text not null
);
create unique index idx_egg_batch_receipts_unique on public.egg_batch_receipts (shipment_batch_id);

alter table public.egg_batch_receipts enable row level security;
create policy egg_batch_receipts_read on public.egg_batch_receipts for select to authenticated
  using (exists (
    select 1 from public.egg_shipment_batches sb
    join public.egg_shipments s on s.id = sb.shipment_id
    where sb.id = egg_batch_receipts.shipment_batch_id
      and chickmark_private.app_can_read_flock(s.flock_id)
  ));
create policy egg_batch_receipts_write on public.egg_batch_receipts for all to authenticated
  using (exists (
    select 1 from public.egg_shipment_batches sb
    join public.egg_shipments s on s.id = sb.shipment_id
    where sb.id = egg_batch_receipts.shipment_batch_id
      and chickmark_private.app_can_write_flock(s.flock_id)
  ))
  with check (exists (
    select 1 from public.egg_shipment_batches sb
    join public.egg_shipments s on s.id = sb.shipment_id
    where sb.id = egg_batch_receipts.shipment_batch_id
      and chickmark_private.app_can_write_flock(s.flock_id)
  ));
