-- 20260727214044 align_flocks_performance_columns
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

alter table public.flocks
  add column if not exists farm_id text,
  add column if not exists sector_key text,
  add column if not exists sex_profile text not null default 'as_hatched',
  add column if not exists target_profile_id text,
  add column if not exists production_phase text;

alter table public.flocks
  drop constraint if exists flocks_sector_key_check,
  add constraint flocks_sector_key_check
    check (sector_key is null or sector_key in ('breeder', 'broiler', 'layer')),
  drop constraint if exists flocks_sex_profile_check,
  add constraint flocks_sex_profile_check
    check (sex_profile in ('as_hatched', 'male', 'female'));

create index if not exists idx_flocks_farm
  on public.flocks(farm_id) where farm_id is not null;

create index if not exists idx_flocks_target_profile
  on public.flocks(target_profile_id) where target_profile_id is not null;
