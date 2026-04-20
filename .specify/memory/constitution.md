<!--
SYNC IMPACT REPORT
==================
Version change: 2.0.0 → 2.1.0
Bump rationale: MINOR — new principles added (Auth & Roles, Calculations & Thresholds,
  Troubleshooting Rules); material expansions to Navigation (corrected audit type count
  from 7 to 5; clarified Egg Breakout as sector inside Hatch Analysis), Design System
  (temperature toggle, green tab, card/button radii, background color, header gradient),
  and Database Design (Setter/Hatcher Optimizing composite key clarified).
Modified principles:
  - VI. Navigation and Screen Structure → corrected audit type count (7 → 5), clarified
    Egg Breakout sector placement
  - V. Database Design Rules → added Setter/Hatcher Optimizing key rule (no flock)
  - X. Design System → expanded with temp toggle, green tab, card/button radius,
    background color, header gradient, font spec
Added sections:
  - XI. Authentication and Authorization Rules
  - XII. Calculations, Thresholds, and Alerts
  - XIII. Troubleshooting Rules
Removed sections: none
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ (Constitution Check section covers updated principles)
  - .specify/templates/spec-template.md ✅ (no structural changes required)
  - .specify/templates/tasks-template.md ✅ (no structural changes required)
Follow-up TODOs: none — all fields resolved.
-->

# HatchAudit Constitution

**App Name**: HatchAudit | **Brand**: ChickMark
**Platform**: Flutter — iOS (primary), Android / Web / macOS (planned)
**Purpose**: Digitize audit workflows for poultry hatchery auditors.

## Core Principles

### I. Offline-First, SQLite as Source of Truth

The app MUST be fully functional without any network connection. Local SQLite storage
(via `sqflite`) is the authoritative data store. All reads and writes MUST go to
SQLite first. Supabase cloud sync is a background, best-effort operation and MUST
NOT block, delay, or crash any user-facing workflow. If sync fails for any reason,
the app MUST continue operating normally.

**Rationale**: Hatchery auditors work in facilities with unreliable or absent
connectivity. Any dependency on network availability for core audit functionality
is unacceptable and will result in data loss or workflow interruption.

### II. Audit Data Integrity

All audit data MUST be persisted atomically — partial writes MUST NOT produce
inconsistent rows. Each audit row is identified by the composite key:
`Customer + Flock + Date + Audit Type + Setter ID + Hatcher ID`. Records are
editable after initial save; edits MUST update the existing row in-place (no
new revision entries). Flock age MUST always be auto-calculated from flock data
and MUST NOT be manually entered by users.

**Rationale**: Field auditors frequently correct data immediately after entry.
Treating records as immutable would produce duplicate or orphaned rows and
undermine the value of the audit history.

### III. Test-First for Calculation Logic

All calculation utilities (e.g., Hatchability %, HOF %, Pasgar Score, CV%,
flock age derivation, BMK Age) MUST have unit tests written before implementation.
Test coverage MUST include the primary formula, boundary inputs (zero, null), and
known-good reference values. UI screens do not require widget tests unless explicitly
requested in a feature specification.

**Rationale**: Hatchery calculations carry direct business impact. An incorrect
Hatchability or HOF value can affect breeding decisions. Bugs in calculations must
be caught mechanically, not discovered in the field.

### IV. Simplicity Over Abstraction

The codebase MUST prefer flat, readable Dart over deep inheritance hierarchies or
speculative abstractions. Provider-based state management (`lib/providers/`) is the
approved pattern. Alternative state management libraries MUST NOT be introduced
without an explicit constitution amendment. Helpers and utilities MUST NOT be
created for one-time operations.

**Rationale**: A small team (or solo developer) requires code that can be understood
and modified quickly. Premature abstraction creates maintenance debt without
corresponding benefit.

### V. Database Design Rules

The audit data MUST be stored in a single denormalized `audits` table. The composite
key `(customer, flock, date, audit_type, setter_id, hatcher_id)` uniquely identifies
each row for Egg Storage, Chick Quality, and Hatch Analysis audits. For Setter
Optimizing and Hatcher Optimizing, the composite key is
`(customer, machine_id, date)` — no flock field applies. The same customer + flock +
date with a different setter or hatcher ID constitutes a separate row — this is
intentional and MUST NOT be de-duplicated. No ORM or repository pattern layer MUST
be interposed between the provider and `sqflite` unless introduced by constitution
amendment. All computed fields MUST be calculated in-app and stored results saved to
the DB. Photos MUST be stored as local file paths linked to the audit row.

**Rationale**: A single denormalized table eliminates join complexity, simplifies
offline sync, and matches the one-row-per-audit-session mental model auditors use.

### VI. Navigation and Screen Structure

The app MUST use a bottom navigation bar with exactly six tabs in this order:
**Home** (recent audits + New Audit shortcut), **Dashboard**, **Customers**,
**Audits** (full history), **BMK** (benchmarks), **Settings**. The New Audit flow
MUST present exactly **5 audit type** cards:
1. Egg Storage & Handling
2. Chick Quality
3. Hatch Analysis (includes Egg Breakout as an internal sector — NOT a separate type)
4. Setter Optimizing
5. Hatcher Optimizing

Egg Breakout is a sector within Hatch Analysis and MUST NOT appear as a standalone
audit type card. After type selection, the flow continues with Customer + Flock
selection, then data entry with Setter ID / Hatcher ID fields. Deviations from
this navigation structure require an explicit constitution amendment.

**Rationale**: Auditors follow a practiced workflow. Structural consistency reduces
training time and prevents navigation errors during fast-paced field audits.

### VII. Dashboard and Reporting Rules

The Dashboard MUST implement a cascade filter in this order:
`Customer → Flock → Age → Setter/Hatcher ID`. It MUST support two comparison modes
for ALL audit types: (a) same-day comparison between setters/hatchers, and (b)
cumulative results over time. Charts MUST appear only on the Dashboard screen —
audit data-entry screens MUST contain no live KPI displays, charts, or calculated
result panels.

**Rationale**: Mixing data entry with live analytics creates cognitive load and
risks auditors modifying entries to chase displayed numbers rather than recording
accurate observations.

### VIII. Benchmark Data Rules

The BMK screen MUST present two read-only sections. Section 1 (Breed Benchmarks)
covers 6 breeds (Ross 308, Arbo, Avian, Cobb 500, Hubbard, IR) filtered by breed
selector + age dropdown, displaying one row with columns: Hatchability%, Fertility%,
HOF%, Production%, Egg Weight (g), Chick Weight (g). Section 2 (Egg Breakout
Benchmarks) is age-based only (same values across all breeds), filtered by age
dropdown. BMK Age MUST be calculated as: `Flock Age − 21 days − Storage Days`.
Benchmark data MUST be read-only and MUST NOT be editable by any user role.

**Rationale**: Benchmark values are industry-standard reference data. Allowing
edits would invalidate their value as a comparison baseline.

### IX. Integration Resilience

All optional hardware and cloud integrations MUST degrade gracefully:
- **Apple Vision OCR**: If the camera is unavailable, the feature MUST disable
  cleanly (show a disabled state or skip the option). It MUST NOT crash or throw
  unhandled exceptions.
- **Govee Bluetooth sensors**: If Bluetooth is unavailable or the device does not
  support it, sensor input fields MUST auto-fill via BLE when available, or remain
  manually editable otherwise. The feature MUST NOT crash.
- **Supabase sync**: Network errors, timeouts, or auth failures MUST be caught and
  logged silently. The app MUST NOT display blocking error dialogs or prevent any
  audit workflow due to sync failures.

Any new integration added to the app MUST include a graceful-degradation path before
it is considered production-ready.

**Rationale**: The app targets field environments where hardware availability varies.
A crash caused by a missing Bluetooth radio or offline Supabase is unacceptable.

### X. Design System

The primary brand color is `#F65C00` (Zoetis orange). The following visual rules MUST
be observed across all screens:

- **Header**: Gradient `#F65C00 → #ff8c42`
- **Background**: `#f0f2f5`
- **Card border-radius**: 14px with subtle shadow
- **Button border-radius**: 12px
- **Font**: SF Pro (iOS system default)
- **Logo**: Line art chick sitting on egg with checkmark inside, rendered in `#F65C00`
- **Temperature toggle**: Every screen that displays temperature values MUST include
  a `[°C / °F]` toggle. Default is °F. All temperatures MUST be stored in °F
  internally and converted on display only — never store °C.
- **Post-save state**: After saving an audit section, the tab/section header MUST
  turn green and enter read-only view. An Edit button MUST be available to unlock
  editing. This pattern MUST be consistent across all audit types.
- **No live KPIs in forms**: Audit data-entry screens MUST contain no live computed
  summary cards, charts, or KPI panels.
- **No hardcoded data**: No hardcoded customer names, flock identifiers, or
  credentials MUST appear anywhere in committed code.

**Rationale**: Consistent visual identity reinforces the ChickMark brand. The
temperature toggle and green tab system are core UX patterns that auditors rely on
to orient themselves during field data entry.

### XI. Authentication and Authorization Rules

The app MUST enforce three user roles:
- **Admin**: Full access — manages users, customers, benchmarks, and all audits.
- **Auditor**: Can create and edit audits; cannot manage users or benchmarks.
- **Customer**: Read-only access to their own audits only; cannot create or edit.

Additional rules:
- All new user registrations MUST be approved by an Admin before access is granted.
- Customer accounts MUST be created by an Admin only (self-registration is not
  available for the Customer role).
- Offline login MUST be supported via cached token after first successful login.
- Cached tokens MUST expire after 30 days.
- Password policy: minimum 8 characters including at least 1 number.
- Email verification MUST be required before any account becomes active.

**Rationale**: Hatchery data is commercially sensitive. Role separation prevents
unauthorized access or accidental modification of audit records and benchmark data.

### XII. Calculations, Thresholds, and Alerts

All calculation formulas are authoritative and MUST be implemented exactly as
specified below. No approximation or rounding MUST be applied before storing results.

**Formulas:**
- `Hatchability (%) = Hatched / Total Set × 100`
- `Fertility (%) = (Tray Size − Infertile) / Tray Size × 100`
- `HOF (%) = Hatchability / Fertility × 100`
- `Pasgar Score = ((Sample Size × 10) − (Reflexes + Beak + Navel + Belly + Leg)) / Sample Size`
- `Chick/Egg Uniformity (%) = percentage of samples within AVG ± 10%`
- `CV% = (Standard Deviation / AVG) × 100`
- `BMK Age = Flock Age − 21 days − Storage Days`

**Thresholds and alert rules (MUST be enforced in-app):**
- Pasgar parameter % > 20% → alert
- Uniformity: < 80% = Poor | 80–85% = Good | > 85% = Excellent
- CV% > 8% → alert (Aviagen standard)
- YFBM %: optimum 8–10%; outside range → alert
- CVT: optimum 103–105°F; outside range → alert
- EST: optimum 100–101°F; outside range → alert
- Shell temp: optimum 19–21°C; > 21°C = bad; < 19°C = better
- Egg breakout vs BMK: > BMK + 3% = High severity | ≤ BMK + 3% = Medium severity
- Culled chicks: ≤ 1% of BMK
- Dead chicks: ≤ 0.2% of BMK

All calculations MUST be instant and responsive — no deferred or lazy computation
on data-entry screens.

**Rationale**: Precise, standardized formulas are essential for auditor trust and
cross-hatchery comparability. Thresholds must be enforced consistently so alerts
are actionable, not noisy.

### XIII. Troubleshooting Rules

The app MUST display a 💡 (lightbulb) icon:
- Next to any egg breakout parameter that exceeds its BMK value.
- Next to any Pasgar parameter whose percentage exceeds 20%.

The 💡 icon MUST appear in BOTH the audit entry screen AND the Dashboard. Tapping
or pressing the 💡 icon MUST open a troubleshooting panel with a toggle:
`[Hatchery Causes] / [Farm/Flock Causes]`. Each panel MUST be organized into
sections: **Management**, **Nutrition**, **Disease**, **Other**.

**Rationale**: Troubleshooting guidance surfaces actionable context exactly where
auditors notice a deviation, reducing the time between observation and corrective
action.

## Quality Standards

All feature branches MUST satisfy the following gates before merge:

- `flutter analyze` MUST pass with zero errors. Warnings require inline justification
  comments (`// ignore: <reason>`).
- All existing unit tests MUST pass (`flutter test`).
- New calculation logic (Hatchability %, HOF %, Pasgar Score, CV%, BMK Age, etc.)
  MUST include at least one unit test covering the primary formula and at least one
  edge-case input.
- No hardcoded credentials, customer data, flock identifiers, or device-specific
  paths MUST appear in committed code.
- All integration features (OCR, BLE, Supabase sync) MUST implement and test their
  graceful-degradation path before being considered complete.
- Photos MUST be linked correctly to their audit row (local file path, not embedded).
- Offline mode MUST be tested on-device or in simulator before each release.

## Development Workflow

1. Features begin as a spec under `specs/###-feature-name/spec.md` using
   `/speckit-specify`.
2. Implementation planning uses `/speckit-plan` before any code is written.
3. Tasks are generated with `/speckit-tasks` and executed with `/speckit-implement`.
4. Each completed feature MUST be committed on its own branch and merged via PR.
5. Database schema changes MUST include a migration path in
   `lib/database/database_helper.dart`. Dropping and recreating tables is only
   acceptable in pre-production development.
6. UI changes MUST be manually tested on at least one physical or simulated iOS
   device (iOS Simulator minimum) before the PR is opened.

## Governance

This constitution supersedes all informal conventions. Amendments require:

1. A proposed change documented in a PR description explaining the motivation and
   the principle(s) affected.
2. A version bump per semantic versioning rules:
   - **MAJOR**: Backward-incompatible governance/principle removals or redefinitions.
   - **MINOR**: New principle or section added, or materially expanded guidance.
   - **PATCH**: Clarifications, wording fixes, non-semantic refinements.
3. Propagation of the change to all affected templates and dependent artifacts,
   documented in a Sync Impact Report (HTML comment at top of this file).

All feature specifications and implementation plans MUST include a "Constitution
Check" section verifying compliance with the principles above. Violations MUST be
explicitly justified in the Complexity Tracking table of the plan.

**Version**: 2.1.0 | **Ratified**: 2026-04-17 | **Last Amended**: 2026-04-18
