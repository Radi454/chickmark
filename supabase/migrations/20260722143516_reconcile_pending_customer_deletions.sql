-- 20260722143516 reconcile_pending_customer_deletions
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- Reconcile customer deletes that older app versions recorded as authoritative
-- tombstones but falsely treated as successful when RLS deleted zero rows.
--
-- This is intentionally ID- and tombstone-driven. It never deletes by customer
-- name, and it is idempotent because already-removed customers no longer match.

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
