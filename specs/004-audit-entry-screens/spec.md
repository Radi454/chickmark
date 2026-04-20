# Feature Specification: Phase 3 — All Audit Entry Screens

**Feature Branch**: `004-audit-entry-screens`  
**Created**: 2026-04-18  
**Status**: Draft  
**Input**: User description: "Phase 3 — All Audit Entry Screens"

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Start a New Audit (Priority: P1)

An auditor opens the app and taps the "New Audit" action. They see a list of 5 audit types. They select one, then pick a customer and (where applicable) a flock. They are taken to the data entry screen for that audit type.

**Why this priority**: This is the entry point for all audit work. Nothing else is usable until the audit type and context (customer/flock) are selected.

**Independent Test**: Launch the app → tap New Audit → select an audit type → select customer and flock → tap Continue → verify the correct data entry screen opens. Can be verified with no data saved.

**Acceptance Scenarios**:

1. **Given** the auditor is on the home screen, **When** they tap New Audit, **Then** a full-width list of 5 audit types is shown with their icons.
2. **Given** the auditor selects an audit type, **When** the customer/flock screen loads, **Then** the title shows the selected audit type and customers from the database are listed.
3. **Given** the auditor selects a customer, **When** they choose a flock, **Then** Continue becomes active and navigates to the correct data entry screen.
4. **Given** the auditor selects Setter or Hatcher Optimizing, **When** the selection screen loads, **Then** a Breed dropdown replaces the Flock dropdown.
5. **Given** the auditor taps Continue without selecting a customer, **When** validation fires, **Then** an error is shown and navigation is blocked.

---

### User Story 2 — Enter and Save Chick Quality Audit (Priority: P1)

An auditor completes a Chick Quality audit across 5 tabs: CHA Environmental, Pasgar Score, Chick Weights, YFBM, and CVT. Each tab can be saved independently and turns green after saving. All calculations update in real time as data is entered.

**Why this priority**: Chick Quality is the most data-rich audit and establishes the tabbed save pattern used by Hatch Analysis. It must work before other audit types are built.

**Independent Test**: Open a Chick Quality audit → fill the CHA tab → save → tab turns green → fill Pasgar with sample size 40 and increment Reflexes to 8 → verify score updates instantly → save all 5 tabs → confirm all green.

**Acceptance Scenarios**:

1. **Given** the Govee sector on CHA tab and BLE is available, **When** the auditor taps Scan & Connect, **Then** the device name, signal strength, temperature, and humidity display automatically.
2. **Given** no BLE device is found, **When** the CHA tab renders, **Then** the Govee sector shows a clearly disabled state with no crash.
3. **Given** the Pasgar tab with sample size 40, **When** Reflexes is incremented to 4, **Then** Reflexes % shows 10.0% and the final score updates instantly.
4. **Given** a Pasgar parameter's % exceeds 20%, **When** the value is set, **Then** a red alert indicator appears on that row immediately.
5. **Given** the Feather Dev row is filled in, **When** the Pasgar score calculates, **Then** Feather Dev count is excluded from the score formula.
6. **Given** 100 weights are entered in the Chick Weights tab, **When** any weight changes, **Then** AVG, Low Margin, High Margin, % in zone, and CV% all update instantly.
7. **Given** CV% exceeds 8%, **When** calculated, **Then** a red alert is shown.
8. **Given** any tab has filled data and the auditor taps Save, **When** save completes, **Then** the tab indicator turns green.
9. **Given** the auditor taps a 📷 icon, **When** camera or gallery opens and a photo is captured, **Then** a thumbnail is shown linked to that field.

---

### User Story 3 — Enter and Save Hatch Analysis Audit (Priority: P1)

An auditor completes a Hatch Analysis audit across 2 tabs. Hatch Results auto-calculates Hatchability, Fertility (from trays), and HOF. Egg Breakout shows parameters filtered by type, with troubleshooting available for high-alert parameters.

**Why this priority**: Hatch Analysis contains the troubleshooting feature and complex tray-based calculations that are central to the app's diagnostic value.

**Independent Test**: Open Hatch Analysis → add 2 trays → enter hatched/culled/dead → verify Hatchability/HOF/Fertility summary cards update → switch to Egg Breakout → select Hatch Residue → set one parameter above BMK+3% → verify 💡 appears → tap it → verify troubleshooting sheet opens with correct tabs.

**Acceptance Scenarios**:

1. **Given** tray infertile counts are entered, **When** any count changes, **Then** per-tray fertility and average Fertility recalculate instantly.
2. **Given** Hatchability, HOF, and Fertility are calculated, **When** the summary cards render, **Then** each shows the value and a green or red comparison against the breed benchmark.
3. **Given** Egg Breakout type is "Fresh Egg", **When** the parameters render, **Then** only Infertile, Early 24h, Early 48h, and Blood Ring rows appear.
4. **Given** Egg Breakout type is "Hatch Residue", **When** parameters render, **Then** all 9 residue parameters appear.
5. **Given** a parameter's % exceeds BMK + 3%, **When** the row renders, **Then** a red status and a 💡 icon appear.
6. **Given** the auditor taps 💡, **When** the troubleshooting sheet opens, **Then** Hatchery Causes and Farm/Flock Causes tabs are present, each with Management, Nutrition, Disease, and Other sections.

---

### User Story 4 — Enter and Save Setter / Hatcher Optimizing Audit (Priority: P2)

An auditor fills a Setter or Hatcher Optimizing single-screen audit with Govee BLE readings, CO2, and a 3×3 temperature grid. Each cell shows instant green/red status. The °C/°F toggle converts display only.

**Why this priority**: Single-screen audits are simpler to implement than tabbed ones. They reuse the temperature display logic from Chick Quality.

**Independent Test**: Open Setter Optimizing → enter 9 EST values in the grid → verify each cell shows green/red per 100–101°F optimum → verify AVG and CV% update → toggle to °C → verify values convert → save.

**Acceptance Scenarios**:

1. **Given** an EST cell value outside 100–101°F is entered, **When** typed, **Then** that cell shows red instantly.
2. **Given** all 9 EST values are entered, **When** any changes, **Then** AVG and CV% at the top update instantly.
3. **Given** the °C/°F toggle is tapped, **When** display updates, **Then** all shown temperatures convert correctly; stored values remain in °F.
4. **Given** a Hatcher Optimizing audit is open, **When** the screen renders, **Then** a Chick Panting Yes/No toggle and 📷 button appear in the Chick Panting sector.
5. **Given** no BLE device is available, **When** the Govee sector loads, **Then** it shows a disabled state with no crash.

---

### User Story 5 — Enter and Save Egg Storage & Handling Audit (Priority: P2)

An auditor fills an Egg Storage audit with Govee BLE, CO2, shell temperature, turning times, UV inspection trays (up to 10), and a 100-cell egg weight grid. All calculations are instant.

**Why this priority**: Egg Storage is field-rich and reuses the weight grid from Chick Quality, proving the shared component pattern. P2 because it depends on the grid widget established in US2.

**Independent Test**: Open Egg Storage → add 3 UV trays with affected counts → verify overall average affected % updates → fill weight grid → verify uniformity and CV% calculate → enter shell temp of 22°C → verify red "High" status → save.

**Acceptance Scenarios**:

1. **Given** shell temp is 22°C, **When** entered, **Then** a red "High (Bad)" status appears instantly.
2. **Given** shell temp is 18°C, **When** entered, **Then** a yellow "Low (Better)" status appears instantly.
3. **Given** a UV tray with 100 total and 15 affected is entered, **When** values are typed, **Then** % shows 15.0% and overall average updates.
4. **Given** 10 UV trays already exist, **When** the auditor attempts to add an 11th, **Then** the Add Tray button is disabled or an error is shown.
5. **Given** egg weight uniformity % is below 80%, **When** calculated, **Then** a red "Poor" status is displayed.

---

### User Story 6 — Add Multiple Hatches in One Session (Priority: P2)

An auditor taps [+] during a tabbed audit to add a second (or more) hatch. Each hatch has its own independent set of tabs and is stored as a separate database record linked to the session.

**Why this priority**: Multi-hatch sessions reflect real field workflows. This drives the session/hatch data model and must be defined before implementation.

**Independent Test**: Open Chick Quality → save 1 tab in Hatch 1 → tap [+] → fill 1 tab in Hatch 2 → save → switch back to Hatch 1 → verify data is intact.

**Acceptance Scenarios**:

1. **Given** the auditor taps [+], **When** a new hatch is created, **Then** a new empty set of tabs appears and the hatch counter increments.
2. **Given** multiple hatches exist, **When** the auditor switches between them, **Then** each hatch's data is independently preserved.
3. **Given** two hatches are saved, **When** stored, **Then** each is a separate database record linked to the same session.

---

### User Story 7 — View and Edit a Saved Audit (Priority: P3)

An existing saved audit is opened from Audit History in read-only mode. An Edit button unlocks all fields. Changes are saved back to the same record.

**Why this priority**: Read-only view exists from Phase 2. Edit-unlock mode is the new addition. P3 because creating new audits is the primary daily workflow.

**Independent Test**: Create and save an audit → open it from Audit History → verify fields are read-only → tap Edit → verify fields become editable → change a value → save → reopen → verify the change persisted.

**Acceptance Scenarios**:

1. **Given** a saved audit is opened, **When** the screen loads, **Then** all fields are displayed but not editable.
2. **Given** the auditor taps Edit, **When** edit mode activates, **Then** all form fields become editable.
3. **Given** the auditor saves in edit mode, **When** the audit is reopened, **Then** the updated values are shown.

---

### Edge Cases

- What happens when the auditor navigates away mid-audit without saving any tab — is a draft preserved or lost?
- What if a weight grid cell contains a non-numeric entry — is it excluded from calculations or does it block saving?
- What if benchmark data is missing for a breed or flock age — are comparison cards shown as "N/A" or hidden?
- What if the auditor adds 0 trays to Hatch Results — can the tab still be saved without fertility data?
- What if the photo file is deleted from local storage after being captured — how is the broken reference handled in read-only view?
- What happens to BLE scan state if the auditor navigates away mid-scan?
- What if local storage is full when attempting to save — is the auditor informed?

---

## Requirements *(mandatory)*

### Functional Requirements

**New Audit Flow**

- **FR-001**: The system MUST present an audit type selection screen with 5 full-width options and a distinct icon for each type.
- **FR-002**: After type selection, the system MUST show a context selection screen titled with the chosen audit type.
- **FR-003**: The Customer dropdown MUST load from local storage; the Flock dropdown MUST filter to the selected customer's flocks.
- **FR-004**: For Setter Optimizing and Hatcher Optimizing, the Flock dropdown MUST be replaced by a Breed dropdown (Ross308, Arbo, Avian, Cobb500, Hubbard, IR).
- **FR-005**: The Continue button MUST be disabled until all required context fields are selected.

**Data Entry — General**

- **FR-006**: Every data entry screen MUST use the gradient app bar displaying the audit type name.
- **FR-007**: Tabbed audits (Chick Quality, Hatch Analysis) MUST show Setter ID and Hatcher ID fields at the top; Egg Storage MUST NOT show these fields.
- **FR-008**: Each tab MUST have its own Save button that persists that tab's data to local storage immediately.
- **FR-009**: After a successful tab save, the tab indicator MUST visually turn green.
- **FR-010**: All calculated fields MUST update within 100ms of each keystroke with no manual submit.
- **FR-011**: The [+] button on tabbed audits MUST create a new hatch as a separate database record linked to the current session.
- **FR-012**: Temperature values MUST be stored in °F; the °C/°F toggle converts display values only.
- **FR-013**: All screens with temperature fields MUST include a °C/°F toggle in the top-right area.
- **FR-014**: Opening a saved audit MUST display it in read-only mode; an Edit button MUST unlock all fields for editing.
- **FR-015**: Local storage MUST be written first; remote sync is fire-and-forget with silent failure on error.

**Govee BLE**

- **FR-016**: All 5 audit types MUST include a Govee BLE sector with a Scan & Connect button.
- **FR-017**: On successful connection, device name, signal strength, temperature, and humidity MUST display automatically.
- **FR-018**: On BLE unavailability or scan failure, the Govee sector MUST show a disabled state without crashing the screen.

**Photo Handling**

- **FR-019**: Every 📷 icon MUST open camera or gallery selection.
- **FR-020**: Captured photos MUST be stored as local file paths linked to the audit record and the field key.
- **FR-021**: After capture, a thumbnail MUST replace the 📷 icon for that field.
- **FR-022**: Tapping a thumbnail MUST open full-size photo view.
- **FR-023**: If camera/gallery is unavailable, the 📷 button MUST degrade gracefully without crashing.

**Chick Quality — CHA Environmental**

- **FR-024**: CHA tab MUST provide optional manual entry fields for: CO2 (ppm), PM10, PM2.5, Air Velocity Spots 1–3, Air Inlet, Air Outlet, Noise Level; each with a 📷 icon.

**Chick Quality — Pasgar Score**

- **FR-025**: Pasgar tab MUST have configurable Sample Size (default 40) and six parameter rows: Reflexes, Beak, Navel, Belly, Leg, Feather Dev.
- **FR-026**: Each row MUST have [−] and [+] buttons plus a manual count entry field.
- **FR-027**: Each row % MUST calculate as `count / sample_size × 100` in real time.
- **FR-028**: Any row % > 20% MUST show a red alert indicator on that row instantly.
- **FR-029**: Final Score MUST calculate as `((sample_size × 10) − (reflexes + beak + navel + belly + leg)) / sample_size`; Feather Dev MUST be excluded from this formula.

**Chick Quality — Weights & Egg Uniformity (shared grid)**

- **FR-030**: The weight grid MUST be 4 columns × 25 rows = 100 numbered cells.
- **FR-031**: Enter/Next on a cell MUST move focus to the next cell.
- **FR-032**: The system MUST calculate in real time: AVG, Low Margin (AVG − 10%), High Margin (AVG + 10%), % in zone, CV% = (SD / AVG) × 100; empty cells excluded from calculations.
- **FR-033**: Zone display: < 80% → red Poor; 80–85% → yellow Good; > 85% → green Excellent.
- **FR-034**: CV% > 8% MUST show a red alert.
- **FR-035**: BMK Age MUST auto-calculate as `flock_age − 21 − storage_days`; BMK weight MUST auto-populate from benchmark table by breed; if missing, display "N/A".

**Chick Quality — YFBM**

- **FR-036**: YFBM tab MUST show a table: Chick Weight (g), Yolk Weight (g), %; 10 initial rows; [+ Add Row] for more.
- **FR-037**: Per-row % = `(yolk_weight / chick_weight) × 100`; 8–10% → green; outside → red; updates in real time.
- **FR-038**: AVG % and CV% MUST display at the top, updated in real time.

**Chick Quality — CVT / Hatcher CVT**

- **FR-039**: CVT section MUST have rows: Top, Middle, Bottom; each with Basket Entry, Temp, and 📷.
- **FR-040**: Each row: green if 103–105°F; red otherwise; updates in real time.
- **FR-041**: AVG Temp and CV% MUST update in real time at the top.

**Hatch Analysis — Hatch Results**

- **FR-042**: Hatch Results MUST include: Total Eggs Set, Hatched, Culled, Dead, Storage Days (default 0).
- **FR-043**: Hatchability = `hatched / total_set × 100`; Fertility = average of per-tray fertility; HOF = `hatchability / fertility × 100`; all real time.
- **FR-044**: Three summary cards MUST show Hatchability, HOF, Fertility vs. breed benchmark (green/red).
- **FR-045**: [+ Add Tray] MUST add a tray with: Tray ID, Position (Top/Middle/Bottom/Random), Tray Size, Infertile count; per-tray fertility = `(tray_size − infertile) / tray_size × 100`.

**Hatch Analysis — Egg Breakout**

- **FR-046**: Breakout type dropdown: Fresh Egg (default 1 day), Candled Egg (default 10 days), Hatch Residue (default 21 days); age field auto-filled and editable.
- **FR-047**: Parameters MUST filter by type: Fresh → 4; Candled → 5; Hatch Residue → 9.
- **FR-048**: Each parameter row: Name, Count, %, BMK%, Status (🔴 > BMK+3%; 🟡 ≤ BMK+3%; 🟢 ≤ BMK).
- **FR-049**: 🔴 rows MUST show a 💡 troubleshooting icon.
- **FR-050**: Tapping 💡 MUST open a bottom sheet with Hatchery Causes / Farm/Flock Causes tabs, each with Management, Nutrition, Disease, Other sections; content loaded from local pre-seeded database.
- **FR-051**: BMK Age = `flock_age − breakout_age − storage_days`.

**Setter Optimizing**

- **FR-052**: Screen MUST include: Breed dropdown, Setter ID, Incubation Age (1–18 days), Govee BLE sector, CO2 with 📷, 3×3 EST grid (rows: Door/Middle/Back; cols: Top/Middle/Bottom; each cell has 📷).
- **FR-053**: EST optimum 100–101°F; each cell instant green/red; AVG and CV% at top update in real time.

**Hatcher Optimizing**

- **FR-054**: Mirrors Setter Optimizing with: Hatcher ID, Incubation Age 18–21 days, CVT grid (optimum 103–105°F), and a Chick Panting Yes/No toggle with 📷.

**Egg Storage & Handling**

- **FR-055**: Screen MUST include: Govee BLE sector, CO2 with 📷, Shell Temp with 📷 and instant status (≤21°C green; >21°C red; <19°C yellow), Turning Times dropdown (No Turning / 1–5 times), UV Inspection section, and Egg Uniformity weight grid.
- **FR-056**: UV Inspection: up to 10 trays; each tray shows Total Eggs, Affected Count, % affected (auto), 📷, and delete button; overall Average Affected % updates in real time above the list.
- **FR-057**: Egg Uniformity grid MUST follow the same rules as FR-030–FR-035 using egg weight benchmarks.

### Key Entities

- **Audit Session**: Links one customer, one audit type, and one or more Hatch Records. Has a status (draft / complete) and a date.
- **Hatch Record**: A single hatch within a session; stores all tab data for that hatch. Each [+] tap creates a new Hatch Record.
- **Tray**: A hatch tray within Hatch Results or Egg Breakout, linked to a Hatch Record.
- **Photo**: A local file path linked to an audit record and a field key (e.g., `cha_co2`, `pasgar_reflexes_photo`).
- **Troubleshooting Entry**: Pre-seeded content (cause text, cause type, section) linked to a breakout parameter name.
- **Benchmark (BMK)**: A per-breed lookup table with age-indexed thresholds for chick weight, egg weight, hatchability, HOF, and fertility.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An auditor can complete a full single-hatch Chick Quality audit (all 5 tabs filled and saved) in under 10 minutes of active data entry.
- **SC-002**: All calculated fields (Pasgar score, CV%, uniformity %, averages) visibly update within 100ms of each keystroke.
- **SC-003**: 100% of Save actions complete locally even when the device is offline — no data is lost due to remote sync failure.
- **SC-004**: Troubleshooting content loads for all high-alert Egg Breakout parameters with no perceptible delay (content is local).
- **SC-005**: Toggling between °C and °F converts all displayed temperatures correctly with zero manual re-entry required.
- **SC-006**: Reopening a saved audit in read-only mode displays all previously entered data correctly for 100% of audits.
- **SC-007**: Adding up to 10 UV inspection trays in Egg Storage causes no visible performance degradation.
- **SC-008**: A Govee BLE scan failure produces a clearly communicated disabled state within 3 seconds with no crash.

---

## Assumptions

- The Govee BLE integration library is already present in the project or a graceful stub exists; BLE failure is handled at the service layer, not the UI layer.
- The `bmk_breeds` benchmark table is already seeded in the local database for all 6 breeds, indexed by flock age in weeks, covering chick weight, egg weight, hatchability, HOF, and fertility benchmarks.
- Troubleshooting content for all Egg Breakout parameters is already seeded in the local database (established in prior phases).
- The `audits` table schema already contains columns for all fields across all 5 audit types (established in Phase 2 foundation).
- Photos are stored in the app's local sandboxed storage directory; no cloud photo storage is required in this phase.
- The °C/°F toggle state is per-screen-session only and is not persisted globally, unless the existing AppProvider already manages this preference.
- Feather Dev is intentionally excluded from the Pasgar score formula — this is a domain rule.
- For Setter and Hatcher Optimizing, no flock is required because the audit captures machine-level data rather than flock-level data.
- Weight and uniformity calculations use only cells that have been filled — empty cells are excluded from AVG, SD, and zone calculations.
- If benchmark data is missing for a breed or age, comparison fields display "N/A" rather than hiding the field.
- The [+] multi-hatch button is available on tabbed audits (Chick Quality, Hatch Analysis) but not on single-screen audits (Setter, Hatcher, Egg Storage).
- Draft preservation on back-navigation (edge case above) defaults to showing a confirmation dialog offering to save or discard.
