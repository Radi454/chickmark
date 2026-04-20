# Research: Phase 5 — Dashboard

**Branch**: `006-dashboard` | **Date**: 2026-04-18

## Summary

All technical questions were resolvable from existing project code and the constitution. No blocking unknowns remain. This document records the decisions made and the rationale behind each.

---

## Decision 1 — Chart Library

**Decision**: Use `fl_chart ^0.70.0` (already in pubspec.yaml).  
**Rationale**: Already a declared dependency; no new package addition required. Supports BarChart, LineChart, and PieChart (used as donut) with animation, touch callbacks, and horizontal reference lines (BMK line rendered as `HorizontalLine` or `ExtraLinesData`).  
**Alternatives considered**: `syncfusion_flutter_charts` (commercial license, overkill), `charts_flutter` (deprecated).

---

## Decision 2 — State Management for Dashboard

**Decision**: A single `DashboardProvider extends ChangeNotifier` placed in `lib/features/dashboard/providers/dashboard_provider.dart`.  
**Rationale**: Consistent with the existing provider-per-feature pattern (e.g., `AuditProvider`, `BmkProvider`, `SettingsProvider`). The provider holds cascade filter selections, triggers SQLite queries on filter change, and exposes typed result models per section.  
**Alternatives considered**: A nested provider-per-section approach would be over-engineered for a read-only screen.

---

## Decision 3 — Cascade Filter State

**Decision**: DashboardProvider exposes three nullable fields — `selectedCustomerId`, `selectedFlockId`, `selectedBmkAge` (nullable String; `null` = "All") — and a single `reload()` method that re-runs all section queries when any value changes.  
**Rationale**: A single reload entry point keeps the provider simple and guarantees all sections are always in sync with the same filter state.

---

## Decision 4 — BMK Age Filtering

**Decision**: "BMK Age" in the cascade filter maps to `bmkAge` on the `audits` row, calculated as `Flock Age − 21 days − Storage Days` per constitution §XII. The dropdown is populated by `SELECT DISTINCT bmkAge FROM audits WHERE flockId = ?`.  
**Rationale**: BMK age is already a stored computed field in the `audits` table (confirmed by `haStorageDays`, `chickStorageDays`, `esGoveeTemp` column pattern). Selecting "All" means `bmkAge IS NOT NULL` (i.e., include every audit for the flock regardless of age).

---

## Decision 5 — Data Aggregation Location

**Decision**: All SQL aggregation (AVG, COUNT, GROUP BY date) is performed in new query methods added to `AuditRepository`. The `DashboardProvider` calls these methods and maps results to typed Dart classes. No raw SQL lives in the provider or screen.  
**Rationale**: Consistent with existing repository pattern (`audit_repository.dart`). Keeps SQL testable in isolation.

---

## Decision 6 — Photo Display

**Decision**: Use Flutter's built-in `Image.file()` for local file-path photos. A reusable `PhotoGrid` widget renders a `GridView` with 3 columns. A new `PhotoFullscreenScreen` handles full-screen view with `InteractiveViewer` (built-in — supports pinch-to-zoom, no extra package needed).  
**Rationale**: `path_provider` is already a dependency. `InteractiveViewer` ships with Flutter; no new package needed.  
**Alternatives considered**: `photo_view` package — adds a dependency for functionality already available natively.

---

## Decision 7 — Temperature Unit

**Decision**: Reuse existing `AppProvider.tempUnit` (type `TempUnit`, values `fahrenheit`/`celsius`) and `TempConverter` utility from `lib/core/utils/temp_converter.dart`. The °C/°F toggle in shell temperature, EST, and CVT sections calls `context.read<AppProvider>().setTempUnit(...)`.  
**Rationale**: Temperature unit is a global preference already persisted via `shared_preferences`. Centralising it in `AppProvider` means toggling once affects the entire screen.

---

## Decision 8 — Setter/Hatcher Machine Selector

**Decision**: The setter/hatcher checkbox list is populated by `SELECT DISTINCT soSetterId FROM audits WHERE customerId = ? AND flockId = ?` (setter) and the equivalent for `hoHatcherId` (hatcher). Checkboxes are stored in `DashboardProvider._selectedSetterIds` (Set\<String\>) and `_selectedHatcherIds`.  
**Rationale**: Machine IDs are string identifiers stored in `soSetterId` / `hoHatcherId` columns. Distinct query guarantees only machines with actual data appear.

---

## Decision 9 — Troubleshooting Icon (💡)

**Decision**: The existing `TroubleshootingIcon` widget from `lib/widgets/troubleshooting_icon.dart` is reused next to egg breakout parameters that exceed BMK and Pasgar parameters > 20%, consistent with constitution §XIII.  
**Rationale**: Widget already exists and is designed exactly for this purpose.

---

## Decision 10 — Chart Colors

**Decision**:
- Actual values: `Color(0xFFF65C00)` (orange — `AppColors.primary`)
- BMK reference: grey dashed line (`ExtraLinesData` / `HorizontalLine` with dash pattern)
- Above BMK bad direction: `Color(0xFFE24B4A)` (red)
- Below BMK good direction: `Color(0xFF3A9A5C)` (green — close to `AppColors.completedText`)
**Rationale**: Matches spec requirement and existing `AppColors` palette.

---

## Decision 11 — Empty States and Loading

**Decision**: Each section uses a `FutureBuilder`/reactive consumer pattern. While data loads, a `CircularProgressIndicator` is shown inside the section. If the result list is empty, a centered `Text` with an icon describes the empty state.  
**Rationale**: Standard Flutter pattern; consistent with other screens in the project.

---

## Decision 12 — Section Collapse

**Decision**: Each section header is wrapped in `ExpansionTile` with `initiallyExpanded: true`. State is local to the widget (no provider involvement needed).  
**Rationale**: `ExpansionTile` handles animation, icon, and state natively. No extra complexity needed.

---

## Open Items

None. All NEEDS CLARIFICATION markers from spec are resolved. Implementation may proceed.
