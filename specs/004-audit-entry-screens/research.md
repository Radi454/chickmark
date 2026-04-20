# Research: Phase 3 — All Audit Entry Screens

**Branch**: `004-audit-entry-screens` | **Date**: 2026-04-18

## Findings

---

### Decision 1: Multi-Hatch Session — DB Schema Extension Required

**Decision**: Add a `hatchNumber` INTEGER column (default `1`) to the `audits` table and update the UNIQUE INDEX from `(customerId, flockId, date, auditType, setterId, hatcherId)` to `(customerId, flockId, date, auditType, setterId, hatcherId, hatchNumber)`. This requires a schema migration: DB version 1 → 2.

**Rationale**: The constitution mandates that each [+] hatch press = a separate DB row. With the current schema, two hatches from the same customer/flock/date/type/setter/hatcher combo would collide on the unique index. `hatchNumber` (1, 2, 3…) is the minimal discriminator that preserves the denormalized single-table design.

**Alternatives considered**:
- A separate `audit_sessions` table linking multiple `audits` rows — rejected because it breaks the single-table constitution principle and adds join complexity.
- A `sessionId` UUID column — rejected as over-engineered; an auto-incrementing integer per session context is simpler and sufficient.

---

### Decision 2: AuditProvider — Session-Scoped Provider

**Decision**: Introduce a new `AuditProvider extends ChangeNotifier` (in `lib/features/audits/providers/audit_provider.dart`) that holds all in-progress audit state: the audit context (type, customer, flock, breed), the list of in-progress AuditModel drafts (one per hatch), the currently active hatch index, tab save states, and the temperature unit mirror. It is registered with `ChangeNotifierProvider` only within the audit entry route subtree — not globally in `app.dart`.

**Rationale**: Audit session state is transient and scoped to the audit entry flow. Polluting the global `AppProvider` (or `CustomersProvider`) with 50+ ephemeral audit fields would cause widespread unnecessary rebuilds and complicate disposal. A scoped provider is disposed automatically when the route is popped.

**Alternatives considered**:
- Extending `AppProvider` — rejected per Constitution IV (simplicity) and because it would rebuild unrelated widgets on every keystroke.
- Using `InheritedWidget` manually — rejected as unnecessary complexity over Provider.

---

### Decision 3: Calculation Bugs — Fix Before Building UI

**Decision**: Fix two incorrect formulas in `lib/core/utils/calculation_utils.dart` before writing any audit UI. Write unit tests first per Constitution III.

**Bug 1 — `pasgarScore`**: Current implementation uses `10 - (sum * 2 / eggs)`. Constitution XII mandates: `((sample_size × 10) − (reflexes + beak + navel + belly + leg)) / sample_size`. These produce different results. The constitution formula is authoritative.

**Bug 2 — `uniformityPercent`**: Current implementation returns % OUTSIDE the range (inverted). The spec and constitution define uniformity as % of samples WITHIN AVG ± 10%. Must be corrected.

**Rationale**: All downstream UI alert logic (green/yellow/red bands) depends on these values being correct. Building screens on top of broken calculations means visual defects that are hard to detect later. Constitution III explicitly requires test-first for all calculation logic.

**Alternatives considered**:
- Fixing the formulas as part of screen implementation — rejected because tests would be written after the fact, violating Constitution III.

---

### Decision 4: Weight Grid Widget — Shared, Reusable

**Decision**: Build a single `WeightGridWidget` (in `lib/features/audits/widgets/weight_grid_widget.dart`) accepting a `List<TextEditingController>` (100 elements), an `onChanged` callback, and an `enabled` flag (for read-only mode). Used by both the Chick Weights tab and the Egg Uniformity section of Egg Storage. The grid uses a `GridView.count` with 4 columns × 25 rows, each cell numbered and focus-chained via `FocusNode` array.

**Rationale**: The 100-cell weight grid is specified identically for ChickWeights and EggUniformity (same layout, same calculations, different benchmark source). A shared widget eliminates duplication and ensures identical behavior.

**Alternatives considered**:
- Two separate, identical grid widgets — rejected (code duplication, maintenance risk).
- A `DataTable` widget — rejected because Flutter's `DataTable` is not optimized for dense text entry; `GridView` with `TextField` cells gives better keyboard control.

---

### Decision 5: Photo Handling — Thin PhotoService over image_picker

**Decision**: Create `lib/services/photo/photo_service.dart` with two methods: `pickPhoto({bool fromCamera})` → returns a local file path string (copies image to app documents directory), and `deletePhoto(String path)`. `image_picker` and `path_provider` are already in pubspec. Photo paths are stored directly in the audit model's photo columns (e.g., `chaCo2Photo`). A shared `PhotoButton` widget encapsulates the picker + thumbnail display.

**Rationale**: The schema already has photo path columns per field. A thin service layer keeps the BLoC/Provider clean and testable. `image_picker` provides both camera and gallery on iOS/Android. `path_provider` gives the documents directory for persistent storage (survives app restart).

**Alternatives considered**:
- Storing photos in Supabase Storage — deferred, not in scope for this phase.
- Embedding photo bytes directly in the DB — rejected (would bloat SQLite well beyond acceptable size).

---

### Decision 6: Govee BLE — Implement Actual Scan Logic

**Decision**: Implement the actual Govee device scan, connect, and characteristic-read logic in `lib/services/govee/govee_service.dart` using `flutter_blue_plus` (already installed). Govee H5179/H5075 devices advertise temperature and humidity in their manufacturer-specific data bytes. The implementation listens to `FlutterBluePlus.scanResults`, filters for device names starting with `'Govee'`, reads advertisement data, and parses temp/humidity. A `GoveeSector` widget (shared across all 5 audit types) wraps the scan button, device name, signal strength, and auto-filled temp/humidity fields.

**Rationale**: The `GoveeService` stub already checks Bluetooth availability. Extending it to parse manufacturer data is the minimum needed for real functionality. Per Constitution IX, the implementation must handle unavailability gracefully — the existing `_isAvailable` guard already provides this.

**Alternatives considered**:
- GATT characteristic subscription — requires device pairing and is more reliable for continuous data, but over-engineered for a one-shot field audit scan. Advertisement data parsing is sufficient and faster.

---

### Decision 7: Troubleshooting Data Structure — Section-Keyed JSON

**Decision**: Enhance `TroubleshootingModel` to parse section-keyed JSON for both hatchery and farm/flock causes. The JSON structure is: `{"Management": ["..."], "Nutrition": ["..."], "Disease": ["..."], "Other": ["..."]}`. The existing `troubleshooting` table stores one row per parameter (keyed by `id` = parameter name, e.g., `"infertile"`, `"early_24h"`). `TroubleshootingIcon` will be fully implemented to open `TroubleshootingSheet` when tapped.

**Rationale**: The constitution requires sections. The current flat JSON arrays in the model lose section grouping. The seeds (already in DB) likely contain this structured data. Updating the model's getter to return `Map<String, List<String>>` instead of `List<String>` is backward-compatible if the seeds are correctly structured.

**Alternatives considered**:
- A separate `troubleshooting_sections` table with one row per cause — rejected as over-normalized; the troubleshooting content is read-only and pre-seeded, so a JSON column is simpler.

---

### Decision 8: Tab Save State — AuditProvider-Tracked Map

**Decision**: `AuditProvider` tracks tab save state as `Map<int, Set<int>> _savedTabs` keyed by `hatchIndex → Set of saved tabIndices`. After each per-tab save, the tab indicator turns green (using a `TabBar` with `Tab(icon: Icon(Icons.check_circle, color: Colors.green))` when saved). Unsaved tabs show default styling.

**Rationale**: Each tab saves independently. The provider is the single source of truth for which tabs have been saved. The UI rebuilds only the `TabBar` header, not the tab content, on save state change.

**Alternatives considered**:
- Local `setState` in each tab widget — rejected because it doesn't survive tab switching; provider keeps state across tab changes.

---

### Decision 9: New Audit Flow — Navigator.push Chain (No Named Routes)

**Decision**: The 3-step new audit flow uses `Navigator.push` with constructor parameters:
1. `AuditTypeSelectionScreen` → tapping a type pushes `AuditContextScreen(auditType: type)`
2. `AuditContextScreen` → tapping Continue pushes the appropriate data entry screen with a newly scoped `AuditProvider` via `ChangeNotifierProvider`
3. Data entry screens are wrapped in a `ChangeNotifierProvider(create: (_) => AuditProvider(...))` at the point of push.

**Rationale**: Audit context (type + customer + flock) is route-scoped and transient. Named routes would require global state to pass parameters. Constructor-based push is simpler, type-safe, and aligns with Constitution IV.

**Alternatives considered**:
- Named routes with global state via `AppProvider` — rejected (pollutes global state, violates Constitution IV).
- `go_router` navigation — rejected; not currently in use in the project and would require a package addition and full refactor.

---

### Decision 10: Tray Data — JSON-Serialized TrayModel

**Decision**: Create `lib/data/models/tray_model.dart` with fields for both Hatch Results trays (trayId, position, traySize, infertile) and Egg Breakout trays (trayId, position, parameters as `Map<String, int>`). Lists of trays are JSON-encoded for storage in the `haTrays` and `ebTrays` TEXT columns (already in the schema). `AuditModel` deserializes them on `fromMap`.

**Rationale**: The existing schema already uses TEXT JSON columns for tray data. A typed `TrayModel` adds serialization safety and makes the provider code readable. Adding a separate `trays` relational table would require joins and a schema redesign, violating Constitution V.

**Alternatives considered**:
- Separate `trays` table with a foreign key to `audits` — rejected (breaks denormalized single-table constitution rule, adds join complexity).

---

### Constitution Compliance Pre-Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Offline-First | ✅ | SQLite writes first; Supabase background sync |
| II. Audit Data Integrity | ⚠️ REQUIRES FIX | `hatchNumber` column must be added to audits table (schema migration DB v1→v2) to support multi-hatch rows |
| III. Test-First Calculations | ⚠️ REQUIRES FIX | `pasgarScore` and `uniformityPercent` formulas are wrong; unit tests must be written and pass before UI work |
| IV. Simplicity | ✅ | Scoped AuditProvider, shared widgets, no new package additions |
| V. Database Design | ✅ | Single denormalized `audits` table maintained; tray data in JSON columns |
| VI. Navigation | ✅ | 5 audit types correct; Egg Breakout is a tab inside Hatch Analysis, not a separate type |
| IX. Integration Resilience | ✅ | GoveeService and PhotoService both have graceful degradation paths |
| X. Design System | ✅ | TempToggle widget exists; GradientAppBar exists; green tab after save is AuditProvider-driven |
| XII. Calculations | ⚠️ REQUIRES FIX | Two formula bugs identified; must be corrected and tested before screens are built |
| XIII. Troubleshooting | ✅ | TroubleshootingIcon will be fully implemented; sheet with section tabs defined |
