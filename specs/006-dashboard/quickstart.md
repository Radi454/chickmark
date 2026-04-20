# Quickstart: Phase 5 — Dashboard

**Branch**: `006-dashboard` | **Date**: 2026-04-18

This guide gives an implementer (or Windsurf) a concise starting point and ordering for building the Dashboard feature.

---

## Prerequisites

- `fl_chart ^0.70.0` is already declared in `pubspec.yaml` — no changes needed.
- No new SQLite migrations required — all columns already exist in `audits` and `photos`.
- Existing utilities to reuse: `TempConverter`, `AppColors`, `AppTextStyles`, `AppThresholds`, `TroubleshootingIcon`, `TempToggle`, `SectionCard`.

---

## Implementation Order

### Step 1 — Dashboard Result Models
Create `lib/features/dashboard/models/` and add the Dart classes defined in `data-model.md`:
- `DashboardFilter`
- `HatchAnalysisAvg`, `HatchAnalysisTrend`
- `EggBreakoutAvg`
- `ChickWeightTrend`, `PasgarAvg`, `CvtAvg`, `YfbmTrend`, `ChaEnvironmentalTrend`
- `EggStorageTrend`
- `SetterComparison`, `HatcherComparison`
- `BmkReference`

### Step 2 — Unit Tests (write BEFORE query implementation)
Create `test/features/dashboard/dashboard_aggregation_test.dart`.
Write tests for:
- `HatchAnalysisAvg` calculation from raw rows (including "All ages" case)
- `BmkReference` lookup by breed + ageWeek
- CV% formula: `(stdDev / avg) × 100`
- Temperature conversion °F → °C and back
- Breakout severity classifier: `> bmk + 3%` → red; `> bmk` → yellow; else green

### Step 3 — AuditRepository query methods
Add to `lib/data/repositories/audit_repository.dart`:
```dart
Future<List<int>> getDistinctBmkAges(String customerId, String flockId);
Future<HatchAnalysisAvg?> getHatchAnalysisAvg(DashboardFilter filter);
Future<List<HatchAnalysisTrend>> getHatchAnalysisTrend(DashboardFilter filter);
Future<EggBreakoutAvg?> getEggBreakoutAvg(DashboardFilter filter, String breakoutType);
Future<List<ChickWeightTrend>> getChickWeightTrend(DashboardFilter filter);
Future<PasgarAvg?> getPasgarAvg(DashboardFilter filter);
Future<CvtAvg?> getCvtAvg(DashboardFilter filter);
Future<List<YfbmTrend>> getYfbmTrend(DashboardFilter filter);
Future<List<ChaEnvironmentalTrend>> getChaEnvironmentalTrend(DashboardFilter filter);
Future<EggStorageTrend?> getEggStorageAvg(DashboardFilter filter);
Future<List<EggStorageTrend>> getEggStorageTrend(DashboardFilter filter);
Future<List<String>> getDistinctSetterIds(String customerId, String flockId);
Future<List<SetterComparison>> getSetterComparisons(DashboardFilter filter, List<String> setterIds);
Future<List<String>> getDistinctHatcherIds(String customerId, String flockId);
Future<List<HatcherComparison>> getHatcherComparisons(DashboardFilter filter, List<String> hatcherIds);
Future<BmkReference?> getBmkReference(String breed, int ageWeek);
Future<List<String>> getPhotoPaths(DashboardFilter filter, String auditType, String description);
```

### Step 4 — DashboardProvider
Create `lib/features/dashboard/providers/dashboard_provider.dart`:

```dart
class DashboardProvider extends ChangeNotifier {
  // Cascade filter
  String? selectedCustomerId;
  String? selectedFlockId;
  int? selectedBmkAge;   // null = All

  // Available options
  List<CustomerModel> customers = [];
  List<FlockModel> flocks = [];
  List<int> bmkAges = [];

  // Machine selectors
  List<String> availableSetterIds = [];
  Set<String> selectedSetterIds = {};
  List<String> availableHatcherIds = [];
  Set<String> selectedHatcherIds = {};

  // Breakout type filter
  String breakoutType = 'fresh';  // 'fresh' | 'candled' | 'residue'

  // Section data (nullable = not yet loaded)
  HatchAnalysisAvg? hatchAnalysisAvg;
  List<HatchAnalysisTrend> hatchAnalysisTrend = [];
  EggBreakoutAvg? eggBreakoutAvg;
  // ... (one field per result model)

  BmkReference? bmkReference;

  bool isLoading = false;

  Future<void> setCustomer(String? id) async { ... notifyListeners(); await reload(); }
  Future<void> setFlock(String? id) async { ... notifyListeners(); await reload(); }
  Future<void> setBmkAge(int? age) async { ... notifyListeners(); await reload(); }
  Future<void> setBreakoutType(String type) async { ... notifyListeners(); await reload(); }
  Future<void> toggleSetter(String id) async { ... notifyListeners(); await reload(); }
  Future<void> toggleHatcher(String id) async { ... notifyListeners(); await reload(); }

  Future<void> reload() async {
    isLoading = true;
    notifyListeners();
    // Run all section queries in parallel with Future.wait(...)
    isLoading = false;
    notifyListeners();
  }
}
```

### Step 5 — Shared Widgets
Create these reusable widgets:

**`lib/widgets/photo_grid.dart`**
- `GridView.count(crossAxisCount: 3)` with `Image.file()` tiles
- Each tile: tap → push `PhotoFullscreenScreen`
- Empty state: centered icon + text

**`lib/widgets/chart_toggle.dart`**
- Three-option `SegmentedButton` or `ToggleButtons`: Bar | Line | Donut
- Passes selected `ChartType` enum back via callback

**`lib/features/dashboard/screens/photo_fullscreen_screen.dart`**
- `InteractiveViewer` wrapping `Image.file()`
- Close button overlay

### Step 6 — Chart Widgets (one per chart type)
Create `lib/features/dashboard/widgets/`:
- `bmk_bar_chart.dart` — `BarChart` with BMK bar alongside actual; BMK bar color grey
- `bmk_line_chart.dart` — `LineChart` with `HorizontalLine` for BMK reference (grey dashed)
- `bmk_donut_chart.dart` — `PieChart` as donut showing % achievement vs BMK
- `setter_comparison_table.dart` — horizontal scrollable `DataTable` with per-setter columns

Chart shared properties:
- `animate: true` (use `swapAnimationDuration`)
- On touch: show `LineTouchData` / `BarTouchData` tooltip with value
- BMK reference: `Color(0xFF9E9E9E)` dashed
- Actual value: `Color(0xFFF65C00)`
- Good (≤ BMK threshold): `Color(0xFF3A9A5C)`
- Bad (> BMK threshold): `Color(0xFFE24B4A)`

### Step 7 — Section Widgets
Create one widget per section in `lib/features/dashboard/widgets/sections/`:
- `hatch_analysis_section.dart`
- `egg_breakout_section.dart`
- `chick_quality_section.dart`
- `egg_storage_section.dart`
- `setter_optimizing_section.dart`
- `hatcher_optimizing_section.dart`

Each section widget:
- Wrapped in `ExpansionTile` (collapsible)
- Header: gradient or white `Card` with section title + icon
- Loading: `CircularProgressIndicator` centered in min-height box
- Empty state: icon + descriptive text
- Reads from `DashboardProvider` via `context.watch<DashboardProvider>()`

### Step 8 — DashboardScreen
Replace the placeholder in `lib/features/dashboard/screens/dashboard_screen.dart`:

```dart
class DashboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DashboardProvider()..init(),
      child: Consumer<DashboardProvider>(
        builder: (context, provider, _) => Scaffold(
          appBar: const GradientAppBar(title: 'Dashboard'),
          body: Column(
            children: [
              _CascadeFilterBar(),   // sticky top
              Expanded(
                child: ListView(
                  children: const [
                    HatchAnalysisSection(),
                    EggBreakoutSection(),
                    ChickQualitySection(),
                    EggStorageSection(),
                    SetterOptimizingSection(),
                    HatcherOptimizingSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Step 9 — Register Provider
Add `DashboardProvider` to the `MultiProvider` in `lib/app.dart` (or scope it to the Dashboard tab only using `ChangeNotifierProvider` inside `DashboardScreen` as shown above — preferred to avoid global state for a single screen).

### Step 10 — Verify & Test
1. Run `flutter analyze` — zero errors required.
2. Run `flutter test test/features/dashboard/` — all aggregation tests pass.
3. Run the app in iOS Simulator, navigate to Dashboard tab, verify:
   - Cascade filter populates correctly.
   - Each section loads data or shows empty state.
   - Chart toggle switches chart type.
   - Collapsing/expanding sections works.
   - Photo grid opens full-screen viewer with pinch-to-zoom.
   - °C/°F toggle converts temperatures globally.
   - 💡 icon appears on out-of-range breakout and Pasgar parameters.

---

## Key Thresholds Reference (from `AppThresholds` / constitution §XII)

| Metric | Threshold | Direction |
|--------|-----------|-----------|
| Culled % | ≤ 1% | Lower is better |
| Dead % | ≤ 0.2% | Lower is better |
| Breakout vs BMK | > BMK + 3% = red; > BMK = yellow | Lower is better |
| Pasgar parameter % | > 20% = alert + 💡 | Lower is better |
| Chick/Egg CV% | > 8% = alert | Lower is better |
| Uniformity % | < 80% poor; 80–85% good; > 85% excellent | Higher is better |
| CVT | 103–105 °F optimum | Outside = alert |
| EST | 100–101 °F optimum | Outside = alert |
| Shell temp | 19–21 °C optimum (> 21 °C = bad; < 19 °C = better) | Keep in range |
| YFBM % | 8–10% optimum | Outside = alert |

---

## Files to Create / Modify

| File | Action |
|------|--------|
| `lib/features/dashboard/models/*.dart` | CREATE (10+ model classes) |
| `lib/features/dashboard/providers/dashboard_provider.dart` | CREATE |
| `lib/features/dashboard/screens/dashboard_screen.dart` | REPLACE (was placeholder) |
| `lib/features/dashboard/screens/photo_fullscreen_screen.dart` | CREATE |
| `lib/features/dashboard/widgets/sections/hatch_analysis_section.dart` | CREATE |
| `lib/features/dashboard/widgets/sections/egg_breakout_section.dart` | CREATE |
| `lib/features/dashboard/widgets/sections/chick_quality_section.dart` | CREATE |
| `lib/features/dashboard/widgets/sections/egg_storage_section.dart` | CREATE |
| `lib/features/dashboard/widgets/sections/setter_optimizing_section.dart` | CREATE |
| `lib/features/dashboard/widgets/sections/hatcher_optimizing_section.dart` | CREATE |
| `lib/features/dashboard/widgets/bmk_bar_chart.dart` | CREATE |
| `lib/features/dashboard/widgets/bmk_line_chart.dart` | CREATE |
| `lib/features/dashboard/widgets/bmk_donut_chart.dart` | CREATE |
| `lib/features/dashboard/widgets/setter_comparison_table.dart` | CREATE |
| `lib/widgets/photo_grid.dart` | CREATE |
| `lib/widgets/chart_toggle.dart` | CREATE |
| `lib/data/repositories/audit_repository.dart` | EXTEND (add query methods) |
| `test/features/dashboard/dashboard_aggregation_test.dart` | CREATE |
