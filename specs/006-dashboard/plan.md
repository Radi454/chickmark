# Implementation Plan: Phase 5 — Dashboard

**Branch**: `006-dashboard` | **Date**: 2026-04-18 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `specs/006-dashboard/spec.md`

## Summary

Replace the placeholder `DashboardScreen` with a fully functional analytics dashboard. The screen presents a sticky cascade filter (Customer → Flock → BMK Age) and six collapsible, scrollable sections — Hatch Analysis, Egg Breakout, Chick Quality, Egg Storage, Setter Optimizing, and Hatcher Optimizing — each showing averages, trend charts (fl_chart), benchmark comparisons, and photo grids sourced entirely from the local SQLite `audits` and `photos` tables.

## Technical Context

**Language/Version**: Dart 3 / Flutter SDK ≥ 3.10.7  
**Primary Dependencies**: provider ^6.1.2, sqflite ^2.3.3+1, fl_chart ^0.70.0, path_provider ^2.1.4  
**Storage**: SQLite via `sqflite` — single `audits` table plus `photos` table; offline-first  
**Testing**: `flutter test` — unit tests required for all new aggregation/calculation functions  
**Target Platform**: iOS (primary), macOS / Android (secondary)  
**Project Type**: Mobile app — feature screen  
**Performance Goals**: All six sections load within 2 s on-device; filter change refreshes within 1 s  
**Constraints**: Offline-capable (no network); °C/°F conversion on display only; no charts on audit-entry screens  
**Scale/Scope**: One new screen; one new provider; multiple query helpers added to `AuditRepository`

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Offline-First / SQLite source of truth | ✅ Pass | Dashboard reads from SQLite only; no Supabase calls |
| II. Audit Data Integrity | ✅ Pass | Dashboard is read-only; no writes |
| III. Test-First for Calculation Logic | ✅ Pass | Aggregation helpers (AVG, CV%, HOF, etc.) must have unit tests before implementation |
| IV. Simplicity Over Abstraction | ✅ Pass | One `DashboardProvider`; repository query methods; no new state libraries |
| V. Database Design Rules | ✅ Pass | Queries target existing `audits` and `photos` tables via composite key filter |
| VI. Navigation & Screen Structure | ✅ Pass | Dashboard is Tab 1 of the existing 6-tab bottom nav; no structural change |
| VII. Dashboard & Reporting Rules | ✅ Pass | Cascade filter, same-day + cumulative modes, charts only on Dashboard |
| VIII. Benchmark Data Rules | ✅ Pass | BMK values read from `bmk_breeds` and `bmk_egg_breakout` tables; never edited |
| IX. Integration Resilience | ✅ Pass | No BLE/OCR/Supabase dependency |
| X. Design System | ✅ Pass | Uses `AppColors.primary`, gradient `AppBar`, `#F65C00`/`#E24B4A`/`#3a9a5c` chart colors, °C/°F toggle via `AppProvider.tempUnit` |
| XI. Auth & Authorization | ✅ Pass | Dashboard content is filtered by `currentUser`; Customer role sees only their own data |
| XII. Calculations & Thresholds | ✅ Pass | Formulas from constitution §XII used for all KPIs; thresholds from `AppThresholds` |
| XIII. Troubleshooting Rules | ✅ Pass | 💡 icon shown next to egg breakout parameters that exceed BMK and Pasgar parameters > 20% |

**Constitution gate: PASS.** No violations; no Complexity Tracking entry required.

## Project Structure

### Documentation (this feature)

```text
specs/006-dashboard/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit-tasks — not created by /speckit-plan)
```

### Source Code (additions / changes)

```text
lib/
├── features/
│   └── dashboard/
│       ├── providers/
│       │   └── dashboard_provider.dart          # NEW — cascade filter state + all queries
│       └── screens/
│           ├── dashboard_screen.dart            # REPLACE placeholder
│           └── photo_fullscreen_screen.dart     # NEW — full-screen photo viewer
├── widgets/
│   ├── photo_grid.dart                          # NEW — reusable 3-col photo grid
│   └── chart_toggle.dart                        # NEW — Bar/Line/Circular switcher widget
└── data/
    └── repositories/
        └── audit_repository.dart                # EXTEND — add dashboard query methods

test/
└── features/
    └── dashboard/
        └── dashboard_aggregation_test.dart      # NEW — unit tests for aggregation helpers
```
