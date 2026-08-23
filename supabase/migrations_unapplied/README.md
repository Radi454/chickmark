# Unapplied migrations

These files are **not** in the production migration ledger and their objects do
not exist in production. They are held here, outside `supabase/migrations/`, so
that the applied set replays cleanly in filename order.

Do not move a file back into `supabase/migrations/` without giving it a fresh
timestamp that sorts after every applied migration, and without a reviewed
decision to apply it.

- `0009_customer_usernames.sql` — superseded. Its `handle_new_auth_user()` body
  would overwrite the live account-type routing added by `20260813172732`.
  Only the column/index/constraint portion should ever be forward-ported.
- `0017_performance_monitoring.sql` — 19 tables, deferred. Blocked on 9
  `public.flocks` rows whose `farm_id` has no `farms` row to reference.
