-- Phase 4: normalized Chick observations. Migration file only; do not apply to
-- a live project from the development workflow.
create table if not exists public.chick_quality_observation (
  id text primary key,
  sample_id text not null,
  customer_id text not null,
  session_id text not null,
  domain text not null,
  kind text not null check (kind in ('series', 'tally', 'ordinal')),
  observation_key text not null check (length(btrim(observation_key)) > 0),
  ordinal integer check (ordinal is null or ordinal >= 0),
  numeric_value double precision,
  text_value text,
  unit text not null,
  quality_flags text not null default '[]',
  source text,
  observed_at text not null,
  created_at text not null,
  updated_at text not null,
  sync_status text not null default 'pending',
  dirty_at text,
  last_synced_at text,
  sync_error text,
  check ((numeric_value is not null) <> (text_value is not null))
);

create unique index if not exists idx_chick_observation_identity
  on public.chick_quality_observation (
    sample_id, domain, kind, observation_key, coalesce(ordinal, -1)
  );
create index if not exists idx_chick_observation_sample
  on public.chick_quality_observation (sample_id);
create index if not exists idx_chick_observation_session
  on public.chick_quality_observation (session_id);
create index if not exists idx_chick_observation_customer
  on public.chick_quality_observation (customer_id, observed_at);

create or replace function public.enforce_chick_observation_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_customer text;
  owner_session text;
  owner_domain text;
begin
  if tg_op = 'UPDATE' and (
    old.id is distinct from new.id
    or old.sample_id is distinct from new.sample_id
    or old.domain is distinct from new.domain
    or old.kind is distinct from new.kind
    or old.observation_key is distinct from new.observation_key
    or old.ordinal is distinct from new.ordinal
  ) then
    raise exception 'Chick observation identity is immutable';
  end if;
  if new.domain = 'chicks.weights' then
    select customer_id, session_id, domain
      into owner_customer, owner_session, owner_domain
      from public.chick_weights where id = new.sample_id;
  else
    select customer_id, session_id, domain
      into owner_customer, owner_session, owner_domain
      from public.chick_quality where id = new.sample_id;
  end if;

  if not found then
    raise exception 'Chick observation owner does not exist';
  end if;
  if owner_customer is distinct from new.customer_id
     or owner_session is distinct from new.session_id
     or owner_domain is distinct from new.domain then
    raise exception 'Chick observation owner metadata mismatch';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_chick_observation_owner() from public;
drop trigger if exists enforce_chick_observation_owner
  on public.chick_quality_observation;
create trigger enforce_chick_observation_owner
before insert or update on public.chick_quality_observation
for each row execute function public.enforce_chick_observation_owner();

create or replace function public.delete_owned_chick_observations()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  delete from public.chick_quality_observation
  where sample_id = old.id
    and domain = case when tg_table_name = 'chick_weights'
      then 'chicks.weights' else old.domain end;
  return old;
end;
$$;

revoke all on function public.delete_owned_chick_observations() from public;
drop trigger if exists delete_owned_chick_observations
  on public.chick_quality;
create trigger delete_owned_chick_observations
before delete on public.chick_quality
for each row execute function public.delete_owned_chick_observations();
drop trigger if exists delete_owned_chick_weight_observations
  on public.chick_weights;
create trigger delete_owned_chick_weight_observations
before delete on public.chick_weights
for each row execute function public.delete_owned_chick_observations();

alter table public.chick_quality_observation enable row level security;
drop policy if exists chick_quality_observation_select
  on public.chick_quality_observation;
create policy chick_quality_observation_select
on public.chick_quality_observation for select to authenticated
using (chickmark_private.app_can_read_customer(customer_id));
drop policy if exists chick_quality_observation_write
  on public.chick_quality_observation;
create policy chick_quality_observation_write
on public.chick_quality_observation for all to authenticated
using (chickmark_private.app_can_write_customer(customer_id))
with check (chickmark_private.app_can_write_customer(customer_id));

alter table public.photos add column if not exists observation_id text;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'photos_observation_id_fkey'
      and conrelid = 'public.photos'::regclass
  ) then
    alter table public.photos
      add constraint photos_observation_id_fkey
      foreign key (observation_id)
      references public.chick_quality_observation(id) on delete set null;
  end if;
end $$;

create or replace function public.enforce_photo_observation_owner()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.observation_id is not null and not exists (
    select 1 from public.chick_quality_observation o
    where o.id = new.observation_id
      and o.sample_id = new.panel_row_id
      and o.session_id = new.session_id
      and o.domain <> 'chicks.weights'
      and new.panel_name = 'chick_quality'
  ) then
    raise exception 'Photo observation owner mismatch';
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_photo_observation_owner() from public;
drop trigger if exists enforce_photo_observation_owner on public.photos;
create trigger enforce_photo_observation_owner
before insert or update of observation_id, panel_row_id, session_id, panel_name
on public.photos
for each row execute function public.enforce_photo_observation_owner();

grant select, insert, update, delete
  on public.chick_quality_observation to authenticated;

-- Keep agent approval parent + raw observations in one database transaction.
-- The existing approval function still owns all intake/session locking and
-- identity allocation; this wrapper adds only the Phase-4 child insert.
create or replace function public.approve_agent_intake_v2(
  p_intake_id text,
  p_expected_summary_version integer,
  p_target_session_id text,
  p_remote_table text,
  p_station_key text,
  p_panel_row_id text,
  p_panel_payload jsonb,
  p_reviewer_id text,
  p_approved_at text,
  p_observations jsonb
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
  approval record;
  raw_observation jsonb;
  observation_payload jsonb;
begin
  if p_observations is null or jsonb_typeof(p_observations) <> 'array' then
    raise exception 'Observation payload must be a JSON array';
  end if;

  select * into approval
    from public.approve_agent_intake(
      p_intake_id,
      p_expected_summary_version,
      p_target_session_id,
      p_remote_table,
      p_station_key,
      p_panel_row_id,
      p_panel_payload,
      p_reviewer_id,
      p_approved_at
    );

  if not approval.already_approved then
    for raw_observation in select value from jsonb_array_elements(p_observations)
    loop
      observation_payload := raw_observation || jsonb_build_object(
        'sample_id', approval.panel_row_id,
        'customer_id', p_panel_payload ->> 'customer_id',
        'session_id', approval.audit_session_id,
        'created_at', coalesce(raw_observation ->> 'created_at', p_approved_at),
        'updated_at', p_approved_at,
        'sync_status', 'synced',
        'dirty_at', null,
        'last_synced_at', p_approved_at,
        'sync_error', null
      );
      insert into public.chick_quality_observation
      select * from jsonb_populate_record(
        null::public.chick_quality_observation,
        observation_payload
      );
    end loop;
  end if;

  return query select
    approval.intake_id::text,
    approval.audit_session_id::text,
    approval.panel_row_id::text,
    approval.already_approved::boolean;
end;
$$;

revoke all on function public.approve_agent_intake_v2(
  text, integer, text, text, text, text, jsonb, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.approve_agent_intake_v2(
  text, integer, text, text, text, text, jsonb, text, text, jsonb
) to service_role;
