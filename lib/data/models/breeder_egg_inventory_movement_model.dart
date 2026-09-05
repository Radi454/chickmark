/// One stock movement for one egg grade on one daily report
/// (breeder-flock-performance ticket 11, design doc section 7, 8, 12, and
/// 14). `breeder_egg_inventory_movements` is the append-only ledger design
/// section 8 describes: "correction or cancellation after approval uses a
/// documented reversing movement rather than destructive deletion".
///
/// Judgment call: today's *production* is deliberately never a row in this
/// table. Design section 11's ticket text says "do not re-enter or
/// duplicate" `breeder_egg_production_entries` — `BreederEggInventoryService`
/// derives today's production for a (report, grade) straight from those
/// entries every time a balance is computed, rather than caching a
/// `production_in` ledger row that could drift out of sync with its source.
/// [BreederEggInventoryMovementKind] therefore only names the five *outward*
/// /adjusting kinds a row can actually be persisted as.
///
/// A movement's location is always the whole flock (via [reportId] ->
/// `breeder_daily_reports.flockId`) — unlike bird movements, feed entries,
/// and egg production entries, inventory is not split by house or isolation
/// area (design section 5.2: "Egg inventory by grade" has no per-location
/// column in the paper form).
library;

/// The five movement kinds a ledger row can actually be. "Production in" is
/// deliberately not a member — see the class doc comment above.
class BreederEggInventoryMovementKind {
  static const String hatcheryDispatch = 'hatchery_dispatch';
  static const String sale = 'sale';
  static const String kitchen = 'kitchen';
  static const String gift = 'gift';
  static const String adjustment = 'adjustment';

  static const List<String> all = [
    hatcheryDispatch,
    sale,
    kitchen,
    gift,
    adjustment,
  ];

  static bool isValid(String value) => all.contains(value);
}

/// Whether an [BreederEggInventoryMovementKind.adjustment] row increases or
/// decreases the balance (design section 7: "+/- approved adjustments").
/// Only meaningful when [BreederEggInventoryMovement.kind] is `adjustment`.
class BreederEggInventoryAdjustmentDirection {
  static const String increase = 'increase';
  static const String decrease = 'decrease';

  static const List<String> all = [increase, decrease];

  static bool isValid(String value) => all.contains(value);
}

class BreederEggInventoryMovement {
  final String id;
  final String reportId;
  final String gradeId;
  final String kind;

  /// Never negative (design section 11/14: "Non-negative quantities").
  /// Direction is carried by [kind] (dispatch/sale/kitchen/gift always
  /// subtract) or by [adjustmentDirection] for an adjustment, never by the
  /// sign of this field.
  final int quantity;

  /// Required, and only ever set, when [kind] is
  /// [BreederEggInventoryMovementKind.adjustment].
  final String? adjustmentDirection;

  /// Required for an adjustment or a reversal (design section 14:
  /// "Adjustments require a reason, an actor, and a time"; section 8:
  /// "documented reversing movement"). Optional for a plain dispatch/sale
  /// /kitchen/gift row.
  final String? reason;
  final String? actorUserId;
  final DateTime? occurredAt;

  /// Non-null when this row is a documented reversal of an earlier movement
  /// (design section 8) — its effect on the balance is the exact opposite
  /// of what [id]'s own [kind]/[adjustmentDirection] would normally produce.
  /// Reversals are always inserted as new rows; the original row is never
  /// edited or deleted (append-only ledger).
  final String? reversedMovementId;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  BreederEggInventoryMovement({
    required this.id,
    required this.reportId,
    required this.gradeId,
    required this.kind,
    required this.quantity,
    this.adjustmentDirection,
    this.reason,
    this.actorUserId,
    this.occurredAt,
    this.reversedMovementId,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    if (!BreederEggInventoryMovementKind.isValid(kind)) {
      throw ArgumentError.value(kind, 'kind', 'must be a valid movement kind');
    }
    if (quantity < 0) {
      throw ArgumentError.value(quantity, 'quantity', 'must not be negative');
    }
    final isAdjustment = kind == BreederEggInventoryMovementKind.adjustment;
    if (isAdjustment) {
      if (adjustmentDirection == null ||
          !BreederEggInventoryAdjustmentDirection.isValid(
            adjustmentDirection!,
          )) {
        throw ArgumentError.value(
          adjustmentDirection,
          'adjustmentDirection',
          'must be increase or decrease for an adjustment',
        );
      }
    } else if (adjustmentDirection != null) {
      throw ArgumentError.value(
        adjustmentDirection,
        'adjustmentDirection',
        'must be null for a non-adjustment movement',
      );
    }
    final requiresDocumentation = isAdjustment || reversedMovementId != null;
    if (requiresDocumentation) {
      if (reason == null || reason!.trim().isEmpty) {
        throw ArgumentError.value(
          reason,
          'reason',
          'is required for an adjustment or a reversal',
        );
      }
      if (actorUserId == null || actorUserId!.trim().isEmpty) {
        throw ArgumentError.value(
          actorUserId,
          'actorUserId',
          'is required for an adjustment or a reversal',
        );
      }
      if (occurredAt == null) {
        throw ArgumentError.value(
          occurredAt,
          'occurredAt',
          'is required for an adjustment or a reversal',
        );
      }
    }
  }

  /// True when this row is a documented reversal (design section 8).
  bool get isReversal => reversedMovementId != null;

  /// The signed effect this row has on the running balance: `-1` for a
  /// plain dispatch/sale/kitchen/gift, `+1`/`-1` for an adjustment per
  /// [adjustmentDirection], and the opposite sign of whichever of those it
  /// would otherwise be when [isReversal] is true. Used by
  /// `BreederEggInventoryService` to sum a set of movements into a net
  /// balance change — never re-derived ad hoc elsewhere.
  int get signedEffect {
    late final int base;
    if (kind == BreederEggInventoryMovementKind.adjustment) {
      base = adjustmentDirection == BreederEggInventoryAdjustmentDirection.increase
          ? 1
          : -1;
    } else {
      base = -1;
    }
    final signed = isReversal ? -base : base;
    return signed * quantity;
  }

  factory BreederEggInventoryMovement.fromMap(Map<String, dynamic> map) {
    return BreederEggInventoryMovement(
      id: map['id'] as String,
      reportId: map['reportId'] as String,
      gradeId: map['gradeId'] as String,
      kind: map['kind'] as String,
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      adjustmentDirection: map['adjustmentDirection']?.toString(),
      reason: map['reason']?.toString(),
      actorUserId: map['actorUserId']?.toString(),
      occurredAt: map['occurredAt'] != null
          ? DateTime.tryParse(map['occurredAt'].toString())
          : null,
      reversedMovementId: map['reversedMovementId']?.toString(),
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
      'reportId': reportId,
      'gradeId': gradeId,
      'kind': kind,
      'quantity': quantity,
      'adjustmentDirection': adjustmentDirection,
      'reason': reason,
      'actorUserId': actorUserId,
      'occurredAt': occurredAt?.toUtc().toIso8601String(),
      'reversedMovementId': reversedMovementId,
    };
  }
}
