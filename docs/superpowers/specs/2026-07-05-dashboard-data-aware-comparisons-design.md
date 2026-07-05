# Dashboard Data-Aware Comparisons Design

**Task ID:** dashboard-data-aware-comparisons
**Date:** 2026-07-05
**Status:** Approved direction; awaiting written-spec review

## Goal

Make every dashboard station comparison reflect how the audit was actually
sampled. A hierarchy level is a comparison control only when the selected data
contains at least two comparable sibling samples at that level. Unused or
single-value hierarchy levels must not appear as comparison filters.

## Scope

This behavior applies to every dashboard station sector that supports scoped
comparison. It changes dashboard query, grouping, and presentation behavior
only. Audit entry, panel-table persistence, sync, and database schemas remain
unchanged.

## BMK Age Selector

Each station sector owns an independent BMK age selector. The selector appears
before the hierarchy comparison controls and defaults to **All BMK Ages**.
Options are labeled by BMK age only, because a flock cannot have two visits at
the same BMK age in the supported workflow.

Selecting one BMK age restricts that sector to the corresponding audit session.
Leaving the selector at All shows each recorded BMK age separately rather than
pooling all visits into one value.

## All-Ages View

The default presentation is the existing table. Each BMK age is a separate
column or data point, followed by an overall average. The overall average gives
each recorded age equal weight; it is the arithmetic mean of the per-age
results, not a raw-sample-weighted mean.

In All Ages mode, only House and Machine are eligible comparison dimensions.
Each is shown only when at least two distinct comparable houses or machines
exist in the selected data. Trolley and Tray controls remain hidden because
they are session-local sampling details rather than stable longitudinal
identities.

When House or Machine comparison is active, the table shows each identity's
value at every recorded age, that identity's equal-age-weighted average, and an
overall average that gives each visible identity equal weight. A missing age is
displayed as No data and is excluded from averages rather than treated as zero.

The existing chart icon switches the same dataset to chart form. It does not
change filters, grouping, missing-value handling, or average calculations.

## Single-Age View

Selecting a BMK age starts with no hierarchy level selected and displays the
pooled result plus its overall average. The available controls can include
House, Machine, Trolley, and Tray, subject to the comparison-validity rules
below.

Users may select multiple eligible levels together. For example, selecting
House and Tray can show H1-T1, H1-T2, H2-T1, and H2-T2. The overall average
remains visible beside detailed comparison results.

## Comparison-Validity Rules

A hierarchy level is eligible only when at least one parent group contains two
or more distinct, nonblank children at that level. “Parent” means the nearest
applicable hierarchy above the level for that sector; top-level levels compare
within the selected sector and BMK age.

Examples:

- One tray with House, Machine, and Trolley unused: no hierarchy comparison
  controls.
- Two trays under one trolley: Tray is eligible; House, Machine, and Trolley
  stay hidden when each has fewer than two comparable values.
- H1-T1 and H2-T2 only: House is eligible, but Tray is not, because neither
  house contains multiple trays.
- H1 has T1 and T2 while H2 has only T1: House and Tray are eligible. H2-T2 is
  displayed as No data when both levels are selected.

Eligibility is computed from the currently selected sector and BMK-age scope.
Blank hierarchy values do not count as identities. Selecting multiple levels
preserves hierarchy order when generating combinations.

## State Transitions

Changing between All Ages and a specific age clears hierarchy selections that
are not valid in the destination mode. Any remaining selection is intersected
with the newly eligible levels so stale or impossible breakdowns cannot remain
active.

Changing Customer or Flock resets each sector to All BMK Ages and clears its
comparison selections. Collapsing and reopening a station during the same
dashboard visit does not reset valid selections.

## Implementation Shape

The existing per-sector period state in `ScopeComparisonProvider` remains the
source of BMK-age selection. The comparison engine will derive eligible layers
from the loaded leaf rows and expose those layers to the sector widgets. The
widgets will render only eligible controls rather than every layer allowed by
static sector configuration.

All-ages table/chart data will use an age-first result model. It will aggregate
each age independently, then compute equal-weight averages from those age-level
results. Optional House or Machine grouping is applied within every age before
the longitudinal series and averages are assembled.

Single-age table/chart data will continue using the existing scope grouping
engine, but it will start pooled and accept only the data-derived eligible
layers.

## Error and Empty States

- No rows for the sector: keep the existing empty state.
- Rows without BMK age: exclude them from the BMK-age series; do not invent an
  age label.
- One recorded age: All Ages still shows that age and the same value as the
  overall average.
- Missing identity at one age: show No data and exclude the missing value from
  that identity's average.
- A previously selected level becomes ineligible after a filter change: remove
  it automatically before recomputing groups.

## Validation

Focused provider/engine tests will cover:

- one tray produces no hierarchy controls;
- sibling-aware eligibility for House, Machine, Trolley, and Tray;
- multi-level House-plus-Tray grouping and No data combinations;
- All Ages returns separate age results plus an equal-age-weighted average;
- missing ages are excluded rather than treated as zero;
- All Ages offers only data-valid House and Machine comparisons;
- selecting one age starts pooled and exposes only valid session levels;
- table/chart toggling preserves the same filter and grouping state.

Focused widget tests will confirm the per-sector age selector, default table,
eligible control visibility, pooled initial state, retained overall average,
and existing chart-icon transition. `docs/LIVING_SPEC.md` will be updated after
the implementation to describe the shipped behavior.
