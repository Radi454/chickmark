import 'package:sqflite/sqflite.dart';

import '../../../data/models/audit_model.dart';
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
  });

  final List<AuditModel> stationAudits;
  final List<StationSampleModel> stationSamples;
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
  return StationReconstruction(
    stationAudits: stationAudits,
    stationSamples: stationSamples,
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
    'id': stationKey == 'egg' && records.first.table == 'egg_quality'
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
    legacyAuditId: stationKey == 'egg' ? persistedId : null,
    createdAt: _parseDate(row['createdAt']) ?? DateTime.now(),
    updatedAt: _parseDate(row['updatedAt']) ?? DateTime.now(),
  );
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
