-- 20260816120000 pip_realtime_v1_persistence
--
-- Checkpoint 2 of the Pip Realtime V1 plan: the shared persistence layer for
-- typed Pip, Telegram and Realtime voice.
--
-- Design constraints this migration deliberately respects, all verified against
-- production during Preflight:
--
--   * `agent_conversation_turns.turn_index` semantics are UNCHANGED. It stays a
--     per-(conversation, context_epoch, direction) sequence guarded by
--     `agent_conversation_turns_order_check` and
--     `idx_agent_conversation_turns_order` (20260730111832). Text and Telegram
--     keep copying the inbound index onto the outbound reply; Realtime
--     allocates outbound indexes independently, because barge-in breaks the 1:1
--     pairing and would otherwise violate that unique index.
--
--   * `conversation_seq` is NEW and is the chronological ordering key across all
--     durable turns of a conversation, both directions. It is monotonic for the
--     life of the conversation and does NOT reset per context_epoch: turn_index
--     already carries the epoch-scoped meaning, and a never-resetting key gives
--     one stable order for audit, transcript rendering and summary coverage.
--
--   * `agent_tool_events` rows are immutable (trigger
--     `agent_tool_events_immutable` raises on UPDATE and DELETE), so a Realtime
--     tool call that fires before its transcript finalizes can never have its
--     turn link back-filled onto the evidence row. The link therefore lives on
--     the MUTABLE claim ledger instead, and `conversation_turn_id` becomes
--     nullable. No placeholder turn is ever fabricated to satisfy a foreign key.
--
--   * Timestamps: existing shared tables keep their `text` convention. Every new
--     server-only operational table uses `timestamptz` with server time, because
--     lease expiry, setup deadlines and UTC-day usage splitting need real time
--     arithmetic.
--
--   * The new server-only tables are never registered in the Flutter sync layer
--     (lib/data/repositories/performance_sync_repository.dart), so they never
--     reach SQLite.

begin;

-- ---------------------------------------------------------------------------
-- 1. agent_conversations: ownership, allocator state, summary pointer
-- ---------------------------------------------------------------------------

alter table public.agent_conversations
  add column if not exists owner_profile_id uuid
    references public.profiles(id) on delete set null,
  add column if not exists next_conversation_seq integer not null default 1,
  -- turn_index is scoped per (context_epoch, direction), so its counters carry
  -- the epoch they belong to and reset when the epoch advances.
  add column if not exists turn_index_epoch integer not null default 1,
  add column if not exists next_inbound_turn_index integer not null default 1,
  add column if not exists next_outbound_turn_index integer not null default 1,
  add column if not exists last_activity_at text,
  add column if not exists current_summary_id text,
  add column if not exists authorization_fingerprint text;

-- App conversations hang off a staff link whose app_user_id IS the profile id.
update public.agent_conversations conversation
set owner_profile_id = link.app_user_id
from public.telegram_staff_links link
where conversation.staff_link_id = link.id
  and link.app_user_id is not null
  and conversation.owner_profile_id is null;

alter table public.agent_conversations
  drop constraint if exists agent_conversations_next_seq_check,
  add constraint agent_conversations_next_seq_check
    check (next_conversation_seq >= 1);

create index if not exists idx_agent_conversations_owner_activity
  on public.agent_conversations(owner_profile_id, last_activity_at)
  where owner_profile_id is not null;

-- ---------------------------------------------------------------------------
-- 2. agent_conversation_turns: chronological ordering + channel/completion
-- ---------------------------------------------------------------------------

alter table public.agent_conversation_turns
  add column if not exists conversation_seq integer,
  add column if not exists source_channel text,
  add column if not exists completion_status text,
  add column if not exists realtime_session_id text,
  add column if not exists realtime_generation integer,
  add column if not exists provider_item_id text,
  add column if not exists finalized_at text,
  add column if not exists interrupted_at text,
  add column if not exists authorization_fingerprint text,
  add column if not exists customer_id text
    references public.customers(id) on delete set null;

-- Deterministic backfill: epoch, then wall clock, then id as the tiebreak.
with ordered as (
  select
    id,
    row_number() over (
      partition by conversation_id
      order by context_epoch, created_at, id
    ) as seq
  from public.agent_conversation_turns
)
update public.agent_conversation_turns turn
set conversation_seq = ordered.seq
from ordered
where turn.id = ordered.id
  and turn.conversation_seq is null;

-- Existing rows predate the channel split. Telegram rows carry a chat id that is
-- not the app sentinel; app rows carry 'app' (app_agent_scope.ts:207).
update public.agent_conversation_turns turn
set source_channel = case
      when conversation.telegram_chat_id = 'app' then 'app_text'
      else 'telegram'
    end
from public.agent_conversations conversation
where turn.conversation_id = conversation.id
  and turn.source_channel is null;

update public.agent_conversation_turns
set completion_status = 'finalized'
where completion_status is null;

alter table public.agent_conversation_turns
  alter column conversation_seq set not null,
  alter column source_channel set not null,
  alter column completion_status set not null;

alter table public.agent_conversation_turns
  drop constraint if exists agent_conversation_turns_seq_check,
  add constraint agent_conversation_turns_seq_check
    check (conversation_seq >= 1),
  drop constraint if exists agent_conversation_turns_source_channel_check,
  add constraint agent_conversation_turns_source_channel_check
    check (source_channel in ('app_text', 'realtime_voice', 'telegram', 'system')),
  drop constraint if exists agent_conversation_turns_completion_check,
  add constraint agent_conversation_turns_completion_check
    check (completion_status in (
      'pending', 'finalized', 'interrupted', 'unavailable', 'failed'
    ));

create unique index if not exists idx_agent_conversation_turns_seq
  on public.agent_conversation_turns(conversation_id, conversation_seq);

-- A provider item never yields two durable turns in the same direction, however
-- many times its events are redelivered.
create unique index if not exists idx_agent_conversation_turns_provider_item
  on public.agent_conversation_turns(realtime_generation, provider_item_id, direction)
  where provider_item_id is not null;

create index if not exists idx_agent_conversation_turns_realtime
  on public.agent_conversation_turns(realtime_session_id, realtime_generation)
  where realtime_session_id is not null;

-- Seed the allocators from the rows that already exist. turn_index counters are
-- seeded only from the conversation's CURRENT epoch, which is what they track.
update public.agent_conversations conversation
set next_conversation_seq = coalesce(seen.max_seq, 0) + 1
from (
  select conversation_id, max(conversation_seq) as max_seq
  from public.agent_conversation_turns
  group by conversation_id
) seen
where conversation.id = seen.conversation_id;

update public.agent_conversations conversation
set turn_index_epoch = conversation.context_epoch,
    next_inbound_turn_index = coalesce(seen.max_inbound, 0) + 1,
    next_outbound_turn_index = coalesce(seen.max_outbound, 0) + 1
from (
  select
    turn.conversation_id,
    turn.context_epoch,
    max(turn.turn_index) filter (where turn.direction = 'inbound') as max_inbound,
    max(turn.turn_index) filter (where turn.direction = 'outbound') as max_outbound
  from public.agent_conversation_turns turn
  group by turn.conversation_id, turn.context_epoch
) seen
where conversation.id = seen.conversation_id
  and conversation.context_epoch = seen.context_epoch;

-- ---------------------------------------------------------------------------
-- 3. Atomic turn-slot allocator
--
-- Replaces the client-side "max over the newest 40 rows" scans in
-- app-hatchery-agent/index.ts:434-444 and
-- telegram-hatchery-agent/index.ts:529-534. Locks the conversation row so two
-- concurrent turns can never collide on either sequence.
--
-- p_turn_index_override preserves the existing convention where an outbound
-- reply reuses its inbound turn_index. Realtime passes NULL to allocate an
-- independent outbound index.
-- ---------------------------------------------------------------------------

create or replace function chickmark_private.allocate_agent_turn_slot(
  p_conversation_id text,
  p_context_epoch integer,
  p_direction text,
  p_turn_index_override integer default null
)
returns table (conversation_seq integer, turn_index integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_seq integer;
  v_turn_index integer;
  v_counter_epoch integer;
  v_next_inbound integer;
  v_next_outbound integer;
begin
  if p_direction not in ('inbound', 'outbound') then
    raise exception 'direction must be inbound or outbound, got %', p_direction;
  end if;
  if p_context_epoch is null or p_context_epoch < 1 then
    raise exception 'context_epoch must be >= 1, got %', p_context_epoch;
  end if;

  -- Serialises every allocation for this conversation.
  select c.next_conversation_seq, c.turn_index_epoch,
         c.next_inbound_turn_index, c.next_outbound_turn_index
  into v_seq, v_counter_epoch, v_next_inbound, v_next_outbound
  from public.agent_conversations c
  where c.id = p_conversation_id
  for update;

  if v_seq is null then
    raise exception 'unknown conversation %', p_conversation_id;
  end if;

  -- turn_index restarts at 1 in a new epoch (a /new reset).
  if v_counter_epoch <> p_context_epoch then
    v_counter_epoch := p_context_epoch;
    v_next_inbound := 1;
    v_next_outbound := 1;
  end if;

  if p_turn_index_override is not null then
    -- The text and Telegram convention: an outbound reply reuses its inbound
    -- index. The counter still advances past it so a later independent
    -- allocation in the same epoch cannot collide with this row.
    if p_turn_index_override < 1 then
      raise exception 'turn_index override must be >= 1, got %',
        p_turn_index_override;
    end if;
    v_turn_index := p_turn_index_override;
    if p_direction = 'inbound' then
      v_next_inbound := greatest(v_next_inbound, v_turn_index + 1);
    else
      v_next_outbound := greatest(v_next_outbound, v_turn_index + 1);
    end if;
  elsif p_direction = 'inbound' then
    v_turn_index := v_next_inbound;
    v_next_inbound := v_next_inbound + 1;
  else
    v_turn_index := v_next_outbound;
    v_next_outbound := v_next_outbound + 1;
  end if;

  -- Counters are authoritative, never re-derived from MAX(): two allocations
  -- taken before either row is inserted must still get distinct indexes.
  update public.agent_conversations
  set next_conversation_seq = v_seq + 1,
      turn_index_epoch = v_counter_epoch,
      next_inbound_turn_index = v_next_inbound,
      next_outbound_turn_index = v_next_outbound
  where id = p_conversation_id;

  conversation_seq := v_seq;
  turn_index := v_turn_index;
  return next;
end;
$$;

revoke all on function chickmark_private.allocate_agent_turn_slot(
  text, integer, text, integer
) from public, anon, authenticated;
grant execute on function chickmark_private.allocate_agent_turn_slot(
  text, integer, text, integer
) to service_role;

-- PostgREST only exposes `public` (and `graphql_public`) on this project, so a
-- `chickmark_private` function is not reachable over the REST API — the Edge
-- Functions would get a 404. Rather than exposing the private schema, publish a
-- thin `public` wrapper and lock it to service_role. SECURITY DEFINER so the
-- caller needs no rights on chickmark_private itself.
create or replace function public.allocate_agent_turn_slot(
  p_conversation_id text,
  p_context_epoch integer,
  p_direction text,
  p_turn_index_override integer default null
)
returns table (conversation_seq integer, turn_index integer)
language sql
security definer
set search_path = ''
as $$
  select *
  from chickmark_private.allocate_agent_turn_slot(
    p_conversation_id, p_context_epoch, p_direction, p_turn_index_override
  );
$$;

revoke all on function public.allocate_agent_turn_slot(
  text, integer, text, integer
) from public, anon, authenticated;
grant execute on function public.allocate_agent_turn_slot(
  text, integer, text, integer
) to service_role;

-- Every component that reasons about a Realtime deadline must share one clock.
-- The setup deadline is written by an Edge Function, evaluated by the Cloud Run
-- sideband, and swept by SQL comparing against now(). If each used its own host
-- clock, skew would silently move the deadline. This is the single source.
create or replace function public.realtime_now()
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select now();
$$;

revoke all on function public.realtime_now() from public, anon, authenticated;
grant execute on function public.realtime_now() to service_role;

-- ---------------------------------------------------------------------------
-- 4. agent_tool_events: allow evidence that has no durable turn yet
--
-- The table-level UNIQUE constraint becomes a partial unique index, exactly the
-- conversion 20260813222045_app_agent_chat_door.sql performed on
-- telegram_staff_links.telegram_user_id. The immutability trigger is untouched.
-- ---------------------------------------------------------------------------

alter table public.agent_tool_events
  alter column conversation_turn_id drop not null;

alter table public.agent_tool_events
  drop constraint if exists agent_tool_events_conversation_turn_id_tool_call_id_key;

create unique index if not exists idx_agent_tool_events_turn_call
  on public.agent_tool_events(conversation_turn_id, tool_call_id)
  where conversation_turn_id is not null;

alter table public.agent_tool_events
  add column if not exists realtime_session_id text,
  add column if not exists realtime_generation integer,
  add column if not exists realtime_interaction_id text,
  add column if not exists argument_hash text,
  add column if not exists source_channel text,
  add column if not exists confirmation_state text,
  add column if not exists started_at text,
  add column if not exists completed_at text;

create unique index if not exists idx_agent_tool_events_realtime_call
  on public.agent_tool_events(realtime_session_id, realtime_generation, tool_call_id)
  where realtime_session_id is not null;

create unique index if not exists idx_agent_tool_events_realtime_sequence
  on public.agent_tool_events(realtime_session_id, realtime_generation, tool_sequence)
  where realtime_session_id is not null;

create index if not exists idx_agent_tool_events_interaction
  on public.agent_tool_events(realtime_interaction_id)
  where realtime_interaction_id is not null;

-- Evidence must be attributable to something: a durable turn or a Realtime
-- generation. Never neither.
alter table public.agent_tool_events
  drop constraint if exists agent_tool_events_attribution_check,
  add constraint agent_tool_events_attribution_check
    check (
      conversation_turn_id is not null
      or (realtime_session_id is not null and realtime_generation is not null)
    );

-- ---------------------------------------------------------------------------
-- 5. agent_tool_call_claims: the mutable lease/idempotency ledger
--
-- Two key shapes. Text and Telegram claim by (inbound turn, tool call). Realtime
-- claims by (session, generation, tool call) because the inbound turn may not
-- exist yet, and back-fills inbound_turn_id when the transcript finalizes.
-- ---------------------------------------------------------------------------

create table if not exists public.agent_tool_call_claims (
  id text primary key,
  inbound_turn_id text
    references public.agent_conversation_turns(id) on delete cascade,
  realtime_session_id text,
  realtime_generation integer,
  realtime_interaction_id text,
  openai_tool_call_id text not null,
  tool_name text not null,
  argument_hash text not null,
  state text not null check (
    state in ('claimed', 'succeeded', 'rejected', 'failed', 'indeterminate')
  ),
  lease_owner text,
  lease_expires_at timestamptz,
  tool_event_id text
    references public.agent_tool_events(id) on delete set null,
  claimed_at timestamptz not null default now(),
  settled_at timestamptz,
  constraint agent_tool_call_claims_key_shape_check check (
    inbound_turn_id is not null
    or (realtime_session_id is not null and realtime_generation is not null)
  )
);

create unique index if not exists idx_agent_tool_call_claims_turn_key
  on public.agent_tool_call_claims(inbound_turn_id, openai_tool_call_id)
  where inbound_turn_id is not null;

create unique index if not exists idx_agent_tool_call_claims_realtime_key
  on public.agent_tool_call_claims(
    realtime_session_id, realtime_generation, openai_tool_call_id
  )
  where realtime_session_id is not null;

create index if not exists idx_agent_tool_call_claims_interaction
  on public.agent_tool_call_claims(realtime_interaction_id)
  where realtime_interaction_id is not null;

-- ---------------------------------------------------------------------------
-- 6. agent_conversation_summaries: immutable, versioned
-- ---------------------------------------------------------------------------

create table if not exists public.agent_conversation_summaries (
  id text primary key,
  conversation_id text not null
    references public.agent_conversations(id) on delete cascade,
  context_epoch integer not null check (context_epoch >= 1),
  authorization_fingerprint text not null,
  version integer not null check (version >= 1),
  first_conversation_seq integer not null check (first_conversation_seq >= 1),
  last_conversation_seq integer not null check (last_conversation_seq >= 1),
  summary_text text not null,
  source_turn_count integer not null check (source_turn_count >= 0),
  provider text,
  model text,
  process_version text,
  supersedes_summary_id text
    references public.agent_conversation_summaries(id) on delete set null,
  generated_at timestamptz not null default now(),
  constraint agent_conversation_summaries_range_check
    check (last_conversation_seq >= first_conversation_seq),
  unique (conversation_id, context_epoch, version)
);

create index if not exists idx_agent_conversation_summaries_current
  on public.agent_conversation_summaries(conversation_id, context_epoch, version desc);

-- ---------------------------------------------------------------------------
-- 7. agent_memories: deliberate, owner-private
-- ---------------------------------------------------------------------------

create table if not exists public.agent_memories (
  id text primary key,
  owner_staff_link_id text not null
    references public.telegram_staff_links(id) on delete cascade,
  owner_profile_id uuid
    references public.profiles(id) on delete cascade,
  customer_id text
    references public.customers(id) on delete cascade,
  scope_kind text not null check (scope_kind in ('owner_global', 'owner_customer')),
  category text not null check (category in ('preference', 'workflow', 'domain_fact')),
  memory_text text not null,
  state text not null default 'active'
    check (state in ('active', 'superseded', 'deleted')),
  source_conversation_id text
    references public.agent_conversations(id) on delete set null,
  source_turn_id text
    references public.agent_conversation_turns(id) on delete set null,
  source_tool_event_id text
    references public.agent_tool_events(id) on delete set null,
  supersedes_memory_id text
    references public.agent_memories(id) on delete set null,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint agent_memories_scope_shape_check check (
    (scope_kind = 'owner_customer' and customer_id is not null)
    or (scope_kind = 'owner_global' and customer_id is null)
  )
);

create index if not exists idx_agent_memories_owner_active
  on public.agent_memories(owner_staff_link_id, scope_kind, state)
  where state = 'active';

create index if not exists idx_agent_memories_customer
  on public.agent_memories(customer_id)
  where customer_id is not null;

-- ---------------------------------------------------------------------------
-- 8. Realtime operational tables (server-only, timestamptz)
-- ---------------------------------------------------------------------------

create table if not exists public.agent_realtime_sessions (
  id text primary key,
  conversation_id text not null
    references public.agent_conversations(id) on delete cascade,
  context_epoch integer not null check (context_epoch >= 1),
  authorization_fingerprint text not null,
  owner_profile_id uuid
    references public.profiles(id) on delete cascade,
  owner_staff_link_id text
    references public.telegram_staff_links(id) on delete set null,
  tenant_id text,
  active_generation integer not null default 1 check (active_generation >= 1),
  state text not null check (state in (
    'provisioning', 'active', 'ending', 'ended', 'failed'
  )),
  recovery_used boolean not null default false,
  usage_settled_at timestamptz,
  created_at timestamptz not null default now(),
  authoritative_ready_at timestamptz,
  expires_at timestamptz,
  ending_at timestamptz,
  ended_at timestamptz,
  end_reason text
);

-- One non-terminal logical session per profile, setup states included.
create unique index if not exists idx_agent_realtime_sessions_one_active
  on public.agent_realtime_sessions(owner_profile_id)
  where state in ('provisioning', 'active', 'ending');

create index if not exists idx_agent_realtime_sessions_conversation
  on public.agent_realtime_sessions(conversation_id, created_at);

create index if not exists idx_agent_realtime_sessions_unsettled
  on public.agent_realtime_sessions(usage_settled_at)
  where usage_settled_at is null and authoritative_ready_at is not null;

create table if not exists public.agent_realtime_calls (
  id text primary key,
  session_id text not null
    references public.agent_realtime_sessions(id) on delete cascade,
  generation integer not null check (generation >= 1),
  openai_call_id text unique,
  setup_state text not null check (setup_state in (
    'provisioning', 'call_registered', 'binding', 'sideband_connecting',
    'active', 'failed', 'ending', 'cleanup_pending', 'ended'
  )),
  authorization_fingerprint text not null,
  provisioned_at timestamptz not null default now(),
  setup_deadline_at timestamptz not null,
  call_registered_at timestamptz,
  binding_started_at timestamptz,
  sideband_connecting_at timestamptz,
  authoritative_ready_at timestamptz,
  webrtc_healthy boolean not null default false,
  data_channel_healthy boolean not null default false,
  sideband_healthy boolean not null default false,
  lease_owner text,
  lease_expires_at timestamptz,
  lease_heartbeat_at timestamptz,
  fencing_token bigint not null default 0 check (fencing_token >= 0),
  binding_token_hash text,
  binding_token_expires_at timestamptz,
  binding_token_consumed_at timestamptz,
  client_secret_issued_at timestamptz,
  client_secret_expires_at timestamptz,
  active_expires_at timestamptz,
  ending_at timestamptz,
  ended_at timestamptz,
  end_reason text,
  hangup_state text check (hangup_state in (
    'not_required', 'pending', 'succeeded', 'failed'
  )),
  cleanup_attempts integer not null default 0 check (cleanup_attempts >= 0),
  cleanup_next_attempt_at timestamptz,
  unique (session_id, generation)
);

create index if not exists idx_agent_realtime_calls_setup_deadline
  on public.agent_realtime_calls(setup_deadline_at)
  where setup_state in (
    'provisioning', 'call_registered', 'binding', 'sideband_connecting'
  );

create index if not exists idx_agent_realtime_calls_cleanup_pending
  on public.agent_realtime_calls(cleanup_next_attempt_at)
  where setup_state = 'cleanup_pending';

create index if not exists idx_agent_realtime_calls_lease
  on public.agent_realtime_calls(lease_expires_at)
  where lease_owner is not null;

-- Usage ledger. One row per (session, UTC date) so a session crossing midnight
-- settles as two slices that sum to its true active seconds. The unique key is
-- the second, independent defence against double settlement; the first is
-- agent_realtime_sessions.usage_settled_at.
create table if not exists public.agent_realtime_usage_seconds (
  session_id text not null
    references public.agent_realtime_sessions(id) on delete cascade,
  usage_date date not null,
  owner_profile_id uuid,
  tenant_id text,
  seconds integer not null check (seconds >= 0),
  settled_at timestamptz not null default now(),
  primary key (session_id, usage_date)
);

create index if not exists idx_agent_realtime_usage_profile_day
  on public.agent_realtime_usage_seconds(owner_profile_id, usage_date);

create index if not exists idx_agent_realtime_usage_tenant_day
  on public.agent_realtime_usage_seconds(tenant_id, usage_date);

create table if not exists public.agent_realtime_start_attempts (
  id text primary key,
  owner_profile_id uuid not null,
  attempted_at timestamptz not null default now(),
  -- 'server_error' exists so a start that failed on OUR side does not consume
  -- the caller's 5-per-300s allowance. Only 'accepted' rows count toward the
  -- window, so a downgraded attempt releases its slot.
  outcome text not null check (outcome in (
    'accepted', 'rate_limited', 'budget_exhausted', 'kill_switch', 'replaced',
    'server_error'
  ))
);

create index if not exists idx_agent_realtime_start_attempts_window
  on public.agent_realtime_start_attempts(owner_profile_id, attempted_at desc);

-- Single-row runtime control. `enabled` is the kill switch; `force_stop_at`
-- fences every session created before it.
create table if not exists public.agent_realtime_runtime_control (
  id integer primary key check (id = 1),
  enabled boolean not null default true,
  draining boolean not null default false,
  force_stop_at timestamptz,
  updated_at timestamptz not null default now(),
  updated_by text
);

insert into public.agent_realtime_runtime_control (id, enabled)
values (1, true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 9. RLS and grants
--
-- Every write path is service_role, which bypasses RLS — matching the existing
-- agent tables, which have no INSERT/UPDATE policies at all. Admin SELECT is
-- granted only where a human diagnostic view is plausible. Purely operational
-- tables get RLS with no policy: service_role only.
-- ---------------------------------------------------------------------------

alter table public.agent_tool_call_claims enable row level security;
alter table public.agent_conversation_summaries enable row level security;
alter table public.agent_memories enable row level security;
alter table public.agent_realtime_sessions enable row level security;
alter table public.agent_realtime_calls enable row level security;
alter table public.agent_realtime_usage_seconds enable row level security;
alter table public.agent_realtime_start_attempts enable row level security;
alter table public.agent_realtime_runtime_control enable row level security;

drop policy if exists agent_conversation_summaries_admin_select
  on public.agent_conversation_summaries;
create policy agent_conversation_summaries_admin_select
  on public.agent_conversation_summaries
  for select
  to authenticated
  using (chickmark_private.app_is_admin());

drop policy if exists agent_realtime_sessions_admin_select
  on public.agent_realtime_sessions;
create policy agent_realtime_sessions_admin_select
  on public.agent_realtime_sessions
  for select
  to authenticated
  using (chickmark_private.app_is_admin());

-- Memories are owner-private. Even an admin does not read them through the
-- client; the runtime reads them as service_role after resolving the owner.

grant all on table public.agent_tool_call_claims to service_role;
grant all on table public.agent_conversation_summaries to service_role;
grant all on table public.agent_memories to service_role;
grant all on table public.agent_realtime_sessions to service_role;
grant all on table public.agent_realtime_calls to service_role;
grant all on table public.agent_realtime_usage_seconds to service_role;
grant all on table public.agent_realtime_start_attempts to service_role;
grant all on table public.agent_realtime_runtime_control to service_role;

commit;
