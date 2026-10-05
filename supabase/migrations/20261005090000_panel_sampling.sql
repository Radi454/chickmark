-- Panel-scoped sampling state, independent branch sync, and offline serial repair.

create table if not exists public.panel_sampling_states (
  id text primary key,
  session_id text not null references public.audit_sessions(id) on delete cascade,
  panel_key text not null,
  serial_high_watermark integer not null default 0,
  created_at text not null,
  updated_at text not null,
  sync_status text not null default 'pending',
  dirty_at text,
  last_synced_at text,
  sync_error text,
  unique (session_id, panel_key)
);

create table if not exists public.panel_sampling_nodes (
  id text primary key,
  session_id text not null references public.audit_sessions(id) on delete cascade,
  panel_key text not null,
  parent_id text not null default '',
  level text not null,
  identity_key text not null default '',
  identity_json text,
  sample_id text,
  sample_number integer,
  is_terminal integer not null default 0,
  created_at text not null,
  updated_at text not null,
  sync_status text not null default 'pending',
  dirty_at text,
  last_synced_at text,
  sync_error text
);

create table if not exists public.panel_sample_serial_reservations (
  id text primary key,
  session_id text not null references public.audit_sessions(id) on delete cascade,
  panel_key text not null,
  sample_number integer not null,
  sample_id text not null,
  created_at text not null,
  sync_status text not null default 'pending',
  dirty_at text,
  last_synced_at text,
  sync_error text,
  unique (session_id, panel_key, sample_id)
);

create unique index if not exists idx_panel_sampling_node_identity
  on public.panel_sampling_nodes
    (session_id, panel_key, parent_id, level, identity_key)
  where is_terminal = 0;
create index if not exists idx_panel_sampling_node_number
  on public.panel_sampling_nodes (session_id, panel_key, sample_number);
create index if not exists idx_panel_serial_reservation_number
  on public.panel_sample_serial_reservations
    (session_id, panel_key, sample_number);

-- IDs and measurements stay owned by the existing panel rows. Null metadata on
-- historical rows is intentional: their identities must not be guessed.
do $$
declare
  panel_table text;
begin
  foreach panel_table in array array[
    'egg_storage', 'egg_quality', 'chick_quality', 'chick_weights',
    'fresh_egg_breakout', 'candled_egg_breakout', 'residue_breakout',
    'setter_optimizing', 'hatcher_optimizing'
  ] loop
    execute format('alter table public.%I add column if not exists sample_id text', panel_table);
    execute format('alter table public.%I add column if not exists sample_number integer', panel_table);
    execute format('alter table public.%I add column if not exists sampling_path_json text', panel_table);
  end loop;
end;
$$;

alter table public.customers add column if not exists sampling_code text;
alter table public.hatcheries add column if not exists sampling_code text;
alter table public.flocks add column if not exists sampling_code text;

alter table public.panel_sampling_states enable row level security;
alter table public.panel_sampling_nodes enable row level security;
alter table public.panel_sample_serial_reservations enable row level security;

grant select, insert, update, delete on public.panel_sampling_states to authenticated;
grant select, insert, update, delete on public.panel_sampling_nodes to authenticated;
grant select, insert, update, delete on public.panel_sample_serial_reservations to authenticated;

drop policy if exists panel_sampling_states_select on public.panel_sampling_states;
create policy panel_sampling_states_select on public.panel_sampling_states
  for select to authenticated using (
    exists (
      select 1 from public.audit_sessions s
      where s.id = session_id
        and chickmark_private.app_can_read_customer(s.customer_id)
    )
  );
drop policy if exists panel_sampling_states_write on public.panel_sampling_states;
create policy panel_sampling_states_write on public.panel_sampling_states
  for all to authenticated using (
    exists (
      select 1 from public.audit_sessions s
      where s.id = session_id
        and chickmark_private.app_can_write_customer(s.customer_id)
    )
  ) with check (
    exists (
      select 1 from public.audit_sessions s
      where s.id = session_id
        and chickmark_private.app_can_write_customer(s.customer_id)
    )
  );

drop policy if exists panel_sampling_nodes_select on public.panel_sampling_nodes;
create policy panel_sampling_nodes_select on public.panel_sampling_nodes
  for select to authenticated using (
    exists (
      select 1 from public.audit_sessions s
      where s.id = session_id
        and chickmark_private.app_can_read_customer(s.customer_id)
    )
  );
drop policy if exists panel_sampling_nodes_write on public.panel_sampling_nodes;
create policy panel_sampling_nodes_write on public.panel_sampling_nodes
  for all to authenticated using (
    exists (
      select 1 from public.audit_sessions s
      where s.id = session_id
        and chickmark_private.app_can_write_customer(s.customer_id)
    )
  ) with check (
    exists (
      select 1 from public.audit_sessions s
      where s.id = session_id
        and chickmark_private.app_can_write_customer(s.customer_id)
    )
  );

drop policy if exists panel_sample_serial_reservations_select on public.panel_sample_serial_reservations;
create policy panel_sample_serial_reservations_select
  on public.panel_sample_serial_reservations
  for select to authenticated using (
    exists (
      select 1 from public.audit_sessions s
      where s.id = session_id
        and chickmark_private.app_can_read_customer(s.customer_id)
    )
  );
drop policy if exists panel_sample_serial_reservations_write on public.panel_sample_serial_reservations;
create policy panel_sample_serial_reservations_write
  on public.panel_sample_serial_reservations
  for all to authenticated using (
    exists (
      select 1 from public.audit_sessions s
      where s.id = session_id
        and chickmark_private.app_can_write_customer(s.customer_id)
    )
  ) with check (
    exists (
      select 1 from public.audit_sessions s
      where s.id = session_id
        and chickmark_private.app_can_write_customer(s.customer_id)
    )
  );

-- Generic row sync may send an older client snapshot after a newer serial
-- has already been consumed. Never lower the merged serial fence.
create or replace function chickmark_private.keep_panel_sampling_high_watermark()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    new.serial_high_watermark := greatest(
      old.serial_high_watermark,
      new.serial_high_watermark
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_panel_sampling_state_high_watermark
  on public.panel_sampling_states;
create trigger trg_panel_sampling_state_high_watermark
  before update of serial_high_watermark on public.panel_sampling_states
  for each row execute function
    chickmark_private.keep_panel_sampling_high_watermark();

-- Reconciled serials are permanent. A stale offline reservation cannot lower
-- the server assignment when generic row sync next uploads that sample.
create or replace function chickmark_private.keep_panel_sample_serial()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.sample_number := greatest(old.sample_number, new.sample_number);
  return new;
end;
$$;

drop trigger if exists trg_panel_sample_reserved_serial
  on public.panel_sample_serial_reservations;
create trigger trg_panel_sample_reserved_serial
  before update of sample_number on public.panel_sample_serial_reservations
  for each row execute function chickmark_private.keep_panel_sample_serial();

-- A security-invoker RPC keeps the normal RLS boundary and serializes repair
-- per session/panel. The lexicographically smallest sample ID keeps a
-- contested serial; other active samples move above every consumed serial.
create or replace function public.reconcile_panel_sample_serials(
  p_session_id text,
  p_panel_key text
)
returns table(sample_id text, sample_number integer)
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_high_watermark integer;
  collision record;
  loser record;
begin
  if not exists (
    select 1
    from public.audit_sessions s
    where s.id = p_session_id
      and chickmark_private.app_can_write_customer(s.customer_id)
  ) then
    raise exception 'Not authorized to reconcile sampling serials';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_session_id || ':' || p_panel_key, 0)
  );

  -- Ensure live terminal samples have durable reservations before collision
  -- checks. A reservation with no active node is a consumed/deleted serial.
  insert into public.panel_sample_serial_reservations (
    id, session_id, panel_key, sample_number, sample_id, created_at,
    sync_status, dirty_at
  )
  select n.sample_id, n.session_id, n.panel_key, n.sample_number, n.sample_id,
         now()::text, 'pending', now()::text
  from public.panel_sampling_nodes n
  where n.session_id = p_session_id and n.panel_key = p_panel_key
    and n.is_terminal = 1 and n.sample_id is not null
    and n.sample_number is not null
  on conflict (session_id, panel_key, sample_id) do update
  set sample_number = greatest(
        panel_sample_serial_reservations.sample_number,
        excluded.sample_number
      ),
      sync_status = 'pending',
      dirty_at = excluded.dirty_at
  where panel_sample_serial_reservations.sample_number
    is distinct from excluded.sample_number;

  -- Nodes may have arrived from an older offline snapshot. Reservations retain
  -- the authoritative assignment even when the incoming node serial is lower.
  update public.panel_sampling_nodes n
  set sample_number = r.sample_number,
      updated_at = now()::text,
      sync_status = 'pending',
      dirty_at = now()::text
  from public.panel_sample_serial_reservations r
  where n.session_id = p_session_id and n.panel_key = p_panel_key
    and n.is_terminal = 1 and n.sample_id = r.sample_id
    and r.session_id = n.session_id and r.panel_key = n.panel_key
    and n.sample_number < r.sample_number;

  select greatest(
    coalesce((select max(st.serial_high_watermark)
      from public.panel_sampling_states st
      where st.session_id = p_session_id and st.panel_key = p_panel_key), 0),
    coalesce((select max(n.sample_number)
      from public.panel_sampling_nodes n
      where n.session_id = p_session_id and n.panel_key = p_panel_key
        and n.is_terminal = 1), 0),
    coalesce((select max(r.sample_number)
      from public.panel_sample_serial_reservations r
      where r.session_id = p_session_id and r.panel_key = p_panel_key), 0)
  ) into v_high_watermark;

  for collision in
    select r.sample_number,
           min(r.sample_id collate "C") as winner_sample_id,
           bool_or(not exists (
             select 1 from public.panel_sampling_nodes active_node
             where active_node.session_id = p_session_id
               and active_node.panel_key = p_panel_key
               and active_node.is_terminal = 1
               and active_node.sample_id = r.sample_id
           )) as has_deleted_reservation
    from public.panel_sample_serial_reservations r
    where r.session_id = p_session_id and r.panel_key = p_panel_key
    group by r.sample_number
    having count(distinct r.sample_id) > 1
    order by r.sample_number
  loop
    for loser in
      select n.id, n.sample_id
      from public.panel_sampling_nodes n
      where n.session_id = p_session_id and n.panel_key = p_panel_key
        and n.is_terminal = 1 and n.sample_number = collision.sample_number
        and (
          collision.has_deleted_reservation
          or n.sample_id collate "C" > collision.winner_sample_id collate "C"
        )
      order by n.sample_id collate "C"
    loop
      v_high_watermark := v_high_watermark + 1;
      update public.panel_sampling_nodes n
      set sample_number = v_high_watermark,
          updated_at = now()::text,
          sync_status = 'pending',
          dirty_at = now()::text
      where n.id = loser.id;

      update public.panel_sample_serial_reservations r
      set sample_number = v_high_watermark,
          sync_status = 'pending',
          dirty_at = now()::text
      where r.session_id = p_session_id and r.panel_key = p_panel_key
        and r.sample_id = loser.sample_id;
    end loop;
  end loop;

  insert into public.panel_sampling_states (
    id, session_id, panel_key, serial_high_watermark, created_at, updated_at,
    sync_status, dirty_at
  ) values (
    p_session_id || ':' || p_panel_key, p_session_id, p_panel_key,
    v_high_watermark, now()::text, now()::text, 'pending', now()::text
  ) on conflict (session_id, panel_key) do update
  set serial_high_watermark = greatest(
        public.panel_sampling_states.serial_high_watermark,
        excluded.serial_high_watermark
      ),
      updated_at = excluded.updated_at,
      sync_status = 'pending',
      dirty_at = excluded.dirty_at;

  return query
  select n.sample_id, n.sample_number
  from public.panel_sampling_nodes n
  where n.session_id = p_session_id and n.panel_key = p_panel_key
    and n.is_terminal = 1 and n.sample_id is not null
  order by n.sample_id collate "C";
end;
$$;

revoke all on function public.reconcile_panel_sample_serials(text, text)
  from public, anon;
grant execute on function public.reconcile_panel_sample_serials(text, text)
  to authenticated;
