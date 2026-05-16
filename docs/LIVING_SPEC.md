# Living Spec — Current Implemented Behavior

This file documents behavior mapped from the current Flutter codebase. The
current Flutter codebase remains the primary source of truth. If this document
and code conflict, inspect the code and report the mismatch.

This file must be updated after every meaningful code change.

## 1. Last Updated

2026-05-16

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
metadata, PWA manifest metadata, and Android/iOS native launcher metadata use
`ChickMark`; the Dart package name and local database filename remain
`hatchaudit` for import and storage compatibility.
The shared ChickMark logo asset and platform launcher icons use the cheerful
chick-and-check mark identity inside an egg-shaped blue outline.
The app uses a compact operational type scale: shared headings, section titles,
body copy, badges, app bars, and major station hero titles are intentionally
smaller than the previous large display scale so dense audit screens stay
scannable on phone-width layouts.

The supported local web development origin is `http://127.0.0.1:57863`. Web
accounts and entered data are scoped to the browser origin, so using this stable
host and port preserves the local IndexedDB-backed database across runs. Local
web previews should be started from Flutter tooling on the same origin with
`make run`; this delegates to `make restart-web` so stale running preview
servers are replaced with the current code. `make run-web` remains available
when the existing preview should be reused instead of restarted. The web
shortcut defaults to a profile web-server build with local Flutter web
resources so the Codex side browser can run the app without the Dart Debug
Chrome extension. Debug web mode is still available by setting
`WEB_BUILD_MODE=debug`. Local preview runs currently enable the temporary auth
bypass by default for developer convenience; production build targets cannot
activate that bypass.

`HatchAuditApp` registers these root providers: `AppProvider`, `AuthProvider`,
`CustomersProvider`, `AuditProvider`, `AuditSessionProvider`,
`GoveeCaptureProvider`, `BmkProvider`, `SettingsProvider`, and
`DashboardProvider`.

Initial route selection is auth-state driven:

- Authenticated users go to `/main`.
- Pending approval users go to `/pending-approval`.
- Loading, error, and unauthenticated users go to `/login`.
- `/register` and `/startup-sync` are also registered routes.

The main shell has six destinations:

- Home
- Dashboard
- Customers
- Audits
- BMK
- Settings

The shell uses a drawer on narrow layouts and a navigation rail at widths of
900px or greater. It lazily builds tabs, keeps a tab history stack for shell
back navigation, and triggers background sync after the first Home build.

The previous floating Measures launcher is no longer shown. Govee recording is
entered from a station-level Govee readings button or from the floating Govee
shortcut shown for authenticated users and the explicitly enabled debug auth
bypass. The floating shortcut is mounted at the app
Navigator layer, so it remains visible on the main shell and pushed audit
station screens while opening the floating Govee capture panel. The shortcut
reflects active Govee recording state globally: idle uses the standard
ChickMark-blue circular thermometer button, while an in-progress recording
switches to a red rounded stop-style button. Users can drag the shortcut to a
different screen position, and dragging or flinging it past the left or right
edge tucks it partly off-screen while leaving a visible strip for reopening.
The shortcut is hidden while root modal routes such as bottom sheets are open,
keeping station entry sheets unobstructed.

The station-selection screen resets its Start Visit loading state when a pushed
visit-session route returns, so backing out from an audit station leaves the
selected visit order editable and the Start Visit button usable.

## 3. Audit Workflow

Debug auth bypass is available only when the app is running as a non-release
build or on a localhost/127.0.0.1 web preview. The bypass is enabled by default
for now and can be disabled for a local run with
`CHICKMARK_DEBUG_AUTH_BYPASS=false`. The bypass
creates a local approved auditor identity and maps auth routes back to the main
shell, so the app opens on Home and audit creation is enabled for local
development. The Home and new-visit edit gates also honor this non-release
bypass so local previews can start new audits even before remote auth is
configured. The bypass cannot activate in release builds. Outside
that temporary bypass, only
approved admins and auditors can create or edit audits. Customer-role users are
read-only and scoped to their assigned `customerId`.

The current New Audit button on Home opens `AuditContextScreen` without an
`auditType`, which means it starts the visit/session flow:

- Select customer using the customer card with the person icon.
- The customer picker sheet includes an `Add` action in the header. It opens the
  shared Add New Customer sheet, and a saved customer becomes the selected
  customer for the new visit. Tapping the dimmed backdrop outside the picker
  dismisses the sheet without changing the current selection.
- Select hatchery for that customer using the hatchery card with the warehouse
  icon.
- Select an audit-available flock using the flock card with the chick icon.
  Flocks are unavailable when sold or past their depletion age.
- Continue to station selection.
- Select one or more stations from the five supported station keys and arrange
  their visit order. The Chicks station uses the shared chick icon in both the
  add list and selected visit-order list.
- Start Visit creates an `audit_sessions` row with status `in_progress`.

Supported station keys are:

- `egg`
- `chicks`
- `hatch_analysis_egg_breakouts`
- `setters`
- `hatchers`

`AuditSessionScreen` renders the selected stations in one visit workflow. It
shows a progress indicator, keeps one `AuditProvider` per station, and shows one
station at a time. Completed/reached station nodes use compact check marks
inside the progress circles. Moving forward, moving back, switching to an
earlier or completed station, leaving the visit, or saving the final station all
go through a station-exit confirmation path that attempts to save the current
station.
When a visit is resumed or a previously saved station is opened inside the
session, the station frame hydrates the station from panel rows for that
session. It synthesizes the current form draft objects from those panel rows so
the existing screens can render and resave in place without using legacy audit
or sample tables. Hatch Analysis & Egg Breakouts suppresses the current-station
progress strip so its breakout header is the first station content. Chicks uses
the standard session progress strip.

Station save behavior:

- Station value changes schedule a quiet local draft autosave after the user
  pauses briefly. Draft autosave writes panel rows only; it does not write
  activity-log entries, trigger threshold notifications, or start legacy audit
  sync.
- Hatch Analysis & Egg Breakouts saves all samples and marks all tab indices saved.
- Other stations save through `AuditProvider.saveSamplesWithResult(tabIndex: 0)`.
- Saving persists directly into panel tables. Pool mode creates one row in each
  affected panel table with `mode = pool`, `scopeType = pool`, `scopeLabel =
  Random`, and `sampleIndex = 1` for the first saved sample.
- Comparison mode creates multiple rows in the same panel table with `mode =
  comparison` and the relevant house, setter, hatcher, tray, trolley, or batch
  scope identity.
- Current saves write Egg panels (`egg_storage`, `egg_quality`),
  Chicks panels (`chick_pasgar`, `chick_weights`, `chick_yfbm`, `chick_cvt`,
  `chick_pm`), the selected breakout panel, Setter optimizing, or Hatcher
  optimizing.
- Save/Next remains the final confirmation path. It retries any pending or
  failed autosave work, persists panel rows, runs remaining local side effects,
  and then allows station navigation or session completion. Intermediate
  station saves move to the next station without the large completion check
  overlay; the overlay is reserved for final selected station completion.
- Final station saves report local panel persistence independently from
  activity-log or threshold-notification side-effect failures. Those failures
  are debug-logged and do not mark the locally saved station data as failed.
- Autosave and explicit save requests share in-flight save work so repeated
  taps or rapid field edits do not create duplicate station rows. If an autosave
  fails, the station remains dirty and the final Save/Next path retries before
  navigation.
- Reopened panel-row drafts may use synthetic in-memory IDs, but panel saves
  resolve conflicts by the panel row identity (`sessionId`, mode, scope, sample
  index, and group key) so reopened edits update the existing panel row instead
  of writing legacy audit/sample tables.
- Completing a station updates `audit_sessions.stationsCompleted`.
- Completing the final selected station updates the session to `completed` and
  returns to the main shell.

The legacy single-station flow still exists in code when `AuditContextScreen` is
constructed with an explicit `auditType`. It collects customer/flock context and,
for Setter or Hatchers, requires the relevant machine id before
opening a single station screen with a fresh `AuditProvider`.

The Audits tab lists recent visit sessions. In-progress sessions resume in
`AuditSessionScreen`; completed sessions open a session detail screen. Legacy
single-audit edit paths remain as compatibility UI code, but the current list
and save/load workflow are session and panel based.

Home starts with a compact left-aligned ChickMark icon mark, then shows monthly
visit counts, active local visit sessions, recent visit sessions, setup
attention items, quick shortcuts, and sync status. Counts and Recent Audits are based on
`audit_sessions` rather than legacy audit rows. Today's Focus metric cards are
actionable when they have a target: Continue opens the first active visit,
Attention opens the first setup/action item, and Ready starts a new audit when a
ready customer setup exists. The previous Audit Type Breakdown, extra
Customers/Active Audits/Total Audits stat cards, and duplicate New Customer/New
Audit action row are not shown on Home.

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
blue brand-gradient Egg storage room card with white foreground styling for the
selected hatchery, then uses a split workbench layout. The left column contains
EST, upside-down scoring, and the storage checklist as expandable cards. The
right column contains the Egg
quality hero, sample controls, expandable Egg Weights & Uniformity and Egg Shell
Quality cards, and station notes.

- Egg Shell Temperature (EST): storage days, target shell-temperature class,
  inline guided OCR capture, EST grid, per-point evidence photos, average, and
  CV%. The Storage Days field sits directly before the expandable Egg Shell
  Temperature card, defaults to `0` for new Egg audits, and clears the default
  zero when focused for faster replacement. The target summary labels are
  Storage duration and EST target. Shell targets are 19.0-21.0°C for short
  storage, 18.0-20.0°C for medium storage, and 16.0-18.0°C for long storage.
- Egg Shell Quality: expandable UV tray inspection with up to 10 UV tray entries
  and overall affected average. Fresh or empty tray data shows a default Tray 1
  editor before the add-tray action. Shell UV summary fields persist on the
  consolidated `egg_quality` row.
- Upside Down Score: tray entries and overall upside-down average. Fresh or
  empty tray data shows a default Tray 1 editor before the add-tray action.
  Its header uses an inverted egg symbol with the pointed end up. Upside-down
  score fields persist on the `egg_storage` row alongside the storage-side Egg
  cards.
- Egg Quality Assessment: shows a blue brand-gradient Egg quality card with
  white foreground styling for flock, breed, and BMK age in one equal-width row,
  a compact text-only Sampling scope
  segmented pill with calm selected-state styling for One sample and Multiple
  samples choices, and an expandable Egg Weights & Uniformity card containing
  house sample chips after multiple samples is chosen, an ordered row-style
  weight metric summary, and the 100-egg weight sheet. The metric summary follows
  the Chicks weight card order: Sample Size, BMK Egg Weight, Avg Weight, Low
  Margin, High Margin, Uniformity, and C.V. BMK Age stays in the Egg quality
  context card instead of the weights summary.
  BMK age is derived from the flock entry date when available and falls back to
  the saved flock age from the visit/session record. The station removes helper
  explanations from the EST, Upside Down, Storage Checklist, Egg quality hero,
  Sampling scope selector, Egg Weights & Uniformity card, Egg Shell Quality card,
  and Notes panel so only the operational labels remain. Egg workbench headers
  omit decorative mark badges such as `EST`, `EW`, `UV`, and `NT`, and omit
  header status pills such as `0/100` and `Avg affected 0.0%`. Expandable
  headers keep the title icon, title, and chevron as the only header controls.
  Multiple samples mode keeps the add/remove house controls together at the
  right edge and persists each house as a comparison row in the affected Egg
  panel tables with sequential `House 1`, `House 2`, etc. scope labels. The
  100-egg sheet uses a compact, responsive numeric grid with single rounded
  number-only input fields. Egg weights, sample size, average weight,
  uniformity, CV%, and BMK egg-weight fields persist on the consolidated
  `egg_quality` row instead of a separate Egg weights table.
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
test can be opened only when needed. These optional panel headers omit compact
mark badges and result pills such as Pasgar score, YFBM status, CVT status, or
PM review state; the full panel title and chevron are the only header controls.
The quality sampling control offers One sample and Multisamples in a compact
text-only segmented pill with a neutral track and subtle selected chip.
The Machine ID card keeps Setter and Hatcher inputs in one equal-width row,
including in narrow visit-session layouts. Optional chick-quality tests are
followers of the selected quality sample scope: One
sample mode has no per-card sample subtitle and saves one pooled sample row for
Pasgar, YFBM, Chick Vent Temperature, and PM Necropsy, while Multisamples mode
shows the active setter/hatcher label, such as `S1H1 setter/hatcher sample`,
and saves one follower row per setter/hatcher sample for each of those panels.
Chicks quality comparison samples persist as rows in the Chicks panel tables
with `mode = comparison`, `scopeType = setter_hatcher`, generated
setter/hatcher labels such as `S1H1`, `S2H2`, etc., and group label `Machine
comparison`. Pasgar captures sample size, six tracked defect
counts/photos, and the final score. The final score uses the first five scored
defect categories; feather development remains a tracked/displayed category but
does not reduce the score. Defect percentages are treated as invalid when a
defect count is negative or greater than the Pasgar sample size. Its embedded
card layout uses compact typography, text-only headings and defect labels, and
responsive defect-count controls so labels, steppers, numeric fields, and photo
buttons remain legible in the narrow side-browser viewport. YFBM keeps the YFBM
photo plus average percentage and CV% visible in the panel; empty YFBM metric
cards render as neutral placeholders until rows are entered. The add/delete row
entry list opens from an Enter YFBM Entries bottom sheet with a draggable modal,
compact progress/target summary, and individual card rows for chick weight,
yolk weight, calculated YFBM percentage, and row deletion. The sheet writes the
existing YFBM entries and calculated fields. Chick
Vent Temperature reuses the EST-style guided grid workflow with Front/Middle/
Back by Top/Middle/Bottom points, Guided CVT capture, inline camera/native
camera fallback, auto scan, confirm/edit, retake, skip, clear reading/photo,
missing-photo attach, and saved-photo highlighting. CVT uses a 103-105°F /
39.4-40.6°C target, has an inline °F/°C entry toggle, persists grid readings
and photos locally in `cvtReadingsJson` and `cvtPhotosJson`, and backfills the
panel CVT average/CV summary fields for dashboards. PM Necropsy captures sample
size, collection point, lesion counts with required severity when count is
positive, gasping fields, deformity counts, suspected cause, and PM photos. The
visible lesion list is Omphalitis (Yolk Sacculitis), Gaseous Ceca, Gizzard
Erosions, Air Sac Caseations, Pulmonary Granuloma, Swollen Joints, Stunted
Organs, Nephritis, and General Septicemia. Legacy PM lesion columns remain in
the model and `chick_pm` storage for existing local data, but the active PM UI
writes the revised lesion fields.

The right workbench column contains Chick Weights & Uniformity. Its embedded
blue flock card shows flock, breed, and BMK age inside one compact translucent
context strip and omits the previous `Uniform`/`Review` title pill; edit flows
fall back to the selected flock breed when a Chicks audit row does not carry a
legacy breed field. Sampling scope lives inside this
panel and offers One sample or Multisamples. Weight comparison samples are
house samples: they persist as `chick_weights` rows with `mode = comparison`,
`scopeType = house`, generated `H1`, `H2`, etc. labels by default, and
`groupLabel = House comparison`. If the active house field is edited, the
custom house value is preserved on save and used for the row scope label.
Multisamples mode shows house sample chips plus add/remove controls, while the
active house editor shows only the house field. The panel shows sample count,
BMK chick weight, average weight, low/high margins, uniformity, and CV% in that
order. The weight metrics render as one compact summary list instead of a
nested card grid, and the 100-chick weight entry grid opens from an
egg-weight-style draggable Enter Weights modal sheet and persists each active
house sample's own weights, sample size, average, uniformity, and CV% into its
`chick_weights` row.
Dashboard chick-weight trends do not read those legacy audit fields.

Hatch Analysis & Egg Breakouts is an egg breakout entry screen rather than a
tabbed screen. It uses a centered workbench layout with a compact blue gradient
Breakout Type card, a separate matching blue metadata card, a neutral Breakout
Samples panel, and the existing sticky
station navigation footer when embedded in a visit session. Breakout types are
Fresh Egg, Candled Egg, and Residue / Hatch Day. The Breakout Type card keeps
the selector beside the header title on wider layouts and stacks it vertically
on mobile. The Breakout Type and metadata cards share the same height. The
metadata card shows auto-filled flock, breed, and read-only BMK age as three
equal-width tiles in one row; long flock or breed values wrap inside their own
tile instead of pushing the BMK Age tile to another row. Storage Days is an
entry field in a shorter light-grey entry card with no section heading, defaults
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

Residue / Hatch Day adds batch tabs directly below the Storage Days card and
above Hatch Results. Batch tab labels are generated from the batch setter and
hatcher fields as `S{setter}H{hatcher}`; the label itself is not separately
editable. New hatch-analysis batches default to setter and hatcher numbers
matching the hatch sequence, so the first three new residue batches appear as
`S1H1`, `S2H2`, and `S3H3` until their setter or hatcher number fields change.
Each residue batch keeps its own total eggs set, hatched chicks, culled chicks,
dead chicks, and tray breakout samples. Total eggs set defaults to `19200`.

Residue / Hatch Day shows a Hatch Results card before Breakout Samples for the
active hatch. The card uses a text-only header with the active hatch label,
groups setter, hatcher, eggs set, hatched, culled, and dead inputs under Hatch
totals, and shows Hatchability, Fertility, HOF, Culled %, and Dead % as
one consolidated Performance summary card with ordered rows for the actual
value, benchmark or limit, and benchmark/limit difference labeled as Gap.
Hatchability is `hatched chicks /
total eggs set * 100`. Fertility is the simple unweighted average of the active
batch's valid tray fertility percentages, where each tray fertility is `(tray
sample size - infertile count) / tray sample size * 100`. HOF is `hatchability /
fertility * 100` and is allowed to exceed 100 when hatchability is greater than
measured fertility. Culled and dead percentages use the same total eggs set
denominator. Hatchability, Fertility, and HOF compare with the nearest breed
benchmark for the selected breed and calculated BMK age; warning styling is
shown when those values are below BMK. Culled and Dead compare with fixed limits
of `1.0%` and `0.2%`; warning styling is shown when those values are above the
limit. Residue no longer enforces the old 100-percent hatch-budget
reconciliation.

Breakout Samples sits below the main card, and below the Hatch Results card for
Residue / Hatch Day. It uses tray chips plus circular add and remove controls to
manage tray samples while keeping the tray cards visible in the scroll view. The
tray/pool toggle is not shown in the current UI; legacy pool samples remain
decodable and are converted to tray-style display while preserving their
sampled-egg denominator. Breakout samples are scoped by breakout type in the
shared JSON field: switching Fresh Egg, Candled Egg, and Residue / Hatch Day
hides the other type's entered rows, and returning to a type restores its
previous tray values. When the station saves panel-table rows, Fresh Egg,
Candled Egg, and Residue / Hatch Day rollups use only samples from that active
breakout type, so hidden samples from the other breakout tabs are preserved but
not included in the saved counts, percentages, tray size, or position for the
current table. Each tray card shows label, position when applicable, and tray
size as one balanced row above the breakout item rows, with the position control
given extra width so values such as Random remain readable. New Fresh Egg tray
samples default to 30 eggs; new Candled Egg and Residue / Hatch Day tray samples
default to 150 eggs.
Candled Egg and Residue / Hatch Day tray cards show a position selector;
Fresh Egg tray cards omit position because those eggs are not set in a machine
yet. The position selector uses the same body typography as the label and tray
size fields. Each breakout item row contains a count input, a calculated percentage from
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
  back to the sample sequence when no setter id is available. Setter tabs and
  the Setter type selector are text-only chips without selected checkmarks.
- Setter type, defaulting to Multi, with Single limiting the setter to one EST
  age/breed sample and Multi allowing additional age/breed EST samples.
- Setter number.
- Machine screen setpoint and actual readings in Fahrenheit, with one shared
  documentation photo for the screen that shows both values.
- Batch size, defaulting to 19,200, and batch count, capped at 6. Total set
  eggs is calculated as `batch size * batch count`.
- Turning angle.
- CO2 level and photo, with the camera action aligned beside the entry field.
- Age/breed EST samples. Breed is selected from the six benchmark breeds
  (`Ross308`, `Arbo`, `Avian`, `Cobb500`, `Hubbard`, `IR`), and each sample
  keeps its own incubation age slider from 1 to 18 days, 0-23 hour slider, EST
  readings/photos, average, and CV.
- EST average/CV summary and EST grid/photos.

Setter EST reuses the storage EST guided grid workflow with Front/Middle/Back
by Top/Middle/Bottom points, inline guided OCR capture, inline camera/native
camera fallback, auto scan, confirm/edit, retake, skip, clear reading/photo,
missing-photo attach, saved-photo highlighting, and per-point evidence photo
records. Setters uses Fahrenheit readings with an allowed range of
99.5-102.0°F and an optimum range of 100.0-101.0°F. Those ranges drive the EST
grid status styling and average summary color, but are not rendered as a
separate helper strip in the entry form. Setter comparison samples
persist as `setter_optimizing` rows with `mode = comparison`, generated setter
labels, and `groupLabel = Setter comparison`. Setter and Hatcher station rows
can store machine-specific breed/identity values while the selected flock is
still required to enter the visit flow.
Setters does not expose the generic Sample Mode selector; the dedicated setter
row is the comparison control.

Hatchers captures:

- A dedicated hatcher chip row. The first hatcher uses the selected visit
  hatcher id when present; Add hatcher creates another hatcher in the same audit
  session. Hatcher tabs are labeled from the hatcher number as `H5`, `H7`, etc.,
  and fall back to the sample sequence when no hatcher id is available.
- A Hatcher settings card for the active hatcher sample, containing the hatcher
  number, incubation age slider from 18 to 21 days, and a separate 0-23 hour
  slider.
- CO2 level and photo, with the camera action aligned beside the entry field.
- CVT (Chick Vent Temp.) average/CV summary and guided grid/photos. The grid
  uses the same guided OCR capture, inline/native camera fallback, evidence
  thumbnails, missing-photo attach, and saved-photo highlighting as the setter
  EST/CVT grid flow.
- Chick panting yes/no with photo.
- Meconium assessment: Normal, Dark greenish, Water, or Excessive, with a
  panel photo action for evidence.

Hatchers does not expose the generic Sample Mode selector, a hatcher type
selector, turning-angle fields, or Transfer Day. The dedicated hatcher row is
shown at the top level, above the Hatcher settings card, and is the comparison
control. Hatcher comparison samples persist as machine samples with
`hatcher_optimizing` rows with `mode = comparison`, generated hatcher labels,
and `groupLabel = Hatcher comparison`. Removing hatchers until only one remains
returns the station to pooled mode, clears comparison metadata, and saves the
station-sample hatcher identity from the edited Hatcher number field.

Govee is a standalone daily capture workflow. It is independent from audit
sessions and is keyed by `customerId`, `hatcheryId`, place, nullable machine id,
and calendar `captureDate`. The floating Govee capture panel is
active-recording first and is the only in-app entry surface for new Govee
recordings. Dashboard surfaces still provide the broader visit-level review.

The active Govee recorder opens on a compact ChickMark-blue gradient live card
that mirrors the Govee app's device-first hierarchy while keeping ChickMark
colors. The card shows the device name, connection status, current Temperature
and Relative Humidity, latest update time, RSSI, and battery level directly on
the main card. It exposes a clear `Scan`, `Read`, or reconnect action, a compact
`°F`/`°C` unit toggle backed by the app temperature setting, and a settings icon.
The settings sheet shows current connection details, diagnostics, discovered
Govee devices, scan/restart scan, read-now, select-device, and disconnect
controls.
The old historical browser tabs and export affordance are not part of the active
recording screen. On Flutter Web, Bluetooth initialization is pre-warmed when
the panel opens, but the Web Bluetooth device request is still started directly
from the user's Scan tap so Chrome keeps the permission request attached to the
gesture. On iOS and macOS, Scan uses adapter-state readiness as the preflight
check and avoids the FlutterBluePlus Darwin `isSupported` call that can produce
duplicate native method responses. Native Scan waits briefly for CoreBluetooth
to leave its initial unknown state and avoids duplicate first-start adapter
state reads before scanning. Manual Scan and rescan requests keep discovery open
for 30 seconds before timing out, and timeout diagnostics report the actual
discovery window used for that scan. BLE scan candidates must have a
Govee/H50/GVH name or Govee manufacturer/service identity before H5051-shaped
payload bytes are accepted as live sensor readings, so unrelated nearby BLE
devices with sensor-shaped data are ignored. Govee manufacturer or service
identity is enough to treat a nameless advertisement as a connectable Govee
device even when that advertisement does not yet contain a live reading; the app
then connects over GATT to request current readings and history. The macOS
CocoaPods build stamps the same Bluetooth usage descriptions into the embedded
FlutterBluePlus framework as the main app bundle so macOS TCC does not abort the
app when CoreBluetooth is first initialized.

Each saved place/date capture is one manual place-level Start/Stop window.
Pressing Start recording also attempts to connect the known Govee sensor,
restart discovery, or start a 30-second discovery scan before opening the
recording window when no GATT connection is active. Live readings from the
connected sensor are buffered into the on-screen preview before recording starts,
while active recording keeps a separate live-reading buffer for the recording
window. When the user stops, the provider syncs Govee history for the full
Start/Stop window and treats that history sync as the authoritative saved
dataset when it contains valid readings. If a recent H5051/H5179 history sync
accepts the request but returns no valid stored history for the just-recorded
window, the provider saves only the live readings collected during the active
recording window instead. Stop and save is available while recording,
and the recorder shows the current recording length. Readings with missing
Temp/RH values, impossible temperatures, or RH outside 0-100% are excluded. If
neither history sync nor the active live-reading fallback contains valid
readings, no capture is saved and the recorder returns to idle with a clear
prompt that no
valid readings matched the recording window. The recorder also surfaces
diagnostics with the synced reading count, recording window, synced timestamp
span, and filter counts so long recordings that fail because of timestamp or
value filtering are explainable.

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
recording, syncing, retry, saving, and saved states. Once the sensor has a valid
current Temp/RH reading, the screen renders live Temperature and RH preview
charts even before recording starts. Repeated connected readings form a live
trend before recording; if only one current reading is available, the preview
shows a single current point. During recording, the preview switches to the
accumulated live recording readings. Live preview charts do not allow pan/scale
interaction. Saved captures appear in an expandable card scoped to the selected
customer, hatchery, and capture date; tapping a saved capture selects its saved
chart card without clearing it when a new recording starts. Saved and live
temperature charts follow the shared `°F`/`°C` app setting for labels,
summaries, points, averages, and tooltips while persisted Govee data remains
stored in Fahrenheit. Saved and live chart cards use a Govee-style chart layout:
white rounded chart card, compact centered dark metric title, Max/Avg/Min value
rail, light dashed grid, dashed cyan average line, straight cyan trace with
subtle fill, inside time ticks, and start/end time labels. The plot keeps a
minimum visual Y range, so tiny Temp/RH changes do not fill the full chart
height. Recorded saved charts retain horizontal pan/scale interaction. Chart
touches show the exact timestamp, Temp, RH, place, and machine context when
present.

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
minute followed by 4-byte little-endian Temp/RH records; the packet epoch
minute is the newest slot in the packet and subsequent records count backward
one minute at a time. Epoch-minute requests clamp the stop bound to the latest
completed minute so a stop inside the current open minute does not ask the
device for a bucket it has not stored yet. Completed minute buckets are saved
when their bucket interval overlaps the Start/Stop window, so short recordings
are not clipped before filtering. On these epoch-minute devices, `2012` can
report a single-byte `0x00` acceptance status, `0x03`
progress status, and `0x02` completion status. Older H507-style devices keep the
`0x3301` 20-byte minute-back request with checksum and packed 3-byte records.
The older minute-back request keeps the stop bound at least one minute back
because the current minute may not yet be stored in device history. The service
logs the packet and reading counts used for hardware validation. Live GATT
polling is paused while a history sync is active so `0x0A` preview reads do not
overlap the history transaction. If GATT drops during an active history
transaction while auto-reconnect is available, the service keeps the original
Start/Stop window pending, reconnects, re-enables notifications, and reissues
the history request before surfacing a sync failure. Disconnect errors raised
while setting up history notifications or writing the history request are
treated as the same reconnectable history-sync interruption when auto-reconnect
is active. Before starting history sync, the service waits for any in-flight
GATT connect or service discovery and rediscovers services if the device is
already connected but the `2012`/`2013` history characteristics are not yet
cached.

Saving a capture atomically replaces any existing capture for the same customer,
hatchery, place, machine id, and date. Captures store a derived station key for
station-aware grouping and sync. The old capture remains intact until the new
place-level recording is saved successfully. After saving, the active live
preview is cleared and the screen can suggest the next default place in this
flow: Egg storage room, Chick holding area, Setter room, Inside setter, Hatcher
room, and Inside hatcher.

Audit station screens show a compact text-only `Govee readings` card button for
room-level stations with a mapped place: Egg storage room, Chick holding area,
Setter room, and Hatcher room. Opening from Setters or Hatchers shows a compact
room vs. inside-machine choice before recording. Room environment captures save
without a machine id. Inside-machine captures save the active station machine id
when it is available. Station entries preselect customer, hatchery, and place in the
floating Govee capture panel, while still letting the user change the place
before recording.

Dashboard has a cascade filter for Customer, Flock, and Age. It loads visit
session summaries plus Hatch Analysis & Egg Breakouts, Egg Breakout, Chicks,
Egg, Setters, and Hatchers sections from repository queries. Egg Breakout
dashboard averages and trends ignore invalid category percentages when a
category count is negative or greater than its tray size. Egg Storage dashboard
trends read the persisted `egg_storage.estAvg` and `egg_storage.estCvPct`
fields. Chicks dashboard weight trends read `chick_weights` panel rows and use
their saved weight JSON plus average, CV%, and uniformity summary fields. CV and
stored environmental standard-deviation summaries use sample standard deviation
by default. Uniformity uses the combined daily average +/- 10% range.

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
- Panel tables: one source-of-truth table per station panel. Each row stores
  visit ownership, pool/comparison identity, notes, sync state, and the
  panel-specific measurements or calculated dashboard values. Pool results are
  one row with `mode = pool`; comparison results are multiple rows in the same
  table with `mode = comparison`.
- `govee_daily_captures`: saved Govee place/day captures scoped by customer,
  hatchery, place, machine id, and capture date, with station key, capture
  start/end timestamps, device metadata, aggregate Temp/RH average/min/max/SD/CV
  summaries, representative reading count, and LTTB-selected chart points in
  `chartPointsJson`.
- `photos`: local photo records tied to `sessionId`, `panelName`,
  `panelRowId`, and `fieldKey`, with upload status.
- `bmk_breeds` and `bmk_egg_breakout`: seeded benchmark reference data.
- `troubleshooting`: seeded troubleshooting/reference content.
- `activity_log`: user actions for logins, syncs, session starts/resumes,
  station completion, audit changes, and related events.

Visit session summaries combine one `audit_sessions` row and its panel rows.
Scorecards are parsed from persisted JSON when present; otherwise they are
derived from completion state and simple threshold heuristics. Dashboard Govee
summaries are loaded separately by customer, hatchery, and selected visit date.

### Source of truth rules

Panel tables are the station source of truth. The app no longer creates or
writes the legacy `audits` table, `sample_records`, sample detail tables, or
`{panel}_samples` child tables.

A sample is represented by a row in the relevant panel table. `mode` is only
`pool` or `comparison`; it is never `sample`. Pool rows use `scopeType = pool`,
`scopeLabel = Random`, and `sampleIndex = 0`. Comparison rows use the relevant
scope identity and sequential sample indexes inside the same panel table.

Dashboard values read panel rows directly. Values that the UI calculates during
station save, such as averages, CV%, uniformity, Pasgar final score, breakout
percentages, hatchability, fertility, HOF, EST averages, and CVT averages, are
stored on the corresponding panel row for dashboard queries and sync.

## 6. Models and Provider State

`AuthProvider` manages auth state, Supabase sign-in/sign-up, offline/local login
fallback, cached token checks, pending approval state, and logout. The temporary
auth bypass starts the provider as an approved local auditor in non-release
builds unless the run explicitly sets `CHICKMARK_DEBUG_AUTH_BYPASS=false`.
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
state, invalid-reading filtering, full-dataset Temp/RH summary stats, LTTB
representative readings, replacement save, finished-place preview, and
next-place progression.

`BmkProvider` reads seeded breed and egg-breakout benchmark rows from SQLite,
tracks selected breed, selected ages, and selected egg-breakout type, and
upserts internal BMK admin edits back into the same `bmk_breeds` and
`bmk_egg_breakout` rows used by audit and dashboard benchmark lookups.

`HomeProvider` derives Home KPIs from audit and flock repositories: audits this
month, active flocks, last audit date, recent audits, and audit type breakdown.

## 7. Persistence Summary

The app uses SQLite through `sqflite` at database version 39. The database file
is `hatchaudit.db`. Foreign keys are disabled during create/upgrade callbacks
so the destructive v39 reset can drop legacy foreign-key tables, then enabled
again when the database opens for normal app use. Web startup
initializes the default sqflite factory with `sqflite_common_ffi_web` before the
database opens and uses the browser-safe `hatchaudit.db` name directly instead
of a native database directory. Browser persistence relies on the checked-in
`web/sqlite3.wasm` asset and runs without the shared-worker factory during app
startup.

In non-release builds, startup treats SQLite corruption or not-a-database
errors during database open as a local development recovery case. The app
deletes the local `hatchaudit.db` store and retries opening once so a malformed
browser-backed IndexedDB database does not leave the Flutter app on a blank
screen. Release builds do not auto-delete the database on open errors.

The v39 database cutover is destructive. Upgrading from any older local schema
drops old app tables and recreates the current fresh schema. Old local audit
history is not migrated. When an already-created v39 database opens, the app
checks panel tables against `PanelSampleSchema` and adds any missing
measurement columns, allowing additive panel fields such as revised PM lesions
to appear without another destructive reset.

Tables created by the current database helper include:

- `users`
- `customers`
- `flocks`
- `bmk_breeds`
- `bmk_egg_breakout`
- `troubleshooting`
- `photos`
- `activity_log`
- `hatcheries`
- `audit_sessions`
- `egg_storage`
- `egg_quality`
- `chick_pasgar`
- `chick_weights`
- `chick_yfbm`
- `chick_cvt`
- `chick_pm`
- `fresh_egg_breakout`
- `candled_egg_breakout`
- `residue_breakout`
- `setter_optimizing`
- `hatcher_optimizing`
- `govee_daily_captures`
- `sync_tombstones`

Fresh databases do not create `audits`, `sample_records`, sample detail tables,
`egg_weights`, or `{panel}_samples` child tables.

Every panel table includes visit ownership fields, pool/comparison identity
fields, panel-specific measurement and calculated summary fields, and sync
fields. Each panel table has session, dashboard, mode, and unique-row indexes.
The unique-row index protects `(sessionId, mode, scopeType, scopeLabel,
sampleIndex, IFNULL(groupKey, ''))`.

Relationship safety is enforced in SQLite for the current parent-child graph:
`flocks` and `hatcheries` belong to `customers`; `audit_sessions` belongs to a
customer, flock, and hatchery; panel rows belong to an audit session, customer,
optional flock, and optional hatchery; `photos` belongs to an audit session and
targets a panel row by `panelName`, `panelRowId`, and `fieldKey`; and
`govee_daily_captures` belongs to a customer and hatchery.

Repository upserts avoid SQLite `REPLACE` for parent tables with children.
Customers, flocks, hatcheries, panel rows, and pulled Govee captures use
insert-or-update semantics so saving a parent does not trigger hidden
delete-and-reinsert cascades. Remaining `REPLACE` usage is limited to
childless/local reference rows such as BMK seeds, troubleshooting seeds, photo
rows, activity log rows, users, and sync tombstones.

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
local customers, hatcheries, flocks, audit sessions, panel rows, Govee captures,
photo work, and tombstones in dependency order, then pulls shared data back into
local repositories in the same parent-before-child order. Removed legacy tables
are not pushed or pulled. It keeps newer local session, Govee, and panel rows
when a pulled remote row has an older or invalid `updatedAt`. Local deletes
create `sync_tombstones`; startup sync uploads those tombstones, deletes remote
rows child-before-parent, marks successful tombstones synced, and applies remote
tombstones locally so another device reload removes stale rows. `BgSyncService`
runs this sync after the shell starts and reports failure as offline data
available. The app assumes Supabase tables and storage are protected by project
RLS/storage policies for authenticated users and their customer scope; the
client only ships anon credentials and never needs service-role access. Debug
sync logs are sanitized and do not print stack traces, tokens, row payloads, or
raw BLE bytes.

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

- Several station screens still use legacy-named `AuditModel` fields as
  in-memory form state. Save/load persistence converts those drafts to panel
  rows instead of writing legacy audit tables.
- The legacy single-station flow is still present in code alongside the newer
  visit/session flow.
- `DiagnosticEngine.evaluate` is a placeholder that returns no findings.
- Visit-session scorecards use persisted JSON only when present; otherwise they
  use fallback threshold heuristics in `VisitSessionSummary`.
- The database includes dummy test data seeding in the database helper.
- Supabase sync is best effort and failures are logged/debugged rather than
  surfaced as blocking workflow errors.
- Govee place names still share the `TemperaturePlace` enum while the active
  persistence path is the standalone Govee workflow.

## 9. Change Log

- 2026-05-16: Changed the Egg Upside Down Score header symbol to an inverted egg
  with the pointed end up.
- 2026-05-16: Redesigned the YFBM entries bottom sheet from a hard-bordered
  table into a draggable card-based entry list with compact progress, target,
  average, and CV summary chips.
- 2026-05-16: Kept the Chicks Active machine Setter and Hatcher fields on one
  equal-width row in narrow visit-session layouts.
- 2026-05-16: Reduced the completed/reached visit progress check glyphs so the
  station nodes read lighter inside their existing circles.
- 2026-05-16: Made the New Visit customer picker dismiss when users tap the
  dimmed backdrop outside the bottom sheet.
- 2026-05-16: Changed the New Visit flock summary card from the Material egg
  glyph to a custom chick icon.
- 2026-05-16: Changed the Select Stations Chicks row from the Material
  `cruelty_free` glyph to the shared chick icon.
- 2026-05-16: Extended visit progress strip connector lines so the line reaches
  the adjacent station circles instead of stopping short between steps.
- 2026-05-16: Added a photo action to the Hatcher Meconium Assessment card.
- 2026-05-16: Revised the Chicks PM Necropsy lesion list to use Omphalitis
  (Yolk Sacculitis), Gizzard Erosions, Air Sac Caseations, Nephritis, and
  General Septicemia, and added matching `chick_pm` backend fields with
  on-open column backfill for existing local databases.
- 2026-05-16: Changed the stable web preview shortcut to default to a profile
  web-server build with local Flutter web resources, fixing the black side
  browser preview caused by the debug web-server handshake.
- 2026-05-16: Replaced the shared ChickMark logo asset and platform launcher
  icons with the cheerful chick-over-check mark inside an egg-shaped blue
  outline.
- 2026-05-16: Updated Android and iOS native launcher display metadata from
  Hatchaudit/hatchaudit to ChickMark while leaving internal package and storage
  identifiers unchanged.
- 2026-05-16: Routed audit `Govee readings` actions and the global Govee
  shortcut into the floating Govee capture panel, and removed the separate
  Govee shell tab so new recordings use only the floating panel surface.
- 2026-05-16: Removed unrelated decorative Pasgar symbols from Sample Size,
  Defect Counts, defect rows, and the score card so the Pasgar panel relies on
  text labels plus functional stepper/photo controls.
- 2026-05-16: Added the ChickMark logo mark to the top of Home, wired Recent
  Audits and active-home counts to `audit_sessions`, and removed the Home Audit
  Type Breakdown/stat/action sector.
- 2026-05-16: Made Home Today's Focus metric cards actionable: Continue opens
  the first active visit, Attention opens the first setup/action item, and Ready
  starts a new audit when a ready customer setup exists.
- 2026-05-16: Calmed the shared app typography by lowering the global heading,
  section-title, title, body, badge, metric, app-bar, pending-approval, and
  major station hero text sizes while leaving dedicated numeric capture displays
  large enough for data entry.
- 2026-05-16: Made Govee Start recording trigger the same scan/reconnect path as
  the manual Scan action when the device is not already GATT connected.
- 2026-05-16: Seeded fresh Egg Shell Quality and Upside Down Score tray sections
  with a default Tray 1 editor before their add-tray action.
- 2026-05-16: Compact Govee live cards now show RSSI, battery, unit switching,
  and a settings sheet for connection details, available devices, read/scan,
  select-device, and disconnect controls; same-day saved captures moved from the
  sticky bottom strip into an expandable card.
- 2026-05-16: Live Govee preview charts now appear as soon as a connected sensor
  has a valid current Temp/RH reading, before recording starts.
- 2026-05-16: Live Govee preview charts now keep a capped connected-reading
  buffer before recording so repeated sensor reads form a trend, while active
  recording still uses a separate windowed buffer for save fallback data.
- 2026-05-16: Live and saved Govee temperature charts now follow the app
  `°F`/`°C` setting for plotted values, rail labels, summaries, and tooltips.
- 2026-05-16: Calmed live and saved Govee Temperature/RH charts for narrow
  variation by enforcing a minimum visual Y range, drawing straight trace
  segments to avoid spline loops, and reducing chart typography for mobile.
- 2026-05-16: Consolidated Egg station quality persistence so Egg weights,
  uniformity, shell UV quality, and notes save into `egg_quality`, removed the
  active `egg_weights` panel table, and moved upside-down score persistence onto
  `egg_storage`.
- 2026-05-16: Prefixed Egg shell UV database columns in `egg_quality` with
  `uv` (`uvTrayEggCount`, `uvAffectedPct`, etc.) to avoid name collisions with
  similar panel metrics.
- 2026-05-16: Prefixed Egg weight and uniformity database columns in
  `egg_quality` with `egg` (`eggWeightsJson`, `eggAvgWeight`,
  `eggUniformityPct`, etc.) so they stay distinct from Chick weight panel
  columns.
- 2026-05-16: Removed Chicks optional panel result pills from Pasgar, YFBM,
  Chick Vent Temperature, and PM Necropsy headers so those rows show only the
  panel title and expand chevron.
- 2026-05-16: Removed the `Uniform`/`Review` result pill from the Chick Weights
  & Uniformity hero card title row.
- 2026-05-16: Restyled the Egg Weights & Uniformity summary to match the Chicks
  weight card row design and metric order, removing the old two-column metric
  tile grid and moving BMK Age out of the weights summary.
- 2026-05-16: Replaced the Egg Sampling scope default segmented button with a
  compact text-only custom pill using a neutral track and subtle selected chip.
- 2026-05-16: Added regression coverage that Egg Weights & Uniformity, Egg
  Shell Quality, and Notes do not render `EW`, `UV`, or `NT` workbench mark
  badges.
- 2026-05-16: Removed the Egg Weights & Uniformity and Egg Shell Quality header
  status pills, including `0/100` and `Avg affected 0.0%`.
- 2026-05-16: Replaced the Chicks Quality sampling and House scope segmented
  buttons with text-only custom pills, removing the selected check and gradient
  segment icons.
- 2026-05-16: Removed the leading thermometer icon from the station-level
  `Govee readings` card and removed compact PG/YF/CVT/PM mark badges from
  Chicks optional panel headers.
- 2026-05-16: Removed Egg station hero icons, shortened the visit progress
  label for Hatch Analysis to one line, changed Hatch Results subtitles/groups
  from Batch to Hatch wording, made Setters chips text-only, aligned the CO2
  camera with its field, removed the Setters EST range helper strip, and
  changed Chicks weight metrics to a compact summary list.
- 2026-05-15: Cut persistence over to panel-only storage. Fresh v36 databases
  no longer create `audits`, `sample_records`, sample detail tables, or
  `{panel}_samples` child tables. Station saves, dashboard reads, Supabase
  sync, tombstones, and photo identity now use `audit_sessions` plus panel
  rows.
- 2026-05-15: Added an end-to-end panel smoke test for the full audit workflow:
  customer/flock/hatchery/session creation, all five stations, save/reopen/edit
  persistence, pool and comparison row behavior, legacy-table absence, and
  dashboard loading from panel tables. Reopened panel saves now update by panel
  row identity when the in-memory draft ID differs, and filtered Egg dashboard
  queries qualify their panel-table aliases.
- 2026-05-15: Restyled live and saved Govee Temperature/RH charts back to a
  light Govee-original-style card with dark titles, light dashed grid lines,
  inside time ticks, cyan traces, and no visible zoom controls below the chart.
- 2026-05-16: Removed the decorative `EST`, `UD`, and `CHK` mark badges and the
  right-side status pills from the EST, Upside Down, and Storage Checklist Egg
  workbench headers.
- 2026-05-15: Allowed Scan to connect to nameless Govee advertisements that
  expose Govee manufacturer or service identity even before live Temp/RH bytes
  are present, while keeping non-Govee sensor-shaped advertisements ignored.
- 2026-05-15: Renamed the Egg Shell Temperature target summary labels to
  Storage duration and EST target, kept Egg quality flock/breed/BMK Age tiles in
  one equal-width row, and refined the Sampling scope choices.
- 2026-05-15: Made Egg EST, Upside Down, Storage Checklist, Egg Weights &
  uniformity, and Egg Shell Quality into expandable cards, removed their helper
  phrases, and renamed the house-sample weights area to Egg Weights & Uniformity.
- 2026-05-15: Kept Hatch Analysis & Egg Breakouts metadata in one equal-width
  row so long flock or breed names wrap inside their tile instead of moving BMK
  Age to a second row.
- 2026-05-15: Equalized the Hatch Analysis Breakout Type and metadata card
  heights, restyled the Storage Days card as a shorter teal-blue card without an
  Entry Fields heading, renamed Batch Results to Hatch Results, removed the
  redundant tray-card title, and aligned tray label/position/size fields in one
  equal-width row.
- 2026-05-16: Changed the Hatch Analysis Storage Days entry card from the
  teal-blue treatment to a light-grey surface with a white input tile and dark
  field text.
- 2026-05-16: Removed the leading analytics icon from the Residue / Hatch Day
  Hatch Results card header.
- 2026-05-15: Moved Storage Days out of the expandable Egg Shell Temperature
  card so it appears immediately before that card.
- 2026-05-15: Hid the app-wide floating Govee shortcut while modal sheets are
  open, preventing it from covering Egg station entry sheets such as egg-weight
  capture.
- 2026-05-15: Fixed Chicks station panel persistence so Pasgar, YFBM, CVT, and
  PM save only to setter/hatcher quality rows, while Chick Weights saves only to
  house-scoped `chick_weights` rows using each house sample's own weights,
  sample size, average, uniformity, CV%, and custom house label.
- 2026-05-15: Fixed Hatcher add/remove sample persistence so removing back to a
  single hatcher saves pooled `hatcher_optimizing` rows and clears comparison
  group metadata while preserving the edited hatcher number in sample metadata.
- 2026-05-14: Simplified the Egg station cards by reducing the Egg storage hero
  to the room name plus hatchery, converting Egg quality to a matching gradient
  hero with flock/breed/BMK age, renaming sample modes to One sample/Multiple
  samples, and removing helper explanations from the selected Egg panels.
- 2026-05-14: Extended manual Govee Scan/rescan discovery from 8 seconds to 30
  seconds and made discovery-timeout diagnostics report the actual scan window.
- 2026-05-14: Tightened Govee BLE device detection so raw H5051-shaped
  advertisement bytes are accepted only from devices with Govee/H50/GVH naming
  or Govee manufacturer/service identity, preventing unrelated nearby BLE
  devices from appearing as connected sensors.
- 2026-05-14: Restyled live and saved Govee Temperature/RH charts to use a
  dark Govee-app-style card with centered white titles, cyan traces, dashed grid
  and average line, filled chart area, endpoint labels, and zoom controls.
- 2026-05-14: Made the app-wide floating Govee shortcut draggable and
  side-tuckable so it can be moved out of the way or hidden partly off the left
  or right edge while remaining tappable.
- 2026-05-14: Removed the large green completion check overlay from
  intermediate station saves; it now appears only when the final selected station
  completes the visit.
- 2026-05-14: Added setter-style Hatcher comparison controls with Add/remove
  hatcher chips, generated H-labels, hatcher comparison sample metadata, and no
  generic Sample Mode, hatcher type, or turning-angle controls.
- 2026-05-14: Moved Hatchers incubation age/hour controls into a CVT sample
  card, reused the setter-style guided OCR sample grid for Chick Vent Temp.,
  removed Transfer Day from the Hatcher screen, and changed Meconium options to
  Normal, Dark greenish, Water, and Excessive.
- 2026-05-14: Added the v35 additive Setter machine-field migration for screen
  readings, machine-screen photo evidence, batch totals, and nested age/breed EST
  sample JSON without clearing existing audit data, and removed flock-derived
  breed identity from Setter/Hatcher machine station rows/screens. This
  pre-cutover dual-write path was superseded by the v36 panel-only schema.
- 2026-05-14: Restored Govee Start/Stop saving without a warmup discard window,
  showed the current recording length while recording, restored live preview
  charts from current readings, saved active live readings when recent H5051
  history returns an empty stored window, and made missing H5051 history
  characteristics fail into the retryable sync path instead of returning an
  empty saved dataset.
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
- 2026-05-13: Defined earlier dashboard/source-of-truth rules for the
  transition-era dual-write schema. This was superseded by the v36 panel-only
  schema, where dashboard queries read panel tables directly.
- 2026-05-13: Lifted the floating Govee shortcut from `MainShell` to the app
  Navigator overlay so it remains available on pushed audit station screens
  while continuing to open the standalone Govee workflow.
- 2026-05-13: Added an active-recording visual state to the floating Govee
  shortcut: the launcher changes from the idle blue circle to a red rounded
  stop-style button while Govee capture is recording.
- 2026-05-13: Fixed the Govee no-valid-readings recovery path so an empty sync
  returns the recorder to idle instead of leaving Stop/save active, and added
  diagnostics for long recordings whose synced readings land outside the valid
  recording window.
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
- 2026-05-14: Fixed H5051/H5179 epoch-minute history requests to avoid the
  still-open current minute, preserve completed minute-bucket boundaries for
  filtering, and pin packet parsing to the observed reverse-minute packet
  layout from captured device traffic.
- 2026-05-14: Hardened Govee history sync retry so a disconnect during `2012` or
  `2013` history notification setup waits for reconnect and reissues the
  original Start/Stop history request instead of failing the recorder
  immediately.
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
