-- 20260813172732 20260813091000_signup_account_routing
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- 20260813091000 signup account routing
--
-- Replaces handle_new_auth_user so registration metadata picks the account
-- model. The legacy branch (no account_type in metadata) is byte-for-byte the
-- behaviour from 0009 so existing Edge Function signups are unaffected.

create or replace function public.handle_new_auth_user()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_account_type text := nullif(new.raw_user_meta_data->>'account_type', '');
  v_org_code     text := nullif(trim(new.raw_user_meta_data->>'org_code'), '');
  v_org          public.organizations%rowtype;
begin
  if v_account_type = 'personal' then
    insert into public.profiles (id, full_name, email, role, status, account_type)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'full_name', new.email),
      new.email,
      'personal',
      'approved',
      'personal'
    )
    on conflict (id) do nothing;
    return new;
  end if;

  if v_account_type = 'organization' then
    select * into v_org from public.organizations o
     where upper(o.code) = upper(v_org_code)
     limit 1;
    if not found then
      raise exception 'ORG_CODE_INVALID';
    end if;

    insert into public.profiles (
      id, full_name, email, role, status, account_type,
      organization_id, org_role, customer_id
    )
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'full_name', new.email),
      new.email,
      'customer',
      'pending',
      'organization',
      v_org.id,
      'member',
      v_org.customer_id
    )
    on conflict (id) do nothing;
    return new;
  end if;

  -- legacy path, unchanged from 0009
  insert into public.profiles (id, full_name, email, username, role, status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email,
    nullif(lower(new.raw_user_meta_data->>'username'), ''),
    'auditor',
    'pending'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_auth_user() from public, anon, authenticated;
grant execute on function public.handle_new_auth_user() to service_role;
