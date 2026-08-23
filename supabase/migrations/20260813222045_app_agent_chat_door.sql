-- 20260814120000 app agent chat door
--
-- Adds a SECOND door into the existing unified agent brain. Until now the only
-- caller was the Telegram webhook, so `public.telegram_staff_links` was a
-- Telegram-only identity table and every agent conversation hung off a Telegram
-- user. The in-app assistant (`app-hatchery-agent` Edge Function) reuses the
-- exact same brain, the same `agent_conversations` / `agent_conversation_turns`
-- / `agent_tool_events` tables, and the same tool catalog. It only needs a
-- staff-link row to hang a conversation off, so this migration teaches
-- `telegram_staff_links` to also represent a signed-in app user.
--
-- What changes:
--   * `channel` distinguishes a Telegram row from an app row. Existing rows
--     default to 'telegram', so the Telegram path is untouched.
--   * `app_user_id` points at `auth.users` for app rows.
--   * `telegram_user_id` becomes nullable (app rows have none). Its UNIQUE
--     constraint becomes a partial unique index so multiple app rows can share
--     a NULL Telegram id.
--   * A channel shape check keeps the two identities mutually exclusive.
--   * `telegram_staff_links_allowed_scope_check` is relaxed for app rows only:
--     an app row with access_role='customer' may carry a NULL customer_id.
--     That is deliberate. A Telegram row stores its single allowed customer in
--     the column, but an app caller's real allow-list is computed at request
--     time from `public.profiles` and `public.auditor_customers` (an auditor
--     may read many customers, which one column cannot express). The app row is
--     an identity anchor, NOT the authorization record; the Edge Function
--     recomputes `AgentScope.allowedCustomerIds` on every request.
--
-- Idempotent: safe to re-run.

begin;

alter table public.telegram_staff_links
  add column if not exists channel text not null default 'telegram',
  add column if not exists app_user_id uuid
    references auth.users(id) on delete cascade;

alter table public.telegram_staff_links
  alter column telegram_user_id drop not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'telegram_staff_links_channel_check'
      and conrelid = 'public.telegram_staff_links'::regclass
  ) then
    alter table public.telegram_staff_links
      add constraint telegram_staff_links_channel_check
      check (channel in ('telegram', 'app'));
  end if;
end
$$;

-- The original table declared `telegram_user_id text not null unique`, which
-- Postgres materialised as a plain unique constraint. Replace it with a partial
-- unique index so NULL-bearing app rows are simply not indexed.
do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'telegram_staff_links_telegram_user_id_key'
      and conrelid = 'public.telegram_staff_links'::regclass
  ) then
    alter table public.telegram_staff_links
      drop constraint telegram_staff_links_telegram_user_id_key;
  end if;
end
$$;

create unique index if not exists idx_telegram_staff_links_telegram_user
  on public.telegram_staff_links(telegram_user_id)
  where telegram_user_id is not null;

create unique index if not exists idx_telegram_staff_links_app_user
  on public.telegram_staff_links(app_user_id)
  where app_user_id is not null;

-- A row is either a Telegram identity or an app identity, never both.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'telegram_staff_links_channel_identity_check'
      and conrelid = 'public.telegram_staff_links'::regclass
  ) then
    alter table public.telegram_staff_links
      add constraint telegram_staff_links_channel_identity_check
      check (
        (
          channel = 'telegram'
          and telegram_user_id is not null
          and app_user_id is null
        )
        or (
          channel = 'app'
          and app_user_id is not null
          and telegram_user_id is null
        )
      );
  end if;
end
$$;

-- Relax the allowed-scope check for app rows only. See the header comment: an
-- app row's allow-list is recomputed per request from profiles /
-- auditor_customers, so a customer-role app row may legitimately have a NULL
-- customer_id (an auditor maps to many customers). Telegram rows keep the
-- original, stricter rule.
alter table public.telegram_staff_links
  drop constraint if exists telegram_staff_links_allowed_scope_check;

alter table public.telegram_staff_links
  add constraint telegram_staff_links_allowed_scope_check
  check (
    status <> 'allowed'
    or (
      channel = 'app'
      and (
        access_role = 'customer'
        or (access_role = 'admin' and customer_id is null)
      )
    )
    or (access_role = 'customer' and customer_id is not null)
    or (access_role = 'admin' and customer_id is null)
  );

create index if not exists idx_telegram_staff_links_channel
  on public.telegram_staff_links(channel);

comment on column public.telegram_staff_links.channel is
  'Which door this identity belongs to: telegram webhook or in-app assistant.';
comment on column public.telegram_staff_links.app_user_id is
  'auth.users id for channel=app rows. NULL for Telegram rows.';

commit;
