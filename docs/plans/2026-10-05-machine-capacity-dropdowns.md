# Hatchery Machine Capacity Dropdowns Plan

> **For agentic workers:** Implement the backend and UI/sync tasks in their assigned worktrees. Sampling identities remain per-session tree nodes; the new catalog stores hatchery equipment and registered capacities.

**Goal:** Register fixed Setter and Hatcher machine IDs per hatchery and expose stored trolley/tray counts for sampling dropdowns.

**Architecture:** A hatchery-owned SQLite catalog stores immutable UUIDs, fixed physical machine codes, capacities, and calculated integer counts. The repository validates and normalizes local writes, tracks dirty rows, and supports remote upserts; the database migration adds the same table to fresh and upgraded installs. Sampling nodes continue to hold historical identities and sample IDs.

**Tech Stack:** Flutter/Dart, SQLite via sqflite, Supabase row sync.

**Spec:** User request and clarifications dated 2026-10-05.

## Global Constraints

- SQLite schema advances additively from version 82 to 83.
- Machine code is a user-entered fixed physical ID and is separate from immutable database UUID.
- `trolleyCount` and `traysPerTrolley` are persisted registration values; sampling reads them rather than calculating counts.
- Capacity values must be positive; division uses ceiling semantics for partial capacities.
- Historical panel sampling nodes, sample IDs, and measurements survive catalog edits or capacity reductions.
- Hatchery deletion removes machine rows child-first and queues tombstones.

## Review Focus

- Duplicate codes after trim/case normalization are rejected per hatchery and machine kind.
- A machine capacity edit preserves its database ID and recalculates persisted counts.
- Invalid zero/negative capacity values are rejected before persistence.
- A v82 database upgrades to the v83 shape without losing hatchery rows.
- Removing a hatchery queues machine tombstones before deleting its machine rows.

---

### Task 1: Model and repository

**Files:**
- Create `lib/data/models/hatchery_machine_model.dart`
- Create `lib/data/repositories/hatchery_machine_repository.dart`
- Test `test/data/repositories/hatchery_machine_repository_test.dart`

**Interfaces:**
- Model fields: `id`, `hatcheryId`, `kind`, `code`, `name`, `batchSize`, `trolleyCapacity`, `traySize`, `trolleyCount`, `traysPerTrolley`, `createdAt`, `updatedAt`, `createdBy`.
- Repository methods: `getByHatchery`, `getById`, `getRowById`, `saveMachine`, `getDirtyRows`, `markRowsSynced`, `markRowsFailed`, `getRowSyncStatus`, `upsertRemoteRow`.

- [x] Test positive-capacity count calculation and invalid capacities.
- [x] Test local save normalization, uniqueness, edit by immutable ID, remote upsert, and dirty cutoff behavior.
- [x] Implement the model and repository using existing hatchery reference sync conventions.

### Task 2: Schema v83

**Files:**
- Modify `lib/data/database/database_schema.dart`
- Modify `lib/data/database/database_migrations.dart`
- Modify `lib/data/database/database_helper.dart`
- Test `test/data/database/hatchery_machine_schema_test.dart`

- [x] Assert fresh schema contains the catalog and all capacity/count/sync columns.
- [x] Assert v82 upgrade creates the catalog without changing hatchery data and is idempotent.
- [x] Add v83 table creation to fresh install and migration, register it for surgical repair, and update the schema version.

### Task 3: Hatchery deletion cleanup

**Files:**
- Modify `lib/data/repositories/hatchery_repository.dart`
- Test `test/data/repositories/hatchery_machine_repository_test.dart`

- [x] Assert deleting a hatchery queues catalog tombstones before deleting catalog rows.
- [x] Implement child cleanup in the existing hatchery deletion transactions.

### Task 4: Integration handoff

**Files:**
- No additional files in this backend task.

- [x] UI reads `trolleyCount` and `traysPerTrolley` from registered machine models and keeps physical machine codes fixed.
- [x] Sync uploads machine reference rows after hatcheries and pulls machine rows through a dedicated upsert callback.
- [x] Supabase migration creates the remote table and hatchery-scoped access policies.

Implementation and focused automated checks are finished. Live browser catalog/sync verification and human acceptance remain pending; checked items describe implementation checks rather than product acceptance.
