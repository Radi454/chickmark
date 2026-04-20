# Data Model: Phase 1 — Foundation, Architecture & Design System

**Date**: 2026-04-18
**Branch**: `002-foundation-architecture-design`

---

## Dart Model Classes

All models live in `lib/data/models/`. They are plain Dart classes with
`fromMap` / `toMap` methods for SQLite serialisation. No ORM annotations.

---

### UserModel (`user_model.dart`)

```dart
class UserModel {
  final String id;           // UUID
  final String fullName;
  final String email;
  final String role;         // 'admin' | 'auditor' | 'customer'
  final String status;       // 'pending' | 'approved' | 'suspended'
  final String? customerId;  // FK → customers (customer role only)
  final String? accessToken; // Cached Supabase JWT
  final DateTime? tokenExpiry;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
}
```

**Validation rules**:
- `email` must be unique across the table
- `role` must be one of three enum values
- `status` defaults to `'pending'` on insert
- `accessToken` + `tokenExpiry` set only after successful Supabase login
- Token considered valid if `tokenExpiry` is non-null and within 30 days of now

**State transitions**:
```
pending → approved (Admin action)
pending → suspended (Admin action)
approved → suspended (Admin action)
```

---

### CustomerModel (`customer_model.dart`)

```dart
class CustomerModel {
  final String id;          // UUID
  final String name;        // Required
  final String? location;
  final String? phone;
  final String? email;
  final DateTime createdAt;
  final String createdBy;   // FK → users.id
}
```

---

### FlockModel (`flock_model.dart`)

```dart
class FlockModel {
  final String id;          // UUID
  final String customerId;  // FK → customers.id
  final String flockId;     // Human-readable text identifier
  final String breed;       // 'Ross308'|'Arbo'|'Avian'|'Cobb500'|'Hubbard'|'IR'
  final DateTime entryDate; // Used to compute age; never stored as age

  // Computed property — never persisted
  double get currentAgeWeeks =>
      DateTime.now().difference(entryDate).inDays / 7.0;
}
```

**Constraint**: `currentAgeWeeks` is a getter, not a column. It MUST NOT be written
to SQLite.

---

### AuditModel (`audit_model.dart`)

The audit model mirrors the full denormalized `audits` table. Only common fields
are typed; audit-type-specific fields use nullable primitives.

```dart
class AuditModel {
  // --- Common ---
  final String id;
  final String auditType;    // 'chick_quality'|'hatch_analysis'|
                             // 'setter_optimizing'|'hatcher_optimizing'|'egg_storage'
  final String customerId;
  final String? flockId;
  final String? setterId;
  final String? hatcherId;
  final DateTime date;
  final String status;       // 'active' | 'completed'
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? notes;

  // --- Chick Quality: CHA Environmental ---
  final bool? chaGoveeConnected;
  final double? chaCo2;
  final String? chaCo2Photo;
  final double? chaPm10;
  final String? chaPm10Photo;
  final double? chaPm25;
  final String? chaPm25Photo;
  final double? chaAirVelocitySpot1;
  final String? chaAirVelocitySpot1Photo;
  final double? chaAirVelocitySpot2;
  final String? chaAirVelocitySpot2Photo;
  final double? chaAirVelocitySpot3;
  final String? chaAirVelocitySpot3Photo;
  final double? chaAirInlet;
  final String? chaAirInletPhoto;
  final double? chaAirOutlet;
  final String? chaAirOutletPhoto;
  final double? chaNoiseLevel;
  final String? chaNoiseLevelPhoto;

  // --- Chick Quality: Pasgar ---
  final int? pasgarSampleSize;         // default 40
  final int? pasgarReflexes;
  final String? pasgarReflexesPhoto;
  final int? pasgarBeak;
  final String? pasgarBeakPhoto;
  final int? pasgarNavel;
  final String? pasgarNavelPhoto;
  final int? pasgarBelly;
  final String? pasgarBellyPhoto;
  final int? pasgarLeg;
  final String? pasgarLegPhoto;
  final int? pasgarFeatherDev;
  final String? pasgarFeatherDevPhoto;
  final double? pasgarFinalScore;      // computed, stored

  // --- Chick Quality: Weights ---
  final int? chickStorageDays;         // default 0
  final int? chickSampleSize;          // default 100
  final String? chickWeights;          // JSON array
  final double? chickAvgWeight;        // computed
  final double? chickUniformityPct;    // computed
  final double? chickCvPct;            // computed
  final int? chickBmkAge;              // computed
  final double? chickBmkWeight;        // from bmk_breeds

  // --- Chick Quality: YFBM ---
  final String? yfbmPhoto;
  final String? yfbmEntries;           // JSON [{chick_weight, yolk_weight}]
  final double? yfbmAvgPct;            // computed
  final double? yfbmCvPct;             // computed

  // --- Chick Quality: CVT ---
  final int? cvtSampleSize;
  final String? cvtTopBasket;
  final double? cvtTopTemp;            // °F
  final String? cvtTopPhoto;
  final String? cvtMiddleBasket;
  final double? cvtMiddleTemp;         // °F
  final String? cvtMiddlePhoto;
  final String? cvtBottomBasket;
  final double? cvtBottomTemp;         // °F
  final String? cvtBottomPhoto;
  final double? cvtAvg;                // computed, °F
  final double? cvtCvPct;             // computed

  // --- Hatch Analysis: Hatch Results ---
  final int? haStorageDays;            // default 0
  final int? haTotalEggsSet;
  final int? haHatched;
  final int? haCulled;
  final int? haDead;
  final double? haHatchability;        // computed
  final double? haFertility;           // computed
  final double? haHof;                 // computed
  final String? haTrays;               // JSON array
  final int? haBmkAge;                 // computed

  // --- Hatch Analysis: Egg Breakout ---
  final int? ebTraySize;               // default 150
  final String? ebBreakoutType;        // 'fresh'|'candled'|'residue'
  final int? ebBreakoutAgeDays;        // auto-set; editable
  final int? ebStorageDays;            // default 0
  final String? ebTrays;               // JSON array
  final int? ebBmkAge;                 // computed

  // --- Setter Optimizing ---
  final String? soBreed;
  final String? soSetterId;
  final int? soIncubationAge;          // 1–18
  final bool? soGoveeConnected;
  final double? soGoveeTemp;           // °F
  final double? soGoveeHumidity;
  final double? soCo2;
  final String? soCo2Photo;
  final String? soEstReadings;         // JSON 3x3, °F
  final String? soEstPhotos;           // JSON 3x3
  final double? soEstAvg;             // computed, °F
  final double? soEstCv;              // computed

  // --- Hatcher Optimizing ---
  final String? hoBreed;
  final String? hoHatcherId;
  final int? hoIncubationAge;          // 18–21
  final bool? hoGoveeConnected;
  final double? hoGoveeTemp;           // °F
  final double? hoGoveeHumidity;
  final double? hoCo2;
  final String? hoCo2Photo;
  final String? hoCvtReadings;         // JSON 3x3, °F
  final String? hoCvtPhotos;           // JSON 3x3
  final double? hoCvtAvg;             // computed, °F
  final double? hoCvtCv;              // computed
  final bool? hoChickPanting;
  final String? hoChickPantingPhoto;

  // --- Egg Storage ---
  final bool? esGoveeConnected;
  final double? esGoveeTemp;           // °F
  final double? esGoveeHumidity;
  final double? esCo2;
  final String? esCo2Photo;
  final double? esShellTemp;           // °C (exception: industry standard in °C)
  final String? esShellTempPhoto;
  final int? esTurningTimes;           // 0–5
  final String? esUvTrays;             // JSON array
  final int? esEggStorageDays;         // default 0
  final int? esEggSampleSize;          // default 100
  final String? esEggWeights;          // JSON array
  final double? esEggAvgWeight;        // computed
  final double? esEggUniformityPct;    // computed
  final double? esEggCvPct;           // computed
  final int? esEggBmkAge;             // computed
  final double? esEggBmkWeight;       // from bmk_breeds
}
```

---

### BmkBreedModel (`bmk_breed_model.dart`)

```dart
class BmkBreedModel {
  final String breed;
  final int ageWeeks;
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double productionPct;
  final double eggWeightG;
  final double chickWeightG;
}
```

**Constraint**: Read-only. No insert/update/delete methods exposed.

---

### BmkEggBreakoutModel (`bmk_egg_breakout_model.dart`)

```dart
class BmkEggBreakoutModel {
  final int ageWeeks;
  final double infertile;
  final double earlyDead24h;
  final double earlyDead48h;
  final double bloodRing;
  final double earlyDead;
  final double midBlackEye;
  final double feathers;
  final double turned;
  final double internalPip;
  final double lateDead;
  final double externalPip;
  final double exposedBrain;
  final double crossedBeak;
  final double contaminated;
  final double cracked;
}
```

**Constraint**: Read-only. BMK Age formula: `bmkAge = flockAge - 21 - storageDays`.

---

### TroubleshootingModel (`troubleshooting_model.dart`)

```dart
class TroubleshootingModel {
  final String id;
  final String category;       // 'egg_breakout' | 'pasgar'
  final String parameter;
  final List<String> hatcheryCauses;
  final List<String> farmFlockCauses;
}
```

---

### PhotoModel (`photo_model.dart`)

```dart
class PhotoModel {
  final String id;          // UUID
  final String auditId;     // FK → audits.id
  final String fieldKey;    // Column name this photo belongs to (e.g. 'cha_co2_photo')
  final String filePath;    // Absolute local file path
  final bool synced;        // Default false
  final DateTime createdAt;
}
```

---

## Calculation Utilities (`lib/core/utils/calculation_utils.dart`)

```dart
class CalculationUtils {
  /// CV% = (stdDev / avg) × 100
  static double cvPercent(List<double> values);

  /// Uniformity = % of samples within avg ± 10%
  static double uniformityPercent(List<double> values);

  /// Pasgar = ((sampleSize × 10) - sum(parameters)) / sampleSize
  static double pasgarScore(int sampleSize, List<int> parameterCounts);

  /// Hatchability = hatched / totalSet × 100
  static double hatchability(int hatched, int totalSet);

  /// Fertility = (traySize - infertile) / traySize × 100
  static double fertility(int traySize, int infertile);

  /// HOF = hatchability / fertility × 100
  static double hof(double hatchabilityPct, double fertilityPct);

  /// YFBM% = yolkWeight / chickWeight × 100 (per entry)
  static double yfbmPercent(double yolkWeight, double chickWeight);

  /// Average of a list of doubles
  static double average(List<double> values);

  /// Standard deviation (population)
  static double stdDev(List<double> values);
}
```

---

## Date Utilities (`lib/core/utils/date_utils.dart`)

```dart
class HatchDateUtils {
  /// Flock age in weeks from entry date to today (computed, never stored)
  static double flockAgeWeeks(DateTime entryDate);

  /// Flock age in days
  static int flockAgeDays(DateTime entryDate);

  /// BMK Age = flockAge (days) - 21 - storageDays → converted to weeks
  static int bmkAgeWeeks(DateTime entryDate, int storageDays);
}
```

---

## Temperature Converter (`lib/core/utils/temp_converter.dart`)

```dart
class TempConverter {
  /// °F to °C: (f - 32) × 5/9
  static double toCelsius(double fahrenheit);

  /// °C to °F: (c × 9/5) + 32
  static double toFahrenheit(double celsius);

  /// Format for display with unit label
  static String display(double fahrenheit, {required bool showCelsius});
}
```

---

## Relationships

```
users ──< customers (created_by)
customers ──< flocks (customer_id)
customers ──< audits (customer_id)
flocks ──< audits (flock_id, nullable)
audits ──< photos (audit_id)
bmk_breeds  [read-only, referenced by calculation logic]
bmk_egg_breakout  [read-only, referenced by calculation logic]
troubleshooting  [read-only, referenced by 💡 widget Phase 2+]
```

---

## Threshold Constants (`lib/core/constants/app_thresholds.dart`)

```dart
class AppThresholds {
  static const double pasgarAlertPct = 20.0;
  static const double uniformityPoor = 80.0;
  static const double uniformityGood = 85.0;
  static const double cvAlertPct = 8.0;
  static const double yfbmMin = 8.0;
  static const double yfbmMax = 10.0;
  static const double cvtMin = 103.0;   // °F
  static const double cvtMax = 105.0;   // °F
  static const double estMin = 100.0;   // °F
  static const double estMax = 101.0;   // °F
  static const double shellTempMin = 19.0; // °C
  static const double shellTempMax = 21.0; // °C
  static const double egBreakoutHighThreshold = 3.0; // BMK + 3% = High
  static const double culledBmkPct = 1.0;
  static const double deadBmkPct = 0.2;
}
```
