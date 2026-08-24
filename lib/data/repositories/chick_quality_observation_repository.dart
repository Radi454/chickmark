import 'package:sqflite/sqflite.dart';

import '../agent/chick_observation_codec.dart';
import '../agent/station_registry.dart';
import '../database/database_helper.dart';
import '../models/chick_quality_observation.dart';
import 'sync_tombstone_repository.dart';

class ChickQualityObservationRepository {
  ChickQualityObservationRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper();

  static const tableName = 'chick_quality_observation';

  final DatabaseHelper _databaseHelper;
  String? _dirtyReadCutoff;

  static Future<void> replaceForSampleWithExecutor(
    DatabaseExecutor executor,
    String sampleId,
    String domain,
    Iterable<ChickQualityObservation> replacements,
  ) async {
    final desired = replacements.toList(growable: false);
    if (desired.any(
      (item) => item.sampleId != sampleId || item.domain != domain,
    )) {
      throw ArgumentError('Observation replacement crosses sample ownership');
    }
    final existing = await executor.query(
      tableName,
      columns: ['id', 'createdAt'],
      where: 'sampleId = ? AND domain = ?',
      whereArgs: [sampleId, domain],
    );
    final desiredIds = desired.map((item) => item.id).toSet();
    final staleIds = existing
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((id) => !desiredIds.contains(id))
        .toList(growable: false);
    if (staleIds.isNotEmpty) {
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        executor,
        tableName,
        staleIds,
      );
      final placeholders = List.filled(staleIds.length, '?').join(', ');
      await executor.delete(
        tableName,
        where: 'id IN ($placeholders)',
        whereArgs: staleIds,
      );
    }
    for (final observation in desired) {
      await SyncTombstoneRepository.cancelPendingDeleteWithExecutor(
        executor,
        tableName,
        observation.id,
      );
      final map = observation.toMap();
      final prior = existing.cast<Map<String, Object?>>().where(
        (row) => row['id'] == observation.id,
      );
      if (prior.isNotEmpty && prior.first['createdAt'] != null) {
        map['createdAt'] = prior.first['createdAt'];
      }
      await executor.insert(
        tableName,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  static Future<List<ChickQualityObservation>> getForSampleWithExecutor(
    DatabaseExecutor executor,
    String sampleId,
    String domain,
  ) async {
    final rows = await executor.query(
      tableName,
      where: 'sampleId = ? AND domain = ?',
      whereArgs: [sampleId, domain],
      orderBy: 'kind, observationKey, COALESCE(ordinal, -1)',
    );
    return rows
        .map(
          (row) =>
              ChickQualityObservation.fromMap(Map<String, Object?>.from(row)),
        )
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await _databaseHelper.db;
    _dirtyReadCutoff = DateTime.now().toUtc().toIso8601String();
    return db.query(
      tableName,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt, id',
    );
  }

  Future<Map<String, dynamic>?> getRowById(String id) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.single);
  }

  Future<void> upsertRemoteRow(Map<String, dynamic> remoteRow) async {
    final db = await _databaseHelper.db;
    final row = _camelize(remoteRow);
    final observation = ChickQualityObservation.fromMap(row);
    AgentStationSchema schema;
    try {
      schema = AgentStationRegistry.schemas.firstWhere(
        (candidate) => candidate.schemaKey == observation.domain,
      );
    } on StateError {
      throw StateError('Observation domain is not registry-owned');
    }
    if (!ChickObservationCodec.isValid(schema, observation)) {
      throw StateError('Observation does not match its registry descriptor');
    }
    final logical = await db.query(
      tableName,
      columns: ['id'],
      where:
          'sampleId = ? AND domain = ? AND kind = ? AND observationKey = ? '
          'AND COALESCE(ordinal, -1) = COALESCE(?, -1)',
      whereArgs: [
        row['sampleId'],
        row['domain'],
        row['kind'],
        row['observationKey'],
        row['ordinal'],
      ],
      limit: 1,
    );
    if (logical.isNotEmpty && logical.single['id'] != row['id']) {
      throw StateError(
        'Observation logical identity collision; preserving both rows for review',
      );
    }
    final synced = <String, Object?>{
      ...row,
      'syncStatus': 'synced',
      'dirtyAt': null,
      'lastSyncedAt': DateTime.now().toUtc().toIso8601String(),
      'syncError': null,
    };
    final updated = await db.update(
      tableName,
      synced,
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    if (updated == 0) {
      await db.insert(
        tableName,
        synced,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  Future<void> markRowsSynced(Iterable<String> ids) async {
    final values = ids.toList(growable: false);
    if (values.isEmpty) return;
    final db = await _databaseHelper.db;
    final placeholders = List.filled(values.length, '?').join(', ');
    await db.update(
      tableName,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': DateTime.now().toUtc().toIso8601String(),
        'syncError': null,
      },
      where: 'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [
        ...values,
        _dirtyReadCutoff ?? DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<void> markRowsFailed(Iterable<String> ids, Object error) async {
    final values = ids.toList(growable: false);
    if (values.isEmpty) return;
    final db = await _databaseHelper.db;
    final placeholders = List.filled(values.length, '?').join(', ');
    await db.update(
      tableName,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: values,
    );
  }

  static Map<String, dynamic> _camelize(Map<String, dynamic> row) => row.map(
    (key, value) => MapEntry(
      key.replaceAllMapped(
        RegExp(r'_([a-z])'),
        (match) => match.group(1)!.toUpperCase(),
      ),
      value,
    ),
  );
}
