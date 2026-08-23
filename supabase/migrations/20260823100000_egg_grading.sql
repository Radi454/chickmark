-- v62: visual egg grading, owned by an egg_quality sample row.
alter table public.egg_quality
  add column if not exists grading_sample_size integer,
  add column if not exists grading_rejected_count integer,
  add column if not exists grading_acceptable_count integer,
  add column if not exists grading_rejected_pct double precision,
  add column if not exists grading_acceptable_pct double precision,
  add column if not exists grading_defects_json text,
  add column if not exists grading_top_defect_code text,
  add column if not exists grading_top_defect_pct double precision;

create table if not exists public.egg_quality_defect_counts (
  id text primary key,
  egg_quality_id text not null,
  session_id text not null,
  customer_id text not null,
  flock_id text,
  hatchery_id text,
  date text not null,
  scope_type text,
  house_key text,
  sample_label text,
  defect_code text not null,
  defect_category text,
  is_reject integer,
  count integer not null default 0,
  pct_of_sample double precision,
  notes text,
  sort_order integer not null default 0,
  created_at text not null,
  updated_at text not null,
  unique (egg_quality_id, defect_code),
  foreign key (egg_quality_id) references public.egg_quality(id) on delete cascade,
  foreign key (session_id) references public.audit_sessions(id) on delete cascade,
  foreign key (customer_id) references public.customers(id) on delete cascade,
  foreign key (flock_id) references public.flocks(id) on delete cascade
);

create index if not exists idx_eqdc_parent
  on public.egg_quality_defect_counts(egg_quality_id);
create index if not exists idx_eqdc_dashboard
  on public.egg_quality_defect_counts(customer_id, flock_id, date, defect_code);

alter table public.egg_quality_defect_counts enable row level security;
create policy authenticated_all on public.egg_quality_defect_counts
  for all to authenticated using (true) with check (true);

-- Derive/validate customer_id from the parent egg_quality row, matching the
-- shape of chickmark_private.validate_hatchery_agent_scope() (see
-- supabase/migrations/20260726100000_telegram_hatchery_agent.sql): resolve
-- customer_id from the parent edge when unset, and reject any write whose
-- explicit customer_id crosses the parent's tenant scope.
create or replace function chickmark_private.validate_egg_quality_defect_counts_scope()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  resolved_customer_id text;
  linked_customer_id text;
begin
  resolved_customer_id := new.customer_id;

  select egg_quality.customer_id into linked_customer_id
    from public.egg_quality as egg_quality
    where egg_quality.id = new.egg_quality_id;
  if linked_customer_id is null then
    raise exception 'Egg quality defect count parent sample does not exist'
      using errcode = '23503';
  end if;
  if resolved_customer_id is null then
    resolved_customer_id := linked_customer_id;
  elsif linked_customer_id is distinct from resolved_customer_id then
    raise exception 'Egg quality defect count crosses customer scope'
      using errcode = '23514';
  end if;

  new.customer_id := resolved_customer_id;
  return new;
end;
$$;

revoke all on function chickmark_private.validate_egg_quality_defect_counts_scope()
  from public, anon, authenticated;

create trigger egg_quality_defect_counts_validate_scope
  before insert or update of customer_id, egg_quality_id
  on public.egg_quality_defect_counts
  for each row execute function
    chickmark_private.validate_egg_quality_defect_counts_scope();
