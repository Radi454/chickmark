-- Production migration history version: 20260730111832.
begin;

alter table public.agent_conversations
  add column if not exists context_epoch integer not null default 1,
  add column if not exists selected_customer_id text
    references public.customers(id) on delete set null,
  add column if not exists selected_flock_id text
    references public.flocks(id) on delete set null,
  add column if not exists selected_audit_id text
    references public.audit_sessions(id) on delete set null,
  add column if not exists context_updated_at text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'agent_conversations_context_epoch_check'
      and conrelid = 'public.agent_conversations'::regclass
  ) then
    alter table public.agent_conversations
      add constraint agent_conversations_context_epoch_check
      check (context_epoch >= 1);
  end if;
end
$$;

alter table public.agent_conversation_turns
  add column if not exists context_epoch integer not null default 1,
  add column if not exists provider text,
  add column if not exists provider_response_id text,
  add column if not exists reply_to_turn_id text
    references public.agent_conversation_turns(id) on delete set null;

alter table public.agent_conversation_turns
  drop constraint if exists agent_conversation_turns_inbound_index_check;

with ranked as (
  select
    id,
    row_number() over (
      partition by conversation_id, direction
      order by created_at, id
    ) as turn_index
  from public.agent_conversation_turns
)
update public.agent_conversation_turns turn
set turn_index = ranked.turn_index
from ranked
where turn.id = ranked.id
  and turn.turn_index is null;

update public.agent_conversation_turns outbound
set reply_to_turn_id = inbound.id
from public.agent_conversation_turns inbound
where outbound.direction = 'outbound'
  and outbound.reply_to_turn_id is null
  and inbound.conversation_id = outbound.conversation_id
  and inbound.direction = 'inbound'
  and inbound.context_epoch = outbound.context_epoch
  and inbound.turn_index = outbound.turn_index;

drop index if exists public.idx_agent_conversation_turns_inbound_index;

create unique index if not exists idx_agent_conversation_turns_order
  on public.agent_conversation_turns(
    conversation_id,
    context_epoch,
    direction,
    turn_index
  )
  where turn_index is not null;

alter table public.agent_conversation_turns
  add constraint agent_conversation_turns_order_check
  check (
    context_epoch >= 1
    and turn_index is not null
    and turn_index >= 1
  );

alter table public.agent_tool_events
  add column if not exists tool_sequence integer;

drop trigger if exists agent_tool_events_immutable
  on public.agent_tool_events;

with ranked as (
  select
    id,
    row_number() over (
      partition by conversation_turn_id
      order by created_at, id
    ) as tool_sequence
  from public.agent_tool_events
)
update public.agent_tool_events event
set tool_sequence = ranked.tool_sequence
from ranked
where event.id = ranked.id
  and event.tool_sequence is null;

create unique index if not exists idx_agent_tool_events_sequence
  on public.agent_tool_events(conversation_turn_id, tool_sequence)
  where tool_sequence is not null;

alter table public.agent_tool_events
  add constraint agent_tool_events_sequence_check
  check (tool_sequence is not null and tool_sequence >= 1);

create trigger agent_tool_events_immutable
before update or delete on public.agent_tool_events
for each row execute function chickmark_private.protect_agent_tool_event();

-- Reviewed legacy-sector backfill, ordered from strongest evidence to weakest:
-- an explicitly linked farm, hatchery-audit history, then one unambiguous active
-- sector for the customer. Ambiguous flocks deliberately remain unassigned.
do $$
begin
  if to_regclass('public.farms') is not null then
    execute $backfill$
      update public.flocks flock
      set sector_key = farm.sector_key
      from public.farms farm
      where flock.sector_key is null
        and flock.farm_id = farm.id
        and flock.customer_id = farm.customer_id
        and farm.sector_key is not null
    $backfill$;
  end if;
end
$$;

update public.flocks flock
set sector_key = 'breeder'
where flock.sector_key is null
  and exists (
    select 1
    from public.audit_sessions audit
    where audit.flock_id = flock.id
      and audit.customer_id = flock.customer_id
      and audit.hatchery_id is not null
  );

do $$
begin
  if to_regclass('public.customer_sectors') is not null then
    execute $backfill$
      update public.flocks flock
      set sector_key = candidate.sector_key
      from (
        select
          sector.customer_id,
          min(sector.sector_key) as sector_key
        from public.customer_sectors sector
        where lower(sector.is_active::text) in ('true', 't', '1')
        group by sector.customer_id
        having count(distinct sector.sector_key) = 1
      ) candidate
      where flock.sector_key is null
        and flock.customer_id = candidate.customer_id
    $backfill$;
  end if;
end
$$;

grant all on table public.agent_conversations to service_role;
grant all on table public.agent_conversation_turns to service_role;
grant all on table public.agent_tool_events to service_role;

commit;
