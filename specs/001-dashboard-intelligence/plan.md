# Implementation Plan: Dashboard Intelligence and Actionability

**Branch**: `001-dashboard-intelligence` | **Date**: 2026-07-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-dashboard-intelligence/spec.md`

## Summary

Make dashboard conclusions operationally safe, freshness-aware, explainable, actionable, historical, fast, bilingual, and accessible. The implementation keeps existing panel tables as field-entry sources of truth, introduces an additive batch analytics read model over those rows, adds synchronized dashboard actions, centralizes aggregation policy and aggregate derivation, and extends the current Provider/UI seams without replacing approved per-sector BMK-age comparison behavior.

## Technical Context

**Language/Version**: Dart 3.10.7 / Flutter SDK compatible with the current workspace
**Primary Dependencies**: Flutter, Provider, sqflite/sqflite_common_ffi_web, Supabase Flutter, fl_chart, uuid, existing custom localization
**Storage**: Offline-first SQLite plus mirrored Supabase PostgreSQL tables and object storage
**Testing**: flutter_test, sqflite_common_ffi repository tests, widget/semantics/localization tests, focused analyzer
**Target Platform**: iOS, Android, macOS, and Flutter web at the existing responsive breakpoints
**Project Type**: Multi-platform Flutter application
**Performance Goals**: One panel-table read per unique dashboard source table per filter; zero per-age re-query after the batch load; zero per-capture Govee reading query loop; stable in-place refresh
**Constraints**: Offline-first, additive migration-safe schema changes, child-before-parent deletion, best-effort cloud sync, professional Arabic/RTL, preserve dirty unrelated work, preserve equal-age averages and sibling-valid controls
**Scale/Scope**: Five dashboard stations, eleven configured sectors, seven Govee places, multi-customer/multi-hatchery auditor scope, synchronized actions, and representative multi-age histories

## Constitution Check

*GATE: Passed before research and again after design.*

- Current Flutter code was inspected before design and remains authoritative.
- `docs/LIVING_SPEC.md` is updated only to describe behavior implemented in this feature.
- The plan does not rely on deleted or historical specifications.
- Changes are additive and preserve existing offline, sync, comparison, localization, and photo behavior.
- Narrow tests are defined for each layer, followed by broader dashboard/database/sync/localization validation.
- Unrelated worktree changes are not reverted, staged, or committed.

## Phase 0 Research Decisions

See [research.md](research.md). All design questions are resolved; no clarification gate remains.

## Phase 1 Design

- [data-model.md](data-model.md) defines scope, metric observations, quality, historical comparison, findings, and synchronized actions.
- [contracts/dashboard-intelligence.md](contracts/dashboard-intelligence.md) defines repository/provider/UI contracts.
- [quickstart.md](quickstart.md) defines executable acceptance scenarios.

## Project Structure

### Documentation

```text
specs/001-dashboard-intelligence/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/dashboard-intelligence.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code

```text
lib/
├── data/
│   ├── database/{database_helper.dart,database_schema.dart,database_migrations.dart}
│   ├── models/{dashboard_action_model.dart,panel_sample_schema.dart}
│   ├── repositories/{dashboard_action_repository.dart,scope_comparison_repository.dart,panel_dashboard_repository.dart,govee_capture_repository.dart}
│   └── services/panel_aggregate_deriver.dart
├── features/dashboard/
│   ├── models/{dashboard_filter.dart,dashboard_intelligence_models.dart}
│   ├── providers/{dashboard_provider.dart,scope_comparison_provider.dart}
│   ├── scope/{scope_config.dart,scope_models.dart,scope_engine.dart}
│   ├── screens/dashboard_screen.dart
│   └── widgets/{dashboard_attention_section.dart,dashboard_quality_strip.dart,scope/*,sections/*}
├── l10n/app_localizations.dart
└── services/supabase/{startup_sync_service.dart,supabase_service.dart}

supabase/migrations/0004_dashboard_actions.sql

test/
├── data/{database,models,repositories,services}/
├── features/dashboard/
├── services/supabase/
└── core/l10n/
```

**Structure Decision**: Extend the current feature/repository/provider architecture. Metric observations are a derived in-memory read model loaded in batches from panel source tables; only user-owned action lifecycle data receives a new synchronized table.

## Implementation Strategy

1. Establish scope safety and batch read-model primitives.
2. Add explicit aggregation/quality/freshness and canonical derivation.
3. Add attention, history, and synchronized action lifecycle.
4. Integrate responsive bilingual accessible UI.
5. Update living documentation and validate focused-to-broad.

## Complexity Tracking

No constitution violations require justification. The new action table is necessary because action lifecycle is user-owned mutable data; calculated observations remain derived to avoid another source of truth.
