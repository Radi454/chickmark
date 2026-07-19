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
  "${psql[@]}" -f "${migration}" >/dev/null
done

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
    and p.proname like 'app_%';

  if helper_count <> 7 then
    raise exception 'expected 7 private authorization helpers, found %', helper_count;
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'chickmark_private'
      and p.proname like 'app_%'
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
    and p.proname like 'app_%';

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
      and p.proname like 'app_%'
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
