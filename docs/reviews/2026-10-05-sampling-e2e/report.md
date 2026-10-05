# Sampling UI and end-to-end audit — 2026-10-05

Task: sampling-ui-e2e-20261005. Current status: authenticated local switching,
identity-edit, approved tray deletion, and save/reopen checks passed on
ab19495. Additional registered-machine dropdown implementation is in progress;
Supabase access is restored and the catalog and tombstone-scope migrations are applied; live catalog and cloud checks remain pending. Human acceptance remains pending.

Scope: current published ChickMark sampling controls and live form flows; offline SQLite save/reopen and sync regressions. Browser evidence was captured in this run.

## Authenticated continuation

On the published ab19495 build, a new named QA fixture was registered under
Dashboard Test Customer. Registered House selection, paired Setter/Hatcher
creation, duplicate rejection, and independent Egg Storage/Quality values and
notes passed. Setter Tray 1 retained 99.5°F while a second tray retained
100.2°F after switching. Renaming the second tray preserved SA2 and its reading,
although the UI selected Tray 1 after the edit. The approved permanent deletion
of that second QA tray reported one measurement and removed only that tray;
Tray 1 and its 99.5°F reading survived.
New Hatcher and nested Trolley branches each created and selected a usable
default Tray 1. The QA visit saved as incomplete, reopened from Audits through
Resume visit, and restored Tray 1's 99.5°F reading. Its visit card still reports
Sync: Failed while the list header reports Synced just now.

A focused combined regression run passed 52 tests for customer reference
lookup refresh, startup dirty-row protection, and actual SQLite adapter
save/reopen, identity edits, photo ownership, and subtree deletion. These tests
do not establish production cloud convergence. The Supabase management connector is authenticated again. The registered catalog migration and sampling/catalog tombstone-scope migration were applied, and the transactional tombstone test passed with rollback. The earlier QA fixture's absence
after sign-in remains unexplained; no browser storage was erased.

The user subsequently requested hatchery-registered machine dropdowns and
numbered trolley/tray dropdowns based on counts calculated during machine
registration. That addition is in progress and is not yet published.

## Flow results

1. Existing sampling card — failed visual review. White scope labels disappear on white cards; selected chip text/icons have poor contrast; unlabeled + controls are ambiguous. See 01-sampling-before.jpg.
2. Independent QA visit setup — passed. Created Sampling QA 2026-10-05 hatchery and flock under Dashboard Test Customer; kept original visit intact.
3. House selector — failed empty-state review. No registered houses yields an empty disabled selector without guidance. See 03-house-empty.jpg.
4. Chick Quality pair — passed creation/selection and independent Chick Weights state. Duplicate pair is rejected but reports a generic save error. See 04-duplicate-error.jpg.
5. Measured Pooled reset — passed warning and cancellation. 99.5°F retained after cancellation. See 05-reset-warning.jpg.
6. Setter Tray switching — failed rendered field ownership. Active sample changes but controllers still display the outgoing reading. Provider/storage tests alone did not catch this. See 08-tray-switch-stale-field.jpg. Correction uses active sample identity for hydration.
7. Branch deletion — passed preview and cancellation; the approved QA second-tray deletion subsequently passed (see continuation above). Dialog reports one affected measurement and no photos/notes. See 09-delete-confirmation.jpg.
8. Hatcher ancestor creation — failed selection/continuation. A new branch without a terminal leaf cannot become active; clicking it does nothing. See 10-hatcher-branch-no-selection.jpg. Correction creates/selects an identified default Tray below a new ancestor.
9. Fresh/Candled breakout switching — passed independent count restoration (Fresh 2/30; Candled 3/150). See 11-breakout-independent.jpg.
10. Save — passed local saved indicator. The authenticated session subsequently became available and the saved QA visit reopened. The visit reports Sync: Failed, while the global header says Synced just now; its flock lookup falls back to the UUID. After deployment 426858c, reload reproduced the same IndexedDB byte-buffer startup failure as the fixed local origin. Post-fix form checks and cloud convergence remain pending.

## Confirmed automated checks in this run

- 36 repository/adapter/save bridge/reopen tests passed.
- 47 startup push/pull and observation sync tests passed, including sampling ordering, pull-only devices, serial reconciliation failures, and tombstone resurrection guards.
- 65 Setter/Hatcher incubation, Egg, and Chick form widget tests passed (23 + 13 + 29).
- 37 Hatch breakout screen tests passed.
- Final sampling controls/House/provider run passed all 20 tests, including actual SQLite terminal identities and serial reservations.
- Localization tests passed in the combined widget run. That combined command also included a nonexistent test filename and exited with a loading error; the correct Hatch test path was then run separately and passed.
- `flutter analyze --no-pub` reports only two pre-existing `unawaited_return_in_try_block` warnings in the environment loader and photo service. No new diagnostics.
- Full app `flutter build web --release --base-href=/chickmark/ --dart-define-from-file=.env --no-pub` succeeded; standard secure-storage Wasm dry-run and font warnings remain.

## Evidence limits

These screenshots establish visible behavior, not full accessibility compliance. Phone-width rendering, readable labels, duplicate feedback, and sample ownership are covered by targeted widget checks. Real multi-device cloud convergence, photo uploads/deletions, offline network switching, and whole-visit cleanup remain pending through the live browser; approved single-tray deletion passed.

The fixed local dev origin also reproduces its prior IndexedDB byte-buffer startup error before database initialization. No browser storage was erased or alternate origin used.

## Follow-up

The bounded UI/controller fixes and focused regressions have been reviewed. Publish the verified release under standing commit/push/Pages authorization. Resume authenticated live checks after sign-in and perform destructive checks only after QA-record deletion approval. QA fixture data remains until approved cleanup.

## Captured live evidence

### Authenticated continuation: save/reopen

![Reopened Setter measurement](25-reopened-setter-measurement.png)

![Surviving tray after approved deletion](22-surviving-tray-after-delete.png)

![New nested Hatcher/Trolley terminal](24-trolley-default-leaf.png)

### 1. Original sampling controls

![1. Original sampling controls](01-sampling-before.jpg)

### 3. Empty House selector

![3. Empty House selector](03-house-empty.jpg)

### 4. Duplicate error

![4. Duplicate error](04-duplicate-error.jpg)

### 5. Reset protection

![5. Reset protection](05-reset-warning.jpg)

### 6. Stale field after switching Tray

![6. Stale field after switching Tray](08-tray-switch-stale-field.jpg)

### 7. Deletion preview

![7. Deletion preview](09-delete-confirmation.jpg)

### 8. Unselected new Hatcher branch

![8. Unselected new Hatcher branch](10-hatcher-branch-no-selection.jpg)

### 9. Restored independent Fresh count

![9. Restored independent Fresh count](11-breakout-independent.jpg)


## UI review after fixes

The real SamplingScopeControls and app theme were rendered in a temporary in-memory browser harness, without authentication or SQLite. Scope text and selected icons are readable, Add buttons have explicit labels, and the paired label fits the narrow layout. The 390px widget test separately checks layout without overflow. These captures validate rendered controls, not authenticated full-app E2E. The harness was removed and the browser viewport restored.

![Updated sampling controls in isolated UI harness](13-controls-after.png)

General health: visible usability and sample-ownership defects were found and corrected. Authenticated reopen and approved single-tray deletion passed. Final acceptance remains pending live catalog verification, photo/cloud convergence checks, QA cleanup, and human review.

Files changed: sampling controls/provider; Setter, Hatcher, Egg and Chick screens; Arabic localization; six focused widget/provider test files; living spec, changelog and this evidence folder. No schema or remote-service change.

## Additional reload and sync findings

Pages run 37355321075 succeeded for commit 426858c. Browser reload then failed inside sqlite3 IndexedDB `readFully` while constructing a Uint8Array; the app rendered blank. The deployed dependency lock uses sqlite3 3.2.0. Upstream sqlite3 3.3.3 documents a fix that ignores obsolete blocks beyond the file length, matching the traced call. See [upstream issue 380](https://github.com/simolus3/sqlite3.dart/issues/380). Browser storage was not cleared.

The global sync header records the last sync operation; it does not establish that each visit synced. The visit's failed pill aggregates session/station row status. Exact `syncError` is stored locally and not exposed by the current Audits UI, so missing cloud schema/RPC/RLS and parent-reference errors remain hypotheses. No production migration was executed.

![Blank page after IndexedDB startup exception](14-reload-startup-error.png)

## Startup compatibility repair verification

Pinned only sqlite3 from 3.2.0 to 3.3.3; no other package lock changes and no schema migration. The upstream Chrome trailing-block fixture passed in isolated test storage. A further 37 actual repository/provider tests passed after the dependency update, and the full release web build succeeded. The full local app now opens its previously failing IndexedDB database at the unchanged 127.0.0.1:57863 origin and displays existing visits with no error console entries; storage was preserved.

Read-only Supabase checks confirm the three sampling tables, reconcile_panel_sample_serials RPC, and both sampling migrations exist in the configured ChickMark project. Missing migration is therefore ruled out; the precise QA visit sync error remains unconfirmed.

## Published recovery handoff

Pages run 37356455285 succeeded for startup-fix commit ab19495. The live browser initially reused the old cached bundle; navigating to the fresh entry URL `https://radi454.github.io/chickmark/?v=ab19495#/main` reached the normal Sign In screen. The latest observed error entries predate that successful fresh-entry navigation. Authenticated after-fix forms still require sign-in.

Read-only cloud queries found neither the new QA hatchery nor flock, confirming cloud convergence has not passed. The QA records remain locally and permanent deletion/cleanup still awaits approval. This task is not accepted as complete.

![Live app recovered to Sign In](15-live-recovered-signin.png)

## Registered catalog validation continuation

A focused 127-test run passed, covering fresh and upgraded SQLite schema v83, catalog isolation and dirty tracking, fixed machine IDs, inline registration/capacity editing, four trolley choices, 32 tray choices, and legacy identities (`0`, `QA-T2`, and out-of-capacity `T40`). Real repository/adapter save and subtree-delete regressions and startup sync/security tests also passed. A failed reference batch retries rows individually so valid hatcheries can upload while invalid records remain failed. These automated results do not establish live multi-device convergence.

A subsequent 45-test startup-sync run passed after tombstone upload isolation: a rejected event remains failed and is never used for target deletion, while the accepted QA event proceeds and is acknowledged. Missing remote targets still require safe reconciliation; no security policies were weakened and rejected events were not silently acknowledged.

Release web build passed for the catalog update. Final startup-sync regression run passed all 45 tests, including the final negative acknowledgment assertions. Analyzer reports only the two existing environment-loader/photo-service warnings.

## Deployment handoff — a5024ea

Task: sampling-ui-e2e-20261005 / registered-machine-dropdowns. Commit a5024ea is pushed to main. The release build passed; 127 combined focused tests passed, followed by all 45 startup-sync tests after the deletion isolation change. The applied Supabase tombstone-scope migration passed its transactional SQL check with rollback. Two pre-existing analyzer warnings remain.

Pages run [37365108360](https://github.com/Radi454/chickmark/actions/runs/37365108360) is queued without an assigned runner. [GitHub Status](https://www.githubstatus.com/) reports an active Actions incident delaying hosted-runner assignment (2026-10-05 19:15 UTC update). The open live app therefore still runs ab19495. New catalog UI registration, real cloud convergence, photo upload/deletion, and approved whole-visit/flock/hatchery cleanup remain pending; QA records have been preserved. No claim of completed live E2E or human acceptance is made.

Files in the implementation commit:

- `AGENTS.md`
- `docs/CHANGELOG.md`
- `docs/LIVING_SPEC.md`
- `docs/plans/2026-10-05-machine-capacity-dropdowns.md`
- `docs/reviews/2026-10-05-sampling-e2e/18-tray-a-preserved.png`
- `docs/reviews/2026-10-05-sampling-e2e/19-tray-b-preserved.png`
- `docs/reviews/2026-10-05-sampling-e2e/20-renamed-tray-measurement.png`
- `docs/reviews/2026-10-05-sampling-e2e/21-qa-tray-delete-warning.png`
- `docs/reviews/2026-10-05-sampling-e2e/22-surviving-tray-after-delete.png`
- `docs/reviews/2026-10-05-sampling-e2e/23-hatcher-default-leaf.png`
- `docs/reviews/2026-10-05-sampling-e2e/24-trolley-default-leaf.png`
- `docs/reviews/2026-10-05-sampling-e2e/25-reopened-setter-measurement.png`
- `docs/reviews/2026-10-05-sampling-e2e/report.md`
- `lib/data/database/database_helper.dart`
- `lib/data/database/database_migrations.dart`
- `lib/data/database/database_schema.dart`
- `lib/data/models/hatchery_machine_model.dart`
- `lib/data/repositories/hatchery_machine_repository.dart`
- `lib/data/repositories/hatchery_repository.dart`
- `lib/data/repositories/panel_sampling_state_repository.dart`
- `lib/data/repositories/sync_tombstone_repository.dart`
- `lib/features/audits/widgets/sampling_scope_controls.dart`
- `lib/features/customers/widgets/hatchery_machine_editor.dart`
- `lib/features/customers/widgets/hatchery_management_sheet.dart`
- `lib/l10n/app_localizations.dart`
- `lib/providers/customers_provider.dart`
- `lib/services/supabase/startup_sync_service.dart`
- `lib/services/supabase/supabase_service.dart`
- `supabase/migrations/20261005190731_add_hatchery_machines_catalog.sql`
- `supabase/migrations/20261005193201_expand_sampling_tombstone_scope.sql`
- `supabase/tests/sampling_tombstone_scope_test.sql`
- `test/data/database/hatchery_machine_schema_test.dart`
- `test/data/database/panel_sampling_schema_test.dart`
- `test/data/database/schema_parity_test.dart`
- `test/data/repositories/hatchery_machine_repository_test.dart`
- `test/data/repositories/panel_sampling_state_repository_test.dart`
- `test/features/audits/sampling_adapter_round_trip_test.dart`
- `test/features/audits/widgets/sampling_scope_machine_controls_test.dart`
- `test/features/customers/customer_hierarchy_test.dart`
- `test/features/customers/hatchery_machine_editor_test.dart`
- `test/services/supabase/startup_sync_harness.dart`
- `test/services/supabase/startup_sync_incoming_test.dart`
- `test/services/supabase/startup_sync_service_test.dart`
- `test/services/supabase/supabase_service_security_test.dart`
