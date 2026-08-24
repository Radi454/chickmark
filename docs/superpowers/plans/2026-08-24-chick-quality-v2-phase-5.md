# Chick Quality V2 Phase 5 Cleanup Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove whether any Chick V2 compatibility storage can be removed and retain every legacy structure unless all four approved safety gates pass.

**Architecture:** A small Dart audit engine derives the compatibility-field vocabulary from `station_registry.json`, inventories conservative token mentions and heuristically detected registry-driven persistence consumers in production Dart/TypeScript, and combines that result with an explicit repository evidence manifest for reader-inventory completeness, replacement coverage, mixed-client release, and migration safety. A generated Markdown report records the evidence and the removal decision; it is checked for drift in tests and CI-style verification. The current Phase 4 fallback contract means the expected safe decision is to remove nothing.

**Tech Stack:** Dart, JSON, Flutter tests, Markdown, Git, existing Flutter/Deno/PostgreSQL verification harnesses.

**Spec:** `docs/superpowers/specs/2026-08-24-chick-quality-v2-phases-2-5-design.md`

## Global Constraints

- No push and no live Supabase changes; SQL remains migration files only.
- Preserve every existing row and backward-compatible reader/writer.
- Never silently merge or delete samples.
- `tool/agent_schema/station_registry.json` remains the only Chick metadata and validation authority.
- Raw observations are the source of truth only where Phase 4 created a valid normalized set; untouched or malformed legacy rows retain cache fallback.
- Remove a compatibility field only if zero runtime readers/writers, complete persisted replacement coverage, release from mixed-client compatibility, and lossless local/cloud migration are all proven.
- Update `docs/LIVING_SPEC.md` and add a newest-first dated `docs/CHANGELOG.md` entry in the same commit.

---

### Task 1: Test the four-gate cleanup decision

**Files:**
- Create: `test/tool/chick_quality_v2_legacy_cleanup_audit_test.dart`
- Create: `tool/chick_quality_v2/legacy_cleanup_audit.dart`

**Interfaces:**
- Consumes: a repository root, canonical registry JSON, and cleanup-evidence JSON.
- Produces: `LegacyCleanupAuditResult auditLegacyCleanup(...)` with registry-derived compatibility fields, conservative token mentions, registry-driven consumers, four gate results, `removalEligible`, and deterministic Markdown rendering.

- [ ] **Step 1: Write the failing engine tests**

Create temporary miniature repositories with a canonical registry containing an observation-backed `weightsJson` field. Prove these behaviors with hand-derived expectations:

```dart
test('runtime compatibility reader blocks cleanup', () async {
  final result = await auditFixture(
    runtimeSource: "final weights = row['weightsJson'];",
    replacementProven: true,
    compatibilityReleased: true,
    migrationSafe: true,
  );
  expect(result.zeroRuntimeReferences, isFalse);
  expect(result.removalEligible, isFalse);
  expect(result.references.single.token, 'weightsJson');
});

test('all four independent proofs permit cleanup', () async {
  final result = await auditFixture(
    runtimeSource: 'final normalized = observations;',
    replacementProven: true,
    compatibilityReleased: true,
    migrationSafe: true,
  );
  expect(result.zeroRuntimeReferences, isTrue);
  expect(result.removalEligible, isTrue);
});
```

Also prove that tests, documentation, and the two exact generated registry definition artifacts do not masquerade as direct token readers; other generated runtime code remains in scope, dynamic registry consumers independently block cleanup, and an unproven non-code gate blocks removal even with no source evidence.

- [ ] **Step 2: Run the test and confirm RED**

Run: `flutter test --no-pub test/tool/chick_quality_v2_legacy_cleanup_audit_test.dart`

Expected: compile failure because `tool/chick_quality_v2/legacy_cleanup_audit.dart` does not exist.

- [ ] **Step 3: Implement the minimal audit engine**

Implement immutable result/evidence/reference value types and:

```dart
Future<LegacyCleanupAuditResult> auditLegacyCleanup({
  required Directory repositoryRoot,
  required File registryFile,
  required File evidenceFile,
});
```

Derive tokens only from registry station fields that carry an `observation` descriptor: `fieldKey`, `persistence.localColumn`, and `persistence.remoteColumn`, plus the compatibility domain `chicks.legacy_combined`. Scan production `.dart` and `.ts` under `lib/` and `supabase/functions/`; exclude `*_test.*`, generated registry artifacts, and the audit tool itself. Return sorted path/line/token references. Parse three explicit evidence gates from JSON and compute `removalEligible` as the conjunction of all four gates.

- [ ] **Step 4: Run tests and confirm GREEN**

Run: `flutter test --no-pub test/tool/chick_quality_v2_legacy_cleanup_audit_test.dart`

Expected: all audit-engine tests pass.

---

### Task 2: Add the repository evidence and drift-checked report

**Files:**
- Create: `tool/chick_quality_v2/legacy_cleanup_evidence.json`
- Create: `tool/chick_quality_v2/audit_legacy_cleanup.dart`
- Create: `docs/reviews/2026-08-24-chick-quality-v2-phase-5-cleanup-audit.md`
- Modify: `test/tool/chick_quality_v2_legacy_cleanup_audit_test.dart`

**Interfaces:**
- Consumes: the Task 1 engine and the real canonical registry/evidence files.
- Produces: a CLI with `--check` and `--write` modes and a deterministic committed report.

- [ ] **Step 1: Write a failing CLI/report drift test**

Add a process-level test that runs the real CLI in `--check` mode and expects exit code zero. Before the report exists, confirm it fails with a missing/stale report message.

- [ ] **Step 2: Record conservative repository evidence**

Create evidence JSON with the reader-inventory subproof and all three non-code
gates false, each with a concrete reason:

```json
{
  "runtimeReaderInventoryComplete": {
    "proven": false,
    "reason": "Lexical and heuristic scans are not a complete call graph; indirect or aliased readers require an explicit reviewed inventory."
  },
  "persistedReplacementCoverage": {
    "proven": false,
    "reason": "Phase 4 intentionally leaves untouched and malformed legacy rows without normalized children."
  },
  "backwardCompatibilityReleased": {
    "proven": false,
    "reason": "Current clients dual-write compatibility caches and observation-first reads still fall back to them."
  },
  "losslessMigrationReady": {
    "proven": false,
    "reason": "No local/cloud proof shows every retained cache is redundant; no live Supabase migration is authorized."
  }
}
```

- [ ] **Step 3: Implement and run the report CLI**

The CLI must print/write deterministic Markdown listing registry-derived compatibility tokens, conservative token mentions grouped by path, registry-driven persistence consumers, each gate with its reason, and the final decision `RETAIN — no compatibility structures removed`. `--check` compares bytes and exits nonzero on drift; `--write` updates only the report path.

Run: `dart run tool/chick_quality_v2/audit_legacy_cleanup.dart --write`

- [ ] **Step 4: Confirm the CLI/report test is GREEN**

Run: `flutter test --no-pub test/tool/chick_quality_v2_legacy_cleanup_audit_test.dart`

Expected: all engine and real-report checks pass.

---

### Task 3: Document, verify, review, and commit Phase 5

**Files:**
- Modify: `docs/LIVING_SPEC.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/superpowers/plans/2026-08-24-chick-quality-v2-phase-5.md` only to mark completed checkboxes if useful.

**Interfaces:**
- Consumes: the committed audit report and verification output.
- Produces: current behavior documentation and one independently revertible Phase 5 commit.

- [ ] **Step 1: Update current docs**

State that Phase 5 found active compatibility readers plus unproven replacement, mixed-client, and migration gates, so no Chick parent column/table, `chicks.legacy_combined`, raw JSON/wide cache, hierarchy field, or fallback was removed. Add the dated changelog entry at the top.

- [ ] **Step 2: Run focused verification**

```bash
dart run tool/chick_quality_v2/audit_legacy_cleanup.dart --check
dart run tool/agent_schema/generate_station_registry.dart --check
flutter test --no-pub test/tool/chick_quality_v2_legacy_cleanup_audit_test.dart
flutter test --no-pub test/data/agent/chick_observation_codec_test.dart test/data/repositories/chick_observation_persistence_test.dart test/features/audits/full_audit_panel_smoke_test.dart
bash scripts/test_supabase_security_hardening.sh
```

- [ ] **Step 3: Run broad verification**

Run `flutter analyze`, the complete Telegram Deno suite, and the full Flutter suite. Compare analyzer/full-suite output to the three known informational lints and three unrelated audit-session navigation failures; do not alter those tests.

- [ ] **Step 4: Obtain independent review**

Request a reviewer to inspect the audit token derivation, scan exclusions, gate logic, report determinism, evidence accuracy, and the no-removal conclusion. Fix all Critical/Important findings test-first and re-run verification.

- [ ] **Step 5: Commit Phase 5**

Exclude the user-owned untracked `CODEX_HANDOFF_CHICK_PHASE1.md`, recheck HEAD/status/diff, then commit:

```bash
git commit -m "chore(chicks): audit v2 legacy cleanup safety"
```
