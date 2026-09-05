import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/egg_shipment_model.dart';

/// CRUD access to `egg_shipments` (breeder-flock-performance ticket 14).
/// This repository only persists rows whose fields have already been
/// validated by `EggBatchDispatchService` — it does not itself validate,
/// matching the "one tested domain service" rule in design doc section 7.
/// Never deletes a shipment: correction/cancellation after approval is
/// [update]d into the `cancelled` status with a `reversalMovementId`, per
/// design section 8's append-only/no-destructive-deletion rule.
class EggShipmentRepository {
  EggShipmentRepository({DatabaseHelper? dbHelper, Uuid uuid = const Uuid()})
    : dbHelper = dbHelper ?? DatabaseHelper(),
      _uuid = uuid;

  final DatabaseHelper dbHelper;
  final Uuid _uuid;

  static const table = 'egg_shipments';

  String newId() => _uuid.v4();
  String _nowStamp() => DateTime.now().toIso8601String();

  Future<EggShipment?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return EggShipment.fromMap(rows.first);
  }

  Future<List<EggShipment>> listForFlock(String flockId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'flockId = ?',
      whereArgs: [flockId],
      orderBy: 'shipmentDate DESC, id DESC',
    );
    return rows.map(EggShipment.fromMap).toList();
  }

  Future<EggShipment> insert(EggShipment shipment) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.insert(table, {
      ...shipment.toMap(),
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return shipment;
  }

  Future<void> update(EggShipment shipment) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.update(
      table,
      {
        ...shipment.toMap(),
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      },
      where: 'id = ?',
      whereArgs: [shipment.id],
    );
  }

  String? _dirtyReadCutoff;

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await dbHelper.db;
    _dirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      table,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC, id ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markRowsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final cutoff = _dirtyReadCutoff ?? _nowStamp();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      table,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _nowStamp(),
        'syncError': null,
      },
      where: 'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...ids, cutoff],
    );
  }

  Future<void> markRowsFailed(List<String> ids, Object error) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      table,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}

/// CRUD access to `egg_shipment_batches` (breeder-flock-performance ticket
/// 14).
class EggShipmentBatchRepository {
  EggShipmentBatchRepository({DatabaseHelper? dbHelper, Uuid uuid = const Uuid()})
    : dbHelper = dbHelper ?? DatabaseHelper(),
      _uuid = uuid;

  final DatabaseHelper dbHelper;
  final Uuid _uuid;

  static const table = 'egg_shipment_batches';

  String newId() => _uuid.v4();
  String _nowStamp() => DateTime.now().toIso8601String();

  Future<EggShipmentBatch?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return EggShipmentBatch.fromMap(rows.first);
  }

  Future<List<EggShipmentBatch>> getForShipment(String shipmentId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'shipmentId = ?',
      whereArgs: [shipmentId],
      orderBy: 'id ASC',
    );
    return rows.map(EggShipmentBatch.fromMap).toList();
  }

  /// Every non-cancelled shipment's line for [batchId] — used to compute
  /// how much of a batch remains undispatched (design section 12: no
  /// dispatch beyond available quantity, cross-checked at the batch level
  /// in addition to ticket 11's grade-level ledger check). Joins to
  /// `egg_shipments` since this table does not itself carry `status`.
  Future<List<EggShipmentBatch>> getActiveForBatch(String batchId) async {
    final db = await dbHelper.db;
    final rows = await db.rawQuery(
      '''
      SELECT sb.* FROM $table sb
      JOIN egg_shipments s ON s.id = sb.shipmentId
      WHERE sb.batchId = ? AND s.status <> 'cancelled'
      ''',
      [batchId],
    );
    return rows.map(EggShipmentBatch.fromMap).toList();
  }

  Future<EggShipmentBatch> insert(EggShipmentBatch line) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.insert(table, {
      ...line.toMap(),
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return line;
  }

  Future<void> delete(String id) async {
    final db = await dbHelper.db;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  String? _dirtyReadCutoff;

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await dbHelper.db;
    _dirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      table,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC, id ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markRowsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final cutoff = _dirtyReadCutoff ?? _nowStamp();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      table,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _nowStamp(),
        'syncError': null,
      },
      where: 'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...ids, cutoff],
    );
  }

  Future<void> markRowsFailed(List<String> ids, Object error) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      table,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}

/// CRUD access to `egg_batch_receipts` (breeder-flock-performance ticket
/// 14). A receipt never mutates the shipment line's dispatched `quantity` —
/// it only ever records what was received and the resulting variance
/// (design section 8: a variance is recorded, not silently reconciled).
class EggBatchReceiptRepository {
  EggBatchReceiptRepository({DatabaseHelper? dbHelper, Uuid uuid = const Uuid()})
    : dbHelper = dbHelper ?? DatabaseHelper(),
      _uuid = uuid;

  final DatabaseHelper dbHelper;
  final Uuid _uuid;

  static const table = 'egg_batch_receipts';

  String newId() => _uuid.v4();
  String _nowStamp() => DateTime.now().toIso8601String();

  Future<EggBatchReceipt?> getByShipmentBatch(String shipmentBatchId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'shipmentBatchId = ?',
      whereArgs: [shipmentBatchId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return EggBatchReceipt.fromMap(rows.first);
  }

  Future<List<EggBatchReceipt>> getForShipmentBatches(
    List<String> shipmentBatchIds,
  ) async {
    if (shipmentBatchIds.isEmpty) return const [];
    final db = await dbHelper.db;
    final placeholders = List.filled(shipmentBatchIds.length, '?').join(', ');
    final rows = await db.query(
      table,
      where: 'shipmentBatchId IN ($placeholders)',
      whereArgs: shipmentBatchIds,
    );
    return rows.map(EggBatchReceipt.fromMap).toList();
  }

  /// Inserts or updates the one receipt for [receipt.shipmentBatchId] — a
  /// receipt is a correction of the hatchery's own report, not a ledger
  /// entry, so it is freely editable rather than append-only.
  Future<EggBatchReceipt> upsert(EggBatchReceipt receipt) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    final existing = await getByShipmentBatch(receipt.shipmentBatchId);
    if (existing == null) {
      await db.insert(table, {
        ...receipt.toMap(),
        'createdAt': now,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      });
      return receipt;
    }
    final updated = EggBatchReceipt(
      id: existing.id,
      shipmentBatchId: receipt.shipmentBatchId,
      receivedQuantity: receipt.receivedQuantity,
      variance: receipt.variance,
      recordedBy: receipt.recordedBy,
      recordedAt: receipt.recordedAt,
      notes: receipt.notes,
    );
    await db.update(
      table,
      {
        ...updated.toMap(),
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      },
      where: 'id = ?',
      whereArgs: [existing.id],
    );
    return updated;
  }

  String? _dirtyReadCutoff;

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await dbHelper.db;
    _dirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      table,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC, id ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markRowsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final cutoff = _dirtyReadCutoff ?? _nowStamp();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      table,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _nowStamp(),
        'syncError': null,
      },
      where: 'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...ids, cutoff],
    );
  }

  Future<void> markRowsFailed(List<String> ids, Object error) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      table,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}
