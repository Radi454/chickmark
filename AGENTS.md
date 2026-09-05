# ChickMark Agent Guide

Repo-level guidance for coding agents working in this repository. ChickMark is
an offline-first Flutter hatchery-audit app: SQLite is the working store,
Supabase is a mirror it syncs to when it can.

## Primary Sources

- Current Flutter codebase is the primary source of truth.
- docs/LIVING_SPEC.md is the living documentation of implemented behavior. It
  describes only current behavior, in the present tense.
- docs/CHANGELOG.md is the dated history of changes, newest at top. It records
  what happened over time, including behavior that has since changed.
- The two are complementary: the spec says what is true now, the changelog says
  what happened. Never rewrite an old changelog entry when behavior later
  changes; add a new entry instead.
- If docs and code conflict, inspect code and report mismatch.
- Do not use deleted/old specs for implementation decisions.

Old generated specs must not be used unless the user explicitly provides them
again for a future task. Agents must inspect the current code before planning or
modifying product behavior.

## Current Workflow

- Work on one user-scoped task at a time.
- Do not mark product tasks complete unless the human reviewer explicitly
  approves it.
- Prefer additive, migration-safe changes.
- Preserve existing working behavior unless the task explicitly changes it.
- Run the narrowest relevant validation for the task you are implementing.
- After every meaningful code change, in the same commit: update
  `docs/LIVING_SPEC.md` so it still describes only current behavior, and add a
  dated entry to `docs/CHANGELOG.md` (newest at top, format `- YYYY-MM-DD:`)
  describing what changed. A meaningful change touches both files.
- End each task with a short handoff that lists:
  - task id
  - summary of changes
  - files changed
  - tests or commands run
  - risks or assumptions

## Where Things Live

- `lib/main.dart`, `lib/app.dart` — bootstrap, root providers, route table.
- `lib/features/<area>/` — one folder per product area (`audits`, `dashboard`,
  `govee`, `auth`, `customers`, `lab_analysis`, `bmk`, `performance`, `agents`,
  `admin`, `home`, `settings`, `sync`), each with its own `screens/`,
  `widgets/`, `providers/`.
- `lib/data/database/` — schema, migrations, `DatabaseHelper`.
- `lib/data/repositories/` — all SQLite reads/writes and sync bookkeeping.
- `lib/services/supabase/` — remote client, startup sync, cloud mappers.
- `lib/core/` — constants, thresholds, calculation utils, security policy.
- `lib/l10n/app_localizations.dart` — localization.
- `test/` — 217 test files mirroring the `lib/` layout, plus
  `test/support/test_database.dart`.

## Commands

```bash
flutter analyze
```

```bash
flutter test
```

Run the narrowest scope while iterating, e.g.
`flutter test test/features/govee/`.

Launching the app goes through the Makefile, which supplies Supabase credentials
from the ignored `.env` via `--dart-define-from-file`:

- `make run` / `make restart-web` — Flutter web on the fixed dev origin.
- `make run-macos`, `make run-ios`, `make run-android` — device/desktop runs;
  these also pass `CHICKMARK_DEBUG_AUTH_BYPASS` (default `true`, non-release
  only).
- `make build-macos`, `make build-ios`, `make build-apk` — release builds.

## Persistence, Sync, and Migrations

Be especially careful in `lib/data/database/`, `lib/data/models/`,
`lib/data/repositories/`, and `lib/services/supabase/`. Bugs here corrupt field
data that may exist only on one device.

**Schema changes.** The database is at version 81 (`database_helper.dart`).
Changing the schema means updating all of these together, or upgrades break on
real devices while fresh installs look fine:

1. Bump the `version:` passed to `openDatabase`.
2. Add an `_applyV<N>Upgrade` handler and wire it into `_onUpgrade`.
3. Make the fresh-install `CREATE TABLE` in `database_schema.dart` match what
   the upgrade produces.
4. Add new columns to the `_criticalColumns` map used by surgical repair.
5. Update the schema tests that assert `PRAGMA user_version`.

Never edit a shipped migration to fix a later problem — add the next version.
Migrations run against databases built by older and divergent branches, so guard
with `_tableExists` / column checks rather than assuming a shape.

**Sync.** Sync is per-row and dirty-tracked: local writes stamp a row pending,
pushes send only dirty rows, and a successful push marks them synced under a
`dirtyAt` cutoff so an edit landing mid-push is not silently dropped. Deletes go
through `sync_tombstones`, child-before-parent. Customer-role devices pull only
(`canPush` is false) and must not be blocked by push-side guards. When adding a
table to sync, follow an existing repository's dirty-tracking methods rather
than inventing a new pattern.

## Gotchas

- **Localization is a hand-written map**, not generated from `.arb` — there is
  no `l10n.yaml`. `lib/l10n/app_localizations.dart` maps English source strings
  to Arabic. Changing a user-facing English literal means changing the matching map
  key in the same edit, or the Arabic translation silently falls back to
  English.
- **Temperature units differ by station.** Egg Storage stores Celsius; Setter,
  Hatcher, and CVT store Fahrenheit. The `°F`/`°C` control is a display toggle
  over a fixed canonical unit — do not assume one unit app-wide.
- **Tests that touch the real database must isolate it.** `DatabaseHelper` is a
  singleton on a fixed filename, and `flutter test` runs suites concurrently in
  separate isolates, so suites sharing the default path race on one file. Use
  `useIsolatedAppDatabase()` from `test/support/test_database.dart`.
- **Widget tests should inject fakes, not the real database.** Driving real
  `sqflite` under `testWidgets` deadlocks against the fake-async clock. Existing
  screen tests pass fake repositories and pump a bounded number of frames rather
  than calling `pumpAndSettle`.
- **Web preview uses a fixed origin**, `http://127.0.0.1:57863`, to preserve the
  browser's IndexedDB-backed local app data between runs. Restart on that same
  origin with `make restart-web` or `RESTART=1 make run-web`; do not switch
  ports unless the user asks for a clean browser-storage environment.
- **The repo may contain unrelated local changes**; do not revert them unless
  the user explicitly asks.
- Documentation should describe implemented behavior, not planned or deprecated
  spec behavior. In `docs/LIVING_SPEC.md` that means current behavior only; in
  `docs/CHANGELOG.md` it means changes that actually shipped, described as they
  were when they landed.

## Stack

- Dart / Flutter, with Provider for state management.
- `sqflite` on mobile and desktop, `sqflite_common_ffi_web` on web.
- Supabase (Postgres + object storage + Edge Functions) as the cloud mirror.
- `fl_chart` for charts, `uuid` for ids, and a hand-written localization layer.
