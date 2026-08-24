#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"

find_postgres_bin() {
  if [[ -n "${CHICKMARK_POSTGRES_BIN:-}" ]] &&
     [[ -x "${CHICKMARK_POSTGRES_BIN}/initdb" ]]; then
    printf '%s\n' "${CHICKMARK_POSTGRES_BIN}"
    return
  fi

  local initdb_path
  initdb_path="$(command -v initdb 2>/dev/null || true)"
  if [[ -n "${initdb_path}" ]]; then
    dirname "${initdb_path}"
    return
  fi

  local candidate
  for candidate in /Library/PostgreSQL/*/bin /opt/homebrew/opt/postgresql*/bin; do
    if [[ -x "${candidate}/initdb" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done
}

postgres_bin="$(find_postgres_bin)"
if [[ -z "${postgres_bin}" ]]; then
  echo "PostgreSQL tools were not found; set CHICKMARK_POSTGRES_BIN." >&2
  exit 69
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/chickmark-security.XXXXXX")"
data_dir="${tmp_dir}/data"
socket_dir="${tmp_dir}/socket"
port=$((49152 + ($$ % 10000)))
mkdir -p "${socket_dir}"

cleanup() {
  if [[ -d "${data_dir}" ]]; then
    "${postgres_bin}/pg_ctl" -D "${data_dir}" -m immediate stop >/dev/null 2>&1 || true
  fi
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

"${postgres_bin}/initdb" \
  -D "${data_dir}" \
  --auth=trust \
  --username=postgres \
  --no-locale \
  --encoding=UTF8 >/dev/null
"${postgres_bin}/pg_ctl" \
  -D "${data_dir}" \
  -o "-F -p ${port} -k ${socket_dir}" \
  -w start >/dev/null

psql=(
  "${postgres_bin}/psql"
  -h "${socket_dir}"
  -p "${port}"
  -U postgres
  -d postgres
  -v ON_ERROR_STOP=1
  -X
)

"${psql[@]}" >/dev/null <<'SQL'
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

create schema auth;
create table auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);
create function auth.uid()
  returns uuid
  language sql
  stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create function auth.role()
  returns text
  language sql
  stable
as $$
  select nullif(current_setting('request.jwt.claim.role', true), '');
$$;

create schema storage;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false
);
create table storage.objects (
  id text primary key,
  bucket_id text references storage.buckets(id),
  name text not null
);
alter table storage.objects enable row level security;
SQL

for migration in "${repo_root}"/supabase/migrations/*.sql; do
  if [[ "$(basename "${migration}")" == "20260824033958_chick_quality_v2_phase2_identity.sql" ]]; then
    "${psql[@]}" >/dev/null <<'SQL'
alter table public.chick_quality
  add column if not exists domain text,
  add column if not exists schema_version integer,
  add column if not exists scope_key text,
  add column if not exists replicate integer,
  add column if not exists sample_key text,
  add column if not exists source text,
  add column if not exists capture_method text,
  add column if not exists created_by text,
  add column if not exists device_id text,
  add column if not exists source_ref_id text,
  add column if not exists observed_at text;
alter table public.chick_weights
  add column if not exists domain text,
  add column if not exists schema_version integer,
  add column if not exists scope_key text,
  add column if not exists replicate integer,
  add column if not exists sample_key text,
  add column if not exists source text,
  add column if not exists capture_method text,
  add column if not exists created_by text,
  add column if not exists device_id text,
  add column if not exists source_ref_id text,
  add column if not exists observed_at text;

drop index if exists public.idx_chick_quality_identity;
drop index if exists public.idx_chick_weights_identity;
insert into public.customers (id, name) values ('phase2-backfill-customer', 'Phase 2 backfill');
insert into public.hatcheries (id, customer_id, name)
  values ('phase2-backfill-hatchery', 'phase2-backfill-customer', 'Backfill hatchery');
insert into public.flocks (id, customer_id, flock_id)
  values ('phase2-backfill-flock', 'phase2-backfill-customer', 'Backfill flock');
insert into public.audit_sessions (id, customer_id, flock_id, hatchery_id, date)
  values ('phase2-backfill-session', 'phase2-backfill-customer',
    'phase2-backfill-flock', 'phase2-backfill-hatchery', '2026-08-24');

with duplicate_key as (
  select rtrim(translate(replace(encode(convert_to(
    '["chicks.legacy_combined","phase2-backfill-session","setter_hatcher","{\"hatcher\":\"H1\",\"setter\":\"S1\"}",1]',
    'UTF8'), 'base64'), E'\n', ''), '+/', '-_'), '=') as value
)
insert into public.chick_quality (
  id, session_id, customer_id, date, setter, hatcher, created_at, updated_at,
  domain, schema_version, scope_type, scope_key, replicate, sample_key
)
select id, 'phase2-backfill-session', 'phase2-backfill-customer', '2026-08-24',
  'S1', 'H1', created_at, created_at, 'chicks.legacy_combined', 1,
  'setter_hatcher', '{"hatcher":"H1","setter":"S1"}', 1, duplicate_key.value
from duplicate_key cross join (values
  ('phase2-backfill-quality-a', '2026-08-24T00:00:00Z'),
  ('phase2-backfill-quality-b', '2026-08-24T00:00:01Z')
) seeded(id, created_at);

insert into public.chick_quality (
  id, session_id, customer_id, date, house, setter, hatcher, trolley, tray,
  position, scope_type, pasgar_sample_size, created_at, updated_at
) values (
  'phase2-backfill-quality-extra', 'phase2-backfill-session',
  'phase2-backfill-customer', '2026-08-24', 'House X', 'S2', 'H2',
  'Trolley X', 'Tray X', 'Position X', 'house', 40,
  '2026-08-24T00:00:02Z', '2026-08-24T00:00:02Z'
);
insert into public.chick_quality (
  id, session_id, customer_id, date, setter, scope_type, pasgar_sample_size,
  created_at, updated_at
) values (
  'phase2-backfill-quality-missing-hatcher', 'phase2-backfill-session',
  'phase2-backfill-customer', '2026-08-24', 'S3', 'setter_hatcher', 30,
  '2026-08-24T00:00:03Z', '2026-08-24T00:00:03Z'
);
insert into public.chick_weights (
  id, session_id, customer_id, date, house, setter, scope_type, weights_json,
  created_at, updated_at
) values (
  'phase2-backfill-weight-extra', 'phase2-backfill-session',
  'phase2-backfill-customer', '2026-08-24', 'House W', 'Ignored Setter',
  'setter_hatcher', '[40.0]', '2026-08-24T00:00:04Z', '2026-08-24T00:00:04Z'
);
insert into public.chick_weights (
  id, session_id, customer_id, date, scope_type, weights_json,
  created_at, updated_at
) values (
  'phase2-backfill-weight-missing-house', 'phase2-backfill-session',
  'phase2-backfill-customer', '2026-08-24', 'house', '[41.0]',
  '2026-08-24T00:00:05Z', '2026-08-24T00:00:05Z'
);
SQL
  fi
  "${psql[@]}" -f "${migration}" >/dev/null
done

"${psql[@]}" >/dev/null <<'SQL'
do $phase2_backfill_test$
declare
  repaired_replicate integer;
  repaired_scope_type text;
  repaired_scope_key text;
begin
  if (select count(*) from public.chick_quality
      where id like 'phase2-backfill-quality-%') <> 4 then
    raise exception 'Phase 2 cloud backfill changed the seeded quality row count';
  end if;
  select replicate into repaired_replicate from public.chick_quality
    where id = 'phase2-backfill-quality-b';
  if repaired_replicate is null or repaired_replicate <> 2 then
    raise exception 'duplicate pre-existing V2 envelope was not repaired: %', repaired_replicate;
  end if;
  select scope_type, scope_key into repaired_scope_type, repaired_scope_key
    from public.chick_quality where id = 'phase2-backfill-quality-extra';
  if repaired_scope_type <> 'setter_hatcher'
     or repaired_scope_key <> '{"hatcher":"H2","house":"House X","position":"Position X","setter":"S2","tray":"Tray X","trolley":"Trolley X"}' then
    raise exception 'quality scope parity mismatch: % %', repaired_scope_type, repaired_scope_key;
  end if;
  select scope_type, scope_key into repaired_scope_type, repaired_scope_key
    from public.chick_weights where id = 'phase2-backfill-weight-extra';
  if repaired_scope_type <> 'house'
     or repaired_scope_key <> '{"house":"House W","setter":"Ignored Setter"}' then
    raise exception 'weight scope parity mismatch: % %', repaired_scope_type, repaired_scope_key;
  end if;
  select scope_type, scope_key into repaired_scope_type, repaired_scope_key
    from public.chick_quality
    where id = 'phase2-backfill-quality-missing-hatcher';
  if repaired_scope_type <> 'setter_hatcher'
     or repaired_scope_key <> '{"hatcher":null,"setter":"S3"}' then
    raise exception 'missing hatcher scope parity mismatch: % %', repaired_scope_type, repaired_scope_key;
  end if;
  select scope_type, scope_key into repaired_scope_type, repaired_scope_key
    from public.chick_weights
    where id = 'phase2-backfill-weight-missing-house';
  if repaired_scope_type <> 'house'
     or repaired_scope_key <> '{"house":null}' then
    raise exception 'missing house scope parity mismatch: % %', repaired_scope_type, repaired_scope_key;
  end if;
end
$phase2_backfill_test$;
SQL

# Keep the Dart cloud-parity fixture tied to the schema PostgreSQL actually
# produced. This deliberately queries information_schema after every migration
# has executed; parsing migration text cannot see DDL emitted by dynamic
# PL/pgSQL. When the schema changes, this guard prints the replacement fixture
# but never rewrites repository files on its own.
cloud_columns_fixture="${repo_root}/test/data/database/fixtures/chick_panel_cloud_columns.json"
actual_cloud_columns="${tmp_dir}/chick_panel_cloud_columns.json"
"${psql[@]}" -At <<'SQL' >"${actual_cloud_columns}"
select jsonb_pretty(jsonb_object_agg(table_name, columns order by table_name))
from (
  select
    table_name,
    jsonb_agg(column_name order by ordinal_position) as columns
  from information_schema.columns
  where table_schema = 'public'
    and table_name in ('chick_quality', 'chick_weights')
  group by table_name
) cloud_columns;
SQL

if [[ ! -f "${cloud_columns_fixture}" ]]; then
  echo "Missing executed-migration cloud column fixture: ${cloud_columns_fixture}" >&2
  echo "Create it with this PostgreSQL-derived content:" >&2
  cat "${actual_cloud_columns}" >&2
  exit 1
fi

if ! diff -u "${cloud_columns_fixture}" "${actual_cloud_columns}"; then
  echo "Chick panel cloud column fixture is stale; replace it with the actual schema above." >&2
  exit 1
fi

"${psql[@]}" <<'SQL'
do $security_test$
declare
  helper_count integer;
  public_helper_count integer;
  function_row record;
begin
  select count(*)
  into helper_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'chickmark_private'
    and p.proname like 'app$_%' escape '$';

  -- 9 since the organizations stack (20260813171740..20260813183005) added
  -- app_org_id and app_org_role alongside the original seven. Verified against
  -- production on 2026-08-16: chickmark_private has exactly these nine.
  if helper_count <> 9 then
    raise exception 'expected 9 private authorization helpers, found %', helper_count;
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'chickmark_private'
      and p.proname like 'app$_%' escape '$'
      and (
        not p.prosecdef
        or coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=""%'
      )
  ) then
    raise exception 'private authorization helpers must be SECURITY DEFINER with an empty search_path';
  end if;

  select count(*)
  into public_helper_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname like 'app$_%' escape '$';

  if public_helper_count <> 0 then
    raise exception 'public authorization helpers were not removed';
  end if;

  if exists (
    select 1
    from pg_policies
    where schemaname in ('public', 'storage')
      and (
        coalesce(qual, '') like '%public.app_%'
        or coalesce(with_check, '') like '%public.app_%'
      )
  ) then
    raise exception 'an RLS policy still references a public authorization helper';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'sync_tombstones'
      and policyname = 'tombstones_select'
      and coalesce(qual, '') like '%chickmark_private.app_is_admin%'
      and coalesce(qual, '') like '%audience_user_ids%'
  ) then
    raise exception 'tenant-scoped tombstone read policy is missing';
  end if;

  for function_row in
    select p.oid, p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'chickmark_private'
      and p.proname like 'app$_%' escape '$'
  loop
    if has_function_privilege('anon', function_row.oid, 'EXECUTE') then
      raise exception 'anon can execute private helper %', function_row.proname;
    end if;
    if not has_function_privilege('authenticated', function_row.oid, 'EXECUTE') then
      raise exception 'authenticated cannot execute private helper %', function_row.proname;
    end if;
    if not has_function_privilege('service_role', function_row.oid, 'EXECUTE') then
      raise exception 'service_role cannot execute private helper %', function_row.proname;
    end if;
    if exists (
      select 1
      from aclexplode(coalesce(
        (select proacl from pg_proc where oid = function_row.oid),
        acldefault('f', (select proowner from pg_proc where oid = function_row.oid))
      )) acl
      where acl.grantee = 0
        and acl.privilege_type = 'EXECUTE'
    ) then
      raise exception 'PUBLIC can execute private helper %', function_row.proname;
    end if;
  end loop;

  for function_row in
    select p.oid, p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'handle_new_auth_user',
        'handle_new_customer',
        'touch_updated_at'
      )
  loop
    if has_function_privilege('anon', function_row.oid, 'EXECUTE')
       or has_function_privilege('authenticated', function_row.oid, 'EXECUTE') then
      raise exception 'API role can execute public trigger function %', function_row.proname;
    end if;
    if exists (
      select 1
      from aclexplode(coalesce(
        (select proacl from pg_proc where oid = function_row.oid),
        acldefault('f', (select proowner from pg_proc where oid = function_row.oid))
      )) acl
      where acl.grantee = 0
        and acl.privilege_type = 'EXECUTE'
    ) then
      raise exception 'PUBLIC can execute public trigger function %', function_row.proname;
    end if;
  end loop;
end
$security_test$;

insert into auth.users (
  id,
  email,
  raw_user_meta_data
) values (
  '00000000-0000-0000-0000-000000000099',
  'security-test@example.test',
  '{"full_name":"Security test"}'
);

update public.profiles
set role = 'admin', status = 'pending'
where id = '00000000-0000-0000-0000-000000000099';

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000099',
  false
);

do $admin_test$
begin
  if chickmark_private.app_is_admin() then
    raise exception 'pending admin was authorized';
  end if;

  update public.profiles
  set status = 'approved'
  where id = '00000000-0000-0000-0000-000000000099';

  if not chickmark_private.app_is_admin() then
    raise exception 'approved admin was not authorized';
  end if;
end
$admin_test$;
SQL

echo "Supabase security migration integration checks passed."

# ---------------------------------------------------------------------------
# chick_quality / chick_weights RLS regression guard.
#
# The base migration (20260605134739_full_sync_schema) shipped a wide-open
# `authenticated_all` policy on both panel tables. It is dropped by
# 20260606080930_0003_auth_rls and replaced with tenant-scoped `<t>_select` /
# `<t>_write` policies by 20260719131203_0007_security_hardening. Nothing in the
# migration chain stops a future migration from re-creating the open policy, so
# the end state is asserted here instead of trusted.
# ---------------------------------------------------------------------------
"${psql[@]}" <<'SQL'
do $security_test$
declare
  panel_table   text;
  policy_row    record;
  policy_count  integer;
  rls_enabled   boolean;
begin
  foreach panel_table in array array['chick_quality', 'chick_weights'] loop
    select c.relrowsecurity
    into rls_enabled
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = panel_table;

    if rls_enabled is distinct from true then
      raise exception 'row level security is not enabled on public.%', panel_table;
    end if;

    if exists (
      select 1
      from pg_policies
      where schemaname = 'public'
        and tablename = panel_table
        and policyname = 'authenticated_all'
    ) then
      raise exception 'the wide-open authenticated_all policy is back on public.%', panel_table;
    end if;

    select count(*)
    into policy_count
    from pg_policies
    where schemaname = 'public'
      and tablename = panel_table;

    if policy_count <> 2 then
      raise exception 'public.% must carry exactly 2 policies, found %',
        panel_table, policy_count;
    end if;

    if not exists (
      select 1
      from pg_policies
      where schemaname = 'public'
        and tablename = panel_table
        and policyname = panel_table || '_select'
        and cmd = 'SELECT'
        and coalesce(qual, '') like '%chickmark_private.app_can_read_customer%'
    ) then
      raise exception 'tenant-scoped select policy %_select is missing or unscoped',
        panel_table;
    end if;

    if not exists (
      select 1
      from pg_policies
      where schemaname = 'public'
        and tablename = panel_table
        and policyname = panel_table || '_write'
        and cmd = 'ALL'
        and coalesce(qual, '') like '%chickmark_private.app_can_write_customer%'
        and coalesce(with_check, '') like '%chickmark_private.app_can_write_customer%'
    ) then
      raise exception 'tenant-scoped write policy %_write is missing or unscoped',
        panel_table;
    end if;

    for policy_row in
      select policyname, cmd, qual, with_check
      from pg_policies
      where schemaname = 'public'
        and tablename = panel_table
    loop
      if policy_row.qual is null or btrim(policy_row.qual) = 'true' then
        raise exception 'policy % on public.% has a permissive-everything USING clause',
          policy_row.policyname, panel_table;
      end if;
      if policy_row.cmd = 'ALL'
         and (policy_row.with_check is null or btrim(policy_row.with_check) = 'true') then
        raise exception 'policy % on public.% has a permissive-everything WITH CHECK clause',
          policy_row.policyname, panel_table;
      end if;
    end loop;
  end loop;
end
$security_test$;
SQL

# ---------------------------------------------------------------------------
# chick_quality / chick_weights cloud identity uniqueness
# (20260823120000_chick_panel_identity_uniqueness).
#
# A fresh database has no rows, so both conditional unique indexes must exist
# after the migration chain, with the exact coalesce() expression list that
# mirrors the local SQLite `_panelUniqueRowIndexSql` rule.
# ---------------------------------------------------------------------------
: <<'LEGACY_PHASE1_IDENTITY_TEST'
"${psql[@]}" <<'SQL'
do $identity_test$
declare
  panel_table text;
  index_name  text;
  index_def   text;
  expected    text;
begin
  foreach panel_table in array array['chick_quality', 'chick_weights'] loop
    index_name := format('idx_%s_identity', panel_table);

    select pg_get_indexdef(c.oid)
    into index_def
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = index_name
      and c.relkind = 'i';

    if index_def is null then
      raise exception 'unique identity index % was not created on a fresh database',
        index_name;
    end if;

    expected := format(
      'CREATE UNIQUE INDEX %s ON public.%s USING btree '
      '(session_id, COALESCE(house, ''''::text), COALESCE(setter, ''''::text), '
      'COALESCE(hatcher, ''''::text), COALESCE(trolley, ''''::text), '
      'COALESCE(tray, ''''::text), COALESCE("position", ''''::text))',
      index_name, panel_table
    );

    if index_def <> expected then
      raise exception 'identity index % has unexpected definition: % (expected %)',
        index_name, index_def, expected;
    end if;
  end loop;

  if not exists (
    select 1
    from pg_views
    where schemaname = 'public'
      and viewname = 'chick_panel_duplicate_identities'
  ) then
    raise exception 'duplicate-detection view is missing';
  end if;

  if has_table_privilege('anon', 'public.chick_panel_duplicate_identities', 'SELECT')
     or has_table_privilege('authenticated', 'public.chick_panel_duplicate_identities', 'SELECT') then
    raise exception 'the duplicate-detection view is exposed to an API role';
  end if;

  if not has_table_privilege('service_role', 'public.chick_panel_duplicate_identities', 'SELECT') then
    raise exception 'service_role cannot read the duplicate-detection view';
  end if;

  if has_function_privilege('anon', 'public.chickmark_apply_chick_identity_unique_indexes()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.chickmark_apply_chick_identity_unique_indexes()', 'EXECUTE') then
    raise exception 'the identity index applier is executable by an API role';
  end if;

  if not has_function_privilege('service_role', 'public.chickmark_apply_chick_identity_unique_indexes()', 'EXECUTE') then
    raise exception 'service_role cannot execute the identity index applier';
  end if;
end
$identity_test$;
SQL

# Behavioural half: the index must actually reject a second row with the same
# identity, and the applier must report (not throw, not delete) when duplicates
# already exist. Everything runs inside one transaction that is rolled back.
"${psql[@]}" <<'SQL'
begin;

insert into public.customers (id, name) values ('cust-identity-test', 'Identity test');
insert into public.hatcheries (id, customer_id, name)
  values ('hatch-identity-test', 'cust-identity-test', 'Identity test hatchery');
insert into public.flocks (id, customer_id, flock_id)
  values ('flock-identity-test', 'cust-identity-test', 'F-identity');
insert into public.audit_sessions (id, customer_id, flock_id, hatchery_id, date)
  values (
    'sess-identity-test',
    'cust-identity-test',
    'flock-identity-test',
    'hatch-identity-test',
    '2026-08-23'
  );

do $identity_reject_test$
declare
  panel_table text;
begin
  foreach panel_table in array array['chick_quality', 'chick_weights'] loop
    execute format($ins$
      insert into public.%I (
        id, session_id, customer_id, date, setter, hatcher,
        created_at, updated_at
      ) values (
        %L, 'sess-identity-test', 'cust-identity-test', '2026-08-23',
        'S1', 'H1', '2026-08-23T00:00:00Z', '2026-08-23T00:00:00Z'
      )
    $ins$, panel_table, panel_table || '-row-a');

    begin
      execute format($ins$
        insert into public.%I (
          id, session_id, customer_id, date, setter, hatcher,
          created_at, updated_at
        ) values (
          %L, 'sess-identity-test', 'cust-identity-test', '2026-08-23',
          'S1', 'H1', '2026-08-23T00:00:00Z', '2026-08-23T00:00:00Z'
        )
      $ins$, panel_table, panel_table || '-row-b');

      raise exception
        'public.% accepted a second row with the same panel identity', panel_table;
    exception
      when unique_violation then
        null;
    end;

    -- NULL and '' must collapse to the same identity, exactly like IFNULL().
    begin
      execute format($ins$
        insert into public.%I (
          id, session_id, customer_id, date, setter, hatcher, house,
          created_at, updated_at
        ) values (
          %L, 'sess-identity-test', 'cust-identity-test', '2026-08-23',
          'S1', 'H1', '', '2026-08-23T00:00:00Z', '2026-08-23T00:00:00Z'
        )
      $ins$, panel_table, panel_table || '-row-c');

      raise exception
        'public.% treated NULL and empty string as different identities', panel_table;
    exception
      when unique_violation then
        null;
    end;
  end loop;
end
$identity_reject_test$;

-- Simulate a legacy database that already carries duplicates: drop the guard,
-- create a collision, and prove the applier reports instead of failing.
drop index public.idx_chick_quality_identity;

insert into public.chick_quality (
  id, session_id, customer_id, date, setter, hatcher, created_at, updated_at
) values (
  'chick_quality-row-dup', 'sess-identity-test', 'cust-identity-test',
  '2026-08-23', 'S1', 'H1', '2026-08-23T00:00:00Z', '2026-08-23T00:00:00Z'
);

do $identity_duplicate_test$
declare
  outcome    text;
  view_rows  integer;
  data_rows  integer;
begin
  select count(*)
  into view_rows
  from public.chick_panel_duplicate_identities
  where table_name = 'chick_quality';

  if view_rows <> 1 then
    raise exception 'duplicate view reported % chick_quality groups, expected 1', view_rows;
  end if;

  if not exists (
    select 1
    from public.chick_panel_duplicate_identities
    where table_name = 'chick_quality'
      and row_count = 2
      and row_ids @> array['chick_quality-row-a', 'chick_quality-row-dup']
  ) then
    raise exception 'duplicate view did not name both colliding chick_quality rows';
  end if;

  outcome := public.chickmark_apply_chick_identity_unique_indexes();

  if outcome not like '%chick_quality: SKIPPED%' then
    raise exception 'applier did not report the chick_quality duplicates: %', outcome;
  end if;

  if outcome not like '%chick_weights: unique identity index%already present%' then
    raise exception 'applier misreported the healthy chick_weights table: %', outcome;
  end if;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'idx_chick_quality_identity'
  ) then
    raise exception 'applier created the unique index despite live duplicates';
  end if;

  select count(*) into data_rows from public.chick_quality;
  if data_rows <> 2 then
    raise exception 'applier mutated chick_quality data (% rows remain)', data_rows;
  end if;

  -- After the operator resolves the duplicate, the same call must succeed.
  delete from public.chick_quality where id = 'chick_quality-row-dup';

  outcome := public.chickmark_apply_chick_identity_unique_indexes();
  if outcome not like '%chick_quality: created unique identity index%' then
    raise exception 'applier did not re-create the index after cleanup: %', outcome;
  end if;
end
$identity_duplicate_test$;

rollback;
SQL

echo "Chick panel identity uniqueness and RLS regression checks passed."
LEGACY_PHASE1_IDENTITY_TEST

# Phase 2 replaces hierarchy uniqueness with immutable customer/sample-key
# uniqueness. Same-scope replicates must coexist; reusing a sample key must
# fail. The helper vector is shared with the Dart identity test.
"${psql[@]}" <<'SQL'
begin;

insert into public.customers (id, name) values ('cust-v2-identity', 'V2 identity');
insert into public.hatcheries (id, customer_id, name)
  values ('hatch-v2-identity', 'cust-v2-identity', 'V2 hatchery');
insert into public.flocks (id, customer_id, flock_id)
  values ('flock-v2-identity', 'cust-v2-identity', 'F-V2');
insert into public.audit_sessions (id, customer_id, flock_id, hatchery_id, date)
  values ('session-1', 'cust-v2-identity', 'flock-v2-identity', 'hatch-v2-identity', '2026-08-24');

do $v2_identity_test$
declare
  panel_table text;
  index_name text;
  derived_key text;
  derived_replicate integer;
  key_one text;
  key_two text;
  identity_rejected boolean;
begin
  derived_key := chickmark_private.chick_sample_key(
    'chicks.weights', 'session-1', 'house', '{"house":"House A"}', 1
  );
  if derived_key <> 'WyJjaGlja3Mud2VpZ2h0cyIsInNlc3Npb24tMSIsImhvdXNlIiwie1wiaG91c2VcIjpcIkhvdXNlIEFcIn0iLDFd' then
    raise exception 'Postgres sample key differs from the Dart canonical vector: %', derived_key;
  end if;

  if to_regclass('public.idx_chick_quality_identity') is not null
     or to_regclass('public.idx_chick_weights_identity') is not null then
    raise exception 'legacy hierarchy identity index survived Phase 2';
  end if;

  foreach panel_table in array array['chick_quality', 'chick_weights'] loop
    index_name := format('idx_%s_sample_key', panel_table);
    if to_regclass('public.' || index_name) is null then
      raise exception 'V2 sample-key index % is missing', index_name;
    end if;
    key_one := chickmark_private.chick_sample_key(
      case when panel_table = 'chick_weights' then 'chicks.weights' else 'chicks.legacy_combined' end,
      'session-1', 'pool', '{}', 1
    );
    key_two := chickmark_private.chick_sample_key(
      case when panel_table = 'chick_weights' then 'chicks.weights' else 'chicks.legacy_combined' end,
      'session-1', 'pool', '{}', 2
    );
    execute format($insert$
      insert into public.%I (
        id, session_id, customer_id, date, created_at, updated_at,
        domain, schema_version, scope_type, scope_key, replicate, sample_key,
        source, capture_method, observed_at
      ) values (
        %L, 'session-1', 'cust-v2-identity', '2026-08-24',
        '2026-08-24T00:00:00Z', '2026-08-24T00:00:00Z', %L, 1,
        'pool', '{}', 1, %L, 'human', 'manual', '2026-08-24T00:00:00Z'
      ), (
        %L, 'session-1', 'cust-v2-identity', '2026-08-24',
        '2026-08-24T00:00:01Z', '2026-08-24T00:00:01Z', %L, 1,
        'pool', '{}', 2, %L, 'agent', 'telegram', '2026-08-24T00:00:01Z'
      )
    $insert$,
      panel_table, panel_table || '-v2-a',
      case when panel_table = 'chick_weights' then 'chicks.weights' else 'chicks.legacy_combined' end,
      key_one, panel_table || '-v2-b',
      case when panel_table = 'chick_weights' then 'chicks.weights' else 'chicks.legacy_combined' end,
      key_two
    );

    execute format($insert$
      insert into public.%I (
        id, session_id, customer_id, date, created_at, updated_at,
        domain, schema_version, scope_type, scope_key,
        source, capture_method, source_ref_id, observed_at
      ) values (
        %L, 'session-1', 'cust-v2-identity', '2026-08-24',
        '2026-08-24T00:00:02Z', '2026-08-24T00:00:02Z', %L, 1,
        'pool', '{}', 'agent', 'conversational_agent', 'intake-v2',
        '2026-08-24T00:00:02Z'
      )
    $insert$,
      panel_table, panel_table || '-v2-agent',
      case when panel_table = 'chick_weights' then 'chicks.weights' else 'chicks.legacy_combined' end
    );
    execute format(
      'select replicate from public.%I where id = %L',
      panel_table, panel_table || '-v2-agent'
    ) into derived_replicate;
    if derived_replicate is null or derived_replicate <> 3 then
      raise exception 'agent replicate allocation for % was %, expected 3', panel_table, derived_replicate;
    end if;

    -- Offline clients can independently mint replicate 1. The cloud must
    -- preserve both ids by reallocating every later collision, regardless of
    -- whether human or agent data arrives first.
    execute format($insert$
      insert into public.%I (
        id, session_id, customer_id, date, created_at, updated_at,
        domain, schema_version, scope_type, scope_key, replicate, sample_key,
        source, capture_method, observed_at
      ) values (
        %L, 'session-1', 'cust-v2-identity', '2026-08-24',
        '2026-08-24T00:00:03Z', '2026-08-24T00:00:03Z', %L, 1,
        'pool', '{}', 1, %L, 'human', 'manual', '2026-08-24T00:00:03Z'
      ), (
        %L, 'session-1', 'cust-v2-identity', '2026-08-24',
        '2026-08-24T00:00:04Z', '2026-08-24T00:00:04Z', %L, 1,
        'pool', '{}', 1, %L, 'agent', 'telegram', '2026-08-24T00:00:04Z'
      )
    $insert$,
      panel_table, panel_table || '-v2-human-collision',
      case when panel_table = 'chick_weights' then 'chicks.weights' else 'chicks.legacy_combined' end,
      key_one, panel_table || '-v2-agent-collision',
      case when panel_table = 'chick_weights' then 'chicks.weights' else 'chicks.legacy_combined' end,
      key_one
    );
    execute format(
      'select min(replicate) from public.%I where id in (%L, %L)',
      panel_table, panel_table || '-v2-human-collision', panel_table || '-v2-agent-collision'
    ) into derived_replicate;
    if derived_replicate is null or derived_replicate <> 4 then
      raise exception 'collision allocation for % started at %, expected 4', panel_table, derived_replicate;
    end if;

    identity_rejected := false;
    begin
      execute format('update public.%I set replicate = 99, sample_key = %L where id = %L',
        panel_table,
        chickmark_private.chick_sample_key(
          case when panel_table = 'chick_weights' then 'chicks.weights' else 'chicks.legacy_combined' end,
          'session-1', 'pool', '{}', 99
        ),
        panel_table || '-v2-b');
    exception when raise_exception then
      identity_rejected := true;
    end;
    if not identity_rejected then
      raise exception 'public.% accepted a mutable V2 identity', panel_table;
    end if;
    execute format('update public.%I set notes = %L where id = %L',
      panel_table, 'measurement-compatible update', panel_table || '-v2-b');
  end loop;
end
$v2_identity_test$;

rollback;
SQL

echo "Chick V2 sample identity and RLS regression checks passed."

# Phase 3 adds advisory quality caches without breaking older inserts. The
# migration trigger conservatively invalidates every caller-supplied cache;
# local clients recompute exact registry quality after pull.
"${psql[@]}" <<'SQL'
begin;

insert into public.customers (id, name)
values ('cust-v2-quality', 'V2 quality');
insert into public.hatcheries (id, customer_id, name)
values ('hatch-v2-quality', 'cust-v2-quality', 'V2 quality hatchery');
insert into public.flocks (id, customer_id, flock_id)
values ('flock-v2-quality', 'cust-v2-quality', 'F-quality');
insert into public.audit_sessions (id, customer_id, flock_id, hatchery_id, date)
values (
  'session-v2-quality', 'cust-v2-quality', 'flock-v2-quality',
  'hatch-v2-quality', '2026-08-24'
);

insert into public.chick_weights (
  id, session_id, customer_id, date, house, weights_json,
  created_at, updated_at, domain, schema_version, scope_type, scope_key,
  source, capture_method, observed_at
) values (
  'quality-old-client', 'session-v2-quality', 'cust-v2-quality',
  '2026-08-24', 'H1', '[40,41]', '2026-08-24T00:00:00Z',
  '2026-08-24T00:00:00Z', 'chicks.weights', 1, 'house', '{"house":"H1"}',
  'legacy', 'unknown', '2026-08-24T00:00:00Z'
);

insert into public.chick_weights (
  id, session_id, customer_id, date, house, weights_json,
  created_at, updated_at, domain, schema_version, scope_type, scope_key,
  source, capture_method, observed_at, quality_status, quality_flags
) values (
  'quality-current-client', 'session-v2-quality', 'cust-v2-quality',
  '2026-08-24', 'H2', '[42,43]', '2026-08-24T00:00:01Z',
  '2026-08-24T00:00:01Z', 'chicks.weights', 1, 'house', '{"house":"H2"}',
  'human', 'manual', '2026-08-24T00:00:01Z', 'OK', '[]'
);

do $quality_test$
declare
  old_status text;
  old_flags text;
  current_status text;
  current_flags text;
begin
  select quality_status, quality_flags into old_status, old_flags
  from public.chick_weights where id = 'quality-old-client';
  if old_status <> 'FLAG' or old_flags not like '%legacy_quality_unclassified%' then
    raise exception 'old-client quality fallback mismatch: % %', old_status, old_flags;
  end if;

  select quality_status, quality_flags into current_status, current_flags
  from public.chick_weights where id = 'quality-current-client';
  if current_status <> 'FLAG' or current_flags not like '%legacy_quality_unclassified%' then
    raise exception 'spoofed current-client quality result was trusted: % %', current_status, current_flags;
  end if;

  update public.chick_weights
  set weights_json = '[0,201]'
  where id = 'quality-current-client';
  select quality_status, quality_flags into current_status, current_flags
  from public.chick_weights where id = 'quality-current-client';
  if current_status <> 'FLAG' or current_flags not like '%legacy_quality_unclassified%' then
    raise exception 'measurement-only update left a stale quality cache: % %', current_status, current_flags;
  end if;

  update public.chick_weights
  set quality_status = 'invented', quality_flags = 'not-json'
  where id = 'quality-current-client';
  select quality_status, quality_flags into current_status, current_flags
  from public.chick_weights where id = 'quality-current-client';
  if current_status <> 'FLAG' or current_flags not like '%legacy_quality_unclassified%' then
    raise exception 'malformed quality cache was not normalized: % %', current_status, current_flags;
  end if;

  if has_function_privilege('anon', 'public.normalize_chick_quality_cache()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.normalize_chick_quality_cache()', 'EXECUTE') then
    raise exception 'quality normalization helper is publicly executable';
  end if;
end
$quality_test$;

rollback;
SQL

echo "Chick V2 registry quality classification regression checks passed."
