# Chick Quality V2 Phase 4 Implementation Plan

**Goal:** Make normalized Chick observations the raw source of truth for every newly touched Chick domain while preserving every existing parent row, legacy cache, sample identity, offline workflow, and mixed-client compatibility surface.

**Architecture:** Extend `station_registry.json` with observation-shape metadata for the six approved Chick domains, then generate equivalent Dart/TypeScript descriptors. SQLite v66 and one migration-only Supabase file add a polymorphic `chick_quality_observation` child table. Exact-domain parents own a replaceable observation set; `chicks.weights` continues to use its existing parent, while a touched `chicks.legacy_combined` parent lazily and idempotently creates only the exact-domain parent rows whose raw evidence is present. Domain parents point back to the compatibility parent through deterministic `sourceRefId` values. Transactions replace observations, rebuild wide/JSON caches from those persisted observations, and dirty-stamp parent and children together. Reads overlay observations first and use legacy caches only when no observation set exists. The compatibility parent remains present and continues to receive derived caches so older clients and dashboards keep working.

**Constraints:** Never bulk-split untouched legacy rows, merge replicates, delete evidence, infer missing measurements, or apply a migration to live Supabase. Parent ids/sample keys remain immutable. `station_registry.json` is the only observation mapping/validation authority. Pull-only roles receive parents and observations without passing push guards. Photos stay attached to a persisted domain sample when their registry-owned evidence field can be resolved; ambiguous legacy photo ownership is retained rather than guessed.

## Task 1 — Registry-owned observation contract

- Write failing generator, Dart, and Deno tests for every approved raw domain: Chick weights, YFBM pairs, CVT temperatures, Pasgar tallies, PM tallies/severity, and culled tallies.
- Add explicit observation descriptors to registry fields: kind, stable observation key strategy, numeric/text value source, optional list ordinal, and canonical unit.
- Validate descriptors against field types, object-list item schemas, unique keys, allowed kinds, and persistence mappings; generate immutable Dart/TypeScript metadata.
- Add cross-runtime parity vectors for extraction and reconstruction, including explicit zero, sparse ordinals, Unicode/list keys, malformed values, and stable deterministic ids.

## Task 2 — SQLite v66 observation storage and safe transition

- Write failing fresh-schema, v65→v66, divergent-schema repair, constraints, and user-version tests.
- Add `chick_quality_observation` with stable id, sample/customer/session/domain ownership, kind (`series`, `tally`, `ordinal`), key, nullable ordinal, exactly one numeric/text value, unit, canonical quality flags, optional source override, observed time, and standard dirty-sync metadata.
- Add uniqueness on `(sampleId, domain, kind, key, ordinal)` with explicit null-ordinal handling, indexes for sample/session/customer reads, value-shape checks, and parent-ownership validation without pretending a polymorphic SQLite foreign key exists.
- Preserve every v65 row byte-for-byte. Do not split or backfill combined quality rows during upgrade. Backfill exact `chicks.weights` observations only when valid raw JSON exists; malformed/absent evidence remains solely in its preserved legacy cache and is flagged rather than guessed.

## Task 3 — Transactional domain write/read path

- Write failing repository tests proving observation replace is atomic, explicit zero survives, stale child rows are tombstoned rather than silently deleted, mid-write failure rolls back parent and children, and cached summaries are derived from the persisted observation set rather than caller JSON.
- Implement an observation codec driven only by generated registry descriptors. It extracts canonical children and reconstructs registry field values without hand-written domain field lists.
- For `chicks.weights`, replace observations on the existing exact parent. For `chicks.legacy_combined`, detect only domains with present raw evidence, find/create deterministic exact-domain children by `sourceRefId`, preserve the compatibility parent, and never touch absent domains.
- Allocate exact-domain parent identity through the Phase 2 identity path; repeated saves reuse the same parent and observation ids. Different sample ids/scopes remain distinct replicates.
- After child persistence, reconstruct raw values from the database, derive summaries, classify quality, and dual-write exact-domain and compatibility caches in the same transaction.
- Make repository reads prefer observations and fall back only when a parent has no observation set. Hide compatibility-linked exact-domain helper rows from duplicate reconstruction while exposing standalone exact-domain samples.

## Task 4 — Reconstruction, photos, and UI compatibility

- Write failing reopen tests for observation-first weights and combined Chick drafts, legacy fallback, lazy domain idempotency, and no duplicate samples in the workbench.
- Carry observation-derived values through `mergePanelRowIntoAuditMap`, station sample reconstruction, providers, save coordination, and dashboard reads while keeping their current row/cache contracts.
- Add an optional observation reference to photos locally/remotely. Re-home only unambiguous registry-owned legacy photo fields to the exact domain parent during lazy materialization; retain ambiguous links unchanged. Never duplicate/delete a photo as a side effect.
- Verify old cache-only rows and mixed observation/cache sessions render and save without data loss.

## Task 5 — Offline sync, tombstones, and migration-only cloud mirror

- Write failing startup-sync tests for parent-before-child push, child-after-parent pull, child-before-parent delete, dirty-cutoff edits, local-dirty pull conflicts, and `canPush: false` observation pulls.
- Add a dedicated observation repository with per-row dirty tracking and conflict-safe remote upsert. Push exact-domain parents before observations; pull panels before observations; tombstone and delete observations before either Chick parent.
- Create the Supabase migration file with the CLI only. Add the observation table, uniqueness/value checks, indexes, ownership-enforcement triggers, parent-delete handling, RLS derived from the owning Chick parent/customer, and snake-case mappings. Do not run `db push`, `migration up`, or any remote apply command.
- Extend the ephemeral security harness with cross-tenant parent/customer rejection, both parent-table ownership paths, spoof-resistant owner metadata, RLS visibility/write checks, and child-before-parent deletion.

## Task 6 — Verification, review, documentation, and commit

- Run focused Flutter registry/model/migration/repository/reconstruction/photo/sync tests, complete affected audit/dashboard tests, the complete Telegram agent Deno suite, generator drift check, local Supabase migration/RLS harness, `flutter analyze`, and the full Flutter suite.
- Update `docs/LIVING_SPEC.md` with current observation-first/fallback behavior and prepend a dated `docs/CHANGELOG.md` entry. Record explicitly that untouched legacy rows and compatibility caches remain.
- Obtain an independent review covering source-of-truth correctness, lazy split idempotency, transactionality, conflict/deletion ordering, tenant isolation, photo preservation, registry authority, and backward compatibility. Fix every Critical/Important finding test-first and rerun verification.
- Recheck moving HEAD and unrelated dirty files, then commit only Phase 4 as `feat(chicks): persist raw quality observations`.
