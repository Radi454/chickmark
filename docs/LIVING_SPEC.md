# Living Spec — Current Implemented Behavior

This file documents behavior mapped from the current Flutter codebase. The
current Flutter codebase remains the primary source of truth. If this document
and code conflict, inspect the code and report the mismatch.

This file must be updated after every meaningful code change.

## 1. Last Updated

2026-05-15

Mapped from the current working tree under `lib/`, especially app bootstrap,
navigation, audit screens, providers, models, repositories, services, and the
SQLite database helper. This update intentionally does not use deleted or old
feature specs as source material.

## 2. Navigation

App bootstrap starts in `main.dart`, initializes SQLite before `runApp`, then
starts token migration, notifications, and guarded Supabase initialization in
the background. Supabase service calls wait for that initialization guard before
reading `Supabase.instance.client`, so remote auth and sync calls cannot race
ahead of the client setup.

The user-facing app name is ChickMark. `MaterialApp.title`, web document
metadata, and PWA manifest metadata use `ChickMark`; the Dart package name and
local database filename remain `hatchaudit` for import and storage
compatibility.

The supported local web development origin is `http://127.0.0.1:57863`. Web
accounts and entered data are scoped to the browser origin, so using this stable
host and port preserves the local IndexedDB-backed database across runs. Local
web previews should be started from Flutter tooling on the same origin with
`make run`; this delegates to `make restart-web` so stale running preview
servers are replaced with the current code. `make run-web` remains available
when the existing preview should be reused instead of restarted. Local debug
run scripts pass the explicit compile-time
`CHICKMARK_DEBUG_AUTH_BYPASS=true` flag for developer convenience; production
build targets do not pass that flag.

`HatchAuditApp` registers these root providers: `AppProvider`, `AuthProvider`,
`CustomersProvider`, `AuditProvider`, `AuditSessionProvider`,
`GoveeCaptureProvider`, `BmkProvider`, `SettingsProvider`, and
`DashboardProvider`.

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
the floating Govee shortcut shown for authenticated users and the explicitly
enabled debug auth bypass. The floating shortcut is mounted at the app
Navigator layer, so it remains visible on the main shell and pushed audit
station screens while opening the same standalone Govee workflow. The shortcut
reflects active Govee recording state globally: idle uses the standard
ChickMark-blue circular thermometer button, while an in-progress recording
switches to a red rounded stop-style button.

The station-selection screen resets its Start Visit loading state when a pushed
visit-session route returns, so backing out from an audit station leaves the
selected visit order editable and the Start Visit button usable.

## 3. Audit Workflow

Debug auth bypass is available only when the app is both running in Flutter
debug mode and compiled with `CHICKMARK_DEBUG_AUTH_BYPASS=true`. The bypass
creates a local approved auditor identity and maps auth routes back to the main
shell, so the app opens on Home and audit creation is enabled for local
development. The bypass cannot activate in profile or release builds, even if
the compile-time flag is present. Outside that temporary debug bypass, only
approved admins and auditors can create or edit audits. Customer-role users are
read-only and scoped to their assigned `customerId`.

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
Hatch Analysis & Egg Breakouts suppresses the current-station progress strip so
its breakout header is the first station content. Chicks uses the standard
session progress strip.

Station save behavior:

- Station value changes schedule a quiet local draft autosave after the user
  pauses briefly. Draft autosave writes the same stable `audits` and
  normalized sample rows plus panel-owned sample rows with audit status
  `draft`, but it does not write activity-log entries, trigger threshold
  notifications, or start Supabase audit sync.
- Hatch Analysis & Egg Breakouts saves all samples and marks all tab indices saved.
- Other stations save through `AuditProvider.saveSamplesWithResult(tabIndex: 0)`.
- Saving persists legacy audit rows in `audits`.
- When a visit session id exists, saving also upserts linked normalized sample
  rows.
- Saving also upserts the corresponding panel-owned main/sample tables for the
  station. Current saves write Egg panels (`egg_storage`, `egg_quality`,
  `egg_weights`), Chicks panels (`chick_pasgar`, `chick_yfbm`, `chick_cvt`,
  `chick_pm`, and `chick_weights`), the selected breakout panel, Setter
  optimizing, or Hatcher optimizing while keeping `audits` as the compatibility
  row.
- Save/Next remains the final confirmation path. It retries any pending or
  failed autosave work, writes the audit row back as `active`, runs the existing
  log/threshold/sync side effects, and then allows station navigation or session
  completion.
- Final station saves report local persistence success independently from
  activity-log, threshold-notification, or Supabase side-effect failures. Those
  side-effect failures are debug-logged and do not mark the locally saved audit
  as failed.
- Autosave and explicit save requests share in-flight save work so repeated
  taps or rapid field edits do not create duplicate station rows. If an autosave
  fails, the station remains dirty and the final Save/Next path retries before
  navigation.
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
the first content on the screen. Visit sessions mount only the current station
at first, then keep previously opened stations mounted, so hidden future
stations do not hydrate their audit data before the user opens them.

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
  CV%. Storage Days defaults to `0` for new Egg audits and clears the default
  zero when focused for faster replacement. Shell targets are 19.0-21.0°C for
  short storage, 18.0-20.0°C for medium storage, and 16.0-18.0°C for long
  storage.
- UV Tray Inspection: up to 10 UV tray entries and overall affected average.
- Upside Down Score: tray entries and overall upside-down average.
- Egg Quality Assessment: shows flock, breed, BMK age, a Sampling scope control
  with One house and Compare houses choices, house sample chips, and the 100-egg
  weight sheet.
  BMK age is derived from the flock entry date when available and falls back to
  the saved flock age from the visit/session record. The panel uses a normal
  workbench header with a status pill, a neutral Sample setup context card, and
  a segmented Sampling scope selector. Multi-house mode keeps the add/remove
  house controls together at the right edge and persists each house as a
  comparison sample with sequential `H1`, `H2`, etc. house metadata in
  `sample_records` plus `sample_house_details`. The 100-egg sheet uses a
  compact, responsive numeric grid with single rounded number-only input
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
restores all saved comparison sample rows and linked normalized samples before
rendering the workbench.

The left workbench column starts directly with Chick Quality sampling controls
without a separate panel header, then contains expandable Pasgar Score, YFBM,
Chick Vent Temperature, and PM Necropsy panels so each optional chick-quality
test can be opened only when needed. The quality sampling control offers One
sample and Multisamples with blue gradient icons matching the station-card
language. The icons render inside small brand-gradient blue frames. Optional
chick-quality tests are followers of the selected quality sample scope: One
sample mode has no per-card sample subtitle and saves one pooled sample row for
Pasgar, YFBM, Chick Vent Temperature, and PM Necropsy, while Multisamples mode
shows the active setter/hatcher label, such as `S1H1 setter/hatcher sample`,
and saves one follower row per setter/hatcher sample for each of those panels.
Chicks quality comparison samples persist as `sectorType = chick_quality`,
`sampleKind = machine`,
`comparisonType = machine_comparison`, generated setter/hatcher labels such as
`S1H1`, `S2H2`, etc., `groupLabel = Machine comparison`, and setter/hatcher ids
in `sample_machine_details`. Pasgar captures sample size, six tracked defect
counts/photos, and the final score. The final score uses the first five scored
defect categories; feather development remains a tracked/displayed category but
does not reduce the score. Defect percentages are treated as invalid when a
defect count is negative or greater than the Pasgar sample size. Its embedded
card layout uses compact typography, icon sizes, and responsive defect-count
controls so labels, steppers, numeric fields, and photo buttons remain legible
in the narrow side-browser viewport. YFBM keeps the YFBM photo plus average
percentage and CV% visible in the panel; empty YFBM metric cards render as
neutral placeholders until rows are entered. The add/delete row table opens
from an Enter YFBM Entries bottom sheet and writes the existing YFBM entries and
calculated fields. Chick
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
blue flock card shows flock, breed, and BMK age inside one compact translucent
context strip; edit flows fall back to the selected flock breed when a Chicks
audit row does not carry a legacy breed field. Sampling scope lives inside this
panel and offers One sample or Multisamples. Weight comparison samples are
house samples: they persist as `sectorType = chick_weights`,
`sampleKind = house`, `comparisonType = house_comparison`, generated `H1`,
`H2`, etc. labels, `groupLabel = House comparison`, and house metadata in
`sample_house_details`. Multisamples mode shows house sample chips plus
add/remove controls, while the active house editor shows only the house field.
The panel shows average weight, BMK chick weight, sample count, low/high
margins, CV%, and uniformity. The weight metric grid flows without spacer-only
tiles, and the 100-chick weight entry grid opens from an egg-weight-style
draggable Enter Weights modal sheet and
persists per active house sample in `resultSummaryJson` while backfilling the
existing `chickWeights`, `chickAvgWeight`, `chickUniformityPct`, and
`chickCvPct` audit fields only for older detail views and compatibility.
Dashboard chick-weight trends do not read those legacy audit fields.

Hatch Analysis & Egg Breakouts is an egg breakout entry screen rather than a
tabbed screen. It uses a centered workbench layout with a compact blue gradient
Breakout Type card, a separate matching blue metadata card, a neutral Breakout
Samples panel, and the existing sticky
station navigation footer when embedded in a visit session. Breakout types are
Fresh Egg, Candled Egg, and Residue / Hatch Day. The Breakout Type card keeps
the selector beside the header title on wider layouts and stacks it vertically
on mobile. The metadata card shows auto-filled flock, breed, read-only BMK age,
and BMK age. Storage Days is an entry field in a separate entry card, defaults
to `0`, and clears its default zero on focus for faster replacement;
Candled Age appears as an additional entry field only when Candled Egg is
selected. The BMK age is displayed as `wks` and is calculated from current flock
age minus storage days
and the breakout-specific incubation offset: 0 days for Fresh Egg, the entered
candled age for Candled Egg, and 21 days for Residue / Hatch Day. A stored
session flock age of zero is treated as unknown, so the screen falls back to the
flock entry date when available; if BMK age still cannot be calculated, the
metadata card shows `--` instead of `0 wks`. Benchmark lookup uses the
calculated day value rounded to the nearest week, while legacy/display BMK week
fields use a ceiling week conversion. When opened from a resumed visit session,
Hatch Analysis restores all saved breakout audit rows and linked station
samples before rendering.

Residue / Hatch Day adds batch tabs directly below the Entry Fields card and
above Batch Results. Batch tab labels are generated from the batch setter and
hatcher fields as `S{setter}H{hatcher}`; the label itself is not separately
editable. New hatch-analysis batches default to setter and hatcher numbers
matching the hatch sequence, so the first three new residue batches appear as
`S1H1`, `S2H2`, and `S3H3` until their setter or hatcher number fields change.
Each residue batch keeps its own total eggs set, hatched chicks, culled chicks,
dead chicks, and tray breakout samples. Total eggs set defaults to `19200`.

Residue / Hatch Day shows a Batch Results card before Breakout Samples for the
active batch. Hatchability is `hatched chicks / total eggs set * 100`. Fertility
is the simple unweighted average of the active batch's valid tray fertility
percentages, where each tray fertility is `(tray sample size - infertile count)
/ tray sample size * 100`. HOF is `hatchability / fertility * 100` and is
allowed to exceed 100 when hatchability is greater than measured fertility.
Culled and dead percentages use the same total eggs set denominator.
Hatchability, Fertility, and HOF compare with the nearest breed benchmark for
the selected breed and calculated BMK age; warning styling is shown when those
values are below BMK. Culled and Dead compare with fixed limits of `1.0%` and
`0.2%`; warning styling is shown when those values are above the limit. Residue
no longer enforces the old 100-percent hatch-budget reconciliation.

Breakout Samples sits below the main card, and below the Batch Results card for
Residue / Hatch Day. It uses tray chips plus circular add and remove controls to
manage tray samples while keeping the tray cards visible in the scroll view. The
tray/pool toggle is not shown in the current UI; legacy pool samples remain
decodable and are converted to tray-style display while preserving their
sampled-egg denominator. Breakout samples are scoped by breakout type in the
shared JSON field: switching Fresh Egg, Candled Egg, and Residue / Hatch Day
hides the other type's entered rows, and returning to a type restores its
previous tray values. Each tray card has label, tray size, and one-column
breakout item rows. New Fresh Egg tray samples default to 30 eggs; new Candled
Egg and Residue / Hatch Day tray samples default to 150 eggs.
Candled Egg and Residue / Hatch Day tray cards also show a position selector;
Fresh Egg tray cards omit position because those eggs are not set in a machine
yet. Each breakout item row contains a count input, a calculated percentage from
the tray size, and a read-only BMK target percentage loaded from the nearest
`bmk_egg_breakout` row for the calculated BMK age. Fresh Egg rows are
Infertile, 24 hours, 48 hours, and Blood Ring. Candled Egg adds Black Eye.
Residue / Hatch Day uses Infertile, Early Dead, Mid Dead, Late Dead, External
Pip, Cracked, and Contaminated. Count inputs keep focus while values are typed
and the keyboard next action moves to the following breakout item count. Empty
or zero count values are treated as not entered for display, while still
contributing `0.0%` to the calculated percentage. Counts below zero, zero or
negative tray sizes, and counts greater than the tray size are invalid for
percentage output. Rows turn into a warning state when the calculated percentage
is higher than the BMK target after a positive count has been entered; the
warning is shown through row and BMK tile styling rather than an icon.

Setters captures:

- A dedicated setter chip row. The first setter uses the selected visit setter
  id when present; Add setter creates another setter in the same audit session.
  Setter tabs are labeled from the setter number as `S5`, `S7`, etc., and fall
  back to the sample sequence when no setter id is available.
- Breed from flock.
- Setter ID.
- Incubation age slider from 1 to 18 days plus a separate 0-23 hour slider.
- Machine type: Single Stage or Multi Stage.
- Turning angle.
- CO2 level and photo.
- EST average/CV summary and EST grid/photos.

Setter EST reuses the storage EST guided grid workflow with Front/Middle/Back
by Top/Middle/Bottom points, inline guided OCR capture, inline camera/native
camera fallback, auto scan, confirm/edit, retake, skip, clear reading/photo,
missing-photo attach, saved-photo highlighting, and per-point evidence photo
records. Setters uses Fahrenheit readings with an allowed range of
99.5-102.0°F and an optimum range of 100.0-101.0°F. Setter comparison samples
persist as machine samples with `sectorType = setter_optimizing`,
`sampleKind = machine`, `comparisonType = machine_comparison`, generated setter
labels, `groupLabel = Setter comparison`, and setter ids in
`sample_machine_details`. Setters does not expose the generic Sample Mode
selector; the dedicated setter row is the comparison control.

Hatchers captures:

- Breed from flock.
- Hatcher ID.
- Incubation age slider from 18 to 21 days plus a separate 0-23 hour slider.
- CO2 level and photo.
- CVT average/CV summary and CVT grid/photos.
- Chick panting yes/no with photo.
- Meconium assessment: Normal, Greenish, Watery, or Excessive.
- Transfer day.

Hatchers does not expose Sample Mode, sample tabs, or compare-sample controls;
it is entered as one machine record for the selected visit context.

Govee is a standalone daily capture workflow. It is independent from audit
sessions and is keyed by `customerId`, `hatcheryId`, place, nullable machine id,
and calendar `captureDate`. The Govee screen is
active-recording first, with same-day saved station chips pinned to the bottom
of the screen so previous saves stay available while the next place is being
recorded. Dashboard surfaces still provide the broader visit-level review.

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
maximum, sample standard deviation, coefficient of variation percent, the saved
representative reading count, and `chartPointsJson` in the capture row. Stored
chart points are selected with LTTB using timestamp as X and
`temperatureFahrenheit + humidity` as the combined Y value.
The LTTB target is 10% of valid readings, clamped to a minimum of 50 and maximum
of 500; valid datasets of 50 readings or fewer are saved whole. First and last
valid readings are preserved.

The recorder body shows the selected place and station/machine context, plus
recording, syncing, retry, saving, and saved states. While recording, the screen
renders live Temperature and RH preview charts. Saved stations remain in a
sticky bottom strip scoped to the selected customer, hatchery, and capture date;
tapping a saved station selects its saved chart card without clearing it when a
new recording starts. Saved and live chart cards use a Govee-style chart layout:
Max/Avg/Min value rail, dashed grid, dashed average line, smooth line with
subtle fill, start/end time labels, and visible zoom in, zoom out, and fit
controls. Chart touches show the exact timestamp, Temp, RH, place, and machine
context when present.

If history sync cannot reconnect or otherwise fails during Stop, no capture is
saved. The recorder keeps the Start/Stop window and exposes a
reconnect-and-retry state for the same place recording. In that state, Retry sync
is the primary action and starting a fresh recording is blocked so the failed
history window is not accidentally overwritten. The failed state also shows sync
diagnostics: the caught error, connected device/GATT/RSSI/window context, and the
most recent BLE diagnostic entries from the Govee service.

If history sync succeeds but the local capture save fails, the recorder keeps
the synced readings in memory, moves into a save-failed retry state, and retries
the database save without requesting another history sync. Live preview readings
are capped to the latest 500 points during long recordings; full saved
statistics still come from the synced history dataset, not the preview list.
Saved-capture lookup failures are surfaced as recoverable recorder errors and
do not block starting a new recording.

Govee history sync uses the Govee GATT command/data characteristics. Live reads
continue to use the `2011` command characteristic. History writes go through the
`2012` history/control characteristic, `2012` also carries acceptance and
completion notifications, and `2013` carries history data packets. H5051/H5179
class devices use the 10-byte epoch-minute history request (`0x0000` plus
little-endian start/end epoch minutes) and parse `2013` packets as an epoch
minute followed by 4-byte little-endian Temp/RH records. On these epoch-minute
devices, `2012` can report a single-byte `0x00` acceptance status, `0x03`
progress status, and `0x02` completion status. Older H507-style
devices keep the `0x3301` 20-byte minute-back request with checksum and packed
3-byte records. The requested stop bound is kept at least one minute back
because the current minute may not yet be stored in device history. The service
logs the packet and reading counts used for hardware validation. Live GATT
polling is paused while a history sync is active so `0x0A` preview reads do not
overlap the history transaction. If GATT drops during an active history
transaction while auto-reconnect is available, the service keeps the original
Start/Stop window pending, reconnects, re-enables notifications, and reissues
the history request before surfacing a sync failure. Before starting history
sync, the service waits for any in-flight GATT connect or service discovery and
rediscovers services if the device is already connected but the `2012`/`2013`
history characteristics are not yet cached.

Saving a capture atomically replaces any existing capture for the same customer,
hatchery, place, machine id, and date. Captures store a derived station key for
station-aware grouping and sync. The old capture remains intact until the new
place-level recording is saved successfully. After saving, the active live
preview is cleared and the screen can suggest the next default place in this
flow: Egg storage room, Chick holding area, Setter room, Inside setter, Hatcher
room, and Inside hatcher.

Audit station screens show a compact `Govee readings` card button for room-level
stations with a mapped place: Egg storage room, Chick holding area, Setter room,
and Hatcher room. Opening from Setters or Hatchers shows a compact room vs.
inside-machine choice before recording. Room environment captures save without a
machine id. Inside-machine captures save the active station machine id when it is
available. Other station entries preselect customer, hatchery, and place in the
Govee tab, while still letting the user change the place before recording.

Dashboard has a cascade filter for Customer, Flock, and Age. It loads visit
session summaries plus Hatch Analysis & Egg Breakouts, Egg Breakout, Chicks,
Egg, Setters, and Hatchers sections from repository queries. Egg Breakout
dashboard averages and trends ignore invalid category percentages when a
category count is negative or greater than its tray size. Egg Storage dashboard
trends read the persisted EST average/CV fields `es_estAvg`/`es_estCv`.
Chicks dashboard weight trends read normalized
`sample_records` with `sectorType = chick_weights`, group samples by dashboard
date, combine all positive raw `chickWeights` values from each sample's
`resultSummaryJson`, and derive average weight, CV%, and uniformity at query
time. CV and stored environmental standard-deviation summaries use sample
standard deviation by default. Uniformity uses the combined daily average +/-
10% range. Stale
`audits.chickAvgWeight`, `audits.chickUniformityPct`, and `audits.chickCvPct`
values are ignored for dashboard trends.

When the selected visit date has saved Govee captures for the same customer and
hatchery, Dashboard shows a dedicated `Govee Environmental Readings` section.
Those Dashboard records are loaded by `customerId`, `hatcheryId`, and
`captureDate`; they are not hard-linked to audit session ids. The section has
local place chips when more than one place exists, and local machine chips when
inside-setter or inside-hatcher records provide more than one machine option.
These filters affect only the Govee section. Each capture card shows place,
machine when present, recording time range, Temp avg/min/max/SD/CV%, RH
avg/min/max/SD/CV%, and saved representative reading count. Each card renders
separate timestamp-based Temperature and Relative Humidity charts from the
capture row's LTTB-selected `chartPointsJson`. Dashboard chart touches show
exact timestamp, temperature, RH, place, and machine when present.

## 5. Data Hierarchy

The implemented hierarchy is:

- `users`: authenticated identities, roles, approval status, optional customer
  assignment, cached token metadata, and local password fallback data. Remote
  session tokens are migrated out of SQLite into secure token storage where the
  platform supports it.
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
- `sample_records`: base companion sample rows linked to `audit_sessions` and
  optionally to a legacy `audits` row. These normalize station type, sector,
  sample kind, sample mode, comparison type, sample index/label, group labels,
  BMK age days, benchmark snapshots, and result summaries.
- `sample_house_details`, `sample_machine_details`, `sample_batch_details`, and
  `sample_timing_details`: detail rows keyed by sample record id for house
  labels, setter/hatcher ids, hatch/batch/storage/incubation metadata, and
  production/setting/hatch dates.
- Panel-owned sampling tables exist alongside the legacy sample tables. Each
  implemented panel has a main table for duplicated dashboard context and a
  `{panel}_samples` table for pool or comparison samples. Pool samples store
  `scopeType = pool` and `scopeLabel = Random`. Comparison samples store the
  selected identity path only where relevant, including house, setter, hatcher,
  trolley, and tray fields.
- `govee_daily_captures`: saved Govee place/day captures scoped by customer,
  hatchery, place, machine id, and capture date, with station key, capture
  start/end timestamps, device metadata, aggregate Temp/RH average/min/max/SD/CV
  summaries, representative reading count, and LTTB-selected chart points in
  `chartPointsJson`.
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

### Source of truth rules

`audits` is the legacy station-row table. It remains the source of truth for
station identity, customer/flock/date context, station status, session linkage,
legacy station fields that do not yet have normalized sample storage, and
backward-compatible summary fields used by older detail views.

`sample_records` is the source of truth for normalized station samples. Pooled
mode keeps one sample row per station sector. Compare mode keeps one row per
sample, preserving `sampleIndex`, labels, grouping, comparison type, BMK age
days, and sample-specific `resultSummaryJson`. Chick weight raw values,
average, CV%, and uniformity belong to `sample_records` rows whose
`sectorType = chick_weights`; the legacy chick-weight columns on `audits` are
compatibility mirrors and are not dashboard inputs. Normalized sample upserts
wrap the parent `sample_records` row and all detail rows in one SQLite
transaction so detail deletes cannot be committed separately from the
replacement parent/sample details.

Panel sample tables are the source of truth for panel-owned raw sample rows
once a panel is migrated to them. Their main panel tables carry duplicated
dashboard context for filtering, while `{panel}_samples` carry the pool or
comparison measurements. Dashboard values that represent averages, CV%, or
uniformity are derived at query time from normalized sample rows rather than
stored as conflicting dashboard facts.

## 6. Models and Provider State

`AuthProvider` manages auth state, Supabase sign-in/sign-up, offline/local login
fallback, cached token checks, pending approval state, and logout. The temporary
auth bypass starts the provider as an approved local auditor only when Flutter
debug mode and `CHICKMARK_DEBUG_AUTH_BYPASS=true` both allow it.
Local fallback users are stored with ids prefixed by `local-`. Local fallback
auth remains available by default for non-release development builds, is
disabled by default for release builds, and can only be enabled in release with
`CHICKMARK_ENABLE_LOCAL_FALLBACK_AUTH=true`. New local fallback passwords use
v3 PBKDF2-HMAC-SHA256 hashes with per-password random salts and iteration
metadata. Legacy local tokens and v2 salted SHA-256 hashes are accepted only for
migration and are upgraded to v3 after a successful local login.

`CustomersProvider` owns customer, flock, hatchery, audit, visit-session, lookup,
and selected-customer state. It scopes data for customer-role users, supports
customer/flock/hatchery CRUD, and loads visit summaries for customer detail
views.

`AuditSessionProvider` owns the active visit session, station order, current
station index, movement state, resume state, selected station keys, and session
errors. It starts, resumes, progresses, completes, deletes, and clears visit
sessions. Async start/resume work is guarded so stale loads cannot overwrite a
newer active session, and duplicate station-completion/session-completion
requests are ignored while the provider is already saving progress.

`AuditProvider` owns station draft rows and station samples. It supports pooled
and comparison sample modes, creates/removes/switches samples, tracks dirty
state, debounced local draft autosave status, saved tabs, active session id,
temperature unit, read-only/edit mode, PM conditional validation, hatch budget
validation, hatch metric recalculation, and save coalescing through in-flight
save futures.

`DashboardProvider` owns cascade filters, available BMK ages, setter/hatcher
filter sets, dashboard aggregate models, photo lists, BMK references, scoped
customer/flock data, visit summaries, selected visit summary, and saved Govee
capture summaries loaded by the selected visit customer, hatchery, and date.

`GoveeCaptureProvider` owns the active standalone Govee capture scope, existing
capture lookup, saved same-day capture summaries, selected saved station,
manual Start/Stop place recording, live preview readings, history-sync retry
state, warmup/invalid filtering, full-dataset Temp/RH summary stats, LTTB
representative readings, replacement save, finished-place preview, and
next-place progression.

`BmkProvider` reads seeded breed and egg-breakout benchmark rows from SQLite,
tracks selected breed, selected ages, and selected egg-breakout type, and
upserts internal BMK admin edits back into the same `bmk_breeds` and
`bmk_egg_breakout` rows used by audit and dashboard benchmark lookups.

`HomeProvider` derives Home KPIs from audit and flock repositories: audits this
month, active flocks, last audit date, recent audits, and audit type breakdown.

## 7. Persistence Summary

The app uses SQLite through `sqflite` at database version 34. The database file
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
- `sample_records`
- `sample_house_details`
- `sample_machine_details`
- `sample_batch_details`
- `sample_timing_details`
- `egg_storage`
- `egg_storage_samples`
- `egg_quality`
- `egg_quality_samples`
- `egg_weights`
- `egg_weights_samples`
- `chick_pasgar`
- `chick_pasgar_samples`
- `chick_weights`
- `chick_weights_samples`
- `chick_yfbm`
- `chick_yfbm_samples`
- `chick_cvt`
- `chick_cvt_samples`
- `chick_pm`
- `chick_pm_samples`
- `fresh_egg_breakout`
- `fresh_egg_breakout_samples`
- `candled_egg_breakout`
- `candled_egg_breakout_samples`
- `residue_breakout`
- `residue_breakout_samples`
- `setter_optimizing`
- `setter_optimizing_samples`
- `hatcher_optimizing`
- `hatcher_optimizing_samples`
- `govee_daily_captures`
- `sync_tombstones`

The current `audits` unique index is on `customerId`, `flockId`, `date`,
`auditType`, `hatchNumber`, `setterId`, and `hatcherId`. Repository writes use
id-based upsert behavior for audits and audit sessions.

The database helper includes upgrade paths through v34. Recent schema areas in
the current code include audit sessions, normalized station samples, hatcheries,
operational indexes, PM necropsy fields, Egg Storage fields, Setter/Hatcher
extra fields, normalized sample detail tables, a v20 station sample rebuild, v22
standalone Govee capture tables, and the v24 machine-aware Govee capture
rebuild. The v22 upgrade deletes old audit-linked temperature rows when those
legacy tables exist. The v24 upgrade normalizes legacy Govee setter place names
and tolerates older on-device Govee tables that do not yet have v25
`stationKey`/`machineId` columns.
The v25 upgrade rebuilds the Govee schema around `govee_daily_captures` and
removes writes to the old spot tables. The v26 upgrade repeats the preserving
Govee rebuild path for devices that upgraded through the demo-capture schema:
existing `govee_daily_captures` rows are copied into the current one-row capture
schema with LTTB chart points in `chartPointsJson`, and legacy spot/place tables
are removed after the copy. The v27 upgrade drops any remaining legacy Govee spot/place
tables and removes old audit-level Govee columns such as `soGoveeTemp`,
`hoGoveeHumidity`, and `esGoveeTemp`. The v28 upgrade drops the legacy
`temperature_sessions` and `temperature_readings` tables; saved Govee chart data
now lives only in `govee_daily_captures`. The v29 upgrade rebuilds
`bmk_egg_breakout` to the cleaned breakout benchmark columns only and reseeds
Fresh/Candled and Residue / Hatch Day values by flock-age band, with the 51-60
week ageing values reused for benchmark ages above 60 weeks.
The v30 upgrade adds Setter and Hatcher incubation-hour columns so station
audits can store the day and within-day hour separately. The v31 upgrade copies
legacy `station_samples` into normalized `sample_records` plus house, machine,
batch, and timing detail tables, verifies each legacy sample id was copied, and
only then drops the legacy table. The v32 upgrade creates additive panel-owned main tables
and matching `{panel}_samples` tables for Egg, Chicks, Hatch Analysis & Egg
Breakouts, Setters, and Hatchers without removing the legacy sample tables. The
v33 upgrade adds `sync_tombstones` so offline deletes can be retried and replayed
on other devices. The v34 upgrade rebuilds logical parent-link tables with
foreign keys after cleaning dangling references, preserving valid rows and
enabling cascade behavior for customers, hatcheries, sessions, audits, samples,
Govee captures, and panel sample rows.

Relationship safety is enforced in SQLite for the current parent-child graph:
`flocks` and `hatcheries` belong to `customers`; `audit_sessions` belongs to a
customer, flock, and hatchery; `audits` belongs to a customer and optional flock;
`photos` belongs to an audit; `sample_records` belongs to an audit session and
may also point to a legacy audit; sample detail tables belong to
`sample_records`; each panel table belongs to an audit session, customer,
optional audit, optional flock, and optional hatchery; panel sample tables
belong to their panel row; and `govee_daily_captures` belongs to a customer and
hatchery. Required missing parents are removed during the v34 corrective
migration where no valid parent can be inferred; optional dangling references
are nulled so valid local rows are preserved. `audits.sessionId` remains an
application-managed link rather than a database FK because startup pull imports
audits before sessions; session deletion nulls that link before deleting the
session row.

Repository upserts avoid SQLite `REPLACE` for parent tables with children.
Customers, flocks, hatcheries, station samples, panel rows, panel sample rows,
and pulled Govee captures use insert-or-update semantics so saving a parent does
not trigger hidden delete-and-reinsert cascades. Remaining `REPLACE` usage is
limited to childless/local reference rows such as BMK seeds, troubleshooting
seeds, photo rows, activity log rows, users, and sync tombstones.

Seed data is inserted for BMK breed rows, cleaned BMK egg breakout rows,
troubleshooting rows, and dummy test data during database creation/upgrade.
Internal BMK admin edits replace local `bmk_breeds` and `bmk_egg_breakout`
rows by id, so saved benchmark changes are immediately visible in BMK reference
views and benchmark lookups that read SQLite.

Photos are copied into the app documents directory and referenced by local file
path. The `photos` table tracks `uploadStatus` as `local`, `synced`, or
`failed`. Photo sync uploads local and failed photos when Supabase is available,
skips missing files, and fails files larger than 5 MB so failed uploads retry on
later sync runs. Uploaded photo rows store
non-public `supabase://photos/...` storage references by default; public storage
URLs are only written when the build explicitly sets
`CHICKMARK_ALLOW_PUBLIC_PHOTO_URLS=true`.

Supabase sync is best effort and offline-first. `StartupSyncService` pushes
local customers, hatcheries, flocks, audit sessions, non-draft audits,
`sample_records`, sample detail tables, panel sample tables, Govee captures, and
photo work in dependency order, then pulls shared data back into local
repositories in the same parent-before-child order. It keeps newer local audit,
session, normalized sample, Govee, and panel rows when a pulled remote row has
an older or invalid `updatedAt`, and sample detail rows are not pulled over a
preserved local sample parent. Local deletes create `sync_tombstones`; startup
sync uploads those tombstones, deletes remote rows child-before-parent, marks
successful tombstones synced, and applies remote tombstones locally so another
device reload removes stale rows. `BgSyncService` runs this sync after the shell
starts and reports failure as offline data available. The app assumes Supabase
tables and storage are protected by project RLS/storage policies for
authenticated users and their customer scope; the client only ships anon
credentials and never needs service-role access. Debug sync logs are sanitized
and do not print stack traces, tokens, row payloads, or raw BLE bytes.

Govee place captures are persisted as one completed daily capture row per
customer, hatchery, place, machine, and date. The row stores Temp/RH summary
fields and the representative LTTB chart points in `chartPointsJson`; the app no
longer writes separate generic Temp/RH session or reading rows.

OCR uses Google ML Kit text recognition when available, with preprocessing,
quality checks, timeouts, and temporary-file cleanup for thermometer scan
capture. OCR and photo pick/save/delete failures keep the same recoverable
return behavior and emit debug logs in development builds instead of silently
discarding the failure context.

## 8. Known Technical Debt

- The app currently keeps both legacy station data in the wide `audits` table
  and normalized companion rows in `sample_records` plus sample detail tables.
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
- Govee place names still share the `TemperaturePlace` enum while the active
  persistence path is the standalone Govee workflow.

## 9. Change Log

- 2026-05-13: Added a formula registry and centralized shared calculation
  behavior for BMK age conversion, Pasgar scoring, sample SD/CV, percent
  validation, residue hatchability/fertility/HOF, and egg-breakout dashboard
  guards. Invalid count-over-total percentages are suppressed except where HOF
  intentionally allows values above 100.
- 2026-05-13: Added the v34 relationship-integrity migration, foreign keys, FK
  cleanup tests, cascade/delete tests, invalid-parent insert tests, and safer
  insert-or-update repository upserts for parent tables with children.
- 2026-05-13: Hardened the highest-risk local persistence paths: V26 now
  preserves existing Govee daily captures during schema cleanup, V31 verifies
  legacy station-sample copies before dropping `station_samples`, station sample
  upserts run as one transaction, and legacy audit metadata patches write
  storage/BMK/incubation values only to the matching station fields.
- 2026-05-13: Split database lifecycle, schema builders, and migration helpers
  into focused database helper files while preserving the same SQLite upgrade
  behavior and test-only migration entrypoints.
- 2026-05-13: Hardened async/save recovery by guarding stale audit-session
  loads, coalescing duplicate station completion and save work, isolating final
  save side-effect failures from local persistence, preserving Govee synced
  readings for save retry, capping long-recording preview memory, and logging
  recoverable photo/OCR failures.
- 2026-05-13: Hardened production safety by requiring an explicit debug-mode
  compile flag for auth bypass, disabling local fallback auth by default in
  release builds, upgrading local fallback passwords to PBKDF2-HMAC-SHA256,
  gating Supabase access on initialization, storing non-public photo references
  by default, and reducing sensitive debug logging.
- 2026-05-13: Defined dashboard/source-of-truth rules for legacy audit rows,
  normalized station samples, and panel sample tables. Chicks dashboard weight
  trends now derive average weight, CV%, and uniformity from normalized
  `sample_records` chick-weight raw samples instead of stale legacy
  `audits` chick summary columns.
- 2026-05-13: Lifted the floating Govee shortcut from `MainShell` to the app
  Navigator overlay so it remains available on pushed audit station screens
  while continuing to open the standalone Govee workflow.
- 2026-05-13: Added an active-recording visual state to the floating Govee
  shortcut: the launcher changes from the idle blue circle to a red rounded
  stop-style button while Govee capture is recording.
- 2026-05-13: Added dedicated Setters multi-setter tabs in one audit session,
  with setter-number labels such as `S5`, restored saved setter station samples
  on resumed visits, and changed Setters EST to the storage-style guided OCR
  grid workflow using 99.5-102.0°F allowed and 100.0-101.0°F optimum ranges.
- 2026-05-13: Removed the generic Sample Mode controls from Hatchers; Hatchers
  stays as one machine record for the selected visit context.
- 2026-05-13: Added Residue / Hatch Day batch tabs below Entry Fields,
  generated from setter and hatcher numbers, per-batch Batch Results cards
  before tray breakout samples, residue hatchability/fertility/HOF/culled/dead
  calculations, breed benchmark comparison for Hatchability/Fertility/HOF, and
  fixed culled/dead percentage limits. Residue no longer enforces the legacy
  100-percent hatch budget.
- 2026-05-13: Added an internal BMK admin mode on the BMK screen. Approved
  internal users can switch from Reference to Admin, edit the selected breed
  benchmark row and selected egg-breakout benchmark row, validate numeric
  percentages/weights, and save back into the same local BMK tables consumed by
  audit and dashboard benchmark lookups.
- 2026-05-09: Hardened the v24 Govee migration so iPhones with legacy v23
  `govee_daily_captures` tables can open and continue through the v25 schema
  rebuild instead of crashing on missing `stationKey` columns.
- 2026-05-09: Fixed Select Stations returning from a visit-session route with
  Start Visit stuck in its loading/disabled state.
- 2026-05-09: Reduced visit station opening work by mounting only the current
  station initially and keeping previously opened stations mounted. Refined the
  embedded Govee entry point and Egg quality panel with a compact card button,
  normal workbench header, neutral sample context, segmented Sampling scope
  control, and lighter metric cards.
- 2026-05-09: Set new Egg station Storage Days to default to `0` and clear the
  default zero on field focus to speed numeric entry.
- 2026-05-09: Added 0-23 hour sliders beside the Setter and Hatcher incubation
  day sliders, storing the hour offsets in SQLite v30 audit columns.
- 2026-05-09: Added audit-station draft autosave for Egg, Chicks, Hatch
  Analysis & Egg Breakouts, Setters, and Hatchers. Station edits now debounce
  into local `draft` audit rows and linked station samples, show compact
  autosave status, retry before leaving when needed, and only publish active
  audit rows through Save/Next or startup sync.
- 2026-05-08: Fixed Hatch Analysis & Egg Breakouts count inputs so loaded zero
  counts remain visually blank like untouched fields, including cleaned residue
  Early Dead values migrated from legacy early-stage counts.
- 2026-05-08: Cleaned Hatch Analysis & Egg Breakouts BMK fields: Fresh Egg now
  uses Infertile, 24 hours, 48 hours, and Blood Ring; Candled Egg adds Black
  Eye; Residue / Hatch Day uses Infertile, Early Dead, Mid Dead, Late Dead,
  External Pip, Cracked, and Contaminated. SQLite v29 rebuilds
  `bmk_egg_breakout` to only those benchmark columns and reseeds 25-65 week BMK
  rows, reusing the 51-60 week values for ages above 60.
- 2026-05-08: Removed legacy generic Temp/RH persistence by dropping
  `temperature_sessions` and `temperature_readings` in v28, removing their
  startup sync path, and leaving `govee_daily_captures` as the saved chart
  source.
- 2026-05-08: Removed obsolete Govee schema leftovers by making
  `govee_daily_captures` the only active Govee table and dropping legacy
  audit-level Govee fields from the audits schema/model.
- 2026-05-08: Simplified Govee capture storage to one row per saved
  place/machine/date by moving LTTB chart points into
  `govee_daily_captures.chartPointsJson`, dropping the local
  `govee_place_readings` table on v26, and syncing only the capture row.
- 2026-05-08: Fixed Hatch Analysis & Egg Breakouts BMK age display so zero
  session flock age falls back to flock entry date and unresolved age displays
  as `--` instead of `0 wks`.
- 2026-05-08: Set Hatch Analysis & Egg Breakouts Storage Days to default to
  `0`, clear that zero on focus for faster entry, and display it in a separate
  entry card below the read-only metadata card.
- 2026-05-08: Removed the `REQUIRED` badge from the Hatch Analysis & Egg
  Breakouts Entry Fields card while keeping Storage Days as a separate entry
  field.
- 2026-05-08: Hid the breakout sample position selector for Fresh Egg entries;
  Candled Egg and Residue / Hatch Day continue to capture position.
- 2026-05-08: Set new Fresh Egg breakout tray samples to default to 30 eggs
  while keeping Candled Egg and Residue / Hatch Day tray samples at 150 eggs.
- 2026-05-08: Temporarily detached login/register in debug builds by enabling
  a development auditor auth bypass and routing auth screens back to Home while
  the app is under active build-out.
- 2026-05-08: Cleaned up the Govee capture UI: same-day saved stations now stay
  pinned in a bottom strip across new recordings, and saved/live charts use a
  Govee-style Max/Avg/Min rail with dashed grid, average line, and zoom controls.
- 2026-05-08: Hardened Govee history sync startup so it waits for in-flight GATT
  connect/discovery work and rediscovers services when a connected sensor only
  has the live `2011` characteristic cached before the `2012`/`2013` history
  characteristics.
- 2026-05-08: Matched H5051/H5179 epoch-minute history status handling to the
  captured device traffic: single-byte `0x00` accepts a request, `0x03` is
  progress, and `0x02` completes the sync after `2013` data packets arrive.
- 2026-05-07: Split Govee history sync by device family: H5051/H5179 names now
  use the 10-byte epoch-minute request on `2012`, older H507-style names keep
  the `0x3301` minute-back request, live `0x0A` reads stay on `2011`, and the
  sync window avoids the not-yet-stored current minute.
- 2026-05-07: Reworked Govee capture persistence to one manual place-level
  Start/Stop window, added Temp/RH SD and CV% summaries, replaced bucketed spot
  readings with LTTB-selected place-level chart points, migrated old spot
  readings into place-level rows, removed spot labels/boundaries from Dashboard
  Govee charts, and synced the new Govee data through startup Supabase sync.
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
- 2026-05-06: Bumped SQLite to v24 for machine-aware Govee capture scope and
  renamed Govee setter places.
- 2026-05-06: Updated an intermediate Govee recording provider iteration; the
  active behavior is now the standalone Govee place-level Start/Stop flow.
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
