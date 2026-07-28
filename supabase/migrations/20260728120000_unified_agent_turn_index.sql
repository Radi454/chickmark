begin;

alter table public.agent_conversation_turns
  add column if not exists turn_index integer;

with ranked as (
  select
    id,
    row_number() over (
      partition by conversation_id
      order by created_at, id
    ) as turn_index
  from public.agent_conversation_turns
  where direction = 'inbound'
)
update public.agent_conversation_turns turn
set turn_index = ranked.turn_index
from ranked
where turn.id = ranked.id
  and turn.turn_index is null;

alter table public.agent_conversation_turns
  drop constraint if exists agent_conversation_turns_inbound_index_check,
  add constraint agent_conversation_turns_inbound_index_check
  check (
    (direction = 'inbound' and turn_index is not null and turn_index >= 1)
    or (direction = 'outbound' and turn_index is null)
  );

create unique index if not exists
  idx_agent_conversation_turns_inbound_index
  on public.agent_conversation_turns(conversation_id, turn_index)
  where direction = 'inbound';

commit;
