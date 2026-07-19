# Feature Specification: Dashboard Intelligence and Actionability

**Feature Branch**: `001-dashboard-intelligence`
**Created**: 2026-07-12
**Status**: Approved for implementation
**Input**: Implement the approved dashboard enhancements covering hatchery scope, freshness and coverage, explicit calculation policy, canonical aggregates, cross-station attention, action ownership, historical analysis, an analytics read model, loading performance, and bilingual accessible responsive polish.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Trust the Selected Operational Scope (Priority: P1)

An auditor or administrator selects a customer, hatchery, and optional flock and sees only measurements, machines, houses, environmental captures, comparisons, and alerts belonging to that scope. Portfolio mode may summarize multiple customers, but it never presents pooled corrective-action details as though they belong to one operation.

**Why this priority**: Correct operational scope is required before any displayed benchmark, trend, or recommendation can be trusted.

**Independent Test**: Create two customers or hatcheries with identically named houses and machines, then verify that a selected operational scope never mixes their values and that portfolio mode does not expose misleading pooled triage.

**Acceptance Scenarios**:

1. **Given** an administrator with access to multiple customers, **When** the dashboard opens without a concrete customer and hatchery selection, **Then** it shows a portfolio summary and withholds detailed corrective triage.
2. **Given** two hatcheries that both contain `H1` and `S1H1`, **When** one hatchery is selected, **Then** every station comparison and alert uses rows from that hatchery only.
3. **Given** a customer-role user, **When** the dashboard opens, **Then** the customer is fixed to that user's assignment and only valid hatcheries and flocks are selectable.

---

### User Story 2 - Understand Data Freshness, Coverage, and Calculation Confidence (Priority: P1)

An operational user can immediately tell how recent, complete, synchronized, and statistically supported every dashboard conclusion is. Old environmental readings are clearly historical rather than active alarms, and calculated values disclose their aggregation basis.

**Why this priority**: A correct number can still cause a wrong decision when its age, missing evidence, denominator, or aggregation method is hidden.

**Independent Test**: Load a scope containing current and stale captures, partially completed stations, missing photos, unequal sample sizes, and an offline sync state; verify that each condition is visible without opening the source audit.

**Acceptance Scenarios**:

1. **Given** a saved environmental capture older than the active freshness window, **When** it is the newest capture for a place, **Then** the dashboard labels it historical/stale and does not count it as a current action alert.
2. **Given** multiple captures on the same day, **When** the latest reading is determined, **Then** the latest recording timestamp wins rather than an arbitrary row for that date.
3. **Given** a station with partial measurements or evidence, **When** it renders, **Then** the user sees completion, sample, missing-data, and photo-coverage indicators.
4. **Given** an aggregate spanning ages or samples, **When** it renders, **Then** the calculation basis and contributing count are available in plain language.
5. **Given** a load or calculation failure, **When** the dashboard settles, **Then** the affected section shows a recoverable error state instead of appearing empty or in target.

---

### User Story 3 - Act on Consolidated Cross-Station Findings (Priority: P2)

An auditor sees one prioritized "What needs attention" area that consolidates related threshold breaches and lets the user open the exact source station, sample, evidence, or audit. A finding can be assigned, tracked, annotated, and resolved with evidence.

**Why this priority**: The dashboard should convert analysis into accountable hatchery work rather than repeating generic warning cards.

**Independent Test**: Trigger related issues across two stations, create an action from the consolidated finding, assign it, add a due date and note, then resolve it with evidence and verify that the history remains available offline and after sync.

**Acceptance Scenarios**:

1. **Given** several related alerts in one selected scope, **When** the dashboard loads, **Then** it ranks and consolidates them by severity, benchmark gap, recency, and data confidence.
2. **Given** a consolidated finding, **When** the user opens it, **Then** the app navigates to the exact source audit, panel row, metric, and linked evidence when available.
3. **Given** a finding, **When** an authorized user creates an action, **Then** owner, status, due date, notes, first/last observed times, and resolution evidence persist offline and synchronize across devices.
4. **Given** a previously resolved issue that reappears, **When** new supporting data arrives, **Then** the user can distinguish recurrence from the earlier resolution.

---

### User Story 4 - Compare Current Performance with History (Priority: P2)

An operational user can compare the latest valid result with the previous comparable audit and see new, persistent, improving, and worsening issues while retaining the approved per-sector BMK-age and equal-age comparison behavior.

**Why this priority**: Actual-versus-benchmark alone cannot show whether corrective work is succeeding or a problem is becoming persistent.

**Independent Test**: Record at least two comparable visits for the same scope and verify latest/previous deltas, trend classification, persistent-breach status, and the existing all-age averages.

**Acceptance Scenarios**:

1. **Given** two comparable visits, **When** a metric is viewed, **Then** the latest value, previous value, signed delta, and trend direction are shown.
2. **Given** a breach across consecutive comparable visits, **When** the dashboard loads, **Then** it is marked persistent rather than newly emerged.
3. **Given** all BMK ages, **When** the existing overall result is shown, **Then** it remains an equal-age average and is labeled as such.
4. **Given** missing age or scope intersections, **When** a trend is calculated, **Then** missing data remains absent and never counts as zero.

---

### User Story 5 - Use a Fast, Responsive, Bilingual Dashboard (Priority: P3)

Users can review the dashboard efficiently on phone, tablet, and desktop in English or Arabic, with balanced use of available width, localized metric language, readable secondary information, and accessible interaction semantics.

**Why this priority**: The analysis is only useful when users can scan, understand, and operate it in their field environment.

**Independent Test**: Exercise the complete dashboard at phone and desktop widths in English and Arabic, using touch, keyboard, and screen-reader semantics, while loading a representative multi-station dataset.

**Acceptance Scenarios**:

1. **Given** a desktop-width viewport, **When** comparison tables and charts render, **Then** they use the available width without large empty regions or clipped controls.
2. **Given** Arabic mode, **When** the dashboard renders, **Then** static labels, metrics, notes, alerts, and action states are professionally localized and directional layout remains correct.
3. **Given** keyboard or assistive-technology navigation, **When** the user traverses filters, collapsible stations, charts, alerts, and actions, **Then** each control has a meaningful label, state, and focus order.
4. **Given** a representative multi-station dataset, **When** filters or cumulative views change, **Then** visible results settle promptly and existing content is not replaced by unnecessary full-screen loading.

### Edge Cases

- A customer has multiple hatcheries but no active flock in one hatchery.
- Two customers or hatcheries reuse the same house, setter, hatcher, trolley, or tray labels.
- A selected flock has audits in more than one hatchery.
- A capture is current by date but an older capture exists later in query order on the same date.
- The device clock or saved timestamp is invalid or in the future.
- A panel row has an aggregate but missing or inconsistent raw inputs after partial sync.
- A metric has no valid benchmark for the selected breed, age, hatchery, or effective date.
- A historical comparison has only one valid point or incompatible scopes.
- An action references a locally deleted or remotely tombstoned source row or photo.
- The device is offline while actions, evidence, or dashboard calculations are updated.
- A dashboard subsection fails while other subsections load successfully.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The operational dashboard MUST support Customer, Hatchery, and Flock cascade scope, with role-appropriate restrictions.
- **FR-002**: Detailed station comparison and corrective triage MUST NOT pool rows across customers or hatcheries.
- **FR-003**: Multi-customer portfolio mode MUST be visually distinct and MUST summarize by customer/hatchery rather than merge same-named operational scopes.
- **FR-004**: Dashboard filters and persisted user choices MUST preserve the existing independent per-sector BMK-age selection and chart/table behavior.
- **FR-005**: Every dashboard section MUST expose its latest contributing observation time, sample/row count, completion or missing-data state, and synchronization freshness when applicable.
- **FR-006**: Environmental status MUST use the latest recording timestamp and MUST distinguish current, aging, stale, invalid-time, and missing data.
- **FR-007**: Stale or invalid-time environmental observations MUST NOT be presented as active current alerts.
- **FR-008**: Each analytical metric MUST declare one aggregation policy from ratio of sums, sample-weighted mean, equal-group mean, sum, or latest valid observation.
- **FR-009**: All-age overall calculations MUST retain equal-age weighting and disclose that policy with contributing age counts.
- **FR-010**: Raw observations and counts MUST be the authoritative inputs for calculated dashboard summaries; cached summaries MUST be produced through one canonical derivation path and checked for drift.
- **FR-011**: Invalid, incomplete, inconsistent, or unsupported calculations MUST carry visible quality flags and MUST NOT silently become zero or in-target values.
- **FR-012**: The dashboard MUST provide a cross-station attention summary ranked by severity, benchmark gap, recency, persistence, and data confidence.
- **FR-013**: Related findings MUST be consolidatable without hiding their individual source metrics and scopes.
- **FR-014**: Every finding MUST support navigation to its exact available source audit, station, panel row, metric, and evidence.
- **FR-015**: Authorized users MUST be able to create, assign, update, resolve, and reopen action items with due dates, notes, timestamps, and optional resolution evidence.
- **FR-016**: Action items and their evidence links MUST work offline and synchronize with existing dependency-safe conflict and deletion behavior.
- **FR-017**: The dashboard MUST identify newly emerged, persistent, improving, worsening, and resolved metric conditions using comparable visits only.
- **FR-018**: Latest-versus-previous analysis MUST disclose both values, the signed delta, comparison date, and scope compatibility.
- **FR-019**: The system MUST expose a normalized analytical representation containing source scope, metric identity, value, unit, numerator, denominator, sample count, observation time, benchmark context, aggregation policy, and quality flags while preserving existing station records as the source of truth.
- **FR-020**: Benchmark selection MUST support global defaults and hatchery-specific overrides with source and effective-time context; environmental targets MUST use the same governed target source rather than independent hidden defaults.
- **FR-021**: Dashboard loading MUST reuse already-fetched panel rows for age and scope derivations and MUST batch related environmental reads where possible.
- **FR-022**: Independent subsection failures MUST be visible and recoverable without discarding successfully loaded sections.
- **FR-023**: Desktop layouts MUST use available width for comparison content while retaining existing phone-safe reflow.
- **FR-024**: All new and existing static dashboard/action text MUST support professional English and poultry-domain Arabic localization with automatic RTL.
- **FR-025**: Dashboard controls, status changes, charts, and action workflows MUST expose meaningful accessibility labels, states, focus order, and non-color status cues.
- **FR-026**: Existing photo recovery, post-sync refresh, sibling-valid hierarchy controls, and migration-safe offline behavior MUST remain intact.

### Key Entities

- **Dashboard Scope**: The selected customer, hatchery, optional flock, role restrictions, and portfolio-versus-operational mode.
- **Metric Observation**: A normalized analytical representation of one derived or directly observed metric with source identity, scope, time, value, sample basis, benchmark, calculation policy, and quality flags.
- **Data Quality Assessment**: Freshness, completeness, consistency, synchronization, and calculation-confidence signals for a section or observation.
- **Consolidated Finding**: A prioritized interpretation that groups related metric conditions while retaining traceability to every source observation.
- **Action Item**: An owned follow-up attached to a finding or source with status, priority, due date, notes, recurrence, and resolution evidence.
- **Benchmark Target**: A governed metric target with scope, source, validity period, and optional hatchery override.
- **Historical Comparison**: A compatible latest/previous observation pair with delta and persistence classification.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In tests with duplicate house and machine labels across two hatcheries, 100% of operational comparisons and alerts use only the selected hatchery's data.
- **SC-002**: Users can identify the selected scope, newest contributing data, completion coverage, sync state, and whether data is stale within 10 seconds of opening the dashboard.
- **SC-003**: No stale environmental capture is counted as a current critical/watch alert, including multiple captures recorded on the same date.
- **SC-004**: Every displayed aggregate in the dashboard test catalog reports a calculation policy and contributing count, and canonical recalculation detects all intentionally introduced raw/aggregate mismatches.
- **SC-005**: Users can open a prioritized issue and reach its available source audit or evidence in no more than two interactions.
- **SC-006**: An action can be created offline, assigned, synchronized to a second device, and resolved with evidence without losing history.
- **SC-007**: Latest-versus-previous classification is correct for new, persistent, improving, worsening, and resolved fixture scenarios, with missing values never interpreted as zero.
- **SC-008**: Representative dashboard refresh performs no repeated per-age database query after the source panel rows have been loaded and performs no per-capture environmental-reading query loop.
- **SC-009**: Phone and desktop dashboard tests complete without overflow; desktop comparison content uses at least 70% of the available content width when data is present.
- **SC-010**: Dashboard localization checks report no untranslated static English strings in Arabic mode, and keyboard/semantics tests cover every interactive dashboard and action control.

## Assumptions

- The current Flutter code and `docs/LIVING_SPEC.md` remain the implementation source of truth; stale living-spec claims will be corrected as part of this feature.
- Existing station panel tables remain authoritative for field entry and offline sync; the normalized analytical representation is additive.
- Equal weighting across BMK ages is an approved product rule and will not be replaced with sample weighting.
- Customer-role users remain restricted to their assigned customer; auditor/admin users may access portfolio mode.
- Freshness thresholds may vary by metric/place and use conservative poultry-domain defaults where no configured operational standard exists, with the source exposed to users.
- Existing Supabase tables and sync orchestration will be extended migration-safely for new synchronized entities.
- Existing user-entered customer, hatchery, flock, machine, house, and evidence values are never translated.
