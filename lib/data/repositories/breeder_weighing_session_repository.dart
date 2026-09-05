import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/breeder_weighing_session_model.dart';

/// CRUD access to `breeder_weighing_sessions`
/// (breeder-flock-performance ticket 13). This repository only persists
/// rows whose fields have already been validated by
/// `BreederWeighingService` — it does not itself validate sample size or
/// derive figures, matching the "one tested domain service" rule in design
/// doc section 7.
///
/// A session's house-belongs-to-flock invariant is enforced by a database
/// trigger (`trg_breeder_weighing_sessions_house_scope_*`), so persisting a
/// session whose house belongs to a different flock surfaces as a
/// `DatabaseException` from the underlying insert/update.
class BreederWeighingSessionRepository {
  BreederWeighingSessionRepository({DatabaseHelper? dbHelper, Uuid uuid = const Uuid()})
    : dbHelper = dbHelper ?? DatabaseHelper(),
      _uuid = uuid;

  final DatabaseHelper dbHelper;
  final Uuid _uuid;

  static const table = 'breeder_weighing_sessions';

  String _nowStamp() => DateTime.now().toIso8601String();

  Future<BreederWeighingSession?> getById(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return BreederWeighingSession.fromMap(rows.first);
  }

  Future<List<BreederWeighingSession>> listForFlock(String flockId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'flockId = ?',
      whereArgs: [flockId],
      orderBy: 'sessionDate DESC, id DESC',
    );
    return rows.map(BreederWeighingSession.fromMap).toList();
  }

  Future<BreederWeighingSession> create({
    required String flockId,
    required String houseId,
    required DateTime sessionDate,
    required String sex,
    required String method,
    required int sampleSize,
    String? notes,
  }) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    final session = BreederWeighingSession(
      id: _uuid.v4(),
      flockId: flockId,
      houseId: houseId,
      sessionDate: sessionDate,
      sex: sex,
      method: method,
      sampleSize: sampleSize,
      notes: notes,
    );
    await db.insert(table, {
      ...session.toMap(),
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return session;
  }

  Future<void> update(BreederWeighingSession session) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    await db.update(
      table,
      {
        ...session.toMap(),
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
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
