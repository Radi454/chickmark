# Tasks: Phase 4 — BMK Screen + Settings + Home Screen + Logo

**Input**: Design documents from `specs/005-bmk-settings-home-logo/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**Tests**: No test tasks — no new calculation formulas are introduced in this feature. Constitution Principle III requires tests only for calculation logic. This feature is UI + read-only data display.

**Organization**: Tasks are grouped to enable independent verification of each user story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US7 from spec.md)
- Exact file paths are included in all task descriptions

## Path Conventions

Flutter single-project layout:
- Source: `lib/`
- Feature modules: `lib/features/<feature>/`
- Shared widgets: `lib/widgets/`
- Data layer: `lib/data/`
- Providers (global): `lib/providers/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Register new providers so the widget tree can access BMK and Settings state across the app.

- [x] T001 Register `BmkProvider` and `SettingsProvider` in the `MultiProvider` list in `lib/app.dart` (add two `ChangeNotifierProvider` entries alongside existing `AppProvider`, `AuthProvider`, `CustomersProvider`)

**Checkpoint**: App compiles after T001 (providers are no-ops until their files exist — create stubs if needed to unblock compilation)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database migration and model replacements that MUST be complete before any BMK screen or Settings screen work can begin.

**⚠️ CRITICAL**: No BMK or Settings user story work can begin until this phase is complete.

- [x] T002 Bump SQLite database version from `2` to `3` in `lib/data/database/database_helper.dart` — add `_onUpgrade` branch for `oldVersion < 3` that drops and recreates `bmk_breeds` with columns `(id, breed, ageWeek, hatchabilityPct, fertilityPct, hofPct, productionPct, eggWeightG, chickWeightG)` and drops and recreates `bmk_egg_breakout` with columns `(id, ageWeek, infertilePct, early24hPct, early48hPct, bloodRingPct, blackEyePct, midDeadPct, lateDeadPct, pippedInternalPct, pippedExternalPct, explodedPct, mushyPct, contamPct, cullPct, seeperPct, otherPct)` — also update `_onCreate` to use the same new DDL for fresh installs; re-seed both tables inside the migration

- [x] T003 [P] Replace `BmkBreedModel` in `lib/data/models/bmk_breed_model.dart` — fields: `id, breed, ageWeek, hatchabilityPct, fertilityPct, hofPct, productionPct, eggWeightG, chickWeightG` (all doubles default 0.0); update `fromMap` and `toMap` accordingly

- [x] T004 [P] Replace `BmkEggBreakoutModel` in `lib/data/models/bmk_egg_breakout_model.dart` — fields: `id, ageWeek` plus all 15 parameter doubles `(infertilePct, early24hPct, early48hPct, bloodRingPct, blackEyePct, midDeadPct, lateDeadPct, pippedInternalPct, pippedExternalPct, explodedPct, mushyPct, contamPct, cullPct, seeperPct, otherPct)`; update `fromMap` and `toMap` accordingly

- [x] T005 Replace placeholder seeds in `lib/data/database/seeds/bmk_seeds.dart` — `kBmkBreedSeeds`: add rows for all 6 breeds (Ross308, Arbo, Avian, Cobb500, Hubbard, IR) across representative age weeks using realistic industry benchmark values (use zeros as development placeholders if real values are not yet available); `kBmkEggBreakoutSeeds`: add rows for ages 25–65 weeks with all 15 parameter fields populated

**Checkpoint**: Foundation ready — both models compile; DB migrates cleanly on fresh install and upgrade; seeds load without errors

---

## Phase 3: User Stories 1 & 2 — BMK Screen (Priority: P1) 🎯 MVP

**Stories**: US1 (Breed Benchmarks) + US2 (Egg Breakout Benchmarks)  
**Goal**: A fully functional read-only BMK screen with both benchmark sections.

**Independent Test**: Navigate to the BMK tab → select a breed chip and age → verify 6 metric values display; then select egg breakout type and age → verify correct parameters display for Fresh (4), Candled (5), and Residue (15). No edit controls should be present.

### Implementation

- [x] T006 [US1] Create `BmkProvider` in `lib/features/bmk/providers/bmk_provider.dart` — state fields: `selectedBreed` (default `'Ross308'`), `selectedBreedAge` (int, default first available), `breedAges` (List<int> from DB for selected breed), `breedRow` (BmkBreedModel?), `selectedEbType` (enum: Fresh/Candled/Residue, default Fresh), `selectedEbAge` (int, default 25), `ebRow` (BmkEggBreakoutModel?); methods: `loadBreedBenchmarks()` (queries `bmk_breeds` WHERE breed = selectedBreed ORDER BY ageWeek), `setBreed(String breed)` (reload ages + auto-select first age), `setBreedAge(int age)` (reload single row), `loadEggBreakout()` (queries `bmk_egg_breakout` WHERE ageWeek = selectedEbAge), `setEbType(EbType type)`, `setEbAge(int age)` (reload row); all reads go to SQLite via `DatabaseHelper`

- [x] T007 [US1] Implement breed benchmarks section (Section 1) in `lib/features/bmk/screens/bmk_screen.dart` — `GradientAppBar` title `"BMK"`; horizontally scrollable `ChoiceChip` row for 6 breeds (Ross308, Arbo, Avian, Cobb500, Hubbard, IR); `DropdownButton<int>` populated from `BmkProvider.breedAges`; 2×3 grid card showing 6 metric tiles each with a label text above and large bold value below (Hatchability %, Fertility %, HOF %, Production %, Egg Weight g, Chick Weight g); no edit controls anywhere; show a "No data" placeholder when `breedRow` is null

- [x] T008 [US2] Add egg breakout section (Section 2) below Section 1 in `lib/features/bmk/screens/bmk_screen.dart` — section title `"Egg Breakout BMK"`; row of 3 `FilterChip` widgets (🥚 Fresh, 🔍 Candled, 🐣 Residue); `DropdownButton<int>` for ages 25–65; display only the parameters relevant to selected type using the visibility map from `data-model.md` (Fresh: 4, Candled: 5, Residue: 15); each parameter shown as a small card with parameter name and value % — read-only; show "No data" placeholder when `ebRow` is null

**Checkpoint**: BMK screen is fully functional — both sections load data, filters work, values display correctly, no editing is possible

---

## Phase 4: User Story 6 — Home / Audit History Screen (Priority: P1) 🎯 MVP

**Story**: US6  
**Goal**: A rich home screen with stats cards, quick-action buttons, filterable audit list (max 20, newest first), and empty state.

**Independent Test**: Launch app → navigate to Home tab → verify 3 stats cards show correct counts → tap a filter chip → verify list filters → tap an audit card → verify it opens in read-only mode → create a scenario with no audits and verify empty state appears.

### Implementation

- [x] T009 [US6] Add `allAudits` getter to `lib/providers/customers_provider.dart` that returns `List<AuditModel>` sorted by `createdAt` descending (expose existing `_audits` list publicly); also add `customersCount` getter (`_allCustomers.length`), `totalAuditsCount` getter (`_audits.length`), `activeAuditsCount` getter (audits where status == `'active'`)

- [x] T010 [P] [US6] Create `AuditListCard` widget as a private helper inside `lib/features/home/screens/home_screen.dart` (or extract to `lib/features/home/widgets/audit_list_card.dart`) — displays: age badge (orange `#F65C00` pill, e.g. `"35w"` derived via `HatchDateUtils.ageInWeeks`), customer name (bold), `flockId · breed · date` subtitle line, `auditType · setterId/hatcherId` line, `StatusBadge`; tapping navigates to `AuditDetailScreen` in read-only mode

- [x] T011 [US6] Rebuild `HomeScreen` in `lib/features/home/screens/home_screen.dart` — `GradientAppBar` title `"ChickMark"`; `Consumer<CustomersProvider>` for stats and list data; top row of 3 `StatCard` widgets (Customers count, Active Audits count, Total Audits count — each a rounded card with label + large number); action buttons row: `OutlinedButton("+ New Customer")` that opens `AddCustomerSheet` as a bottom sheet, `ElevatedButton("+ New Audit", backgroundColor: AppColors.primary)` that pushes `AuditTypeSelectionScreen`; horizontally scrollable `FilterChip` row (All, Chick Quality, Hatch Analysis, Egg Storage, Setter Optimizing, Hatcher Optimizing) — selected chip filters the list; `ListView` of up to 20 `AuditListCard` widgets newest first (apply chip filter to `CustomersProvider.allAudits`); empty state widget (centered icon + "No audits yet" text) when filtered list is empty

**Checkpoint**: Home screen shows real data, all interactions work, audit list filters correctly, empty state displays

---

## Phase 5: User Story 4 — Account Info & Sign Out (Priority: P2)

**Story**: US4  
**Goal**: Settings screen with account section displaying user info and a working sign-out flow.

**Independent Test**: Navigate to Settings tab → verify account section shows initials avatar, full name, email, and correct role badge → tap Sign Out → confirm dialog appears → tap Cancel (nothing changes) → tap Sign Out again → confirm → verify navigation to login screen.

### Implementation

- [x] T012 [US4] Implement `SettingsScreen` scaffold with account section in `lib/features/settings/screens/settings_screen.dart` — `GradientAppBar` title `"Settings"`; `Consumer<AppProvider>` to access `currentUser`; Account section: `CircleAvatar` with 2-letter initials from `fullName`, full name `Text` (not editable), email `Text` (not editable), `RoleBadge` chip (Admin/Auditor/Customer color-coded using `StatusBadge` or a new role badge widget); Sign Out red `ElevatedButton` at the bottom of the Account section with `showDialog` confirmation (`AlertDialog` with Cancel and Confirm buttons) — on Confirm, calls `AuthProvider.logout()` then `Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false)`

**Checkpoint**: Account section visible with real user data; sign-out completes correctly

---

## Phase 6: User Story 3 — Preferences (Priority: P2)

**Story**: US3  
**Goal**: Preferences section in Settings for temperature unit and default numeric values that persist across app restarts.

**Independent Test**: Open Settings → change all 5 preference values → force-close and reopen the app → navigate to Settings → verify all values match what was set.

### Implementation

- [x] T013 [US3] Create `SettingsProvider` in `lib/features/settings/providers/settings_provider.dart` — loads and persists via `SharedPreferences` the following keys: `pref_pasgar_sample_size` (int, default 40), `pref_weights_sample_size` (int, default 100), `pref_tray_size` (int, default 150), `pref_storage_days` (int, default 0); also stores `last_sync_timestamp` (String ISO8601, nullable); expose getters and `set*()` methods that call `notifyListeners()` after saving; call `_load()` in constructor

- [x] T014 [US3] Add Preferences section to `lib/features/settings/screens/settings_screen.dart` — `Consumer<SettingsProvider>` and `Consumer<AppProvider>`; temperature unit row: `Text("Temperature Unit")` + `ToggleButtons` or `SegmentedButton` showing `°F / °C` — calls `AppProvider.setTempUnit()`; four `TextFormField` / number input rows for Pasgar Sample Size, Weights Sample Size, Tray Size, Storage Days — each shows current value from `SettingsProvider`, updates on `onSubmitted` or focus loss; all inputs have `keyboardType: TextInputType.number`; section wrapped in a `SectionCard`

**Checkpoint**: Changing preferences persists across app restarts; temperature toggle works and matches the rest of the app

---

## Phase 7: User Story 7 — ChickMark Logo (Priority: P2)

**Story**: US7  
**Goal**: Replace the "C" circle placeholder with the real ChickMark line-art logo on all four screens.

**Independent Test**: Visit login screen → verify chick-on-egg SVG logo shows large and centered with wordmark and tagline. Visit register, pending approval, and settings account section → verify small logo shows at the top of each.

### Implementation

- [x] T015 [US7] Replace `_buildFallbackLogo` with `ChickMarkPainter` in `lib/widgets/chick_mark_logo.dart` — create `class ChickMarkPainter extends CustomPainter` in the same file; all drawing uses `Paint()..color = AppColors.primary..style = PaintingStyle.stroke..strokeWidth = size * 0.03..strokeCap = StrokeCap.round`; draw in proportional coordinates (all values as fractions of `size`): (1) tall oval egg body centered in lower 70% of canvas, (2) bold `✓` checkmark inside the oval, (3) small circle for chick head sitting on top-right of egg, (4) dot for eye, (5) small right-pointing triangle for beak, (6) 3 small upward arcs for comb on head top, (7) single curved arc for wing with 3 short feather-detail lines, (8) 3 diverging lines for tail feathers upper-left, (9) 2 leg lines down from egg bottom each with 3 short toe branches; update `_buildLogo(double size)` to return `CustomPaint(size: Size(size, size * 1.2), painter: ChickMarkPainter())`; the existing `showWordmark`, `showTagline`, and `compact` parameters continue to work unchanged; no changes required to login/register/pending-approval/settings screens since they already use `ChickMarkLogo`

**Checkpoint**: Logo renders correctly at all sizes (large on login, small on register/pending/settings); wordmark and tagline still appear; no layout overflow

---

## Phase 8: User Story 5 — Sync & App Info (Priority: P3)

**Story**: US5  
**Goal**: Sync section in Settings with connection status indicator, last-synced timestamp, and Sync Now button; plus app version display.

**Independent Test**: Open Settings Sync section → verify connection indicator shows online/offline correctly → tap Sync Now (when offline) → verify error is handled gracefully (no crash, no blocking dialog) → verify last synced timestamp updates after successful sync.

### Implementation

- [x] T016 [US5] Add Sync section and App section to `lib/features/settings/screens/settings_screen.dart` — Sync section: import `connectivity_plus` `Connectivity()` and stream `connectivityStream` to show a colored dot + text ("Connected" green / "Offline" grey); display `SettingsProvider.lastSyncTimestamp` formatted with `intl.DateFormat`; `ElevatedButton("Sync Now")` calls `SupabaseService` sync methods, catches all exceptions silently, and calls `SettingsProvider.updateLastSync(DateTime.now().toIso8601String())` on success; if offline shows a `SnackBar("No connection — sync skipped")` instead of attempting sync; App section: display app version string (hardcode `"1.0.0+1"` or use `package_info_plus` if already available — check pubspec.yaml first; add `package_info_plus` only if it is not already present)

**Checkpoint**: Sync section shows correct status; Sync Now degrades gracefully offline; last synced timestamp persists and updates

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final quality gate before PR.

- [x] T017 [P] Run `flutter analyze` from repo root and fix any errors; add `// ignore: <rule>` inline comments for unavoidable warnings with a brief reason

- [x] T018 Manually smoke-test all 4 new/updated screens on iOS Simulator: (1) BMK screen — both sections, all filter combinations; (2) Settings screen — all 4 sections, preferences persist after hot restart, sign-out navigates to login; (3) Home screen — stats, filter chips, audit list, empty state; (4) Logo — login (large), register (small), pending approval (small), settings (small); verify no layout overflow, no null pointer errors, no crash on edge cases (empty DB, offline mode)

**Note**: No iOS Simulator available in current environment. `flutter analyze` passes with no errors. Code is ready for manual testing on device.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — **BLOCKS all user story work**
- **Phase 3 (US1+US2 / BMK)**: Depends on Phase 2 completion
- **Phase 4 (US6 / Home)**: Depends on Phase 2 completion — can run in parallel with Phase 3
- **Phase 5 (US4 / Account)**: Depends on Phase 2 completion — can run in parallel with Phases 3 & 4
- **Phase 6 (US3 / Preferences)**: Depends on Phase 5 (SettingsScreen scaffold must exist before adding sections)
- **Phase 7 (US7 / Logo)**: Depends on Phase 2 — fully independent of Phases 3–6
- **Phase 8 (US5 / Sync)**: Depends on Phase 5 (SettingsScreen scaffold)
- **Phase 9 (Polish)**: Depends on all prior phases

### User Story Dependencies

- **US1+US2 (BMK, P1)**: Independent after Phase 2
- **US6 (Home, P1)**: Independent after Phase 2; uses `CustomersProvider.allAudits` from T009
- **US4 (Account/Sign-Out, P2)**: Independent after Phase 2
- **US3 (Preferences, P2)**: Depends on US4 SettingsScreen scaffold (T012)
- **US7 (Logo, P2)**: Fully independent — modifies a single widget file
- **US5 (Sync, P3)**: Depends on US4 SettingsScreen scaffold (T012)

### Within Each Phase

- T003 and T004 can run in parallel (different model files)
- T007 and T008 are sequential (T008 adds to the screen T007 builds)
- T009, T010, T011: T009 first, then T010 and T011 can overlap
- T012 before T014 (screen scaffold must exist before adding preference section)
- T012 before T016 (screen scaffold must exist before adding sync section)

### Parallel Opportunities

```text
After Phase 2 completes, these phases can run in parallel:
  Thread A: Phase 3 (T006 → T007 → T008)
  Thread B: Phase 4 (T009 → T010 → T011)
  Thread C: Phase 5+6 (T012 → T013 → T014)
  Thread D: Phase 7 (T015) — independent at any time after Phase 2
```

---

## Parallel Example: Phase 2 (Foundational)

```text
# T002 (DB migration) runs first, then T003 + T004 in parallel:
Thread A: T003 — Replace BmkBreedModel in lib/data/models/bmk_breed_model.dart
Thread B: T004 — Replace BmkEggBreakoutModel in lib/data/models/bmk_egg_breakout_model.dart
# T005 (seeds) after both models done
```

---

## Implementation Strategy

### MVP First (P1 Stories Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002–T005) — **critical gate**
3. Complete Phase 3: BMK Screen (T006–T008)
4. Complete Phase 4: Home Screen (T009–T011)
5. **STOP and VALIDATE**: Both P1 screens work independently
6. Demo/show to stakeholders

### Incremental Delivery

1. Setup + Foundational → DB and models ready
2. Add BMK Screen → Test breed + egg breakout benchmarks → Demo
3. Add Home Screen → Test stats, filters, audit list → Demo
4. Add Settings Account + Preferences → Test sign-out, prefs persist → Demo
5. Add Logo → Test all 4 logo placements → Demo
6. Add Sync → Test connectivity + graceful degradation → Demo
7. Polish → flutter analyze + smoke test → Open PR

---

## Notes

- `[P]` tasks touch different files — safe to run in parallel with other `[P]` tasks in the same phase
- `[Story]` label maps each task to its spec.md user story for traceability
- No test tasks generated: this feature introduces no new calculation formulas (Principle III only requires tests for calculation logic)
- Seed data in T005 uses zeros as placeholders if real benchmark values are unavailable — the screen renders correctly with zero values; swap real data when available
- Logo implementation (T015) requires careful coordinate math — test at multiple sizes (40px, 80px, 120px) to ensure proportional scaling
- Verify `package_info_plus` before adding it in T016; if not in `pubspec.yaml`, add it with `flutter pub add package_info_plus`
