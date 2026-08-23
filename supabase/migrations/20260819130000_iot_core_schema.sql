-- IoT core schema: hubs, sensors, telemetry, events, commands, config, firmware.
--
-- Contract: docs/IOT_API_CONTRACT.md section 9. Read that before changing anything here.
--
-- Three rules this migration exists to enforce, all learned in review:
--   1. A device credential never lives on a tenant-writable table. RLS has no
--      column granularity, so a table staff can UPDATE is a table where staff can
--      overwrite a password hash.
--   2. Every child row is tied to its hub by a composite (hub_id, customer_id)
--      foreign key. Checking only customer_id lets a user who legitimately owns
--      customer A attach a row to customer B's hub.
--   3. RLS is enabled on every telemetry partition, not just the parent.
--      CREATE TABLE ... PARTITION OF inherits neither relrowsecurity nor the
--      parent's policies, and a query naming a partition directly bypasses the
--      parent entirely. Queries through the parent keep working perfectly, which
--      is what makes this so easy to miss.
--
-- Hashing uses encode(sha256(convert_to(x,'UTF8')),'hex'). All pg_catalog, so it
-- resolves under search_path = '' and needs no extension. Do NOT reach for
-- pgcrypto's digest(): it lives in the extensions schema (unresolvable at an
-- empty search_path) and is absent from the migration-replay harness.

-- ---------------------------------------------------------------------------
-- 1. Registry and hub identity
-- ---------------------------------------------------------------------------

create table if not exists public.iot_hub_registry (
  hub_serial           text primary key,
  factory_secret_hash  text not null,
  claim_code_hash      text not null,
  hardware_model       text not null,
  manufactured_at      timestamptz not null default now(),
  claimed_at           timestamptz,
  claim_attempts       integer not null default 0,
  claim_locked_until   timestamptz,
  notes                text
);
alter table public.iot_hub_registry enable row level security;
alter table public.iot_hub_registry force  row level security;
revoke all on public.iot_hub_registry from anon, authenticated;

create table if not exists public.iot_hubs (
  id                 uuid primary key default gen_random_uuid(),
  hub_serial         text not null references public.iot_hub_registry(hub_serial),
  customer_id        text not null references public.customers(id) on delete cascade,
  hatchery_id        text references public.hatcheries(id) on delete set null,
  name               text not null default '',
  hardware_model     text not null,
  firmware_version   text,
  status             text not null default 'active'
                       check (status in ('active','revoked','retired')),
  config_version     integer not null default 1,
  topology_hash      text,
  last_seen_at       timestamptz,
  last_telemetry_at  timestamptz,
  last_heartbeat     jsonb not null default '{}'::jsonb,
  claimed_by         uuid references public.profiles(id) on delete set null,
  claimed_at         timestamptz not null default now(),
  revoked_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint iot_hubs_id_customer_uk unique (id, customer_id)
);
-- Serial is unique among LIVE hubs only, so a retired hub can be re-claimed.
create unique index if not exists idx_iot_hubs_serial_live
  on public.iot_hubs (hub_serial) where status <> 'retired';
create index if not exists idx_iot_hubs_customer
  on public.iot_hubs (customer_id, hatchery_id);
create index if not exists idx_iot_hubs_hatchery_fk
  on public.iot_hubs (hatchery_id) where hatchery_id is not null;

-- Credentials live OUT of the tenant table, in the locked-down private schema.
create table if not exists chickmark_private.iot_hub_secrets (
  hub_id             uuid primary key references public.iot_hubs(id) on delete cascade,
  device_secret_hash text,
  secret_rotated_at  timestamptz,
  rotate_requested   boolean not null default false,
  espnow_pmk         text,
  updated_at         timestamptz not null default now()
);
alter table chickmark_private.iot_hub_secrets enable row level security;
alter table chickmark_private.iot_hub_secrets force  row level security;
revoke all on chickmark_private.iot_hub_secrets from anon, authenticated;

create table if not exists chickmark_private.iot_device_tokens (
  token_hash text primary key,
  hub_id     uuid not null references public.iot_hubs(id) on delete cascade,
  issued_at  timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz
);
alter table chickmark_private.iot_device_tokens enable row level security;
alter table chickmark_private.iot_device_tokens force  row level security;
revoke all on chickmark_private.iot_device_tokens from anon, authenticated;
create index if not exists idx_iot_device_tokens_hub
  on chickmark_private.iot_device_tokens (hub_id);
create index if not exists idx_iot_device_tokens_expiry
  on chickmark_private.iot_device_tokens (expires_at) where revoked_at is null;

-- ---------------------------------------------------------------------------
-- 2. Sensors and metric vocabulary
-- ---------------------------------------------------------------------------

create table if not exists public.iot_sensors (
  id               uuid primary key default gen_random_uuid(),
  hub_id           uuid not null,
  customer_id      text not null references public.customers(id) on delete cascade,
  sensor_uid       text not null,
  model            text,
  firmware_version text,
  capabilities     jsonb not null default '[]'::jsonb,
  hatchery_id      text references public.hatcheries(id) on delete set null,
  station_key      text not null default '',
  place            text not null default '',
  machine_id       text not null default '',
  label            text not null default '',
  status           text not null default 'unassigned'
                     check (status in ('unassigned','active','offline','retired')),
  battery_percent  integer,
  last_rssi        integer,
  first_seen_at    timestamptz not null default now(),
  last_seen_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint iot_sensors_hub_uid_uk unique (hub_id, sensor_uid),
  constraint iot_sensors_id_customer_uk unique (id, customer_id),
  constraint iot_sensors_hub_customer_fk
    foreign key (hub_id, customer_id)
    references public.iot_hubs(id, customer_id) on delete cascade
);
create index if not exists idx_iot_sensors_customer
  on public.iot_sensors (customer_id, hatchery_id, station_key);
create index if not exists idx_iot_sensors_hub on public.iot_sensors (hub_id);

create table if not exists public.iot_metric_registry (
  metric_key    text primary key,
  unit          text not null,
  display_name  text not null,
  category      text not null,
  min_plausible double precision,
  max_plausible double precision,
  is_active     boolean not null default true
);
alter table public.iot_metric_registry enable row level security;

-- ---------------------------------------------------------------------------
-- 3. Telemetry (partitioned) and batch idempotency
-- ---------------------------------------------------------------------------

create table if not exists public.iot_telemetry (
  customer_id     text not null,
  hub_id          uuid not null,
  sensor_id       uuid not null,
  measured_at     timestamptz not null,
  ingested_at     timestamptz not null default now(),
  batch_id        text not null,
  metrics         jsonb not null,
  quality         text not null default 'ok'
                    check (quality in ('ok','suspect','estimated')),
  battery_percent integer,
  rssi            integer,
  primary key (sensor_id, measured_at),
  constraint iot_telemetry_sensor_customer_fk
    foreign key (sensor_id, customer_id) references public.iot_sensors(id, customer_id)
) partition by range (measured_at);

create index if not exists idx_iot_telemetry_scope
  on public.iot_telemetry (customer_id, sensor_id, measured_at desc);

-- Creates a monthly partition AND enables RLS on it. Always use this helper --
-- a hand-written CREATE TABLE ... PARTITION OF silently produces a partition
-- with no row security, readable cross-tenant through PostgREST.
create or replace function chickmark_private.iot_add_telemetry_partition(p_month date)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_name text := 'iot_telemetry_' || to_char(p_month, 'YYYY_MM');
  v_from date := date_trunc('month', p_month)::date;
begin
  execute format(
    'create table if not exists public.%I partition of public.iot_telemetry
       for values from (%L) to (%L)',
    v_name, v_from, (v_from + interval '1 month')::date);
  execute format('alter table public.%I enable row level security', v_name);
  execute format('alter table public.%I force  row level security', v_name);
  execute format('revoke all on public.%I from anon', v_name);
end $$;
revoke execute on function chickmark_private.iot_add_telemetry_partition(date) from public, anon, authenticated;

-- Default partition: a missed maintenance run degrades to "rows landed in the
-- wrong place" instead of a fleet-wide ingest outage.
create table if not exists public.iot_telemetry_default
  partition of public.iot_telemetry default;
alter table public.iot_telemetry_default enable row level security;
alter table public.iot_telemetry_default force  row level security;
revoke all on public.iot_telemetry_default from anon;

do $$
declare i integer;
begin
  for i in -1..3 loop
    perform chickmark_private.iot_add_telemetry_partition(
      (date_trunc('month', now()) + (i || ' month')::interval)::date);
  end loop;
end $$;

-- Private, because the device-facing batch counter is guessable
-- (<hub_serial>-<seq>). A tenant able to pre-insert rows here could make a
-- victim hub's real uploads answer duplicate:true, and the device would then
-- delete them without them ever being stored.
create table if not exists chickmark_private.iot_telemetry_batches (
  hub_id        uuid not null references public.iot_hubs(id) on delete cascade,
  batch_id      text not null,
  received_at   timestamptz not null default now(),
  reading_count integer not null,
  accepted      integer not null default 0,
  primary key (hub_id, batch_id)
);
alter table chickmark_private.iot_telemetry_batches enable row level security;
alter table chickmark_private.iot_telemetry_batches force row level security;
revoke all on chickmark_private.iot_telemetry_batches from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Events, commands, config, firmware
-- ---------------------------------------------------------------------------

create table if not exists public.iot_device_events (
  id          uuid primary key default gen_random_uuid(),
  customer_id text not null references public.customers(id) on delete cascade,
  hub_id      uuid not null,
  sensor_id   uuid references public.iot_sensors(id) on delete set null,
  event_id    text not null,
  event_type  text not null,
  severity    text not null default 'info'
                check (severity in ('info','warning','critical')),
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  detail      jsonb not null default '{}'::jsonb,
  acknowledged_at timestamptz,
  acknowledged_by uuid references public.profiles(id) on delete set null,
  constraint iot_device_events_hub_event_uk unique (hub_id, event_id),
  constraint iot_device_events_hub_customer_fk
    foreign key (hub_id, customer_id)
    references public.iot_hubs(id, customer_id) on delete cascade
);
create index if not exists idx_iot_device_events_scope
  on public.iot_device_events (customer_id, severity, occurred_at desc);
create index if not exists idx_iot_device_events_sensor_fk
  on public.iot_device_events (sensor_id) where sensor_id is not null;

create table if not exists public.iot_commands (
  id           uuid primary key default gen_random_uuid(),
  customer_id  text not null references public.customers(id) on delete cascade,
  hub_id       uuid not null,
  command_type text not null,
  params       jsonb not null default '{}'::jsonb,
  status       text not null default 'pending'
                 check (status in ('pending','delivered','acked','succeeded','failed','expired','cancelled','unsupported')),
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default (now() + interval '1 hour'),
  delivered_at timestamptz,
  acked_at     timestamptz,
  completed_at timestamptz,
  result       jsonb,
  error_code   text,
  error_message text,
  attempt_count integer not null default 0,
  constraint iot_commands_hub_customer_fk
    foreign key (hub_id, customer_id)
    references public.iot_hubs(id, customer_id) on delete cascade
);
create index if not exists idx_iot_commands_pending
  on public.iot_commands (hub_id, created_at)
  where status in ('pending','delivered');
create index if not exists idx_iot_commands_scope
  on public.iot_commands (customer_id, created_at desc);
create index if not exists idx_iot_commands_created_by_fk
  on public.iot_commands (created_by) where created_by is not null;

create table if not exists public.iot_hub_config (
  hub_id      uuid primary key,
  customer_id text not null references public.customers(id) on delete cascade,
  version     integer not null default 1,
  doc         jsonb not null default '{}'::jsonb,
  updated_by  uuid references public.profiles(id) on delete set null,
  updated_at  timestamptz not null default now(),
  constraint iot_hub_config_hub_customer_fk
    foreign key (hub_id, customer_id)
    references public.iot_hubs(id, customer_id) on delete cascade
);
create index if not exists idx_iot_hub_config_updated_by_fk
  on public.iot_hub_config (updated_by) where updated_by is not null;

-- Fleet-wide defaults, resolved server-side. Service-role only: a 'global' row
-- here reconfigures every customer's hardware.
create table if not exists chickmark_private.iot_config_defaults (
  id          uuid primary key default gen_random_uuid(),
  scope_kind  text not null check (scope_kind in ('global','hardware_model','customer','hatchery')),
  scope_value text,
  doc         jsonb not null default '{}'::jsonb,
  priority    integer not null default 0,
  updated_at  timestamptz not null default now(),
  check ((scope_kind = 'global') = (scope_value is null)),
  constraint iot_config_defaults_scope_uk unique (scope_kind, scope_value)
);
alter table chickmark_private.iot_config_defaults enable row level security;
alter table chickmark_private.iot_config_defaults force row level security;
revoke all on chickmark_private.iot_config_defaults from anon, authenticated;

create table if not exists public.iot_firmware_releases (
  id               uuid primary key default gen_random_uuid(),
  hardware_model   text not null,
  target           text not null default 'hub' check (target in ('hub','sensor')),
  version          text not null,
  channel          text not null default 'stable' check (channel in ('dev','beta','stable')),
  storage_path     text not null,
  size_bytes       bigint not null,
  sha256           text not null,
  signature        text not null,
  signature_alg    text not null default 'ed25519-sha256',
  min_from_version text,
  rollout_percent  integer not null default 0 check (rollout_percent between 0 and 100),
  is_active        boolean not null default false,
  release_notes    text,
  created_at       timestamptz not null default now(),
  constraint iot_firmware_releases_uk unique (hardware_model, target, version, channel)
);
alter table public.iot_firmware_releases enable row level security;
alter table public.iot_firmware_releases force  row level security;
revoke all on public.iot_firmware_releases from anon, authenticated;

create table if not exists public.iot_firmware_updates (
  id            uuid primary key default gen_random_uuid(),
  customer_id   text not null references public.customers(id) on delete cascade,
  hub_id        uuid not null,
  release_id    uuid references public.iot_firmware_releases(id) on delete cascade,
  target        text not null default 'hub',
  sensor_id     uuid references public.iot_sensors(id) on delete set null,
  status        text not null default 'offered'
                  check (status in ('offered','downloading','verifying','applying','succeeded','failed','rolled_back')),
  from_version  text,
  to_version    text not null,
  error_code    text,
  error_message text,
  offered_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint iot_firmware_updates_hub_customer_fk
    foreign key (hub_id, customer_id)
    references public.iot_hubs(id, customer_id) on delete cascade
);
create index if not exists idx_iot_firmware_updates_hub
  on public.iot_firmware_updates (hub_id, offered_at desc);
create index if not exists idx_iot_firmware_updates_release_fk
  on public.iot_firmware_updates (release_id) where release_id is not null;
create index if not exists idx_iot_firmware_updates_sensor_fk
  on public.iot_firmware_updates (sensor_id) where sensor_id is not null;
