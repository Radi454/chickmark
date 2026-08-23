-- Fix iot_ack_commands: it wrote the device's ack status straight into
-- iot_commands.status, and the device vocabulary is not the database vocabulary.
--
-- Contract section 12.5 lets firmware send `received` to mean "accepted, still
-- working on it". iot_commands.status has no `received` value -- it calls that
-- state `acked` -- so every `received` ack failed the check constraint and the
-- whole ack request 500'd. Since firmware is told to ack `received` BEFORE doing
-- anything disruptive (a reboot, most importantly), this broke the one ack that
-- matters most for telling a successful reboot from a crash.
--
-- The mapping belongs here rather than in the Edge Function so that any future
-- caller gets it right for free.

create or replace function public.iot_ack_commands(
  p_hub_id uuid, p_customer_id text, p_acks jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_ack      jsonb;
  v_updated  integer := 0;
  v_unknown  text[] := array[]::text[];
  v_hit      integer;
  v_terminal boolean;
  v_wire     text;
  v_status   text;
begin
  for v_ack in select * from jsonb_array_elements(p_acks) loop
    v_wire := v_ack->>'status';

    -- Device vocabulary -> storage vocabulary.
    v_status := case v_wire
                  when 'received'    then 'acked'
                  when 'succeeded'   then 'succeeded'
                  when 'failed'      then 'failed'
                  when 'unsupported' then 'unsupported'
                  when 'expired'     then 'expired'
                  else null
                end;
    if v_status is null then
      continue;  -- unknown status word: ignore rather than fail the batch
    end if;

    v_terminal := v_status in ('succeeded','failed','unsupported','expired');

    update public.iot_commands c
       set status        = v_status,
           acked_at      = coalesce(c.acked_at, now()),
           completed_at  = case when v_terminal then now() else c.completed_at end,
           result        = coalesce(v_ack->'result', c.result),
           error_code    = coalesce(v_ack->>'error_code', c.error_code),
           error_message = coalesce(left(v_ack->>'error_message', 512), c.error_message),
           attempt_count = c.attempt_count + 1
     where c.id::text     = v_ack->>'command_id'
       and c.hub_id       = p_hub_id
       and c.customer_id  = p_customer_id
       -- A terminal status is never overwritten by a later non-terminal one, so
       -- a late `received` cannot un-finish a completed command.
       and (v_terminal or c.status not in ('succeeded','failed','unsupported','expired'));

    get diagnostics v_hit = row_count;
    if v_hit > 0 then
      v_updated := v_updated + 1;
    else
      if exists (select 1 from public.iot_commands c
                  where c.id::text = v_ack->>'command_id'
                    and c.hub_id = p_hub_id and c.customer_id = p_customer_id) then
        -- Exists but already terminal. Re-acking must stay safe.
        v_updated := v_updated + 1;
      else
        v_unknown := v_unknown || (v_ack->>'command_id');
      end if;
    end if;
  end loop;

  return jsonb_build_object('acknowledged', v_updated, 'unknown', to_jsonb(v_unknown));
end $$;

revoke execute on function public.iot_ack_commands(uuid,text,jsonb) from public, anon, authenticated;
grant  execute on function public.iot_ack_commands(uuid,text,jsonb) to service_role;
