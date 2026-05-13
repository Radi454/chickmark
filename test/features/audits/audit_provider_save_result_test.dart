import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/sample_mode.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/data/repositories/station_sample_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

class MockAuditRepository extends Mock implements AuditRepository {}

class MockActivityLogRepository extends Mock implements ActivityLogRepository {}

class MockSupabaseService extends Mock implements SupabaseService {}

class MockStationSampleRepository extends Mock
    implements StationSampleRepository {}

void main() {
  late MockAuditRepository auditRepository;
  late MockActivityLogRepository activityLogRepository;
  late MockSupabaseService supabaseService;
  late MockStationSampleRepository stationSampleRepository;
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
        id: 'fallback',
        auditType: 'Egg',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime(2026, 1, 1),
        hatchNumber: 1,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
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
  });

  setUp(() {
    auditRepository = MockAuditRepository();
    activityLogRepository = MockActivityLogRepository();
    supabaseService = MockSupabaseService();
    stationSampleRepository = MockStationSampleRepository();

    when(
      () => activityLogRepository.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    ).thenAnswer((_) async {});
    when(() => supabaseService.syncAudit(any())).thenAnswer((_) async {});
    when(
      () => stationSampleRepository.upsertSample(any()),
    ).thenAnswer((_) async {});
    when(
      () => stationSampleRepository.deleteSample(any()),
    ).thenAnswer((_) async {});
    when(() => auditRepository.deleteAudit(any())).thenAnswer((_) async {});

    provider = AuditProvider(
      repository: auditRepository,
      activityLogRepository: activityLogRepository,
      supabaseService: supabaseService,
      stationSampleRepository: stationSampleRepository,
    );
    provider.initialize(
      AuditContext(
        auditType: 'Egg',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: '2026-01-01',
      ),
      currentUser: user,
      notify: false,
    );
  });

  AuditProvider createAutosaveProvider({
    String auditType = 'Egg',
    String? sessionId = 'session-1',
  }) {
    final autosaveProvider = AuditProvider(
      repository: auditRepository,
      activityLogRepository: activityLogRepository,
      supabaseService: supabaseService,
      stationSampleRepository: stationSampleRepository,
      autosaveDebounceDuration: const Duration(milliseconds: 10),
    );
    autosaveProvider.initialize(
      AuditContext(
        auditType: auditType,
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: '2026-01-01',
      ),
      currentUser: user,
      sessionId: sessionId,
      notify: false,
    );
    return autosaveProvider;
  }

  test('saveTabWithResult returns true after successful save', () async {
    when(
      () => auditRepository.getAuditById(any()),
    ).thenAnswer((_) async => null);
    when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

    final result = await provider.saveTabWithResult(0);

    expect(result, isTrue);
    verify(() => auditRepository.insertAudit(any())).called(1);
  });

  test('saveTabWithResult returns false when persistence fails', () async {
    when(
      () => auditRepository.getAuditById(any()),
    ).thenAnswer((_) async => null);
    when(
      () => auditRepository.insertAudit(any()),
    ).thenThrow(Exception('database unavailable'));

    final result = await provider.saveTabWithResult(0);

    expect(result, isFalse);
  });

  test(
    'saveSamplesWithResult creates one legacy audit and sample in pooled mode',
    () async {
      provider.setActiveSessionId('session-1');
      when(
        () => auditRepository.getAuditById(any()),
      ).thenAnswer((_) async => null);
      when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

      final result = await provider.saveSamplesWithResult();

      expect(result, isTrue);
      verify(() => auditRepository.insertAudit(any())).called(1);
      final captured =
          verify(
                () => stationSampleRepository.upsertSample(captureAny()),
              ).captured.single
              as StationSampleModel;
      expect(captured.auditSessionId, 'session-1');
      expect(captured.stationType, 'egg');
      expect(captured.sampleMode, StationSampleModel.sampleModePooled);
      expect(captured.legacyAuditId, provider.activeDraft.id);
    },
  );

  test(
    'saveSamplesWithResult persists compare chick weight samples independently',
    () async {
      provider = AuditProvider(
        repository: auditRepository,
        activityLogRepository: activityLogRepository,
        supabaseService: supabaseService,
        stationSampleRepository: stationSampleRepository,
      );
      provider.initialize(
        AuditContext(
          auditType: 'Chicks',
          customerId: 'customer-1',
          flockId: 'flock-1',
          date: '2026-01-01',
        ),
        currentUser: user,
        sessionId: 'session-1',
        notify: false,
      );
      when(
        () => auditRepository.getAuditById(any()),
      ).thenAnswer((_) async => null);
      when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

      provider.setChickWeightSampleMode(
        StationSampleModel.sampleModeComparison,
      );
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode([40, 42]),
        avgWeight: 41,
        uniformityPct: 100,
        cvPct: 3.4,
      );
      provider.addChickWeightSample();
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode([50, 52]),
        avgWeight: 51,
        uniformityPct: 100,
        cvPct: 2.8,
      );

      final result = await provider.saveSamplesWithResult();

      expect(result, isTrue);
      final savedSamples = verify(
        () => stationSampleRepository.upsertSample(captureAny()),
      ).captured.cast<StationSampleModel>();
      final weightSamples = savedSamples
          .where(
            (sample) =>
                sample.sectorType == StationSampleModel.sectorChickWeights,
          )
          .toList();
      expect(weightSamples, hasLength(2));
      expect(weightSamples.map((sample) => sample.sampleMode), [
        StationSampleModel.sampleModeComparison,
        StationSampleModel.sampleModeComparison,
      ]);
      expect(weightSamples.map((sample) => sample.sampleLabel), ['H1', 'H2']);
      expect(
        weightSamples.map((sample) {
          final json = jsonDecode(sample.resultSummaryJson!) as Map;
          return json['chickWeights'];
        }),
        [
          [40, 42],
          [50, 52],
        ],
      );
      expect(
        weightSamples.map((sample) {
          final json = jsonDecode(sample.resultSummaryJson!) as Map;
          return json['chickAvgWeight'];
        }),
        [41, 51],
      );
    },
  );

  test(
    'loadForEdit restores compare chick weight samples from sample records',
    () async {
      final savedAudit = AuditModel(
        id: 'audit-1',
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: DateTime(2026, 1, 1),
        hatchNumber: 1,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        sessionId: 'session-1',
        sampleMode: SampleMode.pool,
        chickWeights: jsonEncode([1, 1]),
        chickAvgWeight: 1,
      );
      final sampleOne = StationSampleModel(
        id: 'weight-sample-1',
        auditSessionId: 'session-1',
        stationType: 'chicks',
        sectorType: StationSampleModel.sectorChickWeights,
        sampleKind: StationSampleModel.sampleKindHouse,
        sampleMode: StationSampleModel.sampleModeComparison,
        comparisonType: StationSampleModel.comparisonTypeHouse,
        sampleIndex: 1,
        sampleLabel: 'H1',
        groupKey: 'weight-group-1',
        groupLabel: 'House comparison',
        resultSummaryJson: jsonEncode({
          'chickWeights': [40, 42],
          'chickAvgWeight': 41,
        }),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final sampleTwo = sampleOne.copyWith(
        id: 'weight-sample-2',
        sampleIndex: 2,
        sampleLabel: 'H2',
        resultSummaryJson: jsonEncode({
          'chickWeights': [50, 52],
          'chickAvgWeight': 51,
        }),
      );
      when(
        () => auditRepository.getAuditById('audit-1'),
      ).thenAnswer((_) async => savedAudit);
      when(
        () => auditRepository.getAuditsBySession(
          'customer-1',
          'flock-1',
          '2026-01-01',
          'Chicks',
        ),
      ).thenAnswer((_) async => [savedAudit]);
      when(
        () => stationSampleRepository.getSamplesBySessionId('session-1'),
      ).thenAnswer((_) async => [sampleOne, sampleTwo]);
      final editProvider = AuditProvider(
        repository: auditRepository,
        activityLogRepository: activityLogRepository,
        supabaseService: supabaseService,
        stationSampleRepository: stationSampleRepository,
      );

      await editProvider.loadForEdit('audit-1');

      expect(editProvider.chickWeightSamples, hasLength(2));
      expect(
        editProvider.chickWeightSamples.map((sample) => sample.sampleLabel),
        ['H1', 'H2'],
      );
      expect(
        editProvider.chickWeightSamples.map((sample) {
          final json = jsonDecode(sample.resultSummaryJson!) as Map;
          return json['chickAvgWeight'];
        }),
        [41, 51],
      );
    },
  );

  testWidgets(
    'field edits autosave one local draft after the debounce without final-save side effects',
    (tester) async {
      provider = createAutosaveProvider();
      when(
        () => auditRepository.getAuditById(any()),
      ).thenAnswer((_) async => null);
      when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

      provider.updateField('esEggStorageDays', 4);

      expect(provider.isDirty, isTrue);
      expect(provider.hasPendingAutosave, isTrue);
      await tester.pump(const Duration(milliseconds: 9));
      verifyNever(() => auditRepository.insertAudit(any()));

      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();

      expect(provider.isDirty, isFalse);
      expect(provider.hasPendingAutosave, isFalse);
      expect(provider.lastAutosavedAt, isNotNull);
      final savedAudit =
          verify(
                () => auditRepository.insertAudit(captureAny()),
              ).captured.single
              as AuditModel;
      expect(savedAudit.status, 'draft');
      verify(() => stationSampleRepository.upsertSample(any())).called(1);
      verifyNever(
        () => activityLogRepository.log(
          any(),
          any(),
          entityType: any(named: 'entityType'),
          entityId: any(named: 'entityId'),
          details: any(named: 'details'),
        ),
      );
      verifyNever(() => supabaseService.syncAudit(any()));
    },
  );

  testWidgets('rapid edits coalesce into one autosave with the latest value', (
    tester,
  ) async {
    provider = createAutosaveProvider();
    when(
      () => auditRepository.getAuditById(any()),
    ).thenAnswer((_) async => null);
    when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

    provider.updateField('esEggStorageDays', 3);
    await tester.pump(const Duration(milliseconds: 5));
    provider.updateField('esEggStorageDays', 7);
    await tester.pump(const Duration(milliseconds: 5));
    verifyNever(() => auditRepository.insertAudit(any()));

    await tester.pump(const Duration(milliseconds: 6));
    await tester.pump();

    final savedAudit =
        verify(() => auditRepository.insertAudit(captureAny())).captured.single
            as AuditModel;
    expect(savedAudit.status, 'draft');
    expect(savedAudit.esEggStorageDays, 7);
    verify(() => stationSampleRepository.upsertSample(any())).called(1);
    expect(provider.isDirty, isFalse);
  });

  testWidgets('comparison add and remove actions autosave linked samples', (
    tester,
  ) async {
    provider = createAutosaveProvider();
    when(
      () => auditRepository.getAuditById(any()),
    ).thenAnswer((_) async => null);
    when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

    provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
    provider.updateField('esEggStorageDays', 3);
    provider.addSample();
    provider.updateField('esEggStorageDays', 7);
    final removedAuditId = provider.activeDraft.id;
    final removedSampleId = provider.activeStationSample.id;

    await tester.pump(const Duration(milliseconds: 11));
    await tester.pump();

    final savedAudits = verify(
      () => auditRepository.insertAudit(captureAny()),
    ).captured.cast<AuditModel>();
    expect(savedAudits.map((audit) => audit.status), ['draft', 'draft']);
    expect(savedAudits.map((audit) => audit.esEggStorageDays), [3, 7]);
    final savedSamples = verify(
      () => stationSampleRepository.upsertSample(captureAny()),
    ).captured.cast<StationSampleModel>();
    expect(savedSamples.map((sample) => sample.sampleMode), [
      StationSampleModel.sampleModeComparison,
      StationSampleModel.sampleModeComparison,
    ]);
    clearInteractions(auditRepository);
    clearInteractions(stationSampleRepository);

    provider.removeActiveSample();
    await tester.pump(const Duration(milliseconds: 11));
    await tester.pump();

    verify(() => auditRepository.insertAudit(any())).called(1);
    verify(() => stationSampleRepository.upsertSample(any())).called(1);
    verify(
      () => stationSampleRepository.deleteSample(removedSampleId),
    ).called(1);
    verify(() => auditRepository.deleteAudit(removedAuditId)).called(1);
    verifyNever(
      () => activityLogRepository.log(
        any(),
        any(),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        details: any(named: 'details'),
      ),
    );
    verifyNever(() => supabaseService.syncAudit(any()));
  });

  testWidgets(
    'edits made during an in-flight autosave trigger a follow-up autosave',
    (tester) async {
      provider = createAutosaveProvider();
      final gate = Completer<void>();
      when(
        () => auditRepository.getAuditById(any()),
      ).thenAnswer((_) async => null);
      when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {
        await gate.future;
      });

      provider.updateField('esEggStorageDays', 3);
      await tester.pump(const Duration(milliseconds: 11));
      await tester.pump();
      expect(provider.isAutosaving, isTrue);

      provider.updateField('esEggStorageDays', 8);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 11));
      await tester.pump();

      final savedAudits = verify(
        () => auditRepository.insertAudit(captureAny()),
      ).captured.cast<AuditModel>();
      expect(savedAudits.map((audit) => audit.status), ['draft', 'draft']);
      expect(savedAudits.map((audit) => audit.esEggStorageDays), [3, 8]);
      expect(provider.isDirty, isFalse);
      expect(provider.hasPendingAutosave, isFalse);
    },
  );

  testWidgets('autosave failure keeps dirty state and exposes a warning', (
    tester,
  ) async {
    provider = createAutosaveProvider();
    when(
      () => auditRepository.getAuditById(any()),
    ).thenAnswer((_) async => null);
    when(
      () => auditRepository.insertAudit(any()),
    ).thenThrow(Exception('database unavailable'));

    provider.updateField('esEggStorageDays', 4);
    await tester.pump(const Duration(milliseconds: 11));
    await tester.pump();

    expect(provider.isDirty, isTrue);
    expect(provider.autosaveError, isNotNull);
    expect(provider.hasPendingAutosave, isTrue);
  });

  testWidgets('final save still performs log and sync side effects', (
    tester,
  ) async {
    provider = createAutosaveProvider();
    when(
      () => auditRepository.getAuditById(any()),
    ).thenAnswer((_) async => null);
    when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

    provider.updateField('esEggStorageDays', 4);
    await tester.pump(const Duration(milliseconds: 11));
    await tester.pump();
    final draftSave =
        verify(() => auditRepository.insertAudit(captureAny())).captured.single
            as AuditModel;
    when(
      () => auditRepository.getAuditById(draftSave.id),
    ).thenAnswer((_) async => draftSave);
    clearInteractions(auditRepository);
    clearInteractions(activityLogRepository);
    clearInteractions(supabaseService);

    expect(await provider.saveSamplesWithResult(tabIndex: 0), isTrue);

    final finalSave =
        verify(() => auditRepository.insertAudit(captureAny())).captured.last
            as AuditModel;
    expect(finalSave.status, 'active');
    verify(
      () => activityLogRepository.log(
        'auditor-1',
        'create',
        entityType: 'audit',
        entityId: any(named: 'entityId'),
        details: 'Egg',
      ),
    ).called(1);
    verify(() => supabaseService.syncAudit(any())).called(1);
  });

  testWidgets(
    'final save succeeds when activity logging fails after local persistence',
    (tester) async {
      provider = createAutosaveProvider();
      when(
        () => auditRepository.getAuditById(any()),
      ).thenAnswer((_) async => null);
      when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});
      when(
        () => activityLogRepository.log(
          any(),
          any(),
          entityType: any(named: 'entityType'),
          entityId: any(named: 'entityId'),
          details: any(named: 'details'),
        ),
      ).thenThrow(Exception('activity log database unavailable'));

      provider.updateField('esEggStorageDays', 4);
      await tester.pump(const Duration(milliseconds: 11));
      await tester.pump();
      clearInteractions(auditRepository);
      clearInteractions(stationSampleRepository);
      clearInteractions(supabaseService);

      final result = await provider.saveSamplesWithResult(tabIndex: 0);

      expect(result, isTrue);
      expect(provider.isDirty, isFalse);
      expect(provider.autosaveError, isNull);
      final savedAudit =
          verify(() => auditRepository.insertAudit(captureAny())).captured.last
              as AuditModel;
      expect(savedAudit.status, 'active');
      verify(() => stationSampleRepository.upsertSample(any())).called(1);
      verify(() => supabaseService.syncAudit(any())).called(1);
    },
  );

  test(
    'saveSamplesWithResult saves each comparison sample independently',
    () async {
      provider.setActiveSessionId('session-1');
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateField('esEggStorageDays', 3);
      provider.addSample();
      provider.updateField('esEggStorageDays', 7);

      when(
        () => auditRepository.getAuditById(any()),
      ).thenAnswer((_) async => null);
      when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

      final result = await provider.saveSamplesWithResult();

      expect(result, isTrue);
      verify(() => auditRepository.insertAudit(any())).called(2);
      final samples = verify(
        () => stationSampleRepository.upsertSample(captureAny()),
      ).captured.cast<StationSampleModel>();
      expect(samples.map((sample) => sample.sampleIndex), [1, 2]);
      expect(samples.map((sample) => sample.storageDays), [3, 7]);
      expect(
        samples.map((sample) => sample.legacyAuditId).toSet(),
        hasLength(2),
      );
    },
  );

  test(
    'saveSamplesWithResult reuses in-flight save to prevent duplicate rows',
    () async {
      provider.setActiveSessionId('session-1');
      final gate = Completer<void>();
      when(
        () => auditRepository.getAuditById(any()),
      ).thenAnswer((_) async => null);
      when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {
        await gate.future;
      });

      final first = provider.saveSamplesWithResult();
      final second = provider.saveSamplesWithResult();
      gate.complete();

      expect(await first, isTrue);
      expect(await second, isTrue);
      verify(() => auditRepository.insertAudit(any())).called(1);
      verify(() => stationSampleRepository.upsertSample(any())).called(1);
    },
  );

  test('re-saving uses the same legacy audit and station sample ids', () async {
    provider.setActiveSessionId('session-1');
    when(
      () => auditRepository.getAuditById(any()),
    ).thenAnswer((_) async => null);
    when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

    expect(await provider.saveSamplesWithResult(), isTrue);
    expect(await provider.saveSamplesWithResult(), isTrue);

    final audits = verify(
      () => auditRepository.insertAudit(captureAny()),
    ).captured.cast<AuditModel>();
    final samples = verify(
      () => stationSampleRepository.upsertSample(captureAny()),
    ).captured.cast<StationSampleModel>();
    expect(audits.map((audit) => audit.id).toSet(), hasLength(1));
    expect(samples.map((sample) => sample.id).toSet(), hasLength(1));
  });

  test(
    'same session saves samples with different egg production dates and BMK ages',
    () async {
      provider = AuditProvider(
        repository: auditRepository,
        activityLogRepository: activityLogRepository,
        supabaseService: supabaseService,
        stationSampleRepository: stationSampleRepository,
      );
      provider.initialize(
        AuditContext(
          auditType: 'Egg',
          customerId: 'customer-1',
          flockId: 'flock-1',
          flockAgeWeeks: 42,
          date: '2026-04-27',
        ),
        currentUser: user,
        notify: false,
      );
      provider.setActiveSessionId('session-1');
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateSampleMetadata({
        'eggProductionDate': DateTime(2026, 4, 6),
      });
      provider.addSample();
      provider.updateSampleMetadata({
        'eggProductionDate': DateTime(2026, 4, 13),
      });
      when(
        () => auditRepository.getAuditById(any()),
      ).thenAnswer((_) async => null);
      when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

      expect(await provider.saveSamplesWithResult(), isTrue);

      final samples = verify(
        () => stationSampleRepository.upsertSample(captureAny()),
      ).captured.cast<StationSampleModel>();
      expect(samples.map((sample) => sample.auditSessionId).toSet(), {
        'session-1',
      });
      expect(samples.map((sample) => sample.eggProductionDate), [
        DateTime(2026, 4, 6),
        DateTime(2026, 4, 13),
      ]);
      expect(samples.map((sample) => sample.calculatedBmkAgeDays), [273, 280]);
    },
  );

  test(
    'machine-level comparison sample saves setter and hatcher metadata',
    () async {
      provider = AuditProvider(
        repository: auditRepository,
        activityLogRepository: activityLogRepository,
        supabaseService: supabaseService,
        stationSampleRepository: stationSampleRepository,
      );
      provider.initialize(
        AuditContext(
          auditType: 'Setters',
          customerId: 'customer-1',
          flockId: 'flock-1',
          setterId: 'S1',
          hatcherId: 'H1',
          date: '2026-04-27',
        ),
        currentUser: user,
        notify: false,
      );
      provider.setActiveSessionId('session-1');
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateSampleMetadata({'setterNo': 'S1', 'hatcherNo': 'H1'});
      when(
        () => auditRepository.getAuditById(any()),
      ).thenAnswer((_) async => null);
      when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

      expect(await provider.saveSamplesWithResult(), isTrue);

      final sample =
          verify(
                () => stationSampleRepository.upsertSample(captureAny()),
              ).captured.single
              as StationSampleModel;
      expect(sample.comparisonType, StationSampleModel.comparisonTypeMachine);
      expect(sample.setterNo, 'S1');
      expect(sample.hatcherNo, 'H1');
    },
  );

  test(
    'chick save writes machine quality sample and house weight sample separately',
    () async {
      provider = AuditProvider(
        repository: auditRepository,
        activityLogRepository: activityLogRepository,
        supabaseService: supabaseService,
        stationSampleRepository: stationSampleRepository,
      );
      provider.initialize(
        AuditContext(
          auditType: 'Chicks',
          customerId: 'customer-1',
          flockId: 'flock-1',
          setterId: 'S1',
          hatcherId: 'H1',
          date: '2026-04-27',
        ),
        currentUser: user,
        notify: false,
      );
      provider.setActiveSessionId('session-1');
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.updateSampleMetadata({'setterNo': 'S1', 'hatcherNo': 'H1'});
      provider.setChickWeightSampleMode(
        StationSampleModel.sampleModeComparison,
      );
      provider.updateChickWeightSampleMetadata({'houseNo': 'H1'});
      provider.updateChickWeightSampleResult(
        weightsJson: '[40.0,41.0,null]',
        avgWeight: 40.5,
        uniformityPct: 100.0,
        cvPct: 1.7,
      );
      when(
        () => auditRepository.getAuditById(any()),
      ).thenAnswer((_) async => null);
      when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

      expect(await provider.saveSamplesWithResult(), isTrue);

      final samples = verify(
        () => stationSampleRepository.upsertSample(captureAny()),
      ).captured.cast<StationSampleModel>();
      expect(samples, hasLength(2));

      final qualitySample = samples.singleWhere(
        (sample) => sample.sectorType == StationSampleModel.sectorChickQuality,
      );
      expect(qualitySample.stationType, 'chicks');
      expect(qualitySample.sampleKind, StationSampleModel.sampleKindMachine);
      expect(
        qualitySample.comparisonType,
        StationSampleModel.comparisonTypeMachine,
      );
      expect(qualitySample.sampleLabel, 'M1');
      expect(qualitySample.groupLabel, 'Machine comparison');
      expect(qualitySample.setterNo, 'S1');
      expect(qualitySample.hatcherNo, 'H1');
      expect(qualitySample.houseNo, isNull);

      final weightSample = samples.singleWhere(
        (sample) => sample.sectorType == StationSampleModel.sectorChickWeights,
      );
      expect(weightSample.sampleKind, StationSampleModel.sampleKindHouse);
      expect(
        weightSample.comparisonType,
        StationSampleModel.comparisonTypeHouse,
      );
      expect(weightSample.sampleLabel, 'H1');
      expect(weightSample.groupLabel, 'House comparison');
      expect(weightSample.houseNo, 'H1');
      expect(weightSample.setterNo, isNull);
      expect(weightSample.hatcherNo, isNull);
      final summary =
          jsonDecode(weightSample.resultSummaryJson!) as Map<String, dynamic>;
      expect(summary['chickAvgWeight'], 40.5);
      expect(summary['chickUniformityPct'], 100.0);
      expect(summary['chickCvPct'], 1.7);
      expect(summary['chickWeights'], [40.0, 41.0, null]);
    },
  );

  test(
    'removing a saved comparison sample deletes the linked sample and legacy audit',
    () async {
      provider.setActiveSessionId('session-1');
      provider.setStationSampleMode(StationSampleModel.sampleModeComparison);
      provider.addSample();
      final removedAuditId = provider.activeDraft.id;
      final removedSampleId = provider.activeStationSample.id;
      when(
        () => auditRepository.getAuditById(any()),
      ).thenAnswer((_) async => null);
      when(() => auditRepository.insertAudit(any())).thenAnswer((_) async {});

      expect(await provider.saveSamplesWithResult(), isTrue);
      clearInteractions(auditRepository);
      clearInteractions(stationSampleRepository);

      provider.removeActiveSample();
      expect(await provider.saveSamplesWithResult(), isTrue);

      verify(() => auditRepository.insertAudit(any())).called(1);
      verify(
        () => stationSampleRepository.deleteSample(removedSampleId),
      ).called(1);
      verify(() => auditRepository.deleteAudit(removedAuditId)).called(1);
    },
  );
}
