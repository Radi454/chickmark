import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/breeder_egg_grade_definition_model.dart';
import 'package:hatchaudit/data/models/breeder_egg_inventory_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_isolation_area_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/repositories/breeder_daily_report_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_grade_definition_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_inventory_movement_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_production_entry_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_isolation_area_repository.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_bird_ledger_service.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_inventory_service.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_production_service.dart';

import '../../support/test_database.dart';

/// `BreederEggInventoryService` (breeder-flock-performance ticket 11,
/// design doc section 7, 8, 12, and 14): the single tested home for the
/// egg-inventory ledger's available/closing-balance arithmetic, previous
/// -balance derivation, over-dispatch/negative-balance rejection, adjustment
/// and reversal rules, and the approval-balance gate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pure balance arithmetic (no database)', () {
    test('available balance is previous balance plus today\'s production', () {
      final available = BreederEggInventoryService.availableBalance(
        previousBalance: 40,
        todaysProduction: 90,
      );
      expect(available, 130);
    });

    test(
      'closing balance is available minus dispatch, sale, kitchen, and '
      'gifts, plus/minus adjustments',
      () {
        final closing = BreederEggInventoryService.closingBalance(
          availableBalance: 130,
          dispatched: 50,
          sold: 20,
          kitchen: 5,
          gifts: 5,
          netAdjustment: -2,
        );
        // 130 - 50 - 20 - 5 - 5 - 2 = 48
        expect(closing, 48);
      },
    );

    test('a positive net adjustment increases the closing balance', () {
      final closing = BreederEggInventoryService.closingBalance(
        availableBalance: 100,
        dispatched: 0,
        sold: 0,
        kitchen: 0,
        gifts: 0,
        netAdjustment: 10,
      );
      expect(closing, 110);
    });

    test(
      'a closing balance that would go negative is rejected rather than '
      'clamped',
      () {
        expect(
          () => BreederEggInventoryService.closingBalance(
            availableBalance: 10,
            dispatched: 15,
            sold: 0,
            kitchen: 0,
            gifts: 0,
          ),
          throwsA(isA<BreederEggInventoryValidationError>()),
        );
      },
    );

    test('a negative previous balance is rejected', () {
      expect(
        () => BreederEggInventoryService.availableBalance(
          previousBalance: -1,
          todaysProduction: 5,
        ),
        throwsA(isA<BreederEggInventoryValidationError>()),
      );
    });
  });

  group('database-backed ledger behaviour', () {
    setUpAll(() async {
      await useIsolatedAppDatabase();
    });

    tearDownAll(() async {
      await DatabaseHelper().close();
    });

    late BreederDailyReportRepository reportRepository;
    late BreederEggGradeDefinitionRepository gradeRepository;
    late BreederEggProductionEntryRepository productionEntryRepository;
    late BreederEggInventoryMovementRepository movementRepository;
    late BreederEggProductionService productionService;
    late BreederEggInventoryService service;
    late BreederBirdLedgerService ledgerService;

    setUp(() {
      reportRepository = BreederDailyReportRepository();
      gradeRepository = BreederEggGradeDefinitionRepository();
      productionEntryRepository = BreederEggProductionEntryRepository();
      movementRepository = BreederEggInventoryMovementRepository();
      productionService = BreederEggProductionService(
        gradeRepository: gradeRepository,
        entryRepository: productionEntryRepository,
      );
      service = BreederEggInventoryService(
        movementRepository: movementRepository,
        gradeRepository: gradeRepository,
        productionEntryRepository: productionEntryRepository,
      );
      ledgerService = BreederBirdLedgerService(
        eggInventoryService: service,
      );
    });

    Future<void> seedFlock(String flockId) async {
      final db = await DatabaseHelper().db;
      await db.insert('flocks', {'id': flockId, 'flockId': flockId});
    }

    Future<void> seedHouse(String flockId, String houseId) async {
      await PoultryHierarchyRepository().saveHouse(
        HouseModel(id: houseId, flockId: flockId, name: houseId),
      );
    }

    Future<void> seedIsolationArea(String flockId, String areaId) async {
      await BreederIsolationAreaRepository().saveArea(
        BreederIsolationArea(id: areaId, flockId: flockId, name: areaId),
      );
    }

    Future<String> seedReport(
      String flockId,
      String reportId,
      DateTime date,
    ) async {
      await reportRepository.createDraft(flockId: flockId, reportDate: date);
      final report = await reportRepository.getByFlockAndDate(flockId, date);
      return report!.id;
    }

    Future<BreederEggGradeDefinition> firstGrade() async {
      return (await gradeRepository.getByCode('first_grade'))!;
    }

    test(
      'today\'s production is derived from breeder_egg_production_entries, '
      'never re-entered',
      () async {
        await seedFlock('flock-inv-1');
        await seedHouse('flock-inv-1', 'house-x');
        await seedIsolationArea('flock-inv-1', 'iso-x');
        final reportId = await seedReport(
          'flock-inv-1',
          'r1',
          DateTime(2026, 6, 1),
        );
        final grade = await firstGrade();
        await productionService.recordGradeCount(
          reportId: reportId,
          houseId: 'house-x',
          gradeId: grade.id,
          count: 40,
        );
        await productionService.recordGradeCount(
          reportId: reportId,
          isolationAreaId: 'iso-x',
          gradeId: grade.id,
          count: 5,
        );

        final production = await service.todaysProduction(
          reportId: reportId,
          gradeId: grade.id,
        );
        // Both house and isolation entries count toward inventory (design
        // section 5.2 has no per-location split for inventory).
        expect(production, 45);
      },
    );

    test(
      'previous balance is carried from prior ledger state, not free typing',
      () async {
        await seedFlock('flock-inv-2');
        await seedHouse('flock-inv-2', 'house-x');
        final grade = await firstGrade();

        final report1 = await seedReport(
          'flock-inv-2',
          'r1',
          DateTime(2026, 6, 1),
        );
        await productionService.recordGradeCount(
          reportId: report1,
          houseId: 'house-x',
          gradeId: grade.id,
          count: 100,
        );
        final report1Model = await reportRepository.getById(report1);
        await service.recordMovement(
          report: report1Model!,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.sale,
          quantity: 30,
        );
        // Day 1 closing: 0 previous + 100 production - 30 sold = 70.

        final report2 = await seedReport(
          'flock-inv-2',
          'r2',
          DateTime(2026, 6, 2),
        );
        final previous = await service.previousBalance(
          flockId: 'flock-inv-2',
          gradeId: grade.id,
          reportDate: DateTime(2026, 6, 2),
        );
        expect(previous, 70);

        // Day 2's available balance builds on that carried-forward balance,
        // not a fresh/free-typed number.
        await productionService.recordGradeCount(
          reportId: report2,
          houseId: 'house-x',
          gradeId: grade.id,
          count: 20,
        );
        final balance = await service.balanceFor(
          flockId: 'flock-inv-2',
          reportId: report2,
          reportDate: DateTime(2026, 6, 2),
          gradeId: grade.id,
        );
        expect(balance.previousBalance, 70);
        expect(balance.availableBalance, 90);
        expect(balance.closingBalance, 90);
      },
    );

    test(
      'available and closing balance arithmetic matches the design '
      'equations end to end',
      () async {
        await seedFlock('flock-inv-3');
        await seedHouse('flock-inv-3', 'house-x');
        final grade = await firstGrade();
        final reportId = await seedReport(
          'flock-inv-3',
          'r1',
          DateTime(2026, 6, 1),
        );
        final report = await reportRepository.getById(reportId);
        await productionService.recordGradeCount(
          reportId: reportId,
          houseId: 'house-x',
          gradeId: grade.id,
          count: 200,
        );
        await service.recordMovement(
          report: report!,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.hatcheryDispatch,
          quantity: 100,
        );
        await service.recordMovement(
          report: report,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.sale,
          quantity: 50,
        );
        await service.recordMovement(
          report: report,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.kitchen,
          quantity: 10,
        );
        await service.recordMovement(
          report: report,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.gift,
          quantity: 5,
        );

        final balance = await service.balanceFor(
          flockId: 'flock-inv-3',
          reportId: reportId,
          reportDate: DateTime(2026, 6, 1),
          gradeId: grade.id,
        );
        expect(balance.previousBalance, 0);
        expect(balance.todaysProduction, 200);
        expect(balance.availableBalance, 200);
        expect(balance.dispatched, 100);
        expect(balance.sold, 50);
        expect(balance.kitchen, 10);
        expect(balance.gifts, 5);
        // 200 - 100 - 50 - 10 - 5 = 35.
        expect(balance.closingBalance, 35);
      },
    );

    test('over-dispatch beyond the available balance is rejected', () async {
      await seedFlock('flock-inv-4');
      await seedHouse('flock-inv-4', 'house-x');
      final grade = await firstGrade();
      final reportId = await seedReport(
        'flock-inv-4',
        'r1',
        DateTime(2026, 6, 1),
      );
      final report = await reportRepository.getById(reportId);
      await productionService.recordGradeCount(
        reportId: reportId,
        houseId: 'house-x',
        gradeId: grade.id,
        count: 10,
      );

      await expectLater(
        service.recordMovement(
          report: report!,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.hatcheryDispatch,
          quantity: 11,
        ),
        throwsA(isA<BreederEggInventoryValidationError>()),
      );

      final balance = await service.balanceFor(
        flockId: 'flock-inv-4',
        reportId: reportId,
        reportDate: DateTime(2026, 6, 1),
        gradeId: grade.id,
      );
      expect(balance.dispatched, 0);
      expect(balance.closingBalance, 10);
    });

    test('a negative-resulting closing balance across kinds is rejected', () async {
      await seedFlock('flock-inv-5');
      await seedHouse('flock-inv-5', 'house-x');
      final grade = await firstGrade();
      final reportId = await seedReport(
        'flock-inv-5',
        'r1',
        DateTime(2026, 6, 1),
      );
      final report = await reportRepository.getById(reportId);
      await productionService.recordGradeCount(
        reportId: reportId,
        houseId: 'house-x',
        gradeId: grade.id,
        count: 10,
      );
      await service.recordMovement(
        report: report!,
        gradeId: grade.id,
        kind: BreederEggInventoryMovementKind.sale,
        quantity: 6,
      );
      // 10 available, 6 already sold -> 4 left. Kitchen of 5 would go
      // negative.
      await expectLater(
        service.recordMovement(
          report: report,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.kitchen,
          quantity: 5,
        ),
        throwsA(isA<BreederEggInventoryValidationError>()),
      );
    });

    test('an adjustment without a reason is rejected', () async {
      await seedFlock('flock-inv-6');
      await seedHouse('flock-inv-6', 'house-x');
      final grade = await firstGrade();
      final reportId = await seedReport(
        'flock-inv-6',
        'r1',
        DateTime(2026, 6, 1),
      );
      final report = await reportRepository.getById(reportId);
      await expectLater(
        service.recordAdjustment(
          report: report!,
          gradeId: grade.id,
          direction: BreederEggInventoryAdjustmentDirection.increase,
          quantity: 5,
          reason: '',
          actorUserId: 'user-1',
        ),
        throwsA(isA<BreederEggInventoryValidationError>()),
      );
    });

    test(
      'an adjustment requires an actor and always carries a time',
      () async {
        await seedFlock('flock-inv-7');
        await seedHouse('flock-inv-7', 'house-x');
        final grade = await firstGrade();
        final reportId = await seedReport(
          'flock-inv-7',
          'r1',
          DateTime(2026, 6, 1),
        );
        final report = await reportRepository.getById(reportId);
        await expectLater(
          service.recordAdjustment(
            report: report!,
            gradeId: grade.id,
            direction: BreederEggInventoryAdjustmentDirection.increase,
            quantity: 5,
            reason: 'Physical recount',
            actorUserId: '',
          ),
          throwsA(isA<BreederEggInventoryValidationError>()),
        );

        final movement = await service.recordAdjustment(
          report: report,
          gradeId: grade.id,
          direction: BreederEggInventoryAdjustmentDirection.increase,
          quantity: 5,
          reason: 'Physical recount',
          actorUserId: 'user-1',
        );
        expect(movement.occurredAt, isNotNull);
        expect(movement.reason, 'Physical recount');
        expect(movement.actorUserId, 'user-1');
      },
    );

    test(
      'a positive adjustment increases and a negative adjustment decreases '
      'the closing balance',
      () async {
        await seedFlock('flock-inv-8');
        await seedHouse('flock-inv-8', 'house-x');
        final grade = await firstGrade();
        final reportId = await seedReport(
          'flock-inv-8',
          'r1',
          DateTime(2026, 6, 1),
        );
        final report = await reportRepository.getById(reportId);
        await productionService.recordGradeCount(
          reportId: reportId,
          houseId: 'house-x',
          gradeId: grade.id,
          count: 50,
        );
        await service.recordAdjustment(
          report: report!,
          gradeId: grade.id,
          direction: BreederEggInventoryAdjustmentDirection.decrease,
          quantity: 3,
          reason: 'Breakage found on recount',
          actorUserId: 'user-1',
        );
        final balance = await service.balanceFor(
          flockId: 'flock-inv-8',
          reportId: reportId,
          reportDate: DateTime(2026, 6, 1),
          gradeId: grade.id,
        );
        expect(balance.netAdjustment, -3);
        expect(balance.closingBalance, 47);
      },
    );

    test(
      'a Draft report\'s movements are editable, but once it leaves Draft '
      'a new movement is refused and only a reversal can correct it',
      () async {
        await seedFlock('flock-inv-9');
        await seedHouse('flock-inv-9', 'house-x');
        final grade = await firstGrade();
        final reportId = await seedReport(
          'flock-inv-9',
          'r1',
          DateTime(2026, 6, 1),
        );
        var report = (await reportRepository.getById(reportId))!;
        await productionService.recordGradeCount(
          reportId: reportId,
          houseId: 'house-x',
          gradeId: grade.id,
          count: 50,
        );
        final dispatch = await service.recordMovement(
          report: report,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.hatcheryDispatch,
          quantity: 10,
        );

        report = await ledgerService.submit(report, actorUserId: 'user-1');

        await expectLater(
          service.recordMovement(
            report: report,
            gradeId: grade.id,
            kind: BreederEggInventoryMovementKind.hatcheryDispatch,
            quantity: 20,
          ),
          throwsA(isA<BreederEggInventoryStateError>()),
        );

        // The append-only correction path still works after Draft.
        final reversal = await service.reverseMovement(
          movementId: dispatch.id,
          reason: 'Dispatch was cancelled',
          actorUserId: 'user-1',
        );
        expect(reversal.isReversal, isTrue);
        expect(reversal.id, isNot(dispatch.id));

        final balance = await service.balanceFor(
          flockId: 'flock-inv-9',
          reportId: reportId,
          reportDate: DateTime(2026, 6, 1),
          gradeId: grade.id,
        );
        // The dispatch of 10 was fully reversed, so it no longer reduces
        // the closing balance: 50 production, nothing dispatched net.
        expect(balance.dispatched, 0);
        expect(balance.closingBalance, 50);

        // The original row itself was never mutated or deleted — both rows
        // still exist in the ledger.
        final allMovements = await movementRepository.getForReportAndGrade(
          reportId,
          grade.id,
        );
        expect(allMovements, hasLength(2));
      },
    );

    test('a reversal without a reason is rejected', () async {
      await seedFlock('flock-inv-10');
      await seedHouse('flock-inv-10', 'house-x');
      final grade = await firstGrade();
      final reportId = await seedReport(
        'flock-inv-10',
        'r1',
        DateTime(2026, 6, 1),
      );
      final report = await reportRepository.getById(reportId);
      await productionService.recordGradeCount(
        reportId: reportId,
        houseId: 'house-x',
        gradeId: grade.id,
        count: 50,
      );
      final dispatch = await service.recordMovement(
        report: report!,
        gradeId: grade.id,
        kind: BreederEggInventoryMovementKind.hatcheryDispatch,
        quantity: 10,
      );
      await expectLater(
        service.reverseMovement(
          movementId: dispatch.id,
          reason: '',
          actorUserId: 'user-1',
        ),
        throwsA(isA<BreederEggInventoryValidationError>()),
      );
    });

    test(
      'approval is blocked when inventory does not balance and allowed '
      'once it does',
      () async {
        await seedFlock('flock-inv-11');
        await seedHouse('flock-inv-11', 'house-x');
        final grade = await firstGrade();
        final reportId = await seedReport(
          'flock-inv-11',
          'r1',
          DateTime(2026, 6, 1),
        );
        var report = (await reportRepository.getById(reportId))!;
        await productionService.recordGradeCount(
          reportId: reportId,
          houseId: 'house-x',
          gradeId: grade.id,
          count: 10,
        );
        await service.recordMovement(
          report: report,
          gradeId: grade.id,
          kind: BreederEggInventoryMovementKind.sale,
          quantity: 8,
        );
        report = await ledgerService.submit(report, actorUserId: 'user-1');

        // Now correct the production count downward *after* the sale was
        // recorded (still possible while the production entry itself is
        // separately editable) so the equations no longer balance:
        // available becomes 4, but 8 was already sold.
        await productionEntryRepository.upsert(
          (await productionEntryRepository.getForReport(
            reportId,
          )).first.copyWith(count: 4),
        );

        await expectLater(
          ledgerService.approve(
            report,
            actorUserId: 'user-1',
            actorRole: 'production_manager',
          ),
          throwsA(isA<BreederEggInventoryValidationError>()),
        );

        // Reverse the sale so the ledger balances again, then approval
        // succeeds.
        final movements = await movementRepository.getForReportAndGrade(
          reportId,
          grade.id,
        );
        final sale = movements.first;
        await service.reverseMovement(
          movementId: sale.id,
          reason: 'Correcting after production recount',
          actorUserId: 'user-1',
        );

        final approved = await ledgerService.approve(
          report,
          actorUserId: 'user-1',
          actorRole: 'production_manager',
        );
        expect(approved.isApproved, isTrue);
      },
    );

    test(
      'a pre-production report (no grades touched) approves trivially',
      () async {
        await seedFlock('flock-inv-12');
        final reportId = await seedReport(
          'flock-inv-12',
          'r1',
          DateTime(2026, 6, 1),
        );
        var report = (await reportRepository.getById(reportId))!;
        report = await ledgerService.submit(report, actorUserId: 'user-1');
        final approved = await ledgerService.approve(
          report,
          actorUserId: 'user-1',
          actorRole: 'production_manager',
        );
        expect(approved.isApproved, isTrue);
      },
    );
  });
}
