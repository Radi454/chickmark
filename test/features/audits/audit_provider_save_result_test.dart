import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/audit_model.dart';
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
