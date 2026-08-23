# Egg Quality Sampling Stability and Egg Grading Design

## Status

Approved in conversation on 2026-08-23. This document records the agreed design
before implementation planning.

Two schema versions are covered:

- **v61** — Egg Quality comparison-row stability, explicit sample metadata,
  domain metadata, Sample Mode UI.
- **v62** — Egg Grading / Visual Quality inside the Egg Quality workflow.

v62 depends on v61 landing first, because grading rows are owned by a stable
`egg_quality.id`.

This document does not authorize changes to Egg Storage measurement logic, new
comparison scopes (tray, trolley, machine) for the egg station, the breakout
stations, the chick stations, or the agent tool catalogue.

## Goal

Make Egg Quality comparison rows keep their identity and their values across
add, switch, rename, remove, save, sync, and reopen; record explicitly what
each saved row represents instead of re-deriving it; make the sampling mode
visible in the UI; and add a visual egg-grading section that inherits that same
sample identity without introducing a second sampling system.

## Current-State Findings

### Sampling today

An Egg station edit session holds two parallel lists in `AuditProvider`:
`_drafts` (`AuditModel`, the values) and `_stationSamples`
(`StationSampleModel`, the identity). They are paired **by list position**.

`StationSampleModel` already carries `sampleMode`, `sampleKind`,
`comparisonType`, `sampleIndex`, `sampleLabel`, `houseNo`, `houseLabel`. None of
that reaches disk. The `station_samples` table was dropped in the panel-only
cutover (`database_helper.dart`, `_resetForPanelCutover`). The only persisted
artefact is one flat `egg_quality` panel row per sample, whose sample-identity
columns are the hierarchy columns `house`, `setter`, `hatcher`, `trolley`,
`tray`, `position`.

On reopen, `_StationFrameState` in `audit_session_screen.dart` reconstructs both
drafts and samples from those rows:

- `_rowHasHierarchy(row)` — any non-null hierarchy column — decides
  `comparison` vs `pooled`.
- `_scopeTypeForRow(row)` derives the scope from which hierarchy column is set.
- `_sampleLabelForRow(row)` falls back to the raw `house` value.
- `row['sampleIndex']` is read, but `egg_quality` has no such column, so the
  index is always the position in the query result.

### Root causes of comparison-row instability

1. **No persisted sample metadata.** Mode, scope, label, and order are all
   re-inferred from `house` being non-null. A comparison row whose house is
   blank reopens as a pooled row.

2. **Hierarchy is the row key.** `_panelUniqueRowIndexSql` builds
   `UNIQUE (sessionId, IFNULL(house,''), IFNULL(setter,''), …)`. Two comparison
   rows with a blank or duplicate house collide on that index and one overwrites
   the other. This is the observed "rows lose or mix data".

3. **Order is not persisted.** Reopen order is the SQL result order, and drafts
   and samples are paired positionally, so any order change pairs values with
   the wrong house.

4. **Identity kept by string sniffing.** `_syncStationSampleFromDraft` keeps a
   typed house only when `_defaultEggHouseNo` decides the current value does not
   look like a generated default (`H1`, `H2`, …). A user-typed value that
   happens to match a generated one is silently regenerated.

5. **Forced collapse to pooled.** `removeActiveSample` and
   `_removeEggQualityScopeIndexes` set `SampleMode.pool` when one row remains,
   even for a row that still holds house data. Its house identity is dropped on
   the next save, and it then merges with the pooled row.

6. **Panel-row id churn.** The saved row id is composed as
   `<panelId>:<sample.id>`, where `panelId` is
   `<sessionId>:<tableName>:<draft.id>`. On reopen, `draft.id` is regenerated as
   `<sessionId>:<stationKey>:<position>`, so row ids are position-derived and
   change between sessions.

### Grading — existing precedent

Culled Chicks Analysis is the same problem already solved once:
`lib/features/audits/models/culled_chicks_analysis.dart` holds a Dart const
defect catalogue (`kCulledChickDefects`: id, category, subtype, description,
common causes, sources); `culled_chicks_analysis_tab.dart` renders count fields
grouped by category with a live summary strip; the result is stored as
`culledChicksAnalysisJson` on the panel row alongside derived summary columns
`culledChicksAffectedPct`, `culledChicksTopCategory`, `culledChicksTopSubtype`.

The limit of that pattern is analytics: `PanelDashboardRepository` is raw SQL,
so a JSON blob can only be summarised client-side. That is why culled-chicks
reporting never went past "top category".

The counter-precedent is the `lab_analysis_reports → lab_analysis_groups →
lab_analysis_rows` trio: a real synced child table whose rows denormalize
`customerId`, `flockId`, `reportDate`, and `testType` so dashboard indexes work
without joins.

### Sync findings

- Local columns are camelCase; `toSupabaseUpsertPayload` converts to snake_case
  automatically. New columns need no mapper, only a matching cloud column.
- A local column with no cloud counterpart makes PostgREST reject the **whole
  batch**, so every dirty row of that table gets stuck. This failure mode is
  already documented in `startup_sync_service.dart` for `flocks.updatedAt`.
- Panel columns are reconciled on every database open
  (`_ensurePanelSampleSchemaColumns`), so a new entry in
  `PanelSampleSchema.measurementColumns` lands without a version bump.
- A new non-panel table must be registered in both `_criticalTables` and the
  repair column map in `database_helper.dart`, or it can silently fail to exist.
- SQLite `ON DELETE CASCADE` does not queue sync tombstones. Child rows must be
  deleted through a repository that calls
  `SyncTombstoneRepository.queueDeletesWithExecutor`, or the cloud keeps
  orphans permanently.
- Tenant-owned cloud child tables carry a server-derived `customer_id` set by a
  before-write trigger (`DATABASE_SPEC.md`, "Storage layers").

## Part One — v61 Sampling Stability

### Decisions

| Question | Decision |
|---|---|
| Row identity | Persisted stable row id, carried through reopen |
| Column placement | All panel tables get the columns; only the egg station reads and writes them |
| Duplicate houses | Blocked with inline validation |
| Cloud | Additive migration written and applied |
| Compare → Pooled flip | Confirm dialog, keep row 1's values, delete the other rows |
| Domain values | `egg_storage`: hatchery / hatchery / hatchery. `egg_quality`: hatchery / farm / farm |

### Schema

Seven nullable columns added to the shared panel context column list in
`database_schema.dart`, so every panel table receives them through the existing
`ALTER TABLE ADD COLUMN` reconciliation pass. No table rebuild, no data
movement.

```
sampleMode TEXT             -- 'pooled' | 'comparison'
scopeType TEXT              -- SamplingLayer.dbValue: 'pool' | 'house'
sampleLabel TEXT            -- 'Pool', 'H1', or the user's text
sampleIndex INTEGER         -- the user's row order, 1-based
sourceDomain TEXT           -- where the measurement is taken
actionDomain TEXT           -- where the corrective action happens
recommendationTarget TEXT   -- who receives the recommendation
```

Schema version goes to **61**. The upgrade handler runs the existing
ensure-columns pass; there is no destructive step and no backfill.

Domain values written by the egg station:

| Panel | sourceDomain | actionDomain | recommendationTarget |
|---|---|---|---|
| `egg_storage` | `hatchery` | `hatchery` | `hatchery` |
| `egg_quality` | `hatchery` | `farm` | `farm` |

The columns are free-text and nullable so the vocabulary can grow without a
schema change.

### Row identity

The `egg_quality` panel row id becomes the station-sample id.

- **Save.** The row id is `sample.id`, not `'$panelId:${sample.id}'`. Upsert is
  by id.
- **Reopen.** `_sampleFromPanelRow` already assigns `sample.id = row['id']`, so
  the id round-trips. The reconstructed draft id is derived from it, which makes
  `_matchingExistingSample` match on `legacyAuditId` instead of falling through
  to positional `sampleIndex` matching.
- **Unique index.** The hierarchy unique index is dropped for `egg_quality`
  only. Identity is the id. This removes the blank/duplicate-house collision.
  Every other panel table keeps its index unchanged. `egg_storage` is pool-only
  and single-row, so it is unaffected.
- **Prune.** Stale-row pruning keeps rows by id set, so a renamed house no
  longer looks like a stale row to delete.

Consequences: renaming a house updates the same row; reordering and removing
rows leave ids untouched; reopen orders by `sampleIndex`, ties broken by
`createdAt`.

### Read path and backward compatibility

Explicit columns win; inference is the fallback for rows written before v61:

```
mode  = row.sampleMode  ?? (rowHasHierarchy ? 'comparison' : 'pooled')
scope = row.scopeType   ?? (house != null ? 'house' : 'pool')
label = row.sampleLabel ?? house ?? 'Sample <n>'
index = row.sampleIndex ?? position in the result set
```

Old sessions therefore reopen exactly as they do today, and acquire explicit
metadata the next time they are saved. No migration backfill is required.

### Provider behaviour

- `_syncStationSampleFromDraft` no longer uses `_defaultEggHouseNo` or
  `_defaultEggHouseLabel` for egg quality. House, label, and scope are owned by
  the sample and are never regenerated from the list index.
- The forced collapse to `SampleMode.pool` on last-row-removal is removed for
  egg quality. A single remaining house row stays `comparison` / `house`.
  Pooled and comparison are changed only by the Sample Mode selector.
- Compare → Pooled shows a confirmation dialog naming what will be discarded.
  On confirm, row 1's values become the pooled row and the other house rows are
  deleted by id.
- Duplicate house numbers are rejected inline, reusing the existing
  `_hasDuplicateEggHouse` helper on the identity-field validator.
- Egg Storage logic is untouched.

### UI

**Egg Storage** — a read-only Sample Mode bar: a single disabled "Pool" chip
with the caption "Egg storage is always measured as one pool."

**Egg Quality** — a real selector with exactly two options, `Pooled` and
`Compare by house`. Tray, trolley, and machine scopes are not offered.
Choosing `Compare by house` creates the first house row. The existing house
chip strip remains beneath the selector and is shown only in comparison mode.

### Cloud

Additive nullable columns on the mirrored panel tables, snake_case:
`sample_mode`, `scope_type`, `sample_label`, `sample_index`, `source_domain`,
`action_domain`, `recommendation_target`. Applied before the client ships.

### Tests

- Add a house — the new row gets its own id, index, and label.
- Switch houses — typed values stay with their own row, no bleed.
- Remove a middle house — remaining rows keep ids, values, and order, and do
  not collapse to pooled.
- Save — `egg_quality` rows carry mode, scope, label, index, and the three
  domain values.
- Reopen — rows rebuild in the saved order with the saved metadata.
- Reopen legacy rows with all new columns null — inference reproduces today's
  behaviour.
- A blank-house comparison row and a pooled row coexist without overwriting
  each other. This is the regression test for the collision.
- Duplicate house rejected.

## Part Two — v62 Egg Grading

### Decisions

| Question | Decision |
|---|---|
| Sampling | Reuses the Egg Quality sample. No separate sampling system. |
| Defect catalogue | Dart catalogue seeded into a local reference table; not synced |
| Join key | `defectCode` string, never a catalogue row id |
| Multiple defects per egg | Allowed. Rejected count is entered, not derived. |
| Detail storage | Child table for analytics, JSON mirror on the panel row |

### Business rule — multiple defects per egg

One egg can carry several defects. Therefore:

- `gradingSampleSize` — eggs inspected.
- `gradingRejectedCount` — **entered by the auditor**, the number of distinct
  eggs rejected. It cannot be derived from the defect counts.
- `gradingAcceptableCount = gradingSampleSize - gradingRejectedCount`.
- Percentages are derived, never typed.

Validation:

- Every count is an integer ≥ 0.
- Each individual defect count ≤ `gradingSampleSize`.
- `gradingRejectedCount` ≤ `gradingSampleSize`.
- **No `SUM(defects) ≤ sampleSize` rule.** The sum may legitimately exceed the
  sample size.
- `UNIQUE (eggQualityId, defectCode)` prevents duplicate rows for one sample.

### Defect catalogue

A Dart catalogue, in the shape of `kCulledChickDefects`, is the source of truth
and is seeded into a local `egg_defect_types` reference table:

```
id TEXT PRIMARY KEY
code TEXT NOT NULL UNIQUE        -- stable join key
name TEXT NOT NULL
category TEXT NOT NULL           -- shell contamination | shell integrity |
                                 -- shell quality | shape and size | other
isReject INTEGER NOT NULL DEFAULT 1
description TEXT
imageAsset TEXT                  -- reference illustration, populated later
sortOrder INTEGER NOT NULL DEFAULT 0
isActive INTEGER NOT NULL DEFAULT 1
createdAt TEXT NOT NULL
updatedAt TEXT NOT NULL
```

Initial codes: `dirty`, `yolk_stained`, `blood_stained`, `stained`, `cracked`,
`hairline_crack`, `toe_hole`, `calcium_deposit`, `wrinkled`, `ridged`,
`thin_shell`, `membrane`, `round`, `elongated`, `slab_sided`, `small`,
`double_yolk`, `other`.

The table is local reference data only. It is not pushed. It may become
pull-only later if cloud-side catalogue editing is ever wanted.

Counts join by `code`, not by catalogue row id, so that renaming, deactivating,
or removing a defect type can never orphan or silently relabel historical audit
data.

### `egg_quality` grading columns

Added to `PanelSampleSchema` measurement columns for `egg_quality`, so they land
through the existing panel reconciliation:

```
gradingSampleSize INTEGER
gradingRejectedCount INTEGER
gradingAcceptableCount INTEGER
gradingRejectedPct REAL
gradingAcceptablePct REAL
gradingDefectsJson TEXT
gradingTopDefectCode TEXT
gradingTopDefectPct REAL
```

`gradingDefectsJson` is a mirror of the child rows. It keeps the panel row
self-describing, gives reopen a fallback when a cloud-pulled panel row arrives
before its children, and rides existing panel sync with no extra wiring. The
child table remains the analytics truth.

### `egg_quality_defect_counts`

A new syncable child table, denormalized in the style of `lab_analysis_rows`:

```
id TEXT PRIMARY KEY
eggQualityId TEXT NOT NULL        -- FK egg_quality(id) ON DELETE CASCADE
sessionId TEXT NOT NULL
customerId TEXT NOT NULL
flockId TEXT
hatcheryId TEXT
date TEXT NOT NULL
scopeType TEXT                    -- snapshot of the owning sample
houseKey TEXT
sampleLabel TEXT
defectCode TEXT NOT NULL
defectCategory TEXT               -- snapshot at entry time
isReject INTEGER                  -- snapshot at entry time
count INTEGER NOT NULL DEFAULT 0
pctOfSample REAL
notes TEXT
sortOrder INTEGER NOT NULL DEFAULT 0
createdAt TEXT NOT NULL
updatedAt TEXT NOT NULL
syncStatus TEXT NOT NULL DEFAULT 'pending'
dirtyAt TEXT
lastSyncedAt TEXT
syncError TEXT
UNIQUE (eggQualityId, defectCode)
INDEX (eggQualityId)
INDEX (customerId, flockId, date, defectCode)
INDEX (syncStatus, dirtyAt)
```

`defectCategory` and `isReject` are snapshotted so a later catalogue edit cannot
rewrite the meaning of a past audit.

The table must be registered in `_criticalTables` and in the repair column map
in `database_helper.dart`.

Schema version goes to **62**, kept separate from v61 so either change can be
diagnosed on its own.

### Flutter changes

- `lib/features/audits/models/egg_grading.dart` — catalogue plus
  `EggGradingSummary`, mirroring the culled-chicks model.
- `lib/data/repositories/egg_grading_repository.dart` — read and write by
  `eggQualityId`, dirty/synced/failed marking, and tombstone-queueing deletes.
- `AuditProvider` — grading counts held per station sample, keyed by
  `sample.id`, never by list index.
- `AuditPanelSaveCoordinator` — after writing each `egg_quality` row, replace
  that row's defect-count children (delete rows no longer present, upsert the
  rest) and write the derived summary columns and JSON mirror.
- Egg Quality UI — a grading section below the existing UV and weights blocks,
  inside the active sample scope.
- `audit_session_screen.dart` — `_loadInitialData` also loads defect counts per
  `egg_quality.id`, falling back to `gradingDefectsJson` when child rows are
  absent.

### Sync and cloud changes

- Cloud `egg_quality`: the eight grading columns, snake_case, nullable.
- Cloud `egg_quality_defect_counts`: mirror table, foreign key to
  `egg_quality(id) ON DELETE CASCADE`, RLS policy, and the server-derived
  `customer_id` trigger required for tenant-owned child tables.
- Push: a new `_pushDirtyEggGrading()` after `_pushDirtyPanelRows()`. Order
  matters — children must follow their parent rows.
- Pull: registered in the pull loop and in `SupabasePullSummary`.
- Deletes: routed through the repository so tombstones are queued.

### UI

Inside Egg Quality, under the active sample:

```
Egg grading / visual quality
  Eggs inspected [ 100 ]     Eggs rejected [ 12 ]
  Acceptable 88 (88%)   Rejected 12 (12%)   Top defect: Dirty 4%

  Shell contamination
    [img] Dirty            [ 4 ]    4.0%
    [img] Yolk stained     [   ]      -
    [img] Blood stained    [ 1 ]    1.0%
    [img] Stained          [   ]      -
  Shell integrity
    [img] Cracked          [ 3 ]    3.0%
    [img] Hairline crack   [   ]      -
    [img] Toe hole         [   ]      -
  Shell quality
    [img] Thin shell       [ 3 ]    3.0%
    [img] Wrinkled         [ 2 ]    2.0%
    [img] Ridged           [   ]      -
    [img] Calcium deposit  [   ]      -
    [img] Membrane         [   ]      -
  Shape and size
    [img] Round / Elongated / Slab sided / Small / Double yolk
  Other
    [img] Other            [   ]      -
```

Each row carries an image slot from the start, populated later from
`imageAsset`. The section sits inside the sample scope, so switching house
chips swaps the entire block.

### Tests

- Counts stay isolated per sample when switching houses.
- Renaming or reordering a sample does not move grading ownership.
- Removing an Egg Quality sample removes its grading rows and queues
  tombstones.
- Reopen restores the correct counts for every sample.
- Reopen falls back to `gradingDefectsJson` when child rows are missing.
- Negative counts rejected; a defect count above the sample size rejected;
  a defect sum above the sample size accepted.
- Duplicate `(eggQualityId, defectCode)` rejected.

## Analytics Readiness

The child table is shaped so these are later `GROUP BY` queries, not new
schema work: defect percentage by type, total rejection rate, most common
defect, defects by flock, defects by house, defect trends over time, house
comparison, customer and farm comparison, and correlation of egg defects with
later hatchery results through `sessionId` and `flockId`.

No dashboard work is in scope here.

## Risks

| Risk | Mitigation |
|---|---|
| New local columns pushed before the cloud migration is applied — PostgREST rejects the whole batch and every dirty row sticks | Apply the cloud migrations before the client ships |
| Grading child rows orphaned if an `egg_quality` row id changes | Grading lands only after the v61 stable-row-id change |
| New table missing from the critical-table or repair lists — silent absence | Register in both lists |
| `ON DELETE CASCADE` removes children without queueing tombstones — permanent cloud orphans | Delete through the repository |
| The existing dashboard join `egg_storage ⟕ egg_quality` matches on hierarchy equality, so pool-only storage rows never join per-house quality rows | Pre-existing quirk, not introduced here. Grading analytics read `egg_quality`'s own house column. Noted, not fixed. |
| Existing audits | Every new column is nullable; absent grading data means the feature is simply not present. No backfill. |

## Implementation Sequence

1. v61 sampling: schema columns, stable row id, read-path fallback, provider
   fixes, Sample Mode UI, tests.
2. Cloud migration for the v61 columns, applied.
3. Cloud migration for grading: `egg_quality` columns,
   `egg_quality_defect_counts`, RLS, and the `customer_id` trigger. Applied
   before any client grading code ships.
4. v62 local schema: grading columns, catalogue table and seed, child table,
   both registration lists.
5. Grading repository, save-coordinator wiring, provider wiring, tests.
6. Grading UI section.
7. Grading sync push, pull, and tombstone tests.
8. Dashboard and analytics reads — a separate task, not in this scope.

## Out of Scope

- Egg Storage measurement logic and its pool-only sampling.
- New comparison scopes for the egg station.
- Dashboard and analytics surfaces for grading.
- Defect reference images.
- Cloud-side editing of the defect catalogue.
