-- 0009 customer usernames
--
-- Customer accounts authenticate through Supabase email/password internally,
-- while the app exposes a short username. The username is stored on profiles
-- for admin display and uniqueness checks; the Edge Function creates the
-- synthetic auth email and assigns the approved customer scope atomically.

alter table public.profiles
  add column if not exists username text;

create unique index if not exists profiles_username_lower_unique
  on public.profiles (lower(username))
  where username is not null;

alter table public.profiles
  drop constraint if exists profiles_username_format;
alter table public.profiles
  add constraint profiles_username_format check (
    username is null
    or username ~ '^[a-z0-9][a-z0-9._-]{2,39}$'
  );

create or replace function public.handle_new_auth_user()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
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

revoke execute on function public.handle_new_auth_user()
  from public, anon, authenticated;
grant execute on function public.handle_new_auth_user()
  to service_role;
