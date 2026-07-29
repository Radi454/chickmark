begin;

alter table public.agent_intake_sessions
  drop constraint if exists agent_intake_sessions_scope_check,
  add constraint agent_intake_sessions_scope_check
  check (
    scope is null
    or scope in (
      'pool',
      'house',
      'setter',
      'hatcher',
      'setter_hatcher',
      'trolley',
      'tray'
    )
  );

create or replace function public.approve_agent_intake(
  p_intake_id text,
  p_expected_summary_version integer,
  p_target_session_id text,
  p_remote_table text,
  p_station_key text,
  p_panel_row_id text,
  p_panel_payload jsonb,
  p_reviewer_id text,
  p_approved_at text
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
  v_approved_session_id text;
  panel_payload jsonb;
begin
  if current_user <> 'service_role' then
    raise exception 'Service role approval is required'
      using errcode = '42501';
  end if;
  if p_remote_table not in (
    'egg_storage',
    'egg_quality',
    'chick_quality',
    'chick_weights',
    'fresh_egg_breakout',
    'candled_egg_breakout',
    'residue_breakout',
    'setter_optimizing',
    'hatcher_optimizing'
  ) then
    raise exception 'Unsupported station persistence table';
  end if;
  if p_station_key not in (
    'egg_storage',
    'egg_quality',
    'chicks',
    'hatch_analysis',
    'setters',
    'hatchers'
  ) then
    raise exception 'Unsupported station key';
  end if;
  if p_panel_payload is null or jsonb_typeof(p_panel_payload) <> 'object' then
    raise exception 'Panel payload must be a JSON object';
  end if;

  select *
    into intake
    from public.agent_intake_sessions
    where id = p_intake_id
    for update;
  if not found then
    raise exception 'Agent intake does not exist'
      using errcode = 'P0002';
  end if;

  if
    intake.summary_version <> p_expected_summary_version
    or (intake.summary_snapshot_json ->> 'version')::integer
      <> p_expected_summary_version
  then
    raise exception 'Agent intake summary version is stale'
      using errcode = '40001';
  end if;

  if intake.approved_panel_row_id is not null then
    if
      p_target_session_id is not null
      and p_target_session_id is distinct from intake.approved_session_id
    then
      raise exception 'Agent intake was approved to another audit session';
    end if;
    return query select
      intake.id,
      intake.approved_session_id,
      intake.approved_panel_row_id,
      true;
    return;
  end if;

  if
    intake.state <> 'awaiting_admin_review'
    or intake.user_confirmed_at is null
    or intake.summary_snapshot_json is null
  then
    raise exception 'Agent intake is not ready for administrator review';
  end if;
  if
    intake.customer_id is null
    or intake.flock_id is null
    or intake.hatchery_id is null
  then
    raise exception 'Agent intake context is incomplete';
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
      jsonb_build_array(p_station_key)::text,
      jsonb_build_array(p_station_key)::text,
      p_reviewer_id,
      p_approved_at,
      p_approved_at
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
      target_session.customer_id is distinct from intake.customer_id
      or target_session.flock_id is distinct from intake.flock_id
      or target_session.hatchery_id is distinct from intake.hatchery_id
      or target_session.date is distinct from intake.audit_date
    then
      raise exception 'Target audit session does not match intake context';
    end if;
    v_approved_session_id := target_session.id;
  end if;

  update public.audit_sessions
  set
    selected_station_keys = (
      select jsonb_agg(value order by value)::text
      from (
        select distinct value
        from jsonb_array_elements_text(
          coalesce(
            nullif(selected_station_keys, '')::jsonb,
            '[]'::jsonb
          ) || jsonb_build_array(p_station_key)
        ) values(value)
      ) unique_values
    ),
    stations_completed = (
      select jsonb_agg(value order by value)::text
      from (
        select distinct value
        from jsonb_array_elements_text(
          coalesce(
            nullif(stations_completed, '')::jsonb,
            '[]'::jsonb
          ) || jsonb_build_array(p_station_key)
        ) values(value)
      ) unique_values
    ),
    updated_at = p_approved_at
  where id = v_approved_session_id;

  panel_payload := p_panel_payload || jsonb_build_object(
    'id', p_panel_row_id,
    'session_id', v_approved_session_id,
    'customer_id', intake.customer_id,
    'flock_id', intake.flock_id,
    'hatchery_id', intake.hatchery_id,
    'date', intake.audit_date,
    'created_at', p_approved_at,
    'updated_at', p_approved_at,
    'sync_status', 'synced',
    'last_synced_at', p_approved_at
  );

  execute format(
    'insert into public.%I '
    'select * from jsonb_populate_record(null::public.%I, $1)',
    p_remote_table,
    p_remote_table
  ) using panel_payload;

  update public.agent_intake_sessions
  set
    state = 'approved',
    approved_session_id = v_approved_session_id,
    approved_panel_row_id = p_panel_row_id,
    reviewed_by = p_reviewer_id,
    reviewed_at = p_approved_at,
    rejection_reason = null,
    updated_at = p_approved_at
  where id = intake.id;

  update public.agent_intake_visits visit
  set
    approved_session_id = v_approved_session_id,
    state = case
      when exists (
        select 1
        from public.agent_intake_sessions other
        where other.visit_id = visit.id
          and other.id <> intake.id
          and other.state = 'awaiting_admin_review'
      ) then 'awaiting_admin_review'
      else 'completed'
    end,
    updated_at = p_approved_at
  where visit.id = intake.visit_id;

  return query select
    intake.id,
    v_approved_session_id,
    p_panel_row_id,
    false;
end;
$$;

revoke all on function public.approve_agent_intake(
  text,
  integer,
  text,
  text,
  text,
  text,
  jsonb,
  text,
  text
) from public, anon, authenticated;
grant execute on function public.approve_agent_intake(
  text,
  integer,
  text,
  text,
  text,
  text,
  jsonb,
  text,
  text
) to service_role;

commit;
