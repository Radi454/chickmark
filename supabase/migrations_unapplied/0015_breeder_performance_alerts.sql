-- 0015 breeder performance alerts (breeder-flock-performance ticket 17,
-- design doc docs/superpowers/specs/2026-08-27-breeder-flock-performance-design.md
-- sections 10 and 12)
--
-- Cloud mirror of local database version 80
-- (lib/data/database/database_migrations.dart, _applyV80Upgrade;
-- lib/data/database/database_schema.dart, createBreederAlertRulesTable /
-- createBreederPerformanceAlertsTable). Columns are the snake_case mirror
-- of the SQLite shape; local-only sync bookkeeping (syncStatus, dirtyAt,
-- lastSyncedAt, syncError) is never present here, matching every other
-- table 0011/0012 mirrored.
--
-- This file is deliberately NOT applied by this change — see
-- supabase/migrations_unapplied/README.md. Apply after 0011-0014.

-- `breeder_alert_rules`: system-wide reference data (seeded locally by
-- seedBreederAlertRules in lib/data/database/seeds/breeder_alert_rule_seeds.dart
-- with fixed ids; the cloud rows below carry the same ids and values so a
-- pull never disagrees with what a fresh local install already seeded).
-- Read-only client-side, sync DOWN only, exactly like
-- breeder_metric_definitions/breeder_benchmark_profiles/
-- breeder_benchmark_values in 0011: RLS allows `select` to `authenticated`
-- and INSERT/UPDATE/DELETE are not granted at all, so a hand-crafted
-- request is refused at the privilege-check level before RLS is even
-- evaluated (mirroring 0014's explicit-revoke treatment of the other
-- benchmark/egg-grade reference tables).
create table public.breeder_alert_rules (
  id                                 text primary key,
  metric_code                        text not null check (metric_code in ('body_weight_g', 'hen_week_production_pct', 'liveability_rearing_pct', 'uniformity_pct', 'cv_pct')),
  scope                              text not null check (scope in ('flock', 'house')),
  period_type                        text not null check (period_type in ('daily', 'weekly', 'cumulative')),
  direction                          text not null check (direction in ('below', 'above', 'either')),
  watch_deviation_pct                double precision not null,
  critical_deviation_pct             double precision not null,
  consecutive_observations_required  integer not null default 1,
  uses_official_bound                boolean not null default false,
  is_active                          boolean not null default true,
  notes                              text,
  created_at                         text not null,
  updated_at                         text not null
);
create unique index idx_breeder_alert_rules_unique on public.breeder_alert_rules (metric_code, scope, period_type, direction);

alter table public.breeder_alert_rules enable row level security;
create policy breeder_alert_rules_read on public.breeder_alert_rules
  for select to authenticated using (true);
revoke insert, update, delete on public.breeder_alert_rules from authenticated, anon;

-- `breeder_performance_alerts`: flock-scoped operational data, mutable
-- (acknowledge/close), scoped exactly like every other breeder/egg table
-- via chickmark_private.app_can_read_flock/app_can_write_flock (0012).
-- `house_id` is optional (a flock-scope alert never sets it); the FK to
-- `houses` alone does not confirm it belongs to `flock_id` the way the
-- local house-scope guard trigger
-- (trg_breeder_performance_alerts_house_scope_*) does, so the write policy
-- additionally re-checks that relationship the same way 0012's
-- egg_batch_house_sources write policy re-checks its own parent
-- relationship. The partial unique index mirrors the local
-- idx_breeder_performance_alerts_open_unique exactly: at most one OPEN
-- (state <> 'closed') alert per customer/flock/house/metric/period, with
-- coalesce(...,'') folding a NULL customer_id/house_id to a stable value
-- so two flock-scope rows for the same key still collide (Postgres, like
-- SQLite, treats two NULLs as distinct in a plain unique index).
create table public.breeder_performance_alerts (
  id                              text primary key,
  customer_id                     text references public.customers(id) on delete cascade,
  flock_id                        text not null references public.flocks(id) on delete cascade,
  house_id                        text references public.houses(id),
  rule_id                         text not null references public.breeder_alert_rules(id),
  metric_code                     text not null check (metric_code in ('body_weight_g', 'hen_week_production_pct', 'liveability_rearing_pct', 'uniformity_pct', 'cv_pct')),
  scope                           text not null check (scope in ('flock', 'house')),
  period_type                     text not null check (period_type in ('daily', 'weekly', 'cumulative')),
  period_start                    text not null,
  period_end                      text not null,
  actual_value                    double precision not null,
  official_target_value           double precision,
  official_lower_bound            double precision,
  official_upper_bound            double precision,
  threshold_is_official           boolean not null default false,
  deviation_value                 double precision not null,
  deviation_pct                   double precision,
  severity                        text not null check (severity in ('watch', 'critical')),
  consecutive_observation_count   integer not null default 1,
  benchmark_profile_id            text references public.breeder_benchmark_profiles(id),
  benchmark_profile_version       text,
  comparison_axis_kind            text check (comparison_axis_kind is null or comparison_axis_kind in ('official', 'milestoneAligned')),
  comparison_axis_offset_weeks    integer,
  evidence_report_dates_json      text not null default '',
  state                           text not null default 'new' check (state in ('new', 'seen', 'closed')),
  closed_reason                   text,
  closed_at                       text,
  acknowledged_at                 text,
  acknowledged_by                 text,
  created_at                      text not null,
  updated_at                      text not null
);
create unique index idx_breeder_performance_alerts_open_unique on public.breeder_performance_alerts
  (coalesce(customer_id, ''), flock_id, coalesce(house_id, ''), metric_code, period_type, period_start, period_end)
  where (state <> 'closed');
create index idx_breeder_performance_alerts_flock on public.breeder_performance_alerts (flock_id, period_type, period_start);
create index idx_breeder_performance_alerts_house on public.breeder_performance_alerts (house_id);
create index idx_breeder_performance_alerts_state on public.breeder_performance_alerts (state);

alter table public.breeder_performance_alerts enable row level security;
create policy breeder_performance_alerts_read on public.breeder_performance_alerts for select to authenticated
  using (chickmark_private.app_can_read_flock(flock_id));
create policy breeder_performance_alerts_write on public.breeder_performance_alerts for all to authenticated
  using (
    chickmark_private.app_can_write_flock(flock_id)
    and (house_id is null or exists (
      select 1 from public.houses h
      where h.id = breeder_performance_alerts.house_id
        and h.flock_id = breeder_performance_alerts.flock_id
    ))
  )
  with check (
    chickmark_private.app_can_write_flock(flock_id)
    and (house_id is null or exists (
      select 1 from public.houses h
      where h.id = breeder_performance_alerts.house_id
        and h.flock_id = breeder_performance_alerts.flock_id
    ))
  );

-- Seeded default rules (breeder-flock-performance ticket 17's own
-- operational judgement — see lib/data/database/seeds/breeder_alert_rule_seeds.dart
-- for the full reasoning behind each value; never hand-edit these without
-- editing that file identically).
insert into public.breeder_alert_rules
  (id, metric_code, scope, period_type, direction, watch_deviation_pct, critical_deviation_pct, consecutive_observations_required, uses_official_bound, notes, created_at, updated_at)
values
  ('rule-body_weight_g-flock-weekly-either', 'body_weight_g', 'flock', 'weekly', 'either', 5, 10, 2, false,
   'App-owned: Ross 308 publishes a body-weight target only, no bound.', '2026-08-27T00:00:00.000Z', '2026-08-27T00:00:00.000Z'),
  ('rule-hen_week_production_pct-flock-weekly-below', 'hen_week_production_pct', 'flock', 'weekly', 'below', 5, 10, 1, false,
   'App-owned: Ross 308 publishes a Hen-Week (%) target only, no bound.', '2026-08-27T00:00:00.000Z', '2026-08-27T00:00:00.000Z'),
  ('rule-liveability_rearing_pct-flock-cumulative-below', 'liveability_rearing_pct', 'flock', 'cumulative', 'below', 1, 0, 1, true,
   'Critical threshold is Ross 308''s own published 95% lower bound; the Watch buffer above it is app-owned.', '2026-08-27T00:00:00.000Z', '2026-08-27T00:00:00.000Z'),
  ('rule-uniformity_pct-house-weekly-below', 'uniformity_pct', 'house', 'weekly', 'below', 80, 70, 2, false,
   'App-owned in full: Ross 308 publishes no uniformity target.', '2026-08-27T00:00:00.000Z', '2026-08-27T00:00:00.000Z'),
  ('rule-cv_pct-house-weekly-above', 'cv_pct', 'house', 'weekly', 'above', 8, 12, 2, false,
   'App-owned in full: Ross 308 publishes no CV target.', '2026-08-27T00:00:00.000Z', '2026-08-27T00:00:00.000Z')
on conflict (id) do nothing;
