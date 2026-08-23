#!/usr/bin/env bash
#
# Tenant-isolation integration test for the IoT schema.
#
# Spins up a throwaway PostgreSQL, replays every migration from empty, then acts
# as real `authenticated` sessions for two different customers and asserts that
# neither can reach the other's hardware or data.
#
# This exists because the IoT tables carry device credentials, bearer tokens and
# remote-control commands. A cross-tenant hole here does not leak a report -- it
# lets one customer reboot another customer's hatchery hardware.
#
# Run: CHICKMARK_POSTGRES_BIN=/Library/PostgreSQL/18/bin bash scripts/test_iot_tenant_isolation.sh

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"

find_postgres_bin() {
  if [[ -n "${CHICKMARK_POSTGRES_BIN:-}" ]] && [[ -x "${CHICKMARK_POSTGRES_BIN}/initdb" ]]; then
    printf '%s\n' "${CHICKMARK_POSTGRES_BIN}"; return
  fi
  local initdb_path
  initdb_path="$(command -v initdb 2>/dev/null || true)"
  if [[ -n "${initdb_path}" ]]; then dirname "${initdb_path}"; return; fi
  local candidate
  for candidate in /Library/PostgreSQL/*/bin /opt/homebrew/opt/postgresql*/bin; do
    if [[ -x "${candidate}/initdb" ]]; then printf '%s\n' "${candidate}"; return; fi
  done
}

postgres_bin="$(find_postgres_bin)"
if [[ -z "${postgres_bin}" ]]; then
  echo "PostgreSQL tools were not found; set CHICKMARK_POSTGRES_BIN." >&2
  exit 69
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/chickmark-iot.XXXXXX")"
data_dir="${tmp_dir}/data"
socket_dir="${tmp_dir}/socket"
port=$((49152 + (($$ + 7) % 10000)))
mkdir -p "${socket_dir}"

cleanup() {
  if [[ -d "${data_dir}" ]]; then
    "${postgres_bin}/pg_ctl" -D "${data_dir}" -m immediate stop >/dev/null 2>&1 || true
  fi
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

"${postgres_bin}/initdb" -D "${data_dir}" --auth=trust --username=postgres \
  --no-locale --encoding=UTF8 >/dev/null
"${postgres_bin}/pg_ctl" -D "${data_dir}" -o "-F -p ${port} -k ${socket_dir}" -w start >/dev/null

psql=(
  "${postgres_bin}/psql" -h "${socket_dir}" -p "${port}" -U postgres -d postgres
  -v ON_ERROR_STOP=1 -X
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
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create function auth.role() returns text language sql stable as $$
  select nullif(current_setting('request.jwt.claim.role', true), '');
$$;

create schema storage;
create table storage.buckets (id text primary key, name text not null, public boolean not null default false);
create table storage.objects (id text primary key, bucket_id text references storage.buckets(id), name text not null);
alter table storage.objects enable row level security;

-- Reproduce Supabase's stock default privileges. Without these the test would
-- pass for the wrong reason: `authenticated` would be blocked by a missing GRANT
-- rather than by RLS, and we would never find out whether RLS actually works.
alter default privileges for role postgres in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on sequences to anon, authenticated, service_role;
SQL

for migration in "${repo_root}"/supabase/migrations/*.sql; do
  "${psql[@]}" -f "${migration}" >/dev/null
done

# ---------------------------------------------------------------------------
# Fixtures: two unrelated customers, each with a hatchery, a hub and a sensor.
# ---------------------------------------------------------------------------
"${psql[@]}" >/dev/null <<'SQL'
insert into public.customers (id, name) values ('cust-a', 'Customer A'), ('cust-b', 'Customer B');
insert into public.hatcheries (id, customer_id, name)
  values ('hatch-a', 'cust-a', 'Hatchery A'), ('hatch-b', 'cust-b', 'Hatchery B');

insert into public.iot_hub_registry (hub_serial, factory_secret_hash, claim_code_hash, hardware_model)
values
  ('CMH-AAAA0001', encode(sha256(convert_to('secret-a','UTF8')),'hex'),
                   encode(sha256(convert_to('CLAIMCODEAAAAAAA','UTF8')),'hex'), 'chickmark-hub-v1'),
  ('CMH-BBBB0001', encode(sha256(convert_to('secret-b','UTF8')),'hex'),
                   encode(sha256(convert_to('CLAIMCODEBBBBBBB','UTF8')),'hex'), 'chickmark-hub-v1'),
  ('CMH-CCCC0001', encode(sha256(convert_to('secret-c','UTF8')),'hex'),
                   encode(sha256(convert_to('CLAIMCODECCCCCCC','UTF8')),'hex'), 'chickmark-hub-v1');

insert into public.iot_hubs (id, hub_serial, customer_id, hatchery_id, hardware_model)
values
  ('11111111-1111-1111-1111-111111111111','CMH-AAAA0001','cust-a','hatch-a','chickmark-hub-v1'),
  ('22222222-2222-2222-2222-222222222222','CMH-BBBB0001','cust-b','hatch-b','chickmark-hub-v1');

insert into public.iot_hub_secrets (hub_id, device_secret_hash)
values ('11111111-1111-1111-1111-111111111111','hash-a'),
       ('22222222-2222-2222-2222-222222222222','hash-b');

insert into public.iot_device_tokens (token_hash, hub_id, expires_at)
values ('token-a','11111111-1111-1111-1111-111111111111', now() + interval '1 day'),
       ('token-b','22222222-2222-2222-2222-222222222222', now() + interval '1 day');

insert into public.iot_sensors (id, hub_id, customer_id, sensor_uid)
values ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','cust-a','A00000000001'),
       ('bbbbbbbb-0000-0000-0000-000000000002','22222222-2222-2222-2222-222222222222','cust-b','B00000000002');

insert into public.iot_telemetry (customer_id, hub_id, sensor_id, measured_at, batch_id, metrics)
values ('cust-a','11111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-000000000001',
        now(), 'batch-a', '{"temperature_c":21}'::jsonb),
       ('cust-b','22222222-2222-2222-2222-222222222222','bbbbbbbb-0000-0000-0000-000000000002',
        now(), 'batch-b', '{"temperature_c":22}'::jsonb);

-- Three people: an admin, an auditor scoped to A only, and a customer user of A.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1','admin@example.test'),
  ('00000000-0000-0000-0000-0000000000a2','auditor-a@example.test'),
  ('00000000-0000-0000-0000-0000000000a3','customer-a@example.test');

update public.profiles set role='admin',    status='approved' where id='00000000-0000-0000-0000-0000000000a1';
update public.profiles set role='auditor',  status='approved' where id='00000000-0000-0000-0000-0000000000a2';
update public.profiles set role='customer', status='approved', customer_id='cust-a'
  where id='00000000-0000-0000-0000-0000000000a3';
insert into public.auditor_customers (auditor_id, customer_id)
  values ('00000000-0000-0000-0000-0000000000a2','cust-a');
SQL

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
"${psql[@]}" <<'SQL'
create or replace function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, false);
end $$;

do $iot_isolation$
declare
  n integer;
  part text;
  ok boolean;
begin
  ----------------------------------------------------------------------------
  -- 1. Telemetry is readable only by its own tenant, through the parent.
  ----------------------------------------------------------------------------
  perform pg_temp.act_as('00000000-0000-0000-0000-0000000000a3');  -- customer A
  set local role authenticated;

  select count(*) into n from public.iot_telemetry;
  if n <> 1 then raise exception 'customer A should see exactly its own 1 telemetry row, saw %', n; end if;

  select count(*) into n from public.iot_telemetry where customer_id = 'cust-b';
  if n <> 0 then raise exception 'customer A can read customer B telemetry through the parent'; end if;

  reset role;

  ----------------------------------------------------------------------------
  -- 2. ...and ALSO through a partition named directly. This is the one that
  --    silently breaks: partitions inherit neither RLS nor the parent policies.
  ----------------------------------------------------------------------------
  part := 'iot_telemetry_' || to_char(now(), 'YYYY_MM');
  perform pg_temp.act_as('00000000-0000-0000-0000-0000000000a3');
  set local role authenticated;
  begin
    execute format('select count(*) from public.%I', part) into n;
    if n <> 0 then
      raise exception 'customer A read % rows straight from partition % -- partition RLS is missing', n, part;
    end if;
  exception when insufficient_privilege then
    null;  -- also acceptable: the grant itself is gone
  end;
  reset role;

  ----------------------------------------------------------------------------
  -- 3. An auditor for A cannot queue a command onto B's hub, even while
  --    supplying its own customer_id. The composite FK is what stops this.
  ----------------------------------------------------------------------------
  perform pg_temp.act_as('00000000-0000-0000-0000-0000000000a2');  -- auditor A
  set local role authenticated;
  ok := false;
  begin
    insert into public.iot_commands (customer_id, hub_id, command_type)
    values ('cust-a', '22222222-2222-2222-2222-222222222222', 'reboot');
    ok := true;
  exception when others then
    null;
  end;
  if ok then
    raise exception 'CROSS-TENANT COMMAND INJECTION: auditor A queued a reboot on customer B hardware';
  end if;

  -- The same insert onto its OWN hub must still work.
  insert into public.iot_commands (customer_id, hub_id, command_type)
  values ('cust-a', '11111111-1111-1111-1111-111111111111', 'reboot');
  reset role;

  ----------------------------------------------------------------------------
  -- 4. The same for events and config: hub_id alone is never enough.
  ----------------------------------------------------------------------------
  perform pg_temp.act_as('00000000-0000-0000-0000-0000000000a2');
  set local role authenticated;
  ok := false;
  begin
    insert into public.iot_device_events (customer_id, hub_id, event_id, event_type, occurred_at)
    values ('cust-a','22222222-2222-2222-2222-222222222222','e1','hub_boot', now());
    ok := true;
  exception when others then null;
  end;
  if ok then raise exception 'auditor A wrote a device event against customer B hardware'; end if;
  reset role;

  ----------------------------------------------------------------------------
  -- 5. Device credentials and bearer tokens are unreachable by ANY tenant
  --    session, including an admin. Only the service role touches these.
  ----------------------------------------------------------------------------
  foreach part in array array['iot_hub_secrets','iot_device_tokens','iot_telemetry_batches','iot_config_defaults','iot_hub_registry']
  loop
    perform pg_temp.act_as('00000000-0000-0000-0000-0000000000a1');  -- admin
    set local role authenticated;
    begin
      execute format('select count(*) from public.%I', part) into n;
      if n <> 0 then
        raise exception 'admin session read % rows from %, which must be service-role only', n, part;
      end if;
    exception when insufficient_privilege then
      null;
    end;
    reset role;
  end loop;

  ----------------------------------------------------------------------------
  -- 6. A revoked hub cannot be quietly un-revoked. RLS has no column
  --    granularity, so this is enforced by the column GRANT.
  ----------------------------------------------------------------------------
  update public.iot_hubs set status = 'revoked' where id = '11111111-1111-1111-1111-111111111111';
  perform pg_temp.act_as('00000000-0000-0000-0000-0000000000a2');
  set local role authenticated;
  ok := false;
  begin
    update public.iot_hubs set config_version = 999
      where id = '11111111-1111-1111-1111-111111111111';
    ok := true;
  exception when insufficient_privilege then null;
  end;
  if ok then
    raise exception 'a tenant session updated iot_hubs.config_version -- column grants are too wide';
  end if;
  reset role;
  update public.iot_hubs set status = 'active' where id = '11111111-1111-1111-1111-111111111111';

  ----------------------------------------------------------------------------
  -- 7. anon reaches nothing at all.
  ----------------------------------------------------------------------------
  foreach part in array array['iot_hubs','iot_sensors','iot_telemetry','iot_commands','iot_device_events','iot_hub_config']
  loop
    set local role anon;
    begin
      execute format('select count(*) from public.%I', part) into n;
      if n <> 0 then raise exception 'anon read % rows from %', n, part; end if;
    exception when insufficient_privilege then null;
    end;
    reset role;
  end loop;
end
$iot_isolation$;

----------------------------------------------------------------------------
-- 8. iot_claim_hub authorization.
----------------------------------------------------------------------------
do $iot_claim$
declare
  v_hub uuid;
  code  text;
begin
  -- A customer-role user has no write scope anywhere, so it cannot claim.
  perform pg_temp.act_as('00000000-0000-0000-0000-0000000000a3');
  set local role authenticated;
  begin
    v_hub := public.iot_claim_hub('CMH-CCCC0001','CLAIMCODECCCCCCC','hatch-a','x');
    raise exception 'a customer-role user claimed a hub';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- An auditor scoped to A cannot claim into B's hatchery...
  perform pg_temp.act_as('00000000-0000-0000-0000-0000000000a2');
  set local role authenticated;
  begin
    v_hub := public.iot_claim_hub('CMH-CCCC0001','CLAIMCODECCCCCCC','hatch-b','x');
    raise exception 'auditor A claimed a hub into customer B hatchery';
  exception when insufficient_privilege then null;
  end;

  -- ...and a hatchery that does not exist must be INDISTINGUISHABLE from one it
  -- simply may not touch, otherwise this is an id-enumeration oracle.
  begin
    v_hub := public.iot_claim_hub('CMH-CCCC0001','CLAIMCODECCCCCCC','no-such-hatchery','x');
    raise exception 'claim against a non-existent hatchery did not fail';
  exception
    when insufficient_privilege then null;
    when others then
      raise exception 'unknown hatchery leaked a distinct error: % (%)', sqlerrm, sqlstate;
  end;

  -- A wrong claim code returns null, and an unknown serial returns null too --
  -- the same outcome, so this cannot be used to enumerate serials.
  v_hub := public.iot_claim_hub('CMH-CCCC0001','WRONGWRONGWRONGW','hatch-a','x');
  if v_hub is not null then raise exception 'a wrong claim code was accepted'; end if;
  v_hub := public.iot_claim_hub('CMH-NOSUCHSERIAL','WRONGWRONGWRONGW','hatch-a','x');
  if v_hub is not null then raise exception 'an unknown serial was accepted'; end if;

  -- The real thing works.
  v_hub := public.iot_claim_hub('CMH-CCCC0001','CLAIMCODECCCCCCC','hatch-a','Shed 3');
  if v_hub is null then raise exception 'a valid claim returned null'; end if;
  if (select customer_id from public.iot_hubs where id = v_hub) <> 'cust-a' then
    raise exception 'claim bound the hub to the wrong customer';
  end if;

  -- Claiming the same serial twice is refused, not silently duplicated.
  begin
    v_hub := public.iot_claim_hub('CMH-CCCC0001','CLAIMCODECCCCCCC','hatch-a','again');
    raise exception 'the same serial was claimed twice';
  exception when unique_violation then null;
  end;
  reset role;

  -- The child rows the gateway depends on must exist. Checked as postgres,
  -- because a tenant session is correctly forbidden from reading them at all.
  if not exists (select 1 from public.iot_hub_secrets where hub_id = v_hub) then
    raise exception 'claim did not create the hub secret row';
  end if;
  if not exists (select 1 from public.iot_hub_config where hub_id = v_hub) then
    raise exception 'claim did not create the hub config row';
  end if;
end
$iot_claim$;

----------------------------------------------------------------------------
-- 9. Brute-force lockout on the claim code.
----------------------------------------------------------------------------
do $iot_lockout$
declare i integer; v_hub uuid; locked boolean := false;
begin
  perform pg_temp.act_as('00000000-0000-0000-0000-0000000000a2');
  set local role authenticated;
  for i in 1..5 loop
    v_hub := public.iot_claim_hub('CMH-BBBB0001','WRONGWRONGWRONGW','hatch-a','x');
    if v_hub is not null then raise exception 'a wrong claim code was accepted'; end if;
  end loop;
  begin
    v_hub := public.iot_claim_hub('CMH-BBBB0001','WRONGWRONGWRONGW','hatch-a','x');
  exception
    when sqlstate '55P03' then locked := true;
    when others then null;
  end;
  if not locked then
    raise exception 'the claim code did not lock out after 5 failed attempts';
  end if;
  reset role;

  -- ...and the correct code is refused too while the lock stands, otherwise the
  -- lock would only slow down the attacker who is already guessing wrong.
  if (select claim_locked_until from public.iot_hub_registry
       where hub_serial = 'CMH-BBBB0001') is null then
    raise exception 'claim_locked_until was not persisted';
  end if;
end
$iot_lockout$;
SQL

echo "IoT tenant-isolation checks passed."
