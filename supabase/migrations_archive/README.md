# Archived migrations (applied in production, not replayable from empty)

These are recovered verbatim from the production migration ledger and are kept
for the historical record. They are held outside `supabase/migrations/` because
they cannot replay against an empty database, so including them would break
`scripts/test_supabase_security_hardening.sh`, which replays the whole
directory in filename order.

- `20260418043712_create_hatchaudit_schema.sql` — the abandoned
  earlier-generation schema (uuid ids, denormalized `audits` wide table). It is
  explicitly dropped and superseded by
  `supabase/migrations/20260605115351_reset_and_vertical_slice.sql`. It is also
  internally forward-referencing (`users.customer_id` references `customers`
  before that table is created), so it only ever applied against a database
  where those objects already existed.

Do not move these back into `supabase/migrations/`.
