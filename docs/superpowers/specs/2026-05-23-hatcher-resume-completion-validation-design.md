# Hatcher Resume And Completion Validation Design

## Goal

Fix two audit-station workflow gaps:

- Hatchers must reopen and edit all saved hatcher machine rows, not only the
  first saved row.
- Station navigation must separate saving meaningful data from marking a station
  completed. Users can continue past an incomplete station after confirmation,
  but incomplete stations must not be added to `stationsCompleted`.

## Current Context

The visit flow currently supports five station keys: `egg`, `chicks`,
`hatch_analysis_egg_breakouts`, `setters`, and `hatchers`.
`AuditSessionScreen` hydrates station drafts from panel rows before rendering
each station. Egg, Chicks, Hatch Analysis, and Setters receive all hydrated
draft rows and station samples. Hatchers receives only `initialAudit`, so saved
multi-hatcher rows are not restored into the Hatcher machine-scope chip flow.

Current station navigation treats a successful save as enough to mark the
station completed. That is too light for audit workflow: a station can write
default-only or partial rows and still advance completion.

## Decisions

- Use station-specific completion validation.
- A sector counts as meaningful once the user entered meaningful data in that
  sector. The user does not need to fill every field in the sector.
- Optional sector data can be saved even when the station core requirement is
  missing.
- If the core requirement is missing, show a confirmation dialog before moving
  forward. If confirmed, save meaningful data, clean blank or invalid partial
  rows, navigate forward, and do not mark the station completed.
- If the user cancels, stay on the current station.
- If the final selected station is incomplete, the visit session must remain
  in progress.

## Hatcher Resume And Edit

`HatcherOptimizingScreen` will accept `initialAudits` and
`initialStationSamples`, matching the Setters screen contract. The session frame
will pass all hydrated Hatcher rows and samples into the screen.

The Hatcher screen will initialize `AuditProvider` with:

- `existingAudit`: the first restored hatcher row for compatibility.
- `existingAudits`: all restored hatcher machine rows.
- `existingStationSamples`: restored hatcher station samples.

The existing Hatcher machine-scope chips will then represent all restored
machines. Switching between chips must restore each machine's own hatcher
number, setpoints, incubation age/hour, CO2, CVT grid/photos, chick panting, and
meconium values. Saving after editing any restored machine must update that
machine's `hatcher_optimizing` row instead of collapsing the station back to one
row.

## Completion Validation

Introduce a station completion validation result that can be used by
`AuditSessionScreen` before calling `markCurrentStationCompleted`.

The result should distinguish:

- `complete`: station has meaningful saved data and satisfies its core
  completion rule.
- `savedButIncomplete`: station has meaningful data, but the station core rule
  is missing.
- `emptyOrDiscarded`: station has no meaningful data after cleanup.
- `failed`: persistence failed and navigation must not continue.

The station-specific core map is:

- Egg: `egg_storage` or `egg_quality` has meaningful user-entered data.
- Chicks: `chick_quality` or `chick_weights` has meaningful user-entered data.
- Hatch Analysis & Egg Breakouts: the active breakout type has meaningful
  breakout or hatch-result data.
- Setters: `setter_optimizing` has meaningful machine data such as setter
  number, setpoints, turning angle, CO2, or EST readings.
- Hatchers: `hatcher_optimizing` has meaningful machine data such as hatcher
  number, setpoints, incubation age/hour, CO2, CVT readings, chick panting, or
  meconium.

When the user taps `Next Station`, `Back`, a reachable station node, or the
final `Save`, the app should run the station exit path:

1. Prepare station-local pending work, such as Egg camera/grid cleanup.
2. Save meaningful sector data.
3. Delete or tombstone blank/default-only rows and invalid partial sector rows.
4. Validate whether the station core requirement is met.
5. If complete, mark the station completed only for forward or final
   completion actions. Back navigation and switching to an already reachable
   station save/clean up the current station but do not newly complete it.
6. If incomplete, ask whether to continue without completing the station.
7. If confirmed, navigate without adding the station to `stationsCompleted`.

The dialog copy should be short and specific, for example:

> This station does not have enough core data to mark complete. Continue without
> completing this station?

## Data Cleanup

The save path should not leave rows that imply progress when they contain no
meaningful user-entered data. Blank/default-only rows should be removed or
tombstoned using the existing panel cleanup patterns.

Meaningful optional data should remain saved even if the station core rule is
missing. For example, if a user entered optional sector data but skipped the
station's core sector, the app can save that meaningful optional row, continue
after confirmation, and leave the station uncompleted.

## User Experience

The user can continue through a visit even when a station is incomplete. The
progress strip should only show a check mark for stations in
`stationsCompleted`. Incomplete skipped stations remain reachable through the
progress strip only when they are current, already reached, or otherwise allowed
by existing navigation rules.

For completed visit review/edit mode, re-saving a complete station keeps the
visit completed only when the station still satisfies its completion rule. If an
edit removes core data from a previously complete station, the station should be
removed from completion progress and the visit should no longer be treated as
fully complete unless all selected stations remain complete.

## Testing

Add or update tests for:

- Hatchers reopen with multiple saved hatcher rows and show multiple
  machine-scope chips.
- Editing a reopened Hatcher machine saves that machine independently.
- An incomplete station can navigate forward after confirmation without being
  added to `stationsCompleted`.
- A station with meaningful optional data but missing core data saves the
  meaningful data and remains uncompleted.
- Blank/default-only rows are removed or tombstoned and do not create a false
  completion signal.
- Final selected station with incomplete core leaves the visit in progress.
- Completed visit review/edit removes station completion if a user deletes core
  data from a previously complete station.

## Out Of Scope

- Rebuilding dashboard station sectors.
- Adding new audit station types.
- Replacing all legacy-named in-memory `AuditModel` fields.
- Changing the station selection list or station order behavior.
