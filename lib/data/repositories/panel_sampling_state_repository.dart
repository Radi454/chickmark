import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/panel_sample_schema.dart';
import '../models/panel_sampling_state.dart';
import '../models/sampling_scope.dart';
import '../../services/sync/app_sync_coordinator.dart';
import 'panel_sample_repository.dart';
import 'photo_repository.dart';
import 'sync_tombstone_repository.dart';

/// Persists per-session, per-panel sampling trees and their stable SA serials.
class PanelSamplingStateRepository {
  PanelSamplingStateRepository({
    DatabaseHelper? databaseHelper,
    PanelSampleRepository? panelSampleRepository,
    PhotoRepository? photoRepository,
    Uuid? uuid,
  }) : _databaseHelper = databaseHelper ?? DatabaseHelper(),
       _panelSamples = panelSampleRepository ?? PanelSampleRepository(),
       _photos = photoRepository ?? PhotoRepository(),
       _uuid = uuid ?? const Uuid();

  static const statesTable = 'panel_sampling_states';
  static const nodesTable = 'panel_sampling_nodes';
  static const reservationsTable = 'panel_sample_serial_reservations';
  static const _syncTables = {statesTable, nodesTable, reservationsTable};

  final DatabaseHelper _databaseHelper;
  final PanelSampleRepository _panelSamples;
  final PhotoRepository _photos;
  final Uuid _uuid;
  final Map<String, String?> _dirtyCutoffs = {};
  final Map<String, String> _activeSampleByState = {};

  Future<PanelSamplingState> loadOrCreateDefault({
    required String sessionId,
    required String panelKey,
  }) async {
    _config(panelKey);
    final db = await _databaseHelper.db;
    late PanelSamplingState state;
    var created = false;
    await db.transaction<void>((txn) async {
      await _requireSession(txn, sessionId);
      final stateRows = await txn.query(
        statesTable,
        where: 'sessionId = ? AND panelKey = ?',
        whereArgs: [sessionId, panelKey],
        limit: 1,
      );
      if (stateRows.isEmpty) {
        created = true;
        final now = _now();
        final legacyRows = await _legacyRows(txn, panelKey, sessionId);
        final maximum = await _maxReservedSerial(txn, sessionId, panelKey);
        await txn.insert(statesTable, {
          'id': _stateId(sessionId, panelKey),
          'sessionId': sessionId,
          'panelKey': panelKey,
          'serialHighWatermark': maximum,
          'createdAt': now,
          'updatedAt': now,
          ..._dirtyValues(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (legacyRows.isNotEmpty) {
          await _backfillLegacyRows(txn, sessionId, panelKey, legacyRows);
        } else {
          await _createDefaultTerminal(txn, sessionId, panelKey, null);
        }
      }
      state = await _readState(txn, sessionId, panelKey);
      if (state.nodes.isEmpty) {
        created = true;
        await _createDefaultTerminal(txn, sessionId, panelKey, null);
        state = await _readState(txn, sessionId, panelKey);
      }
    });
    if (created) AppSyncCoordinator.nudge();
    final active = state.resolvedActiveSampleId;
    if (active != null) {
      _activeSampleByState[_stateId(sessionId, panelKey)] = active;
    }
    return _withActive(state, active);
  }

  Future<SamplingNode> addScopeIdentity({
    required String sessionId,
    required String panelKey,
    required String? parentId,
    required SamplingScopeLevel level,
    required Map<String, String> identity,
    bool discardPooledData = false,
  }) async {
    final config = _config(panelKey);
    final db = await _databaseHelper.db;
    late SamplingNode created;
    final discardedPhotoPaths = <String>[];
    await db.transaction<void>((txn) async {
      await _requireSession(txn, sessionId);
      await _ensureState(txn, sessionId, panelKey);
      final effectiveLevel = _effectiveScopeLevel(config, level);
      await _validateScopeLocation(
        txn,
        sessionId,
        panelKey,
        config,
        parentId,
        effectiveLevel,
      );
      final normalized = _validatedIdentity(config, effectiveLevel, identity);
      if (effectiveLevel == config.terminalLevel) {
        if (config.terminalLevel != SamplingScopeLevel.tray) {
          throw ArgumentError(
            'Use addTerminalSample for panel-native samples.',
          );
        }
        final identityKey = _identityKey(effectiveLevel, normalized);
        final duplicate = await txn.query(
          nodesTable,
          columns: ['id'],
          where:
              'sessionId = ? AND panelKey = ? AND parentId = ? '
              'AND sampleId IS NOT NULL AND identityKey = ?',
          whereArgs: [sessionId, panelKey, parentId ?? '', identityKey],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          throw ArgumentError(
            'That terminal sample identity already exists under this parent.',
          );
        }
        created = await _createTerminalSample(
          txn,
          sessionId,
          panelKey,
          parentId,
          normalized,
        );
        return;
      }
      final identityKey = _identityKey(effectiveLevel, normalized);
      final duplicate = await txn.query(
        nodesTable,
        columns: ['id'],
        where:
            'sessionId = ? AND panelKey = ? AND parentId = ? AND level = ? '
            'AND identityKey = ? AND IFNULL(isTerminal, 0) = 0',
        whereArgs: [
          sessionId,
          panelKey,
          parentId ?? '',
          effectiveLevel.name,
          identityKey,
        ],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw ArgumentError(
          'That scope identity already exists under this parent.',
        );
      }

      discardedPhotoPaths.addAll(
        await _removePooledDefaultBeforeComparison(
          txn,
          sessionId,
          panelKey,
          parentId,
          discardPooledData: discardPooledData,
          targetLevel: effectiveLevel,
        ),
      );
      final now = _now();
      created = SamplingNode(
        id: _uuid.v4(),
        sessionId: sessionId,
        panelKey: panelKey,
        parentId: parentId,
        level: effectiveLevel,
        identityKey: identityKey,
        identity: normalized,
        createdAt: DateTime.parse(now),
        updatedAt: DateTime.parse(now),
      );
      await txn.insert(nodesTable, {
        ...created.toMap(),
        'parentId': parentId ?? '',
        'isTerminal': 0,
        ..._dirtyValues(),
      });
      await _touchState(txn, sessionId, panelKey);
    });
    await _photos.deleteUnreferencedLocalFiles(discardedPhotoPaths);
    AppSyncCoordinator.nudge();
    return created;
  }

  Future<void> updateScopeIdentity({
    required String nodeId,
    required Map<String, String> identity,
  }) async {
    final db = await _databaseHelper.db;
    await db.transaction<void>((txn) async {
      final node = await _nodeById(txn, nodeId);
      await _requireSession(txn, node.sessionId);
      final config = _config(node.panelKey);
      final normalized = _validatedIdentity(config, node.level, identity);
      final identityKey = _identityKey(node.level, normalized);
      if (identityKey != node.identityKey) {
        final terminalClause = node.sampleId == null
            ? 'IFNULL(isTerminal, 0) = 0'
            : 'sampleId IS NOT NULL';
        final duplicates = await txn.query(
          nodesTable,
          columns: ['id'],
          where:
              'sessionId = ? AND panelKey = ? AND parentId = ? AND level = ? '
              'AND identityKey = ? AND id <> ? AND $terminalClause',
          whereArgs: [
            node.sessionId,
            node.panelKey,
            node.parentId ?? '',
            node.level.name,
            identityKey,
            nodeId,
          ],
          limit: 1,
        );
        if (duplicates.isNotEmpty) {
          throw ArgumentError(
            'That scope identity already exists under this parent.',
          );
        }
      }
      await txn.update(
        nodesTable,
        {
          'identityKey': identityKey,
          'identityJson': jsonEncode(normalized),
          'updatedAt': _now(),
          ..._dirtyValues(),
        },
        where: 'id = ?',
        whereArgs: [nodeId],
      );
      await _refreshMeasurementPathsForDescendants(txn, node);
      await _touchState(txn, node.sessionId, node.panelKey);
    });
    AppSyncCoordinator.nudge();
  }

  Future<SamplingDeletePreview> previewDeleteSubtree({
    required String nodeId,
  }) async {
    final db = await _databaseHelper.db;
    final node = await _nodeById(db, nodeId);
    final descendants = await _descendantNodes(db, node);
    final sampleIds = descendants
        .map((item) => item.sampleId)
        .whereType<String>()
        .toSet();
    final rows = await _matchingMeasurementRows(
      db,
      node.panelKey,
      node.sessionId,
      sampleIds,
    );
    final photoTargets = await _photoTargetsForSamples(
      db,
      node.panelKey,
      node.sessionId,
      sampleIds,
      rows,
    );
    final noteCount = rows.where((row) => _text(row['notes']) != null).length;
    return SamplingDeletePreview(
      nodeId: node.id,
      scopeLabel: _scopeLabel(node),
      descendantCount: descendants.length - 1,
      measurementCount: rows.length,
      photoCount: photoTargets.photoCount,
      noteCount: noteCount,
    );
  }

  Future<void> deleteSubtree({required String nodeId}) async {
    final db = await _databaseHelper.db;
    late String sessionId;
    late String panelKey;
    late Set<String> deletedSamples;
    late List<String> deletedPhotoPaths;
    late SamplingScopeLevel removedLevel;
    late String? parentId;
    await db.transaction<void>((txn) async {
      final node = await _nodeById(txn, nodeId);
      sessionId = node.sessionId;
      panelKey = node.panelKey;
      parentId = node.parentId;
      removedLevel = node.level;
      await _requireSession(txn, sessionId);
      final descendants = await _descendantNodes(txn, node);
      deletedSamples = descendants
          .map((item) => item.sampleId)
          .whereType<String>()
          .toSet();

      final measurementRows = await _matchingMeasurementRows(
        txn,
        panelKey,
        sessionId,
        deletedSamples,
      );
      final photoTargets = await _photoTargetsForSamples(
        txn,
        panelKey,
        sessionId,
        deletedSamples,
        measurementRows,
      );
      deletedPhotoPaths = await _photos.deleteForPanelRowsWithExecutor(
        txn,
        sessionId: sessionId,
        panelName: panelKey,
        panelRowIds: photoTargets.panelRowIds,
        observationIds: photoTargets.observationIds,
      );

      await _panelSamples.deleteRowsBySessionIdForSampleIdsWithExecutor(
        txn,
        panelKey,
        sessionId,
        deletedSamples,
      );
      await SyncTombstoneRepository.queueDeletesWithExecutor(
        txn,
        nodesTable,
        descendants.reversed.map((item) => item.id),
      );
      final ids = descendants.map((item) => item.id).toList(growable: false);
      await txn.delete(
        nodesTable,
        where: 'id IN (${_placeholders(ids.length)})',
        whereArgs: ids,
      );
      await _touchState(txn, sessionId, panelKey);

      final remaining = await _readState(txn, sessionId, panelKey);
      final comparisonSibling = remaining.nodes.any(
        (item) =>
            item.parentId == parentId &&
            item.level == removedLevel &&
            item.sampleId == null,
      );
      final parentBranchHasSamples = await _hasSamplesBelow(
        txn,
        sessionId,
        panelKey,
        parentId,
      );
      if (!comparisonSibling && !parentBranchHasSamples) {
        await _createDefaultTerminal(txn, sessionId, panelKey, parentId);
      }
    });
    await _photos.deleteUnreferencedLocalFiles(deletedPhotoPaths);
    AppSyncCoordinator.nudge();
    _activeSampleByState.remove(_stateId(sessionId, panelKey));
    final state = await loadOrCreateDefault(
      sessionId: sessionId,
      panelKey: panelKey,
    );
    final active = state.resolvedActiveSampleId;
    if (active != null) {
      _activeSampleByState[_stateId(sessionId, panelKey)] = active;
    }
  }

  Future<SamplingNode> addTerminalSample({
    required String sessionId,
    required String panelKey,
    required String? parentId,
    Map<String, String>? identity,
  }) async {
    final config = _config(panelKey);
    final db = await _databaseHelper.db;
    late SamplingNode created;
    final discardedPhotoPaths = <String>[];
    await db.transaction<void>((txn) async {
      await _requireSession(txn, sessionId);
      await _ensureState(txn, sessionId, panelKey);
      await _validateTerminalParentAsync(
        txn,
        sessionId,
        panelKey,
        config,
        parentId,
      );
      if (config.terminalLevel == SamplingScopeLevel.tray && identity == null) {
        throw ArgumentError('Tray samples require an identity.');
      }
      final supplied = identity == null
          ? const <String, String>{}
          : _validatedIdentity(config, config.terminalLevel, identity);
      if (config.terminalLevel == SamplingScopeLevel.tray) {
        final identityKey = _identityKey(config.terminalLevel, supplied);
        final duplicate = await txn.query(
          nodesTable,
          columns: ['id'],
          where:
              'sessionId = ? AND panelKey = ? AND parentId = ? '
              'AND sampleId IS NOT NULL AND identityKey = ?',
          whereArgs: [sessionId, panelKey, parentId ?? '', identityKey],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          throw ArgumentError(
            'That terminal sample identity already exists under this parent.',
          );
        }
      } else {
        final existingSample = await txn.query(
          nodesTable,
          columns: ['id'],
          where:
              'sessionId = ? AND panelKey = ? AND parentId = ? AND level = ? AND sampleId IS NOT NULL',
          whereArgs: [
            sessionId,
            panelKey,
            parentId ?? '',
            config.terminalLevel.name,
          ],
          limit: 1,
        );
        if (existingSample.isNotEmpty) {
          throw ArgumentError('This parent already has its terminal sample.');
        }
      }
      created = await _createTerminalSample(
        txn,
        sessionId,
        panelKey,
        parentId,
        supplied,
      );
    });
    await _photos.deleteUnreferencedLocalFiles(discardedPhotoPaths);
    AppSyncCoordinator.nudge();
    return created;
  }

  Future<void> upsertMeasurementIdentity({
    required String sampleId,
    required String measurementRowId,
    required SamplingScopePath path,
    required DatabaseExecutor executor,
  }) async {
    final nodeRows = await executor.query(
      nodesTable,
      where: 'sampleId = ?',
      whereArgs: [sampleId],
      limit: 1,
    );
    if (nodeRows.isEmpty) throw StateError('Unknown sample ID "$sampleId".');
    final sample = _nodeFromRow(nodeRows.single);
    if (path.sampleId != sampleId || path.sampleNumber != sample.sampleNumber) {
      throw ArgumentError('Sampling path does not match the terminal sample.');
    }
    final config = _config(sample.panelKey);
    config.validatePath(_validationPath(path, config));
    final columns = await _tableColumns(executor, sample.panelKey);
    final values = <String, Object?>{
      if (config.levels.contains(SamplingScopeLevel.house) &&
          columns.contains('house'))
        'house': path.house,
      if (config.levels.contains(SamplingScopeLevel.setter) &&
          columns.contains('setter'))
        'setter': path.setter,
      if (config.levels.contains(SamplingScopeLevel.hatcher) &&
          columns.contains('hatcher'))
        'hatcher': path.hatcher,
      if (config.levels.contains(SamplingScopeLevel.trolley) &&
          columns.contains('trolley'))
        'trolley': path.trolley,
      if (config.levels.contains(SamplingScopeLevel.tray) &&
          columns.contains('tray'))
        'tray': path.tray,
      if (columns.contains('sampleId')) 'sampleId': sampleId,
      if (columns.contains('sampleNumber')) 'sampleNumber': path.sampleNumber,
      if (columns.contains('samplingPathJson'))
        'samplingPathJson': path.toJsonString(),
      if (columns.contains('updatedAt')) 'updatedAt': _now(),
      if (columns.contains('syncStatus')) ..._dirtyValues(),
    };
    final count = await executor.update(
      sample.panelKey,
      values,
      where: 'id = ? AND sessionId = ?',
      whereArgs: [measurementRowId, sample.sessionId],
    );
    if (count == 0) {
      throw StateError('Measurement row "$measurementRowId" was not found.');
    }
  }

  Future<void> _refreshMeasurementPathsForDescendants(
    DatabaseExecutor executor,
    SamplingNode editedNode,
  ) async {
    final rootRows = await executor.query(
      nodesTable,
      where: 'id = ?',
      whereArgs: [editedNode.id],
      limit: 1,
    );
    if (rootRows.isEmpty) return;
    final currentRoot = _nodeFromRow(rootRows.single);
    final descendants = await _descendantNodes(executor, currentRoot);
    final sampleIds = descendants
        .map((node) => node.sampleId)
        .whereType<String>()
        .toSet();
    if (sampleIds.isEmpty) return;
    final state = await _readState(
      executor,
      editedNode.sessionId,
      editedNode.panelKey,
    );
    final rows = await _matchingMeasurementRows(
      executor,
      editedNode.panelKey,
      editedNode.sessionId,
      sampleIds,
    );
    for (final row in rows) {
      final sampleId = _text(row['sampleId']) ?? _text(row['id']);
      if (sampleId == null || !sampleIds.contains(sampleId)) continue;
      await upsertMeasurementIdentity(
        sampleId: sampleId,
        measurementRowId: row['id'].toString(),
        path: state.pathFor(sampleId),
        executor: executor,
      );
    }
  }

  Future<void> reconcileSerialCollision({
    required String sessionId,
    required String panelKey,
    required int conflictingNumber,
    required List<String> collidingSampleIds,
  }) async {
    _config(panelKey);
    if (collidingSampleIds.length < 2) return;
    final db = await _databaseHelper.db;
    await db.transaction<void>((txn) async {
      await _requireSession(txn, sessionId);
      await _ensureState(txn, sessionId, panelKey);
      final ids = collidingSampleIds.toSet().toList()..sort();
      final placeholders = _placeholders(ids.length);
      final existing = await txn.query(
        nodesTable,
        where: 'sessionId = ? AND panelKey = ? AND sampleId IN ($placeholders)',
        whereArgs: [sessionId, panelKey, ...ids],
      );
      final bySample = {
        for (final row in existing) row['sampleId'] as String: row,
      };
      final validIds = ids.where(bySample.containsKey).toList();
      if (validIds.length < 2) return;
      var high = await _serialHighWatermark(txn, sessionId, panelKey);
      final reservedHigh = await _maxReservedSerial(txn, sessionId, panelKey);
      final activeHigh =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT MAX(sampleNumber) FROM $nodesTable WHERE sessionId = ? AND panelKey = ?',
              [sessionId, panelKey],
            ),
          ) ??
          0;
      high = [high, reservedHigh, activeHigh].reduce((a, b) => a > b ? a : b);
      final now = _now();
      final winningId = validIds.first;
      final winner = _nodeFromRow(bySample[winningId]!);
      if (winner.sampleNumber != conflictingNumber) {
        await txn.update(
          nodesTable,
          {
            'sampleNumber': conflictingNumber,
            'updatedAt': now,
            ..._dirtyValues(),
          },
          where: 'id = ?',
          whereArgs: [winner.id],
        );
        await _updateReservation(
          txn,
          sessionId,
          panelKey,
          winningId,
          conflictingNumber,
          now,
        );
        await _updateMeasurementSerial(
          txn,
          sessionId,
          panelKey,
          winningId,
          now,
        );
      }
      for (final id in validIds.skip(1)) {
        high += 1;
        final node = _nodeFromRow(bySample[id]!);
        await txn.update(
          nodesTable,
          {'sampleNumber': high, 'updatedAt': now, ..._dirtyValues()},
          where: 'id = ?',
          whereArgs: [node.id],
        );
        await _updateReservation(txn, sessionId, panelKey, id, high, now);
        await _updateMeasurementSerial(txn, sessionId, panelKey, id, now);
      }
      await txn.update(
        statesTable,
        {'serialHighWatermark': high, 'updatedAt': now, ..._dirtyValues()},
        where: 'sessionId = ? AND panelKey = ?',
        whereArgs: [sessionId, panelKey],
      );
    });
    AppSyncCoordinator.nudge();
  }

  Future<List<Map<String, Object?>>> getActiveSerialRows({
    required String sessionId,
    required String panelKey,
  }) async {
    _config(panelKey);
    final db = await _databaseHelper.db;
    final rows = await db.query(
      nodesTable,
      columns: ['sampleId', 'sampleNumber'],
      where: 'sessionId = ? AND panelKey = ? AND sampleId IS NOT NULL',
      whereArgs: [sessionId, panelKey],
      orderBy: 'sampleNumber ASC, sampleId ASC',
    );
    return rows
        .map(
          (row) => <String, Object?>{
            'sampleId': row['sampleId'],
            'sampleNumber': row['sampleNumber'],
          },
        )
        .toList(growable: false);
  }

  Future<void> applySerialAssignments({
    required String sessionId,
    required String panelKey,
    required Map<String, int> assignments,
  }) async {
    _config(panelKey);
    if (assignments.isEmpty) return;
    final db = await _databaseHelper.db;
    await db.transaction<void>((txn) async {
      await _requireSession(txn, sessionId);
      await _ensureState(txn, sessionId, panelKey);
      final now = _now();
      var high = await _serialHighWatermark(txn, sessionId, panelKey);
      for (final entry in assignments.entries) {
        if (entry.value < 1) {
          throw ArgumentError('Sample serials must be positive.');
        }
        final rows = await txn.query(
          nodesTable,
          columns: ['id'],
          where: 'sessionId = ? AND panelKey = ? AND sampleId = ?',
          whereArgs: [sessionId, panelKey, entry.key],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        await txn.update(
          nodesTable,
          {'sampleNumber': entry.value, 'updatedAt': now, ..._dirtyValues()},
          where: 'id = ?',
          whereArgs: [rows.single['id']],
        );
        await _updateReservation(
          txn,
          sessionId,
          panelKey,
          entry.key,
          entry.value,
          now,
        );
        await _updateMeasurementSerial(
          txn,
          sessionId,
          panelKey,
          entry.key,
          now,
        );
        if (entry.value > high) high = entry.value;
      }
      await txn.update(
        statesTable,
        {'serialHighWatermark': high, 'updatedAt': now, ..._dirtyValues()},
        where: 'sessionId = ? AND panelKey = ?',
        whereArgs: [sessionId, panelKey],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getDirtyRows(String tableName) async {
    _requireSyncTable(tableName);
    final db = await _databaseHelper.db;
    final cutoff = _now();
    _dirtyCutoffs[tableName] = cutoff;
    return db.query(
      tableName,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC',
    );
  }

  Future<void> markRowsSynced(String tableName, Iterable<String> ids) async {
    _requireSyncTable(tableName);
    final values = ids.toSet().toList(growable: false);
    if (values.isEmpty) return;
    final db = await _databaseHelper.db;
    final cutoff = _dirtyCutoffs[tableName] ?? _now();
    await db.update(
      tableName,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _now(),
        'syncError': null,
      },
      where:
          'id IN (${_placeholders(values.length)}) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...values, cutoff],
    );
  }

  Future<void> markRowsFailed(
    String tableName,
    Iterable<String> ids,
    Object error,
  ) async {
    _requireSyncTable(tableName);
    final values = ids.toSet().toList(growable: false);
    if (values.isEmpty) return;
    final db = await _databaseHelper.db;
    await db.update(
      tableName,
      {
        'syncStatus': 'failed',
        'syncError': error.toString(),
        'dirtyAt': _now(),
      },
      where: 'id IN (${_placeholders(values.length)})',
      whereArgs: values,
    );
  }

  /// Applies one row pulled from the remote mirror. State high-watermarks merge
  /// by maximum so a stale device cannot lower the serial floor.
  Future<void> upsertRemoteRow({
    required String tableName,
    required Map<String, Object?> row,
  }) async {
    _requireSyncTable(tableName);
    final db = await _databaseHelper.db;
    await db.transaction<void>((txn) async {
      final remote = Map<String, Object?>.from(row)
        ..['syncStatus'] = 'synced'
        ..['dirtyAt'] = null
        ..['lastSyncedAt'] = _now()
        ..['syncError'] = null;
      final remoteId = _text(row['id']);
      var localRows = remoteId == null
          ? const <Map<String, Object?>>[]
          : await txn.query(
              tableName,
              where: 'id = ?',
              whereArgs: [remoteId],
              limit: 1,
            );
      if (tableName == nodesTable &&
          localRows.isEmpty &&
          remoteId != null &&
          row['sampleId'] == null &&
          row['isTerminal'] != 1) {
        final localGroups = await txn.query(
          nodesTable,
          where:
              'sessionId = ? AND panelKey = ? AND parentId = ? '
              'AND level = ? AND identityKey = ? AND sampleId IS NULL '
              'AND IFNULL(isTerminal, 0) = 0 '
              "AND syncStatus IN ('pending', 'failed') AND id <> ?",
          whereArgs: [
            row['sessionId'],
            row['panelKey'],
            row['parentId'] ?? '',
            row['level'],
            row['identityKey'],
            remoteId,
          ],
          limit: 1,
        );
        if (localGroups.isNotEmpty) {
          final localId = localGroups.single['id'] as String;
          final now = _now();
          await _reparentLocalNodeChildren(
            txn,
            localId: localId,
            remoteParentId: remoteId,
            sessionId: row['sessionId']! as String,
            panelKey: row['panelKey']! as String,
            now: now,
          );
          await SyncTombstoneRepository.queueDeleteWithExecutor(
            txn,
            nodesTable,
            localId,
          );
          await txn.update(
            nodesTable,
            {
              'id': remoteId,
              'syncStatus': 'pending',
              'updatedAt': now,
              'dirtyAt': now,
              'syncError': null,
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          localRows = await txn.query(
            nodesTable,
            where: 'id = ?',
            whereArgs: [remoteId],
            limit: 1,
          );
        }
      }
      final preserveLocal =
          localRows.isNotEmpty &&
          const {'pending', 'failed'}.contains(localRows.single['syncStatus']);
      if (tableName == statesTable) {
        final rows = await txn.query(
          statesTable,
          columns: ['serialHighWatermark'],
          where: 'sessionId = ? AND panelKey = ?',
          whereArgs: [row['sessionId'], row['panelKey']],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final localHigh =
              (rows.single['serialHighWatermark'] as num?)?.toInt() ?? 0;
          final remoteHigh = (row['serialHighWatermark'] as num?)?.toInt() ?? 0;
          remote['serialHighWatermark'] = localHigh > remoteHigh
              ? localHigh
              : remoteHigh;
        }
      }
      if (preserveLocal) return;
      await txn.insert(
        tableName,
        remote,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Reparents a local grouping branch to its remote canonical parent. A
  /// child-first pull may already have inserted remote descendants, so merge
  /// same-identity grouping children recursively before updating parentId.
  Future<void> _reparentLocalNodeChildren(
    DatabaseExecutor executor, {
    required String localId,
    required String remoteParentId,
    required String sessionId,
    required String panelKey,
    required String now,
  }) async {
    final localChildren = await executor.query(
      nodesTable,
      where: 'sessionId = ? AND panelKey = ? AND parentId = ?',
      whereArgs: [sessionId, panelKey, localId],
    );
    for (final child in localChildren) {
      final childId = child['id'] as String;
      final isGroupingNode =
          child['sampleId'] == null &&
          (child['isTerminal'] as num?)?.toInt() != 1;
      if (isGroupingNode) {
        final remoteMatches = await executor.query(
          nodesTable,
          where:
              'sessionId = ? AND panelKey = ? AND parentId = ? '
              'AND level = ? AND identityKey = ? AND sampleId IS NULL '
              'AND IFNULL(isTerminal, 0) = 0 AND id <> ?',
          whereArgs: [
            sessionId,
            panelKey,
            remoteParentId,
            child['level'],
            child['identityKey'],
            childId,
          ],
          limit: 1,
        );
        if (remoteMatches.isNotEmpty) {
          final remoteChildId = remoteMatches.single['id'] as String;
          await _mergeLocalGroupingNode(
            executor,
            localNode: child,
            remoteNodeId: remoteChildId,
            sessionId: sessionId,
            panelKey: panelKey,
            now: now,
          );
          continue;
        }
      }
      await executor.update(
        nodesTable,
        {
          'parentId': remoteParentId,
          'syncStatus': 'pending',
          'dirtyAt': now,
          'syncError': null,
          'updatedAt': now,
        },
        where: 'id = ?',
        whereArgs: [childId],
      );
    }
  }

  Future<void> _mergeLocalGroupingNode(
    DatabaseExecutor executor, {
    required Map<String, Object?> localNode,
    required String remoteNodeId,
    required String sessionId,
    required String panelKey,
    required String now,
  }) async {
    final localId = localNode['id'] as String;
    await _reparentLocalNodeChildren(
      executor,
      localId: localId,
      remoteParentId: remoteNodeId,
      sessionId: sessionId,
      panelKey: panelKey,
      now: now,
    );
    await executor.update(
      nodesTable,
      {
        'identityJson': localNode['identityJson'],
        'syncStatus': 'pending',
        'dirtyAt': now,
        'syncError': null,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [remoteNodeId],
    );
    await SyncTombstoneRepository.queueDeleteWithExecutor(
      executor,
      nodesTable,
      localId,
    );
    await executor.delete(nodesTable, where: 'id = ?', whereArgs: [localId]);
  }

  Future<PanelSamplingState> _readState(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
  ) async {
    final stateRows = await executor.query(
      statesTable,
      where: 'sessionId = ? AND panelKey = ?',
      whereArgs: [sessionId, panelKey],
      limit: 1,
    );
    if (stateRows.isEmpty) {
      throw StateError('Sampling state was not initialized.');
    }
    final nodeRows = await executor.query(
      nodesTable,
      where: 'sessionId = ? AND panelKey = ?',
      whereArgs: [sessionId, panelKey],
    );
    final nodes = nodeRows.map(_nodeFromRow).toList(growable: false);
    final id = _stateId(sessionId, panelKey);
    final fallback =
        nodes
            .where((node) => node.sampleId != null)
            .map((node) => node.sampleId!)
            .firstOrNull ??
        '';
    return PanelSamplingState(
      sessionId: sessionId,
      panelKey: panelKey,
      nodes: nodes,
      serialHighWatermark:
          (stateRows.single['serialHighWatermark'] as num?)?.toInt() ?? 0,
      activeSampleId: _activeSampleByState[id] ?? fallback,
    );
  }

  Future<void> _ensureState(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
  ) async {
    final rows = await executor.query(
      statesTable,
      where: 'sessionId = ? AND panelKey = ?',
      whereArgs: [sessionId, panelKey],
      limit: 1,
    );
    if (rows.isNotEmpty) return;
    final now = _now();
    await executor.insert(statesTable, {
      'id': _stateId(sessionId, panelKey),
      'sessionId': sessionId,
      'panelKey': panelKey,
      'serialHighWatermark': await _maxReservedSerial(
        executor,
        sessionId,
        panelKey,
      ),
      'createdAt': now,
      'updatedAt': now,
      ..._dirtyValues(),
    });
  }

  Future<SamplingNode> _createDefaultTerminal(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
    String? parentId,
  ) async {
    final config = _config(panelKey);
    final terminalIdentity = config.terminalLevel == SamplingScopeLevel.tray
        ? const {'code': 'T1', 'name': 'Tray 1'}
        : const <String, String>{};
    return _createTerminalSample(
      executor,
      sessionId,
      panelKey,
      parentId,
      terminalIdentity,
      deterministicDefault: true,
    );
  }

  Future<SamplingNode> _createTerminalSample(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
    String? parentId,
    Map<String, String> identity, {
    bool deterministicDefault = false,
  }) async {
    final config = _config(panelKey);
    final number = await _allocateSerial(executor, sessionId, panelKey);
    final sampleId = deterministicDefault
        ? _uuid.v5(
            Namespace.url.value,
            'panel-default-sample:$sessionId:$panelKey:${parentId ?? 'root'}:$number',
          )
        : _uuid.v4();
    final now = _now();
    final terminalIdentity = Map<String, String>.unmodifiable(identity);
    final node = SamplingNode(
      id: deterministicDefault
          ? _uuid.v5(
              Namespace.url.value,
              'panel-default-node:$sessionId:$panelKey:${parentId ?? 'root'}:$number',
            )
          : _uuid.v4(),
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: config.terminalLevel,
      identityKey: config.terminalLevel == SamplingScopeLevel.tray
          ? _identityKey(SamplingScopeLevel.tray, terminalIdentity)
          : '',
      identity: terminalIdentity,
      sampleId: sampleId,
      sampleNumber: number,
      createdAt: DateTime.parse(now),
      updatedAt: DateTime.parse(now),
    );
    await executor.insert(nodesTable, {
      ...node.toMap(),
      'parentId': parentId ?? '',
      'isTerminal': 1,
      ..._dirtyValues(),
    });
    await executor.insert(reservationsTable, {
      'id': _reservationId(sessionId, panelKey, sampleId),
      'sessionId': sessionId,
      'panelKey': panelKey,
      'sampleNumber': number,
      'sampleId': sampleId,
      'createdAt': now,
      ..._dirtyValues(),
    });
    return node;
  }

  Future<int> _allocateSerial(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
  ) async {
    final stateRows = await executor.query(
      statesTable,
      columns: ['serialHighWatermark'],
      where: 'sessionId = ? AND panelKey = ?',
      whereArgs: [sessionId, panelKey],
      limit: 1,
    );
    final current = stateRows.isEmpty
        ? 0
        : (stateRows.single['serialHighWatermark'] as num?)?.toInt() ?? 0;
    final maxReserved = await _maxReservedSerial(executor, sessionId, panelKey);
    final maxActive =
        Sqflite.firstIntValue(
          await executor.rawQuery(
            'SELECT MAX(sampleNumber) FROM $nodesTable WHERE sessionId = ? AND panelKey = ?',
            [sessionId, panelKey],
          ),
        ) ??
        0;
    final next =
        [current, maxReserved, maxActive].reduce((a, b) => a > b ? a : b) + 1;
    final now = _now();
    await executor.update(
      statesTable,
      {'serialHighWatermark': next, 'updatedAt': now, ..._dirtyValues()},
      where: 'sessionId = ? AND panelKey = ?',
      whereArgs: [sessionId, panelKey],
    );
    return next;
  }

  Future<void> _updateReservation(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
    String sampleId,
    int number,
    String now,
  ) async {
    final count = await executor.update(
      reservationsTable,
      {'sampleNumber': number, ..._dirtyValues()},
      where: 'sessionId = ? AND panelKey = ? AND sampleId = ?',
      whereArgs: [sessionId, panelKey, sampleId],
    );
    if (count == 0) {
      await executor.insert(reservationsTable, {
        'id': _reservationId(sessionId, panelKey, sampleId),
        'sessionId': sessionId,
        'panelKey': panelKey,
        'sampleNumber': number,
        'sampleId': sampleId,
        'createdAt': now,
        ..._dirtyValues(),
      });
    }
  }

  Future<int> _maxReservedSerial(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
  ) async =>
      Sqflite.firstIntValue(
        await executor.rawQuery(
          'SELECT MAX(sampleNumber) FROM $reservationsTable WHERE sessionId = ? AND panelKey = ?',
          [sessionId, panelKey],
        ),
      ) ??
      0;

  Future<void> _updateMeasurementSerial(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
    String sampleId,
    String now,
  ) async {
    final columns = await _tableColumns(executor, panelKey);
    if (!columns.contains('sampleNumber')) return;
    final state = await _readState(executor, sessionId, panelKey);
    final path = state.pathFor(sampleId);
    final rows = await _matchingMeasurementRows(executor, panelKey, sessionId, {
      sampleId,
    });
    for (final row in rows) {
      final rowId = row['id']?.toString();
      if (rowId == null || rowId.isEmpty) continue;
      final sampleColumn = _text(row['sampleId']);
      final matches =
          sampleColumn == sampleId ||
          rowId == sampleId ||
          rowId.endsWith(':$sampleId') ||
          rowId.contains(':$sampleId:');
      if (!matches) continue;
      await executor.update(
        panelKey,
        {
          'sampleNumber': path.sampleNumber,
          if (columns.contains('samplingPathJson'))
            'samplingPathJson': path.toJsonString(),
          if (columns.contains('updatedAt')) 'updatedAt': now,
          if (columns.contains('syncStatus')) ..._dirtyValues(),
        },
        where: 'id = ? AND sessionId = ?',
        whereArgs: [rowId, sessionId],
      );
    }
  }

  Future<int> _serialHighWatermark(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
  ) async {
    final rows = await executor.query(
      statesTable,
      columns: ['serialHighWatermark'],
      where: 'sessionId = ? AND panelKey = ?',
      whereArgs: [sessionId, panelKey],
      limit: 1,
    );
    return rows.isEmpty
        ? 0
        : (rows.single['serialHighWatermark'] as num?)?.toInt() ?? 0;
  }

  Future<List<String>> _removePooledDefaultBeforeComparison(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
    String? parentId, {
    required bool discardPooledData,
    required SamplingScopeLevel targetLevel,
  }) async {
    final config = _config(panelKey);
    final existingComparison = await executor.query(
      nodesTable,
      columns: ['id'],
      where:
          'sessionId = ? AND panelKey = ? AND parentId = ? AND level = ? AND sampleId IS NULL AND IFNULL(isTerminal, 0) = 0',
      whereArgs: [sessionId, panelKey, parentId ?? '', targetLevel.name],
      limit: 1,
    );
    if (existingComparison.isNotEmpty) return const [];
    final allRows = await executor.query(
      nodesTable,
      where: 'sessionId = ? AND panelKey = ?',
      whereArgs: [sessionId, panelKey],
    );
    final allNodes = allRows.map(_nodeFromRow).toList(growable: false);
    final targetOrder = targetLevel == SamplingScopeLevel.sample
        ? config.levels.length
        : config.levels.indexOf(targetLevel);
    final pooledRoots = allNodes
        .where((node) {
          if (node.parentId != parentId) return false;
          if (node.sampleId != null) return true;
          final order = config.levels.indexOf(node.level);
          return order > targetOrder;
        })
        .toList(growable: false);
    if (pooledRoots.isEmpty) return const [];
    final pooledNodes = <SamplingNode>[];
    for (final root in pooledRoots) {
      pooledNodes.addAll(await _descendantNodes(executor, root));
    }
    final uniqueNodes = {
      for (final node in pooledNodes) node.id: node,
    }.values.toList(growable: false);
    final ids = uniqueNodes
        .map((node) => node.sampleId)
        .whereType<String>()
        .toSet();
    final measurements = await _matchingMeasurementRows(
      executor,
      panelKey,
      sessionId,
      ids,
    );
    final photoTargets = await _photoTargetsForSamples(
      executor,
      panelKey,
      sessionId,
      ids,
      measurements,
    );
    final hasStoredData =
        measurements.isNotEmpty ||
        photoTargets.observationIds.isNotEmpty ||
        photoTargets.photoCount > 0;
    if (hasStoredData && !discardPooledData) {
      throw StateError(
        'The measured Pooled sample must be explicitly reset before comparison.',
      );
    }
    var localPhotoPaths = const <String>[];
    if (ids.isNotEmpty) {
      localPhotoPaths = await _photos.deleteForPanelRowsWithExecutor(
        executor,
        sessionId: sessionId,
        panelName: panelKey,
        panelRowIds: photoTargets.panelRowIds,
        observationIds: photoTargets.observationIds,
      );
      await _panelSamples.deleteRowsBySessionIdForSampleIdsWithExecutor(
        executor,
        panelKey,
        sessionId,
        ids,
      );
    }
    final nodeIds = uniqueNodes.map((node) => node.id).toList();
    await SyncTombstoneRepository.queueDeletesWithExecutor(
      executor,
      nodesTable,
      nodeIds,
    );
    await executor.delete(
      nodesTable,
      where: 'id IN (${_placeholders(nodeIds.length)})',
      whereArgs: nodeIds,
    );
    // Its reservation stays forever, ensuring that the serial is not reused.
    return localPhotoPaths;
  }

  Future<void> _validateScopeLocation(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
    PanelSamplingConfig config,
    String? parentId,
    SamplingScopeLevel level,
  ) async {
    if (!config.levels.contains(level)) {
      throw ArgumentError('Panel $panelKey does not allow a $level scope.');
    }
    if (config.pairedLevels != null &&
        config.pairedLevels!.contains(level) &&
        level != config.pairedLevels!.first) {
      throw ArgumentError(
        'Paired scopes must be added together at ${config.pairedLevels!.first}.',
      );
    }
    final levelOrder = config.levels.indexOf(level);
    if (parentId == null) {
      final rootRows = await executor.query(
        nodesTable,
        columns: ['level'],
        where:
            'sessionId = ? AND panelKey = ? AND parentId = ? AND sampleId IS NULL AND IFNULL(isTerminal, 0) = 0',
        whereArgs: [sessionId, panelKey, ''],
      );
      final hasEarlierRoot = rootRows.any((row) {
        final order = config.levels.indexWhere(
          (candidate) => candidate.name == row['level'],
        );
        return order >= 0 && order < levelOrder;
      });
      if (hasEarlierRoot) {
        throw ArgumentError(
          'Choose the nearest selected ancestor as the parent.',
        );
      }
      return;
    }
    final parentRows = await executor.query(
      nodesTable,
      where: 'id = ?',
      whereArgs: [parentId],
      limit: 1,
    );
    if (parentRows.isEmpty) {
      throw ArgumentError('The parent scope does not exist.');
    }
    final parent = _nodeFromRow(parentRows.single);
    if (parent.sessionId != sessionId ||
        parent.panelKey != panelKey ||
        parent.sampleId != null) {
      throw ArgumentError('The parent scope belongs to another sampling tree.');
    }
    final parentOrder = config.levels.indexOf(parent.level);
    if (parentOrder < 0 || parentOrder >= levelOrder) {
      throw ArgumentError(
        'A scope may only be nested under an earlier configured scope.',
      );
    }
    if (await _hasIntermediateSelectedScope(
      executor,
      sessionId,
      panelKey,
      parentId,
      parentOrder,
      levelOrder,
      config,
    )) {
      throw ArgumentError(
        'Choose the nearest selected ancestor as the parent.',
      );
    }
  }

  Future<void> _validateTerminalParentAsync(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
    PanelSamplingConfig config,
    String? parentId,
  ) async {
    final terminalOrder = config.terminalLevel == SamplingScopeLevel.sample
        ? config.levels.length
        : config.levels.indexOf(config.terminalLevel);
    if (parentId == null) {
      if (terminalOrder > 0) {
        final rootRows = await executor.query(
          nodesTable,
          columns: ['level'],
          where:
              'sessionId = ? AND panelKey = ? AND parentId = ? AND sampleId IS NULL AND IFNULL(isTerminal, 0) = 0',
          whereArgs: [sessionId, panelKey, ''],
        );
        final hasEarlierRoot = rootRows.any((row) {
          final order = config.levels.indexWhere(
            (candidate) => candidate.name == row['level'],
          );
          return order >= 0 && order < terminalOrder;
        });
        if (hasEarlierRoot) {
          throw ArgumentError(
            'Choose the nearest selected ancestor as the parent.',
          );
        }
      }
      return;
    }
    final rows = await executor.query(
      nodesTable,
      where: 'id = ?',
      whereArgs: [parentId],
      limit: 1,
    );
    if (rows.isEmpty) throw ArgumentError('The parent scope does not exist.');
    final parent = _nodeFromRow(rows.single);
    if (parent.sessionId != sessionId ||
        parent.panelKey != panelKey ||
        parent.sampleId != null) {
      throw ArgumentError('The parent scope belongs to another sampling tree.');
    }
    if (!config.levels.contains(parent.level)) {
      throw ArgumentError('Invalid terminal parent scope.');
    }
    final parentOrder = config.levels.indexOf(parent.level);
    if (await _hasIntermediateSelectedScope(
      executor,
      sessionId,
      panelKey,
      parentId,
      parentOrder,
      terminalOrder,
      config,
    )) {
      throw ArgumentError(
        'Choose the nearest selected ancestor as the parent.',
      );
    }
  }

  Future<bool> _hasIntermediateSelectedScope(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
    String parentId,
    int parentOrder,
    int targetOrder,
    PanelSamplingConfig config,
  ) async {
    final root = await _nodeById(executor, parentId);
    final descendants = await _descendantNodes(executor, root);
    return descendants.skip(1).any((node) {
      if (node.sampleId != null) return false;
      final order = config.levels.indexOf(node.level);
      return order > parentOrder && order < targetOrder;
    });
  }

  SamplingScopeLevel _effectiveScopeLevel(
    PanelSamplingConfig config,
    SamplingScopeLevel level,
  ) {
    if (level == config.terminalLevel && level == SamplingScopeLevel.sample) {
      throw ArgumentError('Use addTerminalSample for panel-native samples.');
    }
    if (config.pairedLevels?.contains(level) ?? false) {
      return config.pairedLevels!.first;
    }
    return level;
  }

  Map<String, String> _validatedIdentity(
    PanelSamplingConfig config,
    SamplingScopeLevel level,
    Map<String, String> identity,
  ) {
    final clean = <String, String>{};
    for (final entry in identity.entries) {
      final key = entry.key.trim().toLowerCase();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) continue;
      clean[key] = value;
    }
    final pair = config.pairedLevels;
    if (pair != null && pair.contains(level)) {
      for (final pairedLevel in pair) {
        final value = clean[pairedLevel.name];
        if (value == null || value.trim().isEmpty) {
          throw ArgumentError(
            'Both Setter and Hatcher identities are required.',
          );
        }
      }
    } else if ((clean['code'] ?? clean[level.name]) == null) {
      throw ArgumentError(
        'A scope identity needs a code or ${level.name} value.',
      );
    }
    final allowed = <String>{
      'code',
      'name',
      if (level == SamplingScopeLevel.house) 'id',
      'house',
      'setter',
      'hatcher',
      'trolley',
      'tray',
    };
    if (clean.keys.any((key) => !allowed.contains(key))) {
      throw ArgumentError('Scope identity contains an unsupported field.');
    }
    if (pair != null && pair.contains(level)) {
      return Map.unmodifiable({
        for (final pairedLevel in pair)
          pairedLevel.name: clean[pairedLevel.name]!,
        if (clean['name'] != null) 'name': clean['name']!,
      });
    }
    final value = clean['code'] ?? clean[level.name];
    if (value == null) {
      throw ArgumentError(
        'A scope identity needs a code or ${level.name} value.',
      );
    }
    final unexpectedScopeFields = const {
      'house',
      'setter',
      'hatcher',
      'trolley',
      'tray',
    }.where((key) => key != level.name && clean.containsKey(key));
    if (unexpectedScopeFields.isNotEmpty) {
      throw ArgumentError('Identity fields do not match the $level scope.');
    }
    return Map.unmodifiable({
      'code': value,
      if (level == SamplingScopeLevel.house && clean['id'] != null)
        'id': clean['id']!,
      if (clean['name'] != null) 'name': clean['name']!,
    });
  }

  SamplingScopePath _validationPath(
    SamplingScopePath path,
    PanelSamplingConfig config,
  ) => SamplingScopePath(
    house:
        path.unknownLevels.contains(SamplingScopeLevel.house) ||
            !config.levels.contains(SamplingScopeLevel.house)
        ? null
        : path.house,
    setter:
        path.unknownLevels.contains(SamplingScopeLevel.setter) ||
            !config.levels.contains(SamplingScopeLevel.setter)
        ? null
        : path.setter,
    hatcher:
        path.unknownLevels.contains(SamplingScopeLevel.hatcher) ||
            !config.levels.contains(SamplingScopeLevel.hatcher)
        ? null
        : path.hatcher,
    trolley:
        path.unknownLevels.contains(SamplingScopeLevel.trolley) ||
            !config.levels.contains(SamplingScopeLevel.trolley)
        ? null
        : path.trolley,
    tray: !config.levels.contains(SamplingScopeLevel.tray) ? null : path.tray,
    sampleId: path.sampleId,
    sampleNumber: path.sampleNumber,
    unknownLevels: const {},
  );

  String _identityKey(SamplingScopeLevel level, Map<String, String> identity) {
    if ((identity['setter']?.isNotEmpty ?? false) &&
        (identity['hatcher']?.isNotEmpty ?? false)) {
      return canonicalScopeIdentity({
        'setter': identity['setter'] ?? '',
        'hatcher': identity['hatcher'] ?? '',
      }, level);
    }
    final raw = identity['code'] ?? identity[level.name] ?? '';
    return canonicalScopeIdentity({'code': raw}, level);
  }

  Future<bool> _hasSamplesBelow(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
    String? parentId,
  ) async {
    final sampleRows = await executor.query(
      nodesTable,
      columns: ['id'],
      where: 'sessionId = ? AND panelKey = ? AND sampleId IS NOT NULL',
      whereArgs: [sessionId, panelKey],
    );
    if (parentId == null) return sampleRows.isNotEmpty;
    final nodeRows = await executor.query(
      nodesTable,
      where: 'sessionId = ? AND panelKey = ?',
      whereArgs: [sessionId, panelKey],
    );
    final children = <String, List<String>>{};
    for (final row in nodeRows) {
      final node = _nodeFromRow(row);
      final parent = node.parentId;
      if (parent != null) (children[parent] ??= <String>[]).add(node.id);
    }
    final descendants = <String>{parentId};
    final queue = <String>[parentId];
    while (queue.isNotEmpty) {
      final parent = queue.removeAt(0);
      for (final child in children[parent] ?? const <String>[]) {
        if (descendants.add(child)) queue.add(child);
      }
    }
    return sampleRows.any((row) => descendants.contains(row['id']));
  }

  PanelSamplingConfig _config(String panelKey) =>
      PanelSampleSchema.samplingConfigFor(panelKey);

  Future<void> _requireSession(
    DatabaseExecutor executor,
    String sessionId,
  ) async {
    final rows = await executor.query(
      'audit_sessions',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Audit session "$sessionId" does not exist.');
    }
  }

  Future<SamplingNode> _nodeById(
    DatabaseExecutor executor,
    String nodeId,
  ) async {
    final rows = await executor.query(
      nodesTable,
      where: 'id = ?',
      whereArgs: [nodeId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Sampling node "$nodeId" does not exist.');
    }
    return _nodeFromRow(rows.single);
  }

  Future<List<SamplingNode>> _descendantNodes(
    DatabaseExecutor executor,
    SamplingNode root,
  ) async {
    final all = await executor.query(
      nodesTable,
      where: 'sessionId = ? AND panelKey = ?',
      whereArgs: [root.sessionId, root.panelKey],
    );
    final nodes = all.map(_nodeFromRow).toList(growable: false);
    final result = <SamplingNode>[];
    final queue = <String>[root.id];
    final visited = <String>{};
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      if (!visited.add(id)) throw StateError('Sampling tree contains a cycle.');
      final node = nodes.where((candidate) => candidate.id == id).firstOrNull;
      if (node == null) continue;
      result.add(node);
      queue.addAll(
        nodes
            .where((candidate) => candidate.parentId == id)
            .map((candidate) => candidate.id),
      );
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _matchingMeasurementRows(
    DatabaseExecutor executor,
    String panelKey,
    String sessionId,
    Set<String> sampleIds,
  ) async {
    if (sampleIds.isEmpty) return const [];
    final columns = await _tableColumns(executor, panelKey);
    final rows = await executor.query(
      panelKey,
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );
    return rows
        .where((row) {
          final sampleId = columns.contains('sampleId')
              ? row['sampleId']?.toString()
              : null;
          final id = row['id']?.toString() ?? '';
          return (sampleId != null && sampleIds.contains(sampleId)) ||
              sampleIds.any(
                (sample) =>
                    id == sample ||
                    id.endsWith(':$sample') ||
                    id.contains(':$sample:'),
              );
        })
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Future<_SamplingPhotoTargets> _photoTargetsForSamples(
    DatabaseExecutor executor,
    String panelKey,
    String sessionId,
    Set<String> sampleIds,
    List<Map<String, Object?>> measurementRows,
  ) async {
    final panelRowIds = measurementRows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final observationIds = <String>{};
    final observationColumns = await _tableColumns(
      executor,
      'chick_quality_observation',
    );
    if (panelKey == 'chick_quality' &&
        observationColumns.isNotEmpty &&
        (await _tableColumns(executor, panelKey)).contains('sourceRefId')) {
      final helpers = await executor.query(
        panelKey,
        columns: ['id', 'sourceRefId'],
        where: 'sessionId = ? AND sourceRefId IS NOT NULL',
        whereArgs: [sessionId],
      );
      for (final helper in helpers) {
        final sourceRef = helper['sourceRefId']?.toString() ?? '';
        if (!sampleIds.any(
          (sampleId) => sourceRef.startsWith('legacy-domain:$sampleId:'),
        )) {
          continue;
        }
        final id = helper['id']?.toString();
        if (id != null && id.isNotEmpty) panelRowIds.add(id);
      }

      final observationParents = <String>{...sampleIds, ...panelRowIds};
      if (observationParents.isNotEmpty &&
          observationColumns.contains('sampleId') &&
          observationColumns.contains('id')) {
        final parentIds = observationParents.toList(growable: false);
        final rows = await executor.query(
          'chick_quality_observation',
          columns: ['id'],
          where:
              "sampleId IN (${_placeholders(parentIds.length)}) "
              "AND domain <> 'chicks.weights'",
          whereArgs: parentIds,
        );
        observationIds.addAll(
          rows.map((row) => row['id'].toString()).where((id) => id.isNotEmpty),
        );
      }
    }
    final photoSelector = <String>[];
    final photoArgs = <Object?>[sessionId, panelKey];
    if (panelRowIds.isNotEmpty) {
      photoSelector.add('panelRowId IN (${_placeholders(panelRowIds.length)})');
      photoArgs.addAll(panelRowIds);
    }
    if (observationIds.isNotEmpty) {
      photoSelector.add(
        'observationId IN (${_placeholders(observationIds.length)})',
      );
      photoArgs.addAll(observationIds);
    }
    final photoCount = photoSelector.isEmpty
        ? 0
        : Sqflite.firstIntValue(
                await executor.rawQuery(
                  'SELECT COUNT(*) FROM photos WHERE sessionId = ? '
                  'AND panelName = ? AND (${photoSelector.join(' OR ')})',
                  photoArgs,
                ),
              ) ??
              0;
    return _SamplingPhotoTargets(
      panelRowIds: panelRowIds,
      observationIds: observationIds,
      photoCount: photoCount,
    );
  }

  Future<List<Map<String, Object?>>> _legacyRows(
    DatabaseExecutor executor,
    String panelKey,
    String sessionId,
  ) async {
    return (await executor.query(
      panelKey,
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    )).map((row) => Map<String, Object?>.from(row)).toList(growable: false);
  }

  Future<void> _backfillLegacyRows(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
    List<Map<String, Object?>> rows,
  ) async {
    final config = _config(panelKey);
    final branchByPath = <String, String>{};
    final sampleById = <String, SamplingNode>{};
    for (final row in rows) {
      final pathJson = _text(row['samplingPathJson']);
      SamplingScopePath? oldPath;
      if (pathJson != null) {
        try {
          oldPath = SamplingScopePath.decode(pathJson);
        } on Object {
          oldPath = null;
        }
      }
      var parentId = <String>[''].first;
      final unknownLevels = <SamplingScopeLevel>{};
      for (final level in const [
        SamplingScopeLevel.house,
        SamplingScopeLevel.setter,
        SamplingScopeLevel.hatcher,
        SamplingScopeLevel.trolley,
        SamplingScopeLevel.tray,
      ]) {
        if (!config.levels.contains(level) &&
            _text(oldPath?.identityFor(level) ?? row[level.name]) != null) {
          unknownLevels.add(level);
        }
      }
      for (final level in config.levels) {
        if (level == config.terminalLevel) continue;
        final raw = oldPath?.identityFor(level) ?? _text(row[level.name]);
        if (raw == null || raw.isEmpty) continue;
        final paired = config.pairedLevels?.contains(level) ?? false;
        if (paired && level != config.pairedLevels!.first) continue;
        final levelIdentity = <String, String>{'code': raw};
        if (paired) {
          final setter = oldPath?.setter ?? _text(row['setter']);
          final hatcher = oldPath?.hatcher ?? _text(row['hatcher']);
          if (setter == null || hatcher == null) continue;
          levelIdentity
            ..['setter'] = setter
            ..['hatcher'] = hatcher
            ..['_unknownLevels'] = 'setter,hatcher';
        } else {
          levelIdentity['_unknownLevels'] = level.name;
        }
        unknownLevels.add(level);
        final key =
            '$parentId|${level.name}|${_identityKey(level, levelIdentity)}';
        var nodeId = branchByPath[key];
        if (nodeId == null) {
          final now = _now();
          final node = SamplingNode(
            id: _legacyScopeNodeId(
              sessionId,
              panelKey,
              parentId,
              level,
              _identityKey(level, levelIdentity),
            ),
            sessionId: sessionId,
            panelKey: panelKey,
            parentId: parentId.isEmpty ? null : parentId,
            level: level,
            identityKey: _identityKey(level, levelIdentity),
            identity: levelIdentity,
            createdAt: DateTime.parse(now),
            updatedAt: DateTime.parse(now),
          );
          await executor.insert(nodesTable, {
            ...node.toMap(),
            'parentId': parentId,
            'isTerminal': 0,
            ..._dirtyValues(),
          });
          nodeId = node.id;
          branchByPath[key] = nodeId;
        }
        parentId = nodeId;
      }
      final rowId = row['id']?.toString();
      if (rowId == null || rowId.isEmpty) continue;
      final sampleId = _text(row['sampleId']) ?? rowId;
      if (sampleById.containsKey(sampleId)) continue;
      final hinted = (row['sampleNumber'] as num?)?.toInt();
      final number = hinted != null && hinted > 0
          ? hinted
          : await _allocateSerial(executor, sessionId, panelKey);
      final now = _now();
      final terminalLevel = config.terminalLevel;
      var terminalIdentity = unknownLevels.isEmpty
          ? const <String, String>{}
          : <String, String>{
              '_unknownLevels': unknownLevels
                  .map((level) => level.name)
                  .join(','),
            };
      if (terminalLevel == SamplingScopeLevel.tray) {
        final tray = oldPath?.tray ?? _text(row['tray']);
        unknownLevels.add(SamplingScopeLevel.tray);
        final terminalUnknownLevels = {...unknownLevels};
        terminalIdentity = {
          if (terminalUnknownLevels.isNotEmpty)
            '_unknownLevels': terminalUnknownLevels
                .map((level) => level.name)
                .join(','),
          'code': tray ?? 'legacy/unknown',
        };
      }
      final node = SamplingNode(
        id: _legacyTerminalNodeId(sessionId, panelKey, sampleId),
        sessionId: sessionId,
        panelKey: panelKey,
        parentId: parentId.isEmpty ? null : parentId,
        level: terminalLevel,
        identityKey: terminalLevel == SamplingScopeLevel.tray
            ? _identityKey(terminalLevel, terminalIdentity)
            : '',
        identity: terminalIdentity,
        sampleId: sampleId,
        sampleNumber: number,
        createdAt: DateTime.parse(now),
        updatedAt: DateTime.parse(now),
      );
      await executor.insert(nodesTable, {
        ...node.toMap(),
        'parentId': parentId,
        'isTerminal': 1,
        ..._dirtyValues(),
      });
      await _updateReservation(
        executor,
        sessionId,
        panelKey,
        sampleId,
        number,
        now,
      );
      sampleById[sampleId] = node;
      final path = SamplingScopePath(
        house: _text(oldPath?.house ?? row['house']),
        setter: _text(oldPath?.setter ?? row['setter']),
        hatcher: _text(oldPath?.hatcher ?? row['hatcher']),
        trolley: _text(oldPath?.trolley ?? row['trolley']),
        tray: terminalLevel == SamplingScopeLevel.tray
            ? _text(oldPath?.tray ?? row['tray']) ?? 'legacy/unknown'
            : null,
        sampleId: sampleId,
        sampleNumber: number,
        unknownLevels: unknownLevels,
      );
      final columns = await _tableColumns(executor, panelKey);
      await executor.update(
        panelKey,
        {
          if (columns.contains('sampleId')) 'sampleId': sampleId,
          if (columns.contains('sampleNumber')) 'sampleNumber': number,
          if (columns.contains('samplingPathJson'))
            'samplingPathJson': path.toJsonString(),
          if (columns.contains('syncStatus')) ..._dirtyValues(),
        },
        where: 'id = ?',
        whereArgs: [rowId],
      );
    }
    final max = await _maxReservedSerial(executor, sessionId, panelKey);
    await executor.update(
      statesTable,
      {'serialHighWatermark': max, 'updatedAt': _now(), ..._dirtyValues()},
      where: 'sessionId = ? AND panelKey = ?',
      whereArgs: [sessionId, panelKey],
    );
  }

  Future<void> _touchState(
    DatabaseExecutor executor,
    String sessionId,
    String panelKey,
  ) async {
    await executor.update(
      statesTable,
      {'updatedAt': _now(), ..._dirtyValues()},
      where: 'sessionId = ? AND panelKey = ?',
      whereArgs: [sessionId, panelKey],
    );
  }

  Future<Set<String>> _tableColumns(
    DatabaseExecutor executor,
    String table,
  ) async {
    final rows = await executor.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'].toString()).toSet();
  }

  SamplingNode _nodeFromRow(Map<String, Object?> row) {
    final mapped = Map<String, Object?>.from(row);
    if (mapped['parentId'] == '') mapped['parentId'] = null;
    return SamplingNode.fromMap(mapped);
  }

  PanelSamplingState _withActive(PanelSamplingState state, String? active) =>
      PanelSamplingState(
        sessionId: state.sessionId,
        panelKey: state.panelKey,
        nodes: state.nodes,
        serialHighWatermark: state.serialHighWatermark,
        activeSampleId: active ?? state.activeSampleId,
      );

  String _scopeLabel(SamplingNode node) =>
      node.identity['name'] ??
      node.identity['code'] ??
      node.identityKey ??
      node.level.name;

  String _stateId(String sessionId, String panelKey) => '$sessionId::$panelKey';

  String _reservationId(String sessionId, String panelKey, String sampleId) =>
      _uuid.v5(
        Namespace.url.value,
        'panel-sample-reservation:$sessionId:$panelKey:$sampleId',
      );

  String _legacyScopeNodeId(
    String sessionId,
    String panelKey,
    String parentId,
    SamplingScopeLevel level,
    String identityKey,
  ) => _uuid.v5(
    Namespace.url.value,
    'legacy-scope:$sessionId:$panelKey:$parentId:${level.name}:$identityKey',
  );

  String _legacyTerminalNodeId(
    String sessionId,
    String panelKey,
    String sampleId,
  ) => _uuid.v5(
    Namespace.url.value,
    'legacy-terminal:$sessionId:$panelKey:$sampleId',
  );

  String _now() => DateTime.now().toUtc().toIso8601String();

  Map<String, Object?> _dirtyValues() => {
    'syncStatus': 'pending',
    'dirtyAt': _now(),
    'lastSyncedAt': null,
    'syncError': null,
  };

  void _requireSyncTable(String tableName) {
    if (!_syncTables.contains(tableName)) {
      throw ArgumentError.value(tableName, 'tableName');
    }
  }

  String? _text(Object? value) {
    final valueString = value?.toString().trim();
    return valueString == null || valueString.isEmpty ? null : valueString;
  }

  static String _placeholders(int count) => List.filled(count, '?').join(', ');
}

class _SamplingPhotoTargets {
  const _SamplingPhotoTargets({
    required this.panelRowIds,
    required this.observationIds,
    required this.photoCount,
  });

  final Set<String> panelRowIds;
  final Set<String> observationIds;
  final int photoCount;
}
