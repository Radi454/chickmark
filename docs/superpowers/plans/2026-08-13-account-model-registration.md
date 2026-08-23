# Email Registration + Personal/Organization Account Model — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace username-based signup with email registration that forks into a Personal account (immediate access after email confirmation, benchmarks only) or an Organization account (org code + email confirmation, then approval by that organization's own admin).

**Architecture:** A new `public.organizations` tenant table carries the join code. `public.profiles` gains three additive columns (`account_type`, `organization_id`, `org_role`) plus a new `role` value `'personal'` — nothing existing is repurposed, so every current RLS predicate keeps its exact meaning. Signup metadata (`account_type`, `org_code`) is resolved inside the existing `handle_new_auth_user` trigger, which raises on a bad code so signup fails atomically. Org-admin approval and promotion happen through two `SECURITY DEFINER` RPCs (not table UPDATE policies) so an org admin can never touch `role`, `customer_id`, or `organization_id`. The Flutter side adds an account-type chooser ahead of `/register`, reuses the existing `/pending-approval` route and `AuthState.pendingApproval`, and gates the shell tabs for personal accounts.

**Tech Stack:** Flutter 3 / Dart, Provider, sqflite (local v57 → v58), Supabase (Postgres + RLS + Deno Edge Functions), `mocktail` + `flutter_test`, `sqflite_common_ffi` for DB tests.

---

## Recon report (what already exists — read this before Task 1)

The REQ asked for this. Findings against the live code, not the spec text:

| REQ claim | Reality in code |
|---|---|
| "`/pending-approval` route and a pending user state appear" | **True and fully wired.** `/pending-approval` is a real route in [app.dart:190](lib/app.dart:190), listed in `_preAppRouteNames` ([app.dart:246](lib/app.dart:246)). `AuthState.pendingApproval` exists ([auth_provider.dart:18](lib/features/auth/providers/auth_provider.dart:18)) and `login()` already routes to it when `!user.isApproved` ([auth_provider.dart:101](lib/features/auth/providers/auth_provider.dart:101)). [pending_approval_screen.dart](lib/features/auth/screens/pending_approval_screen.dart) exists (175 lines). **Reuse all of it.** |
| "customers log in by username" | True. [customer_account_identifier.dart](lib/core/auth/customer_account_identifier.dart) maps `username` → `username@customers.chickmark.app`. `AuthProvider.login` calls `loginEmail()` on every sign-in. Live customer accounts exist with these synthetic addresses. |
| "`reset-customer-password` Edge Function exists" | True: [supabase/functions/reset-customer-password/index.ts](supabase/functions/reset-customer-password/index.ts). Called from `AdminRepository.resetCustomerPassword` ([admin_repository.dart:111](lib/data/repositories/admin_repository.dart:111)), surfaced by `_ResetCustomerPasswordSheet` in [admin_users_screen.dart:668](lib/features/admin/screens/admin_users_screen.dart:668). The "ask your admin" copy lives in [login_screen.dart:88](lib/features/auth/screens/login_screen.dart:88). |

Things the REQ did **not** mention that materially shape the design:

1. **No organization/tenant-code concept exists anywhere.** Zero hits for `organization` across `lib/`, `supabase/`, `LIVING_SPEC.md`. Built from scratch.
2. **`profiles.role` is constrained to `('admin','auditor','customer')`** ([0003_auth_rls.sql:19](supabase/migrations/0003_auth_rls.sql:19)) and is the input to `app_is_admin()` / `app_is_staff()` / `app_can_read_customer()` / `app_can_write_customer()`.
3. **`app_is_staff()` = `role in ('admin','auditor') and status='approved'`** and it gates **write** access on 22 policy sites (shared bmk reference rows, performance objectives). Therefore a Personal account **must not** be `role='auditor' + approved` — that would silently grant write on shared reference data. This is why Task 1 adds a new role value `'personal'` instead of reusing `'auditor'`.
4. **`create-customer-account` also exists** and also mints `@customers.chickmark.app` identities. The REQ only orders removal of `reset-customer-password`, so `create-customer-account` **stays** — see Open Decision D3.
5. **The local SQLite `users` table** ([database_schema.dart:7](lib/data/database/database_schema.dart:7)) mirrors `UserModel`; DB version is **57** ([database_helper.dart:47](lib/data/database/database_helper.dart:47)) with real per-version `_applyVNNUpgrade` handlers and a `@visibleForTesting applyVNNUpgradeForTest` hook per version. This plan bumps to **58**.
6. **`profiles` is not part of the offline sync set** — `AdminRepository` talks to Supabase directly and says so ([admin_repository.dart:45](lib/data/repositories/admin_repository.dart:45)). Organizations follow the same rule: online-only, never synced.
7. **`AuthProvider.registerLocalFallback`** creates offline accounts with `status: 'approved'` ([auth_provider.dart:198](lib/features/auth/providers/auth_provider.dart:198)). Under the new model an offline-created org account would self-approve. Task 6 closes that.

## Open decisions — resolve before starting Task 1

These change what gets built. Ask the user; do not guess silently.

- **D1 — Does an organization link to an existing `public.customers` row?** This plan assumes **yes, required**: the super-admin picks (or creates) the customer record when creating the org, and `organizations.customer_id` is `not null`. That is what lets org employees inherit today's per-tenant read scope with zero RLS churn. If orgs must be able to exist with no customer data, say so — employees then land with benchmarks-only access like Personal.
- **D2 — Email confirmation is a Supabase Auth dashboard setting**, not code. "Confirm email" must be ON for the project, and the iOS deep-link redirect URL must be allowlisted, or confirmation links dead-end in a browser. Task 10 covers verification; the toggle itself is a human step.
- **D3 — Legacy `@customers.chickmark.app` accounts have no mailbox**, so Supabase's password-reset email cannot reach them. The REQ says manual resets go through the Supabase dashboard. This plan therefore keeps username→email login mapping for sign-in (existing users keep working) and shows those users an explicit "contact your ChickMark administrator" message on Forgot Password, rather than pretending an email was sent. `create-customer-account` stays so admins can still mint those identities; if it should go too, that is a separate pass.

## Global Constraints

- **No existing security check may be weakened.** Every change to `supabase/migrations/` is additive: new tables, new columns, new policies, new `SECURITY DEFINER` functions. Do not edit or drop any existing policy, and do not change the body of `app_is_admin`, `app_is_staff`, `app_can_read_customer`, `app_can_write_customer`, or `chickmark_private.*`.
- **Auth tokens stay in the iOS Keychain exactly as today.** Do not touch `UserRepository.migrateRemoteTokensToSecureStorage` or `cacheToken`.
- **Every new SQL function gets explicit grants**, matching [0008_explicit_function_revokes.sql](supabase/migrations/0008_explicit_function_revokes.sql): `revoke execute ... from public, anon, authenticated;` then `grant execute ... to <exact role>;`.
- **Password policy is 12+ chars with lower, upper, digit, symbol** — `PasswordPolicy.minLength = 12` ([password_policy.dart](lib/core/security/password_policy.dart)). Client and any Edge Function must agree.
- **New migrations use the timestamp naming scheme** already in use: `supabase/migrations/2026MMDDHHMMSS_<name>.sql`.
- **Local DB goes 57 → 58 exactly once.** One `_applyV58Upgrade`, one `applyV58UpgradeForTest`, one `if (oldVersion < 58)` branch. Both `database_schema.dart` (fresh install) and the upgrade path must produce identical columns — there is a parity test and it must stay green.
- **Organizations and profiles are online-only.** Never add them to the sync set, tombstones, or dirty-tracking.
- **Copy strings** go through `AppStrings` ([app_strings.dart](lib/core/constants/app_strings.dart)) where the surrounding screen already uses it.
- **Run after every task:** `flutter analyze` (zero new issues) and `flutter test` (all green). A red analyze or test blocks the commit.

---

### Task 1: Organizations table + profile columns + code lookup (SQL)

Adds the schema and the anonymous code-lookup RPC. No app code yet.

**Files:**
- Create: `supabase/migrations/20260813090000_organizations_and_account_types.sql`
- Reference (read, do not edit): `supabase/migrations/0003_auth_rls.sql`, `supabase/migrations/0008_explicit_function_revokes.sql`

**Interfaces:**
- Consumes: existing `public.profiles`, `public.customers`, `public.app_is_admin()`.
- Produces:
  - table `public.organizations(id uuid, name text, code text, customer_id text, created_by uuid, created_at timestamptz, updated_at timestamptz)`
  - `public.profiles.account_type text` in `('internal','personal','organization')`, default `'internal'`
  - `public.profiles.organization_id uuid` null
  - `public.profiles.org_role text` in `('first_admin','admin','member')` null
  - `public.profiles.role` check widened to include `'personal'`
  - `public.generate_organization_code() returns text` (service_role only)
  - `public.lookup_organization_by_code(p_code text) returns text` — org name or null, granted to `anon` and `authenticated`

- [ ] **Step 1: Write the migration**

```sql
-- 20260813090000 organizations + account types
--
-- Additive only. Existing roles, policies and helper functions are untouched:
-- 'personal' is a NEW role value that no existing predicate matches, so a
-- personal account inherits zero write scope (app_is_staff stays admin/auditor).

-- ============================ organizations ============================
create table if not exists public.organizations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  code        text not null,
  customer_id text not null references public.customers(id) on delete restrict,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists organizations_code_upper_unique
  on public.organizations (upper(code));
alter table public.organizations
  drop constraint if exists organizations_code_format;
alter table public.organizations
  add constraint organizations_code_format check (code ~ '^[A-Z0-9]{8}$');
alter table public.organizations enable row level security;

drop trigger if exists organizations_touch on public.organizations;
create trigger organizations_touch before update on public.organizations
  for each row execute function public.touch_updated_at();

-- ============================ profile columns ============================
alter table public.profiles
  add column if not exists account_type text not null default 'internal';
alter table public.profiles
  add column if not exists organization_id uuid references public.organizations(id) on delete set null;
alter table public.profiles
  add column if not exists org_role text;

alter table public.profiles drop constraint if exists profiles_account_type_check;
alter table public.profiles add constraint profiles_account_type_check
  check (account_type in ('internal','personal','organization'));

alter table public.profiles drop constraint if exists profiles_org_role_check;
alter table public.profiles add constraint profiles_org_role_check
  check (org_role is null or org_role in ('first_admin','admin','member'));

-- org membership is only meaningful for organization accounts
alter table public.profiles drop constraint if exists profiles_org_consistency;
alter table public.profiles add constraint profiles_org_consistency check (
  (account_type = 'organization' and organization_id is not null and org_role is not null)
  or (account_type <> 'organization' and organization_id is null and org_role is null)
);

-- widen role: 'personal' is new and matches no existing policy predicate
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in ('admin','auditor','customer','personal'));

create index if not exists idx_profiles_organization on public.profiles(organization_id);

-- ============================ code generation ============================
create or replace function public.generate_organization_code()
  returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no I/O/0/1
  candidate text;
  attempt int := 0;
begin
  loop
    attempt := attempt + 1;
    candidate := '';
    for _i in 1..8 loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.organizations o where upper(o.code) = candidate);
    if attempt > 50 then
      raise exception 'Could not allocate a unique organization code.';
    end if;
  end loop;
  return candidate;
end;
$$;
revoke execute on function public.generate_organization_code() from public, anon, authenticated;
grant execute on function public.generate_organization_code() to service_role;

-- ============================ anonymous code lookup ============================
-- Returns only the organization NAME so the registration screen can confirm the
-- code before signup. The code is not a secret (every employee holds it) and no
-- other column is exposed.
create or replace function public.lookup_organization_by_code(p_code text)
  returns text language sql stable security definer set search_path = '' as $$
  select o.name from public.organizations o
   where upper(o.code) = upper(trim(p_code))
   limit 1;
$$;
revoke execute on function public.lookup_organization_by_code(text) from public;
grant execute on function public.lookup_organization_by_code(text) to anon, authenticated;

-- ============================ organizations policies ============================
-- Zoetis super-admin manages orgs. Members may read only their own org row.
drop policy if exists organizations_admin_all on public.organizations;
create policy organizations_admin_all on public.organizations for all to authenticated
  using (public.app_is_admin()) with check (public.app_is_admin());

drop policy if exists organizations_member_read on public.organizations;
create policy organizations_member_read on public.organizations for select to authenticated
  using (id = (select p.organization_id from public.profiles p where p.id = auth.uid()));
```

- [ ] **Step 2: Apply the migration and verify constraints hold**

Run against the dev project (`supabase db push`, or the Supabase MCP `apply_migration` with this file's contents).

Then verify — expected results in comments:

```sql
select code ~ '^[A-Z0-9]{8}$' as ok, length(code) = 8 as len
  from (select public.generate_organization_code() as code) t;  -- ok=t, len=t

select public.lookup_organization_by_code('NOSUCH01');          -- null

-- personal role is now legal, garbage still rejected
select 'personal' in ('admin','auditor','customer','personal'); -- t
```

- [ ] **Step 3: Verify no existing policy changed**

Run: `git diff --stat supabase/migrations/`
Expected: exactly one new file, zero modified files.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260813090000_organizations_and_account_types.sql
git commit -m "feat(auth): add organizations table and profile account-type columns"
```

---

### Task 2: Signup trigger routes personal vs organization (SQL)

Makes `auth.signUp` metadata decide the resulting profile. Invalid org code aborts signup.

**Files:**
- Create: `supabase/migrations/20260813091000_signup_account_routing.sql`
- Reference: `supabase/migrations/0009_customer_usernames.sql` (current trigger body)

**Interfaces:**
- Consumes: `public.organizations`, the new profile columns from Task 1.
- Produces: replacement `public.handle_new_auth_user()` reading `raw_user_meta_data->>'account_type'` and `->>'org_code'`. Contract:
  - `account_type='personal'` → `role='personal'`, `status='approved'`, `account_type='personal'`
  - `account_type='organization'` → resolves `org_code`; on miss raises `ORG_CODE_INVALID`; on hit `role='customer'`, `status='pending'`, `account_type='organization'`, `org_role='member'`, `organization_id`, `customer_id = organizations.customer_id`
  - anything else (including absent metadata) → today's behaviour verbatim: `role='auditor'`, `status='pending'`, `account_type='internal'`

- [ ] **Step 1: Write the migration**

```sql
-- 20260813091000 signup account routing
--
-- Replaces handle_new_auth_user so registration metadata picks the account
-- model. The legacy branch (no account_type in metadata) is byte-for-byte the
-- behaviour from 0009 so existing Edge Function signups are unaffected.

create or replace function public.handle_new_auth_user()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_account_type text := nullif(new.raw_user_meta_data->>'account_type', '');
  v_org_code     text := nullif(trim(new.raw_user_meta_data->>'org_code'), '');
  v_org          public.organizations%rowtype;
begin
  if v_account_type = 'personal' then
    insert into public.profiles (id, full_name, email, role, status, account_type)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'full_name', new.email),
      new.email,
      'personal',
      'approved',
      'personal'
    )
    on conflict (id) do nothing;
    return new;
  end if;

  if v_account_type = 'organization' then
    select * into v_org from public.organizations o
     where upper(o.code) = upper(v_org_code)
     limit 1;
    if not found then
      raise exception 'ORG_CODE_INVALID';
    end if;

    insert into public.profiles (
      id, full_name, email, role, status, account_type,
      organization_id, org_role, customer_id
    )
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'full_name', new.email),
      new.email,
      'customer',
      'pending',
      'organization',
      v_org.id,
      'member',
      v_org.customer_id
    )
    on conflict (id) do nothing;
    return new;
  end if;

  -- legacy path, unchanged from 0009
  insert into public.profiles (id, full_name, email, username, role, status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email,
    nullif(lower(new.raw_user_meta_data->>'username'), ''),
    'auditor',
    'pending'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_auth_user() from public, anon, authenticated;
grant execute on function public.handle_new_auth_user() to service_role;
```

- [ ] **Step 2: Apply and verify all three branches**

Apply the migration, then in the SQL editor create a throwaway org and exercise each branch through `auth.admin` (or the dashboard "Add user" with raw metadata). Expected:

```sql
-- after a personal signup
select role, status, account_type, organization_id
  from public.profiles where email = 'personal-probe@example.com';
-- personal | approved | personal | null

-- after an organization signup with a valid code
select role, status, account_type, org_role, organization_id is not null as linked
  from public.profiles where email = 'org-probe@example.com';
-- customer | pending | organization | member | t
```

A signup carrying `account_type='organization'` with a bogus code must fail with `ORG_CODE_INVALID` and leave **no** row in `auth.users` — confirm with:

```sql
select count(*) from auth.users where email = 'bad-code-probe@example.com';  -- 0
```

- [ ] **Step 3: Clean up probe rows**

```sql
delete from auth.users where email in
  ('personal-probe@example.com','org-probe@example.com');
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260813091000_signup_account_routing.sql
git commit -m "feat(auth): route signup metadata to personal or organization profiles"
```

---

### Task 3: Org admin approval + promotion RPCs (SQL)

The three-tier authority model. RPCs, not UPDATE policies — an org admin must never be able to rewrite `role`, `customer_id`, or `organization_id`.

**Files:**
- Create: `supabase/migrations/20260813092000_org_admin_rpcs.sql`

**Interfaces:**
- Consumes: profile columns from Task 1.
- Produces:
  - `public.app_org_id() returns uuid` — caller's `organization_id`
  - `public.app_org_role() returns text` — caller's `org_role`
  - `public.list_org_members() returns table(id uuid, full_name text, email text, status text, org_role text, created_at timestamptz)`
  - `public.approve_org_member(p_user_id uuid) returns void`
  - `public.promote_org_admin(p_user_id uuid) returns void`
  - policy `profiles_org_peer_read` on `public.profiles`

- [ ] **Step 1: Write the migration**

```sql
-- 20260813092000 org admin RPCs
--
-- Authority tiers:
--   first_admin -> approve members AND promote members to admin
--   admin       -> approve members only
--   member      -> nothing
-- Approval/promotion go through SECURITY DEFINER functions so an org admin can
-- only ever move status pending->approved or org_role member->admin. role,
-- customer_id and organization_id are never writable by them.

create or replace function public.app_org_id()
  returns uuid language sql stable security definer set search_path = '' as $$
  select p.organization_id from public.profiles p where p.id = auth.uid();
$$;
revoke execute on function public.app_org_id() from public, anon;
grant execute on function public.app_org_id() to authenticated;

create or replace function public.app_org_role()
  returns text language sql stable security definer set search_path = '' as $$
  select p.org_role from public.profiles p where p.id = auth.uid();
$$;
revoke execute on function public.app_org_role() from public, anon;
grant execute on function public.app_org_role() to authenticated;

-- org admins can see their own org's roster
drop policy if exists profiles_org_peer_read on public.profiles;
create policy profiles_org_peer_read on public.profiles for select to authenticated
  using (
    organization_id is not null
    and organization_id = public.app_org_id()
    and public.app_org_role() in ('first_admin','admin')
  );

create or replace function public.list_org_members()
  returns table (
    id uuid, full_name text, email text,
    status text, org_role text, created_at timestamptz
  )
  language sql stable security definer set search_path = '' as $$
  select p.id, p.full_name, p.email, p.status, p.org_role, p.created_at
    from public.profiles p
   where p.organization_id is not null
     and p.organization_id = public.app_org_id()
     and public.app_org_role() in ('first_admin','admin')
   order by p.status, p.created_at;
$$;
revoke execute on function public.list_org_members() from public, anon;
grant execute on function public.list_org_members() to authenticated;

create or replace function public.approve_org_member(p_user_id uuid)
  returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_caller_org  uuid := public.app_org_id();
  v_caller_role text := public.app_org_role();
begin
  if v_caller_org is null or v_caller_role not in ('first_admin','admin') then
    raise exception 'NOT_ORG_ADMIN';
  end if;
  update public.profiles
     set status = 'approved'
   where id = p_user_id
     and organization_id = v_caller_org
     and status = 'pending';
  if not found then
    raise exception 'MEMBER_NOT_PENDING_IN_ORG';
  end if;
end;
$$;
revoke execute on function public.approve_org_member(uuid) from public, anon;
grant execute on function public.approve_org_member(uuid) to authenticated;

create or replace function public.promote_org_admin(p_user_id uuid)
  returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_caller_org  uuid := public.app_org_id();
  v_caller_role text := public.app_org_role();
begin
  -- only the first admin may create admins; promoted admins cannot
  if v_caller_org is null or v_caller_role <> 'first_admin' then
    raise exception 'NOT_FIRST_ADMIN';
  end if;
  update public.profiles
     set org_role = 'admin'
   where id = p_user_id
     and organization_id = v_caller_org
     and org_role = 'member'
     and status = 'approved';
  if not found then
    raise exception 'MEMBER_NOT_PROMOTABLE';
  end if;
end;
$$;
revoke execute on function public.promote_org_admin(uuid) from public, anon;
grant execute on function public.promote_org_admin(uuid) to authenticated;
```

- [ ] **Step 2: Apply and verify the authority boundaries**

Apply, then seed one org with a `first_admin`, one `admin`, one pending `member`, and a `member` in a *second* org. Signed in as each, check:

| Caller | Call | Expected |
|---|---|---|
| first_admin | `select public.approve_org_member('<pending in own org>')` | succeeds, status → approved |
| first_admin | `select public.promote_org_admin('<approved member>')` | succeeds, org_role → admin |
| promoted admin | `select public.approve_org_member('<pending in own org>')` | succeeds |
| promoted admin | `select public.promote_org_admin('<member>')` | raises `NOT_FIRST_ADMIN` |
| member | `select public.approve_org_member(...)` | raises `NOT_ORG_ADMIN` |
| first_admin of org A | `select public.approve_org_member('<pending in org B>')` | raises `MEMBER_NOT_PENDING_IN_ORG` |

- [ ] **Step 3: Verify an org admin still cannot rewrite privileged columns**

Signed in as the org first_admin:

```sql
update public.profiles set role = 'admin' where id = auth.uid();
```

Expected: `0 rows` (no policy grants UPDATE on profiles to a non-`app_is_admin()` caller). If this updates a row, **stop** — a security check has been weakened.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260813092000_org_admin_rpcs.sql
git commit -m "feat(auth): add org admin approval and promotion RPCs"
```

---

### Task 4: Super-admin org creation Edge Function

Creates the organization, generates its code, and appoints the first admin — the chicken-and-egg step. Needs service-role, so it is an Edge Function, mirroring `create-customer-account`.

**Files:**
- Create: `supabase/functions/create-organization/index.ts`
- Reference: `supabase/functions/create-customer-account/index.ts` (caller-auth pattern to copy verbatim)

**Interfaces:**
- Consumes: `public.generate_organization_code()`, `public.organizations`, `public.profiles`.
- Produces: `POST create-organization`
  - request `{ name: string, customerId: string, adminEmail: string, adminFullName: string, adminPassword: string }`
  - success `200 { organization: { id, name, code, customerId }, firstAdmin: { id, email } }`
  - errors `{ error: string }` with 400 / 401 / 403 / 409

- [ ] **Step 1: Write the function**

```ts
import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json(405, { error: 'Method not allowed.' })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authorization = request.headers.get('Authorization')
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json(500, { error: 'Organization service is not configured.' })
  }
  if (!authorization) return json(401, { error: 'Sign in as an admin to create organizations.' })

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  })
  const { data: authData, error: authError } = await callerClient.auth.getUser()
  if (authError || !authData.user) return json(401, { error: 'Your admin session is not valid.' })

  const { data: callerProfile, error: profileError } = await callerClient
    .from('profiles').select('role, status').eq('id', authData.user.id).single()
  if (profileError || callerProfile?.role !== 'admin' || callerProfile?.status !== 'approved') {
    return json(403, { error: 'Only an approved admin can create organizations.' })
  }

  let body: Record<string, unknown>
  try { body = await request.json() } catch (_) { return json(400, { error: 'Invalid request body.' }) }

  const name = String(body.name ?? '').trim()
  const customerId = String(body.customerId ?? '').trim()
  const adminEmail = String(body.adminEmail ?? '').trim().toLowerCase()
  const adminFullName = String(body.adminFullName ?? '').trim()
  const adminPassword = String(body.adminPassword ?? '')

  if (!name) return json(400, { error: 'Organization name is required.' })
  if (!customerId) return json(400, { error: 'A linked customer is required.' })
  if (!adminFullName) return json(400, { error: "The first admin's name is required." })
  if (!adminEmail.includes('@')) return json(400, { error: 'Enter a valid admin email address.' })
  if (
    adminPassword.length < 12 ||
    !/[a-z]/.test(adminPassword) || !/[A-Z]/.test(adminPassword) ||
    !/[0-9]/.test(adminPassword) || !/[^A-Za-z0-9]/.test(adminPassword)
  ) {
    return json(400, {
      error: 'Password must be 12+ characters with uppercase, lowercase, number, and symbol.',
    })
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: customer } = await adminClient
    .from('customers').select('id').eq('id', customerId).maybeSingle()
  if (!customer) return json(400, { error: 'The selected customer no longer exists.' })

  const { data: code, error: codeError } = await adminClient.rpc('generate_organization_code')
  if (codeError || !code) return json(500, { error: 'Could not allocate an organization code.' })

  const { data: org, error: orgError } = await adminClient
    .from('organizations')
    .insert({ name, code, customer_id: customerId, created_by: authData.user.id })
    .select('id, name, code, customer_id')
    .single()
  if (orgError || !org) return json(400, { error: 'Could not create the organization.' })

  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email: adminEmail,
    password: adminPassword,
    email_confirm: true, // super-admin vouches for the first admin
    user_metadata: { full_name: adminFullName, account_type: 'organization', org_code: org.code },
  })
  if (createError || !created.user) {
    // do not leave a codeless orphan behind
    await adminClient.from('organizations').delete().eq('id', org.id)
    const duplicate = createError?.message?.toLowerCase().includes('already')
    return json(duplicate ? 409 : 400, {
      error: duplicate
        ? 'An account with that email already exists.'
        : 'Could not create the first admin account.',
    })
  }

  const { error: promoteError } = await adminClient
    .from('profiles')
    .update({ org_role: 'first_admin', status: 'approved' })
    .eq('id', created.user.id)
  if (promoteError) {
    await adminClient.auth.admin.deleteUser(created.user.id)
    await adminClient.from('organizations').delete().eq('id', org.id)
    return json(400, { error: 'Could not appoint the first admin.' })
  }

  return json(200, {
    organization: { id: org.id, name: org.name, code: org.code, customerId: org.customer_id },
    firstAdmin: { id: created.user.id, email: adminEmail },
  })
})
```

- [ ] **Step 2: Deploy and verify caller authorization**

Deploy (`supabase functions deploy create-organization`, or the Supabase MCP `deploy_edge_function`).

Call it with **no** Authorization header → expect `401 {"error":"Sign in as an admin to create organizations."}`
Call it as a non-admin signed-in user → expect `403 {"error":"Only an approved admin can create organizations."}`

- [ ] **Step 3: Verify the happy path end to end**

As an approved admin, POST a real body. Expected: `200` with an 8-char `code`, and:

```sql
select o.code, p.org_role, p.status, p.account_type
  from public.organizations o
  join public.profiles p on p.organization_id = o.id
 where o.name = '<name you posted>';
-- <CODE> | first_admin | approved | organization
```

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/create-organization/index.ts
git commit -m "feat(auth): add create-organization edge function"
```

---

### Task 5: Local schema v58 + UserModel account fields

Carries the new identity fields into the offline mirror so the shell can gate tabs without a network round trip.

**Files:**
- Modify: `lib/data/models/user_model.dart`
- Modify: `lib/data/database/database_schema.dart:7-18`
- Modify: `lib/data/database/database_helper.dart:47` (version), `:174-177` (upgrade chain), and add `_applyV58Upgrade` + `applyV58UpgradeForTest`
- Modify: `lib/services/supabase/supabase_service.dart:928-985` (`_buildUserFromAuth`)
- Test: `test/data/database/database_helper_migration_test.dart`, `test/data/models/user_model_test.dart` (create if absent)

**Interfaces:**
- Consumes: nothing new.
- Produces on `UserModel`: `final String accountType;` (default `'internal'`), `final String? organizationId;`, `final String? orgRole;`, plus getters `bool get isPersonalAccount`, `bool get isOrganizationAccount`, `bool get isOrgAdmin` (`orgRole` is `first_admin` or `admin`), `bool get isOrgFirstAdmin`. Local columns: `accountType TEXT`, `organizationId TEXT`, `orgRole TEXT`.

- [ ] **Step 1: Write the failing model test**

Create `test/data/models/user_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/user_model.dart';

void main() {
  UserModel build({
    String accountType = 'internal',
    String? orgRole,
    String? organizationId,
  }) => UserModel(
        id: 'u1',
        fullName: 'Test User',
        email: 'test@example.com',
        role: 'customer',
        status: 'approved',
        accountType: accountType,
        organizationId: organizationId,
        orgRole: orgRole,
        createdAt: DateTime(2026, 8, 13),
      );

  test('defaults to an internal account', () {
    expect(build().accountType, 'internal');
    expect(build().isPersonalAccount, isFalse);
    expect(build().isOrganizationAccount, isFalse);
  });

  test('personal account is flagged', () {
    expect(build(accountType: 'personal').isPersonalAccount, isTrue);
  });

  test('first admin is an org admin, member is not', () {
    final first = build(
      accountType: 'organization', organizationId: 'org-1', orgRole: 'first_admin');
    final promoted = build(
      accountType: 'organization', organizationId: 'org-1', orgRole: 'admin');
    final member = build(
      accountType: 'organization', organizationId: 'org-1', orgRole: 'member');

    expect(first.isOrgAdmin, isTrue);
    expect(first.isOrgFirstAdmin, isTrue);
    expect(promoted.isOrgAdmin, isTrue);
    expect(promoted.isOrgFirstAdmin, isFalse);
    expect(member.isOrgAdmin, isFalse);
  });

  test('round-trips the new fields through toMap/fromMap', () {
    final original = build(
      accountType: 'organization', organizationId: 'org-1', orgRole: 'admin');
    final restored = UserModel.fromMap(original.toMap());

    expect(restored.accountType, 'organization');
    expect(restored.organizationId, 'org-1');
    expect(restored.orgRole, 'admin');
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/data/models/user_model_test.dart`
Expected: FAIL — `No named parameter with the name 'accountType'`.

- [ ] **Step 3: Extend UserModel**

In `lib/data/models/user_model.dart`, add the fields, constructor params, map handling, and getters:

```dart
  final String accountType;
  final String? organizationId;
  final String? orgRole;
```

Constructor gains `this.accountType = 'internal', this.organizationId, this.orgRole,`.

In `fromMap`:

```dart
      accountType: map['accountType'] as String? ?? 'internal',
      organizationId: map['organizationId'] as String?,
      orgRole: map['orgRole'] as String?,
```

In `toMap`:

```dart
      'accountType': accountType,
      'organizationId': organizationId,
      'orgRole': orgRole,
```

Getters, next to the existing `isAdmin` / `isCustomer` block:

```dart
  bool get isPersonalAccount => accountType == 'personal';
  bool get isOrganizationAccount => accountType == 'organization';
  bool get isOrgAdmin => orgRole == 'first_admin' || orgRole == 'admin';
  bool get isOrgFirstAdmin => orgRole == 'first_admin';
```

- [ ] **Step 4: Run the model test**

Run: `flutter test test/data/models/user_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing migration test**

Append to `test/data/database/database_helper_migration_test.dart`, inside `main()`:

```dart
  test('v58 adds account model columns to users', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    // v57-shaped users table, without the new columns
    await db.execute('''CREATE TABLE users (
      id TEXT PRIMARY KEY,
      fullName TEXT,
      email TEXT UNIQUE,
      role TEXT,
      status TEXT,
      customerId TEXT,
      accessToken TEXT,
      tokenExpiry TEXT,
      createdAt TEXT,
      lastLoginAt TEXT
    )''');
    await db.insert('users', {'id': 'u1', 'email': 'legacy@example.com'});

    await DatabaseHelper().applyV58UpgradeForTest(db);

    final columns = (await db.rawQuery('PRAGMA table_info(users)'))
        .map((row) => row['name'] as String)
        .toSet();
    expect(columns, containsAll(['accountType', 'organizationId', 'orgRole']));

    final row = (await db.query('users', where: 'id = ?', whereArgs: ['u1'])).single;
    expect(row['accountType'], 'internal'); // existing users stay internal
  });
```

- [ ] **Step 6: Run it to confirm it fails**

Run: `flutter test test/data/database/database_helper_migration_test.dart -n "v58"`
Expected: FAIL — `applyV58UpgradeForTest` is not defined.

- [ ] **Step 7: Add the v58 upgrade and bump the version**

In `lib/data/database/database_helper.dart`, change `version: 57,` to `version: 58,`. Add to the end of `_onUpgrade`:

```dart
    if (oldVersion < 58) {
      await _applyV58Upgrade(db);
    }
```

Add the handler alongside the other `_applyVNNUpgrade` methods:

```dart
  Future<void> _applyV58Upgrade(Database db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(users)'))
        .map((row) => row['name'] as String)
        .toSet();
    if (!columns.contains('accountType')) {
      await db.execute(
        "ALTER TABLE users ADD COLUMN accountType TEXT NOT NULL DEFAULT 'internal'",
      );
    }
    if (!columns.contains('organizationId')) {
      await db.execute('ALTER TABLE users ADD COLUMN organizationId TEXT');
    }
    if (!columns.contains('orgRole')) {
      await db.execute('ALTER TABLE users ADD COLUMN orgRole TEXT');
    }
  }
```

Add the test hook next to `applyV57UpgradeForTest`:

```dart
  Future<void> applyV58UpgradeForTest(Database db) => _applyV58Upgrade(db);
```

And update the fresh-install schema in `lib/data/database/database_schema.dart` so the `users` table ends:

```dart
    createdAt TEXT,
    lastLoginAt TEXT,
    accountType TEXT NOT NULL DEFAULT 'internal',
    organizationId TEXT,
    orgRole TEXT
  )''');
```

- [ ] **Step 8: Run the DB tests, including parity**

Run: `flutter test test/data/database/`
Expected: PASS, all files. The fresh-install-vs-upgrade parity assertions must stay green — if they fail, `database_schema.dart` and `_applyV58Upgrade` disagree on column names or order.

- [ ] **Step 9: Carry the fields through the Supabase profile mapping**

In `lib/services/supabase/supabase_service.dart`, `_buildUserFromAuth` (around line 965) already camelizes profile keys via `_normalizeProfile`, so `account_type` arrives as `accountType`. Pass them into the constructed `UserModel`:

```dart
      accountType: normalizedProfile['accountType'] as String? ?? 'internal',
      organizationId: normalizedProfile['organizationId'] as String?,
      orgRole: normalizedProfile['orgRole'] as String?,
```

- [ ] **Step 10: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: zero new analyze issues, all tests pass.

- [ ] **Step 11: Commit**

```bash
git add lib/data/models/user_model.dart lib/data/database/database_schema.dart \
        lib/data/database/database_helper.dart lib/services/supabase/supabase_service.dart \
        test/data/models/user_model_test.dart test/data/database/database_helper_migration_test.dart
git commit -m "feat(auth): carry account type and org membership into the local user model"
```

---

### Task 6: AuthProvider — account-typed registration + email confirmation state

The provider learns the fork. `registerLocalFallback` stops being an approval bypass.

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart`
- Modify: `lib/services/supabase/supabase_service.dart:269-326` (`signUp`), plus a new `lookupOrganizationName`
- Test: `test/features/auth/auth_provider_test.dart`

**Interfaces:**
- Consumes: `UserModel.accountType` / `.organizationId` / `.orgRole` (Task 5); `public.lookup_organization_by_code` (Task 1).
- Produces:
  - `enum AccountType { personal, organization }` exported from `auth_provider.dart`
  - `AuthState.awaitingEmailConfirmation` — new enum value
  - `Future<bool> AuthProvider.register(String fullName, String email, String password, {required AccountType accountType, String? organizationCode})`
  - `Future<AuthResult> SupabaseService.signUp(String email, String password, String fullName, {required String accountType, String? organizationCode})`
  - `Future<String?> SupabaseService.lookupOrganizationName(String code)` — org name, or `null` when unknown/offline

- [ ] **Step 1: Write the failing provider tests**

Append to `test/features/auth/auth_provider_test.dart` inside `main()`:

```dart
  test('personal registration ends in awaitingEmailConfirmation', () async {
    when(() => mockSupabase.signUp(
          any(), any(), any(),
          accountType: any(named: 'accountType'),
          organizationCode: any(named: 'organizationCode'),
        )).thenAnswer((_) async => AuthResult(
          success: true,
          user: UserModel(
            id: 'p1',
            fullName: 'Personal User',
            email: email,
            role: 'personal',
            status: 'approved',
            accountType: 'personal',
            createdAt: DateTime.now(),
          ),
        ));
    when(() => mockRepo.upsertUser(any())).thenAnswer((_) async {});

    final ok = await provider.register(
      'Personal User', email, password,
      accountType: AccountType.personal,
    );

    expect(ok, isTrue);
    expect(provider.state, AuthState.awaitingEmailConfirmation);
    verify(() => mockSupabase.signUp(
          email, password, 'Personal User',
          accountType: 'personal',
          organizationCode: null,
        )).called(1);
  });

  test('organization registration forwards the code', () async {
    when(() => mockSupabase.signUp(
          any(), any(), any(),
          accountType: any(named: 'accountType'),
          organizationCode: any(named: 'organizationCode'),
        )).thenAnswer((_) async => AuthResult(
          success: true,
          user: UserModel(
            id: 'o1',
            fullName: 'Org User',
            email: email,
            role: 'customer',
            status: 'pending',
            accountType: 'organization',
            organizationId: 'org-1',
            orgRole: 'member',
            createdAt: DateTime.now(),
          ),
        ));
    when(() => mockRepo.upsertUser(any())).thenAnswer((_) async {});

    final ok = await provider.register(
      'Org User', email, password,
      accountType: AccountType.organization,
      organizationCode: 'ABCD2345',
    );

    expect(ok, isTrue);
    expect(provider.state, AuthState.awaitingEmailConfirmation);
    verify(() => mockSupabase.signUp(
          email, password, 'Org User',
          accountType: 'organization',
          organizationCode: 'ABCD2345',
        )).called(1);
  });

  test('an invalid organization code surfaces a readable error', () async {
    when(() => mockSupabase.signUp(
          any(), any(), any(),
          accountType: any(named: 'accountType'),
          organizationCode: any(named: 'organizationCode'),
        )).thenAnswer((_) async =>
            AuthResult(success: false, error: 'Database error: ORG_CODE_INVALID'));

    final ok = await provider.register(
      'Org User', email, password,
      accountType: AccountType.organization,
      organizationCode: 'BADCODE1',
    );

    expect(ok, isFalse);
    expect(provider.state, AuthState.error);
    expect(provider.errorMessage, "That organization code wasn't recognised.");
  });

  test('local fallback never self-approves an organization account', () async {
    when(() => mockRepo.getUserByEmail(any())).thenAnswer((_) async => null);
    when(() => mockRepo.upsertUser(any())).thenAnswer((_) async {});

    final ok = await provider.registerLocalFallback(
      'Org User', email,
      password: password,
      accountType: AccountType.organization,
    );

    expect(ok, isFalse);
    expect(
      provider.errorMessage,
      'Internet access is required to join an organization.',
    );
  });
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `flutter test test/features/auth/auth_provider_test.dart`
Expected: FAIL — `AccountType` undefined, `awaitingEmailConfirmation` undefined.

- [ ] **Step 3: Widen `SupabaseService.signUp` and add the code lookup**

In `lib/services/supabase/supabase_service.dart`, change the signature and the `auth.signUp` metadata:

```dart
  Future<AuthResult> signUp(
    String email,
    String password,
    String fullName, {
    required String accountType,
    String? organizationCode,
  }) async {
```

Replace the `_client.auth.signUp(...)` call with:

```dart
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'account_type': accountType,
          if (organizationCode != null && organizationCode.isNotEmpty)
            'org_code': organizationCode,
        },
      );
```

Replace the locally-built `UserModel` in `signUp` (currently hard-coded `role: 'auditor', status: 'approved'` — wrong under the new model) with values derived from the requested type:

```dart
      final isPersonal = accountType == 'personal';
      final user = UserModel(
        id: supabaseUser.id,
        fullName: fullName,
        email: email,
        role: isPersonal ? 'personal' : 'customer',
        status: isPersonal ? 'approved' : 'pending',
        accountType: accountType,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
```

Add next to `sendPasswordReset`:

```dart
  /// Confirms an organization code before signup. Returns the organization
  /// name, or null when the code is unknown or the device is offline.
  Future<String?> lookupOrganizationName(String code) async {
    try {
      if (!await _prepareRemoteAccess()) return null;
      final name = await _client.rpc(
        'lookup_organization_by_code',
        params: {'p_code': code},
      );
      return name as String?;
    } catch (e) {
      safeDebugLog('Organization code lookup failed', error: e);
      return null;
    }
  }
```

- [ ] **Step 4: Update AuthProvider**

In `lib/features/auth/providers/auth_provider.dart`:

```dart
enum AccountType { personal, organization }

extension AccountTypeWire on AccountType {
  String get wireValue => this == AccountType.personal ? 'personal' : 'organization';
}
```

Add `awaitingEmailConfirmation` to `AuthState` (place it after `authenticated` so existing switch statements are flagged by the analyzer — fix each one it reports).

Replace `register`:

```dart
  Future<bool> register(
    String fullName,
    String email,
    String password, {
    required AccountType accountType,
    String? organizationCode,
  }) async {
    _setState(AuthState.loading);
    try {
      final result = await _supabaseService.signUp(
        email,
        password,
        fullName,
        accountType: accountType.wireValue,
        organizationCode: organizationCode,
      );
      if (result.success && result.user != null) {
        _user = result.user!;
        await _userRepository.upsertUser(_user!);
        _setState(AuthState.awaitingEmailConfirmation);
        return true;
      }
      _setState(
        AuthState.error,
        error: _friendlyAuthError(result.error ?? 'Registration failed'),
      );
    } catch (e) {
      _setState(AuthState.error, error: _friendlyAuthError(e.toString()));
    }
    return false;
  }
```

Add the org-code case at the top of `_friendlyAuthError`:

```dart
    if (lower.contains('org_code_invalid')) {
      return "That organization code wasn't recognised.";
    }
```

Give `registerLocalFallback` the account type and refuse the org path:

```dart
  Future<bool> registerLocalFallback(
    String fullName,
    String email, {
    required String password,
    required AccountType accountType,
    String? remoteError,
  }) async {
    if (accountType == AccountType.organization) {
      _setState(
        AuthState.error,
        error: 'Internet access is required to join an organization.',
      );
      return false;
    }
    // ...existing body unchanged...
```

and inside that existing body, stamp the local user as personal:

```dart
        role: 'personal',
        status: 'approved',
        accountType: 'personal',
```

- [ ] **Step 5: Run the provider tests**

Run: `flutter test test/features/auth/auth_provider_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze and fix every switch the new enum value broke**

Run: `flutter analyze`
Expected: zero issues. `app.dart`'s `_getInitialRoute` and `authRedirectRouteForState` will both need an `AuthState.awaitingEmailConfirmation` arm — Task 8 defines the routing; for now return `'/login'` from `_getInitialRoute` and `null` from `authRedirectRouteForState`.

- [ ] **Step 7: Commit**

```bash
git add lib/features/auth/providers/auth_provider.dart \
        lib/services/supabase/supabase_service.dart \
        lib/app.dart test/features/auth/auth_provider_test.dart
git commit -m "feat(auth): fork registration into personal and organization account types"
```

---

### Task 7: Account-type chooser + organization code entry (UI)

The "Personal account, or organization account?" fork, and the code field.

**Files:**
- Create: `lib/features/auth/screens/account_type_screen.dart`
- Modify: `lib/features/auth/screens/register_screen.dart`
- Modify: `lib/app.dart` (`_buildRoutes`, `_preAppRouteNames`)
- Modify: `lib/core/constants/app_strings.dart`
- Test: `test/features/auth/account_type_screen_test.dart`

**Interfaces:**
- Consumes: `AccountType` and `AuthProvider.register` (Task 6); `SupabaseService.lookupOrganizationName` (Task 6).
- Produces:
  - route `/account-type` → `AccountTypeScreen`
  - `RegisterScreen({required AccountType accountType})` — the chooser pushes `/register` with `RouteSettings(arguments: accountType)`; `RegisterScreen` falls back to `AccountType.personal` when arguments are absent.

Note on testing: per project experience, `testWidgets` against the real sqflite stack hangs under `FakeAsync`. These tests build the screens with injected fakes and use bounded `pump()` calls, never `pumpAndSettle()`.

- [ ] **Step 1: Write the failing chooser test**

Create `test/features/auth/account_type_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/auth/screens/account_type_screen.dart';

void main() {
  testWidgets('offers both account types and reports the choice', (tester) async {
    AccountType? chosen;
    await tester.pumpWidget(MaterialApp(
      home: AccountTypeScreen(onSelected: (type) => chosen = type),
    ));
    await tester.pump();

    expect(find.text('Personal account'), findsOneWidget);
    expect(find.text('Organization account'), findsOneWidget);

    await tester.tap(find.text('Organization account'));
    await tester.pump();
    expect(chosen, AccountType.organization);

    await tester.tap(find.text('Personal account'));
    await tester.pump();
    expect(chosen, AccountType.personal);
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/features/auth/account_type_screen_test.dart`
Expected: FAIL — `account_type_screen.dart` does not exist.

- [ ] **Step 3: Build the chooser**

Create `lib/features/auth/screens/account_type_screen.dart`:

```dart
import 'package:hatchaudit/localized_material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../widgets/chick_mark_logo.dart';
import '../../../widgets/section_card.dart';
import '../providers/auth_provider.dart';

/// First step of registration: personal or organization. Everything downstream
/// forks from this one choice, so it gets its own screen rather than a toggle.
class AccountTypeScreen extends StatelessWidget {
  /// Injected by tests; in the app this pushes /register with the choice.
  final ValueChanged<AccountType>? onSelected;

  const AccountTypeScreen({super.key, this.onSelected});

  void _choose(BuildContext context, AccountType type) {
    if (onSelected != null) {
      onSelected!(type);
      return;
    }
    Navigator.of(context).pushNamed('/register', arguments: type);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GradientAppBar(title: 'Create Account'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const ChickMarkLogo(logoSize: 80, animated: true),
            const SizedBox(height: 24),
            Text('How will you use ChickMark?', style: AppTextStyles.heading),
            const SizedBox(height: 16),
            _OptionCard(
              title: 'Personal account',
              body:
                  'For a hatchery engineer or hatching manager signing up on '
                  'their own. Confirm your email and you are in.',
              icon: Icons.person_outline_rounded,
              onTap: () => _choose(context, AccountType.personal),
            ),
            const SizedBox(height: 12),
            _OptionCard(
              title: 'Organization account',
              body:
                  'For joining a company that already uses ChickMark. You will '
                  'need your organization code, and an admin at your company '
                  'approves you.',
              icon: Icons.apartment_rounded,
              onTap: () => _choose(context, AccountType.organization),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('Back to Login'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  final VoidCallback onTap;

  const _OptionCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.subheading),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
```

If `AppTextStyles.subheading` does not exist, use `AppTextStyles.heading` — check [app_text_styles.dart](lib/core/theme/app_text_styles.dart) before writing.

- [ ] **Step 4: Run the chooser test**

Run: `flutter test test/features/auth/account_type_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Take the account type into RegisterScreen**

In `lib/features/auth/screens/register_screen.dart`:

```dart
class RegisterScreen extends StatefulWidget {
  final AccountType accountType;

  const RegisterScreen({super.key, this.accountType = AccountType.personal});
```

Add an org-code controller and a resolved-name field next to the existing controllers:

```dart
  final _orgCodeController = TextEditingController();
  final _orgCodeFocusNode = FocusNode();
  String? _resolvedOrgName;
  bool _checkingOrgCode = false;
```

Dispose both in `dispose()`.

Add the code field to the form, rendered only for the organization path, immediately above the Full Name field:

```dart
                        if (widget.accountType == AccountType.organization) ...[
                          TextFormField(
                            controller: _orgCodeController,
                            focusNode: _orgCodeFocusNode,
                            decoration: _fieldDecoration(
                              labelText: 'Organization Code',
                              icon: Icons.vpn_key_outlined,
                            ),
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() => _resolvedOrgName = null),
                            onEditingComplete: _verifyOrgCode,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter your organization code';
                              }
                              return null;
                            },
                          ),
                          if (_checkingOrgCode)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(minHeight: 2),
                            ),
                          if (_resolvedOrgName != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Joining $_resolvedOrgName',
                                style: TextStyle(
                                    color: Colors.green[700], fontSize: 12),
                              ),
                            ),
                          const SizedBox(height: 16),
                        ],
```

Add the lookup:

```dart
  Future<void> _verifyOrgCode() async {
    final code = _orgCodeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _checkingOrgCode = true);
    final name = await SupabaseService().lookupOrganizationName(code);
    if (!mounted) return;
    setState(() {
      _checkingOrgCode = false;
      _resolvedOrgName = name;
    });
  }
```

Rewrite `_handleRegister` to pass the type through and to stop pretending the account is ready:

```dart
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final authProvider = context.read<AuthProvider>();
    final registered = await authProvider.register(
      _fullNameController.text.trim(),
      email,
      _passwordController.text,
      accountType: widget.accountType,
      organizationCode: widget.accountType == AccountType.organization
          ? _orgCodeController.text.trim().toUpperCase()
          : null,
    );

    var completed = registered;
    if (!completed && widget.accountType == AccountType.personal) {
      completed = await authProvider.registerLocalFallback(
        _fullNameController.text.trim(),
        email,
        password: _passwordController.text,
        accountType: AccountType.personal,
        remoteError: authProvider.errorMessage,
      );
    }
    if (!mounted || !completed) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRememberMeKey, email);
    if (!mounted) return;

    Navigator.of(context).pushReplacementNamed('/confirm-email');
  }
```

Replace the green "Your account will be ready to use after it is created." banner text with copy that matches the chosen path:

```dart
                                  widget.accountType == AccountType.personal
                                      ? 'Confirm your email and you are in — no approval needed.'
                                      : 'After you confirm your email, an admin at your organization approves you.',
```

- [ ] **Step 6: Register the routes**

In `lib/app.dart` `_buildRoutes`, add `/account-type` and make `/register` read the argument:

```dart
      '/account-type': (context) => const AccountTypeScreen(),
      '/register': (context) {
        final accountType =
            ModalRoute.of(context)?.settings.arguments as AccountType?;
        return shouldUseDebugBypassShellForRoute(
              authBypassEnabled: authBypassEnabled,
              routeName: '/register',
            )
            ? const MainShell()
            : RegisterScreen(accountType: accountType ?? AccountType.personal);
      },
```

Add `'/account-type'` to `_preAppRouteNames` ([app.dart:246](lib/app.dart:246)).

In `lib/features/auth/screens/login_screen.dart`, point the "Create Account" action at `/account-type` instead of `/register`.

- [ ] **Step 7: Analyze and run the full suite**

Run: `flutter analyze && flutter test`
Expected: zero issues, all pass. `test/app_auth_navigation_test.dart` asserts over `_preAppRouteNames` — extend its route list with `/account-type`.

- [ ] **Step 8: Commit**

```bash
git add lib/features/auth/screens/account_type_screen.dart \
        lib/features/auth/screens/register_screen.dart \
        lib/features/auth/screens/login_screen.dart lib/app.dart \
        test/features/auth/account_type_screen_test.dart \
        test/app_auth_navigation_test.dart
git commit -m "feat(auth): add account type chooser and organization code entry"
```

---

### Task 8: Confirm-email screen + pending-approval rework + routing

Reuses the existing `/pending-approval` route; adds the confirm-email waypoint between signup and sign-in.

**Files:**
- Create: `lib/features/auth/screens/confirm_email_screen.dart`
- Modify: `lib/features/auth/screens/pending_approval_screen.dart`
- Modify: `lib/app.dart` (`_getInitialRoute`, `_buildRoutes`, `_preAppRouteNames`, `authRedirectRouteForState`)
- Test: `test/app_auth_navigation_test.dart`

**Interfaces:**
- Consumes: `AuthState.awaitingEmailConfirmation` (Task 6); `AuthProvider.logout`, `AuthProvider.login`.
- Produces: route `/confirm-email` → `ConfirmEmailScreen`; `_getInitialRoute(AuthState.awaitingEmailConfirmation) == '/confirm-email'`; `PendingApprovalScreen` gains a `Refresh status` action calling `AuthProvider.refreshApprovalStatus()`.
- Also produces on `AuthProvider`: `Future<void> refreshApprovalStatus()` — re-reads the profile and promotes `pendingApproval` → `authenticated` once the org admin has approved.

- [ ] **Step 1: Write the failing routing tests**

Append to `test/app_auth_navigation_test.dart`:

```dart
  test('awaiting email confirmation lands on the confirm-email route', () {
    expect(initialRouteForState(AuthState.awaitingEmailConfirmation), '/confirm-email');
  });

  test('confirm-email and account-type are pre-app routes', () {
    for (final routeName in ['/account-type', '/confirm-email']) {
      expect(
        authRedirectRouteForState(
          state: AuthState.unauthenticated,
          topRouteName: routeName,
        ),
        isNull,
      );
    }
  });
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/app_auth_navigation_test.dart`
Expected: FAIL — `initialRouteForState` is not defined (`_getInitialRoute` is currently a private instance method).

- [ ] **Step 3: Expose the initial-route mapping and add the arm**

In `lib/app.dart`, lift the switch out of the State class into a testable top-level function and have `_getInitialRoute` delegate to it:

```dart
@visibleForTesting
String initialRouteForState(AuthState state) {
  switch (state) {
    case AuthState.authenticated:
      return '/main';
    case AuthState.pendingApproval:
      return '/pending-approval';
    case AuthState.awaitingEmailConfirmation:
      return '/confirm-email';
    case AuthState.loading:
    case AuthState.error:
    case AuthState.unauthenticated:
      return '/login';
  }
}
```

```dart
  String _getInitialRoute(AuthState state) => initialRouteForState(state);
```

Add `'/confirm-email'` to `_preAppRouteNames`, add the `awaitingEmailConfirmation` arm to `authRedirectRouteForState` returning `null`, and register the route in `_buildRoutes`:

```dart
      '/confirm-email': (context) => const ConfirmEmailScreen(),
```

- [ ] **Step 4: Build the confirm-email screen**

Create `lib/features/auth/screens/confirm_email_screen.dart`:

```dart
import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../widgets/chick_mark_logo.dart';
import '../../../widgets/section_card.dart';
import '../providers/auth_provider.dart';

/// Shown straight after signup. The account exists but is unusable until the
/// Supabase confirmation link is opened, so the only way forward is sign-in.
class ConfirmEmailScreen extends StatelessWidget {
  const ConfirmEmailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final email = context.select<AuthProvider, String?>((p) => p.user?.email);
    final isOrganization =
        context.select<AuthProvider, bool>((p) => p.user?.isOrganizationAccount ?? false);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GradientAppBar(title: 'Confirm Your Email'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const ChickMarkLogo(logoSize: 100, animated: true),
            const SizedBox(height: 32),
            SectionCard(
              child: Column(
                children: [
                  const Icon(Icons.mark_email_unread_outlined,
                      size: 64, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text('Check your inbox', style: AppTextStyles.heading),
                  const SizedBox(height: 8),
                  Text(
                    email == null
                        ? 'We sent you a confirmation link. Open it, then sign in.'
                        : 'We sent a confirmation link to $email. Open it, then sign in.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  if (isOrganization) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'After you confirm, an admin at your organization needs to '
                      'approve your account before you can use it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                await context.read<AuthProvider>().logout();
                if (context.mounted) {
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/login', (_) => false);
                }
              },
              child: const Text('Go to Sign In'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Rework the pending-approval screen**

In `lib/features/auth/screens/pending_approval_screen.dart`:

1. **Delete the entire "Forgot Password" `SectionCard`** (lines 84–157) along with `_emailController`, `_handlePasswordReset`, `_resetSent`, `_isSendingReset`, `_resetError`, and the now-unused `SupabaseService` import. Password reset belongs on the login screen (Task 9), not on a screen only reachable once you are already signed in.
2. Change the waiting copy to name the right approver:

```dart
                  const Text(
                    'Your account is waiting for an admin at your organization '
                    'to approve it. You will be able to sign in as soon as they do.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
```

3. Add a refresh action above the existing "Use different account" button:

```dart
            ElevatedButton.icon(
              onPressed: () => context.read<AuthProvider>().refreshApprovalStatus(),
              icon: const Icon(Icons.refresh),
              label: const Text('Check approval status'),
            ),
            const SizedBox(height: 8),
```

The class can now be a `StatelessWidget`; convert it and drop the `State` boilerplate.

- [ ] **Step 6: Add `refreshApprovalStatus` to AuthProvider**

In `lib/features/auth/providers/auth_provider.dart`:

```dart
  /// Re-reads the signed-in profile so a freshly approved org member can enter
  /// without signing out and back in.
  Future<void> refreshApprovalStatus() async {
    final current = _user;
    if (current == null) return;
    final refreshed = await _supabaseService.fetchCurrentProfile();
    if (refreshed == null) return;
    _user = refreshed;
    await _userRepository.upsertUser(refreshed);
    _setState(refreshed.isApproved
        ? AuthState.authenticated
        : AuthState.pendingApproval);
  }
```

And in `lib/services/supabase/supabase_service.dart`, next to `_fetchUserProfile`:

```dart
  /// The signed-in user's profile as a UserModel, or null when offline or
  /// signed out. Used to re-check approval without a full sign-in.
  Future<UserModel?> fetchCurrentProfile() async {
    try {
      if (!await _prepareRemoteAccess()) return null;
      final authUser = _client.auth.currentUser;
      final session = _client.auth.currentSession;
      if (authUser == null || session == null) return null;
      final profile = await _fetchUserProfile(authUser.id);
      return _buildUserFromAuth(
        authUser,
        fallbackEmail: authUser.email ?? '',
        profile: profile,
        accessToken: session.accessToken,
        tokenExpiry: _sessionExpiry(session),
      );
    } catch (e) {
      safeDebugLog('Profile refresh failed', error: e);
      return null;
    }
  }
```

- [ ] **Step 7: Run the routing tests and the suite**

Run: `flutter test test/app_auth_navigation_test.dart && flutter analyze && flutter test`
Expected: all PASS, zero analyze issues.

- [ ] **Step 8: Commit**

```bash
git add lib/features/auth/screens/confirm_email_screen.dart \
        lib/features/auth/screens/pending_approval_screen.dart \
        lib/features/auth/providers/auth_provider.dart \
        lib/services/supabase/supabase_service.dart lib/app.dart \
        test/app_auth_navigation_test.dart
git commit -m "feat(auth): add confirm-email step and rework pending approval"
```

---

### Task 9: Remove `reset-customer-password`; standard email reset on login

Deletes the Edge Function and every call path, and makes Forgot Password honest for the two kinds of account.

**Files:**
- Delete: `supabase/functions/reset-customer-password/` (whole directory)
- Modify: `lib/data/repositories/admin_repository.dart:111-133`
- Modify: `lib/features/admin/screens/admin_users_screen.dart` (`_resetPassword`, its button, `_ResetCustomerPasswordSheet`)
- Modify: `lib/features/auth/screens/login_screen.dart:74-120`
- Test: `test/features/auth/forgot_password_test.dart` (create)

**Interfaces:**
- Consumes: `CustomerAccountIdentifier.isCustomerLoginEmail` ([customer_account_identifier.dart](lib/core/auth/customer_account_identifier.dart)); `SupabaseService.sendPasswordReset`.
- Produces: `@visibleForTesting String forgotPasswordMessageFor(String identifier, {required bool sent})` in `login_screen.dart`.
- Removes: `AdminRepository.resetCustomerPassword`, `_ResetCustomerPasswordSheet`.

- [ ] **Step 1: Write the failing message test**

Create `test/features/auth/forgot_password_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/auth/screens/login_screen.dart';

void main() {
  test('real email addresses get the standard reset message', () {
    expect(
      forgotPasswordMessageFor('engineer@hatchery.com', sent: true),
      'Password reset link sent to engineer@hatchery.com',
    );
  });

  test('a failed send says so instead of claiming success', () {
    expect(
      forgotPasswordMessageFor('engineer@hatchery.com', sent: false),
      'Reset link could not be sent right now. Check your connection and try again.',
    );
  });

  test('legacy username accounts have no mailbox and are told the truth', () {
    expect(
      forgotPasswordMessageFor('oldcustomer', sent: true),
      'This username account has no email address. Ask your ChickMark '
      'administrator to reset it for you.',
    );
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/features/auth/forgot_password_test.dart`
Expected: FAIL — `forgotPasswordMessageFor` is not defined.

- [ ] **Step 3: Implement the message helper and rewrite the login handler**

At the bottom of `lib/features/auth/screens/login_screen.dart`:

```dart
/// Legacy username accounts resolve to synthetic @customers.chickmark.app
/// addresses with no real mailbox, so Supabase's reset email cannot reach
/// them. Say that plainly rather than claiming a link was sent.
@visibleForTesting
String forgotPasswordMessageFor(String identifier, {required bool sent}) {
  final loginEmail = CustomerAccountIdentifier.loginEmail(identifier);
  if (CustomerAccountIdentifier.isCustomerLoginEmail(loginEmail)) {
    return 'This username account has no email address. Ask your ChickMark '
        'administrator to reset it for you.';
  }
  if (!sent) {
    return 'Reset link could not be sent right now. Check your connection and try again.';
  }
  return 'Password reset link sent to ${identifier.trim()}';
}
```

Rewrite `_handleForgotPassword` (currently at [login_screen.dart:74](lib/features/auth/screens/login_screen.dart:74)) so it: reads the identifier field; if `CustomerAccountIdentifier.isCustomerLoginEmail(loginEmail(identifier))` shows the legacy message **without** calling Supabase; otherwise calls `SupabaseService().sendPasswordReset(identifier)` and shows `forgotPasswordMessageFor(identifier, sent: result)`. Delete the hard-coded `'Customer password resets are handled by your ChickMark admin.'` string at line 88.

- [ ] **Step 4: Run the message test**

Run: `flutter test test/features/auth/forgot_password_test.dart`
Expected: PASS.

- [ ] **Step 5: Remove the Edge Function and its call path**

```bash
git rm -r supabase/functions/reset-customer-password
```

Delete `resetCustomerPassword` from `lib/data/repositories/admin_repository.dart` (lines 111–133). Delete `_resetPassword` ([admin_users_screen.dart:501](lib/features/admin/screens/admin_users_screen.dart:501)), the button that calls it (around line 576), the `if (widget.profile.role == 'customer') ...[` reset block (around line 571), and the whole `_ResetCustomerPasswordSheet` widget (from line 668 to its close).

Then undeploy it from the project:

```bash
supabase functions delete reset-customer-password
```

- [ ] **Step 6: Verify nothing still references it**

Run: `grep -rn "reset-customer-password\|resetCustomerPassword\|_ResetCustomerPasswordSheet" lib supabase test`
Expected: no output.

- [ ] **Step 7: Analyze and run the suite**

Run: `flutter analyze && flutter test`
Expected: zero issues, all pass.

- [ ] **Step 8: Commit**

```bash
git add -A supabase/functions lib/data/repositories/admin_repository.dart \
        lib/features/admin/screens/admin_users_screen.dart \
        lib/features/auth/screens/login_screen.dart \
        test/features/auth/forgot_password_test.dart
git commit -m "feat(auth): drop reset-customer-password in favour of email reset"
```

---

### Task 10: Personal-account tool gating in the shell

A personal account sees benchmarks and settings — nothing customer-scoped.

**Files:**
- Modify: `lib/features/home/widgets/main_shell.dart:40-55`
- Test: `test/features/home/main_shell_tabs_test.dart` (create if absent; check first — `mainShellTabKeysForUser` is already `@visibleForTesting`-shaped and may have coverage)

**Interfaces:**
- Consumes: `UserModel.isPersonalAccount` (Task 5).
- Produces: `mainShellTabKeysForUser(UserModel?)` returns exactly `['bmk','settings']` for a personal account. All other roles keep today's behaviour byte-for-byte.

- [ ] **Step 1: Write the failing tab test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/home/widgets/main_shell.dart';

void main() {
  UserModel user({
    required String role,
    String accountType = 'internal',
    String status = 'approved',
  }) => UserModel(
        id: 'u1',
        fullName: 'U',
        email: 'u@example.com',
        role: role,
        status: status,
        accountType: accountType,
        createdAt: DateTime(2026, 8, 13),
      );

  test('personal accounts see benchmarks and settings only', () {
    expect(
      mainShellTabKeysForUser(user(role: 'personal', accountType: 'personal')),
      ['bmk', 'settings'],
    );
  });

  test('customer tabs are unchanged', () {
    expect(
      mainShellTabKeysForUser(user(role: 'customer')),
      ['dashboard', 'settings'],
    );
  });

  test('auditor tabs are unchanged', () {
    final keys = mainShellTabKeysForUser(user(role: 'auditor'));
    expect(keys, contains('audits'));
    expect(keys, isNot(contains('agent')));
  });
}
```

- [ ] **Step 2: Run to confirm the personal case fails**

Run: `flutter test test/features/home/main_shell_tabs_test.dart`
Expected: FAIL on the first test — personal currently falls through to the full auditor tab set.

- [ ] **Step 3: Add the personal branch**

In `lib/features/home/widgets/main_shell.dart`, above the existing customer branch:

```dart
// Personal accounts are not attached to any customer, so every tenant-scoped
// tool is meaningless to them. Benchmarks is the one tool they get today;
// future personal tools get added to this set.
const _personalMainShellTabKeys = <String>{'bmk', 'settings'};

List<String> mainShellTabKeysForUser(UserModel? user) {
  if (user?.isPersonalAccount == true) {
    return _allMainShellTabKeys
        .where(_personalMainShellTabKeys.contains)
        .toList(growable: false);
  }
  if (user?.isCustomer == true) {
    // ...existing body unchanged...
```

- [ ] **Step 4: Run the tab tests**

Run: `flutter test test/features/home/main_shell_tabs_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze and run the suite**

Run: `flutter analyze && flutter test`
Expected: zero issues, all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/widgets/main_shell.dart \
        test/features/home/main_shell_tabs_test.dart
git commit -m "feat(auth): gate personal accounts to benchmarks and settings"
```

---

### Task 11: Super-admin organizations screen

Where the Zoetis super-admin creates an org, sees its code, and appoints the first admin.

**Files:**
- Create: `lib/features/admin/screens/admin_organizations_screen.dart`
- Modify: `lib/data/repositories/admin_repository.dart`
- Modify: wherever `AdminUsersScreen` is reached from (find with `grep -rn "AdminUsersScreen" lib`) — add a sibling entry point
- Test: `test/data/repositories/admin_repository_organizations_test.dart`

**Interfaces:**
- Consumes: `create-organization` Edge Function (Task 4); `public.organizations` read policy (Task 1).
- Produces on `AdminRepository`:
  - `class AdminOrganization { final String id; final String name; final String code; final String customerId; }` with `AdminOrganization.fromMap(Map<String, dynamic>)` reading `id`, `name`, `code`, `customer_id`
  - `Future<List<AdminOrganization>> listOrganizations()`
  - `Future<AdminOrganization> createOrganization({required String name, required String customerId, required String adminEmail, required String adminFullName, required String adminPassword})` — throws `AdminAccountException` with the server message on failure

- [ ] **Step 1: Write the failing repository test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/repositories/admin_repository.dart';

void main() {
  test('AdminOrganization maps the snake_case customer link', () {
    final org = AdminOrganization.fromMap({
      'id': 'org-1',
      'name': 'Nile Hatchery',
      'code': 'ABCD2345',
      'customer_id': 'cust-9',
    });

    expect(org.id, 'org-1');
    expect(org.name, 'Nile Hatchery');
    expect(org.code, 'ABCD2345');
    expect(org.customerId, 'cust-9');
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/data/repositories/admin_repository_organizations_test.dart`
Expected: FAIL — `AdminOrganization` is undefined.

- [ ] **Step 3: Add the model and repository methods**

In `lib/data/repositories/admin_repository.dart`, alongside `AdminProfile`:

```dart
/// An organization tenant as the super-admin sees it.
class AdminOrganization {
  final String id;
  final String name;
  final String code;
  final String customerId;

  const AdminOrganization({
    required this.id,
    required this.name,
    required this.code,
    required this.customerId,
  });

  factory AdminOrganization.fromMap(Map<String, dynamic> map) {
    return AdminOrganization(
      id: map['id'] as String,
      name: (map['name'] as String?) ?? '',
      code: (map['code'] as String?) ?? '',
      customerId: (map['customer_id'] as String?) ?? '',
    );
  }
}
```

And on `AdminRepository`:

```dart
  Future<List<AdminOrganization>> listOrganizations() async {
    final rows = await _client
        .from('organizations')
        .select('id, name, code, customer_id')
        .order('name');
    return rows
        .map((row) => AdminOrganization.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Creates the organization, generates its code, and appoints the first
  /// admin in one server-side transaction. Service-role work never happens in
  /// the client, so this goes through an Edge Function.
  Future<AdminOrganization> createOrganization({
    required String name,
    required String customerId,
    required String adminEmail,
    required String adminFullName,
    required String adminPassword,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-organization',
        body: {
          'name': name,
          'customerId': customerId,
          'adminEmail': adminEmail,
          'adminFullName': adminFullName,
          'adminPassword': adminPassword,
        },
      );
      final data = response.data;
      if (data is! Map || data['organization'] is! Map) {
        throw const AdminAccountException(
          'The server returned an invalid organization response.',
        );
      }
      final org = Map<String, dynamic>.from(data['organization'] as Map);
      return AdminOrganization(
        id: org['id'] as String,
        name: org['name'] as String,
        code: org['code'] as String,
        customerId: org['customerId'] as String,
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error']?.toString() : null;
      throw AdminAccountException(
        message == null || message.isEmpty
            ? 'Could not create the organization.'
            : message,
      );
    } on AdminAccountException {
      rethrow;
    } catch (_) {
      throw const AdminAccountException(
        'Could not create the organization. Check your connection and try again.',
      );
    }
  }
```

- [ ] **Step 4: Run the repository test**

Run: `flutter test test/data/repositories/admin_repository_organizations_test.dart`
Expected: PASS.

- [ ] **Step 5: Build the screen**

Create `lib/features/admin/screens/admin_organizations_screen.dart` following the structure of [admin_users_screen.dart](lib/features/admin/screens/admin_users_screen.dart) — same `Scaffold` + `FutureBuilder`-over-repository + modal bottom sheet form idiom. It must:

- List organizations with name, code (in a `SelectableText` so the admin can copy it), and linked customer.
- Offer a "New organization" FAB opening a sheet with: name, customer picker (reuse the customer picker from `_UserEditorSheet._buildCustomerPicker`), first-admin full name, first-admin email, first-admin password (validated with `PasswordPolicy.validationMessage`).
- On success, show a dialog containing the generated code and the sentence "Give this code to everyone at $name who needs an account." — this is the only moment the code is handed over.
- On `AdminAccountException`, show `error.message` in a `SnackBar`.

- [ ] **Step 6: Wire the entry point**

Run: `grep -rn "AdminUsersScreen" lib`
Add an "Organizations" entry beside the existing "Users" entry in whatever admin surface that returns (Settings, most likely), gated on `user?.isAdmin == true`.

- [ ] **Step 7: Analyze and run the suite**

Run: `flutter analyze && flutter test`
Expected: zero issues, all pass.

- [ ] **Step 8: Commit**

```bash
git add lib/features/admin/screens/admin_organizations_screen.dart \
        lib/data/repositories/admin_repository.dart \
        test/data/repositories/admin_repository_organizations_test.dart
git commit -m "feat(admin): add super-admin organization creation screen"
```

---

### Task 12: Org admin approvals screen

Where an organization's own admin approves waiting employees, and the first admin promotes.

**Files:**
- Create: `lib/features/admin/screens/org_members_screen.dart`
- Modify: `lib/data/repositories/admin_repository.dart`
- Modify: the admin entry point from Task 11 (gate on `isOrgAdmin`, not `isAdmin`)
- Test: `test/data/repositories/admin_repository_org_members_test.dart`

**Interfaces:**
- Consumes: `list_org_members`, `approve_org_member`, `promote_org_admin` RPCs (Task 3); `UserModel.isOrgAdmin` / `.isOrgFirstAdmin` (Task 5).
- Produces on `AdminRepository`:
  - `class OrgMember { final String id; final String fullName; final String email; final String status; final String orgRole; }` with `OrgMember.fromMap` reading `id`, `full_name`, `email`, `status`, `org_role`
  - `Future<List<OrgMember>> listOrgMembers()`
  - `Future<void> approveOrgMember(String userId)`
  - `Future<void> promoteOrgAdmin(String userId)`
  - Both mutators throw `AdminAccountException` carrying a translated message for `NOT_ORG_ADMIN`, `NOT_FIRST_ADMIN`, `MEMBER_NOT_PENDING_IN_ORG`, `MEMBER_NOT_PROMOTABLE`.

- [ ] **Step 1: Write the failing mapping + error-translation test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/repositories/admin_repository.dart';

void main() {
  test('OrgMember maps snake_case rows', () {
    final member = OrgMember.fromMap({
      'id': 'u-1',
      'full_name': 'Sara Ali',
      'email': 'sara@hatchery.com',
      'status': 'pending',
      'org_role': 'member',
    });

    expect(member.id, 'u-1');
    expect(member.fullName, 'Sara Ali');
    expect(member.status, 'pending');
    expect(member.orgRole, 'member');
  });

  test('server error codes become readable messages', () {
    expect(
      orgMemberErrorMessage('NOT_FIRST_ADMIN'),
      'Only your organization\'s first admin can create new admins.',
    );
    expect(
      orgMemberErrorMessage('NOT_ORG_ADMIN'),
      'Only an organization admin can approve members.',
    );
    expect(
      orgMemberErrorMessage('MEMBER_NOT_PENDING_IN_ORG'),
      'That member is no longer waiting for approval in your organization.',
    );
    expect(
      orgMemberErrorMessage('MEMBER_NOT_PROMOTABLE'),
      'That member cannot be promoted — they must be an approved member first.',
    );
    expect(
      orgMemberErrorMessage('something else entirely'),
      'Could not complete that change. Check your connection and try again.',
    );
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/data/repositories/admin_repository_org_members_test.dart`
Expected: FAIL — `OrgMember` undefined.

- [ ] **Step 3: Add the model, translator, and RPC wrappers**

In `lib/data/repositories/admin_repository.dart`:

```dart
/// A member of the caller's own organization, as returned by list_org_members.
class OrgMember {
  final String id;
  final String fullName;
  final String email;
  final String status;
  final String orgRole;

  const OrgMember({
    required this.id,
    required this.fullName,
    required this.email,
    required this.status,
    required this.orgRole,
  });

  factory OrgMember.fromMap(Map<String, dynamic> map) {
    return OrgMember(
      id: map['id'] as String,
      fullName: (map['full_name'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'pending',
      orgRole: (map['org_role'] as String?) ?? 'member',
    );
  }

  bool get isPending => status == 'pending';
  bool get isMember => orgRole == 'member';
}

/// Translates the RPC exception codes from 20260813092000_org_admin_rpcs.sql.
String orgMemberErrorMessage(String rawError) {
  if (rawError.contains('NOT_FIRST_ADMIN')) {
    return 'Only your organization\'s first admin can create new admins.';
  }
  if (rawError.contains('NOT_ORG_ADMIN')) {
    return 'Only an organization admin can approve members.';
  }
  if (rawError.contains('MEMBER_NOT_PENDING_IN_ORG')) {
    return 'That member is no longer waiting for approval in your organization.';
  }
  if (rawError.contains('MEMBER_NOT_PROMOTABLE')) {
    return 'That member cannot be promoted — they must be an approved member first.';
  }
  return 'Could not complete that change. Check your connection and try again.';
}
```

On `AdminRepository`:

```dart
  Future<List<OrgMember>> listOrgMembers() async {
    final rows = await _client.rpc('list_org_members') as List<dynamic>;
    return rows
        .map((row) => OrgMember.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<void> approveOrgMember(String userId) async {
    try {
      await _client.rpc('approve_org_member', params: {'p_user_id': userId});
    } catch (error) {
      throw AdminAccountException(orgMemberErrorMessage(error.toString()));
    }
  }

  Future<void> promoteOrgAdmin(String userId) async {
    try {
      await _client.rpc('promote_org_admin', params: {'p_user_id': userId});
    } catch (error) {
      throw AdminAccountException(orgMemberErrorMessage(error.toString()));
    }
  }
```

- [ ] **Step 4: Run the repository test**

Run: `flutter test test/data/repositories/admin_repository_org_members_test.dart`
Expected: PASS.

- [ ] **Step 5: Build the screen**

Create `lib/features/admin/screens/org_members_screen.dart`, structured like `AdminUsersScreen`:

- Two sections: "Waiting for approval" (`member.isPending`) and "Team" (the rest).
- Each pending row has an **Approve** button → `approveOrgMember(member.id)` → refresh.
- Each approved `member.isMember` row shows a **Make admin** button **only when** `context.read<AuthProvider>().user?.isOrgFirstAdmin == true`. A promoted admin must not see the button — the RPC also refuses, but the UI should not offer it.
- `AdminAccountException` messages go to a `SnackBar`.

- [ ] **Step 6: Gate the entry point**

In the admin entry surface touched in Task 11, show "Organization members" when `user?.isOrgAdmin == true`, and "Organizations" when `user?.isAdmin == true`. These are different tiers and both can be absent.

- [ ] **Step 7: Analyze and run the suite**

Run: `flutter analyze && flutter test`
Expected: zero issues, all pass.

- [ ] **Step 8: Commit**

```bash
git add lib/features/admin/screens/org_members_screen.dart \
        lib/data/repositories/admin_repository.dart \
        test/data/repositories/admin_repository_org_members_test.dart
git commit -m "feat(admin): add organization member approval and promotion screen"
```

---

### Task 13: End-to-end verification + LIVING_SPEC update

The acceptance-criteria pass. Nothing here is optional — the REQ lists the spec update as a checkbox.

**Files:**
- Modify: `docs/LIVING_SPEC.md`
- Verify: Supabase Auth dashboard settings (human step)

- [ ] **Step 1: Confirm email confirmation is enabled**

In the Supabase dashboard → Authentication → Providers → Email: **Confirm email** must be ON. Under URL Configuration, the app's redirect URL must be allowlisted or confirmation links dead-end.

This is a dashboard setting a human must set and confirm. Report its state; do not assume it.

- [ ] **Step 2: Walk the Personal path on a device**

Sign out → Create Account → **Personal account** → register with a real address → confirm-email screen appears → open the emailed link → sign in. Expected: lands in `/main` with exactly two tabs, Benchmarks and Settings. No approval screen.

- [ ] **Step 3: Walk the Organization path**

As super-admin, create an org (Task 11) and note the code. Sign out → Create Account → **Organization account** → enter the code (the screen should show "Joining <org name>") → register → confirm email → sign in. Expected: `/pending-approval`.

Then sign in as that org's first admin → Organization members → Approve. Back on the pending device, tap **Check approval status**. Expected: enters the app without re-signing-in.

- [ ] **Step 4: Verify the negative cases**

| Case | Expected |
|---|---|
| Register organization with code `ZZZZ9999` | "That organization code wasn't recognised." and no account created |
| Sign in before confirming email | "Please confirm your email before signing in." (already handled at [auth_provider.dart:413](lib/features/auth/providers/auth_provider.dart:413)) |
| Forgot Password with a real email | reset email arrives |
| Forgot Password with a legacy username | "Ask your ChickMark administrator to reset it for you." |
| Promoted (non-first) admin viewing the team list | no "Make admin" button anywhere |

- [ ] **Step 5: Confirm no security regression**

Run: `git diff main --stat -- supabase/migrations/`
Expected: only new files listed — zero modifications to `0003`, `0007`, `0008`, `0017`.

Then, signed in as a **personal** account, attempt a write to shared reference data:

```sql
insert into public.bmk_breeds (id, name) values ('probe', 'Probe');
```

Expected: RLS denial. A success means the `'personal'` role leaked into `app_is_staff()` — stop and fix before shipping.

- [ ] **Step 6: Update LIVING_SPEC.md**

Add an "Account model" section covering: the two account types and the registration fork; the organization tenant and its 8-character code; the three authority tiers (Zoetis super-admin / org first admin / org admin) and exactly what each can do; the `profiles` columns `account_type`, `organization_id`, `org_role` and the new `'personal'` role value; the fact that approval and promotion go through `SECURITY DEFINER` RPCs rather than table policies, and why. Update every existing passage that describes username-based signup or the `reset-customer-password` function — find them with:

```bash
grep -n "reset-customer-password\|username" docs/LIVING_SPEC.md
```

- [ ] **Step 7: Final full verification**

Run: `flutter analyze && flutter test`
Expected: zero issues, all tests pass. Paste the actual summary line into the completion report — do not claim green without it.

- [ ] **Step 8: Commit**

```bash
git add docs/LIVING_SPEC.md
git commit -m "docs: describe the personal/organization account model"
```

---

## Acceptance criteria → task map

| REQ §7 criterion | Task |
|---|---|
| Registration begins with "Personal account, or organization account?" | 7 |
| Both paths use a real email + confirmation | 2, 6, 7, 13 |
| Supabase built-in password reset works | 9 |
| `reset-customer-password` removed with its "ask the admin" behaviour | 9 |
| Personal accounts get in immediately, with benchmarks | 2, 6, 10 |
| Organization accounts need a valid code, then pending-approval | 1, 2, 6, 7, 8 |
| Existing `/pending-approval` reused; findings reported | 8 + the Recon report above |
| Super-admin creates an org (code generated) and appoints the first admin | 1, 4, 11 |
| First admin approves employees and promotes admins | 3, 12 |
| Promoted admins approve but cannot create admins | 3, 12 |
| No security check weakened; tokens stay in Keychain | Global Constraints, 13 step 5 |
| LIVING_SPEC.md updated | 13 |
