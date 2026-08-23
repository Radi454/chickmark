# Historical Codex Handoff — Egg Quality Sampling + Egg Grading

This document records the handoff context for the completed A1–A7/B1–B7
implementation. It is not an instruction to repeat those tasks. Use the
current workspace/repository rather than a machine-specific absolute path.

---

This was the takeover context for the ChickMark Flutter + Supabase
hatchery-audit app on branch `main`.

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

**Phase B (v62 egg grading) — COMPLETE.** B1–B7 landed, were reviewed, and the
consolidated final-fix wave closed the merge-blocking local findings.

- B1 — cloud grading schema, applied live to Supabase.
- B2 — Dart defect catalogue (18 codes), local tables `egg_defect_types` and
  `egg_quality_defect_counts`, 8 `grading*` columns on `egg_quality`, schema
  version 62.
- B3 — `EggGradingRepository` (`lib/data/repositories/egg_grading_repository.dart`).
- B4 — grading is wired into drafts, persistence, and production reopen.
- B5 — grading UI, validation display, localization, top-defect summary, and
  per-house state are implemented.
- B6 — grading child sync and child-before-parent tombstone deletion are
  implemented.
- B7 — full-station regression coverage is implemented.

**Remaining external gate only:** Supabase migration history must be reconciled
and verified with explicit human approval. The grading SQL file is local version
`20260823100000` but was recorded remotely as `20260823052253`; the same audit
must cover v61 local version `20260823090000`. Do not run migration repair,
`db push`, DDL, or another cloud mutation from this historical handoff.

## How to work

The following was the execution discipline used for the now-complete tasks:

1. Read that task's section of the plan file in full. Its code and values are to
   be used verbatim unless you find a genuine defect in them (see below).
2. Write the failing test first. Run it. Confirm it fails for the stated reason.
3. Write the minimal implementation. Run the test green.
4. Run `flutter analyze` — it must be clean.
5. Commit, updating `docs/LIVING_SPEC.md` and `docs/CHANGELOG.md` **in the same
   commit** (this is a hard project rule from `CLAUDE.md`). Changelog entries are
   `- YYYY-MM-DD:`, newest at top; never rewrite an existing entry.
6. Append a `Task <N>: complete (commits <base>..<head>)` line to the ledger.

Do not restart B5–B7 from this document. Consult the current code, living spec,
changelog, final-review findings, and final-fix report for present state.

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

## Findings resolved after this handoff

- B6 registered `egg_quality_defect_counts` in sync push/pull and tombstone
  delete order, after its parent on push and before its parent on delete.
- Count row IDs remain deterministic (`'$eggQualityId:$defectCode'`). A local
  re-add cancels a pending tombstone, and a newer row survives an already-synced
  older tombstone.
- B5 did not wire the dead generic sample-mode control. Egg Quality additions
  continue through the identity prompt and duplicate-house validation.

**A known non-bug, do not "fix" it:** removing a house from the middle of a
comparison deliberately does **not** renumber the rest — `H3` stays `H3`. That is
the intended design (spec lines 200-203); two pre-existing tests that encoded the
old renumbering were correctly updated.

**Another known non-bug:** the existing dashboard join between `egg_storage` and
`egg_quality` matches on hierarchy equality, so a pooled storage row never joins a
per-house quality row. Pre-existing, deliberately out of scope, not a drive-by.

## Final-review state

The local final-review findings were triaged and fixed: mixed null-index order
is consistent, drafts/samples bind by persisted ID, production reopen overlays
child counts, invalid grading cannot persist or exit, unknown codes survive,
and Egg Quality deletes are centralized child-first. The migration-version
drift described above remains an external approval gate; a future `db push`
must not proceed until history is reconciled and the live schema/policies/
triggers are verified.

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

## Completion record

The whole-branch review and consolidated local fix wave are complete. See the
final-fix report in the matching `.superpowers/sdd/` directory for numbered
finding dispositions, verification output, and the exact residual cloud gate.
