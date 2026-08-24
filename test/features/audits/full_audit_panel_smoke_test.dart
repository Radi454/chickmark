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
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/repositories/panel_dashboard_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
import 'package:hatchaudit/features/audits/logic/egg_station_reconstruction.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
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
  'chick_quality',
  'chick_weights',
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
      await _expectPoolRowsPerPanel(afterReopen: true);
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
    'comparison mode keeps Egg storage pooled and Egg quality multi-row',
    () async {
      final provider = _newStationProvider('egg');
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      _fillEggStationInitial(provider);

      provider.addSample();
      _fillEggStationSecondHouse(provider);

      expect(await provider.saveSamplesWithResult(), isTrue);

      final storage = await _rows('egg_storage');
      expect(storage, hasLength(1));
      expect(storage.single['house'], isNull);
      expect(storage.single['storagePeriodDays'], 10);

      final quality = await _rows('egg_quality');
      expect(quality, hasLength(2));
      expect(quality.map((row) => row['house']), ['H1', 'H2']);
      // 'mode' was never a real column (see `PanelRecord.mode`, which is
      // internal bookkeeping never written to a db column). 'scopeType' and
      // 'sampleIndex' are real v61 columns as of this plan's Phase A and are
      // now written explicitly on every saved panel row.
      expect(quality.first, isNot(contains('mode')));
      expect(quality.map((row) => row['scopeType']), ['house', 'house']);
      expect(quality.map((row) => row['sampleIndex']), [1, 2]);
      expect(quality.map((row) => row['sampleMode']), [
        'comparison',
        'comparison',
      ]);
      await _expectNoLegacyAuditOrSampleTables();
    },
  );

  test(
    'Egg comparison preserves surviving house identity, measurements, and grading after rename and removal',
    () async {
      final provider = _newStationProvider('egg');

      // Enter Egg storage in its pooled scope before opening the separate
      // per-house Egg quality comparison workflow.
      _fillEggStationInitial(provider);
      expect(provider.stationSamples, hasLength(1));
      expect(provider.isCompareMode, isFalse);

      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.updateSampleMetadata({'houseNo': 'H1', 'houseLabel': 'House 1'});
      _fillEggHouseOneQualityAndGrading(provider);

      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.updateSampleMetadata({'houseNo': 'H2', 'houseLabel': 'House 2'});
      _fillEggHouseTwoQualityAndGrading(provider);
      final houseTwoId = provider.activeStationSample.id;

      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.updateSampleMetadata({'houseNo': 'H3', 'houseLabel': 'House 3'});
      _fillEggHouseThreeQualityAndGrading(provider);
      final houseThreeId = provider.activeStationSample.id;

      expect(provider.stationSamples, hasLength(3));
      expect(provider.drafts, hasLength(3));
      expect(provider.stationSamples.map((sample) => sample.houseNo), [
        'H1',
        'H2',
        'H3',
      ]);
      expect(provider.drafts.map((draft) => draft.esEggAvgWeight), [
        55.5,
        62.25,
        70.4,
      ]);
      expect(provider.drafts.map((draft) => draft.esGradingSampleSize), [
        11,
        13,
        17,
      ]);
      expect(provider.drafts.map((draft) => draft.esGradingRejectedCount), [
        2,
        4,
        6,
      ]);

      provider.switchSample(1);
      provider.updateSampleMetadata({
        'houseNo': 'H2-renamed',
        'houseLabel': 'House 2 renamed',
      });
      provider.switchSample(0);
      provider.removeActiveEggQualityScopeSample(
        StationSampleModel.sampleKindHouse,
      );

      expect(provider.stationSamples, hasLength(2));
      expect(provider.drafts, hasLength(2));
      expect(provider.stationSamples.map((sample) => sample.id), [
        houseTwoId,
        houseThreeId,
      ]);
      expect(provider.stationSamples.map((sample) => sample.houseNo), [
        'H2-renamed',
        'H3',
      ]);
      expect(provider.drafts.map((draft) => draft.esEggAvgWeight), [
        62.25,
        70.4,
      ]);

      expect(await provider.saveSamplesWithResult(), isTrue);
      provider.dispose();

      final storageRows = await _rows('egg_storage');
      expect(storageRows, hasLength(1));
      expect(storageRows.single['house'], isNull);
      expect(storageRows.single['storagePeriodDays'], 6);

      final qualityRows = await _rows('egg_quality');
      expect(qualityRows, hasLength(2));
      expect(qualityRows.map((row) => row['id']), [houseTwoId, houseThreeId]);
      expect(qualityRows.map((row) => row['house']), ['H2-renamed', 'H3']);
      expect(qualityRows.map((row) => row['sampleIndex']), [1, 2]);
      expect(qualityRows.map((row) => row['uvTrayEggCount']), [203, 307]);
      expect(qualityRows.map((row) => row['uvCuticleDamageCount']), [11, 19]);
      expect(qualityRows.map((row) => row['uvWashedCount']), [13, 23]);
      expect(qualityRows.map((row) => row['uvDirtyCount']), [17, 29]);
      expect(qualityRows.map((row) => row['eggAvgWeight']), [62.3, 70.4]);
      expect(qualityRows.map((row) => row['gradingSampleSize']), [13, 17]);
      expect(qualityRows.map((row) => row['gradingRejectedCount']), [4, 6]);
      expect(qualityRows.map((row) => row['gradingAcceptableCount']), [9, 11]);

      final defectRows = await _rows('egg_quality_defect_counts');
      expect(defectRows, hasLength(4));
      final houseTwoDefects = defectRows
          .where((row) => row['eggQualityId'] == houseTwoId)
          .toList();
      final houseThreeDefects = defectRows
          .where((row) => row['eggQualityId'] == houseThreeId)
          .toList();
      expect(houseTwoDefects, hasLength(2));
      expect(houseThreeDefects, hasLength(2));
      expect(
        {for (final row in houseTwoDefects) row['defectCode']: row['count']},
        {'wrinkled': 8, 'toe_hole': 10},
      );
      expect(
        {for (final row in houseThreeDefects) row['defectCode']: row['count']},
        {'calcium_deposit': 12, 'elongated': 15},
      );

      final reopened = await _reopenedStationProvider('egg');
      expect(reopened.stationSamples, hasLength(2));
      expect(reopened.drafts, hasLength(2));
      expect(reopened.stationSamples.map((sample) => sample.id), [
        houseTwoId,
        houseThreeId,
      ]);
      expect(reopened.stationSamples.map((sample) => sample.houseNo), [
        'H2-renamed',
        'H3',
      ]);
      expect(reopened.drafts.map((draft) => draft.esEggAvgWeight), [
        62.3,
        70.4,
      ]);
      final reopenedHouseTwoUvTrays =
          jsonDecode(reopened.drafts.first.esUvTrays!) as List;
      final reopenedHouseThreeUvTrays =
          jsonDecode(reopened.drafts.last.esUvTrays!) as List;
      expect(reopenedHouseTwoUvTrays, hasLength(1));
      expect(reopenedHouseThreeUvTrays, hasLength(1));
      final reopenedHouseTwoUv = reopenedHouseTwoUvTrays.single as Map;
      final reopenedHouseThreeUv = reopenedHouseThreeUvTrays.single as Map;
      expect(reopenedHouseTwoUv['totalEggs'], 203);
      expect(reopenedHouseTwoUv['cuticleDamage'], 11);
      expect(reopenedHouseTwoUv['washed'], 13);
      expect(reopenedHouseTwoUv['dirty'], 17);
      expect(reopenedHouseThreeUv['totalEggs'], 307);
      expect(reopenedHouseThreeUv['cuticleDamage'], 19);
      expect(reopenedHouseThreeUv['washed'], 23);
      expect(reopenedHouseThreeUv['dirty'], 29);
      expect(reopened.drafts.map((draft) => draft.esGradingSampleSize), [
        13,
        17,
      ]);
      expect(reopened.drafts.map((draft) => draft.esGradingRejectedCount), [
        4,
        6,
      ]);
      final reopenedHouseTwoDefects =
          jsonDecode(reopened.drafts.first.esGradingDefectsJson!) as List;
      final reopenedHouseThreeDefects =
          jsonDecode(reopened.drafts.last.esGradingDefectsJson!) as List;
      expect(reopenedHouseTwoDefects, hasLength(2));
      expect(reopenedHouseThreeDefects, hasLength(2));
      expect(
        {
          for (final entry in reopenedHouseTwoDefects)
            (entry as Map)['code']: entry['count'],
        },
        {'wrinkled': 8, 'toe_hole': 10},
      );
      expect(
        {
          for (final entry in reopenedHouseThreeDefects)
            (entry as Map)['code']: entry['count'],
        },
        {'calcium_deposit': 12, 'elongated': 15},
      );
      reopened.dispose();
    },
  );

  test(
    'Chick same-scope replicas survive production reopen and save unchanged',
    () async {
      final provider = _newStationProvider('chicks');
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateSampleMetadata({'setterNo': 'S1', 'hatcherNo': 'H1'});
      provider.updateField('pasgarSampleSize', 20);
      provider.updateField('pasgarReflexes', 1);
      provider.addSample();
      provider.updateSampleMetadata({'setterNo': 'S1', 'hatcherNo': 'H1'});
      provider.updateField('pasgarSampleSize', 20);
      provider.updateField('pasgarReflexes', 2);

      provider.setChickWeightSampleMode(
        StationSampleModel.sampleModeComparison,
      );
      provider.updateChickWeightSampleMetadata({'houseNo': 'House A'});
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode([40.0]),
        avgWeight: 40,
        uniformityPct: 100,
        cvPct: 0,
      );
      provider.addChickWeightSample();
      provider.updateChickWeightSampleMetadata({'houseNo': 'House A'});
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode([41.0]),
        avgWeight: 41,
        uniformityPct: 100,
        cvPct: 0,
      );
      expect(await provider.saveSamplesWithResult(), isTrue);
      provider.dispose();

      final beforeQuality = await _rows('chick_quality');
      final beforeWeights = await _rows('chick_weights');
      expect(beforeQuality, hasLength(2));
      expect(beforeWeights, hasLength(2));

      final rowsByPanel = await _rowsByPanelForStation('chicks');
      final reconstruction = reconstructStation(
        stationKey: 'chicks',
        sessionId: _sessionId,
        context: _reconstructionContextFor('chicks'),
        rowsByPanel: rowsByPanel,
      );
      final reopened = AuditProvider(autosaveEnabled: false);
      reopened.initialize(
        _auditContextFor('chicks'),
        existingAudits: reconstruction.stationAudits,
        // Simulate older in-memory state that regenerated both quality and
        // weight draft ids while retaining the stable persisted sample key.
        existingStationSamples: [
          for (final sample in reconstruction.stationSamples)
            sample.copyWith(id: 'transient-${sample.id}'),
        ],
        readOnly: false,
        sessionId: _sessionId,
        notify: false,
      );
      expect(reopened.drafts, hasLength(2));
      expect(reopened.stationSamples, hasLength(2));
      expect(reopened.chickWeightSamples, hasLength(2));
      expect(await reopened.saveSamplesWithResult(), isTrue);
      reopened.dispose();

      expect(
        (await _rows(
          'chick_quality',
        )).map((row) => (row['id'], row['sampleKey'])).toSet(),
        beforeQuality.map((row) => (row['id'], row['sampleKey'])).toSet(),
      );
      expect(
        (await _rows(
          'chick_weights',
        )).map((row) => (row['id'], row['sampleKey'])).toSet(),
        beforeWeights.map((row) => (row['id'], row['sampleKey'])).toSet(),
      );
      final tombstones = await (await DatabaseHelper().db).query(
        'sync_tombstones',
        where: "tableName IN ('chick_quality', 'chick_weights')",
      );
      expect(tombstones, isEmpty);
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
  if (stationKey == 'egg') {
    final reconstruction = await reopenEggStation(
      await DatabaseHelper().db,
      _sessionId,
      context: _reconstructionContextFor(stationKey),
    );
    final provider = AuditProvider(autosaveEnabled: false);
    provider.initialize(
      _auditContextFor(stationKey),
      existingAudits: reconstruction.stationAudits,
      existingStationSamples: reconstruction.stationSamples,
      readOnly: false,
      sessionId: _sessionId,
      notify: false,
    );
    return provider;
  }
  final rowsByPanel = await _rowsByPanelForStation(stationKey);
  final reconstruction = stationKey == 'chicks'
      ? reconstructStation(
          stationKey: stationKey,
          sessionId: _sessionId,
          context: _reconstructionContextFor(stationKey),
          rowsByPanel: rowsByPanel,
        )
      : null;
  final provider = AuditProvider(autosaveEnabled: false);
  provider.initialize(
    _auditContextFor(stationKey),
    existingAudits:
        reconstruction?.stationAudits ??
        _auditDraftsFromPanelRows(stationKey, rowsByPanel),
    existingStationSamples:
        reconstruction?.stationSamples ??
        _stationSamplesFromPanelRows(stationKey, rowsByPanel),
    readOnly: false,
    sessionId: _sessionId,
    notify: false,
  );
  return provider;
}

AuditContextData _reconstructionContextFor(String stationKey) {
  final context = _auditContextFor(stationKey);
  return AuditContextData(
    auditType: context.auditType,
    customerId: context.customerId,
    flockId: context.flockId,
    hatcheryId: context.hatcheryId,
    sessionId: _sessionId,
    breed: context.breed,
    setterId: context.setterId,
    hatcherId: context.hatcherId,
    flockAgeWeeks: context.flockAgeWeeks,
    date: context.date,
  );
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

void _fillEggHouseOneQualityAndGrading(AuditProvider provider) {
  provider.updateField(
    'esUvTrays',
    jsonEncode([
      {'totalEggs': 101, 'cuticleDamage': 3, 'washed': 5, 'dirty': 7},
    ]),
  );
  provider.updateField('esEggWeights', jsonEncode([55.0, 55.5, 56.0]));
  provider.updateField('esEggSampleSize', 3);
  provider.updateField('esEggAvgWeight', 55.5);
  provider.updateField('esEggUniformityPct', 100.0);
  provider.updateField('esEggCvPct', 0.91);
  provider.updateField('esGradingSampleSize', 11);
  provider.updateField('esGradingRejectedCount', 2);
  provider.updateGradingCounts({'dirty': 6, 'cracked': 7});
}

void _fillEggHouseTwoQualityAndGrading(AuditProvider provider) {
  provider.updateField(
    'esUvTrays',
    jsonEncode([
      {'totalEggs': 203, 'cuticleDamage': 11, 'washed': 13, 'dirty': 17},
    ]),
  );
  provider.updateField('esEggWeights', jsonEncode([62.1, 62.2, 62.3, 62.4]));
  provider.updateField('esEggSampleSize', 4);
  provider.updateField('esEggAvgWeight', 62.25);
  provider.updateField('esEggUniformityPct', 100.0);
  provider.updateField('esEggCvPct', 0.18);
  provider.updateField('esGradingSampleSize', 13);
  provider.updateField('esGradingRejectedCount', 4);
  provider.updateGradingCounts({'wrinkled': 8, 'toe_hole': 10});
}

void _fillEggHouseThreeQualityAndGrading(AuditProvider provider) {
  provider.updateField(
    'esUvTrays',
    jsonEncode([
      {'totalEggs': 307, 'cuticleDamage': 19, 'washed': 23, 'dirty': 29},
    ]),
  );
  provider.updateField('esEggWeights', jsonEncode([70.2, 70.4, 70.6]));
  provider.updateField('esEggSampleSize', 3);
  provider.updateField('esEggAvgWeight', 70.4);
  provider.updateField('esEggUniformityPct', 100.0);
  provider.updateField('esEggCvPct', 0.29);
  provider.updateField('esGradingSampleSize', 17);
  provider.updateField('esGradingRejectedCount', 6);
  provider.updateGradingCounts({'calcium_deposit': 12, 'elongated': 15});
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
        house: 'House 1',
        setter: 'S5',
        hatcher: 'H7',
        trolley: 'T1',
        tray: 'Tray 1',
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
  provider.updateField('esEggWeights', jsonEncode([62.2, 63.2, 64.2]));
}

void _editChickStation(AuditProvider provider) {
  provider.updateField('pasgarReflexes', 5);
  provider.updateField('cvtReadingsJson', jsonEncode([103.7, 103.8, 103.9]));
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
  provider.updateField(
    'soEstReadings',
    jsonEncode({'front': 100.7, 'middle': 100.8, 'back': 100.9}),
  );
}

void _editHatcher(AuditProvider provider) {
  provider.updateField('hoCvtReadings', jsonEncode([103.8, 103.9, 104.0]));
  provider.updateField('ho_meconium', 'none');
}

Future<void> _expectInitialPanelValues() async {
  expect((await _singleRow('egg_storage'))['storagePeriodDays'], 6);
  expect((await _singleRow('egg_storage'))['upsideDownCount'], 3);
  expect((await _singleRow('egg_quality'))['eggAvgWeight'], 62.5);
  expect((await _singleRow('chick_quality'))['pasgarFinalScore'], 9.9);
  expect((await _singleRow('chick_quality'))['cvtAvgTemp'], 104.0);
  expect((await _singleRow('chick_weights'))['avgWeight'], 43.1);
  expect((await _singleRow('residue_breakout'))['hatchabilityPct'], 92.7);
  expect((await _singleRow('setter_optimizing'))['estAvg'], 100.5);
  expect((await _singleRow('hatcher_optimizing'))['cvtAvg'], 104.1);
}

Future<void> _expectEditedPanelValues() async {
  expect((await _singleRow('egg_storage'))['storagePeriodDays'], 8);
  expect((await _singleRow('egg_storage'))['estAvg'], 100.4);
  expect((await _singleRow('egg_quality'))['eggAvgWeight'], 63.2);
  expect((await _singleRow('chick_quality'))['pasgarFinalScore'], 9.8);
  expect((await _singleRow('chick_quality'))['cvtAvgTemp'], 103.8);
  expect((await _singleRow('chick_weights'))['avgWeight'], 43.8);
  expect((await _singleRow('residue_breakout'))['hatchedCount'], 17900);
  expect((await _singleRow('residue_breakout'))['hatchabilityPct'], 93.2);
  expect((await _singleRow('setter_optimizing'))['co2Ppm'], 2600.0);
  expect((await _singleRow('setter_optimizing'))['estAvg'], 100.8);
  expect((await _singleRow('hatcher_optimizing'))['cvtAvg'], 103.9);
  expect((await _singleRow('hatcher_optimizing'))['meconium'], 'none');
}

/// Expected `scopeType`/`sampleMode` for each `_poolWorkflowPanels` table's
/// single saved row, keyed by table name. `sampleIndex` is always `1` for a
/// lone pool-workflow row regardless of scope, so it isn't varied here.
///
/// Most panels stay pool-scoped/pooled throughout this test. Two exceptions:
///  * `residue_breakout` is built by a separate breakout-specific code path
///    (`AuditPanelSaveCoordinator._breakoutPanelRowsForTable`) that never
///    went through this task's `_panelRecordForSamples` metadata merge, so
///    its `sampleMode` column is never written (stays `null`); its
///    `scopeType` was already a real column before this task and is
///    genuinely `tray`-scoped per breakout entry, pool workflow or not.
///  * `setter_optimizing`/`hatcher_optimizing` always populate their
///    `setter`/`hatcher` hierarchy column regardless of scope (see
///    `_panelSampleRecordForStationSample`'s unconditional `usesSetter`/
///    `usesHatcher` for these two tables). This test file's own reopen
///    hydration (`_scopeTypeForRow`) derives scope from that hierarchy
///    column, not from the `scopeType` column, so once a setter/hatcher
///    panel has been saved, reopened, and re-saved, it looks like a
///    comparison-mode sample even though the workflow never left "pool" —
///    a pre-existing quirk of this test's hand-rolled reopen simulation,
///    unrelated to and not fixed by this task.
const _expectedPoolWorkflowScope = {
  'egg_storage': (scopeType: 'pool', sampleMode: 'pooled'),
  'egg_quality': (scopeType: 'pool', sampleMode: 'pooled'),
  'chick_quality': (scopeType: 'pool', sampleMode: 'pooled'),
  'chick_weights': (scopeType: 'pool', sampleMode: 'pooled'),
  'residue_breakout': (scopeType: 'tray', sampleMode: null),
  'setter_optimizing': (scopeType: 'pool', sampleMode: 'pooled'),
  'hatcher_optimizing': (scopeType: 'pool', sampleMode: 'pooled'),
};

/// Overrides for [_expectedPoolWorkflowScope] once a table has been through
/// the reopen-edit-resave cycle (see the doc comment above).
const _expectedPoolWorkflowScopeAfterReopen = {
  'setter_optimizing': (scopeType: 'setter', sampleMode: 'comparison'),
  'hatcher_optimizing': (scopeType: 'hatcher', sampleMode: 'comparison'),
};

Future<void> _expectPoolRowsPerPanel({bool afterReopen = false}) async {
  for (final table in _poolWorkflowPanels) {
    final rows = await _rows(table);
    expect(rows, hasLength(1), reason: table);
    // 'mode' was never a real column (see `PanelRecord.mode`, internal
    // bookkeeping never written to a db column). 'scopeType', 'sampleIndex',
    // and 'sampleMode' are real v61 columns as of this plan's Phase A, now
    // written explicitly on every saved panel row (see
    // _expectedPoolWorkflowScope's doc comment for the two exceptions).
    expect(rows.single, isNot(contains('mode')), reason: table);
    final expected = afterReopen
        ? (_expectedPoolWorkflowScopeAfterReopen[table] ??
              _expectedPoolWorkflowScope[table]!)
        : _expectedPoolWorkflowScope[table]!;
    expect(rows.single['scopeType'], expected.scopeType, reason: table);
    expect(rows.single['sampleIndex'], 1, reason: table);
    expect(rows.single['sampleMode'], expected.sampleMode, reason: table);
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
  await dashboard.init(
    currentUser: UserModel(
      id: 'panel-smoke-admin',
      fullName: 'Panel Smoke Admin',
      email: 'panel-smoke-admin@example.com',
      role: 'admin',
      status: 'approved',
      createdAt: DateTime(2026),
    ),
  );
  await dashboard.setCustomer(_customerId);
  await dashboard.setHatchery(_hatcheryId);

  expect(dashboard.isOperationalScope, isTrue);
  expect(dashboard.eggStorageLatest, isNull);
  expect(dashboard.eggStorageEstEvidence, isNull);
  expect(dashboard.chickWeightLatest, isNull);
  expect(dashboard.pasgarAvg, isNull);
  expect(dashboard.cvtAvg, isNull);
  expect(dashboard.hatchAnalysisAvg, isNull);
  expect(dashboard.availableSetterIds, isEmpty);
  expect(dashboard.availableHatcherIds, isEmpty);
  expect(dashboard.setterComparisons, isEmpty);
  expect(dashboard.hatcherComparisons, isEmpty);
  expect(dashboard.visitSessions, isEmpty);
  expect(dashboard.goveeCaptures, isEmpty);

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
  final eggDrafts = _eggAuditDraftsFromPanelRows(stationKey, rowsByPanel);
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

List<AuditModel>? _eggAuditDraftsFromPanelRows(
  String stationKey,
  Map<String, List<Map<String, dynamic>>> rowsByPanel,
) {
  if (stationKey != 'egg') return null;
  final qualityRows =
      rowsByPanel['egg_quality'] ?? const <Map<String, dynamic>>[];
  if (qualityRows.isEmpty) return null;

  final pooledStorageRecords =
      (rowsByPanel['egg_storage'] ?? const <Map<String, dynamic>>[])
          .where((row) => !_rowHasHierarchy(row))
          .map((row) => (table: 'egg_storage', row: row))
          .toList();

  return [
    for (final entry in qualityRows.asMap().entries)
      AuditModel.fromMap(
        _auditMapFromPanelRows(stationKey, entry.key, [
          (table: 'egg_quality', row: entry.value),
          ...pooledStorageRecords,
        ]),
      ),
  ]..sort((a, b) => a.hatchNumber.compareTo(b.hatchNumber));
}

Map<String, dynamic> _auditMapFromPanelRows(
  String stationKey,
  int sampleIndex,
  List<({String table, Map<String, dynamic> row})> records,
) {
  final first = records.first.row;
  final createdAt =
      first['createdAt']?.toString() ??
      DateTime.utc(2026, 5, 15).toIso8601String();
  final updatedAt = records
      .map((record) => record.row['updatedAt']?.toString())
      .where((value) => value != null && value.isNotEmpty)
      .cast<String>()
      .fold<String>(createdAt, (latest, value) {
        return value.compareTo(latest) > 0 ? value : latest;
      });
  final mode = _rowHasHierarchy(first) ? 'comparison' : 'pool';
  final map = <String, dynamic>{
    'id': '$_sessionId:$stationKey:$sampleIndex',
    'auditType': _auditContextFor(stationKey).auditType,
    'customerId': first['customerId'] ?? _customerId,
    'flockId': first['flockId'] ?? _flockId,
    'date': first['date'] ?? '2026-05-15',
    'status': 'completed',
    'createdBy': _createdBy,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'sessionId': _sessionId,
    'sampleMode': mode,
    'compareGroupKey': _rowHasHierarchy(first)
        ? 'panel-hierarchy-$_sessionId'
        : null,
    'hatchNumber': sampleIndex + 1,
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
      copy('esEggStorageDays', 'storagePeriodDays');
      copy('es_estReadingsJson', 'estReadingsJson');
      copy('es_estAvg', 'estAvg');
      copy('es_estCv', 'estCvPct');
      copy('esTurningTimes', 'turningTimes');
      copy('es_traySpacing', 'traySpacing');
      copy('es_coolerProximity', 'coolerProximity');
      copy('es_condensation', 'condensationPresent');
      _mergeEggTraySummary(map, {'upsideDown': row['upsideDownCount']});
      break;
    case 'egg_quality':
      copy('esEggQualityStorageDays', 'storagePeriodDays');
      _mergeEggTraySummary(map, {
        'totalEggs': row['uvTrayEggCount'],
        'cuticleDamage': row['uvCuticleDamageCount'],
        'washed': row['uvWashedCount'],
        'dirty': row['uvDirtyCount'],
        'qualityTouched': true,
      });
      copy('esEggWeights', 'eggWeightsJson');
      copy('esEggSampleSize', 'eggSampleSize');
      copy('esEggAvgWeight', 'eggAvgWeight');
      copy('esEggUniformityPct', 'eggUniformityPct');
      copy('esEggCvPct', 'eggCvPct');
      copy('esEggBmkAge', 'eggBmkAgeWeeks');
      copy('esEggBmkWeight', 'eggBmkWeight');
      break;
    case 'chick_quality':
      copy('pasgarSampleSize', 'pasgarSampleSize');
      copy('pasgarReflexes', 'pasgarReflexesCount');
      copy('pasgarBeak', 'pasgarBeakCount');
      copy('pasgarNavel', 'pasgarNavelCount');
      copy('pasgarBelly', 'pasgarBellyCount');
      copy('pasgarLeg', 'pasgarLegCount');
      copy('pasgarFeatherDev', 'pasgarFeatherDevCount');
      copy('pasgarFinalScore', 'pasgarFinalScore');
      copy('yfbmEntries', 'yfbmEntriesJson');
      copy('yfbmAvgPct', 'yfbmAvgPct');
      copy('yfbmCvPct', 'yfbmCvPct');
      copy('cvtReadingsJson', 'cvtReadingsJson');
      copy('cvtSampleSize', 'cvtSampleSize');
      copy('cvtAvg', 'cvtAvgTemp');
      copy('cvtCvPct', 'cvtCvPct');
      copy('pm_sampleSize', 'pmSampleSize');
      copy('pm_collectionPoint', 'pmCollectionPoint');
      copy('pm_omphalitisCount', 'pmOmphalitisCount');
      copy('pm_omphalitisSeverity', 'pmOmphalitisSeverity');
      copy('pm_suspectedCauseManual', 'pmSuspectedCauseManual');
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
    case 'fresh_egg_breakout':
      _mergeBreakoutRow(map, row, 'freshEggBreakout');
      break;
    case 'candled_egg_breakout':
      _mergeBreakoutRow(map, row, 'candledEggBreakout');
      break;
    case 'residue_breakout':
      _mergeBreakoutRow(map, row, 'residueHatchDay');
      copy('setterId', 'setter');
      copy('hatcherId', 'hatcher');
      copy('haTotalEggsSet', 'totalEggsSet');
      copy('haHatched', 'hatchedCount');
      copy('haCulled', 'culledCount');
      copy('haDead', 'deadCount');
      copy('haHatchability', 'hatchabilityPct');
      copy('haFertility', 'fertilityPct');
      copy('haHof', 'hofPct');
      break;
    case 'setter_optimizing':
      copy('setterId', 'setter');
      copy('soSetterId', 'setter');
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
      copy('hatcherId', 'hatcher');
      copy('hoHatcherId', 'hatcher');
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

void _mergeBreakoutRow(
  Map<String, dynamic> map,
  Map<String, dynamic> row,
  String breakoutType,
) {
  void copy(String target, String source) {
    final value = row[source];
    if (value != null) map[target] = value;
  }

  map['ebBreakoutType'] = breakoutType;
  copy('ebStorageDays', 'storagePeriodDays');
  copy('haStorageDays', 'storagePeriodDays');
  copy('houseId', 'house');
  copy('setterId', 'setter');
  copy('hatcherId', 'hatcher');
  copy('ebBreakoutAgeDays', 'candlingDay');
  copy('ebBmkAge', 'bmkAgeWeeks');
  copy('ebTraySize', 'traySize');
  copy('ebInfertileCount', 'infertileCount');
  copy('ebEarlyDeadCount', 'earlyDeadCount');
  copy('ebMidDeadCount', 'midDeadCount');
  copy('ebLateDeadCount', 'lateDeadCount');
  copy('ebExternalPipCount', 'externalPipCount');
  copy('ebCrackedCount', 'crackedCount');
  copy('ebContaminatedCount', 'contaminatedCount');
  if (row['early24hCount'] != null || row['early48hCount'] != null) {
    map['ebEarlyDeadCount'] = row['early24hCount'];
    map['ebMidDeadCount'] = row['early48hCount'];
    map['ebLateDeadCount'] = row['bloodRingCount'];
  }
  _mergeBreakoutTrayEntry(map, row, breakoutType);
}

void _mergeBreakoutTrayEntry(
  Map<String, dynamic> map,
  Map<String, dynamic> row,
  String breakoutType,
) {
  final type = EggBreakoutType.fromStorageValue(breakoutType);
  final counts = <String, int>{};
  void addCount(String key, String column) {
    final value = _asInt(row[column]);
    if (value != null && value > 0) counts[key] = value;
  }

  addCount('infertile', 'infertileCount');
  if (type == EggBreakoutType.residueHatchDay) {
    addCount('earlyDead', 'earlyDeadCount');
    addCount('midDead', 'midDeadCount');
    addCount('lateDead', 'lateDeadCount');
    addCount('externalPip', 'externalPipCount');
    addCount('cracked', 'crackedCount');
    addCount('contaminated', 'contaminatedCount');
  } else {
    addCount('early24h', 'early24hCount');
    addCount('early48h', 'early48hCount');
    addCount('early72hBloodRing', 'bloodRingCount');
    if (type == EggBreakoutType.candledEggBreakout) {
      addCount('blackEye', 'blackEyeCount');
    }
  }

  final existing = EggBreakoutSampleEntry.decodeList(
    map['ebTrayBreakoutJson']?.toString(),
    fallbackBreakoutType: type,
  );
  final label = _asText(row['tray']) ?? 'Tray ${existing.length + 1}';
  final next = EggBreakoutSampleEntry.tray(
    id: _asText(row['id']) ?? 'tray-${existing.length + 1}',
    label: label,
    house: _asText(row['house']),
    setter: _asText(row['setter']),
    hatcher: _asText(row['hatcher']),
    trolley: _asText(row['trolley']),
    tray: _asText(row['tray']) ?? label,
    position: _asText(row['position']),
    traySize: _asInt(row['traySize']),
    breakoutType: type,
    counts: counts,
  );
  map['ebTrayBreakoutJson'] = EggBreakoutSampleEntry.encodeList([
    ...existing,
    next,
  ]);
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
  final primaryEntry = _stationSampleSourceRows(stationKey, rowsByPanel);
  if (primaryEntry.value.isEmpty) return const [];
  return [
    for (final entry in primaryEntry.value.asMap().entries)
      _sampleFromPanelRow(
        stationKey,
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
  String table,
  Map<String, dynamic> row, {
  required int fallbackIndex,
}) {
  final scopeType = _scopeTypeForRow(row);
  final sampleMode = _rowHasHierarchy(row)
      ? StationSampleModel.sampleModeComparison
      : StationSampleModel.sampleModePooled;
  final sampleIndex = _asInt(row['sampleIndex']) ?? fallbackIndex;
  final sampleLabel = _sampleLabelForRow(row) ?? 'Sample $sampleIndex';
  return StationSampleModel(
    id: row['id']?.toString() ?? '$_sessionId:$table:$sampleIndex',
    auditSessionId: _sessionId,
    stationType: stationKey,
    sectorType: _sectorTypeForTable(table),
    sampleKind: _sampleKindForScope(scopeType),
    sampleMode: sampleMode,
    comparisonType: _comparisonTypeForScope(scopeType),
    sampleIndex: sampleIndex,
    sampleLabel: sampleLabel,
    sampleType: _sampleTypeForTable(table),
    breakoutType: _breakoutTypeForTable(table),
    groupKey: _rowHasHierarchy(row) ? 'panel-hierarchy-$_sessionId' : null,
    groupLabel: _rowHasHierarchy(row) ? 'Hierarchy comparison' : null,
    houseNo: _asText(row['house']),
    houseLabel: _asText(row['house']),
    storageDays: _asInt(row['storagePeriodDays']),
    incubationDay: _asInt(row['incubationAgeDays'] ?? row['candlingDay']),
    setterNo: _asText(row['setter']),
    hatcherNo: _asText(row['hatcher']),
    notes: row['notes']?.toString(),
    createdAt: _parseDate(row['createdAt']) ?? DateTime.utc(2026, 5, 15),
    updatedAt: _parseDate(row['updatedAt']) ?? DateTime.utc(2026, 5, 15),
  );
}

String _panelRowIdentityKey(Map<String, dynamic> row) {
  return [
    _asText(row['house']) ?? '',
    _asText(row['setter']) ?? '',
    _asText(row['hatcher']) ?? '',
    _asText(row['trolley']) ?? '',
    _asText(row['tray']) ?? '',
    _asText(row['position']) ?? '',
  ].join('|');
}

bool _rowHasHierarchy(Map<String, dynamic> row) {
  return _asText(row['house']) != null ||
      _asText(row['setter']) != null ||
      _asText(row['hatcher']) != null ||
      _asText(row['trolley']) != null ||
      _asText(row['tray']) != null ||
      _asText(row['position']) != null;
}

String _scopeTypeForRow(Map<String, dynamic> row) {
  if (_asText(row['tray']) != null) return 'tray';
  if (_asText(row['trolley']) != null) return 'trolley';
  if (_asText(row['setter']) != null && _asText(row['hatcher']) != null) {
    return 'setter_hatcher';
  }
  if (_asText(row['setter']) != null) return 'setter';
  if (_asText(row['hatcher']) != null) return 'hatcher';
  if (_asText(row['house']) != null) return 'house';
  return 'pool';
}

String? _sampleLabelForRow(Map<String, dynamic> row) {
  final setter = _asText(row['setter']);
  final hatcher = _asText(row['hatcher']);
  if (setter != null && hatcher != null) return '$setter$hatcher';
  return _asText(row['tray']) ??
      _asText(row['trolley']) ??
      setter ??
      hatcher ??
      _asText(row['house']);
}

String _sectorTypeForTable(String table) {
  return switch (table) {
    'egg_storage' || 'egg_quality' => StationSampleModel.sectorEggQuality,
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

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

String? _asText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<String> _panelTablesForStation(String stationKey) {
  return switch (stationKey) {
    'egg' => const ['egg_storage', 'egg_quality'],
    'chicks' => const ['chick_quality', 'chick_weights'],
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
  if (table == 'chick_quality' || table == 'chick_weights') {
    return PanelSampleRepository().getRowsBySessionId(table, _sessionId);
  }
  final db = await DatabaseHelper().db;
  final tableColumns = (await db.rawQuery(
    'PRAGMA table_info($table)',
  )).map((row) => row['name']?.toString()).whereType<String>().toSet();
  final orderBy = [
    'house',
    'setter',
    'hatcher',
    'trolley',
    'tray',
    'position',
    'createdAt',
  ].where(tableColumns.contains).map((column) => '$column ASC').join(', ');
  final rows = await db.query(table, orderBy: orderBy);
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
