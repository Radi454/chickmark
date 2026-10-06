import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/audit_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/repositories/panel_sample_repository.dart';
import '../models/egg_grading.dart';
import '../screens/audit_context_screen.dart';
import 'panel_row_to_draft.dart';

/// Panel-row -> station-draft reconstruction, the read half of station
/// reopen, for the stations whose station key/panel tables were passed in.
///
/// Moved verbatim out of `_StationFrameState` in `audit_session_screen.dart`
/// so the reconstruction can be tested directly against raw panel rows
/// without a widget tree. Bodies, key names and statement order are
/// unchanged from the original private methods — only the enclosing scope
/// moved, and `widget.stationKey` / `widget.sessionId` / `widget.context`
/// became explicit parameters.
class StationReconstruction {
  const StationReconstruction({
    required this.stationAudits,
    required this.stationSamples,
    this.samplingDraftsByPanel = const {},
  });

  final List<AuditModel> stationAudits;
  final List<StationSampleModel> stationSamples;
  final Map<String, Map<String, AuditModel>> samplingDraftsByPanel;
}

const _pasgarPhotoFieldKeys = {
  'pasgarReflexesPhoto',
  'pasgarBeakPhoto',
  'pasgarNavelPhoto',
  'pasgarBellyPhoto',
  'pasgarLegPhoto',
  'pasgarFeatherDevPhoto',
};

/// Restores sanitized photo paths into local panel rows before reconstruction.
/// The photo table is authoritative for these references because inline data
/// URIs are intentionally removed from cloud panel payloads.
Map<String, List<Map<String, dynamic>>> hydratePanelPhotoRows(
  Map<String, List<Map<String, dynamic>>> rowsByPanel,
  Iterable<PhotoModel> photos,
) {
  final rows = {
    for (final entry in rowsByPanel.entries)
      entry.key: entry.value
          .map((row) => Map<String, dynamic>.of(row))
          .toList(),
  };
  final sorted = photos.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  for (final entry in rows.entries) {
    for (final row in entry.value) {
      final rowId = row['id']?.toString();
      if (rowId == null) continue;
      final associated = sorted
          .where(
            (photo) =>
                photo.panelName == entry.key && photo.panelRowId == rowId,
          )
          .toList(growable: false);
      for (final photo in associated) {
        final fieldKey =
            entry.key == 'setter_optimizing' &&
                photo.fieldKey == 'turning_angle'
            ? 'machineScreenPhoto'
            : photo.fieldKey;
        final directKey = _matchingPanelPhotoColumn(row, fieldKey);
        if (directKey != null) {
          if (row[directKey] == null || row[directKey].toString().isEmpty) {
            row[directKey] = photo.filePath;
          }
          continue;
        }
        _hydratePhotoCollection(row, entry.key, photo);
      }
      if (associated.any((photo) => photo.fieldKey == 'pm_photo')) {
        _hydrateMultiPhotoList(row, associated);
      }
    }
  }
  return rows;
}

String? _matchingPanelPhotoColumn(Map<String, dynamic> row, String fieldKey) {
  final target = _normalizePhotoField(fieldKey);
  for (final key in row.keys) {
    if (_normalizePhotoField(key) == target &&
        _normalizePhotoField(key).contains('photo')) {
      return key;
    }
  }
  return null;
}

String _normalizePhotoField(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

void _hydratePhotoCollection(
  Map<String, dynamic> row,
  String panelName,
  PhotoModel photo,
) {
  final definition = switch ((panelName, photo.fieldKey)) {
    ('setter_optimizing', final key) when key.startsWith('setter_est_') => (
      column: 'estPhotosJson',
      entry: key.substring('setter_est_'.length),
    ),
    ('hatcher_optimizing', final key) when key.startsWith('hatcher_cvt_') => (
      column: 'cvtPhotosJson',
      entry: key.substring('hatcher_cvt_'.length),
    ),
    ('chick_quality', 'cvt') => (column: 'cvtPhotosJson', entry: 'cvt'),
    _ => null,
  };
  if (definition == null || !row.containsKey(definition.column)) return;

  final decoded = _decodePhotoMap(row[definition.column]);
  if (decoded[definition.entry] == null ||
      decoded[definition.entry].toString().isEmpty) {
    decoded[definition.entry] = photo.filePath;
    row[definition.column] = jsonEncode(decoded);
  }
}

Map<String, dynamic> _decodePhotoMap(Object? value) {
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  if (value is! String || value.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map) return {};
    return decoded.map((key, value) => MapEntry('$key', value));
  } catch (_) {
    return {};
  }
}

void _hydrateMultiPhotoList(
  Map<String, dynamic> row,
  List<PhotoModel> associated,
) {
  if (!row.containsKey('pmPhotosJson')) return;
  final existing = <String>[];
  final value = row['pmPhotosJson'];
  try {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is List) {
      existing.addAll(
        decoded.whereType<String>().where((path) => path.isNotEmpty),
      );
    }
  } catch (_) {
    // Replace malformed/fully-sanitized payload with the authoritative photo
    // metadata list below.
  }
  for (final photo in associated.reversed) {
    if (photo.fieldKey == 'pm_photo' && !existing.contains(photo.filePath)) {
      existing.add(photo.filePath);
    }
  }
  row['pmPhotosJson'] = jsonEncode(existing);
}

/// Hydrates photo-backed fields that intentionally have no panel-table
/// columns. Photos are joined by the persisted station sample id, not the
/// regenerated draft id, so reopening cannot orphan their thumbnails.
StationReconstruction overlayPanelPhotos(
  StationReconstruction reconstruction,
  Iterable<PhotoModel> photos,
) {
  if (reconstruction.stationAudits.isEmpty ||
      reconstruction.stationSamples.isEmpty) {
    return reconstruction;
  }
  final newestPathByRowAndField = <String, String>{};
  final sorted = photos.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  for (final photo in sorted) {
    if (!_pasgarPhotoFieldKeys.contains(photo.fieldKey)) continue;
    newestPathByRowAndField.putIfAbsent(
      '${photo.panelRowId}\u0000${photo.fieldKey}',
      () => photo.filePath,
    );
  }

  final audits = <AuditModel>[];
  for (var i = 0; i < reconstruction.stationAudits.length; i++) {
    final audit = reconstruction.stationAudits[i];
    if (i >= reconstruction.stationSamples.length) {
      audits.add(audit);
      continue;
    }
    final rowId = reconstruction.stationSamples[i].id;
    final map = audit.toMap();
    for (final fieldKey in _pasgarPhotoFieldKeys) {
      final helperId = const Uuid().v5(
        Namespace.url.value,
        'legacy-domain:$rowId:chicks.pasgar',
      );
      final path =
          newestPathByRowAndField['$rowId\u0000$fieldKey'] ??
          newestPathByRowAndField['$helperId\u0000$fieldKey'];
      if (path != null) map[fieldKey] = path;
    }
    audits.add(AuditModel.fromMap(map));
  }
  return StationReconstruction(
    stationAudits: audits,
    stationSamples: reconstruction.stationSamples,
    samplingDraftsByPanel: reconstruction.samplingDraftsByPanel,
  );
}

StationReconstruction reconstructStation({
  required String stationKey,
  required String sessionId,
  required AuditContextData context,
  required Map<String, List<Map<String, dynamic>>> rowsByPanel,
}) {
  final stationAudits = _auditDraftsFromPanelRows(
    stationKey,
    sessionId,
    context,
    rowsByPanel,
  )..sort((a, b) => a.hatchNumber.compareTo(b.hatchNumber));
  final stationSamples = _stationSamplesFromPanelRows(
    stationKey,
    sessionId,
    rowsByPanel,
  );
  final samplingDraftsByPanel = <String, Map<String, AuditModel>>{};
  for (final entry in rowsByPanel.entries) {
    final panelDrafts = samplingDraftsByPanel.putIfAbsent(
      entry.key,
      () => <String, AuditModel>{},
    );
    for (final rowEntry in entry.value.asMap().entries) {
      final row = rowEntry.value;
      final sampleId =
          panelRowAsText(row['sampleId']) ?? panelRowAsText(row['id']);
      if (sampleId == null) continue;
      final map = _auditMapFromPanelRows(
        stationKey,
        sessionId,
        context,
        rowEntry.key,
        [(table: entry.key, row: row)],
      );
      map['id'] = row['id']?.toString() ?? sampleId;
      panelDrafts[sampleId] = AuditModel.fromMap(map);
    }
  }
  return StationReconstruction(
    stationAudits: stationAudits,
    stationSamples: stationSamples,
    samplingDraftsByPanel: samplingDraftsByPanel,
  );
}

/// Reopens the Egg station's saved panel rows for [sessionId] straight from
/// [db], for use where there is no widget tree (tests) or where the caller
/// already has an open database handle. Production code reaches
/// [reconstructStation] and [overlayEggGradingCounts] via
/// `_StationFrameState._loadInitialData`, which reads rows through
/// repositories instead.
Future<StationReconstruction> reopenEggStation(
  Database db,
  String sessionId, {
  AuditContextData? context,
}) async {
  final rowsByPanel = <String, List<Map<String, dynamic>>>{};
  for (final table in const ['egg_storage', 'egg_quality']) {
    final columns = await _tableColumnNames(db, table);
    final rows = await db.query(
      table,
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: PanelSampleRepository.panelOrderByForColumns(columns),
    );
    rowsByPanel[table] = rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
  final reconstruction = reconstructStation(
    stationKey: 'egg',
    sessionId: sessionId,
    context:
        context ??
        AuditContextData(
          auditType: 'Egg',
          customerId: '',
          flockId: '',
          date: '',
        ),
    rowsByPanel: rowsByPanel,
  );
  final defectRows = await db.query(
    'egg_quality_defect_counts',
    where: 'sessionId = ?',
    whereArgs: [sessionId],
  );
  final countsByEggQualityId = <String, Map<String, int>>{};
  for (final row in defectRows) {
    final eggQualityId = row['eggQualityId']?.toString();
    final code = row['defectCode']?.toString();
    final count = row['count'];
    if (eggQualityId == null || code == null || count is! int) continue;
    (countsByEggQualityId[eggQualityId] ??= <String, int>{})[code] = count;
  }
  return overlayEggGradingCounts(
    reconstruction,
    countsByEggQualityId: countsByEggQualityId,
  );
}

/// Overlays persisted grading child rows onto reconstructed Egg drafts by the
/// persisted `egg_quality.id`. The panel JSON remains the fallback when no
/// child rows for a parent have arrived yet.
StationReconstruction overlayEggGradingCounts(
  StationReconstruction reconstruction, {
  required Map<String, Map<String, int>> countsByEggQualityId,
}) {
  if (countsByEggQualityId.isEmpty) return reconstruction;

  final stationAudits = [
    for (final draft in reconstruction.stationAudits)
      _withGradingOverride(draft, countsByEggQualityId[draft.id]),
  ];
  return StationReconstruction(
    stationAudits: stationAudits,
    stationSamples: reconstruction.stationSamples,
    samplingDraftsByPanel: reconstruction.samplingDraftsByPanel,
  );
}

AuditModel _withGradingOverride(AuditModel draft, Map<String, int>? counts) {
  if (counts == null || counts.isEmpty) return draft;
  final summary = EggGradingSummary.fromCounts(
    sampleSize: draft.esGradingSampleSize ?? 0,
    rejectedCount: draft.esGradingRejectedCount ?? 0,
    counts: counts,
  );
  final map = draft.toMap()..['esGradingDefectsJson'] = summary.encodedJson;
  return AuditModel.fromMap(map);
}

Future<Set<String>> _tableColumnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'] as String).toSet();
}

List<AuditModel> _auditDraftsFromPanelRows(
  String stationKey,
  String sessionId,
  AuditContextData context,
  Map<String, List<Map<String, dynamic>>> rowsByPanel,
) {
  final eggDrafts = _eggAuditDraftsFromPanelRows(
    stationKey,
    sessionId,
    context,
    rowsByPanel,
  );
  if (eggDrafts != null) return eggDrafts;
  final chickDrafts = _chickAuditDraftsFromPanelRows(
    stationKey,
    sessionId,
    context,
    rowsByPanel,
  );
  if (chickDrafts != null) return chickDrafts;

  final grouped = <int, List<({String table, Map<String, dynamic> row})>>{};
  final groupIndexes = <String, int>{};
  for (final entry in rowsByPanel.entries) {
    for (final row in entry.value) {
      final index = stationKey == 'hatch_analysis_egg_breakouts'
          ? 0
          : groupIndexes.putIfAbsent(
              _panelRowIdentityKey(row),
              () => groupIndexes.length,
            );
      grouped
          .putIfAbsent(
            index,
            () => <({String table, Map<String, dynamic> row})>[],
          )
          .add((table: entry.key, row: row));
    }
  }
  return [
    for (final entry in grouped.entries)
      AuditModel.fromMap(
        _auditMapFromPanelRows(
          stationKey,
          sessionId,
          context,
          entry.key,
          entry.value,
        ),
      ),
  ];
}

Map<String, dynamic> _auditMapFromPanelRows(
  String stationKey,
  String sessionId,
  AuditContextData context,
  int sampleIndex,
  List<({String table, Map<String, dynamic> row})> records,
) {
  final first = records.first.row;
  final createdAt =
      first['createdAt']?.toString() ?? DateTime.now().toIso8601String();
  final updatedAt = records
      .map((record) => record.row['updatedAt']?.toString())
      .where((value) => value != null && value.isNotEmpty)
      .cast<String>()
      .fold<String>(createdAt, (latest, value) {
        return value.compareTo(latest) > 0 ? value : latest;
      });
  final mode =
      panelRowAsText(first['sampleMode']) ??
      (_rowHasHierarchy(first) ? 'comparison' : 'pool');
  final isComparison = mode == StationSampleModel.sampleModeComparison;
  final map = <String, dynamic>{
    'id':
        (stationKey == 'egg' && records.first.table == 'egg_quality') ||
            (stationKey == 'chicks' && records.first.table == 'chick_quality')
        ? first['id']?.toString() ?? '$sessionId:$stationKey:$sampleIndex'
        : '$sessionId:$stationKey:$sampleIndex',
    'auditType': context.auditType,
    'customerId': first['customerId'] ?? context.customerId,
    'flockId': first['flockId'] ?? context.flockId,
    'date': first['date'] ?? context.date,
    'status': 'completed',
    'createdBy': 'panel',
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'sessionId': sessionId,
    'sampleMode': isComparison ? 'comparison' : 'pool',
    'compareGroupKey': isComparison ? 'panel-hierarchy-$sessionId' : null,
    'hatchNumber': sampleIndex + 1,
    'notes': first['notes'],
  };

  for (final record in records) {
    mergePanelRowIntoAuditMap(map, record.table, record.row);
  }
  return map;
}

List<AuditModel>? _chickAuditDraftsFromPanelRows(
  String stationKey,
  String sessionId,
  AuditContextData context,
  Map<String, List<Map<String, dynamic>>> rowsByPanel,
) {
  if (stationKey != 'chicks') return null;
  final qualityRows = _sortedByPanelOrder(
    rowsByPanel['chick_quality'] ?? const <Map<String, dynamic>>[],
  );
  if (qualityRows.isEmpty) return null;
  return [
    for (final entry in qualityRows.asMap().entries)
      AuditModel.fromMap(
        _auditMapFromPanelRows(stationKey, sessionId, context, entry.key, [
          (table: 'chick_quality', row: entry.value),
        ]),
      ),
  ];
}

List<AuditModel>? _eggAuditDraftsFromPanelRows(
  String stationKey,
  String sessionId,
  AuditContextData context,
  Map<String, List<Map<String, dynamic>>> rowsByPanel,
) {
  if (stationKey != 'egg') return null;
  final qualityRows = _sortedByPanelOrder(
    rowsByPanel['egg_quality'] ?? const <Map<String, dynamic>>[],
  );
  if (qualityRows.isEmpty) return null;

  final pooledStorageRecords =
      (rowsByPanel['egg_storage'] ?? const <Map<String, dynamic>>[])
          .where((row) => !_rowHasHierarchy(row))
          .map((row) => (table: 'egg_storage', row: row))
          .toList();

  return [
    for (final entry in qualityRows.asMap().entries)
      AuditModel.fromMap(
        _auditMapFromPanelRows(stationKey, sessionId, context, entry.key, [
          (table: 'egg_quality', row: entry.value),
          ...pooledStorageRecords,
        ]),
      ),
  ];
}

/// Sorts panel rows the same way `PanelSampleRepository.getRowsBySessionId`
/// orders them once a table carries `sampleIndex`: index first, then
/// `createdAt`, then `id` as a final tiebreaker. Rows already arrive in this
/// order from the repository in production; this sort exists so drafts and
/// samples always agree even when a caller (like a test) hands in rows in a
/// different order.
List<Map<String, dynamic>> _sortedByPanelOrder(
  List<Map<String, dynamic>> rows,
) {
  final sorted = List<Map<String, dynamic>>.of(rows);
  sorted.sort((a, b) {
    final aIndex = panelRowAsInt(a['sampleIndex']);
    final bIndex = panelRowAsInt(b['sampleIndex']);
    if (aIndex != null && bIndex != null && aIndex != bIndex) {
      return aIndex.compareTo(bIndex);
    }
    if (aIndex != null && bIndex == null) return -1;
    if (aIndex == null && bIndex != null) return 1;
    final aCreated = a['createdAt']?.toString() ?? '';
    final bCreated = b['createdAt']?.toString() ?? '';
    final createdCompare = aCreated.compareTo(bCreated);
    if (createdCompare != 0) return createdCompare;
    final aId = a['id']?.toString() ?? '';
    final bId = b['id']?.toString() ?? '';
    return aId.compareTo(bId);
  });
  return sorted;
}

List<StationSampleModel> _stationSamplesFromPanelRows(
  String stationKey,
  String sessionId,
  Map<String, List<Map<String, dynamic>>> rowsByPanel,
) {
  if (stationKey == 'chicks') {
    return [
      for (final table in const ['chick_quality', 'chick_weights'])
        for (final entry in _sortedByPanelOrder(
          rowsByPanel[table] ?? const <Map<String, dynamic>>[],
        ).asMap().entries)
          _sampleFromPanelRow(
            stationKey,
            sessionId,
            table,
            entry.value,
            fallbackIndex: entry.key + 1,
          ),
    ];
  }
  final primaryEntry = _stationSampleSourceRows(stationKey, rowsByPanel);
  if (primaryEntry.value.isEmpty) return const [];
  final sourceRows = _sortedByPanelOrder(primaryEntry.value);
  return [
    for (final entry in sourceRows.asMap().entries)
      _sampleFromPanelRow(
        stationKey,
        sessionId,
        primaryEntry.key,
        entry.value,
        fallbackIndex: entry.key + 1,
      ),
  ];
}

MapEntry<String, List<Map<String, dynamic>>> _stationSampleSourceRows(
  String stationKey,
  Map<String, List<Map<String, dynamic>>> rowsByPanel,
) {
  if (stationKey == 'egg') {
    final qualityRows = rowsByPanel['egg_quality'];
    if (qualityRows != null && qualityRows.isNotEmpty) {
      return MapEntry('egg_quality', qualityRows);
    }
  }
  return rowsByPanel.entries.firstWhere(
    (entry) => entry.value.isNotEmpty,
    orElse: () => const MapEntry('', []),
  );
}

StationSampleModel _sampleFromPanelRow(
  String stationKey,
  String sessionId,
  String table,
  Map<String, dynamic> row, {
  required int fallbackIndex,
}) {
  final inferredScope = _scopeTypeForRow(row);
  final scopeType = panelRowAsText(row['scopeType']) ?? inferredScope;
  final sampleMode =
      panelRowAsText(row['sampleMode']) ??
      (_rowHasHierarchy(row)
          ? StationSampleModel.sampleModeComparison
          : StationSampleModel.sampleModePooled);
  final sampleIndex = panelRowAsInt(row['sampleIndex']) ?? fallbackIndex;
  final sampleLabel =
      panelRowAsText(row['sampleLabel']) ??
      _sampleLabelForRow(row) ??
      'Sample $sampleIndex';
  final isComparison = sampleMode == StationSampleModel.sampleModeComparison;
  final persistedId = row['id']?.toString();
  return StationSampleModel(
    id: persistedId ?? '$sessionId:$table:$sampleIndex',
    sampleId: panelRowAsText(row['sampleId']),
    auditSessionId: sessionId,
    stationType: stationKey,
    sectorType: _sectorTypeForTable(table),
    sampleKind: _sampleKindForScope(scopeType),
    sampleMode: sampleMode,
    comparisonType: _comparisonTypeForScope(scopeType),
    sampleIndex: sampleIndex,
    sampleLabel: sampleLabel,
    sampleType: _sampleTypeForTable(table),
    breakoutType: _breakoutTypeForTable(table),
    groupKey: isComparison ? 'panel-hierarchy-$sessionId' : null,
    groupLabel: isComparison ? 'Hierarchy comparison' : null,
    houseNo: panelRowAsText(row['house']),
    houseLabel: panelRowAsText(row['house']),
    storageDays: panelRowAsInt(row['storagePeriodDays']),
    incubationDay: panelRowAsInt(
      row['incubationAgeDays'] ?? row['candlingDay'],
    ),
    setterNo: panelRowAsText(row['setter']),
    hatcherNo: panelRowAsText(row['hatcher']),
    notes: row['notes']?.toString(),
    resultSummaryJson: table == 'chick_weights'
        ? jsonEncode({
            'auditType': 'Chicks',
            'sectorType': StationSampleModel.sectorChickWeights,
            'chickWeights': _decodedJsonList(row['weightsJson']),
            'chickAvgWeight': row['avgWeight'],
            'chickUniformityPct': row['uniformityPct'],
            'chickCvPct': row['cvPct'],
          })
        : null,
    sampleKey: panelRowAsText(row['sampleKey']),
    qualityStatus: panelRowAsText(row['qualityStatus']),
    qualityFlags: panelRowAsText(row['qualityFlags']),
    legacyAuditId:
        stationKey == 'egg' ||
            (stationKey == 'chicks' && table == 'chick_quality')
        ? persistedId
        : null,
    createdAt: _parseDate(row['createdAt']) ?? DateTime.now(),
    updatedAt: _parseDate(row['updatedAt']) ?? DateTime.now(),
  );
}

List<Object?>? _decodedJsonList(Object? value) {
  if (value is! String || value.isEmpty) return null;
  try {
    final decoded = jsonDecode(value);
    return decoded is List ? decoded : null;
  } on FormatException {
    return null;
  }
}

String _panelRowIdentityKey(Map<String, dynamic> row) {
  return [
    panelRowAsText(row['house']) ?? '',
    panelRowAsText(row['setter']) ?? '',
    panelRowAsText(row['hatcher']) ?? '',
    panelRowAsText(row['trolley']) ?? '',
    panelRowAsText(row['tray']) ?? '',
    panelRowAsText(row['position']) ?? '',
  ].join('|');
}

bool _rowHasHierarchy(Map<String, dynamic> row) {
  return panelRowAsText(row['house']) != null ||
      panelRowAsText(row['setter']) != null ||
      panelRowAsText(row['hatcher']) != null ||
      panelRowAsText(row['trolley']) != null ||
      panelRowAsText(row['tray']) != null ||
      panelRowAsText(row['position']) != null;
}

String _scopeTypeForRow(Map<String, dynamic> row) {
  if (panelRowAsText(row['tray']) != null) return 'tray';
  if (panelRowAsText(row['trolley']) != null) return 'trolley';
  if (panelRowAsText(row['setter']) != null &&
      panelRowAsText(row['hatcher']) != null) {
    return 'setter_hatcher';
  }
  if (panelRowAsText(row['setter']) != null) return 'setter';
  if (panelRowAsText(row['hatcher']) != null) return 'hatcher';
  if (panelRowAsText(row['house']) != null) return 'house';
  return 'pool';
}

String? _sampleLabelForRow(Map<String, dynamic> row) {
  final setter = panelRowAsText(row['setter']);
  final hatcher = panelRowAsText(row['hatcher']);
  if (setter != null && hatcher != null) return '$setter$hatcher';
  return panelRowAsText(row['tray']) ??
      panelRowAsText(row['trolley']) ??
      setter ??
      hatcher ??
      panelRowAsText(row['house']);
}

String _sectorTypeForTable(String table) {
  return switch (table) {
    'egg_quality' => StationSampleModel.sectorEggQuality,
    'chick_weights' => StationSampleModel.sectorChickWeights,
    'chick_quality' => StationSampleModel.sectorChickQuality,
    'fresh_egg_breakout' ||
    'candled_egg_breakout' ||
    'residue_breakout' => StationSampleModel.sectorHatchBreakout,
    'setter_optimizing' => StationSampleModel.sectorSetterOptimizing,
    'hatcher_optimizing' => StationSampleModel.sectorHatcherOptimizing,
    _ => StationSampleModel.sectorDefault,
  };
}

String _sampleKindForScope(String scopeType) {
  return switch (scopeType) {
    'house' => StationSampleModel.sampleKindHouse,
    'setter' ||
    'hatcher' ||
    'setter_hatcher' => StationSampleModel.sampleKindMachine,
    'tray' => StationSampleModel.sampleKindTray,
    'batch' => StationSampleModel.sampleKindBatch,
    _ => StationSampleModel.sampleKindPooled,
  };
}

String? _comparisonTypeForScope(String scopeType) {
  return switch (scopeType) {
    'house' => StationSampleModel.comparisonTypeHouse,
    'setter' ||
    'hatcher' ||
    'setter_hatcher' => StationSampleModel.comparisonTypeMachine,
    'tray' => StationSampleModel.comparisonTypeTray,
    'batch' => StationSampleModel.comparisonTypeBatch,
    _ => null,
  };
}

String? _sampleTypeForTable(String table) {
  return switch (table) {
    'chick_quality' ||
    'chick_weights' ||
    'fresh_egg_breakout' => StationSampleModel.sampleTypeBreakoutFresh,
    'candled_egg_breakout' => StationSampleModel.sampleTypeBreakoutCandled10d,
    'residue_breakout' => StationSampleModel.sampleTypeBreakoutResidue21d,
    _ => StationSampleModel.sampleTypeDefault,
  };
}

String? _breakoutTypeForTable(String table) {
  return switch (table) {
    'fresh_egg_breakout' => StationSampleModel.breakoutTypeFresh,
    'candled_egg_breakout' => StationSampleModel.breakoutTypeCandled10d,
    'residue_breakout' => StationSampleModel.breakoutTypeResidue21d,
    _ => null,
  };
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}
