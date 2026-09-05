-- 0013 breeder daily report aggregate push (breeder-flock-performance
-- ticket 15, design doc section 13.1)
--
-- A daily report is not a row; it is a header plus bird movements, feed
-- entries, egg production entries, and inventory movements. A revision
-- number on the header alone would not protect those children if they were
-- pushed independently, because a stale child could land after a winning
-- header. So the whole aggregate travels in ONE call, guarded by a
-- concurrency token, and this function replaces the report's entire child
-- set inside one transaction (a Postgres function body is one transaction
-- already; there is no explicit BEGIN/COMMIT to write).
--
-- Optimistic concurrency uses `breeder_daily_reports.sync_token`, NOT the
-- `revision` column, and the two must never be conflated:
--
-- - `revision` (ticket 12) is the user-facing audit counter. It advances
--   only on a state transition or a post-approval correction, and its
--   value is meaningful to a human reading revision history. An ordinary
--   background sync push must never change it as a side effect — this
--   function stores whatever `revision` value the client sends, verbatim,
--   and never computes or increments it itself.
-- - `sync_token` is this function's own opaque concurrency counter. It
--   advances by exactly one on every successful aggregate push, REGARDLESS
--   of whether that push changed `revision` at all.
--
-- Why a revision-based check is not enough by itself: two devices can both
-- hold a report at the same `revision` (neither has transitioned or
-- corrected it) and each edit a different child row offline. Both would
-- then present the same `base_revision`, both would "match" a
-- revision-based comparison, and the second push's delete-then-reinsert
-- would silently destroy the first device's already-accepted children with
-- no conflict ever raised — exactly the hole design section 13 and
-- acceptance criterion 8 forbid. Gating on `sync_token` instead closes it:
-- the first accepted push immediately advances the stored token, so the
-- second device's now-stale token can never match again, even though its
-- `revision` still would have.
--
-- The caller passes `base_revision` (the name is kept from the original
-- shape of this function; its value is this device's last known
-- `sync_token`, stored locally as `lastSyncedRevision` — see local
-- migration v79). If the report already exists in the cloud and its
-- current `sync_token` does not match `base_revision`, the push is
-- REJECTED — nothing is written — and the function returns the cloud's
-- current full aggregate (including its `sync_token`, via `to_jsonb(r.*)`)
-- so the caller can preserve both versions in `sync_conflicts` (a
-- local-only table; it is never mirrored to Supabase), put the report into
-- its local `Sync Conflict` state, and — if a manager resolves the
-- conflict by keeping the local version — adopt the returned `sync_token`
-- as the next `base_revision` before retrying. A first-ever push for a
-- report (no cloud row yet) always succeeds regardless of `base_revision`
-- and starts `sync_token` at 1. On success this function returns the new
-- `sync_token` so the caller can record it as its new `lastSyncedRevision`.
--
-- Authorization happens inside the function (SECURITY DEFINER, so it can
-- read/write across the row set inside one statement) rather than relying
-- solely on the row-level-security policies on the underlying tables, which
-- still apply for ordinary reads and for defense in depth. A caller who
-- cannot write the report's flock gets a permission error and nothing is
-- written.
--
-- This function does not enforce the approval-role check from design
-- section 5.3 ("the Supabase policy for the approval transition checks the
-- actor's role") — the client never reaches `approved` here except via
-- whatever state was already validated client-side, and per
-- `breeder_bird_ledger_service.dart`'s own comment that Supabase-side
-- approval-role enforcement is ticket 16's, not this one's.
--
-- This file is deliberately NOT applied by this change — see
-- supabase/migrations_unapplied/README.md. Apply after 0012.

create or replace function public.push_breeder_daily_report_aggregate(
  payload jsonb,
  base_revision integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_header jsonb := payload->'header';
  v_report_id text := v_header->>'id';
  v_flock_id text := v_header->>'flock_id';
  -- The client's own audit-counter value, stored verbatim — this function
  -- never derives or increments `revision` itself.
  v_client_revision integer := coalesce((v_header->>'revision')::integer, 1);
  v_current_token integer;
  v_new_token integer;
  v_cloud jsonb;
  v_movements jsonb := coalesce(payload->'movements', '[]'::jsonb);
  v_feed jsonb := coalesce(payload->'feed_entries', '[]'::jsonb);
  v_egg jsonb := coalesce(payload->'egg_production_entries', '[]'::jsonb);
  v_inv jsonb := coalesce(payload->'inventory_movements', '[]'::jsonb);
begin
  if v_report_id is null or v_report_id = '' then
    raise exception 'push_breeder_daily_report_aggregate: header.id is required';
  end if;
  if v_flock_id is null or v_flock_id = '' then
    raise exception 'push_breeder_daily_report_aggregate: header.flock_id is required';
  end if;
  if not chickmark_private.app_can_write_flock(v_flock_id) then
    raise exception 'not authorized to write flock %', v_flock_id using errcode = '42501';
  end if;

  -- Lock the header row (if it exists) for the duration of this function so
  -- two concurrent pushes for the same report cannot both pass the token
  -- check before either has written.
  select sync_token into v_current_token
  from public.breeder_daily_reports
  where id = v_report_id
  for update;

  if found and v_current_token is distinct from base_revision then
    select jsonb_build_object(
      'header', to_jsonb(r.*),
      'movements', coalesce((
        select jsonb_agg(to_jsonb(m.*)) from public.breeder_bird_movements m
        where m.report_id = v_report_id
      ), '[]'::jsonb),
      'feed_entries', coalesce((
        select jsonb_agg(to_jsonb(fe.*)) from public.breeder_feed_entries fe
        where fe.report_id = v_report_id
      ), '[]'::jsonb),
      'egg_production_entries', coalesce((
        select jsonb_agg(to_jsonb(e.*)) from public.breeder_egg_production_entries e
        where e.report_id = v_report_id
      ), '[]'::jsonb),
      'inventory_movements', coalesce((
        select jsonb_agg(to_jsonb(iv.*)) from public.breeder_egg_inventory_movements iv
        where iv.report_id = v_report_id
      ), '[]'::jsonb)
    )
    into v_cloud
    from public.breeder_daily_reports r
    where r.id = v_report_id;

    return jsonb_build_object('conflict', true, 'cloud', v_cloud);
  end if;

  v_new_token := coalesce(v_current_token, 0) + 1;

  insert into public.breeder_daily_reports as t (
    id, flock_id, report_date, inside_temperature, outside_temperature, light_hours,
    notes, state, revision, sync_token, created_by, submitted_by, submitted_at, approved_by,
    approved_at, egg_production_denominator_females, benchmark_profile_version_at_approval,
    comparison_axis_at_approval, created_at, updated_at
  ) values (
    v_report_id, v_flock_id, v_header->>'report_date',
    (v_header->>'inside_temperature')::double precision,
    (v_header->>'outside_temperature')::double precision,
    (v_header->>'light_hours')::double precision,
    v_header->>'notes',
    coalesce(v_header->>'state', 'draft'),
    v_client_revision,
    v_new_token,
    v_header->>'created_by', v_header->>'submitted_by', v_header->>'submitted_at',
    v_header->>'approved_by', v_header->>'approved_at',
    (v_header->>'egg_production_denominator_females')::integer,
    v_header->>'benchmark_profile_version_at_approval',
    v_header->>'comparison_axis_at_approval',
    coalesce(v_header->>'created_at', now()::text),
    coalesce(v_header->>'updated_at', now()::text)
  )
  on conflict (id) do update set
    flock_id = excluded.flock_id,
    report_date = excluded.report_date,
    inside_temperature = excluded.inside_temperature,
    outside_temperature = excluded.outside_temperature,
    light_hours = excluded.light_hours,
    notes = excluded.notes,
    state = excluded.state,
    revision = excluded.revision,
    sync_token = excluded.sync_token,
    created_by = excluded.created_by,
    submitted_by = excluded.submitted_by,
    submitted_at = excluded.submitted_at,
    approved_by = excluded.approved_by,
    approved_at = excluded.approved_at,
    egg_production_denominator_females = excluded.egg_production_denominator_females,
    benchmark_profile_version_at_approval = excluded.benchmark_profile_version_at_approval,
    comparison_axis_at_approval = excluded.comparison_axis_at_approval,
    updated_at = excluded.updated_at;

  -- "The cloud side replaces the whole child set for that report" (design
  -- section 13.1) — delete-then-reinsert rather than a diff, so a row the
  -- client deleted locally cannot survive as an orphan.
  delete from public.breeder_bird_movements where report_id = v_report_id;
  delete from public.breeder_feed_entries where report_id = v_report_id;
  delete from public.breeder_egg_production_entries where report_id = v_report_id;
  delete from public.breeder_egg_inventory_movements where report_id = v_report_id;

  insert into public.breeder_bird_movements (
    id, report_id, house_id, isolation_area_id, sex, opening, mortality, culls, sale,
    kitchen_removal, euthanasia, transfer_in, transfer_out, closing, created_at, updated_at
  )
  select
    m->>'id', v_report_id, m->>'house_id', m->>'isolation_area_id', m->>'sex',
    (m->>'opening')::integer, (m->>'mortality')::integer, (m->>'culls')::integer,
    (m->>'sale')::integer, (m->>'kitchen_removal')::integer, (m->>'euthanasia')::integer,
    (m->>'transfer_in')::integer, (m->>'transfer_out')::integer, (m->>'closing')::integer,
    coalesce(m->>'created_at', now()::text), coalesce(m->>'updated_at', now()::text)
  from jsonb_array_elements(v_movements) as m;

  insert into public.breeder_feed_entries (
    id, report_id, house_id, isolation_area_id, sex, feed_kg, created_at, updated_at
  )
  select
    f->>'id', v_report_id, f->>'house_id', f->>'isolation_area_id', f->>'sex',
    (f->>'feed_kg')::double precision,
    coalesce(f->>'created_at', now()::text), coalesce(f->>'updated_at', now()::text)
  from jsonb_array_elements(v_feed) as f;

  insert into public.breeder_egg_production_entries (
    id, report_id, house_id, isolation_area_id, grade_id, count, egg_weight_grams,
    created_at, updated_at
  )
  select
    e->>'id', v_report_id, e->>'house_id', e->>'isolation_area_id', e->>'grade_id',
    (e->>'count')::integer, (e->>'egg_weight_grams')::double precision,
    coalesce(e->>'created_at', now()::text), coalesce(e->>'updated_at', now()::text)
  from jsonb_array_elements(v_egg) as e;

  insert into public.breeder_egg_inventory_movements (
    id, report_id, grade_id, kind, quantity, adjustment_direction, reason, actor_user_id,
    occurred_at, reversed_movement_id, created_at, updated_at
  )
  select
    iv->>'id', v_report_id, iv->>'grade_id', iv->>'kind', (iv->>'quantity')::integer,
    iv->>'adjustment_direction', iv->>'reason', iv->>'actor_user_id', iv->>'occurred_at',
    iv->>'reversed_movement_id',
    coalesce(iv->>'created_at', now()::text), coalesce(iv->>'updated_at', now()::text)
  from jsonb_array_elements(v_inv) as iv;

  return jsonb_build_object('conflict', false, 'sync_token', v_new_token);
end;
$$;

revoke all on function public.push_breeder_daily_report_aggregate(jsonb, integer) from public, anon;
grant execute on function public.push_breeder_daily_report_aggregate(jsonb, integer) to authenticated;
