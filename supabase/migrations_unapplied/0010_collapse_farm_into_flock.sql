-- Collapse Farm into Flock (breeder-flock-performance ticket 02).
--
-- A farm and a flock are the same thing in this business, so the app no
-- longer models them as two levels: see
-- docs/superpowers/specs/2026-08-27-breeder-flock-performance-design.md
-- section 2.1 and local migration v68
-- (lib/data/database/database_migrations.dart, _applyV68Upgrade).
--
-- Verified against the live project with mcp__supabase__list_tables /
-- execute_sql before writing this file: `farms`, `houses`, and
-- `flock_placements` were never created remotely (this hierarchy has been a
-- local-only feature so far), so there is nothing to drop for them here.
-- `public.flocks.farm_id` DOES exist remotely, though, so this migration
-- drops it to match the local schema. This file is deliberately NOT applied
-- by this change — see supabase/migrations_unapplied/README.md.

alter table public.flocks
  drop column if exists farm_id;
