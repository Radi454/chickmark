import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/breeder_alert_models.dart';
import 'package:hatchaudit/data/models/breeder_bird_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_isolation_area_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/features/breeder/screens/breeder_flock_overview_screen.dart';
import 'package:hatchaudit/features/breeder/screens/breeder_performance_alerts_screen.dart';
import 'package:hatchaudit/services/breeder/breeder_bird_ledger_service.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_inventory_service.dart';
import 'package:hatchaudit/services/breeder/breeder_flock_lifecycle_service.dart';
import 'package:hatchaudit/services/breeder/breeder_flock_overview_service.dart';
import 'package:hatchaudit/services/breeder/breeder_report_period_service.dart';
import 'package:hatchaudit/services/breeder/breeder_report_revision_service.dart';
import 'package:hatchaudit/services/breeder/breeder_weighing_service.dart';

import 'fake_breeder_repositories.dart';

/// Widget coverage for the flock Overview screen — the landing view for a
/// flock's breeder performance (breeder-flock-performance ticket 18, design
/// doc section 11). Uses in-memory fakes rather than real sqflite
/// (`testWidgets` hangs against the real database past the first gesture —
/// repo convention) and bounded `pump` calls instead of `pumpAndSettle`.
void main() {
  final now = DateTime(2026, 8, 1);
  // Exactly 30 weeks before "now", so the fake benchmark's
  // production-percent target can be seeded at a known, deterministic
  // ageWeek (HatchDateUtils.flockAgeWeeks floors days/7).
  final flock = FlockModel(
    id: 'flock-1',
    customerId: 'customer-1',
    flockId: 'FLK-1',
    breed: 'Ross308',
    entryDate: now.subtract(const Duration(days: 30 * 7)),
  );

  final houseA = HouseModel(
    id: 'house-a',
    flockId: 'flock-1',
    name: 'House A',
    openingFemales: 100,
    openingMales: 10,
  );
  final isolationA = BreederIsolationArea(
    id: 'isolation-a',
    flockId: 'flock-1',
    name: 'Sick bay',
  );

  Future<void> pumpOverview(WidgetTester tester) async {
    // The Overview is a long scrolling page; give the test surface enough
    // height that every card is actually built (a ListView only builds
    // widgets within its viewport, however tall the physical window), so
    // `find` can see cards below the fold without a manual scroll.
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
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
    FakeBreederBenchmarkRepository benchmarkRepository,
    BreederFlockLifecycleService lifecycleService,
    BreederBirdLedgerService birdLedgerService,
    FakeBreederWeighingSessionRepository weighingSessionRepository,
    FakeBreederWeighingSampleRepository weighingSampleRepository,
    BreederWeighingService weighingService,
    FakeBreederPerformanceAlertRepository alertRepository,
    BreederFlockOverviewService overviewService,
  })
  buildStack() {
    final reportRepository = FakeBreederDailyReportRepository();
    final movementRepository = FakeBreederBirdMovementRepository(
      reportRepository,
    );
    final houseRepository = FakeHouseRepository([houseA]);
    final isolationAreaRepository = FakeIsolationAreaRepository([isolationA]);
    final feedEntryRepository = FakeBreederFeedEntryRepository();
    final eggGradeRepository = FakeBreederEggGradeDefinitionRepository();
    final eggProductionEntryRepository =
        FakeBreederEggProductionEntryRepository(reportRepository);
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
    final birdLedgerService = BreederBirdLedgerService(
      reportRepository: reportRepository,
      movementRepository: movementRepository,
      houseRepository: houseRepository,
      isolationAreaRepository: isolationAreaRepository,
      feedEntryRepository: feedEntryRepository,
      eggInventoryService: eggInventoryService,
      revisionService: revisionService,
      eggProductionEntryRepository: eggProductionEntryRepository,
    );
    final benchmarkRepository = FakeBreederBenchmarkRepository();
    final lifecycleService = BreederFlockLifecycleService(
      benchmarkRepository: benchmarkRepository,
      milestoneRepository: FakeBreederFlockMilestoneRepository(),
    );
    final weighingSessionRepository = FakeBreederWeighingSessionRepository();
    final weighingSampleRepository = FakeBreederWeighingSampleRepository();
    final weighingService = BreederWeighingService(
      sessionRepository: weighingSessionRepository,
      sampleRepository: weighingSampleRepository,
      benchmarkRepository: benchmarkRepository,
      lifecycleService: lifecycleService,
    );
    final alertRepository = FakeBreederPerformanceAlertRepository();
    final periodService = BreederReportPeriodService(
      reportRepository: reportRepository,
    );
    final overviewService = BreederFlockOverviewService(
      lifecycleService: lifecycleService,
      birdLedgerService: birdLedgerService,
      eggInventoryService: eggInventoryService,
      weighingService: weighingService,
      periodService: periodService,
      movementRepository: movementRepository,
      feedEntryRepository: feedEntryRepository,
      eggProductionEntryRepository: eggProductionEntryRepository,
      alertRepository: alertRepository,
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
      benchmarkRepository: benchmarkRepository,
      lifecycleService: lifecycleService,
      birdLedgerService: birdLedgerService,
      weighingSessionRepository: weighingSessionRepository,
      weighingSampleRepository: weighingSampleRepository,
      weighingService: weighingService,
      alertRepository: alertRepository,
      overviewService: overviewService,
    );
  }

  Widget buildScreen(dynamic stack) {
    return MaterialApp(
      home: BreederFlockOverviewScreen(
        flock: flock,
        overviewService: stack.overviewService,
        alertRepository: stack.alertRepository,
        now: now,
      ),
    );
  }

  Future<dynamic> approveReport(
    dynamic stack, {
    required DateTime date,
    int femaleMortality = 0,
    int eggCount = 0,
    double feedKg = 0,
  }) async {
    var report = await stack.reportRepository.createDraft(
      flockId: flock.id,
      reportDate: date,
    );
    await stack.birdLedgerService.recordMovement(
      reportId: report.id,
      houseId: 'house-a',
      sex: BreederBirdMovementSex.female,
      opening: 100,
      mortality: femaleMortality,
    );
    await stack.birdLedgerService.recordMovement(
      reportId: report.id,
      houseId: 'house-a',
      sex: BreederBirdMovementSex.male,
      opening: 10,
    );
    if (feedKg > 0) {
      await stack.birdLedgerService.recordFeedEntry(
        reportId: report.id,
        houseId: 'house-a',
        sex: BreederBirdMovementSex.female,
        feedKg: feedKg,
      );
    }
    if (eggCount > 0) {
      final grades = await stack.eggGradeRepository.listActiveGrades();
      await stack.birdLedgerService.eggProductionService.recordGradeCount(
        reportId: report.id,
        houseId: 'house-a',
        gradeId: grades.first.id,
        count: eggCount,
      );
    }
    report = await stack.birdLedgerService.submit(
      report,
      actorUserId: 'user-entry',
    );
    report = await stack.birdLedgerService.approve(
      report,
      actorUserId: 'user-pm',
      actorRole: 'production_manager',
    );
    return report;
  }

  group('bird inventory', () {
    testWidgets(
      'shows houses, isolation, and total as three distinct figures',
      (tester) async {
        final stack = buildStack();
        await approveReport(stack, date: now.subtract(const Duration(days: 1)));
        // Move 5 females from the house into isolation via a balanced
        // internal transfer on a later report (still on or before "now",
        // so it counts toward the "as of now" bird balance).
        var report = await stack.reportRepository.createDraft(
          flockId: flock.id,
          reportDate: now,
        );
        await stack.birdLedgerService.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
          transferOut: 5,
        );
        await stack.birdLedgerService.recordMovement(
          reportId: report.id,
          isolationAreaId: 'isolation-a',
          sex: BreederBirdMovementSex.female,
          opening: 0,
          transferIn: 5,
        );
        await stack.birdLedgerService.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.male,
          opening: 10,
        );
        report = await stack.birdLedgerService.submit(
          report,
          actorUserId: 'user-entry',
        );
        await stack.birdLedgerService.approve(
          report,
          actorUserId: 'user-pm',
          actorRole: 'production_manager',
        );

        await tester.pumpWidget(buildScreen(stack));
        await pumpOverview(tester);

        // Houses: 95, Isolation: 5, Total: 100 — three distinct numbers,
        // never silently merged.
        expect(find.text('95'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
        expect(find.text('100'), findsOneWidget);
      },
    );
  });

  group('blank, never zero', () {
    testWidgets(
      'a flock with no recorded reports shows blank figures, not zeroes',
      (tester) async {
        final stack = buildStack();

        await tester.pumpWidget(buildScreen(stack));
        await pumpOverview(tester);

        // Total eggs, mortality, and feed all read blank ('—') rather than
        // '0' when nothing has been recorded at all (design section 7.2).
        expect(find.textContaining('Total eggs: —'), findsOneWidget);
        expect(find.textContaining('Mortality: —'), findsOneWidget);
        expect(find.textContaining('Total feed (kg): —'), findsOneWidget);
      },
    );
  });

  group('data completeness', () {
    testWidgets(
      'shows recorded/missing day counts prominently and warns for a partial period',
      (tester) async {
        final stack = buildStack();
        // Only one of the last 7 days is recorded.
        await approveReport(stack, date: now);

        await tester.pumpWidget(buildScreen(stack));
        await pumpOverview(tester);

        // Shown both in the always-visible completeness summary and inside
        // BreederIncompleteDataLabel's own prominent banner.
        expect(find.textContaining('Recorded: 1 / 7'), findsWidgets);
        expect(find.textContaining('Missing: 6'), findsWidgets);
        expect(find.byKey(const Key('breederIncompleteDataLabel')), findsOneWidget);
      },
    );

    testWidgets(
      'shows no incomplete-data label when every day in the period is recorded',
      (tester) async {
        final stack = buildStack();
        for (var i = 0; i < 7; i++) {
          await approveReport(
            stack,
            date: now.subtract(Duration(days: 6 - i)),
          );
        }

        await tester.pumpWidget(buildScreen(stack));
        await pumpOverview(tester);

        expect(find.textContaining('Recorded: 7 / 7'), findsOneWidget);
        expect(find.byKey(const Key('breederIncompleteDataLabel')), findsNothing);
      },
    );
  });

  group('pre-production', () {
    testWidgets('a pre-production flock shows no invented production week', (
      tester,
    ) async {
      final stack = buildStack();
      stack.benchmarkRepository.inProduction = false;

      await tester.pumpWidget(buildScreen(stack));
      await pumpOverview(tester);

      expect(find.text('Pre-production'), findsWidgets);
      expect(find.textContaining('Production week:'), findsNothing);
    });
  });

  group('benchmark provenance', () {
    testWidgets(
      'surfaces the benchmark profile version and comparison axis',
      (tester) async {
        final stack = buildStack();
        stack.benchmarkRepository.inProduction = true;
        // The flock is 30 weeks old at `now` (entryDate 2026-01-09).
        stack.benchmarkRepository.productionPctTargets[30] = 65.0;
        await approveReport(stack, date: now, eggCount: 60);

        await tester.pumpWidget(buildScreen(stack));
        await pumpOverview(tester);

        expect(find.textContaining('Fake Guide v1'), findsWidgets);
        expect(find.textContaining('official'), findsWidgets);
      },
    );
  });

  group('alerts', () {
    testWidgets(
      'shows the official-vs-app-owned threshold distinction and navigates to the alerts screen',
      (tester) async {
        final stack = buildStack();
        final now2 = DateTime.now();
        await stack.alertRepository.insert(
          BreederPerformanceAlert(
            id: 'alert-official',
            flockId: flock.id,
            ruleId: 'rule-1',
            metricCode: BreederAlertMetric.liveabilityRearingPct,
            scope: BreederAlertScope.flock,
            periodType: BreederAlertPeriodType.weekly,
            periodStart: now,
            periodEnd: now,
            actualValue: 90,
            officialLowerBound: 95,
            thresholdIsOfficial: true,
            deviationValue: -5,
            severity: BreederAlertSeverity.critical,
            evidenceReportDates: [now],
            createdAt: now2,
            updatedAt: now2,
          ),
        );
        await stack.alertRepository.insert(
          BreederPerformanceAlert(
            id: 'alert-app',
            flockId: flock.id,
            ruleId: 'rule-2',
            metricCode: BreederAlertMetric.uniformityPct,
            scope: BreederAlertScope.flock,
            periodType: BreederAlertPeriodType.weekly,
            periodStart: now,
            periodEnd: now,
            actualValue: 60,
            thresholdIsOfficial: false,
            deviationValue: -10,
            severity: BreederAlertSeverity.watch,
            evidenceReportDates: [now],
            createdAt: now2,
            updatedAt: now2,
          ),
        );

        await tester.pumpWidget(buildScreen(stack));
        await pumpOverview(tester);

        expect(find.text('Official guide limit'), findsOneWidget);
        expect(find.text('App-defined threshold'), findsOneWidget);
        expect(find.text('Critical'), findsOneWidget);
        expect(find.text('Watch'), findsOneWidget);

        await tester.tap(find.text('View all alerts'));
        await pumpOverview(tester);

        expect(find.byType(BreederPerformanceAlertsScreen), findsOneWidget);
      },
    );

    testWidgets('shows "No open alerts" when there are none', (tester) async {
      final stack = buildStack();

      await tester.pumpWidget(buildScreen(stack));
      await pumpOverview(tester);

      expect(find.text('No open alerts'), findsOneWidget);
    });
  });
}
