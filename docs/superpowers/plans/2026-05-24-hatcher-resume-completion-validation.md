# Hatcher Resume And Completion Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Hatcher multi-machine resume/edit, add station-specific completion validation, clean blank/default-only station rows, preserve explicit Hatch Analysis scopes, and polish the requested Setters/Hatcher UI sections.

**Architecture:** Keep persistence in `AuditProvider`, session progress decisions in `AuditSessionScreen`/`AuditSessionProvider`, and station-specific widgets responsible only for UI and local form synchronization. Add one small completion-validation model so navigation can distinguish a saved complete station from an incomplete station that can be skipped after confirmation.

**Tech Stack:** Flutter, Provider, SQLite-backed repositories, panel-table persistence, `flutter_test`, `mocktail`.

---

## Scope Check

This is one implementation slice because every change supports the visit station exit path and its station-specific data/UI correctness. The plan keeps it as one branch but uses separate commits so the Hatcher resume fix, station validation, Hatch Analysis scope rules, and UI polish can be reviewed independently.

## File Map

- Create: `lib/features/audits/models/station_completion_validation.dart`
  - Defines the result object used between station save logic and session navigation.
- Modify: `lib/features/audits/providers/audit_provider.dart`
  - Adds meaningful-data and core-completion checks.
  - Skips and deletes blank/default-only panel rows for non-Egg station tables.
  - Exposes `validateStationCompletion(String stationKey)` after a save.
- Modify: `lib/features/audits/screens/audit_session_screen.dart`
  - Runs the save/cleanup/validation station exit path.
  - Shows the incomplete-station confirmation dialog.
  - Marks stations complete only for forward/final complete exits.
  - Removes completion when review edits delete core data.
- Modify: `lib/features/audits/providers/audit_session_provider.dart`
  - Adds a focused helper for removing the current station from completion progress.
- Modify: `lib/features/audits/screens/hatcher_optimizing_screen.dart`
  - Accepts `initialAudits` and `initialStationSamples`, matching Setters.
  - Replaces Hatcher incubation sliders with outlined numeric fields.
- Modify: `lib/features/audits/screens/audit_session_screen.dart`
  - Passes all hydrated Hatcher rows and station samples to `HatcherOptimizingScreen`.
- Modify: `lib/features/audits/screens/hatch_analysis_screen.dart`
  - Prevents Machine scope from creating a synthetic House scope.
  - Keeps Tray scope from creating House/Machine scope and syncs tray hierarchy only from active scopes.
- Modify: `lib/features/audits/screens/setter_optimizing_screen.dart`
  - Restyles the Setters incubation-age sample selector.
- Modify: `docs/LIVING_SPEC.md`
  - Documents the implemented completion, resume, scope, and UI behavior.
- Test: `test/features/audits/audit_provider_save_result_test.dart`
  - Covers completion validation and blank/default row cleanup.
- Test: `test/features/audits/audit_session_navigation_test.dart`
  - Covers incomplete station confirmation and progress behavior.
- Test: `test/features/audits/incubation_age_hours_test.dart`
  - Covers Hatcher multi-machine resume and Setters/Hatcher UI changes.
- Test: `test/features/audits/hatch_analysis_screen_breakout_test.dart`
  - Covers Hatch Analysis Machine/Tray scope inheritance.
- Test: `test/features/audits/audit_session_provider_test.dart`
  - Covers removal of a completed station from progress.

---

### Task 1: Completion Validation Model And Provider Rules

**Files:**
- Create: `lib/features/audits/models/station_completion_validation.dart`
- Modify: `lib/features/audits/providers/audit_provider.dart`
- Test: `test/features/audits/audit_provider_save_result_test.dart`

- [ ] **Step 1: Write failing provider validation tests**

Append this group near the bottom of `test/features/audits/audit_provider_save_result_test.dart`:

```dart
group('station completion validation', () {
  test('blank default setter save deletes rows and remains incomplete', () async {
    provider.initialize(
      AuditContext(
        auditType: 'Setters',
        customerId: 'customer-1',
        flockId: 'flock-1',
        flockAgeWeeks: 40,
        setterId: 'S5',
        date: '2026-01-01',
      ),
      currentUser: user,
      sessionId: 'session-1',
      notify: false,
    );

    expect(await provider.saveSamplesWithResult(), isTrue);

    verifyNever(
      () => panelSampleRepository.savePanelWithSamples(
        panel: any(named: 'panel'),
        samples: any(named: 'samples'),
      ),
    );
    verify(
      () => panelSampleRepository.deleteRowsBySessionId(
        'setter_optimizing',
        'session-1',
      ),
    ).called(1);
    expect(
      provider.validateStationCompletion('setters').status,
      StationCompletionStatus.emptyOrDiscarded,
    );
  });

  test('setter setpoint marks station complete', () async {
    provider.initialize(
      AuditContext(
        auditType: 'Setters',
        customerId: 'customer-1',
        flockId: 'flock-1',
        flockAgeWeeks: 40,
        setterId: 'S5',
        date: '2026-01-01',
      ),
      currentUser: user,
      sessionId: 'session-1',
      notify: false,
    );
    provider.updateField('so_setpointF', 99.8);

    expect(await provider.saveSamplesWithResult(), isTrue);

    expect(
      provider.validateStationCompletion('setters').status,
      StationCompletionStatus.complete,
    );
  });

  test('hatcher CVT reading marks station complete', () async {
    provider.initialize(
      AuditContext(
        auditType: 'Hatchers',
        customerId: 'customer-1',
        flockId: 'flock-1',
        flockAgeWeeks: 40,
        hatcherId: 'H7',
        date: '2026-01-01',
      ),
      currentUser: user,
      sessionId: 'session-1',
      notify: false,
    );
    provider.updateField('hoCvtReadings', jsonEncode({'front_top': 99.1}));

    expect(await provider.saveSamplesWithResult(), isTrue);

    expect(
      provider.validateStationCompletion('hatchers').status,
      StationCompletionStatus.complete,
    );
  });

  test('optional chick environment data saves but chick core remains incomplete', () async {
    provider.initialize(
      AuditContext(
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        flockAgeWeeks: 40,
        date: '2026-01-01',
      ),
      currentUser: user,
      sessionId: 'session-1',
      notify: false,
    );
    provider.updateField('chaCo2', 1200.0);

    expect(await provider.saveSamplesWithResult(), isTrue);

    expect(
      provider.validateStationCompletion('chicks').status,
      StationCompletionStatus.savedButIncomplete,
    );
  });
});
```

Add the import at the top:

```dart
import 'package:hatchaudit/features/audits/models/station_completion_validation.dart';
```

- [ ] **Step 2: Run the provider tests and confirm they fail**

Run:

```bash
flutter test test/features/audits/audit_provider_save_result_test.dart
```

Expected: fails because `StationCompletionStatus`, `validateStationCompletion`, and the non-Egg blank-row cleanup do not exist yet.

- [ ] **Step 3: Add the completion validation model**

Create `lib/features/audits/models/station_completion_validation.dart`:

```dart
enum StationCompletionStatus {
  complete,
  savedButIncomplete,
  emptyOrDiscarded,
  failed,
}

class StationCompletionValidation {
  final StationCompletionStatus status;
  final String stationKey;
  final String message;

  const StationCompletionValidation({
    required this.status,
    required this.stationKey,
    required this.message,
  });

  bool get canNavigate => status != StationCompletionStatus.failed;

  bool get shouldMarkCompleted => status == StationCompletionStatus.complete;

  bool get needsIncompleteConfirmation =>
      status == StationCompletionStatus.savedButIncomplete ||
      status == StationCompletionStatus.emptyOrDiscarded;

  static StationCompletionValidation complete(String stationKey) {
    return StationCompletionValidation(
      status: StationCompletionStatus.complete,
      stationKey: stationKey,
      message: 'Station complete.',
    );
  }

  static StationCompletionValidation savedButIncomplete(String stationKey) {
    return StationCompletionValidation(
      status: StationCompletionStatus.savedButIncomplete,
      stationKey: stationKey,
      message:
          'This station has saved data but not enough core data to mark complete.',
    );
  }

  static StationCompletionValidation emptyOrDiscarded(String stationKey) {
    return StationCompletionValidation(
      status: StationCompletionStatus.emptyOrDiscarded,
      stationKey: stationKey,
      message:
          'This station has no core data to mark complete. Blank rows were cleared.',
    );
  }

  static StationCompletionValidation failed(String stationKey) {
    return StationCompletionValidation(
      status: StationCompletionStatus.failed,
      stationKey: stationKey,
      message: 'Could not save station. Try again.',
    );
  }
}
```

- [ ] **Step 4: Add provider meaningful-data helpers**

In `lib/features/audits/providers/audit_provider.dart`, import the new model:

```dart
import '../models/station_completion_validation.dart';
```

Add these public and private helpers near the existing `_hasMeaningfulEggQualityData` helpers:

```dart
StationCompletionValidation validateStationCompletion(String stationKey) {
  final hasAny = _hasAnyMeaningfulStationData(stationKey);
  final hasCore = _hasCoreStationData(stationKey);
  if (hasCore) return StationCompletionValidation.complete(stationKey);
  if (hasAny) return StationCompletionValidation.savedButIncomplete(stationKey);
  return StationCompletionValidation.emptyOrDiscarded(stationKey);
}

bool _hasAnyMeaningfulStationData(String stationKey) {
  return _drafts.any((draft) {
    return switch (stationKey) {
      'egg' => _hasMeaningfulEggStorageData(draft) ||
          _hasMeaningfulEggQualityData(draft),
      'chicks' => _hasMeaningfulChickData(draft),
      'hatch_analysis_egg_breakouts' => _hasMeaningfulHatchData(draft),
      'setters' => _hasMeaningfulSetterData(draft),
      'hatchers' => _hasMeaningfulHatcherData(draft),
      _ => false,
    };
  });
}

bool _hasCoreStationData(String stationKey) {
  return _drafts.any((draft) {
    return switch (stationKey) {
      'egg' => _hasMeaningfulEggStorageData(draft) ||
          _hasMeaningfulEggQualityData(draft),
      'chicks' => _hasMeaningfulChickCoreData(draft),
      'hatch_analysis_egg_breakouts' => _hasMeaningfulHatchData(draft),
      'setters' => _hasMeaningfulSetterData(draft),
      'hatchers' => _hasMeaningfulHatcherData(draft),
      _ => false,
    };
  });
}

bool _hasMeaningfulEggStorageData(AuditModel draft) {
  return draft.esCo2 != null ||
      draft.esShellTemp != null ||
      draft.esTurningTimes != null ||
      _hasMeaningfulJsonValue(draft.esEstReadingsJson) ||
      _hasMeaningfulJsonValue(draft.esEstPhotosJson) ||
      _hasMeaningfulJsonValue(draft.esUvTrays) ||
      _hasText(draft.esTraySpacing) ||
      _hasText(draft.esCoolerProximity) ||
      _hasText(draft.esWallProximity) ||
      draft.esCondensation != null ||
      _hasText(draft.notes);
}

bool _hasMeaningfulChickCoreData(AuditModel draft) {
  return _hasMeaningfulPasgarData(draft) || _hasMeaningfulChickWeightData(draft);
}

bool _hasMeaningfulChickData(AuditModel draft) {
  return _hasMeaningfulChickCoreData(draft) ||
      draft.chaCo2 != null ||
      draft.chaPm10 != null ||
      draft.chaPm25 != null ||
      draft.chaAirVelocitySpot1 != null ||
      draft.chaAirVelocitySpot2 != null ||
      draft.chaAirVelocitySpot3 != null ||
      draft.chaAirInlet != null ||
      draft.chaAirOutlet != null ||
      draft.chaNoiseLevel != null ||
      _hasMeaningfulJsonValue(draft.cvtReadingsJson) ||
      _hasMeaningfulJsonValue(draft.cvtPhotosJson) ||
      _hasMeaningfulPmData(draft) ||
      _hasMeaningfulJsonValue(draft.culledChicksAnalysisJson);
}

bool _hasMeaningfulPasgarData(AuditModel draft) {
  return (draft.pasgarSampleSize ?? 0) > 0 ||
      draft.pasgarReflexes != null ||
      draft.pasgarBeak != null ||
      draft.pasgarNavel != null ||
      draft.pasgarBelly != null ||
      draft.pasgarLeg != null ||
      draft.pasgarFeatherDev != null ||
      draft.pasgarFinalScore != null;
}

bool _hasMeaningfulChickWeightData(AuditModel draft) {
  return (draft.chickSampleSize ?? 0) > 0 ||
      _hasMeaningfulWeightList(draft.chickWeights) ||
      _hasMeaningfulJsonValue(draft.yfbmEntries) ||
      draft.yfbmAvgPct != null ||
      draft.yfbmCvPct != null;
}

bool _hasMeaningfulPmData(AuditModel draft) {
  return (draft.pmSampleSize ?? 0) > 0 ||
      _hasText(draft.pmCollectionPoint) ||
      _hasMeaningfulJsonValue(draft.pmOtherLesionsJson) ||
      _hasMeaningfulJsonValue(draft.pmPhotosJson);
}

bool _hasMeaningfulHatchData(AuditModel draft) {
  return (draft.haTotalEggsSet ?? 0) > 0 ||
      (draft.haHatched ?? 0) > 0 ||
      (draft.haCulled ?? 0) > 0 ||
      (draft.haDead ?? 0) > 0 ||
      (draft.haPipped ?? 0) > 0 ||
      (draft.haInfertileClear ?? 0) > 0 ||
      (draft.haEarlyDead ?? 0) > 0 ||
      (draft.haMidDead ?? 0) > 0 ||
      (draft.haLateDead ?? 0) > 0 ||
      _hasMeaningfulBreakoutSamples(draft.ebTrayBreakoutJson);
}

bool _hasMeaningfulBreakoutSamples(String? source) {
  return _decodedMaps(source).any((sample) {
    final counts = sample['counts'];
    if (counts is Map) {
      return counts.values.any((value) => (_asInt(value) ?? 0) > 0);
    }
    return false;
  });
}

bool _hasMeaningfulSetterData(AuditModel draft) {
  return _hasMeaningfulMachineId(draft.soSetterId, _context?.setterId, 'S') ||
      draft.soCo2 != null ||
      draft.soTurningAngle != null ||
      draft.soSetpointF != null ||
      draft.soActualF != null ||
      draft.soSetpointRh != null ||
      draft.soActualRh != null ||
      _hasMeaningfulSetterEstSamples(draft.soEstSamplesJson);
}

bool _hasMeaningfulSetterEstSamples(String? source) {
  return _decodedMaps(source).any((sample) {
    return _hasMeaningfulJsonValue(sample['estReadings']) ||
        _hasMeaningfulJsonValue(sample['estPhotos']) ||
        sample['estAvg'] != null ||
        sample['estCv'] != null ||
        (_asInt(sample['incubationAge']) != null &&
            _asInt(sample['incubationAge']) != 1) ||
        (_asInt(sample['incubationHours']) ?? 0) > 0;
  });
}

bool _hasMeaningfulHatcherData(AuditModel draft) {
  return _hasMeaningfulMachineId(draft.hoHatcherId, _context?.hatcherId, 'H') ||
      draft.hoCo2 != null ||
      draft.hoSetpointF != null ||
      draft.hoSetpointRh != null ||
      _hasMeaningfulJsonValue(draft.hoCvtReadings) ||
      _hasMeaningfulJsonValue(draft.hoCvtPhotos) ||
      draft.hoCvtAvg != null ||
      draft.hoCvtCv != null ||
      draft.hoChickPanting == true ||
      _hasText(draft.hoMeconium) ||
      (draft.hoIncubationAge != null && draft.hoIncubationAge != 18) ||
      (draft.hoIncubationHours ?? 0) > 0;
}

bool _hasMeaningfulMachineId(String? value, String? contextValue, String prefix) {
  final trimmed = _blankToNull(value);
  if (trimmed == null) return false;
  if (trimmed == prefix) return false;
  if (contextValue != null && trimmed == contextValue.trim()) return false;
  return true;
}

bool _hasMeaningfulJsonValue(Object? value) {
  if (value == null) return false;
  if (value is Map) return value.isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return decoded.isNotEmpty;
      if (decoded is Iterable) return decoded.isNotEmpty;
    } catch (_) {
      return true;
    }
    return true;
  }
  return true;
}
```

- [ ] **Step 5: Filter blank/default-only non-Egg panel rows**

In `_saveSamplesInternal`, replace the loop that saves every `scopedPanelSavePairs` entry with a table-level meaningful filter:

```dart
final meaningfulScopedPanelSavePairs = [
  for (final pair in scopedPanelSavePairs)
    if (_hasMeaningfulPanelData(pair.draft)) pair,
];
final discardedScopedPanelSavePairs = [
  for (final pair in scopedPanelSavePairs)
    if (!_hasMeaningfulPanelData(pair.draft)) pair,
];
```

Then save `meaningfulScopedPanelSavePairs` instead of `scopedPanelSavePairs`, and add cleanup for discarded tables:

```dart
for (final pair in meaningfulScopedPanelSavePairs) {
  await _savePanelTablesForSample(
    pair.draft,
    pair.sample,
    skipTables: pair.draft.auditType == 'Egg'
        ? {
            'egg_storage',
            if (!_hasMeaningfulEggQualityData(pair.draft)) 'egg_quality',
          }
        : const <String>{},
  );
}
await _deleteDiscardedPanelRows(discardedScopedPanelSavePairs);
await _pruneStalePanelHierarchyRows(meaningfulScopedPanelSavePairs);
```

Add the helpers:

```dart
bool _hasMeaningfulPanelData(AuditModel draft) {
  return switch (draft.auditType) {
    'Egg' => _hasMeaningfulEggStorageData(draft) ||
        _hasMeaningfulEggQualityData(draft),
    'Chicks' => _hasMeaningfulChickData(draft),
    'Hatch Analysis & Egg Breakouts' => _hasMeaningfulHatchData(draft),
    'Setters' => _hasMeaningfulSetterData(draft),
    'Hatchers' => _hasMeaningfulHatcherData(draft),
    _ => true,
  };
}

Future<void> _deleteDiscardedPanelRows(List<_PanelSavePair> pairs) async {
  if (pairs.isEmpty) return;
  final bySessionAndTable = <String, ({String tableName, String sessionId})>{};
  for (final pair in pairs) {
    final sessionId = pair.sample.auditSessionId;
    if (sessionId.isEmpty) continue;
    for (final tableName in _panelTablesForDraft(pair.draft)) {
      if (tableName == 'egg_storage' || tableName == 'egg_quality') continue;
      bySessionAndTable['$sessionId::$tableName'] = (
        tableName: tableName,
        sessionId: sessionId,
      );
    }
  }
  for (final entry in bySessionAndTable.values) {
    await _panelSampleRepository.deleteRowsBySessionId(
      entry.tableName,
      entry.sessionId,
    );
  }
}
```

- [ ] **Step 6: Run provider tests and commit**

Run:

```bash
flutter test test/features/audits/audit_provider_save_result_test.dart
```

Expected: all tests in the file pass.

Commit:

```bash
git add lib/features/audits/models/station_completion_validation.dart lib/features/audits/providers/audit_provider.dart test/features/audits/audit_provider_save_result_test.dart
git commit -m "Add station completion validation rules"
```

---

### Task 2: Session Exit Navigation Uses Completion Validation

**Files:**
- Modify: `lib/features/audits/screens/audit_session_screen.dart`
- Modify: `lib/features/audits/providers/audit_session_provider.dart`
- Test: `test/features/audits/audit_session_provider_test.dart`
- Test: `test/features/audits/audit_session_navigation_test.dart`

- [ ] **Step 1: Add provider progress-removal test**

Append to the progress group in `test/features/audits/audit_session_provider_test.dart`:

```dart
test('removeCurrentStationCompletion removes station and reopens session', () async {
  final completed = AuditSessionModel.fromMap(makeAuditSessionRow(
    selectedStationKeys: const ['egg', 'chicks'],
    stationsCompleted: const ['egg', 'chicks'],
    status: 'completed',
    completedAt: DateTime(2026, 1, 1),
  ));
  final updated = AuditSessionModel.fromMap(makeAuditSessionRow(
    id: completed.id,
    selectedStationKeys: const ['egg', 'chicks'],
    stationsCompleted: const ['egg'],
    status: 'in_progress',
    completedAt: null,
  ));
  when(() => mockRepo.updateSessionProgress(completed.id, const ['egg']))
      .thenAnswer((_) async {});
  var getSessionCall = 0;
  when(() => mockRepo.getSessionById(completed.id)).thenAnswer((_) async {
    getSessionCall++;
    return getSessionCall == 1 ? completed : updated;
  });
  when(() => mockSupabase.syncAuditSession(any())).thenAnswer((_) async {});

  await provider.resumeSession(completed.id, initialStationIndex: 1);
  provider.stationTransitionComplete();

  await provider.removeCurrentStationCompletion();

  expect(provider.stationsCompleted, ['egg']);
  expect(provider.isSessionActive, isTrue);
  verify(() => mockRepo.updateSessionProgress(completed.id, const ['egg']))
      .called(1);
});
```

- [ ] **Step 2: Implement `removeCurrentStationCompletion`**

Add this method to `AuditSessionProvider` near `updateProgress`:

```dart
Future<void> removeCurrentStationCompletion() async {
  if (_currentSession == null) return;
  if (_currentStationIndex < 0 || _currentStationIndex >= stationKeys.length) {
    return;
  }
  final stationKey = stationKeys[_currentStationIndex];
  if (!stationsCompleted.contains(stationKey)) return;
  final nextCompleted = stationsCompleted
      .where((completedKey) => completedKey != stationKey)
      .toList(growable: false);
  await updateProgress(nextCompleted);
}
```

- [ ] **Step 3: Run provider test and confirm it passes**

Run:

```bash
flutter test test/features/audits/audit_session_provider_test.dart
```

Expected: pass.

- [ ] **Step 4: Add incomplete navigation widget tests**

In `test/features/audits/audit_session_navigation_test.dart`, add the following widget test. It starts with Egg/Chicks selected, taps `Next Station` on an untouched Egg station, confirms the dialog, and verifies `markStationCompleted` is not called while navigation proceeds.

```dart
testWidgets(
  'incomplete station can continue without marking completed',
  (tester) async {
    final repository = MockAuditSessionRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final panelRepository = MockPanelSampleRepository();
    final provider = AuditSessionProvider(
      repository: repository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    final session = AuditSessionModel.fromMap(
      makeAuditSessionRow(
        id: 'session-incomplete',
        selectedStationKeys: ['egg', 'chicks'],
        stationsCompleted: const [],
      ),
    );

    when(() => repository.insertSession(any())).thenAnswer((_) async {});
    when(() => repository.getSessionById(session.id))
        .thenAnswer((_) async => session);
    when(() => repository.markStationCompleted(any(), any()))
        .thenAnswer((_) async {});
    when(() => repository.updateSessionProgress(any(), any()))
        .thenAnswer((_) async {});
    when(() => activityLog.log(any(), any(),
            entityType: any(named: 'entityType'),
            entityId: any(named: 'entityId'),
            details: any(named: 'details')))
        .thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});
    when(() => panelRepository.savePanelWithSamples(
          panel: any(named: 'panel'),
          samples: any(named: 'samples'),
        )).thenAnswer((_) async {});
    when(() => panelRepository.getRowsBySessionId(any(), session.id))
        .thenAnswer((_) async => []);
    when(() => panelRepository.deleteRowsBySessionId(any(), any()))
        .thenAnswer((_) async {});
    when(() => panelRepository.deleteHierarchyRowsBySessionId(any(), any()))
        .thenAnswer((_) async {});
    when(() => panelRepository.deleteRowsBySessionIdForSampleIds(
          any(),
          any(),
          any(),
        )).thenAnswer((_) async {});
    when(() => panelRepository.deleteHierarchyRowsBySessionIdExcept(
          any(),
          any(),
          any(),
          keepHierarchyRows: any(named: 'keepHierarchyRows'),
        )).thenAnswer((_) async {});

    await provider.resumeSession(session.id);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
        ],
        child: MaterialApp(
          home: AuditSessionScreen(panelSampleRepository: panelRepository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('audit-session-next-action')));
    await tester.pumpAndSettle();

    expect(find.text('Continue without completing?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(provider.currentStationIndex, 1);
    verifyNever(() => repository.markStationCompleted(session.id, 'egg'));
  },
);

testWidgets(
  'final incomplete station stays in progress after confirmation',
  (tester) async {
    final repository = MockAuditSessionRepository();
    final activityLog = MockActivityLogRepository();
    final supabase = MockSupabaseService();
    final panelRepository = MockPanelSampleRepository();
    final provider = AuditSessionProvider(
      repository: repository,
      activityLogRepository: activityLog,
      supabaseService: supabase,
    );

    final session = AuditSessionModel.fromMap(
      makeAuditSessionRow(
        id: 'session-final-incomplete',
        selectedStationKeys: ['egg'],
        stationsCompleted: const [],
        status: 'in_progress',
      ),
    );

    when(() => repository.getSessionById(session.id))
        .thenAnswer((_) async => session);
    when(() => repository.markStationCompleted(any(), any()))
        .thenAnswer((_) async {});
    when(() => repository.updateSessionProgress(any(), any()))
        .thenAnswer((_) async {});
    when(() => activityLog.log(any(), any(),
            entityType: any(named: 'entityType'),
            entityId: any(named: 'entityId'),
            details: any(named: 'details')))
        .thenAnswer((_) async {});
    when(() => supabase.syncAuditSession(any())).thenAnswer((_) async {});
    when(() => panelRepository.savePanelWithSamples(
          panel: any(named: 'panel'),
          samples: any(named: 'samples'),
        )).thenAnswer((_) async {});
    when(() => panelRepository.getRowsBySessionId(any(), session.id))
        .thenAnswer((_) async => []);
    when(() => panelRepository.deleteRowsBySessionId(any(), any()))
        .thenAnswer((_) async {});
    when(() => panelRepository.deleteHierarchyRowsBySessionId(any(), any()))
        .thenAnswer((_) async {});
    when(() => panelRepository.deleteRowsBySessionIdForSampleIds(
          any(),
          any(),
          any(),
        )).thenAnswer((_) async {});
    when(() => panelRepository.deleteHierarchyRowsBySessionIdExcept(
          any(),
          any(),
          any(),
          keepHierarchyRows: any(named: 'keepHierarchyRows'),
        )).thenAnswer((_) async {});

    await provider.resumeSession(session.id);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: supabase),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
          ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
        ],
        child: MaterialApp(
          home: AuditSessionScreen(panelSampleRepository: panelRepository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('audit-session-next-action')));
    await tester.pumpAndSettle();

    expect(find.text('Continue without completing?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(provider.currentSession?.status, 'in_progress');
    verifyNever(() => repository.markStationCompleted(session.id, 'egg'));
    verifyNever(() => repository.updateSessionProgress(session.id, any()));
  },
);
```

- [ ] **Step 5: Run navigation test and confirm it fails**

Run:

```bash
flutter test test/features/audits/audit_session_navigation_test.dart
```

Expected: fails because `_confirmStationExit` returns only a boolean, always marks current station complete in `_handleNextOrSave`, and cannot keep a final incomplete station in progress after confirmation.

- [ ] **Step 6: Refactor session exit result**

In `audit_session_screen.dart`, import the validation model:

```dart
import '../models/station_completion_validation.dart';
```

Add local enums/classes above `_AuditSessionScreenState`:

```dart
enum _StationExitIntent { back, jump, forward, finalSave }

class _StationExitDecision {
  final StationCompletionValidation validation;
  final bool confirmed;

  const _StationExitDecision({
    required this.validation,
    required this.confirmed,
  });

  bool get canMove => confirmed && validation.canNavigate;
}
```

Replace `_handleBackNavigation`, `_handleNextOrSave`, `_handlePreviousStation`, and `_handleStationTap` with these intent-aware versions:

```dart
Future<void> _handleBackNavigation(BuildContext context) async {
  final decision = await _confirmStationExit(intent: _StationExitIntent.back);
  if (!decision.canMove) return;
  if (!mounted) return;

  final sessionProvider = this.context.read<AuditSessionProvider>();
  final sessionId = sessionProvider.currentSession?.id;
  if (!decision.validation.shouldMarkCompleted &&
      sessionProvider.isStationCompleted) {
    await sessionProvider.removeCurrentStationCompletion();
  }
  Navigator.of(this.context).pop();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (sessionProvider.currentSession?.id == sessionId) {
      sessionProvider.clearCurrentSession();
    }
  });
}

Future<void> _handleNextOrSave(AuditSessionProvider provider) async {
  if (_isSavingStation) return;
  final wasCompleted = provider.isSessionComplete;
  final isLast =
      provider.currentStationIndex == provider.stationKeys.length - 1;
  final decision = await _confirmStationExit(
    intent: isLast ? _StationExitIntent.finalSave : _StationExitIntent.forward,
  );
  if (!decision.canMove) return;

  if (decision.validation.shouldMarkCompleted) {
    await provider.markCurrentStationCompleted();
  } else if (provider.isStationCompleted) {
    await provider.removeCurrentStationCompletion();
  }

  if (!isLast) {
    provider.goToNextStation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      provider.stationTransitionComplete();
    });
    return;
  }

  if (!decision.validation.shouldMarkCompleted) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Station saved without completing the visit.'),
      ),
    );
    return;
  }

  if (wasCompleted) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Station saved.')));
  } else {
    await provider.completeSession();
    if (!mounted) return;
    setState(() => _showSavedAnimation = true);
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    Navigator.of(context).popUntil(auditSessionCompletionRoutePredicate);
  }
}

Future<void> _handlePreviousStation(AuditSessionProvider provider) async {
  final decision = await _confirmStationExit(intent: _StationExitIntent.back);
  if (!decision.canMove) return;

  if (!decision.validation.shouldMarkCompleted && provider.isStationCompleted) {
    await provider.removeCurrentStationCompletion();
  }

  provider.goToPreviousStation();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    provider.stationTransitionComplete();
  });
}

Future<void> _handleStationTap(
  AuditSessionProvider provider,
  int stationIndex,
  List<String> stationKeys,
) async {
  if (stationIndex == provider.currentStationIndex) return;

  final decision = await _confirmStationExit(intent: _StationExitIntent.jump);
  if (!decision.canMove) return;

  if (!decision.validation.shouldMarkCompleted && provider.isStationCompleted) {
    await provider.removeCurrentStationCompletion();
  }

  provider.goToStation(stationIndex);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    provider.stationTransitionComplete();
  });
}
```

- [ ] **Step 7: Replace `_confirmStationExit`**

Replace `_confirmStationExit` with:

```dart
Future<_StationExitDecision> _confirmStationExit({
  required _StationExitIntent intent,
}) async {
  final stationAuditProvider = _currentStationProvider;
  final sessionProvider = context.read<AuditSessionProvider>();
  if (stationAuditProvider == null || sessionProvider.currentSession == null) {
    return _StationExitDecision(
      validation: StationCompletionValidation.complete(''),
      confirmed: true,
    );
  }

  if (!mounted) {
    return _StationExitDecision(
      validation: StationCompletionValidation.failed(''),
      confirmed: false,
    );
  }

  setState(() => _isSavingStation = true);
  StationCompletionValidation validation;
  try {
    final prepared = await _prepareCurrentStationForExit();
    if (!prepared) {
      validation = StationCompletionValidation.failed(
        sessionProvider.stationKeys[sessionProvider.currentStationIndex],
      );
    } else {
      final saved = await _saveCurrentStation();
      final stationKey =
          sessionProvider.stationKeys[sessionProvider.currentStationIndex];
      validation = saved
          ? stationAuditProvider.validateStationCompletion(stationKey)
          : StationCompletionValidation.failed(stationKey);
    }
  } catch (_) {
    final stationKey =
        sessionProvider.stationKeys[sessionProvider.currentStationIndex];
    validation = StationCompletionValidation.failed(stationKey);
  } finally {
    if (mounted) setState(() => _isSavingStation = false);
  }

  if (!mounted) {
    return _StationExitDecision(validation: validation, confirmed: false);
  }

  if (validation.status == StationCompletionStatus.failed) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(validation.message)),
    );
    return _StationExitDecision(validation: validation, confirmed: false);
  }

  if (validation.needsIncompleteConfirmation) {
    final confirmed = await _confirmIncompleteStation(validation, intent);
    return _StationExitDecision(
      validation: validation,
      confirmed: confirmed,
    );
  }

  return _StationExitDecision(validation: validation, confirmed: true);
}
```

Add the dialog helper:

```dart
Future<bool> _confirmIncompleteStation(
  StationCompletionValidation validation,
  _StationExitIntent intent,
) async {
  final body = switch (intent) {
    _StationExitIntent.back =>
      '${validation.message}\n\nLeave this station without completing it?',
    _StationExitIntent.jump =>
      '${validation.message}\n\nMove to another station without completing this one?',
    _StationExitIntent.forward || _StationExitIntent.finalSave =>
      '${validation.message}\n\nContinue without completing this station?',
  };
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Continue without completing?'),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      );
    },
  );
  return result == true;
}
```

- [ ] **Step 8: Run navigation tests and commit**

Run:

```bash
flutter test test/features/audits/audit_session_provider_test.dart test/features/audits/audit_session_navigation_test.dart
```

Expected: both files pass.

Commit:

```bash
git add lib/features/audits/screens/audit_session_screen.dart lib/features/audits/providers/audit_session_provider.dart test/features/audits/audit_session_provider_test.dart test/features/audits/audit_session_navigation_test.dart
git commit -m "Validate station completion before progress updates"
```

---

### Task 3: Hatcher Multi-Machine Resume And Hatcher Settings UI

**Files:**
- Modify: `lib/features/audits/screens/hatcher_optimizing_screen.dart`
- Modify: `lib/features/audits/screens/audit_session_screen.dart`
- Test: `test/features/audits/incubation_age_hours_test.dart`

- [ ] **Step 1: Add failing Hatcher resume and settings UI tests**

In `test/features/audits/incubation_age_hours_test.dart`, add:

```dart
testWidgets('Hatcher reopens multiple machine rows as machine chips', (tester) async {
  final now = DateTime(2026, 4, 27);
  final first = AuditModel(
    id: 'hatcher-row-1',
    auditType: 'Hatchers',
    customerId: 'customer-1',
    flockId: 'flock-1',
    date: now,
    hatchNumber: 1,
    status: 'active',
    createdBy: 'auditor-1',
    createdAt: now,
    updatedAt: now,
    hatcherId: 'H5',
    hoHatcherId: 'H5',
    hoSetpointF: 98.8,
    hoIncubationAge: 18,
    hoIncubationHours: 4,
  );
  final second = AuditModel(
    id: 'hatcher-row-2',
    auditType: 'Hatchers',
    customerId: 'customer-1',
    flockId: 'flock-1',
    date: now,
    hatchNumber: 2,
    status: 'active',
    createdBy: 'auditor-1',
    createdAt: now,
    updatedAt: now,
    hatcherId: 'H7',
    hoHatcherId: 'H7',
    hoSetpointF: 99.2,
    hoIncubationAge: 19,
    hoIncubationHours: 9,
  );
  final provider = AuditProvider(autosaveEnabled: false);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuditProvider>.value(value: provider),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
        ),
      ],
      child: MaterialApp(
        home: HatcherOptimizingScreen(
          context: hatcherContext(hatcherId: null),
          initialAudit: first,
          initialAudits: [first, second],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(provider.sampleCount, 2);
  expect(find.widgetWithText(ChoiceChip, 'H5'), findsOneWidget);
  expect(find.widgetWithText(ChoiceChip, 'H7'), findsOneWidget);

  await tester.tap(find.widgetWithText(ChoiceChip, 'H7'));
  await tester.pump();

  expect(
    tester.widget<AuditNumericField>(
      find.byKey(const ValueKey('hatcher-incubation-age-field')),
    ).controller.text,
    '19',
  );
  expect(
    tester.widget<AuditNumericField>(
      find.byKey(const ValueKey('hatcher-incubation-hours-field')),
    ).controller.text,
    '9',
  );
});

testWidgets('Hatcher settings use numeric fields instead of sliders', (tester) async {
  final provider = await pumpHatcherScreen(tester);

  expect(find.byKey(const ValueKey('hatcher-incubation-hours-slider')), findsNothing);
  expect(find.byKey(const ValueKey('hatcher-incubation-age-field')), findsOneWidget);
  expect(find.byKey(const ValueKey('hatcher-incubation-hours-field')), findsOneWidget);

  await tester.enterText(
    find.byKey(const ValueKey('hatcher-incubation-age-field')),
    '20',
  );
  await tester.enterText(
    find.byKey(const ValueKey('hatcher-incubation-hours-field')),
    '6',
  );
  await tester.pump();

  expect(provider.activeDraft.hoIncubationAge, 20);
  expect(provider.activeDraft.hoIncubationHours, 6);
});
```

Add the import:

```dart
import 'package:hatchaudit/data/models/audit_model.dart';
```

- [ ] **Step 2: Run these tests and confirm they fail**

Run:

```bash
flutter test test/features/audits/incubation_age_hours_test.dart --plain-name "Hatcher"
```

Expected: fails because `initialAudits`, Hatcher incubation field keys, and slider removal are not implemented.

- [ ] **Step 3: Add Hatcher constructor fields and provider initialization**

In `HatcherOptimizingScreen`, add imports and fields:

```dart
import '../../../data/models/station_sample_model.dart';
```

```dart
final List<AuditModel> initialAudits;
final List<StationSampleModel> initialStationSamples;
```

Add constructor defaults:

```dart
this.initialAudits = const [],
this.initialStationSamples = const [],
```

In `auditProvider.initialize`, pass:

```dart
existingAudits: widget.initialAudits,
existingStationSamples: widget.initialStationSamples,
readOnly: widget.context.sessionId == null ? null : false,
```

- [ ] **Step 4: Pass hydrated Hatcher rows from station frame**

In `audit_session_screen.dart`, change the Hatcher screen build case:

```dart
case 'hatchers':
  return HatcherOptimizingScreen(
    context: widget.context,
    initialAudit: initialAudit,
    initialAudits: initialData.stationAudits,
    initialStationSamples: initialData.stationSamples,
  );
```

- [ ] **Step 5: Replace Hatcher incubation sliders with fields**

In `_buildHatcherSettingsCard`, replace both `Text` + `Slider` blocks with this second row:

```dart
const SizedBox(height: 12),
Row(
  children: [
    Expanded(
      child: AuditNumericField(
        key: const ValueKey('hatcher-incubation-age-field'),
        controller: _incubationAgeController,
        enabled: !provider.isReadOnly,
        decoration: const InputDecoration(
          labelText: 'Incubation Age (days)',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) {
          final parsed = int.tryParse(value);
          final age = parsed == null ? null : parsed.clamp(18, 21);
          provider.updateField('hoIncubationAge', age);
        },
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: AuditNumericField(
        key: const ValueKey('hatcher-incubation-hours-field'),
        controller: _incubationHoursController,
        enabled: !provider.isReadOnly,
        decoration: const InputDecoration(
          labelText: 'Incubation Hours',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) {
          final parsed = int.tryParse(value);
          final hours = parsed == null ? null : parsed.clamp(0, 23);
          provider.updateField('hoIncubationHours', hours);
        },
      ),
    ),
  ],
),
```

- [ ] **Step 6: Run Hatcher tests and commit**

Run:

```bash
flutter test test/features/audits/incubation_age_hours_test.dart --plain-name "Hatcher"
```

Expected: pass.

Commit:

```bash
git add lib/features/audits/screens/hatcher_optimizing_screen.dart lib/features/audits/screens/audit_session_screen.dart test/features/audits/incubation_age_hours_test.dart
git commit -m "Restore multi-hatcher rows in station resume"
```

---

### Task 4: Hatch Analysis Explicit House, Machine, And Tray Scope Rules

**Files:**
- Modify: `lib/features/audits/screens/hatch_analysis_screen.dart`
- Modify: `lib/features/audits/providers/audit_provider.dart`
- Test: `test/features/audits/hatch_analysis_screen_breakout_test.dart`

- [ ] **Step 1: Add failing Hatch Analysis scope tests**

Add these widget tests to `test/features/audits/hatch_analysis_screen_breakout_test.dart` near the existing residue hierarchy tests:

```dart
testWidgets('machine scope from pool does not create house scope', (tester) async {
  final provider = await pumpScreen(
    tester,
    breakoutType: EggBreakoutType.residueHatchDay,
    benchmarkLookup: mockBenchmarkLookup(),
  );

  await tapVisibleKey(tester, const ValueKey('residue-add-batch'));
  await tester.pumpAndSettle();

  expect(find.widgetWithText(ChoiceChip, 'Pool'), findsOneWidget);
  expect(find.widgetWithText(ChoiceChip, 'H1'), findsNothing);
  expect(provider.activeDraft.houseId, isNull);
  expect(provider.activeDraft.setterId, 'S');
  expect(provider.activeDraft.hatcherId, 'H');
});

testWidgets('tray scope from pooled context stays free of house and machine hierarchy', (tester) async {
  final provider = await pumpScreen(
    tester,
    breakoutType: EggBreakoutType.residueHatchDay,
    benchmarkLookup: mockBenchmarkLookup(),
  );

  await addVisibleSample(tester);

  final samples = EggBreakoutSampleEntry.decodeList(
    provider.activeDraft.ebTrayBreakoutJson,
  );
  expect(samples.single.house, isNull);
  expect(samples.single.setter, isNull);
  expect(samples.single.hatcher, isNull);
});
```

- [ ] **Step 2: Run scope tests and confirm they fail**

Run:

```bash
flutter test test/features/audits/hatch_analysis_screen_breakout_test.dart --plain-name "scope"
```

Expected: at least the machine-from-pool test fails because `_addResidueMachine` writes `houseId` using `_residueHouseKey`, which falls back to `1`.

- [ ] **Step 3: Fix Machine scope from Pool**

In `_residueHouseKey`, stop using fallback `1` when the house is absent:

```dart
String? _residueHouseKeyOrNull(AuditModel audit) {
  return _trimmedOrNull(audit.houseId);
}

String _residueHouseKey(AuditModel audit, int index) {
  return _residueHouseKeyOrNull(audit) ?? 'pool';
}
```

Update `_residueHouseLabel` so pooled chips stay `Pool`:

```dart
String _residueHouseLabel(String raw) {
  if (raw == 'pool') return 'Pool';
  final value = _batchLabelPart(raw, 'H');
  if (value.toLowerCase().startsWith('h')) return value;
  return 'H$value';
}
```

In `_addResidueMachine`, preserve a null house when no house scope exists:

```dart
final activeHouse = _residueHouseKeyOrNull(provider.drafts[activeIndex]);
final shouldConvertActiveDraft = !_isResidueMachineDraft(
  provider.drafts[activeIndex],
);
if (!shouldConvertActiveDraft) {
  provider.addHatch();
}
final nextIndex = shouldConvertActiveDraft
    ? activeIndex
    : provider.activeHatchIndex;
provider.updateHatchField(nextIndex, 'houseId', activeHouse);
```

- [ ] **Step 4: Fix Tray hierarchy sync**

In `_persistBreakoutSamples` or the helper that writes `EggBreakoutSampleEntry`, ensure hierarchy is copied only from active scopes:

```dart
final activeHouse = _residueHouseKeyOrNull(provider.drafts[hatchIndex]);
final activeMachine = _isResidueMachineDraft(provider.drafts[hatchIndex]);
final nextSamples = [
  for (final sample in samples)
    sample.copyWith(
      house: activeHouse,
      setter: activeMachine ? provider.drafts[hatchIndex].setterId : null,
      hatcher: activeMachine ? provider.drafts[hatchIndex].hatcherId : null,
    ),
];
```

Keep Fresh Egg breakout tray samples free of machine hierarchy.

- [ ] **Step 5: Run Hatch Analysis tests and commit**

Run:

```bash
flutter test test/features/audits/hatch_analysis_screen_breakout_test.dart
```

Expected: pass.

Commit:

```bash
git add lib/features/audits/screens/hatch_analysis_screen.dart lib/features/audits/providers/audit_provider.dart test/features/audits/hatch_analysis_screen_breakout_test.dart
git commit -m "Keep hatch analysis scopes explicit"
```

---

### Task 5: Setters Incubation-Age Selector UI Cleanup

**Files:**
- Modify: `lib/features/audits/screens/setter_optimizing_screen.dart`
- Test: `test/features/audits/incubation_age_hours_test.dart`

- [ ] **Step 1: Update failing Setters UI expectations**

In `test/features/audits/incubation_age_hours_test.dart`, update the existing Setters incubation sample expectations:

```dart
expect(find.text('Incubation age samples'), findsOneWidget);
expect(find.text('Incubation age'), findsNothing);
expect(find.widgetWithText(ChoiceChip, 'Pool'), findsOneWidget);
```

In the multi-sample test, replace the duplicated full-label expectation with:

```dart
expect(find.widgetWithText(ChoiceChip, 'Day 1'), findsNWidgets(2));
expect(find.text('Incubation age 1'), findsNothing);
```

In the EST readings switch test, replace chip taps:

```dart
await tester.tap(find.widgetWithText(ChoiceChip, 'Day 1').first);
await tester.pump();
expect(
  tester.widget<AuditNumericField>(frontTop).controller.text,
  '100.2',
);
await tester.tap(find.widgetWithText(ChoiceChip, 'Day 7'));
await tester.pump();
```

- [ ] **Step 2: Run Setters UI tests and confirm they fail**

Run:

```bash
flutter test test/features/audits/incubation_age_hours_test.dart --plain-name "Setter"
```

Expected: fails because the current section title is `Incubation age` and chips still use `Incubation age N`.

- [ ] **Step 3: Change chip labels and action button weight**

In `_incubationAgeScopeLabel`, use:

```dart
String _incubationAgeScopeLabel(
  List<Map<String, dynamic>> samples,
  int index,
) {
  if (samples.length == 1) return 'Pool';
  final sample = samples[index];
  final age = _clampInt(sample['incubationAge'], min: 1, max: 18);
  return 'Day $age';
}
```

In `_buildEstSampleCard`, change the title text to:

```dart
'Incubation age samples',
```

In `_buildSetterSampleActionButton`, reduce the fixed size:

```dart
style: IconButton.styleFrom(
  fixedSize: const Size(40, 40),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
),
```

- [ ] **Step 4: Run Setters tests and commit**

Run:

```bash
flutter test test/features/audits/incubation_age_hours_test.dart --plain-name "Setter"
```

Expected: pass.

Commit:

```bash
git add lib/features/audits/screens/setter_optimizing_screen.dart test/features/audits/incubation_age_hours_test.dart
git commit -m "Clean up setters incubation sample selector"
```

---

### Task 6: Living Spec And Final Verification

**Files:**
- Modify: `docs/LIVING_SPEC.md`

- [ ] **Step 1: Update Living Spec station save behavior**

In `docs/LIVING_SPEC.md`, replace these bullets:

```markdown
- Save/Next remains the final confirmation path. It retries any pending or
  failed autosave work, persists panel rows, runs remaining local side effects,
  and then allows station navigation or session completion. Intermediate
  station saves move to the next station without the large completion check
  overlay; the overlay is reserved for final selected station completion.
- Re-saving a station in an already completed visit persists the edited station
  fields and keeps the visit marked completed. Completed review mode still uses
  `Next Station` for non-final stations and reserves `Save` for the final
  selected station.
```

with:

```markdown
- Save/Next remains the station-exit path. It retries any pending or failed
  autosave work, persists meaningful panel rows, removes blank/default-only
  rows, validates the station core requirement, and then allows navigation.
  Incomplete stations prompt before navigation; when confirmed, the station can
  be skipped without adding it to `stationsCompleted`.
- Re-saving a station in an already completed visit persists the edited station
  fields and keeps the visit marked completed only while that station still
  satisfies its core completion rule. If review edits remove core data, the
  station is removed from `stationsCompleted` and the visit returns to
  `in_progress` until all selected stations are complete again.
```

- [ ] **Step 2: Update Living Spec Setters and Hatchers UI sections**

Replace the Setters EST sample bullet with:

```markdown
- EST samples are grouped by an `Incubation age samples` selector. A single
  incubation-age sample is shown as `Pool`; once multiple incubation-age samples
  exist, chips are labeled from the entered age, such as `Day 1` and `Day 12`.
  Small icon-only actions add or remove incubation-age samples. Each scope keeps
  its own incubation age numeric entry from 1 to 18 days, 0-23 hour numeric
  entry, EST readings/photos, average, and CV, so switching between
  incubation-age samples restores that sample's own EST grid. Setters does not
  expose a breed picker in the EST sample card; benchmark breed identity comes
  from the visit/session context rather than per-sample UI.
```

Replace the Hatcher settings bullet with:

```markdown
- A Hatcher settings card for the active hatcher sample, containing outlined
  numeric fields for machine temperature setpoint in Fahrenheit, RH setpoint
  percentage, incubation age from 18 to 21 days, and incubation hours from 0 to
  23 hours. These fields use the audit numeric keyboard instead of sliders.
```

- [ ] **Step 3: Add changelog entries**

Append to the existing 2026-05-23/2026-05-24 change area:

```markdown
- 2026-05-24: Added station-specific completion validation to the visit exit
  path. Incomplete stations can be skipped after confirmation without being
  marked complete, and blank/default-only station rows are removed instead of
  implying progress.
- 2026-05-24: Restored Hatcher multi-machine resume so all saved Hatcher rows
  reopen as machine-scope chips and can be edited independently.
- 2026-05-24: Kept Hatch Analysis House, Machine, and Tray scopes explicit:
  adding Machine or Tray scope no longer creates synthetic parent scope.
- 2026-05-24: Cleaned the Setters incubation-age sample selector and changed
  Hatcher incubation age/hour controls to numeric fields.
```

- [ ] **Step 4: Run focused verification**

Run:

```bash
flutter test test/features/audits/audit_provider_save_result_test.dart test/features/audits/audit_session_provider_test.dart test/features/audits/audit_session_navigation_test.dart test/features/audits/incubation_age_hours_test.dart test/features/audits/hatch_analysis_screen_breakout_test.dart
```

Expected: all files pass.

- [ ] **Step 5: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: exits with code 0.

- [ ] **Step 6: Restart the stable web preview**

Run:

```bash
make restart-web
```

Expected: Flutter web server is available at `http://127.0.0.1:57863`.

- [ ] **Step 7: Browser smoke check**

Open `http://127.0.0.1:57863/#/main` in the in-app browser and verify:

- Setters shows `Incubation age samples`, compact add/remove icons, and `Pool`/`Day N` chips.
- Hatchers shows multiple restored `H#` chips after reopening saved rows.
- Hatcher settings shows numeric fields for incubation age and hours, not sliders.
- Hatch Analysis Machine scope from pooled House keeps House as `Pool`.
- Hatch Analysis Tray scope from pooled House/Machine does not show hidden House/Setter/Hatcher entry fields.
- Skipping an incomplete station shows `Continue without completing?` and the progress circle stays incomplete after confirming.

- [ ] **Step 8: Commit docs and final verification**

Commit:

```bash
git add docs/LIVING_SPEC.md
git commit -m "Update living spec for station completion validation"
```

Then report:

- Task id: hatcher-resume-completion-validation
- Summary of changes
- Files changed
- Tests or commands run
- Risks or assumptions
