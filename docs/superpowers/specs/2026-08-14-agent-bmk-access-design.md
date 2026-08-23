# Agent BMK Access — Design

**Status:** Approved
**Goal:** Let the hatchery agent answer benchmark questions ("what is the
hatchability of Ross at week 35?") from the real BMK tables instead of model
memory, and compare a selected audit against those standards.

## Scope

Three benchmark datasets, all reachable by the agent:

| Dataset | Cloud today | Work needed |
|---|---|---|
| `bmk_breeds` (breed × age week) | 247 rows, 6 breeds, weeks 24–65 | read tool only |
| `bmk_egg_breakout` (age week) | 41 rows, weeks 25–65 | read tool only |
| `bmk_operational_standards` | **does not exist** | migration + RLS + sync + read tool |

`bmk_operational_standards` is local-SQLite-only today. Rows live on whichever
device typed them, so the server-side agent cannot see any of it. This design
puts the table in the cloud, syncs it, and only then exposes it.

The tools are added to the shared agent tool catalog, so both the Telegram door
(`telegram-hatchery-agent`) and the in-app door (`app-hatchery-agent`) gain them
at once.

## 1. Cloud schema

New migration creating `public.bmk_operational_standards` as a snake_case mirror
of the local SQLite table (`lib/data/database/database_schema.dart`):

```
id                        text primary key
hatchery_id               text references public.hatcheries(id) on delete cascade  -- nullable
station_key               text not null
sector_key                text not null
metric_key                text not null
metric_label              text not null
unit                      text default ''
min_value                 double precision
max_value                 double precision
target_value              double precision
source                    text
source_url                text
source_photo_path         text
source_photo_remote_path  text
notes                     text
sort_order                integer not null default 0
updated_at                text
```

Index on `(hatchery_id, station_key, sector_key, metric_key)`, mirroring the
local `idx_bmk_operational_scope`.

The local table's `syncStatus` / `dirtyAt` / `lastSyncedAt` / `syncError`
columns are device-local and are **not** mirrored — they are stripped before
push, as with every other synced table.

The `bmk_operational_sources` storage bucket already exists with policies
(migration 0017). No storage work.

### RLS — split by row ownership

A row is either **global** (`hatchery_id is null`) or **owned** by exactly one
hatchery, and therefore one customer. The table has no `customer_id` column, so
ownership is resolved by joining `public.hatcheries`, the same shape the
existing `photos` policies use to reach `audit_sessions` (0003).

- Global rows: `select` for all authenticated (reference data, same as
  `bmk_breeds`); insert/update/delete gated on `app_is_admin()`.
- Owned rows: read gated on
  `exists (select 1 from public.hatcheries h where h.id = hatchery_id and public.app_can_read_customer(h.customer_id))`,
  write on the matching `app_can_write_customer(...)`.

Write policies use `with check` on the same predicate so a row cannot be
inserted or re-pointed into a hatchery the caller cannot write.

## 2. Sync

**Push** — new call in `startup_sync_service.dart::_pushLocalData`, using the
existing `_pushDirtyReferenceRows(...)` helper, placed **after** the hatcheries
push so the `hatchery_id` FK resolves. Global rows (null `hatchery_id`) have no
FK dependency and ride along in the same batch. Failure marks only its own rows
failed and the sync continues, matching the documented degradation of the other
reference pushes.

`BmkRepository.upsertOperationalStandard` must start marking rows dirty
(`syncStatus`/`dirtyAt`) so edits made in the BMK screen are picked up; today it
writes without touching the sync columns.

**Pull** — `pullTable('bmk_operational_standards', …)` alongside the existing
bmk pulls in `supabase_service.dart`, backed by a new raw-map upsert on
`BmkRepository` shaped like `upsertBmkBreed` (snake→camel through the existing
`_normalizeRow` / `_filterColumns`, `ConflictAlgorithm.replace` on `id`). The
pull respects the existing dirty-row guard, so a locally-edited row is not
overwritten before it has been pushed.

## 3. Agent tools

New shared module `bmk_tools.ts` under `telegram-hatchery-agent/`. Names added
to the `AgentToolName` union (`agent_protocol.ts`), specs to
`AGENT_TOOL_DEFINITIONS` (`agent_tools.ts`), handlers registered in
`createUnifiedAgentToolHandlers`.

### `get_breed_benchmark(breed, ageWeek)`

Returns `{ breed, ageWeek, hatchabilityPct, fertilityPct, hofPct,
productionPct, eggWeightG, chickWeightG }` for the resolved breed.

### `get_egg_breakout_benchmark(ageWeek)`

Returns the eleven defect targets (`infertilePct`, `early24hPct`, `early48hPct`,
`bloodRingPct`, `blackEyePct`, `earlyDeadPct`, `midDeadPct`, `lateDeadPct`,
`externalPipPct`, `crackedPct`, `contamPct`) for that age week.

### `get_operational_standards(stationKey?, sectorKey?, hatcheryId?)`

Global rows overlaid by that hatchery's rows keyed on `metric_key` — the exact
precedence `BmkRepository.getOperationalStandards` implements locally, so the
agent and the app screen never disagree. Sorted by `sort_order`, then
`metric_label`.

`hatcheryId` is checked against `scope.allowedCustomerIds` via the existing
`assertCustomerAllowed` before any row is read; a hatchery outside scope is a
rejection, not an empty result. Called without `hatcheryId`, the tool returns
global rows only.

### `compare_selected_audit_to_benchmark()`

No arguments. Operates on the audit already selected in the server conversation
context, the same contract as `get_selected_audit_breakouts` — the agent never
supplies or reconstructs an audit id.

Resolves the flock's breed and BMK age week (both already surfaced in
`agent_read_tools.ts`), loads the matching breed and breakout benchmark rows,
and returns `{ metricKey, label, actual, standard, delta, unit }` per metric.
All arithmetic is server-side, so the numbers are deterministic and land in
`agent_tool_events` as evidence.

The compared set is fixed, not discovered: the `bmk_breeds` metrics
(hatchability, fertility, HOF, production, egg weight, chick weight) against the
audit summary, and the eleven `bmk_egg_breakout` defect percentages against the
audit's breakout measurements. Operational standards are not part of this
comparison — they are per-metric ranges, not single-age targets, and are read
through their own tool.

Metrics with no actual value, or no benchmark coverage, are returned with an
explicit reason rather than dropped, so a partial comparison cannot read as a
complete one.

### Reference data is unscoped

`bmk_breeds` and `bmk_egg_breakout` are global reference tables with
read-all-authenticated policies. Their tools read through the admin client with
no customer filter. Only `get_operational_standards` and the compare tool are
scope-checked.

## 4. Breed and age resolution

One pure module, `bmk_lookup.ts`, unit-tested independently of the database.

**Breed:** normalize to lowercase alphanumeric (drop spaces, hyphens, dots),
then exact match against the normalized vocabulary, then **unique** prefix
match. So `ross`, `Ross 308`, `ROSS-308` all resolve to `Ross308`. A prefix
matching more than one breed is *not* resolved.

Vocabulary is read from the table, not hardcoded, so a new breed row is
immediately answerable. Today: `Ross308, Arbo, Avian, Cobb500, Hubbard, IR`.

**Misses** return a structured result, never a substituted value:

- unknown or ambiguous breed → `{ status: 'breed_not_found', availableBreeds: [...] }`
- week outside the breed's coverage → `{ status: 'week_out_of_range', breed, coveredWeeks: { min, max } }`

There is no nearest-week fallback. Week 70 does not silently answer with week
65. Coverage differs per breed (Cobb500 starts at 24, the rest at 25), so the
range is reported per resolved breed rather than as a table-wide constant.

## 5. Auto-attached benchmarks

`get_audit_summary` and `get_selected_audit_breakouts` gain a `benchmark` block
resolved from the flock's `breed` and `ageWeeks`, which both already carry.

When it cannot be resolved (unknown breed, missing age, out of coverage) the
block is present as `{ status: 'unavailable', reason }` rather than omitted, so
the agent can say the standard is unknown instead of quietly answering without
one.

This deliberately overlaps `compare_selected_audit_to_benchmark`: auto-attach
carries the reference row for context on every audit read, the compare tool
carries the computed deltas when the user actually asks how the audit measures
up.

## 6. Prompt

`agent_prompt.ts` gains rules:

- Benchmark figures come only from these tools. Never recite a standard from
  memory.
- Always state the breed and age week the figure belongs to.
- On a miss, ask or report the covered range — never interpolate, extrapolate,
  or substitute a nearby week.

## 7. Testing

**Deno (`supabase/functions/telegram-hatchery-agent/`)**

- `bmk_lookup` resolution table: aliases, casing, ambiguous prefix, unknown
  breed, week below/above coverage, per-breed coverage difference.
- `get_operational_standards`: global/hatchery merge precedence, sort order,
  and rejection for a `hatcheryId` outside `allowedCustomerIds`.
- `compare_selected_audit_to_benchmark`: delta arithmetic, missing-actual and
  missing-benchmark reasons, and the no-selected-audit path.
- Auto-attach: benchmark present on a resolvable audit, `unavailable` with a
  reason otherwise.
- The existing tool-catalog acceptance test extends to cover the new names.

**Dart**

- Push marks dirty operational-standard rows synced; failure marks them failed
  without aborting the sync.
- Pull upserts cloud rows into local, respecting the dirty guard.
- `upsertOperationalStandard` marks the row dirty.
- The existing cloud/local schema parity test covers the new table's column set.

## 8. Docs

Per the repo rule, the same commit updates `docs/LIVING_SPEC.md` (agent tool
catalog, BMK sync coverage) and adds a dated `docs/CHANGELOG.md` entry.

## Out of scope

- Editing benchmarks through the agent. All BMK writes stay in the app's BMK
  screen; every new tool is read-only.
- Any change to the breed or breakout reference data itself.
- Backfilling existing device-local operational standards into the cloud beyond
  what the normal dirty-row push carries on the next sync.
