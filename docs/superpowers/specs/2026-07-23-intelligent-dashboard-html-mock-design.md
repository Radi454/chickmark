# Intelligent Dashboard HTML Mock Design

**Date:** 2026-07-23  
**Status:** Approved for implementation planning  
**Deliverable:** A self-contained HTML dashboard mock using fixture data  
**Primary reference:** Current Flutter dashboard code and `docs/LIVING_SPEC.md`

## Purpose

Create a high-fidelity dashboard mock that demonstrates how ChickMark can
combine three decision levels without turning the default view into a dense
report:

1. Executive portfolio oversight
2. Daily operational triage
3. Audit-specialist root-cause analysis

The mock must focus on the real dashboard's operational core. It must not
invent a replacement product model or treat mock conclusions as real hatchery
evidence.

## Scope And Delivery

- Deliver one portable, self-contained HTML file under `prototypes/`.
- Use clearly labeled fixture data with realistic ChickMark dimensions,
  metrics, benchmarks, and relationships.
- Keep all styling, data, icons, charts, and interactions inside the file so it
  opens offline.
- Do not modify Flutter production behavior in this task.
- Do not publish the mock to Sites. The requested publishing skill routes this
  task to its self-contained HTML handoff because the requested deliverable is a
  local mock file.

## Source-Of-Truth Boundaries

The mock will mirror implemented concepts from:

- `DashboardProvider` and the cascade Customer → Hatchery → Flock filters
- `ScopeComparisonProvider` per-sector state
- `ScopeConfigRegistry` station, sector, parameter, hierarchy, and aggregation
  definitions
- Incremental and cumulative scope views
- Actual-versus-BMK comparisons
- Egg Storage & Handling, Chicks, Hatch Analysis & Egg Breakouts, Setters,
  Hatchers, Govee Environmental Readings, and Lab Analysis
- ChickMark brand tokens in `AppColors` and `AppSizes`

The mock may improve information hierarchy and interaction design, but it must
not imply that every mock insight or forecast is already implemented in the
Flutter app.

## Dashboard Information Hierarchy

### 1. Scope And Freshness

The page starts with the real cascade context: customer, hatchery, and flock.
It also exposes the analysis window, comparison context, latest complete data
time, and fixture-data label. Global scope changes update the entire dashboard.
Sector-specific comparison settings remain independent when they are still
valid under the new global scope.

### 2. Executive Pulse

The first analytical band answers whether the selected operation is on track:

- Hatchability versus BMK
- Projected outcome and direction
- Critical operational risks
- Quality stability
- Data coverage and freshness

No opaque composite health score will be used. Forecasts and statuses expose
the signals that contribute to them.

### 3. Intelligent Action Center

Issues are ranked by severity, expected outcome impact, recency, and evidence
coverage. Each issue shows:

- Affected flock, station, machine, or sample
- Actual value, comparison value, and variance
- Direction and recent movement
- Likely contributing signals
- Recommended next check
- Confidence and evidence coverage

Selecting an issue opens the relevant station and preconfigures its sector,
metric, age, hierarchy, and comparison.

### 4. Root-Cause Analysis

The diagnostic workspace explains movement through:

- Outcome trend versus BMK
- Ranked variance contributors
- Cross-station signal chain
- Alert and audit timeline
- Sample outliers and distribution
- Evidence and calculation details

Likely causes are labeled as hypotheses. The mock does not present veterinary
treatment advice or causal certainty.

### 5. Operational Sectors

The lower page preserves expandable station cards and the real station order.
Each visible sector contains its own analysis controls, status summary, charts,
comparison table, and evidence affordances.

## Sector Comparison Architecture

Every sector receives an independent comparison builder. Options are
data-aware: unavailable layers, periods, metrics, and samples are hidden or
disabled rather than producing empty comparisons.

### Control Order

1. **Analysis mode:** Snapshot or Cumulative
2. **Period:** one BMK age/visit in Snapshot mode; all periods or a contiguous
   period range in Cumulative mode
3. **Breakdown path:** Pool → House → Machine → Trolley → Tray
4. **Samples:** searchable multi-select of valid groups
5. **Metric:** one sector-supported parameter
6. **Baseline:** BMK, pooled average, previous age/visit, or another sample
7. **View:** Chart or table

The breakdown path exposes only the hierarchy supported by that sector's real
sample schema. Selecting more layers narrows the grouping; removing layers
broadens it. Counts beside hierarchy choices explain how many comparable groups
will result before the user applies a choice.

### Snapshot Mode

- Defaults to one selected age or visit.
- Compares a selected sample with its BMK using paired bars.
- Supports up to six samples against the same BMK before switching to a ranked
  variance summary.
- Shows a ranked variance table for the selected metric.
- Keeps actual values severity-colored while BMK remains a quiet slate
  reference.
- Provides Pool and calculated average only when their aggregation semantics
  are valid and clearly labeled.

### Cumulative Mode

- Uses a line chart across flock ages for biological metrics and visits for
  hatchery operational settings.
- Each selected stable sample is a separate line.
- BMK is a dashed reference line.
- Missing periods remain visible as gaps and contribute to a coverage label.
- When more than four sample lines are selected, the chart switches to Pool plus
  min–max/range band and a ranked outlier list rather than drawing unreadable
  lines.
- The matching table retains exact values, BMKs, variance, aggregation method,
  and missing-data states.

### Smart Defaults

- One period starts at Pool, then suggests House or Machine when at least two
  comparable children exist.
- All-period analysis selects stable entities that recur across periods.
- The first benchmarked, decision-relevant metric is the default.
- Opening an intelligent insight preselects the affected period, hierarchy,
  sample, metric, and BMK baseline.
- Changing one sector never overwrites comparison state in another sector.

## Intelligence Model

The mock uses transparent deterministic rules rather than pretending to run an
unexplained AI model.

1. Detect actual-versus-BMK variance, threshold breach, adverse movement, or
   data-coverage risk.
2. Link related signals that share flock, period, station, or machine context.
3. Rank the issue using severity, estimated outcome relevance, recency, and
   evidence coverage.
4. Present a short hypothesis and recommended verification step.
5. Show the contributing observations so the user can challenge the
   interpretation.

Example signal chain:

`Egg storage duration → EST variability → late-dead residue → hatchability gap`

Confidence labels describe evidence coverage and consistency, not causal
certainty.

## Fixture Data Model

Fixture rows will preserve the analytical grain needed by the mock:

- Customer, hatchery, flock, breed, and flock age
- Audit date and visit
- Station and sector
- House, setter/hatcher machine, trolley, and tray where valid
- Metric identifier, actual value, BMK value, unit, directionality, and
  threshold
- Sample size, aggregation policy, freshness, and coverage
- Severity and linked evidence

The dataset will include multiple ages and repeated entities so snapshot and
cumulative comparisons demonstrate meaningful differences.

## Components

- Branded page header and scope bar
- Executive KPI strip
- Forecast/explanation panel
- Ranked intelligent-action feed
- Outcome-versus-BMK trend
- Root-cause contribution view
- Cross-station signal-chain panel
- Expandable station cards
- Per-sector comparison builder
- Snapshot paired-bar chart
- Cumulative multi-line chart with BMK reference and range fallback
- Exact comparison table
- Insight/evidence drawer
- Data freshness, fixture, confidence, and calculation badges

Each component has one clear responsibility and consumes the same filtered
fixture state so cards, charts, and tables reconcile.

## Visual System

The mock will reuse ChickMark's implemented visual language:

- Primary `#1769D8`
- Primary light `#079FE0`
- Primary dark `#193FC2`
- Accent `#E65100`
- Background `#F5F8FC`
- White and light-gray surfaces
- Good `#388E3C`
- Warning `#E67E22`
- Error `#DC2626`
- Benchmark slate `#CBD5E1`
- 10px cards and controls, pill-shaped filters, compact 8px-grid spacing
- Blue brand-gradient station headers
- System typography matching the Flutter application's practical UI tone

Severity color is reserved for status, variance, and action priority. It will
not tint large decorative areas.

## Responsive And Accessible Behavior

- Desktop uses a wide analytical canvas with aligned summary and diagnostic
  columns.
- Tablet collapses secondary diagnostics below the action center.
- Phone keeps the same priority order and turns dense filter rows into
  horizontally scrollable or expandable controls.
- Charts never require the page itself to scroll horizontally.
- Controls use visible labels, keyboard focus, and accessible state text.
- Color is paired with labels, icons, or patterns.
- Reduced-motion preference disables nonessential transitions.

## Empty, Partial, And Error States

- No sector data: explain which scope has no recorded samples.
- One sample only: allow sample-versus-BMK but disable multi-sample comparison.
- Missing BMK: retain actual trend and clearly mark the unavailable baseline.
- Partial age coverage: preserve chart gaps and show coverage percentage.
- Stale fixture/source: show freshness warning without blocking exploration.
- Unsupported hierarchy: hide the layer and explain availability in the
  comparison summary.
- Invalid selection after a parent-filter change: reset only the invalid child
  choice and communicate the reset.

## Verification

Implementation verification must cover:

- Self-contained offline opening with no external requests
- Desktop and phone rendering
- No unintended horizontal page overflow
- Global cascade filtering
- Independent per-sector filter state
- Snapshot/cumulative switching
- Hierarchy availability and selection reset behavior
- Sample-versus-BMK paired bars
- Multi-sample cumulative lines and large-selection range fallback
- Reconciliation of cards, charts, and tables
- Fixture, freshness, confidence, BMK, and aggregation labels
- Keyboard-accessible controls and reduced-motion behavior

## Out Of Scope

- Flutter implementation
- Live SQLite or Supabase connections
- Production forecasts or machine-learning models
- Editing, persistence, refresh, export, or sharing workflows
- Sites deployment
- Veterinary diagnosis or treatment recommendations

## Acceptance Criteria

The mock is ready when:

1. It visibly follows ChickMark branding and current dashboard structure.
2. The default view answers portfolio status and today's priority actions.
3. Every intelligent insight can be traced to visible fixture evidence.
4. Each operational sector demonstrates a data-aware comparison hierarchy.
5. A sample can be compared with its BMK in a paired bar chart.
6. Stable samples can be compared cumulatively across ages or visits in a line
   chart.
7. Dense selections become a readable Pool/range summary.
8. The file works offline at desktop and phone widths.
9. The existing Flutter application remains unchanged.

## Assumptions And Risks

- The mock demonstrates intended interaction behavior using fixture data; it
  does not prove that all necessary historical production data is currently
  populated.
- Some sectors support only a subset of House, Machine, Trolley, and Tray.
- Cross-station hypotheses depend on aligned flock, period, and machine context.
- A future Flutter implementation will need performance and persistence design
  beyond this HTML mock.
