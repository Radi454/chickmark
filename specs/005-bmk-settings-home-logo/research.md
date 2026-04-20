# Research: Phase 4 — BMK Screen + Settings + Home Screen + Logo

**Branch**: `005-bmk-settings-home-logo` | **Date**: 2026-04-18

---

## 1. BMK Database Schema Gap

**Decision**: The current `bmk_breeds` and `bmk_egg_breakout` tables both have a single generic `value REAL` column. A DB migration to version 3 is required to add the named metric columns the BMK screen needs.

**Rationale**: The spec requires displaying 6 distinct metrics per breed+age row (Hatchability%, Fertility%, HOF%, Production%, Egg Weight, Chick Weight) and up to 15 named parameters per age in egg breakout. A single `value` column cannot represent this without EAV rows and complex joins. Named columns are simpler, align with the existing audit table design philosophy, and are easier to query and display.

**Alternatives considered**:
- EAV (Entity-Attribute-Value) with a `metricName TEXT` column added — rejected because it requires multiple DB rows per logical record, grouping queries, and more complex model code.
- JSON blob in a single `metrics TEXT` column — rejected because it defeats SQLite's typed query advantage and is harder to inspect/debug.

**Outcome**: DB schema v3 adds multi-column structure to both bmk tables (see data-model.md for exact DDL).

---

## 2. Egg Breakout Benchmark Parameter Names (15 for Residue type)

**Decision**: The 15 egg breakout parameters stored in `bmk_egg_breakout` will be:

| # | Column Name | Display Label | Visible in |
|---|------------|---------------|------------|
| 1 | infertilePct | Infertile | Fresh, Candled, Residue |
| 2 | early24hPct | Early 24h | Fresh, Candled, Residue |
| 3 | early48hPct | Early 48h | Fresh, Candled, Residue |
| 4 | bloodRingPct | Blood Ring | Fresh, Candled, Residue |
| 5 | blackEyePct | Black Eye | Candled, Residue |
| 6 | midDeadPct | Mid Dead (5-10d) | Residue |
| 7 | lateDeadPct | Late Dead (11-17d) | Residue |
| 8 | pinnedInternalPct | Pipped Internal | Residue |
| 9 | pippedExternalPct | Pipped External | Residue |
| 10 | explodedPct | Exploded | Residue |
| 11 | mushyPct | Mushy/Rotten | Residue |
| 12 | contamPct | Contaminated | Residue |
| 13 | cullPct | Cull/Deformed | Residue |
| 14 | seeperPct | Seeper | Residue |
| 15 | otherPct | Other | Residue |

**Rationale**: These are the standard Aviagen/Ross industry residue analysis parameters used in poultry hatchery practice. They match the aggregate parameter groups already tracked in the egg breakout audit tab (`ebTrays` JSON).

**Note for implementer**: Confirm these 15 parameter names with the domain expert before seeding production data. Column names can be added without breaking changes via ALTER TABLE.

---

## 3. ChickMark Logo — Custom Painter vs flutter_svg

**Decision**: Replace `_buildFallbackLogo()` in `lib/widgets/chick_mark_logo.dart` with a `CustomPainter` implementation that draws the chick-on-egg design using Canvas API.

**Rationale**: The project does not use `flutter_svg`; adding a new package for a single asset violates the Simplicity Over Abstraction principle. A `CustomPainter` requires no new dependencies, scales perfectly to any size, and fits naturally into the existing `ChickMarkLogo` widget's `_buildLogo(double size)` pattern.

**Alternatives considered**:
- `flutter_svg` package with SVG asset file — rejected (new dependency, extra package download, setup overhead).
- PNG raster asset at multiple resolutions — rejected (does not scale cleanly, requires maintaining multiple asset files).

**Outcome**: A `ChickMarkPainter extends CustomPainter` class added to `chick_mark_logo.dart`, drawing all logo elements proportionally from a single `size` parameter.

---

## 4. Settings Preferences — Extend AppProvider vs New SettingsProvider

**Decision**: Create a new `SettingsProvider` in `lib/features/settings/providers/settings_provider.dart`. Do not modify `AppProvider`.

**Rationale**: `AppProvider` currently manages global runtime state (current user + temp unit). Adding 4 additional preference fields would turn it into a catch-all god-object. A dedicated `SettingsProvider` keeps concerns separated and is consistent with the feature-based folder structure already used for `AuditProvider`, `AuthProvider`.

**Alternatives considered**:
- Adding all fields to `AppProvider` — rejected (grows the global provider; harder to test in isolation).
- `InheritedWidget` without Provider — rejected (inconsistent with established pattern).

**SharedPreferences keys** (avoid collision with existing key `'temp_unit'`):

| Preference | Key | Default |
|------------|-----|---------|
| Default Pasgar Sample Size | `pref_pasgar_sample_size` | 40 |
| Default Weights Sample Size | `pref_weights_sample_size` | 100 |
| Default Tray Size | `pref_tray_size` | 150 |
| Default Storage Days | `pref_storage_days` | 0 |

Temperature unit remains in `AppProvider` under key `'temp_unit'` — the Settings screen reads/writes it through `AppProvider`.

---

## 5. Home Screen Stats — Audit Counts

**Decision**: Derive stats (Customers count, Active Audits count, Total Audits count) from existing `CustomersProvider` data.

**Rationale**: `CustomersProvider` already loads all customers (`_allCustomers`) and audits (`_audits`). Stats can be computed as:
- Customers count = `_allCustomers.length`
- Total Audits = `_audits.length`
- Active Audits = `_audits.where((a) => a.status == 'active').length`

No new DB queries needed. The home screen will `Consumer<CustomersProvider>` to access these values.

**Alternatives considered**:
- Separate `HomeProvider` with its own DB queries — rejected (duplicates data already in memory).

---

## 6. Audit List for Home Screen

**Decision**: Home screen uses the `_audits` list from `CustomersProvider`, filtered by selected chip type, sorted by `createdAt` descending, capped at 20 items.

**Rationale**: `AuditModel` contains all fields needed for the audit card: `auditType`, `customerId`, `flockId`, `date`, `setterId`, `hatcherId`, `status`. Customer name must be looked up via `customerId` → `_allCustomers`. Flock breed can be looked up via `flockId` → `_flocks`. Age badge is derived from flock `entryDate` using `HatchDateUtils`.

**Note**: `CustomersProvider` may need a `loadAllAudits()` path that loads audits independent of selected customer. Verify current implementation loads across all customers or add that capability.

---

## 7. Sign-Out Flow

**Decision**: Sign-out calls `AuthProvider.logout()` → clears SQLite `users` token fields → calls `SupabaseService.signOut()` → navigates to `/login` using `Navigator.of(context).pushNamedAndRemoveUntil`.

**Rationale**: `AuthProvider.logout()` already exists and handles this flow. The Settings screen only needs to call it after confirmation dialog approval.

---

## 8. Supabase Connection Status for Settings Sync Section

**Decision**: Use `connectivity_plus` (already in `pubspec.yaml`) to show online/offline status. The "last synced" timestamp will be stored in SharedPreferences under key `'last_sync_timestamp'`.

**Rationale**: `connectivity_plus` is already installed. A simple `ConnectivityResult` check is sufficient for the UI indicator. Actual Supabase reachability (vs just network) is a nice-to-have and not required for v1.

---

## 9. New Audit Flow from Home Screen

**Decision**: `[+ New Audit]` button navigates to `AuditTypeSelectionScreen` (existing). `[+ New Customer]` button opens the existing `AddCustomerSheet` as a modal bottom sheet, reusing the widget from `lib/features/customers/widgets/add_customer_sheet.dart`.

**Rationale**: Both flows are already implemented — the home screen simply needs to trigger them. No new navigation routes required.
