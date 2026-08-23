-- 20260623175743 keep_only_ghareeb_customers_guard
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

create or replace function public.chickmark_keep_only_ghareeb_customers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if trim(coalesce(new.name, '')) = 'الغريب' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists customers_keep_only_ghareeb on public.customers;
create trigger customers_keep_only_ghareeb
before insert or update on public.customers
for each row execute function public.chickmark_keep_only_ghareeb_customers();
