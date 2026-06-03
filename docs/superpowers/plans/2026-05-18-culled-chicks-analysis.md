# Culled Chicks Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Culled Chicks Analysis to Chick Quality data entry and dashboard interpretation without changing existing PM, Pasgar, YFBM, CVT, or Chick Weights behavior.

**Architecture:** Add a static catalog and codec for culled-chick defect subtypes, persist JSON plus derived summary fields on the existing `chick_quality` panel row, and aggregate that JSON in the dashboard repository. The UI gets a new collapsible workbench card after PM and a new Chicks dashboard tab for interpretation.

**Tech Stack:** Flutter, Dart, Provider, sqflite panel tables, existing widget tests and repository tests.

---

### Task 1: Schema And Model Surface

**Files:**
- Modify: `lib/data/models/panel_sample_schema.dart`
- Modify: `lib/data/models/audit_model.dart`
- Test: `test/data/models/panel_sample_schema_test.dart`
- Test: `test/data/database/panel_cutover_schema_test.dart`

- [ ] **Step 1: Write failing schema tests**

Add expectations that `chick_quality` includes:

```dart
containsAll([
  'culledChicksSampleSize INTEGER',
  'culledChicksAnalysisJson TEXT',
  'culledChicksTotalCount INTEGER',
  'culledChicksAffectedPct REAL',
  'culledChicksTopCategory TEXT',
  'culledChicksTopSubtype TEXT',
])
```

- [ ] **Step 2: Run schema tests and verify red**

Run:

```bash
flutter test test/data/models/panel_sample_schema_test.dart test/data/database/panel_cutover_schema_test.dart
```

Expected: tests fail because the new columns are absent.

- [ ] **Step 3: Add schema/model fields**

Add the six columns to the `chick_quality` `PanelSampleDefinition`. Add matching nullable fields to `AuditModel`, constructor, `fromMap`, and `toMap` using the same camelCase keys.

- [ ] **Step 4: Run schema tests and verify green**

Run the same command and expect all selected tests to pass.

### Task 2: Catalog, Codec, And Save Mapping

**Files:**
- Create: `lib/features/audits/models/culled_chicks_analysis.dart`
- Modify: `lib/features/audits/providers/audit_provider.dart`
- Test: `test/features/audits/chick_station_panel_persistence_test.dart`

- [ ] **Step 1: Write failing persistence test**

Extend the existing chick station persistence test to update:

```dart
provider.updateField('culledChicksSampleSize', 20);
provider.updateField(
  'culledChicksAnalysisJson',
  jsonEncode([
    {'id': 'navel_open_unhealed', 'count': 3},
    {'id': 'legs_red_hocks', 'count': 2},
  ]),
);
```

Then expect the saved `chick_quality` row to contain total `5`, affected pct `25.0`, top category `Navel`, and top subtype `Open / unhealed navel`.

- [ ] **Step 2: Run persistence test and verify red**

Run:

```bash
flutter test test/features/audits/chick_station_panel_persistence_test.dart
```

Expected: fails because fields and save mapping are not implemented.

- [ ] **Step 3: Add catalog and derived summary**

Create catalog entries for the user-provided categories, subtypes, descriptions, common causes, and source labels/URLs. Add helpers to decode JSON entries, enrich entries from the catalog, calculate total count, affected percentage, top category, and top subtype.

- [ ] **Step 4: Save derived fields on `chick_quality`**

In `_chickQualityValues`, derive the culled-chicks summary from the active draft and write all six new fields. Include `culledChicksSampleSize` in `_sampleSizeForPanel` so culled-only samples still save.

- [ ] **Step 5: Run persistence test and verify green**

Run the same persistence command and expect it to pass.

### Task 3: Chick Quality Data Entry UI

**Files:**
- Create: `lib/features/audits/widgets/tabs/culled_chicks_analysis_tab.dart`
- Modify: `lib/features/audits/screens/chick_quality_screen.dart`
- Test: `test/features/audits/chick_quality_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

Assert the workbench renders `Culled Chicks Analysis` after `PM Necropsy`, expands the panel, accepts a sample size and subtype count, and updates the provider draft JSON.

- [ ] **Step 2: Run widget test and verify red**

Run:

```bash
flutter test test/features/audits/chick_quality_screen_test.dart
```

Expected: fails because the panel is not present.

- [ ] **Step 3: Add the data-entry widget**

Build a compact collapsible-friendly widget with one sample-size numeric field, grouped subtype rows, count fields, and read-only context text for observation/common causes.

- [ ] **Step 4: Insert after PM**

Import the new widget in `ChickQualityScreen` and add a `_StationPanel` with key `chick-quality-panel-culled-analysis` immediately after the PM panel.

- [ ] **Step 5: Run widget test and verify green**

Run the same widget test command and expect it to pass.

### Task 4: Dashboard Aggregation And Interpretation

**Files:**
- Modify: `lib/features/dashboard/models/chick_quality_models.dart`
- Modify: `lib/data/repositories/panel_dashboard_repository.dart`
- Modify: `lib/features/dashboard/providers/dashboard_provider.dart`
- Modify: `lib/features/dashboard/widgets/sections/stub_sections.dart`
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`
- Test: `test/data/repositories/panel_dashboard_repository_test.dart`
- Test: `test/features/dashboard/dashboard_screen_test.dart`

- [ ] **Step 1: Write failing dashboard tests**

Insert `chick_quality` rows with culled-chicks JSON and expect repository aggregation to return sample size, total count, affected percentage, and top subtype. Add a dashboard widget expectation for `Culled Chicks Analysis` and `Open / unhealed navel`.

- [ ] **Step 2: Run dashboard tests and verify red**

Run:

```bash
flutter test test/data/repositories/panel_dashboard_repository_test.dart test/features/dashboard/dashboard_screen_test.dart
```

Expected: fails because no dashboard aggregation or UI exists.

- [ ] **Step 3: Implement repository/model/provider**

Add `CulledChicksAnalysisAvg`, `getCulledChicksAnalysis`, provider state/getter, and load it with the rest of Chick Quality dashboard data.

- [ ] **Step 4: Add dashboard tab**

Show `ChickQualitySection` on the dashboard and add a `Culled` tab that displays affected percentage, total findings, top category/subtype, review state, causes, and source labels.

- [ ] **Step 5: Run dashboard tests and verify green**

Run the same dashboard test command and expect it to pass.

### Task 5: Documentation And Narrow Regression

**Files:**
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Update living spec**

Document the new Chick Quality sector, same-row persistence fields, and dashboard interpretation behavior.

- [ ] **Step 2: Run narrow regression**

Run:

```bash
flutter test \
  test/data/models/panel_sample_schema_test.dart \
  test/data/database/panel_cutover_schema_test.dart \
  test/features/audits/chick_station_panel_persistence_test.dart \
  test/features/audits/chick_quality_screen_test.dart \
  test/data/repositories/panel_dashboard_repository_test.dart \
  test/features/dashboard/dashboard_screen_test.dart
```

Expected: all selected tests pass.
