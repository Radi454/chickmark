# Chick Quality V2 Phase 3 Implementation Plan

**Goal:** Make `station_registry.json` the single Chick validation and quality-classification authority, persist deterministic quality results on every Chick write, and surface advisory warnings without blocking offline work.

**Architecture:** Extend registry metadata with explicit classification tiers and stable flag codes, then generate equivalent Dart and TypeScript classifiers from that contract. Structural identity/storage failures are `BLOCK`; measurement validity issues are `WARN`; completeness, evidence, scope, conversion, outlier, and derived-cache issues are `FLAG`. SQLite v65 and one migration-only Supabase change add `qualityStatus` and `qualityFlags` to both Chick parent tables. Repository and agent writes always recompute those columns; callers cannot provide trusted cached values.

**Constraints:** Preserve all rows and compatibility columns; do not create observations or split combined rows; never block incomplete field-work samples for `WARN`/`FLAG`; do not apply migrations remotely; update living documentation and changelog in the phase commit.

## Task 1 — Registry-owned classification contract

- Write failing Dart and Deno parity tests for `BLOCK`, `WARN`, and `FLAG`, stable ordering/deduplication, explicit-zero semantics, dependencies, choices, ranges, list items, missing raw evidence, derived-cache mismatch, and scope mismatch.
- Add classification metadata to `tool/agent_schema/station_registry.json` and validate it in the generator.
- Generate equivalent immutable Dart/TypeScript data and implement shared classification adapters with identical canonical flag objects.
- Verify generator checks and cross-runtime parity vectors.

## Task 2 — SQLite v65 and model persistence

- Write failing v64→v65 migration, fresh-schema, repair, and model round-trip tests.
- Add nullable-compatible `qualityStatus TEXT` and `qualityFlags TEXT` columns to `chick_quality` and `chick_weights`, backfilling every existing row by registry classification without changing measurements or identity.
- Add v65 guarded migration, fresh schema, critical-column repair, and schema parity updates.

## Task 3 — Every local write recomputes quality

- Write failing repository tests proving caller-supplied cached quality is ignored, every insert/update recomputes, explicit zero is not missing, incomplete samples remain saveable, and invalid identity remains blocked.
- Recompute classification inside the same transaction as Chick identity preparation/upsert. Persist canonical JSON flags and aggregate status; preserve non-Chick behavior.
- Carry persisted quality through model/reload paths and expose advisory results from the provider.

## Task 4 — UI advisory warning surface

- Write failing widget/provider tests for visible warning/flag summaries and absence of a new save blocker.
- Add compact localized warning/flag presentation to the Chick workbench using persisted/current registry classification.

## Task 5 — Supabase and agent parity

- Create a migration file via the Supabase CLI only.
- Extend the ephemeral Postgres harness with additive columns, deterministic conservative backfill, and server-side recomputation/normalization for Chick writes without changing RLS.
- Write failing agent approval tests, then classify the final mapped payload using the same generated registry contract before persistence. Ensure agent and human vectors match exactly.
- Refresh the executed-migration cloud-column fixture and verify RLS/security.

## Task 6 — Sync, documentation, verification, review, commit

- Write failing push/pull compatibility tests for snake-case quality columns and old remote rows missing them.
- Extend sync mappings while preserving dirty cutoffs and pull-only behavior.
- Update `docs/LIVING_SPEC.md` and prepend the dated `docs/CHANGELOG.md` entry.
- Run focused Flutter, Deno, generator, migration/RLS, analyzer, affected audit/dashboard, and full Flutter suites.
- Obtain independent review for correctness, data integrity, migration safety, registry authority, offline behavior, backward compatibility, and tests; fix all Critical/Important findings test-first.
- Recheck HEAD/status and commit as `feat(chicks): classify sample data quality`.
