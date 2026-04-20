---
description: "Task list for Phase 1 — Foundation, Architecture & Design System"
---

# Tasks: Phase 1 — Foundation, Architecture & Design System

**Input**: Design documents from `specs/002-foundation-architecture-design/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ui-contracts.md ✅, quickstart.md ✅

**Tests**: Calculation utility unit tests are explicitly required by the spec and constitution.
Widget/integration tests are NOT required for this phase.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project structure, dependencies, and gitignore hygiene before any feature code.

- [ ] T001 Add `supabase_flutter: ^2.5.0` to `pubspec.yaml` dependencies and run `flutter pub get`
- [ ] T002 Create `lib/core/constants/supabase_config.dart` with placeholder URL + anonKey constants (file must be gitignored)
- [ ] T003 Add `lib/core/constants/supabase_config.dart` to `.gitignore`
- [ ] T004 [P] Create directory structure: `lib/core/constants/`, `lib/core/theme/`, `lib/core/utils/`, `lib/data/database/`, `lib/data/models/`, `lib/data/repositories/`, `lib/features/auth/screens/`, `lib/features/auth/widgets/`, `lib/features/auth/providers/`, `lib/features/home/screens/`, `lib/features/dashboard/screens/`, `lib/features/customers/screens/`, `lib/features/audits/screens/`, `lib/features/bmk/screens/`, `lib/features/settings/screens/`, `lib/providers/`, `lib/widgets/`, `lib/services/supabase/`, `lib/services/govee/`, `lib/services/ocr/`, `test/utils/`
- [ ] T005 [P] Delete all legacy files from previous project iteration: `lib/main.dart` (will be replaced), all existing files under `lib/models/`, `lib/screens/`, `lib/widgets/`, `lib/providers/`, `lib/utils/`, `lib/database/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Design System Tokens

- [ ] T006 [P] Create `lib/core/constants/app_colors.dart` — define `AppColors` class with named constants: `primary` (#F65C00), `primaryLight` (#ff8c42), `background` (#f0f2f5), `cardBackground` (#ffffff), `ageBadgeBg` (#FFF0E8), `completedBg` (#e8f5e9), `completedText` (#388e3c), `activeBg` (#fff8e1), `activeText` (#f57c00), `inactiveTab` (grey), `greenTab` (#388e3c)
- [ ] T007 [P] Create `lib/core/constants/app_sizes.dart` — define `AppSizes` class with: `cardRadius` (14.0), `buttonRadius` (12.0), `cardPadding` (16.0), `cardShadowBlur` (4.0), `cardShadowOffsetY` (1.0)
- [ ] T008 [P] Create `lib/core/constants/app_strings.dart` — define `AppStrings` class with UI label constants (tab names, button labels, info banners, error messages)
- [ ] T009 [P] Create `lib/core/constants/app_thresholds.dart` — define `AppThresholds` class with all threshold constants: `pasgarAlertPct` (20.0), `uniformityPoor` (80.0), `uniformityGood` (85.0), `cvAlertPct` (8.0), `yfbmMin` (8.0), `yfbmMax` (10.0), `cvtMin` (103.0), `cvtMax` (105.0), `estMin` (100.0), `estMax` (101.0), `shellTempMin` (19.0), `shellTempMax` (21.0), `egBreakoutHighThreshold` (3.0), `culledBmkPct` (1.0), `deadBmkPct` (0.2)
- [ ] T010 Create `lib/core/theme/text_styles.dart` — define `AppTextStyles` class with named `TextStyle` constants using system font (SF Pro default); include heading, body, caption, badge, wordmark styles
- [ ] T011 Create `lib/core/theme/app_theme.dart` — define `AppTheme.light()` returning a `ThemeData` that uses `AppColors`, `AppSizes`, `AppTextStyles`; set scaffold background to `AppColors.background`; configure `CardTheme` with 14px radius and shadow; configure `ElevatedButton` theme with 12px radius and `AppColors.primary` fill; configure `BottomNavigationBarTheme` with `AppColors.primary` selected item

### Calculation Utilities (Test-First)

- [ ] T012 [P] Create `test/utils/temp_converter_test.dart` — write failing tests for: `toCelsius(32.0) == 0.0`, `toCelsius(212.0) == 100.0`, `toFahrenheit(0.0) == 32.0`, `toFahrenheit(100.0) == 212.0`, `display(98.6, showCelsius: false) == "98.6°F"`, `display(98.6, showCelsius: true) == "37.0°C"`
- [ ] T013 [P] Create `test/utils/date_utils_test.dart` — write failing tests for: `flockAgeWeeks` with known entry date returning correct weeks, `flockAgeDays` equivalent, `bmkAgeWeeks(entryDate, 0)` formula = (flockAgeDays - 21) / 7, `bmkAgeWeeks` with storageDays=5 reduces correctly, zero-day flock
- [ ] T014 [P] Create `test/utils/calculation_utils_test.dart` — write failing tests for: `cvPercent([100,100,100]) == 0.0`, `cvPercent([90,100,110])` known value, `uniformityPercent` with all-in-range list = 100%, `uniformityPercent` with some out-of-range, `pasgarScore(40, [2,1,0,1,2]) == 9.0`, `pasgarScore(40, [0,0,0,0,0]) == 10.0`, `hatchability(900, 1000) == 90.0`, `hatchability(0, 1000) == 0.0`, `fertility(150, 0) == 100.0`, `fertility(150, 15) == 90.0`, `hof(90.0, 95.0)` known value, `average([1,2,3]) == 2.0`, `stdDev` known value
- [ ] T015 Create `lib/core/utils/temp_converter.dart` — implement `TempConverter` class per data-model.md contracts; run `flutter test test/utils/temp_converter_test.dart` and confirm all tests pass
- [ ] T016 Create `lib/core/utils/date_utils.dart` — implement `HatchDateUtils` class per data-model.md contracts; run `flutter test test/utils/date_utils_test.dart` and confirm all tests pass
- [ ] T017 Create `lib/core/utils/calculation_utils.dart` — implement `CalculationUtils` class per data-model.md contracts; run `flutter test test/utils/calculation_utils_test.dart` and confirm all tests pass

### Data Models

- [ ] T018 [P] Create `lib/data/models/user_model.dart` — `UserModel` with all fields from data-model.md; include `fromMap(Map)` and `toMap()` methods; include `bool get isTokenValid` getter checking expiry within 30 days
- [ ] T019 [P] Create `lib/data/models/customer_model.dart` — `CustomerModel` with `fromMap`/`toMap`
- [ ] T020 [P] Create `lib/data/models/flock_model.dart` — `FlockModel` with `fromMap`/`toMap`; `currentAgeWeeks` MUST be a getter using `HatchDateUtils.flockAgeWeeks(entryDate)`, NOT a stored field
- [ ] T021 [P] Create `lib/data/models/bmk_breed_model.dart` — `BmkBreedModel` with `fromMap`/`toMap`
- [ ] T022 [P] Create `lib/data/models/bmk_egg_breakout_model.dart` — `BmkEggBreakoutModel` with `fromMap`/`toMap`
- [ ] T023 [P] Create `lib/data/models/troubleshooting_model.dart` — `TroubleshootingModel` with `fromMap`/`toMap`; JSON decode `hatcheryCauses` and `farmFlockCauses` to `List<String>`
- [ ] T024 [P] Create `lib/data/models/photo_model.dart` — `PhotoModel` with `fromMap`/`toMap`
- [ ] T025 Create `lib/data/models/audit_model.dart` — `AuditModel` with ALL columns from data-model.md (common + all 5 audit-type field groups); include `fromMap`/`toMap`; all audit-type-specific fields are nullable

### Database

- [ ] T026 Create `lib/data/database/seeds/bmk_seeds.dart` — define Dart constant maps `kBmkBreedSeeds` (List of maps, placeholder 0.0 values for all 6 breeds × age combinations) and `kBmkEggBreakoutSeeds` (placeholder 0.0 values per age week); `kTroubleshootingSeeds` (empty list placeholder)
- [ ] T027 Create `lib/data/database/database_helper.dart` — implement `DatabaseHelper` singleton: `openDatabase` at `hatchaudit.db`, `_onCreate` creates all 8 tables (users, customers, flocks, audits, bmk_breeds, bmk_egg_breakout, troubleshooting, photos) with exact column definitions from spec.md; `_onUpgrade` migration stub; seed `bmk_breeds`, `bmk_egg_breakout`, `troubleshooting` from `bmk_seeds.dart` on `_onCreate`; add UNIQUE constraint on audits `(customer_id, flock_id, date, audit_type, setter_id, hatcher_id)`

### Repositories

- [ ] T028 [P] Create `lib/data/repositories/user_repository.dart` — methods: `upsertUser(UserModel)`, `getUserByEmail(String)`, `cacheToken(String userId, String token, DateTime expiry)`, `getCachedUser()` (returns first approved user with valid token)
- [ ] T029 [P] Create `lib/data/repositories/customer_repository.dart` — methods: `insertCustomer`, `getAllCustomers`, `getCustomerById`, `updateCustomer`
- [ ] T030 [P] Create `lib/data/repositories/flock_repository.dart` — methods: `insertFlock`, `getFlocksByCustomer(String customerId)`, `getFlockById`
- [ ] T031 [P] Create `lib/data/repositories/audit_repository.dart` — methods: `insertAudit`, `updateAudit`, `getAuditsByCustomer`, `getAuditById`, `getAuditsByType`

### Service Stubs

- [ ] T032 [P] Create `lib/services/supabase/supabase_service.dart` — implement `SupabaseService` per ui-contracts.md; `isAvailable` checks `SupabaseConfig` non-empty + network reachability; all methods wrapped in try/catch; `syncAudit` is fire-and-forget with silent error logging
- [ ] T033 [P] Create `lib/services/govee/govee_service.dart` — implement `GoveeService` per ui-contracts.md; `isAvailable` checks `flutter_blue_plus` Bluetooth state; if unavailable, `startScan` is no-op and `readings` is `Stream.empty()`
- [ ] T034 [P] Create `lib/services/ocr/ocr_service.dart` — implement `OcrService` per ui-contracts.md; `isAvailable` checks `image_picker` camera availability; if unavailable, `recognizeText` returns `null`

### Providers

- [ ] T035 Create `lib/providers/app_provider.dart` — implement `AppProvider extends ChangeNotifier` per ui-contracts.md: `currentUser`, `tempUnit` (default `TempUnit.fahrenheit`), `setCurrentUser`, `setTempUnit`; persist `tempUnit` to `shared_preferences` on change; load `tempUnit` from `shared_preferences` on init
- [ ] T036 Create `lib/features/auth/providers/auth_provider.dart` — implement `AuthProvider extends ChangeNotifier` per ui-contracts.md: `state` (AuthState enum), `errorMessage`, `user`; implement `checkCachedToken()` (reads from `UserRepository`, sets state to `authenticated` or `unauthenticated`); implement `login`, `register`, `logout` (delegate to `SupabaseService`, cache result via `UserRepository`)

### Shared Widgets

- [ ] T037 [P] Create `lib/widgets/chick_mark_logo.dart` — implement `ChickMarkLogo` widget per ui-contracts.md; render SVG asset if available at `assets/images/chickmark_logo.svg`, otherwise render fallback: orange "C" in circle + "CHICKMARK" in Georgia serif #F65C00 + "HATCHERY AUDIT" in grey small-caps
- [ ] T038 [P] Create `lib/widgets/temp_toggle.dart` — implement `TempToggle` widget per ui-contracts.md; reads `AppProvider.tempUnit` via `context.watch`; calls `AppProvider.setTempUnit` on tap; uses `AppColors.primary` for active segment
- [ ] T039 [P] Create `lib/widgets/status_badge.dart` — implement `StatusBadge` widget per ui-contracts.md; two variants (completed, active) with correct colours; unknown status fallback to grey
- [ ] T040 [P] Create `lib/widgets/section_card.dart` — implement `SectionCard` widget per ui-contracts.md; 14px radius, `AppColors.cardBackground` fill, box shadow per `AppSizes`; `isSaved: true` adds 3px green top border and Edit button; all child inputs disabled when `isSaved: true`
- [ ] T041 [P] Create `lib/widgets/troubleshooting_icon.dart` — implement `TroubleshootingIcon` stub widget per ui-contracts.md; Phase 1: always returns `SizedBox.shrink()` regardless of `visible` param

**Checkpoint**: Foundation ready — all providers, models, DB, services, and shared widgets exist. User story implementation can begin.

---

## Phase 3: User Story 1 — Auditor logs in for the first time (Priority: P1) 🎯 MVP

**Goal**: Full auth flow — Login → Register → Pending Approval → Home shell — with offline token caching.

**Independent Test**: Launch app, complete login with approved credentials, verify 6-tab nav shell. Kill app, go offline, relaunch, confirm offline login succeeds.

### Implementation for User Story 1

- [ ] T042 [P] [US1] Create `lib/features/auth/widgets/password_strength_indicator.dart` — renders a row of 3 coloured bars updating on each keystroke: 1 bar red (Weak: <8 chars or no number), 2 bars amber (Medium: ≥8 + 1 number), 3 bars green (Strong: ≥8 + 1 number + uppercase or special char)
- [ ] T043 [US1] Create `lib/features/auth/screens/login_screen.dart` — implement Login screen per spec FR-013: ChickMarkLogo (prominent, full), email `TextFormField`, password `TextFormField` with obscure toggle, right-aligned "Forgot password" `TextButton`, [Sign In] `ElevatedButton` (orange), "don't have an account?" divider, [Create Account] `OutlinedButton`, info banner "Offline mode available after first login"; on Sign In tap call `AuthProvider.login`; route to `MainShell` on `AuthState.authenticated`, route to `PendingApprovalScreen` on `AuthState.pendingApproval`, show `errorMessage` on `AuthState.error`
- [ ] T044 [US1] Create `lib/features/auth/screens/register_screen.dart` — implement Register screen per spec FR-014: small `ChickMarkLogo`, full name field, email field, password field with live `PasswordStrengthIndicator`, confirm password field, info banner about admin approval, [Create Account] `ElevatedButton`, ghost "Back to Login" button; client-side validation: password ≥8 chars + 1 number, passwords match; on submit call `AuthProvider.register`
- [ ] T045 [US1] Create `lib/features/auth/screens/pending_approval_screen.dart` — implement Pending Approval screen per spec FR-015: `ChickMarkLogo`, pending card (hourglass Icon + "Awaiting Approval" heading + description text), Forgot Password section (email field + "Send Reset Link" `ElevatedButton` + success state that hides the form), ghost "Back to Login" button; on reset link send call `SupabaseService.sendPasswordReset`
- [ ] T046 [US1] Create `lib/app.dart` — implement `MaterialApp` with `AppTheme.light()` as theme; use `AuthProvider` to drive initial route: `unauthenticated`/`error` → `LoginScreen`, `loading` → `Scaffold(body: CircularProgressIndicator())`, `authenticated` → `MainShell`, `pendingApproval` → `PendingApprovalScreen`; wrap with `MultiProvider` providing `AppProvider` and `AuthProvider`
- [ ] T047 [US1] Create `lib/main.dart` — `main()` function: initialise `WidgetsFlutterBinding`, call `DatabaseHelper.instance.database` to create DB on first run, call `Supabase.initialize(url, anonKey)` in try/catch (silent failure if offline), call `AuthProvider.checkCachedToken()`, then `runApp(HatchAuditApp())`

**Checkpoint**: User Story 1 complete. Launch app, log in, go offline, relaunch — offline login works. Pending Approval screen reachable. Register screen validates password.

---

## Phase 4: User Story 2 — Auditor navigates the app shell (Priority: P2)

**Goal**: 6-tab bottom navigation shell with correct screens and active tab colour.

**Independent Test**: Log in, tap each of the 6 tabs, confirm named placeholder screen loads and active tab turns #F65C00.

### Implementation for User Story 2

- [ ] T048 [P] [US2] Create `lib/features/home/screens/home_screen.dart` — scaffold placeholder: `AppBar` with orange gradient + "Home" title, `Center(child: Text('Home — coming soon'))`, no content yet
- [ ] T049 [P] [US2] Create `lib/features/dashboard/screens/dashboard_screen.dart` — scaffold placeholder with gradient AppBar "Dashboard"
- [ ] T050 [P] [US2] Create `lib/features/customers/screens/customers_screen.dart` — scaffold placeholder with gradient AppBar "Customers"
- [ ] T051 [P] [US2] Create `lib/features/audits/screens/audits_screen.dart` — scaffold placeholder with gradient AppBar "Audits"
- [ ] T052 [P] [US2] Create `lib/features/bmk/screens/bmk_screen.dart` — scaffold placeholder with gradient AppBar "BMK"
- [ ] T053 [P] [US2] Create `lib/features/settings/screens/settings_screen.dart` — scaffold placeholder with gradient AppBar "Settings"
- [ ] T054 [US2] Create `lib/features/home/widgets/main_shell.dart` — implement `MainShell` with `BottomNavigationBar` containing exactly 6 items in order: Home (home icon), Dashboard (bar_chart icon), Customers (people icon), Audits (assignment icon), BMK (science icon), Settings (settings icon); active item colour = `AppColors.primary`; inactive = grey; body switches between the 6 screen widgets using `IndexedStack` to preserve state; no `FloatingActionButton` at this phase

**Checkpoint**: User Story 2 complete. All 6 tabs navigable; active tab turns orange. No crashes.

---

## Phase 5: User Story 3 — Design system in action (Priority: P3)

**Goal**: Verify every Phase 1 screen passes the visual design-system spec — gradient headers, correct radii, background colour.

**Independent Test**: Open each Phase 1 screen and compare against spec FR-001 through FR-009; no per-screen colour/radius overrides exist.

### Implementation for User Story 3

- [ ] T055 [US3] Create `lib/core/theme/gradient_app_bar.dart` — reusable `GradientAppBar` widget that renders a `PreferredSizeWidget` with `BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]))`, white title text; accept optional `List<Widget> actions`; use this widget in ALL 6 tab placeholder screens and all auth screens (replace any plain `AppBar` calls)
- [ ] T056 [US3] Update `lib/features/auth/screens/login_screen.dart` — replace any plain `AppBar` with `GradientAppBar`; confirm scaffold background inherits `AppColors.background` from theme; wrap input fields in `SectionCard` widgets
- [ ] T057 [US3] Update `lib/features/auth/screens/register_screen.dart` — same as T056; add `GradientAppBar`; wrap form in `SectionCard`
- [ ] T058 [US3] Update `lib/features/auth/screens/pending_approval_screen.dart` — same; pending card MUST use `SectionCard` widget
- [ ] T059 [US3] Update all 6 tab placeholder screens (home, dashboard, customers, audits, bmk, settings) — replace inline `AppBar` with `GradientAppBar` widget (6 files: `home_screen.dart`, `dashboard_screen.dart`, `customers_screen.dart`, `audits_screen.dart`, `bmk_screen.dart`, `settings_screen.dart`)
- [ ] T060 [US3] Run `flutter analyze` — fix ALL reported errors; warnings require inline `// ignore: <reason>` justification; goal is zero errors output

**Checkpoint**: All 3 user stories complete. `flutter analyze` reports zero errors. All screens use design system tokens from `AppTheme`.

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Final quality gates and validations before this phase is considered complete.

- [ ] T061 [P] Run full unit test suite `flutter test test/utils/` — confirm all tests in `calculation_utils_test.dart`, `temp_converter_test.dart`, `date_utils_test.dart` pass; fix any failures
- [ ] T062 [P] Verify no hardcoded credentials, customer names, or flock identifiers appear in any committed file: run `grep -r "supabase.co\|anon_key\|api_key\|customer_name\|flock_id" lib/` (excluding `supabase_config.dart`) — must return zero matches
- [ ] T063 [P] Verify `lib/core/constants/supabase_config.dart` is listed in `.gitignore` and does NOT appear in `git status` tracked files
- [ ] T064 Verify SQLite DB creates all 8 tables on fresh install: launch app in iOS Simulator (fresh install / data cleared), then inspect DB file at `<simulator container>/Documents/hatchaudit.db` using DB Browser for SQLite; confirm tables: `users`, `customers`, `flocks`, `audits`, `bmk_breeds`, `bmk_egg_breakout`, `troubleshooting`, `photos`
- [ ] T065 Manual UI validation per quickstart.md §8: open each auth screen and each tab placeholder; verify gradient headers, #f0f2f5 background, 14px card radius, 12px button radius, correct badge colours
- [ ] T066 Run quickstart.md §7 validation: complete full auth flow on iOS Simulator — register → pending → (seed approve) → login → offline login; confirm each state routes correctly
- [ ] T067 [P] Confirm `TempToggle` widget changes displayed unit on all screens that include it: manually toggle [°C/°F] on a screen with temp field, confirm unit label and converted value update immediately without page rebuild
- [ ] T068 Final `flutter analyze` run — must report `No issues found!` before branch is considered ready for PR

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2 (all of it) — T042–T047
- **User Story 2 (Phase 4)**: Depends on Phase 2 (MainShell needs AppTheme + AppColors) — T048–T054
- **User Story 3 (Phase 5)**: Depends on US1 + US2 (screens must exist) — T055–T060
- **Polish (Phase N)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P1)**: Needs all of Phase 2. Independent of US2, US3.
- **US2 (P2)**: Needs AppTheme, AppColors, AppProvider from Phase 2. Independent of US1.
- **US3 (P3)**: Needs all screens from US1 + US2 to exist. `GradientAppBar` is created here and retrofitted.

### Within Each Phase — Parallel Opportunities

Phase 2 has the most parallelism:
- T006–T009 can all run in parallel (different files, no deps)
- T012–T014 (test files) can all run in parallel
- T018–T025 (models) can all run in parallel after T017
- T028–T031 (repositories) can all run in parallel after T027
- T032–T034 (service stubs) can all run in parallel
- T037–T041 (widgets) can all run in parallel after T006, T010, T011

Phase 4 (US2): T048–T053 (6 scaffold screens) can all run in parallel.

---

## Parallel Execution Example: Phase 2 Design System Tokens

```
# Launch all token files together:
Task T006: lib/core/constants/app_colors.dart
Task T007: lib/core/constants/app_sizes.dart
Task T008: lib/core/constants/app_strings.dart
Task T009: lib/core/constants/app_thresholds.dart
```

## Parallel Execution Example: Phase 2 Test Files (TDD)

```
# Write all failing test files together BEFORE implementing utils:
Task T012: test/utils/temp_converter_test.dart
Task T013: test/utils/date_utils_test.dart
Task T014: test/utils/calculation_utils_test.dart
# Then implement utils (T015, T016, T017) to make tests pass
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T005)
2. Complete Phase 2: Foundational (T006–T041) — CRITICAL
3. Complete Phase 3: User Story 1 (T042–T047)
4. **STOP and VALIDATE**: Login flow works, offline login works, pending screen works
5. Demo to stakeholder

### Incremental Delivery

1. Setup + Foundational → All infrastructure ready
2. User Story 1 → Auth flow works → Demo
3. User Story 2 → Nav shell works → Demo
4. User Story 3 → Design system validated → Branch ready for PR
5. Polish → All quality gates pass → Open PR

---

## Notes

- [P] = different files, no incomplete task dependencies — safe to run in parallel
- [US#] label maps each task to its user story for traceability
- TDD order is mandatory for calculation utils: tests FIRST (T012–T014), then implementation (T015–T017)
- `supabase_config.dart` must NEVER be committed — verify T003 and T063 before any push
- `currentAgeWeeks` in `FlockModel` MUST be a getter, never a stored column (T020)
- `es_shell_temp` is the only temperature stored in °C — all others in °F
- Phase 1 tab screens are intentionally empty scaffolds — no audit content yet
- `TroubleshootingIcon` is a no-op stub in Phase 1 — do not wire logic yet
