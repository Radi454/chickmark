# Audit Scope Add and Remove Guards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prompt for scope-specific identity before creating audit-station scopes and confirm removal only when affected entered results would be discarded.

**Architecture:** Add shared Material dialog helpers that return values without mutating provider state. Keep duplicate checks, affected-scope selection, and result-loss detection in the owning audit feature, with small public `AuditProvider` result probes for draft-backed and Chick Weight scopes. Existing add/remove persistence paths remain authoritative and run only after the dialog outcome permits them.

**Tech Stack:** Dart 3.10.7, Flutter, Provider, existing custom localization, Flutter widget tests, offline-first SQLite/Supabase persistence paths.

## Global Constraints

- Apply only to mounted audit-station data-entry scope controls.
- Scope identifiers and untouched generated defaults must not count as entered results.
- Parent removal must inspect every descendant that the existing action would discard.
- Add cancellation and removal cancellation must not mutate provider, screen-local, autosave, or persistence state.
- Preserve current inline identity editing, read-only behavior, autosave, tombstones, persistence, and synchronization.
- Do not change database schemas, Supabase tables, RLS policies, or sync protocols.
- Update `docs/LIVING_SPEC.md` after meaningful code changes.
- Preserve unrelated worktree changes and stage only feature files.

---

### Task 1: Shared scope dialogs

**Files:**
- Create: `lib/features/audits/widgets/audit_scope_dialogs.dart`
- Create: `test/features/audits/audit_scope_dialogs_test.dart`

**Interfaces:**
- Produces: `AuditScopeIdentityField`, `AuditScopeIdentityValidator`, `showAuditScopeIdentityDialog`, `confirmAuditScopeRemoval`, and `normalizeAuditScopeIdentity`.
- Consumes: Material `BuildContext` and the existing `context.tr(...)` localization extension.

- [ ] **Step 1: Write failing dialog widget tests**

Cover missing values, validator errors, cancellation, successful normalized
values, immediate empty-scope removal, and result-bearing removal cancellation
and confirmation:

```dart
testWidgets('scope identity dialog returns trimmed required values', (tester) async {
  Map<String, String>? result;
  await tester.pumpWidget(_DialogHost(onPressed: (context) async {
    result = await showAuditScopeIdentityDialog(
      context,
      scopeLabel: 'House',
      fields: const [AuditScopeIdentityField(key: 'house', label: 'House')],
    );
  }));

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  expect(find.text('Add House scope'), findsOneWidget);
  await tester.enterText(find.byKey(const ValueKey('scope-identity-house')), ' 12 ');
  await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
  await tester.pumpAndSettle();

  expect(result, {'house': '12'});
});

testWidgets('result-bearing scope removal requires explicit Remove', (tester) async {
  bool? result;
  await tester.pumpWidget(_DialogHost(onPressed: (context) async {
    result = await confirmAuditScopeRemoval(
      context,
      hasEnteredResults: true,
    );
  }));

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  expect(find.text('Remove scope?'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('scope-removal-cancel')));
  await tester.pumpAndSettle();
  expect(result, isFalse);
});

class _DialogHost extends StatelessWidget {
  const _DialogHost({required this.onPressed});

  final Future<void> Function(BuildContext context) onPressed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onPressed(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```bash
flutter test test/features/audits/audit_scope_dialogs_test.dart
```

Expected: compilation failure because `audit_scope_dialogs.dart` and its
interfaces do not exist.

- [ ] **Step 3: Implement the minimal shared dialog APIs**

Create these public interfaces:

```dart
class AuditScopeIdentityField {
  const AuditScopeIdentityField({
    required this.key,
    required this.label,
    this.keyboardType = TextInputType.text,
  });

  final String key;
  final String label;
  final TextInputType keyboardType;
}

typedef AuditScopeIdentityValidator =
    String? Function(Map<String, String> values);

String normalizeAuditScopeIdentity(String value, {String? prefix}) {
  var normalized = value.trim();
  if (prefix != null &&
      normalized.toLowerCase().startsWith(prefix.toLowerCase())) {
    normalized = normalized.substring(prefix.length).trim();
  }
  return normalized.toLowerCase();
}

Future<Map<String, String>?> showAuditScopeIdentityDialog(
  BuildContext context, {
  required String scopeLabel,
  required List<AuditScopeIdentityField> fields,
  AuditScopeIdentityValidator? validator,
});

Future<bool> confirmAuditScopeRemoval(
  BuildContext context, {
  required bool hasEnteredResults,
});
```

`showAuditScopeIdentityDialog` owns and disposes its controllers, trims returned
values, blocks blank required fields, shows the validator's returned message,
and uses stable keys `scope-identity-<field key>`, `scope-identity-cancel`, and
`scope-identity-add`. `confirmAuditScopeRemoval` returns `true` without opening a
dialog when `hasEnteredResults` is false; otherwise it uses the approved copy
and stable `scope-removal-cancel` / `scope-removal-confirm` keys.

- [ ] **Step 4: Run shared dialog tests and verify GREEN**

Run:

```bash
flutter test test/features/audits/audit_scope_dialogs_test.dart
```

Expected: all tests pass with no exceptions or pending timers.

- [ ] **Step 5: Commit the shared interaction primitive**

```bash
git add lib/features/audits/widgets/audit_scope_dialogs.dart test/features/audits/audit_scope_dialogs_test.dart
git commit -m "feat: add audit scope dialogs"
```

---

### Task 2: Result-loss probes

**Files:**
- Modify: `lib/features/audits/models/egg_breakout_sample.dart`
- Modify: `lib/features/audits/providers/audit_provider.dart`
- Modify: `test/features/audits/audit_provider_sample_mode_test.dart`
- Modify: `test/features/audits/egg_breakout_sample_test.dart`

**Interfaces:**
- Produces: `EggBreakoutSampleEntry.hasEnteredResults`,
  `AuditProvider.stationScopeHasEnteredResults(int index)`, and
  `AuditProvider.chickWeightScopeHasEnteredResults(int index)`.
- Consumes: existing provider meaningful-data helpers and current scope model
  fields.

- [ ] **Step 1: Write failing pure-Dart/provider tests**

Add cases proving identity-only/default-only scopes are false while a typed
result, an explicit zero count key, a photo, and a Chick Weight list are true:

```dart
test('breakout scope detects entered zero count but ignores defaults', () {
  final empty = EggBreakoutSampleEntry.tray(
    id: 'tray-1',
    label: 'Tray 1',
    tray: '1',
  );
  expect(empty.hasEnteredResults, isFalse);
  expect(
    empty.copyWith(counts: const {'infertile': 0}).hasEnteredResults,
    isTrue,
  );
});

test('station result probe ignores machine identity but detects results', () {
  final provider = AuditProvider(autosaveEnabled: false);
  provider.initialize(stationContext('Chicks'), notify: false);
  provider.addChickQualityMachineScopeSample();
  provider.updateSampleMetadata({'setterNo': '7', 'hatcherNo': '8'});
  expect(provider.stationScopeHasEnteredResults(0), isFalse);
  provider.updateField('pasgarSampleSize', 100);
  expect(provider.stationScopeHasEnteredResults(0), isTrue);
});
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
flutter test test/features/audits/audit_provider_sample_mode_test.dart test/features/audits/egg_breakout_sample_test.dart
```

Expected: compilation failure for the three missing result-probe interfaces.

- [ ] **Step 3: Add identity-free result detection**

Implement:

```dart
extension EggBreakoutSampleResultDetection on EggBreakoutSampleEntry {
  bool get hasEnteredResults {
    final defaultTraySize =
        breakoutType == EggBreakoutType.freshEggBreakout ? 30 : 150;
    return counts.isNotEmpty ||
        photos.isNotEmpty ||
        (traySize != null && traySize != defaultTraySize) ||
        (sampleMode == EggBreakoutSampleMode.pool &&
            numberOfTrays != null &&
            numberOfTrays != 1);
  }
}
```

In `AuditProvider`, add bounds-checked public probes. The station probe switches
on `draft.auditType` and delegates to new private result-only helpers:

```dart
bool stationScopeHasEnteredResults(int index) {
  if (index < 0 || index >= _drafts.length) return false;
  final draft = _drafts[index];
  return switch (draft.auditType) {
    'Egg' => _hasMeaningfulEggQualityData(draft),
    'Chicks' => _hasMeaningfulChickQualityResults(draft),
    'Hatch Analysis & Egg Breakouts' => _hasHatchScopeResults(draft),
    'Setters' => _hasSetterScopeResults(draft),
    'Hatchers' => _hasHatcherScopeResults(draft),
    _ => false,
  };
}

bool chickWeightScopeHasEnteredResults(int index) {
  if (index < 0 || index >= _chickWeightSamples.length) return false;
  return _hasMeaningfulChickWeightSample(
    activeDraft,
    _chickWeightSamples[index],
  );
}
```

The private result helpers must omit House/Setter/Hatcher identity, breed,
incubation-age identity used by the Setter EST sub-scope, generated labels, and
shared Egg Storage metadata. They include nullable entered measurements,
selected assessments, notes, result JSON/maps, photos, and derived result values.
`_hasHatchScopeResults` decodes breakout entries and calls
`hasEnteredResults`, avoiding a false positive from hierarchy/default JSON.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
flutter test test/features/audits/audit_provider_sample_mode_test.dart test/features/audits/egg_breakout_sample_test.dart
```

Expected: all focused tests pass.

- [ ] **Step 5: Commit the result probes**

```bash
git add lib/features/audits/models/egg_breakout_sample.dart lib/features/audits/providers/audit_provider.dart test/features/audits/audit_provider_sample_mode_test.dart test/features/audits/egg_breakout_sample_test.dart
git commit -m "feat: detect audit scope result loss"
```

---

### Task 3: Egg and Chicks scope interactions

**Files:**
- Modify: `lib/features/audits/screens/egg_storage_screen.dart`
- Modify: `lib/features/audits/screens/chick_quality_screen.dart`
- Modify: `test/features/audits/egg_storage_screen_test.dart`
- Modify: `test/features/audits/chick_quality_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 dialog APIs and Task 2 provider probes.
- Produces: prompted House/Machine creation and guarded removal for Egg Quality,
  Chick Weights, and Chick Quality.

- [ ] **Step 1: Replace existing immediate-add test expectations with RED dialog tests**

For each scope family, test cancel, valid named add, duplicate rejection, empty
remove, result-bearing cancel, and result-bearing confirm. A representative add
assertion is:

```dart
await tester.tap(find.byTooltip('Add house sample'));
await tester.pumpAndSettle();
expect(find.text('Add House scope'), findsOneWidget);
await tester.enterText(
  find.byKey(const ValueKey('scope-identity-house')),
  '12',
);
await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
await tester.pumpAndSettle();
expect(provider.activeChickWeightSample.houseNo, '12');
expect(find.text('H12'), findsWidgets);
```

For removal, first write an entered result through the existing screen/provider
API, tap remove, assert the approved copy, cancel and verify preservation, then
repeat and confirm.

- [ ] **Step 2: Run Egg and Chicks screen tests and verify RED**

Run:

```bash
flutter test test/features/audits/egg_storage_screen_test.dart test/features/audits/chick_quality_screen_test.dart
```

Expected: the new tests fail because `+` still mutates immediately and remove
still bypasses confirmation.

- [ ] **Step 3: Implement async add/remove adapters**

Import `audit_scope_dialogs.dart`, convert callbacks to async closures, and use
the existing provider mutations only after a positive dialog result:

```dart
Future<void> _addEggHouseSample(AuditProvider provider) async {
  final values = await showAuditScopeIdentityDialog(
    context,
    scopeLabel: 'House',
    fields: const [AuditScopeIdentityField(key: 'house', label: 'House')],
    validator: (values) => _duplicateEggHouse(provider, values['house']!)
        ? 'A House scope with this identity already exists.'
        : null,
  );
  if (values == null || !mounted) return;
  provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
  provider.updateSampleMetadata({
    'houseNo': values['house'],
    'houseLabel': 'House ${values['house']}',
  });
  _syncActiveSampleForm(provider.activeDraft);
  setState(() {});
}
```

Chick Weight uses `updateChickWeightSampleMetadata`; Chick Quality Machine asks
for both `setter` and `hatcher` then uses `updateSampleMetadata`. Duplicate
checks normalize optional `H`/`S` prefixes and compare siblings. Removal calls
`confirmAuditScopeRemoval` with the correct active provider probe before running
the existing remove method.

- [ ] **Step 4: Run Egg and Chicks screen tests and verify GREEN**

Run:

```bash
flutter test test/features/audits/egg_storage_screen_test.dart test/features/audits/chick_quality_screen_test.dart
```

Expected: all add, validation, cancel, remove, and existing regression tests
pass.

- [ ] **Step 5: Commit Egg and Chicks integration**

```bash
git add lib/features/audits/screens/egg_storage_screen.dart lib/features/audits/screens/chick_quality_screen.dart test/features/audits/egg_storage_screen_test.dart test/features/audits/chick_quality_screen_test.dart
git commit -m "feat: guard egg and chick scope changes"
```

---

### Task 4: Hatch Analysis hierarchy and breakout scopes

**Files:**
- Modify: `lib/features/audits/screens/hatch_analysis_screen.dart`
- Modify: `test/features/audits/hatch_analysis_screen_breakout_test.dart`

**Interfaces:**
- Consumes: Task 1 dialogs, Task 2 provider probes, and
  `EggBreakoutSampleEntry.hasEnteredResults`.
- Produces: prompted House, Machine, Trolley, and Tray creation plus
  result-aware hierarchy removal.

- [ ] **Step 1: Write failing Hatch Analysis interaction tests**

Update every existing immediate `residue-add-*` and `breakout-add-sample`
sequence to complete its identity dialog. Add explicit tests for:

- House/Machine/Trolley/Tray cancel leaving JSON and draft count unchanged;
- named identity appearing on the selected chip before inline editing;
- duplicate sibling identity validation within the active parent;
- parent removal warning when an affected descendant has counts/photos;
- no warning when hierarchy removal only clears identity and preserves results;
- Tray removal cancel/confirm behavior.

Use stable keys from Task 1 and existing scope button keys.

- [ ] **Step 2: Run Hatch Analysis tests and verify RED**

Run:

```bash
flutter test test/features/audits/hatch_analysis_screen_breakout_test.dart
```

Expected: failures because add/remove actions still run immediately.

- [ ] **Step 3: Parameterize existing add methods and extract Tray add**

Change the add methods to accept dialog identities:

```dart
void _addResidueHouse(AuditProvider provider, String house);
void _addResidueMachine(
  AuditProvider provider, {
  required String setter,
  required String hatcher,
});
void _addResidueTrolley(
  AuditProvider provider,
  int hatchIndex,
  AuditModel audit,
  EggBreakoutType breakoutType,
  List<EggBreakoutSampleEntry> samples,
  String trolley,
);
void _addBreakoutTray(
  AuditProvider provider,
  int hatchIndex,
  AuditModel audit,
  EggBreakoutType breakoutType,
  List<EggBreakoutSampleEntry> samples,
  String tray,
);
```

Each `+` callback opens the matching identity dialog first. Duplicate checks are
scoped to the active parent path. `_addBreakoutTray` replaces the current inline
closure and creates the entry with both `label` and `tray` set from the submitted
identity.

- [ ] **Step 4: Guard only destructive result loss**

Before existing removal:

- House: collect every draft index in the active House; warn only if those
  indexes will be deleted and any provider probe is true.
- Machine: warn only when the active Machine draft will be removed, not when the
  only Machine merely returns to pool.
- Trolley: when current behavior deletes matching pool samples, check those
  entries' `hasEnteredResults`; when it only clears the label and preserves
  samples, do not warn.
- Tray: check the selected entry's `hasEnteredResults`.

After confirmation, call the unchanged mutation once.

- [ ] **Step 5: Run Hatch Analysis tests and verify GREEN**

Run:

```bash
flutter test test/features/audits/hatch_analysis_screen_breakout_test.dart
```

Expected: all hierarchy, breakout, add, remove, and regression tests pass.

- [ ] **Step 6: Commit Hatch Analysis integration**

```bash
git add lib/features/audits/screens/hatch_analysis_screen.dart test/features/audits/hatch_analysis_screen_breakout_test.dart
git commit -m "feat: guard hatch analysis scope changes"
```

---

### Task 5: Setter and Hatcher scope interactions

**Files:**
- Modify: `lib/features/audits/screens/setter_optimizing_screen.dart`
- Modify: `lib/features/audits/screens/hatcher_optimizing_screen.dart`
- Modify: `test/features/audits/incubation_age_hours_test.dart`

**Interfaces:**
- Consumes: Task 1 dialogs and Task 2 provider result probes.
- Produces: prompted Setter/Hatcher Machine creation, prompted Setter EST
  incubation-age sample creation, and guarded removals.

- [ ] **Step 1: Write failing Setter/Hatcher widget tests**

Add cases that:

- require Setter identity before a Setter Machine is created;
- require Hatcher identity before a Hatcher Machine is created;
- require incubation age and hours before an EST sample is created;
- reject duplicate Machine and age/hour sibling identities;
- cancel without changing provider draft/sample counts;
- remove identity-only scopes immediately; and
- confirm before removing scopes with readings, photos, or other results.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
flutter test test/features/audits/incubation_age_hours_test.dart
```

Expected: new dialog assertions fail against immediate current actions.

- [ ] **Step 3: Implement prompted Machine creation and guarded removal**

Convert `_addSetterMachineSample`, `_addHatcherMachineSample`,
`_removeActiveSetterSample`, and `_removeActiveHatcherSample` to async methods.
After valid identity input, call `provider.addSample()`, then update both the
hierarchy field and station-specific field before syncing form state:

```dart
provider.updateField('setterId', setter);
provider.updateField('soSetterId', setter);
```

The Hatcher equivalent updates `hatcherId` and `hoHatcherId`. Removals use
`provider.stationScopeHasEnteredResults(provider.activeSampleIndex)`.

- [ ] **Step 4: Implement prompted EST sample creation and guarded removal**

The EST dialog uses numeric `incubationAge` and `incubationHours` fields,
validates integer age and hours in `0..23`, and rejects a sibling with the same
pair. Only after validation does `_addEstSample` append a normalized sample with
the submitted identity and blank result maps:

```dart
samples.add(_normalizeEstSample({
  'id': DateTime.now().microsecondsSinceEpoch.toString(),
  'breed': base['breed'],
  'incubationAge': int.parse(values['incubationAge']!),
  'incubationHours': int.parse(values['incubationHours']!),
  'estReadings': <String, double>{},
  'estPhotos': <String, String>{},
  'estAvg': null,
  'estCv': null,
}));
```

Removal checks only the selected sample's `estReadings`, `estPhotos`, `estAvg`,
and `estCv`; breed/age/hours identity alone does not trigger confirmation.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
flutter test test/features/audits/incubation_age_hours_test.dart
```

Expected: all Setter, Hatcher, and incubation-age scope tests pass.

- [ ] **Step 6: Commit Setter/Hatcher integration**

```bash
git add lib/features/audits/screens/setter_optimizing_screen.dart lib/features/audits/screens/hatcher_optimizing_screen.dart test/features/audits/incubation_age_hours_test.dart
git commit -m "feat: guard setter and hatcher scope changes"
```

---

### Task 6: Living spec and full quality gate

**Files:**
- Modify: `docs/LIVING_SPEC.md`
- Review: every file committed in Tasks 1–5

**Interfaces:**
- Consumes: all completed behavior and tests.
- Produces: current implemented documentation and verification evidence.

- [ ] **Step 1: Update the living specification**

Document that mounted audit scope `+` controls collect scope-specific identity
before creation, identity/default-only removal is immediate, result-bearing
destructive removal requires confirmation, and parent checks include deleted
descendants. Add a dated Recent Changes entry for 2026-07-23.

- [ ] **Step 2: Format changed Dart files**

Run:

```bash
dart format lib/features/audits/models/egg_breakout_sample.dart lib/features/audits/providers/audit_provider.dart lib/features/audits/widgets/audit_scope_dialogs.dart lib/features/audits/screens/egg_storage_screen.dart lib/features/audits/screens/chick_quality_screen.dart lib/features/audits/screens/hatch_analysis_screen.dart lib/features/audits/screens/setter_optimizing_screen.dart lib/features/audits/screens/hatcher_optimizing_screen.dart test/features/audits/audit_scope_dialogs_test.dart test/features/audits/audit_provider_sample_mode_test.dart test/features/audits/egg_breakout_sample_test.dart test/features/audits/egg_storage_screen_test.dart test/features/audits/chick_quality_screen_test.dart test/features/audits/hatch_analysis_screen_breakout_test.dart test/features/audits/incubation_age_hours_test.dart
```

Expected: exit code 0.

- [ ] **Step 3: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: exit code 0 with no analyzer issues.

- [ ] **Step 4: Run focused and regression tests**

Run:

```bash
flutter test test/features/audits/audit_scope_dialogs_test.dart test/features/audits/audit_provider_sample_mode_test.dart test/features/audits/egg_breakout_sample_test.dart test/features/audits/egg_storage_screen_test.dart test/features/audits/chick_quality_screen_test.dart test/features/audits/hatch_analysis_screen_breakout_test.dart test/features/audits/incubation_age_hours_test.dart test/features/audits/audit_provider_save_result_test.dart test/features/audits/egg_station_panel_persistence_test.dart test/features/audits/chick_station_panel_persistence_test.dart test/features/audits/hatch_breakout_panel_persistence_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Build the affected target**

Run:

```bash
flutter build web
```

Expected: exit code 0 and a completed `build/web` output.

- [ ] **Step 6: Run graphical end-to-end verification**

Restart the current code at the stable origin:

```bash
make restart-web
```

Use Computer Use at `http://127.0.0.1:57863` to verify:

1. cancelling Add creates nothing;
2. valid identity creates and selects the named scope;
3. blank/duplicate identity stays in the dialog;
4. identity remains editable afterward;
5. empty removal is immediate;
6. result-bearing removal can be cancelled without data loss;
7. confirmed removal deletes the intended scope;
8. parent removal detects descendant results;
9. save, navigate away, return, and verify persistence; and
10. read-only controls remain disabled.

Expected: all applicable scenarios pass without console-visible exceptions.

- [ ] **Step 7: Review safety, security, data integrity, and final diff**

Run:

```bash
git diff HEAD~5 --check
git status --short
git diff HEAD~5 -- lib/features/audits test/features/audits docs/LIVING_SPEC.md
```

Confirm no database/RLS/sync protocol change, no secret exposure, no unrelated
file staged, no removal callback runs twice, and cancellation performs no
mutation.

- [ ] **Step 8: Commit documentation and any verified final corrections**

```bash
git add docs/LIVING_SPEC.md
git commit -m "docs: document audit scope guards"
```
