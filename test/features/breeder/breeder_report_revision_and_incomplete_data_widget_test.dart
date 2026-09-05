import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/breeder_bird_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_isolation_area_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/features/breeder/screens/breeder_daily_report_review_screen.dart';
import 'package:hatchaudit/features/breeder/widgets/breeder_incomplete_data_label.dart';
import 'package:hatchaudit/services/breeder/breeder_bird_ledger_service.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_inventory_service.dart';
import 'package:hatchaudit/services/breeder/breeder_flock_lifecycle_service.dart';
import 'package:hatchaudit/services/breeder/breeder_report_period_service.dart';
import 'package:hatchaudit/services/breeder/breeder_report_revision_service.dart';

import 'fake_breeder_repositories.dart';

/// Widget coverage for the post-approval correction/revision-history UI and
/// the incomplete-data label (breeder-flock-performance ticket 12). Uses
/// in-memory fakes rather than real sqflite (`testWidgets` hangs against the
/// real database past the first gesture — repo convention) and bounded
/// `pump` calls instead of `pumpAndSettle`.
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
    FakeBreederEggGradeDefinitionRepository eggGradeRepository,
    FakeBreederEggProductionEntryRepository eggProductionEntryRepository,
    FakeBreederEggInventoryMovementRepository eggInventoryMovementRepository,
    BreederEggInventoryService eggInventoryService,
    FakeBreederReportRevisionRepository revisionRepository,
    BreederReportRevisionService revisionService,
    BreederBirdLedgerService service,
    FakeBreederBenchmarkRepository benchmarkRepository,
  })
  buildStack() {
    final reportRepository = FakeBreederDailyReportRepository();
    final movementRepository = FakeBreederBirdMovementRepository(
      reportRepository,
    );
    final houseRepository = FakeHouseRepository([houseA]);
    final isolationAreaRepository = FakeIsolationAreaRepository(
      const <BreederIsolationArea>[],
    );
    final feedEntryRepository = FakeBreederFeedEntryRepository();
    final eggGradeRepository = FakeBreederEggGradeDefinitionRepository();
    final eggProductionEntryRepository = FakeBreederEggProductionEntryRepository(
      reportRepository,
    );
    final eggInventoryMovementRepository =
        FakeBreederEggInventoryMovementRepository(reportRepository);
    final eggInventoryService = BreederEggInventoryService(
      movementRepository: eggInventoryMovementRepository,
      gradeRepository: eggGradeRepository,
      productionEntryRepository: eggProductionEntryRepository,
    );
    final revisionRepository = FakeBreederReportRevisionRepository();
    final revisionService = BreederReportRevisionService(
      revisionRepository: revisionRepository,
      reportRepository: reportRepository,
    );
    final benchmarkRepository = FakeBreederBenchmarkRepository();
    final service = BreederBirdLedgerService(
      reportRepository: reportRepository,
      movementRepository: movementRepository,
      houseRepository: houseRepository,
      isolationAreaRepository: isolationAreaRepository,
      feedEntryRepository: feedEntryRepository,
      eggInventoryService: eggInventoryService,
      revisionService: revisionService,
    );
    return (
      reportRepository: reportRepository,
      movementRepository: movementRepository,
      houseRepository: houseRepository,
      isolationAreaRepository: isolationAreaRepository,
      feedEntryRepository: feedEntryRepository,
      eggGradeRepository: eggGradeRepository,
      eggProductionEntryRepository: eggProductionEntryRepository,
      eggInventoryMovementRepository: eggInventoryMovementRepository,
      eggInventoryService: eggInventoryService,
      revisionRepository: revisionRepository,
      revisionService: revisionService,
      service: service,
      benchmarkRepository: benchmarkRepository,
    );
  }

  Widget buildReviewScreen(
    dynamic stack, {
    required dynamic report,
  }) {
    return MaterialApp(
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
        revisionRepository: stack.revisionRepository,
        revisionService: stack.revisionService,
        lifecycleService: BreederFlockLifecycleService(
          benchmarkRepository: FakeBreederBenchmarkRepository(),
        ),
        actorUserIdOverride: 'user-pm',
        actorRoleOverride: 'production_manager',
      ),
    );
  }

  group('post-approval correction and revision history', () {
    testWidgets(
      'an Approved report shows Correct report and Revision history actions',
      (tester) async {
        final stack = buildStack();
        var report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 6, 1),
        );
        await stack.service.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
        );
        report = await stack.service.submit(report, actorUserId: 'user-entry');
        report = await stack.service.approve(
          report,
          actorUserId: 'user-pm',
          actorRole: 'production_manager',
        );

        await tester.pumpWidget(buildReviewScreen(stack, report: report));
        await pumpUi(tester);

        expect(find.widgetWithText(OutlinedButton, 'Correct report'), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, 'Revision history'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the correction dialog requires a reason before Save is enabled',
      (tester) async {
        final stack = buildStack();
        var report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 6, 2),
        );
        await stack.service.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
        );
        report = await stack.service.submit(report, actorUserId: 'user-entry');
        report = await stack.service.approve(
          report,
          actorUserId: 'user-pm',
          actorRole: 'production_manager',
        );

        await tester.pumpWidget(buildReviewScreen(stack, report: report));
        await pumpUi(tester);

        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, 'Correct report'),
        );
        await pumpUi(tester);
        await tester.tap(find.widgetWithText(OutlinedButton, 'Correct report'));
        await pumpUi(tester);

        final saveButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Save correction'),
        );
        expect(saveButton.onPressed, isNull);

        await tester.enterText(
          find.byKey(const Key('correctionReasonField')),
          'Data entry mistake',
        );
        await pumpUi(tester);

        final enabledSaveButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Save correction'),
        );
        expect(enabledSaveButton.onPressed, isNotNull);
      },
    );

    testWidgets(
      'saving a correction with a reason records revision history and shows it',
      (tester) async {
        final stack = buildStack();
        var report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 6, 3),
          notes: 'original notes',
        );
        await stack.service.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
        );
        report = await stack.service.submit(report, actorUserId: 'user-entry');
        report = await stack.service.approve(
          report,
          actorUserId: 'user-pm',
          actorRole: 'production_manager',
        );

        await tester.pumpWidget(buildReviewScreen(stack, report: report));
        await pumpUi(tester);

        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, 'Correct report'),
        );
        await pumpUi(tester);
        await tester.tap(find.widgetWithText(OutlinedButton, 'Correct report'));
        await pumpUi(tester);

        await tester.enterText(
          find.byKey(const Key('correctionReasonField')),
          'Notes were wrong',
        );
        await tester.enterText(
          find.byKey(const Key('correctionNotesField')),
          'corrected notes',
        );
        await pumpUi(tester);
        await tester.tap(find.widgetWithText(ElevatedButton, 'Save correction'));
        await pumpUi(tester);

        final history = await stack.revisionService.historyFor(report.id);
        expect(history, isNotEmpty);
        expect(history.any((r) => r.fieldName == 'notes'), isTrue);
        expect(history.first.reason, 'Notes were wrong');
        expect(history.first.actorUserId, 'user-pm');

        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, 'Revision history'),
        );
        await pumpUi(tester);
        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Revision history'),
        );
        await pumpUi(tester);

        expect(find.byKey(const Key('revisionHistoryList')), findsOneWidget);
        expect(find.textContaining('Notes were wrong'), findsOneWidget);
      },
    );

    testWidgets(
      'picking a bird-movement target corrects that movement and records a revision row',
      (tester) async {
        final stack = buildStack();
        var report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 6, 5),
        );
        await stack.service.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
          mortality: 2,
        );
        report = await stack.service.submit(report, actorUserId: 'user-entry');
        report = await stack.service.approve(
          report,
          actorUserId: 'user-pm',
          actorRole: 'production_manager',
        );

        await tester.pumpWidget(buildReviewScreen(stack, report: report));
        await pumpUi(tester);

        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, 'Correct report'),
        );
        await pumpUi(tester);
        await tester.tap(find.widgetWithText(OutlinedButton, 'Correct report'));
        await pumpUi(tester);

        Future<void> pumpMenu() async {
          // The dropdown menu opens via a route push/pop animation; give it
          // a few more (still bounded, non-settling) frames than the plain
          // rebuild pumps elsewhere in this file need.
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        // Switch the target picker from the default "Header fields" to
        // "Bird movement".
        await tester.tap(find.byKey(const Key('correctionTargetPicker')));
        await pumpMenu();
        await tester.tap(find.text('Bird movement').last);
        await pumpMenu();

        // Pick the one recorded movement row.
        await tester.tap(find.byKey(const Key('correctionMovementPicker')));
        await pumpMenu();
        await tester.tap(find.text('House A — Female').last);
        await pumpMenu();

        await tester.enterText(
          find.byKey(const Key('correctionReasonField')),
          'Mortality was miscounted',
        );
        await tester.enterText(
          find.byKey(const Key('correctionMortalityField')),
          '5',
        );
        await pumpUi(tester);
        await tester.tap(find.widgetWithText(ElevatedButton, 'Save correction'));
        await pumpUi(tester);

        final corrected = await stack.reportRepository.getById(report.id);
        expect(corrected, isNotNull);

        final history = await stack.revisionService.historyFor(report.id);
        expect(history, isNotEmpty);
        expect(history.any((r) => r.tableName == 'breeder_bird_movements'), isTrue);
        final mortalityRow = history.singleWhere(
          (r) => r.fieldName == 'mortality',
        );
        expect(mortalityRow.oldValue, '2');
        expect(mortalityRow.newValue, '5');
        expect(mortalityRow.reason, 'Mortality was miscounted');
      },
    );

    testWidgets(
      'Revision history shows an empty state when nothing has been corrected',
      (tester) async {
        final stack = buildStack();
        var report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: DateTime(2026, 6, 4),
        );
        await stack.service.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
        );
        report = await stack.service.submit(report, actorUserId: 'user-entry');
        report = await stack.service.approve(
          report,
          actorUserId: 'user-pm',
          actorRole: 'production_manager',
        );

        await tester.pumpWidget(buildReviewScreen(stack, report: report));
        await pumpUi(tester);

        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, 'Revision history'),
        );
        await pumpUi(tester);
        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Revision history'),
        );
        await pumpUi(tester);

        expect(find.byKey(const Key('revisionHistoryEmpty')), findsOneWidget);
      },
    );
  });

  group('incomplete-data label', () {
    testWidgets('renders nothing for a complete period', (tester) async {
      final completeness = BreederPeriodCompleteness(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 7),
        recordedDates: List.generate(
          7,
          (i) => DateTime(2026, 1, 1 + i),
        ),
        missingDates: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BreederIncompleteDataLabel(completeness: completeness),
          ),
        ),
      );
      await pumpUi(tester);

      expect(find.byKey(const Key('breederIncompleteDataLabel')), findsNothing);
      expect(find.text('Incomplete Data'), findsNothing);
    });

    testWidgets(
      'shows "Incomplete Data" with recorded and missing day counts prominently',
      (tester) async {
        final completeness = BreederPeriodCompleteness(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 7),
          recordedDates: [
            DateTime(2026, 1, 1),
            DateTime(2026, 1, 2),
            DateTime(2026, 1, 3),
          ],
          missingDates: [
            DateTime(2026, 1, 4),
            DateTime(2026, 1, 5),
            DateTime(2026, 1, 6),
            DateTime(2026, 1, 7),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BreederIncompleteDataLabel(completeness: completeness),
            ),
          ),
        );
        await pumpUi(tester);

        expect(find.byKey(const Key('breederIncompleteDataLabel')), findsOneWidget);
        expect(find.text('Incomplete Data'), findsOneWidget);
        expect(find.textContaining('3 / 7'), findsOneWidget);
        expect(find.textContaining('4'), findsWidgets);
      },
    );

    testWidgets('the partial-data benchmark warning shows only when incomplete', (
      tester,
    ) async {
      final complete = BreederPeriodCompleteness(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 2),
        recordedDates: [DateTime(2026, 1, 1), DateTime(2026, 1, 2)],
        missingDates: const [],
      );
      final periodService = BreederReportPeriodService();
      final completeComparison = periodService.compareToBenchmark(
        actualValue: 90,
        benchmarkValue: 95,
        completeness: complete,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BreederPartialDataWarning(comparison: completeComparison),
          ),
        ),
      );
      await pumpUi(tester);
      expect(find.byKey(const Key('breederPartialDataWarning')), findsNothing);

      final partial = BreederPeriodCompleteness(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 7),
        recordedDates: [DateTime(2026, 1, 1)],
        missingDates: List.generate(6, (i) => DateTime(2026, 1, 2 + i)),
      );
      final partialComparison = periodService.compareToBenchmark(
        actualValue: 90,
        benchmarkValue: 95,
        completeness: partial,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BreederPartialDataWarning(comparison: partialComparison),
          ),
        ),
      );
      await pumpUi(tester);
      expect(find.byKey(const Key('breederPartialDataWarning')), findsOneWidget);
      expect(find.textContaining('Partial data'), findsOneWidget);
    });
  });
}
