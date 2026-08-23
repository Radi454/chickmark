import 'dart:convert';

import '../../../core/security/safe_debug_log.dart';
import '../../../core/utils/bmk_age_calculator.dart';
import '../../../data/mappers/station_sample_mapper.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/panel_sample_model.dart';
import '../../../data/models/panel_sample_schema.dart';
import '../../../data/models/sample_mode.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/repositories/benchmark_lookup.dart';
import '../../../data/repositories/panel_sample_repository.dart';
import '../logic/audit_meaningful_data.dart';
import '../logic/audit_value_parsing.dart';
import '../logic/breakout_value_builders.dart';
import '../logic/panel_value_builders.dart';
import '../models/audit_context.dart';
import '../models/egg_breakout_sample.dart';

/// One draft paired with the station sample it is being persisted as.
///
/// Was `_PanelSavePair` in `audit_provider.dart`; it is public here because
/// `AuditProvider._saveSamplesInternal` still assembles the list it hands to
/// [AuditPanelSaveCoordinator.savePanelTables].
typedef PanelSavePair = ({AuditModel draft, StationSampleModel sample});

/// Owns every write and delete the audit save path performs against the panel
/// tables (`egg_storage`, `egg_quality`, `chick_quality`, `chick_weights`, the
/// three egg-breakout tables, and the setter/hatcher optimizing tables).
///
/// This is a **move-only** extraction of the save/delete/prune cluster that
/// used to live in `AuditProvider`. Method bodies, the order in which they call
/// each other, and the order in which the two entry points issue their
/// repository calls are all preserved exactly as they were in
/// `AuditProvider._saveSamplesInternal`, because delete-then-insert sequencing
/// is behaviour here, not style.
///
/// ## Enumerated dependencies
///
/// Repositories the cluster touches (constructor-injected):
///  * [PanelSampleRepository] — every panel read/write/delete: `savePanelWithSamples`,
///    `deleteRowsBySessionId`, `deleteRowsBySessionIdForSampleIds`,
///    `deleteRowsBySessionIdExcept`, `deleteHierarchyRowsBySessionId`,
///    `deleteHierarchyRowsBySessionIdExcept`.
///  * [BenchmarkLookup] — `nearestBreakoutBenchmark`, used only by
///    `_breakoutBenchmarkForDraft` when building egg-breakout panel values.
///
/// Provider state the cluster reads but does not own (injected as read-only
/// accessors so each read still happens at exactly the moment it happened
/// before the move, rather than against a snapshot taken at entry):
///  * `AuditProvider._context` → [_context]. Fields read: `auditType` (via
///    [_isChicksContext]), `setterId`, `hatcherId`, `hatcheryId`, `breed`,
///    `flockAgeWeeks`, `flockEntryDate`.
///  * `AuditProvider._activeSessionId` → [_activeSessionId]. Read only by
///    `_deletePanelRowsForRemovedSamples` when resolving the session to prune.
///  * `AuditProvider._stationSamples` → [_stationSamples]. Read only by
///    `_deletePanelRowsForRemovedSamples`, as the last session-id fallback.
///  * `AuditProvider._chickWeightSamples` → [_chickWeightSamples]. Read only by
///    `_hasMeaningfulPanelTableData`'s `chick_quality` branch.
///
/// Everything else the cluster needs is either a parameter of the two entry
/// points or a pure function from `../logic/`.
///
/// The cluster mutates **no** provider state; the provider keeps ownership of
/// `_stationSamples`/`_chickWeightSamples` reassignment, dirty/version
/// bookkeeping, and the final-save side effects.
class AuditPanelSaveCoordinator {
  AuditPanelSaveCoordinator({
    required PanelSampleRepository panelSampleRepository,
    required BenchmarkLookup benchmarkLookup,
    required AuditContext? Function() context,
    required String? Function() activeSessionId,
    required List<StationSampleModel> Function() stationSamples,
    required List<StationSampleModel> Function() chickWeightSamples,
  }) : _panelSampleRepository = panelSampleRepository,
       _benchmarkLookup = benchmarkLookup,
       _readContext = context,
       _readActiveSessionId = activeSessionId,
       _readStationSamples = stationSamples,
       _readChickWeightSamples = chickWeightSamples;

  final PanelSampleRepository _panelSampleRepository;
  final BenchmarkLookup _benchmarkLookup;
  final AuditContext? Function() _readContext;
  final String? Function() _readActiveSessionId;
  final List<StationSampleModel> Function() _readStationSamples;
  final List<StationSampleModel> Function() _readChickWeightSamples;

  AuditContext? get _context => _readContext();
  String? get _activeSessionId => _readActiveSessionId();
  List<StationSampleModel> get _stationSamples => _readStationSamples();
  List<StationSampleModel> get _chickWeightSamples => _readChickWeightSamples();
  bool get _isChicksContext => _context?.auditType == 'Chicks';

  /// Persists every station panel table for one save pass.
  ///
  /// The body is the verbatim station-panel section of
  /// `AuditProvider._saveSamplesInternal`: scope the pairs, delete rows for
  /// removed samples, delete discarded rows, write the pooled egg-storage
  /// table, write the per-sample panel tables, then prune stale hierarchy and
  /// breakout rows — in that order.
  Future<void> savePanelTables({
    required List<PanelSavePair> panelSavePairs,
    required List<AuditModel> draftsToSave,
    required List<String> removedStationSampleIds,
  }) async {
    final scopedPanelSavePairs = _scopedPanelSavePairs(panelSavePairs);
    final meaningfulScopedPanelSavePairs = scopedPanelSavePairs
        .where(_hasMeaningfulPanelData)
        .toList();
    final eggPanelSavePairs = panelSavePairs
        .where((pair) => pair.draft.auditType == 'Egg')
        .toList();
    final eggQualityPanelSavePairs = meaningfulScopedPanelSavePairs
        .where((pair) => pair.draft.auditType == 'Egg')
        .toList();
    await _deletePanelRowsForRemovedSamples(
      draftsToSave: draftsToSave,
      removedStationSampleIds: removedStationSampleIds,
    );
    await _deleteDiscardedPanelRows(scopedPanelSavePairs);
    if (eggPanelSavePairs.isNotEmpty) {
      await _savePooledEggStoragePanelTable(eggPanelSavePairs);
      if (!_hasAnyMeaningfulEggQualityData(eggQualityPanelSavePairs)) {
        await _deleteEggQualityRowsBySessionId(eggPanelSavePairs);
      }
    }
    for (final pair in meaningfulScopedPanelSavePairs) {
      await _savePanelTablesForSample(
        pair.draft,
        pair.sample,
        skipTables: pair.draft.auditType == 'Egg'
            ? {
                'egg_storage',
                if (!hasMeaningfulEggQualityData(pair.draft)) 'egg_quality',
              }
            : const <String>{},
      );
    }
    await _pruneStalePanelHierarchyRows(meaningfulScopedPanelSavePairs);
    await _pruneStaleBreakoutRows(meaningfulScopedPanelSavePairs);
  }

  /// Persists the `chick_weights` panel table for one save pass.
  ///
  /// The body is the verbatim chick-weight section of
  /// `AuditProvider._saveSamplesInternal`. It runs *after* the provider has
  /// swapped the freshly built samples into `_chickWeightSamples`, which is why
  /// it is a second entry point rather than a tail of [savePanelTables].
  Future<void> saveChickWeightPanels({
    required AuditModel draft,
    required List<StationSampleModel> samplesToSave,
  }) async {
    final meaningfulChickWeightSamples = [
      for (final sample in samplesToSave)
        if (hasMeaningfulChickWeightSample(
          chickWeightValuesForSample(sample, fallback: draft),
        ))
          sample,
    ];
    await _deleteDiscardedChickWeightRows(
      samplesToSave,
      meaningfulChickWeightSamples,
    );
    if (meaningfulChickWeightSamples.isEmpty) {
      final sessionId = samplesToSave.first.auditSessionId;
      if (sessionId.isNotEmpty) {
        await _panelSampleRepository.deleteRowsBySessionId(
          'chick_weights',
          sessionId,
        );
      }
    } else {
      await _saveChickWeightPanelSamples(draft, meaningfulChickWeightSamples);
    }
  }

  // ---------------------------------------------------------------------------
  // Panel writes
  // ---------------------------------------------------------------------------

  Future<void> _savePanelTablesForSample(
    AuditModel draft,
    StationSampleModel sample, {
    Set<String> skipTables = const <String>{},
  }) async {
    for (final tableName in panelTablesForDraft(draft)) {
      if (skipTables.contains(tableName)) continue;
      if (isEggBreakoutPanelTable(tableName)) {
        await _saveEggBreakoutPanelTable(tableName, draft, sample);
      } else {
        await _savePanelTableWithSamples(tableName, draft, [sample]);
      }
    }
  }

  Future<void> _savePooledEggStoragePanelTable(
    List<({AuditModel draft, StationSampleModel sample})> pairs,
  ) async {
    if (pairs.isEmpty) return;
    final sessionId = pairs.first.sample.auditSessionId;
    if (sessionId.isEmpty) return;

    final draft = _pooledEggStorageDraft([
      for (final pair in pairs) pair.draft,
    ]);
    if (!hasSavableEggStorageData(draft)) {
      await _panelSampleRepository.deleteRowsBySessionId(
        'egg_storage',
        sessionId,
      );
      return;
    }

    await _panelSampleRepository.deleteHierarchyRowsBySessionId(
      'egg_storage',
      sessionId,
    );
    await _savePanelTableWithSamples('egg_storage', draft, [
      _pooledEggStorageSample(pairs.first.sample, draft),
    ]);
  }

  AuditModel _pooledEggStorageDraft(List<AuditModel> drafts) {
    final base = drafts.first;
    final map = base.toMap();
    for (final key in _pooledEggStorageFieldKeys) {
      map[key] = _firstMeaningfulDraftValue(drafts, key, map[key]);
    }
    map['notes'] = _firstMeaningfulDraftValue(drafts, 'notes', map['notes']);
    map['sampleMode'] = SampleMode.pool;
    map['compareGroupKey'] = null;
    map['hatchNumber'] = 1;
    map['updatedAt'] = DateTime.now().toIso8601String();
    return AuditModel.fromMap(map);
  }

  StationSampleModel _pooledEggStorageSample(
    StationSampleModel sample,
    AuditModel draft,
  ) {
    final now = DateTime.now();
    return StationSampleModel(
      id: sample.id,
      auditSessionId: sample.auditSessionId,
      legacyAuditId: draft.id,
      stationType: sample.stationType,
      sectorType: sample.sectorType,
      sampleKind: StationSampleModel.sampleKindPooled,
      sampleMode: StationSampleModel.sampleModePooled,
      sampleIndex: 1,
      sampleLabel: 'Sample 1',
      sampleType: sample.sampleType,
      breakoutType: sample.breakoutType,
      batchNo: sample.batchNo,
      hatchNo: sample.hatchNo,
      storageDays: storageDaysForDraft(draft),
      incubationDay: sample.incubationDay,
      calculatedBmkAgeDays: sample.calculatedBmkAgeDays,
      benchmarkBreed: sample.benchmarkBreed,
      benchmarkAgeDays: sample.benchmarkAgeDays,
      benchmarkSource: sample.benchmarkSource,
      benchmarkSnapshotJson: sample.benchmarkSnapshotJson,
      resultSummaryJson: StationSampleMapper.resultSummaryJsonForAudit(draft),
      notes: draft.notes ?? sample.notes,
      createdAt: sample.createdAt,
      updatedAt: now,
    );
  }

  static const _pooledEggStorageFieldKeys = [
    'esEggStorageDays',
    'es_estReadingsJson',
    'es_estPhotosJson',
    'es_estAvg',
    'es_estCv',
    'esTurningTimes',
    'esUvTrays',
    'es_traySpacing',
    'es_coolerProximity',
    'es_condensation',
  ];

  Object? _firstMeaningfulDraftValue(
    List<AuditModel> drafts,
    String key,
    Object? fallback,
  ) {
    for (final draft in drafts) {
      final value = draft.toMap()[key];
      if (isMeaningfulPooledEggStorageValue(key, value)) return value;
    }
    return fallback;
  }

  bool _hasAnyMeaningfulEggQualityData(
    List<({AuditModel draft, StationSampleModel sample})> pairs,
  ) {
    return pairs.any((pair) => hasMeaningfulEggQualityData(pair.draft));
  }

  Future<void> _saveEggBreakoutPanelTable(
    String tableName,
    AuditModel draft,
    StationSampleModel sample,
  ) async {
    final rows = await _breakoutPanelRowsForTable(tableName, draft, sample);
    for (final row in rows) {
      await _panelSampleRepository.savePanelWithSamples(
        panel: row.panel,
        samples: [row.sample],
      );
    }
  }

  Future<List<({PanelRecord panel, PanelSampleRecord sample})>>
  _breakoutPanelRowsForTable(
    String tableName,
    AuditModel draft,
    StationSampleModel sample,
  ) async {
    final entries = breakoutLeafEntriesForTable(tableName, draft);
    if (entries.isEmpty) {
      final panel = _panelRecordForSamples(tableName, draft, [sample]);
      return [
        (
          panel: panel,
          sample: _panelSampleRecordForStationSample(
            tableName: tableName,
            panelId: panel.id,
            draft: draft,
            sample: sample,
          ),
        ),
      ];
    }

    final breakoutType = breakoutTypeForTable(tableName);
    final benchmark = await _breakoutBenchmarkForDraft(draft, breakoutType);
    final basePanel = _panelRecordForSamples(tableName, draft, [sample]);
    final baseRowId = '${basePanel.id}:${sample.id}';
    final rows = <({PanelRecord panel, PanelSampleRecord sample})>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final label = breakoutTrayLabel(entry, i);
      final isFresh = breakoutType == EggBreakoutType.freshEggBreakout;
      final useDraftBatchHierarchy =
          !isFresh && SampleMode.isCompare(draft.sampleMode);
      final entryHouse = blankToNull(entry.house);
      final entrySetter = blankToNull(entry.setter);
      final entryHatcher = blankToNull(entry.hatcher);
      final houseValue = isFresh
          ? entryHouse
          : entryHouse ??
                (useDraftBatchHierarchy ? blankToNull(draft.houseId) : null);
      final setterValue = isFresh
          ? null
          : entrySetter ??
                (useDraftBatchHierarchy ? blankToNull(draft.setterId) : null);
      final hatcherValue = isFresh
          ? null
          : entryHatcher ??
                (useDraftBatchHierarchy ? blankToNull(draft.hatcherId) : null);
      final values = breakoutValuesForEntry(
        tableName,
        draft,
        entry,
        benchmark,
        flockAgeWeeks: _context?.flockAgeWeeks,
        flockEntryDate: _context?.flockEntryDate,
      );
      final scopeType = _breakoutScopeTypeForEntry(
        tableName: tableName,
        entry: entry,
        breakoutType: breakoutType,
      );
      final panel = PanelRecord(
        id: basePanel.id,
        tableName: tableName,
        sessionId: basePanel.sessionId,
        customerId: basePanel.customerId,
        flockId: basePanel.flockId,
        hatcheryId: basePanel.hatcheryId,
        date: basePanel.date,
        breed: basePanel.breed,
        flockAgeWeeks: basePanel.flockAgeWeeks,
        storagePeriodDays: basePanel.storagePeriodDays,
        bmkAgeWeeks: asInt(values['bmkAgeWeeks']) ?? basePanel.bmkAgeWeeks,
        mode: scopeType == SamplingLayer.pool
            ? PanelRecord.modePool
            : PanelRecord.modeCompare,
        scopeType: scopeType,
        scopeLabel: breakoutScopeLabelForEntry(scopeType, entry, label),
        sampleIndex: i + 1,
        groupKey: basePanel.groupKey,
        groupLabel:
            basePanel.groupLabel ?? breakoutGroupLabelForScope(scopeType),
        notes: basePanel.notes,
        syncStatus: basePanel.syncStatus,
        lastSyncedAt: basePanel.lastSyncedAt,
        syncError: basePanel.syncError,
        values: values,
        createdAt: basePanel.createdAt,
        updatedAt: basePanel.updatedAt,
      );
      final panelSample = PanelSampleRecord(
        id: breakoutEntryRowId(baseRowId, i, entry, scopeType),
        panelId: basePanel.id,
        scopeType: scopeType,
        scopeLabel: breakoutScopeLabelForEntry(scopeType, entry, label),
        sampleIndex: i + 1,
        houseId: houseValue,
        houseName: houseValue,
        setterId: setterValue,
        hatcherId: hatcherValue,
        trolleyId: isFresh || scopeBeforeTrolley(scopeType)
            ? null
            : blankToNull(entry.trolley),
        trolleyLabel: isFresh || scopeBeforeTrolley(scopeType)
            ? null
            : blankToNull(entry.trolley),
        trayId: scopeType == SamplingLayer.tray
            ? blankToNull(entry.tray) ?? blankToNull(entry.id)
            : null,
        trayLabel: scopeType == SamplingLayer.tray
            ? blankToNull(entry.tray) ?? label
            : null,
        position: isFresh || scopeType != SamplingLayer.tray
            ? null
            : blankToNull(entry.position),
        sampleSize: entry.totalSample,
        summaryJson: jsonEncode(entry.toJson()),
        rawJson: compactJson({
          ...sample.toMap(),
          'breakoutTray': entry.toJson(),
        }),
        notes: sample.notes,
        createdAt: sample.createdAt,
        updatedAt: sample.updatedAt,
      );
      rows.add((panel: panel, sample: panelSample));
    }
    return rows;
  }

  Future<void> _savePanelTableWithSamples(
    String tableName,
    AuditModel draft,
    List<StationSampleModel> samples,
  ) async {
    if (samples.isEmpty) return;
    final panel = _panelRecordForSamples(tableName, draft, samples);
    final panelSamples = [
      for (final sample in samples)
        _panelSampleRecordForStationSample(
          tableName: tableName,
          panelId: panel.id,
          draft: draft,
          sample: sample,
        ),
    ];
    await _panelSampleRepository.savePanelWithSamples(
      panel: panel,
      samples: panelSamples,
    );
  }

  Future<void> _saveChickWeightPanelSamples(
    AuditModel draft,
    List<StationSampleModel> samples,
  ) async {
    final pairs = [
      for (final sample in samples)
        (
          draft: _draftWithChickWeightSampleValues(draft, sample),
          sample: sample,
        ),
    ];
    for (final pair in pairs) {
      await _savePanelTableWithSamples('chick_weights', pair.draft, [
        pair.sample,
      ]);
    }
    await _pruneStalePanelHierarchyRowsForTable(
      'chick_weights',
      samples.first.auditSessionId,
      pairs,
    );
  }

  // ---------------------------------------------------------------------------
  // Deletes and prunes
  // ---------------------------------------------------------------------------

  Future<void> _deleteEggQualityRowsBySessionId(
    List<PanelSavePair> pairs,
  ) async {
    if (pairs.isEmpty) return;
    final sessionId = pairs.first.sample.auditSessionId;
    if (sessionId.isEmpty) return;
    await _panelSampleRepository.deleteRowsBySessionId(
      'egg_quality',
      sessionId,
    );
  }

  Future<void> _deleteDiscardedPanelRows(List<PanelSavePair> pairs) async {
    final deleted = <String>{};
    for (final pair in pairs) {
      if (pair.draft.auditType == 'Egg') continue;
      final sessionId = pair.sample.auditSessionId;
      if (sessionId.isEmpty) continue;
      for (final tableName in panelTablesForDraft(pair.draft)) {
        if (_hasMeaningfulPanelTableData(tableName, pair.draft)) continue;
        final key = '$sessionId::$tableName';
        if (!deleted.add(key)) continue;
        await _panelSampleRepository.deleteRowsBySessionId(
          tableName,
          sessionId,
        );
      }
    }
  }

  Future<void> _deleteDiscardedChickWeightRows(
    List<StationSampleModel> allSamples,
    List<StationSampleModel> meaningfulSamples,
  ) async {
    if (allSamples.isEmpty) return;
    final meaningfulIds = meaningfulSamples.map((sample) => sample.id).toSet();
    final discardedIds = {
      for (final sample in allSamples)
        if (!meaningfulIds.contains(sample.id)) sample.id,
    };
    if (discardedIds.isEmpty) return;
    final sessionId = allSamples.first.auditSessionId;
    if (sessionId.isEmpty) return;
    await _panelSampleRepository.deleteRowsBySessionIdForSampleIds(
      'chick_weights',
      sessionId,
      discardedIds,
    );
  }

  Future<void> _deletePanelRowsForRemovedSamples({
    required List<AuditModel> draftsToSave,
    required List<String> removedStationSampleIds,
  }) async {
    final sampleIds = removedStationSampleIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (sampleIds.isEmpty || draftsToSave.isEmpty) return;

    final sessionId =
        _activeSessionId ??
        draftsToSave.first.sessionId ??
        (_stationSamples.isEmpty ? null : _stationSamples.first.auditSessionId);
    if (sessionId == null || sessionId.isEmpty) return;

    final tableNames = <String>{
      for (final draft in draftsToSave) ...panelTablesForDraft(draft),
      if (_isChicksContext) 'chick_weights',
    };
    for (final tableName in tableNames) {
      await _panelSampleRepository.deleteRowsBySessionIdForSampleIds(
        tableName,
        sessionId,
        sampleIds,
      );
    }
  }

  Future<void> _pruneStalePanelHierarchyRows(List<PanelSavePair> pairs) async {
    if (pairs.isEmpty) return;
    final pairsByKey = <String, List<PanelSavePair>>{};
    final tableByKey = <String, String>{};
    for (final pair in pairs) {
      final sessionId = pair.sample.auditSessionId;
      if (sessionId.isEmpty) continue;
      for (final tableName in _panelTablesForScopedPrune(pair)) {
        final key = '$sessionId::$tableName';
        tableByKey[key] = tableName;
        pairsByKey.putIfAbsent(key, () => <PanelSavePair>[]).add(pair);
      }
    }
    for (final entry in pairsByKey.entries) {
      final separatorIndex = entry.key.indexOf('::');
      final sessionId = entry.key.substring(0, separatorIndex);
      final tableName = tableByKey[entry.key];
      if (tableName == null) continue;
      await _pruneStalePanelHierarchyRowsForTable(
        tableName,
        sessionId,
        entry.value,
      );
    }
  }

  Iterable<String> _panelTablesForScopedPrune(PanelSavePair pair) sync* {
    for (final tableName in panelTablesForDraft(pair.draft)) {
      if (tableName == 'egg_storage') continue;
      if (isEggBreakoutPanelTable(tableName)) continue;
      if (pair.draft.auditType == 'Egg' &&
          tableName == 'egg_quality' &&
          !hasMeaningfulEggQualityData(pair.draft)) {
        continue;
      }
      yield tableName;
    }
  }

  Future<void> _pruneStalePanelHierarchyRowsForTable(
    String tableName,
    String sessionId,
    List<PanelSavePair> pairs,
  ) async {
    if (pairs.isEmpty) return;
    final keepIds = <String>{};
    final keepHierarchyRows = <Map<String, Object?>>[];
    for (final pair in pairs) {
      final row = _panelHierarchyRowForSample(
        tableName,
        pair.draft,
        pair.sample,
      );
      keepIds.add(row['id']! as String);
      keepHierarchyRows.add(row);
    }
    await _panelSampleRepository.deleteHierarchyRowsBySessionIdExcept(
      tableName,
      sessionId,
      keepIds,
      keepHierarchyRows: keepHierarchyRows,
    );
  }

  Future<void> _pruneStaleBreakoutRows(List<PanelSavePair> pairs) async {
    if (pairs.isEmpty) return;
    final pairsByKey = <String, List<PanelSavePair>>{};
    final tableByKey = <String, String>{};
    for (final pair in pairs) {
      final sessionId = pair.sample.auditSessionId;
      if (sessionId.isEmpty) continue;
      for (final tableName in panelTablesForDraft(pair.draft)) {
        if (!isEggBreakoutPanelTable(tableName)) continue;
        final key = '$sessionId::$tableName';
        tableByKey[key] = tableName;
        pairsByKey.putIfAbsent(key, () => <PanelSavePair>[]).add(pair);
      }
    }

    for (final entry in pairsByKey.entries) {
      final separatorIndex = entry.key.indexOf('::');
      final sessionId = entry.key.substring(0, separatorIndex);
      final tableName = tableByKey[entry.key];
      if (tableName == null) continue;
      final keepIds = <String>{};
      final keepHierarchyRows = <Map<String, Object?>>[];
      for (final pair in entry.value) {
        final rows = await _breakoutPanelRowsForTable(
          tableName,
          pair.draft,
          pair.sample,
        );
        for (final row in rows) {
          keepIds.add(row.sample.id);
          keepHierarchyRows.add(_panelHierarchyRowForPanelSample(row.sample));
        }
      }
      await _panelSampleRepository.deleteRowsBySessionIdExcept(
        tableName,
        sessionId,
        keepIds,
        keepHierarchyRows: keepHierarchyRows,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Scoping / hierarchy helpers
  // ---------------------------------------------------------------------------

  List<PanelSavePair> _scopedPanelSavePairs(List<PanelSavePair> pairs) {
    if (pairs.isEmpty) return pairs;
    return _pruneHatchBreakoutParentPairs(pairs);
  }

  List<PanelSavePair> _pruneHatchBreakoutParentPairs(
    List<PanelSavePair> pairs,
  ) {
    final paths = <_BreakoutHierarchyPath>[];
    for (var i = 0; i < pairs.length; i++) {
      final pair = pairs[i];
      if (pair.draft.auditType != 'Hatch Analysis & Egg Breakouts') {
        continue;
      }
      for (final tableName in panelTablesForDraft(pair.draft)) {
        if (!isEggBreakoutPanelTable(tableName)) continue;
        paths.addAll(_breakoutHierarchyPathsForPair(i, tableName, pair));
      }
    }
    if (paths.length < 2) return pairs;

    final parentPairIndexes = <int>{};
    for (final path in paths) {
      if (!path.canHaveChildren) continue;
      final hasChild = paths.any(
        (candidate) =>
            candidate.pairIndex != path.pairIndex && path.isParentOf(candidate),
      );
      if (hasChild) parentPairIndexes.add(path.pairIndex);
    }
    if (parentPairIndexes.isEmpty) return pairs;

    return [
      for (var i = 0; i < pairs.length; i++)
        if (!parentPairIndexes.contains(i)) pairs[i],
    ];
  }

  List<_BreakoutHierarchyPath> _breakoutHierarchyPathsForPair(
    int pairIndex,
    String tableName,
    PanelSavePair pair,
  ) {
    final entries = breakoutLeafEntriesForTable(tableName, pair.draft);
    if (entries.isEmpty) {
      final panel = _panelRecordForSamples(tableName, pair.draft, [
        pair.sample,
      ]);
      final panelSample = _panelSampleRecordForStationSample(
        tableName: tableName,
        panelId: panel.id,
        draft: pair.draft,
        sample: pair.sample,
      );
      return [
        _BreakoutHierarchyPath(
          pairIndex: pairIndex,
          sessionId: pair.sample.auditSessionId,
          tableName: tableName,
          scopeType: panelSample.scopeType,
          house: blankToNull(panelSample.houseId),
          setter: blankToNull(panelSample.setterId),
          hatcher: blankToNull(panelSample.hatcherId),
          trolley: blankToNull(panelSample.trolleyLabel),
          tray: blankToNull(panelSample.trayLabel),
          position: blankToNull(panelSample.position),
        ),
      ];
    }

    final breakoutType = breakoutTypeForTable(tableName);
    final useDraftBatchHierarchy =
        breakoutType != EggBreakoutType.freshEggBreakout &&
        SampleMode.isCompare(pair.draft.sampleMode);
    return [
      for (final entry in entries)
        _BreakoutHierarchyPath(
          pairIndex: pairIndex,
          sessionId: pair.sample.auditSessionId,
          tableName: tableName,
          scopeType: _breakoutScopeTypeForEntry(
            tableName: tableName,
            entry: entry,
            breakoutType: breakoutType,
          ),
          house: breakoutType == EggBreakoutType.freshEggBreakout
              ? blankToNull(entry.house)
              : blankToNull(entry.house) ??
                    (useDraftBatchHierarchy
                        ? blankToNull(pair.draft.houseId)
                        : null),
          setter: breakoutType == EggBreakoutType.freshEggBreakout
              ? null
              : blankToNull(entry.setter) ??
                    (useDraftBatchHierarchy
                        ? blankToNull(pair.draft.setterId)
                        : null),
          hatcher: breakoutType == EggBreakoutType.freshEggBreakout
              ? null
              : blankToNull(entry.hatcher) ??
                    (useDraftBatchHierarchy
                        ? blankToNull(pair.draft.hatcherId)
                        : null),
          trolley: breakoutType == EggBreakoutType.freshEggBreakout
              ? null
              : blankToNull(entry.trolley),
          tray: blankToNull(entry.tray),
          position: breakoutType == EggBreakoutType.freshEggBreakout
              ? null
              : blankToNull(entry.position),
        ),
    ];
  }

  Map<String, Object?> _panelHierarchyRowForPanelSample(
    PanelSampleRecord sample,
  ) {
    return {
      'id': sample.id,
      'house': blankToNull(sample.houseId) ?? blankToNull(sample.houseName),
      'setter': blankToNull(sample.setterId),
      'hatcher': blankToNull(sample.hatcherId),
      'trolley':
          blankToNull(sample.trolleyLabel) ?? blankToNull(sample.trolleyId),
      'tray': blankToNull(sample.trayLabel) ?? blankToNull(sample.trayId),
      'position': blankToNull(sample.position),
    };
  }

  Map<String, Object?> _panelHierarchyRowForSample(
    String tableName,
    AuditModel draft,
    StationSampleModel sample,
  ) {
    final panel = _panelRecordForSamples(tableName, draft, [sample]);
    final panelSample = _panelSampleRecordForStationSample(
      tableName: tableName,
      panelId: panel.id,
      draft: draft,
      sample: sample,
    );
    return {
      'id': panelSample.id,
      'house':
          blankToNull(panelSample.houseId) ??
          blankToNull(panelSample.houseName) ??
          blankToNull(panel.house),
      'setter': blankToNull(panelSample.setterId) ?? blankToNull(panel.setter),
      'hatcher':
          blankToNull(panelSample.hatcherId) ?? blankToNull(panel.hatcher),
      'trolley':
          blankToNull(panelSample.trolleyLabel) ??
          blankToNull(panelSample.trolleyId) ??
          blankToNull(panel.trolley),
      'tray':
          blankToNull(panelSample.trayLabel) ??
          blankToNull(panelSample.trayId) ??
          blankToNull(panel.tray),
      'position':
          blankToNull(panelSample.position) ?? blankToNull(panel.position),
    };
  }

  // ---------------------------------------------------------------------------
  // Record builders
  // ---------------------------------------------------------------------------

  PanelRecord _panelRecordForSamples(
    String tableName,
    AuditModel draft,
    List<StationSampleModel> samples,
  ) {
    final compareLayer = _compareLayerForPanel(tableName, samples);
    final mode = compareLayer == null
        ? PanelRecord.modePool
        : PanelRecord.modeCompare;
    final sample = samples.first;
    final domains = _domainsForPanel(tableName);
    final metadata = <String, Object?>{
      'sampleMode': sample.sampleMode,
      'scopeType': _scopeTypeForPanel(tableName, sample, draft).dbValue,
      'sampleLabel': sample.sampleLabel,
      'sampleIndex': sample.sampleIndex,
      if (domains != null) ...{
        'sourceDomain': domains.source,
        'actionDomain': domains.action,
        'recommendationTarget': domains.target,
      },
    };
    return PanelRecord(
      id: '${samples.first.auditSessionId}:$tableName:${draft.id}',
      tableName: tableName,
      sessionId: samples.first.auditSessionId,
      customerId: draft.customerId,
      flockId: blankToNull(draft.flockId),
      date: draft.date,
      hatcheryId: blankToNull(_context?.hatcheryId),
      breed: _context?.breed ?? draft.soBreed ?? draft.hoBreed,
      flockAgeWeeks: _context?.flockAgeWeeks,
      storagePeriodDays: _storageDaysForPanel(tableName, draft),
      bmkAgeWeeks: legacyBmkWeeksForDraft(draft),
      mode: mode,
      scopeType: compareLayer ?? SamplingLayer.pool,
      notes: draft.notes,
      values: {
        ...panelValuesForDraft(
          tableName,
          draft,
          flockAgeWeeks: _context?.flockAgeWeeks,
          flockEntryDate: _context?.flockEntryDate,
        ),
        ...metadata,
      },
      createdAt: draft.createdAt,
      updatedAt: draft.updatedAt,
    );
  }

  PanelSampleRecord _panelSampleRecordForStationSample({
    required String tableName,
    required String panelId,
    required AuditModel draft,
    required StationSampleModel sample,
  }) {
    final scopeType = _scopeTypeForPanel(tableName, sample, draft);
    final isHatchBreakout = draft.auditType == 'Hatch Analysis & Egg Breakouts';
    final sampleHouseNo = isHatchBreakout
        ? blankToNull(draft.houseId)
        : blankToNull(sample.houseNo);
    final sampleHouseLabel = isHatchBreakout
        ? blankToNull(draft.houseId)
        : blankToNull(sample.houseLabel);
    final sampleSetterNo = isHatchBreakout
        ? blankToNull(draft.setterId)
        : blankToNull(sample.setterNo);
    final sampleHatcherNo = isHatchBreakout
        ? blankToNull(draft.hatcherId)
        : blankToNull(sample.hatcherNo);
    final usesHouse =
        scopeIncludesHouse(scopeType) &&
        (sampleHouseNo != null || sampleHouseLabel != null);
    final usesSetter =
        tableName == 'setter_optimizing' ||
        scopeType == SamplingLayer.setter ||
        scopeType == SamplingLayer.setterHatcher;
    final usesHatcher =
        tableName == 'hatcher_optimizing' ||
        scopeType == SamplingLayer.hatcher ||
        scopeType == SamplingLayer.setterHatcher;
    final rowId = PanelSampleRepository.idKeyedPanelTables.contains(tableName)
        ? sample.id
        : '$panelId:${sample.id}';
    return PanelSampleRecord(
      id: rowId,
      panelId: panelId,
      scopeType: scopeType,
      scopeLabel: scopeLabelForSample(scopeType, sample),
      sampleIndex: sample.sampleIndex,
      houseId: usesHouse ? sampleHouseNo : null,
      houseName: usesHouse ? sampleHouseLabel : null,
      setterId: usesSetter ? sampleSetterNo : null,
      hatcherId: usesHatcher ? sampleHatcherNo : null,
      sampleSize: _sampleSizeForPanel(tableName, draft),
      summaryJson: sample.resultSummaryJson,
      rawJson: compactJson(sample.toMap()),
      notes: sample.notes,
      createdAt: sample.createdAt,
      updatedAt: sample.updatedAt,
    );
  }

  AuditModel _draftWithChickWeightSampleValues(
    AuditModel draft,
    StationSampleModel sample,
  ) {
    final values = chickWeightValuesForSample(sample, fallback: draft);
    final map = draft.toMap()
      ..['chickWeights'] = values['weightsJson']
      ..['chickSampleSize'] = values['sampleSize']
      ..['chickAvgWeight'] = values['avgWeight']
      ..['chickUniformityPct'] = values['uniformityPct']
      ..['chickCvPct'] = values['cvPct']
      ..['chickBmkAge'] = values['bmkAgeWeeks']
      ..['chickBmkWeight'] = values['bmkWeight'];
    return AuditModel.fromMap(map);
  }

  // ---------------------------------------------------------------------------
  // Meaningfulness / scope classification
  // ---------------------------------------------------------------------------

  bool _hasMeaningfulPanelData(PanelSavePair pair) {
    return panelTablesForDraft(
      pair.draft,
    ).any((tableName) => _hasMeaningfulPanelTableData(tableName, pair.draft));
  }

  bool _hasMeaningfulPanelTableData(String tableName, AuditModel draft) {
    return switch (tableName) {
      'egg_storage' => hasSavableEggStorageData(draft),
      'egg_quality' => hasMeaningfulEggQualityData(draft),
      'chick_quality' => hasMeaningfulChickData(
        draft,
        hasAnyMeaningfulChickWeightSample: _chickWeightSamples.any(
          (sample) => hasMeaningfulChickWeightSample(
            chickWeightValuesForSample(sample, fallback: draft),
          ),
        ),
      ),
      'fresh_egg_breakout' ||
      'candled_egg_breakout' ||
      'residue_breakout' => hasMeaningfulHatchData(draft),
      'setter_optimizing' => hasMeaningfulSetterData(
        draft,
        contextSetterId: _context?.setterId,
      ),
      'hatcher_optimizing' => hasMeaningfulHatcherData(
        draft,
        contextHatcherId: _context?.hatcherId,
      ),
      _ => false,
    };
  }

  /// Which side of the operation a panel's measurement, corrective action, and
  /// recommendation belong to. Egg storage is measured and fixed inside the
  /// hatchery; egg quality is measured in the hatchery but caused and fixed at
  /// the breeder farm, so its recommendations target the farm.
  ({String source, String action, String target})? _domainsForPanel(
    String tableName,
  ) {
    return switch (tableName) {
      'egg_storage' => (
          source: 'hatchery',
          action: 'hatchery',
          target: 'hatchery',
        ),
      'egg_quality' => (source: 'hatchery', action: 'farm', target: 'farm'),
      _ => null,
    };
  }

  SamplingLayer? _compareLayerForPanel(
    String tableName,
    List<StationSampleModel> samples,
  ) {
    for (final sample in samples) {
      if (sample.sampleMode != StationSampleModel.sampleModeComparison) {
        continue;
      }
      final scope = _scopeTypeForPanel(tableName, sample);
      if (scope != SamplingLayer.pool) return scope;
    }
    return null;
  }

  SamplingLayer _scopeTypeForPanel(
    String tableName,
    StationSampleModel sample, [
    AuditModel? draft,
  ]) {
    final allowed = PanelSampleSchema.byTable(tableName).allowedLayers;
    final isHatchBreakout =
        draft?.auditType == 'Hatch Analysis & Egg Breakouts';
    final sampleSetterNo = isHatchBreakout
        ? blankToNull(draft?.setterId)
        : blankToNull(sample.setterNo);
    final sampleHatcherNo = isHatchBreakout
        ? blankToNull(draft?.hatcherId)
        : blankToNull(sample.hatcherNo);
    final isComparison =
        sample.sampleMode == StationSampleModel.sampleModeComparison ||
        (draft != null && SampleMode.isCompare(draft.sampleMode));
    if (!isComparison) {
      return SamplingLayer.pool;
    }
    if (allowed.contains(SamplingLayer.setterHatcher) &&
        sampleSetterNo != null &&
        sampleHatcherNo != null) {
      return SamplingLayer.setterHatcher;
    }
    if (allowed.contains(SamplingLayer.setter) && sampleSetterNo != null) {
      return SamplingLayer.setter;
    }
    if (allowed.contains(SamplingLayer.hatcher) && sampleHatcherNo != null) {
      return SamplingLayer.hatcher;
    }
    if (allowed.contains(SamplingLayer.house)) {
      return SamplingLayer.house;
    }
    return SamplingLayer.pool;
  }

  SamplingLayer _breakoutScopeTypeForEntry({
    required String tableName,
    required EggBreakoutSampleEntry entry,
    required EggBreakoutType breakoutType,
  }) {
    final allowed = PanelSampleSchema.byTable(tableName).allowedLayers;
    final isFresh = breakoutType == EggBreakoutType.freshEggBreakout;
    if (entry.sampleMode == EggBreakoutSampleMode.tray &&
        allowed.contains(SamplingLayer.tray)) {
      return SamplingLayer.tray;
    }
    if (!isFresh &&
        blankToNull(entry.trolley) != null &&
        allowed.contains(SamplingLayer.trolley)) {
      return SamplingLayer.trolley;
    }
    if (!isFresh &&
        blankToNull(entry.setter) != null &&
        blankToNull(entry.hatcher) != null &&
        allowed.contains(SamplingLayer.setterHatcher)) {
      return SamplingLayer.setterHatcher;
    }
    if (!isFresh &&
        blankToNull(entry.setter) != null &&
        allowed.contains(SamplingLayer.setter)) {
      return SamplingLayer.setter;
    }
    if (!isFresh &&
        blankToNull(entry.hatcher) != null &&
        allowed.contains(SamplingLayer.hatcher)) {
      return SamplingLayer.hatcher;
    }
    if (blankToNull(entry.house) != null &&
        allowed.contains(SamplingLayer.house)) {
      return SamplingLayer.house;
    }
    return SamplingLayer.pool;
  }

  int? _storageDaysForPanel(String tableName, AuditModel draft) {
    if (tableName == 'egg_quality') {
      return draft.esEggQualityStorageDays ?? draft.esEggStorageDays ?? 0;
    }
    return storageDaysForDraft(draft);
  }

  int? _sampleSizeForPanel(String tableName, AuditModel draft) {
    return switch (tableName) {
      'egg_quality' => draft.esEggSampleSize,
      'chick_quality' =>
        draft.pasgarSampleSize ??
            draft.cvtSampleSize ??
            draft.pmSampleSize ??
            draft.culledChicksTotalEggSet,
      'chick_weights' => draft.chickSampleSize,
      'fresh_egg_breakout' ||
      'candled_egg_breakout' ||
      'residue_breakout' => draft.ebTraySize ?? draft.haTotalEggsSet,
      _ => null,
    };
  }

  // ---------------------------------------------------------------------------
  // Benchmarks
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>?> _breakoutBenchmarkForDraft(
    AuditModel draft,
    EggBreakoutType breakoutType,
  ) async {
    final ageDays = breakoutType.calculateBmkAgeDays(
      currentFlockAgeDays: BmkAgeCalculator.currentFlockAgeDays(
        flockAgeWeeks: _context?.flockAgeWeeks,
        flockEntryDate: _context?.flockEntryDate,
        auditDate: draft.date,
      ),
      storageDays: draft.ebStorageDays ?? draft.haStorageDays ?? 0,
      candlingDay: draft.ebBreakoutAgeDays ?? 10,
    );
    if (ageDays == null) return null;
    try {
      return await _benchmarkLookup.nearestBreakoutBenchmark(
        calculatedBmkAgeDays: ageDays,
      );
    } catch (error) {
      safeDebugLog('Error loading breakout benchmark for save', error: error);
      return null;
    }
  }
}

/// One resolved hierarchy position a breakout pair would write to.
///
/// Moved verbatim from `audit_provider.dart`; stays private because only
/// [AuditPanelSaveCoordinator._pruneHatchBreakoutParentPairs] uses it.
class _BreakoutHierarchyPath {
  const _BreakoutHierarchyPath({
    required this.pairIndex,
    required this.sessionId,
    required this.tableName,
    required this.scopeType,
    this.house,
    this.setter,
    this.hatcher,
    this.trolley,
    this.tray,
    this.position,
  });

  final int pairIndex;
  final String sessionId;
  final String tableName;
  final SamplingLayer scopeType;
  final String? house;
  final String? setter;
  final String? hatcher;
  final String? trolley;
  final String? tray;
  final String? position;

  bool get canHaveChildren => _samplingLayerDepth(scopeType) < 4;

  bool isParentOf(_BreakoutHierarchyPath child) {
    if (sessionId != child.sessionId || tableName != child.tableName) {
      return false;
    }
    if (_samplingLayerDepth(child.scopeType) <=
        _samplingLayerDepth(scopeType)) {
      return false;
    }
    return switch (scopeType) {
      SamplingLayer.pool => true,
      SamplingLayer.house => _matches(house, child.house),
      SamplingLayer.setter =>
        _matches(house, child.house) && _matches(setter, child.setter),
      SamplingLayer.hatcher =>
        _matches(house, child.house) && _matches(hatcher, child.hatcher),
      SamplingLayer.setterHatcher =>
        _matches(house, child.house) &&
            _matches(setter, child.setter) &&
            _matches(hatcher, child.hatcher),
      SamplingLayer.trolley =>
        _matches(house, child.house) &&
            _matches(setter, child.setter) &&
            _matches(hatcher, child.hatcher) &&
            _matches(trolley, child.trolley),
      SamplingLayer.tray => false,
    };
  }

  static bool _matches(String? parentValue, String? childValue) {
    return parentValue == null || parentValue == childValue;
  }
}

int _samplingLayerDepth(SamplingLayer scopeType) {
  return switch (scopeType) {
    SamplingLayer.pool => 0,
    SamplingLayer.house => 1,
    SamplingLayer.setter ||
    SamplingLayer.hatcher ||
    SamplingLayer.setterHatcher => 2,
    SamplingLayer.trolley => 3,
    SamplingLayer.tray => 4,
  };
}
