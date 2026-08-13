# Offline Cold-Start and Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the authenticated shell and local Home data stable during offline cold starts/resumes while one authoritative connectivity state suppresses automatic cloud work until a verified reconnect.

**Architecture:** Add one app-lifetime network-status monitor with explicit `unknown`, `online`, and `offline` states. Auth revalidation, automatic sync scheduling, settings/cloud UI, and the persistent shell indicator consume that monitor; only the automatic sync coordinator owns reconnect/backoff scheduling. Home separately gains an explicit initial-load state so empty database results are distinguishable from queries that have not completed.

**Tech Stack:** Dart, Flutter, Provider, connectivity_plus, flutter_test, mocktail.

## Global Constraints

- Preserve the 30-day remembered-user offline-auth grace and definitive-server-rejection logout behavior.
- Verify auth behavior with `--dart-define=CHICKMARK_DEBUG_AUTH_BYPASS=false`.
- Do not add arbitrary delays or per-call-site automatic-sync guards.
- Preserve local SQLite workflows while offline.
- Update `docs/LIVING_SPEC.md` and add a newest-first `- 2026-08-14:` entry to `docs/CHANGELOG.md` with the implementation.

---

### Task 1: Explicit Home initial loading

**Files:**
- Modify: `lib/features/home/providers/home_provider.dart`
- Modify: `lib/features/home/screens/home_screen.dart`
- Test: `test/features/home/home_provider_test.dart`
- Test: `test/features/home/home_screen_test.dart`

**Interfaces:**
- Produces: `HomeLoadState`, `HomeProvider.loadState`, and `HomeProvider.hasLoadedData`.
- Consumes: existing repository-backed `HomeProvider.load(currentUser:)`.

- [ ] **Step 1: Write the failing tests**

Add a provider test proving a new provider is uninitialized while a blocked repository query is loading, and becomes loaded only after all Home queries finish. Add a widget test pumping an uninitialized/initially-loading provider and assert that `0`, `—`, and `No recent audits` are absent while a keyed progress indicator is present.

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test test/features/home/home_provider_test.dart test/features/home/home_screen_test.dart`

Expected: FAIL because Home has no explicit initialized state and renders KPI defaults before its first query finishes.

- [ ] **Step 3: Implement the minimum state model**

Add `HomeLoadState { uninitialized, loading, loaded, error }`, retain already-loaded values during refresh, and make Home show progress/error UI until the first load completes.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `flutter test test/features/home/home_provider_test.dart test/features/home/home_screen_test.dart`

Expected: PASS.

### Task 2: Authoritative connectivity and automatic sync gate

**Files:**
- Create: `lib/core/network/network_status_monitor.dart`
- Modify: `lib/core/network/network_reachability.dart`
- Modify: `lib/services/sync/app_sync_coordinator.dart`
- Modify: `lib/services/sync/bg_sync_service.dart`
- Modify: `lib/features/settings/providers/settings_provider.dart`
- Test: `test/core/network/network_status_monitor_test.dart`
- Test: `test/services/sync/app_sync_coordinator_test.dart`
- Test: `test/features/settings/settings_provider_cloud_status_test.dart`

**Interfaces:**
- Produces: `NetworkStatus { unknown, online, offline }`, `NetworkStatusMonitor.start()`, `refresh()`, and `status`.
- Produces: `AppSyncResult { success, offline, transientFailure }` from automatic sync callbacks.
- Consumes: `NetworkReachability.isOnline()` as the single reachability probe.

- [ ] **Step 1: Write the failing tests**

Cover initial unknown state, deduplicated status changes, no automatic sync for unknown/offline nudges, repeated offline nudges producing zero calls, one offline-to-online reconnect producing one call, and transient failures observing exponential retry delay rather than immediate loops.

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test test/core/network/network_status_monitor_test.dart test/services/sync/app_sync_coordinator_test.dart test/features/settings/settings_provider_cloud_status_test.dart`

Expected: FAIL because connectivity ownership is duplicated and the coordinator schedules while offline.

- [ ] **Step 3: Implement the centralized monitor and gate**

Create the app-lifetime monitor; have the coordinator subscribe to it, queue offline nudges without timers or remote work, fire once on a verified reconnect, and back off uncertain failures. Make settings consume the same monitor instead of creating its own connectivity listener. Probe the configured Supabase host even when an interface exists so captive/uplink-less Wi-Fi is not automatically treated as usable cloud connectivity.

- [ ] **Step 4: Run tests to verify GREEN**

Run the command from Step 2 and expect PASS.

### Task 3: Stable offline auth resume and cold-start routing

**Files:**
- Modify: `lib/app.dart`
- Modify: `lib/features/auth/services/session_revalidation_trigger.dart`
- Modify: `lib/features/auth/screens/login_screen.dart`
- Modify: `lib/features/home/widgets/main_shell.dart`
- Test: `test/features/auth/session_revalidation_trigger_test.dart`
- Test: `test/features/auth/login_screen_remember_me_test.dart`
- Test: `test/app_auth_navigation_test.dart`

**Interfaces:**
- Consumes: the app-lifetime `NetworkStatusMonitor`.
- Produces: a pure post-auth route decision that sends an offline-grace restore directly to `/main` and preserves `/startup-sync` for a fresh/online authentication.

- [ ] **Step 1: Write the failing tests**

Add tests proving an offline resume makes no revalidation call, repeated offline resumes make no calls, offline-grace authentication selects `/main`, and offline state keeps the shell route unchanged.

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test test/features/auth/session_revalidation_trigger_test.dart test/features/auth/login_screen_remember_me_test.dart test/app_auth_navigation_test.dart`

Expected: FAIL because resume currently calls auth directly and cached offline authentication always visits `/startup-sync`.

- [ ] **Step 3: Wire the shared monitor**

Create/dispose the monitor once in `HatchAuditApp`, inject it into Settings, auth revalidation, MainShell automatic sync, and the shell indicator. Resume refreshes connectivity and only a known-online state can revalidate or sync. Skip the startup-sync route for an offline-grace restore.

- [ ] **Step 4: Run tests to verify GREEN**

Run the command from Step 2 and expect PASS with `--dart-define=CHICKMARK_DEBUG_AUTH_BYPASS=false` where supported by `flutter test`.

### Task 4: Consolidated offline indicator

**Files:**
- Modify: `lib/features/home/widgets/main_shell.dart`
- Modify: `lib/features/home/screens/home_screen.dart`
- Modify: `lib/l10n/app_localizations.dart`
- Test: `test/widgets/pending_revalidation_chip_test.dart`
- Test: `test/core/l10n/app_localizations_test.dart`

**Interfaces:**
- Consumes: `NetworkStatusMonitor.status`.
- Produces: one persistent shell-level `Offline — will reconnect automatically` indicator.

- [ ] **Step 1: Write/update the failing tests**

Make the existing real-shell composition test provide offline network state and continue to fail if the indicator is removed; assert online/unknown states hide it. Remove the obsolete localization expectation for the duplicate SnackBar.

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test test/widgets/pending_revalidation_chip_test.dart test/core/l10n/app_localizations_test.dart`

Expected: FAIL until the chip uses network state and the duplicate SnackBar is removed.

- [ ] **Step 3: Consolidate UI**

Drive the persistent top chip from the shared network monitor and delete Home's transition SnackBar and its localization entry.

- [ ] **Step 4: Run tests to verify GREEN**

Run the command from Step 2 and expect PASS.

### Task 5: Documentation and verification

**Files:**
- Modify: `docs/LIVING_SPEC.md`
- Modify: `docs/CHANGELOG.md`

**Interfaces:**
- Consumes: implemented and verified behavior from Tasks 1–4.
- Produces: current-behavior documentation and dated history.

- [ ] **Step 1: Update documentation**

Document explicit Home initial loading, direct-to-shell offline cold starts, one authoritative connectivity state, offline automatic-sync suspension, reconnect/backoff behavior, and the single shell indicator.

- [ ] **Step 2: Run targeted auth tests without debug bypass**

Run: `flutter test --dart-define=CHICKMARK_DEBUG_AUTH_BYPASS=false test/features/auth/ test/app_auth_navigation_test.dart test/widgets/pending_revalidation_chip_test.dart`

- [ ] **Step 3: Run the full suite**

Run: `flutter test --dart-define=CHICKMARK_DEBUG_AUTH_BYPASS=false`

- [ ] **Step 4: Run analysis**

Run: `flutter analyze lib test`

- [ ] **Step 5: Self-review**

Confirm all requested regressions are represented, no production auth bypass path changed, only automatic sync is suppressed offline, and real-device verification remains clearly called out if unavailable.
