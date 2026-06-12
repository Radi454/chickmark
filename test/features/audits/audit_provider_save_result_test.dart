import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/panel_sample_model.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/data/repositories/benchmark_lookup.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/station_sample_repository.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
import 'package:hatchaudit/features/audits/models/station_completion_validation.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

class MockAuditRepository extends Mock implements AuditRepository {}

class MockActivityLogRepository extends Mock implements ActivityLogRepository {}

class MockSupabaseService extends Mock implements SupabaseService {}

class MockStationSampleRepository extends Mock
    implements StationSampleRepository {}

class MockPanelSampleRepository extends Mock implements PanelSampleRepository {}

class MockBenchmarkLookup extends Mock implements BenchmarkLookup {}

void main() {
  late MockAuditRepository auditRepository;
  late MockActivityLogRepository activityLogRepository;
  late MockSupabaseService supabaseService;
  late MockStationSampleRepository stationSampleRepository;
  late MockPanelSampleRepository panelSampleRepository;
  late MockBenchmarkLookup benchmarkLookup;
  late AuditProvider provider;

  final user = UserModel(
    id: 'auditor-1',
    fullName: 'Auditor',
    email: 'auditor@example.com',
    role: 'auditor',
    status: 'approved',
    createdAt: DateTime(2026, 1, 1),
  );

  setUpAll(() {
    registerFallbackValue(
      AuditModel(
        id: 'fallback-audit',
        auditType: 'Egg',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime(2026, 1, 1),
        hatchNumber: 1,
        status: 'draft',
        createdBy: 'auditor-1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    registerFallbackValue(
      PanelRecord(
        id: 'fallback-panel',
        tableName: 'egg_storage',
        sessionId: 'session-1',
        customerId: 'customer-1',
        date: DateTime(2026, 1, 1),
      ),
    );
    registerFallbackValue(
      StationSampleModel(
        id: 'fallback-sample',
        auditSessionId: 'session-1',
        stationType: 'egg',
        sampleIndex: 1,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    registerFallbackValue(<PanelSampleRecord>[]);
  });

  setUp(() {
    auditRepository = MockAuditRepository();
    activityLogRepository = MockActivityLogRepository();
    supabaseService = MockSupabaseService();
    stationSampleRepository = MockStationSampleRepository();
    panelSampleRepository = MockPanelSampleRepository();
    benchmarkLookup = MockBenchmarkLookup();

    when(
      () => activityLogRepository.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => panelSampleRepository.savePanelWithSamples(
        panel: any(named: 'panel'),
        samples: any(named: 'samples'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => panelSampleRepository.deleteHierarchyRowsBySessionId(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => panelSampleRepository.deleteHierarchyRowsBySessionIdExcept(
        any(),
        any(),
        any(),
        keepHierarchyRows: any(named: 'keepHierarchyRows'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => panelSampleRepository.deleteRowsBySessionIdExcept(
        any(),
        any(),
        any(),
        keepHierarchyRows: any(named: 'keepHierarchyRows'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => panelSampleRepository.deleteRowsBySessionId(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => panelSampleRepository.deleteRowsBySessionIdForSampleIds(
        any(),
        any(),
        any(),
      ),
    ).thenAnswer((_) async {});
    when(
      () => benchmarkLookup.nearestBreakoutBenchmark(
        calculatedBmkAgeDays: any(named: 'calculatedBmkAgeDays'),
      ),
    ).thenAnswer(
      (_) async => {
        'infertilePct': 5.0,
        'early24hPct': 1.0,
        'early48hPct': 2.0,
        'bloodRingPct': 2.5,
        'blackEyePct': 1.0,
        'earlyDeadPct': 4.0,
        'midDeadPct': 1.0,
        'lateDeadPct': 2.5,
        'externalPipPct': 0.5,
        'crackedPct': 0.5,
        'contamPct': 0.5,
      },
    );

    provider = AuditProvider(
      repository: auditRepository,
      activityLogRepository: activityLogRepository,
      supabaseService: supabaseService,
      stationSampleRepository: stationSampleRepository,
      panelSampleRepository: panelSampleRepository,
      benchmarkLookup: benchmarkLookup,
      autosaveEnabled: false,
    );
    provider.initialize(
      AuditContext(
        auditType: 'Egg',
        customerId: 'customer-1',
        flockId: 'flock-1',
        flockAgeWeeks: 40,
        date: '2026-01-01',
      ),
      currentUser: user,
      sessionId: 'session-1',
      notify: false,
    );
  });

  List<({PanelRecord panel, List<PanelSampleRecord> samples})>
  capturedPanelCalls() {
    final captured = verify(
      () => panelSampleRepository.savePanelWithSamples(
        panel: captureAny(named: 'panel'),
        samples: captureAny(named: 'samples'),
      ),
    ).captured;
    return [
      for (var i = 0; i < captured.length; i += 2)
        (
          panel: captured[i] as PanelRecord,
          samples: captured[i + 1] as List<PanelSampleRecord>,
        ),
    ];
  }

  test('saveSamplesWithResult writes egg station panels only', () async {
    provider.updateField('esEggStorageDays', 4);
    provider.updateField('es_estReadingsJson', jsonEncode({'front_top': 19.4}));
    provider.updateField(
      'esUvTrays',
      jsonEncode([
        {
          'totalEggs': 100,
          'cuticleDamage': 3,
          'washed': 2,
          'dirty': 1,
          'upsideDown': 4,
        },
      ]),
    );

    expect(await provider.saveSamplesWithResult(), isTrue);

    final calls = capturedPanelCalls();
    expect(calls.map((call) => call.panel.tableName), [
      'egg_storage',
      'egg_quality',
    ]);
    final storage = calls.first.panel;
    expect(storage.sessionId, 'session-1');
    expect(storage.mode, PanelRecord.modePool);
    expect(storage.values['storagePeriodDays'], 4);
    expect(storage.values['upsideDownCount'], 4);
    expect(storage.values['upsideDownPct'], 4.0);

    final quality = calls[1].panel;
    expect(quality.values['uvTrayEggCount'], 100);
    expect(quality.values['uvAffectedCount'], 6);
    expect(quality.values['uvAffectedPct'], 6.0);
    expect(quality.values, isNot(contains('affectedCount')));
    expect(quality.values, isNot(contains('upsideDownCount')));
    expect(quality.values, containsPair('eggSampleSize', null));
    expect(quality.values, isNot(contains('sampleSize')));
    expect(calls.expand((call) => call.samples).length, 2);

    verifyNever(() => auditRepository.insertAudit(any()));
    verifyNever(() => stationSampleRepository.upsertSample(any()));
  });

  test(
    'clearStationData deletes station panel rows and resets samples',
    () async {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateSampleMetadata({'houseNo': 'H1', 'houseLabel': 'House 1'});
      provider.updateField('esEggSampleSize', 12);
      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.updateSampleMetadata({'houseNo': 'H2', 'houseLabel': 'House 2'});

      expect(provider.isCompareMode, isTrue);
      expect(provider.stationSamples, hasLength(2));

      final cleared = await provider.clearStationData('egg');

      expect(cleared, isTrue);
      expect(provider.isCompareMode, isFalse);
      expect(provider.stationSamples, hasLength(1));
      expect(provider.activeDraft.esEggSampleSize, isNull);
      expect(provider.activeDraft.sessionId, 'session-1');
      verify(
        () => panelSampleRepository.deleteRowsBySessionId(
          'egg_storage',
          'session-1',
        ),
      ).called(1);
      verify(
        () => panelSampleRepository.deleteRowsBySessionId(
          'egg_quality',
          'session-1',
        ),
      ).called(1);
    },
  );

  test('saveSamplesWithResult skips untouched egg station panels', () async {
    expect(await provider.saveSamplesWithResult(), isTrue);

    verifyNever(
      () => panelSampleRepository.savePanelWithSamples(
        panel: any(named: 'panel'),
        samples: any(named: 'samples'),
      ),
    );
  });

  test('saveSamplesWithResult skips blank egg station panels', () async {
    provider.updateField('esEggStorageDays', null);
    provider.updateField('esEggQualityStorageDays', null);

    expect(await provider.saveSamplesWithResult(), isTrue);

    verifyNever(
      () => panelSampleRepository.savePanelWithSamples(
        panel: any(named: 'panel'),
        samples: any(named: 'samples'),
      ),
    );
    expect(provider.activeStationSample.storageDays, 0);
  });

  test(
    'saveSamplesWithResult skips egg quality with only auto BMK data',
    () async {
      provider.updateField('esEggBmkAge', 38);
      provider.updateField('esEggBmkWeight', 67.0);

      expect(await provider.saveSamplesWithResult(), isTrue);

      verifyNever(
        () => panelSampleRepository.savePanelWithSamples(
          panel: any(named: 'panel'),
          samples: any(named: 'samples'),
        ),
      );
    },
  );

  test(
    'saveSamplesWithResult skips egg storage when only storage days are entered',
    () async {
      provider.updateField('esEggStorageDays', 5);

      expect(await provider.saveSamplesWithResult(), isTrue);

      verifyNever(
        () => panelSampleRepository.savePanelWithSamples(
          panel: any(named: 'panel'),
          samples: any(named: 'samples'),
        ),
      );
    },
  );

  test(
    'saveSamplesWithResult skips egg quality without weights or shell quality',
    () async {
      provider.updateField('esEggQualityStorageDays', 6);
      provider.updateField('esEggBmkAge', 38);
      provider.updateField('esEggBmkWeight', 67.0);
      provider.updateField('notes', 'Quality metadata only');

      expect(await provider.saveSamplesWithResult(), isTrue);

      verifyNever(
        () => panelSampleRepository.savePanelWithSamples(
          panel: any(named: 'panel'),
          samples: any(named: 'samples'),
        ),
      );
    },
  );

  test(
    'saveSamplesWithResult keeps storage-only tray totals out of egg quality',
    () async {
      provider.updateField('esEggStorageDays', 38);
      provider.updateField(
        'es_estReadingsJson',
        jsonEncode({'front_top': 19.4}),
      );
      provider.updateField('esEggQualityStorageDays', 38);
      provider.updateField('esEggBmkAge', 38);
      provider.updateField('esEggBmkWeight', 67.0);
      provider.updateField(
        'esUvTrays',
        jsonEncode([
          {
            'totalEggs': 150,
            'cuticleDamage': 0,
            'washed': 0,
            'dirty': 0,
            'upsideDown': 0,
          },
        ]),
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final calls = capturedPanelCalls();
      expect(calls.map((call) => call.panel.tableName), ['egg_storage']);
      expect(calls.single.panel.values['storagePeriodDays'], 38);
      expect(calls.single.panel.values['upsideDownCount'], 0);
    },
  );

  test(
    'saveSamplesWithResult saves explicit clean UV quality inspections',
    () async {
      provider.updateField(
        'esUvTrays',
        jsonEncode([
          {
            'totalEggs': 150,
            'cuticleDamage': 0,
            'washed': 0,
            'dirty': 0,
            'upsideDown': 0,
            'qualityTouched': true,
          },
        ]),
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final calls = capturedPanelCalls();
      final quality = calls.singleWhere(
        (call) => call.panel.tableName == 'egg_quality',
      );
      expect(quality.panel.values['uvTrayEggCount'], 150);
      expect(quality.panel.values['uvAffectedCount'], 0);
      expect(quality.panel.values['uvAffectedPct'], 0.0);
    },
  );

  test(
    'saveSamplesWithResult writes egg quality storage with quality data',
    () async {
      provider.updateField('esEggStorageDays', 4);
      provider.updateField(
        'es_estReadingsJson',
        jsonEncode({'front_top': 19.4}),
      );
      provider.updateField('esEggQualityStorageDays', 9);
      provider.updateField(
        'esUvTrays',
        jsonEncode([
          {
            'totalEggs': 150,
            'cuticleDamage': 0,
            'washed': 0,
            'dirty': 0,
            'upsideDown': 0,
            'qualityTouched': true,
          },
        ]),
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final calls = capturedPanelCalls();
      final storage = calls.firstWhere(
        (call) => call.panel.tableName == 'egg_storage',
      );
      final quality = calls.firstWhere(
        (call) => call.panel.tableName == 'egg_quality',
      );

      expect(storage.panel.storagePeriodDays, 4);
      expect(storage.panel.values['storagePeriodDays'], 4);
      expect(quality.panel.storagePeriodDays, 9);
      expect(quality.panel.values['storagePeriodDays'], 9);
    },
  );

  test(
    'comparison mode keeps egg storage pooled and writes egg quality rows',
    () async {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateField('esEggStorageDays', 3);
      provider.updateField(
        'es_estReadingsJson',
        jsonEncode({'front_top': 19.2}),
      );
      provider.updateField('esEggQualityStorageDays', 3);
      provider.updateField(
        'esUvTrays',
        jsonEncode([
          {
            'totalEggs': 50,
            'cuticleDamage': 1,
            'washed': 0,
            'dirty': 0,
            'upsideDown': 0,
            'qualityTouched': true,
          },
        ]),
      );
      provider.addSample();
      provider.updateSampleMetadata({'houseNo': '9'});
      provider.updateField('esEggStorageDays', 7);
      provider.updateField(
        'es_estReadingsJson',
        jsonEncode({'front_top': 19.1}),
      );
      provider.updateField('esEggQualityStorageDays', 7);
      provider.updateField(
        'esUvTrays',
        jsonEncode([
          {
            'totalEggs': 60,
            'cuticleDamage': 0,
            'washed': 1,
            'dirty': 0,
            'upsideDown': 0,
            'qualityTouched': true,
          },
        ]),
      );
      expect(provider.isCompareMode, isTrue);
      expect(provider.drafts.map((draft) => draft.sampleMode), [
        'comparison',
        'comparison',
      ]);

      expect(await provider.saveSamplesWithResult(), isTrue);

      final calls = capturedPanelCalls();
      final storageCalls = calls
          .where((call) => call.panel.tableName == 'egg_storage')
          .toList();
      expect(storageCalls, hasLength(1));
      expect(storageCalls.single.samples, hasLength(1));
      expect(storageCalls.single.samples.single.scopeType.dbValue, 'pool');
      expect(storageCalls.single.panel.storagePeriodDays, 7);

      final qualityRows = calls
          .where((call) => call.panel.tableName == 'egg_quality')
          .expand((call) => call.samples)
          .toList();
      expect(qualityRows, hasLength(2));
      expect(qualityRows.map((row) => row.scopeType.dbValue), [
        'house',
        'house',
      ]);
      expect(qualityRows.map((row) => row.scopeLabel), ['House 1', 'House 9']);
      expect(qualityRows.map((row) => row.houseId), ['H1', '9']);
      expect(qualityRows.map((row) => row.sampleIndex), [1, 2]);
      verifyNever(() => auditRepository.insertAudit(any()));
    },
  );

  test(
    'removing egg quality scope sample prunes stale scoped quality rows',
    () async {
      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.updateField('esEggWeights', jsonEncode([50.0]));
      provider.updateField('esEggSampleSize', 1);
      provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
      provider.updateSampleMetadata({'houseNo': '12'});
      provider.updateField('esEggWeights', jsonEncode([51.0]));
      provider.updateField('esEggSampleSize', 1);

      final removedSampleId = provider.activeStationSample.id;
      provider.removeActiveEggQualityScopeSample(
        StationSampleModel.sampleKindHouse,
      );

      expect(provider.sampleCount, 1);
      expect(
        provider.stationSampleMode,
        StationSampleModel.sampleModeComparison,
      );
      expect(await provider.saveSamplesWithResult(), isTrue);

      final prune = verify(
        () => panelSampleRepository.deleteHierarchyRowsBySessionIdExcept(
          'egg_quality',
          'session-1',
          captureAny(),
          keepHierarchyRows: any(named: 'keepHierarchyRows'),
        ),
      );
      prune.called(1);
      final keepIds = (prune.captured.single as Iterable<String>).toList();
      expect(keepIds, hasLength(1));
      expect(keepIds.single, contains(provider.stationSamples.single.id));
      expect(keepIds.single, isNot(contains(removedSampleId)));

      final qualityRows = capturedPanelCalls()
          .where((call) => call.panel.tableName == 'egg_quality')
          .expand((call) => call.samples)
          .toList();
      expect(qualityRows, hasLength(1));
      expect(qualityRows.single.scopeType.dbValue, 'house');
      expect(qualityRows.single.houseId, 'H');
    },
  );

  test(
    'chicks save writes house weight rows from chick weight samples only',
    () async {
      provider.initialize(
        AuditContext(
          auditType: 'Chicks',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 42,
          setterId: 'S-1',
          hatcherId: 'H-1',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );

      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateField('pasgarSampleSize', 40);
      provider.updateField('pasgarReflexes', 2);
      provider.updateField('pasgarFinalScore', 9.8);
      provider.updateField(
        'yfbmEntries',
        jsonEncode([
          {'chickWeight': 42.0, 'yolkWeight': 4.2},
        ]),
      );
      provider.updateField('yfbmAvgPct', 10.0);
      provider.updateField('cvtReadingsJson', jsonEncode([101.4, 102.2]));
      provider.updateField('cvtSampleSize', 2);
      provider.updateField('pm_sampleSize', 12);

      provider.addSample();
      provider.updateSampleMetadata({'setterNo': 'S-2', 'hatcherNo': 'H-2'});
      provider.updateField('pasgarSampleSize', 40);
      provider.updateField('pasgarReflexes', 4);
      provider.updateField('pasgarFinalScore', 9.4);

      provider.setChickWeightSampleMode(
        StationSampleModel.sampleModeComparison,
      );
      provider.switchChickWeightSample(0);
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode([41.0, 42.0, 43.0]),
        avgWeight: 42.0,
        uniformityPct: 100.0,
        cvPct: 2.4,
      );
      provider.addChickWeightSample();
      provider.updateChickWeightSampleMetadata({'houseNo': '12'});
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode([51.0, 52.0]),
        avgWeight: 51.5,
        uniformityPct: 100.0,
        cvPct: 1.4,
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final calls = capturedPanelCalls();
      final chickQualityTables = calls
          .where((call) => call.panel.tableName == 'chick_quality')
          .toList();
      expect(chickQualityTables, hasLength(2));
      expect(
        chickQualityTables
            .expand((call) => call.samples)
            .map((sample) => sample.scopeType.dbValue),
        everyElement('setter_hatcher'),
      );
      expect(chickQualityTables.map((call) => call.panel.values), [
        containsPair('pasgarFinalScore', 9.8),
        containsPair('pasgarFinalScore', 9.4),
      ]);
      expect(
        chickQualityTables.first.panel.values,
        containsPair('yfbmEntriesJson', contains('yolkWeight')),
      );
      expect(
        chickQualityTables.first.panel.values,
        containsPair('cvtSampleSize', 2),
      );
      expect(
        chickQualityTables.first.panel.values,
        containsPair('pmSampleSize', 12),
      );

      final weightCalls = calls
          .where((call) => call.panel.tableName == 'chick_weights')
          .toList();
      expect(weightCalls, hasLength(2));
      expect(weightCalls.map((call) => call.samples.single.scopeType.dbValue), [
        'house',
        'house',
      ]);
      expect(weightCalls.map((call) => call.samples.single.scopeLabel), [
        'House 1',
        'House 12',
      ]);
      expect(weightCalls.map((call) => call.samples.single.houseId), [
        'H1',
        '12',
      ]);
      expect(weightCalls.map((call) => call.samples.single.setterId), [
        null,
        null,
      ]);
      expect(weightCalls.map((call) => call.samples.single.hatcherId), [
        null,
        null,
      ]);
      expect(weightCalls.map((call) => call.panel.values['weightsJson']), [
        jsonEncode([41.0, 42.0, 43.0]),
        jsonEncode([51.0, 52.0]),
      ]);
      expect(weightCalls.map((call) => call.panel.values['sampleSize']), [
        3,
        2,
      ]);
      expect(weightCalls.map((call) => call.panel.values['avgWeight']), [
        42.0,
        51.5,
      ]);
    },
  );

  test('blank chick weight house samples are discarded', () async {
    provider.initialize(
      AuditContext(
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        flockAgeWeeks: 42,
        date: '2026-01-01',
      ),
      currentUser: user,
      sessionId: 'session-1',
      notify: false,
    );

    provider.setChickWeightSampleMode(StationSampleModel.sampleModeComparison);
    provider.switchChickWeightSample(0);
    provider.updateChickWeightSampleResult(
      weightsJson: jsonEncode([41.0, 42.0]),
      avgWeight: 41.5,
      uniformityPct: 100.0,
      cvPct: 1.2,
    );
    provider.addChickWeightSample();
    final blankSampleId = provider.activeChickWeightSample.id;
    provider.updateChickWeightSampleMetadata({'houseNo': '12'});

    expect(await provider.saveSamplesWithResult(), isTrue);

    final weightCalls = capturedPanelCalls()
        .where((call) => call.panel.tableName == 'chick_weights')
        .toList();
    expect(weightCalls, hasLength(1));
    expect(weightCalls.map((call) => call.panel.values['weightsJson']), [
      jsonEncode([41.0, 42.0]),
    ]);
    expect(weightCalls.map((call) => call.panel.values['sampleSize']), [2]);
    expect(weightCalls.map((call) => call.panel.values['avgWeight']), [41.5]);
    verify(
      () => panelSampleRepository.deleteRowsBySessionIdForSampleIds(
        'chick_weights',
        'session-1',
        any(that: contains(blankSampleId)),
      ),
    ).called(1);
  });

  test(
    'removing chick weight sample prunes stale scoped weight rows',
    () async {
      provider.initialize(
        AuditContext(
          auditType: 'Chicks',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 42,
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );

      provider.setChickWeightSampleMode(
        StationSampleModel.sampleModeComparison,
      );
      provider.switchChickWeightSample(0);
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode([41.0, 42.0]),
        avgWeight: 41.5,
        uniformityPct: 100.0,
        cvPct: 1.2,
      );
      provider.addChickWeightSample();
      provider.updateChickWeightSampleMetadata({'houseNo': '12'});
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode([51.0, 52.0]),
        avgWeight: 51.5,
        uniformityPct: 100.0,
        cvPct: 1.4,
      );

      final removedSampleId = provider.activeChickWeightSample.id;
      provider.removeActiveChickWeightSample();

      expect(provider.chickWeightSamples, hasLength(1));
      expect(await provider.saveSamplesWithResult(), isTrue);

      final prune = verify(
        () => panelSampleRepository.deleteHierarchyRowsBySessionIdExcept(
          'chick_weights',
          'session-1',
          captureAny(),
          keepHierarchyRows: any(named: 'keepHierarchyRows'),
        ),
      );
      prune.called(1);
      final keepIds = (prune.captured.single as Iterable<String>).toList();
      expect(keepIds, hasLength(1));
      expect(keepIds.single, contains(provider.chickWeightSamples.single.id));
      expect(keepIds.single, isNot(contains(removedSampleId)));

      final weightRows = capturedPanelCalls()
          .where((call) => call.panel.tableName == 'chick_weights')
          .expand((call) => call.samples)
          .toList();
      expect(weightRows, hasLength(1));
      expect(weightRows.single.houseId, 'H1');
    },
  );

  test('chicks machine scope saves entered setter hatcher rows', () async {
    provider.initialize(
      AuditContext(
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        flockAgeWeeks: 42,
        date: '2026-01-01',
      ),
      currentUser: user,
      sessionId: 'session-1',
      notify: false,
    );

    provider.addSample();
    provider.updateSampleMetadata({
      'houseNo': 'H2',
      'setterNo': '12',
      'hatcherNo': '34',
    });
    provider.switchSample(0);
    provider.updateField('pasgarSampleSize', 40);
    provider.updateField('pasgarFinalScore', 9.8);
    provider.switchSample(1);
    provider.updateField('pasgarSampleSize', 40);
    provider.updateField('pasgarFinalScore', 9.4);

    expect(provider.stationSamples.map((sample) => sample.sampleLabel), [
      'S1H1',
      'S12H34',
    ]);

    expect(await provider.saveSamplesWithResult(), isTrue);

    final qualityRows = capturedPanelCalls()
        .where((call) => call.panel.tableName == 'chick_quality')
        .expand((call) => call.samples)
        .toList();

    expect(qualityRows, hasLength(2));
    expect(qualityRows.map((row) => row.scopeType.dbValue), [
      'setter_hatcher',
      'setter_hatcher',
    ]);
    expect(qualityRows.map((row) => row.scopeLabel), ['S1/H1', '12/34']);
    expect(qualityRows.map((row) => row.setterId), ['S1', '12']);
    expect(qualityRows.map((row) => row.hatcherId), ['H1', '34']);
    expect(qualityRows.map((row) => row.houseId), [null, null]);
  });

  test(
    'removing chick quality machine sample prunes stale quality rows',
    () async {
      provider.initialize(
        AuditContext(
          auditType: 'Chicks',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 42,
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );

      provider.addSample();
      provider.switchSample(0);
      provider.updateField('pasgarSampleSize', 40);
      provider.updateField('pasgarFinalScore', 9.8);
      provider.switchSample(1);
      provider.updateSampleMetadata({'setterNo': '12', 'hatcherNo': '34'});
      provider.updateField('pasgarSampleSize', 40);
      provider.updateField('pasgarFinalScore', 9.4);

      final removedSampleId = provider.activeStationSample.id;
      provider.removeActiveSample();

      expect(provider.stationSampleMode, StationSampleModel.sampleModePooled);
      expect(await provider.saveSamplesWithResult(), isTrue);

      final prune = verify(
        () => panelSampleRepository.deleteHierarchyRowsBySessionIdExcept(
          'chick_quality',
          'session-1',
          captureAny(),
          keepHierarchyRows: any(named: 'keepHierarchyRows'),
        ),
      );
      prune.called(1);
      final keepIds = (prune.captured.single as Iterable<String>).toList();
      expect(keepIds, hasLength(1));
      expect(keepIds.single, contains(provider.stationSamples.single.id));
      expect(keepIds.single, isNot(contains(removedSampleId)));

      final qualityRows = capturedPanelCalls()
          .where((call) => call.panel.tableName == 'chick_quality')
          .expand((call) => call.samples)
          .toList();
      expect(qualityRows, hasLength(1));
      expect(qualityRows.single.scopeType.dbValue, 'pool');
      expect(qualityRows.single.setterId, isNull);
      expect(qualityRows.single.hatcherId, isNull);
    },
  );

  test(
    'removing the last hatcher comparison sample saves the hatcher as pooled',
    () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatchers',
          customerId: 'customer-1',
          flockId: 'flock-1',
          hatcherId: '1',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );

      provider.updateField('hoHatcherId', 'HX-QA-TDD');
      provider.addSample();
      expect(provider.stationSamples, hasLength(2));
      expect(
        provider.stationSampleMode,
        StationSampleModel.sampleModeComparison,
      );

      provider.removeActiveSample();
      expect(provider.stationSamples, hasLength(1));
      expect(provider.sampleMode, 'pool');
      expect(provider.stationSampleMode, StationSampleModel.sampleModePooled);
      expect(provider.activeStationSample.comparisonType, isNull);
      expect(provider.activeStationSample.groupKey, isNull);
      expect(provider.activeStationSample.groupLabel, isNull);
      expect(provider.activeStationSample.hatcherNo, 'HX-QA-TDD');

      expect(await provider.saveSamplesWithResult(), isTrue);

      final calls = capturedPanelCalls();
      expect(calls, hasLength(1));
      final hatcher = calls.single;
      expect(hatcher.panel.tableName, 'hatcher_optimizing');
      expect(hatcher.panel.mode, PanelRecord.modePool);
      expect(hatcher.panel.scopeType.dbValue, 'pool');
      expect(hatcher.samples.single.scopeType.dbValue, 'pool');
      final rawJson =
          jsonDecode(hatcher.samples.single.rawJson!) as Map<String, dynamic>;
      expect(rawJson['sampleMode'], StationSampleModel.sampleModePooled);
      expect(rawJson['comparisonType'], isNull);
      expect(rawJson['groupKey'], isNull);
      expect(rawJson['groupLabel'], isNull);
      expect(rawJson['hatcherNo'], 'HX-QA-TDD');
    },
  );

  test(
    'saveSamplesWithResult returns false when panel persistence fails',
    () async {
      provider.updateField('esEggStorageDays', 4);
      provider.updateField(
        'es_estReadingsJson',
        jsonEncode({'front_top': 19.4}),
      );
      when(
        () => panelSampleRepository.savePanelWithSamples(
          panel: any(named: 'panel'),
          samples: any(named: 'samples'),
        ),
      ).thenThrow(Exception('database unavailable'));

      expect(await provider.saveSamplesWithResult(), isFalse);
      expect(
        provider.validateStationCompletion('egg').status,
        StationCompletionStatus.failed,
      );
    },
  );

  test(
    'hatch breakout save scopes panel row values to active breakout type',
    () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatch Analysis & Egg Breakouts',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField(
        'ebTrayBreakoutJson',
        EggBreakoutSampleEntry.encodeList([
          EggBreakoutSampleEntry.tray(
            id: 'fresh-tray',
            label: 'Fresh tray',
            traySize: 30,
            breakoutType: EggBreakoutType.freshEggBreakout,
            counts: const {'infertile': 3, 'early24h': 2},
          ),
          EggBreakoutSampleEntry.tray(
            id: 'residue-tray',
            label: 'Residue tray',
            traySize: 150,
            breakoutType: EggBreakoutType.residueHatchDay,
            counts: const {'infertile': 15, 'earlyDead': 12},
          ),
        ]),
      );
      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.residueHatchDay.storageValue,
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final calls = capturedPanelCalls();
      final residue = calls.singleWhere(
        (call) => call.panel.tableName == 'residue_breakout',
      );
      expect(residue.panel.values['traySize'], 150);
      expect(residue.panel.values['infertileCount'], 15);
      expect(residue.panel.values['earlyDeadCount'], 12);
      expect(residue.panel.values['infertilePct'], 10.0);
      expect(residue.panel.values['earlyDeadPct'], 8.0);
    },
  );

  test(
    'hatch candled breakout save scopes position to candled samples',
    () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatch Analysis & Egg Breakouts',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField(
        'ebTrayBreakoutJson',
        EggBreakoutSampleEntry.encodeList([
          EggBreakoutSampleEntry.tray(
            id: 'residue-tray',
            label: 'Residue tray',
            position: 'top',
            traySize: 150,
            breakoutType: EggBreakoutType.residueHatchDay,
            counts: const {'infertile': 15},
          ),
          EggBreakoutSampleEntry.tray(
            id: 'candled-tray',
            label: 'Candled tray',
            position: 'random',
            traySize: 150,
            breakoutType: EggBreakoutType.candledEggBreakout,
            counts: const {'infertile': 11, 'blackEye': 2},
          ),
        ]),
      );
      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.candledEggBreakout.storageValue,
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final calls = capturedPanelCalls();
      final candled = calls.singleWhere(
        (call) => call.panel.tableName == 'candled_egg_breakout',
      );
      expect(candled.panel.values['position'], 'random');
      expect(candled.panel.values['traySize'], 150);
      expect(candled.panel.values['infertileCount'], 11);
      expect(candled.panel.values['blackEyeCount'], 2);
    },
  );

  test(
    'hatch breakout save treats blank storage as zero for BMK age',
    () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatch Analysis & Egg Breakouts',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('haStorageDays', null);
      provider.updateField('ebStorageDays', null);
      provider.updateField(
        'ebTrayBreakoutJson',
        EggBreakoutSampleEntry.encodeList([
          EggBreakoutSampleEntry.tray(
            id: 'residue-tray',
            label: 'Residue tray',
            traySize: 150,
            breakoutType: EggBreakoutType.residueHatchDay,
            counts: const {'infertile': 15},
          ),
        ]),
      );
      provider.updateField(
        'ebBreakoutType',
        EggBreakoutType.residueHatchDay.storageValue,
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final residue = capturedPanelCalls().singleWhere(
        (call) => call.panel.tableName == 'residue_breakout',
      );
      expect(residue.panel.storagePeriodDays, 0);
      expect(residue.panel.values['storagePeriodDays'], 0);
      expect(residue.panel.values, isNot(contains('bmkAgeDays')));
      expect(residue.panel.values['bmkAgeWeeks'], 37);
      expect(provider.activeStationSample.storageDays, 0);
    },
  );

  test('hatch breakout save writes one panel row per tray sample', () async {
    provider.initialize(
      AuditContext(
        auditType: 'Hatch Analysis & Egg Breakouts',
        customerId: 'customer-1',
        flockId: 'flock-1',
        flockAgeWeeks: 40,
        date: '2026-01-01',
      ),
      currentUser: user,
      sessionId: 'session-1',
      notify: false,
    );
    provider.updateField(
      'ebTrayBreakoutJson',
      EggBreakoutSampleEntry.encodeList([
        EggBreakoutSampleEntry.tray(
          id: 'residue-tray-1',
          label: 'Tray 1',
          position: 'top',
          traySize: 150,
          breakoutType: EggBreakoutType.residueHatchDay,
          counts: const {'infertile': 15, 'earlyDead': 9},
        ),
        EggBreakoutSampleEntry.tray(
          id: 'residue-tray-2',
          label: 'Tray 2',
          position: 'bottom',
          traySize: 150,
          breakoutType: EggBreakoutType.residueHatchDay,
          counts: const {'infertile': 30, 'earlyDead': 18},
        ),
      ]),
    );
    provider.updateField(
      'ebBreakoutType',
      EggBreakoutType.residueHatchDay.storageValue,
    );

    expect(await provider.saveSamplesWithResult(), isTrue);

    final residueRows = capturedPanelCalls()
        .where((call) => call.panel.tableName == 'residue_breakout')
        .toList();

    expect(residueRows, hasLength(2));
    expect(residueRows.map((call) => call.panel.values['traySize']), [
      150,
      150,
    ]);
    expect(residueRows.map((call) => call.panel.values['infertileCount']), [
      15,
      30,
    ]);
    expect(residueRows.map((call) => call.panel.values['earlyDeadCount']), [
      9,
      18,
    ]);
    expect(residueRows.map((call) => call.panel.values['infertilePct']), [
      10.0,
      20.0,
    ]);
    expect(residueRows.map((call) => call.panel.values['earlyDeadPct']), [
      6.0,
      12.0,
    ]);
    expect(residueRows.map((call) => call.panel.values['infertileDiffPct']), [
      5.0,
      15.0,
    ]);
    expect(residueRows.map((call) => call.panel.values['earlyDeadDiffPct']), [
      2.0,
      8.0,
    ]);
    expect(residueRows.map((call) => call.panel.values['position']), [
      'top',
      'bottom',
    ]);
    expect(residueRows.map((call) => call.samples.single.scopeType.dbValue), [
      'tray',
      'tray',
    ]);
    expect(residueRows.map((call) => call.samples.single.scopeLabel), [
      'Tray 1',
      'Tray 2',
    ]);
    expect(residueRows.map((call) => call.samples.single.sampleIndex), [1, 2]);
    expect(residueRows.map((call) => call.samples.single.houseId), [
      null,
      null,
    ]);
    expect(residueRows.map((call) => call.samples.single.setterId), [
      null,
      null,
    ]);
    expect(residueRows.map((call) => call.samples.single.hatcherId), [
      null,
      null,
    ]);
  });

  test('hatch breakout pooled tray scope saves one rollup row', () async {
    provider.initialize(
      AuditContext(
        auditType: 'Hatch Analysis & Egg Breakouts',
        customerId: 'customer-1',
        flockId: 'flock-1',
        flockAgeWeeks: 40,
        date: '2026-01-01',
      ),
      currentUser: user,
      sessionId: 'session-1',
      notify: false,
    );
    provider.updateField(
      'ebTrayBreakoutJson',
      EggBreakoutSampleEntry.encodeList([
        EggBreakoutSampleEntry.pool(
          id: 'residue-pool',
          label: 'Pool',
          traySize: 150,
          numberOfTrays: 1,
          breakoutType: EggBreakoutType.residueHatchDay,
          counts: const {'infertile': 12, 'earlyDead': 6},
        ),
      ]),
    );
    provider.updateField(
      'ebBreakoutType',
      EggBreakoutType.residueHatchDay.storageValue,
    );

    expect(await provider.saveSamplesWithResult(), isTrue);

    final residueRows = capturedPanelCalls()
        .where((call) => call.panel.tableName == 'residue_breakout')
        .toList();
    expect(residueRows, hasLength(1));
    final residue = residueRows.single;
    expect(residue.panel.mode, PanelRecord.modePool);
    expect(residue.panel.scopeType.dbValue, isNot('tray'));
    expect(residue.panel.values['traySize'], 150);
    expect(residue.panel.values['infertileCount'], 12);
    expect(residue.panel.values['earlyDeadCount'], 6);
    expect(residue.samples.single.scopeType.dbValue, isNot('tray'));
    expect(residue.samples.single.summaryJson, contains('"sampleMode":"pool"'));
  });

  testWidgets(
    'autosave persists the latest panel row without final side effects',
    (tester) async {
      final autosaveProvider = AuditProvider(
        repository: auditRepository,
        activityLogRepository: activityLogRepository,
        supabaseService: supabaseService,
        stationSampleRepository: stationSampleRepository,
        panelSampleRepository: panelSampleRepository,
        autosaveDebounceDuration: const Duration(milliseconds: 10),
      );
      autosaveProvider.initialize(
        AuditContext(
          auditType: 'Egg',
          customerId: 'customer-1',
          flockId: 'flock-1',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );

      autosaveProvider.updateField(
        'es_estReadingsJson',
        jsonEncode({'front_top': 19.4}),
      );
      autosaveProvider.updateField('esEggStorageDays', 3);
      await tester.pump(const Duration(milliseconds: 5));
      autosaveProvider.updateField('esEggStorageDays', 8);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      final calls = capturedPanelCalls();
      final storage = calls.singleWhere(
        (call) => call.panel.tableName == 'egg_storage',
      );
      expect(storage.panel.values['storagePeriodDays'], 8);
      expect(autosaveProvider.isDirty, isFalse);
      verifyNever(
        () => activityLogRepository.log(
          any(),
          any(),
          entityType: any(named: 'entityType'),
          entityId: any(named: 'entityId'),
          details: any(named: 'details'),
        ),
      );
    },
  );

  testWidgets(
    'edits during an in-flight autosave trigger a follow-up panel save',
    (tester) async {
      final gate = Completer<void>();
      var callCount = 0;
      when(
        () => panelSampleRepository.savePanelWithSamples(
          panel: any(named: 'panel'),
          samples: any(named: 'samples'),
        ),
      ).thenAnswer((_) async {
        callCount += 1;
        if (callCount == 1) await gate.future;
      });

      provider = AuditProvider(
        repository: auditRepository,
        activityLogRepository: activityLogRepository,
        supabaseService: supabaseService,
        stationSampleRepository: stationSampleRepository,
        panelSampleRepository: panelSampleRepository,
        autosaveDebounceDuration: const Duration(milliseconds: 10),
      );
      provider.initialize(
        AuditContext(
          auditType: 'Egg',
          customerId: 'customer-1',
          flockId: 'flock-1',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );

      provider.updateField(
        'es_estReadingsJson',
        jsonEncode({'front_top': 19.4}),
      );
      provider.updateField('esEggStorageDays', 3);
      await tester.pump(const Duration(milliseconds: 11));
      await tester.pump();
      provider.updateField('esEggStorageDays', 8);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 11));
      await tester.pump();

      final calls = capturedPanelCalls();
      final storageSaves = calls
          .where((call) => call.panel.tableName == 'egg_storage')
          .toList();
      expect(
        storageSaves.map((call) => call.panel.values['storagePeriodDays']),
        [3, 8],
      );
      expect(provider.isDirty, isFalse);
    },
  );

  group('station completion validation', () {
    test('egg notes save without completing station', () async {
      provider.updateField('notes', 'Stored near cooler wall');

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('egg').status,
        StationCompletionStatus.savedButIncomplete,
      );
    });

    test('egg storage data marks station complete', () async {
      provider.updateField(
        'es_estReadingsJson',
        jsonEncode({'front_top': 19.4}),
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('egg').status,
        StationCompletionStatus.complete,
      );
    });

    test('egg quality data marks station complete', () async {
      provider.updateField('esEggWeights', jsonEncode([52.0, 53.0]));

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('egg').status,
        StationCompletionStatus.complete,
      );
    });

    test('hatch notes save without completing station', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatch Analysis & Egg Breakouts',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('notes', 'Investigate tray labels');

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('hatch').status,
        StationCompletionStatus.savedButIncomplete,
      );
    });

    test('hatch breakout data marks station complete', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatch Analysis & Egg Breakouts',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('ebInfertileCount', 3);

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('hatch').status,
        StationCompletionStatus.complete,
      );
    });

    test('hatch result data marks station complete', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatch Analysis & Egg Breakouts',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('haHatched', 18000);

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('hatch').status,
        StationCompletionStatus.complete,
      );
    });

    test(
      'blank default setter save deletes rows and remains incomplete',
      () async {
        provider.initialize(
          AuditContext(
            auditType: 'Setters',
            customerId: 'customer-1',
            flockId: 'flock-1',
            flockAgeWeeks: 40,
            setterId: 'S5',
            date: '2026-01-01',
          ),
          currentUser: user,
          sessionId: 'session-1',
          notify: false,
        );

        expect(await provider.saveSamplesWithResult(), isTrue);

        verifyNever(
          () => panelSampleRepository.savePanelWithSamples(
            panel: any(named: 'panel'),
            samples: any(named: 'samples'),
          ),
        );
        verify(
          () => panelSampleRepository.deleteRowsBySessionId(
            'setter_optimizing',
            'session-1',
          ),
        ).called(1);
        expect(
          provider.validateStationCompletion('setters').status,
          StationCompletionStatus.emptyOrDiscarded,
        );
      },
    );

    test('setter direct incubation age marks station complete', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Setters',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          setterId: 'S5',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('soIncubationAge', 2);

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('setters').status,
        StationCompletionStatus.complete,
      );
    });

    test('setter direct incubation hours marks station complete', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Setters',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          setterId: 'S5',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('soIncubationHours', 6);

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('setters').status,
        StationCompletionStatus.complete,
      );
    });

    test('setter setpoint marks station complete', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Setters',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          setterId: 'S5',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('so_setpointF', 99.8);

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('setters').status,
        StationCompletionStatus.complete,
      );
    });

    test('hatcher CVT reading marks station complete', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatchers',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          hatcherId: 'H7',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('hoCvtReadings', jsonEncode({'front_top': 99.1}));

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('hatchers').status,
        StationCompletionStatus.complete,
      );
    });

    test('hatcher photo core data is persisted and marks complete', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatchers',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          hatcherId: 'H7',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('hoCo2Photo', '/tmp/hatcher-co2.jpg');

      expect(await provider.saveSamplesWithResult(), isTrue);

      final hatcher = capturedPanelCalls().singleWhere(
        (call) => call.panel.tableName == 'hatcher_optimizing',
      );
      expect(hatcher.panel.values['co2Photo'], '/tmp/hatcher-co2.jpg');
      expect(
        provider.validateStationCompletion('hatchers').status,
        StationCompletionStatus.complete,
      );
    });

    test('hatcher explicit no chick panting marks station complete', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatchers',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          hatcherId: 'H7',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('hoChickPanting', 0);

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('hatchers').status,
        StationCompletionStatus.complete,
      );
    });

    test('setter notes save without completing station', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Setters',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          setterId: 'S5',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('notes', 'Needs follow up');

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('setters').status,
        StationCompletionStatus.savedButIncomplete,
      );
    });

    test('hatcher transfer day saves without completing station', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatchers',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          hatcherId: 'H7',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('ho_transferDay', 19);

      expect(await provider.saveSamplesWithResult(), isTrue);

      final hatcher = capturedPanelCalls().singleWhere(
        (call) => call.panel.tableName == 'hatcher_optimizing',
      );
      expect(hatcher.panel.values['transferDay'], 19);
      expect(
        provider.validateStationCompletion('hatchers').status,
        StationCompletionStatus.savedButIncomplete,
      );
    });

    test('blank hatcher station saves as incomplete', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Hatchers',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          hatcherId: 'H7',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      verifyNever(
        () => panelSampleRepository.savePanelWithSamples(
          panel: any(named: 'panel'),
          samples: any(named: 'samples'),
        ),
      );
      expect(
        provider.validateStationCompletion('hatchers').status,
        StationCompletionStatus.savedButIncomplete,
      );
    });

    test('chick core Pasgar data marks station complete', () async {
      provider.initialize(
        AuditContext(
          auditType: 'Chicks',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 40,
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      provider.updateField('pasgarSampleSize', 100);

      expect(await provider.saveSamplesWithResult(), isTrue);

      expect(
        provider.validateStationCompletion('chicks').status,
        StationCompletionStatus.complete,
      );
    });

    test(
      'PM photos-only data saves but chick core remains incomplete',
      () async {
        provider.initialize(
          AuditContext(
            auditType: 'Chicks',
            customerId: 'customer-1',
            flockId: 'flock-1',
            flockAgeWeeks: 40,
            date: '2026-01-01',
          ),
          currentUser: user,
          sessionId: 'session-1',
          notify: false,
        );
        provider.updateField('pm_photosJson', jsonEncode(['pm-photo.jpg']));

        expect(await provider.saveSamplesWithResult(), isTrue);

        final quality = capturedPanelCalls().singleWhere(
          (call) => call.panel.tableName == 'chick_quality',
        );
        expect(
          quality.panel.values['pmPhotosJson'],
          jsonEncode(['pm-photo.jpg']),
        );
        expect(
          provider.validateStationCompletion('chicks').status,
          StationCompletionStatus.savedButIncomplete,
        );
      },
    );

    test(
      'optional chick environment data saves but chick core remains incomplete',
      () async {
        provider.initialize(
          AuditContext(
            auditType: 'Chicks',
            customerId: 'customer-1',
            flockId: 'flock-1',
            flockAgeWeeks: 40,
            date: '2026-01-01',
          ),
          currentUser: user,
          sessionId: 'session-1',
          notify: false,
        );
        provider.updateField('cvtTopPhoto', '/tmp/cvt-top.jpg');
        provider.updateField('pm_photosJson', jsonEncode(['pm-photo.jpg']));

        expect(await provider.saveSamplesWithResult(), isTrue);

        final quality = capturedPanelCalls().singleWhere(
          (call) => call.panel.tableName == 'chick_quality',
        );
        expect(quality.panel.values['cvtTopPhoto'], '/tmp/cvt-top.jpg');
        expect(
          quality.panel.values['pmPhotosJson'],
          jsonEncode(['pm-photo.jpg']),
        );
        expect(
          provider.validateStationCompletion('chicks').status,
          StationCompletionStatus.savedButIncomplete,
        );
      },
    );
  });
}
