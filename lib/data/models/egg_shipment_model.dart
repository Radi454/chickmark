/// A dispatch of one or more [EggBatch]es to a customer's hatchery
/// (breeder-flock-performance ticket 14, design doc section 8 and 12):
/// "`egg_shipments` and `egg_shipment_batches` record dispatch to a
/// customer hatchery." Approving a shipment produces exactly one
/// `breeder_egg_inventory_movements` `hatchery_dispatch` row via
/// `BreederEggInventoryService` (ticket 11) — never a duplicate, never a
/// second, parallel ledger.
///
/// Judgment call: a shipment carries a single [gradeId], and every batch
/// added to it must share that grade (enforced by `EggBatchDispatchService`,
/// not a DB constraint, since it is a cross-table invariant). This is what
/// makes "one dispatch, one ledger movement" well-defined — a shipment
/// spanning several grades would need one movement per grade, which is not
/// what "one dispatch, one ledger movement" describes.
///
/// Judgment call: `breeder_egg_inventory_movements.reportId` is `NOT NULL`
/// (ticket 11's frozen schema) — a movement always belongs to some
/// `breeder_daily_reports` row. A shipment therefore can only be approved
/// for a flock/date that already has a daily report (design section 14:
/// "Missing days are permitted and never auto-created as zero days" — this
/// feature does not create one on the fly either). [reportId] is populated
/// at approval time and left `NULL` while the shipment is still Draft.
library;

class EggShipmentStatus {
  static const String draft = 'draft';
  static const String approved = 'approved';
  static const String cancelled = 'cancelled';

  static const List<String> all = [draft, approved, cancelled];

  static bool isValid(String value) => all.contains(value);
}

class EggShipment {
  final String id;
  final String flockId;
  final String hatcheryId;
  final String gradeId;
  final DateTime shipmentDate;
  final String status;
  final String? notes;

  /// The `breeder_daily_reports` row the ledger movement was posted
  /// against. Always `NULL` until approval.
  final String? reportId;

  /// The ledger movement created on approval. Always `NULL` while Draft.
  final String? inventoryMovementId;
  final String? approvedBy;
  final DateTime? approvedAt;

  /// The reversing ledger movement created on cancellation. Always `NULL`
  /// unless [status] is [EggShipmentStatus.cancelled].
  final String? reversalMovementId;
  final String? cancelledBy;
  final DateTime? cancelledAt;
  final String? cancelReason;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  EggShipment({
    required this.id,
    required this.flockId,
    required this.hatcheryId,
    required this.gradeId,
    required this.shipmentDate,
    this.status = EggShipmentStatus.draft,
    this.notes,
    this.reportId,
    this.inventoryMovementId,
    this.approvedBy,
    this.approvedAt,
    this.reversalMovementId,
    this.cancelledBy,
    this.cancelledAt,
    this.cancelReason,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    if (!EggShipmentStatus.isValid(status)) {
      throw ArgumentError.value(status, 'status', 'must be a valid status');
    }
  }

  bool get isDraft => status == EggShipmentStatus.draft;
  bool get isApproved => status == EggShipmentStatus.approved;
  bool get isCancelled => status == EggShipmentStatus.cancelled;

  static String dateKey(DateTime date) =>
      DateTime(date.year, date.month, date.day).toIso8601String().split('T').first;

  factory EggShipment.fromMap(Map<String, dynamic> map) {
    return EggShipment(
      id: map['id'] as String,
      flockId: map['flockId'] as String,
      hatcheryId: map['hatcheryId'] as String,
      gradeId: map['gradeId'] as String,
      shipmentDate: DateTime.parse(map['shipmentDate'] as String),
      status: map['status']?.toString() ?? EggShipmentStatus.draft,
      notes: map['notes'] as String?,
      reportId: map['reportId'] as String?,
      inventoryMovementId: map['inventoryMovementId'] as String?,
      approvedBy: map['approvedBy'] as String?,
      approvedAt: map['approvedAt'] != null
          ? DateTime.tryParse(map['approvedAt'].toString())
          : null,
      reversalMovementId: map['reversalMovementId'] as String?,
      cancelledBy: map['cancelledBy'] as String?,
      cancelledAt: map['cancelledAt'] != null
          ? DateTime.tryParse(map['cancelledAt'].toString())
          : null,
      cancelReason: map['cancelReason'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString())
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      dirtyAt: map['dirtyAt'] != null
          ? DateTime.tryParse(map['dirtyAt'].toString())
          : null,
      lastSyncedAt: map['lastSyncedAt'] != null
          ? DateTime.tryParse(map['lastSyncedAt'].toString())
          : null,
      syncError: map['syncError']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'flockId': flockId,
      'hatcheryId': hatcheryId,
      'gradeId': gradeId,
      'shipmentDate': dateKey(shipmentDate),
      'status': status,
      'notes': notes,
      'reportId': reportId,
      'inventoryMovementId': inventoryMovementId,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt?.toUtc().toIso8601String(),
      'reversalMovementId': reversalMovementId,
      'cancelledBy': cancelledBy,
      'cancelledAt': cancelledAt?.toUtc().toIso8601String(),
      'cancelReason': cancelReason,
    };
  }

  EggShipment copyWith({
    String? status,
    String? reportId,
    String? inventoryMovementId,
    String? approvedBy,
    DateTime? approvedAt,
    String? reversalMovementId,
    String? cancelledBy,
    DateTime? cancelledAt,
    String? cancelReason,
  }) {
    return EggShipment(
      id: id,
      flockId: flockId,
      hatcheryId: hatcheryId,
      gradeId: gradeId,
      shipmentDate: shipmentDate,
      status: status ?? this.status,
      notes: notes,
      reportId: reportId ?? this.reportId,
      inventoryMovementId: inventoryMovementId ?? this.inventoryMovementId,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      reversalMovementId: reversalMovementId ?? this.reversalMovementId,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelReason: cancelReason ?? this.cancelReason,
    );
  }
}

/// One [EggBatch]'s contribution to an [EggShipment] (design section 8 and
/// 12). [quantity] is how many eggs from that batch this shipment carries —
/// never more than the batch has left undispatched across every
/// non-cancelled shipment it appears in (`EggBatchDispatchService`
/// enforces this; it is a cross-row invariant no single `CHECK` can
/// express).
class EggShipmentBatch {
  final String id;
  final String shipmentId;
  final String batchId;

  /// Never negative.
  final int quantity;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  EggShipmentBatch({
    required this.id,
    required this.shipmentId,
    required this.batchId,
    required this.quantity,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    if (quantity < 0) {
      throw ArgumentError.value(quantity, 'quantity', 'must not be negative');
    }
  }

  factory EggShipmentBatch.fromMap(Map<String, dynamic> map) {
    return EggShipmentBatch(
      id: map['id'] as String,
      shipmentId: map['shipmentId'] as String,
      batchId: map['batchId'] as String,
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString())
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      dirtyAt: map['dirtyAt'] != null
          ? DateTime.tryParse(map['dirtyAt'].toString())
          : null,
      lastSyncedAt: map['lastSyncedAt'] != null
          ? DateTime.tryParse(map['lastSyncedAt'].toString())
          : null,
      syncError: map['syncError']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shipmentId': shipmentId,
      'batchId': batchId,
      'quantity': quantity,
    };
  }
}

/// What a hatchery reported it actually received for one
/// [EggShipmentBatch] line, and the variance against what was dispatched
/// (design section 8 and 12): "`egg_batch_receipts` records received
/// quantities and differences." [receivedQuantity] is never negative;
/// [variance] (`receivedQuantity - the dispatched quantity`) is signed —
/// negative means a shortfall, positive an overage — and is recorded as
/// reported, never used to silently correct the dispatched figure (design
/// section 8: a variance is recorded, not reconciled away).
class EggBatchReceipt {
  final String id;
  final String shipmentBatchId;

  /// Never negative.
  final int receivedQuantity;

  /// Signed: `receivedQuantity` minus the shipment batch's dispatched
  /// `quantity`.
  final int variance;

  final String? recordedBy;
  final DateTime? recordedAt;
  final String? notes;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  EggBatchReceipt({
    required this.id,
    required this.shipmentBatchId,
    required this.receivedQuantity,
    required this.variance,
    this.recordedBy,
    this.recordedAt,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    if (receivedQuantity < 0) {
      throw ArgumentError.value(
        receivedQuantity,
        'receivedQuantity',
        'must not be negative',
      );
    }
  }

  factory EggBatchReceipt.fromMap(Map<String, dynamic> map) {
    return EggBatchReceipt(
      id: map['id'] as String,
      shipmentBatchId: map['shipmentBatchId'] as String,
      receivedQuantity: (map['receivedQuantity'] as num?)?.toInt() ?? 0,
      variance: (map['variance'] as num?)?.toInt() ?? 0,
      recordedBy: map['recordedBy'] as String?,
      recordedAt: map['recordedAt'] != null
          ? DateTime.tryParse(map['recordedAt'].toString())
          : null,
      notes: map['notes'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString())
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      dirtyAt: map['dirtyAt'] != null
          ? DateTime.tryParse(map['dirtyAt'].toString())
          : null,
      lastSyncedAt: map['lastSyncedAt'] != null
          ? DateTime.tryParse(map['lastSyncedAt'].toString())
          : null,
      syncError: map['syncError']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shipmentBatchId': shipmentBatchId,
      'receivedQuantity': receivedQuantity,
      'variance': variance,
      'recordedBy': recordedBy,
      'recordedAt': recordedAt?.toUtc().toIso8601String(),
      'notes': notes,
    };
  }
}
