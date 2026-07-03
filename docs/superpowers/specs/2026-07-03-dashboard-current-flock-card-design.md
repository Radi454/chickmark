# Dashboard Current Flock Card Design

## Goal

Make the current dashboard flock context visible without keeping the dashboard
filter area fixed while the user scrolls.

## Layout and behavior

- Move the existing Customer/Flock filter card into the dashboard's scrollable
  list so the entire section scrolls away with the remaining dashboard content.
- Keep the current filter controls at the top of that card.
- When a specific flock is selected, show a compact details area in the same
  card, below the filters.
- Show the flock name, current age in completed weeks, breed, and entrance date.
- When `All flocks` is selected, omit the details area because there is no
  single current flock to summarize.
- Preserve the existing phone and wider-screen filter layouts, clear-filter
  behavior, pull-to-refresh behavior, localization support, and downstream
  dashboard filtering.

## Visual treatment

Use the existing `AppCard`, spacing constants, typography, colors, and standard
Material icons already used by ChickMark. The detail area should be compact and
responsive, with wrapping fields so long flock names and narrow phone widths do
not overflow.

## Data flow

Derive the displayed flock from `DashboardProvider.selectedFlockId` and
`DashboardProvider.flocks`. Use `FlockModel.currentAgeWeeks` for age and the
model's existing `breed` and `entryDate` values. This feature adds no new state,
database fields, migrations, or persistence behavior.

## Validation

Add focused dashboard widget coverage that first fails without the feature and
then verifies:

- selecting a flock makes all four details visible in the filter card;
- the filter card is part of the scrollable dashboard content rather than a
  fixed sibling above it;
- phone-width rendering does not overflow.

Run the focused dashboard widget test and analyze only the touched Dart files.
Update `docs/LIVING_SPEC.md` to describe the implemented dashboard behavior.
