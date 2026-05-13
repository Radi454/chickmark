# Sampling Schema Redesign

Date: 2026-05-13

## Purpose

Simplify audit sampling storage so each audit panel owns its own data while still supporting dashboard queries. The current model is too generic for the sampling workflow: users think in panel/sector terms, while dashboards need direct access to final summary rows.

The redesigned model uses the same rule everywhere:

- Every panel has a main panel table.
- Every panel has a `{panel_table}_samples` child table.
- Pool is the default mode for every panel.
- Pool mode still saves one sample row with `scopeType = pool` and `scopeLabel = Random`.
- Compare mode is optional and configured per panel.
- Compare mode saves one sample row per compared group.
- Dashboard summary columns live on sample rows.
- Main panel rows store panel settings and duplicated dashboard context.
- Extra raw detail tables exist only when a sector truly needs them.

## Shared Context

Every main panel table duplicates the dashboard context needed for fast filtering:

- `sessionId`
- `customerId`
- `flockId`
- `date`
- `hatcheryId`
- `breed`
- `flockAgeWeeks`

Main panel tables also store panel-level settings:

- `mode`: `pool` or `compare`
- `compareLayer`: nullable in pool mode, set only in compare mode
- timestamps and notes as needed

Sample rows keep minimal common columns:

- `id`
- `panelId`
- `scopeType`
- `scopeLabel`
- `sampleIndex`
- `notes`
- `createdAt`
- `updatedAt`

Each sample table only adds identity columns that the panel can actually use. For example, `chick_weights_samples` can include `houseId`, while `chick_pasgar_samples` includes `setterId` and `hatcherId`.

## Scope Identity Rule

Sample rows store the full relevant identity path for their scope, not only a display label.

Examples:

- Chick weights by house: `houseId`
- Chick PASGAR by machine pair: `setterId`, `hatcherId`
- Candled breakout by trolley: `houseId`, `setterId`, `trolleyId`
- Residue breakout by trolley: `houseId`, `setterId`, `hatcherId`, `trolleyId`
- Residue breakout by tray: `houseId`, `setterId`, `hatcherId`, `trolleyId`, `trayId`

This prevents ambiguous dashboard rows such as `Tray 1` without its parent machine/trolley context.

## UI Rules

Every panel starts in Pool mode. The UI shows a compact Pool/Compare control per panel. If Compare is selected, that panel shows a sliding segmented control containing only the valid comparison layers for that panel.

Do not use one global comparison mode for the whole screen. Each panel owns its own mode and layer.

Pool rows display as `Random`. The label is fixed system text and is not editable.

## Egg Screen

Egg uses separate panels:

- `egg_storage`
- `egg_quality`
- `egg_weights`

All Egg panels still have sample tables, including Pool-only panels:

- `egg_storage_samples`
- `egg_quality_samples`
- `egg_weights_samples`

Storage, quality, and weights use the same panel/sample storage pattern, but their valid comparison layers differ.

`egg_storage`

- Default: Pool / Random
- Compare layers: none
- Stores storage room assessment fields
- Saves one `egg_storage_samples` row with `scopeType = pool` and `scopeLabel = Random`

`egg_quality`

- Default: Pool / Random
- Compare layers: House
- Stores egg quality assessment counts and percentages

`egg_weights`

- Default: Pool / Random with flock context
- Compare layers: House
- Stores raw weights as JSON on sample rows
- Stores dashboard summaries on sample rows: average, CV, uniformity, min, max, sample size

## Chicks Screen

Chicks uses separate panel tables:

- `chick_pasgar`
- `chick_weights`
- `chick_yfbm`
- `chick_cvt`
- `chick_pm`

All panels have matching sample tables:

- `chick_pasgar_samples`
- `chick_weights_samples`
- `chick_yfbm_samples`
- `chick_cvt_samples`
- `chick_pm_samples`

`chick_weights`

- Default: Pool / Random with flock context
- Compare layers: House
- Stores raw weights as JSON on sample rows
- Stores dashboard summaries on sample rows: average, CV, uniformity, min, max, sample size

`chick_pasgar`

- Default: Pool / Random
- Compare layers: Setter+Hatcher pair
- Sample rows store `setterId` and `hatcherId`
- Stores PASGAR score and defect fields on sample rows

`chick_yfbm`

- Default: Pool / Random
- Compare layers: Setter+Hatcher pair
- Stores YFBM counts and percentages on sample rows

`chick_cvt`

- Default: Pool / Random
- Compare layers: Setter+Hatcher pair
- Stores CVT summary fields on sample rows
- Raw CVT grid/readings stay as JSON on the sample row when needed for screen reload; dashboard reads summary columns

`chick_pm`

- Default: Pool / Random
- Compare layers: Setter+Hatcher pair
- `collectionPoint` is metadata, not a comparison layer
- Stores lesion counts/severity and summary fields on sample rows

## Hatch Analysis And Egg Breakouts

Hatch Analysis has three separate breakout category panels:

- `fresh_egg_breakout`
- `candled_egg_breakout`
- `residue_breakout`

Each category has its own sample table:

- `fresh_egg_breakout_samples`
- `candled_egg_breakout_samples`
- `residue_breakout_samples`

Each category also has a tray table:

- `fresh_egg_breakout_trays`
- `candled_egg_breakout_trays`
- `residue_breakout_trays`

House uses a shared parent table above the breakout categories:

- `hatch_analysis_houses`

The normal/default row is `houseId = random`, `houseLabel = Random`.

One physical tray equals one tray row. Do not use `numberOfTrays` to represent multiple trays in one row.

House is a situational top layer above all three breakout categories. The normal/default state is a compact `House: Random` value. House grouping expands only when needed.

`fresh_egg_breakout`

- Default: Pool / Random
- Deepest identity path: House -> Tray
- Valid compare layers: House, Tray
- Tray rows store direct count and percent columns

`candled_egg_breakout`

- Default: Pool / Random
- Deepest identity path: House -> Setter -> Trolley -> Tray
- Valid compare layers: House, Setter, Trolley, Tray
- Candled tray cards show House and Setter ID
- Tray rows store direct count and percent columns

`residue_breakout`

- Default: Pool / Random
- Deepest identity path: House -> Setter+Hatcher -> Trolley -> Tray
- Valid compare layers: House, Setter+Hatcher, Trolley, Tray
- Residue tray cards show House, Setter ID, and Hatcher ID
- Tray rows store direct count and percent columns

Summary sample rows store both count totals and percentages. Tray rows also store percentages for their own physical tray.

## Setter And Hatcher Optimizing

Setter and Hatcher screens are stage-specific.

Both screens have sample tables:

- `setter_optimizing_samples`
- `hatcher_optimizing_samples`

`setter_optimizing`

- Default: Pool / Random
- Valid compare layers: Setter, Trolley
- Deepest identity path: Setter -> Trolley
- Tray comparison is not valid here
- Sample rows store the full relevant identity path: `setterId` for setter scope, or `setterId` and `trolleyId` for trolley scope

`hatcher_optimizing`

- Default: Pool / Random
- Valid compare layers: Hatcher, Trolley
- Deepest identity path: Hatcher -> Trolley
- Tray comparison is not valid here
- Sample rows store the full relevant identity path: `hatcherId` for hatcher scope, or `hatcherId` and `trolleyId` for trolley scope

## Dashboard Data Flow

Dashboards read sample rows first because sample rows are the dashboard-ready result rows.

Main panel rows are used for:

- panel settings
- session/dashboard context
- joining sample rows to the visit context

Sample rows are used for:

- Pool/Random summaries
- comparison group summaries
- final dashboard values

Raw detail rows are used only for drill-down or recalculation:

- Hatch Analysis tray rows
- other future detail tables where individual physical sample rows are needed

Weight/uniformity panels do not need individual measurement rows because dashboards only need summaries. Raw weight grids stay as JSON on the sample row, alongside summary columns.

## Migration Approach

Existing dummy data does not need to be migrated. The implementation can reset or rebuild local sample tables for this redesign.

The app should keep working behavior while the schema changes:

- Existing screens should continue to save and reload drafts.
- Pool mode must work before comparison mode.
- Comparison mode should be enabled panel by panel.
- Dashboard queries should migrate to the new sample tables once the write path is stable.

## Testing Strategy

Add tests in stages:

1. Model/table mapping tests for main panel rows and sample rows.
2. Repository tests for pool sample save/load.
3. Repository tests for comparison sample save/load by each valid layer.
4. UI/provider tests that switching Pool/Compare updates the correct panel only.
5. Hatch Analysis tests for one physical tray per row and full parent identity path.
6. Dashboard query tests that read summary values from sample rows.

## Open Risks

- Table count will increase. This is intentional, but repositories must stay small and panel-specific.
- Hatch Analysis has the most complex hierarchy. Implement it after simpler Egg/Chicks paths prove the shared pattern.
- Dashboard queries will be easier, but only if sample rows consistently store summary fields and full identity context.
