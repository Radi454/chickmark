# Tasks: Phase 5 — Dashboard

**Input**: Design documents from `specs/006-dashboard/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.
**Tests**: Unit tests are required for all aggregation/calculation helpers per constitution §III.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to
- File paths are relative to the Flutter project root (`hatchaudit/`)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the directory structure and Dart result models that all subsequent phases depend on.

- [x] T001 Create directory `lib/features/dashboard/models/` and add all result model classes: `DashboardFilter`, `HatchAnalysisAvg`, `HatchAnalysisTrend`, `EggBreakoutAvg`, `ChickWeightTrend`, `PasgarAvg`, `CvtAvg`, `YfbmTrend`, `ChaEnvironmentalTrend`, `EggStorageTrend`, `SetterComparison`, `HatcherComparison`, `BmkReference` — one class per file as defined in `specs/006-dashboard/data-model.md`
- [x] T002 Create directory structure `lib/features/dashboard/widgets/sections/` and `lib/features/dashboard/widgets/` (empty directories with `.gitkeep` placeholders if needed)
- [x] T003 Create directory `test/features/dashboard/` and add file `test/features/dashboard/dashboard_aggregation_test.dart` with test stubs (failing) for: AVG calculation from raw rows, BmkReference lookup, CV% formula, temperature conversion °F↔°C, breakout severity classifier (red/yellow/green logic)

**Checkpoint**: Directory scaffolding complete; model classes compilable; test file present and failing.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Query layer and shared UI widgets that all six dashboard sections depend on.

**⚠️ CRITICAL**: No section widget can be built until this phase is complete.

- [x] T004 Extend `lib/data/repositories/audit_repository.dart` — add method `getDistinctBmkAges(String customerId, String flockId) → Future<List<int>>` using the SQL defined in `specs/006-dashboard/data-model.md`
- [x] T005 [P] Extend `lib/data/repositories/audit_repository.dart` — add method `getBmkReference(String breed, int ageWeek) → Future<BmkReference?>` querying `bmk_breeds` and `bmk_egg_breakout` tables
- [x] T006 [P] Extend `lib/data/repositories/audit_repository.dart` — add methods `getDistinctSetterIds(String customerId, String flockId)` and `getDistinctHatcherIds(String customerId, String flockId)` returning `Future<List<String>>`
- [x] T007 Implement aggregation unit tests in `test/features/dashboard/dashboard_aggregation_test.dart` — verify CV% formula, breakout severity thresholds, BMK lookup, and AVG calculations produce correct outputs; all tests must pass before T008
- [x] T008 Create `lib/features/dashboard/providers/dashboard_provider.dart` — implement `DashboardProvider extends ChangeNotifier` with: cascade filter state (`selectedCustomerId`, `selectedFlockId`, `selectedBmkAge`), setter/hatcher selection sets, breakoutType string, `isLoading` flag, `init()` method to load customers, `reload()` method that runs all section queries via `AuditRepository` using `Future.wait()`; expose all result model fields as nullable getters
- [x] T009 [P] Create `lib/widgets/photo_grid.dart` — reusable `PhotoGrid` widget accepting `List<String> filePaths`; renders `GridView.count(crossAxisCount: 3)` with `Image.file()` tiles; tapping a tile pushes `PhotoFullscreenScreen`; empty state when list is empty
- [x] T010 [P] Create `lib/features/dashboard/screens/photo_fullscreen_screen.dart` — `PhotoFullscreenScreen` widget accepting a `String filePath`; renders `InteractiveViewer` wrapping `Image.file(filePath)` with a close (back) button overlay; supports pinch-to-zoom
- [x] T011 [P] Create `lib/widgets/chart_toggle.dart` — `ChartToggle` widget with a `ToggleButtons` or `SegmentedButton` offering three options: Bar, Line, Donut; exposes a `ChartType` enum (`bar`, `line`, `donut`) and `onChanged` callback
- [x] T012 [P] Create `lib/features/dashboard/widgets/bmk_line_chart.dart` — `BmkLineChart` widget accepting `List<FlSpot> dataPoints`, `double bmkValue`, `String yLabel`; renders `LineChart` with animated draw, touch tooltips, and a grey dashed `HorizontalLine` at `bmkValue`; uses `Color(0xFFF65C00)` for data line
- [x] T013 [P] Create `lib/features/dashboard/widgets/bmk_bar_chart.dart` — `BmkBarChart` widget accepting `List<BarChartGroupData>` actual data and a BMK reference value; renders `BarChart` with animated draw, touch tooltips, and a grey dashed reference line; actual bars in `Color(0xFFF65C00)`
- [x] T014 [P] Create `lib/features/dashboard/widgets/bmk_donut_chart.dart` — `BmkDonutChart` widget accepting `double actualPct` and `double bmkPct`; renders `PieChart` as donut showing achievement vs BMK; achievement arc in green if ≥ BMK, red if not; center text shows percentage

**Checkpoint**: `flutter analyze` passes; aggregation tests pass; all foundational widgets compile; `DashboardProvider.reload()` callable (results may be empty).

---

## Phase 3: User Story 1 — Filter and View Hatch Analysis (Priority: P1) 🎯 MVP

**Goal**: Sticky cascade filter (Customer → Flock → BMK Age) fully working; Hatch Analysis section shows averages and three chart types vs BMK.

**Independent Test**: Select a customer/flock/age → Hatch Analysis section populates with five metrics, BMK indicators visible, and all three chart types (Bar, Line, Donut) render without errors.

- [x] T015 [US1] Extend `lib/data/repositories/audit_repository.dart` — add `getHatchAnalysisAvg(DashboardFilter filter) → Future<HatchAnalysisAvg?>` and `getHatchAnalysisTrend(DashboardFilter filter) → Future<List<HatchAnalysisTrend>>` using composite filter SQL from `data-model.md`
- [x] T016 [US1] Update `DashboardProvider` in `lib/features/dashboard/providers/dashboard_provider.dart` — wire `setCustomer()`, `setFlock()`, `setBmkAge()` to load flocks/ages from `AuditRepository`; `reload()` must call `getHatchAnalysisAvg` and `getHatchAnalysisTrend` and store results
- [x] T017 [US1] Create `lib/features/dashboard/widgets/sections/hatch_analysis_section.dart` — `HatchAnalysisSection` widget wrapped in `ExpansionTile`; reads `DashboardProvider`; shows loading indicator while `isLoading`; shows empty state when `hatchAnalysisAvg == null`; otherwise displays five metric rows (each with label, value, BMK target, colour-coded indicator); uses `ChartToggle` to switch between `BmkBarChart`, `BmkLineChart`, `BmkDonutChart`; 💡 icon not required on this section
- [x] T018 [US1] Replace placeholder in `lib/features/dashboard/screens/dashboard_screen.dart` — wrap screen in `ChangeNotifierProvider<DashboardProvider>`; add sticky `_CascadeFilterBar` widget at top (three `DropdownButtonFormField` widgets chained: Customer → Flock → BMK Age with an "All Ages" option); add `ListView` with only `HatchAnalysisSection()` for now (other sections added in later phases); call `provider.init()` in `initState`

- [x] T019 [US2] Extend `lib/data/repositories/audit_repository.dart` — add `getEggBreakoutAvg(DashboardFilter filter, String breakoutType) → Future<EggBreakoutAvg?>` and `getEggBreakoutTrend(DashboardFilter filter, String breakoutType) → Future<List<Map<String, dynamic>>>` (date + per-parameter averages)
- [x] T020 [US2] Extend `lib/data/repositories/audit_repository.dart` — add `getPhotoPaths(DashboardFilter filter, String auditType, String description) → Future<List<String>>` using the sub-select query from `data-model.md`
- [x] T021 [US2] Update `DashboardProvider` — add `setBreakoutType(String type)` method; `reload()` must call egg breakout queries and photo path query; store `eggBreakoutAvg`, `eggBreakoutTrend`, and `eggBreakoutPhotos` fields
- [x] T022 [US2] Create `lib/features/dashboard/widgets/sections/egg_breakout_section.dart` — `EggBreakoutSection` wrapped in `ExpansionTile`; type filter toggle (Fresh | Candled | Residue) calls `provider.setBreakoutType()`; displays only parameters valid for selected type (per spec FR-015); each parameter row shows value, BMK%, colour indicator (red/yellow/green per FR-016), and 💡 icon (using existing `TroubleshootingIcon`) when value > BMK; `ChartToggle` switches between `BmkBarChart`, `BmkLineChart`, `BmkDonutChart`; `PhotoGrid` at bottom using `eggBreakoutPhotos`
- [x] T023 [US2] Add `EggBreakoutSection()` to the `ListView` in `lib/features/dashboard/screens/dashboard_screen.dart`

**Checkpoint**: Egg Breakout section fully functional with type filter, severity badges, charts, and photo grid.

---

## Phase 5: User Story 3 — Analyse Chick Quality Subsections (Priority: P2)

**Goal**: Chick Quality section with five collapsible subsections (Weights, Pasgar, CVT, YFBM, CHA Environmental), each with appropriate charts and photo grids.

**Independent Test**: Each of the five subsections renders its charts independently; Pasgar 💡 icon appears when parameter % > 20%; photo grids show images or empty state.

- [x] T024 [P] [US3] Extend `lib/data/repositories/audit_repository.dart` — add `getChickWeightTrend(DashboardFilter filter) → Future<List<ChickWeightTrend>>` and `getPasgarAvg(DashboardFilter filter) → Future<PasgarAvg?>`
- [x] T025 [P] [US3] Extend `lib/data/repositories/audit_repository.dart` — add `getCvtAvg(DashboardFilter filter) → Future<CvtAvg?>`, `getYfbmTrend(DashboardFilter filter) → Future<List<YfbmTrend>>`, `getChaEnvironmentalTrend(DashboardFilter filter) → Future<List<ChaEnvironmentalTrend>>`
- [x] T026 [US3] Update `DashboardProvider` — add storage fields and `reload()` calls for all five chick quality query methods; add photo path queries for feather dev, CVT, YFBM, and CHA photos
- [x] T027 [US3] Create `lib/features/dashboard/widgets/sections/chick_quality_section.dart` — `ChickQualitySection` outer `ExpansionTile`; contains five inner `ExpansionTile` subsections:
- [x] T028 [US3] Add `ChickQualitySection()` to the `ListView` in `lib/features/dashboard/screens/dashboard_screen.dart`

- [x] T029 [P] [US4] Extend `lib/data/repositories/audit_repository.dart` — add `getEggStorageAvg(DashboardFilter filter) → Future<EggStorageTrend?>` and `getEggStorageTrend(DashboardFilter filter) → Future<List<EggStorageTrend>>`
- [x] T030 [US4] Update `DashboardProvider` — add `eggStorageAvg`, `eggStorageTrend`, `shellTempPhotos`, `uvPhotos` fields; wire `reload()` to call egg storage queries and photo queries
- [x] T031 [US4] Create `lib/features/dashboard/widgets/sections/egg_storage_section.dart` — `EggStorageSection` outer `ExpansionTile`; three inner subsections:
- [x] T032 [US4] Add `EggStorageSection()` to the `ListView` in `lib/features/dashboard/screens/dashboard_screen.dart`

**Checkpoint**: Egg Storage section loads; shell temp toggle switches units; UV bar chart renders.

---

## Phase 7: User Story 4 — Compare Setters and Hatchers (Priority: P3)

**Goal**: Setter Optimizing and Hatcher Optimizing sections with checkbox machine selectors, side-by-side comparison columns, EST/CVT charts, CO2 trends, and (hatchers) chick panting trend.

**Independent Test**: Check Setter 1 and Setter 3 → two side-by-side result columns plus BMK column render; hatcher chick panting % Yes vs No chart appears; machine checkbox deselection removes the column.

- [x] T033 [P] [US4] Extend `lib/data/repositories/audit_repository.dart` — add `getSetterComparisons(DashboardFilter filter, List<String> setterIds) → Future<List<SetterComparison>>` using the per-setter GROUP BY query from `data-model.md`
- [x] T034 [P] [US4] Extend `lib/data/repositories/audit_repository.dart` — add `getHatcherComparisons(DashboardFilter filter, List<String> hatcherIds) → Future<List<HatcherComparison>>`
- [x] T035 [P] [US4] Create `lib/features/dashboard/widgets/setter_comparison_table.dart` — `SetterComparisonTable` widget accepting `List<SetterComparison> setters` and `BmkReference bmk`; renders a horizontally scrollable `DataTable` with one column per setter plus a BMK column; each cell shows value + green/red indicator vs BMK; gap indicator row between parameter groups
- [x] T036 [US4] Update `DashboardProvider` — add `availableSetterIds`, `selectedSetterIds`, `toggleSetter()`, `setterComparisons`; add `availableHatcherIds`, `selectedHatcherIds`, `toggleHatcher()`, `hatcherComparisons`; `reload()` calls all setter/hatcher queries and photo queries; call `getDistinctSetterIds` and `getDistinctHatcherIds` during `init()`
- [x] T037 [US4] Create `lib/features/dashboard/widgets/sections/setter_optimizing_section.dart` — `SetterOptimizingSection` outer `ExpansionTile`; checkbox list for available setters (checked = selected); four subsections:
- [x] T038 [US4] Create `lib/features/dashboard/widgets/sections/hatcher_optimizing_section.dart` — `HatcherOptimizingSection` outer `ExpansionTile`; checkbox list for available hatchers; five subsections:
- [x] T039 [US4] Add `SetterOptimizingSection()` and `HatcherOptimizingSection()` to the `ListView` in `lib/features/dashboard/screens/dashboard_screen.dart`

**Checkpoint**: Both machine comparison sections render; toggling checkboxes adds/removes columns; CO2 and panting trends display.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final quality pass, edge cases, and constitution compliance verification.

- [x] T040 [P] Verify `flutter analyze` produces zero errors; add `// ignore:` comments with justification for any unavoidable warnings
- [x] T041 [P] Run `flutter test test/features/dashboard/` — all aggregation unit tests pass
- [x] T042 Verify customer role data isolation in `DashboardProvider.init()` — if `AppProvider.currentUser.role == 'customer'`, pre-filter `customerId` to `currentUser.customerId` and hide the Customer dropdown
- [x] T043 [P] Add empty state widgets to all six sections: descriptive text + icon for no-data cases; verify no blank white boxes appear when filter returns zero rows
- [x] T044 [P] Verify °C/°F toggle in Shell Temperature (4B), EST (5C), and CVT (6C) all convert correctly by consulting `TempConverter` and testing both directions; temperatures stored in °F per constitution §X
- [x] T045 Verify 💡 (`TroubleshootingIcon`) appears in Egg Breakout section for each parameter that exceeds BMK and in Pasgar Score subsection for each parameter > 20%, per constitution §XIII
- [x] T046 [P] Manual smoke test in iOS Simulator: navigate to Dashboard tab, select a customer/flock, verify all six sections load (or show empty state), collapse/expand each section, open a photo in full-screen view, pinch-to-zoom, switch °C/°F, switch chart types
- [x] T047 [P] Confirm `lib/app.dart` does not add `DashboardProvider` to global `MultiProvider` — it must remain scoped inside `DashboardScreen` via `ChangeNotifierProvider`

**Checkpoint**: `flutter analyze` clean; all tests pass; smoke test passes on simulator.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 completion — BLOCKS all sections
- **Phase 3 (US1 — Hatch Analysis)**: Depends on Phase 2 — MVP deliverable
- **Phase 4 (US2 — Egg Breakout)**: Depends on Phase 2; Phase 3 optional (sections are independent)
- **Phase 5 (US3 — Chick Quality)**: Depends on Phase 2; can run in parallel with Phase 4
- **Phase 6 (US4 — Egg Storage)**: Depends on Phase 2; can run in parallel with Phases 4–5
- **Phase 7 (US4 — Setters/Hatchers)**: Depends on Phase 2; T033–T035 can run in parallel with Phases 4–6
- **Phase 8 (Polish)**: Depends on all prior phases

### Parallel Opportunities Within Phases

**Phase 2**: T005, T006, T009, T010, T011, T012, T013, T014 can all run in parallel after T004 is done.

**Phase 5**: T024 and T025 can run in parallel (different repository methods).

**Phase 7**: T033, T034, T035 can run in parallel before T036 unblocks T037–T039.

**Phase 8**: T040, T041, T042, T043, T044, T045, T046, T047 can all run in parallel.

---

## Parallel Example: Phase 2 (Foundational)

```
After T004 (getDistinctBmkAges) completes, launch in parallel:
  Task T005: getBmkReference query method
  Task T006: getDistinctSetterIds / getDistinctHatcherIds query methods
  Task T009: PhotoGrid widget
  Task T010: PhotoFullscreenScreen widget
  Task T011: ChartToggle widget
  Task T012: BmkLineChart widget
  Task T013: BmkBarChart widget
  Task T014: BmkDonutChart widget

Then T008 (DashboardProvider) after T004–T006 are done.
```

---

## Implementation Strategy

### MVP First (User Story 1 — Hatch Analysis Only)

1. Complete Phase 1 (Setup)
2. Complete Phase 2 (Foundational) — critical blocker
3. Complete Phase 3 (US1 — Hatch Analysis + cascade filter)
4. **STOP and VALIDATE**: Dashboard tab shows cascade filter + Hatch Analysis section with real data and three chart types
5. Continue with Phases 4–7 for remaining sections

### Incremental Delivery

1. Phase 1 + 2 → Foundation ready
2. Phase 3 → Cascade filter + Hatch Analysis (**MVP demo-able**)
3. Phase 4 → Egg Breakout added
4. Phase 5 → Chick Quality added
5. Phase 6 → Egg Storage added
6. Phase 7 → Setter + Hatcher comparison added
7. Phase 8 → Polish and compliance

---

## Notes

- All temperatures stored in °F; convert to °C on display only via `TempConverter`
- `DashboardProvider` must be scoped to `DashboardScreen` (not global `MultiProvider`)
- No charts or computed KPIs on audit entry screens (constitution §VII)
- BMK values are read-only — never modified by dashboard queries
- `flutter analyze` must be clean before any PR is opened (constitution Quality Standards)
- Unit tests for aggregation helpers must pass before section widgets are implemented (constitution §III)
