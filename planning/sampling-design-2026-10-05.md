# ChickMark Sampling — agreed design, 2026-10-05

Status: User authorized planning, GPT-6-luna implementation, parent review, descriptive commits, GitHub push, and GitHub Pages deployment. No further design approval is required by the user. This document supersedes contradictory earlier voice notes and the old project's working draft.

## Purpose and boundaries

One reusable sampling flow per panel and audit session, integrated into current panel-table persistence. Preserve measurement forms, station-specific calculations, shared Egg Storage, independent Chick Quality and Chick Weights, and existing optimizer incubation-age controls. Do not restore abandoned Sampling Plan commits or obsolete station-sample database tables. Preserve unrelated working-tree changes.

## Identity and hierarchy

Physical order: House → Setter → Hatcher → Trolley → Tray. Show only the panel's permitted scopes. Each actual terminal sample has an immutable ID, panel/session ownership, and independent measurements. A hierarchy parent organizes its descendant samples; it does not create a measurement row by itself. Each saved leaf row carries the full applicable scope path. A comparison scope has a registered/user-entered identity; an unscoped level is Pooled. Keep the application's established null representation for Pooled if needed for compatibility; display Pooled explicitly. Do not write a fake registry ID named Pooled.

Where Tray applies, each Tray represents an actual sample and requires a number/code. It cannot itself be pooled. Two parents may both contain Tray 1; these are distinct samples. Panels that do not use Tray retain their actual terminal sample type and do not gain fictitious trays.

| Panel | Permitted scopes |
| --- | --- |
| Egg Storage | Pooled only |
| Egg Quality | House |
| Chick Quality | Setter + Hatcher together, one sample per pair per session/panel |
| Chick Weights | House, independent from Chick Quality |
| Fresh Egg Breakout | House |
| Candled Egg Breakout | House, Setter, Trolley, Tray |
| Residue/day-21 Breakout | House, Setter, Hatcher, Trolley, Tray |
| Setter Optimizing | Setter, Trolley, Tray; preserve incubation-age behavior |
| Hatcher Optimizing | Hatcher, Trolley, Tray |

## Default and comparison items

An applicable ancestor scope defaults to Pooled. Adding its first comparison item collects a valid identity, creates its tab, and makes that level's Pooled tab inactive. Adding more items creates siblings under the active parent. One remaining comparison item is still comparison. Edit identity without changing sample IDs or measurements. Cancelling add/edit changes nothing. Repeated identity is rejected within the same parent, while repeated visible numbers under different parents are allowed.

There is no button converting an existing comparison branch to Pooled. The user deletes comparison items one by one; each deletion removes the selected subtree and its associated data. Once the last comparison item at that level is deleted, the default Pooled state becomes active automatically. Deleted measurement data must not be relabelled as Pooled, merged, averaged, or retained on a new default sample.

The complete Pooled starting state exposes one sample. For Tray-based panels this is one identified Tray with applicable ancestors Pooled. For panels without Tray it is one panel-native sample. The old requirement that Pooled has one sample must not be interpreted as collapsing all descendants merely because an intermediate scope is unscoped.

## Deletion and synchronization

Confirmation identifies the chosen branch and affected descendants/measurement data/photos/notes. Cancellation changes nothing. Confirmed deletion affects only that branch in the current panel/session; other panels and siblings remain intact. Deleting the last comparison branch creates an empty default state, retaining only genuinely shared session/panel-independent context such as Egg Storage.

Delete database children and parent rows atomically where possible and queue sync tombstones in the same transaction. Delete local photo files after commit; reuse existing remote photo storage cleanup and retry paths. Tombstones/pending cleanup records remain until synchronization succeeds: these are required operational bookkeeping, not orphan sample data. Avoid deleting a shared photo backing file referenced by another surviving record. Offline saves and remote pull must not resurrect a deleted branch. Preserve pull-only customer behavior.

## UI

A common scope card renders configured levels and tabs. Pooled is visibly inactive while comparison items exist. Add collects identity before creating state. Active parent determines the child tabs shown. Selecting the terminal sample loads its measurements and shows its identity path above the measurement form. Edit changes identity; remove shows the explicit subtree confirmation. Only one control owns any sampling decision; retain distinct non-sampling controls such as incubation age. All new messages use the existing English/Arabic localization map and read-only/loading guards.

## Human-readable codes

Retain the original agreed code design: three user-entered letters each for customer, hatchery, and farm/current flock; maintained breed abbreviation; selected scope segments in physical order; immutable/non-reused serial SA number within panel/session. Example ORG-HAT-FRM-RS-H1-S2-HT3-TR2-T1-SA1. Pooled levels contribute no segment. Editing identities or reference codes preserves sample IDs and entered measurements. Existing records with missing reference codes remain readable and editable; do not invent trusted reference codes or block unrelated legacy reads. The implementation plan must specify code onboarding and migration explicitly.

## Conservative implementation rulings to verify

- Adding the first comparison item while the default sample has measurements uses an explicit reset confirmation, consistent with the earlier user-authorized Pooled → Comparison warning/deletion. Cancellation preserves data. Do not silently copy pooled measurements into a named comparison identity.
- Existing legacy identities and measurements are preserved on migration. Unclear historical scope identities are displayed as legacy/unknown rather than guessed or discarded.
- Read-only tabs cannot mutate data. Failed deletion/save must leave recoverable state and retries; UI success follows successful persistence.
- Global audit-history and flock-age correction are separate work and are excluded.

## Required verification

Distinct measurements on samples A and B survive switching, save/reopen, and offline sync. Last comparison deletion resets empty Pooled; one remaining item does not. Nested subtree deletion preserves siblings and other panels. Cancellation is inert. Same Tray number under distinct parents stays independent. Selected/pooled ancestor combinations round-trip. Photo and measurement tombstones accompany parent removal, including remote storage retry and pull-only behavior. Existing audits migrate without identity changes or lost measurements. Dashboard returns current sample identities. Build web and verify deployed Pages version after push.

## Review evidence so far

Current baseline main 0cd345b, SQLite v81. PanelSampleRepository and AuditPanelSaveCoordinator persist real panel rows; StationSampleRepository is a no-op compatibility stub. PhotoRepository.deleteByPanelRow is defined but has no call site in lib. SupabaseService.deleteRows('photos', ...) already removes remote storage objects. Generic AuditProvider.removeActiveSample blocks the last item and converts some one-item survivors to Pooled; specialized last-item paths may retain removed measurements. These must be corrected.

Baseline command: flutter test --no-pub test/features/audits/audit_provider_sample_mode_test.dart test/data/repositories/panel_sample_repository_test.dart test/data/repositories/photo_repository_test.dart test/data/repositories/sync_tombstone_repository_test.dart — 53 tests passed.
