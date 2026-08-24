# Living Spec — Current Implemented Behavior

## Maintaining this file

This file describes only how the app works today. It is not a history.

- The Flutter codebase is the source of truth. If this document and the code
  conflict, the code is correct: inspect the code and fix this document.
- Update this file after every meaningful change, in the same commit as the
  change.
- Describe current behavior in the present tense. Do not record what changed,
  what something used to do, or when it changed.
- Dated history lives in `CHANGELOG.md`. This file records what is true now;
  that file records what happened. A meaningful change updates both.

## 1. Last Updated

2026-08-16

Mapped from the working tree under `lib/`, covering app bootstrap, navigation,
audit and station screens, providers, models, repositories, services, and the
SQLite database helper, together with the Supabase Edge Functions and
migrations under `supabase/` that the app calls.

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
hatchery. Writing a `Global defaults` row requires an approved admin, matching
the cloud `bmk_operational_global_write` policy: `BmkProvider` refuses the write
with `BmkGlobalStandardPermissionException` unless the screen has granted
global-write rights via `setCanEditGlobalStandards`. Auditors keep
hatchery-scoped override edits. Allowing a non-admin global edit would create a
locally dirty row that RLS rejects on every push, and because the operational
push sends the whole dirty batch in one call and marks every id failed on any
error, that one row would block every legitimate hatchery override
indefinitely. Existing station and dashboard warning logic still uses the current
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
`NetworkStatusMonitor`, `SettingsProvider`, `DashboardProvider`, and
`ScopeComparisonProvider`.

Initial route selection is auth-state driven:

- Authenticated users go to `/main`.
- Pending approval users go to `/pending-approval`.
- Loading, error, and unauthenticated users go to `/login`.
- `/register` and `/startup-sync` are also registered routes.

After startup, the app also listens for auth-state changes at the root
navigator. If logout or another auth failure leaves the user unauthenticated
while an app route such as `/main` is visible, the navigator is reset to
`/login` so protected screens are not left on screen.

Authentication has two independent gates. The **login gate** requires a real
Supabase sign-in and is unchanged. The **usage gate** decides whether an
already-signed-in install may keep working, and does not depend on the
one-hour access-token expiry.

On startup `AuthProvider.checkCachedToken()` resolves the remembered user
(`UserRepository.getRememberedUser()` — approved, `tokenExpiry` non-null as the
"Remember me" marker, a real token still present in secure storage,
regardless of whether that `tokenExpiry` has passed), asks Supabase to
restore or refresh the session (`SupabaseService.restoreSession()`, skipped
for local-only accounts), reads the Keychain trust record
(`SessionTrustStore`), and feeds all three into the pure
`decideStartupAuth()` function, which returns one of three outcomes. Along
the way, a restored session or trust record that belongs to a different
account than the remembered user is treated as proof of nothing and sent to
`/login` rather than silently granted to the remembered identity.

- **Enter app** — the session is valid or was refreshed by Supabase. The
  access token is re-cached in secure storage and the Keychain trust record
  is stamped with the current time.
- **Enter app pending re-validation** — the session could not be checked
  because the device is offline (or the request otherwise failed in a way
  that is not a definitive server rejection — including a 5xx
  `AuthRetryableFetchException`), but this install recorded a successful
  login within the offline grace window (`AuthSessionPolicy.offlineGrace`,
  30 days). The app runs normally against local SQLite with
  `AuthProvider.isPendingRevalidation` set. This startup path replaces the
  login route directly with `/main`; it does not visit `/startup-sync`, show
  its animated logo, or start a second automatic cloud check while the shared
  network monitor is definitively offline.
- **Go to login** — only when this install has never recorded a successful
  online login, when the grace window has lapsed, or when the server
  definitively rejected the session while online
  (`SupabaseService.classifyRestoreFailure()` reserves rejection for an
  unambiguous `AuthException`, not a connectivity failure). A connectivity
  failure is never a logout.

One app-lifetime `NetworkStatusMonitor` converts `connectivity_plus` events
into explicit `unknown`, `online`, or `offline` state after probing the
configured Supabase host. Auth revalidation, automatic sync, Settings cloud
state, and the shell's offline indicator consume that same state. On resume,
`SessionRevalidationTrigger` refreshes the monitor but calls
`AuthProvider.revalidateSession()` only when connectivity is verified online;
an offline resume does not change auth state or replace the mounted `/main`
route. A real offline-to-online transition revalidates once. Revalidation is
also re-entrancy guarded, clears the pending flag silently on success, and
signs the device out only on a definitive rejection or on discovering the
live session belongs to a different account.

Local-only accounts (`local-` ids) bypass the Supabase path entirely and keep
their existing 30-day `tokenExpiry` rule, checked directly on the remembered
user rather than through `restoreSession()`.

Intended session lifetimes, configured as project-level Supabase Dashboard
settings rather than in this repository (Authentication → Sessions / JWT
settings; not verified from code): access-token (JWT) expiry 3600 seconds (1
hour), refresh-token rotation enabled with a 10-second reuse interval,
session time-boxing disabled (no forced expiry), inactivity timeout 90 days.
The 30-day local offline grace is deliberately shorter than that intended
90-day server window so a device returning from the longest permitted
offline stretch can still refresh instead of meeting a dead refresh token.

Tokens never move to SQLite: the access token stays in `SecureTokenStore` and
the trust record in `SessionTrustStore`, both Keychain-backed (with an
in-memory fallback on web). `users.accessToken` remains `NULL` for remote
users; `UserRepository.upsertUser()` strips any in-memory access token before
the SQL write for non-local accounts, and `cacheToken()` writes the real
token only to `SecureTokenStore`.

The main shell has eleven destinations for approved admins:

- Home
- Dashboard
- Customers
- Audits
- Govee Records
- Lab Analysis
- BMK
- Performance
- Agent
- Pip
- Settings

Approved auditors receive the same destination set except Agent, leaving ten
auditor destinations. Agent Monitor is restricted to approved admins because
its remote tables use admin-only RLS.

Approved customer-role accounts see only Dashboard, Pip, and Settings.
Settings is reduced to account details and sign-out, so the only product data
surfaces they can open are Dashboard and the Pip chat. Their Dashboard
customer selector is locked to the profile's assigned `customerId`; hatchery
and flock selectors are populated only from that customer. Dashboard action
creation/editing is hidden and also rejected by provider guards for
customer-role users. Pip is open to every approved role because the Edge
Function resolves each caller's own customer scope server-side rather than
trusting the client.

The Pip destination is conversation-centric: the tab's root is
`PipConversationsScreen`, a day-grouped list (Today/Yesterday/Earlier, by the
local calendar date of each conversation's `updatedAt`) of every conversation
the caller has with the shared hatchery agent, each row showing its title (or
a preview/"Voice conversation" fallback when untitled), a last-message
preview, and a time/date label. A FAB starts a new conversation by minting a
fresh `'app:'+uuid-v4` key and opening it immediately — the server creates the
row lazily on the first send, so an abandoned new-conversation tap never
leaves a placeholder in the list. `PipConversationsProvider` owns the list
(`load()`/`refresh()`, an `uninitialized`/`loading`/`loaded`/`error` state);
`groupConversationsByDay` is the pure day-bucketing function. Tapping a tile
(or the FAB) pushes `AssistantChatScreen` in its own route with its own
`AssistantProvider(conversationKey: ...)`, so each open conversation keeps its
own history independent of the others and switching shell tabs and back always
lands back on the list rather than mid-thread; returning from a pushed
conversation refreshes the list so its new preview/title/ordering shows
immediately.

`AssistantChatScreen` is one persistent conversation thread with the same
hatchery agent that serves Telegram, by text or by voice; Live (see 7.af) is a
mode reachable from inside that same thread rather than a separate
destination. It shows the conversation oldest-first, a multiline input with
send and mic buttons, a thinking indicator while a reply is outstanding, an
empty state before the first message, and an error banner with a retry action.
A turn whose `source` is `'voice'` (a finalized Realtime call transcript,
distinct from the mic button's own request/response recording) renders with a
small mic glyph and a distinct bubble tint instead of the plain role-based
styling. While the shared network monitor reports offline the input is
disabled behind a short notice, because the conversation runs entirely against
the Edge Function and has no local fallback. An app-bar action clears the
conversation after a confirmation dialog. The mic control starts recording
and, on the next tap, stops and sends the recording. The screen offers no
photo or file attachment; see the `AssistantProvider` section below for
recording and spoken-reply behavior. Its labels, states, notices, errors, and
action tooltips are available in English and Arabic. `AssistantProvider` is
created per pushed conversation route rather than with the root providers, so
it exists only while that conversation's screen is on the stack.

`conversationKey` identifies which conversation a screen shows: `'app'` is the
legacy single-thread key (still what a Pip Live call started with no
conversation context binds to) and `'app:'+uuid-v4` keys any other
conversation; the key is carried through `AssistantChatScreen`,
`AssistantProvider`, `AssistantChatService`/`AssistantChatPort` (every
call — `sendMessage`, `sendVoice`, `loadHistory`, `resetConversation` — takes
it, defaulting to `defaultConversationKey`), `RealtimeVoiceController.start`,
and `RealtimeVoiceScreen`, and is opaque to the client: it never determines
which conversation's turns are loaded on its own (the provider/service call
does), it is just the label passed through to identify the request. While a
live call for a conversation is active, `AssistantChatScreen` listens for that
call reaching `idle` and, if the call belonged to its own `conversationKey`,
reloads history exactly once — this is how a call's persisted transcript
(written server-side by the sideband) appears in the visible thread without
the user leaving and reopening the conversation.

The shell uses a drawer on narrow layouts and a navigation rail at widths of
900px or greater. It lazily builds tabs, keeps a tab history stack for shell
back navigation, and requests background sync after the first Home build.
Automatic requests are held without remote work while network state is
`unknown` or `offline`. The shell keeps one passive top indicator, `Offline —
will reconnect automatically`, driven by the shared monitor; Home does not
show a second offline SnackBar.

There is no floating Measures launcher. Govee recording is
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
  `egg_quality` is the one exception: as of v61 its row identity is its own
  row `id`, not the hierarchy tuple, so two comparison rows with a blank or
  repeated `house` stay separate instead of overwriting each other. It carries
  no hierarchy unique index and no hierarchy-identity merge/update path. If a
  write for an `egg_quality` row somehow neither inserts nor updates by `id`
  (only reachable if a stale hierarchy unique index survives from a pre-v61
  database), the save falls through to the same hierarchy-identity path the
  other panels use rather than silently discarding the row.
- Station panel rows written through the audit save coordinator carry their
  sampling metadata explicitly instead of leaving it to be re-inferred from
  hierarchy columns on reopen: the row's
  `sampleMode` (`pooled`/`comparison`), `scopeType` (the `SamplingLayer` the
  row is scoped to), `sampleLabel`, and `sampleIndex` are all persisted. Egg
  station rows also record which side of the operation owns the measurement,
  the corrective action, and the recommendation, via `sourceDomain` /
  `actionDomain` / `recommendationTarget`: `egg_storage` is measured and fixed
  inside the hatchery (all three `hatchery`), while `egg_quality` is measured
  in the hatchery but caused and fixed at the breeder farm (`sourceDomain`
  `hatchery`, `actionDomain`/`recommendationTarget` `farm`). Other panel tables
  do not yet set these three domain columns.
- Reopening a station reads that saved metadata back explicitly-first: each
  row's `sampleMode`, `scopeType`, and `sampleLabel` are taken from the
  persisted columns when present, and `sampleIndex` orders the row among its
  siblings. Only when a column is null (rows saved before v61) does the read
  path fall back to inferring mode from whether the row carries any hierarchy
  value, scope from which hierarchy columns are populated, and label from the
  row's position. This means a saved comparison row with an intentionally
  blank `house` (e.g. a not-yet-named house) still reopens as a comparison
  row instead of collapsing into pooled mode, which the old inference-only
  read could not distinguish. `PanelSampleRepository.panelOrderByForColumns`
  orders non-null `sampleIndex` values first, legacy null indexes last, then
  falls back to `createdAt` and `id`; the in-memory reconstruction uses the
  same order for drafts and samples. Tables without `sampleIndex` (pre-v61
  test schemas only) keep the previous hierarchy-column ordering. Persisted
  `egg_quality.id` values bind the reopened draft and station sample, including
  through `legacyAuditId`, so mixed pre-v61/v61 rows cannot pair positionally.
  Evidence capture uses the persisted station-sample row id whenever one is
  available, so photo ownership stays stable when a draft id is regenerated on
  reopen. Legacy photo references are repaired only when their panel-row prefix
  identifies exactly one row; ambiguous references remain unchanged and are
  logged. Reopening Pasgar also overlays its six saved defect-photo paths from
  the `photos` table onto the reconstructed station values.
  The
  reconstruction itself lives in `reconstructStation` (and the Egg-only test
  entry point `reopenEggStation`) in
  `lib/features/audits/logic/egg_station_reconstruction.dart`, extracted from
  `_StationFrameState` so it can be exercised directly against raw panel rows
  without a widget tree.
- As of v62, visual egg grading has its catalogue, local schema,
  summary/validation logic, per-sample save/reopen wiring, and Egg Quality UI.
  The defect catalogue is `kEggDefectTypes` in
  `lib/features/audits/models/egg_grading.dart`: 18 fixed defect codes across
  five categories (shell contamination, shell integrity, shell quality, shape
  and size, other), each with a `code`, `name`, `category`, `isReject`,
  `description`, and `sortOrder`. It is seeded into the `egg_defect_types`
  table on create and on every upgrade past v62 by `seedEggDefectTypes`, and
  is the single source of truth other layers join against by `code`.
  **One egg may carry several defects.** Per-defect occurrence counts for one
  `egg_quality` sample live in `egg_quality_defect_counts`, one row per
  `(eggQualityId, defectCode)`, cascading from its parent. The rejected count
  is entered directly by the auditor rather than derived from the defect
  counts; acceptable count is `sampleSize - rejectedCount`. There is
  deliberately no constraint — in SQL or in `EggGradingValidation` — tying
  `SUM(defect counts)` to the sample size, because defects are not mutually
  exclusive per egg. `EggGradingValidation.validate` only rejects negative
  counts, a per-defect count above the sample size, and a rejected count
  above the sample size. `EggGradingSummary` derives `acceptableCount`,
  `rejectedPct`, `acceptablePct`, and the top defect (by count) from a raw
  counts map, and round-trips its non-zero counts through a JSON array
  (`encodedJson` / `fromJson`) that also carries each defect's resolved name,
  category, and reject flag for display without a catalogue join. Malformed or
  wrong-shaped JSON is treated as an empty count map while the supplied sample
  and rejected totals remain available, so one damaged mirror cannot break a
  station reopen or save. The eight
  derived fields (`gradingSampleSize` through `gradingTopDefectPct`) are
  written back onto the owning `egg_quality` row as a fast dashboard summary;
  see `docs/DATABASE_SPEC.md`'s "Egg Grading Tables" section for the full
  column and table shapes.
- `EggGradingRepository` (`lib/data/repositories/egg_grading_repository.dart`)
  is the read/write layer over `egg_quality_defect_counts`, called from the
  audit save path (see below).
  `countsForSample(eggQualityId)` and
  `countsForSession(sessionId)` (the latter keyed by `eggQualityId`) read back
  a `{defectCode: count}` map. `replaceCountsForSample` runs in one
  transaction: it upserts every positive count under the deterministic id
  `'$eggQualityId:$defectCode'` — **an existing count row for that pair keeps
  its id across re-saves, it is never re-minted** — then queues a sync
  tombstone via `SyncTombstoneRepository.queueDeletesWithExecutor` and deletes
  every row for a defect code that is no longer present. This matters because
  cloud `ON DELETE CASCADE` only covers deleting the whole parent sample; an
  auditor removing a single defect code has no other cloud-side signal, and
  because the table also carries `unique (eggQualityId, defectCode)`, a
  re-minted id on an existing pair would make PostgREST reject the whole sync
  batch. Re-adding that deterministic id transactionally cancels an unsynced
  delete tombstone. If the delete tombstone was already synced or pulled, its
  local application compares `deletedAt` with the row's local timestamps and
  keeps a newer resurrection. `pctOfSample` is `count * 100 / sampleSize` (null when
  `sampleSize <= 0`), and `defectCategory`/`isReject` are copied from
  `eggDefectTypeForCode` at write time so a later catalogue edit cannot rewrite
  history. `deleteCountsForSamples` does the same tombstone-then-delete for
  every row under the given `eggQualityId`s. `getDirtyRows`/`markRowsSynced`/
  `markRowsFailed` follow the same pending/failed sync-status convention as
  the other per-row dirty-tracked repositories, including the dirtyAt-cutoff
  guard: `getDirtyRows` captures the read time, and `markRowsSynced` only
  clears `dirtyAt`/flips to `synced` for rows whose `dirtyAt` is still at or
  before that cutoff, so an edit landing between the push read and the sync
  ack stays `pending` instead of being silently marked synced and dropped —
  the same pattern `LabAnalysisRepository.markRowsSynced` uses. A re-save of
  an existing count row also never touches `createdAt`, only `updatedAt`.
  On cloud pull, remote application rereads and conflict-checks the row by
  its deterministic id in the same SQLite transaction that conditionally
  writes the accepted remote row. This means a newer local dirty edit that
  lands while pull is in progress remains pending instead of being overwritten
  by the older remote snapshot. The repository safely normalizes Supabase
  snake_case (and boolean values) back to SQLite camelCase before marking an
  accepted remote row synced; unknown cloud columns are ignored for upgrade
  compatibility.
- Grading is threaded into the draft, save, and reopen paths for every Egg
  Quality sample independently. `AuditModel` carries `esGradingSampleSize`
  (`int?`), `esGradingRejectedCount` (`int?`), and `esGradingDefectsJson`
  (`String?`, the per-sample JSON mirror described above). `AuditProvider`
  exposes `activeGradingCounts` (reads the active sample's counts back out of
  its JSON) and `updateGradingCounts(Map<String, int>)` (re-encodes and writes
  `esGradingDefectsJson` on the active draft only — because the JSON already
  lives on the per-sample draft, switching samples cannot move it). On save,
  `panel_value_builders.dart`'s `eggQualityValues` writes the eight summary
  columns onto the `egg_quality` row from an `EggGradingSummary` built off the
  draft's three grading fields. When grading is cleared, all eight values are
  explicitly written as null so an upsert cannot retain an older summary;
  clearing grading does not synthesize shell-UV `qualityTouched` state.
  `hasMeaningfulEggQualityData` treats a sample with grading data but nothing
  else as savable. Before either explicit save or autosave writes anything,
  every Egg Quality draft is checked with `EggGradingValidation`; any rejected
  or individual defect count above its sample size returns a failed save and
  prevents final station exit while leaving the draft editable. There is no
  total-defect-occurrence ceiling. `AuditPanelSaveCoordinator` writes the child
  `egg_quality_defect_counts` rows immediately after each sample's
  `egg_quality` panel write, via a constructor-injected `EggGradingRepository`
  (defaults to a real instance): `replaceCountsForSample` is called with that
  sample's id as `eggQualityId` (the `egg_quality` row id **is** the sample id
  as of Phase A), its session/customer/flock/hatchery/date, scope type, the
  sample's `houseNo` as `houseKey`, sample label, and the decoded counts —
  called with an empty map when a sample carries no grading data, so any
  previously-saved counts for that sample are removed. On reopen,
  `mergePanelRowIntoAuditMap`
  copies the three `esGrading*` draft fields back from the panel row's
  `gradingSampleSize`/`gradingRejectedCount`/`gradingDefectsJson` columns —
  this is the fallback path for a cloud-pulled row whose child rows have not
  arrived yet. Both the production `_StationFrame` load path and the direct
  `reopenEggStation` test/data entry point read
  `egg_quality_defect_counts` for the session and overlay each parent by its
  persisted `egg_quality.id`; when child rows exist they rebuild
  `esGradingDefectsJson` and win over a stale panel mirror.
- Every repository path that removes an `egg_quality` row routes through one
  transaction that tombstones and deletes its grading children first, then
  tombstones and deletes the parent. This covers removed samples, station
  clears, exact-id prunes, direct row deletes, and whole-session deletion and
  never relies on SQLite's
  `ON DELETE CASCADE` on `egg_quality_defect_counts` — cascade does not queue
  a sync tombstone, so a cascaded child row would go on existing in the cloud
  copy forever, and a still-`pending` child whose cloud parent has already
  been deleted makes PostgREST reject the whole sync batch on an FK
  violation. Because `egg_quality` is id-keyed, its stale-row prune uses only
  the persisted keep-id set; it does not fall back to matching hierarchy
  tuples and includes explicit comparison rows whose hierarchy text is blank.
- `AuditSessionScreen` accepts an optional `eggGradingRepository` constructor
  parameter (alongside its existing `panelSampleRepository`), threaded into
  both the per-station `AuditProvider` and production reopen frame it builds,
  so child-count loading and saving use the same injectable repository.
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
- Chick panel rows carry an immutable V2 identity envelope in addition to the
  compatibility hierarchy columns. `chick_weights` uses domain
  `chicks.weights`; historical combined `chick_quality` rows use
  `chicks.legacy_combined`. The envelope records registry schema version,
  normalized `scopeType`/canonical JSON `scopeKey`, a positive replicate, a
  base64url canonical `sampleKey`, and source/capture/creator/device/reference/
  observation-time provenance. New Chick sample row ids are UUIDv7 values and
  are reused after reload. A different row id at the same scope receives the
  next replicate; it is never merged, overwritten, pruned, or tombstoned by a
  hierarchy collision. Existing rows keep their ids and measurements during
  v64 backfill, and missing legacy hierarchy is represented by explicit JSON
  null rather than inferred. Reopen reconstructs each quality and weight row
  by its persisted id, including multiple rows at one scope, so a no-op save
  retains every id and sample key without creating tombstones. Reconstructed
  station samples also carry their persisted sample key; if older in-memory
  state regenerates an id, that key recovers the exact customer row within the
  same audit session rather than allocating or merging a different sample;
  sample-key-aware pruning preserves the recovered row.
- The Supabase mirror has the snake-case form of the same additive identity and
  provenance columns. Agent-approved Chick intake supplies the registry domain,
  schema version, normalized scope, and provenance. A database trigger validates
  or allocates every inserted Chick replicate/sample key under a per-identity
  transaction lock after the final session is known, including rows from older
  clients and independently-created offline human samples. A collision keeps
  both row ids and receives the next replicate; the push response updates the
  local identity batch before pull. If a new local row took a returned key while
  the upload was in flight, reconciliation preserves it, moves it to the next
  free replicate, and leaves it pending for the next push. Updates cannot mutate
  an existing cloud identity envelope. Human and agent rows at one scope
  therefore coexist, and house-scoped weight intake retains its collected house
  identity through approval. These migrations are repository files only and are
  not applied by the app.
- `tool/agent_schema/station_registry.json` remains the persistence-metadata
  and validation authority. Generation rejects duplicate local or remote column
  claims, incomplete/dead quality issue mappings, invalid policy tiers, and
  malformed shared classification parity vectors. Normal Chick UI save/load and agent
  intake use those generated field mappings and the same quality classifier in
  both directions; adapters also support semantic JSON/list and integer-boolean
  decoding while compatibility-only columns remain available.
- Every Chick parent row stores a registry-recomputed `qualityStatus` and
  canonical JSON `qualityFlags`. `BLOCK` is reserved for malformed identity,
  schema, scope, or value types that cannot be stored safely. `WARN` records
  biologically or operationally suspicious ranges, choices, and dependencies.
  `FLAG` records incomplete/raw-evidence gaps and derived-cache mismatches.
  Explicit zero remains distinct from missing. `WARN` and `FLAG` never block an
  offline save; the Chick workbench shows a localized advisory banner for both
  current draft warnings and persisted flags restored from saved samples.
  SQLite v65 backfills existing rows without changing their measurements,
  identity, provenance, or sync bookkeeping. The migration-only cloud mirror
  never trusts caller-supplied quality caches: every insert and measurement
  update receives a conservative `legacy_quality_unclassified` flag. A pulled
  row is classified exactly from the generated registry when SQLite stores it,
  including rows from older clients that omit both cache columns.
- SQLite v66 stores Chick weights, YFBM pairs, vent temperatures, Pasgar
  tallies, postmortem tallies/severity, and culled-chick counts as normalized
  `chick_quality_observation` children. Observation shape, key, unit, list
  ordinal, and photo-evidence ownership come only from the generated station
  registry. Stable observation identity includes sample id and domain, so the
  same parent id can safely exist in both Chick parent tables without merging
  or cross-deleting evidence. Observation identity and parent ownership are
  immutable; value rows require exactly one numeric or text value.
- Newly touched exact-domain Chick samples replace their observation set and
  then rebuild the wide/JSON and calculated compatibility caches from the
  persisted children in one transaction. Reads for reopen, direct row lookup,
  session reconstruction, dashboard aggregation, and agent queries use
  observations first. A parent with no observations continues to read its
  preserved cache, so malformed, incomplete, and untouched legacy evidence is
  never inferred or discarded. Once a parent owns normalized observations, an
  update whose observation-bearing values cannot round-trip is rejected and
  rolled back instead of silently retaining or replacing the old children.
- Touching a combined legacy Chick row lazily creates deterministic
  exact-domain helper parents only for domains with losslessly round-trippable
  raw evidence. Each helper points back with a `legacy-domain:` source
  reference, is reused on later saves, and is hidden from duplicate UI and
  agent result lists while its observation-derived values overlay the visible
  compatibility row. The original combined row and its caches remain for old
  clients. No bulk split occurs during migration.
- Unambiguous registry-owned Chick photos move to the exact-domain helper
  without copying or deleting the file. Observation-specific evidence also
  stores an optional observation id. Synced rows use a metadata-only pending
  state so the ownership update reaches Supabase even on web; that update does
  not replace the remote storage path with a device-local path. Ownership
  triggers reject cross-sample, cross-session, and wrong-domain links, and
  deleting an observation clears its optional photo reference without deleting
  the photo.
- Observation sync pushes parents before children, pulls parents before
  children for every role (including pull-only customers), and drains child
  tombstones before either Chick parent. Dirty cutoffs protect edits made while
  a push is in flight, logical-id collisions fail for review instead of
  replacing either row, and parent deletion is domain-scoped when both Chick
  tables happen to contain the same id. The additive Supabase schema, RLS,
  ownership triggers, and atomic agent-approval wrapper remain migration files;
  the app does not apply them to a live project. The observation owner trigger
  validates its private parent through a fixed-search-path privileged function,
  while active RLS still limits authenticated reads and writes by customer.
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
- Reopened non-Chick panel-row drafts may use synthetic in-memory IDs, but panel saves
  resolve conflicts by the panel row identity (`sessionId`, `house`, `setter`,
  `hatcher`, `trolley`, `tray`, and `position`) so reopened edits update the
  existing panel row instead of writing legacy audit/sample tables. `egg_quality`
  and both Chick panel tables are excluded from hierarchy-identity resolution;
  their rows resolve by persisted `id` only (see above).
- If an existing scoped sample row is later saved with the same hierarchy as an
  existing pooled or differently scoped row, panel persistence merges the save
  into the existing hierarchy row and tombstones the stale row id instead of
  attempting an `id` update that would violate the unique hierarchy index. This
  merge behavior does not apply to `egg_quality`, `chick_quality`, or
  `chick_weights`, which have no unique hierarchy index to violate.
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
`updatedAt` with visit date as a secondary sort. Tapping a session resumes it
and opens the station workflow (`AuditSessionScreen`) directly, for both
in-progress and completed sessions; the Audits tab does not branch on session
status. Saved stations stay visible without leaving the list because each row is
an inline expandable session card, and a station can be opened directly from
that card. Final results are available from the station screen dashboard action.
Legacy single-audit edit paths remain as compatibility UI code, but the current
list and save/load workflow are session and panel based.

The status branch belongs to Home, not the Audits tab: Home's session tap opens
the station-selection continuation screen for `in_progress` sessions and the
station workflow for every other status.

Home shows a white `Icons.home_rounded` glyph before the `Home` title in the
main gradient app bar. The page body is ordered: a mobile-friendly KPI strip for
monthly visit counts, active flocks, and last audit date; Quick Actions; the
Incomplete Visits section, rendered only when at least one active visit session
exists; Recent Audits; Today's Focus; Attention Needed setup items; and sync
status. The active flocks KPI uses a paired hen/rooster glyph rather
than an egg-only icon. Counts and Recent Audits are based on `audit_sessions`
rather than legacy audit rows. Home has an explicit uninitialized/loading
state and shows progress until every first-load SQLite query completes; zero
KPIs, a missing last-audit marker, and empty-list messages render only from a
completed query result. Later refreshes keep the already-loaded values mounted.
Today's Focus metric cards are actionable when
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
Home does not show an Audit Type Breakdown, extra
Customers/Active Audits/Total Audits stat cards, or a duplicate New Customer/New
Audit action row. Home section headings and quick actions
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
- Egg grading / visual quality: an expandable Egg Quality card below the egg
  weights and Shell UV cards records the number of eggs inspected and rejected,
  then an occurrence count for each visual defect grouped by category. Its
  summary updates live with acceptable/rejected counts and percentages plus
  the localized top-defect name and percentage. Each defect keeps an exact
  40x40 image slot and shows `-` while its percentage is blank/zero. Defect
  codes unknown to the installed catalogue are preserved when a known count or
  the grading totals are edited, so an older client does not tombstone data
  written by a newer catalogue.
  Its category, defect, description, and sample-mode labels are translated by
  the central Arabic localization catalog when Arabic is selected.
  Counts belong to the active Egg Quality sample, so switching House scopes
  restores that house's independent values. A rejected count or an individual
  defect count cannot exceed the eggs inspected; multiple defect counts may
  collectively exceed the sample size because one egg can carry several
  defects.
- Upside Down Score: tray entries and overall upside-down average. Fresh or
  empty tray data shows a default Tray 1 editor before the add-tray action.
  Its header uses an inverted egg symbol with the pointed end up. Upside-down
  score fields persist on the `egg_storage` row alongside the storage-side Egg
  cards.
- Sample mode: Egg storage room shows a read-only "Sample mode" bar with a
  single, permanently-selected `Pool` chip and the note "Egg storage is
  always measured as one pool." — Egg Storage room fields never gain a
  comparison scope. Egg Quality shows its own "Sample mode" bar with a real
  `Pooled` / `Compare by house` `ChoiceChip` pair. Tapping `Compare by house`
  while pooled is the only way to enter compare mode; it seeds one house
  sample with the placeholder identity `H`. Once compare mode is active the
  selected chip stays visually enabled, but re-tapping it is a safe no-op so it
  cannot add a second house — additional houses are added only through the
  House scope card's `+` control below it. Tapping `Pooled` while more than
  one house is recorded shows a confirmation dialog ("Switch to a pooled
  sample?") naming how many houses will be discarded; the first house is
  kept and the rest are removed only after the user confirms. With at most
  one house recorded, switching back to pooled happens immediately with no
  dialog.
- Egg Quality Assessment: shows a blue brand-gradient Egg quality card with
  white foreground styling for flock, breed, and BMK age in one equal-width row,
  a dedicated Quality Storage Days entry used for Egg Quality BMK age and BMK
  egg-weight lookup. Egg Quality has no One sample / Multiple samples
  selector; below the Sample mode bar, a House scope card renders only while
  compare mode is active (it is hidden while pooled). Pressing the House
  scope add control asks for the House identity, then adds a new named chip
  such as `H2`; duplicate House identities are rejected before creation, and
  the same duplicate check runs inline as the identity field for the active
  house is edited directly — a duplicate value shows an inline error under
  the field and is not written back to the sample. Edited
  values continue to update the active chip and saved Egg Quality hierarchy.
  House
  identity input keeps its active editing focus while provider state refreshes
  and syncs provider-side identity changes back into the field when the user is
  not actively editing that field. Removing a House scope removes that house and
  returns Egg Quality to the pooled state when no scoped houses remain; a
  single surviving comparison house stays in comparison mode rather than
  silently collapsing to pooled. Once a House scope sample carries any
  entered house identity, the provider owns and keeps that identity verbatim
  — it is never re-derived by comparing the value against the string a
  placeholder chip would have generated for that position. A practical
  consequence: removing a house from the middle of a comparison does not
  renumber the surviving houses to stay sequential (a house named `H3` stays
  `H3` even if it is now the second house in the list).
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
39.4-40.6°C target. The °F/°C selector changes entry and display only: readings
are canonicalized to °F before persistence and aggregate derivation, while the
stored entry-unit tag restores the selected display unit on reopen. Existing
rows tagged explicitly as °C are converted to °F by the v63 migration; tagged
°F and untagged rows are not guessed at or changed. Readings and photos persist
locally in `cvtReadingsJson` and `cvtPhotosJson`, and the panel CVT average/CV
summary fields are backfilled for dashboards. PM Necropsy captures sample
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
and encoded defect JSON containing both the exact raw count and its percentage.
Older percentage-only payloads remain readable. Derived dashboard fields store
total affected percentage, top category, and top subtype.

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
limit. Residue does not enforce 100-percent hatch-budget reconciliation.

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

Summary statistics are computed from the full valid synced dataset. Each
completed capture stores Temp and RH average, minimum, maximum, sample standard
deviation, coefficient of variation percent, the valid reading count
(`readingCount`), and `chartPointsJson` in the capture row. `chartPointsJson`
holds every valid reading in the recording window, in timestamp order. The app
applies no downsampling or chart reduction, so the stored chart point count
equals `readingCount`.

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

Chick Quality and Chick Weights values are also checked against their generated
station-registry domain rules before save. These checks cover ranges,
count/denominator relationships, YFBM child-weight bounds, and required PM
severity choices. Findings are exposed by the audit provider and logged as
warnings; they never block offline capture. Validation compares choice values
case-insensitively and projects stored object-list items onto the registry's
declared properties, avoiding false warnings from display-only JSON metadata;
all comparison samples are checked, not only the currently selected one.
Aggregate derivation flags such as
missing raw values or invalid denominators are likewise retained by the panel
repository, logged, and exposed to the provider instead of being discarded.
Comparison samples cannot be saved with a blank house or applicable machine
identity, because blank identities would otherwise collide in the panel
uniqueness key. Chick machine samples require Setter and Hatcher, Setter
optimization requires Setter, and Hatcher optimization requires Hatcher;
pooled samples remain unrestricted.
Rejected blank identity edits immediately restore the saved identity in the
field so the visible text cannot disagree with the value that will be saved.

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
range, Temp avg/min/max/SD/CV%, RH avg/min/max/SD/CV%, and saved valid
reading count. Each card renders separate timestamp-based Temperature and
Relative Humidity charts from the capture row's full
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
negative result). Sensitivity does not ask for a bacterial organism; it stores
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
  summaries, valid reading count (`readingCount`), and every valid reading as
  chart points in `chartPointsJson`.
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
  citations. The cloud `public.bmk_operational_standards` table mirrors the
  local schema; global rows (`hatchery_id` null) are reference data readable by
  all authenticated users and writable by admins only. Hatchery-owned rows are
  scoped through the owning customer using the same RLS helpers as other
  customer-owned tables. The local table carries per-row `syncStatus`,
  `dirtyAt`, `lastSyncedAt`, and `syncError` columns (added in the v58
  upgrade). `BmkRepository.upsertOperationalStandard` marks the written row
  `pending`/`dirtyAt = now`; `getDirtyOperationalRows`,
  `markOperationalRowsSynced`, `markOperationalRowsFailed`, and
  `getOperationalRowSyncStatus` mirror the `getDirtyRows`/`markRowsSynced`
  pattern used by `CustomerRepository` et al., including the same
  `dirtyAt`-cutoff guard against clearing an edit that lands mid-push.
  `upsertOperationalStandardRow` accepts a raw snake_case cloud row (as pulled
  from Supabase), camelizes and filters it to known columns, and writes it as
  `synced` with `dirtyAt` cleared since a pulled row is clean by definition.
  Fresh-install and reseed paths mark seeded standards `synced` up front so
  baseline reference data is never treated as a pending local edit. The v58
  upgrade does the same for an existing database, then re-marks
  `pending`/`dirtyAt = now` any row with a non-null `updatedAt` or a non-null
  `hatcheryId`: seeds carry no `updatedAt` and the seed-source backfill never
  writes one, so those two conditions identify exactly the rows a user edited
  before this table joined the sync path. Without that second pass, pre-branch
  local edits would sit permanently `synced` and never push. Column-level
  coverage for the upgrade lives in
  `test/data/database/bmk_operational_sync_migration_test.dart`, because the
  whole-table schema-parity net cannot see a migration that only ALTERs a
  baseline table. Both push
  and pull wiring that call these methods are implemented — see the sync
  section below.
- `troubleshooting`: seeded troubleshooting/reference content.
- `activity_log`: user actions for logins, syncs, session starts/resumes,
  station completion, audit changes, and related events.

Visit session summaries combine one `audit_sessions` row and its panel rows.
Scorecards are parsed from persisted JSON when present; otherwise they are
derived from completion state and simple threshold heuristics. Dashboard Govee
summaries are loaded separately by customer, hatchery, and selected visit date.

### Source of truth rules

Panel tables are the station source of truth. The app does not create or write
the legacy `audits` table, `sample_records`, sample detail tables, or
`{panel}_samples` child tables.

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
Startup may still resume a previously remembered remote session from secure
local token storage without asking the user to sign in again, even once the
cached access token itself has expired; see §2 for the two-gate model
(login vs. usage) that this now goes through.
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
state, invalid-reading filtering, full-dataset Temp/RH summary stats, full
valid-reading chart points, replacement save, finished-place preview, and
next-place progression.

`BmkProvider` reads seeded breed and egg-breakout benchmark rows from SQLite,
tracks selected breed, selected ages, and selected egg-breakout type, and
upserts internal BMK admin edits back into the same `bmk_breeds` and
`bmk_egg_breakout` rows used by audit and dashboard benchmark lookups.

`AssistantProvider` owns one conversation's in-app assistant chat, bound to
the `conversationKey` it is constructed with (default `'app'`, the legacy
thread): an ordered `ChatMessage` list, an `AssistantLoadState` of
uninitialized, loading, loaded, or error, and the send/retry/clear actions. A
`ChatMessage` carries its role (`user` or `assistant`), a `source` (`'text'`
or `'voice'`, exposed as `isVoice` — `'voice'` marks a turn that came from a
finalized Pip Live call transcript rather than the mic button's own
recorded-clip round trip) and, for outgoing messages, a `sending`, `sent`, or
`failed` status. Sending appends the user message optimistically before the request
returns; a failed send keeps the message visible in `failed` state and `retry`
resends it under the same `clientMessageId`, so a reply that was produced but
not received is returned instead of asking the model twice. `canRetry(message)`
gates the retry action to failed, user-authored turns that did **not**
originate as voice: the recorded clip is discarded the instant it is sent, so
there is nothing left to resend, and retrying would otherwise fire the literal
placeholder text ("Voice message") at the agent. `AssistantChatScreen` only
shows the Retry button when `canRetry` is true; a failed voice turn still shows
"Not sent" with no action. The error banner's own Retry button (shown above
the message list whenever `error` is set) applies the same `canRetry` filter
to the failed turns before picking one — it retries the last *retryable*
failed turn, not simply the last failed turn, so a failed voice turn never
leaves the banner's Retry as a dead button, and a retryable typed turn is
still reachable even if a later voice turn also failed. If no failed turn is
retryable (including when the only failure was a voice send), the banner
falls back to `provider.load()`, same as when there is no failed turn at all.
`clear()` resets the conversation, but is a no-op
while a send, a recording, or a voice reply is in flight (`isSending`,
`isRecording`, or `isAwaitingVoiceReply`), and the app-bar clear action is
disabled under the same conditions — otherwise a clear mid-voice-send could
empty the list before the pending reply lands, orphaning it. The provider
talks only to `AssistantChatService` through the `AssistantChatPort` interface
and raises `AssistantChatException` for transport and server errors. The
service's only literal is the Edge Function name: no keys, model names, or
provider details are compiled into the app.

The in-app assistant is named Pip in both English and Arabic interfaces; Arabic
copy keeps `Pip` in Latin script. A static, clean ChickMark avatar appears in
the chat header, empty state, assistant messages, and thinking state, while
user messages receive no avatar. The avatar has no sparkle, badge, or other
AI-brand symbol.

Each message bubble renders `message.text` through `GptMarkdown` instead of
plain `Text`, so bold, numbered/bulleted lists, and other markdown the agent
replies with render as formatted content rather than literal syntax
characters. Its `textDirection` is set per message by
`TextDirectionDetector.detect`, which walks the message's characters and
returns `TextDirection.rtl` on the first strong-direction character from
Hebrew/Arabic script (and their presentation-form blocks), `ltr` on the first
Latin letter, defaulting to `ltr` when neither appears — this follows the
Unicode Bidi algorithm's paragraph-direction rule (P2/P3) rather than the
screen's ambient locale, so an Arabic reply renders right-to-left even inside
an English-locale screen and vice versa, and a bubble is never forced into the
wrong direction just because the app locale doesn't match the reply's
language.

`AssistantProvider` also owns voice-turn state behind an `AssistantAudioRecorder`
and an `AssistantAudioPlayer`, both constructor-injectable so tests never touch
a microphone or speaker. The production recorder uses the `record` 7 plugin
family, whose platform implementations support the app's Flutter 3.44/Dart
3.12 toolchain and compile together for release builds. Because that plugin
opens its platform channel when an `AudioRecorder` is constructed, the default
recorder is created lazily on the first voice action rather than when the text
chat provider starts. `startRecording()` starts capture and sets
`isRecording`, surfacing an `AssistantAudioException` (e.g. denied microphone
permission), or any other platform throw (a generic catch-all fallback), as
`error` without starting the recording. A successful start also arms a
60-second `maxRecordingDuration` timer that auto-stops and sends the clip if
the user never taps stop, so a forgotten open mic cannot record indefinitely.
`stopRecordingAndSend()` cancels that timer, then stops capture; a throw from
the recorder's `stop()` (not just a `null`/empty clip) surfaces as `error`
("Could not save that recording. Please try again.") rather than escaping
uncaught. If a clip was produced, the provider appends an optimistic "Voice
message" user turn, best-effort plays a bundled filler chime while
`isAwaitingVoiceReply` is true (a chime failure is swallowed, never surfaced as
`error` or an unhandled error), and sends the clip through
`AssistantChatPort.sendVoice`. On success the user turn's text is replaced with
the server-reported `transcript`, the reply is appended carrying the server's
`audioBase64` (mp3, memory-only — `ChatMessage.audioBase64` is never parsed
from loaded history, so only replies received this session are replayable),
and if present the provider auto-plays it through `playMessageAudio()`, the
same path a tap on the reply's own playback controls uses; on a failed send
the pending turn is marked `failed` the same way a failed text send is.
`playMessageAudio(message)` sets `playingMessageId` to that message's id,
`isPaused` false, `isSpeaking` true, and awaits full playback completion (not
merely playback start) before clearing all three, so the mic stays disabled
for the whole reply; playing a second message stops whichever one currently
owns the player and takes over. `pausePlayback()`/`resumePlayback()` pause
and resume the current player without losing `playingMessageId` (so the
control row can tell "paused" from "nothing playing"). Playback is
best-effort throughout: if the player throws (bad codec, no output device,
decode failure), the error is swallowed rather than surfacing on `error` or
marking the just-delivered turn failed, since the text reply is already
visible either way. Internally, `AudioplayersAssistantAudioPlayer` tracks one
pending completion `Completer` at a time; if a second `playAsset`/`playBase64`
call interrupts a still-pending first one (e.g. the reply audio cutting off
the filler chime, or a later reply's playback cutting off an earlier one),
the interrupted call's `Completer` is resolved before being replaced, since
`audioplayers` does not emit an `onPlayerComplete` event for a programmatic
`stop()` and the earlier call would otherwise stay pending forever. Reply
audio is played from a temp file via `DeviceFileSource` rather than
`audioplayers`' `BytesSource`, which is unsupported on iOS/macOS and would
otherwise throw silently into the same best-effort handling. A `null` or
empty clip from the recorder is a no-op. `dispose()` cancels any pending
recording-timeout timer and, best-effort, stops an in-progress recording
(releasing the microphone and cleaning up its temp file) and stops any
in-flight playback, so navigating away from the Assistant tab mid-voice never
leaves the mic hot. `AssistantChatScreen` exposes a mic button next to the
text input: tapping it calls `startRecording()` (the icon and color switch to
a stop control), tapping again calls `stopRecordingAndSend()`. While
recording (`isRecording`), the text field is disabled but the mic remains
enabled as the Stop control. Both controls are disabled while offline, during a
text send (`isSending`), while awaiting a voice reply (`isAwaitingVoiceReply`),
or while playing one (`isSpeaking`), so the two input modes cannot race. Any
assistant bubble whose message carries audio renders a small play/pause
toggle and a replay button beneath the text (`assistant-reply-play-pause`,
`assistant-reply-replay`); the toggle plays, pauses, or resumes depending on
whether that message currently owns the player, and replay always restarts
from the top regardless of state. A voice clip's base64 payload is capped
client-side at `assistantAudioMaxBase64Chars` (1,500,000 chars, matching the
server's `MAX_AUDIO_BASE64_CHARS`) — enough for a few seconds of speech, not
minutes, to bound the Whisper/TTS spend.

`HomeProvider` derives Home KPIs from audit and flock repositories: audits this
month, active flocks, last audit date, recently saved audits, and audit type
breakdown. Its load state distinguishes uninitialized, loading, loaded, and
error outcomes so default field values are never interpreted as loaded data.

## 7. Persistence Summary

The app uses SQLite through `sqflite` at database version 66. The database file
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
Version 63 repairs only explicitly Celsius-tagged Chick CVT payloads into the
canonical Fahrenheit unit, restores all nine panel-table dates from their
owning session date when they differ, and reconnects legacy photo references
only where one matching panel row makes the target unambiguous. These repairs
mark changed local rows pending for normal synchronization.
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

Version 56 adds explicit conversation context and ordered diagnostic metadata
to the read-only local agent mirror. Conversations store a context generation
and selected customer/flock/audit. Inbound and outbound turns store generation,
turn order, reply linkage, provider, model, and provider response identity;
tool evidence stores its serial call order. Existing turn and tool rows receive
deterministic chronological order without deleting evidence. The upgrade then
copies the three agent evidence tables through constrained shadow tables,
verifies the row counts and foreign-key graph, and atomically replaces the
legacy tables. Upgraded databases therefore receive the same context/order
checks and selected-context/reply foreign keys as a fresh v56 database. The
immutable tool-event guards are restored immediately after the upgrade-only
backfill and row-preserving rebuild.

Version 57 completes per-row sync dirty tracking for the three master-data
tables. It adds `syncStatus` (defaulting to `pending`), `dirtyAt`,
`lastSyncedAt`, and `syncError` to `customers` and `hatcheries`, and adds the
remaining `lastSyncedAt` column to `flocks`, which already received
`syncStatus`, `dirtyAt`, and `syncError` at version 51. Each column is added
only when the target table exists, so the upgrade is safe on partial databases.

`CustomerRepository`, `HatcheryRepository`, and `FlockRepository` each expose
`getDirtyRows`, `markRowsSynced`, `markRowsFailed`, and `getRowSyncStatus`.
`StartupSyncService` pushes only the rows `getDirtyRows` returns for these three
tables instead of re-pushing every local row, marks the pushed ids synced on
success, and records the error on the affected ids on failure. `markRowsSynced`
is guarded by the `dirtyAt` cutoff captured at the last `getDirtyRows` call, so
an edit that lands while a push is in flight stays dirty and is picked up by the
next sync rather than being marked synced.

This `getDirtyRows`/`markRowsSynced`/`markRowsFailed`/`getRowSyncStatus` push
path currently drives `customers`, `hatcheries`, `flocks`, and
`bmk_operational_standards`. `bmk_operational_standards` carries the same
per-row `syncStatus`, `dirtyAt`, `lastSyncedAt`, and `syncError` columns and
the matching `BmkRepository.getDirtyOperationalRows` /
`markOperationalRowsSynced` / `markOperationalRowsFailed` /
`getOperationalRowSyncStatus` methods (see above). Inside
`StartupSyncService._pushLocalData`, dirty operational-standard rows are
pushed to `public.bmk_operational_standards` right after the `hatcheries`
push and before `flocks`, so any dirty row's `hatchery_id` FK already
resolves remotely (global rows carry a null `hatchery_id` and have no FK
dependency). A private `_operationalStandardToRemote` mapper in
`StartupSyncService` translates the local camelCase columns to the cloud's
snake_case columns via an explicit name dictionary — `hatcheryId` →
`hatchery_id`, `stationKey` → `station_key`, `sectorKey` → `sector_key`,
`metricKey` → `metric_key`, `metricLabel` → `metric_label`, `minValue` →
`min_value`, `maxValue` → `max_value`, `targetValue` → `target_value`,
`sourceUrl` → `source_url`, `sourcePhotoPath` → `source_photo_path`,
`sourcePhotoRemotePath` → `source_photo_remote_path`, `sortOrder` →
`sort_order`, `updatedAt` → `updated_at` — before the shared
`_pushDirtyReferenceRows` helper strips the device-local sync columns
(`syncStatus`, `dirtyAt`, `lastSyncedAt`, `syncError`) and uploads. The pull
side reads `public.bmk_operational_standards` alongside `bmk_breeds` and
`bmk_egg_breakout`: `SupabaseService`'s pull entry point gains a
`SupabasePullSummary.bmkOperationalStandards` count and an optional
`upsertBmkOperationalStandard` callback, called through the shared
`pullTable('bmk_operational_standards', ...)` helper right after the
`bmk_egg_breakout` pull. `StartupSyncService` wires that callback through the
existing `_upsertReferenceRow(..., canPush:, getSyncStatus:, upsert:)` dirty
guard — the same one `hatcheries`/`flocks` use — using
`_bmkRepository.getOperationalRowSyncStatus` and
`_bmkRepository.upsertOperationalStandardRow`, so an incoming cloud row never
overwrites a local edit that has not yet successfully pushed. The remaining
local reference tables — `bmk_breeds`, `bmk_egg_breakout`, and
`troubleshooting` — carry no `syncStatus`, `dirtyAt`, `lastSyncedAt`, or
`syncError` columns at all and are not part of this dirty-guarded push/pull
path (their pulls always overwrite, since they are pull-only).

Version 59 lets the local mirror hold app-channel staff links. It rebuilds
`telegram_staff_links` through a shadow table so `telegramUserId` becomes
nullable and loses its column-level `UNIQUE`, adds `channel` (defaulting to
`telegram`) and `appUserId`, and replaces the dropped uniqueness with partial
unique indexes over the non-null `telegramUserId` and `appUserId` values. Rows
are copied, counted, and foreign-key checked before the swap. The unified-agent
guards are dropped for the rename, because SQLite reparses every trigger during
`ALTER TABLE` and a sparse legacy database can be missing a table an unrelated
guard references; the staff-link guards are recreated immediately and the rest
by the surgical repair pass at `onOpen`.

Two pull behaviours make a schema mismatch like that visible instead of silent.
`SupabaseService.pullOperationalRows` catches per row rather than per table, so
one unusable row no longer discards the rest of its table, and it reports how
many of the fetched rows applied. `PerformanceSyncRepository._upsertById` logs
when neither its `INSERT OR IGNORE` nor its fallback `UPDATE` touched a row —
the signature of a local constraint rejecting a cloud row, which SQLite's
`OR IGNORE` suppresses for NOT NULL, UNIQUE, and CHECK violations (but not for
foreign keys, which is why the children of a dropped parent kept failing
loudly while the parent's own loss went unrecorded).

The v56 local upgrade and the checked-in Supabase migration also apply the same
conservative legacy-flock sector repair. When the deployed schema includes the
optional farm and customer-sector catalogs, an unassigned flock first inherits
the sector of its customer-owned linked farm and a remaining flock inherits a
customer sector only when that customer has exactly one active sector. A
still-unassigned flock with hatchery-audit evidence is classified as Breeder
on every supported schema generation. Explicit sectors are never overwritten,
optional catalogs are detected before they are queried, and ambiguous rows
remain null for human assignment.

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

That catalog is a stable, versioned contract rather than a view of the physical
schema. `agent_tool_contract.ts` holds the only model-facing surface — each
tool's name, description, and JSON-Schema parameters — under
`AGENT_TOOL_CONTRACT_VERSION` (currently `1.2.0`), and `AGENT_TOOL_DEFINITIONS`
in `agent_tools.ts` is derived from it, so there is exactly one source of truth
for the model, the runtime's known-tool set, and the gateway's argument
validation. The contract moves only when a business capability changes;
migrations that rename a column or reshape a table change only the tool
handler's query, never the contract. `contractFingerprint()` is a stable FNV-1a
digest over the canonicalised contract, and `agent_tool_contract_test.ts` pins
both that fingerprint and a full inline snapshot of every tool name, parameter,
required flag, and enum, so any drift fails the build until the version is
deliberately bumped. The same test pins the flat tool-definition shape
(`{type, name, description, parameters}`) that the OpenAI Realtime API
requires, rather than the nested Chat-Completions `{type, function:{…}}` form.

Customer-data tools can now return the enforced customer's identity, flock
list, flock status/breed/sector/entry date, and an exact age calculated for the
query date. The model receives customer IDs only through scoped read tools, not
through its trusted prompt or scope summary. When a user supplies customer and
flock names, `resolve_customer_flock` evaluates them together through a
matching ladder in `agent_name_match.ts`. Names are folded to a comparison key
first — harakat, tatweel, zero-width marks and directional marks removed; أ إ آ
ٱ to ا, ى and ئ to ي, ؤ to و, ة to ه; Arabic-Indic and Eastern Arabic-Indic
digits to 0-9; whitespace collapsed; Latin lowercased — then split into word
tokens on every non-alphanumeric run. Three tiers are tried in decreasing
confidence and the FIRST tier that produces any match wins outright: `exact`
(identical token sequence), `prefix` (the stored name begins with the spoken
one, on a token boundary), then `contains` (the spoken token run appears
anywhere inside the stored one). This is what lets a caller say `بدر` and
resolve the flock stored as `بدر - 25 Oct 2025 - Avian`; matching on tokens
rather than substrings means a match always starts and ends on a word boundary,
so `ابر` can never match `صابر`. The two fallback tiers also strip a leading
Arabic definite article from both sides, so `البدر` finds `بدر` and `امل` finds
`الأمل`; the exact tier stays strict, because if both spellings exist as
separate flocks the caller must be told rather than guessed at. The `contains`
tier — the only one that may match the MIDDLE of a stored name — additionally
requires at least three characters and at least one letter: a stored flock name
carries its entry date and breed as tokens, so without that guard an operator
saying "flock 25" would resolve, confidently and uniquely, to whichever flock
happened to be entered on the 25th.

The fold is deliberately one-way. `normalizeOperationalName` merges the
spellings a name can be written with; `strictOperationalKey` performs the same
NFKC/marks/invisibles/digits/whitespace pass WITHOUT the letter equivalences.
The pair exists because `هانئ` and `هاني` are different people who collide
once hamza is folded, and "these fold together" must never be mistaken for
"these two database rows carry the same name".

Ambiguity is never resolved by guessing: every match in the winning tier is
reported. A single match resolves and the result names the tier in `matchedBy`;
more than one returns `ambiguous_customer` or `ambiguous_flock`. `matchedBy` reports BOTH tiers
(`{customer, flock}`), so a customer reached by a contained word and a flock
matched exactly cannot be presented as simply "exact" — the model keeps the
signal that the weaker half was guessed.

Flock matching runs only over the matched customers' own rosters, which are
themselves re-filtered to `allowedCustomerIds`. More than one matching customer
is refused outright rather than disambiguated by the flock name, UNLESS the
match was exact AND the candidates' fold-free keys agree — that is, unless they
really are spelled the same, which is the one case where the flock is the only
way to answer at all. Every non-resolved status carries candidate IDs with
names — `customer_not_found` returns the customers the caller may see, and both
flock statuses return the roster as `{id, name}` pairs — so the model can pick,
or ask one question naming real options, instead of repeating the question the
caller already answered.

Every roster carries `truncated`. `list_customers` and `resolve_customer_flock`
read at most `MAX_AGENT_READ_ROWS` customers in name order, and an `admin`
staff link is scoped to every customer — so past that cap a real tenant is
invisible to every name-based tool, and the honest answer ("I can only see the
first hundred") used to come out as the confident wrong one ("there is no such
customer"). A list is omitted rather than silently shortened whenever it is
incomplete, for the same reason the inline flock roster is. Versioned station reads derive their table and selectable columns
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
numbered options are persisted in immutable tool evidence. Even a single
result is presented as option 1 instead of a yes/no confirmation. A later
numbered reply calls `select_audit_option` with only a one-based position from
1 through 20; for compatibility with an already-sent single-option
confirmation question, an affirmative reply selects position 1. The server
uses the injected conversation ID to load that conversation's latest
successful audit-list snapshot, so a newly inserted audit cannot remap an
already displayed number. That lookup searches BOTH doors' evidence, because
the two record a tool call differently: the text doors write
`agent_tool_events.conversation_turn_id`, while the realtime broker writes it
NULL by design and links back through `realtime_session_id`, so the snapshot is
found through `agent_realtime_sessions.conversation_id` as well and the newer of
the two wins. Both sides are filtered by the conversation's CURRENT
`context_epoch`, so a cleared conversation cannot serve the user the list they
threw away; the turn side is ordered by `conversation_seq` rather than
`created_at`, which is the same rule the history loader follows and for the
same reason. The cross-door "newer wins" comparison is a plain string
comparison, deliberately not `localeCompare` — ICU collation treats punctuation
as variable-weight and inverts on timestamps whose fractional-second parts
differ in length, and `created_at` is a text column with nothing enforcing one
rendering. An option list read aloud on a live call is therefore selectable
by the number the caller says. The selected opaque audit ID is then revalidated
through the current customer scope before its summary is returned. A refusal
names its recovery: `audit_options_required` when nothing has been listed in
this conversation yet, `audit_position_out_of_range` (with `optionCount`) when
the number is off the end of the list. A snapshot naming a customer outside the
caller's scope still returns a bare `scope_denied`, identical to an unknown or
unauthorized audit, so nothing about another tenant leaks through the shape of
the refusal.
`get_audit_summary` accepts no model-supplied audit ID and can only reload the
audit already selected in the server conversation context. The model never
reconstructs IDs or re-lists an ordinal mapping.

Follow-up Hatch Analysis questions use an explicit selected customer, flock,
and audit context on the conversation. Resolving a different customer or flock
clears the selected audit, and audit-specific tools return
`fresh_audit_selection_required` until the user selects an audit again. This
prevents an older successful audit event from silently surviving a context
change. Audit summary and breakout reads also compare the loaded audit's
customer and flock with the complete persisted selection. Every successful
tool-context write is conditional on both the state version and the context
generation in which that tool began, so an in-flight tool from before `/new`
cannot repopulate cleared context.
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

Two read-only benchmark tools answer breed-standard questions from the global
reference tables `bmk_breeds` and `bmk_egg_breakout` (read-all-authenticated
RLS, no customer scope filter). `get_breed_benchmark` takes a breed name and
an age in weeks; the breed is resolved against the live vocabulary in
`bmk_breeds` (never a hardcoded list) using an exact normalized match or a
unique prefix match, and an ambiguous or unmatched prefix returns
`breed_not_found` with the current `availableBreeds` list. A resolved breed
with no row at the requested week returns `week_out_of_range` with that
breed's own `coveredWeeks` min/max instead of substituting or interpolating a
nearby week's value. `get_egg_breakout_benchmark` takes only an age in weeks
and follows the same never-substitute contract against `bmk_egg_breakout`,
reporting `week_out_of_range` with the table's covered week range when no row
matches. Both tools are pure lookups with no write path. `get_egg_breakout_benchmark`
accepts the same optional `metrics` argument as `get_breed_benchmark`, with
keys `infertile`, `early_24h`, `early_48h`, `blood_ring`, `black_eye`,
`early_dead`, `mid_dead`, `late_dead`, `external_pip`, `cracked` and
`contaminated` (`BREAKOUT_REQUESTABLE_METRICS`; `contaminated` maps to the
`contamPct` column), and returns the same
`requested`/`unavailable`/`unknownMetrics`/`context` shape. A `metrics`
argument whose tokens match no known key returns an empty `requested` plus
`unknownMetrics` and never degrades to the flat eleven-field row, which is
what previously caused the model to read every metric aloud.

`get_breed_benchmark` also accepts an optional `metrics` argument: a
comma/space-separated list of keys from `production`, `hatchability`,
`fertility`, `hof`, `egg_weight`, `chick_weight` (`bmk_tools.ts`'s
`BREED_REQUESTABLE_METRICS`, parsed by `parseRequestedMetrics`). When one or
more known keys are supplied, a resolved lookup returns a shaped payload —
`{ breed, ageWeek, requested: [{ metric, value, unit }, ...], context: {
...fullRow } }` — instead of the flat row: `requested` carries only the asked-
for fields in request order (deduplicated), and `context` carries the
complete row for the model's own understanding, not for reciting. An
unrecognized or empty `metrics` string (or the argument omitted entirely)
falls back to the original flat `{ ...row }` shape unchanged. This exists so
the realtime voice channel can ask for exactly the metric it needs instead of
receiving every metric on every lookup; the miss paths (`breed_not_found`,
`week_out_of_range`) are unaffected by `metrics`.

A third benchmark tool, `get_operational_standards`, reads
`bmk_operational_standards` instead and, unlike the two global lookups above,
is customer-scope-checked: a hatchery's operational-standard overrides belong
to one customer. It takes optional `stationKey`, `sectorKey`, and
`hatcheryId` filters. With no `hatcheryId` it returns only the global rows
(`hatchery_id is null`). With a `hatcheryId`, it resolves that hatchery's
owning customer via `findHatcheryCustomerId`, rejects with `scope_denied` if
the hatchery is unknown or its customer is outside
`scope.allowedCustomerIds` (never returning an empty result to hide the
mismatch), and otherwise merges the global rows with that hatchery's rows,
keyed on `metricKey` so a hatchery row overrides the matching global row —
the same precedence `BmkRepository.getOperationalStandards` implements in the
Flutter app, so the agent and the BMK screen never disagree. The merged rows
are then filtered by `stationKey`/`sectorKey` when supplied and sorted by
`sortOrder` then `metricLabel`. This tool is also a pure lookup with no write
path.

A fourth tool, `compare_selected_audit_to_benchmark`, takes no arguments and
never accepts or reconstructs an audit ID -- it operates only on the audit
already selected in the conversation, the same contract as
`get_selected_audit_breakouts` and `get_audit_summary`: if no audit is
selected, or the conversation's remembered `customerId`/`flockId` no longer
matches the fetched audit's own `customerId`/`flockId` (a stale selection --
e.g. the customer picked a different flock after the audit was selected), it
returns `fresh_audit_selection_required` with
`{ selectedCustomerId, selectedFlockId }` via the same
`freshAuditSelectionRequired` helper the sibling tools use, rather than
comparing against the wrong audit's benchmark. It resolves the selected audit's breed and
flock age against `bmk_breeds`/`bmk_egg_breakout` via the same
`resolveBreedBenchmark`/`resolveEggBreakoutBenchmark` functions the read tools
use, then reads that audit's breakout rows and aggregates each metric's actual
value with `sampleWeightedMean(rows, valueKey, 'traySize')` (not a plain
average). It compares `hatchabilityPct`, `fertilityPct`, and `hofPct` (present
on breakout rows) plus `productionPct`, `eggWeightG`, and `chickWeightG` (no
breakout-row actual, always reported with `reason: 'no_actual'`) against the
breed benchmark, and all eleven `bmk_egg_breakout` defect percentages against
the breakout benchmark -- the audit's `contaminatedPct` column maps explicitly
onto the benchmark's `contamPct` column. For the four metrics that exist on
both `fresh_egg_breakout` and `candled_egg_breakout` (`infertilePct`,
`early24hPct`, `early48hPct`, `bloodRingPct`), the actual is deliberately a
single sample-weighted blend across every breakout-type sample rather than one
figure per breakout stage: the published `bmk_egg_breakout` benchmark carries
exactly one target per age week regardless of which breakout stage measured it,
so blending the actuals before comparing against that single target is the
intended design, not an oversight. Each comparison reports `actual`,
`standard`, `observedRows`, and `delta = actual - standard` rounded to one
decimal via `roundTo`; a metric missing its benchmark value reports `reason:
'no_benchmark'` and a metric missing its actual reports `reason: 'no_actual'`,
but neither is ever dropped from the result. If the breed/week benchmark
cannot be resolved at all, the tool short-circuits to the same
`breed_not_found`/`week_out_of_range` shape `get_breed_benchmark` returns, with
no `comparisons` array. If only the breakout benchmark is unavailable, breed
metrics still compare normally and every breakout metric individually reports
`reason: 'no_benchmark'`, signaled by `breakoutBenchmarkAvailable: false` on
the result. This tool is read-only; it never writes and the audit store
argument to `createAgentBmkToolHandlers` is optional so the tool is only
registered where an audit store is wired in.

`get_audit_summary` and `get_selected_audit_breakouts` also attach a
`benchmark` block to every result, so the agent sees the matching standard on
a plain audit read without asking `compare_selected_audit_to_benchmark`
separately. The block is always present, never silently omitted. When a BMK
store is wired in (`createAgentAuditToolHandlers(store, { bmkStore })`,
`bmkStore` optional for backward compatibility) it resolves the selected
audit's breed and flock age through the same `resolveBreedBenchmark`/
`resolveEggBreakoutBenchmark` functions `compare_selected_audit_to_benchmark`
uses and returns `{ status: 'ok', breed, ageWeek, breedStandard,
breakoutStandard }`, with `breakoutStandard` explicitly `null` when only the
breed benchmark resolves. Otherwise it returns `{ status: 'unavailable',
reason }` with `reason` one of `benchmark_unavailable` (no `bmkStore` wired),
`missing_breed`, `missing_flock_age`, `breed_not_found`, or
`week_out_of_range` -- never a substituted or interpolated benchmark. On the
two resolver misses the block also carries the resolver's coverage payload
through: `availableBreeds` on `breed_not_found`, and `breed` plus
`coveredWeeks` on `week_out_of_range`. That is what lets the agent obey its
own "say what is covered and ask" prompt rule straight from an auto-attached
block, with no second tool call.

The voice policy (`CHICKMARK_REALTIME_POLICY` only — the typed policy is
unchanged) additionally carries a "Report vs benchmark routing" block. It
exists because a live call asked for the last breakout REPORT
("إيه آخر تقرير break out موجود عندك؟") and was answered from the published
standard. The block draws exactly one distinction — a published STANDARD
versus a recorded AUDIT REPORT — and states that nothing else about tool
choice changes. The decision is made silently from the user's wording: the
model must never ask the user which of the two they meant, nor offer them as
options. Ambiguous wording DEFAULTS to the standard, and a question that
gives a flock age in weeks or names no customer is a standard question
answered without asking who the customer is. Only wording that actually names
recorded data (آخر تقرير، آخر breakout، آخر audit، التقرير بتاع العميل،
النتيجة بتاعتنا، السجل) routes to `resolve_customer_flock`,
`list_customer_audits`, `select_audit_option`, `get_audit_summary`,
`get_selected_audit_breakouts` and `compare_selected_audit_to_benchmark`; a
report request is never answered from a benchmark tool, and when no customer
is resolved the model asks exactly one short question and calls no benchmark
tool that turn. Arguments are never carried forward from an earlier benchmark
turn into a report request. The block also records that the egg-breakout
standard is age-only, so the model must not ask which breed before calling
`get_egg_breakout_benchmark`, and that questions which are neither a standard
nor an audit report (flock counts, customer and flock contexts, hatcheries,
station records) keep their existing tools. Each of those last constraints was
added after live canaries caught the model demanding a breed for the
breed-less table, asking "لأي عميل؟" for plain standard questions, and asking
the user out loud whether they meant a standard or a report.

The agent's system prompt (`CHICKMARK_AGENT_POLICY` in
`supabase/functions/telegram-hatchery-agent/agent_prompt.ts`) carries a
"Benchmark discipline" rules block: benchmark figures may only come from
`get_breed_benchmark`, `get_egg_breakout_benchmark`, and
`get_operational_standards` -- the agent must never state a benchmark from
memory; any benchmark figure must be stated alongside its breed and age in
weeks; the `breed` argument to `get_breed_benchmark` must be the Latin-script
breed name — a breed the user names in Arabic script or informally (روس,
كوب/كاب, هبرد) is transliterated before the tool call, never passed in Arabic;
on `breed_not_found` the agent compares the user's wording against the returned
`availableBreeds` and, when exactly one entry plausibly matches, asks a single
"do you mean X?" confirmation (e.g. هل تقصد سلالة كوب 500؟) and only calls the
tool with that breed after the user confirms — only when nothing plausibly
matches does it fall back to listing what is covered; a `week_out_of_range`
tool result must be relayed as what is covered plus a clarifying question,
never interpolated, extrapolated, or answered with a nearby week; and judging
how an audit performed must go through `compare_selected_audit_to_benchmark`
rather than the agent subtracting numbers itself.

The same prompt's "Conversation behavior" block requires the model to output
only the final user-facing reply: internal planning, conversation analysis,
policy/tool deliberation, and third-person self-narration ("We need to
interpret the user's request", "the assistant should") are explicitly
forbidden from the reply text. This guards against reasoning-style models
(the OpenRouter path in particular) bleeding their chain-of-thought into the
message channel. The Responses provider caps each model call at
`max_output_tokens: 2400` (raised from 1200, which reasoning models could
exhaust mid-answer, truncating the reply).

`CHICKMARK_AGENT_POLICY` (Telegram and typed Pip only — NOT
`CHICKMARK_REALTIME_POLICY`, which is parked) also carries a "Grounding
guard" block, added at `CHICKMARK_AGENT_POLICY_VERSION` 1.2.0: a value that
belongs to a specific flock, hatchery, farm, user, session, production
record, metric, or other database state must come from an appropriate tool
result or already-grounded trusted context earlier in the conversation —
never invented, estimated, interpolated, or carried over from an example, a
similar-sounding record, or a benchmark figure. When such a value is needed
and nothing grounds it, the model says it is unavailable or asks one focused
clarification rather than producing a number. The rule is deliberately
scoped narrower than it might read at first: it does not restrict general
veterinary/husbandry reference knowledge that is not specific to this user's
own data, and it does not restrict arithmetic on values the user themselves
already supplied earlier in the same conversation, so the model is not
pushed into over-refusing ordinary questions it can safely answer.

An on-demand text-agent model-acceptance harness lives in
`supabase/functions/app-hatchery-agent/evals/` (see its README), built to
decide whether a candidate OpenRouter model is fit to drive this agent.
`google/gemma-4-31b-it:free` (fallback `openai/gpt-oss-20b:free`) passed this
harness and was the OpenRouter default through 2026-08-19. As of 2026-08-20
the OpenRouter text default moved to the PAID (non-`:free`) tier for
reliability: primary `openai/gpt-oss-120b`, fallback `openai/gpt-oss-20b` —
see `resolveOpenRouterTextModels` in `_shared/pip_model_routing.ts` and the
fallback ladder described below. `google/gemma-4-31b-it` (the same model,
paid tier) was kept on as a separate, dedicated VISION model rather than
retired, because `openai/gpt-oss-120b`/`-20b` are text->text only and cannot
accept image or video input — see "Vision routing" below.
Unlike
the Pip Realtime harness it is modeled on
(`services/pip-realtime-sideband/evals/`), it drives the REST
`/v1/responses` endpoint rather than a WebSocket, because that is what this
agent's provider actually uses, and it imports the real production artefacts
directly rather than re-declaring them: `AGENT_MODEL_TOOL_DEFINITIONS` from
`agent_tools.ts`, `buildAgentInstructions` from `agent_prompt.ts`, and a
request body and multi-round tool loop copied field-for-field from
`createResponsesAgentProvider`/`runAgentTurn`. `run_probe.ts` is a fast
7-check tool-calling compatibility gate; `run_evals.ts` is an 18-scenario,
9-dimension scored acceptance suite runnable against any `--model` so two
candidates get the identical suite, with `--json` output for cross-model
diffing. Both cost real money against a live provider and are, like the Pip
Realtime suites, deliberately not part of `deno test`. One dimension,
`report_vs_benchmark`, is a genuinely open question for this channel rather
than a check against a documented rule: the explicit "Report vs benchmark
routing" section (`REPORT_VS_BENCHMARK` in `agent_prompt.ts`) is voice-only
and is not part of `CHICKMARK_AGENT_POLICY`, the prompt this harness actually
sends — see the harness's own README for why that matters when reading a
failure on that dimension.

The same `evals/` directory also has a separate, on-demand MODEL-VS-MODEL
COMPARISON suite (`models.ts`, `comparison_scenarios.ts`, `run_comparison.ts`)
that answers a different question than the acceptance harness above: not "is
this one model fit to be the default", but "of several PAID OpenRouter
candidates that all advertise tool support, which is the cheapest one that
still meets our reliability bar". It is a pure evaluation tool — running it
never changes the live default model, a secret, or any runtime file; only the
human deciding the outcome does that separately. `models.ts` hand-pins a
pricing snapshot (dated) for five candidates —
`openai/gpt-oss-20b`, `openai/gpt-oss-120b`, `qwen/qwen3-30b-a3b-instruct-2507`,
`deepseek/deepseek-v4-flash-0731`, and `google/gemma-4-31b-it` (the current
production default, included as the baseline, not because it's cheapest) —
and `run_comparison.ts` re-verifies that snapshot against OpenRouter's live
`/v1/models` at startup, aborting before spending anything if an id has
vanished, no longer advertises `tools`, or its price has drifted.
`comparison_scenarios.ts` reuses `agent_client.ts`'s real transport and
`scenarios.ts`'s assertion primitives for 45 scenarios across 9 dimensions
(Arabic/mixed-language intent, tool selection, tool arguments, tool-result
reasoning, progressive disclosure, brevity, hallucination/grounding,
multi-turn conversations, and degradation under a long/loaded conversation).
`run_comparison.ts` runs every scenario `--repeats` times per model (default
3, since temperature 0 was observed not to guarantee identical tool choices
across runs) to separate a consistent defect from noise, retries a transient
transport error with backoff and marks a scenario-repeat that still can't
complete `INCONCLUSIVE` (excluded from every pass-rate metric and reported
separately, never scored as a model failure), and enforces a real-money
`--max-cost` budget guard (default $2.00) checked before every scenario-repeat
against OpenRouter's own reported `usage.cost` — `agent_client.ts`'s
`Round`/`TurnResult` were extended, additively, to parse and return that
`usage` block (tokens and cost) for exactly this purpose. It reports, per
model, a weighted composite score (30% tool selection+arguments, 20%
grounding, 20% Arabic/mixed, 15% scope/progressive-disclosure/brevity, 10%
latency, 5% cost) alongside a separate hard PASS/FAIL gate — any failing
assertion in tool selection, tool arguments, hallucination/grounding,
multi-turn, or degradation-under-load disqualifies a model regardless of its
weighted score — plus estimated cost per 1000 realistic Pip turns (derived
from the measured calls-per-turn ratio in that run). Like the acceptance
harness, it is deliberately not part of `deno test`.

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
Legacy flocks whose sector is still unassigned return
`missing_flock_sector` with an understandable Arabic/English instruction
instead of being reported as unauthorized. Station schema arguments are
validated against the generated registry's exact schema key/version pairs;
unknown pairs return `unsupported_station_schema` before any station handler or
database query executes.

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
For the OpenRouter provider, `createResponsesAgentProvider` (`agent_provider.ts`)
runs a one-step fallback ladder rather than a single hardcoded retry:
`classifyProviderFailure` classifies each attempt's failure into an exact
reason-code table. Fallback-eligible (retried once on the configured
fallback model): a transport error, the provider's own per-attempt timeout,
HTTP 400/402/404/408/429/5xx, an HTTP 200 body carrying an error envelope
instead of a result, a malformed body, or an empty `output` array.
Not eligible (thrown immediately, no fallback): HTTP 401/403 (a bad or
blocked key — a second model cannot fix that), HTTP 413 (the fallback has a
SMALLER context window, so retrying only makes it worse), and an
already-expired turn deadline, which is rethrown untouched rather than
classified. At most one fallback attempt happens per `respond()` call, never
to a fallback that is absent, blank, or equal to the primary, and never to
the paid OpenAI API — the fallback stays on OpenRouter. Once the primary has
failed eligibly once within a turn, later `respond()` calls in that SAME turn
skip the doomed primary attempt entirely and go straight to the fallback
model ("sticky" fallback), because a rate-limited or unavailable model does
not usually recover mid-turn; stickiness lives on the provider instance,
which both doors construct fresh per incoming request, so it never survives
into a later turn. Diagnostic provider-response identities are bounded to
160 characters, and the stored model prefers the concrete model returned by
the provider over a routing alias when that metadata is available.

**Vision routing.** Before choosing a model, `respond()` inspects the call's
`input` for visual content (`requestIsVisual` in `agent_provider.ts`): any
content part with `type === 'input_image'`, or an `input_file` part whose
filename or MIME type indicates an image or video (`.jpg`, `.png`, `.mp4`,
`video/*`, etc.). A visual call is routed to `ResponsesAgentProviderConfig.
visionModel` instead of the text `model`/`fallbackModel` pair; when no
`visionModel` is configured (true for the OpenAI-provider branch of both
doors today), a visual call just takes the ordinary text route, unchanged
from before vision routing existed. `visionModel` defaults to
`google/gemma-4-31b-it` (paid tier) via `resolveOpenRouterTextModels(...)
.vision` in `_shared/pip_model_routing.ts`, overridable with
`OPENROUTER_VISION_MODEL`.
The text fallback model (`openai/gpt-oss-20b`) is text->text and cannot
accept image or video input, so a failed vision call NEVER falls back to it
— that would guarantee a second failure, not retry anything. The vision
route has its own, entirely independent, optional fallback,
`visionFallbackModel` (env `OPENROUTER_VISION_FALLBACK_MODEL`), which
defaults to UNSET: with no vision fallback configured, a failed vision call
throws `AgentProviderError` as that call's terminal outcome, with telemetry
intact, after exactly one attempt. Sticky fallback (above) is tracked as two
separate reasons, one per route, inside the same provider instance — a text
call going sticky within a turn never forces a later vision call in that
same turn onto a text model, and vice versa; each route only ever remembers
its own prior failure. `AgentProviderTelemetry` carries `visionRouted:
boolean` so a call's route is visible in the aggregated per-turn telemetry
below, and `requestedModel`/`actualModel` report the vision model, not the
text primary, on that path.
Both doors' `readAiConfig()` wire `visionModel`/`visionFallbackModel`
through only on the OpenRouter branch, from `resolveOpenRouterTextModels`.
The app door (`app-hatchery-agent/index.ts`) hardcodes `attachment: null`
for every turn regardless of this wiring, so vision routing is reachable
only from Telegram today; sending an image (or a video re-sent as a
document, since Telegram's native video message type is not parsed by
`describeSource` — see the source comment on `requestIsVisual`) is the only
way to exercise it before the app gains its own attachment upload path.

Every text-agent turn — replied or failed — emits one structured
`agent_turn_telemetry` log line, aggregated across every `respond()` call the
turn made (a turn can make several: one per tool-calling pass, plus the
final-answer pass, and with sticky fallback different calls can land on
different models): door, conversation id, turn status, provider, primary and
fallback model, the models actually used in call order, whether/how many
calls fell back and why, provider response ids, total latency, and tool-call
count. It never logs message text, reply text, tokens, or provider keys. A
`replied` turn's outbound row also persists this same turn-aggregated object
in `agent_conversation_turns.provider_telemetry_json` (nullable); a failed
turn writes no outbound row at all, so the log line is its only durable
trace.
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
allocated index within the current context generation, and the exact inbound
evidence is persisted before the runtime starts. The corresponding assistant
turn carries the same turn index, the context generation, an explicit
`reply_to_turn_id`, provider/model/response metadata when a model was used, and
pending delivery before Telegram is called; it is then marked delivered or
failed. Tool calls carry their serial order within the inbound turn. A Telegram
retry sees the original inbound update and cannot rerun the model or duplicate
a delivered reply. Provider or tool failures never fall through into a second
conversational implementation.

The exact `/new` or `/reset` Telegram command starts a new context generation
without calling the model. It clears the selected customer, flock, audit,
pending action, and active visit, stores an ordered bilingual reset reply, and
keeps every earlier turn and tool event available as immutable review evidence.

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
answer to the current summary moves that station to admin review. There is no
Pasgar-specific interpreter or controller conversation path.

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
This legacy compatibility extractor boundary remains available for existing
draft records and compatibility tests; it is not the live Telegram webhook
conversation path.

Pip routes model choices by workload through one internal router. OpenAI typed
app and Telegram conversations use `OPENAI_TEXT_MODEL` when it is set
(trimmed), or `gpt-5-nano` by default; they never inherit the extraction-only
`OPENAI_MODEL`. OpenRouter conversation routing remains explicitly configured
with `OPENROUTER_MODEL` or `AI_MODEL`, defaulting to `openai/gpt-oss-120b`
(text fallback `openai/gpt-oss-20b` via `OPENROUTER_FALLBACK_MODEL`), plus a
separate vision route defaulting to `google/gemma-4-31b-it` via
`OPENROUTER_VISION_MODEL` (optional fallback `OPENROUTER_VISION_FALLBACK_MODEL`,
unset by default — see "Vision routing" above for why the text fallback is
never reused for a failed vision call). The router also pins the live default to
`gpt-realtime-2.1-mini`, recorded-note transcription to
`gpt-4o-mini-transcribe`, and recorded-note speech to `gpt-4o-mini-tts`.
Live-call captions (the Realtime session's own input-audio transcription,
configured by the sideband) default to `gpt-4o-mini-transcribe` as well
($0.003/min instead of `gpt-live-transcribe`'s $0.017/min); the live call
itself never touches the standalone `/audio/transcriptions` or `/audio/speech`
endpoints. The `languages` (plural) and `delay` transcription parameters are
`gpt-live-transcribe`-only: any other model rejects the entire
`session.update` with `invalid_value` (provider-named, live, 2026-08-17), so
`buildSessionUpdate` includes them only for that model. The SINGULAR
`language` field is different and is supported by the default model too —
verified accepted for `gpt-4o-mini-transcribe` on a live probe connection
(`tools/probe_session_knobs.ts`, 2026-08-19), echoed back as `"ar"`.
`buildSessionUpdate` sends it, set from `PIP_REALTIME_TRANSCRIPTION_LANGUAGE`
(default `ar`), for every transcription model except `gpt-live-transcribe`
(which keeps only its own `languages`/`delay` shape); an empty string omits
the field entirely and is the no-code-deploy rollback knob. The transcription
prompt (`TRANSCRIPTION_PROMPT` in `src/session_config.ts`) is bilingual —
Egyptian-Arabic framing and Arabic hatchery terms alongside the original
English term list — replacing an English-only prompt that, combined with no
language hint at all, had been biasing the transcriber into hallucinated
English captions ("Hello, world.", "I'm Elly.", "In Tamil") over Egyptian
Arabic audio, polluting stored conversation history.

`session.max_output_tokens` caps a single spoken reply; the sideband had never
set it before, and the provider's own default is unbounded (echoed `"inf"`,
`tools/probe_session_knobs.ts`, 2026-08-19). It is set from
`PIP_REALTIME_MAX_OUTPUT_TOKENS` (default `1536`, valid range 200-4096,
out-of-range values fail startup rather than clamping). The default was
chosen from measured `response.usage.output_tokens` for every reply size the
voice policy allows (`tools/probe_output_tokens.ts`, 2026-08-19,
`gpt-realtime-2.1-mini`, production session payload): a greeting costs 66
tokens, a single metric 60, two metrics 145, a six-metric breed summary 488,
and an eleven-metric dump — the shape of a 2026-08-19 incident — 761. The
largest reply the policy legitimately permits is an EXPLICITLY requested full
eleven-metric breakout summary, measured on the live canary path at 832 and
865 tokens. 1536 is roughly 1.8x that, so ordinary variance cannot truncate a
real answer mid-word (`max_output_tokens` truncation is not graceful; the
response stops and comes back `incomplete`). It is deliberately not sized to
cut the 761-token dump — that is cured at its source by the shaped tool
payload and the report-vs-benchmark routing policy — and exists only as a
backstop against an unanticipated payload.

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
`AI_PROVIDER`, `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `OPENROUTER_FALLBACK_MODEL`,
`OPENAI_API_KEY`, `OPENAI_MODEL`, `OPENAI_TEXT_MODEL`, `AI_MODEL`, `SUPABASE_URL`, and `SUPABASE_SERVICE_ROLE_KEY`
only from its server environment. Either `OPENROUTER_API_KEY` or
`OPENAI_API_KEY` must be present for extraction. Deployment must disable
Supabase JWT verification for this signed webhook; the function itself
authenticates Telegram's secret-token header.

The `app-hatchery-agent` Supabase Edge Function is the second door into that
same agent. It is deployed with Supabase JWT verification enabled, so every
call carries the signed-in user's access token, and it reuses the existing
brain verbatim: the same turn runner, the same unified tool handlers, the same
Responses provider, the same prompt, and the same tool catalog. It adds no
agent tools of its own. Scope is recomputed from `profiles` on every request
rather than stored: an approved admin receives the current customer catalog, an
approved customer receives its own customer, and an approved auditor receives
its `auditor_customers` list. Any profile that is not `status='approved'` is
refused. The function then ensures one `app` staff-link row for the caller
under a deterministic `app-<auth uid>` id, so app turns produce the same
durable conversation evidence as Telegram turns.

Each app user can have any number of conversations, stored in the existing
`agent_conversations`, `agent_conversation_turns`, and `agent_tool_events`
tables, one `agent_conversations` row per `(staff_link_id, telegram_chat_id)`
under the caller's single app staff-link id. `telegram_chat_id` doubles as the
conversation key: `'app'` is the legacy single conversation (also the row the
staff-link resolution itself always ensures), and `'app:<uuid v4 lowercase>'`
keys any additional conversation the same app user opens — validated against
`APP_CONVERSATION_KEY_PATTERN`, a strict lowercase-v4-UUID regex. `send`,
`history`, and `reset` all take an optional `conversationId` field carrying
this key; a missing or null value resolves to the legacy `'app'` conversation,
preserving pre-multi-conversation behavior exactly, and any other value must
match `'app'` or the `'app:<uuid>'` shape or the request is refused as
`invalid_request`. A conversation row is created lazily on first use
(`loadOrCreateConversation`), so opening a fresh `'app:<uuid>'` key from the
client costs nothing server-side until the first `send`. `send`, `history`,
and `reset` responses all echo `conversationKey` alongside `conversationId` (a
convenience for a client that only tracks the key), and each `history`
message additionally carries `source` — `'voice'` when the turn's
`source_channel` is `'realtime_voice'` (a Pip Live call transcript), `'text'`
otherwise.

A new `conversations` action (`{"action":"conversations"}`, no
`conversationId`) lists the caller's own conversations — up to `limit`
(default 50, max 100) — as `{conversationKey, title, lastMessageText,
lastMessageAt, updatedAt, createdAt}`, newest-`updatedAt`-first. It queries
every `agent_conversations` row for the staff-link id whose key starts with
`'app'` (defensively re-validated against the exact key shape rather than
trusting the SQL `like` prefix match), then loads each conversation's newest
turn with text for the preview (truncated to 140 characters). A conversation
with no turns yet, no title, and that isn't the legacy `'app'` key is a bare
placeholder — nothing yet distinguishes it for the caller — and is omitted
from the list rather than shown empty.

`agent_conversations.title` (added in schema v60, `NULL` until set) is
derived once, server-side, from the caller's first user message in a
conversation: `conversation_title.ts`'s `deriveConversationTitle` collapses
whitespace, keeps at most 48 characters (cutting at the last word boundary at
or after character 12 when one exists in that range, otherwise a hard cut),
and strips trailing Latin or Arabic punctuation left over from the cut. It is
set the first time `send` stores a conversation's first inbound turn
(`maybeSetConversationTitle`) and is otherwise never overwritten; the write is
best-effort and never blocks the reply, and the title itself is never logged
(it is message text). A conversation opened but never sent into keeps
`title = NULL` and is the placeholder case omitted from `conversations` above.

`send` takes either a 1 to 4000 character `message` or an `audioBase64` clip up to
`MAX_AUDIO_BASE64_CHARS` (1,500,000 characters — numerically equal to the
client's `assistantAudioMaxBase64Chars`; an oversized clip is rejected with
`invalid_request`), plus a client-supplied idempotency key, stored as
`telegram_update_id = 'app:<id>'`,
so a replayed send returns the stored reply instead of calling the model
again (and, for voice, never re-transcribes). When `audioBase64` is present,
the function transcribes it via OpenAI (`gpt-4o-mini-transcribe`) using a
dedicated `OPENAI_VOICE_KEY` secret when set, falling back to the text
brain's `OPENAI_API_KEY` otherwise (so voice works immediately off whichever
key is already configured; a separate key only isolates voice spend once one
is explicitly added) — and runs the resulting transcript through the same
reasoning route and unmodified agent brain used for typed messages; a transcription failure or an
empty transcript returns `agent_unavailable` rather than `invalid_request`,
since it is an audio-quality problem, not a malformed request. The stored
turn's `text` is the transcript, indistinguishable from a typed turn once
saved. The function then attempts to synthesize the reply via OpenAI TTS
(`gpt-4o-mini-tts`, voice `cedar` — deliberately the same voice Pip Live uses,
so Pip does not change vocal identity between a recorded note and a live
call), steering pronunciation with the model's `instructions` field when the
reply's detected language is `ar` or `mixed`. Those instructions name Egyptian
Colloquial Arabic (Cairo) explicitly and rule out Modern Standard Arabic and
other regional accents, including the Egyptian pronunciation of ج and ق; the
`mixed` variant additionally asks for English technical terms to stay in
English rather than being transliterated. English replies pass no
instructions. On success the response
carries `audioBase64` for the phone to play back, but a TTS failure is
swallowed and the call still succeeds with the text-only reply, since speech
is a presentation layer over an already-successful turn.
`send` always answers with the conversation ID, the user and reply turn IDs,
the reply text, its language, and a creation time; a voice `send` additionally
returns `transcript` and, when synthesis succeeded, `audioBase64`.
`history` returns the current context epoch's turns oldest-first. For a
conversation the user has opened but not yet sent anything in there is no
server row at all, and `history` answers `{conversationId: null, messages: []}`
rather than an error; the Flutter client treats that id as optional
(`AssistantChatHistory.conversationId` is nullable) so a first open renders an
empty conversation, not an error banner. `reset` bumps
the context epoch, which hides earlier turns from both the user and the model
while retaining them as immutable evidence, matching what `/new` does on
Telegram. Sends are limited to 20 per user per rolling five minutes. Failures
return a code with the error: `invalid_request`, `unauthenticated`,
`not_approved`, `rate_limited`, `agent_unavailable`, or `server_error`. Besides
the `audioBase64` voice input, the door accepts no other attachment or image
field; any such field is rejected as an invalid request.

`supabase/functions/app-hatchery-agent/voice_contract_fixture.json` pins the
exact field-name lists for a voice `send` request and response. Both
`index_test.ts` (Deno) and `assistant_chat_service_test.dart` (Dart) read this
one physical file and assert their own side's actual request/response keys
against it, so a field rename on either side of the client/server boundary
without updating the fixture fails a test in that language.

Only approved admins have an `Agent` main-shell destination.
Auditors and customer-role users do not receive that destination. The screen
and `AgentMonitorProvider` repeat the approved-admin check before loading or
mutating the offline agent mirror, so unauthorized users cannot create pending
local agent-setting writes that remote RLS will reject. For approved admins,
the Agent Monitor loads the locally mirrored agent setting and newest draft
batches plus pending and allowed Telegram staff links, automatically selects
the newest available batch, and preserves the selected batch across refreshes
while it remains available. Admins can refresh the monitor, approve or reject
pending Telegram staff access, and pause or resume Telegram ingestion through
the persisted agent setting. Telegram running/paused state is
cloud-authoritative: the monitor keeps showing the previous confirmed state
and disables its refresh and pause/resume controls while it performs a targeted
Supabase write. Only the verified row returned by Supabase is mirrored to
SQLite and published to the UI. A cloud failure preserves the prior state and
shows an error, so Telegram follows a successful toggle immediately without an
app restart. Approval opens an assignment sheet instead of
granting access immediately: the default customer role requires one customer
selection, while the explicit agent-admin role grants all-customer access and
cannot carry a customer restriction. Allowed Telegram users appear with their
enforced scope and can be reassigned or revoked. The model, repository,
provider, SQLite checks, and Supabase constraints all repeat the role/customer
consistency rule. Rejection or revocation changes the link to `revoked`. The
original unauthorized message remains unprocessed, so staff must resend the
hatchery data after approval.

The monitor also loads a bounded health summary and latest conversation
diagnostics from the server-authored mirror: conversation count, pending and
failed deliveries, rejected/failed tools, flocks still missing sectors,
selected customer/flock/audit labels, latest reply order, delivery state, and
provider/model metadata. Pending replies mark health as needing attention;
conversation ordering uses the newest stored turn rather than only the
conversation row timestamp, and the newest rejected/failed tool exposes its
bounded code and occurrence time. Missing selections, missing mirrored records,
legacy replies without model metadata, and unassigned flock sectors have
distinct plain-language messages. The monitor explains that `/new` clears
current Telegram context while retaining prior evidence. Its preloaded-provider
guard avoids duplicate refreshes, and narrow draft workspaces reduce their list
height instead of overflowing.

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
`bmkAgeWeeks`), panel sample/domain metadata fields (`sampleMode`,
`scopeType`, `sampleLabel`, `sampleIndex`, `sourceDomain`, `actionDomain`,
`recommendationTarget` — all nullable),
panel-specific measurement and calculated summary fields, and sync fields.
Station save/reopen reads and writes the sample mode, scope, label, and index;
Egg station saves also write the three operational-domain fields.
The seven panel sample/domain metadata columns are also mirrored on every
Supabase panel table (`egg_storage`, `egg_quality`, `chick_quality`,
`chick_weights`, `fresh_egg_breakout`, `candled_egg_breakout`,
`residue_breakout`, `setter_optimizing`, `hatcher_optimizing`) under their
snake_case names (`sample_mode`, `scope_type`, `sample_label`, `sample_index`,
`source_domain`, `action_domain`, `recommendation_target`), added additively
and nullable so upsert batches from clients that do not yet write these
columns are unaffected.
The Supabase `egg_quality` table also carries eight nullable grading summary
columns — `grading_sample_size`, `grading_rejected_count`,
`grading_acceptable_count`, `grading_rejected_pct`, `grading_acceptable_pct`,
`grading_defects_json`, `grading_top_defect_code`, `grading_top_defect_pct` —
and a companion `egg_quality_defect_counts` table (one row per defect code per
`egg_quality` sample, unique on `(egg_quality_id, defect_code)`, cascade-deleted
with its parent) for visual egg grading. The matching local v62 schema,
repository, station save/reopen flow, sync path, and grading UI are active; the
child rows are the primary per-defect source and the parent summaries are the
dashboard mirror. RLS on `egg_quality_defect_counts` was tightened
(20260823130000) to match `egg_quality` character-for-character: a
`..._select` policy for `select` gated on
`chickmark_private.app_can_read_customer(customer_id)`, and a `..._write`
policy for `all` gated on `chickmark_private.app_can_write_customer(customer_id)`
in both `using` and `with check`. (The table's first migration,
20260823100000, shipped a blanket `using (true) with check (true)` policy —
that was corrected before any client wrote to the table.) A separate
`before insert or update` trigger derives `customer_id` from the parent
`egg_quality` row when the incoming row omits it, and rejects the write if an
explicit `customer_id` would cross the parent's tenant scope, in the same
shape as `chickmark_private.validate_hatchery_agent_scope()`.
Egg, chick, and breakout panel hierarchy can include `house`,
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
Remotely, a staff link records which door it belongs to. `telegram_staff_links`
carries a `channel` of `telegram` or `app` and, for app rows, an `app_user_id`
referencing the Auth user; `telegram_user_id` is nullable and unique only
within the Telegram channel, and a check constraint requires each row to
identify exactly one of the two. An app row with the `customer` access role may
leave `customer_id` null, because an app row is only an identity anchor: the
caller's real customer allow-list is recomputed per request from `profiles` and
`auditor_customers` rather than read from the link. Telegram rows keep the
existing rule that an allowed customer link names exactly one customer and an
allowed admin link names none. The local SQLite mirror carries the same two
channels: `telegram_staff_links` has a `channel` column defaulting to
`telegram` and a nullable `appUserId`, `telegramUserId` is nullable, and
uniqueness for each identity is enforced by a partial unique index over the
non-null values rather than a column constraint, so app rows without a Telegram
identity neither collide with each other nor fail insertion.
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
local customers, hatcheries, flocks, audit sessions, panel rows, egg-grading
defect counts, Govee captures, photo work, and tombstones in dependency order:
the `egg_quality_defect_counts` child batch follows every panel row (including
its `egg_quality` parent), and its device-local sync columns are stripped before
the normal camelCase-to-snake_case Supabase upsert. It pulls the child table
immediately after panel rows, also on customer-role pull-only devices, and
counts it in `SupabasePullSummary`. Removed legacy tables are not pushed or
pulled. It keeps newer local session, Govee, panel, and grading rows when a
pulled remote row has an older or invalid `updatedAt`. Local deletes
create `sync_tombstones`; startup sync uploads those tombstones, deletes remote
rows child-before-parent (including grading counts before `egg_quality`), marks
successful tombstones synced, and applies remote tombstones locally so another
device reload removes stale rows. Tombstone application keeps a row whose local
`updatedAt`, `dirtyAt`, or `createdAt` is newer than the tombstone's
`deletedAt`, preserving an intentional remove-then-re-add. Customer deletes
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
`BgSyncService` runs this sync after the shell starts and classifies the pass as
successful, definitively offline, or a transient failure for the automatic
coordinator. `AppSyncCoordinator` is the single scheduler for shell startup,
local-write, resume, and reconnect requests. It performs no callback while the
shared `NetworkStatusMonitor` is `unknown` or `offline`, coalesces repeated
offline requests without timers, runs once on a verified offline-to-online
transition, and applies bounded exponential backoff to failures while the
network remains uncertain. The monitor verifies reachability to the Supabase
host even when a Wi-Fi/mobile interface exists, so captive or uplink-less Wi-Fi
is not automatically treated as usable cloud access. Startup and background
sync can surface a Home-screen cloud notice
for sessions and other records pulled from another device after the local
database has previously synced. A successful foreground `Sync Now` action in
Home or Settings acknowledges that notice so it disappears after the user
manually syncs; offline or failed sync attempts leave the notice intact. The
Flutter Web sync path pulls photo metadata but skips the native-file photo
cache/upload pass, because browsers do not expose an application documents
directory. This keeps Supabase row sync successful on web while preserving
remote photo references; dashboard photo renderers turn those references into
short-lived signed storage URLs. The authenticated shell also requests a
debounced sync after local customer, hatchery, flock, audit-session, or panel
writes and on resume. Connectivity causes a run only on a verified reconnect
transition, not on every interface event. Concurrent requests share one sync
pass and a write that lands during that pass schedules one retry. Customer,
hatchery, and flock pushes use strict response verification so a database
trigger or policy cannot silently cancel a parent insert while the UI reports
it as uploaded. Before Supabase upserts, the client strips device-local sync
bookkeeping fields (`syncStatus`, `dirtyAt`, `lastSyncedAt`, and `syncError`)
and then converts business keys to the remote snake_case schema, preventing
local retry metadata from forcing a rejected camelCase fallback payload.
Production does not install the
`customers_keep_only_ghareeb` trigger; multi-customer inserts are supported and
existing device-local rows retry on the next automatic or manual sync.
Each table's push is isolated: a rejected batch marks only its own rows failed
and the run continues to the next table and then to the pull. The failure is
never silent. A sync outcome carries `failed` (rows that did not reach the
cloud this run) and `failedTables` alongside `pushed`, `pulled`, `conflicts`
and `pendingDeletes`; `hasFailures` and `fullySynced` classify the run, and
`failureSummary` / `statusMessage` render it. A run with failures ends on a
progress message naming how many rows did not upload rather than `Ready`,
shows a "Sync incomplete" snackbar for a manual Sync Now, and is recorded
through `SettingsProvider.recordSync(error:)` so the cloud status shows an
error. The customers screen only claims a deletion was synchronized when the
run was fully synced. A run that failed a push but completed its pull still
refreshes the dashboard; only a run that never reached the cloud does not.
Retries are bounded. Because dirty rows keep a `pending`/`failed` status and
are re-read every run, a table whose cloud counterpart is missing would
otherwise re-attempt the same doomed upload on every sync. After a failed
push, `SyncRetryPolicy` skips that table for an exponentially growing window —
1, 2, 4, 8, 16, then 30 minutes — and the first success clears the table's
state. Skipped batches are still counted in `failed`, so backing off never
hides the problem; the state is process-local, so restarting the app is an
immediate retry.
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
fields and every valid reading as chart points in `chartPointsJson`; the app
does not write separate generic Temp/RH session or reading rows.

Thermometer OCR is not used for EST/CVT capture. Egg Storage EST, Setter
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

### 7.x Supabase migration directories

`supabase/migrations/` holds the migrations that replay cleanly, in filename
order, against an empty database. Three scripts depend on that property. Each
spins up a throwaway PostgreSQL cluster, replays the directory, and then asserts
behaviour — not migration text — against the result:

- `scripts/test_supabase_security_hardening.sh` — RLS, grants and function
  hardening.
- `scripts/test_pip_realtime_persistence.sh` — the Pip Realtime V1 invariants
  (atomic turn allocator, evidence with no durable turn, the two claim key
  shapes, the Realtime operational tables) against empty agent tables.
- `scripts/test_pip_realtime_backfill.sh` — the same migration set *minus*
  `20260816120000_pip_realtime_v1_persistence.sql`, seeded with legacy agent
  rows shaped the way the pre-Realtime code wrote them (no `conversation_seq`,
  `source_channel` or `completion_status`; outbound turns reusing the inbound
  `turn_index`; `created_at` disagreeing with insertion order, id order and
  turn_index order; several context epochs including a conversation reset into
  an epoch with no turns). That migration is then applied over the data and
  every backfill is asserted: per-conversation `conversation_seq` unique and
  contiguous from 1 in `(context_epoch, created_at, id)` order, channel
  classification from `agent_conversations.telegram_chat_id`, `finalized`
  completion, `next_conversation_seq = max + 1`, `turn_index` counters seeded
  from the current epoch only, a fresh `public.allocate_agent_turn_slot`
  allocation that does not collide with any pre-existing row, `owner_profile_id`
  set only where the staff link carries an `app_user_id`, and the survival plus
  continued immutability of pre-existing `agent_tool_events`.

Filename prefixes match the versions recorded in
production's `supabase_migrations.schema_migrations`, so `supabase migration
list --linked` is a meaningful comparison.

Two sibling directories deliberately sit outside the replay set:

- `supabase/migrations_unapplied/` — written but never applied to production.
  `0009_customer_usernames.sql` is superseded (its `handle_new_auth_user()`
  body would overwrite the live account-type routing); `0017_performance_monitoring.sql`
  is deferred, and cannot apply as written because nine `public.flocks` rows
  carry a `farm_id` with no `farms` row to reference.
- `supabase/migrations_archive/` — applied in production but not replayable
  from empty. Currently `20260418043712_create_hatchaudit_schema.sql`, the
  pre-reset schema that `20260605115351_reset_and_vertical_slice.sql` drops.

A migration in either directory must not be moved back without a fresh
timestamp that sorts after every applied migration.

### 7.y Agent conversation ordering

Durable agent turns carry two ordering keys, and they mean different things.

`turn_index` is scoped to `(conversation_id, context_epoch, direction)` and is
enforced by `agent_conversation_turns_order_check` and the unique index
`idx_agent_conversation_turns_order`. For typed Pip and Telegram an outbound
reply reuses its inbound turn's index, which is what makes the pairing in
`reply_to_turn_id` readable.

`conversation_seq` is the chronological key across all durable turns of a
conversation, both directions. It is unique per conversation and does not reset
when `context_epoch` advances, so it gives one stable order for transcript
rendering, context loading and summary coverage ranges.

Both are issued by `chickmark_private.allocate_agent_turn_slot`, which locks the
conversation row and reads authoritative counters stored on
`agent_conversations` rather than re-deriving them from `MAX()`. Callers pass a
`turn_index` override to reuse an inbound index; the counter still advances past
it so a later independent allocation in the same epoch cannot collide.

Both text doors call that allocator through their service-role client for every
durable turn they write, and stamp each row with `source_channel`
(`telegram` or `app_text`) and `completion_status = 'finalized'`. Neither door
scans existing rows to guess the next index any more.

`supabase/functions/telegram-hatchery-agent/agent_context.ts` is the one loader
both doors use to assemble a turn's model context. It reads the newest
`AGENT_HISTORY_FETCH_LIMIT` (40) turns of the conversation's current
`context_epoch`, ordered by `conversation_seq` rather than `created_at`, keeps
only `completion_status = 'finalized'` rows, replays at most
`AGENT_MODEL_HISTORY_TURNS` (20) of them to the model oldest-first, and attaches
the conversation's active `agent_intake_sessions` row when one exists. A failed
history read fails the turn; a failed intake read only drops the intake.

### 7.z Pip Realtime session control plane

`supabase/functions/pip-realtime-session/` is the authenticated control plane
for Pip Realtime voice. It carries no audio, runs no agent turn and grants no
tool authority: it decides whether a voice session may exist, records that
decision, and hands the client the short-lived credentials to go and build one.
It is deployed with Supabase JWT verification enabled and re-reads the bearer
token through its service-role client.

Realtime is OpenAI-only. The function reads `OPENAI_API_KEY` and nothing else —
never `OPENAI_VOICE_KEY` (that secret belongs to the recorded-voice path in
`app-hatchery-agent`) and never `OPENROUTER_API_KEY` or the text provider
resolver, because a Realtime session has no text provider to fall back to. A
missing key means Realtime reports itself unavailable.

It accepts four actions on `POST /functions/v1/pip-realtime-session`:

- `start` accepts the same optional `conversationId` field as
  `app-hatchery-agent` (`'app'` or `'app:<uuid v4>'`; missing/null resolves to
  the legacy `'app'` conversation) — validated first, before any DB work or
  rate-limit/budget accounting, by `resolveConversationKey`. It then runs, in
  order: the runtime kill switch, the per-profile start rate limit, identity
  and scope resolution, the daily budgets, and the one-session invariant. On
  success it loads or creates that conversation (same lazy-creation shape as
  the app door) and binds the new session to it — `agent_realtime_sessions.
  conversation_id`/`context_epoch` — so a live call continues the exact
  conversation the client opened it from: both the transcript the sideband
  persists and the conversation-history context it injects (see 7.ab) are
  scoped to that conversation. It then creates the session and its
  generation-1 call row, mints an ephemeral OpenAI client secret, and returns
  the secret, a one-shot binding token, the session and generation ids, the
  sideband URL and the authoritative deadlines.
- `register_call` writes `openai_call_id` and `call_registered_at` onto the
  already-provisioned generation row and advances it to `call_registered`. That
  is the whole of it: it does not consume the binding token, claim the lease,
  advance the fencing token, mark the call active, or grant any tool authority.
- `abort_setup` is the narrow path for a client that created a call but cannot
  continue. It records the known call id and marks the generation
  `cleanup_pending` with `hangup_state = 'pending'` so the sweeper hangs it up.
  It grants nothing, and unlike `register_call` it still works after the setup
  deadline has passed — a client that blew the deadline is exactly the one that
  most needs to report its orphaned call id.
- `end` is user-initiated termination. It marks the session `ending` and the
  live generation `cleanup_pending`; the OpenAI hangup itself is left to the
  sweeper, so a user-facing action never blocks on a provider call that can
  hang. `end_reason` comes from a fixed vocabulary, not client free text.

Authorization is reused, not reinvented: `loadAppProfile`,
`resolveAppAgentScope`, `ensureAppStaffLink` and `APP_CHANNEL_CHAT_ID` come from
`app-hatchery-agent/app_agent_scope.ts`, so a Realtime session sees exactly the
scope typed Pip sees and, via the shared `conversationId` key, can join any of
the same app staff-link's conversations. From that the
function derives an `authorization_fingerprint` — SHA-256 over the staff-link
id, access role, sorted allowed-customer ids, profile role and profile status.
Conversation id, context epoch and state version are deliberately excluded
because they churn every turn and would flag a normal conversation as an
authority change. The fingerprint is stamped on the session and the generation
at provisioning time and recomputed on `register_call`; a demotion or a revoked
approval between `start` and `register_call` invalidates the session.

Budgets are enforced as **settled plus in-flight**, because usage settles only
when a session ends and a caller who never ends one would otherwise never
accrue anything. The gate sums today's (UTC) `agent_realtime_usage_seconds`
rows and adds, for every non-terminal session, `max(0, min(now, end of UTC day,
ready_at + MAX_SESSION_SECONDS) - max(ready_at, start of UTC day))`. A session
that never reached `authoritative_ready_at` contributes zero; an orphaned row
left by a crash cannot bill past its own ceiling; a session crossing midnight
does not charge tomorrow's seconds against today. Exhaustion returns a distinct
`budget_exhausted` code and is recorded as such on the attempt row.

The start rate limit writes its attempt row *before* counting, so a burst
cannot each read a stale count, and only attempts still marked `accepted`
consume the window — a refused start is downgraded to its real outcome and
never eats a later legitimate one. The one-session invariant is enforced by
REPLACEMENT: a `start` that finds the caller's own session still non-terminal
terminalizes it (`ended`/`replaced`), hands its generations to the sweeper as
`cleanup_pending` (the OpenAI hangup is never dropped), and provisions the
replacement — per the plan's race table. The partial unique index on
`agent_realtime_sessions` still decides a genuine concurrent race; only
SQLSTATE `23505` is treated as "you already have a session", so a genuine
insert failure surfaces as an error rather than as a plausible-looking
conflict. Two rapid concurrent starts from one profile may therefore both
return 200, the later displacing the earlier — the invariant is "exactly one
live session", never "somebody gets a 409".

Every instant the function persists comes from a single read of the **database**
clock, `public.realtime_now()`, taken once at the top of the request. Three
hosts arbitrate one deadline — this function writes `setup_deadline_at`, the
Cloud Run sideband evaluates it, and the SQL sweeper compares it against
`now()` — so they must share one clock or skew silently moves the deadline. If
that read fails the request is refused with `clock_unavailable`; it never falls
back to the Edge Function's own clock.

The binding token is 256 bits of CSPRNG entropy returned exactly once, in the
body of a successful `start`. Only its SHA-256 hash reaches
`agent_realtime_calls`, so no later read of the table — by an operator, a backup
or a leaked dump — can recover a usable token. Neither the token, the minted
client secret, nor the standing OpenAI key is ever logged.

Configuration lives in `pip-realtime-session/config.ts` as `PIP_REALTIME_*`
environment variables: `ENABLED`, `MAX_SESSION_SECONDS` (600),
`SETUP_DEADLINE_SECONDS` (60), `CLIENT_SECRET_TTL_SECONDS` (30),
`BIND_TOKEN_TTL_SECONDS` (60), `SESSION_START_LIMIT` (5),
`SESSION_START_WINDOW_SECONDS` (300), `DAILY_SECONDS_PER_PROFILE` (1800),
`DAILY_SECONDS_PER_TENANT` (14400), `TENANT_OVERAGE_FACTOR` (1.25),
`CLOUD_RUN_URL`, `MODEL` (`gpt-realtime-2.1-mini`) and `VOICE` (`cedar`, the warm
male voice; the rendered Live instructions additionally append a voice-only
delivery addendum — warm tone, Egyptian colloquial Arabic when the user speaks
Arabic, short spoken replies — after the shared typed-agent policy, versioned as
`<policy>+voice.N`). A malformed
or out-of-range value, or an incoherent combination such as a setup deadline
longer than the session ceiling, fails fast — it is never silently clamped,
because a clamped budget is indistinguishable from a working one until it costs
money. `tenant_id` resolves to `profiles.organization_id`; a caller with no
organization is subject to the per-profile budget only.

### 7.aa Pip Realtime voice client (Flutter)

**Parked behind a flag.** `FeatureFlags.realtimeEnabled`
(`lib/core/config/feature_flags.dart`) gates every UI entry point below and
defaults to **off** (`bool.fromEnvironment('PIP_REALTIME_ENABLED')`, no
`defaultValue`, so it is `false` unless built with
`--dart-define=PIP_REALTIME_ENABLED=true`). This is a stabilization-phase
parking, not a removal: no Realtime source file, service, test or doc was
deleted, and everything described in this section and in 7.z/7.ab/7.ac still
works exactly as written once the flag is on. With the flag off, "Pip Live" is
unreachable from the app:
- `MainShell` (`lib/features/home/widgets/main_shell.dart`) never constructs a
  `RealtimeVoiceController` and never provides one into the widget tree, at
  the shell level or into a pushed conversation route — this is the single
  choke point everything else follows from. The route guard and the push to
  `RealtimeVoiceScreen` are therefore unreachable, and the shell's Live body
  wrapper renders its bare content with no `RealtimeLiveBanner`.
- `AssistantChatScreen` (`lib/features/chat/screens/assistant_chat_screen.dart`)
  finds no controller via its nullable `context.watch`, so it shows no live
  control (`assistant-live`) next to the composer, in addition to an explicit
  `FeatureFlags.realtimeEnabled` check on the same condition — belt and braces
  against a stray provider resurrecting the button. The recorded-voice mic
  button (`assistant-mic`, request/response, unrelated code path) is
  unaffected and stays fully enabled either way.
- No Realtime session, WebRTC connection or sideband socket is opened at app
  launch, on a notification, or anywhere else outside the (now unreachable)
  entry points above — construction of `RealtimeVoiceController` itself never
  touched the network before this change either (ports are built lazily), and
  it is simply never constructed now.

Restore Pip Live by building with `--dart-define=PIP_REALTIME_ENABLED=true`,
or by flipping `realtimeEnabledDefault` in `feature_flags.dart`. Existing
Realtime widget tests set `FeatureFlags.realtimeEnabled = true` in `setUp` (and
reset it in `tearDown`) to keep exercising the full implementation regardless
of the shipped default; `test/features/chat/realtime_parked_test.dart` asserts
the opposite — that at the default (off) the UI stays unreachable even with a
controller injected.

`lib/services/realtime/` and `RealtimeVoiceController`
(`lib/features/chat/providers/`) are the app's half of Pip Realtime. The
assistant screen registers the controller alongside `AssistantProvider` under a
`MultiProvider` and exposes a **separate** live control in the composer
(`assistant-live`); the existing mic button remains the request/response
recorded-voice path and is not overloaded. `AssistantChatPort` is untouched — it
is strictly request/response.

**The invariant.** No microphone audio reaches the remote peer before the
server declares an authoritative READY. This is *not* implemented with
`track.enabled`: W3C defines a disabled track as delivering zero-information
content, not no content, so on Web the browser keeps sending silence at roughly
40 kbps and `packetsSent` climbs. Instead `WebRtcRealtimeTransport` acquires the
mic stream but never passes the track to `addTrack`; it adds a `sendrecv` audio
transceiver with **no** `track:` argument, producing a sender whose track is
null and which emits zero RTP by specification; SDP is negotiated in that state;
and transmission begins only when `sender.replaceTrack(micTrack)` runs, which
swaps the source without renegotiation so nothing touches the wire.
`stopTransmitting` is `replaceTrack(null)`. `track.enabled` is a secondary UX
mute only. Verification reads `getStats()` off the *peer connection* filtered to
`type == 'outbound-rtp'` and `kind == 'audio'` — never `sender.getStats()`,
which silently returns whole-peer-connection stats when the track is null — and
`noAudioHasBeenTransmitted` treats "no audio report exists" and "packetsSent is
0" as equally valid proof, because some stacks emit no report with no track
attached.

**States.** `idle → requestingPermission → connectingMuted → registeringCall →
bindingSideband → awaitingAuthoritativeReady → listening ↔ userSpeaking ↔
thinking ↔ assistantSpeaking → reconnectingMuted → ending → idle/error`.
`connectingMuted` and `reconnectingMuted` are enforced media states, not
labels: in them the sender holds a null track.

**Setup order.** `start` on `pip-realtime-session` mints the grant; the SDP
offer is POSTed to `https://api.openai.com/v1/realtime/calls` with the ephemeral
client secret (the minted secret already encodes model and voice, so the
endpoint is a fixed API property and never app config); the `rtc_…` call id is
parsed out of the `Location` response header and `register_call` is sent
immediately, before the answer is applied and before the sideband is bound;
only then does the client bind to Cloud Run with the one-shot binding token and
wait. Every step re-checks a monotonically increasing attempt generation, so a
navigation, cancel, logout or dispose mid-setup releases the attempt instead of
letting the last queued step enable the microphone.

**Sideband wire contract.** The server owns the format; the client conforms to
it. It is written down once, in `services/pip-realtime-sideband/WIRE_CONTRACT.md`,
and pinned from both sides by tests that assert the same literal bind frame, so
a change to one side fails the other side's suite. Every field is snake_case.
The client's first application frame is
`{"type":"bind","session_id","generation","access_token","binding_token"}` —
the Supabase JWT read at bind time (never cached) and the one-shot binding token
from `start`, in the frame body, never in the URL, never logged. The only
notices the client parses are `ready` (`session_id`, `generation`), `error`
(`code`) and `closing` (`reason`); anything else is dropped silently. The
socket's close code is mapped to a distinct cause and message — 4408 bind
timeout, 4401 bind rejected, 4409 lease lost, 4400 malformed, 4503 draining,
4500 internal — and anything else is a normal end of call. A private-range close
or an `error` notice goes through the ordinary failure path, so it spends the
one automatic recovery before surfacing. **Captions never travel on this
socket**: transcript deltas arrive on the WebRTC data channel straight from
OpenAI.

**READY validation.** Transmission is enabled at most once per generation, only
while the controller is actually awaiting READY, and only when the frame's
session id and server generation match the current attempt. A stale, duplicate
or foreign READY is inert.

**Ending and recovery.** A call that never reached READY is released with
`abort_setup` (reporting the orphaned call id so the sweeper can hang it up);
one that ran is released with `end` and a reason from the fixed vocabulary.
Recovery is allowed exactly once per user-initiated start, always releases the
previous session first — `start` enforces one live session per profile — and
always restarts from a fresh, non-transmitting transport that needs its own
READY. A microphone-permission denial is never auto-retried.

**Mobile background lifecycle.** Flutter/WebRTC remains the sole owner of the
microphone, peer connection, Realtime grant, SDP, captions, tools and RBAC. On
Android, after microphone acquisition succeeds and before a Realtime session is
minted, the controller starts a package-internal foreground service and waits
for its acknowledgement (up to five seconds). The low-importance ongoing `Pip
Live` notification includes an `End` action; it asks Dart to take the ordinary
user-ended teardown path. The service remains active across the one automatic
recovery and deactivates on stop, terminal error or disposal. On iOS the app
declares only `UIBackgroundModes: audio`; `flutter_webrtc` configures its own
Apple audio session to `localAndRemote` before microphone acquisition and
returns it to `none` after the track stops. Web, macOS, Windows and Linux use a
safe no-op lifecycle adapter. This does not provide incoming-call, VoIP or
unrestricted background execution.

**Client event policy.** The data channel delivers tool/function-call events.
The client never executes them, never relays them to any backend, never logs
their arguments or results, and drops unrecognised types silently; only the
Cloud Run sideband executes tools. `classifyClientEvent` maps every event to a
presentation-only action or to `ignore`, and tool detection short-circuits
before any other matching.

**Teardown** is `replaceTrack(null)` → data channel close → `track.stop()` →
Apple audio mode release → `stream.dispose()` → `pc.close()` → `pc.dispose()`. Skipping `track.stop()`
leaves the iOS microphone indicator lit.

**Audio session contention.** `record`, `audioplayers` and `flutter_webrtc` all
configure `AVAudioSession` independently, so Realtime has its own transport and
an active call ORs into the assistant screen's `isVoiceBusy` gate — recorded
voice, typing and a live call can never run at once.

### 7.ab Pip Realtime sideband service (Cloud Run)

`services/pip-realtime-sideband/` is the Deno service that attaches to a live
OpenAI Realtime call and owns every authoritative consequence of the
conversation. It is deployed to Cloud Run and started from `main.ts`;
`deno test -A` in that directory covers it.

**What it is and is not.** It carries no admission control — only
`pip-realtime-session` may create a session — and it AUTHORS no tool catalogue:
the catalogue still arrives whole as configuration. What it does own is WHEN
each half of that catalogue is sent (see **Staged tool catalogue** below). Its
job is the Realtime CONTROL path: binding a client connection, holding the lease,
configuring the provider session, attributing turns, claiming and evidencing tool
calls, settling usage, and draining cleanly.

**Staged tool catalogue.** A session starts with the CORE catalogue only —
every tool except the intake write path (`start_intake`,
`record_station_values`, `get_intake_status`, `create_station_summary`,
`confirm_station_summary`, `submit_station_for_review`, `pause_intake`,
`resume_intake`, `cancel_intake`). `partitionToolCatalogue` in
`src/session_config.ts` splits the configured catalogue by name at runtime
rather than reading a second env var,
so the two halves cannot drift from what was deployed, and the partition
preserves the configured order because a reordered prefix costs an OpenAI
prompt-cache hit. The staged half is attached by a second `session.update` the
first time the model ATTEMPTS `propose_intake`, sent before the follow-up
`response.create` and awaited to its `session.updated` ack under a bounded
timeout. The gate is attempt-based, not success-based: `propose_intake` is the
only possible gate (every staged tool requires a `pendingActionId` or
`intakeId` that only `propose_intake`/`start_intake` can mint, and the realtime
policy is static so no id can arrive from server context), and gating on
success would mean the upgrade never fires while the broker's missing turn
context makes `propose_intake` return `turn_context_required` on this channel.
That refusal carries `retryable: false` and a bilingual recovery message
naming the only route that exists — record it in the typed chat — so the model
answers in one sentence instead of re-calling the tool until the turn runs out
of budget.
The upgrade is confirmed, not assumed. A provider that REJECTS a
`session.update` drops it WHOLE, so an un-acked upgrade may mean the session is
still running the core catalogue; treating the send itself as durably done
would strand it there for the rest of the call with no retry and nothing in the
logs to say so. The session is therefore marked upgraded only once a
`session.updated` ack is actually observed, a later `propose_intake` may resend
once, and `MAX_INTAKE_UPGRADE_ATTEMPTS` (2) stops that from becoming an
unbounded resend loop. The ack-timeout warning carries
`catalogue_unconfirmed` and `retry_available`, which is what separates "the ack
was merely slow" from "the update was rejected and this session is still on the
core catalogue" — only the second is a problem, and they were previously
indistinguishable. A session never downgrades — the `vad_fallback` resend
carries whichever catalogue is currently active. Measured live: a first turn
costs 4,620 input tokens on the core catalogue against 5,909 on the deployed
full one.

The upgrade is not free, and the trade is deliberately one-sided. OpenAI's
prompt cache keys on the tools array, so the upgrade costs one cache miss and
leaves that session on the larger 32-tool prefix (5,243 tokens/turn measured)
for the rest of the call. Sessions that reach `propose_intake` therefore save
less than sessions that never do — and while the broker's missing turn context
makes `propose_intake` fail, they save nothing at all beyond the schema
slimming. That is accepted because the alternative is paying the full
catalogue in EVERY session, including the large majority that only ever ask
questions.

**Binding.** The wire format — bind frame, the three outbound notices, the close
codes, the ordering rule, and the fact that captions do not flow here — is
documented in `services/pip-realtime-sideband/WIRE_CONTRACT.md` and pinned by a
literal shared with the Flutter client's test. Inbound frames are processed
strictly in arrival order through a per-connection queue: the client sends the
health frame immediately behind the bind frame without waiting for any ack, and
processing the bind frame awaits the database, so an un-serialized health frame
would be inspected while the connection is still unbound and mistaken for a bad
bind (4400 `bind_frame_required`). A connection that closes while its bind is
still in flight also aborts the bind at the next checkpoint instead of claiming
a lease it can never release. Credentials arrive in the FIRST
WebSocket frame, never in the URL,
because a query string is written to proxy logs, browser history and Cloud Run
request logs. The frame carries the Supabase access token and the one-shot
binding token. The access token is verified locally against the project JWKS
(ES256) and proves IDENTITY ONLY; approval status and customer scope are
re-resolved from the database on every bind by
`src/authorization.ts::resolveBindAuthority`, which mirrors the provisioner's
`loadAppProfile`/`resolveAppAgentScope` (profiles is the authorization record;
`customers` / `auditor_customers` give the allow-list; the staff-link id is
derived as `app-<profileId>`, never queried) and re-derives the authorization
fingerprint with the SAME canonical-JSON SHA-256 as
`pip-realtime-session/fingerprint.ts`. The two derivations cannot import each
other (the Docker image ships only `main.ts` + `src/`), so parity is pinned by
`test/authorization_parity_test.ts`, which imports the provisioner's real
source and asserts identical digests — an earlier inline version drifted to a
legacy `role:customerId` string and every bind failed as
`bind.fingerprint_changed` → 4401. The binding token is consumed
atomically, so two clients racing with the same token yield exactly one
`consumed`. Until binding succeeds the connection may do nothing — no control
action, no lease claim, no provider traffic. Close codes in the private range
(4400 malformed, 4401 bind rejected, 4408 bind timeout, 4409 lease lost, 4500
internal, 4503 draining) let the client distinguish causes. The bind deadline
(`PIP_REALTIME_BIND_DEADLINE_SECONDS`, 5s, validated to be shorter than the setup
deadline) starts when the socket is upgraded and is cleared the moment bind
succeeds: a socket that never binds is sent `{"type":"error","code":
"bind_timeout"}` and closed 4408, because an upgraded socket holds a Cloud Run
concurrency slot for its whole life and nothing durable has been claimed at that
point.

**Lease and fencing.** Exactly one worker may drive a given (session,
generation). Ownership is `lease_owner` + `lease_expires_at` on
`agent_realtime_calls`, with a monotonically increasing `fencing_token` bumped on
every claim. Every authoritative write carries the fence it was issued and the
database rejects it if a newer owner has moved past — the failure this defends
against is a worker that is alive but paused (GC, CPU starvation, a stalled
socket) and does not know it lost the lease. On rejection the stale worker stops:
it does not retry and does not reclaim.

**Interactions and the tool budget.** The cap is INTERACTION-scoped, not
generation-scoped: one user utterance plus the entire response chain it provokes,
including the continuation responses the model produces after each
`function_call_output`. `PIP_REALTIME_MAX_TOOL_CALLS_PER_INTERACTION` (5) tool
calls per interaction, fresh budget for the next one. Capping across a whole call
leg would let one long conversation starve its own later turns. This is the only
place the Realtime cap is enforced; the text channel's
`MAX_AGENT_TOOL_CALLS_PER_TURN` is separate and enforced in its own runtime loop.

**Continuations and termination.** The tool budget bounds how many tools RUN;
it does not bound how many RESPONSES are generated, because a refused call is
still answered with a `function_call_output` and every answer used to be
followed by an unconditional `response.create`. A second, separate
per-interaction budget now bounds the continuations themselves
(`InteractionTracker#tryConsumeContinuation`), with a limit of the tool cap plus
two, and answers one of three things:

* `continue` — an ordinary `response.create`; the model may call another tool.
* `final` — `response.create` carrying `response: { tool_choice: 'none' }`. The
  provider cannot emit a function call in that response, so it cannot produce
  another `function_call_output`, so it cannot produce another continuation.
  This is what terminates the chain deterministically rather than waiting for
  the model to lose interest. A `tool_limit_reached` refusal force-finalizes
  immediately, because another tool-calling response is provably useless: the
  budget it would need is already spent.
* `suppress` — nothing is sent. Once a final has gone out the interaction is
  closed to further continuations forever, and the suppression is logged with
  the interaction id, the disposition and the cap.

Tool events are also SERIALISED. The provider socket delivers frames
fire-and-forget, so two `response.output_item.done` events from one response
would otherwise run concurrently, each awaiting its own broker round trip: a
response carrying `propose_intake` plus another tool could interleave so that
the other tool's `response.create` went out while `propose_intake` was still in
flight, and the intake `session.update` landed after it — leaving the model to
answer a data-entry request with the catalogue it started the call with. A
promise chain runs `#onOutputItemDone` strictly in arrival order, so outputs are
submitted, the catalogue is upgraded, and `response.create` is sent in the order
the frames arrived. Only that one event type is serialised; transcripts, deltas
and `response.done` still run immediately, so a slow broker call cannot stall
unrelated work. Telemetry attribution follows the same grain: when one response
emits several tool calls, all their names belong to the SINGLE follow-up they
jointly caused and land on one usage row together, and a new user utterance
clears any names still waiting for a follow-up that a barge-in prevented.

A refused `response.create` is itself recovered. The provider answers a frame
it rejects with an `error` event and NOTHING ELSE, so on the forced-final path
the caller would be left in silence at the exact moment they were owed the
answer, with the interaction already closed to further continuations. Every
`response.create` therefore carries an `event_id` the provider echoes back,
and a rejection naming it is handled three ways:
`conversation_already_has_active_response` is not silence (a response is
already in flight) and is ignored; a rejected FORCED FINAL is retried once
without the `tool_choice` override, because answering plainly beats not
answering and the sticky `finalForced` still refuses everything after it; any
other rejection sends the client `{type:'error', code:'response_create_rejected'}`
rather than leaving it staring at dead air.

A call refused for liveness (`rejected_not_live` — the session is stopped, the
lease is lost, or the generation is no longer this worker's) is still ANSWERED,
because an unanswered function call wedges the chain whoever owns the session,
but never continued: driving a response for a session this worker no longer owns
would be two assistants talking over one caller. The followed-tool name is
queued for telemetry attribution only when a continuation is actually sent, so a
suppressed call cannot pin its name onto an unrelated later response. A fresh
user utterance opens a fresh interaction with a fresh budget.

The text runtime terminates the same way by a different mechanism. When a turn
spends `MAX_AGENT_TOOL_CALLS_PER_TURN`, the over-limit call is answered
`tool_limit_reached` rather than executed — every `function_call` in the model
input needs a matching output or the next provider request is rejected — and the
runtime then makes exactly ONE more provider call with the catalogue withdrawn
(`tools: []`) and `tool_choice: 'none'`, so the model has to answer from what it
already gathered. A provider that emits a function call anyway ends the turn as
`tool_limit_exceeded` instead of looping. The catalogue is still sent on that
pass — `tool_choice: 'none'` is what forbids the call, and withdrawing `tools`
from a request whose input already holds `function_call` items is an unproven
shape on both providers.

The turn deadline still bounds everything, but it is now SPLIT: a fixed slice
is reserved for the final pass, so a turn whose tool calls ate the whole budget
is promoted to its final answer rather than failing as a timeout — running out
of tool time is itself a reason to answer with what was gathered. For the same
reason a tool that overruns is reported to the model as `tool_timeout` with a
recovery and promotes the turn to its final pass, instead of ending it. Each
awaited operation owns its own `AbortController`: a single shared one meant one
timeout poisoned every later call, so a slow tool aborted the very request that
was meant to deliver the answer.

**Tool calls.** `ToolCallCoordinator` takes a REQUIRED, discriminated ownership
argument (`ToolLedgerOwnership`) naming who writes the durable ledger —
`agent_tool_call_claims` and `agent_tool_events` — for the calls it runs. There
is no default, because both tables carry partial unique indexes on
(`realtime_session_id`, `realtime_generation`, …) and a second writer for one
call id is a unique violation, not a duplicate row.

In `ledger: 'sideband'` mode the coordinator claims BEFORE executing — the claim
ledger keyed (session, generation, tool call id) is what makes a redelivered call
idempotent, and executing first would let a reconnect double-apply a write. The
argument hash is part of the identity: the same call id with different arguments
is a conflict, not a redelivery, and is rejected. It never waits for the
transcript, which finalizes asynchronously and may never finalize at all.
Evidence rows are written once with `conversation_turn_id = NULL` and the
interaction id set.

In `ledger: 'broker'` mode — what `main.ts` wires — the coordinator writes
NEITHER table: `pip-realtime-tool-broker` (7.ac) creates, settles and evidences
the claim around the tool it executes, and its answer is authoritative, including
the duplicate it replays from a recorded claim, which arrives as `duplicate:true`
and is reported as a duplicate disposition. What the coordinator keeps in both
modes is what is genuinely its own: the per-interaction tool budget, a liveness
guard that refuses a call outright once the session is stopped, the lease is lost
or the generation is no longer this worker's, and the guarantee that the model
always receives a real `function_call_output` — a broker that is unreachable,
returns 5xx, refuses with 4xx, or answers 200 with an unusable body all produce a
negative tool result the assistant can say out loud, never an invented success
and never silence. A tool call left unanswered would wedge the response chain.

A broker that HANGS is bounded too, and separately: `fetch` has no default
timeout, so an unresponsive broker used to leave the promise unsettled — the
`function_call_output` was never sent, and because tool events run on a
serialized chain, every later tool call on the session queued behind it
forever, leaving the session permanently mute to tool work while still
reporting healthy. The call is now abandoned after `BROKER_TIMEOUT_MS` and
reported as `broker_timeout`, kept distinct from `broker_unreachable` because
the two mean different things: nothing ran, versus something may still be
running. Retrying is safe either way — the broker owns the claim ledger, so a
redelivery of the same call id replays rather than re-executes.

The inbound-turn back-fill runs in both modes and is the one claim write the
sideband keeps when the broker owns the ledger: `inbound_turn_id` has exactly one
writer (only the sideband learns that the transcript finalized), the broker
inserts NULL and never touches it, and the link is back-filled on the MUTABLE
CLAIM, never on the immutable evidence row. No placeholder turn is ever
fabricated to satisfy a foreign key.

The tool catalogue itself is INJECTED (`src/tools.ts`), not defined here, so the
voice channel cannot drift from the text channel. `main.ts` builds the registry
with `brokeredToolRegistry` — the only constructor that pairs
`pipRealtimeToolBrokerExecutor` with `ledger: 'broker'` — over definitions taken
from `config.toolDefinitions`. Those definitions, the broker URL and the broker
secret are all validated at startup and an invalid or absent value crashes the
revision: a sideband serving an empty catalogue announces READY, carries audio
and can do nothing. The secret is placed only in the `x-pip-broker-secret`
request header and is never logged.

Turn detection defaults to `semantic_vad` with `eagerness: low` — verified
accepted for `gpt-realtime-2.1-mini` on a live probe connection
(`tools/probe_turn_detection.ts`) — so the model ends the user's turn on
semantic completion instead of a fixed silence timeout. It is configurable via
`PIP_REALTIME_TURN_DETECTION` (`semantic_vad` | `server_vad`),
`PIP_REALTIME_VAD_EAGERNESS` (`low`|`medium`|`high`|`auto`) and, for
`server_vad` only, `PIP_REALTIME_VAD_SILENCE_MS` (default 800). If the provider
rejects `turn_detection` before the config is acknowledged, the sideband
resends the session.update exactly once with `server_vad` forced (logged
`sideband.vad_fallback`). Both VAD shapes keep `create_response` and
`interrupt_response` true, so user barge-in cancels the assistant's response
server-side. Two on-demand conversation-behavior eval suites live in
`services/pip-realtime-sideband/evals/` (see its README): `run_evals.ts` runs
scripted Egyptian-Arabic conversations against the real model over the Realtime
WebSocket in text mode with stubbed tools, asserting word budgets, progressive
disclosure, benchmark discipline, missing-data honesty, inference hedging, and
ask-before-acting; `run_canaries.ts` is the small production-path gate that
sends the EXACT production `session.update` payload (audio output modality,
reasoning effort, semantic VAD — built by the same `buildSessionUpdate` the
Sideband uses) and asserts on the audio transcript. The canary suite exists
because text-mode passing is not evidence about the spoken channel: the
2026-08-18 production failures (verbose canned greetings, multi-question
clarification paragraphs) reproduced under audio output while the text suite
was green. Canaries run first; the large text suite is the regression tail.
`tools/probe_token_cost.ts` is the third member of that family and answers a
different question: what the provider actually CHARGES for a given payload. It
builds the session through the same `buildSessionUpdate`, drives scripted
turns, and prints `response.usage` per inference, so a token claim is always
provider-reported rather than inferred from source-file size. It accepts
`--instructions`/`--tools` overrides so a live Cloud Run revision's own env can
be measured against the repo's, which is how a before/after is proved. It paces
itself by default because the account's observed 40k TPM ceiling for
`gpt-realtime-2.1-mini` is only about eight inferences a minute at this context
size — an unpaced run gets `rate_limit_exceeded` responses that arrive as an
empty `response.done` with zero usage and look exactly like a provider bug.
`runTurn` also collects every non-empty transcript spoken across a turn's
tool rounds (not just the final reply) into `allSpeech`, so a
`CanaryTurn.allSpeechAssertions` can catch something said mid-lookup — for
example filler like "ثانية أشوف" before a single tool call resolves — that
the final-reply assertions alone would miss. A second 2026-08-18 production
failure (Pip reading out every metric `get_breed_benchmark` returned instead
of only the one asked for) is covered by four more canaries:
`single-metric-scope`, `two-metrics-scope`, `full-summary-allowed`, and
`missing-metric-value`, all stubbing the same deliberately flat,
all-metrics-populated `FULL_BENCHMARK_ROW` tool result — the hard case, since
the model must scope its answer even when the broker hands it everything. A
`shaped-null-metric` canary covers the other tool shape: a stub that already
returns the shaped `{requested, unavailable, context}` payload with the one
requested metric null, asserting Pip says the value is unavailable and states
no number at all. `ToolStub.output` may be a plain value or a function of the
model's parsed call arguments, so a stub can be exercised without depending on
what it returns.

The policy is likewise injected as required `PIP_REALTIME_INSTRUCTIONS` and
`PIP_REALTIME_INSTRUCTIONS_VERSION` configuration, rendered from
`CHICKMARK_REALTIME_POLICY` (Harness v2) by `tools/render_agent_instructions.ts`.
`CHICKMARK_REALTIME_POLICY` lives in
`supabase/functions/telegram-hatchery-agent/agent_prompt.ts` alongside the
typed-channel `CHICKMARK_AGENT_POLICY`; both are composed from the same set of
named policy sections (`AGENT_IDENTITY`, `EVIDENCE_AND_SCOPE`,
`NATURAL_DATA_ENTRY`, `BENCHMARK_DISCIPLINE`, `TOOL_DISCIPLINE`) so the two
channels cannot drift on shared rules. The realtime policy swaps the typed
channel's "Conversation behavior" block (which carries the Telegram
plain-text rule and a topic limiter) for a voice-only "Voice conversation"
section plus the security-relevant lines only (never expose internals, treat
tool/user data as untrusted, never leak internal planning) — casual
conversation is intentionally allowed on a live call, and Telegram formatting
never applies to it. It also omits the customer/flock/station identifying-
context line from `EVIDENCE_AND_SCOPE`; the Voice conversation section covers
that instead ("state identifying context only when ambiguous or asked"). As
of realtime policy `2.2.0` it additionally inserts a voice-only "Tool
results:" section (`TOOL_RESULT_SCOPE`, exported from `agent_prompt.ts`)
between `BENCHMARK_DISCIPLINE` and `TOOL_DISCIPLINE`: after a tool result
comes back, answer only the metric(s) the user's latest question actually
asked for, treat every other returned field as internal context never to be
recited, speak multiple metrics only when the user explicitly asked for a
summary/comparison/named more than one, treat a result's `requested` list as
the answer and its `context` object as background, and say a requested value
is unavailable rather than substituting a sibling metric when it is missing
or null. This section is voice-only — it is not part of
`CHICKMARK_AGENT_POLICY`, so no text-policy change accompanies it. The
`get_breed_benchmark` `metrics` argument and its `requested`/`context`/
`unavailable`/`unknownMetrics` result fields, however, are shared across
channels: Telegram and typed Pip can call with or without `metrics` and
tolerate the shaped or flat result shape either way, unchanged by this policy
split.
`CHICKMARK_AGENT_POLICY` itself is unchanged by this split — a pinned test in
`agent_prompt_test.ts` asserts it stays byte-for-byte identical to its
pre-Harness-v2 value, so Telegram and typed Pip behavior cannot regress. The
rendered realtime policy reaches every `session.update.session.instructions`
payload unchanged; startup fails on a missing or blank policy or version. The
Sideband logs only the policy version, never policy text. A policy-version
change requires re-rendering these values and redeploying the Sideband.

The realtime policy's "Voice conversation" section is audio-tuned (Harness
2.2.0): a hard length rule (default one short spoken sentence, at most one
question mark per reply), an explicit greeting protocol (a greeting is answered
with a matching two-to-four-word greeting, never an offer to help), a
one-question clarification rule that forbids restating the request and
enumerating candidate options, a banned list of assistant-service stock
phrases, a lookup-filler rule ("ثانية أشوف" only when one request genuinely
chains several lookups, never for a single one, never as a sign-off), and a
block of literal calibration examples — including two 2.2.0 examples that
model answering only the requested metric when the tool result carries
several (production-only and fertility+hatchability-only). The examples are
load-bearing: on `gpt-realtime-2.1-mini` in audio mode, abstract brevity and
scope rules alone were not followed reliably — the canary suite only
stabilised after the example pairs were added.

**Session fingerprinting.** Every `session.update` the Sideband sends is logged
as `session_config.sent` (sequence number, source
`initial`/`vad_fallback`/`intake_upgrade`,
Cloud Run revision from `K_REVISION`, harness version, SHA-256 and length of
the instructions, model, voice, tool count, turn-detection type, eagerness,
reasoning effort), and every provider `session.updated` ack as
`session_config.acked`, which additionally hashes the instructions echoed back
by the provider and records `instructions_match` — proving not just that the
config was sent but what the session is actually running. Hash + version +
length only; policy text never reaches a log line.

**Conversation context injection.** Right after the initial `session.update`
send — on the same socket, immediately after, so wire ordering is preserved —
`SidebandSession` best-effort loads the bound conversation's recent finalized
turns (`store.loadRecentTurns`, scoped to the session's
`conversationId`/`contextEpoch` and constrained to
`direction in (inbound, outbound)` and
`source_channel in (app_text, realtime_voice, telegram)` so a future `system`
row can never be replayed as speech) and replays them into the
model as `conversation.item.create` frames (`role: 'user'|'assistant'`,
`input_text`/`text` content) so a caller resuming a conversation — by text
after a prior voice call, or by voice after prior typed turns — picks up where
it left off instead of starting the model cold. Up to the newest
`CONTEXT_TURN_LIMIT` (12) turns are fetched; each turn's text is tail-truncated
to `CONTEXT_PER_TURN_CHAR_CAP` (600 characters, keeping the END so the most
recent content of a long turn survives) and turns are then walked newest-first
and kept while the running total stays under `CONTEXT_TOTAL_CHAR_CAP` (4000
characters) — the walk stops at the first turn that would overflow the
budget, which is exactly "drop the oldest turns first" — before being sent
oldest-first. Injection participates in readiness as the `contextInjected`
precondition: READY is withheld until the injection settles, but the store
fetch is bounded by `CONTEXT_INJECTION_TIMEOUT_MS` (500 ms, overridable as a
test seam), so a slow or hung fetch delays READY by at most that bound and a
failure never blocks it — the precondition is marked in a `finally` on
success, failure, and timeout alike, keeping "history lands before the first
live utterance" without letting the database gate the call. Any failure (the
store fetch, or a frame send) is swallowed after a content-free warning log
(`context_injection.failed`); a success logs only counts
(`context_injection.sent`: turns fetched vs. sent), never turn text.
`contextInjectionPromise` exposes the in-flight injection as a test seam
only. Voice-to-text continuity needed no separate work: the shared context
loader used by `app-hatchery-agent`'s `send` already reads finalized turns
channel-blind, so a realtime-voice turn is already visible to the next typed
turn in the same conversation.

**Turns and usage.** Deltas are never persisted — only finalized text — and an
interrupted response stores only what was actually said. Failed transcription is
recorded as `unavailable` rather than being given invented content. Usage settles
into `agent_realtime_usage_seconds` as one row per (session, UTC date), so a call
crossing midnight becomes two slices that sum to its true active seconds;
`usage_settled_at` plus the table's unique key are two independent defences
against double settlement.

**Token telemetry.** Wall-clock seconds are what the caller is BUDGETED on;
tokens are what the provider BILLS. They are recorded separately and must not
be conflated. Every `response.done` is parsed by `src/response_usage.ts` — a
pure function that never throws and coerces anything missing or non-numeric to
zero — and written to `agent_realtime_response_usage`, one row per
(session, response). The row carries total/input/output, cached and derived
uncached input, the text/audio/image split on both sides, the model, the
response status, whether the response followed a tool call and which tool it
was, and the INTERACTION it belonged to — the same key
`agent_tool_events.realtime_interaction_id` carries, so "how many assistant
responses did one thing the caller said produce?" is a `group by` rather than a
log search. It is null only when a response arrived with no preceding
`response.created` to attribute it. That attribution is read via
`InteractionTracker#lookupInteractionForResponse`, a PURE lookup that never
mints an interaction and never touches budget-tracking state — telemetry
observes attribution, it never creates it. (The tool-budget path uses a
separate, minting `interactionForResponse`/`noteResponseCreated`, which is
correct there: a real tool call in flight needs an interaction to attribute
budget to, even for one the tracker has not seen yet.) A failed or
rate-limited response arrives with all-zero usage and is recorded anyway,
because "the provider refused this turn" is the signal that matters most. The
primary key makes a redelivered `response.done` a no-op rather than a double
count, and a persistence failure is logged content-free and swallowed —
telemetry never breaks a live call.

**Failure containment.** One instance holds many concurrent live calls, and
Deno terminates the process on an unhandled rejection — so a single missing
`.catch` on a fire-and-forget path drops EVERY call on the instance, not just
the one that failed. Provider events are dispatched with an explicit `.catch`,
the lease heartbeat treats a store error as a lost lease (a stale worker stops
rather than retries, which is this service's rule), and `main.ts` registers a
process-level `unhandledrejection` guard as the last resort.

Losing the provider socket is likewise not a degradation the session rides out.
The caller's WebRTC leg to OpenAI is a SEPARATE connection that stays up, so the
model keeps talking while this service can no longer execute a tool, persist a
turn, or drive a response — and every frame it tries to send queues into a
socket that will never open again. The session stops itself and the client is
failed with `sideband_lost`, so it starts a fresh generation instead of talking
to a session with no authority behind it.

**Drain and sweep.** Cloud Run's SIGTERM grace is a fixed, non-configurable 10
seconds. The drain path (`PIP_REALTIME_DRAIN_BUDGET_MS`, 7000) does only what
must be durable: ONE batched statement marks every generation this worker owns
`cleanup_pending` and releases the leases, and a close frame is pushed to each
client so it can fail over immediately. It performs NO OpenAI hangups — each is a
third-party round trip with no latency guarantee. Those, and every setup that
stalled past its deadline, are handled by `POST /internal/cleanup`, called by
Cloud Scheduler on roughly a 60-second cadence and authenticated with Google
OIDC: both the audience and a service-account allowlist are checked, so a token
minted for another service cannot be replayed here. The sweep claims each
generation by compare-and-swap on the fencing token first, so it is safe to run
concurrently with itself and with a live worker. It terminalizes three kinds of
generation: one handed over as `cleanup_pending` by a draining worker, a setup
stalled past `setup_deadline_at`, and — newly enforced — an ACTIVE call past
`active_expires_at`. The provisioner had always stamped that column from
`maxSessionSeconds` and nothing ever selected on it, so a live session was
bounded by nothing but the caller hanging up: every new utterance opens a fresh
interaction with a fresh tool budget, so an echoing line could drive unbounded
tool and inference cost with no server-side stop. Each hangup is bounded by its
own timeout, so one unresponsive provider call cannot stall the whole sweep —
and the sweep is the only thing that terminalizes anything.

**Logging.** `src/log.ts` accepts only a stable event name plus scalar fields and
scrubs any key that looks like content (`text`, `transcript`, `arguments`,
`result`, `output`, …). No audio, transcript, tool argument, tool result, token
or secret may reach a log line.

**Configuration** is validated at startup in `src/config.ts`; an invalid value
crashes the revision where the deploy fails loudly, never at the first session.
Incoherent combinations are rejected too — a heartbeat interval more than half
the lease would let a single missed beat expire the lease. The
`openai-beta.realtime-v1` subprotocol is deliberately never sent: it forces the
retired beta surface and the connection is rejected.

**Attach transport.** The sideband attaches to the live call with `npm:ws`
over http/1.1, sending a real `Authorization: Bearer` header and no
subprotocols — and the bearer must be the call's own EPHEMERAL client secret,
which the provisioner persists on the service-role-only
`agent_realtime_calls.client_secret` column for exactly this purpose. All of
this is load-bearing and was learned from two production outages on the same
socket: the original `openai-insecure-api-key.<KEY>` subprotocol hack is
ignored by the attach endpoint (HTTP 401 on every bind); Deno's
header-capable `WebSocketStream` negotiates h2, which the endpoint rejects
with HTTP 400; and a standard `sk-` key — despite the provider's own
documentation — is answered with 404 `call_id_not_found` even for a live
call, while the `ek_` secret attaches and acks `session.update` (proven with
a real WebRTC call from the macOS integration harness,
`integration_test/realtime_attach_probe_test.dart`). The secret's TTL is 60s,
capped at the setup deadline — the only window attach can legally happen in. A connection that fails before ever opening is retried
twice at ~750ms spacing (`sideband.attach_retry`); a rejected handshake logs
`sideband.attach_rejected` with the HTTP status and a truncated body so the
next transport failure names itself. Post-open failures never re-dial. The
READY gate additionally requires the client's post-bind
`{"type":"health","webrtc":true,"data_channel":true}` frame, which the Flutter
client sends once per attempt immediately after a successful bind.

### 7.ac Pip Realtime tool broker (Edge Function)

`supabase/functions/pip-realtime-tool-broker/` is the narrow, authenticated
internal interface through which the Cloud Run sideband executes ChickMark agent
tools. It exists so the sideband never forks a second copy of the tool catalogue
and never needs broad database privileges: the sideband sends ONE tool call, and
this function executes it through the SAME shared runtime the Telegram and in-app
doors use (`executeAgentTool` in
`telegram-hatchery-agent/agent_tools.ts`, with handlers from
`createUnifiedAgentToolHandlers`).

**Authentication is of the SIDEBAND, not an end user.** A single POST endpoint
accepts a shared secret in the `x-pip-broker-secret` header, compared in constant
time against `PIP_REALTIME_BROKER_SECRET`. It FAILS CLOSED: when the variable is
unset, blank, or shorter than 32 characters the endpoint refuses every request
with 503 rather than degrading into "no secret configured, so accept anyone".
Google OIDC was considered and rejected for this direction — a Supabase Edge
Function has no Google trust anchor, so verifying an ID token would put a JWKS
fetch on the hot tool path. The two directions are therefore asymmetric on
purpose: outbound to Supabase is a shared secret, inbound from Cloud Scheduler to
the sideband is OIDC. The function must be deployed with `--no-verify-jwt`,
because its caller is a server and presents no end-user JWT.

**Authorization is re-resolved, never trusted.** The request carries the caller's
authorization fingerprint, but that is treated as a claim. The function loads the
session row, resolves the owner's CURRENT scope through `loadAppProfile` /
`resolveAppAgentScope`, and recomputes the fingerprint with the same derivation
`pip-realtime-session/fingerprint.ts` used at provisioning time. Three values
must agree — what the caller sent, what was stamped on the session, and what the
database says now. Any disagreement, or a profile that is no longer approved,
refuses the call: authorization changed mid-session. The session must be `active`
and the generation must be both the session's `active_generation` and still in
`setup_state = 'active'`; a stale or terminal generation executes nothing.
Argument-level scope (a tool naming a customer outside the allow-list) is refused
by the shared runtime's own `enforceArgumentScope`, which is not duplicated here.

**Idempotency** uses `agent_tool_call_claims` on the Realtime key shape
(`realtime_session_id`, `realtime_generation`, `openai_tool_call_id`) plus the
argument hash, canonicalised identically to the sideband's (`canonicalJson`:
recursively sorted keys, so a provider reordering the JSON is not mistaken for a
different call). The same call id with the same hash returns the recorded
terminal result WITHOUT re-executing and without writing a second evidence row.
The same call id with a different hash is rejected as a conflict. A mutation that
ends indeterminate — the tool ran but the outcome could not be recorded — settles
its claim `indeterminate` and is NEVER auto-replayed: re-running could double
apply the write and reporting success could report a write that never landed.

**Evidence** is one immutable `agent_tool_events` insert per call. The table's
trigger raises on UPDATE and DELETE, so the row is written once and never
corrected. `conversation_turn_id` is NULL (Realtime evidence predates any durable
turn) and the row carries `realtime_session_id`, `realtime_generation`,
`realtime_interaction_id`, `argument_hash` and `source_channel =
'realtime_voice'`. `tool_sequence` is NOT NULL and is allocated from the rows
already present for that session and generation, re-allocated on collision,
because a partial unique index enforces it and two brokers must not both believe
they own the same sequence number.

**The 5-call cap is NOT enforced here.** It is interaction-scoped and lives in
the sideband's `InteractionTracker`; a second, differently-scoped cap in the
broker could refuse a call the sideband had already budgeted for. The rule is one
cap per channel, enforced where the loop that spends it lives.

**Logging** carries identifiers and outcome codes only — never tool arguments,
results, transcript text or secrets.

### 7.ad Live-voice failure diagnostics

`RealtimeVoiceController` tracks which setup stage is in flight
(`openMicrophone → createSession → createConnection →
addSilentAudioTransceiver → openEventChannel → createOffer → exchangeOffer →
registerCall → acceptAnswer → accessToken → bind`). On failure,
`errorDetail` carries `stage: ExceptionType: message` (truncated, never
tokens/SDP/transcripts), survives the single automatic recovery so the
original cause wins, clears on a fresh start, and renders as a selectable
monospace line in the chat screen's error banner (`assistant-live-error` /
`assistant-error-detail`). Diagnostics are always LTR even under an Arabic
locale.

### 7.ae Answer-SDP handling (terminal newline is load-bearing)

`HttpRealtimeCallSignaling.exchangeOffer` returns OpenAI's answer SDP
byte-preserved except for one guarantee: the string always ends with a
newline (appended only if missing — the body is never trimmed). darwin
libwebrtc (iOS/macOS, `flutter_webrtc`) refuses to parse an SDP whose final
line is unterminated and surfaces it as `setRemoteDescription: Error
SessionDescription is NULL.`, while Chrome's parser accepts the same string —
so a bare `.trim()` on the HTTP body was a full live-voice outage on iOS. A
non-empty body that does not start with `v=` fails signaling with the body's
first line quoted (protocol metadata, never user content).
`integration_test/realtime_sdp_parse_test.dart` pins the parser behaviour
against a captured production answer; run it with
`flutter test integration_test/realtime_sdp_parse_test.dart -d macos`
(macOS shares `flutter_webrtc`'s darwin code and WebRTC framework with iOS).

### 7.af Pip Live conversation surface

Pip Live runs in `RealtimeVoiceScreen` (`pip-live-screen`), a dedicated
minimal call screen backed by the one shell-owned `RealtimeVoiceController`;
the screen never creates a second transport, session, audio-level stream, or
AssistantProvider message. It is reached from inside a conversation's
`AssistantChatScreen` (the live control in the composer) or reopened by the
shell-wide banner, and it joins whichever `conversationKey` it was opened
with — a fresh `autoStart` call binds to that conversation on `start`; once a
call is already active (banner reopen) the screen never calls `start` again,
so the key of a running call cannot change mid-call.

**Header.** A minimal row: a chevron-down minimize button
(`pip-live-minimize`, pops back to the shell — the call stays active), the
centered label "Pip" plus a subtle one-line state label underneath (Listening
/ You are speaking / Pip is thinking / Pip is speaking / Reconnecting / Call
ended / a generic "Connecting securely" fallback while setting up), and a
balancing spacer so the title stays centered. The state label is deliberately
omitted in the error state — that message renders under the orb instead, so
it is never said twice.

**Orb.** `RealtimeVoiceOrb` renders a refined breathing orb reflecting the
controller's turn state, dimmed to 45% opacity (animated) while
`reconnectingMuted`, with an error tint/copy path of its own. Its failure
message and, in the error state, a selectable monospace diagnostic line
(`pip-live-error-detail`, LTR always — see 7.ad) render centered beneath it,
followed by a Retry text button (`pip-live-retry`) shown in both the error and
the muted-reconnect state; during muted reconnect, Retry stops that recovery
first and starts a fresh, bounded attempt, while an error-state Retry starts
directly.

**Transcript.** A collapsed-by-default strip (`pip-live-transcript`) shows
only the latest user turn and the latest assistant turn (each tracked
independently, not just "the last two by index"), top-faded with a gradient
mask; tapping the strip, or the dedicated toggle control, expands it into the
full scrollable caption history (max height 260 vs. 116 collapsed) rendered in
detected per-line text direction. It renders nothing when there are no
captions yet. Caption lines accumulate from `.delta` frames; the terminal
`.done`/`.completed` frame carries the full transcript and REPLACES the open
line rather than extending it, so a reply never renders twice.

**Controls.** Three circular controls in a row, each a `Semantics` button plus
a `Tooltip` (no visible text): mute (`pip-live-mute`, 56dp, mic/mic-off,
filled while muted), End call (`pip-live-end`, 64dp, always filled red), and a
transcript expand/collapse toggle (`pip-live-transcript-toggle`, 44dp,
disabled while there are no captions to show). Mute and End are disabled
whenever the call is not active (`controller.isRealtimeActive` false).

Minimize only returns to the shell, so a call remains active; the active-Live
composer control and the shell-wide banner reopen the same screen bound to the
same `conversationKey` the shell is currently tracking. The banner is visible
across shell tabs and exposes the same stop path as the screen's End control.
Recorded voice and Live remain mutually exclusive through the existing
controller/assistant audio-session gates. All production entry points use the
shell's one guarded route opener, so a near-simultaneous banner and composer
tap can create at most one Live route. The shell reserves a bottom layout slot
for the active-call banner rather than overlaying it on compact navigation or
tab content. Every widget key on this screen is load-bearing for
`realtime_voice_screen_test.dart` and `assistant_chat_screen_realtime_test.dart`
and is kept stable across restyles.

### 7.ag IoT device gateway (Edge Function `iot-gateway`)

`supabase/functions/iot-gateway` is the device-facing API for ChickMark IoT
hubs. It is deployed with `--no-verify-jwt`, because an ESP32 carries no Supabase
credential; authentication is a per-device bearer token checked inside the
function. It serves no browser and sets no CORS headers. The Flutter app never
calls it — the app reaches IoT data through PostgREST and the `iot_claim_hub`
RPC.

Routing anchors on the last `/v1/` path segment, so the same handler works
whether it is reached through `/functions/v1/iot-gateway/v1/telemetry` or a
local `supabase functions serve` path. Endpoints: `GET /v1/health` (no auth),
`POST /v1/provision`, `POST /v1/auth/token`, `POST /v1/telemetry`,
`POST /v1/heartbeat`, `POST /v1/commands/ack`, `GET /v1/commands`,
`POST /v1/topology`, `GET /v1/config`, `POST /v1/events`, `GET /v1/firmware`,
`POST /v1/firmware/status`.

Handlers are pure with respect to I/O: each takes a parsed body, the
authenticated hub context, and a `Db` port. `db_supabase.ts` implements that port
with the service-role key, and the tests implement it with plain objects. Because
service_role bypasses RLS, every hub-scoped query filters on both `hub_id` and
`customer_id`, and `customer_id` is taken only from the row the bearer token
resolves to — never from a request body.

Identity and credentials. `iot_hub_registry` holds one row per manufactured hub
with the SHA-256 hashes of its factory secret and claim code. `iot_claim_hub`
binds a registry entry to a customer's hatchery and is the only path that creates
an `iot_hubs` row; it returns the new `hub_id`, returns `null` for both an unknown
serial and a wrong claim code (indistinguishable on purpose), raises `42501` when
the caller has no write scope on the hatchery or the hatchery does not exist (also
merged), `55P03` when a serial is locked after five failed claim attempts, and
`23505` when the serial already has a live hub. `POST /v1/provision` exchanges the
factory secret for a `hub_id` and a freshly minted 64-hex `device_secret`, storing
only its hash in `iot_hub_secrets` and revoking every previously issued token.
`POST /v1/auth/token` exchanges that secret for an opaque 24-hour bearer token,
stored as a SHA-256 hash in `iot_device_tokens`.

Telemetry is stored raw in `iot_telemetry`, partitioned by month with a default
partition. Ingestion runs through `public.iot_ingest_telemetry`, which merges
metrics on conflict (`metrics || excluded.metrics`) rather than overwriting or
dropping, so a batch re-split after a `413` cannot lose a partial metric set.
Idempotency is two-layer: `(hub_id, batch_id)` in `iot_telemetry_batches`, and the
`(sensor_id, measured_at)` primary key. Readings whose `measured_at` is more than
300 s ahead or 90 days behind server time are rejected per reading, not per batch.
A value outside `iot_metric_registry`'s plausible range is stored with
`quality = 'suspect'` and reported in `flagged[]`; `t_est` marks a row
`estimated`. An unknown `sensor_uid` is auto-created in `unassigned` state rather
than rejected.

Commands ride the heartbeat response, capped at ten, with `next_heartbeat_s`
dropping to 10 s while any are queued. `public.iot_ack_commands` maps the device
ack vocabulary onto the stored one (`received` becomes `acked`) and never lets a
terminal status be overwritten by a non-terminal one.

Configuration is resolved server-side and served flat: `BASE_CONFIG`, then the
matching `iot_config_defaults` layers by priority, then the per-hub
`iot_hub_config.doc`, plus the hub's `espnow_pmk` and the current `base_url`.
Triggers bump `iot_hub_config.version` whenever the document changes, mirror it
onto `iot_hubs.config_version`, and bump every affected hub when a fleet-default
layer changes — that version is what tells a hub to refetch. `GET /v1/config`
honours `If-None-Match` and returns `304`.

Tenant isolation is enforced in the database, not only in the handler: composite
`(hub_id, customer_id)` foreign keys tie every child row to a hub of the same
customer, `iot_hubs` grants `authenticated` only column-level `select` plus
`update` on `name`/`hatchery_id`/`status`, and RLS is enabled and forced on every
telemetry partition as well as the parent, because a partition inherits neither
row security nor the parent's policies.

## 8. Known Technical Debt

- Several station screens still use legacy-named `AuditModel` fields as
  in-memory form state. Save/load persistence converts those drafts to panel
  rows instead of writing legacy audit tables.
- The legacy single-station flow is still present in code alongside the newer
  visit/session flow.
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
- `AGENT_TOOL_CONTRACT` serves two different jobs and they are deliberately
  separated. It remains the VALIDATION schema in full — `executeAgentTool`
  enforces every `minLength`, `maxLength`, `pattern`, `minimum`, `maximum` and
  `enum` in it, and nothing about that changed. What the model is SHOWN is a
  projection of it, `modelFacingContract()`, which drops constraints that carry
  no tool-selection value and are re-enforced server-side regardless. The
  consequence to keep in mind: the model-facing schema is strictly MORE
  permissive than the validator, so an over-long or unknown value is caught at
  the broker with `invalid_arguments`/`unsupported_station_schema` rather than
  by the provider. That is the intended safety net, and it is pinned by tests
  that feed the slimmed schema a value the full rule rejects.
- Tool RESULTS are projected for the same reason the schemas are: a result
  stays in the model's context for the rest of the session, so every field has
  to earn its place. `load_station_schema` returns field `names` in both
  English and Arabic (users speak Egyptian Arabic, and the Arabic name is how
  speech maps to a field) plus a flattened, deduplicated alias list, and it
  keeps `validation` and `explicitZero` because `NATURAL_DATA_ENTRY` tells the
  model to use them and a value rejected at the broker costs a whole retry
  inference. Both it and `list_applicable_stations` drop `moduleKey`, which is
  always the substring of `schemaKey` after the last dot, and both flatten
  their alias lists. `resolve_customer_flock` returns the flock roster it had
  already fetched when exactly one customer matched and the roster is small,
  omitting it entirely rather than truncating past the limit — a silently
  truncated list would read as complete.
- The model-facing tool catalogue reaches the Cloud Run sideband as
  configuration (`PIP_REALTIME_TOOL_DEFINITIONS`), rendered from
  `modelFacingContract()` by
  `services/pip-realtime-sideband/tools/render_tool_definitions.ts`, because the
  two deployments cannot import from each other. A contract change therefore
  needs the value re-rendered and the sideband redeployed; nothing at runtime can
  tell a stale rendering from a fresh one. When the contract or shared tool
  sources change, the Supabase edge functions (`pip-realtime-tool-broker`,
  `telegram-hatchery-agent`, `app-hatchery-agent`) must deploy FIRST — they
  bundle the shared tool sources directly — and only then should env be
  re-rendered and the sideband redeployed; Cloud-Run-first exposes a new tool
  argument to the model while the still-old broker rejects it via
  `additionalProperties:false`, failing every call to that tool until the edge
  functions catch up.
- The Harness v2 realtime policy (`CHICKMARK_REALTIME_POLICY`) reaches Pip
  Live through the required `PIP_REALTIME_INSTRUCTIONS` and
  `PIP_REALTIME_INSTRUCTIONS_VERSION` deployment values, rendered by
  `services/pip-realtime-sideband/tools/render_agent_instructions.ts`. The
  raw policy text is never logged.
- `MUTATION_TOOL_NAMES` in `pip-realtime-tool-broker` is hand-maintained because
  the tool contract carries no mutation flag.
  `services/pip-realtime-sideband/test/tool_contract_test.ts` enumerates every
  contract tool, fails when one is unclassified, and compares the classification
  against the broker's list, so the omission cannot pass silently.


## 9. Change Log

The dated change history lives in `CHANGELOG.md`. Add an entry there for every
meaningful change, newest at the top, and keep this document describing only
current behavior.
