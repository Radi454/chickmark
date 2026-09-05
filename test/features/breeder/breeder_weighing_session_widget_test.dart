import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/features/breeder/screens/breeder_weighing_session_entry_screen.dart';
import 'package:hatchaudit/features/breeder/screens/breeder_weighing_session_list_screen.dart';
import 'package:hatchaudit/services/breeder/breeder_flock_lifecycle_service.dart';
import 'package:hatchaudit/services/breeder/breeder_weighing_service.dart';

import 'fake_breeder_repositories.dart';

/// Widget coverage for the weighing session list/entry workflow
/// (breeder-flock-performance ticket 13). Uses in-memory fake repositories
/// rather than real sqflite (`testWidgets` hangs against the real database
/// past the first gesture — repo convention) and bounded `pump` calls
/// instead of `pumpAndSettle`.
void main() {
  // The entry screen defaults a new session's date to `DateTime.now()` and
  // has no date-field key to override it in these tests, so the flock's
  // entryDate is set exactly 7 days before "now" here — putting the
  // session's implied age at exactly ageWeek 1, matching the fake
  // benchmark's seeded ('female', 1) -> 115g target below.
  final today = DateTime.now();
  final entryDate = DateTime(today.year, today.month, today.day).subtract(
    const Duration(days: 7),
  );
  final flock = FlockModel(
    id: 'flock-1',
    customerId: 'customer-1',
    flockId: 'FLK-1',
    breed: 'Ross308',
    entryDate: entryDate,
  );
  final house = HouseModel(id: 'house-a', flockId: 'flock-1', name: 'House A');

  Future<void> pumpUi(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  ({
    FakeBreederWeighingSessionRepository sessionRepository,
    FakeBreederWeighingSampleRepository sampleRepository,
    FakeHouseRepository houseRepository,
    FakeBreederBenchmarkRepository benchmarkRepository,
    BreederWeighingService service,
  })
  buildStack() {
    final sessionRepository = FakeBreederWeighingSessionRepository();
    final sampleRepository = FakeBreederWeighingSampleRepository();
    final houseRepository = FakeHouseRepository([house]);
    final benchmarkRepository = FakeBreederBenchmarkRepository()
      ..inProduction = true
      ..weightTargets[('female', 1)] = 115.0;
    final lifecycleService = BreederFlockLifecycleService(
      benchmarkRepository: benchmarkRepository,
      milestoneRepository: FakeBreederFlockMilestoneRepository(),
    );
    final service = BreederWeighingService(
      sessionRepository: sessionRepository,
      sampleRepository: sampleRepository,
      benchmarkRepository: benchmarkRepository,
      lifecycleService: lifecycleService,
    );
    return (
      sessionRepository: sessionRepository,
      sampleRepository: sampleRepository,
      houseRepository: houseRepository,
      benchmarkRepository: benchmarkRepository,
      service: service,
    );
  }

  testWidgets('empty list shows the empty state and a New session button', (tester) async {
    final stack = buildStack();
    await tester.pumpWidget(
      MaterialApp(
        home: BreederWeighingSessionListScreen(
          flock: flock,
          repository: stack.sessionRepository,
        ),
      ),
    );
    await pumpUi(tester);

    expect(find.textContaining('No weighing sessions yet'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('creating a session with samples shows derived figures and the official target', (tester) async {
    final stack = buildStack();
    await tester.pumpWidget(
      MaterialApp(
        home: BreederWeighingSessionEntryScreen(
          flock: flock,
          service: stack.service,
          houseRepository: stack.houseRepository,
          sampleRepository: stack.sampleRepository,
        ),
      ),
    );
    await pumpUi(tester);

    // House and sex default to the first available option (female).
    await tester.enterText(
      find.byKey(const Key('weighing_method_field')),
      'Individual bird scale',
    );
    await tester.enterText(
      find.byKey(const Key('weighing_sample_size_field')),
      '3',
    );

    for (var i = 0; i < 3; i++) {
      await tester.ensureVisible(find.byKey(const Key('weighing_add_weight_button')));
      await pumpUi(tester);
      await tester.tap(find.byKey(const Key('weighing_add_weight_button')), warnIfMissed: false);
      await pumpUi(tester);
    }

    for (final entry in const [
      (0, '100'),
      (1, '115'),
      (2, '130'),
    ]) {
      final field = find.byKey(Key('weighing_weight_field_${entry.$1}'));
      await tester.ensureVisible(field);
      await pumpUi(tester);
      await tester.enterText(field, entry.$2);
    }

    await tester.ensureVisible(find.text('Create session'));
    await pumpUi(tester);
    await tester.tap(find.text('Create session'));
    await pumpUi(tester);

    expect(find.text('115.0 g'), findsOneWidget);
    expect(find.textContaining('Target'), findsOneWidget);
    expect(find.textContaining('115.0 g'), findsWidgets);
  });

  testWidgets('creating a summary-only session (no weights) shows "Summary only"', (tester) async {
    final stack = buildStack();
    await tester.pumpWidget(
      MaterialApp(
        home: BreederWeighingSessionEntryScreen(
          flock: flock,
          service: stack.service,
          houseRepository: stack.houseRepository,
          sampleRepository: stack.sampleRepository,
        ),
      ),
    );
    await pumpUi(tester);

    await tester.enterText(
      find.byKey(const Key('weighing_method_field')),
      'Batch/platform scale',
    );
    await tester.enterText(
      find.byKey(const Key('weighing_sample_size_field')),
      '50',
    );

    await tester.ensureVisible(find.text('Create session'));
    await pumpUi(tester);
    await tester.tap(find.text('Create session'));
    await pumpUi(tester);

    expect(find.textContaining('Summary only'), findsOneWidget);
  });

  testWidgets('a validation error is shown for a non-positive sample size', (tester) async {
    final stack = buildStack();
    await tester.pumpWidget(
      MaterialApp(
        home: BreederWeighingSessionEntryScreen(
          flock: flock,
          service: stack.service,
          houseRepository: stack.houseRepository,
          sampleRepository: stack.sampleRepository,
        ),
      ),
    );
    await pumpUi(tester);

    await tester.enterText(
      find.byKey(const Key('weighing_method_field')),
      'Individual bird scale',
    );
    await tester.enterText(
      find.byKey(const Key('weighing_sample_size_field')),
      '0',
    );

    await tester.ensureVisible(find.text('Create session'));
    await pumpUi(tester);
    await tester.tap(find.text('Create session'));
    await pumpUi(tester);

    expect(find.textContaining('positive sample size'), findsOneWidget);
  });
}
