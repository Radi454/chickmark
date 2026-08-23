-- 20260722143804 prevent_customer_resurrection
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- Prevent older/offline clients from recreating a customer after another
-- device has published an authoritative deletion tombstone.

create or replace function chickmark_private.reject_tombstoned_customer_write()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.sync_tombstones as tombstone
    where tombstone.id = 'customers:' || new.id
      and tombstone.table_name = 'customers'
      and tombstone.row_id = new.id
      and tombstone.customer_id = new.id
      and (
        tombstone.created_by is not null
        or cardinality(tombstone.audience_user_ids) > 0
      )
  ) then
    raise exception 'Customer write conflicts with a deletion tombstone'
      using errcode = '23503';
  end if;

  return new;
end;
$$;

revoke all on function chickmark_private.reject_tombstoned_customer_write()
  from public, anon, authenticated;

drop trigger if exists customers_reject_tombstoned_write
  on public.customers;
create trigger customers_reject_tombstoned_write
  before insert or update on public.customers
  for each row execute function
    chickmark_private.reject_tombstoned_customer_write();

-- Install the guard before reconciling. Once this transaction commits, a stale
-- client cannot win the race by immediately upserting the deleted IDs again.
delete from public.customers as customer
using public.sync_tombstones as tombstone
where tombstone.id = 'customers:' || customer.id
  and tombstone.table_name = 'customers'
  and tombstone.row_id = customer.id
  and tombstone.customer_id = customer.id
  and (
    tombstone.created_by is not null
    or cardinality(tombstone.audience_user_ids) > 0
  );
