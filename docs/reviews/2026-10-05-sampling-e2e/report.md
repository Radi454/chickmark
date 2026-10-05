# Sampling UI and end-to-end audit — 2026-10-05

Task: sampling-ui-e2e-20261005. Current status: reviewed fixes prepared for publication; live destructive/reopen checks require user input. Human acceptance remains pending.

Scope: current published ChickMark sampling controls and live form flows; offline SQLite save/reopen and sync regressions. Browser evidence was captured in this run.

## Flow results

1. Existing sampling card — failed visual review. White scope labels disappear on white cards; selected chip text/icons have poor contrast; unlabeled + controls are ambiguous. See 01-sampling-before.jpg.
2. Independent QA visit setup — passed. Created Sampling QA 2026-10-05 hatchery and flock under Dashboard Test Customer; kept original visit intact.
3. House selector — failed empty-state review. No registered houses yields an empty disabled selector without guidance. See 03-house-empty.jpg.
4. Chick Quality pair — passed creation/selection and independent Chick Weights state. Duplicate pair is rejected but reports a generic save error. See 04-duplicate-error.jpg.
5. Measured Pooled reset — passed warning and cancellation. 99.5°F retained after cancellation. See 05-reset-warning.jpg.
6. Setter Tray switching — failed rendered field ownership. Active sample changes but controllers still display the outgoing reading. Provider/storage tests alone did not catch this. See 08-tray-switch-stale-field.jpg. Correction uses active sample identity for hydration.
7. Branch deletion — passed preview and cancellation; permanent deletion awaits specific approval. Dialog reports one affected measurement and no photos/notes. See 09-delete-confirmation.jpg.
8. Hatcher ancestor creation — failed selection/continuation. A new branch without a terminal leaf cannot become active; clicking it does nothing. See 10-hatcher-branch-no-selection.jpg. Correction creates/selects an identified default Tray below a new ancestor.
9. Fresh/Candled breakout switching — passed independent count restoration (Fresh 2/30; Candled 3/150). See 11-breakout-independent.jpg.
10. Save — passed local saved indicator. Reload returned to Sign In; authenticated reopened-visit and cross-device verification await sign-in.

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

These screenshots establish visible behavior, not full accessibility compliance. Phone-width rendering, readable labels, duplicate feedback, and sample ownership are covered by targeted widget checks. Real multi-device cloud convergence, photo uploads/deletions, offline network switching, and permanent branch deletion have not been exercised through the live browser in this run.

The fixed local dev origin also reproduces its prior IndexedDB byte-buffer startup error before database initialization. No browser storage was erased or alternate origin used.

## Follow-up

The bounded UI/controller fixes and focused regressions have been reviewed. Publish the verified release under standing commit/push/Pages authorization. Resume authenticated live checks after sign-in and perform destructive checks only after QA-record deletion approval. QA fixture data remains until approved cleanup.

## Captured live evidence

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

General health: visible usability and sample-ownership defects were found and corrected. Final acceptance remains pending authenticated reopen, permanent deletion approval, photo/cloud convergence checks, and human review.

Files changed: sampling controls/provider; Setter, Hatcher, Egg and Chick screens; Arabic localization; six focused widget/provider test files; living spec, changelog and this evidence folder. No schema or remote-service change.
