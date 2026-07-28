# Unified AI Agent Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ChickMark's fixed Telegram routing and Pasgar-only scripted controller with one customer-scoped, tool-calling AI agent that chats naturally, answers flock-data questions, and collects any supported hatchery station/module into a versioned admin-review draft.

**Architecture:** Keep the verified Telegram webhook as a deterministic harness. After access and duplicate checks, every authorized message enters one bounded AI tool loop. The model owns interpretation and wording; typed tools own customer scope, registry lookup, reads, calculations, intake state, validation, evidence, and review submission. A canonical JSON station registry generates both Dart and TypeScript contracts so Flutter, the Edge Function, and approval mappings share schema keys and versions.

**Tech Stack:** Dart 3.10.7, Flutter, Provider, sqflite/sqflite_common_ffi_web, Supabase PostgreSQL/RLS, Supabase Edge Functions on Deno, `@supabase/supabase-js`, OpenAI/OpenRouter Responses API, existing offline-first sync.

## Global Constraints

- Task id: `AI-AGENT-HARNESS-001`.
- Work only in `/Users/ibrahimradi/.codex/worktrees/cce3/ChickMark` on branch `codex/telegram-hatchery-agent-integrated`.
- Treat current Flutter code and `docs/LIVING_SPEC.md` as the source of truth. Do not revive deleted specs or old generated artifacts.
- Preserve unrelated staged and unstaged changes. Before each commit, inspect `git diff --name-status` plus a task-specific diff of every path named in that task, and commit only those reviewed paths with `git commit --only`.
- Use TDD for every behavior change: add the focused failing test, run it and observe the intended failure, implement the smallest production change, rerun the focused test, then run the adjacent regression set.
- No greeting lists, intent keyword regexes, fixed conversational router, normal-response templates, or fixed field-order dialogue may be introduced.
- Deterministic text is limited to pending/revoked access, paused service, malformed webhook, provider/tool infrastructure failure, and other cases where the AI cannot respond.
- Never pass database credentials, unrestricted SQL, another customer's identifiers, secrets, or raw service-role errors to the model.
- Normal Telegram users have exactly one assigned customer when allowed. Only an explicitly admin-marked Telegram link may access all customers.
- Do not create an intake on inferred intent alone. The agent must first ask for confirmation, and `start_intake` must verify a recent confirmed pending action.
- Save accepted values without per-value confirmation. Require exactly one current-version summary confirmation per completed station/module.
- Telegram never writes final operational rows. Only authenticated app-admin approval may promote a confirmed intake.
- Keep existing submissions, legacy drafts, Pasgar intakes, audit evidence, and approval results readable throughout migration.
- Update `docs/LIVING_SPEC.md` after each meaningful vertical slice.
- Do not deploy a migration or Edge Function until all local schema, security, Deno, and Flutter tests in Task 13 pass.

---

## Task 1: Create the canonical station registry and generated contracts

**Files:**

- Create: `tool/agent_schema/station_registry.json`
- Create: `tool/agent_schema/generate_station_registry.dart`
- Create: `lib/data/agent/station_registry.dart`
- Create: `lib/data/agent/station_registry.g.dart`
- Create: `supabase/functions/_shared/station_registry.generated.ts`
- Create: `test/data/agent/station_registry_test.dart`
- Create: `supabase/functions/telegram-hatchery-agent/station_registry_test.ts`
- Modify: `lib/data/models/panel_sample_schema.dart`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Add failing registry coverage tests**

Create a Dart test that requires every active hatchery panel table to appear in at least one registry persistence mapping and requires unique `(schemaKey, version)` pairs:

```dart
test('every active hatchery panel has a versioned agent schema', () {
  final mappedTables = AgentStationRegistry.schemas
      .expand((schema) => schema.persistence)
      .map((mapping) => mapping.table)
      .toSet();
  expect(
    mappedTables,
    containsAll(PanelSampleSchema.panels.map((panel) => panel.tableName)),
  );
  expect(
    AgentStationRegistry.schemas
        .map((schema) => '${schema.schemaKey}@${schema.version}')
        .toSet()
        .length,
    AgentStationRegistry.schemas.length,
  );
});
```

Create the equivalent Deno contract test, plus assertions for `chicks.pasgar@1`: sample size is required, six explicit count fields are required, counts are bounded by sample size, and the persistence table is `chick_quality`.

Run:

```bash
flutter test test/data/agent/station_registry_test.dart
deno test supabase/functions/telegram-hatchery-agent/station_registry_test.ts
```

Expected: both fail because the canonical registry and generated contracts do not exist.

- [ ] **Step 2: Define one canonical registry document**

Use this top-level shape in `station_registry.json`:

```json
{
  "registryVersion": 1,
  "stations": [
    {
      "schemaKey": "chicks.pasgar",
      "version": 1,
      "sectorKeys": ["breeder"],
      "stationKey": "chicks",
      "moduleKey": "pasgar",
      "names": {"en": "Chick Quality — Pasgar", "ar": "جودة الكتاكيت — باسجار"},
      "aliases": {
        "en": ["pasgar", "chick quality score"],
        "ar": ["باسجار", "جودة الكتكوت", "جودة الكتاكيت"]
      },
      "allowedLayers": ["pool", "setter_hatcher"],
      "fields": [],
      "calculations": [],
      "completion": {"requiredFieldKeys": []},
      "persistence": [{"table": "chick_quality", "columns": {}}],
      "read": {"dimensions": [], "measures": []},
      "warnings": []
    }
  ]
}
```

Populate complete semantics—not just database column names—for these user-selectable modules:

1. `egg.storage_environment@1`
2. `egg.shell_temperature@1`
3. `egg.upside_down@1`
4. `egg.quality_uv@1`
5. `egg.weights@1`
6. `chicks.pasgar@1`
7. `chicks.yfbm@1`
8. `chicks.cvt@1`
9. `chicks.postmortem@1`
10. `chicks.culled_analysis@1`
11. `chicks.weights@1`
12. `hatch_analysis.fresh_breakout@1`
13. `hatch_analysis.candled_breakout@1`
14. `hatch_analysis.residue_breakout@1`
15. `setters.environment@1`
16. `setters.shell_temperature@1`
17. `hatchers.environment@1`
18. `hatchers.cvt@1`

For every field, record `fieldKey`, English/Arabic labels and aliases, `type`, `unit`, `required`, `explicitZero`, range/choice validation, dependencies, and remote column. Copy calculation semantics from current `CalculationUtils`, audit providers, codecs, and scope configuration; never ask the model to perform arithmetic.

- [ ] **Step 3: Generate typed Dart and TypeScript contracts**

The generator must:

- parse and validate the JSON;
- reject duplicate keys, unknown panel tables/columns, empty labels, missing aliases, invalid dependencies, and calculated fields marked as direct input;
- emit immutable Dart definitions and TypeScript `as const` data;
- support `--check`, which exits nonzero if generated output differs;
- produce deterministic key ordering and formatting.

Expose these APIs:

```dart
abstract final class AgentStationRegistry {
  static List<AgentStationSchema> get schemas;
  static AgentStationSchema require(String schemaKey, int version);
  static List<AgentStationSchema> applicableTo(Set<String> sectorKeys);
}
```

```ts
export function requireStationSchema(
  schemaKey: string,
  version: number,
): AgentStationSchema

export function applicableStationSchemas(
  sectorKeys: readonly string[],
): readonly AgentStationSchema[]
```

- [ ] **Step 4: Generate and verify**

Run:

```bash
dart run tool/agent_schema/generate_station_registry.dart
dart run tool/agent_schema/generate_station_registry.dart --check
dart format tool/agent_schema lib/data/agent test/data/agent
deno fmt supabase/functions/_shared/station_registry.generated.ts \
  supabase/functions/telegram-hatchery-agent/station_registry_test.ts
flutter test test/data/agent/station_registry_test.dart
deno test supabase/functions/telegram-hatchery-agent/station_registry_test.ts
```

Expected: generator check exits 0 and both contract suites pass.

- [ ] **Step 5: Document and commit the registry slice**

Update `docs/LIVING_SPEC.md` to identify the JSON as the canonical agent schema contract, list the 18 modules, and explain that aliases help the AI understand tool results rather than act as backend intent triggers.

Commit only Task 1 files:

```bash
git commit --only \
  tool/agent_schema \
  lib/data/agent \
  lib/data/models/panel_sample_schema.dart \
  supabase/functions/_shared/station_registry.generated.ts \
  supabase/functions/telegram-hatchery-agent/station_registry_test.ts \
  test/data/agent/station_registry_test.dart \
  docs/LIVING_SPEC.md \
  -m "feat: add versioned agent station registry"
```

---

## Task 2: Add customer assignment, conversation evidence, visits, and optimistic versions

**Files:**

- Create: `supabase/migrations/20260728103000_unified_agent_harness.sql`
- Create: `test/data/database/unified_agent_harness_schema_test.dart`
- Create: `test/security/unified_agent_harness_security_test.dart`
- Modify: `lib/data/database/database_schema.dart`
- Modify: `lib/data/database/database_migrations.dart`
- Modify: `lib/data/database/database_helper.dart`
- Modify: `lib/services/supabase/supabase_service.dart`
- Modify: `lib/services/supabase/startup_sync_service.dart`
- Modify: `test/services/supabase/startup_sync_service_test.dart`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Add failing local/remote schema and RLS tests**

Require:

- `telegram_staff_links.access_role` with `customer`/`admin`;
- `telegram_staff_links.customer_id`;
- an allowed customer link must have exactly one customer;
- an allowed admin link must have no customer restriction;
- `agent_conversations`;
- `agent_conversation_turns`;
- `agent_tool_events`;
- `agent_intake_visits`;
- `agent_intake_sessions.visit_id` and `row_version`;
- immutable summary evidence and tool-call evidence;
- RLS enabled, no anonymous grants, authenticated admin-only app access, and service-role Edge access.

Run:

```bash
flutter test \
  test/data/database/unified_agent_harness_schema_test.dart \
  test/security/unified_agent_harness_security_test.dart
```

Expected: fail on missing columns/tables.

- [ ] **Step 2: Write the additive Supabase migration**

Add:

```sql
alter table public.telegram_staff_links
  add column if not exists access_role text not null default 'customer',
  add column if not exists customer_id text
    references public.customers(id) on delete restrict;

alter table public.telegram_staff_links
  add constraint telegram_staff_links_access_role_check
    check (access_role in ('customer', 'admin')),
  add constraint telegram_staff_links_allowed_scope_check
    check (
      status <> 'allowed'
      or (access_role = 'customer' and customer_id is not null)
      or (access_role = 'admin' and customer_id is null)
    );
```

Create:

```sql
agent_conversations(
  id, staff_link_id, telegram_chat_id, state_version,
  pending_action_json, active_visit_id, created_at, updated_at
)
agent_conversation_turns(
  id, conversation_id, direction, telegram_update_id,
  telegram_message_id, text, language, model,
  attachment_json, delivery_status, created_at
)
agent_tool_events(
  id, conversation_turn_id, tool_call_id, tool_name,
  arguments_json, result_json, status, duration_ms, created_at
)
agent_intake_visits(
  id, conversation_id, customer_id, flock_id, hatchery_id,
  audit_date, state, created_at, updated_at
)
```

Add `visit_id`, `row_version default 1`, and `last_tool_event_id` to `agent_intake_sessions`. Replace the old active-session uniqueness with one active station intake per conversation while permitting multiple confirmed sessions under one visit. Add scope-validation triggers that prove a visit's flock and hatchery belong to its customer.

Do not delete or rewrite legacy rows. Backfill existing Pasgar sessions into one visit per session and set their row version to 1.

- [ ] **Step 3: Mirror the schema locally and in sync**

Increment the local database version once. Add the same camelCase tables/columns, critical-table repair entries, snake/camel sync mappings, pull ordering, and tombstone exclusions. Ordinary conversation/tool evidence is server-authored and pulled read-only; staff assignment and admin review remain admin-editable.

- [ ] **Step 4: Run focused migration and sync tests**

Run:

```bash
dart format lib/data/database lib/services/supabase test/data/database \
  test/services/supabase
flutter test \
  test/data/database/unified_agent_harness_schema_test.dart \
  test/security/unified_agent_harness_security_test.dart \
  test/services/supabase/startup_sync_service_test.dart \
  test/data/database/conversational_pasgar_intake_schema_test.dart
```

Expected: all pass; existing Pasgar tables remain readable.

- [ ] **Step 5: Update living spec and commit**

Document assignments, conversation evidence, visit grouping, and optimistic `row_version`.

```bash
git commit --only \
  supabase/migrations/20260728103000_unified_agent_harness.sql \
  lib/data/database/database_schema.dart \
  lib/data/database/database_migrations.dart \
  lib/data/database/database_helper.dart \
  lib/services/supabase/supabase_service.dart \
  lib/services/supabase/startup_sync_service.dart \
  test/data/database/unified_agent_harness_schema_test.dart \
  test/security/unified_agent_harness_security_test.dart \
  test/services/supabase/startup_sync_service_test.dart \
  docs/LIVING_SPEC.md \
  -m "feat: persist scoped agent conversations"
```

---

## Task 3: Require a customer assignment in the Agent screen

**Files:**

- Modify: `lib/data/models/hatchery_agent_models.dart`
- Modify: `lib/data/repositories/hatchery_agent_repository.dart`
- Modify: `lib/features/agents/providers/agent_monitor_provider.dart`
- Modify: `lib/features/agents/screens/agent_monitor_screen.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Modify: `test/data/models/hatchery_agent_models_test.dart`
- Modify: `test/data/repositories/hatchery_agent_repository_test.dart`
- Modify: `test/features/agents/agent_monitor_provider_test.dart`
- Modify: `test/features/agents/agent_monitor_screen_test.dart`
- Modify: `test/core/l10n/hardcoded_ui_strings_test.dart`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Add failing model/provider/widget tests**

Tests must prove:

- approving a normal link without selecting a customer is blocked;
- selecting a customer passes `accessRole: customer` and its ID to the repository;
- selecting admin access passes `accessRole: admin` with no customer ID;
- an existing allowed link displays its enforced scope;
- only an approved ChickMark app admin can change link scope.

Use:

```dart
enum TelegramAgentAccessRole {
  customer('customer'),
  admin('admin');
}
```

Run:

```bash
flutter test \
  test/data/models/hatchery_agent_models_test.dart \
  test/data/repositories/hatchery_agent_repository_test.dart \
  test/features/agents/agent_monitor_provider_test.dart \
  test/features/agents/agent_monitor_screen_test.dart
```

Expected: fail because links do not carry access scope and approval accepts only a status.

- [ ] **Step 2: Extend model and repository atomically**

Change the repository API to:

```dart
Future<void> approveStaffLink({
  required String linkId,
  required TelegramAgentAccessRole accessRole,
  required String? customerId,
  required String decidedBy,
  required DateTime decidedAt,
});
```

Validate role/customer consistency before updating. Update `status`, `accessRole`, `customerId`, `invitedBy`, timestamps, and sync metadata in one transaction.

- [ ] **Step 3: Add the assignment UI**

Replace the direct Approve action with an assignment sheet:

- default role is Customer;
- customer role requires one customer dropdown value from `linkCatalog.customers`;
- admin role clearly says it grants all-customer access;
- approval button remains disabled until the scope is valid;
- revoke remains immediate and auditable;
- existing allowed links appear in a compact “Telegram users” scope panel so assignments can be corrected.

The UI text describes access and review behavior only; it does not add bot reply copy.

- [ ] **Step 4: Run and commit**

```bash
dart format lib/data/models/hatchery_agent_models.dart \
  lib/data/repositories/hatchery_agent_repository.dart \
  lib/features/agents/providers/agent_monitor_provider.dart \
  lib/features/agents/screens/agent_monitor_screen.dart \
  lib/l10n/app_localizations.dart test
flutter test \
  test/data/models/hatchery_agent_models_test.dart \
  test/data/repositories/hatchery_agent_repository_test.dart \
  test/features/agents/agent_monitor_provider_test.dart \
  test/features/agents/agent_monitor_screen_test.dart \
  test/core/l10n/hardcoded_ui_strings_test.dart
```

Update `docs/LIVING_SPEC.md`, then:

```bash
git commit --only \
  lib/data/models/hatchery_agent_models.dart \
  lib/data/repositories/hatchery_agent_repository.dart \
  lib/features/agents/providers/agent_monitor_provider.dart \
  lib/features/agents/screens/agent_monitor_screen.dart \
  lib/l10n/app_localizations.dart \
  test/data/models/hatchery_agent_models_test.dart \
  test/data/repositories/hatchery_agent_repository_test.dart \
  test/features/agents/agent_monitor_provider_test.dart \
  test/features/agents/agent_monitor_screen_test.dart \
  test/core/l10n/hardcoded_ui_strings_test.dart \
  docs/LIVING_SPEC.md \
  -m "feat: assign Telegram users to customer scope"
```

---

## Task 4: Build the enforced scope resolver and typed tool gateway

**Files:**

- Create: `supabase/functions/telegram-hatchery-agent/agent_protocol.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_scope.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_scope_test.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_tools.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_tools_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/index.ts`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Add failing authorization tests**

Cover:

- assigned customer user resolves to exactly one customer;
- admin resolves to all customers;
- allowed customer user with no assignment fails closed before AI invocation;
- requested customer/flock/hatchery IDs outside scope return the same `scope_denied` shape as unknown IDs;
- tool JSON never contains service credentials or unrestricted table names.

Run:

```bash
deno test \
  supabase/functions/telegram-hatchery-agent/agent_scope_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools_test.ts
```

Expected: fail because scope and gateway modules do not exist.

- [ ] **Step 2: Define shared protocol types**

Use:

```ts
export interface AgentScope {
  staffLinkId: string
  accessRole: 'customer' | 'admin'
  allowedCustomerIds: readonly string[]
}

export type AgentToolName =
  | 'get_user_scope'
  | 'get_customer_context'
  | 'list_customer_flocks'
  | 'get_flock_context'
  | 'query_station_records'
  | 'compare_station_metrics'
  | 'get_record_provenance'
  | 'list_applicable_stations'
  | 'load_station_schema'
  | 'propose_intake'
  | 'start_intake'
  | 'record_station_values'
  | 'get_intake_status'
  | 'create_station_summary'
  | 'confirm_station_summary'
  | 'submit_station_for_review'
  | 'pause_intake'
  | 'resume_intake'
  | 'cancel_intake'
  | 'list_legacy_draft_questions'
  | 'answer_legacy_draft_question'

export interface AgentToolResult {
  ok: boolean
  code: string
  data: Record<string, unknown> | null
}
```

Tool descriptions may describe capabilities and argument contracts; they must not contain scripted dialogue.

- [ ] **Step 3: Resolve scope server-side**

`resolveAgentScope` accepts only the verified `staffLinkId`. It loads `access_role` and `customer_id` itself. Every tool receives the resolved scope object from the harness, never a model-authored scope.

Implement reusable guards:

```ts
assertCustomerAllowed(scope, customerId)
resolveAuthorizedFlock(client, scope, flockId)
resolveAuthorizedHatchery(client, scope, hatcheryId)
```

All denied/not-found cases return `{ok:false, code:'scope_denied', data:null}` without existence details.

- [ ] **Step 4: Build schema-validated dispatch**

`executeAgentTool(call, context)` must:

1. reject unknown tools and additional arguments;
2. validate types, lengths, dates, enum values, and row limits;
3. inject scope and current conversation/visit IDs;
4. record sanitized arguments/results through an evidence port;
5. return structured data only.

Use a maximum row limit of 100, a maximum read range of 366 days, and a maximum five tool calls per inbound Telegram turn.

- [ ] **Step 5: Run, document, and commit**

```bash
deno fmt supabase/functions/telegram-hatchery-agent
deno test \
  supabase/functions/telegram-hatchery-agent/agent_scope_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools_test.ts
```

Update `docs/LIVING_SPEC.md`, then:

```bash
git commit --only \
  supabase/functions/telegram-hatchery-agent/agent_protocol.ts \
  supabase/functions/telegram-hatchery-agent/agent_scope.ts \
  supabase/functions/telegram-hatchery-agent/agent_scope_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools_test.ts \
  supabase/functions/telegram-hatchery-agent/index.ts \
  docs/LIVING_SPEC.md \
  -m "feat: enforce agent tool customer scope"
```

---

## Task 5: Implement customer/flock read tools with provenance and deterministic metrics

**Files:**

- Create: `supabase/functions/telegram-hatchery-agent/agent_read_tools.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_read_tools_test.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_metrics.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_metrics_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_tools.ts`
- Modify: `supabase/functions/_shared/station_registry.generated.ts`
- Modify: `tool/agent_schema/station_registry.json`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Add failing factual-answer tool tests**

Fixtures must include two customers with similarly named flocks. Assert:

- `list_customer_flocks` returns only the enforced customer;
- `get_flock_context` returns status, breed, entry date, calculated age date, and sector;
- `query_station_records` selects only registry-allowlisted dimensions/measures and injects customer filter;
- a 101-row result is truncated deterministically to 100;
- `compare_station_metrics` matches existing weighted/ratio calculations;
- `get_record_provenance` reports customer, flock, schema key, record date, fetched-at timestamp, and `fresh`/`stale`/`missing`;
- no missing value is estimated.

Run:

```bash
deno test \
  supabase/functions/telegram-hatchery-agent/agent_read_tools_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_metrics_test.ts
```

Expected: fail because read tools are not implemented.

- [ ] **Step 2: Implement allowlisted reads**

Use registry persistence/read metadata to choose tables and columns. Never accept a table or column directly from model arguments. Apply:

- customer ID from scope;
- optional authorized flock;
- normalized inclusive date range;
- stable `date DESC, id DESC` ordering;
- 100-row cap;
- null preservation;
- source query timestamp.

- [ ] **Step 3: Port deterministic calculations**

Implement pure TypeScript equivalents of the Flutter formulas used by registered metrics: percentage/ratio of sums, sample-weighted mean, CV, uniformity, Pasgar score, hatchability, fertility, HOF, and configured warning thresholds. Add parity vectors to both generator source and tests so Dart and TypeScript must return the same rounded results.

- [ ] **Step 4: Run and commit**

```bash
dart run tool/agent_schema/generate_station_registry.dart --check
deno fmt supabase/functions/telegram-hatchery-agent
deno test \
  supabase/functions/telegram-hatchery-agent/station_registry_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_read_tools_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_metrics_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools_test.ts
```

Update `docs/LIVING_SPEC.md`, then commit only Task 5 files with:

```bash
git commit --only \
  tool/agent_schema/station_registry.json \
  supabase/functions/_shared/station_registry.generated.ts \
  supabase/functions/telegram-hatchery-agent/agent_read_tools.ts \
  supabase/functions/telegram-hatchery-agent/agent_read_tools_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_metrics.ts \
  supabase/functions/telegram-hatchery-agent/agent_metrics_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools.ts \
  docs/LIVING_SPEC.md \
  -m "feat: add scoped agent flock data tools"
```

---

## Task 6: Generalize durable intake state and tools

**Files:**

- Create: `supabase/functions/telegram-hatchery-agent/agent_intake_store.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_intake_store_test.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_intake_tools.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_intake_tools_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_tools.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/pasgar_store.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/pasgar_store_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/pasgar_intake_schema.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/pasgar_intake_schema_test.ts`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Add failing generic intake contract tests**

Test:

- `start_intake` rejects an unconfirmed pending action;
- `propose_intake` records a model-selected pending action without creating an intake and expires after five turns or 15 minutes;
- it accepts only an applicable registry schema and authorized context;
- one message can record several fields in any order;
- valid values persist while invalid/low-confidence values return structured clarification needs;
- explicit zero is accepted only where schema permits;
- changing a value invalidates the prior summary and increments `row_version`;
- summary creation requires all completion fields and uses backend calculations;
- confirmation accepts only the current summary version;
- submit creates admin-review state but no panel row;
- pause/resume/cancel preserve evidence;
- optimistic-version conflict returns `state_conflict` without losing data;
- a confirmed first station and second station share one visit.

Run:

```bash
deno test \
  supabase/functions/telegram-hatchery-agent/agent_intake_store_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_intake_tools_test.ts
```

Expected: fail because generic store/tools do not exist.

- [ ] **Step 2: Implement generic state types**

Use registry-independent session types:

```ts
export interface AgentIntakeSession {
  id: string
  visitId: string
  schemaKey: string
  schemaVersion: number
  state: AgentIntakeState
  rowVersion: number
  context: AgentIntakeContext
  workingValues: Readonly<Record<string, unknown>>
  pendingClarification: AgentClarification | null
  summaryVersion: number
  summarySnapshot: AgentSummarySnapshot | null
  userConfirmedAt: string | null
}
```

Keep source phrase, confidence, clarification reason, and tool-event link per field. Store accepted values with an upsert keyed by session and field.

- [ ] **Step 3: Implement registry-driven validation and calculation**

`record_station_values` receives:

```ts
{
  intakeId: string,
  expectedRowVersion: number,
  values: [
    {
      fieldKey: string,
      value: unknown,
      sourcePhrase: string,
      confidence: number
    }
  ]
}
```

The backend returns accepted keys, rejected keys with machine-readable reasons, missing required keys, completeness, and the new row version. It never returns final reply text.

`propose_intake` stores only `{kind:'station_intake', proposedAt, turnId}` on
the conversation. The AI writes the natural confirmation question itself.
`start_intake` requires a later explicit user-confirmation turn linked to that
pending action, then clears the action. Catalog reads are safe before session
creation, allowing the confirmed user to see applicable modules before choosing
one.

- [ ] **Step 4: Adapt Pasgar without a special conversation controller**

Move Pasgar field semantics and calculations into `chicks.pasgar@1`. Keep thin compatibility readers for existing rows and the current approval RPC. Mark `pasgar_conversation.ts` and `pasgar_interpreter.ts` as legacy-only pending deletion in Task 9; no new caller may depend on them.

- [ ] **Step 5: Run and commit**

```bash
deno fmt supabase/functions/telegram-hatchery-agent
deno test \
  supabase/functions/telegram-hatchery-agent/agent_intake_store_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_intake_tools_test.ts \
  supabase/functions/telegram-hatchery-agent/pasgar_store_test.ts \
  supabase/functions/telegram-hatchery-agent/pasgar_intake_schema_test.ts
```

Update `docs/LIVING_SPEC.md`, then:

```bash
git commit --only \
  supabase/functions/telegram-hatchery-agent/agent_intake_store.ts \
  supabase/functions/telegram-hatchery-agent/agent_intake_store_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_intake_tools.ts \
  supabase/functions/telegram-hatchery-agent/agent_intake_tools_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools.ts \
  supabase/functions/telegram-hatchery-agent/pasgar_store.ts \
  supabase/functions/telegram-hatchery-agent/pasgar_store_test.ts \
  supabase/functions/telegram-hatchery-agent/pasgar_intake_schema.ts \
  supabase/functions/telegram-hatchery-agent/pasgar_intake_schema_test.ts \
  docs/LIVING_SPEC.md \
  -m "feat: generalize agent station intake tools"
```

---

## Task 7: Implement the bounded AI tool loop

**Files:**

- Create: `supabase/functions/telegram-hatchery-agent/agent_prompt.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_provider.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_provider_test.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_runtime.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_runtime_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_protocol.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/deno.json`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Add failing provider/runtime tests**

Use a fake Responses API. Test:

- plain model text becomes the one normal reply;
- a tool call executes and its structured result returns to the same model turn;
- several safe tool calls can run up to five;
- the sixth call stops with infrastructure status;
- malformed/unknown tool calls do not execute;
- a tool's untrusted output cannot add instructions or tools;
- recent history is bounded;
- provider timeout/unavailability preserves state and returns a failure status for the webhook fallback;
- OpenRouter 402 fallback is provider behavior, not conversational rerouting.

Run:

```bash
deno test \
  supabase/functions/telegram-hatchery-agent/agent_provider_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_runtime_test.ts
```

Expected: fail because provider/runtime modules do not exist.

- [ ] **Step 2: Define the system policy**

The prompt must state behavior, not fixed replies:

- respond naturally in the user's Arabic, English, or mixed language;
- remain within ChickMark customer/flock/audit operations;
- use tools for facts, calculations, catalog, and persistence;
- never invent missing records or arithmetic;
- mention customer/flock/station/date/freshness when explaining data;
- ask a natural confirmation when data-entry intent is possible;
- never call `start_intake` until the user confirms;
- accept values in any order and ask one focused clarification when needed;
- show one complete station summary and confirm its current version;
- never claim final save before admin approval.

Do not include greetings, phrase examples used as classifiers, or prewritten success messages.

- [ ] **Step 3: Implement provider adapter and loop**

Expose:

```ts
export async function runAgentTurn(
  input: AgentTurnInput,
  deps: AgentRuntimeDependencies,
): Promise<AgentTurnResult>
```

Build model input from the new message/attachment, the most recent 20 bounded turns, active visit/intake state, enforced scope summary, pending action, and typed tool definitions. Execute serial tool calls, persist sanitized evidence and durations, and stop after five calls or 20 seconds.

- [ ] **Step 4: Run and commit**

```bash
deno fmt supabase/functions/telegram-hatchery-agent
deno test \
  supabase/functions/telegram-hatchery-agent/agent_provider_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_runtime_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools_test.ts
```

Update `docs/LIVING_SPEC.md`, then:

```bash
git commit --only \
  supabase/functions/telegram-hatchery-agent/agent_prompt.ts \
  supabase/functions/telegram-hatchery-agent/agent_provider.ts \
  supabase/functions/telegram-hatchery-agent/agent_provider_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_runtime.ts \
  supabase/functions/telegram-hatchery-agent/agent_runtime_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_protocol.ts \
  supabase/functions/telegram-hatchery-agent/deno.json \
  docs/LIVING_SPEC.md \
  -m "feat: add bounded ChickMark AI tool loop"
```

---

## Task 8: Route every authorized Telegram turn through the unified agent

**Files:**

- Modify: `supabase/functions/telegram-hatchery-agent/index.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/index_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/telegram.ts`
- Create: `supabase/functions/telegram-hatchery-agent/unified_agent_e2e_test.ts`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Add failing webhook characterization tests**

Add behavior tests for:

- unseen colloquial Arabic greeting reaches `runAgentTurn`;
- fragment, misspelling, English question, and mixed-language turn reach the same runtime;
- a message during a legacy open question still reaches the runtime;
- a message during an active intake still reaches the runtime;
- duplicate update produces no model call, reply, or write;
- pending/revoked users never invoke the model;
- provider failure sends only the bounded infrastructure retry;
- attachment metadata/content reaches the runtime;
- successful normal reply is exactly the model reply, with no backend prefix/suffix.

Tests must assert behavior/tool calls, not exact AI wording.

Run:

```bash
deno test \
  supabase/functions/telegram-hatchery-agent/index_test.ts \
  supabase/functions/telegram-hatchery-agent/unified_agent_e2e_test.ts \
  --allow-env
```

Expected: fail because current routing returns from the Pasgar controller, hardcoded classifier, or legacy answer interceptor.

- [ ] **Step 2: Replace the authorized-message routing section**

Keep this order only:

1. webhook secret/method validation;
2. Telegram update normalization;
3. staff pending/allowed/revoked gate;
4. agent enabled gate;
5. duplicate receipt check;
6. source/attachment loading;
7. conversation turn persistence;
8. enforced scope resolution;
9. `runAgentTurn`;
10. model reply delivery/evidence.

Delete `isConversationalOnlySource`, `hasHatcheryDataSignal`, the greeting/phrase arrays and regexes, direct `tryHandleQuestionAnswer` interception, and direct `tryHandlePasgarConversation` interception. Do not fall through to the legacy extraction form when the model/provider fails.

- [ ] **Step 3: Preserve legacy data as tools, not routers**

Keep old draft tables and extraction helpers for existing records. New inbound authorized turns access them only through the tool gateway added in Task 11.

- [ ] **Step 4: Run and commit**

```bash
deno fmt supabase/functions/telegram-hatchery-agent
deno test supabase/functions/telegram-hatchery-agent --allow-env
```

Update `docs/LIVING_SPEC.md`, then:

```bash
git commit --only \
  supabase/functions/telegram-hatchery-agent/index.ts \
  supabase/functions/telegram-hatchery-agent/index_test.ts \
  supabase/functions/telegram-hatchery-agent/telegram.ts \
  supabase/functions/telegram-hatchery-agent/unified_agent_e2e_test.ts \
  docs/LIVING_SPEC.md \
  -m "refactor: route authorized Telegram turns through AI agent"
```

---

## Task 9: Complete all 18 station adapters and multi-station transcript flows

**Files:**

- Modify: `tool/agent_schema/station_registry.json`
- Modify: `lib/data/agent/station_registry.g.dart`
- Modify: `supabase/functions/_shared/station_registry.generated.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_intake_tools.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_metrics.ts`
- Create: `supabase/functions/telegram-hatchery-agent/station_adapter_test.ts`
- Create: `supabase/functions/telegram-hatchery-agent/conversation_transcript_test.ts`
- Delete: `supabase/functions/telegram-hatchery-agent/pasgar_conversation.ts`
- Delete: `supabase/functions/telegram-hatchery-agent/pasgar_conversation_test.ts`
- Delete: `supabase/functions/telegram-hatchery-agent/pasgar_conversation_e2e_test.ts`
- Delete: `supabase/functions/telegram-hatchery-agent/pasgar_interpreter.ts`
- Delete: `supabase/functions/telegram-hatchery-agent/pasgar_interpreter_test.ts`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Add failing adapter and transcript tests**

For each of the 18 schemas, provide one valid fixture, one boundary-invalid fixture, one missing-required fixture, expected calculated values, and expected persistence payload. Add transcript scenarios for:

- Arabic, English, and mixed language;
- natural data-entry inference followed by confirmation;
- catalog filtered to an authorized breeder flock;
- station selection by number, name, alias, and description;
- all values in one message;
- several values in any order;
- one focused ambiguity clarification;
- correction invalidating the old summary;
- ordinary flock-data question during active intake;
- confirming one station, adding a second to the same visit, then finishing.

Run:

```bash
dart run tool/agent_schema/generate_station_registry.dart --check
deno test \
  supabase/functions/telegram-hatchery-agent/station_adapter_test.ts \
  supabase/functions/telegram-hatchery-agent/conversation_transcript_test.ts
```

Expected: fail until every schema has a complete adapter.

- [ ] **Step 2: Finish schema semantics and regenerate**

Use current audit UI/provider/codec logic for required fields, ranges, allowed layers, calculations, and JSON payload shapes. Do not make every database column required. A module is complete when its current UI-equivalent required inputs are present and its backend-calculated fields can be produced.

- [ ] **Step 3: Remove the Pasgar-specific conversational path**

Once the generic transcript suite covers Pasgar start, values, clarification, summary, correction, confirmation, and review submission, delete the special interpreter/controller files. Keep only compatibility schema/store code required to read existing Pasgar evidence.

- [ ] **Step 4: Run full station suites and commit**

```bash
dart run tool/agent_schema/generate_station_registry.dart --check
flutter test test/data/agent/station_registry_test.dart
deno fmt supabase/functions
deno test supabase/functions/telegram-hatchery-agent --allow-env
```

Update `docs/LIVING_SPEC.md`, then:

```bash
git commit --only \
  tool/agent_schema/station_registry.json \
  lib/data/agent/station_registry.g.dart \
  supabase/functions/_shared/station_registry.generated.ts \
  supabase/functions/telegram-hatchery-agent \
  docs/LIVING_SPEC.md \
  -m "feat: support all hatchery station intake schemas"
```

---

## Task 10: Generalize admin review and authenticated final approval

**Files:**

- Create: `supabase/functions/approve-agent-intake/index.ts`
- Create: `supabase/functions/approve-agent-intake/index_test.ts`
- Create: `supabase/functions/_shared/agent_intake_approval.ts`
- Create: `supabase/functions/_shared/agent_intake_approval_test.ts`
- Modify: `supabase/migrations/20260728103000_unified_agent_harness.sql`
- Modify: `lib/data/models/agent_intake_models.dart`
- Modify: `lib/data/repositories/agent_intake_repository.dart`
- Modify: `lib/services/supabase/agent_intake_approval_service.dart`
- Modify: `lib/features/agents/providers/agent_monitor_provider.dart`
- Modify: `lib/features/agents/screens/agent_monitor_screen.dart`
- Create: `lib/features/agents/widgets/agent_intake_review_card.dart`
- Delete: `lib/features/agents/widgets/pasgar_intake_review_card.dart`
- Modify: `test/data/models/agent_intake_models_test.dart`
- Modify: `test/data/repositories/agent_intake_repository_test.dart`
- Modify: `test/services/supabase/agent_intake_approval_service_test.dart`
- Modify: `test/features/agents/agent_monitor_provider_test.dart`
- Modify: `test/features/agents/agent_monitor_screen_test.dart`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Add failing generic review tests**

Prove:

- review cards render schema-driven field labels, units, sources, confidence, calculations, and conversation evidence;
- admin edits revalidate and create a new summary version;
- reject requires a reason;
- approve requires authenticated current app admin;
- approval is idempotent;
- approval rejects stale/unconfirmed/mismatched schema versions;
- approval creates or targets the authorized audit visit and writes only registry-mapped columns;
- two approved station sessions can join the same audit session;
- non-admin callers and cross-customer target sessions fail;
- Telegram itself cannot call approval.

- [ ] **Step 2: Replace Pasgar-only Dart review types**

Rename provider state/getters/actions from Pasgar-specific names to generic intake names. `AgentIntakeDetails` resolves its labels and validation from `AgentStationRegistry.require(session.schemaKey, session.schemaVersion)`.

Change the approval port to:

```dart
abstract interface class AgentIntakeApprovalPort {
  Future<AgentIntakeApprovalResult> approve({
    required String intakeId,
    String? targetSessionId,
    required int expectedSummaryVersion,
  });
}
```

- [ ] **Step 3: Implement authenticated approval Edge Function**

The function must:

1. require a valid Supabase bearer token;
2. verify the caller is an approved app admin;
3. load and lock the confirmed intake;
4. validate exact schema/version and summary version;
5. resolve the generated persistence adapter;
6. validate customer/flock/hatchery/target-session consistency;
7. call an atomic database RPC that creates/updates the audit session and mapped panel row;
8. mark the intake approved with final IDs and reviewer evidence;
9. return the same result on safe retry.

The model, Telegram webhook, and anonymous role receive no approval capability.

- [ ] **Step 4: Run focused Flutter, Deno, and security tests**

```bash
deno test \
  supabase/functions/_shared/agent_intake_approval_test.ts \
  supabase/functions/approve-agent-intake/index_test.ts \
  --allow-env
flutter test \
  test/data/models/agent_intake_models_test.dart \
  test/data/repositories/agent_intake_repository_test.dart \
  test/services/supabase/agent_intake_approval_service_test.dart \
  test/features/agents/agent_monitor_provider_test.dart \
  test/features/agents/agent_monitor_screen_test.dart \
  test/security/unified_agent_harness_security_test.dart
```

- [ ] **Step 5: Update docs and commit**

```bash
git commit --only \
  supabase/functions/approve-agent-intake \
  supabase/functions/_shared/agent_intake_approval.ts \
  supabase/functions/_shared/agent_intake_approval_test.ts \
  supabase/migrations/20260728103000_unified_agent_harness.sql \
  lib/data/models/agent_intake_models.dart \
  lib/data/repositories/agent_intake_repository.dart \
  lib/services/supabase/agent_intake_approval_service.dart \
  lib/features/agents/providers/agent_monitor_provider.dart \
  lib/features/agents/screens/agent_monitor_screen.dart \
  lib/features/agents/widgets/agent_intake_review_card.dart \
  lib/features/agents/widgets/pasgar_intake_review_card.dart \
  test/data/models/agent_intake_models_test.dart \
  test/data/repositories/agent_intake_repository_test.dart \
  test/services/supabase/agent_intake_approval_service_test.dart \
  test/features/agents/agent_monitor_provider_test.dart \
  test/features/agents/agent_monitor_screen_test.dart \
  docs/LIVING_SPEC.md \
  -m "feat: review and approve generic agent intakes"
```

---

## Task 11: Expose legacy drafts through tools and finish observability

**Files:**

- Create: `supabase/functions/telegram-hatchery-agent/agent_legacy_tools.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_legacy_tools_test.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_evidence.ts`
- Create: `supabase/functions/telegram-hatchery-agent/agent_evidence_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_tools.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/answer_routing.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/index.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/index_test.ts`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Add failing legacy/evidence tests**

Verify:

- open legacy questions are returned only when the agent calls `list_legacy_draft_questions`;
- an answer is stored only through `answer_legacy_draft_question` with explicit submission/question identity;
- ordinary messages never auto-bind to a legacy question;
- tool evidence records scope, tool name, sanitized arguments, result status, duration, and state versions;
- logs omit secrets, raw attachment bytes, direct contact fields, and unnecessary customer rows;
- delivery failure updates evidence without rerunning the model.

- [ ] **Step 2: Extract safe legacy tools**

Refactor reusable database operations out of `answer_routing.ts`. Keep any existing formatters only for historical/admin display; the AI generates Telegram wording from structured tool results.

- [ ] **Step 3: Implement evidence and metrics**

Add counters/log events for provider failure, tool validation failure, clarification, scope denial, stale data, duplicate update, tool-loop limit, response duration, and delivery failure. Hash or omit unneeded identifiers in logs; retain full authorized evidence only in protected tables.

- [ ] **Step 4: Run and commit**

```bash
deno fmt supabase/functions/telegram-hatchery-agent
deno test supabase/functions/telegram-hatchery-agent --allow-env
```

Update `docs/LIVING_SPEC.md`, then:

```bash
git commit --only \
  supabase/functions/telegram-hatchery-agent/agent_legacy_tools.ts \
  supabase/functions/telegram-hatchery-agent/agent_legacy_tools_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_evidence.ts \
  supabase/functions/telegram-hatchery-agent/agent_evidence_test.ts \
  supabase/functions/telegram-hatchery-agent/agent_tools.ts \
  supabase/functions/telegram-hatchery-agent/answer_routing.ts \
  supabase/functions/telegram-hatchery-agent/index.ts \
  supabase/functions/telegram-hatchery-agent/index_test.ts \
  docs/LIVING_SPEC.md \
  -m "feat: audit unified agent tools and legacy drafts"
```

---

## Task 12: Add adversarial, factual, and reliability acceptance tests

**Files:**

- Create: `supabase/functions/telegram-hatchery-agent/agent_acceptance_test.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/conversation_transcript_test.ts`
- Modify: `test/security/unified_agent_harness_security_test.dart`
- Modify: `test/security/secret_scan_test.dart`
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Build an acceptance matrix from the approved design**

Add deterministic fake-model scenarios for all 11 acceptance criteria:

- no phrase classifier;
- one unified agent decision;
- normal/admin scope;
- factual reads with provenance;
- natural intake inference plus confirmation;
- dynamic sector-filtered catalog;
- any-order data and focused clarification;
- one versioned confirmation;
- multiple stations in one visit;
- no legacy interception;
- security/reliability.

Include prompt-injection attempts in Arabic and English asking for another customer, SQL, secrets, bypassing confirmation, and direct final save. Assert denied tool results and no leaked existence.

- [ ] **Step 2: Add concurrency/idempotency tests**

Simulate duplicate Telegram update, two corrections at the same row version, provider failure after a successful value write, Telegram delivery failure, resume after restart, and stale summary confirmation.

- [ ] **Step 3: Run focused acceptance**

```bash
deno test \
  supabase/functions/telegram-hatchery-agent/agent_acceptance_test.ts \
  supabase/functions/telegram-hatchery-agent/conversation_transcript_test.ts \
  --allow-env
flutter test \
  test/security/unified_agent_harness_security_test.dart \
  test/security/secret_scan_test.dart
```

Expected: all pass without exact reply-string assertions except deterministic infrastructure/access messages.

- [ ] **Step 4: Document and commit**

Update `docs/LIVING_SPEC.md` with the implemented behavior and explicit fallback boundaries.

```bash
git commit --only \
  supabase/functions/telegram-hatchery-agent/agent_acceptance_test.ts \
  supabase/functions/telegram-hatchery-agent/conversation_transcript_test.ts \
  test/security/unified_agent_harness_security_test.dart \
  test/security/secret_scan_test.dart \
  docs/LIVING_SPEC.md \
  -m "test: cover unified agent acceptance and safety"
```

---

## Task 13: Full local verification and deployment gate

**Files:**

- Modify only if verification exposes a defect: files already named in Tasks 1–12
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Verify generated artifacts and formatting**

```bash
dart run tool/agent_schema/generate_station_registry.dart --check
dart format --output=none --set-exit-if-changed lib test tool
deno fmt --check supabase/functions
```

- [ ] **Step 2: Run all agent Deno tests**

```bash
deno test supabase/functions/telegram-hatchery-agent \
  supabase/functions/approve-agent-intake \
  supabase/functions/_shared/agent_intake_approval_test.ts \
  --allow-env
```

- [ ] **Step 3: Run the focused Flutter regression set**

```bash
flutter test \
  test/data/agent \
  test/data/database/telegram_hatchery_agent_schema_test.dart \
  test/data/database/conversational_pasgar_intake_schema_test.dart \
  test/data/database/unified_agent_harness_schema_test.dart \
  test/data/models/agent_intake_models_test.dart \
  test/data/models/hatchery_agent_models_test.dart \
  test/data/repositories/agent_intake_repository_test.dart \
  test/data/repositories/hatchery_agent_repository_test.dart \
  test/features/agents \
  test/services/supabase/agent_intake_approval_service_test.dart \
  test/services/supabase/startup_sync_service_test.dart \
  test/services/supabase/supabase_service_security_test.dart \
  test/security
```

- [ ] **Step 4: Run static analysis**

```bash
flutter analyze
deno check supabase/functions/telegram-hatchery-agent/index.ts
deno check supabase/functions/approve-agent-intake/index.ts
```

- [ ] **Step 5: Inspect the diff for forbidden architecture**

Run:

```bash
rg -n \
  "isConversationalOnlySource|hasHatcheryDataSignal|greeting|mission_chat|start_pasgar|tryHandlePasgarConversation" \
  supabase/functions/telegram-hatchery-agent
git diff --check
git status --short
```

Expected:

- no fixed conversational classifier or Pasgar controller remains;
- any `greeting` occurrence is only in a negative test/assertion or documentation;
- `git diff --check` is clean;
- unrelated user changes remain untouched.

- [ ] **Step 6: Review deployment inputs without deploying**

Confirm:

- migration ordering and idempotent backfill;
- Edge Function secrets are referenced only by environment name;
- `verify_jwt=false` remains only on the Telegram webhook;
- `approve-agent-intake` requires JWT;
- service-role access is server-side;
- rollback is additive: pause agent, redeploy prior function, keep new evidence tables.

Record exact passing commands and remaining assumptions in `docs/LIVING_SPEC.md`. Do not deploy until the human reviewer approves this gate.

- [ ] **Step 7: Commit verification-only fixes/docs**

If verification required code fixes, repeat the narrow failing test before the full gate. Commit only reviewed files:

```bash
git commit --only docs/LIVING_SPEC.md -m "docs: record unified agent verification"
```

If other verified fixes are included, name them explicitly in the `--only` list rather than staging the worktree broadly.

---

## Task 14: Human review, staged Supabase rollout, and live smoke test

**Files:** No local code changes unless the smoke test exposes a confirmed defect.

- [ ] **Step 1: Obtain explicit human approval**

Present:

- task id `AI-AGENT-HARNESS-001`;
- implementation summary;
- changed files grouped by registry, database, Edge Function, Flutter review UI, and tests;
- exact validation results;
- migration/rollback risks;
- confirmation that no fixed conversational classifier remains.

Do not mark the product task complete before explicit approval.

- [ ] **Step 2: Apply migration after approval**

Use the connected Supabase project and verify table/constraint/RLS state after migration. Stop on any mismatch; do not continue to function deployment.

- [ ] **Step 3: Deploy functions in dependency order**

Deploy `approve-agent-intake` first, verify JWT rejection and admin acceptance in a non-mutating test, then deploy `telegram-hatchery-agent`. Inspect deployment status until terminal.

- [ ] **Step 4: Run live scoped smoke tests**

Use approved test identities and non-production fixture records:

1. pending user is denied before AI;
2. assigned user greeting gets a natural AI reply;
3. assigned user asks a flock fact and receives exact scoped provenance;
4. another customer's flock is not revealed;
5. natural data-entry request receives a confirmation question;
6. confirmed request receives applicable modules;
7. Pasgar values in one message produce one complete summary;
8. correction changes summary version;
9. confirmation creates admin review only;
10. second station joins the visit;
11. app admin reviews and approves;
12. duplicate Telegram update produces no duplicate reply/write.

- [ ] **Step 5: Final handoff**

Report:

- task id;
- approved completion status;
- summary of implemented behavior;
- files and migrations changed;
- local and live commands/tests run;
- Edge Function versions;
- remaining risks or assumptions;
- rollback steps.
