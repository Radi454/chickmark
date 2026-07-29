begin;

create table public.agent_intake_sessions (
  id text primary key,
  staff_link_id text not null
    references public.telegram_staff_links(id) on delete cascade,
  telegram_chat_id text not null,
  schema_key text not null,
  schema_version integer not null,
  state text not null check (state in (
    'collecting',
    'awaiting_clarification',
    'paused',
    'ready_for_summary',
    'awaiting_user_confirmation',
    'awaiting_admin_review',
    'approved',
    'rejected',
    'cancelled'
  )),
  language text not null check (language in ('en', 'ar', 'mixed')),
  customer_id text references public.customers(id) on delete set null,
  customer_name text,
  flock_id text references public.flocks(id) on delete set null,
  flock_name text,
  hatchery_id text references public.hatcheries(id) on delete set null,
  hatchery_name text,
  audit_date text not null,
  scope text check (scope is null or scope in ('pool', 'setter_hatcher')),
  setter_identity text,
  hatcher_identity text,
  working_values_json jsonb not null default '{}'::jsonb,
  pending_clarification_json jsonb,
  summary_version integer not null default 0,
  summary_snapshot_json jsonb,
  user_confirmed_at text,
  approved_session_id text
    references public.audit_sessions(id) on delete set null,
  approved_panel_row_id text,
  reviewed_by text,
  reviewed_at text,
  rejection_reason text,
  created_at text not null,
  updated_at text not null
);

create unique index idx_agent_intake_sessions_active
  on public.agent_intake_sessions(staff_link_id, telegram_chat_id)
  where state in (
    'collecting',
    'awaiting_clarification',
    'paused',
    'ready_for_summary',
    'awaiting_user_confirmation'
  );
create index idx_agent_intake_sessions_review
  on public.agent_intake_sessions(state, updated_at desc);
create index idx_agent_intake_sessions_customer
  on public.agent_intake_sessions(customer_id)
  where customer_id is not null;

create table public.agent_intake_turns (
  id text primary key,
  intake_session_id text not null
    references public.agent_intake_sessions(id) on delete cascade,
  direction text not null check (direction in ('inbound', 'outbound')),
  telegram_update_id text unique,
  telegram_message_id text,
  text text not null,
  language text not null check (language in ('en', 'ar', 'mixed')),
  intent text,
  delivery_status text,
  attachment_kind text,
  attachment_file_name text,
  attachment_mime_type text,
  attachment_remote_path text,
  created_at text not null
);
create index idx_agent_intake_turns_session
  on public.agent_intake_turns(intake_session_id, created_at, id);

create table public.agent_intake_values (
  id text primary key,
  intake_session_id text not null
    references public.agent_intake_sessions(id) on delete cascade,
  field_key text not null,
  value_json jsonb not null,
  source_phrase text not null,
  confidence double precision not null
    check (confidence >= 0 and confidence <= 1),
  clarification_reason text,
  created_at text not null,
  updated_at text not null,
  unique (intake_session_id, field_key)
);
create index idx_agent_intake_values_session
  on public.agent_intake_values(intake_session_id, field_key);

alter table public.agent_intake_sessions enable row level security;
alter table public.agent_intake_turns enable row level security;
alter table public.agent_intake_values enable row level security;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'agent_intake_sessions',
    'agent_intake_turns',
    'agent_intake_values'
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
      'revoke all on public.%I from public, anon',
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

create or replace function public.approve_pasgar_intake(
  p_intake_id text,
  p_target_session_id text default null
)
  returns table (
    intake_id text,
    audit_session_id text,
    panel_row_id text,
    already_approved boolean
  )
  language plpgsql
  security invoker
  set search_path = ''
as $$
declare
  intake public.agent_intake_sessions%rowtype;
  target_session public.audit_sessions%rowtype;
  values_json jsonb;
  sample_size integer;
  reflexes_count integer;
  beak_count integer;
  navel_count integer;
  belly_count integer;
  leg_count integer;
  feather_dev_count integer;
  v_approved_session_id text;
  v_approved_panel_id text;
  approved_at text := clock_timestamp()::text;
begin
  if not chickmark_private.app_is_admin() then
    raise exception 'Approved administrator access is required'
      using errcode = '42501';
  end if;

  select *
    into intake
    from public.agent_intake_sessions
    where id = p_intake_id
    for update;
  if not found then
    raise exception 'Pasgar intake does not exist'
      using errcode = 'P0002';
  end if;

  if intake.approved_panel_row_id is not null then
    return query select
      intake.id,
      intake.approved_session_id,
      intake.approved_panel_row_id,
      true;
    return;
  end if;

  if intake.schema_key <> 'chicks.pasgar' or intake.schema_version <> 1 then
    raise exception 'Unsupported Pasgar intake schema';
  end if;
  if intake.state <> 'awaiting_admin_review' then
    raise exception 'Pasgar intake is not ready for admin review';
  end if;
  if intake.user_confirmed_at is null or intake.summary_snapshot_json is null then
    raise exception 'Pasgar intake has no confirmed summary';
  end if;
  if
    (intake.summary_snapshot_json ->> 'version')::integer
      <> intake.summary_version
  then
    raise exception 'Pasgar summary version is stale';
  end if;
  if
    intake.customer_id is null or intake.flock_id is null or
    intake.hatchery_id is null or intake.scope is null
  then
    raise exception 'Pasgar intake context is incomplete';
  end if;
  if
    intake.scope = 'setter_hatcher' and
    (intake.setter_identity is null or intake.hatcher_identity is null)
  then
    raise exception 'Setter/Hatcher scope requires both identities';
  end if;

  -- Keep the customer's confirmed summary immutable as evidence. Admin review
  -- corrections are written to working_values_json and are the values promoted
  -- into the operational record.
  values_json := intake.working_values_json;
  if values_json is null or jsonb_typeof(values_json) <> 'object' then
    raise exception 'Pasgar summary values are invalid';
  end if;

  sample_size := (values_json ->> 'pasgarSampleSize')::integer;
  reflexes_count := (values_json ->> 'pasgarReflexesCount')::integer;
  beak_count := (values_json ->> 'pasgarBeakCount')::integer;
  navel_count := (values_json ->> 'pasgarNavelCount')::integer;
  belly_count := (values_json ->> 'pasgarBellyCount')::integer;
  leg_count := (values_json ->> 'pasgarLegCount')::integer;
  feather_dev_count := (values_json ->> 'pasgarFeatherDevCount')::integer;

  if
    sample_size is null or reflexes_count is null or beak_count is null or
    navel_count is null or belly_count is null or leg_count is null or
    feather_dev_count is null
  then
    raise exception 'Every Pasgar measurement must be explicit';
  end if;
  if sample_size < 1 or sample_size > 500 then
    raise exception 'Pasgar sample size must be between 1 and 500';
  end if;
  if
    reflexes_count not between 0 and sample_size or
    beak_count not between 0 and sample_size or
    navel_count not between 0 and sample_size or
    belly_count not between 0 and sample_size or
    leg_count not between 0 and sample_size or
    feather_dev_count not between 0 and sample_size
  then
    raise exception 'Pasgar defect counts must fit the sample';
  end if;

  if p_target_session_id is null then
    v_approved_session_id := gen_random_uuid()::text;
    insert into public.audit_sessions (
      id,
      customer_id,
      flock_id,
      hatchery_id,
      date,
      status,
      selected_station_keys,
      stations_completed,
      created_by,
      created_at,
      updated_at
    ) values (
      v_approved_session_id,
      intake.customer_id,
      intake.flock_id,
      intake.hatchery_id,
      intake.audit_date,
      'in_progress',
      '["chicks"]',
      '["chicks"]',
      (select auth.uid())::text,
      approved_at,
      approved_at
    );
  else
    select *
      into target_session
      from public.audit_sessions
      where id = p_target_session_id
      for update;
    if not found then
      raise exception 'Target audit session does not exist'
        using errcode = 'P0002';
    end if;
    if
      target_session.customer_id is distinct from intake.customer_id or
      target_session.flock_id is distinct from intake.flock_id or
      target_session.hatchery_id is distinct from intake.hatchery_id or
      target_session.date is distinct from intake.audit_date
    then
      raise exception 'Target audit session does not match intake context';
    end if;
    v_approved_session_id := target_session.id;
  end if;

  update public.audit_sessions
  set
    selected_station_keys = (
      select jsonb_agg(station_key order by station_key)::text
      from (
        select jsonb_array_elements_text(
          coalesce(nullif(selected_station_keys, '')::jsonb, '[]'::jsonb)
        ) as station_key
        union
        select 'chicks'
      ) selected_stations
    ),
    stations_completed = (
      select jsonb_agg(station_key order by station_key)::text
      from (
        select jsonb_array_elements_text(
          coalesce(nullif(stations_completed, '')::jsonb, '[]'::jsonb)
        ) as station_key
        union
        select 'chicks'
      ) completed_stations
    ),
    updated_at = approved_at
  where id = v_approved_session_id;

  v_approved_panel_id := gen_random_uuid()::text;
  insert into public.chick_quality (
    id,
    session_id,
    customer_id,
    flock_id,
    hatchery_id,
    date,
    setter,
    hatcher,
    notes,
    created_at,
    updated_at,
    sync_status,
    last_synced_at,
    pasgar_sample_size,
    pasgar_reflexes_count,
    pasgar_beak_count,
    pasgar_navel_count,
    pasgar_belly_count,
    pasgar_leg_count,
    pasgar_feather_dev_count,
    pasgar_reflexes_pct,
    pasgar_beak_pct,
    pasgar_navel_pct,
    pasgar_belly_pct,
    pasgar_leg_pct,
    pasgar_feather_dev_pct,
    pasgar_final_score
  ) values (
    v_approved_panel_id,
    v_approved_session_id,
    intake.customer_id,
    intake.flock_id,
    intake.hatchery_id,
    intake.audit_date,
    case when intake.scope = 'setter_hatcher'
      then intake.setter_identity else null end,
    case when intake.scope = 'setter_hatcher'
      then intake.hatcher_identity else null end,
    'Conversational Pasgar intake ' || intake.id,
    approved_at,
    approved_at,
    'synced',
    approved_at,
    sample_size,
    reflexes_count,
    beak_count,
    navel_count,
    belly_count,
    leg_count,
    feather_dev_count,
    round((reflexes_count::numeric / sample_size) * 100, 1),
    round((beak_count::numeric / sample_size) * 100, 1),
    round((navel_count::numeric / sample_size) * 100, 1),
    round((belly_count::numeric / sample_size) * 100, 1),
    round((leg_count::numeric / sample_size) * 100, 1),
    round((feather_dev_count::numeric / sample_size) * 100, 1),
    round(
      greatest(
        5::numeric,
        least(
          10::numeric,
          (
            (sample_size * 10) -
            (
              reflexes_count + beak_count + navel_count +
              belly_count + leg_count
            )
          )::numeric / sample_size
        )
      ),
      1
    )
  );

  update public.agent_intake_sessions
  set
    state = 'approved',
    approved_session_id = v_approved_session_id,
    approved_panel_row_id = v_approved_panel_id,
    reviewed_by = (select auth.uid())::text,
    reviewed_at = approved_at,
    updated_at = approved_at
  where id = intake.id;

  return query select
    intake.id,
    v_approved_session_id,
    v_approved_panel_id,
    false;
end;
$$;

revoke execute on function public.approve_pasgar_intake(text, text)
  from public, anon;
grant execute on function public.approve_pasgar_intake(text, text)
  to authenticated;

commit;
