-- 0001 reset stale schema + build vertical slice
--
-- The cloud DB carried an abandoned earlier-generation schema (denormalized `audits`
-- wide table, uuid ids, mismatched bmk_*/troubleshooting/photos columns) that the
-- current Flutter app no longer targets. It held only demo/seed data. We drop it and
-- rebuild the first vertical slice to EXACTLY mirror the local SQLite schema so the
-- existing client sync (SupabaseService / StartupSyncService) round-trips losslessly.
--
-- Conventions (must match the client):
--   * snake_case columns  -- client pushes _snakeCaseKeys(), camelizes again on pull
--   * text ids            -- app generates string uuids; stored as TEXT locally
--   * text date/time      -- exact ISO round-trip (toIso8601String <-> DateTime.parse)
--   * integer booleans    -- 0/1 as in SQLite
--   * RLS: authenticated = full access (first-pass model; harden to per-tenant later)
--
-- auth.users (login accounts) lives in the `auth` schema and is intentionally untouched.

-- 1. Drop the abandoned schema (demo data only) ------------------------------------
drop table if exists public.audits           cascade;
drop table if exists public.photos           cascade;
drop table if exists public.troubleshooting  cascade;
drop table if exists public.bmk_egg_breakout cascade;
drop table if exists public.bmk_breeds       cascade;
drop table if exists public.audit_sessions   cascade;
drop table if exists public.flocks           cascade;
drop table if exists public.hatcheries       cascade;
drop table if exists public.customers        cascade;
drop table if exists public.users            cascade;

-- 2. Vertical slice: customers -> hatcheries -> flocks -> audit_sessions ------------
create table public.customers (
  id          text primary key,
  name        text,
  location    text,
  phone       text,
  email       text,
  created_at  text,
  created_by  text
);

create table public.hatcheries (
  id          text primary key,
  customer_id text not null references public.customers(id) on delete cascade,
  name        text not null,
  location    text,
  notes       text,
  created_at  text,
  created_by  text
);
create index idx_hatcheries_customer on public.hatcheries(customer_id);

create table public.flocks (
  id                  text primary key,
  customer_id         text references public.customers(id) on delete cascade,
  flock_id            text,
  breed               text,
  entry_date          text,
  is_age_estimated    integer not null default 0,
  status              text    not null default 'active',
  depletion_age_weeks integer not null default 65,
  sold_at             text
);
create index idx_flocks_customer on public.flocks(customer_id, status);

create table public.audit_sessions (
  id                    text primary key,
  customer_id           text not null references public.customers(id)  on delete cascade,
  flock_id              text not null references public.flocks(id)      on delete cascade,
  hatchery_id           text not null references public.hatcheries(id)  on delete cascade,
  date                  text not null,
  breed                 text,
  flock_age_weeks       integer,
  status                text default 'in_progress',
  selected_station_keys text,
  stations_completed    text,
  findings_json         text,
  scorecard_json        text,
  notes                 text,
  created_by            text,
  created_at            text,
  updated_at            text,
  completed_at          text
);
create index idx_audit_sessions_customer_date on public.audit_sessions(customer_id, date desc);
create index idx_audit_sessions_flock_date    on public.audit_sessions(flock_id, date desc);

-- 3. RLS: authenticated = full access ----------------------------------------------
alter table public.customers      enable row level security;
alter table public.hatcheries     enable row level security;
alter table public.flocks         enable row level security;
alter table public.audit_sessions enable row level security;

create policy authenticated_all on public.customers
  for all to authenticated using (true) with check (true);
create policy authenticated_all on public.hatcheries
  for all to authenticated using (true) with check (true);
create policy authenticated_all on public.flocks
  for all to authenticated using (true) with check (true);
create policy authenticated_all on public.audit_sessions
  for all to authenticated using (true) with check (true);
