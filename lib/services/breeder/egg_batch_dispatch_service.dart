/// Single tested home for egg-batch creation, hatchery-dispatch shipments,
/// and receipt/variance recording (breeder-flock-performance ticket 14,
/// design doc section 8, 12, and 14): "A batch represents a flock's egg
/// production for a collection date... Batches are dispatched to the
/// customer's hatchery as a shipment... a dispatch moves the inventory it
/// consumed." Entry, list, and dispatch/receipt screens call into this
/// service rather than re-deriving any of these rules themselves, matching
/// the "one tested domain service" convention `BreederEggInventoryService`
/// (ticket 11) and `BreederWeighingService` (ticket 13) already established.
///
/// Every hatchery-dispatch inventory movement is posted through
/// `BreederEggInventoryService.recordHatcheryDispatch` (ticket 11) — this
/// service never writes to `breeder_egg_inventory_movements` directly, and
/// never re-implements the over-dispatch balance check.
library;

import 'package:uuid/uuid.dart';

import '../../data/models/breeder_daily_report_model.dart';
import '../../data/models/egg_batch_model.dart';
import '../../data/models/egg_shipment_model.dart';
import '../../data/repositories/breeder_daily_report_repository.dart';
import '../../data/repositories/egg_batch_repository.dart';
import '../../data/repositories/egg_shipment_repository.dart';
import '../../data/repositories/flock_repository.dart';
import '../../data/repositories/hatchery_repository.dart';
import 'breeder_egg_inventory_service.dart';

/// Thrown when a batch, shipment, or receipt action would violate a domain
/// rule that is this service's own responsibility (not ticket 11's ledger
/// arithmetic, which raises its own [BreederEggInventoryValidationError]).
class EggBatchDispatchValidationError extends Error {
  final String message;
  EggBatchDispatchValidationError(this.message);

  @override
  String toString() => 'EggBatchDispatchValidationError: $message';
}

/// One house's contribution as supplied to [EggBatchDispatchService
/// .createBatch] — a plain input record, never persisted directly (the
/// service turns each into an [EggBatchHouseSource] row).
class EggBatchHouseSourceInput {
  final String houseId;
  final int eggCount;

  const EggBatchHouseSourceInput({
    required this.houseId,
    required this.eggCount,
  });
}

class EggBatchDispatchService {
  EggBatchDispatchService({
    EggBatchRepository? batchRepository,
    EggBatchHouseSourceRepository? houseSourceRepository,
    EggShipmentRepository? shipmentRepository,
    EggShipmentBatchRepository? shipmentBatchRepository,
    EggBatchReceiptRepository? receiptRepository,
    BreederEggInventoryService? inventoryService,
    BreederDailyReportRepository? dailyReportRepository,
    FlockRepository? flockRepository,
    HatcheryRepository? hatcheryRepository,
    Uuid uuid = const Uuid(),
  }) : batchRepository = batchRepository ?? EggBatchRepository(),
       houseSourceRepository =
           houseSourceRepository ?? EggBatchHouseSourceRepository(),
       shipmentRepository = shipmentRepository ?? EggShipmentRepository(),
       shipmentBatchRepository =
           shipmentBatchRepository ?? EggShipmentBatchRepository(),
       receiptRepository = receiptRepository ?? EggBatchReceiptRepository(),
       inventoryService = inventoryService ?? BreederEggInventoryService(),
       dailyReportRepository =
           dailyReportRepository ?? BreederDailyReportRepository(),
       flockRepository = flockRepository ?? FlockRepository(),
       hatcheryRepository = hatcheryRepository ?? HatcheryRepository(),
       _uuid = uuid;

  final EggBatchRepository batchRepository;
  final EggBatchHouseSourceRepository houseSourceRepository;
  final EggShipmentRepository shipmentRepository;
  final EggShipmentBatchRepository shipmentBatchRepository;
  final EggBatchReceiptRepository receiptRepository;
  final BreederEggInventoryService inventoryService;
  final BreederDailyReportRepository dailyReportRepository;
  final FlockRepository flockRepository;
  final HatcheryRepository hatcheryRepository;
  final Uuid _uuid;

  String _generateId() => _uuid.v4();

  // ---------------------------------------------------------------------
  // Batches (design section 8 and 12).
  // ---------------------------------------------------------------------

  /// Creates a batch for (flock, collectionDate, grade), optionally with
  /// per-house contributions (design section 8: "with optional per-house
  /// contributions"). Rejects a house breakdown that sums to more than
  /// [eggCount] — a batch cannot be smaller than the houses that fed it.
  /// House-belongs-to-flock is enforced by
  /// `trg_egg_batch_house_sources_house_scope_*`, so a mismatched house
  /// surfaces as a `DatabaseException` from the underlying insert rather
  /// than a check here.
  Future<EggBatch> createBatch({
    required String flockId,
    required DateTime collectionDate,
    required String gradeId,
    required int eggCount,
    String? notes,
    List<EggBatchHouseSourceInput> houseSources = const [],
  }) async {
    if (eggCount < 0) {
      throw EggBatchDispatchValidationError(
        'eggCount cannot be negative (was $eggCount)',
      );
    }
    var houseTotal = 0;
    for (final source in houseSources) {
      if (source.eggCount < 0) {
        throw EggBatchDispatchValidationError(
          'A house source eggCount cannot be negative (was '
          '${source.eggCount})',
        );
      }
      houseTotal += source.eggCount;
    }
    if (houseTotal > eggCount) {
      throw EggBatchDispatchValidationError(
        'Per-house contributions ($houseTotal) cannot exceed the batch '
        'eggCount ($eggCount)',
      );
    }

    final batch = EggBatch(
      id: _generateId(),
      flockId: flockId,
      collectionDate: collectionDate,
      gradeId: gradeId,
      eggCount: eggCount,
      notes: notes,
    );
    await batchRepository.insert(batch);

    for (final source in houseSources) {
      await houseSourceRepository.insert(
        EggBatchHouseSource(
          id: _generateId(),
          batchId: batch.id,
          houseId: source.houseId,
          eggCount: source.eggCount,
        ),
      );
    }
    return batch;
  }

  Future<List<EggBatch>> listBatchesForFlock(String flockId) =>
      batchRepository.listForFlock(flockId);

  Future<List<EggBatchHouseSource>> houseSourcesForBatch(String batchId) =>
      houseSourceRepository.getForBatch(batchId);

  /// The portion of [batchId]'s `eggCount` not yet committed to any
  /// non-cancelled shipment line — the batch-level counterpart of ticket
  /// 11's grade-level available balance, checked in addition to it since a
  /// single batch could in principle be over-committed across shipments
  /// while the flock's whole-grade balance still has room (e.g. another
  /// day's batch covering the shortfall).
  Future<int> remainingForBatch(EggBatch batch) async {
    final activeLines = await shipmentBatchRepository.getActiveForBatch(
      batch.id,
    );
    final committed = activeLines.fold<int>(0, (sum, line) => sum + line.quantity);
    return batch.eggCount - committed;
  }

  // ---------------------------------------------------------------------
  // Shipments (design section 8 and 12).
  // ---------------------------------------------------------------------

  /// Creates a Draft shipment for (flock, hatchery, grade, date). Rejects a
  /// hatchery that does not belong to the same customer as the flock
  /// (design section 12: "customer ownership traceable for every
  /// operational row").
  Future<EggShipment> createShipment({
    required String flockId,
    required String hatcheryId,
    required String gradeId,
    required DateTime shipmentDate,
    String? notes,
  }) async {
    final flock = await flockRepository.getFlockById(flockId);
    if (flock == null) {
      throw EggBatchDispatchValidationError('No flock found with id $flockId');
    }
    final hatchery = await hatcheryRepository.getById(hatcheryId);
    if (hatchery == null) {
      throw EggBatchDispatchValidationError(
        'No hatchery found with id $hatcheryId',
      );
    }
    if (hatchery.customerId != flock.customerId) {
      throw EggBatchDispatchValidationError(
        "A shipment's hatchery must belong to the same customer as its "
        'flock',
      );
    }

    final shipment = EggShipment(
      id: _generateId(),
      flockId: flockId,
      hatcheryId: hatcheryId,
      gradeId: gradeId,
      shipmentDate: shipmentDate,
      notes: notes,
    );
    await shipmentRepository.insert(shipment);
    return shipment;
  }

  Future<List<EggShipment>> listShipmentsForFlock(String flockId) =>
      shipmentRepository.listForFlock(flockId);

  Future<List<EggShipmentBatch>> linesForShipment(String shipmentId) =>
      shipmentBatchRepository.getForShipment(shipmentId);

  /// Adds [batchId] to a Draft [shipmentId] for [quantity] eggs. Rejects a
  /// batch from a different flock, a batch whose grade does not match the
  /// shipment's grade, and a quantity beyond what the batch has left
  /// undispatched.
  Future<EggShipmentBatch> addBatchToShipment({
    required String shipmentId,
    required String batchId,
    required int quantity,
  }) async {
    if (quantity < 0) {
      throw EggBatchDispatchValidationError(
        'quantity cannot be negative (was $quantity)',
      );
    }
    final shipment = await shipmentRepository.getById(shipmentId);
    if (shipment == null) {
      throw EggBatchDispatchValidationError(
        'No shipment found with id $shipmentId',
      );
    }
    if (!shipment.isDraft) {
      throw EggBatchDispatchValidationError(
        'Only a Draft shipment can have batches added or removed '
        '(was ${shipment.status})',
      );
    }
    final batch = await batchRepository.getById(batchId);
    if (batch == null) {
      throw EggBatchDispatchValidationError('No batch found with id $batchId');
    }
    if (batch.flockId != shipment.flockId) {
      throw EggBatchDispatchValidationError(
        "A shipment's batches must belong to the shipment's own flock",
      );
    }
    if (batch.gradeId != shipment.gradeId) {
      throw EggBatchDispatchValidationError(
        "A batch's grade (${batch.gradeId}) must match the shipment's "
        'grade (${shipment.gradeId})',
      );
    }
    final remaining = await remainingForBatch(batch);
    if (quantity > remaining) {
      throw EggBatchDispatchValidationError(
        'Cannot dispatch $quantity eggs from batch $batchId — only '
        '$remaining remain undispatched',
      );
    }

    final line = EggShipmentBatch(
      id: _generateId(),
      shipmentId: shipmentId,
      batchId: batchId,
      quantity: quantity,
    );
    await shipmentBatchRepository.insert(line);
    return line;
  }

  /// Removes a shipment line while the shipment is still Draft. Once
  /// approved, a shipment's lines are permanent — cancellation reverses the
  /// whole dispatch rather than editing individual lines (design section
  /// 8: no destructive editing after approval).
  Future<void> removeShipmentLine(String shipmentBatchId) async {
    final line = await shipmentBatchRepository.getById(shipmentBatchId);
    if (line == null) return;
    final shipment = await shipmentRepository.getById(line.shipmentId);
    if (shipment != null && !shipment.isDraft) {
      throw EggBatchDispatchValidationError(
        'Only a Draft shipment can have batches added or removed '
        '(was ${shipment.status})',
      );
    }
    await shipmentBatchRepository.delete(shipmentBatchId);
  }

  /// Approves [shipmentId]: sums its lines' quantities, posts exactly one
  /// `hatchery_dispatch` movement via
  /// `BreederEggInventoryService.recordHatcheryDispatch` (design section 8:
  /// "one dispatch, one ledger movement — never a duplicate"), and
  /// transitions the shipment to Approved. Throws
  /// [EggBatchDispatchValidationError] if the flock has no daily report for
  /// the shipment's date yet (a movement's `reportId` is `NOT NULL` — see
  /// this service's own library doc comment) or if the shipment has no
  /// lines, and propagates
  /// [BreederEggInventoryValidationError]/[BreederEggInventoryStateError]
  /// unchanged if ticket 11's ledger rejects the dispatch (over-dispatch
  /// beyond the available grade balance).
  Future<EggShipment> approveShipment({
    required String shipmentId,
    required String actorUserId,
    DateTime? occurredAt,
  }) async {
    final shipment = await shipmentRepository.getById(shipmentId);
    if (shipment == null) {
      throw EggBatchDispatchValidationError(
        'No shipment found with id $shipmentId',
      );
    }
    if (!shipment.isDraft) {
      throw EggBatchDispatchValidationError(
        'Only a Draft shipment can be approved (was ${shipment.status})',
      );
    }
    final lines = await shipmentBatchRepository.getForShipment(shipmentId);
    if (lines.isEmpty) {
      throw EggBatchDispatchValidationError(
        'A shipment cannot be approved with no batches attached',
      );
    }
    final totalQuantity = lines.fold<int>(0, (sum, line) => sum + line.quantity);

    final report = await dailyReportRepository.getByFlockAndDate(
      shipment.flockId,
      shipment.shipmentDate,
    );
    if (report == null) {
      throw EggBatchDispatchValidationError(
        'No daily report exists for flock ${shipment.flockId} on '
        '${BreederDailyReport.dateKey(shipment.shipmentDate)} — record the '
        "day's report before approving a dispatch on that date",
      );
    }

    final movement = await inventoryService.recordHatcheryDispatch(
      report: report,
      gradeId: shipment.gradeId,
      quantity: totalQuantity,
      reason: 'Shipment $shipmentId dispatch to hatchery ${shipment.hatcheryId}',
      actorUserId: actorUserId,
      occurredAt: occurredAt,
    );

    final approved = shipment.copyWith(
      status: EggShipmentStatus.approved,
      reportId: report.id,
      inventoryMovementId: movement.id,
      approvedBy: actorUserId,
      approvedAt: occurredAt ?? DateTime.now(),
    );
    await shipmentRepository.update(approved);
    return approved;
  }

  /// Cancels an already-approved [shipmentId] by reversing its ledger
  /// movement via `BreederEggInventoryService.reverseMovement` (design
  /// section 8: "Correction or cancellation after approval uses a
  /// documented reversing movement rather than destructive deletion") and
  /// marking the shipment Cancelled — never deleting the shipment or its
  /// movement rows.
  Future<EggShipment> cancelShipment({
    required String shipmentId,
    required String reason,
    required String actorUserId,
    DateTime? occurredAt,
  }) async {
    final shipment = await shipmentRepository.getById(shipmentId);
    if (shipment == null) {
      throw EggBatchDispatchValidationError(
        'No shipment found with id $shipmentId',
      );
    }
    if (!shipment.isApproved) {
      throw EggBatchDispatchValidationError(
        'Only an approved shipment can be cancelled (was ${shipment.status})',
      );
    }
    final movementId = shipment.inventoryMovementId;
    if (movementId == null) {
      throw EggBatchDispatchValidationError(
        'Approved shipment $shipmentId has no recorded inventory movement '
        'to reverse',
      );
    }

    final reversal = await inventoryService.reverseMovement(
      movementId: movementId,
      reason: reason,
      actorUserId: actorUserId,
      occurredAt: occurredAt,
    );

    final cancelled = shipment.copyWith(
      status: EggShipmentStatus.cancelled,
      reversalMovementId: reversal.id,
      cancelledBy: actorUserId,
      cancelledAt: occurredAt ?? DateTime.now(),
      cancelReason: reason,
    );
    await shipmentRepository.update(cancelled);
    return cancelled;
  }

  // ---------------------------------------------------------------------
  // Receipts (design section 8 and 12).
  // ---------------------------------------------------------------------

  /// Records what the hatchery reported receiving for [shipmentBatchId],
  /// and the (signed) variance against what was dispatched. Never mutates
  /// the shipment line's dispatched `quantity` (design section 8: a
  /// variance is recorded, not silently reconciled).
  Future<EggBatchReceipt> recordReceipt({
    required String shipmentBatchId,
    required int receivedQuantity,
    String? recordedBy,
    DateTime? recordedAt,
    String? notes,
  }) async {
    if (receivedQuantity < 0) {
      throw EggBatchDispatchValidationError(
        'receivedQuantity cannot be negative (was $receivedQuantity)',
      );
    }
    final line = await shipmentBatchRepository.getById(shipmentBatchId);
    if (line == null) {
      throw EggBatchDispatchValidationError(
        'No shipment batch line found with id $shipmentBatchId',
      );
    }
    final shipment = await shipmentRepository.getById(line.shipmentId);
    if (shipment == null || !shipment.isApproved) {
      throw EggBatchDispatchValidationError(
        'A receipt can only be recorded for an approved shipment '
        '(was ${shipment?.status})',
      );
    }

    final existing = await receiptRepository.getByShipmentBatch(
      shipmentBatchId,
    );
    final receipt = EggBatchReceipt(
      id: existing?.id ?? _generateId(),
      shipmentBatchId: shipmentBatchId,
      receivedQuantity: receivedQuantity,
      variance: receivedQuantity - line.quantity,
      recordedBy: recordedBy,
      recordedAt: recordedAt ?? DateTime.now(),
      notes: notes,
    );
    return receiptRepository.upsert(receipt);
  }

  Future<EggBatchReceipt?> receiptForShipmentLine(String shipmentBatchId) =>
      receiptRepository.getByShipmentBatch(shipmentBatchId);

  Future<List<EggBatchReceipt>> receiptsForShipment(String shipmentId) async {
    final lines = await shipmentBatchRepository.getForShipment(shipmentId);
    return receiptRepository.getForShipmentBatches(
      lines.map((l) => l.id).toList(),
    );
  }
}
