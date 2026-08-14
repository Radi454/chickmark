-- bmk_operational_standards: cloud mirror of the local SQLite table.
--
-- A row is either GLOBAL (hatchery_id is null) or OWNED by one hatchery, and
-- therefore one customer. The table has no customer_id column, so ownership is
-- resolved by joining public.hatcheries -- the same shape the photos policies
-- use to reach audit_sessions (0003).
--
-- Global rows behave like the other bmk_* reference tables: read by every
-- authenticated user, written by admins only. Owned rows follow the normal
-- customer scope helpers.
--
-- Device-local sync columns (syncStatus/dirtyAt/lastSyncedAt/syncError) are
-- intentionally absent: they are stripped before push.

create table if not exists public.bmk_operational_standards (
  id                       text primary key,
  hatchery_id              text references public.hatcheries(id) on delete cascade,
  station_key              text not null,
  sector_key               text not null,
  metric_key               text not null,
  metric_label             text not null,
  unit                     text default '',
  min_value                double precision,
  max_value                double precision,
  target_value             double precision,
  source                   text,
  source_url               text,
  source_photo_path        text,
  source_photo_remote_path text,
  notes                    text,
  sort_order               integer not null default 0,
  updated_at               text
);

create index if not exists idx_bmk_operational_scope
  on public.bmk_operational_standards (hatchery_id, station_key, sector_key, metric_key);

alter table public.bmk_operational_standards enable row level security;

revoke all on public.bmk_operational_standards from anon;
grant select, insert, update, delete on public.bmk_operational_standards to authenticated;

drop policy if exists bmk_operational_global_read   on public.bmk_operational_standards;
drop policy if exists bmk_operational_global_write  on public.bmk_operational_standards;
drop policy if exists bmk_operational_scoped_read   on public.bmk_operational_standards;
drop policy if exists bmk_operational_scoped_write  on public.bmk_operational_standards;

create policy bmk_operational_global_read
  on public.bmk_operational_standards for select to authenticated
  using (hatchery_id is null);

create policy bmk_operational_global_write
  on public.bmk_operational_standards for all to authenticated
  using (hatchery_id is null and chickmark_private.app_is_admin())
  with check (hatchery_id is null and chickmark_private.app_is_admin());

create policy bmk_operational_scoped_read
  on public.bmk_operational_standards for select to authenticated
  using (
    exists (
      select 1 from public.hatcheries h
      where h.id = hatchery_id
        and chickmark_private.app_can_read_customer(h.customer_id)
    )
  );

create policy bmk_operational_scoped_write
  on public.bmk_operational_standards for all to authenticated
  using (
    exists (
      select 1 from public.hatcheries h
      where h.id = hatchery_id
        and chickmark_private.app_can_write_customer(h.customer_id)
    )
  )
  with check (
    exists (
      select 1 from public.hatcheries h
      where h.id = hatchery_id
        and chickmark_private.app_can_write_customer(h.customer_id)
    )
  );
