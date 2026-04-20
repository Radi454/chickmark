# Tasks: Phase 3 — All Audit Entry Screens

**Input**: Design documents from `/specs/004-audit-entry-screens/`
**Branch**: `004-audit-entry-screens`
**Date**: 2026-04-18

---

## Phase 1: Setup

**Purpose**: Confirm project structure and directories for new source files

- [ ] T001 Create directory `lib/features/audits/providers/` (add `.keep` placeholder)
- [ ] T002 [P] Create directory `lib/features/audits/screens/` (add `.keep` placeholder)
- [ ] T003 [P] Create directory `lib/features/audits/widgets/tabs/` (add `.keep` placeholder)
- [ ] T004 [P] Create directory `lib/services/photo/` (add `.keep` placeholder)
- [ ] T005 [P] Create directory `lib/data/repositories/` (confirm exists — already created in Phase 2)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: All items below MUST be complete before any audit screen is built

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### 2A — Calculation Bug Fixes (Constitution III — Test-First)

- [ ] T006 Write unit tests for `pasgarScore` and `uniformityPercent` in `test/calculation_utils_test.dart` — tests must FAIL before T007/T008
- [ ] T007 Fix `pasgarScore` formula in `lib/core/utils/calculation_utils.dart`: replace `10 - (sum * 2 / eggs)` with `((sampleSize * 10) - sum) / sampleSize` (returns 0.0 when sampleSize == 0)
- [ ] T008 Fix `uniformityPercent` formula in `lib/core/utils/calculation_utils.dart`: return % of values INSIDE range (>= min && <= max), not outside
- [ ] T009 Run `flutter test test/calculation_utils_test.dart` — all tests must pass before proceeding

### 2B — Schema Migration (DB v1 → v2)

- [ ] T010 Add `hatchNumber INTEGER NOT NULL DEFAULT 1` column to `audits` table in `lib/data/database/database_helper.dart` via `onUpgrade` (version 1 → 2)
- [ ] T011 Drop old UNIQUE INDEX `idx_audits_unique` and create new one including `hatchNumber` in `lib/data/database/database_helper.dart`
- [ ] T012 Add `hatchNumber` field to `AuditModel` in `lib/data/models/audit_model.dart` — update `fromMap`, `toMap`, and constructor (default 1)
- [ ] T013 Add `getAuditsBySession(String customerId, String flockId, String date, String auditType)` method to `lib/data/repositories/audit_repository.dart`

### 2C — New Data Models

- [ ] T014 [P] Create `lib/data/models/tray_model.dart` with `HatchResultsTray` (trayId, position, traySize, infertile) and `EggBreakoutTray` (trayId, position, parameters Map) — both with `fromMap`/`toMap`/`fromJson`/`toJson`
- [ ] T015 [P] Create `lib/data/models/yfbm_entry_model.dart` with `chickWeight`, `yolkWeight` (both nullable doubles) — with `fromMap`/`toMap`
- [ ] T016 [P] Enhance `TroubleshootingModel` in `lib/data/models/troubleshooting_model.dart`: add `Map<String, List<String>> get hatcheryCausesBySection` and `farmFlockCausesBySection` typed getters that parse section-keyed JSON
- [ ] T017 [P] Create `lib/data/repositories/troubleshooting_repository.dart` with `getByParameter(String parameterId)` → returns `TroubleshootingModel?`

### 2D — Services

- [ ] T018 Create `lib/services/photo/photo_service.dart` with `Future<String?> pickPhoto({bool fromCamera = true})` (copies to app documents dir, returns path) and `Future<void> deletePhoto(String path)`
- [ ] T019 Implement BLE scan and advertisement parse in `lib/services/govee/govee_service.dart`: filter `FlutterBluePlus.scanResults` for names starting with `'Govee'`, parse manufacturer data bytes for temp/humidity; keep existing `_isAvailable` guard

### 2E — AuditProvider

- [ ] T020 Create `lib/features/audits/providers/audit_provider.dart` with full `AuditProvider extends ChangeNotifier`: holds `AuditContext`, `List<AuditModel> _drafts`, `int _activeHatchIndex`, `Map<int, Set<int>> _savedTabs`, `TempUnit tempUnit`; implement `updateField`, `saveTab`, `addHatch`, `switchHatch`, `loadForEdit`, `setEditMode`

### 2F — Shared Widgets

- [ ] T021 [P] Create `lib/features/audits/widgets/weight_grid_widget.dart`: `WeightGridWidget` with 100 `TextEditingController`s + `FocusNode`s, `GridView.count` 4 columns × 25 rows, numbered cells, `TextInputAction.next` focus chain, `enabled` flag for read-only
- [ ] T022 [P] Create `lib/features/audits/widgets/govee_sector.dart`: `GoveeSector` widget showing scan button (disconnected), device name + signal + temp + humidity (connected), or disabled card with "BLE unavailable" (`!isAvailable`)
- [ ] T023 [P] Create `lib/features/audits/widgets/photo_button.dart`: `PhotoButton` showing 📷 icon (no photo) or thumbnail + tap-to-view (photo exists); calls `PhotoService.pickPhoto()` on tap
- [ ] T024 [P] Create `lib/features/audits/widgets/est_grid_widget.dart`: `EstGridWidget` 3×3 grid keyed by `"{row}_{col}"` (`door/middle/back` × `top/middle/bottom`), each cell: `TextField` + `PhotoButton`, instant 🟢/🔴 per cell

**Checkpoint**: Foundation complete — user story phases can now proceed

---

## Phase 3: US1 — New Audit Flow (Priority: P1) 🎯 MVP

**Goal**: Auditor can select audit type, pick customer/flock, and arrive at the correct data entry screen

**Independent Test**: Tap "New Audit" → select "Chick Quality" → select a customer and flock → tap Continue → `ChickQualityScreen` opens with `AuditProvider` scoped

- [ ] T025 [US1] Create `lib/features/audits/screens/audit_type_selection_screen.dart`: full-width list of 5 audit types with icons (Egg Storage 🥚, Chick Quality 🐣, Hatch Analysis 📊, Setter Optimizing 🌡️, Hatcher Optimizing 🌡️); tap → push `AuditContextScreen(auditType)`
- [ ] T026 [US1] Create `lib/features/audits/screens/audit_context_screen.dart`: Customer dropdown (from DB via `CustomersProvider`); Flock dropdown filtered by customer (shown for CQ/HA/ES); Breed dropdown (shown for SO/HO: Ross308, Arbo, Avian, Cobb500, Hubbard, IR); [Continue] button → pushes data entry screen wrapped in `ChangeNotifierProvider(create: (_) => AuditProvider(...))`
- [ ] T027 [US1] Wire "New Audit" button in `lib/features/home/screens/home_screen.dart` → `Navigator.push → AuditTypeSelectionScreen`

**Checkpoint**: Full 3-step navigation flow works end-to-end

---

## Phase 4: US2 — Chick Quality Audit (Priority: P1) 🎯 MVP

**Goal**: Auditor can fill in all 5 CQ tabs, save each independently, and have data persisted to SQLite

**Independent Test**: Open CQ screen → fill Pasgar tab → tap Save → tab indicator turns green → reopen audit → data loads correctly

- [ ] T028 [US2] Create `lib/features/audits/screens/chick_quality_screen.dart`: `GradientAppBar('Chick Quality')`, `TempToggle` top-right, [+] hatch button, hatch selector (shown when hatches > 1), Setter ID + Hatcher ID fields, `TabBar` (5 tabs with green check when saved), `TabBarView`
- [ ] T029 [P] [US2] Create `lib/features/audits/widgets/tabs/cha_env_tab.dart`: `GoveeSector` (sector 1); manual fields CO2, PM10, PM2.5, Air Velocity ×3, Air Inlet, Air Outlet, Noise Level — all optional, each with `PhotoButton`; [Save] button at bottom
- [ ] T030 [P] [US2] Create `lib/features/audits/widgets/tabs/pasgar_tab.dart`: Sample Size field (default 40); table rows (Reflexes, Beak, Navel, Belly, Leg, Feather Dev) each with [−]/[+] buttons + manual entry + % display (count/sampleSize×100) + 🔴 when >20% + `PhotoButton`; Final Score card `((sampleSize×10)−sum)/sampleSize` displayed as X.X/10; Feather Dev excluded from score; [Save] button
- [ ] T031 [P] [US2] Create `lib/features/audits/widgets/tabs/weights_tab.dart`: BMK Age (auto), BMK Chick Weight (auto from bmk_breeds), Egg Storage Period field; `WeightGridWidget(mode: WeightsMode.chick)`; summary cards for AVG, Low Margin, High Margin, Uniformity % (🔴/🟡/🟢), CV% (🔴 if >8%); [Save] button
- [ ] T032 [P] [US2] Create `lib/features/audits/widgets/tabs/yfbm_tab.dart`: AVG% + CV% summary at top; single `PhotoButton`; 10-row table (Chick Weight g | Yolk Weight g | %) with [+ Add Row]; % = yolk/chick×100 per row instant; 🟢 8-10%, 🔴 outside; [Save] button
- [ ] T033 [P] [US2] Create `lib/features/audits/widgets/tabs/cvt_tab.dart`: AVG Temp + CV% summary at top; Sample Size field; `TempToggle`; 3-row table (Top/Middle/Bottom | Basket Entry | Temp | Status 🟢/🔴 | `PhotoButton`); optimum 103-105°F; [Save] button

**Checkpoint**: Full Chick Quality audit flow saves all 5 tabs to SQLite

---

## Phase 5: US3 — Hatch Analysis Audit (Priority: P1) 🎯 MVP

**Goal**: Auditor can fill Hatch Results and Egg Breakout tabs; troubleshooting sheet opens for High parameters

**Independent Test**: Open HA → add a tray → set infertile count → fertility calculates instantly → save tab → reopen → data loads

- [ ] T034 [US3] Create `lib/features/audits/screens/hatch_analysis_screen.dart`: `GradientAppBar('Hatch Analysis')`, [+] hatch button, hatch selector, Setter ID + Hatcher ID fields, `TabBar` (2 tabs: Hatch Results | Egg Breakout)
- [ ] T035 [US3] Create `lib/features/audits/widgets/tabs/hatch_results_tab.dart`: BMK Age (auto), Storage Days; Total Eggs Set, Hatched, Culled, Dead fields; Hatchability/Fertility/HOF summary cards vs BMK benchmarks; [+ Add Tray] with tray rows (Tray ID | Position dropdown | Tray Size | infertile → per-tray fertility); [Save] button
- [ ] T036 [US3] Create `lib/features/audits/widgets/tabs/egg_breakout_tab.dart`: BMK Age (auto), Tray Size (default 150); Breakout Type dropdown (Fresh Egg/Candled Egg/Hatch Residue) with auto-filled age; [+ Add Tray]; per-tray parameter table (Name | Count | % | BMK% | 🔴/🟡/🟢 status); `TroubleshootingIcon` on 🔴 rows; [Save] button
- [ ] T037 [US3] Create `lib/features/audits/widgets/troubleshooting_sheet.dart`: bottom sheet with [Hatchery Causes] / [Farm/Flock Causes] tabs; within each tab: sections (Management, Nutrition, Disease, Other) each as expandable list; loads from `TroubleshootingRepository.getByParameter()`
- [ ] T038 [US3] Fully implement `lib/widgets/troubleshooting_icon.dart`: 💡 `IconButton` that calls `showModalBottomSheet` with `TroubleshootingSheet(parameterId: id)` when tapped

**Checkpoint**: Hatch Analysis with Egg Breakout and troubleshooting fully functional

---

## Phase 6: US4 — Setter & Hatcher Optimizing Audits (Priority: P2)

**Goal**: Auditor can record EST/CVT grid readings with per-cell photos and Govee BLE data

**Independent Test**: Open Setter Optimizing → fill 3×3 EST grid → AVG and CV% calculate instantly → save → data loads

- [ ] T039 [US4] Create `lib/features/audits/screens/setter_optimizing_screen.dart`: `GradientAppBar('Setter Optimizing')`, `TempToggle`, Breed dropdown, Setter ID, Incubation Age slider (1-18); `GoveeSector`; CO2 field + `PhotoButton`; EST section header with AVG + CV% (optimum 100-101°F 🟢/🔴); `EstGridWidget` (rows: Door/Middle/Back, cols: Top/Middle/Bottom); [Save] button
- [ ] T040 [US4] Create `lib/features/audits/screens/hatcher_optimizing_screen.dart`: same structure as Setter with Hatcher ID, Incubation Age (18-21), CVT label (optimum 103-105°F), and additional Chick Panting [Yes/No] toggle + `PhotoButton`; reuse `EstGridWidget`

**Checkpoint**: Both Setter and Hatcher Optimizing screens save EST/CVT grid data

---

## Phase 7: US5 — Egg Storage & Handling Audit (Priority: P2)

**Goal**: Auditor can record Govee readings, shell temp, UV tray inspection, and egg uniformity

**Independent Test**: Open Egg Storage → add 2 UV trays with affected counts → overall avg affected calculates → save → data loads

- [ ] T041 [US5] Create `lib/features/audits/screens/egg_storage_screen.dart`: `GradientAppBar('Egg Storage & Handling')`, `TempToggle`; Sector 1: `GoveeSector`; Sector 2: CO2 + `PhotoButton`; Sector 3: Shell Temp (°C) + `PhotoButton` + 🟢/🟡/🔴 (19-21°C optimum); Sector 4: Turning Times dropdown (No Turning / 1-5 times); Sector 5: UV trays [+ Add Tray] up to 10 (Total Eggs | Affected Count | % auto | `PhotoButton` | 🗑️) + Overall Avg Affected; Sector 6: Egg Uniformity BMK Age/Weight + `WeightGridWidget` + same summary cards as Weights tab; [Save] button

**Checkpoint**: Egg Storage audit saves all 6 sectors to SQLite

---

## Phase 8: US6 — Multi-Hatch Session Support (Priority: P2)

**Goal**: Auditor can add a second hatch to any audit session; each hatch = separate DB row

**Independent Test**: Open Chick Quality → fill Pasgar tab → save → tap [+] → new hatch 2 created → fill Pasgar for hatch 2 → save → DB contains 2 rows with hatchNumber 1 and 2

- [ ] T042 [US6] Implement `addHatch()` in `AuditProvider` in `lib/features/audits/providers/audit_provider.dart`: creates new `AuditModel` draft with `hatchNumber = drafts.length + 1`, appends to `_drafts`, sets `_activeHatchIndex`; confirm `_savedTabs` map is keyed per hatch
- [ ] T043 [US6] Wire [+] hatch button and hatch selector in `ChickQualityScreen` and `HatchAnalysisScreen` to `AuditProvider.addHatch()` and `AuditProvider.switchHatch(index)`

**Checkpoint**: Multiple hatches can be recorded and saved independently within one session

---

## Phase 9: US7 — Read-Only View & Edit Mode (Priority: P3)

**Goal**: Opening an existing audit shows data in read-only mode; Edit button unlocks editing

**Independent Test**: Navigate to an existing Chick Quality audit from the session list → all fields are non-editable → tap Edit → fields become editable

- [ ] T044 [US7] Implement `loadForEdit(String auditId)` and `setEditMode(bool editable)` in `lib/features/audits/providers/audit_provider.dart`: loads all hatch rows for session from `AuditRepository.getAuditsBySession()`, populates `_drafts`, sets `_isReadOnly`
- [ ] T045 [US7] Pass `enabled: !provider.isReadOnly` through all tab form fields and `WeightGridWidget` — no new widgets needed; ensure Edit `IconButton` in `GradientAppBar` calls `provider.setEditMode(true)`

**Checkpoint**: Existing audits open in read-only and can be unlocked for editing

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Quality gates and integration wiring across all stories

- [ ] T046 Run `flutter analyze` — fix all warnings and errors
- [ ] T047 [P] Run `flutter test` — all calculation unit tests pass
- [ ] T048 [P] Smoke test full 3-step flow on iOS simulator: New Audit → Chick Quality → select customer/flock → fill Pasgar tab → save → tab turns green
- [ ] T049 [P] Verify Govee BLE degrades gracefully on macOS simulator (no crash, shows disabled card)
- [ ] T050 [P] Verify camera `PhotoButton` degrades gracefully on macOS simulator (no crash, shows disabled state)
- [ ] T051 Confirm `flutter analyze` clean after all tasks complete

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — BLOCKS all user stories
- **Phases 3–9 (User Stories)**: All depend on Phase 2 completion
  - Phase 3 (US1 Navigation) should be first — screens need somewhere to navigate to
  - Phases 4–9 can proceed in parallel after Phase 3
- **Phase 10 (Polish)**: Depends on all desired story phases complete

### Critical Blocking Order Within Phase 2

```
T006 (write tests) → T007 (fix pasgarScore) → T008 (fix uniformityPercent) → T009 (tests pass)
T010 (schema migration) → T011 (new index) → T012 (AuditModel hatchNumber) → T013 (repository method)
T014/T015/T016/T017 (models) — parallel
T018/T019 (services) — parallel
T020 (AuditProvider) — depends on T012, T014, T015
T021/T022/T023/T024 (shared widgets) — parallel, depend on T020
```

### Parallel Opportunities

```
# Phase 2C models (all parallel):
T014 tray_model.dart  |  T015 yfbm_entry_model.dart  |  T016 troubleshooting_model.dart  |  T017 troubleshooting_repository.dart

# Phase 2F shared widgets (all parallel after T020):
T021 WeightGridWidget  |  T022 GoveeSector  |  T023 PhotoButton  |  T024 EstGridWidget

# Phase 4 tabs (all parallel after T028 screen scaffold):
T029 ChaEnvTab  |  T030 PasgarTab  |  T031 WeightsTab  |  T032 YfbmTab  |  T033 CvtTab
```

---

## Implementation Strategy

### MVP Scope (P1 stories only)

1. Complete Phase 1 + Phase 2 (CRITICAL — blocks everything)
2. Complete Phase 3 (US1 navigation flow)
3. Complete Phase 4 (US2 Chick Quality — highest-value audit type)
4. Complete Phase 5 (US3 Hatch Analysis + Troubleshooting)
5. **VALIDATE**: Run `flutter test`, `flutter analyze`, smoke test on simulator
6. Demo/deploy MVP

### Full Delivery (all P1 + P2 + P3)

Continue with Phase 6 (US4), Phase 7 (US5), Phase 8 (US6), Phase 9 (US7), Phase 10 (Polish)

---

## Task Summary

| Phase | Tasks | User Story | Priority |
|-------|-------|------------|----------|
| Phase 1 Setup | T001–T005 | — | Blocking |
| Phase 2 Foundational | T006–T024 | — | Blocking |
| Phase 3 | T025–T027 | US1 New Audit Flow | P1 |
| Phase 4 | T028–T033 | US2 Chick Quality | P1 |
| Phase 5 | T034–T038 | US3 Hatch Analysis | P1 |
| Phase 6 | T039–T040 | US4 Setter/Hatcher | P2 |
| Phase 7 | T041 | US5 Egg Storage | P2 |
| Phase 8 | T042–T043 | US6 Multi-Hatch | P2 |
| Phase 9 | T044–T045 | US7 Read-Only | P3 |
| Phase 10 Polish | T046–T051 | — | — |

**Total tasks**: 51
**Parallel opportunities**: 20+ tasks marked [P]
**Suggested MVP**: Phases 1–5 (T001–T038, 38 tasks)
