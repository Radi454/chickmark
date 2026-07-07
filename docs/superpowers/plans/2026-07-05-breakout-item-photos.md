# Breakout Item Photos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add saved, editable, metric-scoped photos beside every Fresh, Candled, and Residue breakout item while preserving the existing dashboard photo grid.

**Architecture:** Keep sample JSON migration-safe by prefixing flat photo-map keys with the metric key. Save SQLite photo rows with metric-specific `fieldKey` and `panelRowId` identities, remove stale rows on edit/delete, and make the dashboard aggregate new metric keys together with legacy breakout photo keys.

**Tech Stack:** Flutter/Dart, Provider, SQLite via sqflite, existing `MultiPhotoButton`, Flutter widget and repository tests.

---

### Task 1: Specify row-level metric photo behavior

**Files:**
- Modify: `test/features/audits/hatch_analysis_screen_breakout_test.dart`
- Modify: `lib/features/audits/screens/hatch_analysis_screen.dart`

- [ ] **Step 1: Write failing widget tests**

Add expectations that `freshCountFields.length`, `candledCountFields.length`,
and `residueCountFields.length` metric photo controls render after a sample is
added. Inspect each `MultiPhotoButton` and assert identities such as:

```dart
expect(button.fieldKey, 'breakout_midDead_photo');
expect(button.panelRowId, endsWith(':residue_breakout:sample-1:midDead'));
```

Seed a sample photo map with `midDead:photo-1` and assert the thumbnail is a
descendant of `breakout-photo-sample-1-midDead`, not the `earlyDead` row.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
flutter test test/features/audits/hatch_analysis_screen_breakout_test.dart --plain-name "breakout items keep metric photos beside their rows"
```

Expected: FAIL because the screen currently renders one sample-level photo
control rather than one control for every count field.

- [ ] **Step 3: Implement metric-scoped same-row controls**

Pass each `EggBreakoutCountField` into a metric photo helper from
`_buildBreakoutCountRow`. Filter `sample.photos` with a stable prefix:

```dart
String _breakoutPhotoStoragePrefix(String fieldKey) => '$fieldKey:';

String _breakoutPhotoFieldKey(String fieldKey) =>
    'breakout_${fieldKey}_photo';
```

Render the count, BMK summary, and a fixed-width horizontal
`MultiPhotoButton(singleRow: true)` in one `Row`. Save new entries as
`'$fieldKey:photo_<timestamp>'`; replacement reuses the selected storage key.
Include `field.key` in `_breakoutPhotoRowId`.

- [ ] **Step 4: Run the widget test and verify GREEN**

Run the same focused command. Expected: PASS.

### Task 2: Keep multi-photo controls on one line and clean replaced rows

**Files:**
- Modify: `test/features/audits/photo_button_test.dart`
- Modify: `test/data/repositories/photo_repository_test.dart`
- Modify: `lib/features/audits/widgets/photo_button.dart`
- Modify: `lib/data/repositories/photo_repository.dart`

- [ ] **Step 1: Write failing control and repository tests**

Add a widget assertion that `MultiPhotoButton(singleRow: true)` contains a
horizontal `SingleChildScrollView`. Add an isolated repository test:

```dart
await repository.deleteByFilePath(local.path);
expect(await repository.getByFilePath(local.path), isNull);
expect(await File(local.path).exists(), isFalse);
```

- [ ] **Step 2: Run both suites and verify RED**

```bash
flutter test test/features/audits/photo_button_test.dart test/data/repositories/photo_repository_test.dart
```

Expected: compilation/test failure because `singleRow` and
`deleteByFilePath` do not exist.

- [ ] **Step 3: Implement one-line rendering and deletion**

Add `singleRow` to `MultiPhotoButton`; render its tiles as a `Row` inside a
horizontal `SingleChildScrollView` when enabled. Add
`PhotoRepository.deleteByFilePath`, using the same transaction, tombstone, and
local-file cleanup policy as `deleteByPanelRow`. When a thumbnail is removed or
successfully replaced, delete the obsolete persisted photo path.

- [ ] **Step 4: Run both suites and verify GREEN**

Run the same focused command. Expected: PASS.

### Task 3: Aggregate metric photo fields in the dashboard

**Files:**
- Modify: `test/features/dashboard/scope_comparison_provider_test.dart`
- Modify: `lib/features/dashboard/providers/scope_comparison_provider.dart`

- [ ] **Step 1: Write a failing dashboard aggregation test**

Configure the panel repository mock to return paths for
`breakout_infertile_photo`, `breakout_earlyDead_photo`, and the legacy
`breakout_photo` key, then assert `photoPathsFor('residue_breakout')` contains
the de-duplicated union.

- [ ] **Step 2: Run the focused test and verify RED**

```bash
flutter test test/features/dashboard/scope_comparison_provider_test.dart --plain-name "loads item-scoped breakout photos for the dashboard grid"
```

Expected: FAIL because `_loadBreakoutPhotos` currently queries only
`breakout_photo` and `photo`.

- [ ] **Step 3: Query every supported metric field key**

Extend `_loadBreakoutPhotos` with the metric-specific field keys for Fresh,
Candled, and Residue while retaining both legacy keys and path de-duplication.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the same focused command. Expected: PASS.

### Task 4: Document and verify the complete workflow

**Files:**
- Modify: `docs/LIVING_SPEC.md`
- Verify: all files above

- [ ] **Step 1: Update implemented behavior documentation**

Document same-row metric photo capture, metric-specific sample/SQLite
identities, replacement/removal cleanup, and dashboard grid aggregation. Add a
dated change-log entry.

- [ ] **Step 2: Format touched Dart files**

```bash
dart format lib/features/audits/screens/hatch_analysis_screen.dart lib/features/audits/widgets/photo_button.dart lib/data/repositories/photo_repository.dart lib/features/dashboard/providers/scope_comparison_provider.dart test/features/audits/hatch_analysis_screen_breakout_test.dart test/features/audits/photo_button_test.dart test/data/repositories/photo_repository_test.dart test/features/dashboard/scope_comparison_provider_test.dart
```

Expected: formatter exits successfully.

- [ ] **Step 3: Run focused regression tests**

```bash
flutter test test/features/audits/hatch_analysis_screen_breakout_test.dart test/features/audits/photo_button_test.dart test/data/repositories/photo_repository_test.dart test/features/dashboard/scope_comparison_provider_test.dart test/features/dashboard/scope_insights_hatch_layout_test.dart
```

Expected: all tests pass.

- [ ] **Step 4: Run focused static analysis**

```bash
dart analyze lib/features/audits/screens/hatch_analysis_screen.dart lib/features/audits/widgets/photo_button.dart lib/data/repositories/photo_repository.dart lib/features/dashboard/providers/scope_comparison_provider.dart test/features/audits/hatch_analysis_screen_breakout_test.dart test/features/audits/photo_button_test.dart test/data/repositories/photo_repository_test.dart test/features/dashboard/scope_comparison_provider_test.dart
```

Expected: no new errors or warnings in touched files.
