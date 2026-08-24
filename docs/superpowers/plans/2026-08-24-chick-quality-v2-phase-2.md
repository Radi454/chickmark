# Chick Quality V2 Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add stable Chick sample identity, domain, normalized scope, replicate, provenance, and generated bidirectional registry persistence mappings without splitting historical combined rows.

**Architecture:** Extend the existing `chick_quality` and `chick_weights` rows with an immutable V2 identity envelope. A focused identity service constructs and validates normalized scope/sample keys; repositories allocate replicates transactionally and never overwrite a different id. SQLite v64 and one Supabase migration backfill existing rows deterministically before enforcing customer/sample-key uniqueness. The station-registry generator emits both mapping directions for Dart and TypeScript so UI and agent paths share the same persistence contract.

**Tech Stack:** Flutter/Dart, sqflite, generated Dart/TypeScript registry artifacts, Supabase/Postgres migrations, Deno tests.

**Spec:** `docs/superpowers/specs/2026-08-24-chick-quality-v2-phases-2-5-design.md`

## Global Constraints

- Do not push or apply migrations to live Supabase.
- Keep existing hierarchy columns and wide/JSON fields active.
- Preserve every existing row id and every duplicate as a replicate.
- Never match, overwrite, prune, or tombstone one sample because another id has the same scope.
- `chick_weights` uses domain `chicks.weights`; existing `chick_quality` rows use `chicks.legacy_combined`.
- Phase 2 does not create observations or split combined rows.
- Every meaningful code change updates `docs/LIVING_SPEC.md` and prepends a dated `docs/CHANGELOG.md` entry in the same phase commit.

---

### Task 1: Stable identity envelope and generated bidirectional mapping

**Files:**
- Create: `lib/data/models/chick_sample_identity.dart`
- Modify: `lib/data/models/panel_sample_model.dart`
- Modify: `tool/agent_schema/generate_station_registry.dart`
- Modify generated: `lib/data/agent/station_registry.g.dart`
- Modify generated: `supabase/functions/_shared/station_registry.generated.ts`
- Modify: `lib/data/agent/station_registry.dart`
- Modify: `lib/data/agent/station_adapter.dart`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_station_adapter.ts`
- Test: `test/data/models/chick_sample_identity_test.dart`
- Test: `test/data/agent/station_registry_test.dart`
- Test: `test/features/audits/logic/chick_quality_round_trip_test.dart`
- Test: `supabase/functions/telegram-hatchery-agent/station_registry_test.ts`

**Interfaces:**
- Produces `ChickSampleIdentity`, `ChickSampleProvenance`, `ChickSampleIdentity.buildScopeKey`, `buildSampleKey`, and `validate`.
- Produces registry lookups `fieldForLocalColumn`, `fieldForRemoteColumn`, `localValuesFromColumns`, and their TypeScript equivalents.
- `sampleKey` format is a canonical JSON array encoded as base64url without padding: `[domain,sessionId,scopeType,scopeKey,replicate]`. This avoids delimiter ambiguity while remaining deterministic.
- `scopeKey` is canonical JSON containing only the declared scope hierarchy. Pool is `{}`; non-pool keys preserve exact trimmed identifiers and reject required blanks.

- [ ] **Step 1: Write failing identity tests**

Add tests proving: the same inputs produce the same key; delimiter-like user text cannot collide; pool scope accepts blank hierarchy; non-pool scope requires its declared identifiers; replicate is positive; changing a mutable draft id has no effect; `PanelRecord.fromMap().toMap()` retains id and all V2 fields.

- [ ] **Step 2: Run identity tests and confirm RED**

Run: `flutter test test/data/models/chick_sample_identity_test.dart`

Expected: compilation failure because `chick_sample_identity.dart` and V2 model fields do not exist.

- [ ] **Step 3: Implement the minimal identity model**

Implement immutable value types, canonical JSON serialization with recursively sorted map keys, base64url sample-key encoding, structural validation, and `PanelRecord` map support for `domain`, `schemaVersion`, `scopeKey`, `replicate`, `sampleKey`, `source`, `captureMethod`, `createdBy`, `deviceId`, `sourceRefId`, and `observedAt`.

- [ ] **Step 4: Run identity tests and confirm GREEN**

Run: `flutter test test/data/models/chick_sample_identity_test.dart`

- [ ] **Step 5: Write failing generated-mapping tests**

Assert every registry input and calculation persistence entry has exactly one local and remote reverse lookup; no two fields in one schema claim the same column; Chick round trips use generated column-to-field mapping rather than a test-owned hand-written map.

- [ ] **Step 6: Run registry/round-trip tests and confirm RED**

Run: `flutter test test/data/agent/station_registry_test.dart test/features/audits/logic/chick_quality_round_trip_test.dart`

Run: `deno test supabase/functions/telegram-hatchery-agent/station_registry_test.ts`

Expected: missing reverse mapping APIs or stale generated artifacts.

- [ ] **Step 7: Extend the registry generator and adapters**

Generate immutable local/remote reverse maps per schema and helpers that decode persisted JSON/list/integer-boolean values bidirectionally. Reject duplicate local or remote column claims during generation. Replace the round-trip fixture's hand-written field map with the generated helpers.

- [ ] **Step 8: Regenerate and verify both artifacts**

Run: `dart run tool/agent_schema/generate_station_registry.dart`

Run: `dart run tool/agent_schema/generate_station_registry.dart --check`

Run the Dart and Deno tests from Step 6 and confirm GREEN.

---

### Task 2: SQLite v64 additive schema and safe backfill

**Files:**
- Modify: `lib/data/database/database_helper.dart`
- Modify: `lib/data/database/database_schema.dart`
- Modify: `lib/data/database/database_migrations.dart`
- Modify: `lib/data/models/panel_sample_schema.dart`
- Test: `test/data/database/chick_v2_phase2_migration_test.dart`
- Test: `test/data/database/database_helper_migration_test.dart`
- Test: `test/data/database/panel_metadata_columns_test.dart`
- Test: `test/data/database/schema_parity_test.dart`
- Test: `test/data/database/panel_row_identity_schema_test.dart`

**Interfaces:**
- Adds nullable V2 columns to fresh/reconciled panel schemas, with `replicate INTEGER` and `schemaVersion INTEGER`.
- v64 backfills only `chick_quality` and `chick_weights`, then creates unique indexes `idx_chick_quality_sample_key` and `idx_chick_weights_sample_key` on `(customerId, sampleKey)`.
- Drops `idx_chick_quality_identity`/the Phase-1 hierarchy identity indexes only after successful backfill and uniqueness proof.

- [ ] **Step 1: Write failing v63→v64 migration tests**

Seed multiple legacy rows including identical/blank hierarchy, out-of-order timestamps, and existing V2-shaped values. Assert ids and measurements are unchanged, duplicates receive consecutive replicates and distinct keys, explicit existing identity is retained when valid, weights/combined domains are exact, provenance defaults are conservative (`source=legacy`, `captureMethod=unknown`, `observedAt=createdAt`), and a rerun is idempotent.

- [ ] **Step 2: Run migration tests and confirm RED**

Run: `flutter test test/data/database/chick_v2_phase2_migration_test.dart`

- [ ] **Step 3: Add v64 schema and guarded migration**

Bump SQLite to 64; add columns to fresh creation and critical-column repair; wire `_applyV64Upgrade`; backfill inside a transaction ordered by `customerId, sessionId, createdAt, id`; allocate replicates per normalized domain/scope; validate row counts and non-null/distinct sample keys before replacing indexes. Do not change measurement or hierarchy values.

- [ ] **Step 4: Run migration/schema tests and confirm GREEN**

Run the five tests listed for this task.

---

### Task 3: Transactional repository allocation and no-overwrite save behavior

**Files:**
- Modify: `lib/data/repositories/panel_sample_repository.dart`
- Modify: `lib/features/audits/services/audit_panel_save_coordinator.dart`
- Modify: `lib/features/audits/logic/panel_row_to_draft.dart`
- Modify: `lib/features/audits/providers/audit_provider.dart`
- Test: `test/data/repositories/panel_sample_identity_test.dart`
- Test: `test/data/repositories/panel_sample_repository_test.dart`
- Test: `test/features/audits/chick_station_panel_persistence_test.dart`
- Test: `test/features/audits/audit_provider_sample_mode_test.dart`
- Test: `test/features/audits/full_audit_panel_smoke_test.dart`

**Interfaces:**
- Adds `prepareChickIdentity(txn, table, row)` which preserves a valid persisted envelope, finds the same id first, allocates the next replicate for a new id, and never queries hierarchy to select an overwrite target.
- Save/reload carries the persisted row id and V2 envelope in draft state; new rows mint `Uuid().v7()` once.

- [ ] **Step 1: Write failing concurrency/coexistence tests**

Cover two new ids saved concurrently at the same human scope, agent and human rows at one scope, reload/edit retaining id/key, scope collision allocating a replicate, and pruning one draft not deleting another replicate.

- [ ] **Step 2: Run repository/provider tests and confirm RED**

Run the five test files listed for this task.

- [ ] **Step 3: Implement transactional identity preparation**

Move identity allocation into the same SQLite transaction as the upsert. Use the persisted id as the only update target. Retry replicate allocation after a unique-key constraint race. Carry identity fields through row reconstruction and save coordinator calls. Remove hierarchy-key exceptions that allow different ids to absorb or prune one another for Chick tables; keep non-Chick behavior unchanged.

- [ ] **Step 4: Run repository/provider tests and confirm GREEN**

Run the five test files listed for this task.

---

### Task 4: Supabase identity/provenance migration and parity

**Files:**
- Create via CLI: `supabase/migrations/<timestamp>_chick_quality_v2_phase2_identity.sql`
- Modify: `scripts/test_supabase_security_hardening.sh`
- Modify: `test/data/database/fixtures/chick_panel_cloud_columns.json`
- Test: `test/data/database/chick_panel_cloud_parity_test.dart`
- Test: `test/data/database/chick_v2_phase2_migration_test.dart`

**Interfaces:**
- Adds snake_case columns mirroring v64 and customer/sample-key unique indexes.
- Replaces Phase-1 identity constraints only after a deterministic set-based backfill.
- Existing app authorization policies remain unchanged; no new public table is introduced in Phase 2.

- [ ] **Step 1: Check CLI capabilities and create migration file through CLI**

Run: `supabase --version && supabase migration new chick_quality_v2_phase2_identity`

- [ ] **Step 2: Write failing ephemeral-Postgres assertions**

Extend the harness to seed duplicate/blank legacy Chick rows before the migration, then assert row/id preservation, exact domains, distinct replicates/sample keys, idempotence, uniqueness enforcement, and removal of the interim hierarchy identity constraint.

- [ ] **Step 3: Run security harness and confirm RED**

Run: `bash scripts/test_supabase_security_hardening.sh`

- [ ] **Step 4: Implement guarded SQL backfill and indexes**

Use `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`; rank legacy duplicates deterministically with window functions; retain valid pre-existing envelopes; validate with explicit exception blocks before setting NOT NULL where compatibility permits; create customer/sample-key unique indexes; drop only the named Phase-1 constraint/index. Do not apply remotely.

- [ ] **Step 5: Refresh the checked-in cloud-column fixture from the ephemeral migrated schema**

Run the harness fixture-update mechanism, inspect the diff, then rerun the cloud parity and security tests to confirm GREEN.

---

### Task 5: Agent intake emits the same identity and provenance

**Files:**
- Modify: `supabase/functions/_shared/agent_intake_approval.ts`
- Modify: `supabase/functions/approve-agent-intake/index.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_intake_store.ts`
- Modify: `supabase/functions/telegram-hatchery-agent/agent_station_adapter.ts`
- Test: `supabase/functions/_shared/agent_intake_approval_test.ts`
- Test: `supabase/functions/approve-agent-intake/index_test.ts`
- Test: `supabase/functions/telegram-hatchery-agent/agent_intake_store_test.ts`

**Interfaces:**
- Agent-approved panel payload contains domain/schema/scope/replicate/sample key and provenance (`source=agent`, capture method from intake source, creator/device/source-ref when known, observed time from audit/intake context).
- Agent sample key construction uses the same canonical algorithm as Dart and allocates a new replicate instead of overwriting a human sample.

- [ ] **Step 1: Write failing agent/human coexistence and payload tests**

Assert exact identity/provenance fields, same canonical vectors as Dart, and the approval RPC receives enough identity to allocate without an `on conflict` hierarchy overwrite.

- [ ] **Step 2: Run Deno tests and confirm RED**

Run the three Deno test files listed for this task.

- [ ] **Step 3: Implement shared TypeScript identity and approval payload**

Add a generated/shared key helper; populate domain/schema/scope/provenance; change approval SQL/RPC contract to preserve differently identified rows and allocate replicate transactionally.

- [ ] **Step 4: Run Deno tests and confirm GREEN**

Run the three Deno test files listed for this task.

---

### Task 6: Sync compatibility, documentation, phase verification, review, and commit

**Files:**
- Modify: `lib/services/supabase/startup_sync_service.dart`
- Modify: `test/services/supabase/startup_sync_service_test.dart`
- Modify: `test/services/supabase/startup_sync_incoming_test.dart`
- Modify: `docs/LIVING_SPEC.md`
- Modify: `docs/CHANGELOG.md`

- [ ] **Step 1: Write failing sync mapping tests**

Assert every V2 camelCase field maps to its snake_case cloud column in both push and pull, older rows missing V2 columns still pull, and dirty conflict handling retains a newer local identity/provenance edit.

- [ ] **Step 2: Run sync tests and confirm RED**

Run: `flutter test test/services/supabase/startup_sync_service_test.dart test/services/supabase/startup_sync_incoming_test.dart`

- [ ] **Step 3: Implement sync mappings and compatibility defaults**

Extend explicit snake-case metadata, normalize nullable old-client rows through repository identity preparation, and retain dirty cutoffs/conflict behavior.

- [ ] **Step 4: Update living documentation and changelog**

Document current V2 identity/provenance behavior, migration/backfill semantics, agent parity, and retained legacy combined rows. Prepend a `2026-08-24` changelog entry.

- [ ] **Step 5: Run Phase 2 verification**

Run all task tests, `dart run tool/agent_schema/generate_station_registry.dart --check`, `bash scripts/test_supabase_security_hardening.sh`, `flutter analyze`, and the affected full audit/dashboard suite. Run `flutter test` last and separate pre-existing unrelated failures from regressions.

- [ ] **Step 6: Request independent high-effort Phase 2 review**

Review the Phase 2 diff from `8b80c8b` for data integrity, migration safety, concurrency, offline sync, backward compatibility, agent parity, and test adequacy. Fix Critical/Important findings with failing regression tests and rerun verification.

- [ ] **Step 7: Commit Phase 2**

After a fresh HEAD/status check confirms no interleaved external changes:

```bash
git add <Phase-2 files only>
git commit -m "feat(chicks): add quality v2 sample identity"
```
