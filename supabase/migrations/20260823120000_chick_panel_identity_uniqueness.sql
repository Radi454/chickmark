-- 20260823120000 chick_panel_identity_uniqueness
--
-- Give public.chick_quality and public.chick_weights the same row identity in
-- the cloud that they already have on the device.
--
-- Background
-- ----------
-- The local SQLite schema enforces one panel row per sampling position via
-- `_panelUniqueRowIndexSql` (lib/data/database/database_schema.dart):
--
--   CREATE UNIQUE INDEX idx_<table>_unique_row ON <table> (
--     sessionId,
--     IFNULL(house, ''), IFNULL(setter, ''), IFNULL(hatcher, ''),
--     IFNULL(trolley, ''), IFNULL(tray, ''), IFNULL(position, '')
--   )
--
-- The cloud mirror never had that guard. As verified on 2026-08-23, the only
-- uniqueness on either table is the `id` primary key, so a retried push, a
-- double-tapped save, or a re-imported session can land two rows describing the
-- same physical tray. `id` is client-generated, so those rows are distinct to
-- Postgres and identical to a human. The pull side then hands the device two
-- rows that its own unique index would have collapsed into one.
--
-- IFNULL(col, '') and coalesce(col, '') are the same rule; the SQL below uses
-- coalesce so the cloud identity is byte-for-byte the local identity. Note that
-- this makes NULL and '' the SAME identity, deliberately: the app writes both
-- for "this layer is not used", and treating them as different would let the
-- duplicate back in through the empty-string door.
--
-- Why the index is created CONDITIONALLY
-- --------------------------------------
-- Production may already contain duplicates created before this guard existed.
-- An unconditional `create unique index` would abort the migration, roll back
-- the whole transaction, and block every later migration behind it — turning a
-- data-quality problem into a deployment outage. Deleting or merging the
-- offending rows automatically is worse: which of two near-identical panel
-- readings is the real one is an operator decision, not a migration's.
--
-- So this migration:
--   1. ships `public.chick_panel_duplicate_identities`, a read-only view that
--      names every colliding identity group and the row ids inside it;
--   2. creates the unique index only on a table that currently has zero such
--      groups, and otherwise raises a WARNING naming the table, the group
--      count, and the view to inspect — never failing, never mutating a row;
--   3. ships `public.chickmark_apply_chick_identity_unique_indexes()` so an
--      operator can re-run step 2 after cleaning duplicates, without needing a
--      new migration. It is idempotent and safe to call repeatedly.
--
-- On a fresh database (no rows at all) both indexes are therefore created
-- immediately, which is the state every new environment starts in.

-- ---------------------------------------------------------------------------
-- 1. Duplicate-detection view
-- ---------------------------------------------------------------------------
-- security_invoker = true so the view can never become a privilege-escalation
-- hole: it is evaluated with the caller's rights and the caller's RLS, exactly
-- like querying the base tables directly. Grants are then restricted to
-- service_role only — this is an operator diagnostic, not app surface, and it
-- is deliberately NOT exposed to anon.
create or replace view public.chick_panel_duplicate_identities
with (security_invoker = true) as
select
  'chick_quality'::text                     as table_name,
  q.session_id,
  coalesce(q.house, '')                     as house,
  coalesce(q.setter, '')                    as setter,
  coalesce(q.hatcher, '')                   as hatcher,
  coalesce(q.trolley, '')                   as trolley,
  coalesce(q.tray, '')                      as tray,
  coalesce(q."position", '')                as "position",
  count(*)                                  as row_count,
  array_agg(q.id order by q.id)             as row_ids
from public.chick_quality q
group by
  q.session_id,
  coalesce(q.house, ''),
  coalesce(q.setter, ''),
  coalesce(q.hatcher, ''),
  coalesce(q.trolley, ''),
  coalesce(q.tray, ''),
  coalesce(q."position", '')
having count(*) > 1
union all
select
  'chick_weights'::text                     as table_name,
  w.session_id,
  coalesce(w.house, '')                     as house,
  coalesce(w.setter, '')                    as setter,
  coalesce(w.hatcher, '')                   as hatcher,
  coalesce(w.trolley, '')                   as trolley,
  coalesce(w.tray, '')                      as tray,
  coalesce(w."position", '')                as "position",
  count(*)                                  as row_count,
  array_agg(w.id order by w.id)             as row_ids
from public.chick_weights w
group by
  w.session_id,
  coalesce(w.house, ''),
  coalesce(w.setter, ''),
  coalesce(w.hatcher, ''),
  coalesce(w.trolley, ''),
  coalesce(w.tray, ''),
  coalesce(w."position", '')
having count(*) > 1;

comment on view public.chick_panel_duplicate_identities is
  'Operator diagnostic: one row per colliding panel identity in chick_quality / '
  'chick_weights, using the same coalesce(col, '''') rule as the local SQLite '
  'unique index. Empty on a healthy database.';

revoke all on public.chick_panel_duplicate_identities from public, anon, authenticated;
grant select on public.chick_panel_duplicate_identities to service_role;

-- ---------------------------------------------------------------------------
-- 2. Re-runnable index applier
-- ---------------------------------------------------------------------------
-- security definer + `set search_path = ''` follows the repo convention for
-- privileged SQL entry points (see 20260816120000_pip_realtime_v1_persistence).
-- Every identifier below is schema-qualified for that reason.
create or replace function public.chickmark_apply_chick_identity_unique_indexes()
returns text
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  target          record;
  duplicate_groups bigint;
  index_present   boolean;
  report          text[] := array[]::text[];
begin
  for target in
    select *
    from (values
      ('chick_quality', 'idx_chick_quality_identity'),
      ('chick_weights', 'idx_chick_weights_identity')
    ) as t(table_name, index_name)
  loop
    select exists (
      select 1
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = target.index_name
        and c.relkind = 'i'
    )
    into index_present;

    if index_present then
      report := report || format(
        '%s: unique identity index %s already present; nothing to do.',
        target.table_name, target.index_name
      );
      continue;
    end if;

    execute format($count$
      select count(*)
      from (
        select 1
        from public.%I
        group by
          session_id,
          coalesce(house, ''),
          coalesce(setter, ''),
          coalesce(hatcher, ''),
          coalesce(trolley, ''),
          coalesce(tray, ''),
          coalesce("position", '')
        having count(*) > 1
      ) as duplicates
    $count$, target.table_name)
    into duplicate_groups;

    if duplicate_groups > 0 then
      raise warning
        'chickmark: % has % duplicate identity group(s); unique index % NOT created. Inspect public.chick_panel_duplicate_identities, resolve the duplicates, then re-run public.chickmark_apply_chick_identity_unique_indexes().',
        target.table_name, duplicate_groups, target.index_name;
      report := report || format(
        '%s: SKIPPED - %s duplicate identity group(s); inspect public.chick_panel_duplicate_identities.',
        target.table_name, duplicate_groups
      );
      continue;
    end if;

    execute format($ddl$
      create unique index if not exists %I
        on public.%I (
          session_id,
          coalesce(house, ''),
          coalesce(setter, ''),
          coalesce(hatcher, ''),
          coalesce(trolley, ''),
          coalesce(tray, ''),
          coalesce("position", '')
        )
    $ddl$, target.index_name, target.table_name);

    report := report || format(
      '%s: created unique identity index %s.',
      target.table_name, target.index_name
    );
  end loop;

  return array_to_string(report, E'\n');
end
$fn$;

comment on function public.chickmark_apply_chick_identity_unique_indexes() is
  'Idempotently creates the chick_quality / chick_weights identity unique '
  'indexes, but only for a table with zero duplicate identity groups. Warns '
  'and skips otherwise. Never deletes, merges, or modifies data.';

revoke all on function public.chickmark_apply_chick_identity_unique_indexes()
  from public, anon, authenticated;
grant execute on function public.chickmark_apply_chick_identity_unique_indexes()
  to service_role;

-- ---------------------------------------------------------------------------
-- 3. First application, inside this migration
-- ---------------------------------------------------------------------------
-- Deliberately a NOTICE, not an exception: a database carrying legacy
-- duplicates must still finish this migration successfully.
do $apply$
declare
  outcome text;
begin
  outcome := public.chickmark_apply_chick_identity_unique_indexes();
  raise notice 'chickmark chick panel identity uniqueness:%', E'\n' || outcome;
end
$apply$;
