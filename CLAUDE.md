# hatchaudit Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-18

## Active Technologies
- Dart 3 / Flutter SDK ^3.10.7 + provider ^6.1.2, sqflite ^2.3.3+1, supabase_flutter, uuid (for ID generation) (003-customers-flocks-screen)
- SQLite via `sqflite` (source of truth) + Supabase background sync (003-customers-flocks-screen)
- Dart 3 / Flutter SDK ^3.10.7 + provider ^6.1.2, sqflite ^2.3.3+1, supabase_flutter ^2.5.0, flutter_blue_plus ^1.35.3, image_picker ^1.1.2, path_provider ^2.1.4, uuid ^4.4.2 (004-audit-entry-screens)
- Dart 3 / Flutter SDK ≥ 3.10.7 + `provider ^6.1.2`, `sqflite ^2.3.3+1`, `shared_preferences ^2.3.2`, `connectivity_plus ^6.1.0` — all already in `pubspec.yaml`; no new packages required (005-bmk-settings-home-logo)
- SQLite (source of truth) via `DatabaseHelper` + SharedPreferences for user preferences (005-bmk-settings-home-logo)
- Dart 3 / Flutter SDK ≥ 3.10.7 + provider ^6.1.2, sqflite ^2.3.3+1, fl_chart ^0.70.0, path_provider ^2.1.4 (006-dashboard)
- SQLite via `sqflite` — single `audits` table plus `photos` table; offline-firs (006-dashboard)

- Dart 3 / Flutter SDK ^3.10.7 + provider ^6.1.2, sqflite ^2.3.3+1, supabase_flutter (to be (002-foundation-architecture-design)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for Dart 3 / Flutter SDK ^3.10.7

## Code Style

Dart 3 / Flutter SDK ^3.10.7: Follow standard conventions

## Recent Changes
- 006-dashboard: Added Dart 3 / Flutter SDK ≥ 3.10.7 + provider ^6.1.2, sqflite ^2.3.3+1, fl_chart ^0.70.0, path_provider ^2.1.4
- 005-bmk-settings-home-logo: Added Dart 3 / Flutter SDK ≥ 3.10.7 + `provider ^6.1.2`, `sqflite ^2.3.3+1`, `shared_preferences ^2.3.2`, `connectivity_plus ^6.1.0` — all already in `pubspec.yaml`; no new packages required
- 004-audit-entry-screens: Added Dart 3 / Flutter SDK ^3.10.7 + provider ^6.1.2, sqflite ^2.3.3+1, supabase_flutter ^2.5.0, flutter_blue_plus ^1.35.3, image_picker ^1.1.2, path_provider ^2.1.4, uuid ^4.4.2


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
