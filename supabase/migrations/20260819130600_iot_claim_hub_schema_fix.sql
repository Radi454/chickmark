-- Fix iot_claim_hub after the chickmark_private -> public table move.
--
-- 20260819130300 relocated iot_hub_secrets (and three siblings) into public so
-- the Edge Function could reach them through PostgREST, but iot_claim_hub still
-- wrote to chickmark_private.iot_hub_secrets. Because the function body is only
-- resolved at call time, the migration applied cleanly and claiming stayed
-- broken until something actually claimed a hub.
--
-- Caught by scripts/test_iot_tenant_isolation.sh, which is why that test drives
-- the real RPC rather than asserting on the schema alone.

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
  -- Resolve the hatchery and the caller's authority over it in ONE branch, so a
  -- non-existent hatchery is indistinguishable from an unauthorised one and this
  -- cannot be used to enumerate hatchery ids across tenants.
  select h.customer_id into v_customer_id
    from public.hatcheries h where h.id = p_hatchery_id;
  if v_customer_id is null
     or not chickmark_private.app_can_write_customer(v_customer_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  -- Lock the registry row: makes check-then-insert atomic and serialises
  -- concurrent claims of the same serial behind one another.
  select * into v_reg from public.iot_hub_registry r
    where r.hub_serial = p_hub_serial for update;

  if v_reg.claim_locked_until is not null and v_reg.claim_locked_until > now() then
    raise exception 'claim_locked' using errcode = '55P03';
  end if;

  v_code_hash := encode(sha256(convert_to(upper(trim(coalesce(p_claim_code,''))), 'UTF8')), 'hex');

  -- One indistinguishable branch for "no such serial" and "wrong code".
  if v_reg.hub_serial is null or v_reg.claim_code_hash is distinct from v_code_hash then
    update public.iot_hub_registry
       set claim_attempts     = claim_attempts + 1,
           claim_locked_until = case when claim_attempts + 1 >= 5
                                     then now() + interval '15 minutes' end
     where hub_serial = p_hub_serial;
    raise exception 'invalid_claim' using errcode = '22023';
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
