-- The SECURITY INVOKER quality-cache trigger calls this deterministic helper
-- during Chick panel writes. Grant only the roles that perform those writes.
grant execute on function public.chick_quality_legacy_flag(text)
  to authenticated, service_role;
