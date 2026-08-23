#!/usr/bin/env bash
# Replays every migration into a throwaway PostgreSQL and exercises the Pip
# Realtime V1 persistence layer for real: the atomic turn allocator, evidence
# that has no durable turn yet, the two claim key shapes, and the Realtime
# operational invariants.
#
# This is behavioural, not textual — it catches a migration that parses but does
# not enforce what the plan says it enforces.
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

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/chickmark-realtime.XXXXXX")"
data_dir="${tmp_dir}/data"
socket_dir="${tmp_dir}/socket"
port=$((39152 + ($$ % 10000)))
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

# --- fixtures ---------------------------------------------------------------
"${psql[@]}" >/dev/null <<'SQL'
insert into auth.users (id, email, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000000000a1', 'realtime@example.test',
        '{"full_name":"Realtime test"}');

update public.profiles
set role = 'admin', status = 'approved'
where id = '00000000-0000-0000-0000-0000000000a1';

insert into public.telegram_staff_links
  (id, channel, app_user_id, status, access_role, customer_id, created_at, updated_at)
values
  ('app-a1', 'app', '00000000-0000-0000-0000-0000000000a1', 'allowed', 'admin',
   null, '2026-08-16T00:00:00Z', '2026-08-16T00:00:00Z');

insert into public.agent_conversations
  (id, staff_link_id, telegram_chat_id, created_at, updated_at)
values
  ('conv-1', 'app-a1', 'app', '2026-08-16T00:00:00Z', '2026-08-16T00:00:00Z');
SQL

# --- assertions -------------------------------------------------------------
"${psql[@]}" <<'SQL'
do $realtime_test$
declare
  seq_a integer; idx_a integer;
  seq_b integer; idx_b integer;
  seq_c integer; idx_c integer;
  seq_d integer; idx_d integer;
  next_seq integer;
begin
  -- 1. Allocator: conversation_seq is monotonic across BOTH directions, while
  --    turn_index stays per (epoch, direction).
  select conversation_seq, turn_index into seq_a, idx_a
  from chickmark_private.allocate_agent_turn_slot('conv-1', 1, 'inbound');
  select conversation_seq, turn_index into seq_b, idx_b
  from chickmark_private.allocate_agent_turn_slot('conv-1', 1, 'outbound', idx_a);

  if seq_a <> 1 or seq_b <> 2 then
    raise exception 'conversation_seq must run 1,2 across directions; got %,%',
      seq_a, seq_b;
  end if;
  if idx_a <> 1 or idx_b <> 1 then
    raise exception 'outbound must reuse the inbound turn_index; got %,%',
      idx_a, idx_b;
  end if;

  insert into public.agent_conversation_turns
    (id, conversation_id, direction, text, language, created_at,
     turn_index, context_epoch, conversation_seq, source_channel, completion_status)
  values
    ('turn-in-1', 'conv-1', 'inbound', 'hello', 'en', '2026-08-16T00:00:01Z',
     idx_a, 1, seq_a, 'app_text', 'finalized'),
    ('turn-out-1', 'conv-1', 'outbound', 'hi', 'en', '2026-08-16T00:00:02Z',
     idx_b, 1, seq_b, 'app_text', 'finalized');

  -- 2. Realtime allocates outbound indexes INDEPENDENTLY. Two assistant turns
  --    for one user turn (barge-in) must not collide on the unique index
  --    (conversation_id, context_epoch, direction, turn_index).
  select conversation_seq, turn_index into seq_c, idx_c
  from chickmark_private.allocate_agent_turn_slot('conv-1', 1, 'outbound');
  select conversation_seq, turn_index into seq_d, idx_d
  from chickmark_private.allocate_agent_turn_slot('conv-1', 1, 'outbound');

  if idx_c <> 2 or idx_d <> 3 then
    raise exception 'independent outbound allocation must yield 2,3; got %,%',
      idx_c, idx_d;
  end if;

  insert into public.agent_conversation_turns
    (id, conversation_id, direction, text, language, created_at,
     turn_index, context_epoch, conversation_seq, source_channel,
     completion_status, realtime_session_id, realtime_generation, provider_item_id)
  values
    ('turn-out-2', 'conv-1', 'outbound', 'partial', 'en', '2026-08-16T00:00:03Z',
     idx_c, 1, seq_c, 'realtime_voice', 'interrupted', 'sess-1', 1, 'item_out_a'),
    ('turn-out-3', 'conv-1', 'outbound', 'resumed', 'en', '2026-08-16T00:00:04Z',
     idx_d, 1, seq_d, 'realtime_voice', 'finalized', 'sess-1', 1, 'item_out_b');

  -- 3. The allocator actually advanced the stored counter.
  select next_conversation_seq into next_seq
  from public.agent_conversations where id = 'conv-1';
  if next_seq <> 5 then
    raise exception 'next_conversation_seq must be 5 after 4 allocations, got %',
      next_seq;
  end if;

  -- 4. conversation_seq is unique per conversation.
  begin
    insert into public.agent_conversation_turns
      (id, conversation_id, direction, text, language, created_at,
       turn_index, context_epoch, conversation_seq, source_channel, completion_status)
    values
      ('turn-dupe', 'conv-1', 'inbound', 'dupe', 'en', '2026-08-16T00:00:05Z',
       99, 1, 1, 'app_text', 'finalized');
    raise exception 'duplicate conversation_seq was accepted';
  exception when unique_violation then
    null;
  end;

  -- 5. A provider item cannot yield two durable turns in the same direction.
  begin
    insert into public.agent_conversation_turns
      (id, conversation_id, direction, text, language, created_at,
       turn_index, context_epoch, conversation_seq, source_channel,
       completion_status, realtime_session_id, realtime_generation, provider_item_id)
    values
      ('turn-out-dupe', 'conv-1', 'outbound', 'again', 'en', '2026-08-16T00:00:06Z',
       50, 1, 50, 'realtime_voice', 'finalized', 'sess-1', 1, 'item_out_a');
    raise exception 'duplicate provider item created a second turn';
  exception when unique_violation then
    null;
  end;
end
$realtime_test$;

do $evidence_test$
begin
  -- 6. Realtime evidence with NO durable turn is accepted.
  insert into public.agent_tool_events
    (id, conversation_turn_id, tool_call_id, tool_name, arguments_json, status,
     created_at, tool_sequence, realtime_session_id, realtime_generation,
     realtime_interaction_id, argument_hash, source_channel)
  values
    ('ev-rt-1', null, 'call_abc', 'get_flock_status', '{"flock_id":"F-123"}',
     'succeeded', '2026-08-16T00:00:07Z', 1, 'sess-1', 1, 'item:item_in_a',
     'hash-1', 'realtime_voice');

  -- 7. Evidence attributable to NOTHING is rejected.
  begin
    insert into public.agent_tool_events
      (id, conversation_turn_id, tool_call_id, tool_name, arguments_json, status,
       created_at, tool_sequence)
    values
      ('ev-orphan', null, 'call_orphan', 'get_flock_status', '{}', 'succeeded',
       '2026-08-16T00:00:08Z', 1);
    raise exception 'orphan tool evidence was accepted';
  exception when check_violation then
    null;
  end;

  -- 8. Evidence is still immutable — the claim ledger, not the evidence row,
  --    carries the late turn link.
  begin
    update public.agent_tool_events
    set argument_hash = 'tampered'
    where id = 'ev-rt-1';
    raise exception 'tool evidence was mutable';
  exception when raise_exception then
    if sqlerrm <> 'Tool-call evidence is immutable' then
      raise exception 'unexpected immutability error: %', sqlerrm;
    end if;
  end;

  -- 9. A Realtime claim needs no inbound turn, and the link back-fills later.
  insert into public.agent_tool_call_claims
    (id, realtime_session_id, realtime_generation, realtime_interaction_id,
     openai_tool_call_id, tool_name, argument_hash, state, tool_event_id)
  values
    ('claim-rt-1', 'sess-1', 1, 'item:item_in_a', 'call_abc',
     'get_flock_status', 'hash-1', 'succeeded', 'ev-rt-1');

  update public.agent_tool_call_claims
  set inbound_turn_id = 'turn-in-1'
  where id = 'claim-rt-1';

  if not exists (
    select 1 from public.agent_tool_call_claims
    where id = 'claim-rt-1' and inbound_turn_id = 'turn-in-1'
  ) then
    raise exception 'claim turn link did not back-fill';
  end if;

  -- 10. The same tool call cannot be claimed twice in one generation.
  begin
    insert into public.agent_tool_call_claims
      (id, realtime_session_id, realtime_generation, openai_tool_call_id,
       tool_name, argument_hash, state)
    values
      ('claim-rt-dupe', 'sess-1', 1, 'call_abc', 'get_flock_status',
       'hash-1', 'claimed');
    raise exception 'duplicate realtime claim was accepted';
  exception when unique_violation then
    null;
  end;

  -- 11. A claim keyed to neither shape is rejected.
  begin
    insert into public.agent_tool_call_claims
      (id, openai_tool_call_id, tool_name, argument_hash, state)
    values ('claim-shapeless', 'call_x', 'get_flock_status', 'h', 'claimed');
    raise exception 'claim with no key shape was accepted';
  exception when check_violation then
    null;
  end;
end
$evidence_test$;

do $realtime_ops_test$
begin
  insert into public.agent_realtime_sessions
    (id, conversation_id, context_epoch, authorization_fingerprint,
     owner_profile_id, active_generation, state)
  values
    ('sess-1', 'conv-1', 1, 'fp-1', '00000000-0000-0000-0000-0000000000a1',
     1, 'active');

  -- 12. One non-terminal session per profile, setup states included.
  begin
    insert into public.agent_realtime_sessions
      (id, conversation_id, context_epoch, authorization_fingerprint,
       owner_profile_id, active_generation, state)
    values
      ('sess-2', 'conv-1', 1, 'fp-1', '00000000-0000-0000-0000-0000000000a1',
       1, 'provisioning');
    raise exception 'a second non-terminal session was accepted';
  exception when unique_violation then
    null;
  end;

  -- A terminal session does not block a replacement.
  update public.agent_realtime_sessions set state = 'ended' where id = 'sess-1';
  insert into public.agent_realtime_sessions
    (id, conversation_id, context_epoch, authorization_fingerprint,
     owner_profile_id, active_generation, state)
  values
    ('sess-2', 'conv-1', 1, 'fp-1', '00000000-0000-0000-0000-0000000000a1',
     1, 'provisioning');

  -- 13. `active` is not reachable by accident: the setup state machine and the
  --     fencing token both start where the plan says they do.
  insert into public.agent_realtime_calls
    (id, session_id, generation, setup_state, authorization_fingerprint,
     setup_deadline_at)
  values
    ('call-1', 'sess-2', 1, 'provisioning', 'fp-1', now() + interval '60 seconds');

  if exists (
    select 1 from public.agent_realtime_calls
    where id = 'call-1' and (fencing_token <> 0 or webrtc_healthy or sideband_healthy)
  ) then
    raise exception 'a freshly provisioned generation was not fully un-ready';
  end if;

  -- 14. One generation number per session.
  begin
    insert into public.agent_realtime_calls
      (id, session_id, generation, setup_state, authorization_fingerprint,
       setup_deadline_at)
    values
      ('call-dupe', 'sess-2', 1, 'provisioning', 'fp-1', now());
    raise exception 'duplicate generation was accepted';
  exception when unique_violation then
    null;
  end;

  -- 15. Usage settles at most once per (session, UTC day), and a session that
  --     crosses midnight settles as two slices.
  insert into public.agent_realtime_usage_seconds
    (session_id, usage_date, owner_profile_id, seconds)
  values
    ('sess-2', date '2026-08-16', '00000000-0000-0000-0000-0000000000a1', 120),
    ('sess-2', date '2026-08-17', '00000000-0000-0000-0000-0000000000a1', 45);

  begin
    insert into public.agent_realtime_usage_seconds
      (session_id, usage_date, owner_profile_id, seconds)
    values
      ('sess-2', date '2026-08-16', '00000000-0000-0000-0000-0000000000a1', 999);
    raise exception 'usage was settled twice for one day';
  exception when unique_violation then
    null;
  end;

  if (select sum(seconds) from public.agent_realtime_usage_seconds
      where session_id = 'sess-2') <> 165 then
    raise exception 'midnight-split slices do not sum to the session total';
  end if;

  -- 16. The kill switch exists and defaults to enabled.
  if not exists (
    select 1 from public.agent_realtime_runtime_control
    where id = 1 and enabled
  ) then
    raise exception 'runtime control row missing or disabled by default';
  end if;
end
$realtime_ops_test$;

do $memory_test$
begin
  -- 17. A customer-scoped memory must name its customer; a global one must not.
  begin
    insert into public.agent_memories
      (id, owner_staff_link_id, scope_kind, category, memory_text)
    values ('mem-bad', 'app-a1', 'owner_customer', 'preference', 'x');
    raise exception 'customer-scoped memory without a customer was accepted';
  exception when check_violation then
    null;
  end;

  insert into public.agent_memories
    (id, owner_staff_link_id, scope_kind, category, memory_text)
  values ('mem-1', 'app-a1', 'owner_global', 'preference', 'prefers Celsius');
end
$memory_test$;

do $summary_test$
begin
  -- 18. A summary covers a real range and is versioned per epoch.
  insert into public.agent_conversation_summaries
    (id, conversation_id, context_epoch, authorization_fingerprint, version,
     first_conversation_seq, last_conversation_seq, summary_text, source_turn_count)
  values
    ('sum-1', 'conv-1', 1, 'fp-1', 1, 1, 4, 'summary', 4);

  begin
    insert into public.agent_conversation_summaries
      (id, conversation_id, context_epoch, authorization_fingerprint, version,
       first_conversation_seq, last_conversation_seq, summary_text, source_turn_count)
    values
      ('sum-bad', 'conv-1', 1, 'fp-1', 2, 9, 4, 'backwards', 1);
    raise exception 'a summary with an inverted range was accepted';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.agent_conversation_summaries
      (id, conversation_id, context_epoch, authorization_fingerprint, version,
       first_conversation_seq, last_conversation_seq, summary_text, source_turn_count)
    values
      ('sum-dupe', 'conv-1', 1, 'fp-1', 1, 1, 4, 'dupe', 4);
    raise exception 'duplicate summary version was accepted';
  exception when unique_violation then
    null;
  end;
end
$summary_test$;
SQL

echo "Pip Realtime V1 persistence integration checks passed."
