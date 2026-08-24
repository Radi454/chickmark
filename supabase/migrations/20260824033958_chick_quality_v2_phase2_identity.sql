-- Chick Quality V2 Phase 2: additive sample identity and provenance.
-- This migration never merges or deletes samples. Legacy scope gaps are
-- represented explicitly as JSON null values and every colliding row receives
-- a deterministic replicate.

do $columns$
declare
  panel_table text;
begin
  foreach panel_table in array array['chick_quality', 'chick_weights'] loop
    execute format('alter table public.%I add column if not exists domain text', panel_table);
    execute format('alter table public.%I add column if not exists schema_version integer', panel_table);
    execute format('alter table public.%I add column if not exists scope_key text', panel_table);
    execute format('alter table public.%I add column if not exists replicate integer', panel_table);
    execute format('alter table public.%I add column if not exists sample_key text', panel_table);
    execute format('alter table public.%I add column if not exists source text', panel_table);
    execute format('alter table public.%I add column if not exists capture_method text', panel_table);
    execute format('alter table public.%I add column if not exists created_by text', panel_table);
    execute format('alter table public.%I add column if not exists device_id text', panel_table);
    execute format('alter table public.%I add column if not exists source_ref_id text', panel_table);
    execute format('alter table public.%I add column if not exists observed_at text', panel_table);
  end loop;
end
$columns$;

alter table public.agent_intake_sessions
  add column if not exists house_identity text,
  add column if not exists trolley_identity text,
  add column if not exists tray_identity text,
  add column if not exists position_identity text;

create or replace function chickmark_private.chick_scope_key(
  p_scope_type text,
  p_house text,
  p_setter text,
  p_hatcher text,
  p_trolley text,
  p_tray text,
  p_position text
) returns text
language sql immutable strict
set search_path = ''
as $fn$
  select case when p_scope_type = 'pool' then '{}' else
    '{' || concat_ws(',',
      case when p_scope_type in ('hatcher','setter_hatcher') or nullif(btrim(p_hatcher), '') is not null
        then '"hatcher":' || coalesce(pg_catalog.to_json(nullif(btrim(p_hatcher), ''))::text, 'null') end,
      case when p_scope_type = 'house' or nullif(btrim(p_house), '') is not null
        then '"house":' || coalesce(pg_catalog.to_json(nullif(btrim(p_house), ''))::text, 'null') end,
      case when nullif(btrim(p_position), '') is not null
        then '"position":' || pg_catalog.to_json(nullif(btrim(p_position), ''))::text end,
      case when p_scope_type in ('setter','setter_hatcher') or nullif(btrim(p_setter), '') is not null
        then '"setter":' || coalesce(pg_catalog.to_json(nullif(btrim(p_setter), ''))::text, 'null') end,
      case when p_scope_type = 'tray' or nullif(btrim(p_tray), '') is not null
        then '"tray":' || coalesce(pg_catalog.to_json(nullif(btrim(p_tray), ''))::text, 'null') end,
      case when p_scope_type = 'trolley' or nullif(btrim(p_trolley), '') is not null
        then '"trolley":' || coalesce(pg_catalog.to_json(nullif(btrim(p_trolley), ''))::text, 'null') end
    ) || '}' end
$fn$;

create or replace function chickmark_private.chick_sample_key(
  p_domain text,
  p_session_id text,
  p_scope_type text,
  p_scope_key text,
  p_replicate integer
) returns text
language sql immutable strict
set search_path = ''
as $fn$
  select rtrim(
    translate(
      replace(
        encode(
          convert_to(
            '[' || pg_catalog.to_json(btrim(p_domain))::text || ',' ||
            pg_catalog.to_json(btrim(p_session_id))::text || ',' ||
            pg_catalog.to_json(p_scope_type)::text || ',' ||
            pg_catalog.to_json(p_scope_key)::text || ',' || p_replicate::text || ']',
            'UTF8'
          ),
          'base64'
        ),
        E'\n',
        ''
      ),
      '+/',
      '-_'
    ),
    '='
  )
$fn$;

revoke all on function chickmark_private.chick_scope_key(text,text,text,text,text,text,text)
  from public, anon, authenticated;
revoke all on function chickmark_private.chick_sample_key(text,text,text,text,integer)
  from public, anon, authenticated;
grant execute on function chickmark_private.chick_scope_key(text,text,text,text,text,text,text)
  to service_role;
grant execute on function chickmark_private.chick_sample_key(text,text,text,text,integer)
  to service_role;

do $backfill$
declare
  panel_table text;
  default_domain text;
  invalid_count bigint;
begin
  foreach panel_table in array array['chick_quality', 'chick_weights'] loop
    default_domain := case panel_table
      when 'chick_weights' then 'chicks.weights'
      else 'chicks.legacy_combined'
    end;

    execute format($sql$
      with normalized as (
        select
          p.id,
          coalesce(nullif(btrim(p.domain), ''), %L) as normalized_domain,
          case
            when %L = 'chick_weights' and p.scope_type in ('pool','house')
              then p.scope_type
            when %L = 'chick_quality' and p.scope_type in ('pool','setter_hatcher')
              then p.scope_type
            when %L = 'chick_weights' and nullif(btrim(p.house), '') is not null then 'house'
            when %L = 'chick_quality' and (
              nullif(btrim(p.setter), '') is not null or nullif(btrim(p.hatcher), '') is not null
            ) then 'setter_hatcher'
            else 'pool'
          end as normalized_scope_type,
          p.session_id,
          p.customer_id,
          p.house, p.setter, p.hatcher, p.trolley, p.tray, p.position,
          p.created_at,
          p.schema_version,
          p.scope_key as existing_scope_key,
          p.replicate as existing_replicate,
          p.sample_key as existing_sample_key,
          p.source,
          p.capture_method,
          p.observed_at
        from public.%I p
      ), scoped as (
        select n.*,
          chickmark_private.chick_scope_key(
            n.normalized_scope_type,
            coalesce(n.house, ''), coalesce(n.setter, ''), coalesce(n.hatcher, ''),
            coalesce(n.trolley, ''), coalesce(n.tray, ''), coalesce(n.position, '')
          ) as normalized_scope_key
        from normalized n
      ), candidate as (
        select s.*,
          s.existing_replicate is not null
          and s.existing_replicate > 0
          and nullif(btrim(s.existing_scope_key), '') is not null
          and s.existing_sample_key = chickmark_private.chick_sample_key(
            s.normalized_domain, s.session_id, s.normalized_scope_type,
            s.existing_scope_key, s.existing_replicate
          ) as identity_candidate
        from scoped s
      ), qualified as (
        select c.*,
          c.identity_candidate
          and row_number() over (
            partition by c.customer_id, c.existing_sample_key
            order by c.created_at nulls last, c.id
          ) = 1
          and row_number() over (
            partition by c.customer_id, c.session_id, c.normalized_domain,
              c.normalized_scope_type, c.existing_scope_key, c.existing_replicate
            order by c.created_at nulls last, c.id
          ) = 1 as identity_valid
        from candidate c
      ), partitioned as (
        select q.*,
          case when q.identity_valid then q.existing_scope_key
            else q.normalized_scope_key end as final_scope_key
        from qualified q
      ), ranked as (
        select p.*,
          coalesce(max(existing_replicate) filter (where identity_valid) over (
            partition by customer_id, session_id, normalized_domain,
              normalized_scope_type, final_scope_key
          ), 0) + sum(case when identity_valid then 0 else 1 end) over (
            partition by customer_id, session_id, normalized_domain,
              normalized_scope_type, final_scope_key
            order by created_at nulls last, id
          )::integer as allocated_replicate
        from partitioned p
      )
      update public.%I p
      set domain = r.normalized_domain,
          schema_version = case when r.schema_version is not null and r.schema_version > 0
            then r.schema_version else 1 end,
          scope_type = r.normalized_scope_type,
          scope_key = r.final_scope_key,
          replicate = case when r.identity_valid then r.existing_replicate
            else r.allocated_replicate end,
          sample_key = case when r.identity_valid then r.existing_sample_key
            else chickmark_private.chick_sample_key(
              r.normalized_domain, r.session_id, r.normalized_scope_type,
              r.final_scope_key, r.allocated_replicate
            ) end,
          source = coalesce(nullif(btrim(r.source), ''), 'legacy'),
          capture_method = coalesce(nullif(btrim(r.capture_method), ''), 'unknown'),
          observed_at = coalesce(r.observed_at, r.created_at)
      from ranked r
      where p.id = r.id
    $sql$, default_domain, panel_table, panel_table, panel_table, panel_table,
      panel_table, panel_table);

    execute format($sql$
      select count(*) from public.%I
      where domain is null or btrim(domain) = ''
         or schema_version is null or schema_version < 1
         or scope_type is null or scope_key is null
         or replicate is null or replicate < 1
         or sample_key is null or btrim(sample_key) = ''
         or source is null or capture_method is null or observed_at is null
    $sql$, panel_table) into invalid_count;
    if invalid_count <> 0 then
      raise exception 'chickmark: % rows in % lack a complete V2 identity', invalid_count, panel_table;
    end if;

    execute format($sql$
      select count(*) from (
        select customer_id, sample_key from public.%I
        group by customer_id, sample_key having count(*) > 1
      ) duplicates
    $sql$, panel_table) into invalid_count;
    if invalid_count <> 0 then
      raise exception 'chickmark: % duplicate V2 sample keys in %', invalid_count, panel_table;
    end if;
  end loop;
end
$backfill$;

drop function if exists public.chickmark_apply_chick_identity_unique_indexes();
drop view if exists public.chick_panel_duplicate_identities;
drop index if exists public.idx_chick_quality_identity;
drop index if exists public.idx_chick_weights_identity;

create unique index if not exists idx_chick_quality_sample_key
  on public.chick_quality(customer_id, sample_key) where sample_key is not null;
create unique index if not exists idx_chick_weights_sample_key
  on public.chick_weights(customer_id, sample_key) where sample_key is not null;

alter table public.chick_quality
  add constraint chick_quality_replicate_positive
  check (replicate is null or replicate > 0) not valid;
alter table public.chick_weights
  add constraint chick_weights_replicate_positive
  check (replicate is null or replicate > 0) not valid;
alter table public.chick_quality validate constraint chick_quality_replicate_positive;
alter table public.chick_weights validate constraint chick_weights_replicate_positive;

create or replace function chickmark_private.prepare_chick_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  lock_key text;
begin
  new.domain := coalesce(nullif(btrim(new.domain), ''),
    case tg_table_name when 'chick_weights' then 'chicks.weights'
      else 'chicks.legacy_combined' end);
  new.schema_version := case when new.schema_version is not null and new.schema_version > 0
    then new.schema_version else 1 end;
  new.scope_type := case
    when tg_table_name = 'chick_weights' and new.scope_type in ('pool','house')
      then new.scope_type
    when tg_table_name = 'chick_quality' and new.scope_type in ('pool','setter_hatcher')
      then new.scope_type
    when tg_table_name = 'chick_weights' and nullif(btrim(new.house), '') is not null
      then 'house'
    when tg_table_name = 'chick_quality' and (
      nullif(btrim(new.setter), '') is not null or nullif(btrim(new.hatcher), '') is not null
    ) then 'setter_hatcher'
    else 'pool'
  end;
  new.scope_key := coalesce(nullif(btrim(new.scope_key), ''),
    chickmark_private.chick_scope_key(
      new.scope_type, coalesce(new.house, ''), coalesce(new.setter, ''),
      coalesce(new.hatcher, ''), coalesce(new.trolley, ''),
      coalesce(new.tray, ''), coalesce(new.position, '')
    ));
  new.source := coalesce(nullif(btrim(new.source), ''), 'legacy');
  new.capture_method := coalesce(nullif(btrim(new.capture_method), ''), 'unknown');
  new.observed_at := coalesce(new.observed_at, new.created_at, new.updated_at);

  lock_key := concat_ws('|', tg_table_name, new.customer_id, new.session_id,
    new.domain, new.scope_type, new.scope_key);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(lock_key, 0)
  );
  if new.replicate is null or new.replicate < 1
     or new.sample_key is distinct from chickmark_private.chick_sample_key(
       new.domain, new.session_id, new.scope_type, new.scope_key, new.replicate
     )
     or exists (
       select 1 from public.chick_quality q
       where tg_table_name = 'chick_quality'
         and q.customer_id = new.customer_id and q.sample_key = new.sample_key
         and q.id <> new.id
     )
     or exists (
       select 1 from public.chick_weights w
       where tg_table_name = 'chick_weights'
         and w.customer_id = new.customer_id and w.sample_key = new.sample_key
         and w.id <> new.id
     ) then
    execute format(
      'select coalesce(max(replicate), 0) + 1 from public.%I '
      'where customer_id = $1 and session_id = $2 and domain = $3 '
      'and scope_type = $4 and scope_key = $5',
      tg_table_name
    ) into new.replicate using
      new.customer_id, new.session_id, new.domain, new.scope_type, new.scope_key;
    new.sample_key := chickmark_private.chick_sample_key(
      new.domain, new.session_id, new.scope_type, new.scope_key, new.replicate
    );
  end if;
  return new;
end
$fn$;

revoke all on function chickmark_private.prepare_chick_identity()
  from public, anon, authenticated;

drop trigger if exists chick_quality_prepare_agent_identity on public.chick_quality;
drop trigger if exists chick_quality_prepare_identity on public.chick_quality;
create trigger chick_quality_prepare_identity
before insert on public.chick_quality
for each row execute function chickmark_private.prepare_chick_identity();

drop trigger if exists chick_weights_prepare_agent_identity on public.chick_weights;
drop trigger if exists chick_weights_prepare_identity on public.chick_weights;
create trigger chick_weights_prepare_identity
before insert on public.chick_weights
for each row execute function chickmark_private.prepare_chick_identity();

create or replace function chickmark_private.guard_chick_identity_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if (new.domain, new.schema_version, new.scope_type, new.scope_key,
      new.replicate, new.sample_key)
     is distinct from
     (old.domain, old.schema_version, old.scope_type, old.scope_key,
      old.replicate, old.sample_key) then
    raise exception 'Chick sample identity is immutable';
  end if;
  return new;
end
$fn$;

revoke all on function chickmark_private.guard_chick_identity_update()
  from public, anon, authenticated;

drop trigger if exists chick_quality_guard_identity_update on public.chick_quality;
create trigger chick_quality_guard_identity_update
before update on public.chick_quality
for each row execute function chickmark_private.guard_chick_identity_update();

drop trigger if exists chick_weights_guard_identity_update on public.chick_weights;
create trigger chick_weights_guard_identity_update
before update on public.chick_weights
for each row execute function chickmark_private.guard_chick_identity_update();
