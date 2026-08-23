#!/usr/bin/env bash
# Replays every migration EXCEPT the Pip Realtime persistence migration into a
# throwaway PostgreSQL, seeds realistic legacy agent data shaped the way the OLD
# code wrote it (no conversation_seq / source_channel / completion_status), and
# only THEN applies 20260816120000_pip_realtime_v1_persistence.sql.
#
# scripts/test_pip_realtime_persistence.sh proves the new invariants hold on an
# EMPTY database. This script proves the backfills are correct on the data
# production actually holds: two conversations, hundreds of turns, tool events.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
realtime_migration="20260816120000_pip_realtime_v1_persistence.sql"
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

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/chickmark-backfill.XXXXXX")"
data_dir="${tmp_dir}/data"
socket_dir="${tmp_dir}/socket"
port=$((29152 + ($$ % 10000)))
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

# --- 1. bring the database to its PRE-Realtime-migration state ---------------
#
# Everything DATED BEFORE the Realtime migration, and nothing else. Skipping
# only the Realtime migration itself (which is what this loop used to do) also
# ran every LATER migration first — and later migrations build on the tables
# the Realtime one creates, so `20260817201500_realtime_call_client_secret.sql`
# failed with `relation "public.agent_realtime_calls" does not exist` and took
# the whole script with it. Migration filenames are timestamp-prefixed, so a
# plain lexicographic comparison is the same as chronological order.
applied_realtime=0
for migration in "${repo_root}"/supabase/migrations/*.sql; do
  name="$(basename "${migration}")"
  if [[ "${name}" == "${realtime_migration}" ]]; then
    applied_realtime=1
    continue
  fi
  # `>` here is a lexicographic string comparison inside [[ ]], not numeric.
  if [[ "${name}" > "${realtime_migration}" ]]; then
    continue
  fi
  "${psql[@]}" -f "${migration}" >/dev/null
done

if [[ "${applied_realtime}" -ne 1 ]]; then
  echo "Expected to find ${realtime_migration} in supabase/migrations." >&2
  exit 1
fi

# Guard: the columns the migration is supposed to ADD must not exist yet, or the
# whole premise of this script (backfilling over legacy rows) is void.
"${psql[@]}" >/dev/null <<'SQL'
do $pre_state$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'agent_conversation_turns'
      and column_name in ('conversation_seq', 'source_channel', 'completion_status')
  ) then
    raise exception 'the Realtime migration leaked into the pre-migration state';
  end if;
end
$pre_state$;
SQL

# --- 2. seed LEGACY data, shaped the way the old code wrote it ---------------
#
# Deliberate adversarial shapes:
#   * conv-app is an app conversation (telegram_chat_id = 'app') now on its
#     SECOND context epoch; conv-tg is a Telegram conversation on epoch 1.
#   * Every outbound turn REUSES its inbound turn_index (the old convention).
#   * created_at ordering disagrees with insertion order, with id ordering, and
#     with turn_index ordering, so a naive backfill produces a different answer.
#   * One epoch-2 turn is older in wall-clock than every epoch-1 turn, so a
#     backfill that ordered by created_at alone would sequence it first.
#   * Two turns share a created_at, so the `id` tiebreak has to do real work.
#   * The Telegram staff link has no app_user_id, so its conversation must end
#     up with a NULL owner_profile_id.
"${psql[@]}" >/dev/null <<'SQL'
insert into auth.users (id, email, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000000000b1', 'backfill@example.test',
        '{"full_name":"Backfill test"}');

update public.profiles
set role = 'admin', status = 'approved'
where id = '00000000-0000-0000-0000-0000000000b1';

insert into public.telegram_staff_links
  (id, channel, telegram_user_id, app_user_id, status, access_role, customer_id,
   created_at, updated_at)
values
  ('link-app', 'app', null, '00000000-0000-0000-0000-0000000000b1', 'allowed',
   'admin', null, '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z'),
  ('link-tg', 'telegram', '55501', null, 'allowed', 'admin', null,
   '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z');

insert into public.agent_conversations
  (id, staff_link_id, telegram_chat_id, context_epoch, created_at, updated_at)
values
  ('conv-app', 'link-app', 'app', 2, '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z'),
  ('conv-tg', 'link-tg', '55501', 1, '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z'),
  -- A conversation that was reset (/new) but has not spoken in its current
  -- epoch yet: its allocator counters must not be seeded from the stale epoch.
  ('conv-reset', 'link-tg', '9002', 3, '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z');

-- Insertion order below is deliberately NOT the chronological order.
insert into public.agent_conversation_turns
  (id, conversation_id, direction, text, language, created_at, turn_index,
   context_epoch)
values
  -- conv-app, epoch 1: the SECOND exchange is inserted first.
  ('turn-app-e1-in-2',  'conv-app', 'inbound',  'second ask',  'en', '2026-08-10T09:05:00Z', 2, 1),
  ('turn-app-e1-out-2', 'conv-app', 'outbound', 'second reply','en', '2026-08-10T09:05:01Z', 2, 1),
  ('turn-app-e1-in-1',  'conv-app', 'inbound',  'first ask',   'en', '2026-08-10T09:00:00Z', 1, 1),
  ('turn-app-e1-out-1', 'conv-app', 'outbound', 'first reply', 'en', '2026-08-10T09:00:01Z', 1, 1),
  -- conv-app, epoch 2 (the CURRENT epoch). e2-in-1 predates every epoch-1 row
  -- in wall clock; epoch must still dominate the ordering.
  ('turn-app-e2-in-1',  'conv-app', 'inbound',  'epoch2 ask',  'en', '2026-08-09T00:00:00Z', 1, 2),
  ('turn-app-e2-out-1', 'conv-app', 'outbound', 'epoch2 reply','en', '2026-08-11T08:00:01Z', 1, 2),
  -- These two share a created_at; the id tiebreak orders in-2 before out-2.
  ('turn-app-e2-in-2',  'conv-app', 'inbound',  'epoch2 ask 2','en', '2026-08-11T08:01:00Z', 2, 2),
  ('turn-app-e2-out-2', 'conv-app', 'outbound', 'epoch2 rep 2','en', '2026-08-11T08:01:00Z', 2, 2),
  -- conv-tg, epoch 1, again inserted out of order.
  ('turn-tg-in-2',  'conv-tg', 'inbound',  'tg ask 2',   'ar', '2026-08-12T10:01:00Z', 2, 1),
  ('turn-tg-out-2', 'conv-tg', 'outbound', 'tg reply 2', 'ar', '2026-08-12T10:01:05Z', 2, 1),
  ('turn-tg-in-1',  'conv-tg', 'inbound',  'tg ask 1',   'ar', '2026-08-12T10:00:00Z', 1, 1),
  ('turn-tg-out-1', 'conv-tg', 'outbound', 'tg reply 1', 'ar', '2026-08-12T10:00:05Z', 1, 1),
  -- conv-reset: turns only in the STALE epoch 1, none in the current epoch 3.
  ('turn-reset-in-1',  'conv-reset', 'inbound',  'stale ask',  'en', '2026-08-05T07:00:00Z', 1, 1),
  ('turn-reset-out-1', 'conv-reset', 'outbound', 'stale reply','en', '2026-08-05T07:00:01Z', 1, 1),
  ('turn-reset-in-2',  'conv-reset', 'inbound',  'stale ask 2','en', '2026-08-05T07:02:00Z', 2, 1),
  ('turn-reset-out-2', 'conv-reset', 'outbound', 'stale rep 2','en', '2026-08-05T07:02:01Z', 2, 1);

insert into public.agent_tool_events
  (id, conversation_turn_id, tool_call_id, tool_name, arguments_json, result_json,
   status, created_at, tool_sequence)
values
  ('ev-legacy-1', 'turn-app-e1-in-1', 'call_legacy_a', 'get_flock_status',
   '{"flock_id":"F-1"}', '{"ok":true}', 'succeeded', '2026-08-10T09:00:00Z', 1),
  ('ev-legacy-2', 'turn-app-e1-in-1', 'call_legacy_b', 'get_customer_summary',
   '{"customer_id":"C-1"}', '{"ok":true}', 'succeeded', '2026-08-10T09:00:00Z', 2),
  ('ev-legacy-3', 'turn-tg-in-2', 'call_legacy_c', 'get_flock_status',
   '{"flock_id":"F-2"}', null, 'requested', '2026-08-12T10:01:00Z', 1);
SQL

# --- 3. NOW apply the Realtime migration over that real data ----------------
"${psql[@]}" -f "${repo_root}/supabase/migrations/${realtime_migration}" >/dev/null

# --- 4. assert the backfills produced the right answers ---------------------
"${psql[@]}" <<'SQL'
do $seq_backfill$
declare
  bad record;
  expected text;
  actual text;
begin
  -- 1. Every legacy turn got a conversation_seq. `set not null` would have
  --    failed the migration, but assert it explicitly so a future relaxation is
  --    caught here rather than in production.
  if exists (select 1 from public.agent_conversation_turns where conversation_seq is null) then
    raise exception 'a legacy turn was left without a conversation_seq';
  end if;

  -- 2. conversation_seq is unique per conversation and contiguous from 1.
  for bad in
    select conversation_id,
           count(*) as n,
           count(distinct conversation_seq) as distinct_n,
           min(conversation_seq) as lo,
           max(conversation_seq) as hi
    from public.agent_conversation_turns
    group by conversation_id
  loop
    if bad.n <> bad.distinct_n then
      raise exception 'conversation % has duplicate conversation_seq values', bad.conversation_id;
    end if;
    if bad.lo <> 1 or bad.hi <> bad.n then
      raise exception 'conversation % is not contiguous from 1: min=%, max=%, count=%',
        bad.conversation_id, bad.lo, bad.hi, bad.n;
    end if;
  end loop;

  -- 3. The order is (context_epoch, created_at, id) — NOT insertion order, NOT
  --    id order, NOT created_at alone. Every one of those would disagree with
  --    the expectation below on this fixture.
  select string_agg(id, ',' order by conversation_seq)
  into actual
  from public.agent_conversation_turns
  where conversation_id = 'conv-app';

  expected := 'turn-app-e1-in-1,turn-app-e1-out-1,turn-app-e1-in-2,turn-app-e1-out-2,'
           || 'turn-app-e2-in-1,turn-app-e2-out-1,turn-app-e2-in-2,turn-app-e2-out-2';
  if actual is distinct from expected then
    raise exception 'conv-app backfill order wrong.
  expected: %
  actual:   %', expected, actual;
  end if;

  select string_agg(id, ',' order by conversation_seq)
  into actual
  from public.agent_conversation_turns
  where conversation_id = 'conv-tg';

  expected := 'turn-tg-in-1,turn-tg-out-1,turn-tg-in-2,turn-tg-out-2';
  if actual is distinct from expected then
    raise exception 'conv-tg backfill order wrong.
  expected: %
  actual:   %', expected, actual;
  end if;

  -- 4. The epoch key dominates wall clock: the epoch-2 turn that is the OLDEST
  --    row in the conversation still sorts after every epoch-1 turn.
  if (select conversation_seq from public.agent_conversation_turns
      where id = 'turn-app-e2-in-1') <> 5 then
    raise exception 'created_at beat context_epoch in the ordering key';
  end if;

  -- 5. The id tiebreak resolved the created_at tie deterministically.
  if (select conversation_seq from public.agent_conversation_turns
      where id = 'turn-app-e2-in-2') >=
     (select conversation_seq from public.agent_conversation_turns
      where id = 'turn-app-e2-out-2') then
    raise exception 'the id tiebreak did not order the created_at tie';
  end if;
end
$seq_backfill$;

do $channel_backfill$
begin
  -- 6. source_channel derives from the CONVERSATION, not the turn.
  if exists (
    select 1 from public.agent_conversation_turns
    where conversation_id = 'conv-app' and source_channel <> 'app_text'
  ) then
    raise exception 'app conversation turns were not classified as app_text';
  end if;

  if exists (
    select 1 from public.agent_conversation_turns
    where conversation_id in ('conv-tg', 'conv-reset') and source_channel <> 'telegram'
  ) then
    raise exception 'telegram conversation turns were not classified as telegram';
  end if;

  -- 7. Every legacy row is finalized.
  if exists (
    select 1 from public.agent_conversation_turns where completion_status <> 'finalized'
  ) then
    raise exception 'a legacy turn was not marked finalized';
  end if;

  -- 8. The new NOT NULLs really landed on the table.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'agent_conversation_turns'
      and column_name in ('conversation_seq', 'source_channel', 'completion_status')
      and is_nullable = 'YES'
  ) then
    raise exception 'a backfilled column is still nullable';
  end if;
end
$channel_backfill$;

do $owner_backfill$
begin
  -- 9. owner_profile_id comes from telegram_staff_links.app_user_id, so only the
  --    app conversation gets one.
  if (select owner_profile_id from public.agent_conversations where id = 'conv-app')
     is distinct from '00000000-0000-0000-0000-0000000000b1'::uuid then
    raise exception 'the app conversation did not inherit its owner profile';
  end if;

  if (select owner_profile_id from public.agent_conversations where id = 'conv-tg')
     is not null then
    raise exception 'a Telegram conversation was given an owner profile';
  end if;
end
$owner_backfill$;

do $allocator_backfill$
declare
  conv record;
  seen_max integer;
  seq_1 integer; idx_1 integer;
  seq_2 integer; idx_2 integer;
  seq_3 integer; idx_3 integer;
begin
  -- 10. next_conversation_seq == max(conversation_seq) + 1 for every seeded
  --     conversation.
  for conv in select id from public.agent_conversations loop
    select coalesce(max(conversation_seq), 0) into seen_max
    from public.agent_conversation_turns where conversation_id = conv.id;

    if (select next_conversation_seq from public.agent_conversations where id = conv.id)
       <> seen_max + 1 then
      raise exception 'next_conversation_seq for % is not max(seq)+1 (max=%)',
        conv.id, seen_max;
    end if;
  end loop;

  -- 11. The turn_index counters track the CURRENT epoch only. conv-app is on
  --     epoch 2, whose max index is 2 in both directions.
  if not exists (
    select 1 from public.agent_conversations
    where id = 'conv-app'
      and turn_index_epoch = 2
      and next_inbound_turn_index = 3
      and next_outbound_turn_index = 3
  ) then
    raise exception 'conv-app turn_index counters were not seeded from epoch 2: %',
      (select format('epoch=%s in=%s out=%s', turn_index_epoch,
                     next_inbound_turn_index, next_outbound_turn_index)
       from public.agent_conversations where id = 'conv-app');
  end if;

  -- conv-reset is on epoch 3 with turns only in the stale epoch 1, so the
  -- seeding must skip it entirely rather than carry epoch 1's maxima (2, 2)
  -- forward. Whether it is left at the default epoch or stamped with epoch 3,
  -- both counters must read 1.
  if exists (
    select 1 from public.agent_conversations
    where id = 'conv-reset'
      and (next_inbound_turn_index <> 1 or next_outbound_turn_index <> 1)
  ) then
    raise exception 'conv-reset leaked stale-epoch turn indexes: in=%, out=%',
      (select next_inbound_turn_index from public.agent_conversations where id = 'conv-reset'),
      (select next_outbound_turn_index from public.agent_conversations where id = 'conv-reset');
  end if;

  -- 12. A fresh allocation after the migration must not collide with any
  --     pre-existing row. This is the assertion that actually protects
  --     production: the unique index (conversation_id, context_epoch, direction,
  --     turn_index) would reject a collision on INSERT.
  select conversation_seq, turn_index into seq_1, idx_1
  from public.allocate_agent_turn_slot('conv-app', 2, 'inbound');
  select conversation_seq, turn_index into seq_2, idx_2
  from public.allocate_agent_turn_slot('conv-app', 2, 'outbound', idx_1);

  if seq_1 <> 9 or seq_2 <> 10 then
    raise exception 'post-backfill conversation_seq must continue 9,10; got %,%',
      seq_1, seq_2;
  end if;
  if idx_1 <> 3 or idx_2 <> 3 then
    raise exception 'post-backfill turn_index must continue at 3 (reused outbound); got %,%',
      idx_1, idx_2;
  end if;

  -- Prove it by actually inserting: the unique indexes are the real judge.
  insert into public.agent_conversation_turns
    (id, conversation_id, direction, text, language, created_at, turn_index,
     context_epoch, conversation_seq, source_channel, completion_status)
  values
    ('turn-app-e2-in-3', 'conv-app', 'inbound', 'after migration', 'en',
     '2026-08-16T12:00:00Z', idx_1, 2, seq_1, 'app_text', 'finalized'),
    ('turn-app-e2-out-3', 'conv-app', 'outbound', 'after migration reply', 'en',
     '2026-08-16T12:00:01Z', idx_2, 2, seq_2, 'app_text', 'finalized');

  -- 13. The Telegram conversation allocates on top of its own legacy rows.
  select conversation_seq, turn_index into seq_3, idx_3
  from public.allocate_agent_turn_slot('conv-tg', 1, 'inbound');
  if seq_3 <> 5 or idx_3 <> 3 then
    raise exception 'conv-tg allocation must continue 5/3; got %/%', seq_3, idx_3;
  end if;

  insert into public.agent_conversation_turns
    (id, conversation_id, direction, text, language, created_at, turn_index,
     context_epoch, conversation_seq, source_channel, completion_status)
  values
    ('turn-tg-in-3', 'conv-tg', 'inbound', 'after migration', 'ar',
     '2026-08-16T12:00:02Z', idx_3, 1, seq_3, 'telegram', 'finalized');

  -- 14. conv-reset advancing into its current epoch 3 starts turn_index at 1
  --     without colliding with the stale epoch-1 rows.
  select conversation_seq, turn_index into seq_3, idx_3
  from public.allocate_agent_turn_slot('conv-reset', 3, 'inbound');
  if seq_3 <> 5 or idx_3 <> 1 then
    raise exception 'conv-reset epoch-3 allocation must be 5/1; got %/%', seq_3, idx_3;
  end if;

  insert into public.agent_conversation_turns
    (id, conversation_id, direction, text, language, created_at, turn_index,
     context_epoch, conversation_seq, source_channel, completion_status)
  values
    ('turn-reset-in-3', 'conv-reset', 'inbound', 'new epoch', 'en',
     '2026-08-16T12:00:03Z', idx_3, 3, seq_3, 'telegram', 'finalized');
end
$allocator_backfill$;

do $evidence_survives$
begin
  -- 15. Pre-existing tool evidence survived the nullability change, the
  --      constraint-to-partial-index conversion and the new attribution check.
  if (select count(*) from public.agent_tool_events) <> 3 then
    raise exception 'legacy tool events did not survive the migration';
  end if;

  if exists (select 1 from public.agent_tool_events where conversation_turn_id is null) then
    raise exception 'a legacy tool event lost its turn link';
  end if;

  -- 16. The turn/call uniqueness survived the conversion to a partial index.
  begin
    insert into public.agent_tool_events
      (id, conversation_turn_id, tool_call_id, tool_name, arguments_json, status,
       created_at, tool_sequence)
    values
      ('ev-legacy-dupe', 'turn-app-e1-in-1', 'call_legacy_a', 'get_flock_status',
       '{}', 'succeeded', '2026-08-16T12:01:00Z', 9);
    raise exception 'a duplicate (turn, tool_call_id) was accepted after the migration';
  exception when unique_violation then
    null;
  end;

  -- 17. Evidence is still immutable.
  begin
    update public.agent_tool_events set status = 'failed' where id = 'ev-legacy-1';
    raise exception 'legacy tool evidence became mutable';
  exception when raise_exception then
    if sqlerrm <> 'Tool-call evidence is immutable' then
      raise exception 'unexpected immutability error: %', sqlerrm;
    end if;
  end;

  begin
    delete from public.agent_tool_events where id = 'ev-legacy-1';
    raise exception 'legacy tool evidence was deletable';
  exception when raise_exception then
    if sqlerrm <> 'Tool-call evidence is immutable' then
      raise exception 'unexpected immutability error: %', sqlerrm;
    end if;
  end;
end
$evidence_survives$;

do $post_state$
declare
  bad record;
begin
  -- 18. After the migration AND a round of fresh allocations, the whole table
  --      still satisfies the invariants end to end.
  for bad in
    select conversation_id, count(*) as n, count(distinct conversation_seq) as distinct_n,
           min(conversation_seq) as lo, max(conversation_seq) as hi
    from public.agent_conversation_turns
    group by conversation_id
  loop
    if bad.n <> bad.distinct_n or bad.lo <> 1 or bad.hi <> bad.n then
      raise exception 'conversation % broke contiguity after fresh allocation', bad.conversation_id;
    end if;
  end loop;
end
$post_state$;
SQL

echo "Pip Realtime V1 backfill integration checks passed."
