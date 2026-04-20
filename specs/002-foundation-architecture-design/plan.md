# Implementation Plan: Phase 1 — Foundation, Architecture & Design System

**Branch**: `002-foundation-architecture-design` | **Date**: 2026-04-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/002-foundation-architecture-design/spec.md`

## Summary

Establish the complete HatchAudit app foundation: Flutter project structure, AppTheme
design system, ChickMark branding widget, 6-tab bottom navigation shell, Supabase-backed
auth flow (Login / Register / Pending Approval screens), offline token caching in SQLite,
full 8-table SQLite schema with versioned migrations, and gracefully-degrading service
stubs for Govee BLE and Apple Vision OCR. No audit data-entry screens are built in this
phase — tab content screens are scaffolds. All calculation utility functions are
implemented and unit-tested before any UI that depends on them.

## Technical Context

**Language/Version**: Dart 3 / Flutter SDK ^3.10.7
**Primary Dependencies**: provider ^6.1.2, sqflite ^2.3.3+1, supabase_flutter (to be
added), flutter_blue_plus ^1.35.3, image_picker ^1.1.2, connectivity_plus ^6.1.0,
uuid ^4.4.2, path_provider ^2.1.4, intl ^0.19.0, shared_preferences ^2.3.2
**Storage**: SQLite (sqflite) — source of truth; Supabase Postgres for cloud sync
**Testing**: flutter_test (built-in); unit tests for all calculation utilities
**Target Platform**: iOS 15+ primary; Android / Web / macOS planned
**Project Type**: Offline-first mobile app
**Performance Goals**: Login flow ≤ 10 s on device with network; offline login ≤ 2 s;
tab switch ≤ 100 ms
**Constraints**: Fully functional offline; Supabase sync never blocks UI; Govee BLE and
Apple Vision OCR degrade gracefully; no hardcoded credentials; `flutter analyze`
passes zero errors
**Scale/Scope**: ~50 screens total across all phases; Phase 1 delivers ~10 screens
(3 auth + 6 tab scaffolds + shared widgets); single-developer team

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Offline-First, SQLite as Source of Truth | ✅ PASS | SQLite initialised first; Supabase is background-only |
| II. Audit Data Integrity | ✅ PASS | Single denormalized `audits` table; composite key enforced; flock age computed at runtime |
| III. Test-First for Calculation Logic | ✅ PASS | All calc utilities (CV%, uniformity, Pasgar, hatchability, HOF, BMK age, flock age) will have unit tests before any UI is built |
| IV. Simplicity Over Abstraction | ✅ PASS | Provider pattern; no ORM; no repository abstraction layer in this phase |
| V. Database Design Rules | ✅ PASS | Single denormalized `audits` table; Setter/Hatcher Optimizing key uses machine_id, no flock |
| VI. Navigation and Screen Structure | ✅ PASS | 6-tab bottom nav; 5 audit type cards defined (scaffolded); Egg Breakout is sector inside Hatch Analysis |
| VII. Dashboard and Reporting Rules | ✅ PASS | Dashboard is scaffold only in Phase 1; no live KPIs anywhere |
| VIII. Benchmark Data Rules | ✅ PASS | bmk_breeds + bmk_egg_breakout seeded as read-only; BMK Age formula implemented in utils |
| IX. Integration Resilience | ✅ PASS | Govee BLE, Apple Vision OCR, Supabase all implemented with graceful-degradation stubs |
| X. Design System | ✅ PASS | AppTheme centralises all tokens; temp toggle, green tab, card/button radii all implemented |
| XI. Auth & Authorization Rules | ✅ PASS | 3 roles; Admin approval; offline cached token; 30-day expiry; password policy |
| XII. Calculations, Thresholds & Alerts | ✅ PASS | All calc utilities implemented and tested in Phase 1; threshold constants defined |
| XIII. Troubleshooting Rules | ✅ PASS | troubleshooting table seeded; 💡 widget stub created (activated in Phase 2+) |

**No constitution violations. Complexity Tracking table not required.**

## Project Structure

### Documentation (this feature)

```text
specs/002-foundation-architecture-design/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (UI contracts)
│   └── ui-contracts.md
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
lib/
  main.dart                          # Entry point; initialises DB, providers, runs app
  app.dart                           # MaterialApp + router (auth guard)
  core/
    constants/
      app_colors.dart                # All colour constants (#F65C00, #f0f2f5, etc.)
      app_sizes.dart                 # Border radii, padding, spacing constants
      app_strings.dart               # Static UI strings / labels
    theme/
      app_theme.dart                 # ThemeData factory; card/button decoration builders
      text_styles.dart               # Named TextStyle constants
    utils/
      temp_converter.dart            # °F ↔ °C conversion (display only)
      calculation_utils.dart         # CV%, uniformity, Pasgar, hatchability, HOF
      date_utils.dart                # Flock age (weeks) from entry_date; BMK age
  data/
    database/
      database_helper.dart           # sqflite; create/migrate all 8 tables; seed BMK
    models/
      user_model.dart
      customer_model.dart
      flock_model.dart
      audit_model.dart
      bmk_breed_model.dart
      bmk_egg_breakout_model.dart
      troubleshooting_model.dart
      photo_model.dart
    repositories/
      audit_repository.dart          # CRUD for audits table (SQLite)
      customer_repository.dart
      flock_repository.dart
      user_repository.dart           # Cached user / token storage
  features/
    auth/
      screens/
        login_screen.dart
        register_screen.dart
        pending_approval_screen.dart
      widgets/
        password_strength_indicator.dart
      providers/
        auth_provider.dart
    home/
      screens/home_screen.dart       # Scaffold placeholder
    dashboard/
      screens/dashboard_screen.dart  # Scaffold placeholder
    customers/
      screens/customers_screen.dart  # Scaffold placeholder
    audits/
      screens/audits_screen.dart     # Scaffold placeholder
    bmk/
      screens/bmk_screen.dart        # Scaffold placeholder
    settings/
      screens/settings_screen.dart   # Scaffold placeholder
  providers/
    app_provider.dart                # Global state (current user, temp unit pref)
  widgets/
    chick_mark_logo.dart             # Logo + wordmark + tagline widget
    status_badge.dart                # Completed / active badge
    temp_toggle.dart                 # [°C / °F] toggle button
    section_card.dart                # Reusable card with standard decoration
    troubleshooting_icon.dart        # 💡 stub widget (activated Phase 2+)
  services/
    supabase/
      supabase_service.dart          # Auth calls; background sync stub
    govee/
      govee_service.dart             # BLE scan + degrade stub
    ocr/
      ocr_service.dart               # Apple Vision OCR + degrade stub

test/
  utils/
    calculation_utils_test.dart      # CV%, uniformity, Pasgar, hatchability, HOF
    temp_converter_test.dart
    date_utils_test.dart             # Flock age, BMK age
```

**Structure Decision**: Single Flutter project (Option 3 variant — mobile-first,
no separate API project). All source lives under `lib/`; tests under `test/`.
