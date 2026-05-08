# Living Spec — Current Implemented Behavior

This file documents behavior mapped from the current Flutter codebase. The
current Flutter codebase remains the primary source of truth. If this document
and code conflict, inspect the code and report the mismatch.

This file must be updated after every meaningful code change.

## 1. Last Updated

2026-05-07

Mapped from the current working tree under `lib/`, especially app bootstrap,
navigation, audit screens, providers, models, repositories, services, and the
SQLite database helper. This update intentionally does not use deleted or old
feature specs as source material.

## 2. Navigation

App bootstrap starts in `main.dart`, initializes SQLite before `runApp`, then
starts token migration, notifications, and Supabase initialization in the
background.

The user-facing app name is ChickMark. `MaterialApp.title`, web document
metadata, and PWA manifest metadata use `ChickMark`; the Dart package name and
local database filename remain `hatchaudit` for import and storage
compatibility.

The supported local web development origin is `http://127.0.0.1:57863`. Web
accounts and entered data are scoped to the browser origin, so using this stable
host and port preserves the local IndexedDB-backed database across runs. Local
web previews should be restarted on the same origin with `make restart-web` or
`RESTART=1 make run-web` when current code needs to replace a stale running
server.

`HatchAuditApp` registers these root providers: `AppProvider`, `AuthProvider`,
`CustomersProvider`, `AuditProvider`, `AuditSessionProvider`,
`TemperatureRhProvider`, `GoveeCaptureProvider`, `BmkProvider`,
`SettingsProvider`, and `DashboardProvider`.

Initial route selection is auth-state driven:

- Authenticated users go to `/main`.
- Pending approval users go to `/pending-approval`.
- Loading, error, and unauthenticated users go to `/login`.
- `/register` and `/startup-sync` are also registered routes.

The main shell has seven destinations:

- Home
- Dashboard
- Customers
- Audits
- Govee
- BMK
- Settings

The shell uses a drawer on narrow layouts and a navigation rail at widths of
900px or greater. It lazily builds tabs, keeps a tab history stack for shell
back navigation, and triggers background sync after the first Home build.

The previous floating Measures launcher is no longer shown. Govee recording is
entered from the Govee tab, from a station-level Govee readings button, or from
the scoped floating Govee shortcut on the authenticated main shell. The floating
shortcut opens the same standalone Govee workflow and is hidden on pushed page
routes because it is scoped to `MainShell`, so station editors and detail
screens are not covered.

## 3. Audit Workflow

Only approved admins and auditors can create or edit audits. Customer-role users
are read-only and scoped to their assigned `customerId`.

The current New Audit button on Home opens `AuditContextScreen` without an
`auditType`, which means it starts the visit/session flow:

- Select customer.
- Select hatchery for that customer.
- Select an audit-available flock. Flocks are unavailable when sold or past
  their depletion age.
- Continue to station selection.
- Select one or more stations from the five supported station keys and arrange
  their visit order.
- Start Visit creates an `audit_sessions` row with status `in_progress`.

Supported station keys are:

- `egg`
- `chicks`
- `hatch_analysis_egg_breakouts`
- `setters`
- `hatchers`

`AuditSessionScreen` renders the selected stations in one visit workflow. It
shows a progress indicator, keeps one `AuditProvider` per station, and shows one
station at a time. Moving forward, moving back, switching to an earlier or
completed station, leaving the visit, or saving the final station all go through
a station-exit confirmation path that attempts to save the current station.
When a visit is resumed or a previously saved station is opened inside the
session, the station frame hydrates the station from saved `audits` rows and
station sample rows for that session before rendering so edits resave in place.
Hatch Analysis & Egg Breakouts and Chicks suppress the current-station progress
strip so their own workbench headers are the first station content.

Station save behavior:

- Hatch Analysis & Egg Breakouts saves all samples and marks all tab indices saved.
- Other stations save through `AuditProvider.saveSamplesWithResult(tabIndex: 0)`.
- Saving persists legacy audit rows in `audits`.
- When a visit session id exists, saving also upserts linked rows in
  `station_samples`.
- Completing a station updates `audit_sessions.stationsCompleted`.
- Completing the final selected station updates the session to `completed` and
  returns to the main shell.

The legacy single-station flow still exists in code when `AuditContextScreen` is
constructed with an explicit `auditType`. It collects customer/flock context and,
for Setter or Hatchers, requires the relevant machine id before
opening a single station screen with a fresh `AuditProvider`.

The Audits tab lists recent visit sessions and legacy audit rows. In-progress
sessions resume in `AuditSessionScreen`; completed sessions open a session
detail screen. Legacy audit rows open audit detail/edit flows.

Home shows recent audits, monthly audit counts, active local audit rows, setup
attention items, quick shortcuts, and sync status. The active-audit count comes
from rows in `audits` whose status is `active`; visit completion is tracked
separately in `audit_sessions`.

## 4. Station Screens

All station screens initialize an `AuditProvider` with `AuditContext`, hide
their own app bar when embedded in `AuditSessionScreen`, and use read-only mode
for existing audits unless edit mode is enabled by an allowed user. Visit
sessions use a default-height gradient station app bar and a compact raised
bottom navigation bar with the primary Next Station/Save action. Most stations
also show a white compact stepper strip with short wrapping station labels; Hatch
Analysis & Egg Breakouts hides that strip so its Hatching & Breakout card is
the first content on the screen.

Audit numeric fields use a platform-adaptive input surface. Android and iOS
targets open the large in-app audit keypad with decimal, negative, backspace,
next, and grid-down actions. Desktop targets, including web browsers whose
platform string reports macOS, Windows, or Linux, use the normal editable text
field so physical keyboard entry works without opening the custom keypad. Both
paths enforce the same numeric rules for decimal, negative, and
max-decimal-place limits.

Egg is the station name shown across the app. The station is divided into
storage and handling controls plus Egg Quality Assessment. It starts with a
gradient Audit Station card showing the selected hatchery, then uses a split
workbench layout. The left column contains EST, upside-down scoring, and the
storage checklist. The right column contains egg quality context/sample
controls, UV inspection, and station notes.

- Egg Shell Temperature (EST): storage days, target shell-temperature class,
  inline guided OCR capture, EST grid, per-point evidence photos, average, and
  CV%. Shell targets are 19.0-21.0°C for short storage, 18.0-20.0°C for medium
  storage, and 16.0-18.0°C for long storage.
- UV Tray Inspection: up to 10 UV tray entries and overall affected average.
- Upside Down Score: tray entries and overall upside-down average.
- Egg Quality Assessment: shows flock, breed, BMK age, single-sample versus
  multi-house sample mode, house sample chips, and the 100-egg weight sheet.
  BMK age is derived from the flock entry date when available and falls back to
  the saved flock age from the visit/session record. The panel uses its embedded
  blue context header without a duplicate workbench header or descriptive
  subtitle. Multi-house mode keeps the add/remove house controls together at the
  right edge and persists each house as a comparison sample with sequential
  `H1`, `H2`, etc. house metadata in `station_samples`. The 100-egg sheet uses
  a compact, responsive numeric grid with single rounded number-only input
  fields.
- Storage Checklist: egg turning, tray spacing, cooler proximity,
  condensation, and related storage fields.
- Notes: optional free-text station comments persisted on the audit row.

Chicks uses a split workbench structure instead of tabs. The screen
starts with a blue gradient Audit Station card showing Chick quality and the
selected hatchery context. The workbench uses two columns on wide screens and
collapses into one scrollable column on smaller screens. The Chicks screen does
not render its own sticky save footer; visit sessions use the session-level
Back / Next Station navigation, and standalone editor saves are handled outside
this embedded workbench. When opened from a resumed visit session, Chicks
restores all saved comparison sample rows and linked station samples before rendering the
workbench.

The left workbench column contains Pasgar Score, YFBM, Chick Vent Temperature,
and PM Necropsy panels. Pasgar captures sample size, defect counts/photos, and
the final score. YFBM keeps the YFBM photo plus average percentage and CV%
visible in the panel; the add/delete row table opens from an Enter YFBM Entries
bottom sheet and writes the existing YFBM entries and calculated fields. Chick
Vent Temperature reuses the EST-style guided grid workflow with Front/Middle/
Back by Top/Middle/Bottom points, Guided CVT capture, inline camera/native
camera fallback, auto scan, confirm/edit, retake, skip, clear reading/photo,
missing-photo attach, and saved-photo highlighting. CVT uses a 103-105°F /
39.4-40.6°C target, has an inline °F/°C entry toggle, persists grid readings
and photos locally in `cvtReadingsJson` and `cvtPhotosJson`, and backfills the
legacy CVT average/CV/top/middle/bottom summary fields for dashboards and old
detail views. PM Necropsy captures sample size, collection point, lesion counts
with required severity when count is positive, gasping fields, deformity
counts, suspected cause, and PM photos.

The right workbench column contains Chick Weights & Uniformity. Its embedded
blue flock card shows flock, breed, and BMK age. Chick Sample Mode lives inside
this panel and offers Single Sample or Multi House Samples while reusing the
existing station sample provider and persistence behavior. Multi-house mode
shows comparison sample chips plus add/remove controls. The panel shows average
weight, BMK chick weight, sample count, low/high margins, CV%, and uniformity.
The 100-chick weight entry grid opens from an Enter Weights modal sheet and
persists to the existing `chickWeights`, `chickAvgWeight`,
`chickUniformityPct`, and `chickCvPct` audit fields.

Hatch Analysis & Egg Breakouts is an egg breakout entry screen rather than a
tabbed screen. It uses a centered workbench layout with a compact blue gradient
Breakout Type card, a separate matching blue metadata card, a neutral Breakout
Samples panel, and the existing sticky
station navigation footer when embedded in a visit session. Breakout types are
Fresh Egg, Candled Egg, and Residue / Hatch Day. The Breakout Type card keeps
the selector beside the header title on wider layouts and stacks it vertically
on mobile. The metadata card shows auto-filled flock, breed, read-only BMK age,
and editable Storage Days; Candled Age appears as an additional entry field only
when Candled Egg is selected. The BMK age is displayed as `wks` and is
calculated from current flock age minus storage days
and the breakout-specific incubation offset: 0 days for Fresh Egg, the entered
candled age for Candled Egg, and 21 days for Residue / Hatch Day. Benchmark
lookup still uses the calculated day value, then stores the legacy week value in
the existing BMK age fields. When opened from a resumed visit session, Hatch
Analysis restores all saved breakout audit rows and linked station samples
before rendering.

Breakout Samples sits below the main card. It uses tray chips plus circular add
and remove controls to manage tray samples while keeping the tray cards visible
in the scroll view. The tray/pool toggle is not shown in the current UI; legacy
pool samples remain decodable and are converted to tray-style display while
preserving their sampled-egg denominator. Breakout samples are scoped by
breakout type in the shared JSON field: switching Fresh Egg, Candled Egg, and
Residue / Hatch Day hides the other type's entered rows, and returning to a type
restores its previous tray values. Each tray card has label, position, tray
size, and one-column breakout item rows. Each breakout item row contains a count
input, a calculated percentage from the tray size, and a read-only BMK target
percentage loaded from the nearest `bmk_egg_breakout` row for the calculated BMK
age. Count inputs keep focus while values are typed and the keyboard next action
moves to the following breakout item count. Rows turn into a warning state when
the calculated percentage is higher than the BMK target after a positive count
has been entered; the warning is shown through row and BMK tile styling rather
than an icon.

Setters captures:

- Breed from flock.
- Setter ID.
- Incubation age slider from 1 to 18 days.
- Machine type: Single Stage or Multi Stage.
- Turning angle.
- CO2 level and photo.
- EST average/CV summary and EST grid/photos.

Hatchers captures:

- Breed from flock.
- Hatcher ID.
- Incubation age slider from 18 to 21 days.
- CO2 level and photo.
- CVT average/CV summary and CVT grid/photos.
- Chick panting yes/no with photo.
- Meconium assessment: Normal, Greenish, Watery, or Excessive.
- Transfer day.

Govee is a standalone daily capture workflow. It is independent from audit
sessions and is keyed by `customerId`, `hatcheryId`, place, nullable machine id,
and calendar `captureDate`. The Govee screen is
active-recording only; saved captures are reviewed from dashboard surfaces
rather than browsed in the Govee tab.

The active Govee recorder opens on a ChickMark-blue gradient live header that
mirrors the Govee app's device-first hierarchy while keeping ChickMark colors.
The header centers the device name and connection status, shows large
Temperature and Relative Humidity values side by side, displays the latest
updated-at timestamp, and exposes a clear `Scan`, `Read`, or reconnect action.
The old historical browser tabs and export affordance are not part of the active
recording screen. On Flutter Web, Bluetooth initialization is pre-warmed when
the screen opens, but the Web Bluetooth device request is still started directly
from the user's Scan tap so Chrome keeps the permission request attached to the
gesture. On iOS and macOS, Scan uses adapter-state readiness as the preflight
check and avoids the FlutterBluePlus Darwin `isSupported` call that can produce
duplicate native method responses. Native Scan waits briefly for CoreBluetooth
to leave its initial unknown state and avoids duplicate first-start adapter
state reads before scanning. The macOS CocoaPods build stamps the same
Bluetooth usage descriptions into the embedded FlutterBluePlus framework as the
main app bundle so macOS TCC does not abort the app when CoreBluetooth is first
initialized.

Each saved place/date capture is one manual place-level Start/Stop window. Live
readings are shown only as a preview while recording. When the user stops, the
provider syncs Govee history for the full Start/Stop window and treats that
history sync as the authoritative saved dataset. The first 60 seconds of the
window are warmup and ignored before statistics or chart reduction. Readings with
missing Temp/RH values, impossible temperatures, or RH outside 0-100% are also
excluded.

Summary statistics are computed from the full valid synced dataset before any
chart reduction. Each completed capture stores Temp and RH average, minimum,
maximum, standard deviation, coefficient of variation percent, and the saved
representative reading count. Stored chart points are selected with LTTB using
timestamp as X and `temperatureFahrenheit + humidity` as the combined Y value.
The LTTB target is 10% of valid readings, clamped to a minimum of 50 and maximum
of 500; valid datasets of 50 readings or fewer are saved whole. First and last
valid readings are preserved.

The recorder body shows the selected place and station/machine context, plus
recording, syncing, retry, saving, and saved states. While recording, the screen
renders live Temperature and RH preview charts. After save, it shows a finished
place card with Avg, Min, Max, SD, CV%, and separate saved Temperature and RH
charts. Chart touches show the exact timestamp, Temp, RH, place, and machine
context when present.

If history sync cannot reconnect or otherwise fails during Stop, no capture is
saved. The recorder keeps the Start/Stop window and exposes a
reconnect-and-retry state for the same place recording. In that state, Retry sync
is the primary action and starting a fresh recording is blocked so the failed
history window is not accidentally overwritten. The failed state also shows sync
diagnostics: the caught error, connected device/GATT/RSSI/window context, and the
most recent BLE diagnostic entries from the Govee service.

Govee history sync uses the Govee GATT command/data characteristics. Live reads
continue to use the `2011` command characteristic. History writes go through the
`2012` history/control characteristic, `2012` also carries acceptance and
completion notifications, and `2013` carries history data packets. H5051/H5179
class devices use the 10-byte epoch-minute history request (`0x0000` plus
little-endian start/end epoch minutes) and parse `2013` packets as an epoch
minute followed by 4-byte little-endian Temp/RH records. Older H507-style
devices keep the `0x3301` 20-byte minute-back request with checksum and packed
3-byte records. The requested stop bound is kept at least one minute back
because the current minute may not yet be stored in device history. The service
logs the packet and reading counts used for hardware validation. Live GATT
polling is paused while a history sync is active so `0x0A` preview reads do not
overlap the history transaction. If GATT drops during an active history
transaction while auto-reconnect is available, the service keeps the original
Start/Stop window pending, reconnects, re-enables notifications, and reissues
the history request before surfacing a sync failure.

Saving a capture atomically replaces any existing capture for the same customer,
hatchery, place, machine id, and date. Captures store a derived station key for
station-aware grouping and sync. The old capture remains intact until the new
place-level recording is saved successfully. After saving, the active live
preview is cleared and the screen can suggest the next default place in this
flow: Egg storage room, Chick holding area, Setter room, Inside setter, Hatcher
room, and Inside hatcher.

Audit station screens show a compact `Govee readings` button for room-level
stations with a mapped place: Egg storage room, Chick holding area, Setter room,
and Hatcher room. Opening from Setters or Hatchers shows a compact room vs.
inside-machine choice before recording. Room environment captures save without a
machine id. Inside-machine captures save the active station machine id when it is
available. Other station entries preselect customer, hatchery, and place in the
Govee tab, while still letting the user change the place before recording.

Dashboard has a cascade filter for Customer, Flock, and Age. It loads visit
session summaries plus Hatch Analysis & Egg Breakouts, Egg Breakout, Chicks,
Egg, Setters, and Hatchers sections from repository queries. Egg Storage
dashboard trends read the persisted EST average/CV fields
`es_estAvg`/`es_estCv`.

When the selected visit date has saved Govee captures for the same customer and
hatchery, Dashboard shows a dedicated `Govee Environmental Readings` section.
Those Dashboard records are loaded by `customerId`, `hatcheryId`, and
`captureDate`; they are not hard-linked to audit session ids. The section has
local place chips when more than one place exists, and local machine chips when
inside-setter or inside-hatcher records provide more than one machine option.
These filters affect only the Govee section. Each capture card shows place,
machine when present, recording time range, Temp avg/min/max/SD/CV%, RH
avg/min/max/SD/CV%, and saved representative reading count. Each card renders
separate timestamp-based Temperature and Relative Humidity charts from
place-level LTTB readings. Dashboard chart touches show exact timestamp,
temperature, RH, place, and machine when present.

## 5. Data Hierarchy

The implemented hierarchy is:

- `users`: authenticated identities, roles, approval status, optional customer
  assignment, cached token metadata, and local password fallback data.
- `customers`: top-level customer records.
- `hatcheries`: customer-owned hatchery/location records.
- `flocks`: customer-owned flocks with breed, entry date, estimated-age flag,
  active/sold status, depletion age, and sold date.
- `audit_sessions`: visit-level orchestration for a selected customer,
  hatchery, flock, date, station order, station completion, optional findings,
  optional scorecards, notes, creator, and completion timestamp.
- `audits`: legacy and station audit data rows. Each row stores the station
  audit type plus station-specific fields, sample mode, compare group, hatch
  number, optional `sessionId`, photos embedded as field paths/JSON, and status.
- `station_samples`: companion sample rows linked to `audit_sessions` and
  optionally to a legacy `audits` row. These normalize sample mode, comparison
  type, station type, sample index, hatch/batch labels, production/setting/hatch
  dates, house labels for Egg multi-house samples, storage/incubation
  metadata, machine ids, BMK age days, benchmark snapshots, and result
  summaries.
- `temperature_sessions` and `temperature_readings`: legacy place-based
  temperature/RH logs. Audit-linked temperature rows are deleted during the v22
  migration and the new Govee workflow does not query them.
- `govee_daily_captures`: saved Govee place/day captures scoped by customer,
  hatchery, place, machine id, and capture date, with station key, capture
  start/end timestamps, device metadata, aggregate Temp/RH average/min/max/SD/CV
  summaries, and representative reading count.
- `govee_place_readings`: LTTB-selected representative readings for each saved
  place/day capture, ordered by reading index with timestamp, Temp, RH, and
  creation timestamp.
- `photos`: local photo records tied to audit ids, with upload status.
- `bmk_breeds` and `bmk_egg_breakout`: seeded benchmark reference data.
- `troubleshooting`: seeded troubleshooting/reference content.
- `activity_log`: user actions for logins, syncs, session starts/resumes,
  station completion, audit changes, and related events.

Visit session summaries combine one `audit_sessions` row and its station
audits. Scorecards are parsed from persisted JSON when present; otherwise they
are derived from completion state and simple threshold heuristics. Dashboard
Govee summaries are loaded separately by customer, hatchery, and selected visit
date.

## 6. Models and Provider State

`AuthProvider` manages auth state, Supabase sign-in/sign-up, offline/local login
fallback, cached token checks, pending approval state, and logout. Local fallback
users are stored with ids prefixed by `local-` and v2 salted SHA-256 password
hashes.

`CustomersProvider` owns customer, flock, hatchery, audit, visit-session, lookup,
and selected-customer state. It scopes data for customer-role users, supports
customer/flock/hatchery CRUD, and loads visit summaries for customer detail
views.

`AuditSessionProvider` owns the active visit session, station order, current
station index, movement state, resume state, selected station keys, and session
errors. It starts, resumes, progresses, completes, deletes, and clears visit
sessions.

`AuditProvider` owns station draft rows and station samples. It supports pooled
and comparison sample modes, creates/removes/switches samples, tracks dirty
state, saved tabs, active session id, temperature unit, read-only/edit mode, PM
conditional validation, hatch budget validation, hatch metric recalculation, and
save coalescing through an in-flight save future.

`DashboardProvider` owns cascade filters, available BMK ages, setter/hatcher
filter sets, dashboard aggregate models, photo lists, BMK references, scoped
customer/flock data, visit summaries, selected visit summary, and saved Govee
capture summaries loaded by the selected visit customer, hatchery, and date.

`GoveeCaptureProvider` owns the active standalone Govee capture scope, existing
capture lookup, manual Start/Stop place recording, live preview readings,
history-sync retry state, warmup/invalid filtering, full-dataset Temp/RH summary
stats, LTTB representative readings, replacement save, finished-place preview,
and next-place progression.

`TemperatureRhProvider` owns BLE/Govee initialization, scan/connect state,
preferred device persistence, active place/session, live and saved readings,
recording pause/resume, warmup filtering, summary calculation, chart
downsampling, and the measure log.

`BmkProvider` reads seeded breed and egg-breakout benchmark rows from SQLite and
tracks selected breed, selected ages, and selected egg-breakout type.

`HomeProvider` derives Home KPIs from audit and flock repositories: audits this
month, active flocks, last audit date, recent audits, and audit type breakdown.

## 7. Persistence Summary

The app uses SQLite through `sqflite` at database version 25. The database file
is `hatchaudit.db`. Foreign keys are enabled on configure. Web startup
initializes the default sqflite factory with `sqflite_common_ffi_web` before the
database opens and uses the browser-safe `hatchaudit.db` name directly instead
of a native database directory. Browser persistence relies on the checked-in
`web/sqlite3.wasm` asset and runs without the shared-worker factory during app
startup.

Tables created by the current database helper include:

- `users`
- `customers`
- `flocks`
- `audits`
- `bmk_breeds`
- `bmk_egg_breakout`
- `troubleshooting`
- `photos`
- `activity_log`
- `hatcheries`
- `audit_sessions`
- `station_samples`
- `temperature_sessions`
- `temperature_readings`
- `govee_daily_captures`
- `govee_place_readings`

The current `audits` unique index is on `customerId`, `flockId`, `date`,
`auditType`, `hatchNumber`, `setterId`, and `hatcherId`. Repository writes use
id-based upsert behavior for audits and audit sessions.

The database helper includes upgrade paths through v25. Recent schema areas in
the current code include audit sessions, station samples, hatcheries,
temperature sessions/readings, operational indexes, PM necropsy fields, Egg
Storage fields, Setter/Hatcher extra fields, station sample house fields, a v20
station sample rebuild, v22 standalone Govee capture tables, and the v24
machine-aware Govee capture rebuild. The v22 upgrade also deletes old
audit-linked `temperature_sessions` and `temperature_readings` rows. The v24
upgrade normalizes legacy Govee setter place names. The v25 upgrade rebuilds the
Govee schema around `govee_daily_captures` and `govee_place_readings`, removes
new writes to the old spot tables, preserves existing daily captures, migrates
old spot readings into place-level readings, and drops the old spot tables after
migration.

Seed data is inserted for BMK breed rows, BMK egg breakout rows,
troubleshooting rows, and dummy test data during database creation/upgrade.

Photos are copied into the app documents directory and referenced by local file
path. The `photos` table tracks `uploadStatus` as `local`, `synced`, or
`failed`. Photo sync uploads local photos when Supabase is available, skips
missing files, and fails files larger than 5 MB.

Supabase sync is best effort. `StartupSyncService` pushes local customers,
flocks, hatcheries, audits, audit sessions, photos, temperature logs, and Govee
capture tables in dependency order, then pulls shared data back into local
repositories. It keeps newer local audit rows when a pulled remote row is older
by `updatedAt`. `BgSyncService` runs this sync after the shell starts and
reports failure as offline data available.

Temperature/RH sessions are persisted first as active/syncing rows and then as
completed summaries. Summary readings exclude warmup data, out-of-range values,
and missing temperature/RH values. Summary fields include min, max, average,
CV%, reading count, and downsampled chart JSON.

OCR uses Google ML Kit text recognition when available, with preprocessing,
quality checks, timeouts, and temporary-file cleanup for thermometer scan
capture.

## 8. Known Technical Debt

- The app currently keeps both legacy station data in the wide `audits` table
  and normalized companion rows in `station_samples`.
- Saved station audit rows are initialized with status `active`; visit
  completion lives on `audit_sessions`, so Home's active audit count can differ
  from completed visit state.
- `DiagnosticEngine.evaluate` is a placeholder that returns no findings.
- Visit-session scorecards use persisted JSON only when present; otherwise they
  use fallback threshold heuristics in `VisitSessionSummary`.
- The legacy single-station flow is still present in code alongside the newer
  visit/session flow.
- The database includes dummy test data seeding in the database helper.
- `audits` remains a very wide table with station-specific columns for all
  station types.
- Supabase sync is best effort and failures are logged/debugged rather than
  surfaced as blocking workflow errors.
- Some legacy temperature/RH provider code remains for old rows and tests, but
  the user-facing tab is now the standalone Govee workflow.

## 9. Change Log

- 2026-05-07: Split Govee history sync by device family: H5051/H5179 names now
  use the 10-byte epoch-minute request on `2012`, older H507-style names keep
  the `0x3301` minute-back request, live `0x0A` reads stay on `2011`, and the
  sync window avoids the not-yet-stored current minute.
- 2026-05-07: Reworked Govee capture persistence to one manual place-level
  Start/Stop window, added Temp/RH SD and CV% summaries, replaced bucketed spot
  readings with LTTB-selected `govee_place_readings`, migrated old spot readings
  into place-level rows, removed spot labels/boundaries from Dashboard Govee
  charts, and synced the new table through startup Supabase sync.
- 2026-05-07: Hardened native Govee Scan on iOS/macOS by using adapter-state
  readiness instead of the FlutterBluePlus Darwin `isSupported` preflight that
  can emit duplicate native method responses, and by avoiding duplicate
  first-start adapter state reads while CoreBluetooth is still initializing.
  The macOS build also injects the Bluetooth usage descriptions into the
  embedded FlutterBluePlus framework to satisfy TCC when the framework touches
  CoreBluetooth.
- 2026-05-07: Tightened the visit-session station shell with a default-height
  station app bar, compact progress strip, smaller station icons/labels, and a
  shorter bottom navigation footer. Progress labels wrap to avoid hidden station
  names in five-station visits.
- 2026-05-06: Added the Dashboard `Govee Environmental Readings` section with
  local place/machine filters, timestamp-based Temperature and RH charts, and
  detailed chart touch tooltips loaded by selected hatchery/date.
- 2026-05-06: Bumped SQLite to v24 for machine-aware Govee capture scope,
  renamed Govee setter places, and preserved legacy Govee records during
  migration. This was superseded by the v25 place-level readings migration.
- 2026-05-06: Updated an intermediate Govee recording provider iteration; the
  active behavior is now the v25 place-level Start/Stop flow.
- 2026-05-06: Redesigned the active Govee entry screen with the gradient live
  header, station room/inside-machine picker, and Temp/RH preview charts.
- 2026-05-03: Scoped the floating Govee shortcut to `MainShell` so the launcher
  does not rebuild the root navigator or retrigger startup background sync.
- 2026-05-03: Restored the scoped floating Govee shortcut on the authenticated
  main shell as a hardware-validation entrypoint while keeping the standalone
  Govee capture workflow unchanged.
- 2026-05-03: Restored H5051 live Scan/Read controls and the stored-history
  `0x3301` sync path needed to validate device history before redesigning the
  visit-based Govee model.
- 2026-05-02: Replaced the Measures tab/launcher with standalone Govee daily
  captures, added Govee persistence and sync tables, exposed station deep links,
  and moved saved Govee charts to dashboard/visit surfaces.
- 2026-04-28: Replaced placeholders with a code-derived map of current
  navigation, audit workflow, station screens, data hierarchy, provider state,
  persistence, sync, measures, OCR, and known technical debt.
- 2026-04-28: Created living spec placeholder and reset documentation source of
  truth to the implemented Flutter codebase.
