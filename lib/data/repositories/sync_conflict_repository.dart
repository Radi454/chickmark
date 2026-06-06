import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

class SyncConflict {
  final String id;
  final String tableName;
  final String rowId;
  final DateTime? localUpdatedAt;
  final DateTime? remoteUpdatedAt;
  final String winner;
  final DateTime detectedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  const SyncConflict({
    required this.id,
    required this.tableName,
    required this.rowId,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    required this.winner,
    required this.detectedAt,
    this.reviewedAt,
    this.reviewedBy,
  });

  factory SyncConflict.fromMap(Map<String, Object?> row) {
    return SyncConflict(
      id: row['id'] as String,
      tableName: row['tableName'] as String,
      rowId: row['rowId'] as String,
      localUpdatedAt: _parseDate(row['localUpdatedAt']),
      remoteUpdatedAt: _parseDate(row['remoteUpdatedAt']),
      winner: row['winner'] as String,
      detectedAt: _parseDate(row['detectedAt']) ?? DateTime.now(),
      reviewedAt: _parseDate(row['reviewedAt']),
      reviewedBy: row['reviewedBy'] as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'tableName': tableName,
    'rowId': rowId,
    'localUpdatedAt': localUpdatedAt?.toIso8601String(),
    'remoteUpdatedAt': remoteUpdatedAt?.toIso8601String(),
    'winner': winner,
    'detectedAt': detectedAt.toIso8601String(),
    'reviewedAt': reviewedAt?.toIso8601String(),
    'reviewedBy': reviewedBy,
  };

  static DateTime? _parseDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}

class SyncConflictRepository {
  SyncConflictRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  static const tableName = 'sync_conflicts';

  /// Build a deterministic id so re-detecting the same conflict on a
  /// subsequent sync replaces the prior row rather than piling duplicates.
  static String _conflictId(
    String table,
    String rowId,
    DateTime? remoteUpdatedAt,
  ) {
    final stamp = remoteUpdatedAt?.toIso8601String() ?? 'unknown';
    return '$table:$rowId:$stamp';
  }

  /// Persist a conflict event. Same `(table, rowId, remoteUpdatedAt)` tuple
  /// yields the same deterministic id, so:
  /// - re-detection on a subsequent sync is a no-op (INSERT OR IGNORE),
  /// - an already-reviewed conflict stays reviewed,
  /// - a genuinely new conflict event (remote bumped) gets a fresh row.
  Future<void> recordConflict({
    required String table,
    required String rowId,
    required DateTime? localUpdatedAt,
    required DateTime? remoteUpdatedAt,
    required String winner,
  }) async {
    final db = await _dbHelper.db;
    final conflict = SyncConflict(
      id: _conflictId(table, rowId, remoteUpdatedAt),
      tableName: table,
      rowId: rowId,
      localUpdatedAt: localUpdatedAt,
      remoteUpdatedAt: remoteUpdatedAt,
      winner: winner,
      detectedAt: DateTime.now(),
    );
    await db.insert(
      tableName,
      conflict.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> getOpenCount() async {
    final db = await _dbHelper.db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $tableName WHERE reviewedAt IS NULL',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<SyncConflict>> getOpenConflicts({int limit = 100}) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      tableName,
      where: 'reviewedAt IS NULL',
      orderBy: 'detectedAt DESC',
      limit: limit,
    );
    return rows.map((row) => SyncConflict.fromMap(Map.from(row))).toList();
  }

  Future<void> markReviewed(String id, {required String reviewedBy}) async {
    final db = await _dbHelper.db;
    await db.update(
      tableName,
      {
        'reviewedAt': DateTime.now().toIso8601String(),
        'reviewedBy': reviewedBy,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAllReviewed({required String reviewedBy}) async {
    final db = await _dbHelper.db;
    await db.update(
      tableName,
      {
        'reviewedAt': DateTime.now().toIso8601String(),
        'reviewedBy': reviewedBy,
      },
      where: 'reviewedAt IS NULL',
    );
  }

  /// Delete reviewed conflicts older than [age]. Open (unreviewed) rows are
  /// never pruned. Returns the number of rows deleted.
  Future<int> pruneReviewedOlderThan(Duration age) async {
    final db = await _dbHelper.db;
    final cutoff = DateTime.now().subtract(age).toIso8601String();
    return db.delete(
      tableName,
      where: 'reviewedAt IS NOT NULL AND reviewedAt < ?',
      whereArgs: [cutoff],
    );
  }
}
