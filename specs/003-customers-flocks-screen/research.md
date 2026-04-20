# Research: Phase 2 — Customers & Flocks Screen

**Branch**: `003-customers-flocks-screen` | **Date**: 2026-04-18

## Findings

---

### Decision 1: State management for Customers & Flocks

**Decision**: Introduce a dedicated `CustomersProvider` in `lib/providers/customers_provider.dart` that holds the customer list, selected customer, and flock list for the selected customer. `AppProvider` remains scoped to app-wide state (current user, temp unit).

**Rationale**: The customers and flocks data is tab-scoped and shouldn't pollute `AppProvider`. A focused provider keeps `ChangeNotifier` rebuilds minimal. This mirrors the pattern used by `AuthProvider` for auth state.

**Alternatives considered**:
- Extend `AppProvider` — rejected because it would cause unrelated widgets to rebuild on customer changes.
- Use `FutureBuilder` without a provider — rejected because it cannot hold mutable state (selected flock dropdown value, search query).

---

### Decision 2: Search filtering strategy

**Decision**: Filter the customer list in-memory inside `CustomersProvider` using a `String searchQuery` field. `CustomersProvider.filteredCustomers` returns the derived filtered list. The full list is always loaded from SQLite on tab entry; filtering never triggers a new DB query.

**Rationale**: Customer counts are small (< 500 per constitution scale assumption). In-memory filtering is instantaneous and avoids query latency per keystroke.

**Alternatives considered**:
- SQL `LIKE` query per keystroke — rejected because it adds unnecessary DB round-trips and makes debouncing more complex.

---

### Decision 3: Flock count badge on customer card

**Decision**: The flock count is fetched once per customer load by querying `FlockRepository.getFlocksByCustomer()` for each customer and storing counts in a `Map<String, int>` inside `CustomersProvider`. Count is not stored on the `customers` table.

**Rationale**: Keeping a denormalized `flockCount` column on the customer row would require updating it on every flock insert/delete — fragile. A single batch load of all flocks at screen load is simpler and offline-safe.

**Alternatives considered**:
- Storing `flockCount` in `customers` table — rejected (denormalization risk per constitution principle V: single source of truth).
- SQL `COUNT` subquery per card render — rejected (too many individual queries for large lists).

---

### Decision 4: Audit history read-only navigation

**Decision**: Tapping an audit card in the Customer Detail screen navigates to a new `AuditDetailScreen` using `Navigator.push`. The screen receives an `AuditModel` argument and renders all fields in read-only `Text` widgets with no edit controls. This screen is a new, lightweight widget; it is NOT the same as the (future) audit edit flow.

**Rationale**: The spec explicitly requires a read-only view. Reusing a future edit screen with read-only mode toggling would couple this feature to an unbuilt one. A dedicated read-only screen is simpler and decoupled.

**Alternatives considered**:
- Bottom sheet read-only summary — rejected because audit records have many fields; a full screen is more readable.
- Show read-only inline expanded card — rejected because the card list would become too long.

---

### Decision 5: Add Flock UX pattern

**Decision**: Tapping [+ Add Flock] opens a `showModalBottomSheet` with a form containing: Flock ID (text field), Breed (dropdown), Entry Date (date picker via `showDatePicker`). On Save, `FlockRepository.insertFlock()` is called and the flock list in `CustomersProvider` is refreshed. The flock dropdown on the Customer Detail screen auto-selects the newly added flock.

**Rationale**: Consistent with the Add Customer bottom sheet pattern. Keeps modal UI lightweight.

**Alternatives considered**:
- Separate full-screen route for Add Flock — rejected (overkill for a 3-field form).

---

### Decision 6: Supabase background sync

**Decision**: After each SQLite write (insert customer, insert flock), a fire-and-forget async call is made to `SupabaseService` targeting the `customers` and `flocks` Supabase tables respectively. Errors are caught and swallowed silently per Constitution Principle IX. No retry queue is introduced in this phase.

**Rationale**: Constitution I mandates offline-first and silent sync failures. A retry queue is acceptable future scope but not required for MVP.

**Alternatives considered**:
- Sync via a background isolate — deferred to future phase.
- Batch sync on app foreground — rejected; simpler to sync immediately after write.

---

### Decision 7: Flock age calculation

**Decision**: Use the existing `HatchDateUtils.flockAgeWeeks(entryDate)` utility already in `lib/core/utils/date_utils.dart`. Display as `floor((today - entryDate).inDays / 7)` weeks. Negative values display as 0 (already handled by `floor` clamped to 0 in the widget layer). No changes to `HatchDateUtils` are needed.

**Rationale**: The utility exists and is correct per the spec formula. Constitution Principle III requires unit tests for calculation logic; `HatchDateUtils` already has this coverage from the foundation phase.

---

### Decision 8: Breed enum representation

**Decision**: Breeds are stored as plain strings in SQLite (`breed TEXT` column, already defined in schema). The UI presents a `DropdownButton<String>` with the six values: `['Ross308', 'Arbo', 'Avian', 'Cobb500', 'Hubbard', 'IR']`. No Dart enum is introduced — keeps the model simple and forward-compatible.

**Rationale**: SQLite stores strings; mapping to a Dart enum adds a conversion layer with no benefit for this screen. Constitution Principle IV (simplicity over abstraction) applies.

---

### Constitution Compliance Pre-Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Offline-First | ✅ | SQLite writes first; Supabase is fire-and-forget |
| II. Audit Data Integrity | ✅ | Flock age not manually entered; calculated from `entryDate` |
| III. Test-First Calculations | ✅ | `HatchDateUtils` already tested; no new formulas introduced |
| IV. Simplicity | ✅ | New provider, no new abstraction layers |
| V. Database Design | ⚠️ | `CustomerRepository`/`FlockRepository` already exist — pre-existing deviation, not introduced by this feature |
| VI. Navigation | ✅ | Customers tab already defined in bottom nav |
| X. Design System | ✅ | Orange gradient header, #f0f2f5 background, 14px card radius |
| XI. Auth & Roles | ✅ | Screen is accessible to Admin and Auditor; Customer role read-only (future) |
