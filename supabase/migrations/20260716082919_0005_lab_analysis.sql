create table if not exists public.lab_analysis_reports (
  id text primary key,
  customer_id text not null references public.customers(id) on delete cascade,
  flock_id text not null references public.flocks(id) on delete cascade,
  report_date timestamptz not null,
  received_date timestamptz,
  lab_name text not null default '',
  sample_type text not null default '',
  flock_age_weeks integer,
  title text,
  notes text,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create index if not exists idx_lab_reports_scope
  on public.lab_analysis_reports(customer_id, flock_id, report_date desc);

create table if not exists public.lab_analysis_groups (
  id text primary key,
  report_id text not null references public.lab_analysis_reports(id) on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  flock_id text not null references public.flocks(id) on delete cascade,
  report_date timestamptz not null,
  test_type text not null,
  group_label text not null default '',
  sample_scope text not null default '',
  analyte text not null default '',
  method text not null default '',
  kit_name text not null default '',
  product_code text not null default '',
  antigen text not null default '',
  sample_count integer,
  mean_titer double precision,
  min_titer double precision,
  max_titer double precision,
  gmt_titer double precision,
  cv_pct double precision,
  positive_count integer,
  negative_count integer,
  positive_pct double precision,
  cutoff_value double precision,
  cutoff_titer double precision,
  gm_log2 double precision,
  protective_threshold_log2 double precision,
  protective_count integer,
  protective_pct double precision,
  interpretation text not null default '',
  severity text not null default 'normal',
  notes text,
  sort_order integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create index if not exists idx_lab_groups_report
  on public.lab_analysis_groups(report_id, sort_order);
create index if not exists idx_lab_groups_dashboard
  on public.lab_analysis_groups(customer_id, flock_id, report_date desc, test_type);

create table if not exists public.lab_analysis_rows (
  id text primary key,
  group_id text not null references public.lab_analysis_groups(id) on delete cascade,
  report_id text not null references public.lab_analysis_reports(id) on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  flock_id text not null references public.flocks(id) on delete cascade,
  report_date timestamptz not null,
  test_type text not null,
  row_label text not null default '',
  analyte text not null default '',
  result text not null default '',
  result_category text not null default '',
  numeric_value double precision,
  unit text not null default '',
  ct_value double precision,
  od_value double precision,
  sp_ratio double precision,
  titer double precision,
  titer_group integer,
  hi_log2 integer,
  count integer,
  antibiotic text not null default '',
  sensitivity_category text not null default '',
  interpretation text not null default '',
  severity text not null default 'normal',
  sort_order integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create index if not exists idx_lab_rows_group
  on public.lab_analysis_rows(group_id, sort_order);
create index if not exists idx_lab_rows_dashboard
  on public.lab_analysis_rows(customer_id, flock_id, report_date desc, test_type);

alter table public.lab_analysis_reports enable row level security;
alter table public.lab_analysis_groups enable row level security;
alter table public.lab_analysis_rows enable row level security;

drop policy if exists lab_analysis_reports_read on public.lab_analysis_reports;
create policy lab_analysis_reports_read on public.lab_analysis_reports for select to authenticated
using (public.app_can_read_customer(customer_id));

drop policy if exists lab_analysis_reports_write on public.lab_analysis_reports;
create policy lab_analysis_reports_write on public.lab_analysis_reports for all to authenticated
using (public.app_can_write_customer(customer_id))
with check (public.app_can_write_customer(customer_id));

drop policy if exists lab_analysis_groups_read on public.lab_analysis_groups;
create policy lab_analysis_groups_read on public.lab_analysis_groups for select to authenticated
using (public.app_can_read_customer(customer_id));

drop policy if exists lab_analysis_groups_write on public.lab_analysis_groups;
create policy lab_analysis_groups_write on public.lab_analysis_groups for all to authenticated
using (public.app_can_write_customer(customer_id))
with check (public.app_can_write_customer(customer_id));

drop policy if exists lab_analysis_rows_read on public.lab_analysis_rows;
create policy lab_analysis_rows_read on public.lab_analysis_rows for select to authenticated
using (public.app_can_read_customer(customer_id));

drop policy if exists lab_analysis_rows_write on public.lab_analysis_rows;
create policy lab_analysis_rows_write on public.lab_analysis_rows for all to authenticated
using (public.app_can_write_customer(customer_id))
with check (public.app_can_write_customer(customer_id));
