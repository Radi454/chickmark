# Dashboard Data-Aware Comparisons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each dashboard station default to an all-BMK-age table and expose only hierarchy comparisons that contain two or more comparable sibling samples.

**Architecture:** Keep SQLite panel rows as the source of truth and reuse `ScopeEngine` for within-age aggregation. Add pure engine helpers for sibling-aware layer eligibility, carry BMK age on loaded leaf rows, and extend the existing cumulative model into an age-first longitudinal result that can contain pooled, House, or Machine series. `ScopeComparisonProvider` owns per-sector age selection and valid layer state; widgets render the age table by default and use the existing chart icon to switch representations.

**Tech Stack:** Flutter/Dart, Provider, SQLite/sqflite, fl_chart, flutter_test.

---

## File Structure

- `lib/features/dashboard/scope/scope_models.dart`: add optional BMK-age metadata to each loaded leaf.
- `lib/features/dashboard/scope/scope_engine.dart`: compute sibling-aware eligible layers and equal-weight scalar averages.
- `lib/data/repositories/scope_comparison_repository.dart`: select the correct BMK-age column for every panel and return age-only periods.
- `lib/features/dashboard/models/scope_cumulative.dart`: represent longitudinal groups and equal-age averages.
- `lib/features/dashboard/providers/scope_comparison_provider.dart`: own all-age/single-age state, valid layer selection, and longitudinal series.
- `lib/features/dashboard/widgets/scope/scope_age_picker.dart`: shared independent BMK-age selector for generic and bespoke sectors.
- `lib/features/dashboard/widgets/scope/scope_sector_widget.dart`: render the per-sector age selector first and choose age-table versus selected-age matrix.
- `lib/features/dashboard/widgets/scope/scope_cumulative_view.dart`: render longitudinal table or chart from the same grouped series.
- `lib/features/dashboard/widgets/sections/egg_storage_station_section.dart`: apply the same age and one-house rules to bespoke Egg Quality.
- `lib/l10n/app_localizations.dart`: translate the new age/comparison labels.
- `test/features/dashboard/scope_engine_test.dart`: pure eligibility and averaging regressions.
- `test/features/dashboard/scope_comparison_provider_test.dart`: provider state and grouped-age regressions.
- `test/features/dashboard/scope_cumulative_view_test.dart`: selector, table-default, filter visibility, and chart-toggle regressions.
- `docs/LIVING_SPEC.md`: describe implemented dashboard behavior.

### Task 1: Sibling-aware comparison eligibility

**Files:**
- Modify: `lib/features/dashboard/scope/scope_engine.dart`
- Test: `test/features/dashboard/scope_engine_test.dart`

- [ ] **Step 1: Write failing eligibility tests**

Add tests that call this intended API:

```dart
expect(
  ScopeEngine.eligibleLayers(residue, [singleTrayLeaf]),
  isEmpty,
);
expect(
  ScopeEngine.eligibleLayers(residue, [h1t1, h2t2]),
  [SamplingLayer.house],
);
expect(
  ScopeEngine.eligibleLayers(residue, [h1t1, h1t2, h2t1]),
  [SamplingLayer.house, SamplingLayer.tray],
);
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/features/dashboard/scope_engine_test.dart`

Expected: compilation failure because `ScopeEngine.eligibleLayers` does not exist.

- [ ] **Step 3: Implement the pure eligibility helper**

Add a hierarchy-ordered helper that groups each candidate level by its preceding nonblank path and enables the candidate when any parent bucket has at least two nonblank children:

```dart
static List<SamplingLayer> eligibleLayers(
  ScopeSectorConfig sector,
  List<ScopeLeafRow> leaves, {
  Set<SamplingLayer>? limitTo,
}) {
  final ordered = nonPoolLayers(sector);
  final eligible = <SamplingLayer>[];
  for (var i = 0; i < ordered.length; i++) {
    final candidate = ordered[i];
    if (limitTo != null && !limitTo.contains(candidate)) continue;
    final childrenByParent = <String, Set<String>>{};
    for (final leaf in leaves) {
      final child = leaf.layerSegments[candidate]?.trim();
      if (child == null || child.isEmpty) continue;
      final parent = ordered
          .take(i)
          .map((layer) => leaf.layerSegments[layer]?.trim() ?? '')
          .where((value) => value.isNotEmpty)
          .join('·');
      childrenByParent.putIfAbsent(parent, () => <String>{}).add(child);
    }
    if (childrenByParent.values.any((children) => children.length >= 2)) {
      eligible.add(candidate);
    }
  }
  return eligible;
}
```

- [ ] **Step 4: Re-run the test and verify GREEN**

Run: `flutter test test/features/dashboard/scope_engine_test.dart`

Expected: all scope-engine tests pass.

### Task 2: Load BMK ages on scope leaves

**Files:**
- Modify: `lib/features/dashboard/scope/scope_models.dart`
- Modify: `lib/data/repositories/scope_comparison_repository.dart`
- Test: `test/features/dashboard/scope_comparison_provider_test.dart`

- [ ] **Step 1: Add a failing fake-repository/provider test**

Construct leaves with the intended optional field and verify period-local eligibility can be calculated without mixing ages:

```dart
ScopeLeafRow(
  bmkAge: 34,
  layerSegments: {SamplingLayer.house: 'H1'},
  cells: cells,
);
```

Expected assertion: H1 at W34 and H2 at W35 do not make House eligible because the houses never coexist at one age.

- [ ] **Step 2: Run the provider test and verify RED**

Run: `flutter test test/features/dashboard/scope_comparison_provider_test.dart`

Expected: compilation failure because `ScopeLeafRow.bmkAge` does not exist.

- [ ] **Step 3: Add age metadata and repository mapping**

Use this compatible model shape so existing dummy and test leaves remain valid:

```dart
class ScopeLeafRow {
  final int? bmkAge;
  final Map<SamplingLayer, String> layerSegments;
  final Map<String, ScopeCellAccumulator> cells;

  const ScopeLeafRow({
    this.bmkAge,
    required this.layerSegments,
    required this.cells,
  });
}
```

In `getScopeLeaves`, select `_ageColumnFor(table) AS _scopeBmkAge`, pass that same column to `_where`, and map the numeric value to `bmkAge`. Change `distinctPeriods` to return `W{age}` entries for every sector using `_ageColumnFor(table)`; do not create visit/date periods.

- [ ] **Step 4: Re-run provider tests and verify GREEN**

Run: `flutter test test/features/dashboard/scope_comparison_provider_test.dart`

Expected: provider tests compile and the age-isolation regression passes.

### Task 3: Provider age state and equal-age longitudinal series

**Files:**
- Modify: `lib/features/dashboard/models/scope_cumulative.dart`
- Modify: `lib/features/dashboard/providers/scope_comparison_provider.dart`
- Test: `test/features/dashboard/scope_comparison_provider_test.dart`

- [ ] **Step 1: Write failing provider tests**

Cover these public behaviors:

```dart
expect(provider.selectedLayersFor('residue_breakout'), isEmpty);
expect(provider.eligibleLayersFor('residue_breakout'), isEmpty); // one tray

await provider.setPeriod('residue_breakout', w36);
expect(provider.groupsFor('residue_breakout').single.label, 'Pool');
expect(provider.eligibleLayersFor('residue_breakout'), [SamplingLayer.tray]);

await provider.setPeriod('residue_breakout', null);
await provider.loadCumulative('residue_breakout');
expect(provider.cumulativeSeriesFor('residue_breakout')!.periods.map((p) => p.label), ['W34', 'W35']);
expect(provider.cumulativeSeriesFor('residue_breakout')!.groups.single.params.first.averageValue, 85);
```

Use W34 = 80 and W35 = 90 to prove the all-age average is 85 regardless of per-age leaf counts. Add a missing-age group case and assert null display data is excluded from its average.

- [ ] **Step 2: Run provider tests and verify RED**

Run: `flutter test test/features/dashboard/scope_comparison_provider_test.dart`

Expected: failures for missing eligible-layer API, all-on defaults, and missing grouped longitudinal model.

- [ ] **Step 3: Extend the longitudinal model**

Add grouped series while preserving a convenient pooled shape:

```dart
class CumulativeGroup {
  final String label;
  final List<CumulativeParam> params;
  const CumulativeGroup({required this.label, required this.params});
}

class CumulativeParam {
  final ScopeParam param;
  final List<num?> values;
  final List<num?> bmks;
  final List<String> texts;
  final List<ScopeSeverity> severities;
  final num? averageValue;
  final String averageText;

  const CumulativeParam({
    required this.param,
    required this.values,
    required this.bmks,
    required this.texts,
    required this.severities,
    required this.averageValue,
    required this.averageText,
  });
}

class CumulativeSeries {
  final List<ScopePeriod> periods;
  final List<CumulativeGroup> groups;
  List<CumulativeParam> get params => groups.isEmpty ? const [] : groups.first.params;
}
```

Calculate `averageValue` as the arithmetic mean of non-null per-age resolved values and format it through `ScopeParam.formatValue`. Text/yes-no values use `—` for the all-age average.

- [ ] **Step 4: Implement provider state rules**

Initialize `_selectedLayers[sectorId]` to an empty list. Expose `eligibleLayersFor`. For All Ages, partition leaves by `bmkAge`, union the sibling-aware results within each age, and retain only House/Machine layers. For a selected age, compute eligibility from that age's leaves and allow all configured levels. Reject toggles for ineligible levels.

Changing the period clears selected layers and hidden columns. Rebuild the longitudinal cache when an All-Ages House/Machine layer changes. Build one longitudinal group per stable label, keep null cells for missing ages, and add an overall group/average using equal weights rather than accumulator totals.

- [ ] **Step 5: Re-run provider tests and verify GREEN**

Run: `flutter test test/features/dashboard/scope_comparison_provider_test.dart`

Expected: all provider tests pass, including one-tray, nested sibling, all-age average, longitudinal House/Machine, and missing-age cases.

### Task 4: Per-sector age-first table and chart UX

**Files:**
- Modify: `lib/features/dashboard/widgets/scope/scope_sector_widget.dart`
- Create: `lib/features/dashboard/widgets/scope/scope_age_picker.dart`
- Modify: `lib/features/dashboard/widgets/scope/scope_cumulative_view.dart`
- Modify: `lib/features/dashboard/widgets/scope/layer_toggle_bar.dart`
- Modify: `lib/features/dashboard/widgets/sections/egg_storage_station_section.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Test: `test/features/dashboard/scope_cumulative_view_test.dart`
- Test: `test/features/dashboard/scope_sector_widget_test.dart`
- Test: `test/features/dashboard/egg_storage_station_section_test.dart`

- [ ] **Step 1: Write failing widget tests**

Assert the following:

```dart
expect(find.text('All BMK Ages'), findsOneWidget);
expect(find.byType(LineChart), findsNothing); // table default
expect(find.text('W25'), findsWidgets);
expect(find.text('W36'), findsWidgets);
expect(find.text('AVG'), findsOneWidget);
expect(find.text('Tray'), findsNothing); // All Ages
```

Select W36 and assert the pooled column is visible, only valid hierarchy chips appear, and tapping House plus Tray produces combined labels while keeping the average column. Tap the existing chart icon and assert the table is replaced by a chart without changing the selected age or layers.

- [ ] **Step 2: Run widget tests and verify RED**

Run: `flutter test test/features/dashboard/scope_cumulative_view_test.dart test/features/dashboard/scope_sector_widget_test.dart`

Expected: failures because the selector still says All, the mode toggle is present, and cumulative table/chart render together.

- [ ] **Step 3: Implement the age-first sector layout**

In `ScopeSectorWidget`, place the period picker before breakdown controls, label null selection `All BMK Ages`, remove the Incremental/Cumulative switch from this surface, and keep the existing chart/table icon. Render `ScopeCumulativeView` whenever no specific age is selected; render the existing tiles/matrix/chart path for a selected age.

Pass `provider.eligibleLayersFor(sectorId)` to `LayerToggleBar`. Hide the breakdown help and chips when the list is empty. In All Ages, the list can contain only House and Machine; in a selected age it can include any sibling-valid configured level.

- [ ] **Step 4: Split longitudinal table and chart rendering**

Make `ScopeCumulativeView` read `provider.isChartMode(sectorId)`. Table mode renders group/parameter rows with W-age columns, an `AVG` column, `No data`/`—` for missing values, and an overall row/group. Chart mode renders the selected parameter with one line per visible House/Machine group plus an overall-average reference where comparison is active.

- [ ] **Step 5: Re-run widget tests and verify GREEN**

Run: `flutter test test/features/dashboard/scope_cumulative_view_test.dart test/features/dashboard/scope_sector_widget_test.dart`

Expected: all age-selector, table, eligible-filter, pooled, and chart-toggle tests pass.

### Task 5: Living documentation and focused verification

**Files:**
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Update implemented behavior**

Document the per-sector `All BMK Ages` selector, separate age results, equal-age averages, pooled single-age default, sibling-valid hierarchy controls, multi-level selection, All-Ages House/Machine trends, missing-data behavior, and table/chart toggle. Add a dated change-log entry.

- [ ] **Step 2: Format touched Dart files**

Run:

```bash
dart format \
  lib/data/repositories/scope_comparison_repository.dart \
  lib/features/dashboard/models/scope_cumulative.dart \
  lib/features/dashboard/providers/scope_comparison_provider.dart \
  lib/features/dashboard/scope/scope_engine.dart \
  lib/features/dashboard/scope/scope_models.dart \
  lib/features/dashboard/widgets/scope/layer_toggle_bar.dart \
  lib/features/dashboard/widgets/scope/scope_cumulative_view.dart \
  lib/features/dashboard/widgets/scope/scope_sector_widget.dart \
  test/features/dashboard/scope_comparison_provider_test.dart \
  test/features/dashboard/scope_cumulative_view_test.dart \
  test/features/dashboard/scope_engine_test.dart \
  test/features/dashboard/scope_sector_widget_test.dart
```

Expected: formatter exits 0.

- [ ] **Step 3: Run the focused regression suite**

Run:

```bash
flutter test \
  test/features/dashboard/scope_engine_test.dart \
  test/features/dashboard/scope_comparison_provider_test.dart \
  test/features/dashboard/scope_cumulative_view_test.dart \
  test/features/dashboard/scope_sector_widget_test.dart \
  test/features/dashboard/scope_insights_hatch_layout_test.dart \
  test/features/dashboard/egg_storage_station_section_test.dart
```

Expected: all focused tests pass.

- [ ] **Step 4: Analyze touched Dart files**

Run:

```bash
flutter analyze \
  lib/data/repositories/scope_comparison_repository.dart \
  lib/features/dashboard/models/scope_cumulative.dart \
  lib/features/dashboard/providers/scope_comparison_provider.dart \
  lib/features/dashboard/scope/scope_engine.dart \
  lib/features/dashboard/scope/scope_models.dart \
  lib/features/dashboard/widgets/scope/layer_toggle_bar.dart \
  lib/features/dashboard/widgets/scope/scope_cumulative_view.dart \
  lib/features/dashboard/widgets/scope/scope_sector_widget.dart
```

Expected: no analyzer errors in touched production files.

- [ ] **Step 5: Review the final diff without disturbing unrelated changes**

Run: `git diff --check` and `git diff -- <touched paths>`.

Expected: no whitespace errors; only the approved dashboard comparison behavior, tests, plan, and living-spec additions are present in task-owned hunks.
