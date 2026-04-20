# Feature Specification: Phase 4 — BMK Screen + Settings + Home Screen + Logo

**Feature Branch**: `005-bmk-settings-home-logo`  
**Created**: 2026-04-18  
**Status**: Draft  
**Input**: User description: "Phase 4 — BMK Screen + Settings + Home Screen + Logo"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Breed Benchmarks (Priority: P1)

An auditor selects a breed and age to instantly see standard industry benchmark values for hatchability, fertility, HOF, production, egg weight, and chick weight — all read-only for reference during an audit.

**Why this priority**: Benchmark reference is core to the audit workflow; auditors need this to evaluate flock performance against standards.

**Independent Test**: Can be fully tested by navigating to the BMK screen, selecting a breed chip and an age, and confirming the correct single-row benchmark card is displayed with all 6 values.

**Acceptance Scenarios**:

1. **Given** the BMK screen is open, **When** the auditor taps a breed chip (e.g., Ross308) and selects an age from the dropdown, **Then** a single card displays Hatchability %, Fertility %, HOF %, Production %, Egg Weight (g), and Chick Weight (g) for that breed/age combination.
2. **Given** benchmark data is displayed, **When** the auditor attempts to edit any value, **Then** no editing is possible — all values are read-only.
3. **Given** a breed is selected, **When** the auditor opens the age dropdown, **Then** only ages available in the database for that breed are shown.

---

### User Story 2 - View Egg Breakout Benchmarks (Priority: P1)

An auditor filters egg breakout benchmark data by type (Fresh, Candled, or Residue) and age to see the relevant benchmark percentages for each egg breakout parameter.

**Why this priority**: Egg breakout benchmarks are referenced during audit entry; auditors must be able to quickly look up expected values by type and age.

**Independent Test**: Can be fully tested by navigating to Section 2 of the BMK screen, selecting each egg breakout type, choosing an age, and confirming only the relevant parameters are shown with correct values.

**Acceptance Scenarios**:

1. **Given** the Egg Breakout BMK section is visible, **When** the auditor selects "Fresh" type and an age, **Then** 4 parameters are shown: Infertile, Early 24h, Early 48h, Blood Ring.
2. **Given** "Candled" type is selected, **When** an age is chosen, **Then** 5 parameters are shown: Infertile, Early 24h, Early 48h, Blood Ring, plus Black Eye.
3. **Given** "Residue" type is selected, **When** an age is chosen, **Then** all 15 parameters are shown.
4. **Given** benchmark data is displayed, **When** the auditor attempts to edit any value, **Then** no editing is possible — all values are read-only.

---

### User Story 3 - Manage Audit Preferences in Settings (Priority: P2)

An auditor configures personal preferences (temperature unit, default sample sizes, tray size, storage days) that pre-populate audit entry forms, saving time on every audit.

**Why this priority**: Preferences reduce repetitive data entry across audits and personalize the experience, but audits can function without them.

**Independent Test**: Can be fully tested by opening Settings, changing preference values, closing and reopening Settings, and confirming values persisted.

**Acceptance Scenarios**:

1. **Given** the Settings screen is open, **When** the auditor toggles temperature unit between °F and °C, **Then** the selection is saved and persists after app restart.
2. **Given** the Settings screen is open, **When** the auditor changes Default Sample Size — Pasgar, Default Sample Size — Weights, Default Tray Size, or Default Storage Days, **Then** the new values are saved and persist across sessions.
3. **Given** fresh install with no preferences set, **When** Settings is opened, **Then** defaults are: Pasgar = 40, Weights = 100, Tray Size = 150, Storage Days = 0.

---

### User Story 4 - View Account Info and Sign Out (Priority: P2)

An auditor views their account details (name, email, role) and can sign out securely with a confirmation step to prevent accidental logout.

**Why this priority**: Account display and secure sign-out are required for multi-user environments.

**Independent Test**: Can be fully tested by opening Settings, verifying account section shows correct user info and role badge, and completing sign-out with confirmation.

**Acceptance Scenarios**:

1. **Given** the Settings screen is open, **When** the account section is viewed, **Then** the user's initials avatar, full name, email, and role badge (Admin/Auditor/Customer) are displayed and not editable.
2. **Given** the auditor taps [Sign Out], **When** the confirmation dialog appears, **Then** tapping "Confirm" clears the local session, clears SQLite cached token, and navigates to the login screen.
3. **Given** the confirmation dialog is shown, **When** the auditor taps "Cancel", **Then** nothing changes and the auditor remains on Settings.

---

### User Story 5 - Sync Status and Manual Sync (Priority: P3)

An auditor can check when data was last synced to the cloud and trigger a manual sync to ensure data is up to date.

**Why this priority**: Sync visibility and control are useful but not blocking for core audit functionality.

**Independent Test**: Can be tested by opening Settings > Sync section, verifying connection status and last-synced timestamp display, and tapping Sync Now.

**Acceptance Scenarios**:

1. **Given** the Settings Sync section is visible, **When** the device has internet, **Then** the Supabase connection status indicator shows "Connected" (or equivalent).
2. **Given** the last sync timestamp is stored, **When** the Sync section is viewed, **Then** the formatted date/time of last sync is displayed.
3. **Given** the auditor taps [Sync Now], **When** sync completes, **Then** the last synced timestamp updates to the current time.

---

### User Story 6 - Home Screen Audit Dashboard (Priority: P1)

An auditor opens the app to a home screen showing summary stats, quick-action buttons to start new customers/audits, filterable audit history, and can tap any past audit to review it.

**Why this priority**: The home screen is the primary entry point and navigation hub for all audit activity.

**Independent Test**: Can be tested by launching the app, verifying stats cards show counts, tapping filter chips, and confirming the audit list updates accordingly.

**Acceptance Scenarios**:

1. **Given** the home screen is open, **When** viewed, **Then** three stats cards show: Customers count, Active Audits count, and Total Audits count — sourced from local database.
2. **Given** the home screen is open, **When** the auditor taps [+ New Customer], **Then** the new customer flow is initiated.
3. **Given** the home screen is open, **When** the auditor taps [+ New Audit], **Then** the new audit flow is initiated.
4. **Given** audits exist, **When** a filter chip is selected (e.g., "Chick Quality"), **Then** the audit list shows only audits of that type.
5. **Given** the auditor taps an audit card, **When** the audit opens, **Then** it is displayed in read-only mode.
6. **Given** no audits exist, **When** the home screen is viewed, **Then** an empty state message is displayed.
7. **Given** audits exist, **When** the list is rendered, **Then** up to 20 audits are shown, ordered newest first, each showing: age badge (e.g. 35w), customer name, flock ID, breed, date, audit type, setter/hatcher ID, and status badge.

---

### User Story 7 - ChickMark Logo Displayed Across Screens (Priority: P2)

A user opening the app sees the real ChickMark SVG line-art logo (chick on egg with checkmark) on the login, register, pending approval, and settings screens — replacing the placeholder "C" circle.

**Why this priority**: Brand identity is important for a professional product but does not affect core functionality.

**Independent Test**: Can be tested by navigating to login, register, pending approval, and settings screens and confirming the ChickMark SVG logo is displayed at the correct size in each location.

**Acceptance Scenarios**:

1. **Given** the login screen is shown, **When** viewed, **Then** a large centered ChickMark SVG logo is displayed with the "CHICKMARK" wordmark in Georgia serif (#F65C00) and "HATCHERY AUDIT" tagline in small caps grey.
2. **Given** the register or pending approval screen is shown, **When** viewed, **Then** a small ChickMark SVG logo appears at the top of the screen.
3. **Given** the settings screen is open, **When** the account section is viewed, **Then** a small ChickMark SVG logo appears alongside the account info.
4. **Given** the logo is rendered, **When** inspected, **Then** it shows a chick sitting on a tall oval egg with a checkmark inside, drawn as #F65C00 stroke line art on transparent background — no fill.

---

### Edge Cases

- What happens when no benchmark data exists for the selected breed/age combination?
- How does the age dropdown behave when switching breeds (should reset to first available age)?
- What happens when Sync Now is tapped but the device is offline?
- What happens when the audit list has more than 20 items (only top 20 shown)?
- How are stats counts displayed when the database is empty (show 0)?

## Requirements *(mandatory)*

### Functional Requirements

**BMK Screen**

- **FR-001**: System MUST display a horizontally scrollable breed chip selector with options: Ross308, Arbo, Avian, Cobb500, Hubbard, IR.
- **FR-002**: System MUST populate the age dropdown with only the ages available in the database for the currently selected breed.
- **FR-003**: System MUST display a single benchmark card matching the selected breed and age, showing: Hatchability %, Fertility %, HOF %, Production %, Egg Weight (g), Chick Weight (g) — each with label above and large value below.
- **FR-004**: System MUST display all breed benchmark data as read-only (no editing).
- **FR-005**: System MUST display an "Egg Breakout BMK" section with a type filter: Fresh, Candled, Residue.
- **FR-006**: System MUST show an age dropdown (25–65 weeks) for egg breakout benchmarks.
- **FR-007**: For Fresh type, system MUST show only: Infertile, Early 24h, Early 48h, Blood Ring.
- **FR-008**: For Candled type, system MUST show: Infertile, Early 24h, Early 48h, Blood Ring, Black Eye.
- **FR-009**: For Residue type, system MUST show all 15 egg breakout parameters.
- **FR-010**: System MUST display egg breakout benchmark data as read-only.
- **FR-011**: Both sections MUST load data from the local SQLite database (bmk_breeds and bmk_egg_breakout tables).

**Settings Screen**

- **FR-012**: Settings MUST display an account section with: initials avatar circle, full name (read-only), email (read-only), and role badge (Admin/Auditor/Customer).
- **FR-013**: Settings MUST provide a temperature unit toggle (°F / °C) with default °F.
- **FR-014**: Settings MUST provide number fields for: Default Sample Size — Pasgar (default 40), Default Sample Size — Weights (default 100), Default Tray Size (default 150), Default Storage Days (default 0).
- **FR-015**: All preference values MUST persist across app sessions via SharedPreferences.
- **FR-016**: Settings MUST display a Sync section showing: Supabase connection status indicator, last synced timestamp, and a [Sync Now] button.
- **FR-017**: Settings MUST display the app version.
- **FR-018**: Settings MUST provide a [Sign Out] button (visually red) that shows a confirmation dialog before proceeding.
- **FR-019**: On confirmed sign-out, system MUST clear SQLite cached token and navigate to the login screen.

**Home Screen**

- **FR-020**: Home screen MUST display three stats cards: Customers count, Active Audits count, Total Audits count — sourced from local SQLite.
- **FR-021**: Home screen MUST display [+ New Customer] (outlined) and [+ New Audit] (filled orange) action buttons.
- **FR-022**: Home screen MUST display horizontally scrollable filter chips: All, Chick Quality, Hatch Analysis, Egg Storage, Setter Optimizing, Hatcher Optimizing.
- **FR-023**: The audit list MUST show up to 20 audits, ordered newest first, filtered by the selected chip.
- **FR-024**: Each audit card MUST display: age badge (orange pill, e.g. 35w), customer name (bold), flock ID, breed, date, audit type, setter/hatcher ID, and status badge (active/completed).
- **FR-025**: Tapping an audit card MUST open the audit in read-only mode.
- **FR-026**: When no audits exist, home screen MUST show an appropriate empty state.

**Logo**

- **FR-027**: System MUST replace the "C" circle placeholder with the ChickMark SVG line-art logo (chick on egg with checkmark inside, #F65C00 stroke, transparent background, no fill).
- **FR-028**: Login screen MUST show the logo large and centered, with "CHICKMARK" wordmark in Georgia serif (#F65C00) and "HATCHERY AUDIT" tagline in small caps grey.
- **FR-029**: Register and pending approval screens MUST show a small logo at the top.
- **FR-030**: Settings screen account section MUST show a small logo.

**General**

- **FR-031**: All screens MUST use the GradientAppBar component with the appropriate title.
- **FR-032**: All screens MUST follow existing code patterns in the codebase.

### Key Entities

- **BreedBenchmark**: Represents a benchmark row for a specific breed and flock age. Key attributes: breed name, age (weeks), hatchability %, fertility %, HOF %, production %, egg weight (g), chick weight (g).
- **EggBreakoutBenchmark**: Represents benchmark values for egg breakout analysis at a specific age. Key attributes: age (weeks), and up to 15 named percentage parameters.
- **UserPreferences**: Persisted user settings. Key attributes: temperature unit, default Pasgar sample size, default weights sample size, default tray size, default storage days.
- **AuditSummary**: Lightweight representation of an audit for list display. Key attributes: audit type, customer name, flock ID, breed, age, date, setter/hatcher ID, status.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An auditor can look up any breed benchmark in under 10 seconds by selecting a breed chip and age — with zero data entry required.
- **SC-002**: An auditor can look up egg breakout benchmarks for any type and age in under 10 seconds.
- **SC-003**: Preference changes persist across 100% of app restarts with no data loss.
- **SC-004**: The home screen loads with accurate stats and up to 20 audit records in under 2 seconds on a standard device.
- **SC-005**: Audit type filter chips correctly filter the audit list with 100% accuracy.
- **SC-006**: Sign-out completes within 3 seconds and always returns the user to the login screen.
- **SC-007**: The ChickMark SVG logo renders correctly at all required sizes with no visual artifacts on all supported screen densities.
- **SC-008**: All 4 screens with logo placement (login, register, pending approval, settings) display the logo without layout overflow or misalignment.

## Assumptions

- Breed benchmark data (bmk_breeds table) and egg breakout benchmark data (bmk_egg_breakout table) are pre-seeded in the SQLite database — this feature does not include data entry for benchmarks.
- The 15 egg breakout parameter names for Residue type are defined in the existing database schema; this spec assumes they already exist.
- The existing GradientAppBar widget is already implemented and reusable.
- User account data (name, email, role) is available from the authenticated session stored locally.
- The app version string is accessible via the standard Flutter package_info_plus or equivalent mechanism already in the project.
- SharedPreferences is already available as a project dependency or will be added.
- "Read-only mode" for audit viewing reuses existing audit detail screens with editing disabled.
- The pending approval screen is an existing screen in the auth flow.
- The ChickMark SVG will be created as an asset file (assets/images/chickmark_logo.svg) and referenced via flutter_svg or a custom painter.
- Supabase connection status can be determined by checking the existing Supabase client state.
