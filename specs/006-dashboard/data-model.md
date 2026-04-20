# Data Model: Phase 5 — Dashboard

**Branch**: `006-dashboard` | **Date**: 2026-04-18

> The Dashboard is **read-only**. No new tables or schema migrations are required.
> All data comes from the existing `audits`, `photos`, `bmk_breeds`, and `bmk_egg_breakout` tables.

---

## Source Tables (existing)

### `audits` — columns used by dashboard queries

| Column | Type | Used by Section |
|--------|------|-----------------|
| `id` | TEXT (PK) | All |
| `customerId` | TEXT | Cascade filter |
| `flockId` | TEXT | Cascade filter |
| `auditType` | TEXT | Section routing |
| `date` | TEXT (ISO) | Trend charts |
| `hatchNumber` | INTEGER | Hatch index |
| `haHatchability` | REAL | Section 1 |
| `haFertility` | REAL | Section 1 |
| `haHof` | REAL | Section 1 |
| `haCulled` | REAL | Section 1 |
| `haDead` | REAL | Section 1 |
| `ebBreakoutType` | TEXT | Section 2 filter |
| `ebInfertilePct` | REAL | Section 2 |
| `ebEarly24hPct` | REAL | Section 2 |
| `ebEarly48hPct` | REAL | Section 2 |
| `ebBloodRingPct` | REAL | Section 2 |
| `ebBlackEyePct` | REAL | Section 2 |
| `ebMidDeadPct` | REAL | Section 2 |
| `ebLateDeadPct` | REAL | Section 2 |
| `ebPippedInternalPct` | REAL | Section 2 |
| `ebPippedExternalPct` | REAL | Section 2 |
| `ebExplodedPct` | REAL | Section 2 |
| `ebMushyPct` | REAL | Section 2 |
| `ebContamPct` | REAL | Section 2 |
| `ebCullPct` | REAL | Section 2 |
| `ebSeeperPct` | REAL | Section 2 |
| `chickAvgWeight` | REAL | Section 3A |
| `chickUniformityPct` | REAL | Section 3A |
| `chickCvPct` | REAL | Section 3A |
| `pasgarFinalScore` | REAL | Section 3B |
| `pasgarReflexes` | REAL | Section 3B |
| `pasgarBeak` | REAL | Section 3B |
| `pasgarNavel` | REAL | Section 3B |
| `pasgarBelly` | REAL | Section 3B |
| `pasgarLeg` | REAL | Section 3B |
| `pasgarFeatherDev` | REAL | Section 3B |
| `cvtAvg` | REAL | Section 3C |
| `cvtCvPct` | REAL | Section 3C |
| `yfbmAvgPct` | REAL | Section 3D |
| `yfbmCvPct` | REAL | Section 3D |
| `chaCo2` | REAL | Section 3E |
| `chaPm10` | REAL | Section 3E |
| `chaPm25` | REAL | Section 3E |
| `chaAirVelocity` | REAL | Section 3E |
| `chaNoiseLevel` | REAL | Section 3E |
| `esShellTemp` | REAL | Section 4B |
| `eggUniformityPct` | REAL | Section 4A |
| `eggCvPct` | REAL | Section 4A |
| `eggAvgWeight` | REAL | Section 4A |
| `esUvAffectedPct` | REAL | Section 4C |
| `soSetterId` | TEXT | Section 5 |
| `soHatchability` | REAL | Section 5A |
| `soFertility` | REAL | Section 5A |
| `soHof` | REAL | Section 5A |
| `soCulled` | REAL | Section 5A |
| `soDead` | REAL | Section 5A |
| `soEstAvg` | REAL | Section 5C |
| `soEstCvPct` | REAL | Section 5C |
| `soCo2` | REAL | Section 5D |
| `hoHatcherId` | TEXT | Section 6 |
| `hoHatchability` | REAL | Section 6A |
| `hoFertility` | REAL | Section 6A |
| `hoHof` | REAL | Section 6A |
| `hoCulled` | REAL | Section 6A |
| `hoDead` | REAL | Section 6A |
| `hoCvtAvg` | REAL | Section 6C |
| `hoCvtCvPct` | REAL | Section 6C |
| `hoCo2` | REAL | Section 6D |
| `hoChickPantingPct` | REAL | Section 6E |
| `bmkAge` | INTEGER | Cascade filter + BMK lookup |

### `photos`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT (PK) | |
| `auditId` | TEXT (FK → audits.id) | Links photo to audit row |
| `filePath` | TEXT | Absolute local path |
| `description` | TEXT | Section tag (e.g., "egg_breakout", "cvt", "yfbm") |
| `createdAt` | TEXT | |

### `bmk_breeds`

| Column | Type | Notes |
|--------|------|-------|
| `breed` | TEXT | Used to look up BMK for selected flock's breed |
| `ageWeek` | INTEGER | Matched to `bmkAge` |
| `hatchabilityPct` | REAL | Section 1 BMK |
| `fertilityPct` | REAL | Section 1 BMK |
| `hofPct` | REAL | Section 1 BMK |
| `eggWeightG` | REAL | Section 4A BMK |
| `chickWeightG` | REAL | Section 3A BMK |

### `bmk_egg_breakout`

| Column | Type | Notes |
|--------|------|-------|
| `ageWeek` | INTEGER | Matched to `bmkAge` |
| `infertilePct` | REAL | Section 2 BMK |
| `early24hPct` | REAL | Section 2 BMK |
| `early48hPct` | REAL | Section 2 BMK |
| `bloodRingPct` | REAL | Section 2 BMK |
| `blackEyePct` | REAL | Section 2 BMK |
| `midDeadPct` | REAL | Section 2 BMK — late dead (Section 6B) |
| `lateDeadPct` | REAL | Section 6B |
| `pippedExternalPct` | REAL | Section 6B |
| `explodedPct` | REAL | Section 6B |
| `mushyPct` | REAL | Section 6B |
| `contamPct` | REAL | Section 6B |
| `cullPct` | REAL | Section 6B |

---

## Dart Result Models (new, in `lib/features/dashboard/models/`)

These are lightweight, immutable value types used to carry aggregated query results from `AuditRepository` to `DashboardProvider`.

### `DashboardFilter`
```dart
class DashboardFilter {
  final String? customerId;
  final String? flockId;
  final int? bmkAge;       // null = All ages
}
```

### `HatchAnalysisAvg`
```dart
class HatchAnalysisAvg {
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double culledPct;
  final double deadPct;
}
```

### `HatchAnalysisTrend`
```dart
class HatchAnalysisTrend {
  final String date;
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double culledPct;
  final double deadPct;
}
```

### `EggBreakoutAvg`
```dart
class EggBreakoutAvg {
  final String breakoutType;   // 'fresh' | 'candled' | 'residue'
  final double infertilePct;
  final double early24hPct;
  final double early48hPct;
  final double bloodRingPct;
  final double blackEyePct;
  final double midDeadPct;
  final double lateDeadPct;
  final double pippedExternalPct;
  final double explodedPct;
  final double mushyPct;
  final double contamPct;
  final double cullPct;
  final double seeperPct;
}
```

### `ChickWeightTrend`
```dart
class ChickWeightTrend {
  final String date;
  final double avgWeightG;
  final double uniformityPct;
  final double cvPct;
}
```

### `PasgarAvg`
```dart
class PasgarAvg {
  final double score;          // out of 10
  final double reflexesPct;
  final double beakPct;
  final double navelPct;
  final double bellyPct;
  final double legPct;
  final double featherDevPct;
}
```

### `CvtAvg`
```dart
class CvtAvg {
  final double avgTempF;
  final double cvPct;
}
```

### `YfbmTrend`
```dart
class YfbmTrend {
  final String date;
  final double avgPct;
  final double cvPct;
}
```

### `ChaEnvironmentalTrend`
```dart
class ChaEnvironmentalTrend {
  final String date;
  final double co2;
  final double pm10;
  final double pm25;
  final double airVelocity;
  final double noiseLevel;
}
```

### `EggStorageTrend`
```dart
class EggStorageTrend {
  final String date;
  final double avgWeightG;
  final double uniformityPct;
  final double cvPct;
  final double shellTempC;     // converted on display
  final double uvAffectedPct;
}
```

### `SetterComparison`
```dart
class SetterComparison {
  final String setterId;
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double culledPct;
  final double deadPct;
  final double infertilePct;
  final double early24hPct;
  final double early48hPct;
  final double bloodRingPct;
  final double estAvgF;
  final double estCvPct;
  final List<MapEntry<String, double>> co2Trend; // date → value
}
```

### `HatcherComparison`
```dart
class HatcherComparison {
  final String hatcherId;
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double culledPct;
  final double deadPct;
  final double lateDeadPct;
  final double externalPipPct;
  final double exposedBrainPct;
  final double crossedBeakPct;
  final double contamPct;
  final double crackedPct;
  final double cvtAvgF;
  final double cvtCvPct;
  final List<MapEntry<String, double>> co2Trend;
  final List<MapEntry<String, double>> pantingTrend; // date → % Yes
}
```

### `BmkReference`
```dart
class BmkReference {
  // From bmk_breeds
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double eggWeightG;
  final double chickWeightG;
  // From bmk_egg_breakout
  final double infertilePct;
  final double early24hPct;
  final double early48hPct;
  final double bloodRingPct;
  final double blackEyePct;
  final double midDeadPct;
  final double lateDeadPct;
  final double pippedExternalPct;
  final double explodedPct;
  final double mushyPct;
  final double contamPct;
  final double cullPct;
}
```

---

## Key Queries (pseudocode)

### Filter: Distinct BMK ages for a flock
```sql
SELECT DISTINCT bmkAge FROM audits
WHERE customerId = ? AND flockId = ?
ORDER BY bmkAge ASC
```

### Section 1: Hatch Analysis AVG
```sql
SELECT AVG(haHatchability), AVG(haFertility), AVG(haHof), AVG(haCulled), AVG(haDead)
FROM audits
WHERE customerId = ? AND flockId = ? AND auditType = 'hatch_analysis'
  AND (bmkAge = ? OR ? IS NULL)
```

### Section 1: Hatch Analysis trend (by date)
```sql
SELECT date, AVG(haHatchability), AVG(haFertility), AVG(haHof), AVG(haCulled), AVG(haDead)
FROM audits
WHERE customerId = ? AND flockId = ? AND auditType = 'hatch_analysis'
  AND (bmkAge = ? OR ? IS NULL)
GROUP BY date ORDER BY date ASC
```

### Section 5: Available setter IDs
```sql
SELECT DISTINCT soSetterId FROM audits
WHERE customerId = ? AND auditType = 'setter_optimizing'
ORDER BY soSetterId ASC
```

### Section 5: Per-setter comparison
```sql
SELECT soSetterId,
       AVG(soHatchability), AVG(soFertility), AVG(soHof), AVG(soCulled), AVG(soDead),
       AVG(soEstAvg), AVG(soEstCvPct)
FROM audits
WHERE customerId = ? AND flockId = ? AND auditType = 'setter_optimizing'
  AND (bmkAge = ? OR ? IS NULL)
  AND soSetterId IN (?, ?, ...)
GROUP BY soSetterId
```

### Photos for a section
```sql
SELECT filePath FROM photos
WHERE auditId IN (
  SELECT id FROM audits WHERE customerId = ? AND flockId = ?
    AND auditType = ? AND (bmkAge = ? OR ? IS NULL)
)
AND description = ?
ORDER BY createdAt DESC
```
