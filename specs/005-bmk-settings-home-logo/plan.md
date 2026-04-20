# Implementation Plan: Phase 4 — BMK Screen + Settings + Home Screen + Logo

**Branch**: `005-bmk-settings-home-logo` | **Date**: 2026-04-18 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `specs/005-bmk-settings-home-logo/spec.md`

## Summary

Implement the BMK benchmark reference screen (breed + egg breakout), the Settings screen (account display, preferences, sync, sign-out), a full Home/Audit History screen (stats, filters, audit list), and replace the placeholder "C" logo with the real ChickMark SVG line-art design. All data is read from SQLite. A DB migration (v2 → v3) is required to redesign the BMK tables with named metric columns. New providers (`BmkProvider`, `SettingsProvider`) are added following the existing feature-based architecture.

## Technical Context

**Language/Version**: Dart 3 / Flutter SDK ≥ 3.10.7  
**Primary Dependencies**: `provider ^6.1.2`, `sqflite ^2.3.3+1`, `shared_preferences ^2.3.2`, `connectivity_plus ^6.1.0` — all already in `pubspec.yaml`; no new packages required  
**Storage**: SQLite (source of truth) via `DatabaseHelper` + SharedPreferences for user preferences  
**Testing**: `flutter test` (unit tests required for any new calculation logic)  
**Target Platform**: iOS (primary), Android / macOS (secondary)  
**Project Type**: Mobile app  
**Performance Goals**: Home screen loads in < 2 seconds; BMK lookup in < 500ms  
**Constraints**: Offline-first; no network calls for BMK data or preferences; graceful degradation for Sync Now when offline  
**Scale/Scope**: Single-hatchery field tool; ~20 recent audits shown; ~6 breeds × ~30 age rows in BMK

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Offline-First | ✅ PASS | All BMK from SQLite; prefs from SharedPreferences; Sync Now degrades gracefully |
| II. Audit Data Integrity | ✅ N/A | No audit writes in this feature |
| III. Test-First for Calculations | ✅ PASS | No new calculation formulas introduced; HatchDateUtils.ageInWeeks used for age badge |
| IV. Simplicity Over Abstraction | ✅ PASS | Two new providers follow existing pattern; no new state management libraries |
| V. Database Design Rules | ✅ PASS | BMK tables redesigned; no change to audits table or its unique constraint |
| VI. Navigation | ✅ PASS | Home (tab 1), BMK (tab 5), Settings (tab 6) already wired in MainShell |
| VII. Dashboard Rules | ✅ N/A | No charts on data-entry screens |
| VIII. Benchmark Data Rules | ✅ PASS | BMK screen is read-only; breed + age filter matches spec |
| IX. Integration Resilience | ✅ PASS | Sync Now catches network errors; shows offline indicator |
| X. Design System | ✅ PASS | GradientAppBar on all screens; logo replaced with #F65C00 custom painter |
| XI. Auth Rules | ✅ PASS | Role badge displayed; sign-out with confirmation; clears cached token |
| XII. Calculations | ✅ N/A | No new formulas |
| XIII. Troubleshooting Rules | ✅ N/A | No troubleshooting triggers in this feature |

**Gate result**: ALL PASS — no violations, no Complexity Tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/005-bmk-settings-home-logo/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── checklists/
│   └── requirements.md  # Quality checklist
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT yet created)
```

### Source Code Changes

```text
lib/
├── app.dart                                     # Register BmkProvider + SettingsProvider
├── data/
│   ├── database/
│   │   ├── database_helper.dart                 # MODIFY — version 2→3, new DDL for bmk tables
│   │   └── seeds/
│   │       └── bmk_seeds.dart                   # MODIFY — full breed + egg breakout seed rows
│   └── models/
│       ├── bmk_breed_model.dart                 # REPLACE — add 6 metric fields
│       └── bmk_egg_breakout_model.dart          # REPLACE — add 15 parameter fields
├── features/
│   ├── bmk/
│   │   ├── providers/
│   │   │   └── bmk_provider.dart               # NEW — loads + filters BMK data from SQLite
│   │   └── screens/
│   │       └── bmk_screen.dart                 # REPLACE stub — full implementation
│   ├── home/
│   │   └── screens/
│   │       └── home_screen.dart                # REPLACE stub — stats + actions + audit list
│   └── settings/
│       ├── providers/
│       │   └── settings_provider.dart          # NEW — SharedPreferences-backed preferences
│       └── screens/
│           └── settings_screen.dart            # REPLACE stub — full implementation
└── widgets/
    └── chick_mark_logo.dart                    # MODIFY — replace _buildFallbackLogo with CustomPainter
```

**Structure Decision**: Single-project Flutter app using existing `lib/features/<feature>/` pattern. All new code follows the existing feature-module structure with `screens/`, `providers/`, and `widgets/` sub-directories.

## Complexity Tracking

> No constitution violations — table not required.
