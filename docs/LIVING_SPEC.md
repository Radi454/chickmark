# Living Spec — Current Implemented Behavior

This file documents behavior mapped from the current Flutter codebase. The
current Flutter codebase remains the primary source of truth. If this document
and code conflict, inspect the code and report the mismatch.

This file must be updated after every meaningful code change.

## 1. Last Updated

2026-05-26

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
The shared in-app ChickMark logo asset uses the cap-and-glasses
chick-and-check mark identity with a transparent background for app-bar and auth
placements. Platform launcher icons use the same chick-and-check mark brand
family. Large auth and startup placements can opt into a subtle bob-and-glint
logo animation while compact navigation marks remain static.
The app uses a compact operational type scale: shared headings, section titles,
body copy, badges, app bars, and major station hero titles are intentionally
smaller than the previous large display scale so dense audit screens stay
scannable on phone-width layouts.
Shared card surfaces use a restrained operational style with tighter corner
radii, soft low-contrast shadows, and subtle default borders. Section cards may
show small leading Material symbols in blue-tinted icon containers, and the
Customers, Settings, and BMK reference surfaces use those simple symbols instead
of decorative or emoji-led labeling.
The add/edit flock bottom sheet uses compact input fields, local pill selectors
for age source and availability, and quiet helper text while preserving the
existing flock ID, breed, estimated age, depletion age, and active/sold save
behavior.
User-facing date labels use left-to-right `dd-MM-yyyy` formatting across Home,
Audits, Customers, Activity Log, Dashboard Govee charts, and active Govee
capture surfaces. Internal persistence keys and repository filters that depend
on ISO date strings continue to store and compare `yyyy-MM-dd`.

The BMK reference tab presents benchmark data as compact dashboard sections.
Approved internal users see a small Reference/Admin mode toolbar above the
content. The Reference view uses custom selector bars for breed and a text-only
Fresh/Candled/Residue breakout type selector, labeled age dropdown controls, and
responsive metric tiles. Phone-width layouts keep selector pills and benchmark
values dense: breeds render three across when width allows, the breakout type
selector stays one row, and sector metrics render two columns so Breed
Benchmarks and Egg Breakout BMK read as two compact sectors rather than long
single-item stacks. BMK metric tiles are text-only value cards and do not show
per-metric decorative symbols; the Egg Breakout BMK sector header uses the
standard egg symbol.

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

The station-selection screen resets its Start Visit loading state after the
pushed visit-session route has yielded a frame, so backing out from an audit
station leaves the selected visit order editable and the Start Visit button
usable without mutating the shell layout during the route-pop frame.
When the same customer, flock, hatchery, and visit date already has an
in-progress session, station selection resumes that session instead of creating
a duplicate. Saved stations stay in the visit-order list with a visible `Saved`
badge, can be removed from the resumed visit order, and can be tapped outside
the removal button to open that station for review/edit. Unsaved remaining
stations can still be added before continuing the resumed visit.

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
- Start Visit creates an `audit_sessions` row with status `in_progress`, or
  resumes the matching same-context in-progress session when one already
  exists.

Supported station keys are:

- `egg`
- `chicks`
- `hatch_analysis_egg_breakouts`
- `setters`
- `hatchers`

`AuditSessionScreen` renders the selected stations in one visit workflow. It
shows a progress indicator, keeps one `AuditProvider` per station, and shows one
station at a time. Completed or reached past station nodes use compact check
marks inside green progress circles, while the current station uses a blue circle
with a small white dot marker so it is visually distinct from completed
stations. Moving forward, moving back, switching to an earlier or completed
station, leaving the visit, or saving the final station all go through a
station-exit confirmation path that attempts to save the current station.
When a visit is resumed or a previously saved station is opened inside the
session, the station frame hydrates the station from panel rows for that
session. It synthesizes the current form draft objects from those panel rows so
the existing screens can render and resave in place without using legacy audit
or sample tables. All selected station screens, including Hatch Analysis & Egg
Breakouts, show the standard session progress strip above the station content.
Completed visit sessions also open through `AuditSessionScreen` first, starting
at the first station so the saved station fields can be reviewed and edited in
place. Completed-session app bars show a `View final results` dashboard action
that opens the final visit results view separately.

Station save behavior:

- Station value changes schedule a quiet local draft autosave after the user
  pauses briefly. Draft autosave writes panel rows only; it does not write
  activity-log entries, trigger threshold notifications, or start legacy audit
  sync.
- Hatch Analysis & Egg Breakouts saves all samples and marks all tab indices saved.
- Other stations save through `AuditProvider.saveSamplesWithResult(tabIndex: 0)`.
- Saving persists directly into panel tables. Each saved leaf sample is one row
  in the affected panel table. The row identity is the session plus that
  table's explicit nullable hierarchy columns. Egg, chick, and breakout panels
  can use `house`, `setter`, `hatcher`, `trolley`, `tray`, and `position`;
  Setter optimizing starts at `setter` and can nest `trolley` then `tray`;
  Hatcher optimizing starts at `hatcher` and can nest `trolley` then `tray`.
- Scope hierarchy is nested from broadest to narrowest inside the sampling
  sector: `house` where the panel supports it, then machine (`setter`/`hatcher`
  pair or the station's single machine id), then `trolley`, then `tray`. Visit
  ownership fields such as `customerId`, `hatcheryId`, `flockId`, `breed`, and
  date remain row context for filtering and session ownership, but they are not
  Setter/Hatcher sampling scopes. If a sector has no added scope, it saves one
  station-scoped row with all hierarchy columns null. If a sector is scoped to a
  deeper layer, each saved row carries every populated parent scope. For example,
  two houses with two machines per house, two trolleys per machine, and two
  trays per trolley save sixteen tray rows.
- One-sample rows leave unused hierarchy columns null. Multi-sample rows repeat
  the shared parent context and differ at the selected leaf scope, while keeping
  parent columns populated for comparison and dashboard grouping.
- Current saves write Egg panels (`egg_storage`, `egg_quality`), Chicks
  panels (`chick_quality`, `chick_weights`), the selected breakout panel,
  Setter optimizing, or Hatcher optimizing.
- Storage-capable stations default blank storage-day values to `0` in drafts
  and station-sample metadata so BMK age calculations can run even when the
  user leaves the storage field untouched.
- Egg panel persistence skips `egg_storage` and `egg_quality` rows when their
  corresponding fields are untouched or blank. If a save finds no meaningful
  values for an Egg panel, it removes any existing rows for that session instead
  of writing metadata-only rows populated only by default zeroes or auto-derived
  BMK age/weight values.
- Egg storage upside-down tray totals can save `egg_storage` without creating
  `egg_quality`. `egg_quality` UV rows require a quality-side signal: an edited
  UV tray, a quality defect count, UV evidence photo, egg-weight values, or
  quality notes. Quality Storage Days and auto BMK age/weight values persist as
  context only when a quality row has another quality-side signal.
- Save/Next remains the station-exit path. It retries any pending or failed
  autosave work, persists meaningful panel rows, removes blank/default-only
  rows, validates the station core requirement, and then allows navigation.
  Incomplete stations prompt before navigation; when confirmed, the station can
  be skipped without adding it to `stationsCompleted`.
- Each station footer includes a `Clear` action. After a short confirmation, it
  removes the current station's local panel rows for the active visit session,
  resets the visible station fields and added scopes/samples to the blank
  single-sample state, and removes that station from `stationsCompleted`.
- Re-saving a station in an already completed visit persists the edited station
  fields and keeps the visit marked completed only while that station still
  satisfies its core completion rule. If review edits remove core data, the
  station is removed from `stationsCompleted` and the visit returns to
  `in_progress` until all selected stations are complete again.
- Final station saves report local panel persistence independently from
  activity-log or threshold-notification side-effect failures. Those failures
  are debug-logged and do not mark the locally saved station data as failed.
- Autosave and explicit save requests share in-flight save work so repeated
  taps or rapid field edits do not create duplicate station rows. If an autosave
  fails, the station remains dirty and the final Save/Next path retries before
  navigation.
- Panel rows keep `hatcheryId` only when the referenced hatchery exists locally.
  Older or repaired visit sessions that still point at a missing hatchery record
  can autosave their station panel data by omitting the nullable panel
  `hatcheryId`; the setup attention item remains responsible for surfacing the
  missing hatchery record.
- Reopened panel-row drafts may use synthetic in-memory IDs, but panel saves
  resolve conflicts by the panel row identity (`sessionId`, `house`, `setter`,
  `hatcher`, `trolley`, `tray`, and `position`) so reopened edits update the
  existing panel row instead of writing legacy audit/sample tables.
- If an existing scoped sample row is later saved with the same hierarchy as an
  existing pooled or differently scoped row, panel persistence merges the save
  into the existing hierarchy row and tombstones the stale row id instead of
  attempting an `id` update that would violate the unique hierarchy index.
- After current scoped rows save, the provider prunes stale hierarchy rows for
  the same session/table when their row id or explicit hierarchy no longer
  matches the active sample set. Removing a House or Machine scope chip, or
  returning a comparison station to pooled mode, deletes the obsolete local panel
  rows and queues sync tombstones instead of leaving hidden dashboard rows in
  the database.
- Removed scope sample row ids are tombstoned before panel rows are re-saved, so
  a retained scope that shifts into the removed scope's hierarchy label cannot
  inherit the deleted row's saved identity.
- Completing a station updates `audit_sessions.stationsCompleted` only when the
  saved station validates as complete. A station with saved but incomplete data,
  or with only blank/default data that was discarded during save, can be left
  and revisited later but does not receive a green completion check.
- Completing the final selected station updates the session to `completed` and
  returns to the main shell.

The legacy single-station flow still exists in code when `AuditContextScreen` is
constructed with an explicit `auditType`. It collects customer/flock context and,
for Setter or Hatchers, requires the relevant machine id before
opening a single station screen with a fresh `AuditProvider`.

The Audits tab lists recent visit sessions. In-progress sessions open the
station-selection continuation screen so saved stations are visible and unsaved
stations can still be added. Completed sessions open the station workflow first
for review/edit, with final results available from the station screen dashboard
action. Legacy single-audit edit paths remain as compatibility UI code, but the
current list and save/load workflow are session and panel based.

Home shows the ChickMark icon mark before the `ChickMark` title in the main
gradient app bar, then starts the page body with a mobile-friendly KPI strip for
monthly visit counts, active flocks, and last audit date before active local
visit sessions, recent visit sessions, setup attention items, quick shortcuts,
and sync status. The active flocks KPI uses a paired hen/rooster glyph rather
than an egg-only icon. Counts and Recent Audits are based on `audit_sessions`
rather than legacy audit rows. Today's Focus metric cards are actionable when
they have a target: Continue opens the first active visit's station-selection
continuation screen, Attention opens the first setup/action item, and Ready
starts a new audit when a ready customer setup exists. Active and recent visit
cards show station completion progress such as `3/5`. The previous Audit Type
Breakdown, extra
Customers/Active Audits/Total Audits stat cards, and duplicate New Customer/New
Audit action row are not shown on Home. Home section headings and quick actions
use a restrained operational scale so narrow browser previews do not read like
oversized stacked display cards.

## 4. Station Screens

All station screens initialize an `AuditProvider` with `AuditContext`, hide
their own app bar when embedded in `AuditSessionScreen`, and use read-only mode
for existing audits unless edit mode is enabled by an allowed user. Visit
sessions use a default-height gradient station app bar and a compact raised
bottom navigation bar with the primary Next Station/Save action. Visit station
screens also show a white compact stepper strip with short wrapping station
labels and a small white dot marker on the active blue station circle; Hatch Analysis &
Egg Breakouts uses the same strip above its Hatching & Breakout card. Visit
sessions mount only the current station at first, then
keep previously opened stations mounted, so hidden future
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
  Egg Storage panel persistence is EST-gated: Storage Days, upside-down counts,
  checklist fields, and notes can accompany the storage row, but they do not
  create an `egg_storage` row until EST data is entered.
- Egg Shell Quality: expandable UV tray inspection with up to 10 UV tray entries
  and a top UV Summary card showing Cuticle Damage %, Washed %, Dirty %, and
  total Affected %. Fresh or empty tray data shows a default Tray 1 editor
  before the add-tray action. Shell UV summary fields persist on the
  consolidated `egg_quality` row, including dashboard-ready per-type percentage
  columns (`uvCuticleDamagePct`, `uvWashedPct`, and `uvDirtyPct`) alongside the
  total affected percentage.
- Upside Down Score: tray entries and overall upside-down average. Fresh or
  empty tray data shows a default Tray 1 editor before the add-tray action.
  Its header uses an inverted egg symbol with the pointed end up. Upside-down
  score fields persist on the `egg_storage` row alongside the storage-side Egg
  cards.
- Egg Quality Assessment: shows a blue brand-gradient Egg quality card with
  white foreground styling for flock, breed, and BMK age in one equal-width row,
  a dedicated Quality Storage Days entry used for Egg Quality BMK age and BMK
  egg-weight lookup. Egg Quality no longer shows the old One sample / Multiple
  samples selector; it uses a single House scope card instead. House scope shows
  `Pool` while inactive. Pressing the House scope add control turns the pooled
  Egg Quality sample into a single House placeholder chip (`H`) with a blank
  House field until the user enters the house value. Egg Quality scope rows do
  not receive serial defaults: converted and newly added House scope rows start
  as `H`, with the identity input shown blank. Edited values update the active
  chip label, such as `H2`, and the saved Egg Quality hierarchy identity. House
  identity input keeps its active editing focus while provider state refreshes
  and syncs provider-side identity changes back into the field when the user is
  not actively editing that field. Removing a House scope removes that house and
  returns Egg Quality to the pooled state when no scoped houses remain.
  The expandable Egg Weights &
  Uniformity card contains an ordered row-style weight metric summary and the
  100-egg weight sheet. The metric summary follows
  the Chicks weight card order: Sample Size, BMK Egg Weight, Avg Weight, Low
  Margin, High Margin, Uniformity, and C.V. BMK Age stays in the Egg quality
  context card instead of the weights summary.
  BMK age is derived from the flock entry date when available, falls back to the
  saved flock age from the visit/session record, and subtracts the Egg Quality
  storage period rather than the Egg Storage room period. The default Quality
  Storage Days value runs the same BMK egg-weight lookup on screen load, so the
  BMK Egg Weight row is populated before the user edits storage days or enters
  weights. Egg storage-room fields, Quality Storage Days, BMK age, and BMK egg
  weight are shared across all Egg Quality House scope samples, so
  switching from `H` to `H2` does not require re-entering
  storage metadata and does not blank BMK values. Per-scope Egg Quality
  measurements such as weights remain
  independent. Egg Quality panel persistence requires either Egg Weights &
  Uniformity data or Egg Shell Quality UV data; Quality Storage Days, BMK
  values, and notes alone do not create an `egg_quality` row. The station
  removes helper explanations from the EST, Upside
  Down, Storage Checklist, Egg quality hero, Egg scope card, Egg Weights &
  Uniformity card, Egg Shell Quality card, and Notes panel so only the
  operational labels remain. Egg workbench headers
  omit decorative mark badges such as `EST`, `EW`, `UV`, and `NT`, and omit
  header status pills such as `0/100` and `Avg affected 0.0%`. Expandable
  headers keep the title icon, title, and chevron as the only header controls.
  Egg Quality house comparison persists each house as a comparison row with
  the entered house identity. A new House placeholder remains a prefix-only `H`
  sample until the user enters the value that produces the final label, such as
  `H2`. Egg Storage remains a station-level
  pooled row with null sample hierarchy columns (`house`, `setter`, `hatcher`,
  `trolley`, `tray`, and `position`) even when Egg Quality has an active House
  scope. When a saved Egg station is resumed, the screen rebuilds Egg
  Quality scope chips from `egg_quality` hierarchy rows instead of the pooled
  `egg_storage` row, while still merging pooled Egg Storage fields into each
  active Egg Quality draft. Removing an Egg Quality scope sample deletes its stale
  `egg_quality` hierarchy row on the next save. Egg storage-period fields,
  EST/storage handling fields, Egg Quality storage period, and Egg Quality BMK
  age/weight are shared across all active Egg Quality house samples,
  so switching scope chips never requires re-entering storage data or re-running
  the BMK lookup. The
  100-egg sheet uses a compact, responsive numeric grid with single rounded
  number-only input fields. Egg weights, sample size, average weight,
  uniformity, CV%, Egg Quality storage period, and BMK egg-weight fields persist
  on the consolidated `egg_quality` row instead of a separate Egg weights table.
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
Chick Vent Temperature, PM Necropsy, and Culled Chicks Analysis panels so each
optional chick-quality test can be opened only when needed. These optional
panel headers omit compact mark badges and result pills such as Pasgar score,
YFBM status, CVT status, or PM review state; the full panel title and chevron
are the only header controls.
The quality sampling control is a single `Machine scope` card matching the Egg
quality machine-scope pattern. In pooled state it shows a disabled `Pool` chip
and an add control; there is no separate One sample / Multisamples segmented
control and no separate Machine ID card. Pressing the add control switches
Chick Quality to a single active `SH` placeholder on first activation;
subsequent adds create additional `SH` placeholders until the user enters
Setter/Hatcher values. The active sample can then be switched or removed from
the same card; removing the only active machine sample returns the card to
`Pool` and hides the Setter/Hatcher entry fields. Active comparison mode shows
the same blank Setter and Hatcher entry fields used by Egg quality machine scope.
Chick Quality machine
scope does not expose a House entry, and saved `chick_quality` rows keep house
hierarchy columns empty while using setter/hatcher as the explicit leaf scope.
Entered setter/hatcher values update the active chip label and the saved
`chick_quality` setter/hatcher hierarchy identity.
Optional chick-quality tests follow the selected quality sample scope: pooled
mode has no per-card sample subtitle and saves one pooled sample row for Pasgar,
YFBM, Chick Vent Temperature, and PM Necropsy, while machine scope shows the
active setter/hatcher label, such as `SH setter/hatcher sample`, and saves one
`chick_quality` follower row per setter/hatcher sample. Chicks quality machine
rows use the explicit `setter` and `hatcher` hierarchy columns, with generated
setter/hatcher values stored on the normalized sample and panel sample rows.
The consolidated `chick_quality` row stores prefixed Pasgar, YFBM, CVT, and PM
Necropsy fields so optional quality sections share the same sample identity
without colliding with weight fields.
Pasgar captures sample size, six tracked defect
counts/photos, and the final score. The final score uses the first five scored
defect categories; feather development remains a tracked/displayed category but
does not reduce the score. Defect percentages are treated as invalid when a
defect count is negative or greater than the Pasgar sample size. Its embedded
layout uses one light form block instead of nested card surfaces: the sample
size appears as a compact row, defect counts share one divided list, and the
score appears as a slim green summary row. It omits the redundant Sample Size
and Defect Counts card headings, and uses responsive defect-count controls so
labels, steppers, numeric fields, and photo buttons remain legible in the narrow
side-browser viewport.
At normal station panel widths, embedded Pasgar defect rows keep operational
16-17px labels and small count/photo controls instead of reusing the full-page
audit scale. YFBM
keeps the YFBM photo plus rows complete, average percentage, CV%, and target
range visible in the main panel; empty YFBM metric cards render as neutral
placeholders until rows are entered. The add/delete row entry list opens from
an Enter YFBM Entries bottom sheet with a draggable, simple data-entry form for
chick weight, yolk weight, and row deletion. The sheet writes the existing YFBM
entries and calculated fields. Chick
Vent Temperature reuses the EST-style guided grid workflow with Front/Middle/
Back by Top/Middle/Bottom points, Guided CVT capture, inline camera/native
camera fallback, auto scan, confirm/edit, retake, skip, clear reading/photo,
missing-photo attach, and saved-photo highlighting. CVT uses a 103-105°F /
39.4-40.6°C target, enters grid readings in °F, persists readings and photos
locally in `cvtReadingsJson` and `cvtPhotosJson`, and backfills the panel CVT
average/CV summary fields for dashboards. PM Necropsy captures sample
size, collection point, lesion counts with required severity when count is
positive, custom other lesion rows, suspected cause, and PM photos. The visible
lesion list is Omphalitis, Gaseous Ceca,
Air Sac Caseations, Urolithiasis (Urate Deposits), Nephritis, General
Septicemia, and Gizzard Erosions. PM also shows an Others row whose lesion name
is editable and can be expanded with additional custom lesion rows for unlisted
findings. Custom lesion rows persist as `pmOtherLesionsJson`; fixed PM storage
lives on the active `chick_quality` row using `pm*`-prefixed backend fields.
Fresh `chick_quality` tables and current save maps omit deleted legacy PM
lesions such as unabsorbed yolk, perihepatitis, pericarditis, airsac acute/
chronic, pulmonary granuloma, swollen joints, stunted organs, and pulmonary
hemorrhage; existing local databases may still carry those columns as legacy
compatibility data.
Culled Chicks Analysis appears immediately after the PM Necropsy panel and
follows the same active quality sample scope. It records total egg set
(defaulting new entries to 19,200) as the denominator for defect rates, with
operator-entered defect counts grouped by Navel, Belly, Sticky, Dehydrated,
Legs, Head, Neuro, Small/Weak, and Hair Chick. Belly appears as a
standalone group immediately after Navel and contains the residual yolk / large
abdomen item. Dehydrated appears as a standalone group after Sticky and contains
Dehydrated / burned chick. Active entry rows show the defect subtype and a
compact Count stepper with minus/plus buttons around the editable count field,
plus the calculated percentage of total egg set for non-zero rows;
hatchery-guide descriptions, likely causes, and source labels remain in the
defect catalogue for Dashboard interpretation rather than cluttering the station
counting workflow. The active `chick_quality` row stores `culledChicksTotalEggSet`
and encoded defect percentage JSON; defect row counts are not persisted. Derived
dashboard fields store total affected percentage, top category, and top subtype.

The right workbench column contains Chick Weights & Uniformity. Its embedded
blue flock card shows flock, breed, and BMK age inside one compact translucent
context strip and omits the previous `Uniform`/`Review` title pill; edit flows
fall back to the selected flock breed when a Chicks audit row does not carry a
legacy breed field. Chick Weights uses an Egg-quality-style House scope card
instead of a One house / Compare houses selector or separate Active house
editor. In pooled state the card shows `Pool` plus an add control. Pressing the
add control switches Chick Weights to the Egg-style house scope flow: the
first activation becomes a single active `H` placeholder, and subsequent adds
create additional `H` placeholders until the user enters House values. The House
entry field is blank for the active placeholder. Entered house values update the
active chip label and persist to `chick_weights` rows through the explicit house
hierarchy columns; removing a house sample deletes its stale `chick_weights` row
on the next save, and removing the only active `H` sample returns Chick Weights
to pooled `Pool` state. The panel shows sample count, BMK chick weight, average
weight, low/high margins,
uniformity, and CV% in that order. The weight metrics
render as one compact summary list instead of a nested card grid, and the
100-chick weight entry grid opens from an
egg-weight-style draggable Enter Weights modal sheet and persists each active
house sample's own weights, sample size, average, uniformity, and CV% into its
`chick_weights` row. Weight entry changes are staged briefly while the user is
typing and then committed after a short debounce, or immediately when the sheet
closes, so the full Chicks station does not rebuild on every keypad tap. New or
blank comparison-house samples do not inherit the previous active house's
weight grid or calculated metrics.
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
to `0`, treats blank or older missing values as `0`, and clears its default zero
on focus for faster replacement;
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

Candled Egg and Residue / Hatch Day add hierarchy controls directly below the
Storage Days card. The controls use the same scope-card treatment as Egg and
Chicks screens: a `House scope` card contains the house tabs and active House
field, and a `Machine scope` card contains setter/hatcher machine tabs for the
selected house plus the active Setter and Hatcher fields. Both cards show a
disabled selected `Pool` chip while their scope has not been activated. Pressing
House scope `+` turns the pooled hatch row into the first house scope, shows a
blank House field, and labels the first chip as prefix-only `H` until a house
number is entered. Entered values update the chip to compact labels such as
`H1` and `H2`. The House scope remove action is available as soon as House
scope is active; removing the only active house returns the Hatch Analysis
hierarchy to pooled mode. Pressing Machine scope `+` creates the first
setter/hatcher machine row without creating a synthetic House scope. If House
scope is still pooled, the House card remains `Pool`; if a House scope is
active, the machine row inherits that active house. Machine rows show blank
Setter and Hatcher fields and label the chip as prefix-only `SH` until either
number field is entered. Additional Machine scope `+` actions in the same
house or pooled context default to matching numeric Setter and Hatcher values,
so chips advance like House and Trolley scopes: `SH`, `S1H1`, `S2H2`, and so
on, with the numeric fields showing `1`, `2`, etc. Entered values update chips
as `S{setter}H{hatcher}`; the label itself is not separately editable. The
Machine scope remove action is available as soon as a real machine chip is
active; removing the only active machine returns the selected context to
machine `Pool` without changing House scope. A `Trolley scope` card appears
directly below Machine scope even while House and Machine are pooled. It shows
`Pool` until a trolley is added. Pressing
Trolley scope `+` attaches the trolley to the pooled breakout sample with a
prefix-only `T` trolley placeholder, so the Tray scope stays on `Pool` and adding
a trolley never starts tray comparison on its own. It selects the new trolley
without scrolling to the tray entry fields, shows the active Trolley field blank,
and labels the chip `T` until a number is entered. A second trolley in the same
scope adds another pooled sample, so trolleys can be compared while the Tray
scope is still pooled. If House or Machine scope is active, the trolley sample
inherits that parent hierarchy; if they are pooled, the trolley comparison keeps
House, Setter, and Hatcher blank. Entered trolley values update the chip as
`T{trolley}`. The active trolley only breaks into trays when Tray scope `+` is
pressed, and the first tray inherits the active trolley; adding more tray samples
while a trolley is selected assigns those trays to the same trolley. Selecting an
existing Trolley chip switches the active trolley without scrolling the page to
the tray entry fields. Switching to another machine shows that machine's own
trolley scope instead of sharing trolley chips across machines. Removing the
active trolley drops that trolley's pooled sample when other trolleys remain, or
clears the trolley label back to plain `Pool` when it is the only trolley,
without deleting trays in an active tray comparison. The selected House,
Setter, Hatcher, and Trolley values are shared by Hatch Results and all tray
samples in that scope, while unactivated pooled tray rows save without hidden
House/Setter/Hatcher/Trolley hierarchy. Each residue machine keeps its own total
eggs set, hatched chicks, culled chicks, dead chicks, trolley groups, and tray
breakout samples. Total eggs set defaults to `19200` and counts as meaningful
Hatch Analysis panel data for persistence, so opening house or machine scope
paths saves those rows even before hatched, culled, dead, or tray breakout
counts are entered. The default total alone does not complete the station;
station completion still requires hatch result, breakout, metric, or tray data.

Residue / Hatch Day shows a Hatch Results card before Breakout Samples for the
active hatch. The card uses a text-only header with the active hatch label,
groups eggs set, hatched, culled, and dead inputs under Hatch totals, and shows
Hatchability, Fertility, HOF, Culled %, and Dead % as
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
Residue / Hatch Day. It has a dedicated `Tray scope` card that mirrors the
House and Machine scope pattern. In pooled state the Tray scope card shows a
selected `Pool` chip, the sample card records one aggregate pool sample, and no
tray-local Trolley, Tray, or Position fields are shown. Adding a Trolley scope
keeps the Tray scope on `Pool`; only Tray scope `+` starts tray comparison.
Pressing Tray scope `+`
switches the active breakout type into tray comparison, creates `Tray 1`,
selects the new tray without scrolling the page to the tray entry fields, and
shows tray chips plus circular add and remove controls while keeping the tray
entry panel tabbed: only the selected tray's entry card is rendered below the
Tray scope tabs, so other trays are selected from the chip row instead of
stacked as scroll content. Selecting an existing Tray chip switches the active
tray without scrolling the page to the tray entry fields. Removing the final
tray returns that breakout type to Tray scope `Pool`. The Candled Egg and
Residue tray-card header contains
only tray-local fields: Tray, Position, and Tray size; House, Setter, Hatcher,
and Trolley come from the shared hierarchy cards above the samples. Breakout
samples are scoped by breakout type in the shared JSON field: switching Fresh
Egg, Candled Egg, and Residue / Hatch Day hides the other type's entered rows,
and returning to a type restores its previous pool or tray values. When the
station saves panel-table rows, breakout persistence uses Scope Grain
Expansion: it stores one row for each real hierarchy path at the narrowest
active scope. A pooled station saves one row with all hierarchy columns blank.
House scope saves one row per open house, with machine, trolley, tray, and
position blank. Machine scope saves one row per `house -> setter/hatcher` path,
with trolley, tray, and position blank. Trolley scope saves one row per active
trolley path, preserving blank House/Setter/Hatcher values when trolley
comparison starts from pooled House and Machine scope. Tray scope saves one row
per full leaf path; for example, two houses with three machines per house,
three trolleys per machine, and three trays per trolley save fifty-four tray
rows. Fresh Egg tray rows use `house` and `tray` only,
because those eggs are not set in a machine yet. Candled Egg and Residue /
Hatch Day rows use the full sample hierarchy:
`house -> setter/hatcher -> trolley -> tray -> position`. When a deeper
breakout scope is saved, stale parent aggregate rows from the same session/table
are removed so App Inspector shows the current leaf rows instead of duplicated
Pool, House, Machine, or Trolley parents. Each saved tray row stores that tray's
own counts, percentages, current-versus-BMK percentage-point differences, tray
size, hierarchy fields, and position when applicable, so multiple trays are
comparable instead of being collapsed into one summed row.
If older saved breakout JSON contains repeated tray ids, the screen normalizes
those ids before rendering and persists the corrected ids on the next tray edit
so each tray owns independent input state.
Legacy pool or no-tray data still falls back to a single rollup row, and hidden
samples from the other breakout tabs are preserved but not included in the
current table. Each tray card shows label, position when applicable, and tray
size as one balanced row above the breakout item rows, with the position control
given extra width so values such as Random remain readable. New Fresh Egg tray
samples default to 30 eggs; new Candled Egg and Residue / Hatch Day tray
samples default to 150 eggs.
Candled Egg and Residue / Hatch Day tray cards show a position selector;
Fresh Egg tray cards omit position because those eggs are not set in a machine
yet. The position selector uses the same body typography as the label and tray
size fields. Each breakout item row contains a count input and one read-only
summary field that combines the calculated percentage from tray size, the BMK
target percentage loaded from the nearest `bmk_egg_breakout` row for the
calculated BMK age, and the Gap value showing current percentage minus BMK
target without a `pp` suffix. Fresh Egg rows are Infertile, 24 hours, 48 hours,
and Blood Ring. Candled Egg adds Black Eye.
Residue / Hatch Day uses Infertile, Early Dead, Mid Dead, Late Dead, External
Pip, Cracked, and Contaminated. Count inputs keep focus while values are typed
and the keyboard next action moves to the following breakout item count. Empty
or zero count values are treated as not entered for display, while still
contributing `0.0%` to the calculated percentage. Counts below zero, zero or
negative tray sizes, and counts greater than the tray size are invalid for
percentage output. Rows turn into a warning state when the calculated percentage
is higher than the BMK target after a positive count has been entered; the
warning is shown through row and BMK tile styling rather than an icon.
Breakout BMK age is calculated in days from the current flock age and storage
period: Fresh Egg uses `flockAgeDays - storagePeriodDays`, Candled Egg uses
`flockAgeDays - storagePeriodDays - candlingDay`, and Residue / Hatch Day uses
`flockAgeDays - storagePeriodDays - 21`; a missing storage period is treated as
zero. The saved rows keep `storagePeriodDays` and rounded `bmkAgeWeeks`; the
day-level BMK value is calculated in memory for benchmark lookup and is not
persisted as a panel-table column.

Setters captures:

- A dedicated `Machine scope` card for setter machines, matching the existing
  Egg and Chicks machine-scope pattern with S-only chips and circular icon
  actions. The active setter-number entry is inside this Machine scope card.
  The first setter uses the selected visit setter id when present; otherwise it
  defaults to `S`. The add action creates another setter machine in the same
  audit session, defaulted to `S`, and the remove action appears once more than
  one machine is available. Setter machine chips use labels from the setter
  number, such as `S5` and `S7`, and they never include the hatcher-oriented
  `H` suffix used by setter/hatcher machine scope elsewhere. The Setter type
  selector remains text-only without selected checkmarks.
- Setter type, defaulting to Multi, with Single limiting the setter to one
  incubation-age EST scope and Multi allowing additional incubation-age scopes.
- Setter number.
- Machine screen temperature and relative humidity setpoint readings only.
  Actual temperature/RH entry fields are not shown in the Setters setup card.
- Batch size, defaulting to 19,200, and batch count, capped at 6. Total set
  eggs is calculated as `batch size * batch count`.
- Turning angle uses a numeric field with its label floated on the field outline
  in the larger blue label style, and it includes a camera action aligned beside
  the entry field; there is no separate Setter settings title.
- CO2 level uses the same larger blue floated field label and keeps the camera
  action aligned beside the entry field.
- EST samples are grouped by an `Incubation age samples` selector. A single
  incubation-age sample is shown as `Pool` in the same compact outlined chip
  style as multi-sample days; once multiple incubation-age samples exist, chips
  are labeled from the entered age, such as `Day 1` and `Day 12`.
  Duplicate days are disambiguated with compact occurrence labels such as
  `Day 1 · 1` and `Day 1 · 2`. Small icon-only actions add or remove
  incubation-age samples with accessible tap targets. Each scope keeps its own
  incubation age numeric entry from 1 to 18 days, 0-23 hour numeric entry, EST
  readings/photos, average, and CV, so switching between incubation-age samples
  restores that sample's own EST grid and active save payload. Setters does not
  expose a breed picker in the EST sample card; benchmark breed identity comes
  from the visit/session context rather than per-sample UI.
- EST average/CV summary and EST grid/photos.

Setter EST reuses the storage EST guided grid workflow with Front/Middle/Back
by Top/Middle/Bottom points, inline guided OCR capture, inline camera/native
camera fallback, auto scan, confirm/edit, retake, skip, clear reading/photo,
missing-photo attach, saved-photo highlighting, and per-point evidence photo
records. Setters uses Fahrenheit readings with an allowed range of
99.5-102.0°F and an optimum range of 100.0-101.0°F. Those ranges drive the EST
grid status styling and average summary color, but are not rendered as a
separate helper strip in the entry form. Setter samples persist as
`setter_optimizing` rows. The table's sampling hierarchy starts at the `setter`
machine column and can nest `trolley` then `tray`; it does not include house or
hatcher hierarchy columns. Multi-setter rows use the `setter` hierarchy column
as their row identity. Setter and Hatcher station rows can store
machine-specific identity values while the selected flock is still required to
enter the visit flow.
Setters does not expose the generic Sample Mode selector; the dedicated setter
row is the comparison control.

Hatchers captures:

- A dedicated `Machine scope` card for hatcher machines, matching the Setters
  machine-scope pattern with H-only chips and circular icon actions. The active
  hatcher-number entry is inside this Machine scope card. The first hatcher uses
  the selected visit hatcher id when present; otherwise it defaults to `H`. The
  add action creates another hatcher machine in the same audit session, defaulted
  to `H`, and the remove action appears once more than one machine is available.
  Hatcher machine chips use labels from the hatcher number, such as `H5` and
  `H7`, and they never include setter scope.
- A Hatcher settings card for the active hatcher sample, containing outlined
  numeric entry fields for machine temperature setpoint in Fahrenheit, RH
  setpoint percentage, incubation age from 18 to 21 days, and incubation hours
  from 0 to 23 hours. The incubation age and hours controls use the audit
  numeric keyboard instead of sliders.
- CO2 level and photo, with the camera action aligned beside the entry field.
- CVT (Chick Vent Temp.) average/CV summary and guided grid/photos. The grid
  uses the same guided OCR capture, inline/native camera fallback, evidence
  thumbnails, missing-photo attach, and saved-photo highlighting as the setter
  EST/CVT grid flow.
- Chick panting uses compact Yes/No choice chips with the photo action in the
  card header. New hatcher samples start with neither choice selected; selecting
  either Yes or No records an explicit observation and counts as hatcher core
  completion data.
- Meconium assessment: Normal, Dark greenish, Water, or Excessive, with a
  panel photo action for evidence.

Hatchers does not expose the generic Sample Mode selector, a hatcher type
selector, turning-angle fields, or Transfer Day. The dedicated Machine scope
card is shown at the top level, above the Hatcher settings card, and is the
comparison control. Hatcher comparison samples persist as machine samples with
`hatcher_optimizing` rows. The table's sampling hierarchy starts at the
`hatcher` machine column and can nest `trolley` then `tray`; it does not include
house or setter hierarchy columns. Multiple hatchers use the `hatcher`
hierarchy column as their row identity. Removing hatchers until only one remains
returns the station to the single-sample state and saves the station-sample
hatcher identity from the edited Hatcher number field.

Govee is a standalone daily capture workflow. It is independent from audit
sessions and is keyed by `customerId`, `hatcheryId`, place, nullable machine id,
and calendar `captureDate`. The floating Govee capture panel is
active-recording first and is the only in-app entry surface for new Govee
recordings. Dashboard surfaces still provide the broader visit-level review.

The active Govee recorder opens on a compact ChickMark brand-gradient live card
with white/translucent-white controls and small metric tiles. The card shows the
device name, connection status, current Temperature and Relative Humidity,
latest update time, RSSI, and battery level directly on the main card. It
exposes a clear `Scan`, `Read`, or reconnect action, a compact `°F`/`°C` unit
toggle backed by the app temperature setting, and a settings icon. The floating
panel header, scope picker, and place recorder use the shared compact
operational type scale and light bordered surfaces.
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

Dashboard has a cascade filter for Customer, Flock, and Age. On phone-width
layouts the filter stacks Customer above a compact Flock/Age row and constrains
dropdown labels with ellipsis so selected customer/flock names do not overflow.
The current dashboard build shows the rebuilt Egg station sector and saved
Govee Environmental Readings while the other station sectors are rebuilt one at
a time. Egg Storage dashboard trends read the persisted
`egg_storage.estAvg`, `egg_storage.estCvPct`, storage checklist metadata, and
upside-down egg fields. The dashboard also loads the latest 9-point EST
readings and matching `shell_temp_*` evidence photos for the same Egg storage
session. The Egg sector shows the approved Egg Storage & Handling EST card in
an evidence-first layout: the 9-point reading grid sits beside a blue brand
summary card containing Average, target range, and CV%. The summary card raises
an alarm when the EST average is outside the storage-day target range or CV% is
above `AppThresholds.cvAlertPct`. EST alarm styling uses a soft red alert panel
with neutral translucent metric tiles, and missing evidence photo placeholders
use a light blue treatment instead of the shared yellow/orange warning palette.
On phone-width layouts, the EST summary compresses into one compact
Average/Target/CV row above the reading grid, and grid readings stay on one
line. Upside Down Egg remains a separate row below the EST card. Storage days,
turning, tray spacing, cooler proximity, and condensation render together in a
single `Storage Info` card without a status recorded tile.

The dashboard also includes an Egg Quality card directly under Egg Storage. It
reads dashboard-ready `egg_quality` values joined by session/sample from the Egg
storage trend query. The Egg Weights & Uniformity card uses the same brand-blue
summary pattern for average egg weight, uniformity, and C.V, and raises an alarm
when C.V is above `AppThresholds.cvAlertPct` or uniformity is below
`AppThresholds.uniformityGood`. Its detail tiles show sample size, BMK egg
weight, and calculated low/high margins based on the saved average weight. The
Shell Quality UV card shows total affected percentage against the `<= 5.0%`
dashboard limit, raises an alarm when the saved affected percentage is higher
than that limit, and organizes Cuticle Damage, Washed, and Dirty percentages in
separate tiles with saved UV photos below when available. The Egg sector does
not render CO2 dashboard tabs or Chicks station dashboard content.

Dashboard shows a dedicated `Govee Environmental Readings` sector for saved
Govee captures. Those records are loaded from saved Govee capture rows and may
be scoped by the dashboard Customer filter; Flock and Age filters do not affect
Govee records. The section is organized by place, with inside-setter and
inside-hatcher captures kept as separate machine records within their place
group. Each capture card shows place, machine when present, recording time
range, Temp avg/min/max/SD/CV%, RH avg/min/max/SD/CV%, and saved representative
reading count. Each card renders separate timestamp-based Temperature and
Relative Humidity charts from the capture row's LTTB-selected
`chartPointsJson`. Dashboard chart touches show exact timestamp, temperature,
RH, place, and machine when present. The Govee screen remains focused on live
device status, scope selection, recording, syncing, and save feedback; saved
history cards live on Dashboard.

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
  visit ownership, explicit nullable sample hierarchy, storage/BMK context,
  notes, sync state, and the panel-specific measurements or calculated
  dashboard values. Single-sample results are one row; multi-sample results are
  multiple rows in the same table, one row per sampled leaf.
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
A sample is represented by a row in the relevant panel table. Panel tables do
not store the old generic identity columns (`mode`, `scopeType`, `scopeLabel`,
`sampleIndex`, `groupKey`, or `groupLabel`). Instead they use nullable
hierarchy columns (`house`, `setter`, `hatcher`, `trolley`, `tray`,
`position`). Hierarchy columns that are not meaningful for the current panel or
single-sample state stay null.

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

The app uses SQLite through `sqflite` at database version 41. The database file
is `hatchaudit.db`. Foreign keys are disabled during create/upgrade callbacks
so the destructive v41 reset can drop legacy foreign-key tables, then enabled
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

The v41 database cutover is destructive. Upgrading from any older local schema
drops old app tables, including legacy audit/sample tables, legacy Govee spot
tables, and legacy generic temperature tables, then recreates the current fresh
schema. Old local audit history is not migrated. When an already-created v41
database opens, the app
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
- `chick_quality`
- `chick_weights`
- `fresh_egg_breakout`
- `candled_egg_breakout`
- `residue_breakout`
- `setter_optimizing`
- `hatcher_optimizing`
- `govee_daily_captures`
- `sync_tombstones`

Fresh databases do not create `audits`, `sample_records`, sample detail tables,
`egg_weights`, `{panel}_samples` child tables, legacy generic temperature
tables, or legacy Govee spot-reading tables.

Every panel table includes visit ownership fields, explicit sample hierarchy
fields for that panel, storage/BMK context fields (`storagePeriodDays`,
`bmkAgeWeeks`), panel-specific measurement and calculated summary fields, and
sync fields. Egg, chick, and breakout panel hierarchy can include `house`,
`setter`, `hatcher`, `trolley`, `tray`, and `position`; `setter_optimizing`
uses only `setter`, `trolley`, and `tray`; `hatcher_optimizing` uses only
`hatcher`, `trolley`, and `tray`. Each panel table has session, dashboard, and
unique-row indexes. The unique-row index protects `sessionId` plus the panel's
actual hierarchy columns.

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

- 2026-06-03: Debounced Chicks weight-sheet calculation commits so keypad entry
  updates the draft after a short pause or sheet close instead of rebuilding the
  full Chicks station on every tap.
- 2026-06-03: Changed Hatch Analysis Trolley scope so adding a trolley attaches
  it to the pooled breakout sample and keeps the Tray scope on `Pool`. The Tray
  scope only enters tray comparison when Tray scope `+` is pressed, and the first
  tray inherits the active trolley. Removing a trolley drops its pooled sample
  when other trolleys remain, or reverts to plain `Pool` when it is the last one.
- 2026-06-03: Tightened Egg panel persistence so `egg_storage` rows are created
  only after EST data is entered, and `egg_quality` rows are created only after
  Egg Weights & Uniformity or Egg Shell Quality UV data is entered.
- 2026-06-03: Fixed Chicks machine-scope panel forms so switching setter/hatcher
  machine chips reloads that machine's own Pasgar, YFBM, CVT, PM Necropsy, and
  Culled Chicks Analysis draft values instead of leaving stale form-controller
  values from the previously selected machine visible.
- 2026-06-03: Changed Hatch Analysis Machine scope additions so the first
  machine stays prefix-only `SH`, while later machines in the same house or
  pooled context default to numbered `S1H1`, `S2H2`, etc. chips with matching
  numeric Setter/Hatcher fields.
- 2026-06-03: Added a bottom `Clear` action to visit station footers. Confirmed
  clears delete that station's saved panel rows for the active session, reset
  fields/scopes/samples, and remove the station from completion progress.
- 2026-06-03: Deferred audit-session provider clearing and station-selection
  loading reset until after the route-pop frame so backing from a station to the
  main station-selection screen does not mutate active `LayoutBuilder` layout.
- 2026-05-26: Kept Hatch Analysis `Trolley scope` independent from House and
  Machine scope, so users can leave both pooled and start comparison at trolley.
- 2026-05-26: Counted Hatch Analysis `Total eggs set` as meaningful panel data
  so Scope Grain Expansion writes open house and machine paths instead of
  discarding them until a hatched/cull/dead count is entered.
- 2026-05-26: Kept Hatch Analysis station completion separate from panel
  persistence so the default `Total eggs set` alone does not complete the
  station.
- 2026-05-26: Removed the Egg Quality `Machine scope` card from the Egg station
  screen so Egg quality sampling exposes only the House scope control.
- 2026-05-26: Fixed Hatch Analysis / Egg Breakouts panel persistence to use
  Scope Grain Expansion in the database: pooled saves one blank-hierarchy row,
  house saves one row per house, machine saves one row per house-machine path,
  trolley saves one row per house-machine-trolley path, and tray saves only full
  leaf paths while pruning parent aggregate rows.
- 2026-05-26: Changed Hatcher Chick Panting so blank samples no longer
  preselect No, unanswered model values remain null, and either explicit Yes or
  No counts as core data for station completion.
- 2026-05-26: Stopped Hatch Analysis Trolley and Tray scope chip selection from
  auto-scrolling to the tray entry fields; chips still switch the active
  trolley or tray in place.
- 2026-05-25: Aligned Egg Breakout panel persistence with the Egg Quality
  hierarchy model. Breakout rows now save at the deepest active scope
  (`Pool`, `House`, `Machine`, `Trolley`, or tray leaf), Candled/Residue schema
  includes Trolley as a real layer, and tray saves prune stale parent aggregate
  rows from the same session/table.
- 2026-05-25: Added a Hatch Analysis Trolley scope card under Machine scope.
  Trolleys are owned by the active machine, added trays inherit the selected
  trolley, and Candled/Residue tray cards now keep trolley out of the tray-local
  header fields.
- 2026-05-25: Added station-specific completion validation to the visit exit
  path. Incomplete stations can be skipped after confirmation without being
  marked complete, and blank/default-only station rows are removed instead of
  implying progress.
- 2026-05-25: Restored Hatcher multi-machine resume so all saved Hatcher rows
  reopen as machine-scope chips and can be edited independently, including
  machine-specific CO2 and incubation values.
- 2026-05-25: Kept Hatch Analysis House, Machine, and Tray scopes explicit:
  adding Machine or Tray scope no longer creates synthetic parent scope.
- 2026-05-25: Fixed Egg Breakout tray-row persistence so explicit saved tray
  hierarchy is written to the breakout panel tables, while hidden draft
  hierarchy still remains blank until the matching scope is active.
- 2026-05-25: Cleaned the Setters incubation-age sample selector with `Pool` /
  `Day N` chips, duplicate-day disambiguation, compact icon actions, and active
  EST sample payload sync; Hatcher incubation age/hour controls now use numeric
  fields.
- 2026-05-23: Changed the visit-session progress strip so the active station
  circle uses a small white dot marker on blue, leaving green checks for
  completed/reached past stations.
- 2026-05-23: Changed Hatch Analysis / Egg Breakouts Tray scope comparison to
  render only the active tray entry panel under the tray chips instead of
  stacking every tray card in the scroll view.
- 2026-05-23: Updated Hatch Analysis / Egg Breakouts scope controls so House
  scope starts as prefix-only `H`, Machine scope starts as prefix-only `SH`,
  both active hierarchy cards expose remove actions that return to pooled mode,
  and Breakout Samples uses a dedicated Tray scope where `Pool` stores aggregate
  counts while tray comparison still saves one panel row per physical tray.
- 2026-05-23: Removed persisted `bmkAgeDays` from panel tables. BMK day values
  are still calculated in memory for benchmark lookups, while stored panel
  context keeps current flock age weeks, storage period, and rounded BMK weeks.
- 2026-05-23: Fixed Chick Weights House scope so newly added or blank house
  samples no longer inherit the previous active house's entered weight grid,
  sample size, average, uniformity, or C.V. Saves now keep each `chick_weights`
  row tied to that house sample's own entered values.
- 2026-05-23: Fixed Chick Weights House scope removal so the first active `H`
  sample exposes the remove action and removing it returns the weights card to
  pooled `Pool` state.
- 2026-05-22: Fixed panel row upserts when a Chicks/Egg scoped sample returns to
  the pooled hierarchy while an older pooled row already exists. Saves now merge
  into the existing hierarchy row and queue a tombstone for the stale scoped row
  id, avoiding `idx_chick_quality_unique_row` unique-index failures.
- 2026-05-22: Replaced the shared in-app ChickMark logo asset with the
  cap-and-glasses chick mark, removed the checkerboard/white square background
  by saving it with PNG transparency, regenerated web/Android/iOS/macOS launcher
  icons from the same mark, and added optional bob-and-glint motion for large
  auth/startup logo placements.
- 2026-05-22: Restored the visit-session progress strip on Hatch Analysis &
  Egg Breakouts so its station check marks appear like the other station
  screens.
- 2026-05-23: Added the station removal button to saved rows on the resumed
  Select Stations visit-order list while preserving row taps for review/edit.
- 2026-05-23: Kept visit-session footer navigation on `Next Station` for
  non-final completed/review stations, reserving `Save` for the final station.
- 2026-05-20: Added same-context visit resume for station selection. Matching
  in-progress sessions now reopen with saved station badges, unsaved stations
  can be added before continuing, Home and Audits route active visits through
  station selection, and completed visits open station screens first with a
  separate final-results action.
- 2026-05-23: Fixed resumed Egg stations so `egg_quality` house and
  setter/hatcher hierarchy rows hydrate the House/Machine scope chips even when
  `egg_storage` is only a pooled row. Egg sample synchronization now applies
  generated house labels only to house samples and generated machine labels only
  to machine samples, preventing machine children from being reassigned or
  relabeled during resume/save.
- 2026-05-23: Fixed Egg Quality Machine scope removal from a selected House
  scope. Visible machine children now expose the remove action even when the
  house chip is active, and removal deletes that machine child while preserving
  the selected house.
- 2026-05-23: Fixed Egg Quality parent scope selection so selecting a house with
  machine children activates the first machine child instead of leaving
  setter/hatcher null, and saving now prunes parent-only house rows once machine
  leaf rows exist under that house.
- 2026-05-23: Fixed Egg Quality active machine removal so deleting `S1H1` under
  `H1` returns to the `H1` context instead of falling through by list position
  to the next house such as `H2`.
- 2026-05-23: Changed first Egg Quality scope activation to use the same
  prefix-only placeholders as later scope rows. Converting pooled Egg Quality to
  House scope now creates only `H`, converting pooled Egg Quality to Machine
  scope now creates only `SH`, and removing the only active scope returns the
  station to `Pool`.
- 2026-05-23: Changed newly added Egg Quality scope rows to start as prefix-only
  placeholders. New House rows show `H` with a blank House field, new Machine
  rows show `SH` with blank Setter/Hatcher fields, and entering values updates
  the chip labels such as `H2` or `S3H4`.
- 2026-05-23: Stabilized Egg Quality House/Setter/Hatcher identity fields so
  entering a House number keeps the field active during provider rebuilds, while
  idle fields still sync metadata changes back into the visible input.
- 2026-05-23: Deleted removed scope sample panel rows before re-saving retained
  scopes, preventing reindexed House/Machine labels from reusing a deleted
  scope's saved row id.
- 2026-05-23: Fixed Egg Quality House-field edits while a Machine child is
  active. Renaming the selected House now updates the parent House sample and
  cascades the new house key to its Machine children instead of orphaning the
  active Machine scope.
- 2026-05-23: Aligned first Chicks scope activation with Egg placeholder scope
  behavior. Chick Quality Machine scope now starts with a single `SH`
  placeholder, and Chick Weights House scope starts with a single `H`
  placeholder instead of adding generated `S1H1`/`H1` rows beside them.
- 2026-05-23: Fixed Chick Quality Machine scope removal so the first active
  `SH` sample exposes the remove action and removing it returns the card to
  pooled `Pool` state.
- 2026-05-23: Restyled the embedded Chicks Pasgar form to remove nested card
  boxes, group defect rows in one divided list, and show the final score as a
  compact summary row.
- 2026-05-23: Removed the embedded Chicks CVT inline °F/°C toggle. CVT grid
  entry now stays in °F while retaining the 103-105°F / 39.4-40.6°C target
  reference and guided capture action.
- 2026-05-23: Moved the Chicks PM Necropsy fixed Gizzard Erosions row to the
  end of the built-in lesion checklist before custom Others rows.
- 2026-05-23: Made Setter/Hatcher panel-table hierarchy machine-first:
  `setter_optimizing` now uses only `setter -> trolley -> tray`, and
  `hatcher_optimizing` now uses only `hatcher -> trolley -> tray`; existing
  current databases drop the old unrelated house/opposite-machine/position
  hierarchy columns and rebuild the unique-row indexes.
- 2026-05-23: Updated Hatch Analysis Candled/Residue hierarchy controls to use
  Egg/Chicks-style `House scope` and `Machine scope` cards. The House card owns
  the House field, while the Machine card owns the Setter and Hatcher fields.
- 2026-05-20: Replaced Chicks Quality sampling/Machine ID controls with an
  Egg-style `Machine scope` card. Adding machine scope now generates
  setter/hatcher samples such as `S1H1` and `S2H2`, and Chick Quality panel
  saves persist `setter_hatcher` scoped rows with generated setter/hatcher
  hierarchy values instead of UI-only labels.
- 2026-05-20: Stopped Egg storage upside-down tray totals, Quality Storage Days,
  and auto BMK age/weight values from creating Egg Quality rows by themselves.
  Explicit clean UV inspections still persist by marking the UV tray as
  quality-entered when the quality controls are edited.
- 2026-05-19: Prevented untouched Egg station saves from creating metadata-only
  `egg_storage` or `egg_quality` rows. Blank storage defaults still feed draft
  and sample metadata for BMK calculations, and auto BMK age/weight can still be
  displayed, but panel persistence now skips and clears Egg panel rows when no
  corresponding storage or quality field has been entered.
- 2026-05-19: Redesigned the BMK reference screen into a denser operational
  dashboard with compact Reference/Admin mode controls, custom breed and
  breakout type selector bars, labeled age controls, and responsive benchmark
  metric tiles. Phone-width BMK sectors now use two-column metric grids and
  one-row breakout type controls so the whole sector can be scanned without
  long vertical scrolling; per-metric decorative symbols were removed from
  Breed Benchmarks and Egg Breakout BMK value cards, the Egg Breakout selector
  is text-only, and the Egg Breakout sector header now uses the standard egg
  symbol.
- 2026-05-19: Split Egg Storage and Egg Quality storage periods. Egg Storage
  keeps its own storage-room days for storage/EST persistence, while Egg Quality
  now has a dedicated Quality Storage Days entry that drives Egg Quality BMK age,
  BMK egg-weight lookup, mapper patches, and `egg_quality.storagePeriodDays`.
- 2026-05-19: Defaulted blank storage-day values to `0` for Egg, Chicks, and
  Hatch Analysis / Egg Breakout station metadata, plus saved rows that have
  other meaningful panel data, so BMK age continues calculating when storage is
  left untouched or missing in older rows.
- 2026-05-19: Added Hatcher machine temperature and RH setpoint fields, storing
  them in the hatcher audit draft and `hatcher_optimizing` panel row.
- 2026-05-19: Removed the Setters `Setter settings` title and changed Turning
  Angle and CO2 Level to always show larger blue labels on the field outline.
- 2026-05-23: Added a Setters Turning Angle camera action aligned beside the
  entry field.
- 2026-05-23: Changed the Setters selector to the existing Egg-style `Machine
  scope` card with circular icon actions while keeping its chips S-only, such
  as `S1` and `S5`, without any `H` suffix.
- 2026-05-23: Moved the Setters setter-number entry into the Machine scope card
  and defaulted blank first/new setter machine samples to `S`.
- 2026-05-25: Removed the Setters machine-screen actual temperature and actual
  RH entry fields from the setup card, leaving only the Fahrenheit and RH
  setpoint fields.
- 2026-05-23: Removed the Setters EST sample breed picker so samples only show
  incubation age, incubation hours, readings, photos, average, and CV inputs.
- 2026-05-23: Replaced the Setters EST sample tabs with an incubation-age
  selector that shows one sample as `Pool`, manages samples with plus/minus
  icon actions, and keeps EST grids isolated per incubation-age sample.
- 2026-05-23: Changed the Hatchers selector to the Setters-style `Machine
  scope` card, moved Hatcher number into that card, and defaulted blank
  first/new hatcher machine samples to `H`.
- 2026-05-23: Restyled Hatcher Chick Panting from a full-width segmented
  control to compact Yes/No chips with the photo action in the card header.
- 2026-05-23: Changed Hatch Analysis / Egg Breakouts House scope chips from
  `House 1` wording to compact `H1`, `H2`, etc. labels.
- 2026-05-23: Changed Hatch Analysis / Egg Breakouts hierarchy controls to show
  `Pool` in House scope and Machine scope until activated, and kept unactivated
  pooled tray rows from saving hidden House/Setter/Hatcher hierarchy.
- 2026-05-19: Added Setters machine-screen relative humidity setpoint and
  actual entry fields, storing them in the audit draft and setter panel
  persistence beside the existing Fahrenheit setpoint/actual readings.
- 2026-05-19: Removed the Short beak item from Chicks Culled Chicks Analysis.
  The defect catalogue no longer renders it in the UI, encodes it into
  `culledChicksAnalysisJson`, or decodes older saved `head_short_beak` rows.
- 2026-05-22: Changed Chicks Culled Chicks Analysis to use total egg set
  (default 19,200) as the denominator and persist defect percentages only in
  `culledChicksAnalysisJson`, with no saved defect row counts.
- 2026-05-22: Standardized user-facing app dates to left-to-right
  `dd-MM-yyyy` labels while preserving ISO date keys for persistence, search
  fallback, and Govee capture queries.
- 2026-05-23: Renamed the Hatch Analysis & Egg Breakouts row summary delta from
  Diff to Gap and removed the `pp` suffix from the displayed value.
- 2026-05-22: Combined Hatch Analysis & Egg Breakouts row percentage, BMK, and
  delta metrics into one readable summary field instead of three narrow tiles.
- 2026-05-19: Removed the Weak / inactive chick item from Chicks Culled Chicks
  Analysis. The defect catalogue no longer renders it in the UI, encodes it into
  `culledChicksAnalysisJson`, or decodes older saved
  `small_weak_weak_inactive_chick` rows.
- 2026-05-19: Moved Egg quality comparison sample chips and add/remove controls
  into the Sampling scope card so the active house sample applies visibly to UV
  tray inspection, weights/uniformity, and future Egg quality items rather than
  appearing inside only the Egg Weights & Uniformity card.
- 2026-05-19: Reworked panel persistence to use explicit nullable hierarchy
  columns (`house`, `setter`, `hatcher`, `trolley`, `tray`, `position`) plus
  storage/BMK context columns instead of the old generic mode/scope/sample
  identity fields. Reopened station edits now update rows by that hierarchy
  identity, and breakout BMK age is saved from the Fresh/Candled/Residue
  formulas.
- 2026-05-19: Normalized duplicate Hatch Analysis breakout tray ids before
  rendering so tray inputs keep independent field state and persist corrected
  ids on the next tray edit.
- 2026-05-19: Replaced Dashboard Egg EST yellow/orange warning surfaces with
  calmer red alarm panels, neutral summary metric highlighting, and light
  blue evidence photo placeholders.
- 2026-05-19: Made panel row saves tolerate orphaned hatchery references from
  older or repaired visit sessions by omitting the nullable panel `hatcheryId`
  when the local hatchery record is missing. This keeps station autosave working
  while Home continues to flag the missing hatchery setup item.
- 2026-05-18: Added minus/plus stepper buttons to Chicks Culled Chicks
  Analysis Count fields while preserving direct numeric entry.
- 2026-05-18: Moved Culled Chicks Analysis Dehydrated / burned chick from
  Sticky into a standalone Dehydrated group.
- 2026-05-18: Removed the Wet chick item from Chicks Culled Chicks Analysis
  Sticky defects.
- 2026-05-18: Removed the Albumen on feathers / glued down item from Chicks
  Culled Chicks Analysis Sticky defects.
- 2026-05-18: Moved Culled Chicks Analysis residual yolk / large abdomen from
  Navel into a standalone Belly group displayed immediately after Navel.
- 2026-05-18: Trimmed Chicks Culled Chicks Analysis counting rows to defect
  subtype plus Count field, keeping descriptions/causes/references for
  Dashboard interpretation instead of the active station entry screen.
- 2026-05-18: Removed deleted legacy Chicks PM lesion columns from fresh
  `chick_quality` schema and current save maps while keeping existing local
  database compatibility.
- 2026-05-18: Changed Hatch Analysis & Egg Breakouts panel persistence so
  Fresh, Candled, and Residue tray samples save as separate tray-scoped rows
  with per-tray counts and percentages instead of one summed breakout row.
- 2026-05-18: Added current-versus-BMK Diff tiles to breakout item rows and
  persisted per-category percentage-point differences on Fresh, Candled, and
  Residue breakout panel rows for dashboard use.
- 2026-05-18: Added Chicks Culled Chicks Analysis after PM Necropsy, with
  grouped defect data entry, guide-based descriptions/causes/references,
  persisted summary fields, and Dashboard Culled interpretation inside the
  Chick Quality sector.
- 2026-05-18: Rebuilt the Dashboard Egg sector around Egg Storage & Handling:
  a 9-point EST temperature grid with evidence thumbnails and AVG/CV summary,
  an Upside Down Egg card, and organized storage checklist metadata. The Egg
  sector does not show Egg uniformity, UV, or CO2 tabs.
- 2026-05-18: Restyled the Dashboard Egg EST card into an evidence-first layout
  with the 9-point grid beside a blue Average/Target/CV summary, alarm text for
  out-of-range average or CV above `AppThresholds.cvAlertPct`, smaller summary
  metric type, a separate Upside Down Egg row, and one combined Storage Info row
  for storage and handling metadata.
- 2026-05-19: Combined the Dashboard Egg Storage Checklist and Handling Metadata
  rows into one `Storage Info` card and removed the storage status recorded tile.
- 2026-05-18: Fixed Dashboard mobile layout by making the Customer/Flock/Age
  filter responsive, constraining dropdown labels, compacting the Egg EST
  summary into a single mobile row above the grid, keeping EST readings on one
  line, and removing Chicks content from Dashboard so the current screen shows
  only Egg plus saved Govee sectors.
- 2026-05-17: Moved the Home ChickMark icon mark into the main gradient app bar
  before the `ChickMark` title and removed the standalone body logo slot.
- 2026-05-17: Changed the Govee live capture card to the ChickMark blue brand
  gradient and adjusted its controls, metric tiles, metadata, and unit toggle
  to white/translucent-white foreground styling.
- 2026-05-17: Hid the Chicks weight active house editor while House scope is in
  One sample mode; Multisamples mode still shows house chips, add/remove
  controls, and the house field for comparison rows.
- 2026-05-17: Limited the Dashboard to the Egg station sector and saved Govee
  Environmental Readings while future sectors are rebuilt. Removed the
  dashboard Egg CO2 tab to match the current Egg station screen, moved saved
  Govee history out of the Govee screen, and grouped saved Govee records by
  place on Dashboard.
- 2026-05-17: Removed the Chicks PM Necropsy Gasping and Deformities sectors
  from the active UI, fresh `chick_quality` schema, save mapping, legacy
  `AuditModel` serialization, and PM dashboard/detail summaries.
- 2026-05-16: Renamed the Chicks PM Necropsy visible lesion label from
  Omphalitis (Yolk Sacculitis) to Omphalitis.
- 2026-05-16: Added Urolithiasis (Urate Deposits) as a fixed Chicks PM
  Necropsy lesion field with count and severity.
- 2026-05-16: Removed Pulmonary Granuloma, Swollen Joints, and Stunted Organs
  from the active Chicks PM Necropsy visible lesion list while leaving legacy
  storage fields intact.
- 2026-05-16: Added editable custom Others lesion rows to Chicks PM Necropsy,
  persisted as `pmOtherLesionsJson`.
- 2026-05-16: Simplified the YFBM entries bottom sheet into a clean entry form
  and moved rows complete, average, CV, and target range details into the main
  YFBM panel.
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
- 2026-05-16: Revised the Chicks PM Necropsy lesion list to use Omphalitis,
  Gizzard Erosions, Air Sac Caseations, Urolithiasis (Urate Deposits),
  Nephritis, and General Septicemia, and added matching `chick_quality`
  backend fields with on-open column backfill for existing local databases.
- 2026-05-16: Consolidated Chicks quality persistence into one
  `chick_quality` panel table with prefixed Pasgar, YFBM, CVT, and PM fields,
  while keeping Chick Weights & Uniformity in the separate `chick_weights`
  table.
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
- 2026-05-16: Tightened the embedded Chicks Pasgar defect-count layout so
  station panel labels, percentages, count inputs, steppers, and photo buttons
  use compact sizing instead of full-page audit typography.
- 2026-05-16: Removed the redundant embedded Chicks Pasgar Defect Counts card
  heading so the defect rows start directly under the card surface.
- 2026-05-16: Removed the redundant embedded Chicks Pasgar Sample Size card
  heading so the sample-size input starts directly under the card surface.
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
- 2026-05-16: Tightened the Home preview and floating Govee capture panel
  styling: Home KPIs now render as a compact strip at browser-preview widths,
  quick actions use primary/secondary hierarchy, and the Govee panel uses light
  bordered surfaces with smaller headers and metric values.
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
- 2026-05-16: Added per-type Egg shell UV percentage columns
  (`uvCuticleDamagePct`, `uvWashedPct`, and `uvDirtyPct`) to `egg_quality` and
  surfaced a matching UV Summary card at the top of the Egg Shell Quality
  section.
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
- 2026-05-19: Added the Machine Scope title above the Chicks setter/hatcher
  sample chip row in Multisamples mode.
- 2026-05-19: Removed the Chicks weight-panel House scope selector so the
  flock card flows directly into metrics unless house comparison samples are
  already active.
- 2026-05-19: Renamed the Chicks weight comparison chip card to House scope and
  changed its first blank house sample to `Pool`; typed house numbers derive
  labels such as `H1`, while added houses keep automatic serial labels.
- 2026-05-19: Changed blank Chicks machine-sample chips to display `Pool` until
  both Setter and Hatcher values are entered, then derive labels such as
  `S1H1`.
- 2026-05-19: Replaced the Egg Quality One sample / Multiple samples selector
  with House scope and Machine scope cards. Both default to `Pool`; House scope
  activates sequential `H1`, `H2` comparison rows and Machine scope activates
  sequential setter/hatcher rows such as `S1H1`, `S2H2`, while Egg Storage stays
  pooled.
- 2026-05-21: Changed Chick Weights & Uniformity to use an Egg-quality-style
  House scope card. The card is visible in pooled state, add switches to
  generated `H1`/`H2` house comparison samples, the separate Active house editor
  is removed, and saved `chick_weights` panel rows carry house hierarchy values.
- 2026-05-21: Added active scope identity fields: House fields for Egg Quality
  and Chick Weights house scopes, and Setter/Hatcher fields for Egg Quality and
  Chick Quality machine scopes. Entered values update chip labels and persist
  through the panel sample hierarchy columns.
- 2026-05-21: Pruned stale scoped panel rows after station saves so deleting
  House or Machine scope samples removes their database rows and queues
  tombstones for sync.
- 2026-05-22: Fixed Egg Quality scope hierarchy so Machine scope is added under
  the active House scope instead of replacing it. House chips stay visible as
  the parent level, machine chips are filtered to the selected house, houses
  without machine samples show pooled machine scope, and adding House scope after
  Machine-only scope resets the lower machine samples.
- 2026-05-22: Kept generated Egg Quality scope chip labels while leaving their
  House/Setter/Hatcher input fields blank until the user enters real numbers,
  and made House scope removal cascade-delete nested Machine scope samples.
- 2026-05-22: Removed the inherited House field from the Egg Quality Machine
  scope card; Machine scope now relies on the selected House scope and only asks
  for Setter and Hatcher values.
- 2026-05-22: Kept generated Egg Quality scope serials local to each visible
  scope list, so machine samples under a selected house start at `S1H1` even
  when house scope already contains `H1`/`H2`.
- 2026-05-22: Made Egg Quality House-scope removal target the selected parent
  house even when a nested machine sample is active, so one House `-` press
  removes the house and all machine samples beneath it.
- 2026-05-22: Tightened the v41 destructive cutover and current-schema tests so
  obsolete audit/sample repositories remain inert, current panel relationship
  cascades are verified, and legacy Govee/temperature tables are dropped during
  reset.
- 2026-05-19: Made Egg storage-period, EST/storage handling, Egg Quality storage
  period, and Egg Quality BMK age/weight fields shared across Egg Quality
  house/machine scope samples so the second sample keeps the same BMK lookup
  instead of showing blank benchmark weight.
- 2026-05-19: Started the Egg Quality BMK egg-weight lookup from the default
  Quality Storage Days value when the Egg screen opens, so the BMK Egg Weight row
  does not stay blank until storage days are manually edited.
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
- 2026-05-19: Changed Hatch Analysis Candled/Residue hierarchy entry to shared
  house tabs followed by setter/hatcher machine tabs, moved House/Setter/Hatcher
  out of tray cards, and kept tray cards scoped to Trolley, Tray, Position, and
  Tray size.
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
