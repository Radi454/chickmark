# Home Incomplete Visits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Home-screen sector that lists every incomplete audit visit, asks the user to complete it soon, and resumes directly at the first unfinished station.

**Architecture:** Keep `HomeProvider.activeSessions` as the customer-scoped data source. Add a focused presentation widget for one incomplete visit, compose all cards inside the existing Home section pattern, and route card actions through `AuditSessionProvider.resumeSession` without reopening station selection.

**Tech Stack:** Dart 3.10.7, Flutter, Provider, existing offline-first SQLite repositories, Flutter widget tests, mocktail.

## Global Constraints

- Render every customer-visible session whose status is `in_progress`; do not truncate or paginate the Home sector.
- Place `Incomplete Visits` immediately after Quick Actions and hide it when empty.
- Use the exact reminder `Please complete this visit soon.` and action label `Complete now`.
- Open the first station absent from `stationsCompleted` directly in `AuditSessionScreen`.
- Reload Home after the station workflow closes.
- Do not add database columns, migrations, Supabase triggers, scheduled notifications, or dependencies.
- Preserve unrelated local changes and update `docs/LIVING_SPEC.md` after the meaningful code change.
- Do not mark the product task complete without human reviewer approval.

---

## File Structure

- Create `lib/features/home/widgets/incomplete_visit_card.dart`: presentation-only card for one unfinished session.
- Modify `lib/features/home/screens/home_screen.dart`: conditionally compose the sector, resolve display labels, and perform direct resume/reload.
- Modify `test/features/home/home_screen_test.dart`: Home rendering and direct-resume widget coverage.
- Modify `test/features/home/home_provider_test.dart`: explicitly preserve customer scoping for active sessions.
- Modify `docs/LIVING_SPEC.md`: document the implemented Home behavior.

### Task 1: Render every incomplete visit on Home

**Files:**
- Create: `lib/features/home/widgets/incomplete_visit_card.dart`
- Modify: `lib/features/home/screens/home_screen.dart:128-150`
- Modify: `lib/features/home/screens/home_screen.dart:253-290`
- Test: `test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `HomeProvider.activeSessions`, `CustomersProvider.customerById`, `CustomersProvider.flockById`, and `AuditSessionProvider.stationDisplayLabels`.
- Produces: `IncompleteVisitCard({session, customerName, flockLabel, breed, missingStationLabels, onTap})`.

- [ ] **Step 1: Add a failing Home rendering test**

Add a static Home provider and session fixture to
`test/features/home/home_screen_test.dart`:

```dart
class _StaticHomeProvider extends HomeProvider {
  _StaticHomeProvider(this.sessions);

  final List<AuditSessionModel> sessions;

  @override
  List<AuditSessionModel> get activeSessions => List.unmodifiable(sessions);

  @override
  List<AuditSessionModel> get recentSessions => const [];
}

AuditSessionModel incompleteSession({
  required String id,
  List<String> selected = const [
    'chicks',
    'hatch_analysis_egg_breakouts',
  ],
  List<String> completed = const [],
}) {
  final date = DateTime(2026, 7, 21, 12, 30);
  return AuditSessionModel(
    id: id,
    customerId: 'customer-$id',
    flockId: 'flock-$id',
    hatcheryId: 'hatchery-$id',
    date: date,
    breed: 'Avian',
    status: 'in_progress',
    selectedStationKeys: selected,
    stationsCompleted: completed,
    createdAt: date,
    updatedAt: date,
  );
}
```

Extend the existing `pumpHome` helper with optional `homeProvider` and
`auditSessionProvider` arguments:

```dart
Future<void> pumpHome(
  WidgetTester tester, {
  HomeProvider? homeProvider,
  AuditSessionProvider? auditSessionProvider,
}) async {
  SharedPreferences.setMockInitialValues({});
  final sessionProvider = auditSessionProvider ?? AuditSessionProvider();
  addTearDown(sessionProvider.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            supabaseService: _MockSupabaseService(),
            bypassAuth: true,
          ),
        ),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider.value(value: sessionProvider),
        ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
      ],
      child: MaterialApp(
        home: HomeScreen(
          loadInitialData: false,
          homeProvider: homeProvider,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
```

Add the required imports for `AuditSessionModel`,
`GoveeCaptureProvider`, and later navigation assertions, then add:

```dart
testWidgets('Home lists every incomplete visit with completion reminder', (
  tester,
) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final sessions = [
    incompleteSession(id: 'one', completed: const ['chicks']),
    incompleteSession(id: 'two'),
    incompleteSession(id: 'three'),
  ];

  await pumpHome(
    tester,
    homeProvider: _StaticHomeProvider(sessions),
  );

  expect(
    find.byKey(const ValueKey('home-incomplete-visits-section')),
    findsOneWidget,
  );
  for (final session in sessions) {
    expect(
      find.byKey(ValueKey('home-incomplete-visit-${session.id}')),
      findsOneWidget,
    );
  }
  expect(find.text('Please complete this visit soon.'), findsNWidgets(3));
  expect(find.text('Complete now'), findsNWidgets(3));
  expect(find.text('1/2 stations complete'), findsOneWidget);
  expect(find.text('Still needed: Hatch Analysis & Egg Breakouts'), findsOneWidget);
});
```

- [ ] **Step 2: Run the rendering test and verify RED**

Run:

```bash
flutter test test/features/home/home_screen_test.dart \
  --plain-name "Home lists every incomplete visit with completion reminder"
```

Expected: FAIL because `home-incomplete-visits-section` and the incomplete
visit cards do not exist.

- [ ] **Step 3: Add the focused incomplete-visit card**

Create `lib/features/home/widgets/incomplete_visit_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/audit_session_model.dart';
import '../../../widgets/app_card.dart';

class IncompleteVisitCard extends StatelessWidget {
  const IncompleteVisitCard({
    super.key,
    required this.session,
    required this.customerName,
    required this.flockLabel,
    required this.missingStationLabels,
    required this.onTap,
    this.breed,
  });

  final AuditSessionModel session;
  final String customerName;
  final String flockLabel;
  final String? breed;
  final List<String> missingStationLabels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final breedPart = breed == null || breed!.trim().isEmpty
        ? ''
        : ' · ${breed!.trim()}';
    final completed = session.stationsCompleted
        .where(session.selectedStationKeys.contains)
        .length;
    final total = session.selectedStationKeys.length;
    final stationWord = total == 1 ? 'station' : 'stations';
    final missing = missingStationLabels.isEmpty
        ? 'Still needed: Review visit'
        : 'Still needed: ${missingStationLabels.join(', ')}';

    return AppCard(
      key: ValueKey('home-incomplete-visit-${session.id}'),
      margin: EdgeInsets.zero,
      color: AppColors.statusWarningBg,
      border: Border.all(
        color: AppColors.statusWarning.withValues(alpha: 0.35),
      ),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pending_actions_outlined,
                color: AppColors.statusWarning,
                size: AppSizes.iconSm,
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Text('Incomplete visit', style: AppTextStyles.title),
              ),
              Text(
                '$completed/$total $stationWord complete',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.statusWarning,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(
            '$customerName · $flockLabel$breedPart · '
            '${HatchDateUtils.formatDisplayDate(session.date)}',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(missing, style: AppTextStyles.caption),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            'Please complete this visit soon.',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.statusWarning,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSizes.spaceMd),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              key: ValueKey('home-complete-now-${session.id}'),
              onPressed: onTap,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Complete now'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.statusWarning,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Compose the Home sector**

Import `IncompleteVisitCard`, insert the conditional sector immediately after
Quick Actions, and add:

```dart
Widget _buildIncompleteVisits(
  CustomersProvider customers,
  HomeProvider home,
) {
  return KeyedSubtree(
    key: const ValueKey('home-incomplete-visits-section'),
    child: _HomeSection(
      title: 'Incomplete Visits',
      child: Column(
        children: [
          for (var i = 0; i < home.activeSessions.length; i++) ...[
            IncompleteVisitCard(
              session: home.activeSessions[i],
              customerName:
                  customers
                      .customerById(home.activeSessions[i].customerId)
                      ?.name ??
                  home.activeSessions[i].customerId,
              flockLabel:
                  customers.flockById(home.activeSessions[i].flockId)?.flockId ??
                  home.activeSessions[i].flockId,
              breed: customers.flockById(home.activeSessions[i].flockId)?.breed,
              missingStationLabels: home.activeSessions[i].selectedStationKeys
                  .where(
                    (key) =>
                        !home.activeSessions[i].stationsCompleted.contains(key),
                  )
                  .map(
                    (key) =>
                        AuditSessionProvider.stationDisplayLabels[key] ?? key,
                  )
                  .toList(growable: false),
              onTap: () {},
            ),
            if (i < home.activeSessions.length - 1)
              const SizedBox(height: AppSizes.spaceMd),
          ],
        ],
      ),
    ),
  );
}
```

Use this list composition:

```dart
_buildQuickActions(context),
if (home.activeSessions.isNotEmpty) ...[
  const SizedBox(height: AppSizes.spaceLg),
  _buildIncompleteVisits(provider, home),
],
const SizedBox(height: AppSizes.spaceLg),
_buildRecentAudits(provider, home),
```

- [ ] **Step 5: Run the rendering test and verify GREEN**

Run:

```bash
flutter test test/features/home/home_screen_test.dart \
  --plain-name "Home lists every incomplete visit with completion reminder"
```

Expected: PASS.

### Task 2: Resume the first unfinished station directly

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart:775-838`
- Modify: `test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `AuditSessionProvider.resumeSession(String, {int? initialStationIndex})`.
- Produces: `_openIncompleteSession(AuditSessionModel)` which opens
  `AuditSessionScreen` directly and reloads Home on return.

- [ ] **Step 1: Add a failing direct-resume widget test**

Add a mock repository and use a real `AuditSessionProvider`:

```dart
class _MockAuditSessionRepository extends Mock
    implements AuditSessionRepository {}

testWidgets('Complete now opens the first unfinished station directly', (
  tester,
) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = incompleteSession(
    id: 'resume',
    selected: const ['egg', 'chicks'],
    completed: const ['egg'],
  );
  final repository = _MockAuditSessionRepository();
  when(() => repository.getSessionById('resume')).thenAnswer((_) async => session);
  final auditSessionProvider = AuditSessionProvider(repository: repository);

  await pumpHome(
    tester,
    homeProvider: _StaticHomeProvider([session]),
    auditSessionProvider: auditSessionProvider,
  );
  await tester.tap(
    find.byKey(const ValueKey('home-complete-now-resume')),
  );
  await tester.pumpAndSettle();

  verify(() => repository.getSessionById('resume')).called(1);
  expect(auditSessionProvider.currentStationIndex, 1);
  expect(find.byType(AuditSessionScreen), findsOneWidget);
  expect(find.byType(AuditStationSelectionScreen), findsNothing);
});
```

- [ ] **Step 2: Run the navigation test and verify RED**

Run:

```bash
flutter test test/features/home/home_screen_test.dart \
  --plain-name "Complete now opens the first unfinished station directly"
```

Expected: FAIL because the incomplete card/action and
`_openIncompleteSession` direct route are not yet wired for this behavior.

- [ ] **Step 3: Implement direct resume and reload**

Add to `_HomeScreenState`:

```dart
Future<void> _openIncompleteSession(AuditSessionModel session) async {
  await _openStationWorkflow(session);
  if (!mounted) return;
  await _reloadHomeData();
}
```

Replace the Task 1 placeholder callback with:

```dart
onTap: () => _openIncompleteSession(home.activeSessions[i]),
```

Do not call `_openSession` here: that method intentionally sends existing
in-progress sessions through station selection. Leaving it unchanged preserves
Recent Audits and Today's Focus behavior outside the new sector.

- [ ] **Step 4: Run the direct-resume test and verify GREEN**

Run:

```bash
flutter test test/features/home/home_screen_test.dart \
  --plain-name "Complete now opens the first unfinished station directly"
```

Expected: PASS with `currentStationIndex == 1` and `AuditSessionScreen`
rendered.

- [ ] **Step 5: Add and run the empty-state regression**

Add:

```dart
testWidgets('Home hides Incomplete Visits when there are none', (tester) async {
  await pumpHome(
    tester,
    homeProvider: _StaticHomeProvider(const []),
  );

  expect(
    find.byKey(const ValueKey('home-incomplete-visits-section')),
    findsNothing,
  );
});
```

Run:

```bash
flutter test test/features/home/home_screen_test.dart \
  --plain-name "Home hides Incomplete Visits when there are none"
```

Expected: PASS.

### Task 3: Preserve customer scope and document the behavior

**Files:**
- Modify: `test/features/home/home_provider_test.dart:85-145`
- Modify: `docs/LIVING_SPEC.md:440-465`

**Interfaces:**
- Consumes: `HomeProvider.load({required UserModel? currentUser})`.
- Produces: explicit regression coverage that `activeSessions` remains
  customer-scoped.

- [ ] **Step 1: Strengthen the existing customer-scope test**

After the existing `loaded.load` assertions, add:

```dart
expect(
  loaded.activeSessions.map((item) => item.id),
  ['customer-session'],
);
```

- [ ] **Step 2: Run the provider test**

Run:

```bash
flutter test test/features/home/home_provider_test.dart \
  --plain-name "scopes recent sessions to customer users"
```

Expected: PASS because `HomeProvider` already filters in-progress sessions to
the signed-in customer's id.

- [ ] **Step 3: Update the living specification**

Extend the current Home paragraph in `docs/LIVING_SPEC.md` with:

```markdown
When incomplete visits exist, Home shows an `Incomplete Visits` section
immediately after Quick Actions. It renders every customer-visible
`in_progress` visit with customer/flock/date context, completed/selected
station progress, the remaining station labels, the reminder to complete the
visit soon, and a `Complete now` action. The action resumes
`AuditSessionScreen` directly at the first selected station absent from
`stationsCompleted`; returning to Home reloads the list, so a completed visit
disappears. The section is hidden when no incomplete visits remain.
```

- [ ] **Step 4: Format and run focused verification**

Run:

```bash
dart format \
  lib/features/home/widgets/incomplete_visit_card.dart \
  lib/features/home/screens/home_screen.dart \
  test/features/home/home_screen_test.dart \
  test/features/home/home_provider_test.dart
flutter test test/features/home/home_screen_test.dart
flutter test test/features/home/home_provider_test.dart
dart analyze \
  lib/features/home/widgets/incomplete_visit_card.dart \
  lib/features/home/screens/home_screen.dart \
  test/features/home/home_screen_test.dart \
  test/features/home/home_provider_test.dart
git diff --check
```

Expected: formatting succeeds, both Flutter test files pass, focused analysis
reports no errors, and `git diff --check` emits no output.

- [ ] **Step 5: Review the final diff without staging unrelated changes**

Run:

```bash
git diff -- \
  lib/features/home/widgets/incomplete_visit_card.dart \
  lib/features/home/screens/home_screen.dart \
  test/features/home/home_screen_test.dart \
  test/features/home/home_provider_test.dart \
  docs/LIVING_SPEC.md
```

Confirm the diff implements only the incomplete-visits sector and preserves
the pre-existing edits in overlapping dirty files. Leave implementation
changes unstaged for human review unless the reviewer explicitly requests a
commit.
