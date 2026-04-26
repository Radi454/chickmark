import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/activity_log_model.dart';

class ActivityLogRepository {
  final DatabaseHelper dbHelper = DatabaseHelper();
  final Uuid _uuid = const Uuid();

  Future<void> log(
    String userId,
    String action, {
    String? entityType,
    String? entityId,
    String? details,
  }) async {
    if (userId.isEmpty) return;

    final db = await dbHelper.db;
    final entry = ActivityLogModel(
      id: _uuid.v4(),
      userId: userId,
      action: action,
      entityType: entityType,
      entityId: entityId,
      details: details,
      timestamp: DateTime.now(),
    );

    await db.insert(
      'activity_log',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ActivityLogModel>> getRecent({
    int limit = 100,
    String? userId,
  }) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      'activity_log',
      where: userId == null ? null : 'userId = ?',
      whereArgs: userId == null ? null : [userId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(ActivityLogModel.fromMap).toList();
  }

  Future<void> pruneOlderThan(Duration age) async {
    final db = await dbHelper.db;
    final cutoff = DateTime.now().subtract(age).toIso8601String();
    await db.delete(
      'activity_log',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }
}
