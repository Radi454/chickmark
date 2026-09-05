import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/breeder_flock_milestone_model.dart';

/// CRUD access to `breeder_flock_milestones` (breeder-flock-performance
/// ticket 06): dated operational events recorded against a flock (grading,
/// physical transfer, light stimulation, first egg, production milestones,
/// and depletion events). There is one row per (flockId, eventType) —
/// recording the same event type again corrects the existing row's date
/// rather than appending a duplicate, which keeps "the recorded 5%
/// -production milestone" in `BreederFlockLifecycleService` unambiguous.
class BreederFlockMilestoneRepository {
  BreederFlockMilestoneRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();
  final DatabaseHelper dbHelper;

  static const _table = 'breeder_flock_milestones';
  final Uuid _uuid = const Uuid();

  String _nowStamp() => DateTime.now().toIso8601String();

  /// Records or corrects a milestone. [eventType] must be one of
  /// [BreederFlockMilestoneType.all]. Returns the stored milestone (with a
  /// generated id on first insert, or the existing id when correcting an
  /// existing event).
  Future<BreederFlockMilestone> recordMilestone({
    required String flockId,
    required String eventType,
    required DateTime eventDate,
    String? notes,
  }) async {
    if (!BreederFlockMilestoneType.isValid(eventType)) {
      throw ArgumentError.value(
        eventType,
        'eventType',
        'must be one of BreederFlockMilestoneType.all',
      );
    }
    final db = await dbHelper.db;
    final existing = await getByType(flockId, eventType);
    final now = _nowStamp();
    final milestone = BreederFlockMilestone(
      id: existing?.id ?? _uuid.v4(),
      flockId: flockId,
      eventType: eventType,
      eventDate: eventDate,
      notes: notes,
    );

    if (existing == null) {
      await db.insert(_table, {
        ...milestone.toMap(),
        'createdAt': now,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      });
    } else {
      await db.update(
        _table,
        {
          ...milestone.toMap(),
          'updatedAt': now,
          'syncStatus': 'pending',
          'dirtyAt': now,
        },
        where: 'id = ?',
        whereArgs: [milestone.id],
      );
    }
    return milestone;
  }

  Future<List<BreederFlockMilestone>> getForFlock(String flockId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      _table,
      where: 'flockId = ?',
      whereArgs: [flockId],
      orderBy: 'eventDate ASC',
    );
    return rows.map(BreederFlockMilestone.fromMap).toList();
  }

  Future<BreederFlockMilestone?> getByType(
    String flockId,
    String eventType,
  ) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      _table,
      where: 'flockId = ? AND eventType = ?',
      whereArgs: [flockId, eventType],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BreederFlockMilestone.fromMap(rows.first);
  }

  Future<void> deleteMilestone(String id) async {
    final db = await dbHelper.db;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  /// dirtyAt cutoff captured at the last [getDirtyRows] call, mirroring
  /// `FlockRepository`'s dirty-tracking convention so a push landing mid
  /// -edit does not clobber a concurrent local change.
  String? _dirtyReadCutoff;

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await dbHelper.db;
    _dirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      _table,
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
      _table,
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
      _table,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}
