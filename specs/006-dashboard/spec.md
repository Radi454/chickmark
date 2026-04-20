# Feature Specification: Phase 5 — Dashboard

**Feature Branch**: `006-dashboard`  
**Created**: 2026-04-18  
**Status**: Draft  

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Filter and View Hatch Analysis (Priority: P1)

An auditor selects a customer, then a flock, then a BMK age (or "All") from the sticky top filter bar. The dashboard instantly refreshes all sections to show aggregated hatch analysis metrics — Hatchability, Fertility, HOF, Culled, and Dead percentages — each compared to the relevant benchmark. The auditor switches between Bar, Line, and Circular chart views to understand current performance and trends.

**Why this priority**: Hatch Analysis is the primary KPI summary. It is the most frequently consulted section and validates the entire cascade filter mechanism, which all other sections depend on.

**Independent Test**: Can be tested by selecting a customer/flock/age and verifying that the five hatch metrics display, benchmark indicators are shown, and all three chart types render without implementing any other section.

**Acceptance Scenarios**:

1. **Given** audit data exists for a flock, **When** the auditor selects that customer → flock → BMK age, **Then** the Hatch Analysis section shows the five metrics as averages across all matching samples, each with a colour-coded BMK indicator.
2. **Given** the auditor is viewing a Bar chart, **When** they tap the Line chart toggle, **Then** the chart transitions to a trend-over-time line chart showing historical values alongside the BMK reference line.
3. **Given** "All" is selected for BMK age, **When** the section loads, **Then** values shown are the average across every audit age for that flock.
4. **Given** no audit data exists for the selected filter combination, **When** the section loads, **Then** an empty state message is shown and no chart is rendered.

---

### User Story 2 — Browse Egg Breakout Analysis (Priority: P2)

An auditor filters by breakout type (Fresh, Candled, or Residue) within the Egg Breakout section. The relevant parameters appear with colour-coded severity indicators against BMK thresholds. The auditor also browses a photo grid of egg breakout images captured during audits, tapping any photo to view it full-screen with pinch-to-zoom.

**Why this priority**: Egg Breakout provides root-cause data for hatch problems. The sub-type filter and photo grid introduce UI patterns reused in several later sections.

**Independent Test**: Can be tested independently using the breakout type filter toggles, verifying parameters change, BMK indicators appear, and photos display in a 3-column grid.

**Acceptance Scenarios**:

1. **Given** breakout type is "Fresh", **When** the section loads, **Then** only Infertile, Early 24h, Early 48h, and Blood Ring parameters are shown.
2. **Given** a parameter value exceeds BMK + 3%, **When** displayed, **Then** a red indicator is shown; if ≤ BMK + 3% but above BMK, a yellow indicator; if within BMK, a green indicator.
3. **Given** photos are attached to egg breakout entries, **When** the auditor scrolls to the photo grid, **Then** photos appear in a 3-column grid and tapping one opens a full-screen zoomable view.

---

### User Story 3 — Analyse Chick Quality Subsections (Priority: P2)

An auditor reviews the five Chick Quality subsections — Chick Weights, Pasgar Score, CVT, YFBM, and CHA Environmental — each with relevant charts and photo grids. Charts show averages and trends against scientific thresholds (e.g., CV% vs 8%, CVT vs 103–105 °F, YFBM vs 8–10%).

**Why this priority**: Chick Quality covers live-animal welfare KPIs with the most subsections; completing this story validates the collapsible subsection pattern used throughout.

**Independent Test**: Can be tested by verifying that each subsection renders its charts and photo grids independently.

**Acceptance Scenarios**:

1. **Given** chick weight data exists, **When** the auditor views Chick Weights, **Then** three line charts display: AVG weight trend vs BMK, Uniformity % vs thresholds, and CV% vs 8%.
2. **Given** Pasgar data exists, **When** the Pasgar Score subsection loads, **Then** a circular chart shows the overall score out of 10, a column chart shows per-parameter percentages, and feather development photos appear in a grid.
3. **Given** CVT readings exist, **When** the CVT subsection loads, **Then** the circular chart shows AVG CVT against the 103–105 °F optimum with a green or red indicator.

---

### User Story 4 — Compare Setters and Hatchers (Priority: P3)

An auditor uses checkboxes to select which setters (or hatchers) to compare side-by-side. The selected machines' hatch results, egg breakout parameters, temperature readings, CO2 levels, and (for hatchers) chick panting trends appear in aligned columns alongside BMK reference values. Colour-coded indicators immediately highlight underperforming machines.

**Why this priority**: Multi-machine comparison delivers operational insight but depends on all earlier data entry screens being complete; it is lower priority than per-flock analytics.

**Independent Test**: Can be tested by selecting multiple setters and verifying that side-by-side columns render for each active setter plus BMK.

**Acceptance Scenarios**:

1. **Given** records exist for three setters, **When** the auditor checks Setter 1 and Setter 3, **Then** two side-by-side result columns plus a BMK column are shown for each metric.
2. **Given** a setter's Hatchability % is below BMK, **When** displayed, **Then** a red indicator appears next to that value.
3. **Given** no data exists for a machine, **When** its checkbox is ticked, **Then** the column shows an empty state rather than zeroes.

---

### Edge Cases

- What happens when a customer has no flocks? → Customer dropdown shows the name but Flock dropdown is empty; all sections show empty states.
- What happens when a flock has only one audit entry? → Line charts render a single point; trend lines are omitted; bar and circular charts render normally.
- What happens when photos fail to load from local storage? → Broken-image placeholder shown in the grid cell; other photos are unaffected.
- What happens when the temperature unit toggle is changed mid-session? → All temperature values and thresholds in all sections convert instantly without page reload.
- What happens when the auditor collapses and then re-expands a section? → Section content is preserved; no additional data fetch is triggered.

## Requirements *(mandatory)*

### Functional Requirements

**Cascade Filter**

- **FR-001**: The screen MUST display a sticky top filter bar with three dependent dropdowns: Customer → Flock → BMK Age.
- **FR-002**: The Flock dropdown MUST populate only with flocks belonging to the selected customer.
- **FR-003**: The BMK Age dropdown MUST list all distinct ages recorded in the database for the selected flock, plus an "All" option.
- **FR-004**: Selecting "All" for BMK Age MUST cause all sections to display the average across every audit age for that flock.
- **FR-005**: Any change to any filter value MUST immediately refresh all six sections without requiring a manual refresh action.

**Section Layout & Navigation**

- **FR-006**: All six sections MUST be stacked vertically on a single scrollable page.
- **FR-007**: Each section MUST be collapsible and expandable by tapping its header.
- **FR-008**: A loading indicator MUST be shown while section data is being fetched.
- **FR-009**: Each section MUST display a contextually appropriate empty state when no data matches the current filter.

**Section 1 — Hatch Analysis**

- **FR-010**: The section MUST display average Hatchability %, Fertility %, HOF %, Culled %, and Dead % across all samples matching the filter.
- **FR-011**: Each metric MUST be compared to its benchmark: Hatchability/Fertility/HOF ≥ BMK (higher is better); Culled ≤ 1%; Dead ≤ 0.2%.
- **FR-012**: The section MUST offer three chart type options (Bar, Line, Circular/Donut) switchable via a toggle control.
- **FR-013**: Bar charts MUST show actual vs BMK values side by side. Line charts MUST show the trend over time with a BMK reference line. Circular/Donut charts MUST show percentage achievement vs BMK.

**Section 2 — Egg Breakout**

- **FR-014**: The section MUST provide a filter for breakout type: Fresh, Candled, or Residue.
- **FR-015**: Parameters shown MUST match the selected breakout type: Fresh shows 4 parameters; Candled adds Black Eye; Residue shows all parameters.
- **FR-016**: Each parameter MUST display a colour-coded severity indicator: red if value > BMK + 3%, yellow if ≤ BMK + 3% above BMK, green if within BMK.
- **FR-017**: The section MUST display a photo grid sourced from egg breakout audit entries.

**Section 3 — Chick Quality**

- **FR-018**: The section MUST contain five collapsible subsections: Chick Weights, Pasgar Score, CVT, YFBM, and CHA Environmental.
- **FR-019**: Chick Weights MUST show three line charts: AVG weight trend vs BMK, Uniformity % vs thresholds, CV% vs 8%.
- **FR-020**: Pasgar Score MUST show a circular overall score (X.X/10), a column chart for each parameter (Reflexes, Beak, Navel, Belly, Leg), a circular Feather Development %, and a feather development photo grid.
- **FR-021**: CVT MUST show a circular chart for AVG CVT vs the 103–105 °F optimum with a green/red indicator and a photo grid.
- **FR-022**: YFBM MUST show a line chart for AVG YFBM % vs 8–10% optimum, a CV% trend line, and a photo grid.
- **FR-023**: CHA Environmental MUST show individual line charts for CO2, PM10, PM2.5, Air Velocity, and Noise Level trends, plus a photo grid.

**Section 4 — Egg Storage**

- **FR-024**: Egg Uniformity MUST show three line charts: AVG egg weight vs BMK, Uniformity % vs thresholds, CV% vs 8%.
- **FR-025**: Shell Temperature MUST show a line chart vs the 19–21 °C optimum with green/red indicators, a °C/°F toggle, and a photo grid.
- **FR-026**: UV Inspection MUST show a bar chart of % affected per audit visit, a trend line chart, and a photo grid.

**Section 5 — Setter Optimizing**

- **FR-027**: The section MUST show checkboxes listing available setters (from DB records); checking a setter adds its column to all subsection comparisons.
- **FR-028**: Hatch Results MUST display side-by-side columns for selected setters + BMK for Hatchability, Fertility, HOF, Culled, and Dead, with green/red per-value indicators.
- **FR-029**: Egg Breakout (Early) MUST compare Infertile, Early 24h, Early 48h, and Blood Ring per setter vs BMK.
- **FR-030**: EST Comparison MUST show AVG EST per setter vs the 100–101 °F optimum, CV% per setter, a °C/°F toggle, and Bar/Line/Circular chart options.
- **FR-031**: CO2 trend MUST be shown per setter as a line chart.
- **FR-032**: A photo grid from setter entries MUST appear at the bottom of this section.

**Section 6 — Hatcher Optimizing**

- **FR-033**: The section MUST show checkboxes listing available hatchers (from DB records).
- **FR-034**: Hatch Results comparison MUST mirror Section 5's layout but use hatcher data.
- **FR-035**: Egg Breakout (Late) MUST compare Late Dead, External Pip, Exposed Brain, Crossed Beak, Contaminated, and Cracked per hatcher vs BMK.
- **FR-036**: CVT Comparison MUST show AVG CVT per hatcher vs 103–105 °F optimum, CV% per hatcher, a °C/°F toggle.
- **FR-037**: CO2 levels per hatcher MUST be shown as a line chart.
- **FR-038**: Chick Panting trend MUST show % Yes vs No per hatcher over time.
- **FR-039**: A photo grid from hatcher entries MUST appear at the bottom of this section.

**Charts (all sections)**

- **FR-040**: All charts MUST animate on initial load.
- **FR-041**: All charts MUST display the value on tap/hover.
- **FR-042**: All charts MUST show a BMK reference line (grey dashed).
- **FR-043**: Actual values MUST use the colour #F65C00 (orange). Values above BMK (bad direction) MUST use #E24B4A (red). Values within or below BMK (good direction) MUST use #3a9a5c (green).

**Photo Grids (all sections)**

- **FR-044**: Photo grids MUST use a 3-column layout.
- **FR-045**: Tapping a photo MUST open a full-screen viewer.
- **FR-046**: The full-screen viewer MUST support pinch-to-zoom.
- **FR-047**: When no photos are available, an empty state MUST be shown in place of the grid.

### Key Entities

- **Customer**: Organisation whose hatchery is being audited; parent of flocks.
- **Flock**: A batch of parent birds associated with a customer; identified by age (weeks).
- **Audit Session**: A single audit visit recording date, flock, and all measurement sections.
- **Benchmark (BMK)**: Target thresholds per metric, associated with a flock age; stored in the database.
- **Hatch Analysis Record**: Per-session aggregate metrics (Hatchability, Fertility, HOF, Culled, Dead).
- **Egg Breakout Record**: Per-session breakout counts by type and category, with optional photos.
- **Chick Quality Record**: Per-session weight, Pasgar, CVT, YFBM, and CHA environmental readings with photos.
- **Egg Storage Record**: Per-session egg uniformity, shell temperature, and UV inspection data with photos.
- **Setter / Hatcher Record**: Per-session machine-specific measurements including EST/CVT, CO2, and breakout data.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An auditor can select a customer, flock, and age, and see all six sections populated within 2 seconds on a device with local data.
- **SC-002**: Changing any cascade filter value refreshes all visible sections within 1 second.
- **SC-003**: 100% of metrics in all sections display a visible benchmark comparison indicator (colour or reference line).
- **SC-004**: An auditor can switch between all three chart types in Section 1 without any section reloading or data re-fetching.
- **SC-005**: Photo grids load and display thumbnails within 1 second per grid; full-screen view opens within 0.5 seconds of tap.
- **SC-006**: All six sections correctly show an empty state (no blank screens or errors) when no matching data exists.
- **SC-007**: The temperature unit toggle (°C/°F) converts all displayed temperature values instantly across all sections where it appears.
- **SC-008**: Collapsing and re-expanding any section takes under 0.3 seconds with no visible data loss.

## Assumptions

- All audit data is already stored locally in SQLite by the time the dashboard is viewed; no network request is required to display the dashboard.
- Benchmark values are pre-configured in the database per flock age; the dashboard reads but does not edit benchmarks.
- The `fl_chart` package will be added to `pubspec.yaml` as a dependency before implementation begins.
- Temperature conversions use standard formulae (°C × 9/5 + 32 = °F); no server-side conversion is needed.
- Photo files are stored on the device's local file system; the database stores file paths only.
- A flock may have zero audit sessions; the dashboard handles this gracefully with empty states.
- The dashboard is read-only; no data entry or editing occurs on this screen.
- Existing `AppColors` and `AppTextStyles` from the project's design system are used for all styling; no new global theme tokens are introduced.
- The "setter" and "hatcher" machine identifiers are stored as named entries in the database per audit session.
- Chick Panting data (Yes/No) is recorded as a boolean/percentage field in the hatcher audit table.
