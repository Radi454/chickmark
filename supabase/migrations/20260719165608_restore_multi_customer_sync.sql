-- Restore the current multi-customer product behavior.
--
-- A one-off production cleanup installed this trigger in June 2026. It
-- silently cancels every customer insert whose name is not `الغريب`, so the
-- client receives a successful HTTP response even though no row was created.
-- The current app supports multiple customers and relies on those customer
-- rows as parents for hatcheries, flocks, audit sessions, and panel data.

drop trigger if exists customers_keep_only_ghareeb on public.customers;
drop function if exists public.chickmark_keep_only_ghareeb_customers();
