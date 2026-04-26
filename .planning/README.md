# ChickMark — Execution Roadmap Index

Audited: April 24 2026 | Branch: `006-dashboard` | DB version: 11

## How to Use These Files

Each phase is a standalone file. Give one phase at a time to your AI agent.
**Never combine phases in one prompt.**

Before starting any task:
1. Tell the agent to read all files listed under "Files to modify"
2. Ask for a full diff before committing anything
3. Run `dart analyze` after every task
4. Run the manual test listed in the task
5. Commit one task at a time — never batch

---

## Phase Files

| File | Phase | Priority | Est. Time |
|---|---|---|---|
| [phase-0-security.md](phase-0-security.md) | Security & Critical Fixes | MANDATORY FIRST | ~6h |
| [phase-1-stabilization.md](phase-1-stabilization.md) | Fix Broken/Incomplete Features | High | ~11h |
| [phase-2-ux-completion.md](phase-2-ux-completion.md) | Core UX Completion | High | ~9h |
| [phase-3-data-performance.md](phase-3-data-performance.md) | Data Integrity & Performance | Medium | ~5h |
| [phase-4-export.md](phase-4-export.md) | Export & Reporting | Medium | ~6h |
| [phase-5-advanced.md](phase-5-advanced.md) | Advanced Features | Lower | ~11h |
| [phase-6-optional.md](phase-6-optional.md) | Optional / Deferred | Lowest | ~3h |
| [testing-strategy.md](testing-strategy.md) | Testing Plan | Run throughout | ~8h |
| [ai-agent-rules.md](ai-agent-rules.md) | AI Agent Instructions | Read before any task | — |

---

## Critical Finding (Read First)

`_buildWhere()` in `lib/data/repositories/audit_repository.dart` uses **string interpolation** for SQL WHERE clauses:
```dart
parts.add("customerId = '${filter.customerId}'");  // SQL INJECTION
parts.add("flockId = '${filter.flockId}'");         // SQL INJECTION
```
**Phase 0 Task 0.1 must be completed before any other code changes.**

---

## App Overview (for agent context)

- **Framework**: Flutter (Dart 3), Material 3
- **State management**: Provider (`ChangeNotifier`)
- **Local DB**: SQLite via `sqflite`, version 11, file: `hatchaudit.db`
- **Cloud**: Supabase (sync only — SQLite is source of truth)
- **Auth**: Supabase auth + local offline fallback
- **Key providers**: `AppProvider`, `AuthProvider`, `CustomersProvider`, `AuditProvider`, `DashboardProvider`, `BmkProvider`, `SettingsProvider`, `TemperatureRhProvider`
- **Audit types**: Chick Quality, Hatch Analysis, Egg Storage, Setter Optimizing, Hatcher Optimizing

## Project Structure

```
lib/
├── core/
│   ├── constants/       app_colors, app_sizes, app_strings, app_thresholds, supabase_config
│   ├── theme/           app_theme, app_text_styles, gradient_app_bar
│   └── utils/           calculation_utils, date_utils, temp_converter
├── data/
│   ├── database/        database_helper.dart  ← DB schema + migrations
│   │   └── seeds/       bmk_seeds, dummy_data_seeds
│   ├── models/          audit_model (165+ fields), customer, flock, user, photo, etc.
│   └── repositories/    audit, customer, flock, hatchery, photo, user, bmk, troubleshooting
├── features/
│   ├── auth/            login, register, pending_approval screens + auth_provider
│   ├── audits/          5 audit type screens + tabs + audit_provider
│   ├── customers/       customers list, detail, audit detail screens
│   ├── dashboard/       dashboard screen + provider + chart widgets + section stubs
│   ├── home/            home_screen
│   ├── bmk/             bmk_screen + bmk_provider
│   ├── settings/        settings_screen + settings_provider
│   ├── sync/            startup_sync_screen
│   └── temperature/     temperature screen + govee BLE provider
├── providers/           app_provider, customers_provider
├── services/
│   ├── govee/           govee_service (BLE)
│   ├── ocr/             ocr_service (stub — not implemented)
│   ├── photo/           photo_service
│   └── supabase/        supabase_service, startup_sync_service
└── widgets/             shared widgets (chart_toggle, photo_grid, section_card, etc.)
```
