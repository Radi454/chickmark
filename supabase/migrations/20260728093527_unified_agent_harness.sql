begin;

alter table public.telegram_staff_links
  add column if not exists access_role text not null default 'customer',
  add column if not exists customer_id text
    references public.customers(id) on delete restrict;

-- Existing allowed links predate customer assignment and represent the
-- administrator who configured the Telegram agent. Preserve their access
-- explicitly as admin rather than silently assigning an arbitrary customer.
update public.telegram_staff_links
set
  access_role = 'admin',
  customer_id = null
where status = 'allowed'
  and customer_id is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'telegram_staff_links_access_role_check'
      and conrelid = 'public.telegram_staff_links'::regclass
  ) then
    alter table public.telegram_staff_links
      add constraint telegram_staff_links_access_role_check
      check (access_role in ('customer', 'admin'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'telegram_staff_links_allowed_scope_check'
      and conrelid = 'public.telegram_staff_links'::regclass
  ) then
    alter table public.telegram_staff_links
      add constraint telegram_staff_links_allowed_scope_check
      check (
        status <> 'allowed'
        or (access_role = 'customer' and customer_id is not null)
        or (access_role = 'admin' and customer_id is null)
      );
  end if;
end
$$;

create index if not exists idx_telegram_staff_links_customer
  on public.telegram_staff_links(customer_id)
  where customer_id is not null;

create table public.agent_conversations (
  id text primary key,
  staff_link_id text not null
    references public.telegram_staff_links(id) on delete cascade,
  telegram_chat_id text not null,
  state_version integer not null default 1 check (state_version >= 1),
  pending_action_json jsonb,
  active_visit_id text,
  created_at text not null,
  updated_at text not null,
  unique (staff_link_id, telegram_chat_id)
);

create unique index idx_agent_conversations_staff_chat
  on public.agent_conversations(staff_link_id, telegram_chat_id);

create table public.agent_conversation_turns (
  id text primary key,
  conversation_id text not null
    references public.agent_conversations(id) on delete cascade,
  direction text not null check (direction in ('inbound', 'outbound')),
  telegram_update_id text unique,
  telegram_message_id text,
  text text not null,
  language text not null check (language in ('en', 'ar', 'mixed')),
  model text,
  attachment_json jsonb,
  delivery_status text,
  created_at text not null
);

create index idx_agent_conversation_turns_conversation
  on public.agent_conversation_turns(conversation_id, created_at, id);

create table public.agent_tool_events (
  id text primary key,
  conversation_turn_id text not null
    references public.agent_conversation_turns(id) on delete cascade,
  tool_call_id text not null,
  tool_name text not null,
  arguments_json jsonb not null default '{}'::jsonb,
  result_json jsonb,
  status text not null check (
    status in ('requested', 'succeeded', 'rejected', 'failed')
  ),
  duration_ms integer check (duration_ms is null or duration_ms >= 0),
  state_version_before integer check (
    state_version_before is null or state_version_before >= 1
  ),
  state_version_after integer check (
    state_version_after is null or state_version_after >= 1
  ),
  created_at text not null,
  unique (conversation_turn_id, tool_call_id)
);

create index idx_agent_tool_events_turn
  on public.agent_tool_events(conversation_turn_id, created_at, id);

create table public.agent_intake_visits (
  id text primary key,
  conversation_id text not null
    references public.agent_conversations(id) on delete cascade,
  customer_id text references public.customers(id) on delete restrict,
  flock_id text references public.flocks(id) on delete restrict,
  hatchery_id text references public.hatcheries(id) on delete restrict,
  audit_date text not null,
  state text not null check (state in (
    'selecting_station',
    'collecting',
    'awaiting_admin_review',
    'completed',
    'cancelled'
  )),
  approved_session_id text
    references public.audit_sessions(id) on delete set null,
  created_at text not null,
  updated_at text not null
);

create index idx_agent_intake_visits_conversation
  on public.agent_intake_visits(conversation_id, created_at, id);
create index idx_agent_intake_visits_customer
  on public.agent_intake_visits(customer_id, audit_date)
  where customer_id is not null;

alter table public.agent_conversations
  add constraint agent_conversations_active_visit_fkey
  foreign key (active_visit_id)
  references public.agent_intake_visits(id) on delete set null;

alter table public.agent_intake_sessions
  add column if not exists visit_id text
    references public.agent_intake_visits(id) on delete set null,
  add column if not exists row_version integer not null default 1,
  add column if not exists last_tool_event_id text
    references public.agent_tool_events(id) on delete set null;

alter table public.agent_intake_sessions
  add constraint agent_intake_sessions_row_version_check
  check (row_version >= 1);

-- Backfill the deployed Pasgar sessions additively. A deterministic
-- conversation is shared by a staff/chat pair and each legacy session gets
-- its own visit, so no confirmed evidence is merged or rewritten.
insert into public.agent_conversations (
  id,
  staff_link_id,
  telegram_chat_id,
  state_version,
  created_at,
  updated_at
)
select
  'legacy-conversation-' || md5(
    intake.staff_link_id || chr(31) || intake.telegram_chat_id
  ),
  intake.staff_link_id,
  intake.telegram_chat_id,
  1,
  min(intake.created_at),
  max(intake.updated_at)
from public.agent_intake_sessions intake
group by intake.staff_link_id, intake.telegram_chat_id
on conflict (staff_link_id, telegram_chat_id) do nothing;

insert into public.agent_intake_visits (
  id,
  conversation_id,
  customer_id,
  flock_id,
  hatchery_id,
  audit_date,
  state,
  approved_session_id,
  created_at,
  updated_at
)
select
  'legacy-visit-' || intake.id,
  conversation.id,
  intake.customer_id,
  intake.flock_id,
  intake.hatchery_id,
  intake.audit_date,
  case
    when intake.state = 'approved' then 'completed'
    when intake.state in ('rejected', 'cancelled') then 'cancelled'
    when intake.state = 'awaiting_admin_review' then 'awaiting_admin_review'
    else 'collecting'
  end,
  intake.approved_session_id,
  intake.created_at,
  intake.updated_at
from public.agent_intake_sessions intake
join public.agent_conversations conversation
  on conversation.staff_link_id = intake.staff_link_id
 and conversation.telegram_chat_id = intake.telegram_chat_id
on conflict (id) do nothing;

update public.agent_intake_sessions
set
  visit_id = 'legacy-visit-' || id,
  row_version = 1
where visit_id is null;

update public.agent_conversations conversation
set active_visit_id = (
  select visit.id
  from public.agent_intake_visits visit
  where visit.conversation_id = conversation.id
    and visit.state in (
      'selecting_station',
      'collecting',
      'awaiting_admin_review'
    )
  order by visit.updated_at desc, visit.id desc
  limit 1
)
where exists (
  select 1
  from public.agent_intake_visits visit
  where visit.conversation_id = conversation.id
    and visit.state in (
      'selecting_station',
      'collecting',
      'awaiting_admin_review'
    )
);

drop index if exists public.idx_agent_intake_sessions_active;
create unique index idx_agent_intake_sessions_active_conversation
  on public.agent_intake_sessions(visit_id)
  where visit_id is not null
    and state in (
      'collecting',
      'awaiting_clarification',
      'paused',
      'ready_for_summary',
      'awaiting_user_confirmation'
    );
create index idx_agent_intake_sessions_visit
  on public.agent_intake_sessions(visit_id, created_at, id)
  where visit_id is not null;

create or replace function chickmark_private.validate_agent_intake_visit_scope()
  returns trigger
  language plpgsql
  security invoker
  set search_path = ''
as $$
begin
  if new.customer_id is null then
    raise exception 'Visit customer is required';
  end if;
  if new.flock_id is not null and not exists (
    select 1
    from public.flocks flock
    where flock.id = new.flock_id
      and flock.customer_id = new.customer_id
  ) then
    raise exception 'Flock does not belong to visit customer';
  end if;
  if new.hatchery_id is not null and not exists (
    select 1
    from public.hatcheries hatchery
    where hatchery.id = new.hatchery_id
      and hatchery.customer_id = new.customer_id
  ) then
    raise exception 'Hatchery does not belong to visit customer';
  end if;
  return new;
end
$$;

create trigger validate_agent_intake_visit_scope
before insert or update of customer_id, flock_id, hatchery_id
on public.agent_intake_visits
for each row execute function
  chickmark_private.validate_agent_intake_visit_scope();

create or replace function chickmark_private.protect_confirmed_agent_intake_summary()
  returns trigger
  language plpgsql
  security invoker
  set search_path = ''
as $$
begin
  if old.user_confirmed_at is not null and (
    new.schema_key is distinct from old.schema_key
    or new.schema_version is distinct from old.schema_version
    or new.summary_version is distinct from old.summary_version
    or new.summary_snapshot_json is distinct from old.summary_snapshot_json
    or new.user_confirmed_at is distinct from old.user_confirmed_at
  ) then
    raise exception 'Confirmed intake summary evidence is immutable';
  end if;
  return new;
end
$$;

create trigger agent_intake_summary_immutable
before update on public.agent_intake_sessions
for each row execute function
  chickmark_private.protect_confirmed_agent_intake_summary();

create or replace function chickmark_private.protect_agent_tool_event()
  returns trigger
  language plpgsql
  security invoker
  set search_path = ''
as $$
begin
  raise exception 'Tool-call evidence is immutable';
end
$$;

create trigger agent_tool_events_immutable
before update or delete on public.agent_tool_events
for each row execute function chickmark_private.protect_agent_tool_event();

revoke all on function
  chickmark_private.validate_agent_intake_visit_scope()
  from public, anon, authenticated;
revoke all on function
  chickmark_private.protect_confirmed_agent_intake_summary()
  from public, anon, authenticated;
revoke all on function
  chickmark_private.protect_agent_tool_event()
  from public, anon, authenticated;

alter table public.agent_conversations enable row level security;
alter table public.agent_conversation_turns enable row level security;
alter table public.agent_tool_events enable row level security;
alter table public.agent_intake_visits enable row level security;

create policy agent_conversations_admin_select
  on public.agent_conversations
  for select
  to authenticated
  using (chickmark_private.app_is_admin());
create policy agent_conversation_turns_admin_select
  on public.agent_conversation_turns
  for select
  to authenticated
  using (chickmark_private.app_is_admin());
create policy agent_tool_events_admin_select
  on public.agent_tool_events
  for select
  to authenticated
  using (chickmark_private.app_is_admin());
create policy agent_intake_visits_admin_select
  on public.agent_intake_visits
  for select
  to authenticated
  using (chickmark_private.app_is_admin());

revoke all on table public.agent_conversations
  from public, anon, authenticated;
revoke all on table public.agent_conversation_turns
  from public, anon, authenticated;
revoke all on table public.agent_tool_events
  from public, anon, authenticated;
revoke all on table public.agent_intake_visits
  from public, anon, authenticated;

grant select on table public.agent_conversations to authenticated;
grant select on table public.agent_conversation_turns to authenticated;
grant select on table public.agent_tool_events to authenticated;
grant select on table public.agent_intake_visits to authenticated;

grant all on table public.agent_conversations to service_role;
grant all on table public.agent_conversation_turns to service_role;
grant all on table public.agent_tool_events to service_role;
grant all on table public.agent_intake_visits to service_role;

commit;
