-- Make the claim-code lockout actually work.
--
-- The previous version incremented iot_hub_registry.claim_attempts and then
-- raised `invalid_claim`. In PostgreSQL the RAISE aborts the whole function
-- call, so the increment rolled back with it: the counter never advanced, and
-- claim_locked_until was never set. The lockout looked present in the source and
-- did nothing at all. Caught by scripts/test_iot_tenant_isolation.sh.
--
-- Fix: an invalid claim now RETURNS NULL instead of raising. No exception means
-- the increment commits, so the counter and the 15-minute lock work as intended.
-- Genuine authorization failures still raise, because those must never be
-- confusable with "wrong code".
--
-- Caller contract:
--   returns uuid  -> claimed, this is the hub_id
--   returns null  -> unknown serial OR wrong claim code (deliberately the same
--                    outcome, so this cannot be used to enumerate serials)
--   42501 forbidden      -> caller has no write scope on that hatchery, or the
--                           hatchery does not exist (also deliberately merged)
--   55P03 claim_locked   -> too many failed attempts, try later
--   23505 already_claimed-> that serial already has a live hub

create or replace function public.iot_claim_hub(
  p_hub_serial  text,
  p_claim_code  text,
  p_hatchery_id text,
  p_name        text default ''
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_customer_id text;
  v_reg         public.iot_hub_registry%rowtype;
  v_hub_id      uuid;
  v_code_hash   text;
begin
  select h.customer_id into v_customer_id
    from public.hatcheries h where h.id = p_hatchery_id;
  if v_customer_id is null
     or not chickmark_private.app_can_write_customer(v_customer_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select * into v_reg from public.iot_hub_registry r
    where r.hub_serial = p_hub_serial for update;

  if v_reg.claim_locked_until is not null and v_reg.claim_locked_until > now() then
    raise exception 'claim_locked' using errcode = '55P03';
  end if;

  v_code_hash := encode(sha256(convert_to(upper(trim(coalesce(p_claim_code,''))), 'UTF8')), 'hex');

  if v_reg.hub_serial is null or v_reg.claim_code_hash is distinct from v_code_hash then
    -- Return, do not raise: raising would roll this increment back and the
    -- lockout would never engage.
    update public.iot_hub_registry
       set claim_attempts     = claim_attempts + 1,
           claim_locked_until = case when claim_attempts + 1 >= 5
                                     then now() + interval '15 minutes' end
     where hub_serial = p_hub_serial;
    return null;
  end if;

  insert into public.iot_hubs (hub_serial, customer_id, hatchery_id, name,
                               hardware_model, claimed_by)
  values (p_hub_serial, v_customer_id, p_hatchery_id, coalesce(p_name, ''),
          v_reg.hardware_model, (select auth.uid()))
  returning id into v_hub_id;

  update public.iot_hub_registry
     set claimed_at = now(), claim_attempts = 0, claim_locked_until = null
   where hub_serial = p_hub_serial;

  insert into public.iot_hub_secrets (hub_id)
    values (v_hub_id) on conflict (hub_id) do nothing;
  insert into public.iot_hub_config (hub_id, customer_id)
    values (v_hub_id, v_customer_id) on conflict (hub_id) do nothing;
  return v_hub_id;
exception
  when unique_violation then
    raise exception 'already_claimed' using errcode = '23505';
end $$;

revoke execute on function public.iot_claim_hub(text,text,text,text) from public, anon;
grant  execute on function public.iot_claim_hub(text,text,text,text) to authenticated, service_role;
