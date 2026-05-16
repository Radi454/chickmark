import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/repositories/panel_dashboard_repository.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _customerId = 'smoke-customer';
const _flockId = 'smoke-flock';
const _hatcheryId = 'smoke-hatchery';
const _sessionId = 'smoke-session';
const _breed = 'Ross 308';
const _createdBy = 'panel-smoke';

const _poolWorkflowPanels = [
  'egg_storage',
  'egg_quality',
  'chick_pasgar',
  'chick_weights',
  'chick_yfbm',
  'chick_cvt',
  'chick_pm',
  'residue_breakout',
  'setter_optimizing',
  'hatcher_optimizing',
];

const _legacyTables = [
  'audits',
  'sample_records',
  'station_samples',
  'sample_house_details',
  'sample_machine_details',
  'sample_batch_details',
  'sample_timing_details',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuditSessionRepository sessionRepository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final databaseDir = Directory(
      p.join(
        Directory.systemTemp.path,
        'chickmark_panel_smoke_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await databaseDir.create(recursive: true);
    await databaseFactory.setDatabasesPath(databaseDir.path);
  });

  setUp(() async {
    await _resetDatabase();
    sessionRepository = AuditSessionRepository();
    await _createWorkflowScaffold();
  });

  tearDown(() async {
    await DatabaseHelper().close();
  });

  test(
    'full audit workflow saves, reopens, edits, and reloads from panel tables',
    () async {
      await _saveStation('egg', _fillEggStationInitial);
      await sessionRepository.markStationCompleted(_sessionId, 'egg');
      await _saveStation('chicks', _fillChickStationInitial);
      await sessionRepository.markStationCompleted(_sessionId, 'chicks');
      await _saveStation(
        'hatch_analysis_egg_breakouts',
        _fillHatchAnalysisInitial,
      );
      await sessionRepository.markStationCompleted(
        _sessionId,
        'hatch_analysis_egg_breakouts',
      );
      await _saveStation('setters', _fillSetterInitial);
      await sessionRepository.markStationCompleted(_sessionId, 'setters');
      await _saveStation('hatchers', _fillHatcherInitial);
      await sessionRepository.markStationCompleted(_sessionId, 'hatchers');

      final closedSession = await sessionRepository.getSessionById(_sessionId);
      expect(closedSession?.status, 'completed');
      expect(closedSession?.stationsCompleted, supportedStationKeys);

      await _expectInitialPanelValues();
      await _expectPoolRowsPerPanel();

      await _reopenEditAndSave('egg', _editEggStation);
      await _reopenEditAndSave('chicks', _editChickStation);
      await _reopenEditAndSave(
        'hatch_analysis_egg_breakouts',
        _editHatchAnalysis,
      );
      await _reopenEditAndSave('setters', _editSetter);
      await _reopenEditAndSave('hatchers', _editHatcher);

      await _expectEditedPanelValues();
      await _expectPoolRowsPerPanel();
      await _expectNoLegacyAuditOrSampleTables();
      await _expectDashboardLoadsFromPanelTables();
    },
  );

  test('pool mode creates one row per saved panel', () async {
    await _saveStation('egg', _fillEggStationInitial);
    await _saveStation('chicks', _fillChickStationInitial);
    await _saveStation(
      'hatch_analysis_egg_breakouts',
      _fillHatchAnalysisInitial,
    );
    await _saveStation('setters', _fillSetterInitial);
    await _saveStation('hatchers', _fillHatcherInitial);

    await _expectPoolRowsPerPanel();
  });

  test(
    'comparison mode creates multiple rows in the same panel table',
    () async {
      final provider = _newStationProvider('egg');
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      _fillEggStationInitial(provider);

      provider.addSample();
      _fillEggStationSecondHouse(provider);

      expect(await provider.saveSamplesWithResult(), isTrue);

      for (final table in ['egg_storage', 'egg_quality']) {
        final rows = await _rows(table);
        expect(rows, hasLength(2), reason: table);
        expect(rows.map((row) => row['mode']), ['comparison', 'comparison']);
        expect(rows.map((row) => row['scopeType']), ['house', 'house']);
        expect(rows.map((row) => row['sampleIndex']), [1, 2]);
      }

      final storage = await _rows('egg_storage');
      expect(storage.map((row) => row['storageDays']), [6, 10]);
      await _expectNoLegacyAuditOrSampleTables();
    },
  );

  test(
    'hard cutover schema exposes no legacy audit or sample tables',
    () async {
      await _saveStation('egg', _fillEggStationInitial);

      await _expectNoLegacyAuditOrSampleTables();
    },
  );
}

Future<void> _createWorkflowScaffold() async {
  final now = DateTime.utc(2026, 5, 15, 8);
  await CustomerRepository().insertCustomer(
    CustomerModel(
      id: _customerId,
      name: 'Smoke Customer',
      location: 'QA City',
      createdAt: now,
      createdBy: _createdBy,
    ),
  );
  await FlockRepository().insertFlock(
    FlockModel(
      id: _flockId,
      customerId: _customerId,
      flockId: 'Flock A',
      breed: _breed,
      entryDate: DateTime.utc(2025, 7, 25),
    ),
  );
  await HatcheryRepository().insertHatchery(
    HatcheryModel(
      id: _hatcheryId,
      customerId: _customerId,
      name: 'Smoke Hatchery',
      createdAt: now,
      createdBy: _createdBy,
    ),
  );
  await AuditSessionRepository().insertSession(
    AuditSessionModel(
      id: _sessionId,
      customerId: _customerId,
      flockId: _flockId,
      hatcheryId: _hatcheryId,
      date: DateTime.utc(2026, 5, 15),
      breed: _breed,
      flockAgeWeeks: 42,
      selectedStationKeys: supportedStationKeys,
      createdBy: _createdBy,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

Future<void> _saveStation(
  String stationKey,
  void Function(AuditProvider provider) fill,
) async {
  final provider = _newStationProvider(stationKey);
  fill(provider);
  expect(await provider.saveSamplesWithResult(), isTrue, reason: stationKey);
  provider.dispose();
}

Future<void> _reopenEditAndSave(
  String stationKey,
  void Function(AuditProvider provider) edit,
) async {
  final provider = await _reopenedStationProvider(stationKey);
  edit(provider);
  expect(await provider.saveSamplesWithResult(), isTrue, reason: stationKey);
  provider.dispose();
}

AuditProvider _newStationProvider(String stationKey) {
  final provider = AuditProvider(autosaveEnabled: false);
  provider.initialize(
    _auditContextFor(stationKey),
    sessionId: _sessionId,
    notify: false,
  );
  return provider;
}

Future<AuditProvider> _reopenedStationProvider(String stationKey) async {
  final rowsByPanel = await _rowsByPanelForStation(stationKey);
  final provider = AuditProvider(autosaveEnabled: false);
  provider.initialize(
    _auditContextFor(stationKey),
    existingAudits: _auditDraftsFromPanelRows(stationKey, rowsByPanel),
    existingStationSamples: _stationSamplesFromPanelRows(
      stationKey,
      rowsByPanel,
    ),
    readOnly: false,
    sessionId: _sessionId,
    notify: false,
  );
  return provider;
}

AuditContext _auditContextFor(String stationKey) {
  return AuditContext(
    auditType: switch (stationKey) {
      'egg' => 'Egg',
      'chicks' => 'Chicks',
      'hatch_analysis_egg_breakouts' => 'Hatch Analysis & Egg Breakouts',
      'setters' => 'Setters',
      'hatchers' => 'Hatchers',
      _ => throw ArgumentError('Unknown station: $stationKey'),
    },
    customerId: _customerId,
    flockId: _flockId,
    hatcheryId: _hatcheryId,
    breed: _breed,
    flockAgeWeeks: 42,
    setterId: 'S5',
    hatcherId: 'H7',
    date: '2026-05-15',
  );
}

void _fillEggStationInitial(AuditProvider provider) {
  provider.updateField('esEggStorageDays', 6);
  provider.updateField(
    'es_estReadingsJson',
    jsonEncode({'front_top': 100.2, 'middle_center': 100.4, 'back_low': 100.5}),
  );
  provider.updateField('es_estAvg', 100.4);
  provider.updateField('es_estCv', 0.15);
  provider.updateField('esShellTemp', 20.2);
  provider.updateField('esTurningTimes', 4);
  provider.updateField('es_traySpacing', 'Even');
  provider.updateField('es_coolerProximity', 'Middle rack');
  provider.updateField('es_condensation', 0);
  provider.updateField(
    'esUvTrays',
    jsonEncode([
      {
        'totalEggs': 100,
        'cuticleDamage': 2,
        'washed': 1,
        'dirty': 1,
        'upsideDown': 3,
      },
    ]),
  );
  provider.updateField(
    'esEggWeights',
    jsonEncode([61.0, 62.0, 62.5, 63.0, 64.0]),
  );
  provider.updateField('esEggSampleSize', 5);
  provider.updateField('esEggAvgWeight', 62.5);
  provider.updateField('esEggUniformityPct', 100.0);
  provider.updateField('esEggCvPct', 1.72);
  provider.updateField('esEggBmkAge', 42);
  provider.updateField('esEggBmkWeight', 62.0);
}

void _fillEggStationSecondHouse(AuditProvider provider) {
  provider.updateField('esEggStorageDays', 10);
  provider.updateField(
    'es_estReadingsJson',
    jsonEncode({'front_top': 100.6, 'middle_center': 100.8}),
  );
  provider.updateField('es_estAvg', 100.7);
  provider.updateField('es_estCv', 0.2);
  provider.updateField('esShellTemp', 20.4);
  provider.updateField('esTurningTimes', 3);
  provider.updateField(
    'esUvTrays',
    jsonEncode([
      {
        'totalEggs': 90,
        'cuticleDamage': 1,
        'washed': 2,
        'dirty': 2,
        'upsideDown': 4,
      },
    ]),
  );
  provider.updateField('esEggWeights', jsonEncode([64.0, 64.5, 65.0]));
  provider.updateField('esEggSampleSize', 3);
  provider.updateField('esEggAvgWeight', 64.5);
  provider.updateField('esEggUniformityPct', 100.0);
  provider.updateField('esEggCvPct', 0.63);
  provider.updateField('esEggBmkAge', 42);
  provider.updateField('esEggBmkWeight', 62.0);
}

void _fillChickStationInitial(AuditProvider provider) {
  provider.updateField('pasgarSampleSize', 40);
  provider.updateField('pasgarReflexes', 2);
  provider.updateField('pasgarBeak', 1);
  provider.updateField('pasgarNavel', 0);
  provider.updateField('pasgarBelly', 1);
  provider.updateField('pasgarLeg', 1);
  provider.updateField('pasgarFeatherDev', 1);
  provider.updateField('pasgarFinalScore', 96.5);
  provider.updateField(
    'yfbmEntries',
    jsonEncode([
      {'chickWeight': 42.0, 'yolkWeight': 3.9},
      {'chickWeight': 43.0, 'yolkWeight': 4.1},
    ]),
  );
  provider.updateField('yfbmAvgPct', 9.4);
  provider.updateField('yfbmCvPct', 1.1);
  provider.updateField('cvtReadingsJson', jsonEncode([103.8, 104.1, 104.0]));
  provider.updateField('cvtSampleSize', 3);
  provider.updateField('cvtAvg', 104.0);
  provider.updateField('cvtCvPct', 0.3);
  provider.updateField('pm_sampleSize', 20);
  provider.updateField('pm_collectionPoint', 'Chick basket');
  provider.updateField('pm_omphalitisCount', 1);
  provider.updateField('pm_omphalitisSeverity', 'mild');
  provider.updateField('pm_gaspingPresent', 0);
  provider.updateField('pm_gaspingType', 'none');
  provider.updateField('pm_otherDeformityCount', 1);
  provider.updateField('pm_otherDeformityText', 'curled toes');
  provider.updateField('pm_suspectedCauseManual', 'smoke baseline');
  provider.updateField('chickBmkAge', 42);
  provider.updateField('chickBmkWeight', 42.0);
  provider.updateChickWeightSampleResult(
    weightsJson: jsonEncode([42.0, 43.0, 43.5, 44.0]),
    avgWeight: 43.125,
    uniformityPct: 100.0,
    cvPct: 1.8,
  );
}

void _fillHatchAnalysisInitial(AuditProvider provider) {
  provider.updateField(
    'ebBreakoutType',
    EggBreakoutType.residueHatchDay.storageValue,
  );
  provider.updateField('haStorageDays', 6);
  provider.updateField('haTotalEggsSet', 19200);
  provider.updateField('haHatched', 17800);
  provider.updateField('haCulled', 120);
  provider.updateField('haDead', 80);
  provider.updateField('haHatchability', 92.7);
  provider.updateField('haFertility', 96.1);
  provider.updateField('haHof', 96.5);
  provider.updateField('ebStorageDays', 6);
  provider.updateField('ebBreakoutAgeDays', 294);
  provider.updateField('ebBmkAge', 42);
  provider.updateField('setterId', 'S5');
  provider.updateField('hatcherId', 'H7');
  provider.updateField(
    'ebTrayBreakoutJson',
    EggBreakoutSampleEntry.encodeList([
      EggBreakoutSampleEntry.tray(
        id: 'residue-tray-1',
        label: 'Tray 1',
        position: 'Middle',
        traySize: 150,
        breakoutType: EggBreakoutType.residueHatchDay,
        counts: const {
          'infertile': 5,
          'earlyDead': 2,
          'midDead': 1,
          'lateDead': 3,
          'externalPip': 1,
          'cracked': 1,
          'contaminated': 1,
        },
      ),
    ]),
  );
}

void _fillSetterInitial(AuditProvider provider) {
  provider.updateField('soSetterId', 'S5');
  provider.updateField('setterId', 'S5');
  provider.updateField('soBreed', _breed);
  provider.updateField('so_machineType', 'Multi');
  provider.updateField('soIncubationAge', 10);
  provider.updateField('soIncubationHours', 12);
  provider.updateField('soCo2', 2500.0);
  provider.updateField('so_setpointF', 100.2);
  provider.updateField('so_actualF', 100.4);
  provider.updateField('so_turningAngle', 42.0);
  provider.updateField('so_batchSize', 19200);
  provider.updateField('so_batchCount', 1);
  provider.updateField('so_totalEggsSet', 19200);
  provider.updateField(
    'soEstReadings',
    jsonEncode({'front': 100.4, 'middle': 100.5, 'back': 100.6}),
  );
  provider.updateField('soEstAvg', 100.5);
  provider.updateField('soEstCv', 0.2);
}

void _fillHatcherInitial(AuditProvider provider) {
  provider.updateField('hoHatcherId', 'H7');
  provider.updateField('hatcherId', 'H7');
  provider.updateField('hoBreed', _breed);
  provider.updateField('hoIncubationAge', 18);
  provider.updateField('hoIncubationHours', 6);
  provider.updateField('hoCo2', 2800.0);
  provider.updateField('hoCvtReadings', jsonEncode([103.9, 104.1, 104.2]));
  provider.updateField('hoCvtAvg', 104.1);
  provider.updateField('hoCvtCv', 0.25);
  provider.updateField('hoChickPanting', 0);
  provider.updateField('ho_meconium', 'clean');
}

void _editEggStation(AuditProvider provider) {
  provider.updateField('esEggStorageDays', 8);
  provider.updateField('esShellTemp', 20.6);
  provider.updateField('esEggAvgWeight', 63.2);
}

void _editChickStation(AuditProvider provider) {
  provider.updateField('pasgarFinalScore', 97.2);
  provider.updateField('cvtAvg', 103.8);
  provider.updateChickWeightSampleResult(
    weightsJson: jsonEncode([43.0, 43.5, 44.0, 44.5]),
    avgWeight: 43.75,
    uniformityPct: 100.0,
    cvPct: 1.3,
  );
}

void _editHatchAnalysis(AuditProvider provider) {
  provider.updateField('haHatched', 17900);
  provider.updateField('haHatchability', 93.1);
  provider.updateField('haFertility', 96.4);
}

void _editSetter(AuditProvider provider) {
  provider.updateField('soCo2', 2600.0);
  provider.updateField('soEstAvg', 100.8);
}

void _editHatcher(AuditProvider provider) {
  provider.updateField('hoCvtAvg', 103.9);
  provider.updateField('ho_meconium', 'none');
}

Future<void> _expectInitialPanelValues() async {
  expect((await _singleRow('egg_storage'))['storageDays'], 6);
  expect((await _singleRow('egg_storage'))['upsideDownCount'], 3);
  expect((await _singleRow('egg_quality'))['eggAvgWeight'], 62.5);
  expect((await _singleRow('chick_pasgar'))['finalScore'], 96.5);
  expect((await _singleRow('chick_cvt'))['avgTemp'], 104.0);
  expect((await _singleRow('chick_weights'))['avgWeight'], 43.125);
  expect((await _singleRow('residue_breakout'))['hatchabilityPct'], 92.7);
  expect((await _singleRow('setter_optimizing'))['estAvg'], 100.5);
  expect((await _singleRow('hatcher_optimizing'))['cvtAvg'], 104.1);
}

Future<void> _expectEditedPanelValues() async {
  expect((await _singleRow('egg_storage'))['storageDays'], 8);
  expect((await _singleRow('egg_storage'))['shellTemp'], 20.6);
  expect((await _singleRow('egg_quality'))['eggAvgWeight'], 63.2);
  expect((await _singleRow('chick_pasgar'))['finalScore'], 97.2);
  expect((await _singleRow('chick_cvt'))['avgTemp'], 103.8);
  expect((await _singleRow('chick_weights'))['avgWeight'], 43.75);
  expect((await _singleRow('residue_breakout'))['hatchedCount'], 17900);
  expect((await _singleRow('residue_breakout'))['hatchabilityPct'], 93.2);
  expect((await _singleRow('setter_optimizing'))['co2Ppm'], 2600.0);
  expect((await _singleRow('setter_optimizing'))['estAvg'], 100.8);
  expect((await _singleRow('hatcher_optimizing'))['cvtAvg'], 103.9);
  expect((await _singleRow('hatcher_optimizing'))['meconium'], 'none');
}

Future<void> _expectPoolRowsPerPanel() async {
  for (final table in _poolWorkflowPanels) {
    final rows = await _rows(table);
    expect(rows, hasLength(1), reason: table);
    expect(rows.single['mode'], 'pool', reason: table);
    expect(rows.single['scopeType'], 'pool', reason: table);
  }
  expect(await _rows('fresh_egg_breakout'), isEmpty);
  expect(await _rows('candled_egg_breakout'), isEmpty);
}

Future<void> _expectNoLegacyAuditOrSampleTables() async {
  final tables = await _tableNames();
  for (final table in _legacyTables) {
    expect(tables, isNot(contains(table)), reason: table);
  }
  expect(
    tables.where((table) => table.endsWith('_samples')),
    isEmpty,
    reason: 'panel child sample tables must not exist after the hard cutover',
  );
}

Future<void> _expectDashboardLoadsFromPanelTables() async {
  final tables = await _tableNames();
  expect(tables, isNot(contains('audits')));

  final panelDashboard = PanelDashboardRepository();
  final filteredEggTrend = await panelDashboard.getEggStorageTrend(
    DashboardFilter(customerId: _customerId),
  );
  expect(filteredEggTrend?.single.avgWeightG, 63.2);
  final estEvidence = await panelDashboard.getLatestEggStorageEstEvidence(
    DashboardFilter(customerId: _customerId),
  );
  expect(
    estEvidence?.points.where((point) => point.readingC != null),
    isNotEmpty,
  );

  final dashboard = DashboardProvider();
  await dashboard.init();
  await dashboard.setCustomer(_customerId);

  expect(dashboard.eggStorageLatest?.avgWeightG, 63.2);
  expect(dashboard.chickWeightLatest?.avgWeightG, 43.75);
  expect(dashboard.pasgarAvg?.score, 97.2);
  expect(dashboard.cvtAvg?.avgTempF, 103.8);
  expect(dashboard.hatchAnalysisAvg?.hatchabilityPct, 93.2);
  expect(dashboard.availableSetterIds, contains('S5'));
  expect(dashboard.availableHatcherIds, contains('H7'));
  expect(dashboard.setterComparisons.single.estAvgF, 100.8);
  expect(dashboard.hatcherComparisons.single.cvtAvgF, 103.9);
  expect(
    dashboard.visitSessions.map((summary) => summary.session.id),
    contains(_sessionId),
  );

  dashboard.dispose();
}

Future<Map<String, List<Map<String, dynamic>>>> _rowsByPanelForStation(
  String stationKey,
) async {
  final rowsByPanel = <String, List<Map<String, dynamic>>>{};
  for (final table in _panelTablesForStation(stationKey)) {
    rowsByPanel[table] = await _rows(table);
  }
  return rowsByPanel;
}

List<AuditModel> _auditDraftsFromPanelRows(
  String stationKey,
  Map<String, List<Map<String, dynamic>>> rowsByPanel,
) {
  final grouped = <int, List<({String table, Map<String, dynamic> row})>>{};
  for (final entry in rowsByPanel.entries) {
    for (final row in entry.value) {
      final index = (row['sampleIndex'] as num?)?.toInt() ?? 1;
      grouped.putIfAbsent(index, () => []).add((table: entry.key, row: row));
    }
  }
  final drafts = [
    for (final entry in grouped.entries)
      AuditModel.fromMap(
        _auditMapFromPanelRows(stationKey, entry.key, entry.value),
      ),
  ];
  drafts.sort((a, b) => a.hatchNumber.compareTo(b.hatchNumber));
  return drafts;
}

Map<String, dynamic> _auditMapFromPanelRows(
  String stationKey,
  int sampleIndex,
  List<({String table, Map<String, dynamic> row})> records,
) {
  final first = records.first.row;
  final map = <String, dynamic>{
    'id': '$_sessionId:$stationKey:$sampleIndex',
    'auditType': _auditContextFor(stationKey).auditType,
    'customerId': first['customerId'] ?? _customerId,
    'flockId': first['flockId'] ?? _flockId,
    'date': first['date'] ?? '2026-05-15',
    'status': 'completed',
    'createdBy': _createdBy,
    'createdAt':
        first['createdAt'] ?? DateTime.utc(2026, 5, 15).toIso8601String(),
    'updatedAt':
        first['updatedAt'] ?? DateTime.utc(2026, 5, 15).toIso8601String(),
    'sessionId': _sessionId,
    'sampleMode': first['mode'] == 'comparison' ? 'comparison' : 'pool',
    'compareGroupKey': first['groupKey'],
    'hatchNumber': sampleIndex,
    'notes': first['notes'],
  };

  for (final record in records) {
    _mergePanelRowIntoAuditMap(map, record.table, record.row);
  }
  return map;
}

void _mergePanelRowIntoAuditMap(
  Map<String, dynamic> map,
  String table,
  Map<String, dynamic> row,
) {
  void copy(String target, String source) {
    if (row[source] != null) map[target] = row[source];
  }

  switch (table) {
    case 'egg_storage':
      copy('esEggStorageDays', 'storageDays');
      copy('es_estReadingsJson', 'estReadingsJson');
      copy('es_estAvg', 'estAvg');
      copy('es_estCv', 'estCvPct');
      copy('esShellTemp', 'shellTemp');
      copy('esTurningTimes', 'turningTimes');
      copy('es_traySpacing', 'traySpacing');
      copy('es_coolerProximity', 'coolerProximity');
      copy('es_condensation', 'condensationPresent');
      _mergeEggTraySummary(map, {'upsideDown': row['upsideDownCount']});
      break;
    case 'egg_quality':
      _mergeEggTraySummary(map, {
        'totalEggs': row['uvTrayEggCount'],
        'cuticleDamage': row['uvCuticleDamageCount'],
        'washed': row['uvWashedCount'],
        'dirty': row['uvDirtyCount'],
      });
      copy('esEggWeights', 'eggWeightsJson');
      copy('esEggSampleSize', 'eggSampleSize');
      copy('esEggAvgWeight', 'eggAvgWeight');
      copy('esEggUniformityPct', 'eggUniformityPct');
      copy('esEggCvPct', 'eggCvPct');
      copy('esEggBmkAge', 'eggBmkAgeWeeks');
      copy('esEggBmkWeight', 'eggBmkWeight');
      break;
    case 'chick_pasgar':
      copy('pasgarSampleSize', 'sampleSize');
      copy('pasgarReflexes', 'reflexesCount');
      copy('pasgarBeak', 'beakCount');
      copy('pasgarNavel', 'navelCount');
      copy('pasgarBelly', 'bellyCount');
      copy('pasgarLeg', 'legCount');
      copy('pasgarFeatherDev', 'featherDevCount');
      copy('pasgarFinalScore', 'finalScore');
      break;
    case 'chick_weights':
      copy('chickWeights', 'weightsJson');
      copy('chickSampleSize', 'sampleSize');
      copy('chickAvgWeight', 'avgWeight');
      copy('chickUniformityPct', 'uniformityPct');
      copy('chickCvPct', 'cvPct');
      copy('chickBmkAge', 'bmkAgeWeeks');
      copy('chickBmkWeight', 'bmkWeight');
      break;
    case 'chick_yfbm':
      copy('yfbmEntries', 'entriesJson');
      copy('yfbmAvgPct', 'avgPct');
      copy('yfbmCvPct', 'cvPct');
      break;
    case 'chick_cvt':
      copy('cvtReadingsJson', 'readingsJson');
      copy('cvtSampleSize', 'sampleSize');
      copy('cvtAvg', 'avgTemp');
      copy('cvtCvPct', 'cvPct');
      break;
    case 'chick_pm':
      for (final key in _pmKeys) {
        if (row[key] != null) map['pm_$key'] = row[key];
      }
      break;
    case 'residue_breakout':
      map['ebBreakoutType'] = EggBreakoutType.residueHatchDay.storageValue;
      copy('setterId', 'setterId');
      copy('hatcherId', 'hatcherId');
      copy('haStorageDays', 'storageDays');
      copy('haTotalEggsSet', 'totalEggsSet');
      copy('haHatched', 'hatchedCount');
      copy('haCulled', 'culledCount');
      copy('haDead', 'deadCount');
      copy('haHatchability', 'hatchabilityPct');
      copy('haFertility', 'fertilityPct');
      copy('haHof', 'hofPct');
      copy('ebStorageDays', 'storageDays');
      copy('ebBreakoutAgeDays', 'bmkAgeDays');
      copy('ebBmkAge', 'bmkAgeWeeks');
      copy('ebTraySize', 'traySize');
      copy('ebInfertileCount', 'infertileCount');
      copy('ebEarlyDeadCount', 'earlyDeadCount');
      copy('ebMidDeadCount', 'midDeadCount');
      copy('ebLateDeadCount', 'lateDeadCount');
      copy('ebExternalPipCount', 'externalPipCount');
      copy('ebCrackedCount', 'crackedCount');
      copy('ebContaminatedCount', 'contaminatedCount');
      break;
    case 'setter_optimizing':
      copy('setterId', 'setterId');
      copy('soSetterId', 'setterId');
      copy('so_machineType', 'machineType');
      copy('so_setpointF', 'setpointF');
      copy('so_actualF', 'actualF');
      copy('so_batchSize', 'batchSize');
      copy('so_batchCount', 'batchCount');
      copy('so_totalEggsSet', 'totalEggsSet');
      copy('so_turningAngle', 'turningAngle');
      copy('soCo2', 'co2Ppm');
      copy('soBreed', 'estBreed');
      copy('soIncubationAge', 'incubationAgeDays');
      copy('soIncubationHours', 'incubationHours');
      copy('soEstReadings', 'estReadingsJson');
      copy('soEstAvg', 'estAvg');
      copy('soEstCv', 'estCvPct');
      break;
    case 'hatcher_optimizing':
      copy('hatcherId', 'hatcherId');
      copy('hoHatcherId', 'hatcherId');
      copy('hoIncubationAge', 'incubationAgeDays');
      copy('hoIncubationHours', 'incubationHours');
      copy('hoCo2', 'co2Ppm');
      copy('hoCvtReadings', 'cvtReadingsJson');
      copy('hoCvtAvg', 'cvtAvg');
      copy('hoCvtCv', 'cvtCvPct');
      copy('hoChickPanting', 'chickPanting');
      copy('ho_meconium', 'meconium');
      break;
  }
}

void _mergeEggTraySummary(
  Map<String, dynamic> auditMap,
  Map<String, Object?> values,
) {
  final merged = <String, Object?>{
    ..._firstEggTraySummary(auditMap['esUvTrays']),
    ...values,
  }..removeWhere((_, value) => value == null);
  if (merged.isEmpty) return;
  auditMap['esUvTrays'] = jsonEncode([merged]);
}

Map<String, Object?> _firstEggTraySummary(Object? raw) {
  if (raw == null) return const {};
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      return Map<String, Object?>.from(decoded.first as Map);
    }
  } catch (_) {
    return const {};
  }
  return const {};
}

List<StationSampleModel> _stationSamplesFromPanelRows(
  String stationKey,
  Map<String, List<Map<String, dynamic>>> rowsByPanel,
) {
  return [
    for (final entry in rowsByPanel.entries)
      for (final row in entry.value)
        _sampleFromPanelRow(stationKey, entry.key, row),
  ];
}

StationSampleModel _sampleFromPanelRow(
  String stationKey,
  String table,
  Map<String, dynamic> row,
) {
  final scopeType = row['scopeType']?.toString() ?? 'pool';
  return StationSampleModel(
    id: row['id']?.toString() ?? '$_sessionId:$table:${row['sampleIndex']}',
    auditSessionId: _sessionId,
    stationType: stationKey,
    sectorType: _sectorTypeForTable(table),
    sampleKind: _sampleKindForScope(scopeType),
    sampleMode: row['mode'] == 'comparison'
        ? StationSampleModel.sampleModeComparison
        : StationSampleModel.sampleModePooled,
    comparisonType: _comparisonTypeForScope(scopeType),
    sampleIndex: (row['sampleIndex'] as num?)?.toInt() ?? 1,
    sampleLabel: row['scopeLabel']?.toString(),
    groupKey: row['groupKey']?.toString(),
    groupLabel: row['groupLabel']?.toString(),
    houseNo: scopeType == 'house' ? row['scopeLabel']?.toString() : null,
    houseLabel: scopeType == 'house' ? row['scopeLabel']?.toString() : null,
    storageDays: (row['storageDays'] as num?)?.toInt(),
    incubationDay: ((row['incubationAgeDays'] ?? row['bmkAgeDays']) as num?)
        ?.toInt(),
    setterNo: row['setterId']?.toString(),
    hatcherNo: row['hatcherId']?.toString(),
    notes: row['notes']?.toString(),
    createdAt:
        DateTime.tryParse(row['createdAt']?.toString() ?? '') ??
        DateTime.utc(2026, 5, 15),
    updatedAt:
        DateTime.tryParse(row['updatedAt']?.toString() ?? '') ??
        DateTime.utc(2026, 5, 15),
  );
}

String _sectorTypeForTable(String table) {
  return switch (table) {
    'egg_storage' || 'egg_quality' => StationSampleModel.sectorEggQuality,
    'chick_weights' => StationSampleModel.sectorChickWeights,
    'chick_pasgar' ||
    'chick_yfbm' ||
    'chick_cvt' ||
    'chick_pm' => StationSampleModel.sectorChickQuality,
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

List<String> _panelTablesForStation(String stationKey) {
  return switch (stationKey) {
    'egg' => const ['egg_storage', 'egg_quality'],
    'chicks' => const [
      'chick_pasgar',
      'chick_weights',
      'chick_yfbm',
      'chick_cvt',
      'chick_pm',
    ],
    'hatch_analysis_egg_breakouts' => const [
      'fresh_egg_breakout',
      'candled_egg_breakout',
      'residue_breakout',
    ],
    'setters' => const ['setter_optimizing'],
    'hatchers' => const ['hatcher_optimizing'],
    _ => const [],
  };
}

Future<Map<String, dynamic>> _singleRow(String table) async {
  final rows = await _rows(table);
  expect(rows, hasLength(1), reason: table);
  return rows.single;
}

Future<List<Map<String, dynamic>>> _rows(String table) async {
  final db = await DatabaseHelper().db;
  final rows = await db.query(
    table,
    orderBy: 'sampleIndex ASC, scopeLabel ASC, createdAt ASC',
  );
  return rows.map((row) => Map<String, dynamic>.from(row)).toList();
}

Future<Set<String>> _tableNames() async {
  final db = await DatabaseHelper().db;
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((row) => row['name'] as String).toSet();
}

Future<void> _resetDatabase() async {
  await DatabaseHelper().close();
  final dbPath = p.join(
    await databaseFactory.getDatabasesPath(),
    'hatchaudit.db',
  );
  await databaseFactory.deleteDatabase(dbPath);
}

const _pmKeys = {
  'sampleSize',
  'collectionPoint',
  'omphalitisCount',
  'omphalitisSeverity',
  'gaspingPresent',
  'gaspingType',
  'otherDeformityCount',
  'otherDeformityText',
  'suspectedCauseManual',
};
