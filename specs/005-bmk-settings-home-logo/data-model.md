# Data Model: Phase 4 — BMK Screen + Settings + Home Screen + Logo

**Branch**: `005-bmk-settings-home-logo` | **Date**: 2026-04-18

---

## 1. Database Migration (v2 → v3)

### 1a. `bmk_breeds` — Redesigned

The existing single-`value` schema is replaced by named metric columns.

**Migration approach**: DROP and recreate table (acceptable in pre-production per constitution). Re-seed with proper data.

```sql
-- v3 migration
DROP TABLE IF EXISTS bmk_breeds;
CREATE TABLE bmk_breeds (
  id TEXT PRIMARY KEY,
  breed TEXT NOT NULL,
  ageWeek INTEGER NOT NULL,
  hatchabilityPct REAL,
  fertilityPct REAL,
  hofPct REAL,
  productionPct REAL,
  eggWeightG REAL,
  chickWeightG REAL
);
```

**Dart model** (`lib/data/models/bmk_breed_model.dart` — replace):
```dart
class BmkBreedModel {
  final String id;
  final String breed;
  final int ageWeek;
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double productionPct;
  final double eggWeightG;
  final double chickWeightG;
}
```

---

### 1b. `bmk_egg_breakout` — Redesigned

All 15 egg breakout parameter columns added.

```sql
-- v3 migration
DROP TABLE IF EXISTS bmk_egg_breakout;
CREATE TABLE bmk_egg_breakout (
  id TEXT PRIMARY KEY,
  ageWeek INTEGER NOT NULL UNIQUE,
  infertilePct REAL,
  early24hPct REAL,
  early48hPct REAL,
  bloodRingPct REAL,
  blackEyePct REAL,
  midDeadPct REAL,
  lateDeadPct REAL,
  pippedInternalPct REAL,
  pippedExternalPct REAL,
  explodedPct REAL,
  mushyPct REAL,
  contamPct REAL,
  cullPct REAL,
  seeperPct REAL,
  otherPct REAL
);
```

**Dart model** (`lib/data/models/bmk_egg_breakout_model.dart` — replace):
```dart
class BmkEggBreakoutModel {
  final String id;
  final int ageWeek;
  final double infertilePct;
  final double early24hPct;
  final double early48hPct;
  final double bloodRingPct;
  final double blackEyePct;
  final double midDeadPct;
  final double lateDeadPct;
  final double pippedInternalPct;
  final double pippedExternalPct;
  final double explodedPct;
  final double mushyPct;
  final double contamPct;
  final double cullPct;
  final double seeperPct;
  final double otherPct;
}
```

---

## 2. Seed Data

### `bmk_seeds.dart` — Replace with real values

`kBmkBreedSeeds`: One row per (breed × age) combination. 6 breeds × available age range.
`kBmkEggBreakoutSeeds`: One row per age week (25–65).

> **Note**: Real benchmark percentages must be provided by the domain expert. Seed file should have real industry values before production. Placeholder zeros are acceptable for development.

---

## 3. UserPreferences (SharedPreferences-backed)

Not a DB entity — stored via `SharedPreferences`. Managed by `SettingsProvider`.

| Preference | SP Key | Type | Default |
|------------|--------|------|---------|
| Temperature unit | `temp_unit` | int (index) | 0 (°F) |
| Pasgar sample size | `pref_pasgar_sample_size` | int | 40 |
| Weights sample size | `pref_weights_sample_size` | int | 100 |
| Tray size | `pref_tray_size` | int | 150 |
| Storage days | `pref_storage_days` | int | 0 |
| Last sync timestamp | `last_sync_timestamp` | String (ISO8601) | null |

Temperature unit is owned by `AppProvider` (key `temp_unit`). All other keys are owned by `SettingsProvider`. No key collision.

---

## 4. AuditSummary (derived, no new table)

For the home screen audit list, data is derived from existing `AuditModel` + lookups into `_allCustomers` and `_flocks` in `CustomersProvider`.

| Field | Source |
|-------|--------|
| auditType | AuditModel.auditType |
| customerName | customers.firstWhere(id == audit.customerId).name |
| flockId | AuditModel.flockId |
| breed | flocks.firstWhere(id == audit.flockId).breed |
| ageWeeks | HatchDateUtils.ageInWeeks(flock.entryDate, audit.date) |
| date | AuditModel.date |
| setterId | AuditModel.setterId |
| hatcherId | AuditModel.hatcherId |
| status | AuditModel.status |

No new model class required — computed inline in HomeScreen widget.

---

## 5. Egg Breakout Type Visibility Map

| Parameter | Fresh | Candled | Residue |
|-----------|-------|---------|---------|
| Infertile | ✅ | ✅ | ✅ |
| Early 24h | ✅ | ✅ | ✅ |
| Early 48h | ✅ | ✅ | ✅ |
| Blood Ring | ✅ | ✅ | ✅ |
| Black Eye | ❌ | ✅ | ✅ |
| Mid Dead | ❌ | ❌ | ✅ |
| Late Dead | ❌ | ❌ | ✅ |
| Pipped Internal | ❌ | ❌ | ✅ |
| Pipped External | ❌ | ❌ | ✅ |
| Exploded | ❌ | ❌ | ✅ |
| Mushy/Rotten | ❌ | ❌ | ✅ |
| Contaminated | ❌ | ❌ | ✅ |
| Cull/Deformed | ❌ | ❌ | ✅ |
| Seeper | ❌ | ❌ | ✅ |
| Other | ❌ | ❌ | ✅ |

---

## 6. BMK Breed Selector Values

Breed chip values map to `breed` column in `bmk_breeds`:

| Display | DB Value |
|---------|----------|
| Ross 308 | `Ross308` |
| Arbo | `Arbo` |
| Avian | `Avian` |
| Cobb 500 | `Cobb500` |
| Hubbard | `Hubbard` |
| IR | `IR` |

---

## 7. Provider Overview

### New: `BmkProvider` (`lib/features/bmk/providers/bmk_provider.dart`)
- State: `selectedBreed`, `selectedBreedAge`, `selectedEbType`, `selectedEbAge`
- Data: `List<BmkBreedModel> _breedRows`, `List<BmkEggBreakoutModel> _ebRows`
- Methods: `loadBreedBenchmarks(breed)`, `loadEggBreakoutBenchmarks()`, `setBreed()`, `setBreedAge()`, `setEbType()`, `setEbAge()`
- Source: SQLite queries to `bmk_breeds` and `bmk_egg_breakout`

### New: `SettingsProvider` (`lib/features/settings/providers/settings_provider.dart`)
- State: `pasgarSampleSize`, `weightsSampleSize`, `traySize`, `storageDays`, `lastSyncTimestamp`
- Methods: `load()`, `setPasgarSampleSize()`, `setWeightsSampleSize()`, `setTraySize()`, `setStorageDays()`, `updateLastSync()`
- Source: SharedPreferences

### Updated: `AppProvider` — no structural change, Settings screen reads `tempUnit` via `Provider.of<AppProvider>`

### Updated: `CustomersProvider` — ensure `_audits` is loaded across all customers (not just selected), expose `allAudits` getter
