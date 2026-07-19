# Tasks: Dashboard Intelligence and Actionability

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/dashboard-intelligence.md](contracts/dashboard-intelligence.md)

## Phase 1: Setup

- [x] T001 Add dashboard-intelligence database migration and remote schema migration in `lib/data/database/database_helper.dart`, `lib/data/database/database_schema.dart`, `lib/data/database/database_migrations.dart`, and `supabase/migrations/0004_dashboard_actions.sql`
- [x] T002 [P] Add shared dashboard intelligence and action models in `lib/features/dashboard/models/dashboard_intelligence_models.dart` and `lib/data/models/dashboard_action_model.dart`
- [x] T003 [P] Add baseline model/schema tests in `test/features/dashboard/dashboard_intelligence_models_test.dart` and `test/data/models/dashboard_action_model_test.dart`

## Phase 2: Foundational

- [x] T004 Extend `DashboardFilter` with hatchery and operational/portfolio scope in `lib/features/dashboard/models/dashboard_filter.dart`
- [x] T005 Add explicit metric aggregation policies and generic numerator/denominator support in `lib/features/dashboard/scope/scope_config.dart`, `lib/features/dashboard/scope/scope_models.dart`, and `lib/features/dashboard/scope/scope_engine.dart`
- [x] T006 Add aggregation-policy regression tests in `test/features/dashboard/scope_engine_test.dart`
- [x] T007 Add canonical panel aggregate derivation in `lib/data/services/panel_aggregate_deriver.dart` and invoke it from `lib/data/repositories/panel_sample_repository.dart`
- [x] T008 Add canonical derivation tests in `test/data/services/panel_aggregate_deriver_test.dart` and `test/data/repositories/panel_sample_repository_test.dart`
- [x] T009 Implement synchronized dashboard action persistence in `lib/data/repositories/dashboard_action_repository.dart` and extend `lib/data/repositories/sync_tombstone_repository.dart`
- [x] T010 Add dashboard action repository/database migration tests in `test/data/repositories/dashboard_action_repository_test.dart` and `test/data/database/database_helper_migration_test.dart`
- [x] T011 Extend Supabase push/pull/conflict wiring for dashboard actions in `lib/services/supabase/startup_sync_service.dart` and `lib/services/supabase/supabase_service.dart`
- [x] T012 Add dashboard action sync tests in `test/services/supabase/startup_sync_service_test.dart` and `test/services/supabase/startup_sync_incoming_test.dart`

## Phase 3: User Story 1 - Trust the Selected Operational Scope

- [x] T013 [US1] Add customer-to-hatchery cascade state and operational-scope guard in `lib/features/dashboard/providers/dashboard_provider.dart`
- [x] T014 [US1] Apply hatchery scope to every panel/scope/Govee dashboard query in `lib/data/repositories/scope_comparison_repository.dart`, `lib/data/repositories/panel_dashboard_repository.dart`, and `lib/features/dashboard/providers/dashboard_provider.dart`
- [x] T015 [US1] Implement Customer-Hatchery-Flock filters and portfolio summary guard in `lib/features/dashboard/screens/dashboard_screen.dart` and `lib/features/dashboard/widgets/dashboard_portfolio_summary.dart`
- [x] T016 [US1] Add scope-isolation repository/provider/widget tests in `test/data/repositories/scope_comparison_repository_test.dart`, `test/features/dashboard/scope_comparison_provider_test.dart`, and `test/features/dashboard/dashboard_screen_test.dart`

## Phase 4: User Story 2 - Freshness, Coverage, and Calculation Confidence

- [x] T017 [US2] Batch-load normalized observations, periods, quality, and history by unique source table in `lib/data/repositories/scope_comparison_repository.dart`
- [x] T018 [US2] Consume the batch bundle and cached age slices in `lib/features/dashboard/providers/scope_comparison_provider.dart`
- [x] T019 [US2] Batch Govee summaries and implement timestamp-based freshness/status in `lib/data/repositories/govee_capture_repository.dart`, `lib/features/dashboard/models/govee_capture_summary.dart`, and `lib/features/dashboard/widgets/scope/govee_triage_builder.dart`
- [x] T020 [US2] Add quality/freshness/coverage presentation in `lib/features/dashboard/widgets/dashboard_quality_strip.dart`, `lib/features/dashboard/widgets/scope/scope_sector_widget.dart`, and `lib/features/dashboard/widgets/sections/govee_environmental_readings_section.dart`
- [x] T021 [US2] Add per-section recoverable error state in `lib/features/dashboard/providers/dashboard_provider.dart`, `lib/features/dashboard/providers/scope_comparison_provider.dart`, and dashboard widgets
- [x] T022 [US2] Add batch-query, freshness, quality, and failure tests in `test/data/repositories/scope_comparison_repository_test.dart`, `test/data/repositories/govee_capture_repository_test.dart`, `test/features/dashboard/govee_triage_builder_test.dart`, and `test/features/dashboard/scope_comparison_provider_test.dart`

## Phase 5: User Story 3 - Consolidated Findings and Owned Actions

- [x] T023 [US3] Derive ranked cross-station findings with stable keys and source traces in `lib/features/dashboard/providers/scope_comparison_provider.dart` and `lib/features/dashboard/widgets/scope/scope_triage_builder.dart`
- [x] T024 [US3] Add the operational attention summary and source navigation in `lib/features/dashboard/widgets/dashboard_attention_section.dart` and `lib/features/dashboard/screens/dashboard_screen.dart`
- [x] T025 [US3] Integrate action lifecycle state in `lib/features/dashboard/providers/dashboard_provider.dart`
- [x] T026 [US3] Build create/assign/progress/resolve/reopen action UI in `lib/features/dashboard/widgets/dashboard_action_sheet.dart` and `lib/features/dashboard/widgets/dashboard_attention_section.dart`
- [x] T027 [US3] Add finding/action provider and widget tests in `test/features/dashboard/dashboard_attention_section_test.dart` and `test/features/dashboard/dashboard_action_sheet_test.dart`

## Phase 6: User Story 4 - Latest-versus-Previous Analysis

- [x] T028 [US4] Derive compatible latest/previous metric comparisons and lifecycle classifications from cached observations in `lib/data/repositories/scope_comparison_repository.dart` and `lib/features/dashboard/providers/scope_comparison_provider.dart`
- [x] T029 [US4] Surface latest/previous values, deltas, equal-age labels, persistence, and recurrence in dashboard attention/sector widgets
- [x] T030 [US4] Add historical classification and equal-age disclosure tests in `test/features/dashboard/scope_comparison_provider_test.dart` and `test/features/dashboard/scope_cumulative_view_test.dart`

## Phase 7: User Story 5 - Fast Responsive Bilingual Accessible Dashboard

- [x] T031 [US5] Remove desktop comparison dead space and add responsive station/attention layouts in `lib/features/dashboard/widgets/scope/scope_matrix_table.dart`, `lib/features/dashboard/widgets/scope/scope_cumulative_view.dart`, and dashboard widgets
- [x] T032 [US5] Add semantics and non-color state cues to dashboard filters, collapse headers, chart/table controls, findings, and actions
- [x] T033 [US5] Add professional Arabic translations and dynamic patterns in `lib/l10n/app_localizations.dart`
- [x] T034 [US5] Add responsive, semantics, and localization tests in `test/features/dashboard/dashboard_screen_test.dart`, `test/features/dashboard/dashboard_attention_section_test.dart`, and `test/core/l10n`

## Phase 8: Polish and Cross-Cutting Validation

- [x] T035 Update implemented behavior and data rules in `docs/LIVING_SPEC.md`, `docs/DATABASE_SPEC.md`, and `docs/FORMULA_REGISTRY.md`
- [x] T036 Run focused formatter/analyzer/tests for database, repositories, dashboard, sync, localization, and widgets
- [x] T037 Run broader Flutter tests and browser verification on `http://127.0.0.1:57863`
- [x] T038 Reconcile task completion, run `git diff --check`, and record risks/assumptions in this feature handoff

## Dependencies

- Phase 2 depends on Phase 1.
- US1 depends on the scope/model foundations in Phase 2.
- US2 depends on US1 scope safety and the aggregation model.
- US3 depends on US2 observations/quality plus action persistence.
- US4 depends on the US2 batch observation cache and enriches US3 findings.
- US5 depends on the final UI/data contracts from US1-US4.
- Polish depends on all user stories.

## Parallel Opportunities

- T002 and T003 can proceed independently after T001's schema contract is known.
- Model tests, localization catalog work, and remote SQL can be developed separately when they do not touch shared providers.
- Repository tests can be added alongside widget tests after each story contract is stable.

## Independent Test Criteria

- **US1**: Duplicate labels across hatcheries never mix; portfolio mode has no detailed triage.
- **US2**: Stale/same-day Govee, partial coverage, aggregation basis, and subsection errors are visible and correct.
- **US3**: A consolidated finding opens its source and an action completes an offline-to-synced lifecycle.
- **US4**: New/persistent/improving/worsening/resolved classifications match fixtures and equal-age behavior remains unchanged.
- **US5**: Phone/desktop English/Arabic layouts, semantics, and controls pass without overflow or untranslated static text.

## Implementation Strategy

Deliver in priority order. US1 is the safety MVP. US2 makes analysis trustworthy. US3/US4 turn it into an operating workflow. US5 completes usability and accessibility. Tests are required in every phase because persistence, sync, and aggregation changes are high risk.
