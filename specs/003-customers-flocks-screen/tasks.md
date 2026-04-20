# Tasks: Phase 2 — Customers & Flocks Screen

**Input**: Design documents from `/specs/003-customers-flocks-screen/`
**Branch**: `003-customers-flocks-screen`
**Stack**: Dart 3 / Flutter SDK ^3.10.7, provider ^6.1.2, sqflite ^2.3.3+1, supabase_flutter

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US4)
- No test tasks — not requested in the feature spec

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create all new files and wire the provider before any UI work begins.

- [ ] T001 Register `CustomersProvider` in `MultiProvider` list in `lib/app.dart`
- [ ] T002 [P] Create empty `lib/providers/customers_provider.dart` with class stub, all state fields, and `ChangeNotifier` boilerplate
- [ ] T003 [P] Create directory structure: `lib/features/customers/widgets/` (create `.keep` or first widget file to establish the path)

**Checkpoint**: Provider registered; directory structure ready. No UI changes visible yet.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement the full `CustomersProvider` logic before any screen can use it. All user story UI tasks block on this phase.

**⚠️ CRITICAL**: No user story screen work can begin until T004–T008 are complete.

- [ ] T004 Implement `CustomersProvider.loadCustomers()` in `lib/providers/customers_provider.dart` — queries `CustomerRepository.getAllCustomers()` and `FlockRepository.getFlocksByCustomer()` for each customer to populate `_flockCounts` map
- [ ] T005 Implement `CustomersProvider.setSearchQuery(String)` in `lib/providers/customers_provider.dart` — updates `_searchQuery` and notifies listeners; `filteredCustomers` getter returns case-insensitive filtered list
- [ ] T006 Implement `CustomersProvider.addCustomer(CustomerModel)` in `lib/providers/customers_provider.dart` — calls `CustomerRepository.insertCustomer()`, refreshes `_allCustomers` and `_flockCounts`, then fires background Supabase sync (try/catch, silent failure)
- [ ] T007 Implement `CustomersProvider.selectCustomer(CustomerModel)` in `lib/providers/customers_provider.dart` — sets `_selectedCustomer`, loads flocks via `FlockRepository.getFlocksByCustomer()`, loads audits via `AuditRepository.getAuditsByCustomer()` sorted newest-first, auto-selects first flock if list is non-empty
- [ ] T008 Implement `CustomersProvider.addFlock(FlockModel)` and `CustomersProvider.selectFlock(FlockModel?)` in `lib/providers/customers_provider.dart` — `addFlock` calls `FlockRepository.insertFlock()`, refreshes `_flocks`, updates `_flockCounts`, auto-selects new flock, fires background Supabase sync; `selectFlock` simply updates `_selectedFlock`

**Checkpoint**: `CustomersProvider` is fully functional. Can be unit-tested independently of any UI.

---

## Phase 3: User Story 1 — Browse & Search Customers (Priority: P1) 🎯 MVP

**Goal**: Customers tab shows a searchable, filterable list of customer cards with flock count badges. Empty state handled.

**Independent Test**: Run app → tap Customers tab → see cards with name, location, phone, flock badge → type in search bar → list filters in real time → clear search → full list returns → no customers → empty state shown.

### Implementation

- [ ] T009 [US1] Create `lib/features/customers/widgets/customer_card.dart` — `Card` with 14px radius, bold name, location, phone (nullable), `Badge` widget showing flock count; `onTap` callback parameter
- [ ] T010 [US1] Replace stub in `lib/features/customers/screens/customers_screen.dart` with full implementation: `Consumer<CustomersProvider>`, `GradientAppBar('Customers')`, `TextField` search bar wired to `provider.setSearchQuery`, `OutlinedButton('[+ Add Customer]')` placeholder, `ListView.builder` over `provider.filteredCustomers`, empty state `Text` widget, calls `provider.loadCustomers()` in `initState`
- [ ] T011 [US1] Wire `OutlinedButton('[+ Add Customer]')` in `lib/features/customers/screens/customers_screen.dart` to call `_showAddCustomerSheet(context)` — implement the method as `showModalBottomSheet` call (sheet content in T012)
- [ ] T012 [US1] Create `lib/features/customers/widgets/add_customer_sheet.dart` — `Form` with `TextFormField` for Full Name (required validator), Location, Phone, Email; `ElevatedButton('Save', style: radius 12)` calls `provider.addCustomer(CustomerModel(...))` using `uuid` for ID, `AppProvider.currentUser.id` for `createdBy`, then `Navigator.pop(context)`

**Checkpoint**: US1 fully functional. Customer list renders, search works, Add Customer saves and refreshes list.

---

## Phase 4: User Story 2 — Add a New Customer (Priority: P1)

> US2 shares the same priority as US1 but depends on US1 infrastructure. T011–T012 above complete the Add Customer flow. This phase documents the validation wiring and Supabase sync confirmation.

**Goal**: Add Customer bottom sheet validates Full Name, saves to SQLite immediately, syncs silently to Supabase, closes sheet, and shows new card instantly.

**Independent Test**: Open bottom sheet → tap Save with empty name → see validation error → enter name → tap Save → sheet closes → new card appears in list.

### Implementation

- [ ] T013 [US2] Add form validation in `lib/features/customers/widgets/add_customer_sheet.dart` — `GlobalKey<FormState>`, `validator` on Full Name field returns error string when blank; `Save` button calls `_formKey.currentState!.validate()` before calling provider
- [ ] T014 [US2] Add Supabase background sync in `lib/providers/customers_provider.dart` `addCustomer()` method — after SQLite insert, call `SupabaseService().syncCustomer(customer.toMap())` inside a `try { unawaited(...) } catch (_) {}` block; add `syncCustomer` method to `lib/services/supabase/supabase_service.dart` targeting `customers` table

**Checkpoint**: Full Name validation fires correctly; Supabase sync is fire-and-forget with no UI impact.

---

## Phase 5: User Story 3 — View Customer Detail & Manage Flocks (Priority: P2)

**Goal**: Tapping a customer opens the Customer Detail screen with a flock dropdown, Add Flock button, and a flock detail card showing Flock ID, Breed, Entry Date, and auto-calculated Current Age in weeks (read-only).

**Independent Test**: Open any customer → flock dropdown populated → select flock → card shows correct age in weeks → tap Add Flock → form appears → fill fields → save → new flock appears in dropdown and is auto-selected → age calculates correctly from entry date.

### Implementation

- [ ] T015 [US3] Create `lib/features/customers/screens/customer_detail_screen.dart` — `Scaffold` with `GradientAppBar(title: customer.name)`, Edit `IconButton` (disabled, `onPressed: null`), `SingleChildScrollView` body; calls `provider.selectCustomer(customer)` in `initState`; renders Flocks section and Audit History section placeholders
- [ ] T016 [US3] Create `lib/features/customers/widgets/flock_detail_card.dart` — `Card` (14px radius) showing Flock ID, Breed (plain `Text`, not editable), Entry Date (formatted), Current Age as `Text('${flock.currentAgeWeeks} weeks')` with label 'Current Age (auto)'; reads from `FlockModel.currentAgeWeeks` getter
- [ ] T017 [US3] Implement Flocks section in `lib/features/customers/screens/customer_detail_screen.dart` — `DropdownButton<FlockModel>` bound to `provider.selectedFlock`, `onChanged: provider.selectFlock`, empty hint when no flocks; `OutlinedButton('[+ Add Flock]')` → `_showAddFlockSheet(context)`; `FlockDetailCard` shown below dropdown only when `provider.selectedFlock != null`; empty state text when `provider.flocks.isEmpty`
- [ ] T018 [US3] Create `lib/features/customers/widgets/add_flock_sheet.dart` — `Form` with `TextFormField` for Flock ID (required), `DropdownButtonFormField<String>` for Breed (items: `['Ross308','Arbo','Avian','Cobb500','Hubbard','IR']`, default `'Ross308'`), `ListTile` entry date picker (`showDatePicker`, default today); `ElevatedButton('Save')` calls `provider.addFlock(FlockModel(...))` then `Navigator.pop(context)`
- [ ] T019 [US3] Add Supabase background sync for flocks in `lib/providers/customers_provider.dart` `addFlock()` — after SQLite insert, fire-and-forget call to `SupabaseService().syncFlock(flock.toMap())`; add `syncFlock` method to `lib/services/supabase/supabase_service.dart` targeting `flocks` table
- [ ] T020 [US3] Wire `CustomerCard.onTap` in `lib/features/customers/screens/customers_screen.dart` to `Navigator.push(CustomerDetailScreen(customer: customer))`

**Checkpoint**: Full customer detail screen functional. Flocks load, dropdown works, Add Flock saves and auto-selects, age shows correctly.

---

## Phase 6: User Story 4 — View Audit History for a Customer (Priority: P3)

**Goal**: Customer Detail screen shows an Audit History section (newest first) with cards displaying age badge, customer, flock, date, audit type, setter/hatcher IDs, and status badge. Tapping opens a read-only audit detail screen.

**Independent Test**: Open customer with existing audits → Audit History section shows cards newest-first with all fields → tap a card → read-only detail screen opens → no edit controls visible → back button works.

### Implementation

- [ ] T021 [US4] Create `lib/features/customers/widgets/audit_history_card.dart` — `Card` (14px radius) with: age-weeks badge (derived via `HatchDateUtils.flockAgeWeeks(flock.entryDate)` using today's date), customer name, flock `flockId`, date formatted as `dd MMM yyyy`, audit type, `'Setter: ${audit.setterId}'`, `'Hatcher: ${audit.hatcherId}'`, `StatusBadge(audit.status)`; `onTap` callback parameter
- [ ] T022 [US4] Create `lib/features/customers/screens/audit_detail_screen.dart` — receives `AuditModel`; `GradientAppBar` with back button only; `SingleChildScrollView` body with `ListTile` rows for every non-null audit field; no edit controls; read-only mode enforced by using only `Text` widgets
- [ ] T023 [US4] Implement Audit History section in `lib/features/customers/screens/customer_detail_screen.dart` — `Consumer<CustomersProvider>`, `ListView` (non-scrollable, inside `SingleChildScrollView`) of `AuditHistoryCard` widgets from `provider.audits` (already sorted newest-first by `selectCustomer`); each card `onTap` → `Navigator.push(AuditDetailScreen(audit: audit))`; empty state text when `provider.audits.isEmpty`
- [ ] T024 [P] [US4] Resolve flock for each audit card in `lib/features/customers/widgets/audit_history_card.dart` — accept optional `FlockModel?` parameter for age badge; when null, show `'? wks'` badge gracefully

**Checkpoint**: Full audit history functional. Cards render newest-first, age badge shows, tapping opens read-only detail.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Loading states, edge cases, design system compliance, and constitution gate checks.

- [ ] T025 [P] Add `isLoading` spinner in `lib/features/customers/screens/customers_screen.dart` — show `CircularProgressIndicator` while `provider.isLoading` is true during `loadCustomers()`
- [ ] T026 [P] Add `isLoading` spinner in `lib/features/customers/screens/customer_detail_screen.dart` — show during `selectCustomer()` load
- [ ] T027 Verify design system compliance across all new widgets — confirm: gradient header (`#F65C00 → #ff8c42`), background `#f0f2f5`, card radius 14px, button radius 12px; fix any deviations
- [ ] T028 [P] Verify negative flock age displays as 0 weeks — in `lib/features/customers/widgets/flock_detail_card.dart`, render `max(0, flock.currentAgeWeeks).toInt()` weeks
- [ ] T029 Run `flutter analyze` from repo root and fix all errors; add `// ignore: <reason>` for any justified warnings
- [ ] T030 Manual smoke test on iOS Simulator per constitution §Development Workflow — verify: customer list, search, add customer, customer detail, add flock, audit history, audit detail, offline mode (airplane mode)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Requires Phase 1 complete — **BLOCKS all UI phases**
- **Phase 3 (US1)**: Requires Phase 2 complete
- **Phase 4 (US2)**: Requires T009–T012 (Phase 3) complete — extends Add Customer sheet
- **Phase 5 (US3)**: Requires Phase 2 complete — independent of US1/US2 screen files; depends on `provider.selectCustomer()` from T007
- **Phase 6 (US4)**: Requires T015 (detail screen scaffold) and T007 (selectCustomer loads audits)
- **Phase 7 (Polish)**: Requires all prior phases complete

### User Story Dependencies

- **US1**: Foundational complete → independent
- **US2**: US1 screen exists (add_customer_sheet.dart created) → adds validation on top
- **US3**: Foundational complete → independent (separate screen file)
- **US4**: T015 (detail screen exists) + T007 (audits loaded) → adds section to existing screen

### Parallel Opportunities

- T002 and T003 (Phase 1) run in parallel
- T004–T008 (Phase 2) are sequential — each builds on provider state
- T009 and T012 (Phase 3) — widget files, run in parallel
- T015 and T016 (Phase 5) — separate files, run in parallel
- T021 and T022 (Phase 6) — separate files, run in parallel
- T025, T026, T028 (Phase 7) — separate files, run in parallel

---

## Parallel Example: Phase 3 (US1)

```
# These two widget files have no interdependence — write simultaneously:
Task T009: lib/features/customers/widgets/customer_card.dart
Task T012: lib/features/customers/widgets/add_customer_sheet.dart

# Then wire them into the screen:
Task T010: customers_screen.dart (depends on T009)
Task T011: add customer sheet launch (depends on T012)
```

---

## Implementation Strategy

### MVP First (US1 + US2 only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (`CustomersProvider`)
3. Complete Phase 3: US1 — searchable customer list
4. Complete Phase 4: US2 — add customer with validation
5. **STOP and VALIDATE**: Customers tab fully usable
6. Demo: scrollable list, search, add customer

### Incremental Delivery

1. Setup + Foundational → provider works
2. US1 + US2 → Customers tab fully functional (MVP)
3. US3 → Customer Detail + Flock management
4. US4 → Audit History read-only
5. Polish → production-ready

---

## Notes

- No new packages required — `uuid` may need to be added to `pubspec.yaml` if not already present (check before T006)
- `AuditRepository.getAuditsByCustomer()` already exists — no changes needed
- `HatchDateUtils.flockAgeWeeks()` already tested — no new tests required per constitution
- All Supabase sync calls MUST be wrapped in try/catch with silent error swallowing per Constitution IX
- Temperature toggle is NOT required on this screen — no temperature values displayed
