import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/breeder_bird_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_daily_report_model.dart';
import 'package:hatchaudit/data/models/breeder_egg_grade_definition_model.dart';
import 'package:hatchaudit/data/models/breeder_egg_inventory_movement_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/repositories/breeder_bird_movement_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_daily_report_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_grade_definition_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_inventory_movement_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_production_entry_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_feed_entry_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_report_revision_repository.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_bird_ledger_service.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_inventory_service.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_production_service.dart';
import 'package:hatchaudit/services/breeder/breeder_report_revision_service.dart';

import '../../support/test_database.dart';

/// Post-approval correction paths for the report's CHILD tables
/// (breeder-flock-performance ticket 12, extending the header-only path
/// tested in `breeder_report_revision_service_test.dart`): bird movements
/// (`correctMovement`), feed entries (`correctFeedEntry`), egg-production
/// counts (`correctEggProductionEntry`), and egg-inventory movements
/// (`correctEggInventoryMovement`). Design doc section 5.3/12 requires the
/// same reason/actor/revision-row/single-counter-bump guarantees for these
/// as for the header, plus (section 8/14) that an egg-inventory correction
/// never mutates a historical row and that nothing persists if a
/// correction would unbalance the ledger.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  late BreederDailyReportRepository reportRepository;
  late BreederBirdMovementRepository movementRepository;
  late PoultryHierarchyRepository houseRepository;
  late BreederFeedEntryRepository feedEntryRepository;
  late BreederEggGradeDefinitionRepository gradeRepository;
  late BreederEggProductionEntryRepository productionEntryRepository;
  late BreederEggInventoryMovementRepository inventoryMovementRepository;
  late BreederEggProductionService productionService;
  late BreederEggInventoryService inventoryService;
  late BreederReportRevisionRepository revisionRepository;
  late BreederReportRevisionService revisionService;
  late BreederBirdLedgerService ledgerService;

  setUp(() {
    reportRepository = BreederDailyReportRepository();
    movementRepository = BreederBirdMovementRepository();
    houseRepository = PoultryHierarchyRepository();
    feedEntryRepository = BreederFeedEntryRepository();
    gradeRepository = BreederEggGradeDefinitionRepository();
    productionEntryRepository = BreederEggProductionEntryRepository();
    inventoryMovementRepository = BreederEggInventoryMovementRepository();
    productionService = BreederEggProductionService(
      gradeRepository: gradeRepository,
      entryRepository: productionEntryRepository,
    );
    inventoryService = BreederEggInventoryService(
      movementRepository: inventoryMovementRepository,
      gradeRepository: gradeRepository,
      productionEntryRepository: productionEntryRepository,
    );
    revisionRepository = BreederReportRevisionRepository();
    revisionService = BreederReportRevisionService(
      revisionRepository: revisionRepository,
      reportRepository: reportRepository,
    );
    ledgerService = BreederBirdLedgerService(
      reportRepository: reportRepository,
      movementRepository: movementRepository,
      houseRepository: houseRepository,
      feedEntryRepository: feedEntryRepository,
      eggInventoryService: inventoryService,
      revisionService: revisionService,
      eggProductionEntryRepository: productionEntryRepository,
      eggProductionService: productionService,
    );
  });

  Future<void> seedFlock(String flockId) async {
    final db = await DatabaseHelper().db;
    await db.insert('flocks', {'id': flockId, 'flockId': flockId});
  }

  Future<void> seedHouse(
    String flockId,
    String houseId, {
    int openingFemales = 0,
  }) async {
    await houseRepository.saveHouse(
      HouseModel(
        id: houseId,
        flockId: flockId,
        name: houseId,
        openingFemales: openingFemales,
      ),
    );
  }

  Future<BreederEggGradeDefinition> firstGrade() async {
    return (await gradeRepository.getByCode('first_grade'))!;
  }

  Future<BreederDailyReport> approveReport(BreederDailyReport draft) async {
    var report = await ledgerService.submit(draft, actorUserId: 'entry-user');
    report = await ledgerService.approve(
      report,
      actorUserId: 'manager-1',
      actorRole: 'production_manager',
    );
    return report;
  }

  group('correctMovement', () {
    test(
      'correcting a mortality count writes the right revision row and updates the closing balance',
      () async {
        const flockId = 'flock-movement-mortality';
        await seedFlock(flockId);
        await seedHouse(flockId, 'house-a', openingFemales: 100);
        var report = await reportRepository.createDraft(
          flockId: flockId,
          reportDate: DateTime(2026, 7, 1),
        );
        await ledgerService.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
          mortality: 2,
        );
        report = await approveReport(report);
        final movement = await movementRepository.getByReportHouseSex(
          report.id,
          'house-a',
          BreederBirdMovementSex.female,
        );
        expect(movement!.closing, 98);

        final updated = await ledgerService.correctMovement(
          report,
          movementId: movement.id,
          reason: 'Mortality was entered against the wrong house',
          actorUserId: 'manager-1',
          mortality: 5,
        );

        final corrected = await movementRepository.getById(movement.id);
        expect(corrected!.mortality, 5);
        expect(corrected.closing, 95);
        expect(updated.revision, report.revision + 1);

        // mortality AND closing both changed (98 -> 95 as a direct
        // consequence), so two rows are written for this one correction —
        // "one revision row per changed field" (design section 12), not
        // per correction action.
        final history = await revisionService.historyFor(report.id);
        expect(history, hasLength(2));
        for (final entry in history) {
          expect(entry.tableName, 'breeder_bird_movements');
          expect(entry.rowId, movement.id);
          expect(entry.reason, 'Mortality was entered against the wrong house');
          expect(entry.actorUserId, 'manager-1');
        }
        final mortalityEntry = history.singleWhere((r) => r.fieldName == 'mortality');
        expect(mortalityEntry.oldValue, '2');
        expect(mortalityEntry.newValue, '5');
        final closingEntry = history.singleWhere((r) => r.fieldName == 'closing');
        expect(closingEntry.oldValue, '98');
        expect(closingEntry.newValue, '95');
      },
    );

    test(
      'correcting multiple fields on one movement writes multiple revision rows but bumps the counter once',
      () async {
        const flockId = 'flock-movement-multi';
        await seedFlock(flockId);
        await seedHouse(flockId, 'house-a', openingFemales: 100);
        var report = await reportRepository.createDraft(
          flockId: flockId,
          reportDate: DateTime(2026, 7, 2),
        );
        await ledgerService.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
          mortality: 1,
          culls: 1,
        );
        report = await approveReport(report);
        final movement = await movementRepository.getByReportHouseSex(
          report.id,
          'house-a',
          BreederBirdMovementSex.female,
        );

        final startingRevision = report.revision;
        final updated = await ledgerService.correctMovement(
          report,
          movementId: movement!.id,
          reason: 'Both mortality and culls were transposed',
          actorUserId: 'manager-1',
          mortality: 3,
          culls: 4,
        );

        expect(updated.revision, startingRevision + 1);
        // mortality, culls, AND closing all changed -> three rows, one
        // counter bump.
        final history = await revisionService.historyFor(report.id);
        expect(history, hasLength(3));
        for (final entry in history) {
          expect(entry.revisionAfter, updated.revision);
        }
        expect(history.map((r) => r.fieldName).toSet(), {
          'mortality',
          'culls',
          'closing',
        });
      },
    );

    test('requires a reason', () async {
      const flockId = 'flock-movement-reason';
      await seedFlock(flockId);
      await seedHouse(flockId, 'house-a', openingFemales: 50);
      var report = await reportRepository.createDraft(
        flockId: flockId,
        reportDate: DateTime(2026, 7, 3),
      );
      await ledgerService.recordMovement(
        reportId: report.id,
        houseId: 'house-a',
        sex: BreederBirdMovementSex.female,
        opening: 50,
      );
      report = await approveReport(report);
      final movement = await movementRepository.getByReportHouseSex(
        report.id,
        'house-a',
        BreederBirdMovementSex.female,
      );
      expect(
        () => ledgerService.correctMovement(
          report,
          movementId: movement!.id,
          reason: '',
          actorUserId: 'manager-1',
          mortality: 3,
        ),
        throwsA(isA<BreederReportCorrectionError>()),
      );
      final unchanged = await movementRepository.getById(movement!.id);
      expect(unchanged!.mortality, 0);
    });

    test(
      'rejects a correction that would leave a transfer unbalanced, and writes nothing',
      () async {
        const flockId = 'flock-movement-transfer';
        await seedFlock(flockId);
        await seedHouse(flockId, 'house-a', openingFemales: 100);
        await seedHouse(flockId, 'house-b', openingFemales: 50);
        var report = await reportRepository.createDraft(
          flockId: flockId,
          reportDate: DateTime(2026, 7, 4),
        );
        await ledgerService.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
          transferOut: 10,
        );
        await ledgerService.recordMovement(
          reportId: report.id,
          houseId: 'house-b',
          sex: BreederBirdMovementSex.female,
          opening: 50,
          transferIn: 10,
        );
        report = await approveReport(report);
        final movementA = await movementRepository.getByReportHouseSex(
          report.id,
          'house-a',
          BreederBirdMovementSex.female,
        );

        expect(
          () => ledgerService.correctMovement(
            report,
            movementId: movementA!.id,
            reason: 'Trying to change transferOut without the matching leg',
            actorUserId: 'manager-1',
            transferOut: 15,
          ),
          throwsA(isA<BreederLedgerValidationError>()),
        );
        final unchanged = await movementRepository.getById(movementA!.id);
        expect(unchanged!.transferOut, 10);
        final history = await revisionService.historyFor(report.id);
        expect(history, isEmpty);
      },
    );

    test(
      'rejects a correction that would drive the closing balance negative, and writes nothing',
      () async {
        const flockId = 'flock-movement-negative';
        await seedFlock(flockId);
        await seedHouse(flockId, 'house-a', openingFemales: 10);
        var report = await reportRepository.createDraft(
          flockId: flockId,
          reportDate: DateTime(2026, 7, 5),
        );
        await ledgerService.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 10,
          mortality: 2,
        );
        report = await approveReport(report);
        final movement = await movementRepository.getByReportHouseSex(
          report.id,
          'house-a',
          BreederBirdMovementSex.female,
        );

        expect(
          () => ledgerService.correctMovement(
            report,
            movementId: movement!.id,
            reason: 'Overcorrected mortality',
            actorUserId: 'manager-1',
            mortality: 50,
          ),
          throwsA(isA<BreederLedgerValidationError>()),
        );
        final unchanged = await movementRepository.getById(movement!.id);
        expect(unchanged!.mortality, 2);
        final history = await revisionService.historyFor(report.id);
        expect(history, isEmpty);
      },
    );
  });

  group('correctFeedEntry', () {
    test('corrects feedKg and writes a revision row', () async {
      const flockId = 'flock-feed-correct';
      await seedFlock(flockId);
      await seedHouse(flockId, 'house-a', openingFemales: 100);
      var report = await reportRepository.createDraft(
        flockId: flockId,
        reportDate: DateTime(2026, 7, 6),
      );
      await ledgerService.recordMovement(
        reportId: report.id,
        houseId: 'house-a',
        sex: BreederBirdMovementSex.female,
        opening: 100,
      );
      final feedEntry = await ledgerService.recordFeedEntry(
        reportId: report.id,
        houseId: 'house-a',
        sex: BreederBirdMovementSex.female,
        feedKg: 12.0,
      );
      report = await approveReport(report);

      final updated = await ledgerService.correctFeedEntry(
        report,
        feedEntryId: feedEntry.id,
        feedKg: 15.5,
        reason: 'Scale was misread',
        actorUserId: 'manager-1',
      );

      final corrected = await feedEntryRepository.getById(feedEntry.id);
      expect(corrected!.feedKg, 15.5);
      expect(updated.revision, report.revision + 1);

      final history = await revisionService.historyFor(report.id);
      expect(history, hasLength(1));
      expect(history.single.tableName, 'breeder_feed_entries');
      expect(history.single.oldValue, '12.0');
      expect(history.single.newValue, '15.5');
    });
  });

  group('correctEggProductionEntry', () {
    test(
      'correcting a count flows through to totals/percentages and the inventory ledger',
      () async {
        const flockId = 'flock-egg-count';
        await seedFlock(flockId);
        await seedHouse(flockId, 'house-a', openingFemales: 100);
        final grade = await firstGrade();
        var report = await reportRepository.createDraft(
          flockId: flockId,
          reportDate: DateTime(2026, 7, 7),
        );
        await ledgerService.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
        );
        final entry = await productionService.recordGradeCount(
          reportId: report.id,
          houseId: 'house-a',
          gradeId: grade.id,
          count: 10,
        );
        report = await approveReport(report);

        final beforeBalance = await inventoryService.balanceFor(
          flockId: flockId,
          reportId: report.id,
          reportDate: report.reportDate,
          gradeId: grade.id,
        );
        expect(beforeBalance.todaysProduction, 10);
        expect(beforeBalance.closingBalance, 10);

        final updated = await ledgerService.correctEggProductionEntry(
          report,
          entryId: entry.id,
          count: 15,
          reason: 'Miscounted grade at entry time',
          actorUserId: 'manager-1',
        );

        final correctedEntry = await productionEntryRepository.getById(entry.id);
        expect(correctedEntry!.count, 15);
        expect(updated.revision, report.revision + 1);

        // Flows through to totals (BreederEggProductionService.totalEggs
        // sums live from entries — nothing cached to fall out of sync).
        final allEntries = await productionEntryRepository.getForReport(report.id);
        expect(
          BreederEggProductionService.totalEggs(allEntries.map((e) => e.count)),
          15,
        );

        // Flows through to the inventory ledger (todaysProduction is a
        // live sum of production entries).
        final afterBalance = await inventoryService.balanceFor(
          flockId: flockId,
          reportId: report.id,
          reportDate: report.reportDate,
          gradeId: grade.id,
        );
        expect(afterBalance.todaysProduction, 15);
        expect(afterBalance.closingBalance, 15);

        final history = await revisionService.historyFor(report.id);
        expect(history, hasLength(1));
        expect(history.single.tableName, 'breeder_egg_production_entries');
        expect(history.single.oldValue, '10');
        expect(history.single.newValue, '15');
      },
    );

    test(
      'a correction that would drive the grade inventory balance negative is rejected, and writes nothing',
      () async {
        const flockId = 'flock-egg-unbalance';
        await seedFlock(flockId);
        await seedHouse(flockId, 'house-a', openingFemales: 100);
        final grade = await firstGrade();
        var report = await reportRepository.createDraft(
          flockId: flockId,
          reportDate: DateTime(2026, 7, 8),
        );
        await ledgerService.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
        );
        final entry = await productionService.recordGradeCount(
          reportId: report.id,
          houseId: 'house-a',
          gradeId: grade.id,
          count: 10,
        );
        // Dispatch 8 of the 10 produced today, while still Draft.
        await inventoryService.recordMovement(
          report: report,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.hatcheryDispatch,
          quantity: 8,
        );
        report = await approveReport(report);

        // Lowering the count to 5 would make available (5) less than the
        // already-dispatched 8 — the ledger would go negative.
        expect(
          () => ledgerService.correctEggProductionEntry(
            report,
            entryId: entry.id,
            count: 5,
            reason: 'Overcorrecting the count',
            actorUserId: 'manager-1',
          ),
          throwsA(isA<BreederEggInventoryValidationError>()),
        );

        final unchanged = await productionEntryRepository.getById(entry.id);
        expect(unchanged!.count, 10);
        final history = await revisionService.historyFor(report.id);
        expect(history, isEmpty);
      },
    );
  });

  group('correctEggInventoryMovement', () {
    test(
      'appends a reversing movement rather than mutating the original row',
      () async {
        const flockId = 'flock-inventory-reverse';
        await seedFlock(flockId);
        await seedHouse(flockId, 'house-a', openingFemales: 100);
        final grade = await firstGrade();
        var report = await reportRepository.createDraft(
          flockId: flockId,
          reportDate: DateTime(2026, 7, 9),
        );
        await ledgerService.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
        );
        await productionService.recordGradeCount(
          reportId: report.id,
          houseId: 'house-a',
          gradeId: grade.id,
          count: 20,
        );
        final dispatch = await inventoryService.recordMovement(
          report: report,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.hatcheryDispatch,
          quantity: 5,
        );
        report = await approveReport(report);

        final updated = await ledgerService.correctEggInventoryMovement(
          report,
          movementId: dispatch.id,
          quantity: 8,
          reason: 'Dispatch count was short-counted',
          actorUserId: 'manager-1',
        );
        expect(updated.revision, report.revision + 1);

        final original = await inventoryMovementRepository.getById(dispatch.id);
        expect(original!.quantity, 5, reason: 'the original row is never mutated');
        expect(original.isReversal, isFalse);

        final allMovements = await inventoryMovementRepository.getForReportAndGrade(
          report.id,
          grade.id,
        );
        expect(allMovements, hasLength(3)); // original, reversal, corrected
        final reversal = allMovements.singleWhere(
          (m) => m.reversedMovementId == dispatch.id,
        );
        expect(reversal.quantity, 5);
        expect(reversal.isReversal, isTrue);
        final corrected = allMovements.singleWhere(
          (m) => m.id != dispatch.id && m.id != reversal.id,
        );
        expect(corrected.quantity, 8);
        expect(corrected.isReversal, isFalse);

        final balance = await inventoryService.balanceFor(
          flockId: flockId,
          reportId: report.id,
          reportDate: report.reportDate,
          gradeId: grade.id,
        );
        expect(balance.dispatched, 8);
        expect(balance.closingBalance, 12); // 20 - 8

        final history = await revisionService.historyFor(report.id);
        expect(history, hasLength(1));
        expect(history.single.tableName, 'breeder_egg_inventory_movements');
        expect(history.single.rowId, dispatch.id);
        expect(history.single.oldValue, '5');
        expect(history.single.newValue, '8');
      },
    );

    test(
      'a correction that would unbalance inventory is rejected, and nothing is written',
      () async {
        const flockId = 'flock-inventory-unbalance';
        await seedFlock(flockId);
        await seedHouse(flockId, 'house-a', openingFemales: 100);
        final grade = await firstGrade();
        var report = await reportRepository.createDraft(
          flockId: flockId,
          reportDate: DateTime(2026, 7, 10),
        );
        await ledgerService.recordMovement(
          reportId: report.id,
          houseId: 'house-a',
          sex: BreederBirdMovementSex.female,
          opening: 100,
        );
        await productionService.recordGradeCount(
          reportId: report.id,
          houseId: 'house-a',
          gradeId: grade.id,
          count: 10,
        );
        final dispatch = await inventoryService.recordMovement(
          report: report,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.hatcheryDispatch,
          quantity: 10,
        );
        report = await approveReport(report);

        expect(
          () => ledgerService.correctEggInventoryMovement(
            report,
            movementId: dispatch.id,
            quantity: 15,
            reason: 'Trying to dispatch more than was ever produced',
            actorUserId: 'manager-1',
          ),
          throwsA(isA<BreederEggInventoryValidationError>()),
        );

        final unchanged = await inventoryMovementRepository.getById(dispatch.id);
        expect(unchanged!.quantity, 10);
        final allMovements = await inventoryMovementRepository.getForReportAndGrade(
          report.id,
          grade.id,
        );
        expect(allMovements, hasLength(1), reason: 'no reversal or corrected row was written');
        final history = await revisionService.historyFor(report.id);
        expect(history, isEmpty);
      },
    );
  });
}
