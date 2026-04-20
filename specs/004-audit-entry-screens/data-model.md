# Data Model: Phase 3 — All Audit Entry Screens

**Branch**: `004-audit-entry-screens` | **Date**: 2026-04-18

---

## Schema Migration Required: DB Version 1 → 2

Add `hatchNumber INTEGER NOT NULL DEFAULT 1` to the `audits` table and replace the existing UNIQUE index:

```sql
-- Remove old index
DROP INDEX IF EXISTS idx_audits_unique;

-- Add hatchNumber column
ALTER TABLE audits ADD COLUMN hatchNumber INTEGER NOT NULL DEFAULT 1;

-- New unique index includes hatchNumber
CREATE UNIQUE INDEX idx_audits_unique
  ON audits (customerId, flockId, date, auditType, setterId, hatcherId, hatchNumber);
```

For Setter/Hatcher Optimizing (no flock), `flockId` is NULL; the index handles NULL correctly in SQLite (NULLs are distinct, so multiple NULL rows may collide — use `''` as the stored value for flock when not applicable).

---

## Entities

---

### AuditModel (existing — add `hatchNumber`)

**Table**: `audits` (existing, schema v2)

New column added this phase:

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `hatchNumber` | INTEGER | No | Defaults to 1; increments per [+] press within the same session context |

All other columns remain unchanged from Phase 2 foundation.

**Dart model**: `lib/data/models/audit_model.dart` — add `hatchNumber` field, update `fromMap` and `toMap`.

**Repository**: `lib/data/repositories/audit_repository.dart` — add `getAuditsBySession(customerId, flockId, date, auditType)` to load all hatches for a session.

---

### TrayModel (NEW)

**Storage**: JSON-encoded list in `audits.haTrays` (Hatch Results) and `audits.ebTrays` (Egg Breakout).

**Dart model**: `lib/data/models/tray_model.dart`

#### Hatch Results Tray

| Field | Type | Nullable | Notes |
|-------|------|----------|-------|
| `trayId` | String | No | User-entered label |
| `position` | String | No | One of: `Top`, `Middle`, `Bottom`, `Random` |
| `traySize` | int | No | Number of eggs in tray |
| `infertile` | int | No | Count of infertile eggs; default 0 |

**Derived**:
- `fertility = (traySize − infertile) / traySize × 100` — calculated in provider, not stored per tray

#### Egg Breakout Tray

| Field | Type | Nullable | Notes |
|-------|------|----------|-------|
| `trayId` | String | No | User-entered label |
| `position` | String | No | One of: `Top`, `Middle`, `Bottom`, `Random` |
| `parameters` | `Map<String, int>` | No | Keyed by parameter name (e.g., `infertile`, `early_24h`, `blood_ring`); value = count |

**Parameter names by breakout type**:

| Breakout Type | Parameters |
|---------------|-----------|
| Fresh Egg | `infertile`, `early_24h`, `early_48h`, `blood_ring` |
| Candled Egg | all Fresh + `black_eye` |
| Hatch Residue | `infertile`, `early`, `mid`, `late`, `external_pip`, `exposed_brain`, `crossed_beak`, `contaminated`, `cracked` |

---

### YfbmEntryModel (NEW)

**Storage**: JSON-encoded list in `audits.yfbmEntries`.

**Dart model**: `lib/data/models/yfbm_entry_model.dart`

| Field | Type | Nullable | Notes |
|-------|------|----------|-------|
| `chickWeight` | double? | Yes | g; null = empty row |
| `yolkWeight` | double? | Yes | g; null = empty row |

**Derived**:
- `percent = (yolkWeight / chickWeight) × 100` — calculated in provider when both fields non-null

---

### EstGridReading / CvtGridReading (NEW)

**Storage**: JSON-encoded in `audits.soEstReadings` / `audits.hoCvtReadings`. Photos stored in parallel `soEstPhotos` / `hoCvtPhotos` column (same JSON structure).

**Structure**: A 3×3 Map keyed by `"row_col"` (e.g., `"door_top"`, `"middle_bottom"`).

| Key format | Row options | Column options |
|-----------|-------------|----------------|
| `"{row}_{col}"` | `door`, `middle`, `back` | `top`, `middle`, `bottom` |

**Dart representation**: `Map<String, double?>` for readings; `Map<String, String?>` for photo paths.

---

### TroubleshootingModel (ENHANCED)

**Table**: `troubleshooting` (existing)

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | Parameter name key (e.g., `'infertile'`, `'early_24h'`) |
| `hatcheryCauses` | TEXT | JSON: `{"Management": [...], "Nutrition": [...], "Disease": [...], "Other": [...]}` |
| `farmFlockCauses` | TEXT | JSON: same structure |

**Dart model enhancement** (`lib/data/models/troubleshooting_model.dart`):

```dart
// New typed getters replacing flat List<String>:
Map<String, List<String>> get hatcheryCausesBySection  // parses section-keyed JSON
Map<String, List<String>> get farmFlockCausesBySection
```

**Repository**: Add `lib/data/repositories/troubleshooting_repository.dart` with `getByParameter(String parameterId)`.

---

### PhotoModel (existing — unchanged)

**Table**: `photos` (existing)

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | UUID |
| `filePath` | TEXT | Absolute path to local file in app documents directory |
| `description` | TEXT | Human-readable label |
| `createdAt` | TEXT | ISO 8601 |
| `auditId` | TEXT | FK → audits.id |

**Note**: Field-level photos (e.g., `chaCo2Photo`) are stored directly in the `audits` table as file path strings. The `photos` table is for gallery/overview use. Both are populated when a photo is captured.

---

## Computed / Derived Values

| Value | Formula | Where computed |
|-------|---------|----------------|
| Pasgar % per row | `count / sampleSize × 100` | `AuditProvider` |
| Pasgar Final Score | `((sampleSize × 10) − (reflexes + beak + navel + belly + leg)) / sampleSize` | `CalculationUtils.pasgarScore()` (to be fixed) |
| Weight AVG | `sum(weights) / count(non-null)` | `CalculationUtils.average()` |
| Low Margin | `avg − (avg × 0.10)` | `AuditProvider` |
| High Margin | `avg + (avg × 0.10)` | `AuditProvider` |
| Uniformity % | `count(in range) / total × 100` | `CalculationUtils.uniformityPercent()` (to be fixed — currently inverted) |
| CV% | `(stdDev / avg) × 100` | `CalculationUtils.cvPercent()` |
| BMK Age | `flockAgeWeeks − 21 − storageDays` | `HatchDateUtils` + `AuditProvider` |
| YFBM % per row | `yolkWeight / chickWeight × 100` | `AuditProvider` |
| YFBM AVG % | `avg(all row %)` | `AuditProvider` |
| Per-tray Fertility | `(traySize − infertile) / traySize × 100` | `AuditProvider` |
| Overall Fertility | `avg(per-tray fertility)` | `AuditProvider` |
| Hatchability | `hatched / totalEggsSet × 100` | `CalculationUtils.hatchability()` |
| HOF | `hatchability / fertility × 100` | `CalculationUtils.hof()` |
| EST/CVT AVG | `avg(all 9 grid cells non-null)` | `AuditProvider` |
| EST/CVT CV% | `cvPercent(all 9 cells)` | `CalculationUtils.cvPercent()` |
| UV tray % affected | `affected / totalEggs × 100` | `AuditProvider` |
| Overall UV avg affected | `avg(all tray % affected)` | `AuditProvider` |
| Egg breakout BMK Age | `flockAgeWeeks − breakoutAgeDays − storageDays` | `AuditProvider` |

---

## In-Memory State (AuditProvider)

```
AuditProvider
├── AuditContext
│   ├── auditType: String             // 'chick_quality' | 'hatch_analysis' | etc.
│   ├── customer: CustomerModel
│   ├── flock: FlockModel?            // null for Setter/Hatcher Optimizing
│   └── breed: String?                // for Setter/Hatcher Optimizing only
│
├── List<AuditModel> _drafts          // one draft per hatch (hatchNumber 1, 2, 3...)
├── int _activeHatchIndex             // which draft is currently being edited
│
├── Map<int, Set<int>> _savedTabs     // hatchIndex → set of saved tab indices
│
├── TempUnit tempUnit                  // mirrors AppProvider.tempUnit
│
├── bool isLoading
└── String? errorMessage

Derived:
├── AuditModel get activeDraft        // _drafts[_activeHatchIndex]
└── bool isTabSaved(int hatch, int tab)
```

---

## Validation Rules

| Rule | Entity | Condition |
|------|--------|-----------|
| Sample size > 0 | Pasgar, Weights | Denominator protection; defaults prevent 0 |
| Pasgar counts ≥ 0 | Pasgar | [−] button disabled at 0 |
| Pasgar counts ≤ sampleSize | Pasgar | [+] button disabled at limit |
| Total eggs ≥ hatched + culled + dead | Hatch Results | Provider validates before save |
| Hatch number unique per session | DB | Enforced via UNIQUE INDEX |
| Tray ID not empty | Hatch Results / Egg Breakout | Required field; provider validates before tray add |
| Photo path valid at save | All photo fields | `File(path).existsSync()` check on save |
| Incubation age in range | Setter (1–18), Hatcher (18–21) | Enforced in UI (slider/stepper min/max) |
| UV tray count ≤ 10 | Egg Storage | [+ Add Tray] disabled when count = 10 |

---

## No New Tables Required

All new data (hatchNumber, tray JSON, YFBM JSON, EST/CVT grid JSON) fits within the existing `audits` schema. Only the `hatchNumber` column and UNIQUE INDEX update require a schema migration.
