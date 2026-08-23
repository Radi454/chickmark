-- 20260606081246 0004_harden_function_grants
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- 0004 lock down helper/trigger function execution (clears anon RPC-exposure advisor)
-- Scope helpers: only authenticated may execute (needed inside RLS policies); anon revoked.
do $$
declare f text;
begin
  foreach f in array array[
    'public.app_role()','public.app_status()','public.app_customer_id()',
    'public.app_is_admin()','public.app_is_staff()',
    'public.app_can_read_customer(text)','public.app_can_write_customer(text)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant  execute on function %s to authenticated', f);
  end loop;
  -- trigger functions are never called directly; revoke from everyone (triggers run as owner)
  foreach f in array array[
    'public.handle_new_auth_user()','public.handle_new_customer()','public.touch_updated_at()'
  ] loop
    execute format('revoke execute on function %s from public', f);
  end loop;
end $$;
