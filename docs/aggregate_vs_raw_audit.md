# Aggregate-vs-Raw storage audit

## Why this exists

The panel tables store **both** the raw inputs a user enters (grids, weight
arrays, defect counts) **and** the aggregates computed from them (averages, CVs,
percentages). The two are written independently, so a row can hold an aggregate
whose raw source is empty or inconsistent — an *impossible state* that can never
arise from the real entry UI but is trivially produced by a hand-written seed,
a partial sync, or a future code path that updates one side but not the other.

This is the class of bug that made the dashboard show Egg-Shell-Temperature
numbers while the entry grid reopened blank: the demo seed wrote `estAvg` /
`shellTemp` but left `estReadingsJson` empty. The dashboard reads the aggregate;
the entry screen hydrates from the raw grid.

The seed is now round-trip complete (see `dashboard_demo_seeds.dart` and
`test/features/audits/session_round_trip_test.dart`), but the underlying
*independent-writability* remains. This document lists the candidates for a
future refactor that would make aggregates **derived**, not stored-in-parallel.

## Candidates (aggregate ← raw source)

| Table | Aggregate column(s) | Should derive from |
|---|---|---|
| `egg_storage` | `estAvg`, `estCvPct`, `shellTemp` | `estReadingsJson` (EST grid) — note `shellTemp` is literally set to the grid mean in `_updateEstCalculations` |
| `egg_quality` | `eggAvgWeight`, `eggUniformityPct`, `eggCvPct`, `eggSampleSize` | `eggWeightsJson` |
| `egg_quality` | `uvAffectedPct`, `uvCuticleDamagePct`, `uvWashedPct`, `uvDirtyPct` | `uv*Count` / `uvTrayEggCount` |
| `chick_weights` | `avgWeight`, `uniformityPct`, `cvPct`, `sampleSize` | `weightsJson` |
| `chick_quality` | `pasgar*Pct`, `pasgarFinalScore` | `pasgar*Count` / `pasgarSampleSize` |
| `chick_quality` | `cvtAvgTemp`, `cvtCvPct` | `cvtReadingsJson` |
| `chick_quality` | `yfbmAvgPct`, `yfbmCvPct` | `yfbmEntriesJson` |
| `setter_optimizing` | `estAvg`, `estCvPct` | `estReadingsJson` / `estSamplesJson` |
| `hatcher_optimizing` | `cvtAvg`, `cvtCvPct` | `cvtReadingsJson` |
| `fresh/candled/residue_breakout` | `*Pct`, `hatchabilityPct`, `fertilityPct`, `hofPct` | `*Count` / `traySize` (already kept consistent via the seed's `_count` helper) |

## Recommended direction (no refactor in this task)

Introduce a single derivation point so the impossible states above are
*unrepresentable*:

- **Preferred:** compute aggregates from raw at write time in one place (the
  panel-save mapping in `audit_provider.dart`), and treat the aggregate columns
  as a denormalized cache only ever written by that function. Raw is the source
  of truth.
- **Alternative:** drop the stored aggregates and expose them as computed
  getters / SQL views over the raw columns. Heavier read cost, zero drift.

Either removes the "aggregate present, raw empty" failure mode at the schema
level rather than relying on every writer (UI, seed, sync) to keep both sides in
step.

## Autosave-overwrite finding (investigated)

`_updateEstCalculations` (egg) nulls `estAvg`/`estCv`/`shellTemp` when the grid
is empty. This is **correct** — no readings means no average. It is **not**
triggered by autosave itself (autosave persists the current draft); it fires
only on grid-cell edits and storage-days changes. With the raw grid now seeded,
the controllers populate on load, so any later recompute *reproduces* the mean
instead of wiping it. The earlier wipe risk was a symptom of the empty seed, now
fixed — no logic change was required. Guarded by the "Autosave does not wipe a
populated aggregate" test.

## Not yet seeded (raw still absent in the demo)

Lower-value or complex-shape raw fields intentionally left aggregate-only for
now; reopening these sub-sections shows summary values but blank raw entry:

- `chick_quality.yfbmEntriesJson` (Yolk-Free Body Mass entry list)
- `chick_quality.pm*` post-mortem necropsy counts
- all `*PhotosJson` / `*Photo` columns (no demo image assets)
