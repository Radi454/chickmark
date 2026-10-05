-- Physical setter/hatcher catalog rows belong to one customer-scoped hatchery.
create table public.hatchery_machines (
  id                text primary key,
  hatchery_id       text not null references public.hatcheries(id) on delete cascade,
  kind              text not null check (kind in ('setter', 'hatcher')),
  code              text not null check (length(btrim(code)) > 0),
  name              text not null check (length(btrim(name)) > 0),
  batch_size        integer not null check (batch_size > 0),
  trolley_capacity  integer not null check (trolley_capacity > 0),
  tray_size         integer not null check (tray_size > 0),
  trolley_count     integer not null check (trolley_count > 0),
  trays_per_trolley integer not null check (trays_per_trolley > 0),
  created_at        text,
  updated_at        text,
  created_by        text
);

create index idx_hatchery_machines_hatchery_kind
  on public.hatchery_machines (hatchery_id, kind);
create unique index idx_hatchery_machines_code
  on public.hatchery_machines (hatchery_id, kind, upper(btrim(code)));

alter table public.hatchery_machines enable row level security;
revoke all on table public.hatchery_machines from anon, authenticated;
grant select, insert, update, delete on table public.hatchery_machines
  to authenticated;
grant select, insert, update, delete on table public.hatchery_machines
  to service_role;

create policy hatchery_machines_select
  on public.hatchery_machines for select to authenticated
  using (
    exists (
      select 1
      from public.hatcheries h
      where h.id = hatchery_id
        and chickmark_private.app_can_read_customer(h.customer_id)
    )
  );

create policy hatchery_machines_insert
  on public.hatchery_machines for insert to authenticated
  with check (
    exists (
      select 1
      from public.hatcheries h
      where h.id = hatchery_id
        and chickmark_private.app_can_write_customer(h.customer_id)
    )
  );

create policy hatchery_machines_update
  on public.hatchery_machines for update to authenticated
  using (
    exists (
      select 1
      from public.hatcheries h
      where h.id = hatchery_id
        and chickmark_private.app_can_write_customer(h.customer_id)
    )
  )
  with check (
    exists (
      select 1
      from public.hatcheries h
      where h.id = hatchery_id
        and chickmark_private.app_can_write_customer(h.customer_id)
    )
  );

create policy hatchery_machines_delete
  on public.hatchery_machines for delete to authenticated
  using (
    exists (
      select 1
      from public.hatcheries h
      where h.id = hatchery_id
        and chickmark_private.app_can_write_customer(h.customer_id)
    )
  );
