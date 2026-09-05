import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/egg_shipment_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/repositories/breeder_daily_report_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_grade_definition_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_inventory_movement_repository.dart';
import 'package:hatchaudit/data/repositories/egg_batch_repository.dart';
import 'package:hatchaudit/data/repositories/egg_shipment_repository.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_inventory_service.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_production_service.dart';
import 'package:hatchaudit/services/breeder/egg_batch_dispatch_service.dart';

import '../../support/test_database.dart';

/// `EggBatchDispatchService` (breeder-flock-performance ticket 14, design
/// doc section 8, 12, and 14): egg-batch creation, hatchery-dispatch
/// shipments, approval/cancellation through ticket 11's ledger, and
/// receipt/variance recording.
///
/// A batch's own `eggCount` (design section 8: "a flock's egg production
/// for a collection date") is a separate figure from
/// `breeder_egg_production_entries` (ticket 10), which is what ticket 11's
/// ledger actually balances against. Tests that need a dispatch to succeed
/// therefore record a matching production entry via
/// `BreederEggProductionService`, exactly as a real daily report would —
/// a batch alone never manufactures ledger balance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  late EggBatchRepository batchRepository;
  late EggBatchHouseSourceRepository houseSourceRepository;
  late EggShipmentRepository shipmentRepository;
  late EggShipmentBatchRepository shipmentBatchRepository;
  late EggBatchReceiptRepository receiptRepository;
  late BreederEggInventoryService inventoryService;
  late BreederDailyReportRepository reportRepository;
  late BreederEggGradeDefinitionRepository gradeRepository;
  late BreederEggProductionService productionService;
  late EggBatchDispatchService service;

  var counter = 0;
  String uniqueId(String prefix) {
    counter += 1;
    return '$prefix-$counter';
  }

  setUp(() {
    batchRepository = EggBatchRepository();
    houseSourceRepository = EggBatchHouseSourceRepository();
    shipmentRepository = EggShipmentRepository();
    shipmentBatchRepository = EggShipmentBatchRepository();
    receiptRepository = EggBatchReceiptRepository();
    inventoryService = BreederEggInventoryService();
    reportRepository = BreederDailyReportRepository();
    gradeRepository = BreederEggGradeDefinitionRepository();
    productionService = BreederEggProductionService();
    service = EggBatchDispatchService(
      batchRepository: batchRepository,
      houseSourceRepository: houseSourceRepository,
      shipmentRepository: shipmentRepository,
      shipmentBatchRepository: shipmentBatchRepository,
      receiptRepository: receiptRepository,
      inventoryService: inventoryService,
      dailyReportRepository: reportRepository,
    );
  });

  Future<String> firstGradeId() async {
    final grade = await gradeRepository.getByCode('first_grade');
    return grade!.id;
  }

  Future<String> seedCustomer() async {
    final id = uniqueId('customer');
    final db = await DatabaseHelper().db;
    await db.insert('customers', {'id': id, 'name': id});
    return id;
  }

  Future<String> seedFlock(String customerId) async {
    final id = uniqueId('flock');
    final db = await DatabaseHelper().db;
    await db.insert('flocks', {
      'id': id,
      'customerId': customerId,
      'flockId': id,
    });
    return id;
  }

  Future<String> seedHouse(String flockId) async {
    final id = uniqueId('house');
    await PoultryHierarchyRepository().saveHouse(
      HouseModel(id: id, flockId: flockId, name: id),
    );
    return id;
  }

  Future<String> seedHatchery(String customerId) async {
    final id = uniqueId('hatchery');
    final db = await DatabaseHelper().db;
    await db.insert('hatcheries', {
      'id': id,
      'customerId': customerId,
      'name': id,
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': 'tester',
    });
    return id;
  }

  /// Seeds flock/hatchery/grade/report/house, and records [availableEggs]
  /// of real production for that (report, house, grade) — the actual
  /// figure ticket 11's ledger balances a dispatch against.
  Future<
    ({
      String flockId,
      String hatcheryId,
      String gradeId,
      DateTime date,
      String reportId,
    })
  >
  seedDispatchablePrereqs({int availableEggs = 1000}) async {
    final customerId = await seedCustomer();
    final flockId = await seedFlock(customerId);
    final hatcheryId = await seedHatchery(customerId);
    final houseId = await seedHouse(flockId);
    final gradeId = await firstGradeId();
    final date = DateTime(2026, 7, 10 + counter);
    await reportRepository.createDraft(flockId: flockId, reportDate: date);
    final report = await reportRepository.getByFlockAndDate(flockId, date);
    await productionService.recordGradeCount(
      reportId: report!.id,
      houseId: houseId,
      gradeId: gradeId,
      count: availableEggs,
    );
    return (
      flockId: flockId,
      hatcheryId: hatcheryId,
      gradeId: gradeId,
      date: date,
      reportId: report.id,
    );
  }

  test('creates a batch without per-house sources', () async {
    final customerId = await seedCustomer();
    final flockId = await seedFlock(customerId);
    final gradeId = await firstGradeId();

    final batch = await service.createBatch(
      flockId: flockId,
      collectionDate: DateTime(2026, 7, 1),
      gradeId: gradeId,
      eggCount: 200,
    );

    expect(batch.eggCount, 200);
    final sources = await service.houseSourcesForBatch(batch.id);
    expect(sources, isEmpty);
  });

  test(
    'creates a batch with per-house sources summing to less than the total',
    () async {
      final customerId = await seedCustomer();
      final flockId = await seedFlock(customerId);
      final houseA = await seedHouse(flockId);
      final houseB = await seedHouse(flockId);
      final gradeId = await firstGradeId();

      final batch = await service.createBatch(
        flockId: flockId,
        collectionDate: DateTime(2026, 7, 2),
        gradeId: gradeId,
        eggCount: 200,
        houseSources: [
          EggBatchHouseSourceInput(houseId: houseA, eggCount: 90),
          EggBatchHouseSourceInput(houseId: houseB, eggCount: 80),
        ],
      );

      final sources = await service.houseSourcesForBatch(batch.id);
      expect(sources.length, 2);
      expect(sources.fold<int>(0, (sum, s) => sum + s.eggCount), 170);
    },
  );

  test('rejects per-house sources summing to more than the batch total', () async {
    final customerId = await seedCustomer();
    final flockId = await seedFlock(customerId);
    final houseA = await seedHouse(flockId);
    final gradeId = await firstGradeId();

    expect(
      () => service.createBatch(
        flockId: flockId,
        collectionDate: DateTime(2026, 7, 3),
        gradeId: gradeId,
        eggCount: 50,
        houseSources: [EggBatchHouseSourceInput(houseId: houseA, eggCount: 60)],
      ),
      throwsA(isA<EggBatchDispatchValidationError>()),
    );
  });

  test('rejects a negative batch eggCount', () async {
    final customerId = await seedCustomer();
    final flockId = await seedFlock(customerId);
    final gradeId = await firstGradeId();

    expect(
      () => service.createBatch(
        flockId: flockId,
        collectionDate: DateTime(2026, 7, 4),
        gradeId: gradeId,
        eggCount: -1,
      ),
      throwsA(isA<EggBatchDispatchValidationError>()),
    );
  });

  test('house-belongs-to-flock is enforced for batch house sources', () async {
    final customerId = await seedCustomer();
    final flockA = await seedFlock(customerId);
    final flockB = await seedFlock(customerId);
    final houseOfB = await seedHouse(flockB);
    final gradeId = await firstGradeId();

    expect(
      () => service.createBatch(
        flockId: flockA,
        collectionDate: DateTime(2026, 7, 5),
        gradeId: gradeId,
        eggCount: 100,
        houseSources: [EggBatchHouseSourceInput(houseId: houseOfB, eggCount: 10)],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    "a shipment's hatchery must belong to the same customer as the flock",
    () async {
      final customerA = await seedCustomer();
      final customerB = await seedCustomer();
      final flockId = await seedFlock(customerA);
      final hatcheryOfB = await seedHatchery(customerB);
      final gradeId = await firstGradeId();

      expect(
        () => service.createShipment(
          flockId: flockId,
          hatcheryId: hatcheryOfB,
          gradeId: gradeId,
          shipmentDate: DateTime(2026, 7, 6),
        ),
        throwsA(isA<EggBatchDispatchValidationError>()),
      );
    },
  );

  test(
    'approving a dispatch produces exactly one matching inventory movement',
    () async {
      final prereqs = await seedDispatchablePrereqs(availableEggs: 1000);
      final batch = await service.createBatch(
        flockId: prereqs.flockId,
        collectionDate: prereqs.date,
        gradeId: prereqs.gradeId,
        eggCount: 500,
      );
      final shipment = await service.createShipment(
        flockId: prereqs.flockId,
        hatcheryId: prereqs.hatcheryId,
        gradeId: prereqs.gradeId,
        shipmentDate: prereqs.date,
      );
      await service.addBatchToShipment(
        shipmentId: shipment.id,
        batchId: batch.id,
        quantity: 300,
      );

      final approved = await service.approveShipment(
        shipmentId: shipment.id,
        actorUserId: 'tester',
      );

      expect(approved.status, EggShipmentStatus.approved);
      expect(approved.inventoryMovementId, isNotNull);

      final movementRepository = BreederEggInventoryMovementRepository();
      final movements = await movementRepository.getForReportAndGrade(
        approved.reportId!,
        prereqs.gradeId,
      );
      final dispatchMovements = movements
          .where((m) => m.kind == 'hatchery_dispatch' && !m.isReversal)
          .toList();
      expect(dispatchMovements.length, 1);
      expect(dispatchMovements.single.quantity, 300);
    },
  );

  test(
    'approving two shipments against the same report/grade produces two '
    'separate movements, never a silent replacement',
    () async {
      final prereqs = await seedDispatchablePrereqs(availableEggs: 1000);
      final batch = await service.createBatch(
        flockId: prereqs.flockId,
        collectionDate: prereqs.date,
        gradeId: prereqs.gradeId,
        eggCount: 1000,
      );
      final shipment1 = await service.createShipment(
        flockId: prereqs.flockId,
        hatcheryId: prereqs.hatcheryId,
        gradeId: prereqs.gradeId,
        shipmentDate: prereqs.date,
      );
      await service.addBatchToShipment(
        shipmentId: shipment1.id,
        batchId: batch.id,
        quantity: 200,
      );
      final approved1 = await service.approveShipment(
        shipmentId: shipment1.id,
        actorUserId: 'tester',
      );

      final shipment2 = await service.createShipment(
        flockId: prereqs.flockId,
        hatcheryId: prereqs.hatcheryId,
        gradeId: prereqs.gradeId,
        shipmentDate: prereqs.date,
      );
      await service.addBatchToShipment(
        shipmentId: shipment2.id,
        batchId: batch.id,
        quantity: 300,
      );
      final approved2 = await service.approveShipment(
        shipmentId: shipment2.id,
        actorUserId: 'tester',
      );

      expect(approved1.inventoryMovementId, isNot(approved2.inventoryMovementId));

      final movementRepository = BreederEggInventoryMovementRepository();
      final movements = await movementRepository.getForReportAndGrade(
        prereqs.reportId,
        prereqs.gradeId,
      );
      final dispatchMovements = movements
          .where((m) => m.kind == 'hatchery_dispatch' && !m.isReversal)
          .toList();
      expect(dispatchMovements.length, 2);
      expect(
        dispatchMovements.fold<int>(0, (sum, m) => sum + m.quantity),
        500,
      );
    },
  );

  test('over-dispatch beyond the available grade balance is rejected', () async {
    final prereqs = await seedDispatchablePrereqs(availableEggs: 100);
    final batch = await service.createBatch(
      flockId: prereqs.flockId,
      collectionDate: prereqs.date,
      gradeId: prereqs.gradeId,
      // The batch itself allows a bigger line than the flock's real grade
      // balance — this is what forces the assertion onto ticket 11's own
      // ledger check rather than the batch-remaining cross-check.
      eggCount: 500,
    );
    final shipment = await service.createShipment(
      flockId: prereqs.flockId,
      hatcheryId: prereqs.hatcheryId,
      gradeId: prereqs.gradeId,
      shipmentDate: prereqs.date,
    );
    await service.addBatchToShipment(
      shipmentId: shipment.id,
      batchId: batch.id,
      quantity: 150,
    );

    expect(
      () => service.approveShipment(
        shipmentId: shipment.id,
        actorUserId: 'tester',
      ),
      throwsA(isA<BreederEggInventoryValidationError>()),
    );
  });

  test('cannot add more to a shipment than a batch has left undispatched', () async {
    final prereqs = await seedDispatchablePrereqs(availableEggs: 1000);
    final batch = await service.createBatch(
      flockId: prereqs.flockId,
      collectionDate: prereqs.date,
      gradeId: prereqs.gradeId,
      eggCount: 100,
    );
    final shipment = await service.createShipment(
      flockId: prereqs.flockId,
      hatcheryId: prereqs.hatcheryId,
      gradeId: prereqs.gradeId,
      shipmentDate: prereqs.date,
    );

    expect(
      () => service.addBatchToShipment(
        shipmentId: shipment.id,
        batchId: batch.id,
        quantity: 150,
      ),
      throwsA(isA<EggBatchDispatchValidationError>()),
    );
  });

  test(
    'cancelling an approved shipment appends a reversal and never deletes',
    () async {
      final prereqs = await seedDispatchablePrereqs(availableEggs: 1000);
      final batch = await service.createBatch(
        flockId: prereqs.flockId,
        collectionDate: prereqs.date,
        gradeId: prereqs.gradeId,
        eggCount: 500,
      );
      final shipment = await service.createShipment(
        flockId: prereqs.flockId,
        hatcheryId: prereqs.hatcheryId,
        gradeId: prereqs.gradeId,
        shipmentDate: prereqs.date,
      );
      await service.addBatchToShipment(
        shipmentId: shipment.id,
        batchId: batch.id,
        quantity: 200,
      );
      final approved = await service.approveShipment(
        shipmentId: shipment.id,
        actorUserId: 'tester',
      );

      final cancelled = await service.cancelShipment(
        shipmentId: shipment.id,
        reason: 'Hatchery cancelled the pickup',
        actorUserId: 'tester',
      );

      expect(cancelled.status, EggShipmentStatus.cancelled);
      expect(cancelled.reversalMovementId, isNotNull);

      final movementRepository = BreederEggInventoryMovementRepository();
      final original = await movementRepository.getById(
        approved.inventoryMovementId!,
      );
      expect(
        original,
        isNotNull,
        reason: 'the original dispatch row is never deleted',
      );
      final reversal = await movementRepository.getById(
        cancelled.reversalMovementId!,
      );
      expect(reversal, isNotNull);
      expect(reversal!.reversedMovementId, approved.inventoryMovementId);

      final movements = await movementRepository.getForReportAndGrade(
        approved.reportId!,
        prereqs.gradeId,
      );
      expect(
        movements.where((m) => m.id == approved.inventoryMovementId).length,
        1,
        reason: 'no destructive deletion of the original movement',
      );
    },
  );

  test('a cancelled shipment cannot be cancelled a second time', () async {
    final prereqs = await seedDispatchablePrereqs(availableEggs: 1000);
    final batch = await service.createBatch(
      flockId: prereqs.flockId,
      collectionDate: prereqs.date,
      gradeId: prereqs.gradeId,
      eggCount: 500,
    );
    final shipment = await service.createShipment(
      flockId: prereqs.flockId,
      hatcheryId: prereqs.hatcheryId,
      gradeId: prereqs.gradeId,
      shipmentDate: prereqs.date,
    );
    await service.addBatchToShipment(
      shipmentId: shipment.id,
      batchId: batch.id,
      quantity: 100,
    );
    await service.approveShipment(shipmentId: shipment.id, actorUserId: 'tester');
    await service.cancelShipment(
      shipmentId: shipment.id,
      reason: 'first cancellation',
      actorUserId: 'tester',
    );

    expect(
      () => service.cancelShipment(
        shipmentId: shipment.id,
        reason: 'second cancellation',
        actorUserId: 'tester',
      ),
      throwsA(isA<EggBatchDispatchValidationError>()),
    );
  });

  test(
    'a receipt records variance without mutating the dispatched quantity',
    () async {
      final prereqs = await seedDispatchablePrereqs(availableEggs: 1000);
      final batch = await service.createBatch(
        flockId: prereqs.flockId,
        collectionDate: prereqs.date,
        gradeId: prereqs.gradeId,
        eggCount: 500,
      );
      final shipment = await service.createShipment(
        flockId: prereqs.flockId,
        hatcheryId: prereqs.hatcheryId,
        gradeId: prereqs.gradeId,
        shipmentDate: prereqs.date,
      );
      final line = await service.addBatchToShipment(
        shipmentId: shipment.id,
        batchId: batch.id,
        quantity: 300,
      );
      await service.approveShipment(
        shipmentId: shipment.id,
        actorUserId: 'tester',
      );

      final receipt = await service.recordReceipt(
        shipmentBatchId: line.id,
        receivedQuantity: 290,
        recordedBy: 'hatchery-clerk',
      );

      expect(receipt.receivedQuantity, 290);
      expect(receipt.variance, -10);

      final refreshedLine = await shipmentBatchRepository.getById(line.id);
      expect(
        refreshedLine!.quantity,
        300,
        reason: 'dispatched figure is never adjusted to match a receipt',
      );
    },
  );

  test('rejects a negative received quantity on a receipt', () async {
    final prereqs = await seedDispatchablePrereqs(availableEggs: 1000);
    final batch = await service.createBatch(
      flockId: prereqs.flockId,
      collectionDate: prereqs.date,
      gradeId: prereqs.gradeId,
      eggCount: 500,
    );
    final shipment = await service.createShipment(
      flockId: prereqs.flockId,
      hatcheryId: prereqs.hatcheryId,
      gradeId: prereqs.gradeId,
      shipmentDate: prereqs.date,
    );
    final line = await service.addBatchToShipment(
      shipmentId: shipment.id,
      batchId: batch.id,
      quantity: 100,
    );
    await service.approveShipment(shipmentId: shipment.id, actorUserId: 'tester');

    expect(
      () => service.recordReceipt(shipmentBatchId: line.id, receivedQuantity: -1),
      throwsA(isA<EggBatchDispatchValidationError>()),
    );
  });

  test('rejects a negative quantity when adding a batch to a shipment', () async {
    final prereqs = await seedDispatchablePrereqs(availableEggs: 1000);
    final batch = await service.createBatch(
      flockId: prereqs.flockId,
      collectionDate: prereqs.date,
      gradeId: prereqs.gradeId,
      eggCount: 100,
    );
    final shipment = await service.createShipment(
      flockId: prereqs.flockId,
      hatcheryId: prereqs.hatcheryId,
      gradeId: prereqs.gradeId,
      shipmentDate: prereqs.date,
    );

    expect(
      () => service.addBatchToShipment(
        shipmentId: shipment.id,
        batchId: batch.id,
        quantity: -5,
      ),
      throwsA(isA<EggBatchDispatchValidationError>()),
    );
  });
}
