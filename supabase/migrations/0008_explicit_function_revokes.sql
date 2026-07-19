-- 0008 explicit trigger-function revokes
--
-- 0007 revoked PUBLIC and anon execution across the public schema and revoked
-- authenticated execution from these trigger functions. Keep the effective
-- state explicit for every API role so future grant changes cannot expose them.

revoke execute on function public.handle_new_auth_user() from public, anon, authenticated;
revoke execute on function public.handle_new_customer() from public, anon, authenticated;
revoke execute on function public.touch_updated_at() from public, anon, authenticated;

do $$
begin
  if to_regprocedure('public.chickmark_keep_only_ghareeb_customers()') is not null then
    execute
      'revoke execute on function public.chickmark_keep_only_ghareeb_customers() from public, anon, authenticated';
  end if;
end
$$;
