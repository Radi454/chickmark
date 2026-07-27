-- Required Edge Function secrets:
-- TELEGRAM_BOT_TOKEN: regenerated bot token from BotFather.
-- TELEGRAM_WEBHOOK_SECRET: random 32+ character value used with Telegram
-- setWebhook secret_token.
-- OPENAI_API_KEY: OpenAI API key used only by the Edge Function.
-- Deploy telegram-hatchery-agent without Supabase JWT verification; the
-- function authenticates each webhook with Telegram's secret-token header.

begin;

create table public.telegram_staff_links (
  id text primary key,
  telegram_user_id text not null unique,
  telegram_chat_id text,
  display_name text,
  username text,
  status text not null default 'allowed'
    check (status in ('allowed', 'revoked')),
  invited_by text,
  created_at text,
  updated_at text
);

create table public.agent_settings (
  id integer primary key check (id = 1),
  telegram_enabled integer not null default 1
    check (telegram_enabled in (0, 1)),
  hatchability_warning_threshold_points double precision not null default 3.0,
  minimum_ready_confidence_pct double precision not null default 85.0,
  updated_at text
);

create table public.agent_submissions (
  id text primary key,
  telegram_update_id text unique,
  telegram_message_id text,
  telegram_chat_id text,
  telegram_user_id text,
  staff_link_id text
    references public.telegram_staff_links(id) on delete set null,
  source_kind text not null
    check (source_kind in ('text', 'image', 'pdf', 'spreadsheet', 'file')),
  source_text text,
  source_file_name text,
  source_mime_type text,
  source_remote_path text,
  status text not null check (status in (
    'received', 'processing', 'waiting_for_staff_answer', 'draft_ready',
    'needs_admin_review', 'partially_approved', 'approved', 'rejected', 'failed'
  )),
  error_message text,
  submitted_at text not null,
  processed_at text,
  created_at text,
  updated_at text
);
create index idx_agent_submissions_status
  on public.agent_submissions(status, submitted_at desc);
create index idx_agent_submissions_staff
  on public.agent_submissions(staff_link_id)
  where staff_link_id is not null;

create table public.agent_questions (
  id text primary key,
  submission_id text not null
    references public.agent_submissions(id) on delete cascade,
  row_ordinal integer,
  field_key text not null,
  question_text_en text not null,
  question_text_ar text not null,
  status text not null default 'open'
    check (status in ('open', 'answered', 'closed')),
  answer_text text,
  answered_at text,
  created_at text,
  updated_at text
);
create index idx_agent_questions_submission
  on public.agent_questions(submission_id, status);

create table public.hatchery_draft_batches (
  id text primary key,
  submission_id text not null
    references public.agent_submissions(id) on delete cascade,
  status text not null check (status in (
    'received', 'processing', 'waiting_for_staff_answer', 'draft_ready',
    'needs_admin_review', 'partially_approved', 'approved', 'rejected', 'failed'
  )),
  source_summary text,
  created_at text,
  updated_at text
);
create index idx_hatchery_draft_batches_submission
  on public.hatchery_draft_batches(submission_id);

create table public.hatchery_draft_rows (
  id text primary key,
  batch_id text not null
    references public.hatchery_draft_batches(id) on delete cascade,
  row_ordinal integer not null,
  status text not null
    check (status in ('pending', 'needs_review', 'approved', 'rejected')),
  customer_id text references public.customers(id) on delete set null,
  customer_name text,
  flock_id text references public.flocks(id) on delete set null,
  flock_name text,
  hatchery_id text references public.hatcheries(id) on delete set null,
  station_name text,
  breed text,
  eggs_placed integer,
  production_date text,
  placement_date text,
  egg_weight_g double precision,
  fertility_pct double precision,
  transfer_weight_g double precision,
  setter_number text,
  hatcher_number text,
  hatch_date text,
  healthy_chicks integer,
  second_grade_chicks integer,
  condemned_chicks integer,
  total_production integer,
  hatchability_pct double precision,
  confidence_pct double precision,
  extraction_json text,
  warnings_json text,
  proposed_flock_age_weeks integer,
  approved_record_id text,
  reviewed_by text,
  reviewed_at text,
  created_at text,
  updated_at text
);
create index idx_hatchery_draft_rows_batch
  on public.hatchery_draft_rows(batch_id, row_ordinal);
create index idx_hatchery_draft_rows_customer
  on public.hatchery_draft_rows(customer_id)
  where customer_id is not null;
create index idx_hatchery_draft_rows_flock
  on public.hatchery_draft_rows(flock_id)
  where flock_id is not null;
create index idx_hatchery_draft_rows_hatchery
  on public.hatchery_draft_rows(hatchery_id)
  where hatchery_id is not null;

create table public.hatchery_agent_audit_events (
  id text primary key,
  submission_id text not null
    references public.agent_submissions(id) on delete cascade,
  row_id text
    references public.hatchery_draft_rows(id) on delete set null,
  actor_type text not null,
  actor_id text,
  event_type text not null,
  details_json text,
  created_at text not null
);
create index idx_hatchery_agent_audit_submission
  on public.hatchery_agent_audit_events(submission_id, created_at);
create index idx_hatchery_agent_audit_row
  on public.hatchery_agent_audit_events(row_id)
  where row_id is not null;

create table public.hatchery_daily_records (
  id text primary key,
  source_draft_row_id text
    references public.hatchery_draft_rows(id) on delete set null,
  customer_id text not null
    references public.customers(id) on delete cascade,
  flock_id text not null
    references public.flocks(id) on delete cascade,
  hatchery_id text
    references public.hatcheries(id) on delete set null,
  station_name text not null,
  breed text not null,
  eggs_placed integer not null,
  production_date text,
  placement_date text,
  egg_weight_g double precision,
  fertility_pct double precision,
  transfer_weight_g double precision,
  setter_number text,
  hatcher_number text,
  hatch_date text not null,
  healthy_chicks integer,
  second_grade_chicks integer,
  condemned_chicks integer,
  total_production integer not null,
  hatchability_pct double precision not null,
  approved_by text,
  approved_at text,
  created_at text,
  updated_at text
);
create index idx_hatchery_daily_records_comparable
  on public.hatchery_daily_records
  (customer_id, flock_id, station_name, breed, hatch_date desc);
create index idx_hatchery_daily_records_hatchery
  on public.hatchery_daily_records(hatchery_id)
  where hatchery_id is not null;
create index idx_hatchery_daily_records_source
  on public.hatchery_daily_records(source_draft_row_id)
  where source_draft_row_id is not null;

create or replace function chickmark_private.validate_hatchery_agent_scope()
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

  if new.flock_id is not null then
    select flock.customer_id into linked_customer_id
      from public.flocks as flock where flock.id = new.flock_id;
    if linked_customer_id is null then
      raise exception 'Hatchery agent flock does not exist'
        using errcode = '23503';
    end if;
    if resolved_customer_id is null then
      resolved_customer_id := linked_customer_id;
    elsif linked_customer_id is distinct from resolved_customer_id then
      raise exception 'Hatchery agent flock crosses customer scope'
        using errcode = '23514';
    end if;
  end if;

  if new.hatchery_id is not null then
    select hatchery.customer_id into linked_customer_id
      from public.hatcheries as hatchery where hatchery.id = new.hatchery_id;
    if linked_customer_id is null then
      raise exception 'Hatchery agent hatchery does not exist'
        using errcode = '23503';
    end if;
    if resolved_customer_id is null then
      resolved_customer_id := linked_customer_id;
    elsif linked_customer_id is distinct from resolved_customer_id then
      raise exception 'Hatchery agent hatchery crosses customer scope'
        using errcode = '23514';
    end if;
  end if;

  new.customer_id := resolved_customer_id;
  return new;
end;
$$;

revoke all on function chickmark_private.validate_hatchery_agent_scope()
  from public, anon, authenticated;

create trigger hatchery_draft_rows_validate_scope
  before insert or update of customer_id, flock_id, hatchery_id
  on public.hatchery_draft_rows
  for each row execute function
    chickmark_private.validate_hatchery_agent_scope();

create trigger hatchery_daily_records_validate_scope
  before insert or update of customer_id, flock_id, hatchery_id
  on public.hatchery_daily_records
  for each row execute function
    chickmark_private.validate_hatchery_agent_scope();

alter table public.telegram_staff_links enable row level security;
alter table public.agent_settings enable row level security;
alter table public.agent_submissions enable row level security;
alter table public.agent_questions enable row level security;
alter table public.hatchery_draft_batches enable row level security;
alter table public.hatchery_draft_rows enable row level security;
alter table public.hatchery_agent_audit_events enable row level security;
alter table public.hatchery_daily_records enable row level security;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'telegram_staff_links',
    'agent_settings',
    'agent_submissions',
    'agent_questions',
    'hatchery_draft_batches',
    'hatchery_draft_rows',
    'hatchery_agent_audit_events',
    'hatchery_daily_records'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (chickmark_private.app_is_admin())',
      table_name || '_admin_select',
      table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (chickmark_private.app_is_admin())',
      table_name || '_admin_insert',
      table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (chickmark_private.app_is_admin()) '
      'with check (chickmark_private.app_is_admin())',
      table_name || '_admin_update',
      table_name
    );
    execute format(
      'revoke all on public.%I from anon',
      table_name
    );
    execute format(
      'grant select, insert, update on public.%I to authenticated',
      table_name
    );
    execute format(
      'grant all on public.%I to service_role',
      table_name
    );
  end loop;
end
$$;

commit;
