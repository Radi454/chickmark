-- Hybrid flock-performance monitoring and diagnostic farm auditing.
--
-- The Flutter client stores camelCase columns in SQLite and converts them to
-- snake_case for Supabase. Date/time values and JSON snapshots remain TEXT so
-- offline round-trips preserve the exact values authored on the device.
--
-- Tenant-owned child tables carry a server-derived customer_id. The column is
-- intentionally absent from the local SQLite row shape: before-write triggers
-- derive it from the authoritative parent edge and reject cross-customer links.

-- ============================ shared broiler objectives ============================

create table public.broiler_target_profiles (
  id text primary key,
  brand text not null,
  breed text not null,
  feathering_variant text,
  sex_profile text not null
    check (sex_profile in ('as_hatched', 'male', 'female')),
  publication_version text not null,
  publication_date text,
  source_title text not null,
  source_url text not null,
  source_file_path text,
  region text,
  language_code text not null default 'en',
  active_from text,
  active_to text,
  is_official integer not null default 0 check (is_official in (0, 1)),
  is_active integer not null default 1 check (is_active in (0, 1)),
  supersedes_profile_id text
    references public.broiler_target_profiles(id) on delete set null,
  created_by text,
  created_at text,
  updated_at text
);

create index idx_broiler_target_profiles_lookup
  on public.broiler_target_profiles
  (brand, breed, sex_profile, is_active, publication_version);
create index idx_broiler_target_profiles_supersedes_fk
  on public.broiler_target_profiles(supersedes_profile_id)
  where supersedes_profile_id is not null;

create table public.broiler_target_rows (
  id text primary key,
  profile_id text not null
    references public.broiler_target_profiles(id) on delete cascade,
  age_day integer not null check (age_day >= 0),
  body_weight_g double precision,
  daily_gain_g double precision,
  average_daily_gain_g double precision,
  daily_feed_intake_g_per_living_bird double precision,
  cumulative_feed_intake_g_per_living_bird double precision,
  fcr double precision,
  water_ml_per_living_bird double precision,
  metric_method_notes text,
  created_at text,
  updated_at text,
  unique (profile_id, age_day)
);

-- ============================ customer hierarchy ============================

create table public.customer_sectors (
  id text primary key,
  customer_id text not null
    references public.customers(id) on delete cascade,
  sector_key text not null check (sector_key in ('breeder', 'broiler', 'layer')),
  is_active integer not null default 1 check (is_active in (0, 1)),
  created_at text,
  updated_at text,
  unique (customer_id, sector_key)
);

create table public.farms (
  id text primary key,
  customer_id text not null
    references public.customers(id) on delete cascade,
  sector_key text not null check (sector_key in ('breeder', 'broiler', 'layer')),
  name text not null,
  location text,
  notes text,
  is_active integer not null default 1 check (is_active in (0, 1)),
  created_by text,
  created_at text,
  updated_at text
);
create index idx_farms_customer_sector
  on public.farms(customer_id, sector_key, is_active, name);

create table public.houses (
  id text primary key,
  farm_id text not null references public.farms(id) on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  name text not null,
  code text,
  capacity integer,
  notes text,
  is_active integer not null default 1 check (is_active in (0, 1)),
  created_by text,
  created_at text,
  updated_at text,
  unique (farm_id, name)
);
create unique index idx_houses_farm_code
  on public.houses(farm_id, code)
  where code is not null and code <> '';
create index idx_houses_customer_fk on public.houses(customer_id);

alter table public.flocks
  add column if not exists farm_id text,
  add column if not exists sector_key text,
  add column if not exists sex_profile text not null default 'as_hatched',
  add column if not exists target_profile_id text,
  add column if not exists production_phase text;

alter table public.flocks
  drop constraint if exists flocks_farm_id_fkey,
  add constraint flocks_farm_id_fkey
    foreign key (farm_id) references public.farms(id) on delete set null,
  drop constraint if exists flocks_target_profile_id_fkey,
  add constraint flocks_target_profile_id_fkey
    foreign key (target_profile_id)
    references public.broiler_target_profiles(id) on delete set null,
  drop constraint if exists flocks_sector_key_check,
  add constraint flocks_sector_key_check
    check (sector_key is null or sector_key in ('breeder', 'broiler', 'layer')),
  drop constraint if exists flocks_sex_profile_check,
  add constraint flocks_sex_profile_check
    check (sex_profile in ('as_hatched', 'male', 'female'));

create index idx_flocks_farm_fk
  on public.flocks(farm_id) where farm_id is not null;
create index idx_flocks_target_profile_fk
  on public.flocks(target_profile_id) where target_profile_id is not null;

create or replace function chickmark_private.validate_flock_scope()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  parent_customer_id text;
  parent_sector_key text;
begin
  if new.farm_id is null then
    return new;
  end if;

  select farm.customer_id, farm.sector_key
    into parent_customer_id, parent_sector_key
    from public.farms as farm
   where farm.id = new.farm_id;

  if parent_customer_id is null then
    raise exception 'Flock farm does not exist' using errcode = '23503';
  end if;
  if new.customer_id is distinct from parent_customer_id then
    raise exception 'Flock and farm must belong to the same customer'
      using errcode = '23514';
  end if;
  if new.sector_key is null then
    new.sector_key := parent_sector_key;
  elsif new.sector_key is distinct from parent_sector_key then
    raise exception 'Flock and farm must belong to the same sector'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function chickmark_private.validate_flock_scope()
  from public, anon, authenticated;

create trigger flocks_validate_scope
  before insert or update of customer_id, farm_id, sector_key
  on public.flocks
  for each row execute function chickmark_private.validate_flock_scope();

-- ============================ daily performance ============================

create table public.flock_placements (
  id text primary key,
  flock_id text not null references public.flocks(id) on delete cascade,
  house_id text not null references public.houses(id) on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  placed_birds integer not null check (placed_birds > 0),
  placed_at text not null,
  ended_at text,
  status text not null default 'active'
    check (status in ('active', 'ended', 'transferred')),
  notes text,
  created_by text,
  created_at text,
  updated_at text
);
create index idx_flock_placements_flock
  on public.flock_placements(flock_id, status, placed_at);
create unique index idx_active_placement_per_house
  on public.flock_placements(house_id)
  where status = 'active' and ended_at is null;
create index idx_flock_placements_customer_fk
  on public.flock_placements(customer_id);

create table public.broiler_daily_records (
  id text primary key,
  placement_id text not null
    references public.flock_placements(id) on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  record_date text not null,
  current_revision_id text,
  verification_status text not null default 'pending_entry'
    check (verification_status in (
      'pending_entry', 'entered', 'reviewed', 'verified',
      'requires_clarification', 'corrected'
    )),
  created_by text,
  created_at text,
  updated_at text,
  unique (placement_id, record_date)
);
create index idx_broiler_daily_records_customer_fk
  on public.broiler_daily_records(customer_id);

create table public.broiler_daily_record_revisions (
  id text primary key,
  record_id text not null
    references public.broiler_daily_records(id) on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  revision_number integer not null check (revision_number > 0),
  verification_status text not null
    check (verification_status in (
      'pending_entry', 'entered', 'reviewed', 'verified',
      'requires_clarification', 'corrected'
    )),
  data_source_type text not null default 'manual',
  source_description text,
  reported_by text,
  entered_by text not null,
  entered_at text not null,
  reviewed_by text,
  reviewed_at text,
  verified_by text,
  verified_at text,
  correction_reason text,
  opening_bird_count integer,
  daily_mortality integer,
  daily_culls integer,
  transfers_in integer,
  transfers_out integer,
  partial_depletion integer,
  other_population_adjustment integer,
  mortality_causes_json text,
  closing_live_bird_count integer,
  daily_feed_consumed_kg double precision,
  feed_type text,
  feed_phase text,
  feed_change text,
  feed_interruption_minutes integer,
  feed_shortage integer check (feed_shortage in (0, 1)),
  water_consumed_liters double precision,
  flushing_water_liters double precision,
  water_interruption_minutes integer,
  water_medication text,
  water_vaccination text,
  average_body_weight_g double precision,
  birds_weighed integer,
  uniformity_pct double precision,
  cv_pct double precision,
  individual_weights_json text,
  min_temperature_c double precision,
  max_temperature_c double precision,
  average_temperature_c double precision,
  relative_humidity_pct double precision,
  co2_ppm double precision,
  ammonia_ppm double precision,
  environment_incident text,
  clinical_signs text,
  treatment_started text,
  treatment_stopped text,
  vaccination text,
  power_failure integer check (power_failure in (0, 1)),
  equipment_failure text,
  veterinary_observation text,
  notes text,
  created_at text not null,
  unique (record_id, revision_number)
);
create index idx_broiler_daily_revisions_customer_fk
  on public.broiler_daily_record_revisions(customer_id);

alter table public.broiler_daily_records
  add constraint broiler_daily_records_current_revision_id_fkey
  foreign key (current_revision_id)
  references public.broiler_daily_record_revisions(id)
  on delete set null
  deferrable initially deferred;

create index idx_broiler_daily_records_current_revision_fk
  on public.broiler_daily_records(current_revision_id)
  where current_revision_id is not null;

create table public.daily_record_sources (
  id text primary key,
  revision_id text not null
    references public.broiler_daily_record_revisions(id) on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  source_kind text not null,
  remote_storage_path text,
  original_filename text,
  checksum text,
  created_at text,
  updated_at text
);
create index idx_daily_record_sources_revision
  on public.daily_record_sources(revision_id, created_at);
create index idx_daily_record_sources_customer_fk
  on public.daily_record_sources(customer_id);

create table public.broiler_daily_events (
  id text primary key,
  revision_id text not null
    references public.broiler_daily_record_revisions(id) on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  event_type text not null,
  event_at text,
  is_all_day integer not null default 1 check (is_all_day in (0, 1)),
  event_state text,
  description text,
  treatment text,
  vaccination text,
  feed_phase text,
  equipment text,
  created_at text
);
create index idx_broiler_daily_events_revision
  on public.broiler_daily_events(revision_id, event_at);
create index idx_broiler_daily_events_customer_fk
  on public.broiler_daily_events(customer_id);

-- ============================ alerts, visits, and actions ============================

create table public.performance_alert_rules (
  id text primary key,
  metric_key text not null,
  scope_level text not null check (scope_level in ('global', 'customer')),
  customer_id text references public.customers(id) on delete cascade,
  watch_threshold double precision,
  critical_threshold double precision,
  lower_threshold double precision,
  upper_threshold double precision,
  direction text not null
    check (direction in ('above', 'below', 'outside_range', 'rate_of_change')),
  persistence_window integer not null default 1,
  minimum_valid_observations integer not null default 1,
  source text not null,
  rationale text,
  is_enabled integer not null default 1 check (is_enabled in (0, 1)),
  created_at text,
  updated_at text,
  unique (metric_key, scope_level, customer_id),
  check (
    (scope_level = 'global' and customer_id is null)
    or (scope_level = 'customer' and customer_id is not null)
  )
);
create index idx_performance_alert_rules_customer_fk
  on public.performance_alert_rules(customer_id)
  where customer_id is not null;

create table public.performance_concerns (
  id text primary key,
  rule_id text references public.performance_alert_rules(id) on delete set null,
  customer_id text not null references public.customers(id) on delete cascade,
  farm_id text references public.farms(id) on delete cascade,
  flock_id text references public.flocks(id) on delete cascade,
  placement_id text references public.flock_placements(id) on delete cascade,
  house_id text references public.houses(id) on delete cascade,
  metric_key text not null,
  severity text not null check (severity in ('watch', 'critical')),
  first_observed_at text not null,
  last_observed_at text not null,
  evidence_window_start text,
  evidence_window_end text,
  baseline_value double precision,
  target_value double precision,
  actual_value double precision,
  evidence_json text,
  status text not null default 'open'
    check (status in (
      'open', 'monitoring', 'assigned_to_visit', 'resolved', 'dismissed'
    )),
  resolved_at text,
  resolved_by text,
  resolution_notes text,
  dismissed_at text,
  dismissed_by text,
  dismissal_reason text,
  recurrence_of_id text
    references public.performance_concerns(id) on delete set null,
  created_at text,
  updated_at text
);
create index idx_performance_concerns_scope
  on public.performance_concerns
  (customer_id, farm_id, flock_id, placement_id, metric_key, status, updated_at);
create index idx_performance_concerns_rule_fk
  on public.performance_concerns(rule_id) where rule_id is not null;
create index idx_performance_concerns_farm_fk
  on public.performance_concerns(farm_id) where farm_id is not null;
create index idx_performance_concerns_flock_fk
  on public.performance_concerns(flock_id) where flock_id is not null;
create index idx_performance_concerns_placement_fk
  on public.performance_concerns(placement_id) where placement_id is not null;
create index idx_performance_concerns_house_fk
  on public.performance_concerns(house_id) where house_id is not null;
create index idx_performance_concerns_recurrence_fk
  on public.performance_concerns(recurrence_of_id)
  where recurrence_of_id is not null;

create table public.farm_visit_sessions (
  id text primary key,
  customer_id text not null references public.customers(id) on delete cascade,
  farm_id text not null references public.farms(id) on delete cascade,
  flock_id text references public.flocks(id) on delete set null,
  visit_date text not null,
  briefing_snapshot_json text not null default '{}',
  status text not null default 'planned'
    check (status in ('planned', 'in_progress', 'completed', 'cancelled')),
  assigned_auditor_id text,
  started_at text,
  completed_at text,
  notes text,
  created_by text,
  created_at text,
  updated_at text
);
create index idx_farm_visit_sessions_scope
  on public.farm_visit_sessions
  (customer_id, farm_id, flock_id, visit_date desc);
create index idx_farm_visit_sessions_farm_fk
  on public.farm_visit_sessions(farm_id);
create index idx_farm_visit_sessions_flock_fk
  on public.farm_visit_sessions(flock_id) where flock_id is not null;

create table public.farm_visit_houses (
  id text primary key,
  visit_id text not null
    references public.farm_visit_sessions(id) on delete cascade,
  house_id text not null references public.houses(id) on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  created_at text,
  unique (visit_id, house_id)
);
create index idx_farm_visit_houses_house_fk
  on public.farm_visit_houses(house_id);
create index idx_farm_visit_houses_customer_fk
  on public.farm_visit_houses(customer_id);

create table public.visit_investigations (
  id text primary key,
  visit_id text not null
    references public.farm_visit_sessions(id) on delete cascade,
  source_concern_id text
    references public.performance_concerns(id) on delete set null,
  house_id text references public.houses(id) on delete set null,
  customer_id text not null references public.customers(id) on delete cascade,
  location text,
  origin text not null default 'suggested',
  investigation_type text not null,
  instruction text not null,
  status text not null default 'pending'
    check (status in ('pending', 'in_progress', 'completed', 'not_applicable')),
  result_summary text,
  created_at text,
  updated_at text
);
create index idx_visit_investigations_visit
  on public.visit_investigations(visit_id, status);
create index idx_visit_investigations_concern_fk
  on public.visit_investigations(source_concern_id)
  where source_concern_id is not null;
create index idx_visit_investigations_house_fk
  on public.visit_investigations(house_id) where house_id is not null;
create index idx_visit_investigations_customer_fk
  on public.visit_investigations(customer_id);

create table public.visit_findings (
  id text primary key,
  visit_id text not null
    references public.farm_visit_sessions(id) on delete cascade,
  investigation_id text
    references public.visit_investigations(id) on delete set null,
  customer_id text not null references public.customers(id) on delete cascade,
  finding_type text not null,
  severity text,
  measured_value double precision,
  unit text,
  observation_json text,
  house_id text references public.houses(id) on delete set null,
  location text,
  staff_explanation text,
  attachment_refs_json text,
  authored_by text,
  created_at text,
  updated_at text
);
create index idx_visit_findings_visit
  on public.visit_findings(visit_id, investigation_id, created_at);
create index idx_visit_findings_investigation_fk
  on public.visit_findings(investigation_id)
  where investigation_id is not null;
create index idx_visit_findings_house_fk
  on public.visit_findings(house_id) where house_id is not null;
create index idx_visit_findings_customer_fk
  on public.visit_findings(customer_id);

create table public.cause_assessments (
  id text primary key,
  visit_id text not null
    references public.farm_visit_sessions(id) on delete cascade,
  concern_id text not null
    references public.performance_concerns(id) on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  probable_cause text not null,
  alternative_causes_json text,
  supporting_evidence_json text,
  conflicting_evidence_json text,
  status text not null default 'suspected'
    check (status in ('suspected', 'probable', 'confirmed', 'ruled_out')),
  authored_by text,
  created_at text,
  updated_at text
);
create index idx_cause_assessments_visit_concern
  on public.cause_assessments(visit_id, concern_id, status);
create index idx_cause_assessments_concern_fk
  on public.cause_assessments(concern_id);
create index idx_cause_assessments_customer_fk
  on public.cause_assessments(customer_id);

create table public.corrective_actions (
  id text primary key,
  concern_id text not null
    references public.performance_concerns(id) on delete cascade,
  visit_id text references public.farm_visit_sessions(id) on delete set null,
  cause_assessment_id text
    references public.cause_assessments(id) on delete set null,
  customer_id text not null references public.customers(id) on delete cascade,
  instruction text not null,
  owner_id text,
  owner_name text,
  due_at text,
  implemented_at text,
  implementation_confirmed_by text,
  status text not null default 'open'
    check (status in (
      'open', 'in_progress', 'implemented', 'completed', 'cancelled'
    )),
  completion_notes text,
  evidence_refs_json text,
  created_by text,
  created_at text,
  updated_at text
);
create index idx_corrective_actions_concern_status
  on public.corrective_actions(concern_id, status, due_at);
create index idx_corrective_actions_visit_fk
  on public.corrective_actions(visit_id) where visit_id is not null;
create index idx_corrective_actions_cause_fk
  on public.corrective_actions(cause_assessment_id)
  where cause_assessment_id is not null;
create index idx_corrective_actions_customer_fk
  on public.corrective_actions(customer_id);

create table public.action_kpi_evaluations (
  id text primary key,
  action_id text not null
    references public.corrective_actions(id) on delete cascade,
  customer_id text not null references public.customers(id) on delete cascade,
  kpi_key text not null,
  scope_json text not null default '{}',
  baseline_window_start text,
  baseline_window_end text,
  baseline_value double precision,
  target_rule text,
  target_value double precision,
  evaluation_start text not null,
  evaluation_end text not null,
  observed_value double precision,
  effectiveness text not null default 'not_evaluated'
    check (effectiveness in (
      'effective', 'partially_effective', 'ineffective', 'not_evaluated'
    )),
  evaluation_reason text,
  evaluated_by text,
  evaluated_at text,
  created_at text,
  updated_at text
);
create index idx_action_kpi_evaluations_action
  on public.action_kpi_evaluations(action_id, kpi_key, evaluation_end);
create index idx_action_kpi_evaluations_customer_fk
  on public.action_kpi_evaluations(customer_id);

-- ============================ inherited tenant scope ============================

create or replace function chickmark_private.derive_performance_customer()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  resolved_customer_id text;
  related_customer_id text;
  related_record_id text;
begin
  case tg_table_name
    when 'houses' then
      select parent.customer_id into resolved_customer_id
        from public.farms as parent where parent.id = new.farm_id;
    when 'flock_placements' then
      select flock.customer_id into resolved_customer_id
        from public.flocks as flock where flock.id = new.flock_id;
      select house.customer_id into related_customer_id
        from public.houses as house where house.id = new.house_id;
    when 'broiler_daily_records' then
      select parent.customer_id into resolved_customer_id
        from public.flock_placements as parent
       where parent.id = new.placement_id;
      if new.current_revision_id is not null then
        select revision.customer_id, revision.record_id
          into related_customer_id, related_record_id
          from public.broiler_daily_record_revisions as revision
         where revision.id = new.current_revision_id;
        if related_record_id is distinct from new.id then
          raise exception 'Current revision must belong to its daily record'
            using errcode = '23514';
        end if;
      end if;
    when 'broiler_daily_record_revisions' then
      select parent.customer_id into resolved_customer_id
        from public.broiler_daily_records as parent
       where parent.id = new.record_id;
    when 'daily_record_sources' then
      select parent.customer_id into resolved_customer_id
        from public.broiler_daily_record_revisions as parent
       where parent.id = new.revision_id;
    when 'broiler_daily_events' then
      select parent.customer_id into resolved_customer_id
        from public.broiler_daily_record_revisions as parent
       where parent.id = new.revision_id;
    when 'farm_visit_houses' then
      select parent.customer_id into resolved_customer_id
        from public.farm_visit_sessions as parent
       where parent.id = new.visit_id;
      select house.customer_id into related_customer_id
        from public.houses as house where house.id = new.house_id;
    when 'visit_investigations' then
      select parent.customer_id into resolved_customer_id
        from public.farm_visit_sessions as parent
       where parent.id = new.visit_id;
      if new.source_concern_id is not null then
        select concern.customer_id into related_customer_id
          from public.performance_concerns as concern
         where concern.id = new.source_concern_id;
        if related_customer_id is distinct from resolved_customer_id then
          raise exception 'Investigation concern crosses customer scope'
            using errcode = '23514';
        end if;
      end if;
      if new.house_id is not null then
        select house.customer_id into related_customer_id
          from public.houses as house where house.id = new.house_id;
      end if;
    when 'visit_findings' then
      select parent.customer_id into resolved_customer_id
        from public.farm_visit_sessions as parent
       where parent.id = new.visit_id;
      if new.investigation_id is not null then
        select investigation.customer_id into related_customer_id
          from public.visit_investigations as investigation
         where investigation.id = new.investigation_id;
        if related_customer_id is distinct from resolved_customer_id then
          raise exception 'Finding investigation crosses customer scope'
            using errcode = '23514';
        end if;
      end if;
      if new.house_id is not null then
        select house.customer_id into related_customer_id
          from public.houses as house where house.id = new.house_id;
      end if;
    when 'cause_assessments' then
      select parent.customer_id into resolved_customer_id
        from public.farm_visit_sessions as parent
       where parent.id = new.visit_id;
      select concern.customer_id into related_customer_id
        from public.performance_concerns as concern
       where concern.id = new.concern_id;
    when 'corrective_actions' then
      select parent.customer_id into resolved_customer_id
        from public.performance_concerns as parent
       where parent.id = new.concern_id;
      if new.visit_id is not null then
        select visit.customer_id into related_customer_id
          from public.farm_visit_sessions as visit
         where visit.id = new.visit_id;
        if related_customer_id is distinct from resolved_customer_id then
          raise exception 'Corrective-action visit crosses customer scope'
            using errcode = '23514';
        end if;
      end if;
      if new.cause_assessment_id is not null then
        select cause.customer_id into related_customer_id
          from public.cause_assessments as cause
         where cause.id = new.cause_assessment_id;
      end if;
    when 'action_kpi_evaluations' then
      select parent.customer_id into resolved_customer_id
        from public.corrective_actions as parent
       where parent.id = new.action_id;
    else
      raise exception 'Unsupported performance scope table: %', tg_table_name;
  end case;

  if resolved_customer_id is null then
    raise exception 'Performance record parent does not exist'
      using errcode = '23503';
  end if;
  if related_customer_id is not null
     and related_customer_id is distinct from resolved_customer_id then
    raise exception 'Performance record links different customers'
      using errcode = '23514';
  end if;
  if new.customer_id is not null
     and new.customer_id is distinct from resolved_customer_id then
    raise exception 'Performance customer scope cannot be overridden'
      using errcode = '23514';
  end if;

  new.customer_id := resolved_customer_id;
  return new;
end;
$$;

revoke all on function chickmark_private.derive_performance_customer()
  from public, anon, authenticated;

create trigger houses_derive_customer
  before insert or update of farm_id, customer_id on public.houses
  for each row execute function chickmark_private.derive_performance_customer();
create trigger flock_placements_derive_customer
  before insert or update of flock_id, house_id, customer_id
  on public.flock_placements
  for each row execute function chickmark_private.derive_performance_customer();
create trigger broiler_daily_records_derive_customer
  before insert or update of placement_id, current_revision_id, customer_id
  on public.broiler_daily_records
  for each row execute function chickmark_private.derive_performance_customer();
create trigger broiler_daily_revisions_derive_customer
  before insert or update of record_id, customer_id
  on public.broiler_daily_record_revisions
  for each row execute function chickmark_private.derive_performance_customer();
create trigger daily_record_sources_derive_customer
  before insert or update of revision_id, customer_id
  on public.daily_record_sources
  for each row execute function chickmark_private.derive_performance_customer();
create trigger broiler_daily_events_derive_customer
  before insert or update of revision_id, customer_id
  on public.broiler_daily_events
  for each row execute function chickmark_private.derive_performance_customer();
create trigger farm_visit_houses_derive_customer
  before insert or update of visit_id, house_id, customer_id
  on public.farm_visit_houses
  for each row execute function chickmark_private.derive_performance_customer();
create trigger visit_investigations_derive_customer
  before insert or update of
    visit_id, source_concern_id, house_id, customer_id
  on public.visit_investigations
  for each row execute function chickmark_private.derive_performance_customer();
create trigger visit_findings_derive_customer
  before insert or update of
    visit_id, investigation_id, house_id, customer_id
  on public.visit_findings
  for each row execute function chickmark_private.derive_performance_customer();
create trigger cause_assessments_derive_customer
  before insert or update of visit_id, concern_id, customer_id
  on public.cause_assessments
  for each row execute function chickmark_private.derive_performance_customer();
create trigger corrective_actions_derive_customer
  before insert or update of
    concern_id, visit_id, cause_assessment_id, customer_id
  on public.corrective_actions
  for each row execute function chickmark_private.derive_performance_customer();
create trigger action_kpi_evaluations_derive_customer
  before insert or update of action_id, customer_id
  on public.action_kpi_evaluations
  for each row execute function chickmark_private.derive_performance_customer();

-- Directly-scoped records may contain several optional parent links. Reject any
-- relationship that points outside the declared customer.
create or replace function chickmark_private.validate_performance_links()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  linked_customer_id text;
begin
  if tg_table_name = 'performance_concerns' then
    if new.rule_id is not null then
      select customer_id into linked_customer_id
        from public.performance_alert_rules where id = new.rule_id;
      if linked_customer_id is not null
         and linked_customer_id is distinct from new.customer_id then
        raise exception 'Concern rule crosses customer scope'
          using errcode = '23514';
      end if;
    end if;
    if new.farm_id is not null then
      select customer_id into linked_customer_id
        from public.farms where id = new.farm_id;
      if linked_customer_id is distinct from new.customer_id then
        raise exception 'Concern farm crosses customer scope'
          using errcode = '23514';
      end if;
    end if;
    if new.flock_id is not null then
      select customer_id into linked_customer_id
        from public.flocks where id = new.flock_id;
      if linked_customer_id is distinct from new.customer_id then
        raise exception 'Concern flock crosses customer scope'
          using errcode = '23514';
      end if;
    end if;
    if new.placement_id is not null then
      select customer_id into linked_customer_id
        from public.flock_placements where id = new.placement_id;
      if linked_customer_id is distinct from new.customer_id then
        raise exception 'Concern placement crosses customer scope'
          using errcode = '23514';
      end if;
    end if;
    if new.house_id is not null then
      select customer_id into linked_customer_id
        from public.houses where id = new.house_id;
      if linked_customer_id is distinct from new.customer_id then
        raise exception 'Concern house crosses customer scope'
          using errcode = '23514';
      end if;
    end if;
    if new.recurrence_of_id is not null then
      select customer_id into linked_customer_id
        from public.performance_concerns where id = new.recurrence_of_id;
      if linked_customer_id is distinct from new.customer_id then
        raise exception 'Concern recurrence crosses customer scope'
          using errcode = '23514';
      end if;
    end if;
  elsif tg_table_name = 'farm_visit_sessions' then
    select customer_id into linked_customer_id
      from public.farms where id = new.farm_id;
    if linked_customer_id is distinct from new.customer_id then
      raise exception 'Visit farm crosses customer scope'
        using errcode = '23514';
    end if;
    if new.flock_id is not null then
      select customer_id into linked_customer_id
        from public.flocks where id = new.flock_id;
      if linked_customer_id is distinct from new.customer_id then
        raise exception 'Visit flock crosses customer scope'
          using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function chickmark_private.validate_performance_links()
  from public, anon, authenticated;

create trigger performance_concerns_validate_links
  before insert or update on public.performance_concerns
  for each row execute function chickmark_private.validate_performance_links();
create trigger farm_visit_sessions_validate_links
  before insert or update on public.farm_visit_sessions
  for each row execute function chickmark_private.validate_performance_links();

-- ============================ immutable evidence ============================

create or replace function chickmark_private.reject_daily_revision_mutation()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if current_setting('chickmark.allow_daily_revision_delete', true) = 'on' then
      return old;
    end if;
    raise exception 'Daily record revisions are immutable'
      using errcode = '55000';
  end if;

  -- Supabase upsert retries issue an UPDATE even when every value is equal.
  -- Permit that idempotent retry, while rejecting any changed evidence.
  if new is not distinct from old then
    return new;
  end if;
  raise exception 'Daily record revisions are immutable'
    using errcode = '55000';
end;
$$;

revoke all on function chickmark_private.reject_daily_revision_mutation()
  from public, anon, authenticated;

create trigger broiler_daily_revisions_immutable
  before update or delete on public.broiler_daily_record_revisions
  for each row execute function
    chickmark_private.reject_daily_revision_mutation();

-- ============================ row-level security ============================

alter table public.customer_sectors enable row level security;
alter table public.farms enable row level security;
alter table public.houses enable row level security;
alter table public.flock_placements enable row level security;
alter table public.broiler_daily_records enable row level security;
alter table public.broiler_daily_record_revisions enable row level security;
alter table public.daily_record_sources enable row level security;
alter table public.broiler_daily_events enable row level security;
alter table public.broiler_target_profiles enable row level security;
alter table public.broiler_target_rows enable row level security;
alter table public.performance_alert_rules enable row level security;
alter table public.performance_concerns enable row level security;
alter table public.farm_visit_sessions enable row level security;
alter table public.farm_visit_houses enable row level security;
alter table public.visit_investigations enable row level security;
alter table public.visit_findings enable row level security;
alter table public.cause_assessments enable row level security;
alter table public.corrective_actions enable row level security;
alter table public.action_kpi_evaluations enable row level security;

-- Equivalent policy shape installed on every tenant table:
--   using (customer_id is not null and app_can_read_customer(customer_id))
--   with check (customer_id is not null and app_can_write_customer(customer_id))
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'customer_sectors',
    'farms',
    'houses',
    'flock_placements',
    'broiler_daily_records',
    'broiler_daily_record_revisions',
    'daily_record_sources',
    'broiler_daily_events',
    'performance_concerns',
    'farm_visit_sessions',
    'farm_visit_houses',
    'visit_investigations',
    'visit_findings',
    'cause_assessments',
    'corrective_actions',
    'action_kpi_evaluations'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (customer_id is not null and '
      'chickmark_private.app_can_read_customer(customer_id))',
      table_name || '_select',
      table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (customer_id is not null and '
      'chickmark_private.app_can_write_customer(customer_id))',
      table_name || '_insert',
      table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (customer_id is not null and '
      'chickmark_private.app_can_write_customer(customer_id)) '
      'with check (customer_id is not null and '
      'chickmark_private.app_can_write_customer(customer_id))',
      table_name || '_update',
      table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated '
      'using (customer_id is not null and '
      'chickmark_private.app_can_write_customer(customer_id))',
      table_name || '_delete',
      table_name
    );
  end loop;
end
$$;

create policy broiler_target_profiles_select
  on public.broiler_target_profiles for select to authenticated
  using (chickmark_private.app_status() = 'approved');
create policy broiler_target_profiles_insert
  on public.broiler_target_profiles for insert to authenticated
  with check (chickmark_private.app_is_staff());
create policy broiler_target_profiles_update
  on public.broiler_target_profiles for update to authenticated
  using (chickmark_private.app_is_staff())
  with check (chickmark_private.app_is_staff());
create policy broiler_target_profiles_delete
  on public.broiler_target_profiles for delete to authenticated
  using (chickmark_private.app_is_staff());

create policy broiler_target_rows_select
  on public.broiler_target_rows for select to authenticated
  using (chickmark_private.app_status() = 'approved');
create policy broiler_target_rows_insert
  on public.broiler_target_rows for insert to authenticated
  with check (chickmark_private.app_is_staff());
create policy broiler_target_rows_update
  on public.broiler_target_rows for update to authenticated
  using (chickmark_private.app_is_staff())
  with check (chickmark_private.app_is_staff());
create policy broiler_target_rows_delete
  on public.broiler_target_rows for delete to authenticated
  using (chickmark_private.app_is_staff());

create policy performance_alert_rules_select
  on public.performance_alert_rules for select to authenticated
  using (
    (customer_id is null and chickmark_private.app_status() = 'approved')
    or chickmark_private.app_can_read_customer(customer_id)
  );
create policy performance_alert_rules_insert
  on public.performance_alert_rules for insert to authenticated
  with check (
    (customer_id is null and chickmark_private.app_is_staff())
    or chickmark_private.app_can_write_customer(customer_id)
  );
create policy performance_alert_rules_update
  on public.performance_alert_rules for update to authenticated
  using (
    (customer_id is null and chickmark_private.app_is_staff())
    or chickmark_private.app_can_write_customer(customer_id)
  )
  with check (
    (customer_id is null and chickmark_private.app_is_staff())
    or chickmark_private.app_can_write_customer(customer_id)
  );
create policy performance_alert_rules_delete
  on public.performance_alert_rules for delete to authenticated
  using (
    (customer_id is null and chickmark_private.app_is_staff())
    or chickmark_private.app_can_write_customer(customer_id)
  );

-- New Supabase projects no longer expose newly-created tables through the
-- Data API implicitly, so authenticated grants are explicit.
grant select, insert, update, delete on
  public.customer_sectors,
  public.farms,
  public.houses,
  public.flock_placements,
  public.broiler_daily_records,
  public.broiler_daily_record_revisions,
  public.daily_record_sources,
  public.broiler_daily_events,
  public.broiler_target_profiles,
  public.broiler_target_rows,
  public.performance_alert_rules,
  public.performance_concerns,
  public.farm_visit_sessions,
  public.farm_visit_houses,
  public.visit_investigations,
  public.visit_findings,
  public.cause_assessments,
  public.corrective_actions,
  public.action_kpi_evaluations
to authenticated, service_role;

revoke all on
  public.customer_sectors,
  public.farms,
  public.houses,
  public.flock_placements,
  public.broiler_daily_records,
  public.broiler_daily_record_revisions,
  public.daily_record_sources,
  public.broiler_daily_events,
  public.broiler_target_profiles,
  public.broiler_target_rows,
  public.performance_alert_rules,
  public.performance_concerns,
  public.farm_visit_sessions,
  public.farm_visit_houses,
  public.visit_investigations,
  public.visit_findings,
  public.cause_assessments,
  public.corrective_actions,
  public.action_kpi_evaluations
from anon;

-- Extend the existing deletion-event scope resolver to the tenant-owned
-- performance graph. Shared objective rows have no tenant customer_id and are
-- intentionally not accepted as sync tombstone targets.
create or replace function chickmark_private.prepare_sync_tombstone_scope()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  resolved_customer_id text;
  is_global_target boolean := false;
begin
  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.table_name := old.table_name;
    new.row_id := old.row_id;
    new.deleted_at := old.deleted_at;
    new.created_at := old.created_at;
    new.customer_id := old.customer_id;
    new.created_by := old.created_by;
    new.audience_user_ids := old.audience_user_ids;
    return new;
  end if;

  if new.table_name = 'customers' then
    resolved_customer_id := new.row_id;
  elsif new.table_name = 'photos' then
    select session.customer_id
      into resolved_customer_id
      from public.photos as photo
      join public.audit_sessions as session on session.id = photo.session_id
     where photo.id = new.row_id;
  elsif new.table_name = any (array[
    'hatcheries',
    'flocks',
    'audit_sessions',
    'govee_daily_captures',
    'dashboard_actions',
    'lab_analysis_reports',
    'lab_analysis_groups',
    'lab_analysis_rows',
    'egg_storage',
    'egg_quality',
    'chick_quality',
    'chick_weights',
    'fresh_egg_breakout',
    'candled_egg_breakout',
    'residue_breakout',
    'setter_optimizing',
    'hatcher_optimizing',
    'customer_sectors',
    'farms',
    'houses',
    'flock_placements',
    'broiler_daily_records',
    'broiler_daily_record_revisions',
    'daily_record_sources',
    'broiler_daily_events',
    'performance_alert_rules',
    'performance_concerns',
    'farm_visit_sessions',
    'farm_visit_houses',
    'visit_investigations',
    'visit_findings',
    'cause_assessments',
    'corrective_actions',
    'action_kpi_evaluations'
  ]) then
    execute format(
      'select target.customer_id from public.%I target where target.id = $1',
      new.table_name
    )
    into resolved_customer_id
    using new.row_id;
  elsif new.table_name = any (array[
    'broiler_target_profiles',
    'broiler_target_rows'
  ]) then
    execute format(
      'select exists (select 1 from public.%I target where target.id = $1)',
      new.table_name
    )
    into is_global_target
    using new.row_id;
  else
    raise exception 'Unsupported tombstone target table'
      using errcode = '42501';
  end if;

  if resolved_customer_id is null and not is_global_target then
    raise exception 'Tombstone target is missing or has no customer scope'
      using errcode = '42501';
  end if;

  new.customer_id := resolved_customer_id;
  new.created_by := (select auth.uid());
  if new.created_by is null
     and coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'Authenticated identity required for tombstone creation'
      using errcode = '42501';
  end if;

  select coalesce(array_agg(scoped.user_id), '{}'::uuid[])
    into new.audience_user_ids
    from (
      select profile.id as user_id
      from public.profiles as profile
      where profile.status = 'approved'
        and (
          is_global_target
          or
          profile.role = 'admin'
          or (
            profile.role = 'customer'
            and profile.customer_id = resolved_customer_id
          )
          or (
            profile.role = 'auditor'
            and exists (
              select 1
              from public.auditor_customers as assignment
              where assignment.auditor_id = profile.id
                and assignment.customer_id = resolved_customer_id
            )
          )
        )
      union
      select new.created_by
    ) as scoped
   where scoped.user_id is not null;

  return new;
end;
$$;

revoke all on function chickmark_private.prepare_sync_tombstone_scope()
  from public, anon;
grant execute on function chickmark_private.prepare_sync_tombstone_scope()
  to authenticated, service_role;

drop policy if exists tombstones_insert on public.sync_tombstones;
create policy tombstones_insert
  on public.sync_tombstones for insert to authenticated
  with check (
    chickmark_private.app_is_admin()
    or (
      created_by = (select auth.uid())
      and (
        (customer_id is null and chickmark_private.app_is_staff())
        or chickmark_private.app_can_write_customer(customer_id)
      )
    )
  );

-- ============================ authorized destructive operations ============================

create or replace function public.delete_performance_row(
  p_table_name text,
  p_row_id text
)
  returns table (deleted_id text)
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  target_customer_id text;
  target_exists boolean;
begin
  if p_table_name not in (
    'customer_sectors', 'farms', 'houses', 'flock_placements',
    'broiler_daily_records', 'broiler_daily_record_revisions',
    'daily_record_sources', 'broiler_daily_events',
    'performance_alert_rules', 'performance_concerns',
    'farm_visit_sessions', 'farm_visit_houses', 'visit_investigations',
    'visit_findings', 'cause_assessments', 'corrective_actions',
    'action_kpi_evaluations'
  ) then
    raise exception 'Unsupported performance table'
      using errcode = '22023';
  end if;

  execute format(
    'select exists (select 1 from public.%1$I where id = $1), '
    '(select customer_id from public.%1$I where id = $1)',
    p_table_name
  )
  into target_exists, target_customer_id
  using p_row_id;

  if not target_exists then
    return;
  end if;
  if target_customer_id is null
     and not (
       p_table_name = 'performance_alert_rules'
       and chickmark_private.app_is_staff()
     ) then
    raise exception 'Global performance delete is not permitted'
      using errcode = '42501';
  end if;
  if target_customer_id is not null
     and not chickmark_private.app_can_write_customer(target_customer_id) then
    raise exception 'Performance delete is not permitted'
      using errcode = '42501';
  end if;

  perform set_config('chickmark.allow_daily_revision_delete', 'on', true);
  return query execute format(
    'delete from public.%I where id = $1 returning id',
    p_table_name
  )
  using p_row_id;
end;
$$;

revoke execute on function public.delete_performance_row(text, text)
  from public, anon;
grant execute on function public.delete_performance_row(text, text)
  to authenticated, service_role;

-- Customer deletion cascades through immutable revision evidence only after the
-- existing, authorized customer-delete RPC has approved the tenant operation.
create or replace function public.delete_customer_cascade(p_customer_id text)
  returns table (deleted_id text)
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authenticated identity required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.customers as customer
    where customer.id = p_customer_id
  ) then
    if exists (
      select 1
      from public.sync_tombstones as tombstone
      where tombstone.id = 'customers:' || p_customer_id
        and (
          tombstone.created_by = (select auth.uid())
          or (select auth.uid()) = any (tombstone.audience_user_ids)
          or chickmark_private.app_is_admin()
        )
    ) then
      return query select p_customer_id;
      return;
    end if;
    raise exception 'Customer not found' using errcode = 'P0002';
  end if;

  if not chickmark_private.app_can_write_customer(p_customer_id) then
    raise exception 'Customer delete is not permitted'
      using errcode = '42501';
  end if;

  insert into public.sync_tombstones (
    id, table_name, row_id, deleted_at, created_at
  ) values (
    'customers:' || p_customer_id,
    'customers',
    p_customer_id,
    now()::text,
    now()::text
  )
  on conflict (id) do nothing;

  perform set_config('chickmark.allow_daily_revision_delete', 'on', true);
  return query
    delete from public.customers as customer
    where customer.id = p_customer_id
    returning customer.id;

  if not found then
    raise exception 'Customer delete did not affect a row'
      using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.delete_customer_cascade(text)
  from public, anon;
grant execute on function public.delete_customer_cascade(text)
  to authenticated, service_role;

-- ============================ source-document storage ============================

drop policy if exists photos_read on storage.objects;
drop policy if exists photos_write on storage.objects;

create policy photos_read on storage.objects for select to authenticated
  using (
    bucket_id = 'photos'
    and (
      exists (
        select 1
        from public.audit_sessions s
        where s.id = split_part(name, '/', 1)
          and chickmark_private.app_can_read_customer(s.customer_id)
      )
      or (
        split_part(name, '/', 1) = 'lab_analysis_reports'
        and chickmark_private.app_can_read_customer(
          split_part(name, '/', 2)
        )
      )
      or (
        split_part(name, '/', 1) = 'bmk_operational_sources'
        and chickmark_private.app_status() = 'approved'
      )
      or (
        split_part(name, '/', 1) = 'performance_sources'
        and chickmark_private.app_can_read_customer(
          split_part(name, '/', 2)
        )
      )
    )
  );

create policy photos_write on storage.objects for all to authenticated
  using (
    bucket_id = 'photos'
    and (
      exists (
        select 1
        from public.audit_sessions s
        where s.id = split_part(name, '/', 1)
          and chickmark_private.app_can_write_customer(s.customer_id)
      )
      or (
        split_part(name, '/', 1) = 'lab_analysis_reports'
        and chickmark_private.app_can_write_customer(
          split_part(name, '/', 2)
        )
      )
      or (
        split_part(name, '/', 1) = 'bmk_operational_sources'
        and chickmark_private.app_is_staff()
      )
      or (
        split_part(name, '/', 1) = 'performance_sources'
        and chickmark_private.app_can_write_customer(
          split_part(name, '/', 2)
        )
      )
    )
  )
  with check (
    bucket_id = 'photos'
    and (
      exists (
        select 1
        from public.audit_sessions s
        where s.id = split_part(name, '/', 1)
          and chickmark_private.app_can_write_customer(s.customer_id)
      )
      or (
        split_part(name, '/', 1) = 'lab_analysis_reports'
        and chickmark_private.app_can_write_customer(
          split_part(name, '/', 2)
        )
      )
      or (
        split_part(name, '/', 1) = 'bmk_operational_sources'
        and chickmark_private.app_is_staff()
      )
      or (
        split_part(name, '/', 1) = 'performance_sources'
        and chickmark_private.app_can_write_customer(
          split_part(name, '/', 2)
        )
      )
    )
  );
