# Unapplied migrations

These files are **not** in the production migration ledger and their objects do
not exist in production. They are held here, outside `supabase/migrations/`, so
that the applied set replays cleanly in filename order.

Do not move a file back into `supabase/migrations/` without giving it a fresh
timestamp that sorts after every applied migration, and without a reviewed
decision to apply it.

- `0009_customer_usernames.sql` — superseded. Its `handle_new_auth_user()` body
  would overwrite the live account-type routing added by `20260813172732`.
  Only the column/index/constraint portion should ever be forward-ported.
- `0010_collapse_farm_into_flock.sql` — deferred. Drops the now-unused
  `public.flocks.farm_id` column to match local migration v68. `farms`,
  `houses`, and `flock_placements` were confirmed absent from the remote
  project (this hierarchy has been local-only so far), so nothing else needs
  dropping there.
- `0011_breeder_benchmark_foundation.sql` — deferred. Creates
  `breeder_metric_definitions`, `breeder_benchmark_profiles`, and
  `breeder_benchmark_values` (read-only to `authenticated`, immutable once a
  profile leaves `draft`) and seeds them from the same
  `assets/benchmarks/*.json` files local migration v69 imports, so cloud and
  local hold identical values. Apply together with, or after, local v69.
- `0012_breeder_flock_sync_registration.sql` — deferred (breeder-flock
  -performance ticket 15). Creates every remaining breeder/egg table
  (`houses`, `breeder_flock_milestones`, `breeder_isolation_areas`,
  `breeder_egg_grade_definitions`, `breeder_daily_reports` and its four
  child tables, `breeder_report_revisions`, `breeder_weighing_sessions`/
  `_samples`, and the five `egg_batches`/`egg_shipments` tables) with
  flock-scoped RLS via new `chickmark_private.app_can_read_flock`/
  `app_can_write_flock` helpers. None of these tables existed remotely
  before this file (verified with `mcp__supabase__list_tables`). Its
  `flock_id` foreign keys target `flocks(id)` only, so it applies cleanly
  whether or not 0010 (which drops the unrelated `flocks.farm_id` column)
  has been applied yet. Apply together with, or after, 0011, local
  migration v79, and this ticket's 0013.
- `0013_breeder_daily_report_aggregate_push.sql` — deferred (breeder-flock
  -performance ticket 15, design section 13.1). Adds
  `push_breeder_daily_report_aggregate(payload, base_revision)`, the single
  revision-guarded transaction a daily report's header and all four child
  tables push through together — never a plain per-row upsert, which could
  let a stale child land after a winning header. Apply after 0012.
- `0014_breeder_customer_scope_and_approval_role.sql` — deferred (breeder-
  flock-performance ticket 16, design sections 5.3 and 13). Three things:
  (1) widens `profiles_role_check` to allow `production_manager` and
  redefines `chickmark_private.app_can_read_customer`/`app_can_write_customer`
  (same signatures, so every existing caller picks this up with no other
  file touched) to scope that role via `auditor_customers`, the same
  assignment table `auditor` already uses; (2) adds
  `chickmark_private.app_can_approve_breeder_report()` — the single
  enumerated, documented set of roles (`admin`, `production_manager`)
  permitted to approve a breeder daily report, mirroring
  `BreederApprovalRole.permitted` in
  `lib/services/breeder/breeder_bird_ledger_service.dart` — and a BEFORE
  INSERT/UPDATE trigger on `breeder_daily_reports` that rejects a
  transition into `approved` from a disallowed role, closing the hole
  0013's own header comment flagged (its SECURITY DEFINER RPC bypasses RLS
  but not table triggers, so this also gates the RPC's
  `insert ... on conflict do update` write path); (3) explicitly revokes
  INSERT/UPDATE/DELETE from `authenticated`/`anon` on the benchmark and
  egg-grade reference tables as defense in depth alongside 0011/0012's
  RLS-by-omission. Redefines a function 0012 depends on and adds a trigger
  to a table 0012/0013 create, so apply after 0011, 0012, and 0013 — last
  in the sequence.
- `0015_breeder_performance_alerts.sql` — deferred (breeder-flock
  -performance ticket 17, design sections 10 and 12). Mirrors local
  database version 80's `breeder_alert_rules` (system-wide, seeded, read
  -only client-side reference data — RLS `select` only, INSERT/UPDATE/
  DELETE explicitly revoked, same treatment as 0011's benchmark/egg-grade
  tables) and `breeder_performance_alerts` (flock-scoped, mutable, RLS via
  `chickmark_private.app_can_read_flock`/`app_can_write_flock`, plus a
  house-belongs-to-flock re-check on the write policy since an optional
  `house_id` foreign key alone does not confirm that relationship). Carries
  a partial unique index mirroring the local schema's "at most one open
  alert per customer/flock/house/metric/period" invariant, and seeds the
  same five default alert rules `seedBreederAlertRules` seeds locally.
  Its `rule_id`/`benchmark_profile_id` foreign keys target
  `breeder_alert_rules`/`breeder_benchmark_profiles`, so apply after 0011
  and 0012.
- `0016_breeder_benchmark_additional_profiles.sql` — deferred. Adds the
  three breeder lines that ship alongside Ross 308: Arbor Acres Plus,
  Indian River, Hubbard Conventional (EDGE), and Cobb500 Fast Feather, plus
  the four metric definitions only the Cobb supplement publishes (weekly and
  cumulative fertility, cumulative flock mortality, chick weight).
  Cobb500 Slow Feather was in an earlier revision of this file and was
  removed on 2026-08-29; since the file has never been applied, that is a
  regeneration rather than a cloud delete. GENERATED from the same
  `assets/benchmarks/*.json` files the local importer reads — regenerate
  with `dart run tool/gen_breeder_benchmark_seed_sql.dart` rather than
  hand-editing, and `test/data/database/breeder_benchmark_cloud_parity_test.dart`
  fails if the two drift. Apply after 0011, which creates these tables,
  their RLS policies, and the immutability triggers this file's
  draft -> active sequence is written to satisfy.
