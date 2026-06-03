# Station Session Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resume same-context visit sessions, make saved stations visible/editable from station setup, and route completed visits through station screens before dashboard results.

**Architecture:** Keep `audit_sessions` as the visit workflow record and panel tables as station field truth. Add repository/provider helpers for matching sessions and updating selected station order, then extend `AuditStationSelectionScreen`, `HomeScreen`, `AuditsScreen`, and `AuditSessionScreen` routing around those helpers without changing panel schemas.

**Tech Stack:** Flutter, Provider, sqflite repositories, existing station screens, widget tests with mocktail.

---

### Task 1: Session Repository And Provider Helpers

**Files:**
- Modify: `lib/data/repositories/audit_session_repository.dart`
- Modify: `lib/features/audits/providers/audit_session_provider.dart`
- Test: `test/features/audits/audit_session_provider_test.dart`

- [ ] **Step 1: Write failing provider tests**

Add tests under `AuditSessionProvider - startSession`:

```dart
test('resumes matching in-progress session instead of creating a duplicate', () async {
  final existing = AuditSessionModel.fromMap(
    makeAuditSessionRow(
      id: 'existing-session',
      selectedStationKeys: ['egg', 'chicks'],
      stationsCompleted: ['egg'],
    ),
  );

  when(
    () => mockRepo.findInProgressSession(
      customerId: SessionTestFixtures.testCustomerId,
      flockId: SessionTestFixtures.testFlockId,
      hatcheryId: SessionTestFixtures.testHatcheryId,
      date: SessionTestFixtures.testVisitDate,
    ),
  ).thenAnswer((_) async => existing);

  await provider.startOrResumeSession(
    context: testContext.copyWith(selectedStationKeys: const ['egg', 'chicks']),
    currentUser: testUser,
  );

  expect(provider.currentSession?.id, 'existing-session');
  expect(provider.stationKeys, ['egg', 'chicks']);
  expect(provider.stationsCompleted, ['egg']);
  expect(provider.currentStationIndex, 1);
  expect(provider.isResumed, isTrue);
  verifyNever(() => mockRepo.insertSession(any()));
});

test('updates selected stations on an existing in-progress session', () async {
  final existing = AuditSessionModel.fromMap(
    makeAuditSessionRow(
      id: 'existing-session',
      selectedStationKeys: ['egg'],
      stationsCompleted: ['egg'],
    ),
  );
  final updated = existing.copyWith(
    selectedStationKeys: const ['egg', 'chicks'],
    stationsCompleted: const ['egg'],
  );

  when(
    () => mockRepo.updateSelectedStationKeys(
      'existing-session',
      const ['egg', 'chicks'],
    ),
  ).thenAnswer((_) async {});
  when(
    () => mockRepo.getSessionById('existing-session'),
  ).thenAnswer((_) async => updated);

  when(
    () => mockRepo.getSessionById(existing.id),
  ).thenAnswer((_) async => existing);

  await provider.resumeSession(existing.id, initialStationIndex: 0);
  await provider.updateSelectedStationKeys(const ['egg', 'chicks']);

  expect(provider.stationKeys, ['egg', 'chicks']);
  expect(provider.stationsCompleted, ['egg']);
});
```

Add this helper to the test file near `testContext`:

```dart
extension _ContextCopy on AuditSessionContext {
  AuditSessionContext copyWith({List<String>? selectedStationKeys}) {
    return AuditSessionContext(
      customerId: customerId,
      hatcheryId: hatcheryId,
      flockId: flockId,
      date: date,
      breed: breed,
      flockAgeWeeks: flockAgeWeeks,
      selectedStationKeys: selectedStationKeys ?? this.selectedStationKeys,
    );
  }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
flutter test test/features/audits/audit_session_provider_test.dart --plain-name "resumes matching in-progress session instead of creating a duplicate"
flutter test test/features/audits/audit_session_provider_test.dart --plain-name "updates selected stations on an existing in-progress session"
```

Expected: fail because `findInProgressSession`, `startOrResumeSession`, `loadMatchingSessionForStationSelection`, and `updateSelectedStationKeys` do not exist.

- [ ] **Step 3: Add repository helpers**

In `AuditSessionRepository`, add:

```dart
Future<AuditSessionModel?> findInProgressSession({
  required String customerId,
  required String flockId,
  required String hatcheryId,
  required DateTime date,
}) async {
  final db = await _dbHelper.db;
  final day = date.toIso8601String().split('T').first;
  final result = await db.query(
    'audit_sessions',
    where:
        'customerId = ? AND flockId = ? AND hatcheryId = ? AND status = ? AND substr(date, 1, 10) = ?',
    whereArgs: [customerId, flockId, hatcheryId, 'in_progress', day],
    orderBy: 'updatedAt DESC, createdAt DESC',
    limit: 1,
  );
  if (result.isEmpty) return null;
  return AuditSessionModel.fromMap(result.first);
}

Future<void> updateSelectedStationKeys(
  String sessionId,
  List<String> selectedStationKeys,
) async {
  final db = await _dbHelper.db;
  final current = await getSessionById(sessionId);
  if (current == null) return;
  final selected = normalizeStationKeys(selectedStationKeys);
  final completed = current.stationsCompleted
      .where((stationKey) => selected.contains(stationKey))
      .toList(growable: false);
  final isComplete = _isComplete(completed, selected);
  await db.update(
    'audit_sessions',
    {
      'selectedStationKeys': jsonEncode(selected),
      'stationsCompleted': completed.isEmpty ? null : jsonEncode(completed),
      'updatedAt': DateTime.now().toIso8601String(),
      'status': isComplete ? 'completed' : 'in_progress',
      'completedAt': isComplete ? DateTime.now().toIso8601String() : null,
    },
    where: 'id = ?',
    whereArgs: [sessionId],
  );
}
```

- [ ] **Step 4: Add provider helpers**

In `AuditSessionProvider`, add:

```dart
Future<void> startOrResumeSession({
  required AuditSessionContext context,
  UserModel? currentUser,
}) async {
  final operation = ++_loadOperation;
  _currentUser = currentUser;
  _isLoading = true;
  _error = null;
  _notifyListeners();

  try {
    final existing = await _repository.findInProgressSession(
      customerId: context.customerId,
      flockId: context.flockId,
      hatcheryId: context.hatcheryId,
      date: context.date,
    );
    if (!_isCurrentLoad(operation)) return;
    if (existing != null) {
      _currentSession = existing;
      _isResumed = true;
      _setResumeStationIndex(existing);
      await _safeLogActivity('session_resume', existing.id);
      return;
    }
  } catch (e) {
    if (!_isCurrentLoad(operation)) return;
    _error = 'Failed to resume visit session';
    safeDebugLog('Error finding session to resume', error: e);
    return;
  } finally {
    if (_isCurrentLoad(operation)) {
      _isLoading = false;
      _notifyListeners();
    }
  }

  await startSession(context: context, currentUser: currentUser);
}

Future<bool> loadMatchingSessionForStationSelection({
  required AuditSessionContext context,
  UserModel? currentUser,
}) async {
  final operation = ++_loadOperation;
  _currentUser = currentUser;
  _selectedStationKeys = normalizeStationKeys(context.selectedStationKeys);
  _isLoading = true;
  _error = null;
  _notifyListeners();

  try {
    final existing = await _repository.findInProgressSession(
      customerId: context.customerId,
      flockId: context.flockId,
      hatcheryId: context.hatcheryId,
      date: context.date,
    );
    if (!_isCurrentLoad(operation)) return false;
    if (existing == null) return false;
    _currentSession = existing;
    _selectedStationKeys = normalizeStationKeys(existing.selectedStationKeys);
    _isResumed = true;
    _setResumeStationIndex(existing, initialStationIndex: 0);
    await _safeLogActivity('session_resume', existing.id);
    return true;
  } catch (e) {
    if (_isCurrentLoad(operation)) {
      _error = 'Failed to resume visit session';
      safeDebugLog('Error finding session to resume', error: e);
    }
    return false;
  } finally {
    if (_isCurrentLoad(operation)) {
      _isLoading = false;
      _notifyListeners();
    }
  }
}

Future<void> updateSelectedStationKeys(List<String> selectedStationKeys) async {
  if (_currentSession == null) return;
  try {
    await _repository.updateSelectedStationKeys(
      _currentSession!.id,
      selectedStationKeys,
    );
    final updated = await _repository.getSessionById(_currentSession!.id);
    if (updated != null) {
      _currentSession = updated;
      _selectedStationKeys = normalizeStationKeys(updated.selectedStationKeys);
      _setResumeStationIndex(updated);
    }
    unawaited(_supabaseService.syncAuditSession(_currentSession!.toMap()));
    _notifyListeners();
  } catch (e) {
    _error = 'Failed to update visit stations';
    safeDebugLog('Error updating selected station keys', error: e);
  }
}

void _setResumeStationIndex(AuditSessionModel session, {int? initialStationIndex}) {
  final keys = normalizeStationKeys(session.selectedStationKeys);
  if (initialStationIndex != null && initialStationIndex >= 0 && initialStationIndex < keys.length) {
    _currentStationIndex = initialStationIndex;
    _targetStationIndex = initialStationIndex;
    return;
  }
  final completed = session.stationsCompleted;
  if (completed.length >= keys.length) {
    _currentStationIndex = 0;
  } else {
    _currentStationIndex = keys.indexWhere((stationKey) => !completed.contains(stationKey));
    if (_currentStationIndex == -1) _currentStationIndex = 0;
  }
  _targetStationIndex = _currentStationIndex;
}
```

Update `resumeSession` signature to:

```dart
Future<void> resumeSession(String sessionId, {int? initialStationIndex}) async
```

Replace its existing index-selection block with:

```dart
_setResumeStationIndex(session, initialStationIndex: initialStationIndex);
```

- [ ] **Step 5: Run provider tests**

Run:

```bash
flutter test test/features/audits/audit_session_provider_test.dart
```

Expected: all provider tests pass after updating mocks for new repository calls where needed.

### Task 2: Station Selection Resume UI

**Files:**
- Modify: `lib/features/audits/screens/audit_station_selection_screen.dart`
- Test: `test/features/audits/audit_session_navigation_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add a test that starts `AuditStationSelectionScreen`, stubs a matching in-progress session with `stationsCompleted: ['egg']`, and expects:

```dart
expect(find.text('Saved'), findsOneWidget);
expect(find.text('Continue Visit'), findsOneWidget);
expect(find.byTooltip('Remove saved station'), findsNothing);
```

Add another test that taps `Chicks`, taps `Continue Visit`, and verifies:

```dart
verify(
  () => repository.updateSelectedStationKeys(
    'existing-session',
    const ['egg', 'chicks'],
  ),
).called(1);
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
flutter test test/features/audits/audit_session_navigation_test.dart --plain-name "station selection shows saved badge for resumed session"
flutter test test/features/audits/audit_session_navigation_test.dart --plain-name "resumed station selection can add unsaved stations"
```

Expected: fail because station selection does not load matching sessions or render saved badges.

- [ ] **Step 3: Add resumed-session state**

In `_AuditStationSelectionScreenState`, add:

```dart
AuditSessionModel? _existingSession;
final Set<String> _savedStationKeys = <String>{};
String? _selectedOpenStationKey;
```

In `initState`, call a private loader after first frame:

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) => _loadExistingSession());
}
```

Implement:

```dart
Future<void> _loadExistingSession() async {
  final sessionProvider = context.read<AuditSessionProvider>();
  await sessionProvider.loadMatchingSessionForStationSelection(
    context: _sessionContext(selectedStationKeys: const []),
    currentUser: context.read<AuthProvider>().user,
  );
  if (!mounted) return;
  final session = sessionProvider.currentSession;
  if (session == null || !sessionProvider.isResumed) return;
  setState(() {
    _existingSession = session;
    _orderedSelectedKeys
      ..clear()
      ..addAll(session.selectedStationKeys);
    _savedStationKeys
      ..clear()
      ..addAll(session.stationsCompleted);
  });
}
```

Add:

```dart
DateTime get _visitDate => DateTime.now();

AuditSessionContext _sessionContext({List<String>? selectedStationKeys}) {
  return AuditSessionContext(
    customerId: widget.customerId,
    hatcheryId: widget.hatcheryId,
    flockId: widget.flockId,
    date: _visitDate,
    breed: widget.selectedFlock.breed,
    flockAgeWeeks: widget.selectedFlock.currentAgeWeeks.toInt(),
    selectedStationKeys: selectedStationKeys ?? _orderedSelectedKeys,
  );
}
```

- [ ] **Step 4: Render saved badges and lock saved removal**

In `_buildSelectedTile`, compute:

```dart
final isSaved = _savedStationKeys.contains(stationKey);
```

Add a `Saved` badge before the remove button:

```dart
if (isSaved) ...[
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.completedText.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      border: Border.all(color: AppColors.completedText.withValues(alpha: 0.18)),
    ),
    child: Text(
      'Saved',
      style: AppTextStyles.badgeLabel.copyWith(color: AppColors.completedText),
    ),
  ),
  const SizedBox(width: 8),
],
```

Render the remove button only when `!isSaved`.

- [ ] **Step 5: Continue existing session**

Update `_buildStartVisitButton` text to:

```dart
_existingSession == null ? 'Start Visit' : 'Continue Visit'
```

Update `_handleStartVisit`:

```dart
if (_existingSession != null) {
  await sessionProvider.updateSelectedStationKeys(_orderedSelectedKeys);
  await sessionProvider.resumeSession(
    _existingSession!.id,
    initialStationIndex: _selectedOpenStationKey == null
        ? null
        : _orderedSelectedKeys.indexOf(_selectedOpenStationKey!),
  );
} else {
  await sessionProvider.startSession(
    context: _sessionContext(),
    currentUser: context.read<AuthProvider>().user,
  );
}
```

Clear invalid selected-open station keys after reorder/remove.

- [ ] **Step 6: Run station selection tests**

Run:

```bash
flutter test test/features/audits/audit_session_navigation_test.dart --plain-name "station selection"
```

Expected: station selection tests pass.

### Task 3: Home And Audits Routing

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart`
- Modify: `lib/features/audits/screens/audits_screen.dart`
- Test: `test/features/home/home_screen_test.dart`
- Test: `test/features/audits/audit_session_navigation_test.dart`

- [ ] **Step 1: Write failing routing tests**

Add Home test with a completed session and tap its recent tile. Expect `AuditSessionScreen`, not `VisitDetailScreen`.

Add Audits test with a completed session and tap its session tile. Expect `AuditSessionScreen`, not `_SessionDetailScreen`.

- [ ] **Step 2: Run routing tests to verify failure**

Run:

```bash
flutter test test/features/home/home_screen_test.dart --plain-name "completed visit opens station workflow"
flutter test test/features/audits/audit_session_navigation_test.dart --plain-name "completed audit session opens station workflow"
```

Expected: fail because completed sessions still open summary/detail screens.

- [ ] **Step 3: Add station-workflow route helper**

In both Home and Audits screens, replace completed-session detail routing with:

```dart
final sessionProvider = context.read<AuditSessionProvider>();
await sessionProvider.resumeSession(session.id, initialStationIndex: 0);
if (!mounted) return;
if (sessionProvider.error != null) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(sessionProvider.error!)),
  );
  return;
}
await Navigator.push(
  context,
  AppPageRoute(
    builder: (context) => ChangeNotifierProvider.value(
      value: sessionProvider,
      child: const AuditSessionScreen(),
    ),
  ),
);
```

Keep `VisitDetailScreen` or existing final-results screens reachable from the explicit dashboard/results action added in Task 4.

- [ ] **Step 4: Run routing tests**

Run:

```bash
flutter test test/features/home/home_screen_test.dart test/features/audits/audit_session_navigation_test.dart
```

Expected: all focused navigation tests pass.

### Task 4: Results Action In Station Workflow

**Files:**
- Modify: `lib/features/audits/screens/audit_session_screen.dart`
- Test: `test/features/audits/audit_session_navigation_test.dart`

- [ ] **Step 1: Write failing results-action test**

Add a widget test with a completed session. Pump `AuditSessionScreen` and expect:

```dart
expect(find.byTooltip('View final results'), findsOneWidget);
```

Tap it and assert a results route opens. If wiring to the full dashboard detail is too expensive for the widget test, assert the callback route trigger by finding the pushed `VisitDetailScreen` title:

```dart
await tester.tap(find.byTooltip('View final results'));
await tester.pumpAndSettle();
expect(find.text('Visit Summary'), findsOneWidget);
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
flutter test test/features/audits/audit_session_navigation_test.dart --plain-name "completed station workflow exposes final results action"
```

Expected: fail because no final-results action exists in `AuditSessionScreen`.

- [ ] **Step 3: Add app-bar action**

In `_buildAppBar`, when `provider.currentSession?.status == 'completed'`, add:

```dart
actions: [
  IconButton(
    tooltip: 'View final results',
    icon: const Icon(Icons.dashboard_outlined),
    onPressed: () => _openFinalResults(provider.currentSession!),
  ),
],
```

If `GradientAppBar` does not expose actions, extend it conservatively with an optional `actions` parameter and pass it through to `AppBar`.

Implement `_openFinalResults` in `AuditSessionScreen` using `PanelSampleRepository.getRowsBySessionId` for panel tables or `PanelDashboardRepository.getPanelRowsBySession`, then build `VisitSessionSummary.fromPanelRows` and push `VisitDetailScreen`.

- [ ] **Step 4: Run results-action test**

Run:

```bash
flutter test test/features/audits/audit_session_navigation_test.dart --plain-name "completed station workflow exposes final results action"
```

Expected: pass.

### Task 5: Completion-Safe Editing

**Files:**
- Modify: `lib/features/audits/providers/audit_session_provider.dart`
- Modify: `lib/features/audits/screens/audit_session_screen.dart`
- Test: `test/features/audits/audit_session_provider_test.dart`
- Test: `test/features/audits/audit_session_navigation_test.dart`

- [ ] **Step 1: Write failing completion-preservation test**

Add provider test:

```dart
test('re-saving completed station keeps completed session complete', () async {
  final completed = AuditSessionModel.fromMap(
    makeAuditSessionRow(
      status: 'completed',
      selectedStationKeys: ['egg'],
      stationsCompleted: ['egg'],
      completedAt: DateTime(2026, 1, 2),
    ),
  );

  when(() => mockRepo.getSessionById(completed.id)).thenAnswer((_) async => completed);
  await provider.resumeSession(completed.id, initialStationIndex: 0);
  await provider.markCurrentStationCompleted();

  expect(provider.currentSession?.status, 'completed');
  expect(provider.stationsCompleted, ['egg']);
});
```

- [ ] **Step 2: Run test to verify behavior**

Run:

```bash
flutter test test/features/audits/audit_session_provider_test.dart --plain-name "re-saving completed station keeps completed session complete"
```

Expected: pass if current repository behavior already preserves completion; if it fails, adjust `markCurrentStationCompleted` and repository progress updates to keep status completed when all selected stations remain completed.

- [ ] **Step 3: Guard final-save navigation**

In `_handleNextOrSave`, if the session is already completed, save the current station and stay in the station workflow instead of showing the final completion overlay:

```dart
final wasCompleted = provider.currentSession?.status == 'completed';
await provider.markCurrentStationCompleted();
if (wasCompleted) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Station saved.')),
  );
  return;
}
```

- [ ] **Step 4: Run completion-safe navigation tests**

Run:

```bash
flutter test test/features/audits/audit_session_provider_test.dart test/features/audits/audit_session_navigation_test.dart
```

Expected: completed-session edit tests pass and existing final-completion behavior still passes for newly completed visits.

### Task 6: Documentation And Final Verification

**Files:**
- Modify: `docs/LIVING_SPEC.md`
- Test: relevant Flutter test suites

- [ ] **Step 1: Update living spec**

Add a changelog entry and update session workflow text to state:

```markdown
Same customer/flock/hatchery/date Start Visit resumes an in-progress visit instead of creating a duplicate. Select Stations shows saved station badges for resumed visits, protects saved stations from removal, and still allows adding unsaved stations. Completed visits open station screens for edit/review first, with dashboard/final results available as a separate action.
```

- [ ] **Step 2: Run formatting and diff checks**

Run:

```bash
dart format --set-exit-if-changed lib/data/repositories/audit_session_repository.dart lib/features/audits/providers/audit_session_provider.dart lib/features/audits/screens/audit_station_selection_screen.dart lib/features/audits/screens/audit_session_screen.dart lib/features/home/screens/home_screen.dart lib/features/audits/screens/audits_screen.dart test/features/audits/audit_session_provider_test.dart test/features/audits/audit_session_navigation_test.dart test/features/home/home_screen_test.dart
git diff --check -- lib/data/repositories/audit_session_repository.dart lib/features/audits/providers/audit_session_provider.dart lib/features/audits/screens/audit_station_selection_screen.dart lib/features/audits/screens/audit_session_screen.dart lib/features/home/screens/home_screen.dart lib/features/audits/screens/audits_screen.dart test/features/audits/audit_session_provider_test.dart test/features/audits/audit_session_navigation_test.dart test/features/home/home_screen_test.dart docs/LIVING_SPEC.md
```

Expected: both commands pass.

- [ ] **Step 3: Run focused tests**

Run:

```bash
flutter test test/features/audits/audit_session_provider_test.dart test/features/audits/audit_session_navigation_test.dart test/features/home/home_screen_test.dart
```

Expected: all tests pass.

- [ ] **Step 4: Restart stable web preview**

Run:

```bash
make restart-web
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:57863/main.dart.js
```

Expected: HTTP status `200`.
