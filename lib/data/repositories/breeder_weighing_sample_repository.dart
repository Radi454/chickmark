import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/breeder_weighing_session_model.dart';

/// CRUD access to `breeder_weighing_samples`
/// (breeder-flock-performance ticket 13). Non-negative `weightGrams` is
/// enforced both by the model constructor and a database CHECK constraint.
class BreederWeighingSampleRepository {
  BreederWeighingSampleRepository({DatabaseHelper? dbHelper, Uuid uuid = const Uuid()})
    : dbHelper = dbHelper ?? DatabaseHelper(),
      _uuid = uuid;

  final DatabaseHelper dbHelper;
  final Uuid _uuid;

  static const table = 'breeder_weighing_samples';

  String _nowStamp() => DateTime.now().toIso8601String();

  Future<List<BreederWeighingSample>> getForSession(String sessionId) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      table,
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'createdAt ASC, id ASC',
    );
    return rows.map(BreederWeighingSample.fromMap).toList();
  }

  Future<BreederWeighingSample> add({
    required String sessionId,
    required double weightGrams,
  }) async {
    final db = await dbHelper.db;
    final now = _nowStamp();
    final sample = BreederWeighingSample(
      id: _uuid.v4(),
      sessionId: sessionId,
      weightGrams: weightGrams,
    );
    await db.insert(table, {
      ...sample.toMap(),
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
    });
    return sample;
  }

  /// Replaces every sample recorded for [sessionId] with [weights], in
  /// order. Used by the entry workflow, which edits the whole sample list
  /// at once rather than one weight at a time.
  Future<List<BreederWeighingSample>> replaceForSession({
    required String sessionId,
    required List<double> weights,
  }) async {
    final db = await dbHelper.db;
    return db.transaction<List<BreederWeighingSample>>((txn) async {
      await txn.delete(table, where: 'sessionId = ?', whereArgs: [sessionId]);
      final now = _nowStamp();
      final created = <BreederWeighingSample>[];
      for (final weight in weights) {
        final sample = BreederWeighingSample(
          id: _uuid.v4(),
          sessionId: sessionId,
          weightGrams: weight,
        );
        await txn.insert(table, {
          ...sample.toMap(),
          'createdAt': now,
          'updatedAt': now,
          'syncStatus': 'pending',
          'dirtyAt': now,
        });
        created.add(sample);
      }
      return created;
    });
  }

  Future<void> deleteForSession(String sessionId) async {
    final db = await dbHelper.db;
    await db.delete(table, where: 'sessionId = ?', whereArgs: [sessionId]);
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
