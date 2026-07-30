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

tmp_dir="$(mktemp -d /tmp/cm-agent-hardening.XXXXXX)"
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
create role service_role nologin;

create schema chickmark_private;

create table public.customers (
  id text primary key
);

create table public.flocks (
  id text primary key,
  customer_id text references public.customers(id),
  farm_id text,
  sector_key text check (
    sector_key is null or sector_key in ('breeder', 'broiler', 'layer')
  )
);

create table public.audit_sessions (
  id text primary key,
  customer_id text not null references public.customers(id),
  flock_id text not null references public.flocks(id),
  hatchery_id text not null
);

create table public.agent_conversations (
  id text primary key,
  state_version integer not null default 1
    check (state_version >= 1)
);

create table public.agent_conversation_turns (
  id text primary key,
  conversation_id text not null
    references public.agent_conversations(id) on delete cascade,
  direction text not null check (direction in ('inbound', 'outbound')),
  model text,
  created_at text not null,
  turn_index integer,
  constraint agent_conversation_turns_inbound_index_check check (
    (direction = 'inbound' and turn_index is not null and turn_index >= 1)
    or (direction = 'outbound' and turn_index is null)
  )
);

create unique index idx_agent_conversation_turns_inbound_index
  on public.agent_conversation_turns(conversation_id, turn_index)
  where direction = 'inbound';

create table public.agent_tool_events (
  id text primary key,
  conversation_turn_id text not null
    references public.agent_conversation_turns(id) on delete cascade,
  created_at text not null
);

create function chickmark_private.protect_agent_tool_event()
returns trigger
language plpgsql
as $$
begin
  raise exception 'agent tool evidence is immutable';
end
$$;

create trigger agent_tool_events_immutable
before update or delete on public.agent_tool_events
for each row execute function chickmark_private.protect_agent_tool_event();

insert into public.customers(id) values ('customer-a');

insert into public.flocks(id, customer_id, farm_id, sector_key) values
  ('flock-a', 'customer-a', null, null),
  ('flock-explicit', 'customer-a', null, 'layer');

insert into public.audit_sessions(id, customer_id, flock_id, hatchery_id)
values ('audit-a', 'customer-a', 'flock-a', 'hatchery-a');

insert into public.agent_conversations(id) values ('conversation-a');

insert into public.agent_conversation_turns(
  id,
  conversation_id,
  direction,
  created_at,
  turn_index
) values
  ('turn-inbound', 'conversation-a', 'inbound', '2026-07-30T10:00:00Z', 1),
  ('turn-outbound', 'conversation-a', 'outbound', '2026-07-30T10:00:01Z', null);

insert into public.agent_tool_events(id, conversation_turn_id, created_at)
values ('tool-a', 'turn-inbound', '2026-07-30T10:00:00.500Z');
SQL

"${psql[@]}" \
  -f "${repo_root}/supabase/migrations/20260730111832_agent_hardening.sql" \
  >/dev/null

"${psql[@]}" <<'SQL'
do $agent_hardening_test$
begin
  if to_regclass('public.farms') is not null
     or to_regclass('public.customer_sectors') is not null then
    raise exception 'production-compatible fixture unexpectedly has optional sector tables';
  end if;

  if (
    select sector_key
    from public.flocks
    where id = 'flock-a'
  ) is distinct from 'breeder' then
    raise exception 'hatchery-audit sector evidence was not applied';
  end if;

  if (
    select sector_key
    from public.flocks
    where id = 'flock-explicit'
  ) is distinct from 'layer' then
    raise exception 'explicit flock sector was overwritten';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'agent_conversations'
      and column_name = 'selected_audit_id'
  ) then
    raise exception 'conversation context columns were not added';
  end if;

  if (
    select reply_to_turn_id
    from public.agent_conversation_turns
    where id = 'turn-outbound'
  ) is distinct from 'turn-inbound' then
    raise exception 'assistant reply ordering was not backfilled';
  end if;

  if (
    select tool_sequence
    from public.agent_tool_events
    where id = 'tool-a'
  ) is distinct from 1 then
    raise exception 'tool sequence was not backfilled';
  end if;
end
$agent_hardening_test$;
SQL

echo "Agent hardening migration compatibility checks passed."
