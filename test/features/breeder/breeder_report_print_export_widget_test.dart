import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/breeder_bird_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_isolation_area_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/features/breeder/screens/breeder_daily_report_review_screen.dart';
import 'package:hatchaudit/features/breeder/services/breeder_report_composition.dart';
import 'package:hatchaudit/features/breeder/services/breeder_report_pdf_export.dart';
import 'package:hatchaudit/services/breeder/breeder_bird_ledger_service.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_inventory_service.dart';
import 'package:hatchaudit/services/breeder/breeder_flock_lifecycle_service.dart';
import 'package:hatchaudit/services/breeder/breeder_report_revision_service.dart';

import 'fake_breeder_repositories.dart';

/// Records the composition it was asked to print instead of touching the
/// platform print/share channel (breeder-flock-performance ticket 19) —
/// `Printing.layoutPdf` has no platform implementation in a widget test.
class _RecordingPdfExport extends BreederReportPdfExport {
  const _RecordingPdfExport(this.calls);

  final List<BreederReportComposition> calls;

  @override
  Future<void> printOrShare({
    required BreederReportComposition composition,
    required String flockLabel,
    required String reportDateLabel,
    required bool rtl,
    required String Function(String key) translate,
  }) async {
    calls.add(composition);
  }
}

/// Widget coverage for the print/export entry point on the consolidated
/// review screen (breeder-flock-performance ticket 19). Uses in-memory
/// fakes rather than real sqflite (`testWidgets` hangs against the real
/// database past the first gesture — repo convention) and bounded `pump`
/// calls instead of `pumpAndSettle`.
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
      benchmarkRepository: FakeBreederBenchmarkRepository(),
    );
  }

  Widget buildReviewScreen(
    dynamic stack,
    dynamic report,
    List<BreederReportComposition> printCalls,
  ) {
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
        pdfExport: _RecordingPdfExport(printCalls),
        actorUserIdOverride: 'user-pm',
        actorRoleOverride: 'production_manager',
      ),
    );
  }

  testWidgets('the Print / Export action is offered on a Draft report', (
    tester,
  ) async {
    final stack = buildStack();
    final report = await stack.reportRepository.createDraft(
      flockId: flock.id,
      reportDate: DateTime(2026, 7, 1),
    );
    final calls = <BreederReportComposition>[];

    await tester.pumpWidget(buildReviewScreen(stack, report, calls));
    await pumpUi(tester);

    expect(find.byKey(const Key('printOrExportButton')), findsOneWidget);
  });

  testWidgets(
    'tapping Print / Export builds a composition matching this report, not '
    'approved and at revision 1',
    (tester) async {
      final stack = buildStack();
      var report = await stack.reportRepository.createDraft(
        flockId: flock.id,
        reportDate: DateTime(2026, 7, 2),
      );
      await stack.service.recordMovement(
        reportId: report.id,
        houseId: 'house-a',
        sex: BreederBirdMovementSex.female,
        opening: 100,
      );
      final calls = <BreederReportComposition>[];

      await tester.pumpWidget(buildReviewScreen(stack, report, calls));
      await pumpUi(tester);

      await tester.ensureVisible(find.byKey(const Key('printOrExportButton')));
      await pumpUi(tester);
      await tester.tap(find.byKey(const Key('printOrExportButton')));
      await pumpUi(tester);

      expect(calls, hasLength(1));
      expect(calls.single.isApproved, isFalse);
      expect(calls.single.revisionNumber, 1);
      expect(calls.single.femaleMovements.rows.single.first, 'House A');
    },
  );

  testWidgets(
    'printing an Approved, corrected report reflects the latest approved '
    'revision, not a stale in-memory snapshot',
    (tester) async {
      final stack = buildStack();
      var report = await stack.reportRepository.createDraft(
        flockId: flock.id,
        reportDate: DateTime(2026, 7, 3),
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
      final revisionBeforeCorrection = report.revision;

      final calls = <BreederReportComposition>[];
      // The widget is built with the pre-correction report snapshot on
      // purpose — the print action must re-read the current row rather
      // than trusting whatever object it was constructed with.
      await tester.pumpWidget(buildReviewScreen(stack, report, calls));
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

      final afterCorrection = await stack.reportRepository.getById(report.id);
      expect(afterCorrection!.revision, greaterThan(revisionBeforeCorrection));

      await tester.ensureVisible(
        find.byKey(const Key('printOrExportButton')),
      );
      await pumpUi(tester);
      await tester.tap(find.byKey(const Key('printOrExportButton')));
      await pumpUi(tester);

      expect(calls, hasLength(1));
      expect(calls.single.isApproved, isTrue);
      expect(calls.single.revisionNumber, afterCorrection.revision);
      final noteField = calls.single.headerFields.firstWhere(
        (f) => f.label == 'Notes',
      );
      expect(noteField.value, 'corrected notes');
    },
  );

  test('BreederReportPdfExport.build renders without throwing (English)', () async {
    final composition = BreederReportComposition(
      headerFields: const [BreederReportHeaderField('Date', '2026-07-01')],
      stateLabel: 'Draft',
      isApproved: false,
      revisionNumber: 1,
      femaleMovements: const BreederReportTable(
        title: 'Females',
        columns: ['Location', 'Opening'],
        rows: [
          ['House A', '100'],
        ],
      ),
      maleMovements: const BreederReportTable(
        title: 'Males',
        columns: ['Location', 'Opening'],
        rows: [
          ['House A', '10'],
        ],
      ),
    );
    final doc = await const BreederReportPdfExport().build(
      composition: composition,
      flockLabel: 'Ross308',
      reportDateLabel: '2026-07-01',
      rtl: false,
      translate: (key) => key,
    );
    final bytes = await doc.save();
    expect(bytes, isNotEmpty);
  });

  test(
    'BreederReportPdfExport.build renders without throwing in Arabic RTL',
    () async {
      final composition = BreederReportComposition(
        headerFields: const [
          BreederReportHeaderField('Date', '2026-07-01'),
          BreederReportHeaderField('Notes', 'ملاحظة'),
        ],
        stateLabel: 'Approved',
        isApproved: true,
        revisionNumber: 2,
        femaleMovements: const BreederReportTable(
          title: 'Females',
          columns: ['Location', 'Opening'],
          rows: [
            ['House A', '100'],
          ],
        ),
        maleMovements: const BreederReportTable(
          title: 'Males',
          columns: ['Location', 'Opening'],
          rows: [
            ['House A', '10'],
          ],
        ),
      );
      final doc = await const BreederReportPdfExport().build(
        composition: composition,
        flockLabel: 'Ross308',
        reportDateLabel: '2026-07-01',
        rtl: true,
        translate: (key) => key == 'Date' ? 'التاريخ' : key,
      );
      final bytes = await doc.save();
      expect(bytes, isNotEmpty);
    },
  );
}
