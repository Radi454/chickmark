# ChickMark — Application Specification

**Status**: Living document | **Branch at generation**: `006-dashboard` | **DB version**: 15 | **Constitution**: 2.2.0 | **Generated**: 2026-04-25

---

## 1. Executive Summary

ChickMark is an offline-first Flutter application for poultry hatchery auditors. It digitizes structured audit workflows across five station types: Egg Storage, Chick Quality, Hatch Analysis, Setter Optimizing, and Hatcher Optimizing. Auditors conduct visits on-device without connectivity; data syncs to Supabase in the background.

**Package**: `hatchaudit` | **App Title**: `ChickMark` | **File**: `hatchaudit.db`
**Flutter SDK**: `^3.10.7` | **Dart 3** | **Material 3**
**Version**: `1.0.0+1`
**Platforms**: iOS (primary), Android (supported), web/macOS (planned)

### Architecture at a Glance

| Layer | Technology |
|-------|-----------|
| UI | Flutter / Material 3 |
| State | Provider (`ChangeNotifier`) |
| Local DB | SQLite via `sqflite` v15 |
| Cloud | Supabase (sync only — SQLite is source of truth) |
| Auth | Supabase JWT + local offline fallback (SHA-256 v2 hash) |
| BLE | `flutter_blue_plus` → Govee temperature/humidity sensors |
| Storage | `flutter_secure_storage` for JWT tokens |

---

## 2. Architecture Overview

### Entry Point

`lib/main.dart` → initializes `DatabaseHelper`, runs `_migrateTokensToSecureStorage()`, then calls `runApp(HatchAuditApp())`.

### App Bootstrap (`lib/app.dart`)

`HatchAuditApp` (StatefulWidget) wraps a `MultiProvider` containing all top-level providers, then a `Consumer<AuthProvider>` that drives route selection via `_getInitialRoute()`.

**Route selection logic:**
```
authenticated   → /startup-sync
pendingApproval → /pending-approval
loading/error/unauthenticated → /login
```

A `_RouteNameObserver` (NavigatorObserver) tracks the current route name so the `_AppMeasureOverlay` knows when to show/hide the floating Govee launcher.

### Navigation Shell

`/main` → `MainShell` (bottom navigation, 6 tabs):

| Index | Tab | Screen |
|-------|-----|--------|
| 0 | Home | `HomeScreen` |
| 1 | Dashboard | `DashboardScreen` |
| 2 | Customers | `CustomersScreen` |
| 3 | Audits | `AuditsScreen` |
| 4 | BMK | `BmkScreen` |
| 5 | Settings | `SettingsScreen` |

**Constitution exception**: a 7th tab for Temperature exists as a temporary carve-out during the session-based workflow rollout. It does not appear in the core 6-tab spec.

### State Management

All state via `ChangeNotifier` providers registered at app root:

| Provider | Owns |
|----------|------|
| `AppProvider` | General app state / UI flags |
| `AuthProvider` | Auth state, user identity, login/logout |
| `CustomersProvider` | Customer list, flock list, audit counts |
| `AuditProvider` | Single audit record under edit, dirty tracking |
| `AuditSessionProvider` | Active multi-station visit session, station progress |
| `TemperatureRhProvider` | Govee BLE session, live readings |
| `BmkProvider` | Benchmark breed + egg breakout data |
| `SettingsProvider` | User preferences, temperature unit |
| `DashboardProvider` | Aggregated chart data for dashboard (feature/dashboard/) |
| `HomeProvider` | KPIs, recent audits, continue-sessions for home screen |

### Persistence Stack

```
UI → Provider → Repository → DatabaseHelper (sqflite)
                           ↘ SupabaseService (background sync)
```

- All writes go to SQLite first.
- Supabase sync is fire-and-forget; failures are logged, not surfaced.
- `StartupSyncService` pulls remote data on each authenticated app launch.

---

## 3. Screens Inventory

### Authentication

| Screen | File | Path | Purpose | Reached Via |
|--------|------|------|---------|-------------|
| LoginScreen | `lib/features/auth/screens/login_screen.dart` | `/login` | Email/password login. "Remember me" enables offline token cache. Offline fallback to local SHA-256 hash. | Initial route when unauthenticated |
| RegisterScreen | `lib/features/auth/screens/register_screen.dart` | `/register` | New account creation. Password strength indicator. After submit → pending approval. | "Create account" link on LoginScreen |
| PendingApprovalScreen | `lib/features/auth/screens/pending_approval_screen.dart` | `/pending-approval` | Read-only holding screen. Shows "waiting for admin approval" message. | After successful registration |

### App Shell & Sync

| Screen | File | Path | Purpose | Reached Via |
|--------|------|------|---------|-------------|
| StartupSyncScreen | `lib/features/sync/screens/startup_sync_screen.dart` | `/startup-sync` | Progress UI during initial Supabase sync. Navigates to `/main` on completion. | First screen after authentication |
| MainShell | `lib/features/home/widgets/main_shell.dart` | `/main` | Bottom navigation container for 6 tabs. | After sync completes |

### Home

| Screen | File | Purpose | UI Elements |
|--------|------|---------|-------------|
| HomeScreen | `lib/features/home/screens/home_screen.dart` | Dashboard KPIs, recent audits, quick-start new audit, continue in-progress sessions. | KPI cards, recent audit list, "New Visit" FAB/button, continue-session cards, sync status indicator |

### Customer Management

| Screen | File | Purpose | Reached Via | Key UI |
|--------|------|---------|-------------|--------|
| CustomersScreen | `lib/features/customers/screens/customers_screen.dart` | List all customers with search. | Tab 2 | Search bar, `CustomerCard` list, FAB → `AddCustomerSheet` |
| CustomerDetailScreen | `lib/features/customers/screens/customer_detail_screen.dart` | View customer profile, flocks, hatcheries, audit history. | Tap customer card | Flock cards, hatchery cards, `AuditHistoryCard`, edit/delete actions |
| AuditDetailScreen | `lib/features/customers/screens/audit_detail_screen.dart` | Full read-only view of a single legacy audit record. | Tap audit in history | All audit fields grouped by section; photo thumbnails |
| VisitDetailScreen | `lib/features/customers/screens/visit_detail_screen.dart` | Detailed view of a completed audit session (multi-station visit). | Tap session in history | Station summaries, findings, scorecard |

### Audit / Visit Workflow

| Screen | File | Purpose | Reached Via | Key UI |
|--------|------|---------|-------------|--------|
| AuditsScreen | `lib/features/audits/screens/audits_screen.dart` | Full audit history with search, filter, CSV export. | Tab 3 | Search bar, `AuditFilterSheet`, list of audits, export button |
| AuditTypeSelectionScreen | `lib/features/audits/screens/audit_type_selection_screen.dart` | Select one of 5 audit type cards. | New audit flow | 5 type cards |
| AuditContextScreen | `lib/features/audits/screens/audit_context_screen.dart` | Select customer, flock, hatchery for the new session. | After type selection | Dropdowns for customer/flock/hatchery, date picker |
| AuditSessionScreen | `lib/features/audits/screens/audit_session_screen.dart` | Multi-station visit shell. Shows progress, navigates between 5 stations. | After context selection | Step progress indicator, station navigation buttons, `UnsavedChangesGuard` |
| ChickQualityScreen | `lib/features/audits/screens/chick_quality_screen.dart` | Data entry for Chick Quality station. 6 sub-tabs. | Station 2 in session | Tabs: CHA Env, Pasgar, Weights, YFBM, CVT, PM Necropsy |
| HatchAnalysisScreen | `lib/features/audits/screens/hatch_analysis_screen.dart` | Data entry for Hatch Analysis. 2 sections: Hatch Results + Egg Breakout. | Station 3 in session | Tray grid, counts, BMK comparison, breakout type selector |
| EggStorageScreen | `lib/features/audits/screens/egg_storage_screen.dart` | Data entry for Egg Storage station. | Station 1 in session | Govee sector, shell temp, EST grid, UV inspection, egg weights, orientation fields |
| SetterOptimizingScreen | `lib/features/audits/screens/setter_optimizing_screen.dart` | Data entry for Setter Optimizing. | Station 4 in session | Machine type, turning angle, Govee sector, EST grid, CO2 |
| HatcherOptimizingScreen | `lib/features/audits/screens/hatcher_optimizing_screen.dart` | Data entry for Hatcher Optimizing. | Station 5 in session | Govee sector, CVT grid, CO2, chick panting, meconium, transfer day |

### Dashboard & Analytics

| Screen | File | Purpose | Key UI |
|--------|------|---------|--------|
| DashboardScreen | `lib/features/dashboard/screens/dashboard_screen.dart` | Cascade-filtered analytics charts for all audit types. | Customer → Flock → Age → ID filter chain; chart sections per audit type; clear-filters button |
| PhotoFullscreenScreen | `lib/features/dashboard/screens/photo_fullscreen_screen.dart` | Full-screen photo viewer. | Pinch-to-zoom, swipe navigation |

### Temperature / Govee

| Screen | File | Purpose | Key UI |
|--------|------|---------|--------|
| TemperatureRhScreen | `lib/features/temperature/screens/temperature_rh_screen.dart` | Dedicated temperature monitoring screen. | Device selector, live temp/RH values, session controls, chart |

### BMK

| Screen | File | Purpose | Key UI |
|--------|------|---------|--------|
| BmkScreen | `lib/features/bmk/screens/bmk_screen.dart` | Read-only benchmark reference. 2 sections. | Section 1: breed selector + age dropdown → 1 row table. Section 2: age-only egg breakout percentages |

### Settings

| Screen | File | Purpose | Key UI |
|--------|------|---------|--------|
| SettingsScreen | `lib/features/settings/screens/settings_screen.dart` | App preferences, user profile, temp unit toggle. | °C/°F toggle, profile fields, logout button |
| ActivityLogScreen | `lib/features/settings/screens/activity_log_screen.dart` | View user action history. | Timestamped action list |

---

## 4. Features Inventory

### 4.1 Multi-Station Audit Sessions

**Files**: `audit_session_provider.dart`, `audit_session_repository.dart`, `audit_session_model.dart`, `audit_session_screen.dart`, `audit_sessions` table

**Stations** (in order): `egg_storage` → `chick_quality` → `hatch_analysis` → `setter_optimizing` → `hatcher_optimizing`

**Inputs**: customer, flock, hatchery, date, breed, flock age (auto-calculated)

**Outputs**: `AuditSessionModel` with `stationsCompleted` list, `findingsJson`, `scorecardJson`, `status` (in_progress / completed)

**Status**: Implemented. `AuditSessionProvider` manages navigation between stations, auto-wires Govee place per station (see §8).

---

### 4.2 Chick Quality Audit

**Files**: `chick_quality_screen.dart`, tabs in `lib/features/audits/widgets/tabs/`

| Sub-tab | Widget | Key Fields |
|---------|--------|------------|
| CHA Env | `cha_env_tab.dart` | CO2, PM10, PM25, air velocity (3 spots + inlet/outlet), noise level, Govee connected |
| Pasgar | `pasgar_tab.dart` | Sample size, 6 parameter counts (reflexes, beak, navel, belly, leg, featherDev), final score (auto-calculated) |
| Weights | `weights_tab.dart` | Storage days, sample size, individual weights (JSON), avg weight, uniformity%, CV%, BMK age/weight |
| YFBM | `yfbm_tab.dart` | Photo, entries (chick weight + yolk weight pairs), avg%, CV% |
| CVT | `cvt_tab.dart` | Sample size, top/middle/bottom basket temps, avg, CV% |
| PM Necropsy | `pm_necropsy_tab.dart` | Sample size, collection point, 20+ condition counts with severity, deformity counts, suspected cause (auto + manual), photos JSON |

**Status**: Implemented. All 6 tabs functional.

---

### 4.3 Hatch Analysis Audit

**Files**: `hatch_analysis_screen.dart`, `tray_model.dart`

| Section | Key Fields |
|---------|-----------|
| Hatch Results | Storage days, total eggs set, hatched, culled, dead, hatchability%, fertility%, HOF%, tray grid (JSON), pipped, infertile clear, early/mid/mid-late/late dead, contaminated exploders, benchmark statuses JSON |
| Egg Breakout | Tray size, breakout type (Fresh/Residue/Candled), age days, storage days, tray data (JSON), 12 count fields (infertile, early/mid/late dead, internal/external pip, cracked, contaminated, malposition, exposed brain, crossed beak, culled dead) |

**Status**: Implemented.

---

### 4.4 Egg Storage Audit

**Files**: `egg_storage_screen.dart`

**Key Fields**: Govee connected + readings, CO2, shell temp, EST readings (JSON), EST avg/CV, UV inspection (sample size + 5 defect counts + photos), egg quality percentages (crack, broken, misshaped, pale shell, rough texture, floor egg), color distribution (JSON), orientation/spacing/proximity/condensation fields, egg weights (JSON), avg/uniformity/CV%, BMK age/weight.

**Status**: Implemented.

---

### 4.5 Setter Optimizing Audit

**Files**: `setter_optimizing_screen.dart`

**Key Fields**: Breed, setter ID, incubation age, machine type, turning angle, Govee connected + readings, CO2, EST grid readings (JSON), EST avg/CV.

**Status**: Implemented.

---

### 4.6 Hatcher Optimizing Audit

**Files**: `hatcher_optimizing_screen.dart`

**Key Fields**: Breed, hatcher ID, incubation age, Govee connected + readings, CO2, CVT readings (JSON), CVT avg/CV, chick panting (boolean + photo), meconium, transfer day.

**Status**: Implemented.

---

### 4.7 Temperature / RH Monitoring (Govee)

**Files**: `govee_service.dart`, `temperature_rh_provider.dart`, `temperature_rh_repository.dart`, `temperature_rh_model.dart`, `temperature_rh_screen.dart`, `temperature_rh_launcher.dart`, `temperature_rh_panel.dart`

**Tables**: `temperature_sessions`, `temperature_readings`

**Session lifecycle**: Start session with place + device → warmup period (120s) → readings accumulate in `temperature_readings` → end session → summary stats written to `temperature_sessions` (avg/min/max/CV for temp + RH, chart point JSON arrays).

**Places** (TemperaturePlace enum): `outsideHatchery`, `eggStorageRoom`, `chickHoldingArea`, `incubatorRoom`, `hatcherRoom`, `insideIncubator`, `insideHatcher`

**Floating launcher**: `_AppMeasureOverlay` in `app.dart` renders a draggable, dockable overlay button (64×64) visible on all authenticated routes except `/login` and `/startup-sync`. Docks to left/right edge with pull-tab handle.

**Status**: Implemented. BLE scanning via `flutter_blue_plus`. Graceful fallback to manual entry when BLE unavailable.

---

### 4.8 Dashboard Analytics

**Files**: `dashboard_provider.dart`, `dashboard_screen.dart`, `stub_sections.dart`, `hatch_analysis_section.dart`, `egg_breakout_section.dart`, chart widgets

**Filter chain**: Customer → Flock → BMK Age → Setter/Hatcher ID

**Sections**: HatchAnalysis, EggBreakout, ChickQuality (5 sub-tabs: Pasgar, Weights, YFBM, CVT, CHA Env), EggStorage, SetterOptimizing, HatcherOptimizing

**Charts**: `BmkBarChart`, `BmkLineChart`, `BmkDonutChart` via `fl_chart`

**Status**: Partially implemented. HatchAnalysis and EggBreakout sections wired. ChickQuality sub-tabs, EggStorage, Setter, Hatcher sections are stub implementations pending Phase 1 work. Filter cascade reset also pending.

---

### 4.9 Customer & Flock Management

**Files**: `customers_provider.dart`, `customer_repository.dart`, `flock_repository.dart`, `hatchery_repository.dart`, customers screens + sheet widgets

**Features**: CRUD for customers, flocks, hatcheries. Search. Flock age auto-calculation from `entryDate`. Flock status (active/sold) with depletion age tracking.

**Status**: Implemented.

---

### 4.10 Benchmark Reference (BMK)

**Files**: `bmk_provider.dart`, `bmk_screen.dart`, `bmk_repository.dart`, `bmk_breed_model.dart`, `bmk_egg_breakout_model.dart`, `bmk_seeds.dart`

**Breeds**: Ross308, Arbo, Avian, Cobb500, Hubbard, IR | **Age range**: 24–65 weeks
**Formula**: `BMK Age = Flock Age − 21 days − Storage Days`

**Status**: Implemented. Read-only. Seeded at DB creation.

---

### 4.11 Authentication

**Files**: `auth_provider.dart`, `user_repository.dart`, `secure_token_store.dart`

**Online flow**: Supabase auth → JWT stored in `flutter_secure_storage` (not SQLite).
**Offline flow**: Local account (`id` prefix `local-`) with v2 password hash (`v2:<salt>:<sha256(salt:password)>`).
**Legacy migration**: v1 tokens (`local:base64...`) upgraded to v2 on next login.
**Roles**: admin, auditor, customer (see Constitution §XI).
**Token expiry**: 30 days.

**Status**: Implemented. Secure storage migration path included.

---

### 4.12 Photo Management

**Files**: `photo_service.dart`, `photo_sync_service.dart`, `photo_repository.dart`, `photo_model.dart`, `photo_button.dart`, `photo_grid.dart`

**Storage**: Local file path in `photos` table, linked by `auditId`.
**Upload status**: `local` | `synced` | `failed` (column `uploadStatus` added v12).
**Sync**: `PhotoSyncService.syncPending()` called by `StartupSyncService`. Uploads to Supabase Storage bucket `photos`.
**UI**: `PhotoButton` shows cloud status icon overlay. `PhotoGrid` for multi-photo display. `PhotoFullscreenScreen` for full-size view.

**Status**: Implemented.

---

### 4.13 Export & Reporting

**Files**: `csv_export_service.dart`, `pdf_export_service.dart`

**Status**: Files exist. Wire-up to UI is partial (CSV export button in `AuditsScreen`). PDF generation not fully surfaced.

---

### 4.14 Troubleshooting Guide

**Files**: `troubleshooting_seeds.dart`, `troubleshooting_repository.dart`, `troubleshooting_model.dart`, `troubleshooting_sheet.dart`, `troubleshooting_icon.dart`

**IDs seeded**: `high_infertile`, `high_early_dead`, `high_late_dead`, `low_hatchability`, `low_pasgar`, `high_cv`

**Structure**: Each record has `hatcheryCauses` + `farmFlockCauses` (both JSON, organized by section header → string list).

**UI**: 💡 icon next to threshold-exceeding fields → taps open `TroubleshootingSheet` (bottom sheet, tabbed [Hatchery / Farm], search field).

**Status**: Implemented. Seeds run at DB creation (v12+).

---

### 4.15 Activity Log

**Files**: `activity_log_repository.dart`, `activity_log_model.dart`, `activity_log_screen.dart`

**Fields**: userId, action, entityType, entityId, details, timestamp

**Status**: Implemented. `AuditSessionProvider` logs session create/update/complete events.

---

### 4.16 Offline-First Sync

**Files**: `supabase_service.dart`, `startup_sync_service.dart`

**On startup**: Pulls customers, flocks, hatcheries, audits, photos, audit sessions from Supabase → upserts to SQLite.
**On write**: Local SQLite write first; background push to Supabase.
**Conflict resolution**: Last-write-wins via `upsert` with `updatedAt` timestamps.

**Status**: Implemented.

---

## 5. Navigation Map

```
/login
  └─► /register
        └─► /pending-approval
  └─► (authenticated) /startup-sync
        └─► /main (MainShell)
              ├─ Tab 0: HomeScreen
              │    └─► AuditContextScreen (new visit)
              │          └─► AuditSessionScreen
              │                ├─ EggStorageScreen
              │                ├─ ChickQualityScreen
              │                ├─ HatchAnalysisScreen
              │                ├─ SetterOptimizingScreen
              │                └─ HatcherOptimizingScreen
              ├─ Tab 1: DashboardScreen
              │    └─► PhotoFullscreenScreen
              ├─ Tab 2: CustomersScreen
              │    └─► CustomerDetailScreen
              │          ├─► AuditDetailScreen (legacy audit)
              │          └─► VisitDetailScreen (session)
              ├─ Tab 3: AuditsScreen
              │    └─► (AuditFilterSheet — modal)
              ├─ Tab 4: BmkScreen
              └─ Tab 5: SettingsScreen
                   └─► ActivityLogScreen
```

**Floating overlay** (all authenticated routes except /login, /startup-sync):
```
_AppMeasureOverlay
  └─ TemperatureRhLauncher (draggable/dockable FAB)
       └─► TemperatureRhPanel (side panel or modal)
             └─► TemperatureRhScreen (optional full-screen)
```

---

## 6. Database Audit

**File**: `lib/data/database/database_helper.dart`
**Database**: `hatchaudit.db` (SQLite)
**Current Version**: **15**

### Migration History

| Version | Changes |
|---------|---------|
| 1 | Initial schema: users, customers, flocks, audits, bmk_breeds, bmk_egg_breakout, troubleshooting, photos |
| 2 | `audits.hatchNumber` added; `idx_audits_unique` recreated with hatchNumber |
| 3 | `bmk_breeds` + `bmk_egg_breakout` recreated; seeds re-inserted |
| 4 | `bmk_egg_breakout`: added feathersPct, turnedPct, exposedBrainPct, crossedBeakPct, crackedPct |
| 5 | `bmk_egg_breakout`: added earlyDeadPct, midBlackEyePct, internalPipPct, externalPipPct; BMK seed backfill |
| 6 | `audits`: 12 egg breakout count columns added (ebInfertileCount … ebCulledDeadCount) |
| 7 | `_ensureUserAuthColumns` — token/expiry columns |
| 8 | Dummy test data seeded |
| 9 | `flocks.isAgeEstimated` added |
| 10 | `hatcheries` table created; `temperature_sessions` + `temperature_readings` tables created |
| 11 | `flocks.status`, `flocks.depletionAgeWeeks`, `flocks.soldAt` added |
| 12 | `photos.uploadStatus` added; existing photos marked `synced`; troubleshooting seeded |
| 13 | Operational indexes created on audits, photos, flocks |
| 14 | `activity_log` table created + index |
| 15 | `audit_sessions` table created; `audits.sessionId` added; all PM Necropsy columns (pm_*) added; extended egg storage columns (es_*); setter/hatcher extension columns (so_*, ho_*); extended hatch analysis columns (haPipped … haContaminatedExploders, haBenchmarkStatusesJson); temperature_sessions stat columns + warmupSeconds + auditSessionId added; audit_session index on temperature_sessions |

---

### Table Schemas (v15)

#### `users`
| Column | Type | Constraints |
|--------|------|-------------|
| id | TEXT | PRIMARY KEY |
| fullName | TEXT | |
| email | TEXT | UNIQUE |
| role | TEXT | (admin/auditor/customer) |
| status | TEXT | |
| customerId | TEXT | |
| accessToken | TEXT | NULL for online users (token in secure storage) |
| tokenExpiry | TEXT | |
| createdAt | TEXT | |
| lastLoginAt | TEXT | |

#### `customers`
| Column | Type |
|--------|------|
| id | TEXT PK |
| name | TEXT |
| location | TEXT |
| phone | TEXT |
| email | TEXT |
| createdAt | TEXT |
| createdBy | TEXT |

#### `flocks`
| Column | Type | Default |
|--------|------|---------|
| id | TEXT PK | |
| customerId | TEXT | |
| flockId | TEXT | |
| breed | TEXT | |
| entryDate | TEXT | |
| isAgeEstimated | INTEGER | 0 |
| status | TEXT NN | 'active' |
| depletionAgeWeeks | INTEGER NN | 65 |
| soldAt | TEXT | |

**Index**: `idx_flocks_customer` ON (customerId, status)

#### `hatcheries`
| Column | Type | Constraints |
|--------|------|-------------|
| id | TEXT PK | |
| customerId | TEXT | NOT NULL |
| name | TEXT | NOT NULL |
| location | TEXT | |
| notes | TEXT | |
| createdAt | TEXT | |
| createdBy | TEXT | |

**Index**: `idx_hatcheries_customer` ON (customerId)

#### `audits` — 200+ columns (denormalized)

**Core Identity**:
`id`, `customerId`, `flockId`, `auditType`, `date`, `hatchNumber` (NN DEFAULT 1), `setterId`, `hatcherId`, `status`, `createdBy`, `createdAt`, `updatedAt`, `notes`, `sessionId`

**Unique constraint**: `idx_audits_unique` ON (customerId, flockId, date, auditType, hatchNumber, setterId, hatcherId)

**Chick Quality — CHA Environmental** (`cha` prefix):
`chaGoveeConnected`, `chaCo2` + Photo, `chaPm10` + Photo, `chaPm25` + Photo,
`chaAirVelocitySpot1/2/3` + Photos, `chaAirInlet/Outlet` + Photos, `chaNoiseLevel` + Photo

**Chick Quality — Pasgar** (`pasgar` prefix):
`pasgarSampleSize`, `pasgarReflexes/Beak/Navel/Belly/Leg/FeatherDev` + Photos each, `pasgarFinalScore`

**Chick Quality — Weights** (`chick` prefix):
`chickStorageDays`, `chickSampleSize`, `chickWeights` (JSON), `chickAvgWeight`, `chickUniformityPct`, `chickCvPct`, `chickBmkAge`, `chickBmkWeight`

**Chick Quality — YFBM**:
`yfbmPhoto`, `yfbmEntries` (JSON), `yfbmAvgPct`, `yfbmCvPct`

**Chick Quality — CVT**:
`cvtSampleSize`, `cvtTopBasket`, `cvtTopTemp`, `cvtTopPhoto`, `cvtMiddleBasket`, `cvtMiddleTemp`, `cvtMiddlePhoto`, `cvtBottomBasket`, `cvtBottomTemp`, `cvtBottomPhoto`, `cvtAvg`, `cvtCvPct`

**Chick Quality — PM Necropsy** (`pm_` prefix, added v15):
`pm_sampleSize`, `pm_collectionPoint`,
Disease counts + severity: `pm_omphalitis`, `pm_gaseousCeca`, `pm_unabsorbedYolk`, `pm_perihepatitis`, `pm_pericarditis`, `pm_airsacAcute`, `pm_airsacChronic`, `pm_pulmonaryGranuloma`, `pm_swollenJoints`, `pm_stuntedOrgans`, `pm_pulmonaryHemorrhage`
`pm_gaspingPresent`, `pm_gaspingType`
Deformities: `pm_exposedBrainCount`, `pm_ectopicVisceraCount`, `pm_extraLegsCount`, `pm_crossedBeakCount`, `pm_absentEyeBothCount`, `pm_absentEyeOneCount`, `pm_smallEyeCount`, `pm_hydrocephalyCount`, `pm_starGazerCount`, `pm_curledToesCount`, `pm_shortLegsCount`, `pm_spinalDeformityCount`, `pm_cardiacAnomalyCount`, `pm_conjoinedCount`, `pm_otherDeformityCount`, `pm_otherDeformityText`
`pm_suspectedCauseAuto`, `pm_suspectedCauseManual`, `pm_photosJson`

**Hatch Analysis — Hatch Results** (`ha` prefix):
`haStorageDays`, `haTotalEggsSet`, `haHatched`, `haCulled`, `haDead`,
`haHatchability`, `haFertility`, `haHof`, `haTrays` (JSON), `haBmkAge`,
`haPipped`, `haInfertileClear`, `haEarlyDead`, `haMidDead`, `haMidLateDead`, `haLateDead`, `haContaminatedExploders`, `haBenchmarkStatusesJson`

**Hatch Analysis — Egg Breakout** (`eb` prefix):
`ebTraySize`, `ebBreakoutType`, `ebBreakoutAgeDays`, `ebStorageDays`, `ebTrays` (JSON), `ebBmkAge`,
`ebInfertileCount`, `ebEarlyDeadCount`, `ebMidDeadCount`, `ebLateDeadCount`, `ebInternalPipCount`, `ebExternalPipCount`, `ebCrackedCount`, `ebContaminatedCount`, `ebMalpositionCount`, `ebExposedBrainCount`, `ebCrossedBeakCount`, `ebCulledDeadCount`

**Setter Optimizing** (`so` prefix):
`soBreed`, `soSetterId`, `soIncubationAge`, `soGoveeConnected`, `soGoveeTemp`, `soGoveeHumidity`,
`soCo2` + Photo, `soEstReadings` (JSON), `soEstPhotos` (JSON), `soEstAvg`, `soEstCv`,
`so_machineType`, `so_turningAngle`

**Hatcher Optimizing** (`ho` prefix):
`hoBreed`, `hoHatcherId`, `hoIncubationAge`, `hoGoveeConnected`, `hoGoveeTemp`, `hoGoveeHumidity`,
`hoCo2` + Photo, `hoCvtReadings` (JSON), `hoCvtPhotos` (JSON), `hoCvtAvg`, `hoCvtCv`,
`hoChickPanting` + Photo, `ho_meconium`, `ho_transferDay`

**Egg Storage** (`es` prefix):
`esGoveeConnected`, `esGoveeTemp`, `esGoveeHumidity`, `esCo2` + Photo, `esShellTemp` + Photo,
`esTurningTimes`, `esUvTrays`, `esEggStorageDays`, `esEggSampleSize`, `esEggWeights` (JSON),
`esEggAvgWeight`, `esEggUniformityPct`, `esEggCvPct`, `esEggBmkAge`, `esEggBmkWeight`,
`es_estReadingsJson`, `es_estAvg`, `es_estCv`,
`es_uvSampleSize`, `es_uvCuticleDamageCount`, `es_uvWashingEvidenceCount`, `es_uvFecalCount`, `es_uvMottledCount`, `es_uvOtherCount`, `es_uvPhotosJson`,
`es_crackPct`, `es_brokenPct`, `es_misshapedPct`, `es_paleShellPct`, `es_roughTexturePct`, `es_floorEggPct`,
`es_eggColorDistJson`, `es_eggOrientation`, `es_traySpacing`, `es_coolerProximity`, `es_wallProximity`, `es_condensation`

**Indexes on `audits`**:
- `idx_audits_unique` (customerId, flockId, date, auditType, hatchNumber, setterId, hatcherId)
- `idx_audits_customer` (customerId)
- `idx_audits_flock` (flockId)
- `idx_audits_date` (date DESC)
- `idx_audits_type` (auditType)
- `idx_audits_customer_type` (customerId, auditType)
- `idx_audits_customer_date` (customerId, date DESC)

#### `audit_sessions` (added v15)
| Column | Type | Constraints |
|--------|------|-------------|
| id | TEXT | PRIMARY KEY |
| customerId | TEXT | NOT NULL |
| flockId | TEXT | NOT NULL |
| hatcheryId | TEXT | NOT NULL |
| date | TEXT | NOT NULL |
| breed | TEXT | |
| flockAgeWeeks | INTEGER | |
| status | TEXT | DEFAULT 'in_progress' |
| stationsCompleted | TEXT | JSON array of station keys |
| findingsJson | TEXT | |
| scorecardJson | TEXT | |
| notes | TEXT | |
| createdBy | TEXT | |
| createdAt | TEXT | |
| updatedAt | TEXT | |
| completedAt | TEXT | |

**Valid station keys**: `egg_storage`, `chick_quality`, `hatch_analysis`, `setter_optimizing`, `hatcher_optimizing`

**Indexes**: `idx_audit_sessions_customer_date` (customerId, date DESC), `idx_audit_sessions_flock_date` (flockId, date DESC)

#### `bmk_breeds`
`id` PK, `breed` NN, `ageWeek` NN, `hatchabilityPct`, `fertilityPct`, `hofPct`, `productionPct`, `eggWeightG`, `chickWeightG` (all REAL DEFAULT 0.0)

**Breeds**: Ross308, Arbo, Avian, Cobb500, Hubbard, IR | **Age range**: Cobb500 24–65w, others 25–65w

#### `bmk_egg_breakout`
`id` PK, `ageWeek` UNIQUE, 25 percentage fields (infertilePct … externalPipPct)

#### `temperature_sessions`
`id` PK, `customerId` NN, `hatcheryId` NN, `deviceId`, `deviceName`, `startedAt` NN, `endedAt`, `activePlace` NN, `status` NN, `tempAvg/Min/Max/CvPct`, `rhAvg/Min/Max/CvPct`, `readingCount`, `alertCount`, `tempChartPointsJson`, `rhChartPointsJson`, `warmupSeconds` DEFAULT 120, `auditSessionId`, `createdAt` NN, `updatedAt` NN

**Indexes**: `idx_temperature_sessions_hatchery` (hatcheryId, startedAt), `idx_temperature_sessions_audit_session` (auditSessionId, startedAt)

#### `temperature_readings`
`id` PK, `sessionId` NN, `customerId` NN, `hatcheryId` NN, `place` NN, `temperatureFahrenheit` REAL NN, `humidity` REAL NN, `rssi`, `deviceName`, `recordedAt` NN, `createdAt` NN

**Indexes**: `idx_temperature_readings_session_time` (sessionId, recordedAt), `idx_temperature_readings_hatchery_time` (hatcheryId, recordedAt)

#### `photos`
`id` PK, `filePath`, `description`, `createdAt`, `auditId`, `uploadStatus` TEXT NN DEFAULT 'local'

**Index**: `idx_photos_audit` (auditId)

#### `activity_log`
`id` PK, `userId` NN, `action` NN, `entityType`, `entityId`, `details`, `timestamp` NN

**Index**: `idx_activity_log_user` (userId, timestamp DESC)

#### `troubleshooting`
`id` PK (parameter key e.g. `high_infertile`), `hatcheryCauses` TEXT (JSON), `farmFlockCauses` TEXT (JSON)

---

## 7. Data Flow

### Create Audit Session Flow

```
User taps "New Visit" on HomeScreen
  → HomeScreen pushes AuditContextScreen
  → User selects customer, flock, hatchery
  → AuditContextScreen calls AuditSessionProvider.startSession(context, currentUser)
  → Provider creates AuditSessionModel with UUID, status='in_progress', empty stationsCompleted
  → AuditSessionRepository.insertSession() → SQLite INSERT into audit_sessions
  → Provider sets _currentStationIndex = 0
  → Navigator pushes AuditSessionScreen
  → AuditSessionScreen reads provider.currentStationIndex → shows station 0 (EggStorageScreen)
```

### Station Save Flow

```
User fills fields in EggStorageScreen
  → calls AuditProvider.updateField(key, value) → sets _isDirty = true
  → User taps "Save Tab"
  → AuditProvider.saveTab() called
    → builds AuditModel from current state
    → AuditRepository.upsertAudit() → SQLite INSERT OR REPLACE into audits
    → sets audits.sessionId = currentSession.id
    → _isDirty = false
  → AuditSessionProvider.markCurrentStationCompleted()
    → adds 'egg_storage' to stationsCompleted
    → AuditSessionRepository.markStationCompleted(sessionId, 'egg_storage')
    → SQLite UPDATE audit_sessions SET stationsCompleted = JSON, updatedAt = now
```

### Read Flow (Dashboard)

```
DashboardScreen init
  → DashboardProvider.init(filter)
  → AuditRepository.getAuditsByCustomerAndType(customerId, auditType, ...)
    → rawQuery with parameterized WHERE clause (no string interpolation)
  → results parsed to model list
  → aggregated into chart data models
  → notifyListeners()
  → DashboardScreen rebuilds charts via Consumer<DashboardProvider>
```

### Update Audit Flow

```
User opens existing audit record
  → AuditProvider.loadAudit(auditId)
    → AuditRepository.getAuditById(id) → SQLite SELECT
    → sets _currentAudit = AuditModel.fromMap(row)
  → User edits field → AuditProvider.updateField()
  → User saves → AuditProvider.saveTab()
    → AuditRepository.updateAudit(model)
    → SQLite UPDATE audits SET ... WHERE id = ?
```

---

## 8. Govee Architecture

### Session Lifecycle

1. **Discovery**: `GoveeService.scanDevices()` → BLE scan → list of nearby Govee devices
2. **Connect**: `GoveeService.connectDevice(deviceId)` → BLE GATT connection
3. **Session start**: `TemperatureRhProvider.startSession(customerId, hatcheryId, activePlace)` → creates `TemperatureSessionModel`, inserts to `temperature_sessions` with `status='active'`
4. **Warmup**: 120-second warmup window (`warmupSeconds`); readings during warmup are discarded from statistics
5. **Live readings**: `GoveeService.readTemperature()` / `readHumidity()` → `TemperatureRhProvider.recordReading(temp, humidity)` → `TemperatureReadingRepository.insertTemperatureReading()` → live notification to UI
6. **Session end**: `TemperatureRhProvider.endSession()` → calculates avg/min/max/CV for temp and RH, serializes chart point arrays to JSON, updates `temperature_sessions` with summary stats + `status='completed'` + `endedAt`

### In-Memory Buffer

`TemperatureRhProvider` maintains readings in-memory for live chart rendering. The `tempChartPoints` and `rhChartPoints` getters on `TemperatureSessionModel` parse JSON → `List<ChartPoint>` for chart widgets.

### Summary Storage

Final statistics stored in `temperature_sessions`:
- `tempAvg`, `tempMin`, `tempMax`, `tempCvPct`
- `rhAvg`, `rhMin`, `rhMax`, `rhCvPct`
- `readingCount`, `alertCount`
- `tempChartPointsJson`, `rhChartPointsJson` (downsampled series for chart replay)

### Audit Session Integration

`AuditSessionProvider._stationGoveeMapping` maps each station key to a `TemperaturePlace`:

| Station | Place |
|---------|-------|
| `egg_storage` | `eggStorageRoom` |
| `chick_quality` | `chickHoldingArea` |
| `hatch_analysis` | `hatcherRoom` |
| `setter_optimizing` | `insideIncubator` |
| `hatcher_optimizing` | `insideHatcher` |

`TemperatureSession.auditSessionId` links readings to a specific visit session.

### Graceful Degradation

If BLE is unavailable or device is not found, all temperature/humidity fields remain manually editable. `chaGoveeConnected` / `soGoveeConnected` / `hoGoveeConnected` / `esGoveeConnected` / `hoGoveeConnected` flags track whether BLE was used for that audit record.

---

## 9. New Features Added in DB v15 Upgrade

This section documents everything added in the v15 schema upgrade (branch `006-dashboard` era, corresponding to the "007-chickmark-upgrade" spec directory).

### 9.1 Audit Sessions (`audit_sessions` table)

Full multi-station visit orchestration. Replaces the prior ad-hoc "audit type selection + single-screen" model with a coordinated session that:
- Links all 5 station audits under one `sessionId`
- Tracks which stations are complete (`stationsCompleted` JSON array)
- Stores cross-station metadata (`findingsJson`, `scorecardJson`)
- Supports resume: `AuditSessionProvider.resumeSession(sessionId)` restores navigation state

### 9.2 PM Necropsy

40+ new columns in `audits` (`pm_*` prefix). Captures post-mortem chick findings:
- 11 disease/condition groups with count + severity
- 15 deformity types with count
- Suspected cause (auto-generated from counts + manual override)
- Gasping type + presence
- Photos JSON array

New tab `pm_necropsy_tab.dart` in `ChickQualityScreen`.

### 9.3 Extended Egg Storage Fields

21 new columns (`es_*`):
- EST (Egg Shell Temperature) readings grid + avg/CV
- UV inspection grid: sample size + 5 defect type counts + photos
- Egg quality visual percentages (crack, broken, misshaped, pale shell, rough texture, floor egg)
- Color distribution JSON
- Orientation, tray spacing, cooler/wall proximity, condensation

### 9.4 Extended Hatch Analysis

7 new columns in `audits`:
`haPipped`, `haInfertileClear`, `haEarlyDead`, `haMidDead`, `haMidLateDead`, `haLateDead`, `haContaminatedExploders`, `haBenchmarkStatusesJson`

Enables detailed dead-in-shell categorization and per-category BMK status tracking.

### 9.5 Setter / Hatcher Extensions

- `so_machineType` (TEXT) — machine brand/type
- `so_turningAngle` (REAL) — setter turning angle in degrees
- `ho_meconium` (TEXT) — meconium quality observation
- `ho_transferDay` (INTEGER) — transfer day number

### 9.6 Temperature Session Summaries

7 new columns on `temperature_sessions` (v15):
`tempAvg`, `tempMin`, `tempMax`, `tempCvPct`, `rhAvg`, `rhMin`, `rhMax`, `rhCvPct`, `readingCount`, `alertCount`, `tempChartPointsJson`, `rhChartPointsJson`, `warmupSeconds`, `auditSessionId`

Plus new index linking temperature sessions to audit sessions.

### 9.7 Activity Log (`activity_log` table, v14)

Audit trail for all user actions. Entities logged: customers, flocks, hatcheries, audits, sessions, auth events.

### 9.8 Photo Upload Status (v12)

`photos.uploadStatus` column. Three states: `local` (not yet synced), `synced`, `failed`. `PhotoSyncService` handles retry on next startup.

### 9.9 Troubleshooting Seeding (v12)

`troubleshooting_seeds.dart` seeds 6 parameter guides on DB creation and upgrade. `TroubleshootingSheet` now always has data.

### 9.10 Operational Indexes (v13)

7 indexes on `audits`, 1 on `photos`, 1 on `flocks` to support dashboard query performance.

---

## 10. Known Gaps and Tech Debt

### Security (Phase 0 — mandatory)

| # | Issue | Risk | Status |
|---|-------|------|--------|
| 0.1 | `_buildWhere()` in `audit_repository.dart` uses string interpolation for SQL WHERE clauses (SQL injection risk) | HIGH | **OPEN** — planned in Phase 0 |
| 0.2 | Legacy v1 password tokens (`local:base64`) still accepted | HIGH | Partially addressed — v2 hash implemented, migration on next login |
| 0.3 | Supabase anon key must not appear in git history | MEDIUM | Requires `git log` audit |
| 0.4 | Pre-commit hook for secret detection not yet installed | MEDIUM | **OPEN** |

### Feature Completeness (Phase 1)

| # | Gap | Notes |
|---|-----|-------|
| 1.1 | Dashboard `ChickQualitySection` sub-tabs (Pasgar, Weights, YFBM, CVT, CHA Env) show stub/empty UI | Provider has data methods; UI not wired |
| 1.2 | Dashboard `EggStorageSection`, `SetterOptimizingSection`, `HatcherOptimizingSection` are stubs | Same as above |
| 1.3 | Dashboard filter cascade: changing customer does not reset flock dropdown; no "Clear filters" button | `clearFilters()` + `hasActiveFilters` methods not yet added to `DashboardProvider` |
| 1.4 | `UnsavedChangesGuard` widget exists in file but not confirmed wired to all 5 audit screens | Should wrap Scaffold in each screen |
| 1.5 | OCR service (`ocr_service.dart`) is a stub — not implemented | Apple Vision integration not done |
| 1.6 | PDF export not fully surfaced in UI | `pdf_export_service.dart` exists |
| 1.7 | Supabase `photos` storage bucket must be manually created before photo sync works | Not automated |
| 1.8 | `DashboardProvider` not included in `MultiProvider` in `app.dart` | Must be added before dashboard loads |

### Architecture Debt

| # | Issue |
|---|-------|
| D.1 | Constitution §V says "no repository layer" but repositories exist — this is an approved divergence in practice |
| D.2 | `audits` table has 200+ columns; any new audit field requires migration + model update + repository update |
| D.3 | Temperature tab is a permanent 7th tab despite constitution specifying 6 tabs — temporary exception (constitution §Exceptions) |
| D.4 | `troubleshooting` table uses the parameter key as `id` — adding new parameters requires new seed rows, not UI-driven creation |
| D.5 | `dummy_data_seeds.dart` inserts test data on every DB upgrade — should be dev-only |
| D.6 | No unit tests for calculation utilities (`calculation_utils.dart`) despite constitution §III requiring test-first |

### Design System Gaps

| # | Issue |
|---|-------|
| S.1 | Constitution §X specifies primary brand color `#F65C00` (Zoetis orange); current `AppColors.primary` is `#1769D8` (blue) — brand color not applied |
| S.2 | Constitution §X specifies gradient header `#F65C00 → #ff8c42`; current gradient is `primaryLight → primaryDark` (blue tones) |
| S.3 | Post-save green tab + read-only pattern not consistently applied across all 5 audit screens |
| S.4 | `°C / °F` toggle missing from several audit screens |

---

## Appendix A — Key Constants

### Thresholds (`lib/core/constants/app_thresholds.dart`)

| Threshold | Value |
|-----------|-------|
| Pasgar alert (parameter %) | > 20% |
| Uniformity poor | < 80% |
| Uniformity good | 80–85% |
| Uniformity excellent | > 85% |
| CV% alert | > 8% |
| YFBM optimum | 8–10% |
| CVT optimum | 103–105°F |
| EST optimum | 100–101°F |
| Shell temp optimum | 19–21°C |
| Egg breakout high severity | > BMK + 3% |
| Culled chick benchmark | ≤ 1% |
| Dead chick benchmark | ≤ 0.2% |

### Colors (`lib/core/constants/app_colors.dart`)

| Key | Hex |
|-----|-----|
| primary | #1769D8 |
| primaryLight | #079FE0 |
| primaryDark | #193FC2 |
| background | #F5F8FC |
| cardBackground | #FFFFFF |
| completedBg | #E8F5E9 |
| completedText | #388E3C |

*(Note: constitution specifies #F65C00 orange — see Gap S.1)*

---

## Appendix B — File Tree

```
lib/
├── app.dart                          ← Root widget, routing, Govee overlay
├── main.dart                         ← Entry point, DB init, token migration
├── core/
│   ├── constants/
│   │   ├── app_colors.dart
│   │   ├── app_sizes.dart
│   │   ├── app_strings.dart
│   │   ├── app_thresholds.dart
│   │   └── supabase_config.dart      ← gitignored
│   ├── navigation/
│   │   └── shell_navigation_scope.dart
│   ├── theme/
│   │   ├── app_text_styles.dart
│   │   ├── app_theme.dart
│   │   └── gradient_app_bar.dart
│   └── utils/
│       ├── calculation_utils.dart
│       ├── date_utils.dart
│       ├── field_validators.dart
│       ├── scorecard_formatter.dart
│       └── temp_converter.dart
├── data/
│   ├── database/
│   │   ├── database_helper.dart      ← Schema + migrations v1–v15
│   │   └── seeds/
│   │       ├── bmk_seeds.dart
│   │       ├── dummy_data_seeds.dart
│   │       └── troubleshooting_seeds.dart
│   ├── models/
│   │   ├── activity_log_model.dart
│   │   ├── audit_model.dart          ← 200+ fields
│   │   ├── audit_session_model.dart
│   │   ├── bmk_breed_model.dart
│   │   ├── bmk_egg_breakout_model.dart
│   │   ├── customer_model.dart
│   │   ├── flock_model.dart
│   │   ├── hatchery_model.dart
│   │   ├── photo_model.dart
│   │   ├── temperature_rh_model.dart ← TemperatureSessionModel, TemperatureReadingModel, ChartPoint
│   │   ├── tray_model.dart           ← HatchResultsTray, EggBreakoutTray
│   │   ├── troubleshooting_model.dart
│   │   ├── user_model.dart
│   │   └── yfbm_entry_model.dart
│   └── repositories/
│       ├── activity_log_repository.dart
│       ├── audit_repository.dart     ← ⚠ SQL injection in _buildWhere (Phase 0 task)
│       ├── audit_session_repository.dart
│       ├── bmk_repository.dart
│       ├── customer_repository.dart
│       ├── flock_repository.dart
│       ├── hatchery_repository.dart
│       ├── photo_repository.dart
│       ├── temperature_rh_repository.dart
│       ├── troubleshooting_repository.dart
│       └── user_repository.dart
├── features/
│   ├── audits/
│   │   ├── models/audit_filter.dart
│   │   ├── providers/
│   │   │   ├── audit_provider.dart
│   │   │   └── audit_session_provider.dart
│   │   ├── screens/
│   │   │   ├── audit_context_screen.dart
│   │   │   ├── audit_session_screen.dart
│   │   │   ├── audit_type_selection_screen.dart
│   │   │   ├── audits_screen.dart
│   │   │   ├── chick_quality_screen.dart
│   │   │   ├── egg_storage_screen.dart
│   │   │   ├── hatch_analysis_screen.dart
│   │   │   ├── hatcher_optimizing_screen.dart
│   │   │   └── setter_optimizing_screen.dart
│   │   └── widgets/
│   │       ├── audit_filter_sheet.dart
│   │       ├── audit_save_action.dart
│   │       ├── est_grid_widget.dart
│   │       ├── govee_sector.dart
│   │       ├── photo_button.dart
│   │       ├── tabs/
│   │       │   ├── cha_env_tab.dart
│   │       │   ├── cvt_tab.dart
│   │       │   ├── pasgar_tab.dart
│   │       │   ├── pm_necropsy_tab.dart
│   │       │   ├── weights_tab.dart
│   │       │   └── yfbm_tab.dart
│   │       ├── troubleshooting_sheet.dart
│   │       ├── unsaved_changes_guard.dart
│   │       └── weight_grid_widget.dart
│   ├── auth/
│   │   ├── providers/auth_provider.dart
│   │   ├── screens/ (login, register, pending_approval)
│   │   └── widgets/password_strength_indicator.dart
│   ├── bmk/
│   │   ├── providers/bmk_provider.dart
│   │   └── screens/bmk_screen.dart
│   ├── customers/
│   │   ├── screens/ (customers, customer_detail, audit_detail, visit_detail)
│   │   └── widgets/ (add_customer/flock/hatchery sheets, cards, management sheets)
│   ├── dashboard/
│   │   ├── models/ (chick_quality, dashboard_filter, egg_breakout, egg_storage, hatch_analysis, visit_session_summary)
│   │   ├── providers/dashboard_provider.dart
│   │   ├── screens/ (dashboard, photo_fullscreen)
│   │   └── widgets/ (bmk_bar/line/donut charts, sections/)
│   ├── home/
│   │   ├── providers/home_provider.dart
│   │   ├── screens/home_screen.dart
│   │   └── widgets/main_shell.dart
│   ├── settings/
│   │   ├── providers/settings_provider.dart
│   │   └── screens/ (settings, activity_log)
│   ├── sync/screens/startup_sync_screen.dart
│   └── temperature/
│       ├── providers/temperature_rh_provider.dart
│       ├── screens/temperature_rh_screen.dart
│       └── widgets/ (temperature_rh_launcher, temperature_rh_panel)
├── providers/
│   ├── app_provider.dart
│   └── customers_provider.dart
├── services/
│   ├── auth/secure_token_store.dart
│   ├── backup/backup_service.dart
│   ├── diagnostics/diagnostic_engine.dart
│   ├── export/ (csv_export_service, pdf_export_service)
│   ├── govee/govee_service.dart
│   ├── notifications/notification_service.dart
│   ├── ocr/ocr_service.dart           ← stub, not implemented
│   ├── photo/ (photo_service, photo_sync_service)
│   └── supabase/ (supabase_service, startup_sync_service)
└── widgets/
    ├── chart_toggle.dart
    ├── chick_mark_logo.dart
    ├── photo_grid.dart
    ├── section_card.dart
    ├── status_badge.dart
    ├── temp_toggle.dart
    └── troubleshooting_icon.dart
```
