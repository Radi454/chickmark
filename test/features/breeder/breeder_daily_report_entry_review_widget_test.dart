import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/breeder_bird_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_egg_inventory_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_isolation_area_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/features/breeder/screens/breeder_daily_report_entry_screen.dart';
import 'package:hatchaudit/features/breeder/screens/breeder_daily_report_review_screen.dart';
import 'package:hatchaudit/services/breeder/breeder_bird_ledger_service.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_inventory_service.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_production_service.dart';
import 'package:hatchaudit/services/breeder/breeder_flock_lifecycle_service.dart';

import 'fake_breeder_repositories.dart';

/// Widget coverage for the house-by-house entry screen and the
/// consolidated review screen (breeder-flock-performance ticket 07; extended
/// by ticket 08 for isolation areas). Uses in-memory fake repositories
/// rather than real sqflite (`testWidgets` hangs against the real database
/// past the first gesture — see repo convention) and bounded `pump` calls
/// instead of `pumpAndSettle`.
void main() {
  final flock = FlockModel(
    id: 'flock-1',
    customerId: 'customer-1',
    flockId: 'FLK-1',
    breed: 'Ross308',
    entryDate: DateTime(2026, 1, 1),
  );
  final houseA = HouseModel(
    id: 'house-a',
    flockId: 'flock-1',
    name: 'House A',
    openingFemales: 100,
    openingMales: 10,
  );
  final houseB = HouseModel(
    id: 'house-b',
    flockId: 'flock-1',
    name: 'House B',
    openingFemales: 50,
    openingMales: 5,
  );

  Future<void> pumpUi(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  ({
    FakeBreederDailyReportRepository reportRepository,
    FakeBreederBirdMovementRepository movementRepository,
    FakeHouseRepository houseRepository,
    FakeIsolationAreaRepository isolationAreaRepository,
    FakeBreederFeedEntryRepository feedEntryRepository,
    BreederBirdLedgerService service,
    FakeBreederEggGradeDefinitionRepository eggGradeRepository,
    FakeBreederEggProductionEntryRepository eggProductionEntryRepository,
    BreederEggProductionService eggProductionService,
    FakeBreederEggInventoryMovementRepository eggInventoryMovementRepository,
    BreederEggInventoryService eggInventoryService,
    BreederFlockLifecycleService lifecycleService,
    FakeBreederBenchmarkRepository benchmarkRepository,
  })
  buildStack({
    List<BreederIsolationArea> isolationAreas = const [],
    bool inProduction = false,
  }) {
    final reportRepository = FakeBreederDailyReportRepository();
    final movementRepository = FakeBreederBirdMovementRepository(
      reportRepository,
    );
    final houseRepository = FakeHouseRepository([houseA, houseB]);
    final isolationAreaRepository = FakeIsolationAreaRepository(
      List.of(isolationAreas),
    );
    final feedEntryRepository = FakeBreederFeedEntryRepository();
    final eggGradeRepository = FakeBreederEggGradeDefinitionRepository();
    final eggProductionEntryRepository = FakeBreederEggProductionEntryRepository(
      reportRepository,
    );
    final eggProductionService = BreederEggProductionService(
      gradeRepository: eggGradeRepository,
      entryRepository: eggProductionEntryRepository,
    );
    // Egg-inventory ledger fakes (breeder-flock-performance ticket 11).
    // `BreederBirdLedgerService.approve` always validates inventory
    // balances now, regardless of whether the flock has entered
    // production, so every test's `service` needs one of these — not just
    // the `inProduction: true` cases — or it falls back to the real,
    // database-backed `BreederEggInventoryService` and crashes in this
    // sqflite-free widget-test environment.
    final eggInventoryMovementRepository =
        FakeBreederEggInventoryMovementRepository(reportRepository);
    final eggInventoryService = BreederEggInventoryService(
      movementRepository: eggInventoryMovementRepository,
      gradeRepository: eggGradeRepository,
      productionEntryRepository: eggProductionEntryRepository,
    );
    final service = BreederBirdLedgerService(
      reportRepository: reportRepository,
      movementRepository: movementRepository,
      houseRepository: houseRepository,
      isolationAreaRepository: isolationAreaRepository,
      feedEntryRepository: feedEntryRepository,
      eggInventoryService: eggInventoryService,
    );
    final benchmarkRepository = FakeBreederBenchmarkRepository()
      ..inProduction = inProduction;
    final lifecycleService = BreederFlockLifecycleService(
      benchmarkRepository: benchmarkRepository,
      milestoneRepository: FakeBreederFlockMilestoneRepository(),
    );
    return (
      reportRepository: reportRepository,
      movementRepository: movementRepository,
      houseRepository: houseRepository,
      isolationAreaRepository: isolationAreaRepository,
      feedEntryRepository: feedEntryRepository,
      service: service,
      eggGradeRepository: eggGradeRepository,
      eggProductionEntryRepository: eggProductionEntryRepository,
      eggProductionService: eggProductionService,
      eggInventoryMovementRepository: eggInventoryMovementRepository,
      eggInventoryService: eggInventoryService,
      lifecycleService: lifecycleService,
      benchmarkRepository: benchmarkRepository,
    );
  }

  testWidgets('entry screen shows opening balances for every house', (
    tester,
  ) async {
    final stack = buildStack();
    final report = await stack.reportRepository.createDraft(
      flockId: flock.id,
      reportDate: DateTime(2026, 3, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BreederDailyReportEntryScreen(
          flock: flock,
          report: report,
          service: stack.service,
          houseRepository: stack.houseRepository,
          isolationAreaRepository: stack.isolationAreaRepository,
          movementRepository: stack.movementRepository,
          reportRepository: stack.reportRepository,
          feedEntryRepository: stack.feedEntryRepository,
          lifecycleService: stack.lifecycleService,
        ),
      ),
    );
    await pumpUi(tester);

    expect(find.text('House A'), findsOneWidget);
    // Opening female balance for house A (100) shown as a read-only field
    // (opening and closing both read 100 before any movement is entered).
    expect(find.text('100'), findsWidgets);

    // The report-header card (ticket 09) pushes House B out of the default
    // test viewport; scroll it into view like the isolation-area card
    // below.
    await tester.dragUntilVisible(
      find.text('House B'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await pumpUi(tester);
    expect(find.text('House B'), findsOneWidget);
    expect(find.text('50'), findsWidgets);
  });

  testWidgets('editing mortality updates the closing balance', (
    tester,
  ) async {
    final stack = buildStack();
    final report = await stack.reportRepository.createDraft(
      flockId: flock.id,
      reportDate: DateTime(2026, 3, 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BreederDailyReportEntryScreen(
          flock: flock,
          report: report,
          service: stack.service,
          houseRepository: stack.houseRepository,
          isolationAreaRepository: stack.isolationAreaRepository,
          movementRepository: stack.movementRepository,
          reportRepository: stack.reportRepository,
          feedEntryRepository: stack.feedEntryRepository,
          lifecycleService: stack.lifecycleService,
        ),
      ),
    );
    await pumpUi(tester);

    final mortalityField = find.byKey(
      const Key('house-a|female-mortality'),
    );
    expect(mortalityField, findsOneWidget);

    await tester.enterText(mortalityField, '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpUi(tester);

    final movement = await stack.movementRepository.getByReportHouseSex(
      report.id,
      'house-a',
      BreederBirdMovementSex.female,
    );
    expect(movement, isNotNull);
    expect(movement!.mortality, 5);
    expect(movement.closing, 95);
    expect(find.text('95'), findsOneWidget);
  });

  testWidgets('a negative-resulting closing balance shows an error', (
    tester,
  ) async {
    final stack = buildStack();
    final report = await stack.reportRepository.createDraft(
      flockId: flock.id,
      reportDate: DateTime(2026, 3, 3),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BreederDailyReportEntryScreen(
          flock: flock,
          report: report,
          service: stack.service,
          houseRepository: stack.houseRepository,
          isolationAreaRepository: stack.isolationAreaRepository,
          movementRepository: stack.movementRepository,
          reportRepository: stack.reportRepository,
          feedEntryRepository: stack.feedEntryRepository,
          lifecycleService: stack.lifecycleService,
        ),
      ),
    );
    await pumpUi(tester);

    final mortalityField = find.byKey(
      const Key('house-a|female-mortality'),
    );
    await tester.enterText(mortalityField, '99999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpUi(tester);

    expect(find.textContaining('negative closing balance'), findsOneWidget);

    final movement = await stack.movementRepository.getByReportHouseSex(
      report.id,
      'house-a',
      BreederBirdMovementSex.female,
    );
    // The bad value was never persisted; the row keeps its last-good state.
    expect(movement!.mortality, 0);
    expect(movement.closing, 100);
  });

  testWidgets(
    'review screen renders the consolidated table and allows submit',
    (tester) async {
      final stack = buildStack();
      final report = await stack.reportRepository.createDraft(
        flockId: flock.id,
        reportDate: DateTime(2026, 3, 4),
      );
      await stack.service.recordMovement(
        reportId: report.id,
        houseId: 'house-a',
        sex: BreederBirdMovementSex.female,
        opening: 100,
        mortality: 3,
      );
      await stack.service.recordMovement(
        reportId: report.id,
        houseId: 'house-b',
        sex: BreederBirdMovementSex.female,
        opening: 50,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BreederDailyReportReviewScreen(
            flock: flock,
            report: report,
            service: stack.service,
            houseRepository: stack.houseRepository,
            isolationAreaRepository: stack.isolationAreaRepository,
            movementRepository: stack.movementRepository,
            reportRepository: stack.reportRepository,
            benchmarkRepository: stack.benchmarkRepository,
            feedEntryRepository: stack.feedEntryRepository,
            lifecycleService: BreederFlockLifecycleService(
              benchmarkRepository: FakeBreederBenchmarkRepository(),
            ),
            actorUserIdOverride: 'user-entry',
            actorRoleOverride: 'auditor',
          ),
        ),
      );
      await pumpUi(tester);

      expect(find.text('House A'), findsWidgets);
      expect(find.text('House B'), findsWidgets);
      expect(find.text('Draft'), findsWidgets);
      expect(find.widgetWithText(ElevatedButton, 'Submit'), findsOneWidget);
      // Auditor role cannot approve, and the report isn't Submitted yet.
      expect(find.widgetWithText(ElevatedButton, 'Approve'), findsNothing);

      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Submit'));
      await pumpUi(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await pumpUi(tester);

      expect(find.text('Submitted'), findsWidgets);
    },
  );

  testWidgets('approval is refused for an insufficient role in the UI', (
    tester,
  ) async {
    final stack = buildStack();
    var report = await stack.reportRepository.createDraft(
      flockId: flock.id,
      reportDate: DateTime(2026, 3, 5),
    );
    await stack.service.recordMovement(
      reportId: report.id,
      houseId: 'house-a',
      sex: BreederBirdMovementSex.female,
      opening: 100,
    );
    report = await stack.service.submit(report, actorUserId: 'user-entry');

    await tester.pumpWidget(
      MaterialApp(
        home: BreederDailyReportReviewScreen(
          flock: flock,
          report: report,
          service: stack.service,
          houseRepository: stack.houseRepository,
          isolationAreaRepository: stack.isolationAreaRepository,
          movementRepository: stack.movementRepository,
          reportRepository: stack.reportRepository,
          benchmarkRepository: stack.benchmarkRepository,
          feedEntryRepository: stack.feedEntryRepository,
          lifecycleService: BreederFlockLifecycleService(
            benchmarkRepository: FakeBreederBenchmarkRepository(),
          ),
          actorUserIdOverride: 'user-auditor',
          actorRoleOverride: 'auditor',
        ),
      ),
    );
    await pumpUi(tester);

    // Auditor is not a permitted approval role, so no Approve button shows.
    expect(find.widgetWithText(ElevatedButton, 'Approve'), findsNothing);
  });

  testWidgets('a production manager can approve a Submitted report', (
    tester,
  ) async {
    final stack = buildStack();
    var report = await stack.reportRepository.createDraft(
      flockId: flock.id,
      reportDate: DateTime(2026, 3, 6),
    );
    await stack.service.recordMovement(
      reportId: report.id,
      houseId: 'house-a',
      sex: BreederBirdMovementSex.female,
      opening: 100,
    );
    report = await stack.service.submit(report, actorUserId: 'user-entry');

    await tester.pumpWidget(
      MaterialApp(
        home: BreederDailyReportReviewScreen(
          flock: flock,
          report: report,
          service: stack.service,
          houseRepository: stack.houseRepository,
          isolationAreaRepository: stack.isolationAreaRepository,
          movementRepository: stack.movementRepository,
          reportRepository: stack.reportRepository,
          benchmarkRepository: stack.benchmarkRepository,
          feedEntryRepository: stack.feedEntryRepository,
          lifecycleService: BreederFlockLifecycleService(
            benchmarkRepository: FakeBreederBenchmarkRepository(),
          ),
          actorUserIdOverride: 'user-pm',
          actorRoleOverride: 'production_manager',
        ),
      ),
    );
    await pumpUi(tester);

    expect(find.widgetWithText(ElevatedButton, 'Approve'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Approve'));
    await pumpUi(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await pumpUi(tester);

    expect(find.text('Approved'), findsWidgets);
  });

  group('isolation areas (breeder-flock-performance ticket 08)', () {
    final sickPen = BreederIsolationArea(id: 'area-1', flockId: 'flock-1', name: 'Sick Pen');

    testWidgets('an isolation area appears as its own location in entry', (
      tester,
    ) async {
      final stack = buildStack(isolationAreas: [sickPen]);
      final report = await stack.reportRepository.createDraft(
        flockId: flock.id,
        reportDate: DateTime(2026, 8, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BreederDailyReportEntryScreen(
            flock: flock,
            report: report,
            service: stack.service,
            houseRepository: stack.houseRepository,
            isolationAreaRepository: stack.isolationAreaRepository,
            movementRepository: stack.movementRepository,
            reportRepository: stack.reportRepository,
            feedEntryRepository: stack.feedEntryRepository,
          lifecycleService: stack.lifecycleService,
          ),
        ),
      );
      await pumpUi(tester);

      expect(find.text('House A'), findsOneWidget);
      // The report-header card (ticket 09) and the isolation area (the
      // third and tallest card) both push content out of the default test
      // viewport; scroll down to reach each in turn (the same lazy-ListView
      // pitfall documented on the review screen).
      await tester.dragUntilVisible(
        find.text('House B'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await pumpUi(tester);
      expect(find.text('House B'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Sick Pen'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await pumpUi(tester);
      expect(find.text('Sick Pen'), findsOneWidget);
      expect(find.byKey(const Key('isolation-badge-area-1')), findsOneWidget);

      // Isolation opens at 0, not any house's opening count.
      final transferInField = find.byKey(
        const Key('area-1|female-transferIn'),
      );
      expect(transferInField, findsOneWidget);
      await tester.enterText(transferInField, '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpUi(tester);

      final movement = await stack.movementRepository
          .getByReportIsolationAreaSex(
            report.id,
            'area-1',
            BreederBirdMovementSex.female,
          );
      expect(movement, isNotNull);
      expect(movement!.opening, 0);
      expect(movement.transferIn, 10);
      expect(movement.closing, 10);
    });

    testWidgets('an isolation area appears as its own row in review', (
      tester,
    ) async {
      final stack = buildStack(isolationAreas: [sickPen]);
      final report = await stack.reportRepository.createDraft(
        flockId: flock.id,
        reportDate: DateTime(2026, 8, 2),
      );
      await stack.service.recordMovement(
        reportId: report.id,
        houseId: 'house-a',
        sex: BreederBirdMovementSex.female,
        opening: 100,
        transferOut: 10,
      );
      await stack.service.recordMovement(
        reportId: report.id,
        isolationAreaId: 'area-1',
        sex: BreederBirdMovementSex.female,
        opening: 0,
        transferIn: 10,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BreederDailyReportReviewScreen(
            flock: flock,
            report: report,
            service: stack.service,
            houseRepository: stack.houseRepository,
            isolationAreaRepository: stack.isolationAreaRepository,
            movementRepository: stack.movementRepository,
            reportRepository: stack.reportRepository,
            benchmarkRepository: stack.benchmarkRepository,
            feedEntryRepository: stack.feedEntryRepository,
            lifecycleService: BreederFlockLifecycleService(
              benchmarkRepository: FakeBreederBenchmarkRepository(),
            ),
            actorUserIdOverride: 'user-entry',
            actorRoleOverride: 'auditor',
          ),
        ),
      );
      await pumpUi(tester);

      expect(find.text('House A'), findsWidgets);
      expect(find.textContaining('Sick Pen'), findsWidgets);
    });
  });

  group('feed and environment (breeder-flock-performance ticket 09)', () {
    testWidgets(
      'entering feed kg computes and displays grams per bird, never an '
      'editable field',
      (tester) async {
        final stack = buildStack();
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 9, 1),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportEntryScreen(
              flock: flock,
              report: report,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              feedEntryRepository: stack.feedEntryRepository,
          lifecycleService: stack.lifecycleService,
            ),
          ),
        );
        await pumpUi(tester);

        // House A opens with 100 females; feed of 10 kg -> 100 g/bird.
        final feedField = find.byKey(const Key('house-a|female-feedKg'));
        expect(feedField, findsOneWidget);
        await tester.enterText(feedField, '10');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUi(tester);

        final feedEntry = await stack.feedEntryRepository
            .getByReportHouseSex(
              report.id,
              'house-a',
              BreederBirdMovementSex.female,
            );
        expect(feedEntry, isNotNull);
        expect(feedEntry!.feedKg, 10);

        // Grams-per-bird never appears as an editable TextField anywhere —
        // only as a read-only InputDecorator showing the computed value
        // (10 kg * 1000 / 100 closing females = 100 g/bird).
        final derivedField = find.byKey(
          const Key('house-a|female-feedGramsPerBird'),
        );
        expect(derivedField, findsOneWidget);
        expect(
          find.descendant(of: derivedField, matching: find.byType(TextField)),
          findsNothing,
        );
        expect(
          find.descendant(of: derivedField, matching: find.text('100.0')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a house with zero closing birds shows a blank grams-per-bird value',
      (tester) async {
        final stack = buildStack();
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 9, 2),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportEntryScreen(
              flock: flock,
              report: report,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              feedEntryRepository: stack.feedEntryRepository,
          lifecycleService: stack.lifecycleService,
            ),
          ),
        );
        await pumpUi(tester);

        // Deplete house A's females to zero, then enter feed.
        final mortalityField = find.byKey(
          const Key('house-a|female-mortality'),
        );
        await tester.enterText(mortalityField, '100');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUi(tester);

        final feedField = find.byKey(const Key('house-a|female-feedKg'));
        await tester.enterText(feedField, '5');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUi(tester);

        final derivedField = find.byKey(
          const Key('house-a|female-feedGramsPerBird'),
        );
        expect(
          find.descendant(of: derivedField, matching: find.text('—')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'header fields persist inside/outside temperature, light hours, '
      'and notes',
      (tester) async {
        final stack = buildStack();
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 9, 3),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportEntryScreen(
              flock: flock,
              report: report,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              feedEntryRepository: stack.feedEntryRepository,
          lifecycleService: stack.lifecycleService,
            ),
          ),
        );
        await pumpUi(tester);

        await tester.enterText(
          find.byKey(const Key('header-insideTemperature')),
          '21',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.enterText(
          find.byKey(const Key('header-lightHours')),
          '16',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUi(tester);

        final updated = await stack.reportRepository.getById(report.id);
        expect(updated!.insideTemperature, 21);
        expect(updated.lightHours, 16);

        // The temperature field carries its own unit label — never a
        // single global unit toggle.
        expect(find.text('°C'), findsWidgets);
      },
    );

    testWidgets(
      'the review screen shows feed kg and derived grams per bird per '
      'location',
      (tester) async {
        final stack = buildStack();
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 9, 4),
        );
        await stack.service.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
        );
        await stack.service.recordFeedEntry(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          feedKg: 10,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportReviewScreen(
              flock: flock,
              report: report,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              benchmarkRepository: stack.benchmarkRepository,
              feedEntryRepository: stack.feedEntryRepository,
              lifecycleService: BreederFlockLifecycleService(
                benchmarkRepository: FakeBreederBenchmarkRepository(),
              ),
              actorUserIdOverride: 'user-entry',
              actorRoleOverride: 'auditor',
            ),
          ),
        );
        await pumpUi(tester);

        expect(find.text('10.0'), findsWidgets); // feed kg column
        // 10 kg * 1000 / 100 birds = 100.0 g/bird, printed at
        // `daily_feed_intake_g`'s displayPrecision (0) — breeder-flock
        // -performance ticket 19.
        expect(find.text('100'), findsWidgets);
      },
    );
  });

  group('egg production (breeder-flock-performance ticket 10)', () {
    testWidgets(
      'the egg section is hidden before the flock enters production',
      (tester) async {
        final stack = buildStack(); // inProduction defaults to false
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 5, 1),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportEntryScreen(
              flock: flock,
              report: report,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              feedEntryRepository: stack.feedEntryRepository,
              eggGradeRepository: stack.eggGradeRepository,
              eggProductionEntryRepository: stack.eggProductionEntryRepository,
              eggProductionService: stack.eggProductionService,
              eggInventoryMovementRepository: stack.eggInventoryMovementRepository,
              eggInventoryService: stack.eggInventoryService,
              lifecycleService: stack.lifecycleService,
            ),
          ),
        );
        await pumpUi(tester);

        expect(find.text('Egg production'), findsNothing);
        expect(find.text('First grade'), findsNothing);
      },
    );

    testWidgets(
      'the egg section appears once the flock has entered production, and '
      'total eggs is derived from grade counts, never typed',
      (tester) async {
        final stack = buildStack(inProduction: true);
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 5, 2),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportEntryScreen(
              flock: flock,
              report: report,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              feedEntryRepository: stack.feedEntryRepository,
              eggGradeRepository: stack.eggGradeRepository,
              eggProductionEntryRepository: stack.eggProductionEntryRepository,
              eggProductionService: stack.eggProductionService,
              eggInventoryMovementRepository: stack.eggInventoryMovementRepository,
              eggInventoryService: stack.eggInventoryService,
              lifecycleService: stack.lifecycleService,
            ),
          ),
        );
        await pumpUi(tester);

        expect(find.text('Egg production'), findsWidgets);
        expect(find.text('First grade'), findsWidgets);

        final firstGradeField = find.byKey(
          const Key('egg-house-a-first_grade'),
        );
        expect(firstGradeField, findsOneWidget);
        await tester.enterText(firstGradeField, '80');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUi(tester);

        final crackedField = find.byKey(const Key('egg-house-a-cracked'));
        await tester.enterText(crackedField, '5');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUi(tester);

        // Total eggs (85) is calculated from the two grade counts entered —
        // never independently typed.
        final totalEggsField = find.byKey(
          const Key('egg-house-a-totalEggs'),
        );
        expect(totalEggsField, findsOneWidget);
        expect(
          find.descendant(of: totalEggsField, matching: find.text('85')),
          findsOneWidget,
        );

        final entries = await stack.eggProductionEntryRepository.getForReport(
          report.id,
        );
        final houseAEntries = entries.where((e) => e.houseId == 'house-a');
        expect(
          houseAEntries.fold<int>(0, (a, e) => a + e.count),
          85,
        );
      },
    );

    testWidgets(
      'a negative egg-grade count is rejected and shows an error',
      (tester) async {
        final stack = buildStack(inProduction: true);
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 5, 3),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportEntryScreen(
              flock: flock,
              report: report,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              feedEntryRepository: stack.feedEntryRepository,
              eggGradeRepository: stack.eggGradeRepository,
              eggProductionEntryRepository: stack.eggProductionEntryRepository,
              eggProductionService: stack.eggProductionService,
              eggInventoryMovementRepository: stack.eggInventoryMovementRepository,
              eggInventoryService: stack.eggInventoryService,
              lifecycleService: stack.lifecycleService,
            ),
          ),
        );
        await pumpUi(tester);

        // int.tryParse('-1') is a genuine negative int (unlike the movement
        // fields' plain TextInputType.number keyboard, this reaches the
        // service with a real negative value), so this exercises
        // `BreederEggProductionValidationError` end to end.
        final firstGradeField = find.byKey(
          const Key('egg-house-a-first_grade'),
        );
        await tester.enterText(firstGradeField, '-1');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUi(tester);

        expect(find.textContaining('cannot be negative'), findsOneWidget);
      },
    );

    testWidgets(
      'the review screen shows the grade partition rule, calculated total '
      'eggs, and the hen-week/hen-housed comparison note',
      (tester) async {
        final stack = buildStack(inProduction: true);
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 5, 4),
        );
        // House A: closing 100 females (no movements recorded yet, so
        // opening==closing via the ledger's lazy initialization).
        await stack.eggProductionService.recordGradeCount(
          reportId: report.id,
          houseId: 'house-a',
          gradeId: (await stack.eggGradeRepository.getByCode('first_grade'))!.id,
          count: 90,
        );
        await stack.movementRepository.upsert(
          BreederBirdMovement(
            id: 'mv-eggreview-1',
            reportId: report.id,
            houseId: 'house-a',
            sex: BreederBirdMovementSex.female,
            opening: 100,
            closing: 100,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportReviewScreen(
              flock: flock,
              report: report,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              benchmarkRepository: stack.benchmarkRepository,
              feedEntryRepository: stack.feedEntryRepository,
              eggGradeRepository: stack.eggGradeRepository,
              eggProductionEntryRepository: stack.eggProductionEntryRepository,
              eggInventoryMovementRepository: stack.eggInventoryMovementRepository,
              eggInventoryService: stack.eggInventoryService,
              lifecycleService: stack.lifecycleService,
              actorUserIdOverride: 'user-review',
              actorRoleOverride: 'production_manager',
            ),
          ),
        );
        await pumpUi(tester);

        expect(find.text('Egg production'), findsOneWidget);
        expect(find.textContaining('highest-priority'), findsOneWidget);
        expect(find.text('About this comparison'), findsOneWidget);
        expect(find.textContaining('hen-week'), findsOneWidget);
        expect(find.textContaining('hen-day'), findsNothing);
        // 90 eggs / 100 closing females = 90%.
        expect(find.text('90.0%'), findsWidgets);
      },
    );

    testWidgets(
      'approving a report in production retains the denominator and '
      'benchmark profile version on the report',
      (tester) async {
        final stack = buildStack(inProduction: true);
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 5, 5),
        );
        await stack.movementRepository.upsert(
          BreederBirdMovement(
            id: 'mv-eggapprove-1',
            reportId: report.id,
            houseId: 'house-a',
            sex: BreederBirdMovementSex.female,
            opening: 100,
            closing: 100,
          ),
        );
        final submitted = await stack.service.submit(
          report,
          actorUserId: 'user-review',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportReviewScreen(
              flock: flock,
              report: submitted,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              benchmarkRepository: stack.benchmarkRepository,
              feedEntryRepository: stack.feedEntryRepository,
              eggGradeRepository: stack.eggGradeRepository,
              eggProductionEntryRepository: stack.eggProductionEntryRepository,
              eggInventoryMovementRepository: stack.eggInventoryMovementRepository,
              eggInventoryService: stack.eggInventoryService,
              lifecycleService: stack.lifecycleService,
              actorUserIdOverride: 'user-review',
              actorRoleOverride: 'production_manager',
            ),
          ),
        );
        await pumpUi(tester);

        await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Approve'));
        await pumpUi(tester);
        await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
        await pumpUi(tester);

        final approved = await stack.reportRepository.getById(report.id);
        expect(approved!.isApproved, isTrue);
        expect(approved.eggProductionDenominatorFemales, 100);
        expect(approved.benchmarkProfileVersionAtApproval, 'Fake Guide v1');
        expect(approved.comparisonAxisAtApproval, isNotNull);
      },
    );
  });

  group('egg inventory (breeder-flock-performance ticket 11)', () {
    testWidgets(
      'the inventory section shows read-only previous/available/closing '
      'balances and lets dispatched-to-hatchery be entered',
      (tester) async {
        final stack = buildStack(inProduction: true);
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 7, 1),
        );
        final firstGrade = (await stack.eggGradeRepository.getByCode(
          'first_grade',
        ))!;
        await stack.eggProductionService.recordGradeCount(
          reportId: report.id,
          houseId: 'house-a',
          gradeId: firstGrade.id,
          count: 50,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportEntryScreen(
              flock: flock,
              report: report,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              feedEntryRepository: stack.feedEntryRepository,
              eggGradeRepository: stack.eggGradeRepository,
              eggProductionEntryRepository: stack.eggProductionEntryRepository,
              eggProductionService: stack.eggProductionService,
              eggInventoryMovementRepository: stack.eggInventoryMovementRepository,
              eggInventoryService: stack.eggInventoryService,
              lifecycleService: stack.lifecycleService,
            ),
          ),
        );
        await pumpUi(tester);

        await tester.dragUntilVisible(
          find.text('Egg inventory'),
          find.byType(ListView),
          const Offset(0, -300),
        );
        await pumpUi(tester);
        expect(find.text('Egg inventory'), findsOneWidget);

        // Previous balance, today's production, and available balance are
        // never editable TextFields — always read-only InputDecorators.
        final productionField = find.byKey(
          const Key('inventory-first_grade-production'),
        );
        expect(productionField, findsOneWidget);
        expect(
          find.descendant(of: productionField, matching: find.byType(TextField)),
          findsNothing,
        );
        expect(
          find.descendant(of: productionField, matching: find.text('50')),
          findsOneWidget,
        );
        final availableField = find.byKey(
          const Key('inventory-first_grade-available'),
        );
        expect(
          find.descendant(of: availableField, matching: find.text('50')),
          findsOneWidget,
        );

        final dispatchedField = find.byKey(
          const Key('inventory-first_grade-dispatched'),
        );
        await tester.dragUntilVisible(
          dispatchedField,
          find.byType(ListView),
          const Offset(0, -100),
        );
        await pumpUi(tester);
        expect(dispatchedField, findsOneWidget);
        await tester.enterText(dispatchedField, '20');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUi(tester);

        final closingField = find.byKey(
          const Key('inventory-first_grade-closing'),
        );
        await tester.dragUntilVisible(
          closingField,
          find.byType(ListView),
          const Offset(0, -100),
        );
        await pumpUi(tester);

        expect(
          find.descendant(of: closingField, matching: find.text('30')),
          findsOneWidget,
        );

        final movements = await stack.eggInventoryMovementRepository
            .getForReportAndGrade(report.id, firstGrade.id);
        expect(movements, hasLength(1));
        expect(movements.first.quantity, 20);
      },
    );

    testWidgets(
      'over-dispatching beyond the available balance shows an error and '
      'does not persist',
      (tester) async {
        final stack = buildStack(inProduction: true);
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 7, 2),
        );
        final firstGrade = (await stack.eggGradeRepository.getByCode(
          'first_grade',
        ))!;
        await stack.eggProductionService.recordGradeCount(
          reportId: report.id,
          houseId: 'house-a',
          gradeId: firstGrade.id,
          count: 10,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportEntryScreen(
              flock: flock,
              report: report,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              feedEntryRepository: stack.feedEntryRepository,
              eggGradeRepository: stack.eggGradeRepository,
              eggProductionEntryRepository: stack.eggProductionEntryRepository,
              eggProductionService: stack.eggProductionService,
              eggInventoryMovementRepository: stack.eggInventoryMovementRepository,
              eggInventoryService: stack.eggInventoryService,
              lifecycleService: stack.lifecycleService,
            ),
          ),
        );
        await pumpUi(tester);

        await tester.dragUntilVisible(
          find.byKey(const Key('inventory-first_grade-dispatched')),
          find.byType(ListView),
          const Offset(0, -300),
        );
        await pumpUi(tester);

        final dispatchedField = find.byKey(
          const Key('inventory-first_grade-dispatched'),
        );
        await tester.enterText(dispatchedField, '11');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUi(tester);

        // The error banner sits above the location cards, near the top of
        // the ListView — scroll back up to it (the same lazy-ListView
        // pitfall documented elsewhere in this file).
        await tester.dragUntilVisible(
          find.textContaining('drive the closing balance negative'),
          find.byType(ListView),
          const Offset(0, 300),
        );
        await pumpUi(tester);
        expect(
          find.textContaining('drive the closing balance negative'),
          findsOneWidget,
        );
        final movements = await stack.eggInventoryMovementRepository
            .getForReportAndGrade(report.id, firstGrade.id);
        expect(movements, isEmpty);
      },
    );

    testWidgets(
      'the review screen shows the egg-inventory table with previous, '
      'production, available, and closing balances',
      (tester) async {
        final stack = buildStack(inProduction: true);
        final report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 7, 3),
        );
        final firstGrade = (await stack.eggGradeRepository.getByCode(
          'first_grade',
        ))!;
        await stack.eggProductionService.recordGradeCount(
          reportId: report.id,
          houseId: 'house-a',
          gradeId: firstGrade.id,
          count: 60,
        );
        await stack.eggInventoryService.recordMovement(
          report: report,
          gradeId: firstGrade.id,
          kind: BreederEggInventoryMovementKind.sale,
          quantity: 15,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BreederDailyReportReviewScreen(
              flock: flock,
              report: report,
              service: stack.service,
              houseRepository: stack.houseRepository,
              isolationAreaRepository: stack.isolationAreaRepository,
              movementRepository: stack.movementRepository,
              reportRepository: stack.reportRepository,
              benchmarkRepository: stack.benchmarkRepository,
              feedEntryRepository: stack.feedEntryRepository,
              eggGradeRepository: stack.eggGradeRepository,
              eggProductionEntryRepository: stack.eggProductionEntryRepository,
              eggInventoryMovementRepository: stack.eggInventoryMovementRepository,
              eggInventoryService: stack.eggInventoryService,
              lifecycleService: stack.lifecycleService,
              actorUserIdOverride: 'user-review',
              actorRoleOverride: 'production_manager',
            ),
          ),
        );
        await pumpUi(tester);

        expect(find.text('Egg inventory'), findsOneWidget);
        // 60 produced, 15 sold -> 45 closing.
        expect(find.text('45'), findsWidgets);
      },
    );
  });
}
