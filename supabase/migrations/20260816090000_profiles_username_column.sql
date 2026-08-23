-- 20260816090000 profiles_username_column
--
-- HOTFIX for a live production defect, kept deliberately separate from the Pip
-- Realtime V1 work.
--
-- `public.handle_new_auth_user()` in production still contains the legacy
-- branch inherited from the never-applied `0009_customer_usernames.sql`:
--
--     insert into public.profiles (id, full_name, email, username, role, status)
--
-- but `public.profiles` has no `username` column, because 0009 was never
-- applied. The client never sends `account_type`
-- (lib/services/supabase/supabase_service.dart calls signUp with only
-- `full_name`), so every self-serve signup falls through the `personal` and
-- `organization` branches into that legacy branch and raises
-- `42703 column "username" of relation "profiles" does not exist`, which
-- aborts the `auth.users` insert. The client then masks the failure with
-- `registerLocalFallback`, telling the user "Account created locally."
-- `public.profiles` contains 2 rows, both `account_type='internal'` — no
-- self-serve signup has ever succeeded.
--
-- It also breaks Admin -> Users: lib/data/repositories/admin_repository.dart
-- selects `username`, so PostgREST rejects the whole request and the screen
-- fails to load.
--
-- This migration adds ONLY the missing column, its partial unique index and its
-- format check. It deliberately does NOT touch `handle_new_auth_user()`.
-- Applying 0009 as written would `create or replace` that function and silently
-- delete the `personal` / `organization` account-type routing added by
-- 20260813172732_signup_account_routing — a regression of the whole
-- organization signup model. 0009 stays in supabase/migrations_unapplied/.
--
-- Safe by construction: the column is nullable, the CHECK permits NULL, and the
-- unique index is partial, so the 2 existing rows need no backfill.
-- Rollback: alter table public.profiles drop column username cascade;
--
-- NOTE: after this lands, signup will SUCCEED but land in the legacy branch as
-- role='auditor', status='pending', because the client still sends no
-- account_type. Choosing the intended self-serve account model is a separate
-- product decision (see docs/superpowers/plans/2026-08-13-account-model-registration.md).

begin;

alter table public.profiles
  add column if not exists username text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_username_format'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_username_format
      check (
        username is null
        or username ~ '^[a-z0-9][a-z0-9._-]{2,39}$'
      );
  end if;
end
$$;

create unique index if not exists profiles_username_lower_unique
  on public.profiles (lower(username))
  where username is not null;

comment on column public.profiles.username is
  'Optional short login handle for customer accounts. NULL for accounts that '
  'sign in with an email address.';

commit;
