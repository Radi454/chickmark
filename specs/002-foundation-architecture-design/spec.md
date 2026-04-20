# Feature Specification: Phase 1 — Foundation, Architecture & Design System

**Feature Branch**: `002-foundation-architecture-design`
**Created**: 2026-04-18
**Status**: Draft

## Overview

HatchAudit (brand: ChickMark) is a Flutter mobile app for poultry hatchery auditors.
Phase 1 establishes the complete app foundation — navigation shell, SQLite database
schema, design system, authentication flow, and core project architecture — before any
audit feature is built. No audit data-entry screens are in scope for this phase.

---

## User Scenarios & Testing

### User Story 1 — Auditor logs in for the first time (Priority: P1)

A field auditor opens HatchAudit on an iOS device, sees the ChickMark branded login
screen, enters their approved credentials, and lands on the Home tab of the app shell.
On subsequent opens, they can log in offline using their cached token without an internet
connection.

**Why this priority**: Everything in the app is gated behind authentication. No other
story is reachable until this works.

**Independent Test**: Launch the app, log in with valid credentials, verify the bottom
navigation shell appears with all 6 tabs visible.

**Acceptance Scenarios**:

1. **Given** the app is freshly installed and has network, **When** an approved user
   enters correct email + password and taps Sign In, **Then** credentials are cached
   locally and the Home screen is shown with the 6-tab bottom nav bar.
2. **Given** the user has previously logged in successfully, **When** they open the app
   with no network, **Then** they can log in with cached credentials and reach the Home
   screen within 30 days of the original login.
3. **Given** a user submits a registration form, **When** Admin has not yet approved the
   account, **Then** the Pending Approval screen is shown with an hourglass and a "Back
   to Login" option.
4. **Given** a user's cached token is older than 30 days, **When** they attempt to log
   in offline, **Then** they are informed that internet access is required to
   re-authenticate.
5. **Given** a user enters a password fewer than 8 characters or without a number,
   **When** they tap Create Account, **Then** an inline validation error prevents
   submission.

---

### User Story 2 — Auditor navigates the app shell (Priority: P2)

After logging in, any role can tap the 6 bottom navigation tabs and land on the correct
placeholder screen for each section.

**Why this priority**: The navigation shell is the container for every feature in the
app. It must exist before any tab content is built.

**Independent Test**: Log in, tap each of the 6 tabs in sequence, confirm each reaches
its named screen and the active tab turns #F65C00.

**Acceptance Scenarios**:

1. **Given** the user is on the Home tab, **When** they tap any other tab, **Then** the
   correct screen loads and the tapped tab icon/label turns orange (#F65C00).
2. **Given** an Auditor role is logged in, **When** they navigate to all 6 tabs, **Then**
   no tab is hidden or disabled — all 6 are accessible.
3. **Given** a Customer role is logged in, **When** they navigate the app, **Then** they
   only see data belonging to their own account (enforced at data layer; navigation tabs
   remain visible).

---

### User Story 3 — Auditor views the design system in action (Priority: P3)

All screens rendered in Phase 1 (login, register, pending approval, Home placeholder,
and all other tab placeholders) use the ChickMark design system tokens: orange gradient
headers, correct card radii, background colour, and typography.

**Why this priority**: Visual consistency must be established now so all subsequent
features inherit it automatically via shared theme tokens.

**Independent Test**: Open each Phase 1 screen and compare against the design spec;
verify colours, radii, shadows, and font match without per-screen overrides.

**Acceptance Scenarios**:

1. **Given** any screen with a header, **When** rendered, **Then** the header shows a
   left-to-right gradient from #F65C00 to #ff8c42.
2. **Given** any card widget, **When** rendered, **Then** it has a 14px border radius,
   white background, and a shadow of `0 1px 4px rgba(0,0,0,0.06)`.
3. **Given** any primary action button, **When** rendered, **Then** it has a 12px border
   radius and uses #F65C00 as its fill colour.
4. **Given** the app background, **When** any content screen is shown, **Then** the
   scaffold background is #f0f2f5.

---

### Edge Cases

- What happens when the device has no camera or Bluetooth radio? → Both OCR and BLE
  integrations MUST be absent/disabled gracefully; no crashes, no mandatory permissions
  dialogs on first launch.
- What happens if Supabase is unreachable during login? → If a valid cached token exists,
  offline login proceeds. If no cached token exists, the user sees a connectivity error
  and cannot proceed.
- What happens if email verification has not been completed? → The user is redirected to
  a verification-pending message and cannot access the app shell.

---

## Requirements

### Functional Requirements

**Design System & Theme**

- **FR-001**: The app MUST define a central `AppTheme` class in `lib/core/theme/` that
  exposes all colour constants, text styles, card decoration, and button styles used
  across the app.
- **FR-002**: Primary brand colour MUST be `#F65C00`. Background MUST be `#f0f2f5`.
  Card background MUST be white (`#ffffff`). These MUST be defined as named constants,
  never hardcoded at call sites.
- **FR-003**: Card widgets MUST use 14px border radius and a box shadow of
  `0 1px 4px rgba(0,0,0,0.06)`.
- **FR-004**: Primary action buttons MUST use 12px border radius and `#F65C00` fill.
- **FR-005**: Page headers MUST render a gradient from `#F65C00` to `#ff8c42`.
- **FR-006**: The ChickMark logo widget MUST be implemented as a reusable Flutter widget
  rendering the line-art chick-on-egg SVG in `#F65C00`; the wordmark "CHICKMARK" in
  Georgia serif bold in `#F65C00`; and the tagline "HATCHERY AUDIT" in small-caps grey.
- **FR-007**: Every screen that displays temperature values MUST include a `[°C / °F]`
  toggle button in the top-right area. Default unit is °F. All temperatures MUST be
  stored in °F in the database; conversion to °C MUST happen only at display time.
- **FR-008**: Status badges MUST be implemented as a reusable widget with two variants:
  completed (green: `#e8f5e9` bg / `#388e3c` text) and active (amber: `#fff8e1` bg /
  `#f57c00` text).
- **FR-009**: Audit card age badges MUST use an orange pill style (`#FFF0E8` bg /
  `#F65C00` text).

**Navigation Shell**

- **FR-010**: The app shell MUST render a `BottomNavigationBar` with exactly 6 tabs in
  this order: Home, Dashboard, Customers, Audits, BMK, Settings.
- **FR-011**: Active tab colour MUST be `#F65C00`; inactive tab colour MUST be grey.
- **FR-012**: Each tab MUST navigate to its named screen. Phase 1 screens may be
  placeholder scaffolds; they MUST not crash.

**Authentication**

- **FR-013**: The Login screen MUST display the ChickMark logo, wordmark, and tagline
  prominently at the top, followed by email field, password field, a right-aligned
  "Forgot password" link, a [Sign In] primary button, a "don't have an account?" divider,
  a [Create Account] outline button, and an info banner stating "Offline mode available
  after first login".
- **FR-014**: The Register screen MUST display a small logo, full name field, email
  field, password field with a live 3-level strength indicator (Weak / Medium / Strong
  coloured bars), confirm password field, an info banner about admin approval, a
  [Create Account] primary button, and a ghost "Back to Login" button.
- **FR-015**: The Pending Approval screen MUST display the logo, a card with a hourglass
  icon + "Awaiting Approval" heading + description, a Forgot Password section (email
  field + Send Reset Link button + success state), and a ghost "Back to Login" button.
- **FR-016**: Supabase MUST handle authentication (sign-up, sign-in, password reset,
  email verification).
- **FR-017**: On first successful login, credentials (access token, expiry, user record)
  MUST be cached in SQLite so subsequent launches can authenticate offline.
- **FR-018**: Cached tokens MUST expire 30 days from issuance. Expired tokens require
  internet access to re-authenticate.
- **FR-019**: Password validation MUST enforce a minimum of 8 characters including at
  least 1 number, evaluated client-side before submission.
- **FR-020**: Email verification MUST be required before a user can access the app shell.
- **FR-021**: Role assignment (Admin / Auditor / Customer) is performed by Admin only;
  users MUST NOT be able to select their own role during registration.
- **FR-022**: Admin must explicitly approve each registration before the account becomes
  active; a pending user sees only the Pending Approval screen.
- **FR-023**: Customer accounts MUST be created by Admin only; the self-registration flow
  is limited to the Auditor role.

**Database Schema**

- **FR-024**: The SQLite database MUST be initialised via a `DatabaseHelper` class in
  `lib/data/database/` with versioned migration support.
- **FR-025**: The following tables MUST be created on first launch:
  `users`, `customers`, `flocks`, `audits`, `bmk_breeds`, `bmk_egg_breakout`,
  `troubleshooting`, `photos`.
- **FR-026**: The `audits` table MUST be a single denormalized table containing all
  audit-type-specific columns as defined in the database schema section below. Nullable
  columns for irrelevant audit types are acceptable.
- **FR-027**: The `flocks` table MUST NOT store `current_age_weeks` as a persisted
  column; flock age MUST always be computed at runtime from `entry_date`.
- **FR-028**: `bmk_breeds` and `bmk_egg_breakout` tables MUST be seeded with read-only
  reference data on first launch and MUST NOT be editable by any user.
- **FR-029**: Photos MUST be stored as local file path strings in the `photos` table;
  binary image data MUST NOT be embedded in the database.

**Architecture & Project Structure**

- **FR-030**: The project MUST follow the folder structure defined in the Tech Stack
  section (`lib/core/`, `lib/data/`, `lib/features/`, `lib/providers/`, `lib/widgets/`,
  `lib/services/`).
- **FR-031**: State management MUST use the Provider package. No alternative state
  management libraries may be introduced.
- **FR-032**: Supabase sync MUST operate as a background, fire-and-forget operation.
  Any Supabase error MUST be caught and logged silently; it MUST NOT surface a blocking
  dialog or prevent any user action.
- **FR-033**: Govee BLE integration MUST be implemented with graceful degradation: if
  Bluetooth is unavailable the feature is hidden or shown as disabled; the app MUST NOT
  crash.
- **FR-034**: Apple Vision OCR integration MUST be implemented with graceful degradation:
  if the camera is unavailable the feature is disabled cleanly; the app MUST NOT crash.
- **FR-035**: `flutter analyze` MUST pass with zero errors before the phase is considered
  complete.
- **FR-036**: All calculation utility functions (CV%, uniformity, Pasgar score,
  hatchability, HOF, BMK age, flock age) MUST have unit tests covering the primary
  formula and at least one boundary/edge-case input.

### Key Entities

- **User**: App account with role (Admin / Auditor / Customer) and approval status.
- **Customer**: Hatchery company managed by Admin; Auditors conduct audits on their behalf.
- **Flock**: A breeder flock belonging to a Customer, identified by breed and entry date;
  age is always derived, never stored.
- **Audit**: A single data-collection session keyed by Customer + Flock + Date + Audit
  Type + Setter/Hatcher ID. Stored in one denormalized table.
- **BmkBreed**: Read-only breed benchmark reference row (age-based, per breed).
- **BmkEggBreakout**: Read-only egg breakout benchmark reference row (age-based,
  all breeds).
- **Troubleshooting**: Read-only lookup table mapping egg breakout / Pasgar parameters
  to hatchery and farm/flock causes.
- **Photo**: Local file path record linked to a specific audit row and field key.

---

## Database Schema

### TABLE: users
| Column | Type | Notes |
|--------|------|-------|
| id | TEXT (UUID) | Primary key |
| full_name | TEXT | Required |
| email | TEXT | Unique, required |
| role | TEXT | admin / auditor / customer |
| status | TEXT | pending / approved / suspended |
| customer_id | TEXT | Nullable FK → customers (customer role only) |
| created_at | TEXT (ISO8601) | |
| last_login_at | TEXT (ISO8601) | Nullable |

### TABLE: customers
| Column | Type | Notes |
|--------|------|-------|
| id | TEXT (UUID) | Primary key |
| name | TEXT | Required |
| location | TEXT | Nullable |
| phone | TEXT | Nullable |
| email | TEXT | Nullable |
| created_at | TEXT (ISO8601) | |
| created_by | TEXT | FK → users |

### TABLE: flocks
| Column | Type | Notes |
|--------|------|-------|
| id | TEXT (UUID) | Primary key |
| customer_id | TEXT | FK → customers |
| flock_id | TEXT | Human-readable identifier |
| breed | TEXT | Ross308 / Arbo / Avian / Cobb500 / Hubbard / IR |
| entry_date | TEXT (ISO8601 date) | Used to compute age at runtime |
| created_at | TEXT (ISO8601) | |

### TABLE: audits (single denormalized table)

**Common columns**

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT (UUID) | Primary key |
| audit_type | TEXT | chick_quality / hatch_analysis / setter_optimizing / hatcher_optimizing / egg_storage |
| customer_id | TEXT | FK → customers |
| flock_id | TEXT | Nullable FK → flocks |
| setter_id | TEXT | Nullable |
| hatcher_id | TEXT | Nullable |
| date | TEXT (ISO8601 date) | |
| status | TEXT | active / completed |
| created_by | TEXT | FK → users |
| created_at | TEXT (ISO8601) | |
| updated_at | TEXT (ISO8601) | |
| notes | TEXT | Nullable |

**Chick Quality — CHA Environmental**

| Column | Type |
|--------|------|
| cha_govee_connected | INTEGER (boolean) |
| cha_co2 | REAL |
| cha_co2_photo | TEXT |
| cha_pm10 | REAL |
| cha_pm10_photo | TEXT |
| cha_pm25 | REAL |
| cha_pm25_photo | TEXT |
| cha_air_velocity_spot1 | REAL |
| cha_air_velocity_spot1_photo | TEXT |
| cha_air_velocity_spot2 | REAL |
| cha_air_velocity_spot2_photo | TEXT |
| cha_air_velocity_spot3 | REAL |
| cha_air_velocity_spot3_photo | TEXT |
| cha_air_inlet | REAL |
| cha_air_inlet_photo | TEXT |
| cha_air_outlet | REAL |
| cha_air_outlet_photo | TEXT |
| cha_noise_level | REAL |
| cha_noise_level_photo | TEXT |

**Chick Quality — Pasgar**

| Column | Type | Notes |
|--------|------|-------|
| pasgar_sample_size | INTEGER | Default 40 |
| pasgar_reflexes | INTEGER | |
| pasgar_reflexes_photo | TEXT | |
| pasgar_beak | INTEGER | |
| pasgar_beak_photo | TEXT | |
| pasgar_navel | INTEGER | |
| pasgar_navel_photo | TEXT | |
| pasgar_belly | INTEGER | |
| pasgar_belly_photo | TEXT | |
| pasgar_leg | INTEGER | |
| pasgar_leg_photo | TEXT | |
| pasgar_feather_dev | INTEGER | |
| pasgar_feather_dev_photo | TEXT | |
| pasgar_final_score | REAL | Computed, stored |

**Chick Quality — Weights**

| Column | Type | Notes |
|--------|------|-------|
| chick_storage_days | INTEGER | Default 0 |
| chick_sample_size | INTEGER | Default 100 |
| chick_weights | TEXT | JSON array (max 100 values) |
| chick_avg_weight | REAL | Computed, stored |
| chick_uniformity_pct | REAL | Computed, stored |
| chick_cv_pct | REAL | Computed, stored |
| chick_bmk_age | INTEGER | Computed = flock_age − 21 − storage_days |
| chick_bmk_weight | REAL | From bmk_breeds by bmk_age |

**Chick Quality — YFBM**

| Column | Type | Notes |
|--------|------|-------|
| yfbm_photo | TEXT | |
| yfbm_entries | TEXT | JSON array of {chick_weight, yolk_weight} |
| yfbm_avg_pct | REAL | Computed, stored |
| yfbm_cv_pct | REAL | Computed, stored |

**Chick Quality — CVT**

| Column | Type | Notes |
|--------|------|-------|
| cvt_sample_size | INTEGER | |
| cvt_top_basket | TEXT | |
| cvt_top_temp | REAL | Stored in °F |
| cvt_top_photo | TEXT | |
| cvt_middle_basket | TEXT | |
| cvt_middle_temp | REAL | Stored in °F |
| cvt_middle_photo | TEXT | |
| cvt_bottom_basket | TEXT | |
| cvt_bottom_temp | REAL | Stored in °F |
| cvt_bottom_photo | TEXT | |
| cvt_avg | REAL | Computed, stored in °F |
| cvt_cv_pct | REAL | Computed, stored |

**Hatch Analysis — Sector 1: Hatch Results**

| Column | Type | Notes |
|--------|------|-------|
| ha_storage_days | INTEGER | Default 0 |
| ha_total_eggs_set | INTEGER | |
| ha_hatched | INTEGER | |
| ha_culled | INTEGER | |
| ha_dead | INTEGER | |
| ha_hatchability | REAL | Computed = hatched / total_set × 100 |
| ha_fertility | REAL | Computed = avg fertility across trays |
| ha_hof | REAL | Computed = hatchability / fertility × 100 |
| ha_trays | TEXT | JSON array: {tray_id, position, tray_size, infertile_count, fertility_pct} |
| ha_bmk_age | INTEGER | Computed = flock_age − 21 − storage_days |

**Hatch Analysis — Sector 2: Egg Breakout**

| Column | Type | Notes |
|--------|------|-------|
| eb_tray_size | INTEGER | Default 150 |
| eb_breakout_type | TEXT | fresh / candled / residue |
| eb_breakout_age_days | INTEGER | Auto: fresh=1, candled=10, residue=21; editable |
| eb_storage_days | INTEGER | Default 0 |
| eb_trays | TEXT | JSON array: {tray_id, position, parameter counts} |
| eb_bmk_age | INTEGER | Computed = flock_age − breakout_age − storage_days |

**Setter Optimizing**

| Column | Type | Notes |
|--------|------|-------|
| so_breed | TEXT | |
| so_setter_id | TEXT | |
| so_incubation_age | INTEGER | 1–18 days |
| so_govee_connected | INTEGER | Boolean |
| so_govee_temp | REAL | Stored in °F |
| so_govee_humidity | REAL | |
| so_co2 | REAL | |
| so_co2_photo | TEXT | |
| so_est_readings | TEXT | JSON 3×3: door/middle/back × top/middle/bottom, °F |
| so_est_photos | TEXT | JSON 3×3 |
| so_est_avg | REAL | Computed, stored in °F |
| so_est_cv | REAL | Computed, stored |

**Hatcher Optimizing**

| Column | Type | Notes |
|--------|------|-------|
| ho_breed | TEXT | |
| ho_hatcher_id | TEXT | |
| ho_incubation_age | INTEGER | 18–21 days |
| ho_govee_connected | INTEGER | Boolean |
| ho_govee_temp | REAL | Stored in °F |
| ho_govee_humidity | REAL | |
| ho_co2 | REAL | |
| ho_co2_photo | TEXT | |
| ho_cvt_readings | TEXT | JSON 3×3: door/middle/back × top/middle/bottom, °F |
| ho_cvt_photos | TEXT | JSON 3×3 |
| ho_cvt_avg | REAL | Computed, stored in °F |
| ho_cvt_cv | REAL | Computed, stored |
| ho_chick_panting | INTEGER | Boolean |
| ho_chick_panting_photo | TEXT | |

**Egg Storage**

| Column | Type | Notes |
|--------|------|-------|
| es_govee_connected | INTEGER | Boolean |
| es_govee_temp | REAL | Stored in °F |
| es_govee_humidity | REAL | |
| es_co2 | REAL | |
| es_co2_photo | TEXT | |
| es_shell_temp | REAL | Stored in °C (shell temp standard is °C) |
| es_shell_temp_photo | TEXT | |
| es_turning_times | INTEGER | 0–5 |
| es_uv_trays | TEXT | JSON array: {total_eggs, affected_count, photo} |
| es_egg_storage_days | INTEGER | Default 0 |
| es_egg_sample_size | INTEGER | Default 100 |
| es_egg_weights | TEXT | JSON array (max 100 values) |
| es_egg_avg_weight | REAL | Computed, stored |
| es_egg_uniformity_pct | REAL | Computed, stored |
| es_egg_cv_pct | REAL | Computed, stored |
| es_egg_bmk_age | INTEGER | Computed = flock_age − 21 − storage_days |
| es_egg_bmk_weight | REAL | From bmk_breeds by bmk_age |

### TABLE: bmk_breeds (read-only seed data)
| Column | Type |
|--------|------|
| breed | TEXT |
| age_weeks | INTEGER |
| hatchability_pct | REAL |
| fertility_pct | REAL |
| hof_pct | REAL |
| production_pct | REAL |
| egg_weight_g | REAL |
| chick_weight_g | REAL |

### TABLE: bmk_egg_breakout (read-only seed data)
| Column | Type |
|--------|------|
| age_weeks | INTEGER |
| infertile | REAL |
| early_dead_24h | REAL |
| early_dead_48h | REAL |
| blood_ring | REAL |
| early_dead | REAL |
| mid_black_eye | REAL |
| feathers | REAL |
| turned | REAL |
| internal_pip | REAL |
| late_dead | REAL |
| external_pip | REAL |
| exposed_brain | REAL |
| crossed_beak | REAL |
| contaminated | REAL |
| cracked | REAL |

### TABLE: troubleshooting
| Column | Type | Notes |
|--------|------|-------|
| id | TEXT (UUID) | Primary key |
| category | TEXT | egg_breakout / pasgar |
| parameter | TEXT | |
| hatchery_causes | TEXT | JSON array of cause strings |
| farm_flock_causes | TEXT | JSON array of cause strings |

### TABLE: photos
| Column | Type | Notes |
|--------|------|-------|
| id | TEXT (UUID) | Primary key |
| audit_id | TEXT | FK → audits |
| field_key | TEXT | Column name this photo belongs to |
| file_path | TEXT | Absolute local file path |
| synced | INTEGER | Boolean, default 0 |
| created_at | TEXT (ISO8601) | |

---

## Tech Stack & Architecture

**Framework**: Flutter (iOS primary; Android/Web/macOS planned)
**State management**: Provider (`lib/providers/`)
**Local database**: SQLite via `sqflite`
**Cloud sync**: Supabase (background only, never blocks UI)
**OCR**: Apple Vision — graceful degradation required
**BLE**: Govee sensors — graceful degradation required

### Folder Structure

```
lib/
  main.dart
  app.dart
  core/
    constants/       # AppColors, AppSizes, AppStrings
    theme/           # AppTheme, TextStyles, Decorations
    utils/           # TempConverter, CalculationUtils, DateUtils
  data/
    database/        # DatabaseHelper (sqflite migrations)
    models/          # Dart model classes
    repositories/    # Data access layer (SQLite reads/writes)
  features/
    auth/            # login, register, pending_approval screens + logic
    home/            # Home tab scaffold
    dashboard/       # Dashboard tab scaffold
    customers/       # Customers tab scaffold
    audits/          # Audits tab scaffold
    bmk/             # BMK tab scaffold
    settings/        # Settings tab scaffold
  providers/         # ChangeNotifier providers
  widgets/           # Shared UI components (ChickMarkLogo, StatusBadge, TempToggle, etc.)
  services/
    supabase/        # Auth + background sync (graceful degradation)
    govee/           # BLE sensor service (graceful degradation)
    ocr/             # Apple Vision OCR service (graceful degradation)
```

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: An approved user can complete the full login flow (app open → authenticated →
  Home screen) in under 10 seconds on an iPhone with network access.
- **SC-002**: An approved user can log in offline (no network) within 30 days of their
  last successful online login, reaching the Home screen without any error dialogs.
- **SC-003**: The bottom navigation shell renders all 6 tabs and allows switching between
  them with zero crashes on iOS Simulator.
- **SC-004**: `flutter analyze` reports zero errors after Phase 1 implementation.
- **SC-005**: All calculation utility unit tests pass (`flutter test`) — covering CV%,
  uniformity, Pasgar score, hatchability, HOF, BMK age, and flock age computations.
- **SC-006**: The app launches successfully with no network connection and no Supabase
  credentials configured; Govee BLE and Apple Vision features are absent/disabled but
  do not produce crashes or unhandled exceptions.
- **SC-007**: The SQLite database is created with all 8 required tables on first launch;
  schema can be inspected and confirmed correct.
- **SC-008**: No hardcoded customer names, flock identifiers, passwords, or API keys
  appear anywhere in committed source code (verified by code review / `grep`).

---

## Assumptions

- The Supabase project (URL + anon key) will be provided as environment variables or a
  local config file excluded from version control; no credentials are hardcoded.
- BMK seed data values (breed benchmarks and egg breakout benchmarks) will be provided
  separately before the database seeding task is implemented; placeholder rows are
  acceptable for Phase 1.
- Troubleshooting content (hatchery causes, farm/flock causes per parameter) will be
  provided as a data file before that table is seeded; placeholder rows are acceptable.
- The ChickMark logo will be delivered as an SVG asset; if unavailable, the widget
  renders a styled text fallback during Phase 1.
- Shell temp (egg storage) is stored in °C because the industry optimum range (19–21°C)
  is defined in Celsius; all other temperatures are stored in °F.
- Phase 1 does not implement any audit data-entry screens — tab content screens are
  scaffolds (empty or placeholder). Full audit screens are Phase 2+.
- iOS Simulator is the minimum accepted test target for manual UI validation; physical
  device testing is preferred but not required for this phase.
- The Admin approval workflow (approving pending users) is out of scope for Phase 1;
  a seed admin account will be used for testing purposes.
