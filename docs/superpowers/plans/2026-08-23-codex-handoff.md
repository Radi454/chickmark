# Codex Handoff — Egg Quality Sampling + Egg Grading

Paste everything below the line into Codex as the opening prompt.

---

You are taking over a partially-executed implementation plan in the ChickMark
Flutter + Supabase hatchery-audit app. Repo root: `/Users/ibrahimradi/Claude/ChickMark`,
branch `main`. Work through it task by task; do not start until you have read the
three documents named below.

## Read these first, in this order

1. `docs/superpowers/specs/2026-08-23-egg-quality-sampling-and-grading-design.md`
   — the approved design. Explains the six root causes of the Egg Quality
   comparison-row instability and the grading data model.
2. `docs/superpowers/plans/2026-08-23-egg-quality-sampling-and-grading.md`
   — the 14-task implementation plan (A1–A7, B1–B7). Each task has real test
   code, real implementation code, exact file paths, and its own commit step.
   **Read the `## Global Constraints` section at the top and treat it as
   binding on every task.**
3. `.superpowers/sdd/2026-08-23-egg-quality-sampling-and-grading/progress.md`
   — the execution ledger. It records every completed task with its commit
   range, every fix round, and every deferred minor finding. **This is the
   source of truth for what is done.** Trust it and `git log` over anything
   else.

Per-task briefs and implementer reports for the completed tasks are in the same
`.superpowers/sdd/2026-08-23-egg-quality-sampling-and-grading/` directory
(`task-<N>-brief.md`, `task-<N>-report.md`). That directory is git-ignored
scratch; the git history is the real record.

## State when this was handed over

**Phase A (v61 sampling stability) — COMPLETE.** Tasks A1–A7 are merged and
reviewed clean. Egg Quality samples now persist and reopen with stable identity
(mode, scope, label, index) and stable row ids; the provider no longer
string-sniffs house identity; the Sample Mode UI ships with a Compare→Pooled
confirmation dialog and inline duplicate-house validation.

**Phase B (v62 egg grading) — B1, B2, B3 complete and reviewed clean; B4 in its
first fix round.**

- B1 — cloud grading schema, applied live to Supabase.
- B2 — Dart defect catalogue (18 codes), local tables `egg_defect_types` and
  `egg_quality_defect_counts`, 8 `grading*` columns on `egg_quality`, schema
  version 62.
- B3 — `EggGradingRepository` (`lib/data/repositories/egg_grading_repository.dart`).
- B4 — grading wired into the draft, the save path, and reopen. Its review
  raised one Critical and one Important finding; a fix round was dispatched.
  **Check the ledger's last B4 lines and `git log` to see whether the fix
  landed and whether it was re-reviewed.** If the ledger has no
  `Task B4: complete` line, B4 is unfinished — finish it before starting B5.

**Remaining: B5 (grading UI), B6 (sync the grading child table), B7 (full-station
regression pass), then a whole-branch final review.**

## How to work

For each remaining task, in order:

1. Read that task's section of the plan file in full. Its code and values are to
   be used verbatim unless you find a genuine defect in them (see below).
2. Write the failing test first. Run it. Confirm it fails for the stated reason.
3. Write the minimal implementation. Run the test green.
4. Run `flutter analyze` — it must be clean.
5. Commit, updating `docs/LIVING_SPEC.md` and `docs/CHANGELOG.md` **in the same
   commit** (this is a hard project rule from `CLAUDE.md`). Changelog entries are
   `- YYYY-MM-DD:`, newest at top; never rewrite an existing entry.
6. Append a `Task <N>: complete (commits <base>..<head>)` line to the ledger.

## Hard rules — these are not negotiable

- **ONE EGG MAY CARRY SEVERAL DEFECTS.** The rejected count is entered by the
  auditor; acceptable = inspected − rejected. There is deliberately **NO**
  `SUM(defects) <= sampleSize` rule. Do not add one in SQL, in Dart validation,
  in the draft layer, or in the UI.
- **Cloud migration before client code.** A local column with no matching cloud
  column makes PostgREST reject the **entire batch** for that table. Apply the
  Supabase migration first, verify it, then ship the code that writes the column.
- **SQLite `ON DELETE CASCADE` does NOT queue sync tombstones.** Child-row
  deletes must go through the repository, which calls
  `SyncTombstoneRepository.queueDeletesWithExecutor`.
- **Egg Storage stays pool-only** and its Sample Mode bar is read-only. Do not
  change `egg_storage` measurement logic. Do not enable tray, trolley, or
  machine comparison scopes for the egg station.
- Local SQLite is camelCase; the Supabase mirror is snake_case; the conversion
  is automatic via `toSupabaseUpsertPayload` / `_supabaseSnakeCase`. **Never
  hand-write a mapper.**
- Every new column is nullable. No `NOT NULL` without a default, no backfill, no
  destructive migration, no table rebuild.
- A new non-panel table must be registered in **both**
  `DatabaseHelper._criticalTables` and `DatabaseHelper._criticalColumns`, or it
  can silently fail to exist after a repair pass.

## Traps this plan has already fallen into — do not repeat them

These are not hypothetical. Every one of them was caught by review after an
implementer reported the task as done.

1. **A test that still passes when you revert your implementation is worthless.**
   Before every commit: revert your implementation in the working tree, run your
   new tests, confirm each goes RED *for the right reason*, restore the tree
   exactly, confirm green. If a test cannot be made to go red, say so explicitly
   and explain what it guards instead. Four separate tasks in this plan shipped
   a test that passed with the fix removed.
2. **A test that asserts over an empty collection asserts nothing.** Confirm
   every collection your assertions loop over is non-empty. One task's entire
   `egg_storage` assertion block iterated over an empty list.
3. **Never write a verification claim you did not perform.** Three reports in
   this plan asserted a check that was never run, and all three were wrong —
   including one that claimed new RLS policies matched their siblings when a
   single `pg_policies` query disproved it.
4. **Check that the plan's own test data discriminates.** Twice the plan chose
   values where the old and new behaviour coincided, so the test passed either
   way. If the data doesn't discriminate, change it and say that you did.
5. **`pumpAndSettle()` hangs under `FakeAsync` with a real database.** In
   `testWidgets` tests use bounded `pump(Duration(...))` and prefer injected
   fakes over standing up real sqflite.
6. **Two sample-mode vocabularies.** `StationSampleModel` uses
   `pooled` / `comparison`; `AuditModel.sampleMode` (via `SampleMode`) uses
   `pool` / `compare`. The persisted `sampleMode` column carries the **first**.
   Convert deliberately at every boundary.

## Carry-forward findings that land on the remaining tasks

**B6 has a hard prerequisite, logged during the B3 review:**
`SyncTombstoneRepository.deleteOrder` does not list `egg_quality_defect_counts`
(it is not a `PanelSampleSchema` table). `_pushPendingDeletes`
(`lib/services/supabase/startup_sync_service.dart:656-674`) only issues
`deleteRows` and `markSynced` for tables in `deleteOrder`, so queued tombstones
for this table upload to `sync_tombstones` but the **cloud row is never deleted
and the tombstone is never marked synced** — it re-uploads forever. B6 must
extend `deleteOrder` **and** drain the tombstones that have already accumulated.

**Also for B6:** the cloud table carries `unique (egg_quality_id, defect_code)`
while the sync upserts on `id`. If a local row is ever regenerated with a fresh
`id` for the same pair, the upsert violates that constraint and PostgREST
rejects the whole batch. B3 makes count-row ids deterministic
(`'$eggQualityId:$defectCode'`) and never re-mints them — keep it that way.

**For B5:** `lib/features/audits/widgets/sample_mode_controls.dart` is still dead
code in `lib` and still calls bare `addSample()`. `audit_provider.dart`
`_houseNoForDraft` is positional, so via that path
`[H1,H2,H3]` → remove middle → add yields a **duplicate H3**. It is unreachable
today only because no screen wires that widget. If B5 wires it, route the add
through the identity prompt / duplicate check instead.

**A known non-bug, do not "fix" it:** removing a house from the middle of a
comparison deliberately does **not** renumber the rest — `H3` stays `H3`. That is
the intended design (spec lines 200-203); two pre-existing tests that encoded the
old renumbering were correctly updated.

**Another known non-bug:** the existing dashboard join between `egg_storage` and
`egg_quality` matches on hierarchy equality, so a pooled storage row never joins a
per-house quality row. Pre-existing, deliberately out of scope, not a drive-by.

## Deferred minor findings

The ledger carries roughly twenty `minor (deferred)` lines from the completed
tasks — small correctness and test-hygiene items that reviewers judged
non-blocking. **The final whole-branch review should triage that list and decide
which must be fixed before merge.** Do not silently discard them. Two worth
knowing early:

- `egg_station_reconstruction.dart:219-221` sorts NULL `sampleIndex` **last**
  while the SQL `ORDER BY` sorts NULLs **first**. A session mixing pre-v61 and
  v61 `egg_quality` rows would desync `stationAudits` from `stationSamples` —
  reintroducing the exact misalignment this plan exists to fix.
- Applied Supabase migration versions drift from their filenames (an artifact of
  applying via MCP). A future `supabase db push` would treat the files as
  unapplied and replay them; `create policy` and `create trigger` are not
  `IF NOT EXISTS`, so the replay errors mid-file.

## Working-tree note

Several files belong to a **different concurrent effort** and must never be
staged, modified, or reverted:

- `supabase/migrations/20260823120000_chick_panel_identity_uniqueness.sql`
- `test/data/agent/chick_registry_schema_parity_test.dart`
- `test/data/database/chick_panel_cloud_parity_test.dart`
- `test/features/audits/logic/chick_quality_round_trip_test.dart`
- `scripts/test_supabase_security_hardening.sh`

Always `git add` only the files you actually changed — never `git add -A`.

There are also three known-failing tests in `test/features/audits/`
(footer overflow in `egg_storage_screen.dart`) that were verified as
pre-existing before this plan's Phase B work. They are not yours to fix unless
B7 scopes them in.

## When all tasks are done

Run a whole-branch review against the merge base, triage the deferred-minor list
from the ledger, fix what blocks merge, and report what you left open and why.
