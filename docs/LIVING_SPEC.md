# Living Spec — Current Implemented Behavior

This file documents behavior mapped from the current Flutter codebase. The
current Flutter codebase remains the primary source of truth. If this document
and code conflict, inspect the code and report the mismatch.

This file must be updated after every meaningful code change.

## 1. Last Updated

2026-07-28

Mapped from the current working tree under `lib/`, especially app bootstrap,
navigation, audit screens, providers, models, repositories, services, and the
SQLite database helper. This update intentionally does not use deleted or old
feature specs as source material.

## 2. Navigation

App bootstrap starts in `main.dart`, initializes SQLite before `runApp`, then
starts token migration, notifications, and guarded Supabase initialization in
the background. Supabase service calls wait for that initialization guard before
reading `Supabase.instance.client`, so remote auth and sync calls cannot race
ahead of the client setup. Supabase configuration uses complete compile-time
`SUPABASE_URL` and `SUPABASE_ANON_KEY` values when both are supplied. When both
compile-time values are empty or placeholders, startup may load a local `.env`
file copied from the ignored repository `.env` into the macOS debug/profile app
bundle, then fall back to the bundled `.env.json` placeholder asset. Partial
compile-time credentials are treated as unconfigured and are not completed from
a fallback source. Local macOS development launch paths use the ignored `.env`
credential file: `make run-macos` passes it to `flutter run -d macos`, `make
build-macos` passes it to `flutter build macos`, the checked-in VS Code launch
config also uses `--dart-define-from-file=.env`, and the macOS Xcode build
copies `.env` into debug/profile bundles while removing it for Release. This
keeps the desktop app from falling back to the placeholder `.env.json` asset and
showing "Cloud not configured" during local sync checks. Supabase availability
refreshes re-run the config load before declaring cloud unavailable so a
foreground Retry can recover after the local macOS bundle/config becomes
available.

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
Shared gradient app bars keep long titles to one ellipsized line, including
titles with leading brand or screen icons. Shared status badges constrain their
label width and ellipsize overflow so card headers remain stable on phone-width
layouts.
Shared card surfaces use a restrained operational style with tighter corner
radii, soft low-contrast shadows, and subtle default borders. Section cards may
show small leading Material symbols in blue-tinted icon containers, and the
Customers, Settings, and BMK reference surfaces use those simple symbols instead
of decorative or emoji-led labeling.
Shared app chrome and simple account/admin states use the central design tokens
for common action labels, neutral surfaces, status colors, and exact-match
spacing where those tokens already exist, preserving the existing workflows and
screen hierarchy.
The add/edit flock bottom sheet uses compact input fields, local pill selectors
for age source and availability, and quiet helper text while preserving the
existing flock ID, breed, estimated age, depletion age, and active/sold save
behavior.
User-facing date labels use left-to-right `dd-MM-yyyy` formatting across Home,
Audits, Customers, Activity Log, Dashboard Govee charts, and active Govee
capture surfaces. Internal persistence keys and repository filters that depend
on ISO date strings continue to store and compare `yyyy-MM-dd`.

The app supports English and Arabic UI language selection from Settings. The
selected language is stored locally in SharedPreferences and applied at app
startup through Flutter `Localizations` delegates. Arabic uses Flutter's
right-to-left directionality automatically. Static text rendered through the
shared localized Material text layer uses the central ChickMark translation
catalog, including `Text.rich` spans, input decorations, validation errors, and
tooltips. Dynamic translations preserve customer, hatchery, flock, product,
and entered values while translating their surrounding operational copy.
Directional padding, alignment, navigation-drawer corners, and control order
follow the active text direction. App text styles provide Arabic-capable font
fallbacks, and the Home last-audit KPI reserves a two-line value area so Arabic
dates are not truncated. A source audit test rejects untranslated static UI
copy while allowing approved product names and measurement abbreviations.

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
The BMK screen also includes an Operational BMKs reference sector backed by
`bmk_operational_standards`. It lists global operational targets for station
setup and hatchery work, including egg-storage EST/RH, CV and uniformity caps,
shell UV, Pasgar, CVT, YFBM/residual yolk, culled/dead chick limits, setter EST
and turning angle, CO2, hatcher CVT, and hatcher RH. The reference view groups
these rows into Egg, Chicks, Hatch Results, Setters, and Hatchers categories so
station setup values are separated from hatch-result and chick-quality values.
Each operational BMK tile with source metadata includes a citation action beside
the item label. Tapping it opens a compact dialog for that item, showing the
source label, active external source link when one exists, notes, and
source/reference photo actions. ChickMark-only operational defaults do not store
or show an internal docs link. Source photos are saved locally for preview and
uploaded to the Supabase `photos` storage bucket under a BMK source path; the
dialog can replace or delete the photo and opens a zoomable high-quality image
viewer for available previews. In Admin mode, approved admins and auditors can
edit the selected operational BMK row's minimum, maximum, target, and notes. The
Operational BMK Admin sector includes a `Global defaults`
scope plus every saved hatchery; saving while a hatchery is selected writes a
hatchery-specific row that overrides the matching global metric for that
hatchery. Existing station and dashboard warning logic still uses the current
hard-coded `AppThresholds` values until those consumers are explicitly wired to
the operational BMK lookup.

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
Local macOS development uses `make run-macos` for a debug desktop run and
`make build-macos` for a packaged desktop build; both use the same ignored
`.env` Supabase credentials as the mobile run/build shortcuts. Direct
debug/profile macOS builds also copy that ignored `.env` into the app bundle as
a local-only fallback, and Release builds remove the copied file.

`HatchAuditApp` registers these root providers: `AppProvider`, `AuthProvider`,
`CustomersProvider`, `AuditProvider`, `AuditSessionProvider`,
`GoveeCaptureProvider`, `BmkProvider`, `LabAnalysisProvider`,
`SettingsProvider`, `DashboardProvider`, and `ScopeComparisonProvider`.

Initial route selection is auth-state driven:

- Authenticated users go to `/main`.
- Pending approval users go to `/pending-approval`.
- Loading, error, and unauthenticated users go to `/login`.
- `/register` and `/startup-sync` are also registered routes.

After startup, the app also listens for auth-state changes at the root
navigator. If logout or another auth failure leaves the user unauthenticated
while an app route such as `/main` is visible, the navigator is reset to
`/login` so protected screens are not left on screen.

The main shell has ten destinations for approved admins:

- Home
- Dashboard
- Customers
- Audits
- Govee Records
- Lab Analysis
- BMK
- Performance
- Agent
- Settings

Approved auditors receive the same destination set except Agent, leaving nine
auditor destinations. Agent Monitor is restricted to approved admins because
its remote tables use admin-only RLS.

Approved customer-role accounts see only Dashboard and Settings. Settings is
reduced to account details and sign-out, so the only product data surface they
can open is Dashboard. Their Dashboard customer selector is locked to the
profile's assigned `customerId`; hatchery and flock selectors are populated
only from that customer. Dashboard action creation/editing is hidden and also
rejected by provider guards for customer-role users.

The shell uses a drawer on narrow layouts and a navigation rail at widths of
900px or greater. It lazily builds tabs, keeps a tab history stack for shell
back navigation, and triggers background sync after the first Home build.

The previous floating Measures launcher is no longer shown. Govee recording is
entered from a station-level Govee readings button or from the floating Govee
shortcut shown for authenticated users and the explicitly enabled debug auth
bypass after the main app shell has been entered. It stays hidden on login,
registration, pending-approval, and startup-sync screens. The floating shortcut
is mounted at the app Navigator layer, so it remains visible on the main shell
and pushed audit station screens while opening the floating Govee capture
panel. The shortcut reflects active Govee recording state globally: idle uses
the standard ChickMark-blue circular thermometer button, while an in-progress
recording switches to a red rounded stop-style button. Users can drag the
shortcut to a different screen position, and dragging or flinging it past the
left or right edge tucks it partly off-screen while leaving a visible strip for
reopening. The shortcut is hidden while root modal routes such as bottom sheets
are open, keeping station entry sheets unobstructed.

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
creates a local approved auditor identity, so the app opens on Home and audit
creation is enabled for local development. If that development user signs out,
the provider stays unauthenticated for the current session and the `/login`
route renders the real login screen instead of the main shell. The Home and
new-visit edit gates also honor this non-release bypass so local previews can
start new audits even before remote auth is configured. The bypass cannot
activate in release builds. Outside
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
On narrow phones the station footer keeps Back, Clear, and Next/Save in one
compact row. Back and Clear use fixed icon-width controls, Next/Save takes the
remaining width, and reserved trailing space prevents the floating Govee action
from covering the primary action.
When the on-screen keyboard is open on phone-width visit sessions, the fixed
station chrome is hidden: the Govee readings card and visit footer are removed
while editing so the focused field has the available height. The same editing
mode engages when a station text input holds focus, covering mobile builds that
resize the view without exposing a readable keyboard inset to the footer.
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
- Audit-station scope add actions collect the new scope identity before they
  create or switch any sample. House, machine, trolley, tray, and Setter EST
  incubation-age dialogs require all applicable identity fields, reject an
  identity already present under the same parent scope, and leave the current
  data unchanged when cancelled. Identity comparisons ignore case and the
  display prefixes `H`, `S`, `T`, and `Tray`.
- Removing a scope asks for confirmation only when that action would discard
  entered result values, counts, measurements, observations, or evidence
  photos. Scope identity fields by themselves do not trigger the warning.
  Removal paths that only return the last scoped sample to `Pool` while
  preserving its results also do not warn. The destructive dialog states that
  the entered results will be permanently discarded and offers Cancel and
  Remove actions.
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
- A blank Hatchers station can be explicitly saved as incomplete on station
  exit. The save clears any default-only hatcher panel rows and leaves the
  visit in progress instead of blocking the final station save.
- Completing the final selected station updates the session to `completed` and
  returns to the main shell.

The legacy single-station flow still exists in code when `AuditContextScreen` is
constructed with an explicit `auditType`. It collects customer/flock context and,
for Setter or Hatchers, requires the relevant machine id before
opening a single station screen with a fresh `AuditProvider`.

The Audits tab lists recently saved visit sessions, ordered by session
`updatedAt` with visit date as a secondary sort. In-progress sessions open the
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
cards show station completion progress such as `3/5`; Recent Audits uses the
latest saved session order so editing an older visit moves it back into view.
When incomplete visits exist, Home shows an `Incomplete Visits` section
immediately after Quick Actions. It renders every customer-visible
`in_progress` visit with customer, flock, breed, and date context,
completed/selected station progress, the remaining station labels, the reminder
to complete the visit soon, and a `Complete now` action. The action resumes
`AuditSessionScreen` directly at the first selected station absent from
`stationsCompleted`; returning to Home reloads the list, so a completed visit
disappears. The section is hidden when no incomplete visits remain.
The previous Audit Type Breakdown, extra
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

Audit numeric fields use a platform-adaptive input surface. Native Android and
iOS targets open the large in-app ChickMark keypad with decimal, negative,
backspace, next, and grid-down actions. Ordinary text fields continue to use
the device keyboard. Desktop targets, including desktop web browsers, use
normal editable text fields for physical keyboard entry. All paths enforce the
same numeric rules for decimal, negative, and max-decimal-place limits.
Audit station scroll containers reserve extra bottom scroll space while the
device keyboard is visible, so focused text and numeric fields across Egg,
Chicks, Hatch Analysis, Setters, and Hatchers can scroll clear of the keyboard
and session footer.
Audit screen background taps dismiss the active system keyboard after gesture
resolution. Pointer-down events inside editable fields do not clear focus, so
native mobile keyboard activation is not interrupted before data entry begins.
When keyboard editing hides the fixed session Govee and navigation chrome, the
mounted station subtree retains stable widget identity. Its controllers and
focus nodes remain alive while fields or station-owned modal sheets are active.
Egg and Chicks weight-entry modal sheets use a keyboard-aware scroll wrapper
that reserves bottom scroll space for the in-app numeric keypad and device safe
area, so lower grid rows can be scrolled fully above the keypad while entering
weights. Dragging or touching inside those weight-entry sheets keeps the
in-app keypad open so users can scroll through cells without losing the active
entry field. When lower weight cells become active, the custom keypad scroll
alignment keeps the active row above the keypad overlay instead of centered
behind it.

Egg is the station name shown across the app. The station is divided into
storage and handling controls plus Egg Quality Assessment. It starts with a
blue brand-gradient Egg storage room card with white foreground styling for the
selected hatchery, then uses a split workbench layout. The left column contains
EST, upside-down scoring, and the storage checklist as expandable cards. The
right column contains the Egg
quality hero, sample controls, expandable Egg Weights & Uniformity and Egg Shell
Quality cards, and station notes.

- Egg Shell Temperature (EST): storage days, target shell-temperature class,
  guided manual photo capture, EST grid, per-point evidence photos, average, and
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
  total affected percentage. UV tray photo paths draft-save inside the tray
  JSON so reopening the Egg screen restores the thumbnail, and new tray photo
  captures are also registered as `egg_quality` photo rows with `uv_tray_*`
  field keys so photo sync can upload them.
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
  `Pool` while inactive. Pressing the House scope add control first asks for the
  House identity, then turns the pooled Egg Quality sample into a named chip
  such as `H2`; duplicate House identities are rejected before creation. Edited
  values continue to update the active chip and saved Egg Quality hierarchy.
  House
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
  the entered house identity. Egg Storage remains a station-level
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
control and no separate Machine ID card. Pressing the add control asks for both
Setter and Hatcher identities before creating the named machine sample;
duplicate Setter/Hatcher pairs are rejected. The active sample can then be
switched or removed from the same card; removing the only active machine sample
returns the card to `Pool` and hides the Setter/Hatcher entry fields. Active
comparison mode shows the same Setter and Hatcher entry fields used by Egg
quality machine scope.
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
rows use the explicit `setter` and `hatcher` hierarchy columns.
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
Back by Top/Middle/Bottom points, guided CVT capture, inline camera/native
camera fallback, manual reading entry, retake, skip, clear reading/photo,
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
legacy breed field. Resumed visit sessions prefer the live Flock Manager row
for Chicks breed and age, so correcting a flock from 30 to 37 weeks updates the
station context and rewrites Chick Weights BMK age/weight from the matching
breed benchmark instead of keeping the stale saved session snapshot. Chick
Weights uses an Egg-quality-style House scope card instead of a One house /
Compare houses selector or separate Active house editor. In pooled state the
card shows `Pool` plus an add control. Pressing the add control asks for the
House identity before switching Chick Weights to the Egg-style named house scope
flow; duplicate House identities are rejected. Entered house values update the
active chip label and persist to `chick_weights` rows through the explicit house
hierarchy columns;
removing a house sample deletes its stale `chick_weights` row on the next save,
and removing the only active house sample returns Chick Weights to pooled `Pool`
state. The panel shows sample count, BMK chick weight, average weight,
low/high margins,
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
on mobile. The Breakout Type and metadata cards use the same minimum height but
can grow when wrapped content needs more room, avoiding clipped or unbounded
layouts. The metadata card shows auto-filled flock, breed, and read-only BMK
age as three
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

Every breakout item row (for example Infertile, Early Dead, Mid Dead, or
Contaminated) includes its own fixed-width photo control beside the count and
BMK summary. The control stays in the same horizontal row on phone layouts and
scrolls its thumbnails horizontally instead of wrapping below the item. Photos
are saved in the sample JSON under their metric key for in-station review and
create `photos` rows using the active breakout panel
(`fresh_egg_breakout`, `candled_egg_breakout`, or `residue_breakout`), a
panel-row identity containing the sample and metric, and a metric-specific
field key such as `breakout_infertile_photo` or `breakout_midDead_photo`.
Existing thumbnails remain visible at their owning item; tapping a thumbnail
or its edit control replaces that slot, while the add-photo tile remains
available until the item reaches the multi-photo limit. Replaced and removed
photo rows queue sync tombstones and delete their local backing files. Older
sample-level photo entries are preserved as read-only legacy evidence.

Candled Egg and Residue / Hatch Day add hierarchy controls directly below the
Storage Days card. The controls use the same scope-card treatment as Egg and
Chicks screens: a `House scope` card contains the house tabs and active House
field, and a `Machine scope` card contains setter/hatcher machine tabs for the
selected house plus the active Setter and Hatcher fields. Both cards show a
disabled selected `Pool` chip while their scope has not been activated. Pressing
House scope `+` asks for the House identity before turning the pooled hatch row
into the first named house scope, with compact labels such as `H1` and `H2`.
The House scope remove action is available as soon as House
scope is active; removing the only active house returns the Hatch Analysis
hierarchy to pooled mode without discarding its results. Pressing Machine scope
`+` asks for Setter and Hatcher identities before creating the first machine row
without creating a synthetic House scope. If House
scope is still pooled, the House card remains `Pool` and does not show House
entry or House remove controls; if a House scope is active, the machine row
inherits that active house. Machine chips use the submitted identities as
`S{setter}H{hatcher}`; duplicate pairs are rejected within the same House or
pooled parent context, and the label itself is not separately editable. The
Machine scope remove action is available as soon as a real machine chip is
active; removing the only active machine returns the selected context to
machine `Pool` without changing House scope. A `Trolley scope` card appears
directly below Machine scope even while House and Machine are pooled. It shows
`Pool` until a trolley is added. Pressing Trolley scope `+` asks for the
Trolley identity and attaches it to the pooled breakout sample, so the Tray
scope stays on `Pool` and adding a trolley never starts tray comparison on its
own. It selects the new trolley without scrolling to the tray entry fields.
A second trolley in the same
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
Pressing Tray scope `+` first asks for the Tray identity, rejects a duplicate
within the selected trolley, then switches the active breakout type into tray
comparison with that named tray,
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

Breakout count rows use an egg-count capture action instead of the generic
photo picker. Tapping the camera action opens a full-screen guided capture flow
for that breakout item. Each captured photo is analyzed for likely eggs, shows
the counted number for user confirmation, and can be retried or manually
corrected before it is added to the item total. The same breakout item can have
multiple confirmed photos; confirmed counts are summed into the count field and
the confirmed photo paths are stored with the sample JSON. The first photo keeps
the count field key, and additional photos use suffixed field keys for the same
breakout item. Local photo records are registered against the active breakout
panel table, sample row id, and field key so sync can upload the evidence.
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
  defaults to `S`. The add action asks for the Setter identity before creating
  another machine in the same audit session and rejects duplicate S-normalized
  identities. The remove action appears once more than one machine is available.
  Setter machine chips use labels from the setter
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
  The add action asks for a 1-18 day incubation age and 0-23 incubation hours
  before creating the sample, and rejects duplicate age/hour pairs. Small
  icon-only actions add or remove incubation-age samples with accessible tap
  targets. Each scope keeps its own
  incubation age numeric entry from 1 to 18 days, 0-23 hour numeric entry, EST
  readings/photos, average, and CV, so switching between incubation-age samples
  restores that sample's own EST grid and active save payload. Setters does not
  expose a breed picker in the EST sample card; benchmark breed identity comes
  from the visit/session context rather than per-sample UI.
- EST average/CV summary and EST grid/photos.

Setter EST reuses the storage EST guided grid workflow with Front/Middle/Back
by Top/Middle/Bottom points, serial photo capture, manual reading entry, saved
photo highlighting, and per-point evidence photo records. The shared guided
capture footer keeps only a Done action; point-to-point movement happens by
saving a reading, which advances to the next open cell, or by tapping a grid
cell directly. Setters uses Fahrenheit readings with an allowed range of
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
  add action asks for the Hatcher identity before creating another machine in the
  same audit session and rejects duplicate H-normalized identities. The remove
  action appears once more than one machine is available.
  Hatcher machine chips use labels from the hatcher number, such as `H5` and
  `H7`, and they never include setter scope.
- A Hatcher settings card for the active hatcher sample, containing outlined
  numeric entry fields for machine temperature setpoint in Fahrenheit, RH
  setpoint percentage, incubation age from 18 to 21 days, and incubation hours
  from 0 to 23 hours. The incubation age and hours controls use the audit
  numeric keyboard instead of sliders.
- CO2 level and photo, with the camera action aligned beside the entry field.
- CVT (Chick Vent Temp.) average/CV summary and guided grid/photos. The grid
  uses the same guided manual capture, inline/native camera fallback, evidence
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
hatcher identity from the edited Hatcher number field. Saving a blank/default
Hatchers station confirms as an incomplete station save without creating a
metadata-only `hatcher_optimizing` row.

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
operational type scale and light bordered surfaces. Scope dropdown labels for
customers, flocks, hatcheries, and places stay single-line and ellipsized inside
their fields on narrow layouts. The active capture scope picker shows the flock
for visit context, but saved Govee capture rows remain scoped by customer,
hatchery, place, machine id, and capture date. The active capture scope picker
does not expose a separate date field; the provider still assigns the current
capture date internally. Live Temp/RH, update, RSSI, and battery values are
shown only while the most recent live update is fresh:
the current live update plus the first 30 seconds after it. Once the latest live
reading is more than 30 seconds old, the card treats the device as disconnected
for display purposes even if a lower BLE/GATT transport flag is still stale, and
shows empty placeholders instead of old readings. Main-card and settings-sheet
connection labels use the same display status rules; a fresh reading without an
active transport connection is labeled as a recent reading instead of a live
connection. Scan/GATT connection attempts use a small inline activity spinner in
the live-card action, and the compact main-card scan action is disabled while an
active scan is already running. The settings sheet keeps the explicit restart
scan affordance.
The settings sheet shows current connection details, diagnostics, discovered
Govee devices, scan/restart scan, read-now, select-device, and disconnect
controls. Long diagnostic lines are capped to avoid horizontal overflow.
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
shows a single current point. When the sensor has been disconnected for more
than 30 seconds since the last live update, live preview charts reset to an
empty state and are hidden until a new connected reading is available. During
recording, the preview switches to the accumulated live recording readings. Live
preview charts do not allow pan/scale
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
height. The Max/Avg/Min rail scales its labels within the fixed chart rail
slots so 360dp phone layouts with larger text do not overflow the plot area.
Recorded saved charts retain horizontal pan/scale interaction. Chart touches
show the exact timestamp, Temp, RH, place, and machine context when present.

The Govee Records tab shows all saved Govee captures grouped by customer,
hatchery, and capture date. Groups are ordered by the most recently updated
capture first so a newly saved floating-panel recording appears immediately,
even when older seeded/demo rows have future capture dates. If the records tab
is already mounted behind the floating panel, it listens for the finished
capture and merges that row into the visible list without requiring a manual
sync or route reload.

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
when it is available. Station entries preselect customer, hatchery, and place in
the floating Govee capture panel. Setter and Hatcher station entries keep the
Customer and Hatchery controls visible above the room/inside-machine choice so
the capture scope can still be corrected before recording.

Dashboard has a cascade filter for Customer, Hatchery, and Flock. The filter card is part
of the dashboard's scrolling content rather than a frozen section above it. On
phone-width layouts the filter stacks the controls and constrains dropdown
labels with ellipsis so selected names do not overflow. A customer plus
hatchery is required for operational station analysis. `All customers`, a
customer with no hatchery selected, and cleared filters show a portfolio summary
only; detailed station comparisons, alerts, and corrective actions are blocked
so unrelated houses and machines cannot be pooled. When a specific flock is
selected, the same card shows a compact
summary of its name, current age in completed weeks, breed, and entrance date;
the summary is omitted for `All flocks`.
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

Dashboard station cards and the Govee Environmental Readings sector start
expanded and can be collapsed independently. Their expanded/collapsed state is
owned by the current Dashboard screen, so collapsed cards stay collapsed while
the user scrolls and during a pull-to-refresh loading cycle. The state resets
when a new Dashboard screen visit begins. Dashboard reloads are serialized and
coalesced when sync completion, pull-to-refresh, or another refresh request
arrives while a load is already running. Background refresh keeps the existing
sector data mounted, and the Dashboard owns one stable scroll controller, so a
long Lab Analysis sector cannot temporarily collapse and clamp the reader into
a different sector while fresh data is queried.

An operational scope starts with a quality strip and a cross-station `What
needs attention` section. Quality chips show latest observation age, last sync,
station completion, source-row and sample counts, missing-measurement coverage,
photo evidence coverage, pending/failed sync, and raw-versus-cache drift. Govee
shows capture/readings totals and the latest capture age. Readings older than
seven days are historical and excluded from active alarm triage; readings from
48 hours through seven days are aging, while future-dated readings are invalid.
Panel and Govee load failures remain visible within their affected section.

The attention section consolidates critical/watch findings across audit
stations and Govee, ranks them by severity, persistence, freshness, and data
confidence, and keeps source identifiers for the station, metric, session, and
panel row. `View source` expands and scrolls to the exact available sector (or
its station fallback). Findings can create persistent corrective actions with
priority, owner, status, due date, first/last observed timestamps, notes,
resolution metadata, and sync state. Actions support open, in-progress,
resolved, and reopened states and synchronize through Supabase like other
offline-first records.

Each rebuilt dashboard comparison sector has its own BMK-age selector. The
default `All BMK Ages` table keeps every recorded age as a separate column and
adds an equal-age-weighted average, so visits are not silently pooled or
weighted by their number of samples. The existing chart icon switches that same
dataset to a trend chart. In All Ages mode, only House and Machine can be used
as longitudinal comparisons, and they appear only when at least two comparable
identities occur within one age. Missing identity/age intersections display as
no data and do not count as zero in averages.

Selecting one BMK age returns the sector to a pooled result first. House,
Machine, Trolley, and Tray controls are then derived from that age's saved rows:
a level appears only when at least one parent path has two distinct nonblank
children at that level. For example, H1-T1 plus H2-T2 enables House but not Tray,
while H1-T1 plus H1-T2 enables Tray. Multiple valid levels can be selected
together, and the overall average remains visible with the detailed columns.
Unused hierarchy levels and one-sample levels are hidden.

Every dashboard metric declares an aggregation policy. `ratioOfSums` uses the
sum of raw numerators divided by the sum of denominators;
`sampleWeightedMean` weights values by their sample sizes; `equalGroupMean`
gives each displayed group equal weight; `sum` totals values; and `latest`
uses the last date-ordered value. The selected policy is disclosed below each
sector. All-age cumulative results intentionally retain equal-age weighting and
state that basis in the UI.

Raw readings and counts are authoritative. Local panel writes pass through one
canonical derivation service for EST/CVT summaries, egg/chick weight summaries,
Pasgar, Shell UV ratios, and breakout percentages. Persisted dashboard summary
columns are controlled caches. The analytics loader compares those caches with
fresh derivation and raises an aggregate-drift quality flag instead of allowing
the values to diverge silently. The normalized in-memory analytics read model
keeps source scope, numerator, denominator, sample count, value, unit/format,
benchmark context, timestamp, and quality flags while leaving offline panel
tables unchanged.

Legacy database repair is migration-safe: panel query and unique indexes are
created only when their required columns exist, then rechecked after additive
panel-column repair. Older partial panel tables therefore open without an index
creation failure and keep their existing rows.

The dashboard also includes an Egg Quality card directly under Egg Storage. It
reads dashboard-ready `egg_quality` values through the shared scope engine and
renders Egg Weights & Uniformity plus Shell Quality UV as one comparison sector
rather than separate per-house detail cards. When House scope data exists, the
sector's `All BMK Ages` state uses the same separate-age table and equal-age
average as the other scoped sectors. Selecting one age starts with its pooled
result. House comparison appears only when that age contains at least two
houses; a single recorded house does not create a false comparison control.
When House is selected, users can unselect or reselect Pool and individual
houses to control which columns appear in the table. The sector also includes
the same chart/table icon toggle used by other
dashboard scope sectors; chart mode compares the selected Egg Quality metric
across Pool and the selected houses with paired Actual vs BMK bars, wraps the
metric selector instead of clipping it, fits normal Pool-plus-house counts
without horizontal scrolling, keeps per-bar values in touch tooltips instead of
pinning overlapping labels, and shows a dashed average reference line across the
bars. Egg Quality alarms still flag C.V above
`AppThresholds.cvAlertPct`, uniformity below `AppThresholds.uniformityGood`, and
UV affected above the `<= 5.0%` dashboard limit. The Egg sector does not render
CO2 dashboard tabs or Chicks station dashboard content.

Dashboard shows a dedicated `Govee Environmental Readings` sector for saved
Govee captures. Those records are loaded once from saved capture rows and are
scoped by the selected Customer and Hatchery; Flock and BMK-age filters do not
affect Govee records. The stored `chartPointsJson` is decoded from the same
loaded capture rows, avoiding one reading query per capture. The section is organized by place, with inside-setter and
inside-hatcher captures kept as separate machine records within their place
group. Each capture card shows place, machine when present, recording time
range, Temp avg/min/max/SD/CV%, RH avg/min/max/SD/CV%, and saved representative
reading count. Each card renders separate timestamp-based Temperature and
Relative Humidity charts from the capture row's LTTB-selected
`chartPointsJson`. Dashboard chart touches show exact timestamp, temperature,
RH, place, and machine when present. The Govee screen remains focused on live
device status, scope selection, recording, syncing, and save feedback; saved
history cards live on Dashboard. The sector includes a compact `°F`/`°C` toggle
backed by the shared app temperature unit, and the saved capture cards plus
cumulative temperature trend update together when it changes.

Lab Analysis is a standalone breeder-farm lab register scoped to customer,
flock, and report date; it does not require a hatchery or audit visit session.
The main-shell `Lab Analysis` tab lets editors choose customer, flock, and date,
then add ELISA, PCR, HI, Bacterial Culture, or Sensitivity result groups. The add-report sheet is a
three-section flow: report context, test-specific results, then source PDF and
notes. Test-type cards change both the guidance and visible fields so unrelated
assay inputs are not mixed together. A saved lab report header
stores lab name, sample type, optional received date, flock age, notes, and sync
state. It can also carry the original lab-result PDF: the app stores the PDF
filename, local path when available, and Supabase Storage URI on the report row,
and report cards expose a `View PDF` action that opens the local file or a
signed cloud URL. Each report can contain multiple result groups, such as MG
ELISA by house, PCR molecular-detection pages, HI antigen distributions,
bacterial culture/isolation findings, and antibiotic sensitivity panels. ELISA entry saves the printed plate summary
first: mean, minimum, maximum, GMT, CV%, positives, negatives, and cutoffs.
Individual sample entry is optional and hidden by default; enabling it stores
sample number, OD, S/P ratio, result, titer, and titer group, while blank
default rows are never persisted. PCR rows store analyte, result, and Ct. HI
rows store the complete log2 titer distribution including the `>=12` bin,
number of sera, GM, and the saved protective-threshold summary. Bacterial
Culture is a separate test type that stores the culture/isolation method plus
one or more organism/result findings (for example, Salmonella isolation with a
negative result). Sensitivity no longer asks for a bacterial organism; it stores
only antimicrobial names and laboratory S/I/R categories for the selected
sample/isolate scope. Known-value entry fields use controlled lists for sample type,
house/scope, ELISA analyte, kit manufacturer (`IDvet`, `IDEXX`, or `Other`),
ELISA row result, PCR target and result, HI antigen, culture method and organism,
antimicrobial, culture result, and sensitivity category. The actual laboratory name, numeric
results, kit/product codes, notes, and sample identifiers remain editable.
Selecting the MG IDvet preset fills its saved `MG/0416`,
S/P `0.5`, and titer `843` defaults, while other analytes clear MG-specific
cutoffs rather than reusing them accidentally.

Saved Lab Analysis cards use the ChickMark blue brand strip and neutral white
surfaces instead of tinting the full result area by severity. ELISA results
open in a compact summary state showing sample size, mean, GMT, CV%,
positive/negative counts, minimum titer, and maximum titer. Large whole-number
results use thousands separators. The full per-sample ELISA table remains
available from the collapsed `Sample details` control; PCR, HI, Culture, and sensitivity
rows use the same progressive-disclosure pattern with test-appropriate compact
summary metrics. Severity color is limited to the status badge, border, and
interpretation note so alerts remain visible without overpowering the report.

Lab interpretation is deliberately a dashboard guardrail rather than veterinary
treatment advice. PCR positive rows are surfaced as alerts and Ct is shown as
load context because lower Ct generally reflects more target nucleic acid, while
lab/manufacturer cutoffs remain authoritative. ELISA positive samples are shown
as seropositive signals that must be interpreted with vaccine/exposure history;
high ELISA CV% is flagged for non-uniform flock response. HI stores a default
protective threshold by antigen family and flags low GM or low protected
percentage. Sensitivity reports summarize S/I/R categories and highlight panels
with no sensitive option or resistant-dominant patterns.

Dashboard shows a `Lab Analysis` sector directly under the cascade filters and
loads it by the selected customer and flock only, independent of the selected
hatchery. The sector shows report/test-type counts and group-level alert/watch
counts; sample-row severities are not added to these counters, preventing a
single multi-sera plate from appearing as dozens of warnings. When an ELISA
analyte has at least two canonical report dates, the sector adds a longitudinal
panel with selectable GMT, CV%, and positivity lines, house range shading,
latest-snapshot metrics, change callouts, and a house-by-date GMT/CV heatmap.
Pooled repeat plates remain visible as a separate dashed series but are excluded
from canonical house averages and row-level trend weighting. The sector then
shows the latest saved result groups with compact per-test metrics: ELISA
GMT/CV/positive rate, PCR positive count and minimum Ct, HI GM/protected
percentage, bacterial-culture positive/negative counts, and sensitivity S/I/R
counts. It remains visible with all-customer
or no-hatchery filters so breeder-farm lab results can be reviewed without
entering an operational hatchery scope. Dashboard Lab Analysis loading retains
up to 120 recent result groups so multi-date house trends are not truncated by
the previous 30-group cap.

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
- `dashboard_actions`: persistent dashboard findings/corrective actions scoped
  by customer and hatchery, with optional flock/session/panel source trace,
  owner, priority, lifecycle status, due date, observed timestamps, resolution
  evidence metadata, and offline sync state.
- Lab Analysis tables: `lab_analysis_reports` stores customer/flock/date report
  headers; `lab_analysis_groups` stores one ELISA, PCR, HI, or Sensitivity
  result group; and `lab_analysis_rows` stores the full sample, analyte, HI
  distribution, or antibiotic rows under each group.
- `photos`: local photo records tied to `sessionId`, `panelName`,
  `panelRowId`, and `fieldKey`, with upload status.
- `bmk_breeds` and `bmk_egg_breakout`: seeded benchmark reference data.
- `bmk_operational_standards`: seeded global operational BMK rows plus optional
  hatchery-specific override rows for station setup targets. Each row stores a
  source label, optional external `sourceUrl`, optional local
  `sourcePhotoPath`, and optional cloud `sourcePhotoRemotePath` for per-item
  citations.
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
builds unless the run explicitly sets `CHICKMARK_DEBUG_AUTH_BYPASS=false`; an
explicit debug-bypass logout clears that development identity for the current
session instead of immediately reactivating it.
Local fallback users are stored with ids prefixed by `local-`. Local fallback
auth remains available by default for non-release development builds, is
disabled by default for release builds, and can only be enabled in release with
`CHICKMARK_ENABLE_LOCAL_FALLBACK_AUTH=true`. New local fallback passwords use
v3 PBKDF2-HMAC-SHA256 hashes with per-password random salts and iteration
metadata. Legacy local tokens and v2 salted SHA-256 hashes are accepted only for
migration and are upgraded to v3 after a successful local login.
An explicit login attempt must verify the entered password through Supabase or
through an enabled local fallback account. A cached Supabase profile is not
accepted as proof of the newly entered password when the device is offline.
Startup may still resume a previously remembered, unexpired remote session from
secure local token storage without asking the user to sign in again.
The login identifier accepts either an internal user's email or an
admin-issued customer username. Customer usernames are case-insensitive and are
mapped internally to `<username>@customers.chickmark.app` for Supabase password
authentication; the synthetic email is not presented as a mailbox to the
customer.
The live Supabase Auth configuration requires at least 12 characters with
lowercase and uppercase letters, a digit, and a symbol; the registration form
enforces the same policy locally. Password changes require both a recent
reauthenticated session and the current password. HaveIBeenPwned leaked-password
checking is not available on the project's current Supabase Free plan, so the
security advisor retains that single plan-bound warning.
The login screen's Remember me option stores only the entered username/email in
shared preferences and forwards the remember-session choice into Supabase
sign-in. When Remember me is unchecked on a successful login, the saved
identifier is removed and the remote session is not persisted by the sign-in
request. The Remember me / Forgot Password row wraps on phone-width layouts
instead of overflowing.

Approved admins can open Settings > User access and create a customer account
without leaving or replacing their own session. The creation sheet requires an
existing customer assignment, display name, unique username, and a password
that matches the live 12-character complexity policy. The Flutter client calls
the `create-customer-account` Supabase Edge Function; that function verifies
the caller is an approved admin, creates a confirmed Auth user with the
server-only service-role key, and writes an approved `customer` profile linked
to the chosen `customer_id`. The `profiles.username` column has a
case-insensitive unique index and format constraint. The service-role key stays
inside the deployed Edge Function and is never bundled into the app. Username
accounts do not have a real recovery mailbox: Forgot Password directs them to
their ChickMark admin, and the admin can open that customer profile in User
access and set a new policy-compliant password through the separately verified
`reset-customer-password` Edge Function.

`CustomersProvider` owns customer, flock, hatchery, audit, visit-session, lookup,
and selected-customer state. It scopes data for customer-role users, supports
customer/flock/hatchery CRUD, and loads visit summaries for customer detail
views. Editors can delete a customer from the customer list card or customer
detail screen only after confirming a destructive dialog. Confirmed customer
deletion removes local visit sessions, station rows, linked photos, Govee
captures, lab-analysis reports, flocks, hatcheries, and the customer row, and
queues sync tombstones for the synced rows so Supabase is cleaned up on the next
startup/background sync. Customer-list deletes immediately run a foreground
sync attempt after the local cascade and show whether the cloud deletion
synchronized or remains pending because the device is offline or the remote
delete failed. Other devices apply the synced tombstones on their next
startup/background sync and remove the same customer graph locally.

`StartupSyncService` checks cloud tombstones and applies remote deletes before
bulk-uploading local customers, hatcheries, and flocks. This prevents a device
with stale local reference rows from recreating customers that another sync has
already deleted from the cloud. It pushes dirty audit sessions, panel rows,
Govee captures, dashboard actions, and Lab Analysis report/group/row tables,
then pulls the same optional shared tables when they exist remotely.

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
capture summaries loaded by the selected visit customer, hatchery, and date. It
also loads Lab Analysis dashboard summaries by customer and flock independently
from hatchery scope.

`LabAnalysisProvider` owns the standalone Lab Analysis screen state: scoped
customer/flock/date selection, saved report batches, and create/delete actions
for ELISA, PCR, HI, and Sensitivity result groups.

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
month, active flocks, last audit date, recently saved audits, and audit type
breakdown.

## 7. Persistence Summary

The app uses SQLite through `sqflite` at database version 55. The database file
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
Later additive upgrades create dashboard action rows and Lab Analysis tables
without resetting existing local data. Version 51 adds the persistence
foundation for poultry customer sectors, farms, houses, multi-house flock
placements, revision-safe Broiler daily evidence, versioned Broiler objectives,
operational concern state, diagnostic farm visits, probable-cause assessments,
corrective actions, and KPI-based effectiveness evaluations. Existing flock
rows remain valid: only flocks already linked to a hatchery audit are safely
backfilled as Breeder; other legacy flock sectors remain unset for later user
classification.

Version 52 adds the Telegram hatchery-agent data foundation. Local SQLite now
stores Telegram staff links with `pending`, `allowed`, and `revoked` states;
new staff links default to `pending` unless an admin explicitly allows them.
It also stores one agent-settings row, original submission metadata, bilingual follow-up
questions and answers, draft batches and rows, agent audit events, and approved
hatchery daily-record-shaped rows. The
repository can create a submission/batch/rows/questions/events graph in one
transaction, load or update default agent thresholds, list newest draft batch
summaries, list newest pending Telegram staff requests, update staff-link
approval decisions, load complete batch details, and find the previous approved
customer/flock/station/breed record before a hatch date. Every local repository
write is marked pending with dirty metadata.

Version 53 adds the schema-driven conversational intake graph:
`agent_intake_sessions` owns the current workflow state, resolved customer,
flock, hatchery, audit date, scope, machine identities, working values, and
versioned confirmation snapshot; `agent_intake_turns` preserves immutable
inbound and outbound conversation evidence; and `agent_intake_values` stores
the latest normalized value, source phrase, confidence, and any clarification
reason for each schema field. The three tables participate in normal
dependency-ordered startup push/pull sync.

Version 54 adds the persistence and authorization boundary for the unified AI
agent. Every Telegram staff link now carries an explicit `customer` or `admin`
access role; an allowed customer link must reference exactly one customer,
while an allowed admin link cannot carry a customer restriction. Existing
allowed links are preserved as explicit admin links during the additive
upgrade. The upgrade idempotently restores the v52 Telegram-agent and v53
conversational-intake prerequisites before creating unified-agent indexes and
guards. This also safely handles local databases whose version 53 originated
from the former flock-monitoring development line without deleting or
rewriting unrelated rows. Startup's additive surgical repair also restores the
current indexed farm and flock-placement columns when that former v53 schema is
encountered. The new `agent_conversations`, `agent_conversation_turns`,
`agent_tool_events`, and `agent_intake_visits` tables preserve free-form chat,
model/tool evidence, and a multi-station visit context. Intake sessions now
reference their visit, carry an optimistic row version, and may reference the
tool event that last changed them. Each deployed v53 intake is preserved and
backfilled into its own legacy visit under a deterministic staff/chat
conversation; no intake or confirmed summary is deleted or merged.

Conversation turns, tool events, and visit rows are authored by the Supabase
Edge agent. The Flutter admin app pulls these rows read-only in dependency
order and never pushes or tombstones them. Remote RLS exposes them only for
approved app-admin review and retains service-role Edge access. Database
guards reject invalid visit/customer relationships, protect a user-confirmed
summary from later mutation, and make completed tool-call evidence immutable.
One visit can contain multiple sequential confirmed station sessions, while a
partial unique index permits only one active station intake for that visit at
a time.

Version 55 widens the local conversational-intake scope constraint from the
original pooled/machine Pasgar scopes to every sampling layer used by the
station registry: pool, house, setter, hatcher, setter+hatcher, trolley, and
tray. The additive upgrade rebuilds only `agent_intake_sessions`, preserves its
rows and references, and recreates the active/review indexes and database
guards.

The unified-agent station registry foundation is generated from
`tool/agent_schema/station_registry.json`. The generator validates localized
names and aliases, unique schema identities, field/completion references,
validation metadata, and local/remote persistence mappings, then emits the
typed Dart and TypeScript contracts used by Flutter and Supabase functions.
Its first registry version exposes 18 Breeder hatchery modules across all nine
active panel tables: egg storage environment, egg shell temperature,
upside-down eggs, UV shell quality, egg weights, Pasgar, YFBM, chick vent
temperature, PM necropsy, culled-chick analysis, chick weights, fresh/candled/
residue breakout, setter environment and shell temperature, and hatcher
environment and vent temperature. These aliases are schema vocabulary for the
AI and are not backend intent triggers.

The Edge harness now resolves the authorized Telegram staff-link scope from
the database before any AI path can run. Customer links receive exactly their
assigned customer ID; explicit agent-admin links receive the current customer
catalog. Missing, revoked, malformed, or unassigned links fail closed. Flock,
hatchery, and customer authorization use indistinguishable `scope_denied`
results for unknown and out-of-scope identifiers so the model cannot probe
another customer's records.

The unified runtime exposes a typed tool catalog rather than database access.
The gateway rejects unknown tools, extra arguments, invalid types, oversized
strings, reads over 100 rows, and date windows over 366 days. It injects the
server-resolved scope plus conversation/visit IDs into each handler, limits a
turn to five tool calls, and records sanitized arguments, structured results,
status, duration, bounded access scope, and optimistic state versions through an
evidence port. Tool definitions and evidence never contain service credentials,
unrestricted table names, raw attachment bytes, or secret-shaped values.

Customer-data tools can now return the enforced customer's identity, flock
list, flock status/breed/sector/entry date, and an exact age calculated for the
query date. The model receives customer IDs only through scoped read tools, not
through its trusted prompt or scope summary. When a user supplies customer and
flock names, an exact Arabic-normalized resolver evaluates them together; a
unique flock can disambiguate duplicate customer names, while missing or
multiple matches return structured clarification candidates instead of choosing
an ID. Versioned station reads derive their table and selectable columns
only from the canonical registry, always inject customer scope, optionally
verify flock ownership, use inclusive bounded dates, keep nulls as null, and
return at most 100 records in stable date/ID order. Provenance reports the
schema, customer, flock, record date, fetch time, and fresh/stale/missing state
without estimating absent facts or revealing whether an inaccessible record
exists.

Audit discovery is a scoped, stable selection flow. `list_customer_audits`
defaults to 10 authorized recent audits for an allowed customer and optional
owned flock, accepts a limit of at most 20, and returns `truncated` when a
larger result exists or the bounded scan cannot prove source exhaustion. Its
numbered options are persisted in immutable tool evidence.
A later numbered reply calls `select_audit_option` with only a one-based
position from 1 through 20; the server uses the injected conversation ID to
load that conversation's latest successful audit-list snapshot, so a newly
inserted audit cannot remap an already displayed number. The selected opaque
audit ID is then revalidated through the current customer scope before its
summary is returned. The model never reconstructs or re-lists an ordinal
mapping.

Follow-up Hatch Analysis questions use the latest successful audit selection
or verified audit-summary event from the same conversation.
`get_selected_audit_breakouts` revalidates that audit against the current
customer scope, then reads only rows whose `session_id` and `customer_id`
match the selected audit from `fresh_egg_breakout`, `candled_egg_breakout`,
and `residue_breakout`. The bounded result exposes sample hierarchy, tray
size, infertile count/percentage, the breakout-stage percentages available for
that row, and residue hatchability/fertility/HOF/culled/dead percentages. It
returns at most 20 stable rows, omits absent measurements, and reports
truncation instead of substituting
a same-date or same-flock row from another audit.

Name text is never accepted in audit ID arguments; the model must resolve names
through the scoped customer/flock resolver before listing audits. Audit rows
are discarded unless embedded customer, flock, and hatchery relation IDs match
their foreign keys and the flock/hatchery owners match the audit customer.
Summary `findings_json` and `scorecard_json` decode only bounded valid JSON
arrays or objects; malformed, scalar, or oversized values remain null. Listing
orders date, creation time, and ID descending with nulls last. Listing,
selection, and detail lookup fail closed for missing, malformed, unknown,
inaccessible, changed-scope, or mismatched evidence without revealing whether
an out-of-scope audit exists.

Shared calculation parity vectors now verify the Dart and Edge implementations
of percent-of, sample CV, uniformity, Pasgar score, fertility, hatchability, and
HOF. Edge metric aggregation uses ratio-of-sums or sample-weighted means from
raw observed rows, reports its observation count, and returns null when no
valid evidence exists. Configured warning deltas also remain deterministic.

Generic station intake is now a durable, registry-driven state machine rather
than a fixed question sequence. A model-selected data-entry proposal records
only a pending action and cannot create a session until the user explicitly
confirms on a later turn; the proposal expires after five turns or 15 minutes.
After confirmation, the server resolves authorized customer, flock, hatchery,
date, layer, and machine context before opening the selected schema. One message
may supply several fields in any order. Static and sample-dependent limits are
validated against the complete message, accepted values retain their source
phrase and confidence, and uncertain or invalid values return structured
clarification needs without guessing.

The applicable-station catalog is resolved from the selected authorized flock's
persisted sector. It returns only matching registry schemas together with their
localized names, aliases, and valid sampling layers. The AI can therefore
interpret a selection by number, module name, Arabic/English alias, or natural
description without a phrase router or fixed scenario list.

The state machine does not interrupt after each accepted field. It creates one
backend-calculated, versioned summary only when every required field for the
station is present, and only that exact summary version can be confirmed.
Corrections invalidate the previous summary, optimistic row versions prevent
stale overwrites, and submission moves the station to admin review without
creating an operational panel row. Pausing, resuming, or cancelling preserves
the collected evidence, while sequential station sessions for the same
customer/flock/hatchery/date reuse one visit. Legacy Pasgar readers remain only
for compatibility with already-created rows; new intake semantics come from the
canonical `chicks.pasgar@1` registry schema.

All 18 registry schemas have matching Dart and TypeScript adapters. Each
adapter validates its current UI-equivalent required inputs, field types,
explicit-zero rules, static and dynamic limits, nested list/object values,
backend calculations, and allowlisted local/remote persistence mapping. The
same registry drives the AI's questions, the server-side summary, and the
generic Flutter admin review card.

The unified provider runtime now sends that state and the latest 20 bounded
conversation turns to one policy-guided Responses-compatible AI loop. The
model—not a backend phrase router—writes the normal Arabic, English, or mixed
reply and may request typed tools; each structured result is returned to the
same model turn before the reply. Calls execute serially, stop after five or
the 20-second turn budget, and preserve reasoning/function output items needed
by the provider protocol. Malformed and unknown calls never reach a handler,
tool data cannot add instructions or capabilities, and provider
unavailability returns an infrastructure status for the webhook boundary.
OpenRouter HTTP 402 fallback remains contained inside the provider adapter.
The policy distinguishes an informational flock question from a request to
record operational data: asking to review, explain, or compare existing flock
data uses scoped read tools and cannot by itself propose an intake. Intake is
proposed only when the user expresses an intent to add, record, submit, correct,
or update data.

The live Telegram webhook routes every authorized text, photo, PDF,
spreadsheet, and document turn through this same runtime, including greetings,
questions, possible data-entry requests, active intakes, and legacy open-draft
contexts. There is no deployed phrase-classifier branch for normal replies.
Downloaded attachment bytes and trusted Telegram metadata are supplied to the
model in provider-native image or file input blocks. The webhook sends the
model's final response as Telegram-safe plain text; visible Markdown emphasis
and code markers are removed at the transport boundary. Only a bounded
bilingual infrastructure retry is fixed at that boundary.

Each accepted Telegram update is deduplicated before mutable staff metadata or
conversation state is changed. Its inbound turn receives a monotonically
allocated index that is unique inside the conversation, and the exact inbound
evidence is persisted before the runtime starts. The corresponding assistant
turn is stored with pending delivery before Telegram is called, then marked
delivered or failed. A Telegram retry sees the original inbound update and
cannot rerun the model or duplicate a delivered reply. Provider or tool failures
never fall through into a second conversational implementation.

The `chicks.pasgar@1` schema requires sample size,
reflexes, beak, navel, belly, leg, and feather-development counts, while
reusing the app's Pasgar percentage and score calculations. Approved staff may
provide several values in either Arabic or English, in any order. Valid values
are saved without a confirmation interruption; an uncertain, ambiguous, or
invalid value produces one focused clarification and is never silently guessed.
Zeroes must be explicit, including an explicit "all remaining are zero"
instruction. The bot asks only for missing context or measurements, and a
normal mission question can interrupt an active intake without changing its
data.

Only after a whole station schema is complete does the bot send one localized,
versioned summary and ask the staff member to confirm it. A correction updates
the relevant values and generates a new complete summary; only an affirmative
answer to the current summary moves that station to admin review. The deleted
Pasgar-specific interpreter/controller is no longer a callable conversation
path.

Agent Monitor lists all confirmed generic station intakes separately from
legacy hatchery drafts. Approved admins can inspect the registry-driven context,
values, calculated results, schema version, language, scope, and expandable
conversation evidence; edit a typed scalar or JSON list/object value; reject
with a reason; or approve into a new audit or a matching existing audit. The
original user-confirmed summary remains immutable evidence when an admin makes
a correction; approval validates the reviewed working values against the same
schema.

Final approval calls the authenticated `approve-agent-intake` Edge Function
with the expected summary version. The function authenticates the caller,
requires an approved app-admin profile, revalidates context/schema/values and
any target audit, derives only registry-allowlisted panel columns, then invokes
a service-role-only atomic RPC. The RPC locks the intake and target audit,
writes the proper allowlisted panel table, updates selected/completed stations,
and records the approved audit/panel IDs idempotently. Customer users and
ordinary authenticated clients cannot execute the commit function directly.

The `telegram-hatchery-agent` Supabase Edge Function now receives Telegram POST
webhooks and validates Telegram's secret-token header before reading the
payload. It accepts only pre-authorized, non-revoked staff links, refreshes the
known staff member's Telegram metadata, honors the remote pause setting, and
treats a repeated Telegram update as an idempotent success. Unknown or revoked
staff do not create a submission or draft. Unknown staff are inserted or
refreshed as pending `telegram_staff_links` rows and receive an Arabic-only
message telling them that admin approval is required. Existing pending staff
receive the same waiting message. Revoked staff receive an Arabic-only
rejection.
Telegram exposes numeric user IDs, chat IDs, usernames, and display names to the
bot; it does not provide a phone number unless a user explicitly sends a contact
message. Accepted text, photo, PDF, spreadsheet, and document turns create
durable unified-conversation evidence; Telegram file IDs are retained as source
references and file bytes are downloaded only inside the backend. The AI
decides from the whole turn whether it should answer a scoped flock question,
ask a natural clarifying question, propose a station intake, or continue the
current intake. It cannot create an intake from inferred intent alone: the
generic intake tool requires the later explicit confirmation described above.
Unknown, pending, or revoked senders still receive only the access-flow
messages and cannot invoke the AI runtime.

The earlier draft-extraction compatibility helper uses a deterministic
labeled-text parser when text clearly provides hatchery fields as
`Label: value` lines. This allows old draft workflows and tests to reconstruct
their original extraction. Its structured extraction uses either the OpenAI
Responses API or the OpenRouter
Responses-compatible API with a strict JSON schema, server-only credentials, and
input appropriate to the Telegram source. `AI_PROVIDER`
can explicitly select `openai` or `openrouter`; otherwise the backend uses
OpenRouter when `OPENROUTER_API_KEY` is present and falls back to OpenAI. The
model can be set with `OPENROUTER_MODEL`, `OPENAI_MODEL`, or shared `AI_MODEL`;
when OpenRouter returns HTTP 402 for a configured paid model, the backend
retries once with `openrouter/free` for testing continuity. Without an explicit
OpenRouter model, testing deployments default to `openrouter/free`.
The prompt supports English, Arabic, and mixed tables, requires nulls for
unknown values, and forbids guessing customer, flock, station, or breed names.
One draft batch groups every returned row. The backend calculates hatchability
as total production divided by positive eggs placed times 100, stores the raw
structured extraction, and marks invalid-count or unresolved rows for review.
This extractor remains available for existing draft records and compatibility
tests; it is not the live authorized Telegram conversation router.
Before storing rows, the backend loads existing customers, flocks, and
hatcheries and compares extracted identity names using Unicode-normalized,
case-insensitive exact matching with collapsed whitespace. A uniquely matched
customer and customer-scoped flock are stored as their real IDs; an omitted
customer can also be derived from a globally unique exact flock match. A
resolved customer with exactly one hatchery receives that hatchery ID.
When duplicate customer names exist, an exact flock match may disambiguate
them only if that customer/flock combination is unique. Other duplicate,
conflicting, or missing customer/flock matches and multiple customer
hatcheries are never guessed: their affected IDs remain null and the draft
stores identity-resolution warnings and Arabic Telegram follow-up questions.
When the backend can safely derive relevant choices, such as known flocks for
the resolved customer or multiple hatcheries for the customer, the question
includes a numbered Arabic choice list. Staff can answer with the option number
instead of retyping the full name. If the
hierarchy lookup itself is unavailable, extraction still produces editable
unresolved drafts with a distinct lookup-unavailable warning instead of
claiming that the names do not exist or discarding the submission.

Parseable extracted dates are normalized to the submitted calendar date at UTC
midnight before persistence and text-date comparison. For a resolved
customer/flock/station/breed/hatch-date key, the backend loads the latest
earlier approved hatchery daily row and recalculates both current and historical
hatchability from their production and egg counts; a legacy stored historical
percentage is only a fallback when its counts are invalid. An absolute change at
or above `hatchability_warning_threshold_points` is stored as a
`historicalChange` review warning. The setting defaults to 3 percentage points.
A review warning routes the draft to `needs_admin_review`.

Structured extraction includes nullable flock age. A positive extracted age is
stored as proposed draft metadata; otherwise a uniquely resolved flock entry
date and the row hatch date derive completed whole weeks. For a rising
historical result, the backend loads the nearest breed BMK age and stores
informational `bmkContext` when the rise remains at or below that BMK, or
`missingBmk` when no benchmark exists. The nearest lookup compares the closest
available BMK at or below the flock age with the closest one at or above it, so
it does not depend on an arbitrary query page. When no positive flock age can
be extracted or derived, the backend stores an Arabic staff-facing
`flockAgeWeeks` question for that row, adds `missingFlockAge` context when a
rising comparison requested BMK, and keeps the row in `needs_review` while the
submission and batch wait in `waiting_for_staff_answer`.

Configured minimum confidence selects `draft_ready` versus
`needs_admin_review`; extracted and deterministic missing questions are stored
and sent to the same Telegram chat as clean Arabic prompts without exposing
draft identifiers or internal field keys when only one submission is waiting.
Historical/BMK enrichment is
owned by the Edge Function because it is the authoritative ingestion boundary
with current cloud history and reference data. Startup pull preserves the
stored warning evidence without locally recomputing or dirtying the row; local
post-pull enrichment is deliberately avoided because an offline client can
have stale history/BMK data and a pull-triggered write would risk sync conflicts
or replay loops. Processing failures are persisted as `failed` and acknowledged
to Telegram so the durable submission remains available to an admin.

The legacy draft-answer compatibility operations can check text replies against
open questions for the same staff link and Telegram chat. A single
open question accepts a direct answer; multiple questions use deterministic
row/field ordering and require numbered, row/field-referenced answers. If a
question lists choices, a numbered reply such as `2: 1` stores the first
displayed choice for question 2. Numbered answers accept either punctuation
(`1: 30`) or a natural space-separated form (`1 30`). When more than one draft is waiting, the
Arabic prompt separates the pending requests by request number. Ambiguous,
duplicate-target, out-of-range, or invalid typed replies leave all affected
questions open and return an Arabic clarification. In the live webhook, legacy
open questions are exposed only as state/tool data to the unified runtime
instead of taking over inbound routing. Greetings, thanks, help requests,
ordinary questions, and data-bearing answers therefore remain one AI
conversation while the underlying legacy draft is preserved.
The unified AI must explicitly call `list_legacy_draft_questions` for one
submission before those questions are returned, and it must provide both the
submission and question identity to `answer_legacy_draft_question`. Ordinary
messages never auto-bind to an old question.
Resolved replies store `answer_text`, `answered_at`, and the `answered` status.
Supported hatchery fields are type-checked and copied to the matching draft
row, with hatchability recalculated after count changes; unsupported fields or
missing row links retain the answer for admin review. Partially answered
submissions stay `waiting_for_staff_answer`. Fully answered submissions and
batches move only to `needs_admin_review`, and their rows remain
`needs_review` until explicit admin approval. Successful answer webhooks also
write a service-role-only Telegram update receipt so a replay is acknowledged
idempotently instead of becoming a new submission; this backend receipt table
is intentionally excluded from the app's mirrored sync graph.

The Edge Function reads `TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET`,
`AI_PROVIDER`, `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `OPENAI_API_KEY`,
`OPENAI_MODEL`, `AI_MODEL`, `SUPABASE_URL`, and `SUPABASE_SERVICE_ROLE_KEY`
only from its server environment. Either `OPENROUTER_API_KEY` or
`OPENAI_API_KEY` must be present for extraction. Deployment must disable
Supabase JWT verification for this signed webhook; the function itself
authenticates Telegram's secret-token header.

Only approved admins have an `Agent` main-shell destination before Settings.
Auditors and customer-role users do not receive that destination. The screen
and `AgentMonitorProvider` repeat the approved-admin check before loading or
mutating the offline agent mirror, so unauthorized users cannot create pending
local agent-setting writes that remote RLS will reject. For approved admins,
the Agent Monitor loads the locally mirrored agent setting and newest draft
batches plus pending and allowed Telegram staff links, automatically selects
the newest available batch, and preserves the selected batch across refreshes
while it remains available. Admins can refresh the monitor, approve or reject
pending Telegram staff access, and pause or resume Telegram ingestion through
the persisted agent setting. Approval opens an assignment sheet instead of
granting access immediately: the default customer role requires one customer
selection, while the explicit agent-admin role grants all-customer access and
cannot carry a customer restriction. Allowed Telegram users appear with their
enforced scope and can be reassigned or revoked. The model, repository,
provider, SQLite checks, and Supabase constraints all repeat the role/customer
consistency rule. Rejection or revocation changes the link to `revoked`. The
original unauthorized message remains unprocessed, so staff must resend the
hatchery data after approval.

The responsive monitor presents submission cards beside draft detail on wide
screens and above detail on narrower screens. Pending Telegram access requests
appear above the draft workspace with display name, username, Telegram user ID,
chat ID, request time, and approve/reject actions. It shows the original Telegram
text or file reference, source type, submitter identifier, submission and row
statuses, questions and staff answers, extracted hatchery values, calculated
hatchability, extraction confidence, historical/BMK warning messages, and
agent audit history. Confidence and biological/historical warnings are
displayed separately. Edit, approve, and reject controls are available only to
signed-in admins. Admins can correct every extracted business field before
saving a draft row, reject a row with an optional reason, or approve a complete
row. Approval requires resolved customer and flock IDs plus station, breed,
eggs placed, hatch date, total production, and hatchability. It atomically
creates one pending-sync `hatchery_daily_records` row, links the approved draft
row to it, and records the approving admin in an audit event. Rejection creates
no final record and retains its reason in the audit trail.

The draft editor loads the locally mirrored customer/flock/hatchery catalog and
uses customer-scoped selectors instead of editable raw UUID fields. Existing
unresolved drafts preselect a customer and flock only when their extracted
names have one normalized exact match; a sole hatchery is selected
automatically. Changing the customer resets and scopes the flock and hatchery
choices, while ambiguous names remain visible as extracted hints until an
admin selects the intended records. Persisted links that are temporarily absent
from the local mirror appear as unavailable local choices and remain unchanged
when an admin saves an unrelated edit.

After each row decision, a batch remains partially approved while unresolved
rows coexist with approved rows, becomes approved when all rows are resolved
and at least one was approved, becomes rejected when every row was rejected,
or requires admin review when rejected and unresolved rows remain without an
approval. Draft edits, decisions, final records, batch status changes, and
audit events are all marked for sync. Startup sync pushes and pulls the eight
hatchery-agent operational tables after their customer, flock, and hatchery
dependencies, using the operational dirty-row and conflict handling.
Agent Monitor labels, statuses, empty/error states, and dynamic row/Telegram
identity labels are available in English and Arabic.

The hatchery-agent rule service calculates hatchability as total production
divided by eggs placed times 100 only when both counts are present, production
is non-negative, and eggs placed is positive. It emits a review warning when
the absolute change from the previous approved comparable hatchability meets
or exceeds the configured percentage-point threshold, allowing for normal
floating-point representation error at the boundary. For rising results, a
breed BMK at or above the current result adds informational context that the
increase may be consistent with BMK; an unavailable BMK or missing/nonpositive
flock age adds an informational missing-data warning instead. The rule engine
retrieves the previous comparable record using the exact
customer/flock/station/breed key, looks up BMK using a positive flock age in
days, and records the selected BMK row's age in warning context. The Edge
Function mirrors this deterministic contract at write time and serializes the
same warning keys consumed by the local app. The local engine remains available
for local/admin re-evaluation but is not a post-pull sync mutator. Serialized
warnings reject unknown kind or severity values rather than silently
reclassifying them.

Tables created by the current database helper include:

- `users`
- `customers`
- `flocks`
- `bmk_breeds`
- `bmk_egg_breakout`
- `bmk_operational_standards`
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
- `dashboard_actions`
- `lab_analysis_reports`
- `lab_analysis_groups`
- `lab_analysis_rows`
- `sync_tombstones`
- `sync_conflicts`
- `customer_sectors`
- `farms`
- `houses`
- `flock_placements`
- `broiler_daily_records`
- `broiler_daily_record_revisions`
- `daily_record_sources`
- `broiler_daily_events`
- `broiler_target_profiles`
- `broiler_target_rows`
- `performance_alert_rules`
- `performance_concerns`
- `farm_visit_sessions`
- `farm_visit_houses`
- `visit_investigations`
- `visit_findings`
- `cause_assessments`
- `corrective_actions`
- `action_kpi_evaluations`
- `telegram_staff_links`
- `agent_settings`
- `agent_submissions`
- `agent_questions`
- `hatchery_draft_batches`
- `hatchery_draft_rows`
- `hatchery_agent_audit_events`
- `hatchery_daily_records`
- `agent_intake_sessions`
- `agent_intake_turns`
- `agent_intake_values`

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
`govee_daily_captures` belongs to a customer and hatchery. Lab Analysis reports
belong to a customer and flock; lab groups belong to a lab report, customer, and
flock; and lab rows belong to a lab group and report.
For performance monitoring, a customer may enable multiple poultry sectors,
each farm has exactly one sector, houses belong to farms, and a flock may span
multiple house placements. A partial unique index prevents two active flock
placements in one house. One stable Broiler daily record exists per
placement/date; source corrections are stored as numbered revision rows rather
than overwriting earlier evidence. Visits, findings, cause assessments,
corrective actions, and action KPI evaluations use farm-specific tables and do
not overload hatchery `audit_sessions` or `dashboard_actions`.
Hatchery-agent questions and draft batches belong to one submission, draft rows
belong to one batch, agent audit events retain their submission and optional row
links, and final-shaped hatchery daily rows require customer/flock/station/breed
identity. The matching Supabase migration uses snake_case tables, validates
flock and hatchery customer scope, enables RLS on every agent table, exposes
authenticated reads/writes only to approved admins, and leaves backend
service-role access available to the Telegram hatchery-agent Edge Function.
Conversational intake turns and normalized values belong to one intake session.
The intake context links to the customer, flock, and hatchery hierarchy, while
approved intake rows link back to the resulting audit session and Chick Quality
panel row. Remote RLS limits intake review reads and writes to approved admins;
the Edge Function retains service-role access for Telegram ingestion.
The backend-only `telegram_agent_update_receipts` table records processed
Telegram answer updates for idempotency and is intentionally excluded from the
offline app sync graph.
The hierarchy repository saves active/inactive customer-sector membership,
sector-filtered farms, farm houses, and flock placements with offline dirty
metadata. Creating a new Broiler flock and all selected house placements is one
transaction, so a placement validation or active-house conflict cannot leave a
partially created flock. Existing legacy flock models continue to load without a
farm or sector; new performance flocks can retain farm, sector, sex-profile,
target-profile, and production-phase context.
Customer detail exposes this hierarchy through a Structure tab. Editors can
enable Breeder, Broiler, and Layer together, add farms using exactly one of the
customer's enabled sectors, and add houses beneath each farm. Disabling a
sector keeps its membership history inactive and prevents new farms from being
assigned to it. Hatchery management is available only while Breeder is enabled;
the Hatcheries tab otherwise explains how to enable the required sector. The
main shell exposes the Broiler Performance workspace to approved staff without
changing the customer-role Dashboard-and-Settings destination set.
The Broiler objective catalogue contains versioned day 0-56 as-hatched, male,
and female profiles for Ross 308 / Ross 308 FF, Indian River / Indian River FF,
Arbor Acres Plus / Arbor Acres Plus S, Hubbard Efficiency Plus, and Cobb500.
Every official row retains its source title, publication version, official URL,
units, and metric-method notes; Ross 308 AP is not included. Source-absent values
remain null. Hubbard water targets are derived only on its as-hatched profile
from the published daily feed objective multiplied by 1.70, with that method
stored on each applicable row. Administrators can clone a profile into an
inactive custom draft, replace the draft's rows, and activate it as a new
version. Activation deactivates the previous matching version without changing
its historical row set, so flocks that reference the older profile remain
reproducible.
Broiler daily entry uses one stable record per house placement and logical date,
with every submission stored as a numbered immutable revision. Corrections add
a revision and move the stable record's current pointer instead of overwriting
earlier farm evidence. Each revision can retain reported/entered/reviewed/
verified provenance, population changes, mortality causes, feed, water,
weighing samples, environment, health facts, typed operational events, and
source-document metadata. Validation rejects negative facts, inconsistent
closing-population arithmetic, corrections without a reason, and verified rows
without verifier metadata before any transaction is written. The repository
also exposes the current placement/day value, previous-day value, complete
revision history, and a house-by-house flock entry grid.
The pure Broiler KPI calculator derives local-calendar flock age, average live
birds, daily and cumulative mortality, livability, feed and water per live bird,
water-to-feed ratio, cumulative feed per placed bird, weight gain, sampled
uniformity and CV, target deviations, and mortality trend direction. Expected
cumulative feed is adjusted by each day's actual average live population before
comparison with actual feed. Actual FCR is labeled estimated and is withheld
with a specific missing-data reason when live population, current weight,
placement weight, or cumulative feed is unavailable. EPEF is calculated only
after cycle completion is explicitly confirmed; unvalidated final-weight and
final-FCR projections are not produced.
The Broiler manual quick-entry screen follows Customer → Broiler farm → flock →
date selection and loads every active house placement together. Each house card
keeps previous-day and target context read-only while today's draft remains
separate, then places population, feed, and water before expandable weight,
environment, events, mortality causes, and source-document sections. Wide
screens use a two-column house grid and narrow screens use a single list.
Saving validates each started house independently: valid houses append their
revision, invalid house drafts remain editable, and a per-house summary reports
what still needs attention. Corrected entries expose and require a correction
reason.
Operational alert rules are separate from genetic objectives. Seeded defaults
cover sustained weight and mortality deviations plus mortality/population
mismatches, decreasing cumulative feed, unexplained water changes, repeated
identical values, implausible weekly weight change, and extended zero mortality.
Customer rules override the matching global metric rule. Evaluation requires
the configured number of valid observations, records structured evidence and
recommended investigation keys, and never treats null data as a performance
loss. A detected scope/rule/metric combination updates one persistent open or
monitoring concern instead of creating dashboard duplicates. Resolution and
dismissal retain explicit user evidence, and a later detection creates a linked
recurrence.
The Broiler Performance workspace follows Customer → Broiler farm → flock and
an explicit date range. It aggregates the current revision from every selected
flock house into immutable view snapshots and presents Current status, Trends,
Active concerns, and Audits and corrective actions. Current metrics never
render missing data as zero; they show the calculator's missing-data reason.
The context strip distinguishes farm-reported data from its current
entered/reviewed/verified/corrected state and labels the exact target
publication. Trend cards use valid daily values from the selected period.
Changing scope or date range rebuilds the snapshot, and returning from manual
quick entry refreshes it from SQLite.
Farm visits use a generated briefing snapshot that freezes the concern ids,
performance evidence, target/rule versions, and suggested investigations at
planning time. A visit selects one or more houses and can add manual
investigations without mutating that original briefing. Investigations retain
their source-concern link, house/location, origin, lifecycle status, and result.
Visit findings can store measurements, structured observations, staff
explanations, and attachment references. Cause assessments link the findings
back to a concern and retain supporting and conflicting evidence; a newly saved
assessment remains `suspected` until a user explicitly changes it to
`probable`, `confirmed`, or `ruled_out`.
Corrective actions link a performance concern to the originating visit and
optional cause assessment, with an owner, due date, implementation confirmer,
completion evidence, and one or more KPI definitions. Each KPI definition
freezes its baseline window/value, target rule/value, evaluation scope, and
future evaluation window when the action is issued. Effectiveness uses the
latest valid in-scope observation only after implementation is confirmed and
the complete evaluation window is available. It reports effective when the
target is met, partially effective when the KPI moved toward the target, and
ineffective when it did not; incomplete or insufficient evidence remains
explicitly not evaluated with a reason. Calculated results are persisted only
through an explicit evaluator action.
The diagnostic visit screen renders the frozen daily briefing as read-only
evidence, then keeps visit-only investigations, measured findings, staff
explanations, and attachment counts separate from daily entry. Users can add
manual investigations and findings, complete investigation results, and
explicitly change a cause among suspected, probable, confirmed, and ruled out.
The corrective-action screen supports issuing an owned action with a KPI
baseline/target/evaluation window, confirming implementation, reviewing
before/target/after evidence, and explicitly recording the effectiveness
decision and reason.

Repository upserts avoid SQLite `REPLACE` for parent tables with children.
Customers, flocks, hatcheries, panel rows, pulled Govee captures, dashboard
actions, and pulled Lab Analysis rows use
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
`failed`. Egg Quality UV tray captures, EST/CVT evidence, Chicks YFBM,
PASGAR, PM necropsy, Hatch Analysis breakout, Setter, and Hatcher evidence
photos create local `photos` rows tied to their owning panel row and field key.
Hatch Analysis breakout photo rows use the active breakout table
(`fresh_egg_breakout`, `candled_egg_breakout`, or `residue_breakout`) instead
of a generic station default, and each item uses its own field key and
sample-plus-metric row id. Dashboard Scopes aggregates all supported breakout
item photo field keys plus legacy `breakout_photo` / `photo` rows, de-duplicates
their paths, and shows the combined evidence in the recorded breakout type's
existing photo grid.
Photo sync uploads local and failed photos when
Supabase is available,
skips missing files, and fails files larger than 5 MB so failed uploads retry on
later sync runs. Uploaded photo rows store
non-public `supabase://photos/...` storage references by default; public storage
URLs are only written when the build explicitly sets
`CHICKMARK_ALLOW_PUBLIC_PHOTO_URLS=true`. Startup sync also downloads pulled
remote photo rows from Supabase storage into the app documents directory, then
updates the local `photos.filePath` to the downloaded file so dashboard and
photo-grid readers can show evidence captured on another device. Flutter Web
keeps pulled remote references because it has no app documents directory; photo
grids, EST evidence thumbnails, and the fullscreen viewer resolve private
`supabase://photos/...` references to signed storage URLs when rendering. If a
native download fails, the remote reference is kept so later sync runs can
retry. Photo
tombstone sync removes matching Supabase storage objects before deleting remote
`photos` metadata rows, so deleted evidence is removed from other devices and
the backing bucket.

Before checking cloud availability, downloaded-photo sync reconciles persisted
local photo paths against the current app documents directory. If an iOS
application-container path has changed but the same filename exists in the
current documents directory, the `photos.filePath` row is repaired locally and
works offline. During cloud pull, an existing local path is preserved only when
it points to a non-empty file; a missing local file yields to the incoming
remote reference so the normal download pass can restore it. If startup or
manual sync finishes while Dashboard is already mounted, Dashboard refreshes
its main and Scope providers so downloaded photo paths replace stale paths
already cached by the selected flock view.

The Egg Storage dashboard EST evidence card reads photo rows from the synced
`photos` table for the latest egg-storage session. It accepts both current
`shell_temp_<grid point>` field keys and generic grid-point keys such as
`front_top`, so cloud-pulled evidence rows created by either capture path can be
mapped back onto the 9-point dashboard grid after the file is downloaded.

Supabase sync is best effort and offline-first. `StartupSyncService` pushes
local customers, hatcheries, flocks, audit sessions, panel rows, Govee captures,
photo work, and tombstones in dependency order, then pulls shared data back into
local repositories in the same parent-before-child order. Removed legacy tables
are not pushed or pulled. It keeps newer local session, Govee, and panel rows
when a pulled remote row has an older or invalid `updatedAt`. Local deletes
create `sync_tombstones`; startup sync uploads those tombstones, deletes remote
rows child-before-parent, marks successful tombstones synced, and applies remote
tombstones locally so another device reload removes stale rows. Customer deletes
queue child tombstones for station panel rows, photos, audit sessions, Govee
captures, flocks, and hatcheries before the customer tombstone, avoiding orphaned
cloud rows even when local SQLite cascade removes the children immediately.
The local tombstone repository can read and write both current camelCase
columns (`syncedAt`, `deletedAt`) and legacy snake_case columns (`synced_at`,
`deleted_at`), so an older browser SQLite/IndexedDB cache cannot break manual
or startup sync and hide pulled agent drafts.
Customer-role startup and background sync runs are explicitly pull-only: they
skip local uploads and tombstone writes, then download only the tenant rows
allowed by Supabase RLS. A missing user identity also defaults to pull-only
instead of enabling writes.
Supabase derives each new tombstone's customer from the still-existing target
row before remote deletion and snapshots the approved users authorized for that
customer. RLS exposes the deletion event only to that audience (or an approved
admin), preventing one tenant's tombstones from deleting another tenant's local
cache. Historical tombstones that predate customer scope remain admin-only.
`BgSyncService`
runs this sync after the shell starts and reports failure as offline data
available. Startup and background sync can surface a Home-screen cloud notice
for sessions and other records pulled from another device after the local
database has previously synced. A successful foreground `Sync Now` action in
Home or Settings acknowledges that notice so it disappears after the user
manually syncs; offline or failed sync attempts leave the notice intact. The
Flutter Web sync path pulls photo metadata but skips the native-file photo
cache/upload pass, because browsers do not expose an application documents
directory. This keeps Supabase row sync successful on web while preserving
remote photo references; dashboard photo renderers turn those references into
short-lived signed storage URLs. The authenticated shell also requests a
debounced sync after local customer,
hatchery, flock, audit-session, or panel writes, whenever connectivity changes,
and whenever a mobile/desktop app resumes. Concurrent requests share one sync
pass and a write that lands during that pass schedules one retry. Customer,
hatchery, and flock pushes use strict response verification so a database
trigger or policy cannot silently cancel a parent insert while the UI reports
it as uploaded. Before Supabase upserts, the client strips device-local sync
bookkeeping fields (`syncStatus`, `dirtyAt`, `lastSyncedAt`, and `syncError`)
and then converts business keys to the remote snake_case schema, preventing
local retry metadata from forcing a rejected camelCase fallback payload.
Production no longer installs the obsolete
`customers_keep_only_ghareeb` trigger; multi-customer inserts are supported and
existing device-local rows retry on the next automatic or manual sync.
The generic operational sync adapter recognizes and synchronizes the eight
hatchery-agent tables after the customer/flock/hatchery dependency graph.
The app assumes Supabase tables and storage are protected by project
RLS/storage policies for approved authenticated users and their customer scope.
The private `photos` bucket authorizes audit evidence through its audit-session
path and authorizes Lab Analysis PDFs either through the customer ID in the
standard `lab_analysis_reports/<customerId>/...` path or through an authorized
Lab Analysis report row that references the exact storage object. This keeps
signed PDF viewing and replacement customer-scoped without opening the bucket.
Authorization helpers live in a non-exposed private schema; approved status is
required for admin privileges, direct execution of trigger functions is
revoked, and the anonymous database role has no public-table CRUD grants. The
client only ships a publishable key and never needs service-role access. Debug
sync logs are sanitized and do not print stack traces, tokens, row payloads, or
raw BLE bytes. Shared debug logging redacts JWTs, Supabase publishable/secret
keys, and token/password/API-key values in query/form and JSON-style messages
before printing in debug builds.
The tracked-file secret scanner also rejects Telegram bot-token-shaped content.
No Telegram bot token is stored in the app, migration, tests, or documentation.

Govee place captures are persisted as one completed daily capture row per
customer, hatchery, place, machine, and date. The row stores Temp/RH summary
fields and the representative LTTB chart points in `chartPointsJson`; the app no
longer writes separate generic Temp/RH session or reading rows.

Thermometer OCR is no longer used for EST/CVT capture. Egg Storage EST, Setter
EST, Chicks CVT, and Hatcher CVT each expose a local `°F` / `°C` selector that
defaults to Fahrenheit. Grid values, targets, summaries, validation colors, and
manual entry use the selected display unit. The selected unit is persisted with
the saved readings, so a reading entered in `°C` is saved and later displayed as
`°C`, and a reading entered in `°F` is saved and later displayed as `°F`.
Legacy plain reading JSON without explicit unit metadata falls back to its
historical storage unit: Egg Storage EST is treated as Celsius, while Setter
EST, Chicks CVT, and Hatcher CVT are treated as Fahrenheit. Dashboard EST
evidence tiles and summaries display the saved unit, while threshold checks can
convert internally only for status comparison.

Guided temperature capture uses the same 9-point Front/Middle/Back by
Top/Middle/Bottom grid as the station forms. The first open point is highlighted,
the auditor can tap any grid cell to jump, the footer keeps a primary `Capture`
action, and `Done` sits in the top-right app bar action. For each point, the
auditor captures a photo, then types the reading manually against the attached
photo; after capture, the manual reading field receives focus automatically.
The custom mobile keypad uses a check/done action for this single entry field
instead of grid-navigation arrows. Photo-backed saves stage the captured image as
evidence, manual entry records the typed value, and saving advances to the next
open point. A compact recorded-photo strip under the camera preview shows the
current photo count and thumbnails for points with evidence; tapping a thumbnail
jumps back to that point. Retake marks the current saved point as ready for a
fresh capture, shows a retaking state for that point, and lets the attached photo
and reading be replaced. Dirty-only readings and photo paths are returned to the
caller, which continues to update the station draft, averages/CV, JSON photo-path
maps, and local `photos` rows for photo sync. The station-screen grids are
display/edit surfaces: cells show the saved reading plus evidence thumbnail when
present, and capture-flow grid cells show a small photo badge when evidence is
already attached. Tapping a cell opens or moves the full-screen capture flow
focused on that point so the attached photo and reading can be replaced through
the same save path. Photo pick/save/delete failures keep recoverable return
behavior and emit debug logs in development builds.

## 8. Known Technical Debt

- Several station screens still use legacy-named `AuditModel` fields as
  in-memory form state. Save/load persistence converts those drafts to panel
  rows instead of writing legacy audit tables.
- The legacy single-station flow is still present in code alongside the newer
  visit/session flow.
- `DiagnosticEngine.evaluate` is a placeholder that returns no findings.
- Visit-session scorecards use persisted JSON only when present; otherwise they
  use fallback threshold heuristics in `VisitSessionSummary`.
- Normal app startup does not seed or rewrite dashboard demo data. Tests that
  exercise the legacy dashboard fixture may opt in explicitly; that fixture
  keeps `الغريب` plus one dashboard test customer and creates five-reading
  Govee captures for its temperature scopes.
- Supabase sync is best effort and failures are logged/debugged rather than
  surfaced as blocking workflow errors.
- Govee place names still share the `TemperaturePlace` enum while the active
  persistence path is the standalone Govee workflow.

## 9. Change Log

- 2026-07-30: Made the SQLite v54 unified-agent migration re-establish its
  additive v52/v53 table prerequisites before creating intake-session indexes.
  This preserves existing local data while repairing databases whose schema
  version 53 came from the former flock-monitoring development line. Surgical
  repair now adds that line's missing indexed farm and flock-placement columns
  before rebuilding current indexes. Normal app startup no longer injects the
  rejected dashboard demo fixture into the user's local database.
- 2026-07-29: Hardened the SQLite v55 agent-intake rebuild by temporarily
  removing unified-agent guards before replacing the session table, then
  restoring them once the schema is stable. Added missing flock sync columns
  required by the v51 poultry hierarchy repository and completed Arabic
  coverage for the generic Agent Monitor review workflow.
- 2026-07-28: Fixed selected-audit Hatch Analysis follow-ups in the Telegram
  agent. Infertile-egg and breakout questions now read the three breakout
  panel tables by the exact persisted audit session and authorized customer,
  instead of falling back to the audit header or an unsafe date-range search.
- 2026-07-28: Exposed scoped audit browsing to the unified Telegram agent.
  Authorized users receive numbered choices from a bounded page of recent
  audits (default 10, maximum 20); `truncated` signals either a larger valid
  result or that the 500-row bounded scan could not prove exhaustion. The
  selected audit is retrieved in a second opaque-ID summary call. Name text
  remains forbidden in ID arguments, while list/detail denials stay
  indistinguishable for unknown and out-of-scope records.
- 2026-07-28: Added scoped customer/flock name resolution to the unified
  Telegram agent. Duplicate customer names can now be disambiguated by an exact
  flock-name match, internal IDs are no longer injected into the model prompt,
  and the policy requires one clear question per reply, safe handling of
  ambiguous yes/no answers, flock resolution before hatchery/machine context,
  and consistent Arabic hatchery vocabulary.
- 2026-07-28: Completed the registry-driven agent implementation for all 18
  hatchery modules. Generic Dart/TypeScript adapters now validate nested and
  scalar values, calculate derived fields, map allowlisted panel columns, and
  drive the generic Agent Monitor review UI. Added SQLite v55 scope support and
  an authenticated admin-only Edge/RPC approval boundary with exact summary
  versions and atomic operational writes. The RPC verifies the active database
  role directly and does not depend on deprecated JWT-role helpers.
- 2026-07-28: Clarified the unified agent policy so questions about existing
  flock information stay on scoped read tools instead of being mistaken for
  data entry, and normalized final Telegram replies to plain text so Markdown
  markers never appear to customers.
- 2026-07-28: Removed the dormant fixed greeting/Pasgar conversation router.
  Every authorized Telegram turn now reaches only the unified AI runtime;
  registry catalogs include localized aliases and valid layers, adversarial
  tests enforce scope/confirmation boundaries, and assistant delivery is
  persisted as pending then marked delivered/failed so retries cannot rerun the
  model.
- 2026-07-28: Exposed old draft questions only through explicit scoped AI tools
  and added scope plus optimistic-state metadata to protected tool evidence.
  Legacy answers require both submission and question identity; ordinary chat
  never auto-binds to an old draft.
- 2026-07-28: Routed every authorized Telegram text and attachment through the
  unified AI runtime. Update receipts are checked before mutable writes,
  inbound turns receive a conversation-unique index, attachment bytes reach
  provider-native image/file inputs, and the exact model reply is delivered
  without a second phrase router or Pasgar controller. Provider failures use
  only the bounded infrastructure retry at the webhook boundary.
- 2026-07-28: Added the bounded unified AI provider/runtime loop. It supplies
  behavior policy, trusted scope/state, recent chat, attachments, and typed
  tools to one natural conversation turn, feeds tool results back to the model,
  and enforces serial execution, five-call/20-second limits, malformed-call
  rejection, and provider-safe failure statuses.
- 2026-07-28: Added the generic durable station-intake state machine and tools.
  Natural data-entry intent now creates an expiring proposal, explicit
  confirmation opens a registry schema, multi-field messages validate in any
  order, and one complete versioned summary is confirmed only at the end.
  Corrections use optimistic concurrency and submissions stop at admin review;
  legacy Pasgar row readers remain compatibility-only.
- 2026-07-28: Added customer-scoped AI read tools for customer/flock context,
  registry-allowlisted station records, deterministic metric aggregation, and
  record provenance. Reads retain missing values as null, cap and sort results,
  verify customer/flock ownership in depth, and share canonical calculation
  parity vectors with Flutter.
- 2026-07-28: Added the unified agent's server-side scope resolver and typed
  tool gateway. Every configured AI path now fails closed unless the Telegram
  staff link resolves to its enforced customer/admin scope; unknown and
  out-of-scope entities share the same denial shape. Tool calls use bounded
  JSON contracts, server-injected scope, five-call/100-row/366-day limits, and
  sanitized evidence without database credentials or raw table access.
- 2026-07-28: Replaced direct Telegram-user approval with an admin-only scope
  assignment sheet. Customer access now requires one selected customer;
  agent-admin access is an explicit all-customer grant. Agent Monitor lists
  allowed users with their enforced scope and supports reassignment or
  revocation, with bilingual labels and repository/provider validation.
- 2026-07-28: Added the v54 unified-agent persistence boundary. Telegram staff
  links now enforce customer/admin scope, conversations preserve turns and
  immutable tool evidence, visits group sequential station intakes, and intake
  sessions carry visit and optimistic-version references. Existing Pasgar
  sessions are backfilled without deletion. The admin app pulls server-authored
  evidence read-only, while RLS limits it to approved admins and service-role
  Edge execution.
- 2026-07-28: Added the canonical versioned AI station registry and deterministic
  Dart/TypeScript generator. Registry contracts now cover 18 Breeder hatchery
  modules across every active panel table, with localized vocabulary,
  validation metadata, completion requirements, read measures, and persistence
  mappings. Pasgar retains its seven explicit sample-bound inputs.
- 2026-07-28: Kept Telegram greetings and ordinary mission chat conversational
  when a legacy hatchery draft still has open questions. The bot no longer
  responds to greetings such as "Hi", `صباح الفل`, or `الو` by dumping the
  pending numbered form; the draft remains untouched and later data-bearing
  answers still use the existing safe router.
- 2026-07-28: Hardened OpenAI/OpenRouter Responses API parsing so Telegram
  mission chat and Pasgar interpretation accept only assistant `message`
  `output_text` content. Reasoning items are ignored and can no longer be sent
  to staff as customer-facing bot replies.
- 2026-07-28: Added schema-driven conversational Pasgar intake for approved
  Telegram staff. The bot accepts natural Arabic, English, and mixed-language
  measurements in any order, asks focused clarification when uncertain, saves
  valid progress silently, and requests confirmation only once after presenting
  the complete summary. Corrections create a new summary version. Added v53
  local/remote persistence and sync, idempotent admin approval into Chick
  Quality, and a full Agent Monitor review/edit/approve/reject/evidence
  workspace.
- 2026-07-28: Hardened local sync tombstones against older browser database
  shapes by detecting camelCase versus snake_case tombstone columns at runtime.
  Manual/background sync now keeps working when an IndexedDB cache still has
  `synced_at`/`deleted_at`, allowing Telegram agent drafts pulled from Supabase
  to appear in Agent Monitor.
- 2026-07-28: Added bounded Arabic mission chat for approved Telegram staff
  greetings/help messages without creating drafts, kept unapproved senders in
  the access flow, made pending-question greetings return a friendly reminder,
  and accepted relaxed numbered answers such as `1 30`.
- 2026-07-27: Added Telegram staff self-registration for unknown bot senders.
  Unknown senders now become pending staff links with Telegram ID, chat ID,
  username, and display name metadata; Agent Monitor shows pending requests to
  approved admins, and admin approve/reject decisions mark staff links allowed
  or revoked for future Telegram messages.
- 2026-07-27: Hardened Telegram staff-link defaults so newly inserted staff
  links default to `pending`, and added deterministic labeled-text extraction
  for routine Telegram messages so structured hatchery text can become a draft
  without an AI provider call.
- 2026-07-27: Switched testing-mode OpenRouter extraction to default to
  `openrouter/free` and retry paid-model 402 credit failures once with the free
  router.
- 2026-07-27: Cleaned Telegram staff prompts to Arabic-only messages that hide
  draft references and internal field keys for normal one-draft flows, add
  numbered choice lists for resolvable flock/customer/hatchery questions, and
  accept option-number replies.
- 2026-07-27: Fixed Supabase upsert payload preparation so local sync metadata
  is removed before snake_case conversion; manual/background sync no longer
  falls back to rejected camelCase fields such as `customerId` on remote tables.
- 2026-07-27: Fixed local debug-bypass sign-out so the development auditor is
  cleared for the current session, later cached-token checks do not immediately
  recreate it, and `/login` uses the real login route instead of the main shell.
- 2026-07-27: Aligned Agent Monitor navigation, data loading, and Telegram
  pause/resume controls with admin-only agent-table RLS. Auditors and customers
  no longer receive the Agent destination, and provider guards prevent
  unauthorized agent reads and local pending-sync writes.
- 2026-07-27: Resolved Telegram hatchery draft customer/flock IDs through
  unique normalized hierarchy matches, retained missing or ambiguous
  identities as bilingual review warnings/questions, linked sole customer
  hatcheries, and replaced raw Agent Monitor UUID entry with scoped hierarchy
  selectors that also repair uniquely matched existing drafts.
- 2026-07-27: Wired Telegram draft ingestion to count-derived historical
  hatchability warnings, unique exact customer/flock resolution, the configured
  3-point default threshold, nearest-age BMK context for rising results, and
  bilingual missing-flock-age questions. Warning enrichment is server-owned;
  pulled rows retain its evidence without local rewrite.
- 2026-07-27: Routed authorized Telegram staff replies to same-chat open
  hatchery-agent questions, added deterministic numbered/row answer matching
  with bilingual clarification, persisted question answers, copied validated
  values into related draft fields, kept completed replies in admin review,
  and added backend-only update receipts for answer-replay idempotency.
- 2026-07-27: Added admin-only hatchery draft row editing, rejection with an
  audited reason, atomic approval into final hatchery daily records,
  batch-status recalculation, and startup push/pull coverage for the
  hatchery-agent operational tables.
- 2026-07-27: Added the admin-only Agent Monitor tab with persisted Telegram
  pause/resume control, responsive submission and draft evidence review,
  question/answer and audit-history display, separate confidence and warning
  presentation, bilingual copy, and role-gated navigation.
- 2026-07-27: Added the Telegram hatchery-agent Edge Function with verified
  webhook ingestion, allowed-staff enforcement, idempotent update handling,
  Telegram text/photo/document loading, strict OpenAI structured extraction,
  multi-row draft creation, hatchability calculation, confidence routing,
  bilingual missing-data questions, and durable failure status. All backend
  tests use injected fakes.
- 2026-07-27: Added the v52 hatchery-agent data foundation with additive local
  and Supabase tables, immutable storage models, atomic draft-graph repository
  writes, settings and historical comparable queries, operational sync
  allowlisting, admin-only remote RLS, tenant-scope validation, and
  Telegram-token-shaped secret scanning.
- 2026-07-24: Added customer poultry-structure management for concurrent
  Breeder, Broiler, and Layer membership, single-sector farms, nested houses,
  and the Breeder-only hatchery gate. Added Performance as a staff main-shell
  destination while preserving the customer-role navigation boundary.
- 2026-07-24: Added localized diagnostic visit and corrective-action workflow
  screens. Daily evidence remains read-only during visits; investigations,
  findings, staff explanations, explicit cause decisions, action ownership,
  implementation confirmation, and before/after KPI decisions are editable.
- 2026-07-24: Added the responsive Broiler Performance workspace with
  customer/farm/flock/date scope, multi-house SQLite aggregation, current KPI
  cards, daily trend charts, active concerns, visits/actions, provenance and
  verification badges, exact objective-source labels, and a daily quick-entry
  path.
- 2026-07-24: Added corrective-action KPI follow-up with immutable baseline and
  evaluation windows, implementation confirmation, valid scoped observations,
  all four effectiveness outcomes, explicit reasons, and persisted evaluator
  identity/time.
- 2026-07-24: Added the diagnostic farm-visit evidence layer for performance
  concerns: immutable pre-visit briefing snapshots, selected houses, suggested
  and manual investigations, measurements and observations, staff explanations,
  attachment references, and explicit suspected/probable/confirmed/ruled-out
  cause assessment states.
- 2026-07-24: Added the Home `Incomplete Visits` section. It lists every
  customer-visible in-progress visit with station progress, remaining stations,
  and an explicit completion reminder. `Complete now` resumes the first
  unfinished station directly, and Home reloads the list after the workflow
  closes.
- 2026-07-21: Stabilized Dashboard background refresh and scrolling. Overlapping
  refresh requests are now serialized/coalesced, existing Lab Analysis content
  remains mounted while refreshed data is queried, stale filter-scope loads are
  ignored, and the Dashboard keeps one scroll controller so refreshes no longer
  make the reader jump between Lab Analysis and adjacent sectors.
- 2026-07-21: Completed Arabic localization coverage for the new Lab Analysis
  report workflow, bacterial-culture interpretations, and longitudinal trend
  labels.
- 2026-07-19: Restored mobile multi-customer sync by removing the obsolete
  production trigger that silently cancelled every non-`الغريب` customer
  insert. Parent uploads now verify returned Supabase rows, and local customer,
  hatchery, flock, audit-session, and panel writes automatically request a
  debounced sync that also retries on connectivity changes and app resume.
- 2026-07-19: Added admin-issued, username-based customer accounts. Admins can
  create an approved read-only Supabase Auth identity and assign it to one
  existing customer through Settings > User access; the privileged user-create
  operation lives in a caller-verified Edge Function. Customer accounts see
  only Dashboard plus account/sign-out Settings, are locked to their assigned
  customer/hatcheries/flocks, cannot create dashboard actions, and run both
  startup and background sync in pull-only mode. Added admin-assisted password
  reset for username accounts and fail-closed clearing of dashboard state when
  the active identity or assigned tenant changes.
- 2026-07-19: Hardened Supabase authorization by moving RLS helpers out of the
  exposed API schema, requiring approved admin status, revoking anonymous table
  and trigger-function grants, and tenant-scoping deletion tombstones with a
  server-derived immutable customer and snapshotted audience. Explicit offline
  login no longer accepts a cached Supabase profile as proof of an entered
  password; remembered valid sessions still resume during startup. Strengthened
  live Auth and registration rules to 12 characters with lowercase, uppercase,
  digit, and symbol requirements, plus recent-session and current-password
  checks for password changes. Registration counts user-perceived Unicode
  characters consistently, and disposable PostgreSQL integration checks verify
  the effective helper, policy, and function-grant state across migrations.
- 2026-07-20: Reorganized Lab Analysis entry into test-aware report, result, and
  source-document sections; replaced known specimen, scope, analyte/target,
  kit-manufacturer, antigen, organism, antimicrobial, and interpretation text
  fields with controlled choices while leaving the actual laboratory name
  editable; made ELISA specimen rows explicitly
  optional; and added ELISA longitudinal GMT/CV/positivity charts, pooled-repeat
  separation, latest snapshot callouts, and a house/date heatmap to Dashboard.
  Dashboard alert/watch KPIs now count result groups instead of every sample
  row. Extended the private photos-bucket RLS policy so customer-authorized Lab
  Analysis report rows can open their attached PDF and new uploads can use the
  standard customer-scoped lab-report path.
- 2026-07-20: Split bacterial culture from antibiotic sensitivity in Lab
  Analysis. Sensitivity now records antimicrobial S/I/R results only, while the
  new Bacterial Culture tab records the isolation method, tested organisms, and
  positive/negative or isolated/not-isolated findings, based on the supplied
  Salmonella isolation report.
- 2026-07-19: Aligned the iOS Runner deployment target with the Podfile's iOS
  15.5 minimum and disabled parallel CocoaPods framework code signing for
  Release builds so local device release builds complete reliably before
  installing fresh provisioning profiles.
- 2026-07-16: Redesigned saved Lab Analysis results as compact ChickMark cards.
  ELISA opens with sample size, mean, GMT, CV%, positive/negative counts, and
  minimum/maximum titers; large numbers use thousands separators, while full
  specimen rows are collapsed under an expandable Sample details control.
- 2026-07-11: Resumed Chicks visit sessions now prefer the live Flock Manager
  breed and age over stale session snapshots, and Chick Weights recalculates and
  persists BMK age plus BMK chick weight from the matching breed benchmark.
- 2026-07-05: Added a destructive delete action to each editable Customers-list
  card. The action confirms the named customer, runs the existing local cascade,
  immediately attempts foreground Supabase tombstone sync, and reports whether
  the cloud delete synchronized or remains pending for a later sync.
- 2026-07-05: Made dashboard comparisons BMK-age-first and data-aware. Each
  scoped sector now defaults to a separate-age table with an equal-age average,
  supports House/Machine trends across ages, starts pooled when one age is
  selected, and exposes only sibling-valid House, Machine, Trolley, or Tray
  controls. Added missing-data handling, multi-level comparisons, and matching
  table/chart state; applied the same one-house rule and age table to the bespoke
  Egg Quality sector.
- 2026-07-05: Moved Hatch Analysis breakout photo capture into every Fresh,
  Candled, and Residue metric row; saved photos with metric-specific JSON and
  SQLite identities; kept thumbnails editable in-row; cleaned replaced/removed
  photo rows through sync tombstones; and kept the dashboard breakout photo
  grid loading both item-scoped and legacy evidence.
- 2026-07-05: Refreshed an already-mounted Dashboard after successful sync so
  downloaded breakout photos replace stale in-memory paths without requiring a
  manual pull-to-refresh or filter change.
- 2026-07-05: Preserved the dashboard Govee sector's collapsed state when it is
  disposed off-screen and recreated during scrolling.
- 2026-07-04: Preserved dashboard station-card collapse state while scrolling
  and through pull-to-refresh loading during the current Dashboard visit.
- 2026-07-04: Repaired stale evidence-photo paths after iOS app-container path
  changes by reconciling filenames against the current documents directory,
  and allowed cloud pull/download to recover rows whose local file is missing.
- 2026-07-03: Added the selected flock's name, current age, breed, and entrance
  date to the dashboard filter card and moved that card into the scrolling
  dashboard content so it no longer stays frozen while the user scrolls.
- 2026-07-03: Completed the Arabic UI copy audit across administration, auth,
  customers, visits, poultry audit stations, BMK, Dashboard, Govee, Home, and
  Settings; localized input decorations, validators, tooltips, semantics, and
  dynamic operational messages while preserving entered names and values;
  corrected directional RTL spacing/alignment and the navigation drawer shape;
  added Arabic font fallbacks and prevented the Home last-audit date from being
  truncated; and added regression tests for RTL, static strings, dynamic copy,
  tooltips, fonts, and the long Arabic date layout.
- 2026-06-26: Added English/Arabic app localization, Settings language
  selection, local persistence for the selected language, Flutter localization
  delegates, automatic Arabic RTL directionality, and a central Arabic
  translation catalog for shared user-facing text.
- 2026-06-26: Expanded the Arabic catalog for Home and Dashboard operational
  labels, dashboard filter labels, triage alerts, and rich text spans.
- 2026-06-28: Expanded the Arabic catalog for remaining Home focus, sync,
  conflict, Dashboard scope, and Govee labels, including dynamic count/name
  messages.
- 2026-06-23: Added root auth-state navigation so logout resets the app back to
  `/login`, and covered Remember me loading, saved-email persistence, clearing,
  remember-session forwarding, and phone-width Remember me row layout with login
  screen tests.
- 2026-06-23: Simplified guided EST/CVT capture to a serial photo-first flow
  with one Take photo action, Done-only footer navigation, display-only
  photo-backed station grid cells, and tapped-cell edit routing through the
  attached-photo capture screen.
- 2026-06-24: Moved guided temperature capture completion to a top-right Done
  action, changed the footer primary action to Capture, and fixed Retake so a
  saved point returns to capture-ready state. Added a recorded-photo strip,
  per-cell photo badges, retaking state text, and automatic manual-entry focus
  after capture.
- 2026-06-24: Added startup photo download sync for pulled Supabase photo rows
  and remote storage-object cleanup for synced photo deletes, so evidence can
  appear on other devices and deleted photo rows remove their backing bucket
  objects.
- 2026-06-22: Added `bmk_operational_standards` with seeded global operational
  BMKs, hatchery-specific overrides, an Operational BMKs reference sector, and
  an Admin editor with global/hatchery scope selection.
- 2026-06-25: Organized the Operational BMKs reference sector into Egg, Chicks,
  Hatch Results, Setters, and Hatchers categories and added a source citation
  dialog from the sector header.
- 2026-06-25: Added per-item Operational BMK citation actions and source URLs
  to the `bmk_operational_standards` model, schema, and seed data.
- 2026-06-25: Moved Operational BMK citation icons beside each metric label and
  added per-metric citation photo attachment through `sourcePhotoPath`.
- 2026-06-25: Removed Operational BMK category/header citation actions, made
  external source links open from each metric dialog, stopped showing internal
  links for ChickMark operational defaults, and added cloud-backed source photo
  replace/delete plus zoom preview.
- 2026-06-25: Persisted EST/CVT readings with their selected `°F`/`°C` unit,
  preserved legacy unit fallbacks, and made dashboard EST evidence display the
  saved unit instead of assuming Celsius.
- 2026-06-25: Changed dashboard Egg Quality to one Pool-plus-house comparison
  sector with default-selected Pool/house chips and a chart/table toggle, instead
  of separate selected-house cards plus a nested `Compare houses` reveal.
- 2026-06-25: Tightened the dashboard Egg Quality chart layout with wrapping
  metric chips, compact Act-vs-BMK paired bars for normal house counts, and a
  dashed average reference line.
- 2026-06-23: Added Hatch Analysis breakout sample photo capture, saving new
  captures under the active breakout panel and showing recorded breakout photos
  in the dashboard Scopes grid. The dashboard Hatch breakout area now shows only
  breakout types with real recorded rows instead of always showing Fresh,
  Candled, and Residue tabs.
- 2026-06-22: Added a `°F`/`°C` toggle to the dashboard Govee Environmental
  Readings sector and made its cumulative temperature metric follow the shared
  app temperature unit.
- 2026-06-22: Removed thermometer OCR from EST/CVT capture, deleted the unused
  ML Kit OCR service/tests/dependency, and converted Egg EST, Setter EST,
  Chicks CVT, and Hatcher CVT to a guided manual photo capture flow that saves
  typed readings plus evidence photos, shows photo-backed station grid cells,
  and reopens tapped cells in the attached-photo edit flow.
- 2026-06-22: Scoped debug seed data to `الغريب` plus one dashboard test
  customer, removed older dummy customer seeds, and added deterministic
  five-reading Govee captures for the dashboard places.
- 2026-06-22: Gated the app-wide floating Govee shortcut on entering the main
  app shell so it remains hidden during login, registration, pending approval,
  and startup sync even when the user already has Govee permissions.
- 2026-06-13: Tuned thermometer OCR for the red seven-segment device by
  isolating the large display row, adding red/inverted/adaptive preprocessing,
  preserving detected units, warning on selected-unit mismatches, and adding
  Fahrenheit-default `°F` / `°C` controls to Egg EST, Setter EST, Chicks CVT,
  and Hatcher CVT without changing their canonical stored units.
- 2026-06-13: Restored the in-app ChickMark keypad for adaptive native iOS
  audit numeric fields after the focus-preservation and stable-station fixes,
  while leaving ordinary text fields on the native iOS keyboard.
- 2026-06-13: Kept the narrow audit-session footer actions in one compact row
  with protected space for the floating Govee action, and changed the Hatch
  Analysis Breakout Type and metadata cards from fixed heights to matching
  minimum heights so wrapped content can expand without overflow or infinite
  layout constraints.
- 2026-06-12: Preserved the mounted audit station subtree while keyboard focus
  hides session chrome, preventing active numeric fields and modal sheets from
  rebuilding with station-owned focus nodes that were already disposed.
- 2026-06-12: Changed audit keyboard dismissal from raw pointer-down handling
  to resolved background taps, preventing iOS text fields from losing focus
  during the same press that opens the native keyboard.
- 2026-06-12: Switched adaptive native iOS audit numeric fields from the
  in-app overlay keypad to the system numeric keyboard, preventing focused
  fields from scrolling into view without presenting an input surface while
  preserving Android custom-keypad and desktop physical-keyboard behavior.
- 2026-06-12: Registered audit photo buttons across Egg, Chicks, Hatch
  Analysis, Setters, and Hatchers with explicit panel field keys, and mapped
  Hatch Analysis breakout photos to the active breakout table so saved captures
  enter the same local photo-sync queue as their screen JSON paths.
- 2026-06-12: Hardened shared debug-log sanitization for JWTs, Supabase
  publishable/secret keys, and token/password/API-key values in query/form and
  JSON-style messages while preserving debug-build-only logging.
- 2026-06-12: Added a shared keyboard-aware audit station scroll wrapper and hid
  fixed visit chrome, including the Govee readings card and Next Station footer,
  while station inputs are being edited on phone layouts.
- 2026-06-12: Fixed Hatch Analysis Machine scope activation from pooled House
  scope so the machine row no longer opens the House entry or House remove
  controls; the House card stays visibly pooled until House scope is explicitly
  added.
- 2026-06-12: Made the Egg and Chicks weight-entry modal sheets reserve
  scrollable bottom space for the in-app numeric keypad so lower weight cells
  remain fully reachable instead of sitting partly behind the keypad, and kept
  the keypad open while users touch or drag within the sheet. Active lower rows
  now scroll above the keypad overlay after entry or keypad navigation.
- 2026-06-11: Made the Govee Records tab merge completed floating-panel saves
  into its open list immediately and sort visit-day groups by latest update
  time, so newly recorded current-date captures are not hidden behind
  future-dated demo records.
- 2026-06-11: Hardened mobile UI responsiveness by truncating long shared
  gradient app-bar titles and status badges, stacking the audit-session footer
  actions on narrow phones, ellipsizing Select Stations row labels, and keeping
  audit/Govee filter dropdown labels constrained inside their fields.
- 2026-06-11: Hid the read-only Govee capture date field from the active scope
  picker while keeping the provider-owned capture date behavior unchanged.
- 2026-06-11: Gated the live Govee card and preview charts on latest-reading
  freshness so sensors with no live update for more than 30 seconds show empty
  Temp/RH metadata and no stale chart trend even if BLE/GATT flags lag, added an
  inline scan/connect activity spinner, and kept Customer and Hatchery controls
  visible for Setter/Hatcher Govee measure scopes.
- 2026-06-11: Refactored the compact Govee live-card settings sheet into a
  private part, shared the device-name and connection-status display helpers
  between the card and sheet, disabled duplicate compact-card scan taps while a
  scan is already active, and capped diagnostics text to prevent overflow.
- 2026-06-04: Enhanced thermometer OCR with primary-first fallback
  preprocessing, confidence-scored reading consensus, a shared lower-CPU
  auto-scan cadence, and testable OCR-reader injection while leaving correction
  telemetry out of scope.
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
- 2026-06-12: Allowed a blank/default Hatchers station to save as an
  explicitly incomplete station, while still clearing metadata-only
  `hatcher_optimizing` panel rows and leaving the visit in progress.
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
