import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/breeder_egg_production_entry_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/features/breeder/screens/egg_batch_entry_screen.dart';
import 'package:hatchaudit/features/breeder/screens/egg_shipment_detail_screen.dart';
import 'package:hatchaudit/features/breeder/screens/egg_shipment_entry_screen.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_inventory_service.dart';
import 'package:hatchaudit/services/breeder/egg_batch_dispatch_service.dart';

import 'fake_breeder_repositories.dart';

/// Widget coverage for the egg-batch and hatchery-dispatch-shipment
/// workflow (breeder-flock-performance ticket 14). Uses in-memory fake
/// repositories rather than real sqflite (`testWidgets` hangs against the
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
  final house = HouseModel(id: 'house-a', flockId: 'flock-1', name: 'House A');
  final hatchery = HatcheryModel(
    id: 'hatchery-1',
    customerId: 'customer-1',
    name: 'Hatchery One',
    createdAt: DateTime(2026, 1, 1),
    createdBy: 'tester',
  );

  Future<void> pumpUi(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  // The default 800x600 test surface clips some of these screens' wider
  // rows (long shipment/date titles, action buttons) right at the edge,
  // which makes `tester.tap` miss a real, on-screen widget. Every test in
  // this file uses a bigger surface so a tap always lands where the pixels
  // actually are.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first
        .physicalSize = const Size(1400, 1000);
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first
        .devicePixelRatio = 1.0;
    addTearDown(() {
      TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first
          .resetPhysicalSize();
      TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first
          .resetDevicePixelRatio();
    });
  });

  ({
    FakeEggBatchRepository batchRepository,
    FakeEggBatchHouseSourceRepository houseSourceRepository,
    FakeEggShipmentRepository shipmentRepository,
    FakeEggShipmentBatchRepository shipmentBatchRepository,
    FakeEggBatchReceiptRepository receiptRepository,
    FakeBreederDailyReportRepository reportRepository,
    FakeBreederEggProductionEntryRepository productionRepository,
    FakeBreederEggInventoryMovementRepository movementRepository,
    FakeBreederEggGradeDefinitionRepository gradeRepository,
    EggBatchDispatchService service,
  })
  buildStack() {
    final batchRepository = FakeEggBatchRepository();
    final houseSourceRepository = FakeEggBatchHouseSourceRepository(
      batchRepository,
      [house],
    );
    final shipmentRepository = FakeEggShipmentRepository();
    final shipmentBatchRepository = FakeEggShipmentBatchRepository(
      shipmentRepository,
    );
    final receiptRepository = FakeEggBatchReceiptRepository();
    final reportRepository = FakeBreederDailyReportRepository();
    final productionRepository = FakeBreederEggProductionEntryRepository(
      reportRepository,
    );
    final movementRepository = FakeBreederEggInventoryMovementRepository(
      reportRepository,
    );
    final gradeRepository = FakeBreederEggGradeDefinitionRepository();
    final inventoryService = BreederEggInventoryService(
      movementRepository: movementRepository,
      gradeRepository: gradeRepository,
      productionEntryRepository: productionRepository,
    );
    final flockRepository = FakeFlockRepository([flock]);
    final hatcheryRepository = FakeHatcheryRepository([hatchery]);
    final service = EggBatchDispatchService(
      batchRepository: batchRepository,
      houseSourceRepository: houseSourceRepository,
      shipmentRepository: shipmentRepository,
      shipmentBatchRepository: shipmentBatchRepository,
      receiptRepository: receiptRepository,
      inventoryService: inventoryService,
      dailyReportRepository: reportRepository,
      flockRepository: flockRepository,
      hatcheryRepository: hatcheryRepository,
    );
    return (
      batchRepository: batchRepository,
      houseSourceRepository: houseSourceRepository,
      shipmentRepository: shipmentRepository,
      shipmentBatchRepository: shipmentBatchRepository,
      receiptRepository: receiptRepository,
      reportRepository: reportRepository,
      productionRepository: productionRepository,
      movementRepository: movementRepository,
      gradeRepository: gradeRepository,
      service: service,
    );
  }

  /// Seeds a Draft report and enough real production for [gradeId] on
  /// [date] that a dispatch of up to [availableEggs] eggs will balance —
  /// mirrors the real `BreederEggInventoryService`'s rule that a batch's
  /// own `eggCount` never manufactures ledger balance by itself.
  Future<void> seedBalance(
    ({
      FakeEggBatchRepository batchRepository,
      FakeEggBatchHouseSourceRepository houseSourceRepository,
      FakeEggShipmentRepository shipmentRepository,
      FakeEggShipmentBatchRepository shipmentBatchRepository,
      FakeEggBatchReceiptRepository receiptRepository,
      FakeBreederDailyReportRepository reportRepository,
      FakeBreederEggProductionEntryRepository productionRepository,
      FakeBreederEggInventoryMovementRepository movementRepository,
      FakeBreederEggGradeDefinitionRepository gradeRepository,
      EggBatchDispatchService service,
    })
    stack,
    DateTime date,
    String gradeId, {
    int availableEggs = 1000,
  }) async {
    final report = await stack.reportRepository.createDraft(
      flockId: flock.id,
      reportDate: date,
    );
    await stack.productionRepository.upsert(
      BreederEggProductionEntry(
        id: 'seed-production-1',
        reportId: report.id,
        houseId: house.id,
        gradeId: gradeId,
        count: availableEggs,
      ),
    );
  }

  testWidgets('creating a batch without house sources', (tester) async {
    final stack = buildStack();
    await tester.pumpWidget(
      MaterialApp(
        home: EggBatchEntryScreen(
          flock: flock,
          service: stack.service,
          gradeRepository: stack.gradeRepository,
          houseRepository: FakeHouseRepository([house]),
        ),
      ),
    );
    await pumpUi(tester);

    await tester.enterText(
      find.byKey(const Key('egg_batch_count_field')),
      '300',
    );
    await tester.tap(find.byKey(const Key('egg_batch_save_button')));
    await pumpUi(tester);

    final batches = await stack.batchRepository.listForFlock(flock.id);
    expect(batches.length, 1);
    expect(batches.single.eggCount, 300);
    final sources = await stack.houseSourceRepository.getForBatch(
      batches.single.id,
    );
    expect(sources, isEmpty);
  });

  testWidgets('creating a batch with a per-house source', (tester) async {
    final stack = buildStack();
    await tester.pumpWidget(
      MaterialApp(
        home: EggBatchEntryScreen(
          flock: flock,
          service: stack.service,
          gradeRepository: stack.gradeRepository,
          houseRepository: FakeHouseRepository([house]),
        ),
      ),
    );
    await pumpUi(tester);

    await tester.enterText(
      find.byKey(const Key('egg_batch_count_field')),
      '300',
    );
    await tester.enterText(
      find.byKey(Key('egg_batch_house_field_${house.id}')),
      '250',
    );
    await tester.tap(find.byKey(const Key('egg_batch_save_button')));
    await pumpUi(tester);

    final batches = await stack.batchRepository.listForFlock(flock.id);
    expect(batches.length, 1);
    final sources = await stack.houseSourceRepository.getForBatch(
      batches.single.id,
    );
    expect(sources.single.eggCount, 250);
  });

  testWidgets(
    'creating a shipment, adding a batch, and approving it produces one '
    'inventory movement',
    (tester) async {
      final stack = buildStack();
      final gradeId = stack.gradeRepository.grades.first.id;
      // The entry screen's shipment-date field has no test key to drive
      // programmatically (same limitation ticket 13's weighing-session
      // widget test notes for its own date field), so this test seeds the
      // report/production balance for *today* -- the date a freshly opened
      // entry screen defaults to -- rather than trying to override it.
      final today = DateTime.now();
      final date = DateTime(today.year, today.month, today.day);
      await seedBalance(stack, date, gradeId, availableEggs: 1000);
      final batch = await stack.service.createBatch(
        flockId: flock.id,
        collectionDate: date,
        gradeId: gradeId,
        eggCount: 500,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: EggShipmentEntryScreen(
            flock: flock,
            service: stack.service,
            gradeRepository: stack.gradeRepository,
            hatcheryRepository: FakeHatcheryRepository([hatchery]),
            actorUserIdOverride: 'tester',
          ),
        ),
      );
      await pumpUi(tester);

      await tester.tap(find.byKey(const Key('egg_shipment_save_button')));
      await pumpUi(tester);
      // pushReplacement's default page-transition animation (~300ms) is
      // still mid-slide after pumpUi's shorter pumps, which leaves the new
      // route's widgets positioned off-screen for hit testing — settle the
      // transition itself (a fixed, finite animation, unlike the unbounded
      // real-sqflite Futures `pumpAndSettle` is normally avoided for in
      // this repo) before interacting with the detail screen.
      await tester.pump(const Duration(milliseconds: 350));

      // The entry screen replaces itself with the detail screen once the
      // Draft shipment is created.
      expect(find.byType(EggShipmentDetailScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('egg_shipment_add_batch_button')));
      await pumpUi(tester);
      expect(find.byKey(const Key('egg_shipment_batch_dropdown')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('egg_shipment_batch_quantity_field')),
        '300',
      );
      await tester.tap(find.text('Add'));
      await pumpUi(tester);

      expect(find.textContaining('Dispatched: 300'), findsOneWidget);

      await tester.tap(find.byKey(const Key('egg_shipment_approve_button')));
      await pumpUi(tester);
      await tester.pump(const Duration(milliseconds: 200)); // dialog transition
      await tester.tap(find.text('Confirm'));
      await pumpUi(tester);
      await tester.pump(const Duration(milliseconds: 200)); // dialog dismissal

      expect(find.text('Status: Approved'), findsOneWidget);

      final shipments = await stack.shipmentRepository.listForFlock(flock.id);
      expect(shipments.single.isApproved, isTrue);
      final movements = await stack.movementRepository.getForReportAndGrade(
        shipments.single.reportId!,
        gradeId,
      );
      final dispatches = movements
          .where((m) => m.kind == 'hatchery_dispatch' && !m.isReversal)
          .toList();
      expect(
        dispatches.length,
        1,
        reason: 'approving one shipment posts exactly one ledger movement',
      );
      expect(dispatches.single.quantity, 300);

      // The batch itself is untouched by dispatch bookkeeping.
      final storedBatch = await stack.batchRepository.getById(batch.id);
      expect(storedBatch!.eggCount, 500);
    },
  );

  testWidgets(
    'cancelling an approved shipment shows Cancelled and keeps the '
    'original movement (reversal, not deletion)',
    (tester) async {
      final stack = buildStack();
      final gradeId = stack.gradeRepository.grades.first.id;
      final date = DateTime(2026, 7, 16);
      await seedBalance(stack, date, gradeId, availableEggs: 1000);
      final batch = await stack.service.createBatch(
        flockId: flock.id,
        collectionDate: date,
        gradeId: gradeId,
        eggCount: 500,
      );
      final shipment = await stack.service.createShipment(
        flockId: flock.id,
        hatcheryId: hatchery.id,
        gradeId: gradeId,
        shipmentDate: date,
      );
      await stack.service.addBatchToShipment(
        shipmentId: shipment.id,
        batchId: batch.id,
        quantity: 200,
      );
      final approved = await stack.service.approveShipment(
        shipmentId: shipment.id,
        actorUserId: 'tester',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: EggShipmentDetailScreen(
            flock: flock,
            shipment: approved,
            service: stack.service,
            actorUserIdOverride: 'tester',
          ),
        ),
      );
      await pumpUi(tester);

      await tester.tap(find.byKey(const Key('egg_shipment_cancel_button')));
      await pumpUi(tester);
      await tester.enterText(find.byType(TextField).first, 'no longer needed');
      await tester.tap(find.text('Save'));
      await pumpUi(tester);

      expect(find.textContaining('Status: Cancelled'), findsOneWidget);

      final original = await stack.movementRepository.getById(
        approved.inventoryMovementId!,
      );
      expect(original, isNotNull, reason: 'the original movement is never deleted');
      final updatedShipment = await stack.shipmentRepository.getById(shipment.id);
      expect(updatedShipment!.reversalMovementId, isNotNull);
      final reversal = await stack.movementRepository.getById(
        updatedShipment.reversalMovementId!,
      );
      expect(reversal!.reversedMovementId, approved.inventoryMovementId);
    },
  );

  testWidgets(
    'recording a receipt shows the variance without changing the '
    'dispatched quantity',
    (tester) async {
      final stack = buildStack();
      final gradeId = stack.gradeRepository.grades.first.id;
      final date = DateTime(2026, 7, 17);
      await seedBalance(stack, date, gradeId, availableEggs: 1000);
      final batch = await stack.service.createBatch(
        flockId: flock.id,
        collectionDate: date,
        gradeId: gradeId,
        eggCount: 500,
      );
      final shipment = await stack.service.createShipment(
        flockId: flock.id,
        hatcheryId: hatchery.id,
        gradeId: gradeId,
        shipmentDate: date,
      );
      final line = await stack.service.addBatchToShipment(
        shipmentId: shipment.id,
        batchId: batch.id,
        quantity: 300,
      );
      final approved = await stack.service.approveShipment(
        shipmentId: shipment.id,
        actorUserId: 'tester',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: EggShipmentDetailScreen(
            flock: flock,
            shipment: approved,
            service: stack.service,
            actorUserIdOverride: 'hatchery-clerk',
          ),
        ),
      );
      await pumpUi(tester);

      await tester.tap(find.byKey(Key('egg_shipment_receipt_button_${line.id}')));
      await pumpUi(tester);
      await tester.enterText(find.byType(TextField).first, '285');
      await tester.tap(find.text('Save'));
      await pumpUi(tester);

      expect(find.textContaining('Received: 285'), findsOneWidget);
      expect(find.textContaining('-15'), findsOneWidget);
      expect(find.textContaining('Dispatched: 300'), findsOneWidget);

      final storedLine = await stack.shipmentBatchRepository.getById(line.id);
      expect(
        storedLine!.quantity,
        300,
        reason: 'a receipt never mutates the dispatched figure',
      );
      final receipt = await stack.receiptRepository.getByShipmentBatch(line.id);
      expect(receipt!.variance, -15);
    },
  );
}
