create table if not exists public.dashboard_actions (
  id text primary key,
  finding_key text not null,
  customer_id text not null references public.customers(id) on delete cascade,
  hatchery_id text not null references public.hatcheries(id) on delete cascade,
  flock_id text references public.flocks(id) on delete set null,
  session_id text references public.audit_sessions(id) on delete set null,
  panel_name text,
  panel_row_id text,
  field_key text,
  metric_key text,
  title text not null,
  description text,
  priority text not null default 'watch',
  status text not null default 'open',
  owner_id text,
  owner_name text,
  due_at timestamptz,
  first_observed_at timestamptz,
  last_observed_at timestamptz,
  resolved_at timestamptz,
  resolution_notes text,
  resolution_photo_id text,
  recurrence_of_id text,
  created_by text,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create index if not exists idx_dashboard_actions_scope
  on public.dashboard_actions(customer_id, hatchery_id, flock_id, status, updated_at desc);
create index if not exists idx_dashboard_actions_finding
  on public.dashboard_actions(finding_key, updated_at desc);

alter table public.dashboard_actions enable row level security;

drop policy if exists dashboard_actions_read on public.dashboard_actions;
create policy dashboard_actions_read on public.dashboard_actions for select to authenticated
using (public.app_can_read_customer(customer_id));

drop policy if exists dashboard_actions_write on public.dashboard_actions;
create policy dashboard_actions_write on public.dashboard_actions for all to authenticated
using (public.app_can_write_customer(customer_id))
with check (public.app_can_write_customer(customer_id));
