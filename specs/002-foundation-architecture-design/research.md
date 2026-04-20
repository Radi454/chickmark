# Research: Phase 1 — Foundation, Architecture & Design System

**Date**: 2026-04-18
**Branch**: `002-foundation-architecture-design`

All technical decisions for this phase were fully specified by the product owner.
No ambiguous unknowns required external research. This document records the
rationale for each decision and alternatives considered.

---

## Decision 1: SQLite via sqflite as source of truth

**Decision**: Use `sqflite ^2.3.3+1` for all local persistence. SQLite is always
written first; Supabase is synced in the background.

**Rationale**: The app MUST work fully offline in hatchery facilities with
unreliable connectivity. sqflite is the Flutter-ecosystem standard for embedded
SQL, has broad iOS/Android support, and provides raw SQL access without the
complexity of an ORM.

**Alternatives considered**:
- `drift` (typed ORM over sqflite) — rejected; adds abstraction layer prohibited
  by Constitution §IV and §V.
- `isar` — rejected; NoSQL schema incompatible with relational audit composite
  keys; unfamiliar to most Flutter developers.
- `hive` — rejected; key-value store unsuitable for complex relational queries
  needed by Dashboard filters.

---

## Decision 2: Provider for state management

**Decision**: Use `provider ^6.1.2`. `ChangeNotifier`-based providers live in
`lib/providers/` and per-feature `providers/` subdirectories.

**Rationale**: Mandated by Constitution §IV. Provider is lightweight, well-
documented, and sufficient for the app's complexity. Avoids speculative overhead
of Bloc/Riverpod.

**Alternatives considered**: Bloc, Riverpod, GetX — all rejected by constitution.

---

## Decision 3: Supabase for cloud auth and sync

**Decision**: `supabase_flutter` handles sign-up, sign-in, email verification,
and password reset. Background sync writes completed audit rows to Supabase.
All Supabase calls are wrapped in try/catch; errors are logged silently.

**Rationale**: Supabase provides managed Postgres + Auth + RLS out of the box,
reducing backend build time. Constitutionally required to never block the UI.

**Offline auth approach**: On first successful login, the Supabase access token,
expiry timestamp, and user record are written to the `users` SQLite table. On
subsequent launches, the app checks for a valid cached token (not expired >30 days)
before attempting a Supabase call. If valid and offline, login proceeds immediately.

**Token storage**: Stored in SQLite `users` table (not `shared_preferences`) so
it participates in the same atomic transaction as the user record.

---

## Decision 4: Temperature storage and display

**Decision**: All temperatures stored in °F in SQLite (except `es_shell_temp`
which is stored in °C per industry convention). Conversion to °C happens only
in display widgets via `TempConverter`. The `[°C/°F]` toggle preference is held
in `AppProvider` and persisted in `shared_preferences`.

**Rationale**: Constitutionally mandated (§X, §XII). Shell temp is the single
exception because its alert thresholds (19–21°C) are defined in Celsius by
Aviagen/Cobb standards; storing it in °C avoids precision loss from round-trips.

---

## Decision 5: Single denormalized `audits` table

**Decision**: One wide table with nullable columns for each audit type's fields.
Composite key uniqueness is enforced by a UNIQUE constraint on
`(customer_id, flock_id, date, audit_type, setter_id, hatcher_id)`.
Setter/Hatcher Optimizing uses `(customer_id, setter_id/hatcher_id, date)`
with `flock_id = NULL`.

**Rationale**: Constitutionally mandated (§V). Eliminates join complexity,
simplifies offline sync (one table to push), and matches the auditor's mental
model of one session = one row.

**Alternatives considered**: Separate table per audit type — rejected; multiplies
sync complexity and violates §V.

---

## Decision 6: Graceful degradation pattern for integrations

**Decision**: Each optional integration (`GoveeService`, `OcrService`,
`SupabaseService`) follows the same pattern:
1. Capability check on init (Bluetooth available? Camera available? Network reachable?)
2. If unavailable: set an `isAvailable` flag to `false`, return no-op stubs.
3. All call sites guard with `if (service.isAvailable)` before calling.
4. No `throw` propagates to UI from these services.

**Rationale**: Constitutionally mandated (§IX). Field devices vary widely; a crash
from a missing Bluetooth radio is unacceptable.

---

## Decision 7: Calculation utilities as pure functions

**Decision**: All formulas (CV%, uniformity, Pasgar score, hatchability, HOF,
BMK age, flock age) are implemented as static methods in `CalculationUtils` and
`DateUtils` in `lib/core/utils/`. They take plain numbers/dates and return numbers.
No Flutter or Provider dependencies.

**Rationale**: Pure functions are trivially unit-testable (Constitution §III).
Isolating calculations from UI prevents any future mixing of data entry with
live KPI display (Constitution §VII).

**Unit test strategy**: Each method gets a test group with: primary formula case,
zero input, null-equivalent input, and at least one known reference value from
industry documentation.

---

## Decision 8: Auth UI — password strength indicator

**Decision**: Implemented as a row of 3 coloured bars that update on each keystroke:
- 1 bar (red): length < 8 or no number → Weak
- 2 bars (amber): length ≥ 8 + 1 number but no uppercase or special char → Medium
- 3 bars (green): length ≥ 8 + 1 number + uppercase or special char → Strong

**Rationale**: Required by spec (FR-014). Live feedback prevents failed submissions
and guides users to the minimum policy (8 chars + 1 number) before they tap submit.

---

## Decision 9: BMK seed data delivery

**Decision**: BMK values and troubleshooting content are seeded from Dart constant
maps defined in `lib/data/database/seeds/`. Placeholder rows with `0.0` values
are acceptable for Phase 1; the product owner will supply real values before Phase 2.

**Rationale**: The spec assumption states seed data will be provided separately.
Using Dart constants (not external JSON files) keeps seeding atomic with DB creation
and avoids asset-loading edge cases on first launch.

---

## Decision 10: `supabase_flutter` package not yet in pubspec

**Decision**: Add `supabase_flutter: ^2.5.0` (latest stable) to `pubspec.yaml`
during Phase 1 implementation. The anon key and project URL will be provided as
compile-time constants in a `lib/core/constants/supabase_config.dart` file that is
gitignored.

**Rationale**: Keeps credentials out of version control (Constitution §XII quality
gate). A `.env`-style approach is not idiomatic in Flutter; compile-time constants
with gitignore is the standard Flutter Supabase pattern.
