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
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/station_sample_repository.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

class MockAuditRepository extends Mock implements AuditRepository {}

class MockActivityLogRepository extends Mock implements ActivityLogRepository {}

class MockSupabaseService extends Mock implements SupabaseService {}

class MockStationSampleRepository extends Mock
    implements StationSampleRepository {}

class MockPanelSampleRepository extends Mock implements PanelSampleRepository {}

void main() {
  late MockAuditRepository auditRepository;
  late MockActivityLogRepository activityLogRepository;
  late MockSupabaseService supabaseService;
  late MockStationSampleRepository stationSampleRepository;
  late MockPanelSampleRepository panelSampleRepository;
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

    provider = AuditProvider(
      repository: auditRepository,
      activityLogRepository: activityLogRepository,
      supabaseService: supabaseService,
      stationSampleRepository: stationSampleRepository,
      panelSampleRepository: panelSampleRepository,
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
    expect(storage.values['storageDays'], 4);
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
    'comparison mode writes multiple rows inside each panel table',
    () async {
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateField('esEggStorageDays', 3);
      provider.addSample();
      provider.updateField('esEggStorageDays', 7);
      expect(provider.isCompareMode, isTrue);
      expect(provider.drafts.map((draft) => draft.sampleMode), [
        'comparison',
        'comparison',
      ]);

      expect(await provider.saveSamplesWithResult(), isTrue);

      final calls = capturedPanelCalls();
      final storageRows = calls
          .where((call) => call.panel.tableName == 'egg_storage')
          .expand((call) => call.samples)
          .toList();
      expect(storageRows, hasLength(2));
      expect(storageRows.map((row) => row.scopeType.dbValue), [
        'house',
        'house',
      ]);
      expect(storageRows.map((row) => row.sampleIndex), [1, 2]);
      verifyNever(() => auditRepository.insertAudit(any()));
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
      provider.updateField('pm_gaspingPresent', 1);
      provider.updateField('pm_gaspingType', 'mild');

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
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode([51.0, 52.0]),
        avgWeight: 51.5,
        uniformityPct: 100.0,
        cvPct: 1.4,
      );

      expect(await provider.saveSamplesWithResult(), isTrue);

      final calls = capturedPanelCalls();
      final chickQualityTables = calls
          .where(
            (call) => {
              'chick_pasgar',
              'chick_yfbm',
              'chick_cvt',
              'chick_pm',
            }.contains(call.panel.tableName),
          )
          .toList();
      expect(chickQualityTables, hasLength(8));
      expect(
        chickQualityTables
            .expand((call) => call.samples)
            .map((sample) => sample.scopeType.dbValue),
        everyElement('setter_hatcher'),
      );

      final weightCalls = calls
          .where((call) => call.panel.tableName == 'chick_weights')
          .toList();
      expect(weightCalls, hasLength(2));
      expect(weightCalls.map((call) => call.samples.single.scopeType.dbValue), [
        'house',
        'house',
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
      when(
        () => panelSampleRepository.savePanelWithSamples(
          panel: any(named: 'panel'),
          samples: any(named: 'samples'),
        ),
      ).thenThrow(Exception('database unavailable'));

      expect(await provider.saveSamplesWithResult(), isFalse);
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

      autosaveProvider.updateField('esEggStorageDays', 3);
      await tester.pump(const Duration(milliseconds: 5));
      autosaveProvider.updateField('esEggStorageDays', 8);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      final calls = capturedPanelCalls();
      final storage = calls.singleWhere(
        (call) => call.panel.tableName == 'egg_storage',
      );
      expect(storage.panel.values['storageDays'], 8);
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
      expect(storageSaves.map((call) => call.panel.values['storageDays']), [
        3,
        8,
      ]);
      expect(provider.isDirty, isFalse);
    },
  );
}
