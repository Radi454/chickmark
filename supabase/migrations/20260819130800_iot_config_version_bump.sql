-- Make config_version actually change when the config changes.
--
-- The whole config-push mechanism rests on one firmware rule: "if the
-- config_version in a heartbeat or telemetry response differs from the one you
-- stored, call GET /v1/config". Nothing incremented iot_hub_config.version, so
-- it sat at 1 forever and a hub would never refetch. Staff could edit a hub's
-- configuration in the app and the hardware would never hear about it.
--
-- Two triggers:
--   1. Editing a hub's own config row bumps that row's version.
--   2. Editing a fleet-default layer bumps every hub the layer resolves onto,
--      because the hub is served a flattened document and cannot tell which
--      layer a value came from.

create or replace function chickmark_private.iot_bump_hub_config_version()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.doc is distinct from old.doc then
    new.version := old.version + 1;
    new.updated_at := now();
  end if;
  return new;
end $$;

drop trigger if exists iot_hub_config_bump_version on public.iot_hub_config;
create trigger iot_hub_config_bump_version
before update on public.iot_hub_config
for each row execute function chickmark_private.iot_bump_hub_config_version();

-- Mirror the version onto iot_hubs so a reader that only has the hub row (the
-- app's fleet list, for instance) sees the same number the device does.
create or replace function chickmark_private.iot_mirror_config_version()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.iot_hubs h
     set config_version = new.version, updated_at = now()
   where h.id = new.hub_id and h.config_version is distinct from new.version;
  return null;
end $$;

drop trigger if exists iot_hub_config_mirror_version on public.iot_hub_config;
create trigger iot_hub_config_mirror_version
after insert or update on public.iot_hub_config
for each row execute function chickmark_private.iot_mirror_config_version();

-- A fleet-default layer changed: bump every hub it applies to. `global` touches
-- the whole fleet, which is deliberate and is why iot_config_defaults is
-- service-role only.
create or replace function chickmark_private.iot_bump_scoped_config_versions()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_kind  text := coalesce(new.scope_kind, old.scope_kind);
  v_value text := coalesce(new.scope_value, old.scope_value);
begin
  update public.iot_hub_config c
     set version = c.version + 1, updated_at = now()
   where exists (
     select 1 from public.iot_hubs h
      where h.id = c.hub_id
        and (
          v_kind = 'global'
          or (v_kind = 'hardware_model' and h.hardware_model = v_value)
          or (v_kind = 'customer'       and h.customer_id    = v_value)
          or (v_kind = 'hatchery'       and h.hatchery_id    = v_value)
        )
   );
  return null;
end $$;

drop trigger if exists iot_config_defaults_bump on public.iot_config_defaults;
create trigger iot_config_defaults_bump
after insert or update or delete on public.iot_config_defaults
for each row execute function chickmark_private.iot_bump_scoped_config_versions();

-- These are trigger functions. Nobody calls them directly.
revoke execute on function chickmark_private.iot_bump_hub_config_version() from public, anon, authenticated;
revoke execute on function chickmark_private.iot_mirror_config_version() from public, anon, authenticated;
revoke execute on function chickmark_private.iot_bump_scoped_config_versions() from public, anon, authenticated;
