import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/chick_sample_identity.dart';
import '../models/panel_sample_model.dart';
import '../models/panel_sample_schema.dart';
import '../services/panel_aggregate_deriver.dart';
import '../../core/security/safe_debug_log.dart';
import '../../services/sync/app_sync_coordinator.dart';
import 'egg_grading_repository.dart';
import 'sync_tombstone_repository.dart';

class PanelSampleRepository {
  PanelSampleRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _databaseHelper;

  /// dirtyAt cutoff per table, captured at the last getDirtyRows() call for
  /// that table; see markRowsSynced.
  final Map<String, String> _dirtyReadCutoffByTable = {};
  final Map<String, Set<String>> _lastQualityFlagsByTable = {};

  Map<String, Set<String>> get lastQualityFlagsByTable => {
    for (final entry in _lastQualityFlagsByTable.entries)
      entry.key: Set.unmodifiable(entry.value),
  };

  /// Panel tables whose row identity is the row id itself, not the hierarchy
  /// tuple. See `PanelSampleSchema.idKeyedPanelTables` for why the set lives
  /// there (import-cycle avoidance) and is only re-exposed here.
  static const Set<String> idKeyedPanelTables =
      PanelSampleSchema.idKeyedPanelTables;

  Future<void> savePanelWithSamples({
    required PanelRecord panel,
    required List<PanelSampleRecord> samples,
  }) async {
    final definition = PanelSampleSchema.byTable(panel.tableName);
    _lastQualityFlagsByTable.remove(definition.tableName);

    final database = await _databaseHelper.db;
    await database.transaction<void>((txn) async {
      if (samples.isEmpty) {
        final row = _stampDirty(
          _deriveAndRecord(
            definition.tableName,
            await _withoutOrphanedPanelHatcheryId(txn, panel.toMap()),
          ),
        );
        await _upsertById(
          txn,
          definition.tableName,
          await _prepareChickIdentity(txn, definition.tableName, row),
        );
        return;
      }
      for (final sample in samples) {
        final row = _stampDirty(
          _deriveAndRecord(
            definition.tableName,
            await _withoutOrphanedPanelHatcheryId(
              txn,
              _rowFromLegacySample(panel, sample),
            ),
          ),
        );
        await _upsertById(
          txn,
          definition.tableName,
          await _prepareChickIdentity(txn, definition.tableName, row),
        );
      }
    });
    AppSyncCoordinator.nudge();
  }

  Future<void> upsertRow({
    required String tableName,
    required Map<String, Object?> row,
    bool deriveAggregates = true,
  }) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    _lastQualityFlagsByTable.remove(definition.tableName);
    final values = deriveAggregates
        ? _deriveAndRecord(definition.tableName, row)
        : Map<String, Object?>.of(row);
    if (definition.identityColumnDefinitions.isEmpty) {
      await _upsertById(database, definition.tableName, values);
    } else {
      await database.transaction<void>((txn) async {
        await _upsertById(
          txn,
          definition.tableName,
          await _prepareChickIdentity(txn, definition.tableName, values),
        );
      });
    }
    AppSyncCoordinator.nudge();
  }

  Map<String, Object?> _deriveAndRecord(
    String tableName,
    Map<String, Object?> row,
  ) {
    final result = PanelAggregateDeriver.derive(tableName, row);
    if (result.qualityFlags.isNotEmpty) {
      (_lastQualityFlagsByTable[tableName] ??= <String>{}).addAll(
        result.qualityFlags,
      );
      safeDebugLog(
        'Panel aggregate quality warning for $tableName: '
        '${result.qualityFlags.join(', ')}',
      );
    }
    return result.row;
  }

  Future<List<Map<String, dynamic>>> getRowsBySessionId(
    String tableName,
    String sessionId,
  ) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final columns = await _tableColumns(database, definition.tableName);
    final rows = await database.query(
      definition.tableName,
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: panelOrderByForColumns(columns),
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getRowsBySessionIdAndMode(
    String tableName,
    String sessionId,
    String mode,
  ) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final columns = await _tableColumns(database, definition.tableName);
    final hierarchyColumns = _hierarchyColumnsForTable(columns);
    final rows = mode == PanelRecord.modeComparison
        ? await database.query(
            definition.tableName,
            where: _hierarchyRowsWhereForColumns(hierarchyColumns),
            whereArgs: [sessionId],
            orderBy: panelOrderByForColumns(columns),
          )
        : await database.query(
            definition.tableName,
            where: _pooledRowsWhereForColumns(hierarchyColumns),
            whereArgs: [sessionId],
            orderBy: panelOrderByForColumns(columns),
          );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getComparisonRows(
    String tableName,
    String sessionId,
  ) {
    return getRowsBySessionIdAndMode(
      tableName,
      sessionId,
      PanelRecord.modeComparison,
    );
  }

  Future<void> deleteRowsBySessionId(String tableName, String sessionId) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    await database.transaction<void>((txn) async {
      final rows = await txn.query(
        definition.tableName,
        columns: ['id'],
        where: 'sessionId = ?',
        whereArgs: [sessionId],
      );
      await _deleteRowsByIdWithTombstones(
        txn,
        definition.tableName,
        rows.map((row) => row['id']),
      );
    });
  }

  Future<void> deleteHierarchyRowsBySessionId(
    String tableName,
    String sessionId,
  ) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    await database.transaction<void>((txn) async {
      final columns = await _tableColumns(txn, definition.tableName);
      final hierarchyColumns = _hierarchyColumnsForTable(columns);
      final rows = await txn.query(
        definition.tableName,
        columns: ['id', ...hierarchyColumns],
        where: _hierarchyRowsWhereForColumns(hierarchyColumns),
        whereArgs: [sessionId],
      );
      await _deleteRowsByIdWithTombstones(
        txn,
        definition.tableName,
        rows.map((row) => row['id']),
      );
    });
  }

  Future<void> deleteHierarchyRowsBySessionIdExcept(
    String tableName,
    String sessionId,
    Iterable<String> keepIds, {
    Iterable<Map<String, Object?>> keepHierarchyRows = const [],
    Iterable<String> keepSampleKeys = const [],
  }) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final keepIdSet = keepIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final keepSampleKeySet = keepSampleKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet();
    await database.transaction<void>((txn) async {
      final columns = await _tableColumns(txn, definition.tableName);
      final hierarchyColumns = _hierarchyColumnsForTable(columns);
      final isIdKeyed = idKeyedPanelTables.contains(definition.tableName);
      final keepHierarchyKeys = isIdKeyed
          ? const <String>{}
          : keepHierarchyRows
                .map((row) => _hierarchyKey(row, hierarchyColumns))
                .toSet();
      final rows = await txn.query(
        definition.tableName,
        columns: [
          'id',
          ...hierarchyColumns,
          if (isIdKeyed && columns.contains('sampleKey')) 'sampleKey',
        ],
        where: isIdKeyed
            ? 'sessionId = ?'
            : _hierarchyRowsWhereForColumns(hierarchyColumns),
        whereArgs: [sessionId],
      );
      final staleIds = <String>[];
      for (final row in rows) {
        final id = row['id']?.toString();
        final sampleKey = row['sampleKey']?.toString();
        if (id != null &&
            id.isNotEmpty &&
            !keepIdSet.contains(id) &&
            (sampleKey == null || !keepSampleKeySet.contains(sampleKey)) &&
            (isIdKeyed ||
                !keepHierarchyKeys.contains(
                  _hierarchyKey(row, hierarchyColumns),
                ))) {
          staleIds.add(id);
        }
      }
      if (staleIds.isEmpty) return;

      await _deleteRowsByIdWithTombstones(txn, definition.tableName, staleIds);
    });
  }

  Future<void> deleteRowsBySessionIdExcept(
    String tableName,
    String sessionId,
    Iterable<String> keepIds, {
    Iterable<Map<String, Object?>> keepHierarchyRows = const [],
  }) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final keepIdSet = keepIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    await database.transaction<void>((txn) async {
      final columns = await _tableColumns(txn, definition.tableName);
      final hierarchyColumns = _hierarchyColumnsForTable(columns);
      final isIdKeyed = idKeyedPanelTables.contains(definition.tableName);
      final keepHierarchyKeys = isIdKeyed
          ? const <String>{}
          : keepHierarchyRows
                .map((row) => _hierarchyKey(row, hierarchyColumns))
                .toSet();
      final rows = await txn.query(
        definition.tableName,
        columns: ['id', ...hierarchyColumns],
        where: 'sessionId = ?',
        whereArgs: [sessionId],
      );
      final staleIds = <String>[];
      for (final row in rows) {
        final id = row['id']?.toString();
        if (id != null &&
            id.isNotEmpty &&
            !keepIdSet.contains(id) &&
            (isIdKeyed ||
                !keepHierarchyKeys.contains(
                  _hierarchyKey(row, hierarchyColumns),
                ))) {
          staleIds.add(id);
        }
      }
      if (staleIds.isEmpty) return;

      await _deleteRowsByIdWithTombstones(txn, definition.tableName, staleIds);
    });
  }

  Future<void> deleteRowsBySessionIdForSampleIds(
    String tableName,
    String sessionId,
    Iterable<String> sampleIds,
  ) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final sampleIdSet = sampleIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (sampleIdSet.isEmpty) return;

    final database = await _databaseHelper.db;
    await database.transaction<void>((txn) async {
      final rows = await txn.query(
        definition.tableName,
        columns: ['id'],
        where: 'sessionId = ?',
        whereArgs: [sessionId],
      );
      final staleIds = <String>[];
      for (final row in rows) {
        final rowId = row['id']?.toString();
        if (rowId == null || rowId.isEmpty) continue;
        if (sampleIdSet.any(
          (sampleId) => _rowIdMatchesSampleId(rowId, sampleId),
        )) {
          staleIds.add(rowId);
        }
      }
      if (staleIds.isEmpty) return;

      await _deleteRowsByIdWithTombstones(txn, definition.tableName, staleIds);
    });
  }

  Future<void> deleteRow(String tableName, String id) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    await database.transaction<void>((txn) async {
      await _deleteRowsByIdWithTombstones(txn, definition.tableName, [id]);
    });
  }

  Future<List<Map<String, dynamic>>> getDashboardRows(
    String tableName, {
    String? customerId,
    String? flockId,
    int? limit,
  }) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final where = <String>[];
    final args = <Object?>[];
    if (customerId != null) {
      where.add('customerId = ?');
      args.add(customerId);
    }
    if (flockId != null) {
      where.add('flockId = ?');
      args.add(flockId);
    }
    final rows = await database.query(
      definition.tableName,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, updatedAt DESC',
      limit: limit,
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, Object?>>> getPanelSamples({
    required String panelTable,
    required String panelId,
  }) async {
    final definition = PanelSampleSchema.byTable(panelTable);
    final database = await _databaseHelper.db;
    final columns = await _tableColumns(database, definition.tableName);
    return database.query(
      definition.tableName,
      where: 'id = ?',
      whereArgs: [panelId],
      orderBy: panelOrderByForColumns(columns),
    );
  }

  Future<List<Map<String, dynamic>>> getAllPanelRows(String panelTable) async {
    final definition = PanelSampleSchema.byTable(panelTable);
    final database = await _databaseHelper.db;
    final rows = await database.query(
      definition.tableName,
      orderBy: 'createdAt ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @Deprecated('Panel sample child tables were removed.')
  Future<List<Map<String, dynamic>>> getAllPanelSampleRows(
    String panelTable,
  ) async {
    return const [];
  }

  Future<Map<String, dynamic>?> getRowById(String tableName, String id) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final rows = await database.query(
      definition.tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  /// Sync-pull write: rows arriving from Supabase are in sync with the cloud,
  /// so mark them synced. Only reached when the conflict check let the remote
  /// row win (a newer local edit short circuits earlier, keeping it pending).
  Future<void> upsertPanelRow(
    String tableName,
    Map<String, dynamic> row,
  ) async {
    await upsertRow(
      tableName: tableName,
      row: _markRowSynced(_normalizeRow(row)),
      deriveAggregates: false,
    );
  }

  /// Applies identity ordinals returned by the cloud before the pull pass.
  /// Cloud insertion may reallocate an offline-colliding replicate; clearing
  /// all keys in the returned batch first avoids transient local uniqueness
  /// conflicts while the batch is permuted to its authoritative assignments.
  Future<void> reconcileChickIdentityAssignments(
    String tableName,
    List<Map<String, dynamic>> remoteRows,
  ) async {
    if (!const {'chick_quality', 'chick_weights'}.contains(tableName) ||
        remoteRows.isEmpty) {
      return;
    }
    final assignments = <({String id, int replicate, String sampleKey})>[];
    for (final remoteRow in remoteRows) {
      final row = _normalizeRow(remoteRow);
      final id = _text(row['id']);
      final replicate = row['replicate'];
      final sampleKey = _text(row['sampleKey']);
      if (id == null ||
          replicate is! int ||
          replicate < 1 ||
          sampleKey == null) {
        throw StateError('$tableName returned an incomplete Chick identity');
      }
      assignments.add((id: id, replicate: replicate, sampleKey: sampleKey));
    }
    final database = await _databaseHelper.db;
    await database.transaction((txn) async {
      final assignmentIds = assignments.map((item) => item.id).toSet();
      final returnedKeys = assignments
          .map((item) => item.sampleKey)
          .toSet()
          .toList(growable: false);
      final keyPlaceholders = List.filled(returnedKeys.length, '?').join(', ');
      final displacedRows = (await txn.query(
        tableName,
        where: 'sampleKey IN ($keyPlaceholders)',
        whereArgs: returnedKeys,
      )).where((row) => !assignmentIds.contains(_text(row['id']))).toList();
      final rowsToClear = <String>{
        ...assignmentIds,
        for (final row in displacedRows) _text(row['id'])!,
      };
      for (final id in rowsToClear) {
        final changed = await txn.update(
          tableName,
          {'sampleKey': null},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (changed != 1) {
          throw StateError('$tableName cloud identity id is missing: $id');
        }
      }
      for (final assignment in assignments) {
        await txn.update(
          tableName,
          {
            'replicate': assignment.replicate,
            'sampleKey': assignment.sampleKey,
          },
          where: 'id = ?',
          whereArgs: [assignment.id],
        );
      }
      // A local sample can be created after the dirty snapshot is uploaded.
      // If it minted an ordinal the cloud returned for an older row, keep the
      // new row and move only that still-local identity to the next free
      // replicate. It remains pending and will be inserted on the next push.
      for (final displaced in displacedRows) {
        final prepared = await _prepareChickIdentity(txn, tableName, {
          ...displaced,
          'replicate': null,
          'sampleKey': null,
        });
        await txn.update(
          tableName,
          {
            'domain': prepared['domain'],
            'schemaVersion': prepared['schemaVersion'],
            'scopeType': prepared['scopeType'],
            'scopeKey': prepared['scopeKey'],
            'replicate': prepared['replicate'],
            'sampleKey': prepared['sampleKey'],
          },
          where: 'id = ?',
          whereArgs: [prepared['id']],
        );
      }
    });
  }

  /// Panel rows awaiting a push (locally edited or last push failed).
  Future<List<Map<String, dynamic>>> getDirtyRows(String tableName) async {
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    _dirtyReadCutoffByTable[definition.tableName] = DateTime.now()
        .toIso8601String();
    final rows = await database.query(
      definition.tableName,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markRowsSynced(String tableName, Iterable<String> ids) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) return;
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final cutoff =
        _dirtyReadCutoffByTable[definition.tableName] ??
        DateTime.now().toIso8601String();
    final placeholders = List.filled(idList.length, '?').join(', ');
    await database.update(
      definition.tableName,
      {
        'syncStatus': 'synced',
        'lastSyncedAt': DateTime.now().toIso8601String(),
        'dirtyAt': null,
        'syncError': null,
      },
      where: 'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...idList, cutoff],
    );
  }

  Future<void> markRowsFailed(
    String tableName,
    Iterable<String> ids,
    Object error,
  ) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) return;
    final definition = PanelSampleSchema.byTable(tableName);
    final database = await _databaseHelper.db;
    final placeholders = List.filled(idList.length, '?').join(', ');
    await database.update(
      definition.tableName,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: idList,
    );
  }

  /// Per-session, per-panel-table sync rollup for the Audits screen. Runs one
  /// grouped query per panel table (constant — no N+1 over sessions) and returns
  /// `sessionId -> tableName -> syncStatus -> count`. Callers fold table names
  /// into stations and statuses into a single station/session rollup.
  Future<Map<String, Map<String, Map<String, int>>>>
  getStationRollupForSessions(Iterable<String> sessionIds) async {
    final ids = sessionIds.toList(growable: false);
    final result = <String, Map<String, Map<String, int>>>{};
    if (ids.isEmpty) return result;
    final database = await _databaseHelper.db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    for (final panel in PanelSampleSchema.panels) {
      final rows = await database.rawQuery(
        'SELECT sessionId, syncStatus, COUNT(*) AS c FROM ${panel.tableName} '
        'WHERE sessionId IN ($placeholders) GROUP BY sessionId, syncStatus',
        ids,
      );
      for (final row in rows) {
        final sessionId = row['sessionId'] as String?;
        if (sessionId == null) continue;
        final status = (row['syncStatus'] as String?) ?? 'synced';
        final count = (row['c'] as int?) ?? 0;
        final byTable = result.putIfAbsent(sessionId, () => {});
        final byStatus = byTable.putIfAbsent(panel.tableName, () => {});
        byStatus[status] = (byStatus[status] ?? 0) + count;
      }
    }
    return result;
  }

  Map<String, Object?> _stampDirty(Map<String, Object?> row) {
    return {
      ...row,
      'syncStatus': 'pending',
      'dirtyAt': DateTime.now().toIso8601String(),
      'syncError': null,
    };
  }

  Map<String, Object?> _markRowSynced(Map<String, Object?> row) {
    return {
      ...row,
      'syncStatus': 'synced',
      'lastSyncedAt': DateTime.now().toIso8601String(),
      'dirtyAt': null,
      'syncError': null,
    };
  }

  @Deprecated('Panel sample child tables were removed.')
  Future<void> upsertPanelSampleRow(
    String sampleTableName,
    Map<String, dynamic> row,
  ) async {}

  Future<void> _upsertById(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> row,
  ) async {
    final columns = await _tableColumns(executor, table);
    final filtered = Map<String, Object?>.fromEntries(
      _normalizeRow(row).entries.where((entry) => columns.contains(entry.key)),
    );
    final rowId = filtered['id'];
    if (rowId == null) return;
    if (idKeyedPanelTables.contains(table)) {
      final inserted = await executor.insert(
        table,
        filtered,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (inserted != 0) return;
      final updatedById = await executor.update(
        table,
        filtered,
        where: 'id = ?',
        whereArgs: [rowId],
      );
      if (updatedById != 0) return;
      throw StateError(
        '$table rejected id-keyed row $rowId because another immutable '
        'identity conflicts with it',
      );
    }
    final inserted = await executor.insert(
      table,
      filtered,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return;
    final identityRowId = await _rowIdForPanelIdentity(
      executor,
      table,
      filtered,
    );
    if (identityRowId != null && identityRowId != rowId.toString()) {
      final incomingIdExists = await _rowExistsById(executor, table, rowId);
      await _updateExistingPanelIdentity(
        executor,
        table,
        filtered,
        identityRowId,
      );
      if (incomingIdExists) {
        await SyncTombstoneRepository.queueDeleteWithExecutor(
          executor,
          table,
          rowId,
        );
        await executor.delete(table, where: 'id = ?', whereArgs: [rowId]);
      }
      return;
    }
    final updatedById = await executor.update(
      table,
      filtered,
      where: 'id = ?',
      whereArgs: [rowId],
    );
    if (updatedById != 0) return;
    await _updateByPanelIdentity(executor, table, filtered);
  }

  Future<bool> _rowExistsById(
    DatabaseExecutor executor,
    String table,
    Object rowId,
  ) async {
    final rows = await executor.query(
      table,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [rowId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<String?> _rowIdForPanelIdentity(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> row,
  ) async {
    final sessionId = row['sessionId'];
    if (sessionId == null) return null;
    final columns = await _tableColumns(executor, table);
    final hierarchyColumns = _hierarchyColumnsForTable(columns);
    final rows = await executor.query(
      table,
      columns: ['id'],
      where: _panelIdentityWhereForColumns(hierarchyColumns),
      whereArgs: _panelIdentityWhereArgs(row, hierarchyColumns),
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id']?.toString();
  }

  Future<void> _updateExistingPanelIdentity(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> row,
    String existingId,
  ) async {
    final updateValues = Map<String, Object?>.from(row)..remove('id');
    if (updateValues.isEmpty) return;
    await executor.update(
      table,
      updateValues,
      where: 'id = ?',
      whereArgs: [existingId],
    );
  }

  Future<void> _updateByPanelIdentity(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> row,
  ) async {
    final sessionId = row['sessionId'];
    if (sessionId == null) {
      return;
    }

    final updateValues = Map<String, Object?>.from(row)..remove('id');
    if (updateValues.isEmpty) return;
    final columns = await _tableColumns(executor, table);
    final hierarchyColumns = _hierarchyColumnsForTable(columns);
    await executor.update(
      table,
      updateValues,
      where: _panelIdentityWhereForColumns(hierarchyColumns),
      whereArgs: _panelIdentityWhereArgs(row, hierarchyColumns),
    );
  }

  Map<String, Object?> _rowFromLegacySample(
    PanelRecord panel,
    PanelSampleRecord sample,
  ) {
    return {
      ...panel.toMap(),
      'id': sample.id,
      'scopeType': sample.scopeType.dbValue,
      'house': _firstText(sample.houseId, sample.houseName, panel.house),
      'setter': _firstText(sample.setterId, panel.setter),
      'hatcher': _firstText(sample.hatcherId, panel.hatcher),
      'trolley': _firstText(
        sample.trolleyLabel,
        sample.trolleyId,
        panel.trolley,
      ),
      'tray': _firstText(sample.trayLabel, sample.trayId, panel.tray),
      'position': _firstText(sample.position, panel.position),
      'sampleSize': sample.sampleSize,
      'sampleKey': sample.sampleKey,
      'notes': sample.notes ?? panel.notes,
      'createdAt': sample.createdAt.toUtc().toIso8601String(),
      'updatedAt': sample.updatedAt.toUtc().toIso8601String(),
    };
  }

  Future<Map<String, Object?>> _prepareChickIdentity(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> row,
  ) async {
    final definition = PanelSampleSchema.byTable(table);
    if (definition.identityColumnDefinitions.isEmpty) return row;
    final tableColumns = await _tableColumns(executor, table);
    if (!tableColumns.containsAll({
      'domain',
      'scopeKey',
      'replicate',
      'sampleKey',
    })) {
      return row;
    }
    final rowId = _text(row['id']);
    final customerId = _text(row['customerId']);
    final sessionId = _text(row['sessionId']);
    if (rowId == null || customerId == null || sessionId == null) {
      throw ArgumentError('$table requires id, customerId, and sessionId');
    }

    final existing = await executor.query(
      table,
      where: 'id = ?',
      whereArgs: [rowId],
      limit: 1,
    );
    if (existing.isNotEmpty && _text(existing.single['sampleKey']) != null) {
      final prepared = Map<String, Object?>.from(row);
      for (final column in definition.identityColumnDefinitions.map(
        (definition) => definition.split(RegExp(r'\s+')).first,
      )) {
        prepared[column] = existing.single[column];
      }
      // scopeType predates the V2 column list but is part of the immutable
      // envelope once a sample key exists.
      prepared['scopeType'] = existing.single['scopeType'];
      return prepared;
    }

    // Reopened drafts normally retain the persisted id. The sample key is a
    // second stable locator for older/rebuilt draft state whose transient id
    // was regenerated. Recover the persisted row instead of allocating a
    // duplicate replicate; customer/sampleKey uniqueness makes this exact.
    final requestedSampleKey = _text(row['sampleKey']);
    if (existing.isEmpty && requestedSampleKey != null) {
      final bySampleKey = await executor.query(
        table,
        where: 'customerId = ? AND sessionId = ? AND sampleKey = ?',
        whereArgs: [customerId, sessionId, requestedSampleKey],
        limit: 1,
      );
      if (bySampleKey.isNotEmpty) {
        final prepared = Map<String, Object?>.from(row)
          ..['id'] = bySampleKey.single['id'];
        for (final column in definition.identityColumnDefinitions.map(
          (definition) => definition.split(RegExp(r'\s+')).first,
        )) {
          prepared[column] = bySampleKey.single[column];
        }
        prepared['scopeType'] = bySampleKey.single['scopeType'];
        return prepared;
      }
    }

    final scopeType = _scopeTypeForChickIdentity(table, row);
    final domain =
        _text(row['domain']) ??
        (table == 'chick_weights'
            ? 'chicks.weights'
            : 'chicks.legacy_combined');
    final schemaVersion =
        row['schemaVersion'] is int && (row['schemaVersion'] as int) > 0
        ? row['schemaVersion']! as int
        : 1;
    final scopeKey =
        _text(row['scopeKey']) ??
        ChickSampleIdentity.buildLegacyScopeKey(
          scopeType: scopeType,
          house: _text(row['house']),
          setter: _text(row['setter']),
          hatcher: _text(row['hatcher']),
          trolley: _text(row['trolley']),
          tray: _text(row['tray']),
          position: _text(row['position']),
        );

    var replicate = row['replicate'] is int && (row['replicate'] as int) > 0
        ? row['replicate']! as int
        : null;
    var sampleKey = _text(row['sampleKey']);
    if (replicate != null && sampleKey != null) {
      final expected = ChickSampleIdentity.buildSampleKey(
        domain: domain,
        sessionId: sessionId,
        scopeType: scopeType,
        scopeKey: scopeKey,
        replicate: replicate,
      );
      final conflicts = await executor.query(
        table,
        columns: ['id'],
        where: 'customerId = ? AND sampleKey = ? AND id <> ?',
        whereArgs: [customerId, sampleKey, rowId],
        limit: 1,
      );
      if (sampleKey != expected || conflicts.isNotEmpty) {
        replicate = null;
        sampleKey = null;
      }
    } else {
      replicate = null;
      sampleKey = null;
    }
    if (replicate == null) {
      final maximum = Sqflite.firstIntValue(
        await executor.rawQuery(
          '''SELECT MAX(replicate) FROM $table
             WHERE customerId = ? AND sessionId = ? AND domain = ?
               AND scopeType = ? AND scopeKey = ?''',
          [customerId, sessionId, domain, scopeType.dbValue, scopeKey],
        ),
      );
      replicate = (maximum ?? 0) + 1;
      sampleKey = ChickSampleIdentity.buildSampleKey(
        domain: domain,
        sessionId: sessionId,
        scopeType: scopeType,
        scopeKey: scopeKey,
        replicate: replicate,
      );
    }

    final isSyncedPull = row['syncStatus'] == 'synced';
    return {
      ...row,
      'domain': domain,
      'schemaVersion': schemaVersion,
      'scopeType': scopeType.dbValue,
      'scopeKey': scopeKey,
      'replicate': replicate,
      'sampleKey': sampleKey,
      'source': _text(row['source']) ?? (isSyncedPull ? 'legacy' : 'human'),
      'captureMethod':
          _text(row['captureMethod']) ?? (isSyncedPull ? 'unknown' : 'manual'),
      'createdBy': row['createdBy'],
      'deviceId': row['deviceId'],
      'sourceRefId': row['sourceRefId'],
      'observedAt': row['observedAt'] ?? row['createdAt'],
    };
  }

  SamplingLayer _scopeTypeForChickIdentity(
    String table,
    Map<String, Object?> row,
  ) {
    final stored = _text(row['scopeType']);
    if (stored != null) {
      try {
        final parsed = SamplingLayer.fromDbValue(stored);
        if (PanelSampleSchema.byTable(table).allowedLayers.contains(parsed)) {
          return parsed;
        }
      } on ArgumentError {
        // Infer only from explicit hierarchy below.
      }
    }
    if (table == 'chick_weights') {
      return _text(row['house']) == null
          ? SamplingLayer.pool
          : SamplingLayer.house;
    }
    return _text(row['setter']) == null && _text(row['hatcher']) == null
        ? SamplingLayer.pool
        : SamplingLayer.setterHatcher;
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  bool _rowIdMatchesSampleId(String rowId, String sampleId) {
    if (rowId == sampleId) return true;
    final marker = ':$sampleId';
    return rowId.endsWith(marker) || rowId.contains('$marker:');
  }

  Future<void> _deleteRowsByIdWithTombstones(
    DatabaseExecutor executor,
    String tableName,
    Iterable<Object?> rowIds,
  ) async {
    final ids = rowIds
        .map((id) => id?.toString().trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return;
    if (tableName == 'egg_quality') {
      await EggGradingRepository.deleteEggQualityParentsWithExecutor(
        executor,
        ids,
      );
      return;
    }
    await SyncTombstoneRepository.queueDeletesWithExecutor(
      executor,
      tableName,
      ids,
    );
    final placeholders = List.filled(ids.length, '?').join(', ');
    await executor.delete(
      tableName,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<Map<String, Object?>> _withoutOrphanedPanelHatcheryId(
    DatabaseExecutor executor,
    Map<String, Object?> row,
  ) async {
    final rawHatcheryId = row['hatcheryId']?.toString().trim();
    if (rawHatcheryId == null || rawHatcheryId.isEmpty) {
      return row['hatcheryId'] == null
          ? row
          : (Map<String, Object?>.from(row)..['hatcheryId'] = null);
    }
    final hatcheryRows = await executor.query(
      'hatcheries',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [rawHatcheryId],
      limit: 1,
    );
    if (hatcheryRows.isNotEmpty) return row;
    return Map<String, Object?>.from(row)..['hatcheryId'] = null;
  }

  Future<Set<String>> _tableColumns(
    DatabaseExecutor executor,
    String table,
  ) async {
    final rows = await executor.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'] as String).toSet();
  }

  Map<String, Object?> _normalizeRow(Map<dynamic, dynamic> row) {
    return row.map((key, value) => MapEntry(_camelize(key.toString()), value));
  }

  String _camelize(String key) {
    if (!key.contains('_')) return key;
    final parts = key.split('_');
    return parts.first +
        parts.skip(1).map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1);
        }).join();
  }

  static const _defaultHierarchyColumns = [
    'house',
    'setter',
    'hatcher',
    'trolley',
    'tray',
    'position',
  ];

  static List<String> _hierarchyColumnsForTable(Set<String> columns) {
    return _defaultHierarchyColumns
        .where(columns.contains)
        .toList(growable: false);
  }

  /// Orders panel rows by their saved `sampleIndex` when the table has that
  /// column (every panel table, since v61), placing legacy null indexes last
  /// before falling back to `createdAt` and `id` as tiebreakers. Tables without
  /// `sampleIndex` (pre-v61 schemas seen only in older tests) keep the previous
  /// hierarchy-column ordering.
  static String panelOrderByForColumns(Set<String> columns) {
    if (columns.contains('sampleIndex')) {
      final orderColumns = [
        'CASE WHEN sampleIndex IS NULL THEN 1 ELSE 0 END',
        'sampleIndex',
        if (columns.contains('createdAt')) 'createdAt',
        if (columns.contains('id')) 'id',
      ];
      return orderColumns.map((column) => '$column ASC').join(', ');
    }
    final orderColumns = [
      ..._hierarchyColumnsForTable(columns),
      if (columns.contains('createdAt')) 'createdAt',
    ];
    return orderColumns.map((column) => '$column ASC').join(', ');
  }

  static String _hierarchyRowsWhereForColumns(List<String> hierarchyColumns) {
    if (hierarchyColumns.isEmpty) return 'sessionId = ? AND 1 = 0';
    final hierarchyWhere = hierarchyColumns
        .map((column) => '$column IS NOT NULL')
        .join('\n      OR ');
    return '''
      sessionId = ?
      AND (
        $hierarchyWhere
      )
    ''';
  }

  static String _pooledRowsWhereForColumns(List<String> hierarchyColumns) {
    if (hierarchyColumns.isEmpty) return 'sessionId = ?';
    final hierarchyWhere = hierarchyColumns
        .map((column) => '$column IS NULL')
        .join('\n      AND ');
    return '''
      sessionId = ?
      AND $hierarchyWhere
    ''';
  }

  static String _panelIdentityWhereForColumns(List<String> hierarchyColumns) {
    final hierarchyWhere = hierarchyColumns
        .map((column) => "AND IFNULL($column, '') = ?")
        .join('\n    ');
    return '''
    sessionId = ?
    $hierarchyWhere
  ''';
  }

  static List<Object?> _panelIdentityWhereArgs(
    Map<String, Object?> row,
    List<String> hierarchyColumns,
  ) {
    return [
      row['sessionId'],
      for (final column in hierarchyColumns) row[column] ?? '',
    ];
  }

  static String _hierarchyKey(
    Map<String, Object?> row,
    List<String> hierarchyColumns,
  ) {
    return hierarchyColumns
        .map((column) => row[column]?.toString().trim() ?? '')
        .join('\u001F');
  }

  String? _firstText(String? first, [String? second, String? third]) {
    for (final value in [first, second, third]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}
