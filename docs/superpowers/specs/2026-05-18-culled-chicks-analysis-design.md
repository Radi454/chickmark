# Culled Chicks Analysis Design

## Context

Chick Quality currently saves Pasgar, YFBM, Chick Vent Temperature, and PM
Necropsy on the active `chick_quality` panel row. In comparison mode, each row
is scoped to the selected setter/hatcher sample. The new Culled Chicks Analysis
sector follows that same scope and appears directly after the PM Necropsy card
in the Chick Quality workbench.

## User Goal

Auditors need a structured way to record why chicks were culled, using the
provided hatchery-guide categories as reference material for both data entry and
dashboard interpretation.

## Data Entry

Add a collapsible `Culled Chicks Analysis` card after `PM Necropsy` in
`ChickQualityScreen`.

The panel captures:

- Inspected culled chicks sample size.
- Count per fixed subtype.
- Read-only hatchery observation and common-cause context per subtype.

The fixed subtype catalog is grouped as:

- Navel: Open / unhealed navel, String navel, Black button, Residual yolk /
  large abdomen.
- Sticky: Sticky chick, Albumen on feathers / glued down, Wet chick,
  Dehydrated / burned chick.
- Legs: Spraddle leg, Curled toes, Twisted legs / feet, Red hocks.
- Head: Crossed beak / crooked beak, Short beak, Missing eye / one eye,
  Exposed brain.
- Neuro: Stargazer / nervous signs, Wry neck.
- Small/Weak: Small chick, Weak / inactive chick.
- Hair Chick: Hair chick / sparse down.

Rows are count-only. Percentages are derived from the inspected culled chicks
sample size. Empty rows save as zero or are omitted from JSON, but the catalog
order remains stable in the UI and dashboard.

## Persistence

Persist the panel on the existing `chick_quality` row. No separate table or
station sample workflow is introduced.

Add additive columns:

- `culledChicksSampleSize INTEGER`
- `culledChicksAnalysisJson TEXT`
- `culledChicksTotalCount INTEGER`
- `culledChicksAffectedPct REAL`
- `culledChicksTopCategory TEXT`
- `culledChicksTopSubtype TEXT`

`culledChicksAnalysisJson` stores the subtype entries with stable IDs,
category, subtype label, count, description, common causes, and source labels.
Summary columns are derived during provider save so dashboard queries can stay
simple.

## Dashboard

Load Culled Chicks Analysis from `chick_quality` with the same dashboard filter
rules as the other Chick Quality measurements.

The dashboard sector shows:

- Latest or aggregate inspected sample size.
- Total recorded culled-chick findings.
- Affected percentage of inspected culled chicks.
- Top category and subtype.
- Problem interpretation using the provided subtype causes and source labels.

Interpretation is source-backed and lower-is-better. Since the provided guide
table does not define a numeric benchmark threshold, the dashboard does not
invent one. It flags `Review` when the affected percentage is greater than
zero. It labels a top category as dominant when that category contributes at
least 50% of recorded findings, and it surfaces likely causes from the top
subtype.

## Reference Content

Use the user-provided hatchery-guide table as the local benchmark/reference
catalog. Source labels are stored/displayed in short form, including Aviagen,
H&N International, Cobb, Petersime, Lohmann, Pas Reform, CABI, and ResearchGate
where applicable.

The app does not fetch these references at runtime. The catalog is static
application metadata, similar to existing troubleshooting seed data.

## Testing

Use test-first implementation for the behavior changes:

- Schema test: `chick_quality` includes the additive culled-chicks columns.
- Model/provider persistence test: saving a Chick Quality sample persists JSON
  and derived summary fields on the same row as PM.
- Widget test: the new panel renders after PM and accepts subtype counts.
- Dashboard repository/model test: aggregation returns top subtype/category and
  derived percentage.
- Dashboard widget test: the Chick Quality dashboard sector displays the new
  interpretation when analysis data exists.

## Documentation

Update `docs/LIVING_SPEC.md` after implementation to describe the implemented
UI, persistence fields, and dashboard behavior.

## Risks And Assumptions

- Existing local worktree changes touch the same files; implementation must work
  with current file contents and avoid reverting unrelated changes.
- The provided references are treated as qualitative interpretation sources, not
  numeric benchmark limits.
- The new sector follows the active Chick Quality sample scope, including
  setter/hatcher comparison mode.
