# Phase 1 — Stabilization

**Goal**: All existing features work correctly. No empty states without feedback. No data loss from navigation. Troubleshooting always has data. Photos have sync status.
**Prerequisite**: Phase 0 complete.
**Estimated time**: ~11 hours total
**DB version change**: v11 → v12 (in Task 1.6)

---

## TASK 1.1 — Dashboard: Wire ChickQualitySection (5 sub-tabs)

**Risk**: LOW
**Time**: 2h

### Problem
`ChickQualitySection` in `stub_sections.dart` has 5 tabs (Pasgar, Weights, YFBM, CVT, CHA Env) that are either empty or partially wired. `DashboardProvider` already has all the data methods — just need to connect them.

### Files to Read (context)
- `lib/features/dashboard/widgets/sections/stub_sections.dart` — full file
- `lib/features/dashboard/providers/dashboard_provider.dart` — full file
- `lib/core/constants/app_thresholds.dart` — full file
- `lib/features/dashboard/models/chick_quality_models.dart` — full file

### Files to Modify
- `lib/features/dashboard/widgets/sections/stub_sections.dart`

### Step-by-Step Implementation

**Step 1**: Add a reusable empty-state widget at the top of the file (after imports):

```dart
Widget _emptySection(String label) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
  child: Column(
    children: [
      const Icon(Icons.bar_chart_outlined, size: 48, color: Colors.black26),
      const SizedBox(height: 8),
      Text(
        'No $label data yet.\nCreate audits to see analytics.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black45, fontSize: 13),
      ),
    ],
  ),
);
```

**Step 2**: In `ChickQualitySection`, wrap the build in `Consumer<DashboardProvider>`.

**Step 3**: Wire **Pasgar tab** (tab index 0):
- Read `provider.pasgarAvg` (type: `PasgarAvg?`)
- If null → `_emptySection('Pasgar')`
- If not null → show:
  - `_metricRow('Sample Size', provider.pasgarAvg!.sampleSize.toString())`
  - `_metricRow('Final Score', '${provider.pasgarAvg!.finalScore.toStringAsFixed(1)}%', color: _threshold(provider.pasgarAvg!.finalScore, 80))`
  - Metric rows for each of: reflexes, beak, navel, belly, leg, featherDev scores
  - Photo section: `_photoSection(context, provider.pasgarPhotos ?? [])`

**Step 4**: Wire **Weights tab** (tab index 1):
- Read `provider.chickWeightTrend` (type: `ChickWeightTrend?`)
- If null → `_emptySection('Chick Weights')`
- If not null → show:
  - `BmkLineChart` with `avgWeight` over time
  - `_metricRow('Avg Weight', '${provider.chickWeightTrend!.avgWeight.toStringAsFixed(1)}g')`
  - `_metricRow('CV%', '${provider.chickWeightTrend!.cvPct.toStringAsFixed(1)}%', color: _threshold(provider.chickWeightTrend!.cvPct, AppThresholds.cvAlertPct, lowerIsBetter: true))`

**Step 5**: Wire **YFBM tab** (tab index 2):
- Read `provider.yfbmTrend` (type: `List<YfbmTrend>`)
- If empty → `_emptySection('YFBM')`
- If not empty → show:
  - `BmkLineChart` with `avgPct` over time
  - Latest value metric row with threshold band (AppThresholds.yfbmMin / yfbmMax)
  - Photo section: `_photoSection(context, provider.yfbmPhotos)`

**Step 6**: Wire **CVT tab** (tab index 3):
- Read `provider.cvtAvg` (type: `CvtAvg?`)
- If null → `_emptySection('CVT')`
- If not null → show:
  - `_metricRow('Avg Temp', formatTemp(provider.cvtAvg!.avgTemp, provider... tempUnit))`
  - `_metricRow('CV%', '${provider.cvtAvg!.cvPct.toStringAsFixed(1)}%', color: _threshold(...))`
  - Photo section

**Step 7**: Wire **CHA Environmental tab** (tab index 4):
- Read `provider.chaTrend` (type: `List<ChaEnvironmentalTrend>`)
- If empty → `_emptySection('CHA Environmental')`
- If not empty → show:
  - `BmkLineChart` for CO2 over time
  - Latest reading metric rows: CO2 ppm, PM10, PM25, avg air velocity, noise dB
  - Photo section: `_photoSection(context, provider.chaPhotos)`

### Notes on Provider Getters
Check `DashboardProvider` for exact getter names before implementing. They may be:
- `pasgarAvg` → `PasgarAvg?`
- `chickWeightTrend` → `ChickWeightTrend?`  
- `yfbmTrend` → `List<YfbmTrend>`
- `cvtAvg` → `CvtAvg?`
- `chaTrend` → `List<ChaEnvironmentalTrend>`

If a getter doesn't exist, check if the data is loaded in `DashboardProvider.init()`. If not loaded, add the load call.

### Expected Output
All 5 tabs show real data when audits exist, or clear empty state when no data. No white blank areas.

### Manual Test
1. Run app with `dummy_data_seeds` loaded → all 5 tabs show data
2. Filter to customer with no Chick Quality audits → all 5 tabs show empty state
3. No crash when switching between tabs rapidly

---

## TASK 1.2 — Dashboard: Wire EggStorage, Setter, Hatcher Sections

**Risk**: LOW
**Time**: 1.5h

### Files to Read (context)
- `lib/features/dashboard/widgets/sections/stub_sections.dart` — full file
- `lib/features/dashboard/providers/dashboard_provider.dart` — full file
- `lib/features/dashboard/models/egg_storage_models.dart` — full file
- `lib/core/constants/app_thresholds.dart`

### Files to Modify
- `lib/features/dashboard/widgets/sections/stub_sections.dart`

### Step-by-Step Implementation

**EggStorageSection**:
- Read `provider.eggStorageTrend` (type: `EggStorageTrend?`)
- If null → `_emptySection('Egg Storage')`
- Show:
  - Shell temp trend line chart
  - `_metricRow('Shell Temp', formatTemp(value))` with threshold (AppThresholds.shellTempMin/Max: 19–21°C)
  - `_metricRow('Avg Egg Weight', '${value}g')`
  - `_metricRow('CV%', '${value}%')`
  - Photo section: `_photoSection(context, provider.shellTempPhotos)`

**SetterOptimizingSection**:
- Read `provider.setterComparisons` (type: `List<SetterComparison>` — check exact type name in provider)
- If empty → `_emptySection('Setter Optimizing')`
- Show:
  - `BmkBarChart` where each bar = one setter ID, height = avg EST temp
  - Add threshold reference line at `AppThresholds.estMin/Max`
  - List of setter IDs with their avg EST below chart

**HatcherOptimizingSection**:
- Read `provider.hatcherComparisons`
- If empty → `_emptySection('Hatcher Optimizing')`
- Show:
  - `BmkBarChart` with avg CVT per hatcher ID
  - Threshold line at `AppThresholds.cvtMin/Max`

### Manual Test
1. With setter/hatcher audits in DB → sections show bar charts
2. Without setter audits → setter section shows empty state
3. No crash on section scroll

---

## TASK 1.3 — Dashboard: Filter Reset + Cascade Fix

**Risk**: LOW
**Time**: 1h

### Files to Read (context)
- `lib/features/dashboard/providers/dashboard_provider.dart` — full file
- `lib/features/dashboard/screens/dashboard_screen.dart` — full file

### Files to Modify
- `lib/features/dashboard/providers/dashboard_provider.dart`
- `lib/features/dashboard/screens/dashboard_screen.dart`

### Step-by-Step Implementation

**Step 1**: Add to `DashboardProvider`:

```dart
bool get hasActiveFilters =>
    _selectedCustomerId != null ||
    _selectedFlockId != null ||
    _selectedBmkAge != null;

void clearFilters() {
  _selectedCustomerId = null;
  _selectedFlockId = null;
  _selectedBmkAge = null;
  _flocks = [];
  notifyListeners();
  _reload();
}
```

**Step 2**: Fix cascade — when customer changes, reset flock. In existing `setCustomer()` method, add:
```dart
void setCustomer(String? customerId) {
  _selectedCustomerId = customerId;
  _selectedFlockId = null;  // ← add this line
  _flocks = [];             // ← add this line
  notifyListeners();
  _reload();
}
```

**Step 3**: In `DashboardScreen._buildCascadeFilter`, add a "Clear" button row below the 3 dropdowns:

```dart
if (provider.hasActiveFilters)
  Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      onPressed: provider.clearFilters,
      icon: const Icon(Icons.clear, size: 16),
      label: const Text('Clear filters'),
      style: TextButton.styleFrom(foregroundColor: Colors.black54),
    ),
  ),
```

Place this as the last child in the filter `Column`.

### Expected Output
- Clear button appears only when at least one filter is active
- Changing customer resets flock to "All flocks"
- Clear resets all 3 dropdowns and reloads charts

### Manual Test
1. Select customer → flock dropdown auto-populates with that customer's flocks only
2. Change customer → flock resets
3. Select age filter → "Clear filters" button appears
4. Tap Clear → all 3 dropdowns reset, charts reload

---

## TASK 1.4 — Unsaved Changes Warning (All 5 Audit Screens)

**Risk**: MEDIUM
**Time**: 2h

### Files to Read (context)
- `lib/features/audits/providers/audit_provider.dart` — full file
- `lib/features/audits/screens/chick_quality_screen.dart` — full file (check Scaffold structure)
- `lib/features/audits/screens/hatch_analysis_screen.dart` — first 50 lines
- `lib/features/audits/screens/egg_storage_screen.dart` — first 30 lines

### Files to Modify
- `lib/features/audits/providers/audit_provider.dart`
- `lib/features/audits/screens/chick_quality_screen.dart`
- `lib/features/audits/screens/hatch_analysis_screen.dart`
- `lib/features/audits/screens/egg_storage_screen.dart`
- `lib/features/audits/screens/setter_optimizing_screen.dart`
- `lib/features/audits/screens/hatcher_optimizing_screen.dart`

### New Files to Create
- `lib/features/audits/widgets/unsaved_changes_guard.dart`

### Step-by-Step Implementation

**Step 1**: Add `_isDirty` tracking to `AuditProvider`. Find `updateField` method and add:

```dart
bool _isDirty = false;
bool get isDirty => _isDirty;
```

In `updateField()`:
```dart
void updateField(String key, dynamic value) {
  _isDirty = true;     // ← add this as first line
  // ... rest of existing updateField logic
}
```

In `saveTab()` success path, add after successful save:
```dart
_isDirty = false;
```

In `initialize()` method, add at the end:
```dart
_isDirty = false;
```

**Step 2**: Create `lib/features/audits/widgets/unsaved_changes_guard.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audit_provider.dart';

class UnsavedChangesGuard extends StatelessWidget {
  final Widget child;
  const UnsavedChangesGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final provider = context.read<AuditProvider>();
        if (!provider.isDirty) {
          if (context.mounted) Navigator.of(context).pop();
          return;
        }
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Unsaved changes'),
            content: const Text(
              'You have unsaved changes in this tab. Leave without saving?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: child,
    );
  }
}
```

**Step 3**: Wrap the `Scaffold` in each of the 5 audit screens with `UnsavedChangesGuard`:

```dart
// In each audit screen's build() method:
return UnsavedChangesGuard(
  child: Scaffold(
    // ... existing scaffold content unchanged
  ),
);
```

Add import: `import '../widgets/unsaved_changes_guard.dart';`

### Expected Output
- Back navigation with unsaved changes triggers dialog
- "Stay" → remains on screen
- "Leave" → exits without saving
- After saving a tab → back navigation works without dialog

### Edge Cases
- Tab switching within the screen (TabController) must NOT trigger the guard — `PopScope` only intercepts route pop, not tab changes, so this is automatic
- `isReadOnly` mode: guard should still apply (user might have accidentally enabled edit mode)
- Multi-hatch: `isDirty` is global per session, not per-hatch — acceptable

### Manual Test
1. Open Chick Quality audit → type any value in any field → press back → dialog appears
2. Press "Stay" → on screen, value still there
3. Press "Leave" → returns to previous screen
4. Open audit → type value → tap "Save Tab" → press back → no dialog

---

## TASK 1.5 — Troubleshooting: Seed Data + Empty State + Search

**Risk**: LOW
**Time**: 2h

### Files to Read (context)
- `lib/data/database/database_helper.dart` — `_onCreate` method and end of `_onUpgrade`
- `lib/features/audits/widgets/troubleshooting_sheet.dart` — full file
- `lib/data/repositories/troubleshooting_repository.dart` — full file
- `lib/data/models/troubleshooting_model.dart` — full file

### New Files to Create
- `lib/data/database/seeds/troubleshooting_seeds.dart`

### Files to Modify
- `lib/data/database/database_helper.dart`
- `lib/features/audits/widgets/troubleshooting_sheet.dart`

### Step-by-Step Implementation

**Step 1**: Create `lib/data/database/seeds/troubleshooting_seeds.dart`.

The data structure: `id` = the parameter key used when calling `TroubleshootingSheet(parameterId: ...)`. Check `lib/widgets/troubleshooting_icon.dart` and all tab files for what `parameterId` values are used when launching the sheet.

```dart
import 'dart:convert';

const List<Map<String, dynamic>> kTroubleshootingSeeds = [
  {
    'id': 'high_infertile',
    'hatcheryCauses': {
      'Setter Equipment': [
        'Temperature set too high or too low',
        'Humidity levels incorrect',
        'Turning mechanism failure',
      ],
      'Egg Handling': [
        'Eggs stored too long before setting',
        'Eggs stored at wrong temperature',
        'Rough handling during transfer',
      ],
    },
    'farmFlockCauses': {
      'Male Fertility': [
        'Poor male-to-female ratio',
        'Heat stress in males',
        'Age-related fertility decline',
        'Nutritional deficiency (Vitamin E/Selenium)',
      ],
      'Flock Management': [
        'Infrequent egg collection',
        'Poor nesting box hygiene',
        'Overcrowding causing missed matings',
      ],
    },
  },
  {
    'id': 'high_early_dead',
    'hatcheryCauses': {
      'Setter Conditions': [
        'Temperature too high in first 3 days',
        'CO2 levels above 0.5%',
        'Fumigation errors',
      ],
      'Egg Quality': [
        'Cracked eggs set',
        'Contaminated eggs',
      ],
    },
    'farmFlockCauses': {
      'Breeder Health': [
        'Mycoplasma infection',
        'Salmonella in breeders',
        'Nutritional deficiencies (Vitamin A, B12)',
      ],
      'Vaccination': [
        'Incomplete vaccination program',
        'Maternal antibody interference',
      ],
    },
  },
  {
    'id': 'high_late_dead',
    'hatcheryCauses': {
      'Hatcher Conditions': [
        'CO2 above 0.5% at hatching time',
        'Humidity too low causing desiccation',
        'Temperature spike at lockdown',
      ],
    },
    'farmFlockCauses': {
      'Breeder Nutrition': [
        'Vitamin D3 deficiency',
        'Calcium/phosphorus imbalance',
        'Biotin deficiency',
      ],
    },
  },
  {
    'id': 'low_hatchability',
    'hatcheryCauses': {
      'Temperature': [
        'Chronic high or low temperature',
        'Temperature variation > 0.3°F between setter zones',
        'Faulty temperature probe calibration',
      ],
      'Humidity': [
        'Wet bulb below 84°F during incubation',
        'Wet bulb above 90°F at hatch',
      ],
      'Turning': [
        'Turning angle less than 45°',
        'Turning frequency less than hourly',
        'Turning stopped prematurely',
      ],
    },
    'farmFlockCauses': {
      'Flock Age': [
        'Flock past peak production age',
        'Flock too young (under 26 weeks)',
      ],
      'Disease': [
        'IB, ILT, or ND infection in breeders',
        'MG/MS in breeders',
      ],
    },
  },
  {
    'id': 'low_pasgar',
    'hatcheryCauses': {
      'Hatcher Management': [
        'Pull time too early or too late',
        'High CO2 at hatch (> 0.8%)',
        'Temperature spike during hatch window',
        'Inadequate ventilation',
      ],
      'Chick Holding': [
        'Holding room temperature too high or too low',
        'Extended hold time before delivery',
        'Dehydration during holding',
      ],
    },
    'farmFlockCauses': {
      'Breeder Nutrition': [
        'Vitamin B12 deficiency',
        'Riboflavin deficiency',
        'Folic acid deficiency',
      ],
    },
  },
  {
    'id': 'high_cv',
    'hatcheryCauses': {
      'Setter Loading': [
        'Mixed-age eggs in same setter',
        'Uneven egg size across trays',
        'Uneven air distribution in setter',
      ],
    },
    'farmFlockCauses': {
      'Flock Uniformity': [
        'High coefficient of variation in breeder flock weight',
        'Multiple age flocks combined',
        'Feed delivery not uniform across house',
      ],
    },
  },
];

/// Convert seed data to DB row format (JSON-encode the nested maps)
List<Map<String, dynamic>> get kTroubleshootingDbRows {
  return kTroubleshootingSeeds.map((seed) {
    return {
      'id': seed['id'],
      'hatcheryCausesJson': jsonEncode(seed['hatcheryCauses']),
      'farmFlockCausesJson': jsonEncode(seed['farmFlockCauses']),
    };
  }).toList();
}
```

**Step 2**: Add seed call to `DatabaseHelper`. Find `_onCreate` method and add at the end:

```dart
import '../seeds/troubleshooting_seeds.dart'; // add import at top of file

// In _onCreate, after all table creation:
await _seedTroubleshooting(db);
```

Add the method:
```dart
Future<void> _seedTroubleshooting(Database db) async {
  for (final row in kTroubleshootingDbRows) {
    await db.insert(
      'troubleshooting',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
```

**Step 3**: Add same call to `_onUpgrade`. Find the LAST migration block (the highest version number check) and add after it:

```dart
// Seed troubleshooting data (safe to re-run — uses INSERT OR IGNORE)
await _seedTroubleshooting(db);
```

**Step 4**: Add search and empty state to `TroubleshootingSheet`. Find the existing sheet widget and modify:

1. Add `TextEditingController _searchController = TextEditingController()` to state.
2. Add `String _searchQuery = ''` to state.
3. In `initState`, add: `_searchController.addListener(() => setState(() => _searchQuery = _searchController.text.toLowerCase()));`
4. In `dispose`: `_searchController.dispose()`.
5. Add a `TextField` at the top of the sheet body (below the handle bar, above the TabBar):

```dart
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  child: TextField(
    controller: _searchController,
    decoration: InputDecoration(
      hintText: 'Search causes...',
      prefixIcon: const Icon(Icons.search, size: 20),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      suffixIcon: _searchQuery.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => _searchController.clear(),
            )
          : null,
    ),
  ),
),
```

6. When rendering causes, filter by `_searchQuery`:
```dart
// Before displaying a category's causes list:
final filteredCauses = causes.where(
  (c) => _searchQuery.isEmpty || c.toLowerCase().contains(_searchQuery),
).toList();
if (filteredCauses.isEmpty) continue; // skip empty categories
```

7. Add empty state for when `_troubleshooting == null` after loading:
```dart
if (_troubleshooting == null) {
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'No troubleshooting data available for this parameter.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.black45),
      ),
    ),
  );
}
```

### Expected Output
- Fresh install: troubleshooting table seeded automatically
- Existing install: upgrade seeds with `INSERT OR IGNORE` (no duplicates)
- Sheet always shows content or clear empty state
- Search filters causes list live

### Manual Test
1. Fresh install (or delete DB) → open any audit → tap troubleshooting icon → causes appear
2. Type "temperature" in search → only temperature-related causes shown
3. Clear search → all causes return
4. Open troubleshooting for a parameter with no seed data → empty state message shown
5. Existing install after upgrade → `INSERT OR IGNORE` → no duplicate rows in DB

---

## TASK 1.6 — Photo Sync: Upload Status + Retry Queue

**Risk**: MEDIUM
**Time**: 2.5h

### This task includes DB migration to v12

### Files to Read (context)
- `lib/data/models/photo_model.dart` — full file
- `lib/data/repositories/photo_repository.dart` — full file
- `lib/services/supabase/supabase_service.dart` — full file
- `lib/services/supabase/startup_sync_service.dart` — full file
- `lib/features/audits/widgets/photo_button.dart` — full file
- `lib/data/database/database_helper.dart` — `_onUpgrade` method

### New Files to Create
- `lib/services/photo/photo_sync_service.dart`

### Files to Modify
- `lib/data/database/database_helper.dart` (migration v12)
- `lib/data/models/photo_model.dart`
- `lib/data/repositories/photo_repository.dart`
- `lib/services/supabase/startup_sync_service.dart`
- `lib/features/audits/widgets/photo_button.dart`

### Step-by-Step Implementation

**Step 1**: DB Migration v12. In `database_helper.dart`:

1. Change `version: 11` to `version: 12`.
2. In `_onUpgrade`, add a new block for v12:

```dart
if (oldVersion < 12) {
  // Add upload status tracking to photos
  final photoCols = await db.rawQuery('PRAGMA table_info(photos)');
  final photoColNames = photoCols.map((r) => r['name'] as String).toSet();
  
  if (!photoColNames.contains('uploadStatus')) {
    await db.execute(
      "ALTER TABLE photos ADD COLUMN uploadStatus TEXT NOT NULL DEFAULT 'local'",
    );
    // Existing photos were created before this feature — mark as synced
    // (they were inserted by startup sync which already pushed them)
    await db.execute("UPDATE photos SET uploadStatus = 'synced'");
  }
}
```

**Step 2**: Update `PhotoModel`:

```dart
// Add field:
final String uploadStatus; // 'local' | 'synced' | 'failed'

// Update constructor to include uploadStatus with default:
const PhotoModel({
  required this.id,
  required this.filePath,
  this.description,
  required this.createdAt,
  this.auditId,
  this.uploadStatus = 'local',  // default for new photos
});

// Update fromMap:
uploadStatus: map['uploadStatus'] as String? ?? 'local',

// Update toMap:
'uploadStatus': uploadStatus,
```

**Step 3**: Add methods to `PhotoRepository`:

```dart
Future<List<PhotoModel>> getByUploadStatus(String status) async {
  final db = await dbHelper.db;
  final result = await db.query(
    'photos',
    where: 'uploadStatus = ?',
    whereArgs: [status],
  );
  return result.map(PhotoModel.fromMap).toList();
}

Future<void> updateUploadStatus(String photoId, String status) async {
  final db = await dbHelper.db;
  await db.update(
    'photos',
    {'uploadStatus': status},
    where: 'id = ?',
    whereArgs: [photoId],
  );
}
```

**Step 4**: Create `lib/services/photo/photo_sync_service.dart`:

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../data/repositories/photo_repository.dart';
import '../supabase/supabase_service.dart';

class PhotoSyncService {
  final PhotoRepository _repo = PhotoRepository();
  final SupabaseService _supabase = SupabaseService();

  Future<void> syncPending() async {
    try {
      final pending = await _repo.getByUploadStatus('local');
      for (final photo in pending) {
        await _syncPhoto(photo.id, photo.filePath);
      }
      // Retry previously failed ones
      final failed = await _repo.getByUploadStatus('failed');
      for (final photo in failed) {
        await _syncPhoto(photo.id, photo.filePath);
      }
    } catch (e) {
      debugPrint('[PhotoSyncService] syncPending error: $e');
    }
  }

  Future<void> _syncPhoto(String photoId, String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        await _repo.updateUploadStatus(photoId, 'failed');
        return;
      }
      // Upload to Supabase Storage
      await _supabase.uploadPhotoFile(photoId, file);
      await _repo.updateUploadStatus(photoId, 'synced');
    } catch (e) {
      debugPrint('[PhotoSyncService] failed to sync photo $photoId: $e');
      await _repo.updateUploadStatus(photoId, 'failed');
    }
  }
}
```

**Step 5**: Add `uploadPhotoFile` to `SupabaseService`:

```dart
Future<void> uploadPhotoFile(String photoId, File file) async {
  final client = Supabase.instance.client;
  final bytes = await file.readAsBytes();
  final fileName = 'photos/$photoId.jpg';
  await client.storage.from('photos').uploadBinary(
    fileName,
    bytes,
    fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
  );
}
```

Note: Supabase Storage bucket named `photos` must be created in Supabase dashboard before this works.

**Step 6**: Call `PhotoSyncService().syncPending()` in `StartupSyncService`. Find where the sync steps end and add:

```dart
// After existing sync steps:
onProgress?.call(0.95, 'Syncing photos...');
await PhotoSyncService().syncPending();
onProgress?.call(1.0, 'Sync complete');
```

**Step 7**: Update `PhotoButton` widget to show upload status icon. Find where photos are displayed (likely a Stack with the image). Add a small status indicator:

```dart
// After loading photo from PhotoRepository, check uploadStatus
// Show overlay icon on thumbnail:
Positioned(
  bottom: 4,
  right: 4,
  child: Icon(
    photo.uploadStatus == 'synced'
        ? Icons.cloud_done
        : photo.uploadStatus == 'failed'
            ? Icons.cloud_off
            : Icons.cloud_upload,
    size: 14,
    color: photo.uploadStatus == 'synced'
        ? Colors.green
        : photo.uploadStatus == 'failed'
            ? Colors.red
            : Colors.grey,
  ),
),
```

Note: This requires `PhotoButton` to have access to the `PhotoModel` (with `uploadStatus`), not just the file path. Check current implementation — if it only uses file paths, you may need to load the `PhotoModel` from `PhotoRepository` for each photo to get the status.

### Expected Output
- New photos created offline: `uploadStatus = 'local'`, grey cloud icon
- On next sync with internet: uploads succeed → `uploadStatus = 'synced'`, green icon
- Upload failures: `uploadStatus = 'failed'`, red icon, retried on next sync
- No silent data loss

### Edge Cases
- Supabase storage bucket `photos` must exist — document this requirement
- File > 5MB: Supabase free tier has limits — add file size check: if `file.lengthSync() > 5 * 1024 * 1024`, skip upload and log warning
- `uploadBinary` may fail on bad network — caught by try/catch, marked `failed`

### Manual Test
1. Enable airplane mode → take photo in audit → save → check DB: `uploadStatus = 'local'`
2. Disable airplane mode → restart app → startup sync runs → check DB: `uploadStatus = 'synced'`
3. Take photo → delete file manually from filesystem → restart app → check DB: `uploadStatus = 'failed'`, red icon on thumbnail
4. Verify DB version is now 12

---

## Phase 1 Completion Checklist

- [ ] Task 1.1: ChickQuality all 5 tabs show data or empty state (no blank areas)
- [ ] Task 1.2: EggStorage, Setter, Hatcher sections functional
- [ ] Task 1.3: Filter clear button works, cascade resets on customer change
- [ ] Task 1.4: Back navigation with unsaved data triggers dialog on all 5 audit screens
- [ ] Task 1.5: Troubleshooting data present after fresh install; search works
- [ ] Task 1.6: Photos have upload status, retry works on next sync
- [ ] DB version is 12
- [ ] `dart analyze` passes
- [ ] `flutter build apk --debug` compiles
