import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/dashboard_action_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/models/sync_tombstone_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/chick_quality_observation_repository.dart';
import 'package:hatchaudit/data/repositories/dashboard_action_repository.dart';
import 'package:hatchaudit/data/repositories/egg_grading_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_machine_repository.dart';
import 'package:hatchaudit/data/repositories/lab_analysis_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/data/repositories/performance_sync_repository.dart';
import 'package:hatchaudit/data/repositories/photo_repository.dart';
import 'package:hatchaudit/data/repositories/sync_tombstone_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_report_sync_service.dart';
import 'package:hatchaudit/services/photo/photo_sync_service.dart';
import 'package:hatchaudit/services/supabase/startup_sync_service.dart';
import 'package:hatchaudit/services/supabase/sync_retry_policy.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

class _MockCustomerRepository extends Mock implements CustomerRepository {}

class _MockChickQualityObservationRepository extends Mock
    implements ChickQualityObservationRepository {}

class _MockDashboardActionRepository extends Mock
    implements DashboardActionRepository {}

class _MockEggGradingRepository extends Mock implements EggGradingRepository {}

class _MockFlockRepository extends Mock implements FlockRepository {}

class _MockHatcheryRepository extends Mock implements HatcheryRepository {}

class _MockHatcheryMachineRepository extends Mock
    implements HatcheryMachineRepository {}

class _MockLabAnalysisRepository extends Mock
    implements LabAnalysisRepository {}

class _MockActivityLogRepository extends Mock
    implements ActivityLogRepository {}

class _MockPhotoRepository extends Mock implements PhotoRepository {}

class _MockBmkRepository extends Mock implements BmkRepository {}

class _MockAuditSessionRepository extends Mock
    implements AuditSessionRepository {}

class _MockGoveeCaptureRepository extends Mock
    implements GoveeCaptureRepository {}

class _MockPanelSampleRepository extends Mock
    implements PanelSampleRepository {}

class _MockPanelSamplingStateRepository extends Mock
    implements PanelSamplingStateRepository {}

class _MockPerformanceSyncRepository extends Mock
    implements PerformanceSyncRepository {}

class _MockSyncTombstoneRepository extends Mock
    implements SyncTombstoneRepository {}

class _MockBreederReportSyncService extends Mock
    implements BreederReportSyncService {}

class _MockPhotoSyncService extends Mock implements PhotoSyncService {}

void main() {
  late _MockSupabaseService supabase;
  late _MockCustomerRepository customers;
  late _MockChickQualityObservationRepository chickObservations;
  late _MockDashboardActionRepository actions;
  late _MockEggGradingRepository eggGrading;
  late _MockFlockRepository flocks;
  late _MockHatcheryRepository hatcheries;
  late _MockHatcheryMachineRepository hatcheryMachines;
  late _MockLabAnalysisRepository labAnalysis;
  late _MockActivityLogRepository activityLog;
  late _MockPhotoRepository photos;
  late _MockBmkRepository bmk;
  late _MockAuditSessionRepository sessions;
  late _MockGoveeCaptureRepository govee;
  late _MockPanelSampleRepository panels;
  late _MockPanelSamplingStateRepository sampling;
  late _MockPerformanceSyncRepository operational;
  late _MockSyncTombstoneRepository tombstones;
  late _MockBreederReportSyncService breederReportSync;
  late _MockPhotoSyncService photoSync;
  // Retry backoff is process-local state; give every test its own policy and
  // its own controllable clock so one test's failures cannot leak into the next.
  late SyncRetryPolicy retryPolicy;
  late DateTime clock;

  setUpAll(() {
    registerFallbackValue(<Map<String, dynamic>>[]);
    registerFallbackValue(<String>[]);
    registerFallbackValue(Object());
  });

  setUp(() {
    supabase = _MockSupabaseService();
    customers = _MockCustomerRepository();
    chickObservations = _MockChickQualityObservationRepository();
    actions = _MockDashboardActionRepository();
    eggGrading = _MockEggGradingRepository();
    flocks = _MockFlockRepository();
    hatcheries = _MockHatcheryRepository();
    hatcheryMachines = _MockHatcheryMachineRepository();
    labAnalysis = _MockLabAnalysisRepository();
    activityLog = _MockActivityLogRepository();
    photos = _MockPhotoRepository();
    bmk = _MockBmkRepository();
    sessions = _MockAuditSessionRepository();
    govee = _MockGoveeCaptureRepository();
    panels = _MockPanelSampleRepository();
    sampling = _MockPanelSamplingStateRepository();
    operational = _MockPerformanceSyncRepository();
    tombstones = _MockSyncTombstoneRepository();
    breederReportSync = _MockBreederReportSyncService();
    when(() => breederReportSync.pushDirtyReportsDetailed()).thenAnswer(
      (_) async => const BreederReportSyncRunResult(
        pushedRowCount: 0,
        conflictCount: 0,
        failedReportIds: [],
      ),
    );
    photoSync = _MockPhotoSyncService();
    clock = DateTime.utc(2026, 8, 16, 9);
    retryPolicy = SyncRetryPolicy(now: () => clock);

    when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
    when(() => customers.getAllCustomers()).thenAnswer(
      (_) async => [
        CustomerModel(
          id: 'customer-1',
          name: 'Customer 1',
          createdAt: DateTime(2026, 5, 1),
          createdBy: 'tester',
        ),
      ],
    );
    when(() => hatcheries.getAllHatcheries()).thenAnswer(
      (_) async => [
        HatcheryModel(
          id: 'hatchery-1',
          customerId: 'customer-1',
          name: 'Hatchery 1',
          createdAt: DateTime(2026, 5, 1),
          createdBy: 'tester',
        ),
      ],
    );
    when(() => flocks.getAllFlocks()).thenAnswer(
      (_) async => [
        FlockModel(
          id: 'flock-1',
          customerId: 'customer-1',
          flockId: 'Flock 1',
          breed: 'Ross308',
          entryDate: DateTime(2026, 1, 1),
        ),
      ],
    );
    // Per-row dirty-tracking push for reference tables: default to nothing
    // dirty (clean rows are never pushed) unless a test overrides it.
    when(() => customers.getDirtyRows()).thenAnswer((_) async => const []);
    when(
      () => chickObservations.getDirtyRows(),
    ).thenAnswer((_) async => const []);
    when(
      () => chickObservations.getRowById(any()),
    ).thenAnswer((_) async => null);
    when(
      () => chickObservations.upsertRemoteRow(any()),
    ).thenAnswer((_) async {});
    when(
      () => chickObservations.markRowsSynced(any()),
    ).thenAnswer((_) async {});
    when(
      () => chickObservations.markRowsFailed(any(), any()),
    ).thenAnswer((_) async {});
    when(() => customers.markRowsSynced(any())).thenAnswer((_) async {});
    when(() => customers.markRowsFailed(any(), any())).thenAnswer((_) async {});
    when(
      () => customers.getRowSyncStatus(any()),
    ).thenAnswer((_) async => 'synced');
    // Dirty-tracking push for BMK operational standards (Task 3): default to
    // nothing dirty unless a test overrides it.
    when(() => bmk.getDirtyOperationalRows()).thenAnswer((_) async => const []);
    when(() => bmk.markOperationalRowsSynced(any())).thenAnswer((_) async {});
    when(
      () => bmk.markOperationalRowsFailed(any(), any()),
    ).thenAnswer((_) async {});
    when(() => hatcheries.getDirtyRows()).thenAnswer((_) async => const []);
    when(
      () => hatcheryMachines.getDirtyRows(),
    ).thenAnswer((_) async => const []);
    when(() => hatcheryMachines.markRowsSynced(any())).thenAnswer((_) async {});
    when(
      () => hatcheryMachines.markRowsFailed(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => hatcheryMachines.getRowSyncStatus(any()),
    ).thenAnswer((_) async => null);
    when(
      () => hatcheryMachines.upsertRemoteRow(any()),
    ).thenAnswer((_) async {});
    when(() => hatcheries.markRowsSynced(any())).thenAnswer((_) async {});
    when(
      () => hatcheries.markRowsFailed(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => hatcheries.getRowSyncStatus(any()),
    ).thenAnswer((_) async => 'synced');
    when(() => flocks.getDirtyRows()).thenAnswer((_) async => const []);
    when(() => flocks.markRowsSynced(any())).thenAnswer((_) async {});
    when(() => flocks.markRowsFailed(any(), any())).thenAnswer((_) async {});
    when(
      () => flocks.getRowSyncStatus(any()),
    ).thenAnswer((_) async => 'synced');
    when(() => sessions.getAllSessions(limit: any(named: 'limit'))).thenAnswer(
      (_) async => [
        AuditSessionModel(
          id: 'session-1',
          customerId: 'customer-1',
          flockId: 'flock-1',
          hatcheryId: 'hatchery-1',
          date: DateTime(2026, 5, 1),
          createdAt: DateTime(2026, 5, 1),
          updatedAt: DateTime(2026, 5, 1),
        ),
      ],
    );
    // Per-row dirty-tracking push: the service pulls only dirty sessions/panel
    // rows and confirms them synced after upload.
    when(() => sessions.getDirtySessionRows()).thenAnswer(
      (_) async => [
        AuditSessionModel(
          id: 'session-1',
          customerId: 'customer-1',
          flockId: 'flock-1',
          hatcheryId: 'hatchery-1',
          date: DateTime(2026, 5, 1),
          createdAt: DateTime(2026, 5, 1),
          updatedAt: DateTime(2026, 5, 1),
        ),
      ],
    );
    when(() => sessions.markSessionsSynced(any())).thenAnswer((_) async {});
    when(() => panels.getDirtyRows(any())).thenAnswer((invocation) async {
      final table = invocation.positionalArguments.first as String;
      if (table == 'egg_storage') {
        return [
          {
            'id': 'row-1',
            'sessionId': 'session-1',
            'customerId': 'customer-1',
            'date': '2026-05-01',
            'mode': 'pool',
            'scopeType': 'pool',
            'scopeLabel': 'Random',
            'sampleIndex': 0,
            'syncStatus': 'pending',
            'createdAt': '2026-05-01T00:00:00.000Z',
            'updatedAt': '2026-05-01T00:00:00.000Z',
          },
        ];
      }
      return const [];
    });
    when(() => panels.markRowsSynced(any(), any())).thenAnswer((_) async {});
    when(() => sampling.getDirtyRows(any())).thenAnswer((_) async => const []);
    when(() => sampling.markRowsSynced(any(), any())).thenAnswer((_) async {});
    when(
      () => sampling.markRowsFailed(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => sampling.getActiveSerialRows(
        sessionId: any(named: 'sessionId'),
        panelKey: any(named: 'panelKey'),
      ),
    ).thenAnswer((_) async => const []);
    when(
      () => sampling.upsertRemoteRow(
        tableName: any(named: 'tableName'),
        row: any(named: 'row'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => sampling.applySerialAssignments(
        sessionId: any(named: 'sessionId'),
        panelKey: any(named: 'panelKey'),
        assignments: any(named: 'assignments'),
      ),
    ).thenAnswer((_) async {});
    when(() => panels.getRowById(any(), any())).thenAnswer((_) async => null);
    when(() => panels.upsertPanelRow(any(), any())).thenAnswer((_) async {});
    when(
      () => operational.getDirtyRows(any()),
    ).thenAnswer((_) async => const []);
    when(() => operational.prepareRemoteRow(any(), any())).thenAnswer((
      invocation,
    ) {
      return Map<String, dynamic>.from(
        invocation.positionalArguments[1] as Map<String, dynamic>,
      )..removeWhere(
        (key, _) => const {
          'syncStatus',
          'dirtyAt',
          'lastSyncedAt',
          'syncError',
        }.contains(key),
      );
    });
    when(
      () => operational.markRowsSynced(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => operational.markRowsFailed(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => operational.getRowById(any(), any()),
    ).thenAnswer((_) async => null);
    when(
      () => operational.upsertRemoteRow(any(), any()),
    ).thenAnswer((_) async {});
    when(() => govee.getDirtyCaptureRows()).thenAnswer((_) async => const []);
    when(() => actions.getDirtyRows()).thenAnswer((_) async => const []);
    when(() => actions.getRowById(any())).thenAnswer((_) async => null);
    when(() => actions.upsertRemoteRow(any())).thenAnswer((_) async {});
    when(() => eggGrading.getDirtyRows()).thenAnswer((_) async => const []);
    when(() => eggGrading.markRowsSynced(any())).thenAnswer((_) async {});
    when(
      () => eggGrading.markRowsFailed(any(), any()),
    ).thenAnswer((_) async {});
    when(() => eggGrading.getRowById(any())).thenAnswer((_) async => null);
    when(() => eggGrading.upsertRemoteRow(any())).thenAnswer((_) async {});
    when(
      () => labAnalysis.getDirtyRows(any()),
    ).thenAnswer((_) async => const []);
    when(
      () => labAnalysis.getRowById(any(), any()),
    ).thenAnswer((_) async => null);
    when(
      () => labAnalysis.upsertRemoteRow(any(), any()),
    ).thenAnswer((_) async {});
    when(() => govee.markCapturesSynced(any())).thenAnswer((_) async {});
    when(() => photos.getAllPhotos()).thenAnswer((_) async => const []);
    when(
      () => tombstones.getPendingDeletes(),
    ).thenAnswer((_) async => const []);
    when(() => tombstones.applyRemoteDeletes()).thenAnswer((_) async {});
    when(
      () => tombstones.upsertRemoteTombstone(any()),
    ).thenAnswer((_) async {});
    when(() => tombstones.markSynced(any())).thenAnswer((_) async {});
    when(() => tombstones.markFailed(any(), any())).thenAnswer((_) async {});
    when(
      () => supabase.pullSyncTombstones(
        upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
      ),
    ).thenAnswer((_) async => 0);
    when(() => photoSync.syncDownloaded()).thenAnswer((_) async {});
    when(() => photoSync.syncPending()).thenAnswer((_) async {});
    when(
      () => supabase.upsertRowsStrict(any(), any()),
    ).thenAnswer((_) async {});
    when(() => supabase.upsertRowsReturningStrict(any(), any())).thenAnswer((
      invocation,
    ) async {
      return (invocation.positionalArguments[1] as List<Map<String, dynamic>>)
          .map(Map<String, dynamic>.from)
          .toList();
    });
    when(() => supabase.deleteRows(any(), any())).thenAnswer((_) async {});
    when(
      () => supabase.reconcilePanelSampleSerials(
        sessionId: any(named: 'sessionId'),
        panelKey: any(named: 'panelKey'),
      ),
    ).thenAnswer((_) async => const []);
    when(
      () => activityLog.log(any(), any(), details: any(named: 'details')),
    ).thenAnswer((_) async {});
    when(
      () => supabase.pullFromSupabase(
        upsertCustomer: any(named: 'upsertCustomer'),
        upsertFlock: any(named: 'upsertFlock'),
        upsertHatchery: any(named: 'upsertHatchery'),
        upsertHatcheryMachine: any(named: 'upsertHatcheryMachine'),
        upsertPhoto: any(named: 'upsertPhoto'),
        upsertBmkBreed: any(named: 'upsertBmkBreed'),
        upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
        upsertBmkOperationalStandard: any(
          named: 'upsertBmkOperationalStandard',
        ),
        upsertAuditSession: any(named: 'upsertAuditSession'),
        upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
        upsertDashboardAction: any(named: 'upsertDashboardAction'),
        upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
        upsertPanelRow: any(named: 'upsertPanelRow'),
        upsertChickObservation: any(named: 'upsertChickObservation'),
        upsertEggGradingCount: any(named: 'upsertEggGradingCount'),
        upsertPanelSamplingRow: any(named: 'upsertPanelSamplingRow'),
        upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
      ),
    ).thenAnswer((_) async => const SupabasePullSummary(panelRows: 1));
    when(
      () => supabase.pullOperationalRows(
        upsertOperationalRow: any(named: 'upsertOperationalRow'),
      ),
    ).thenAnswer((_) async => 0);
  });

  StartupSyncService service() => StartupSyncService(
    supabaseService: supabase,
    customerRepository: customers,
    dashboardActionRepository: actions,
    flockRepository: flocks,
    hatcheryRepository: hatcheries,
    hatcheryMachineRepository: hatcheryMachines,
    labAnalysisRepository: labAnalysis,
    activityLogRepository: activityLog,
    photoRepository: photos,
    bmkRepository: bmk,
    auditSessionRepository: sessions,
    goveeCaptureRepository: govee,
    panelSampleRepository: panels,
    panelSamplingStateRepository: sampling,
    chickObservationRepository: chickObservations,
    eggGradingRepository: eggGrading,
    performanceSyncRepository: operational,
    syncTombstoneRepository: tombstones,
    breederReportSyncService: breederReportSync,
    photoSyncService: photoSync,
    retryPolicy: retryPolicy,
  );

  Future<void> Function(Map<String, dynamic>) hatcheryMachinePullCallback() =>
      verify(
            () => supabase.pullFromSupabase(
              upsertCustomer: any(named: 'upsertCustomer'),
              upsertFlock: any(named: 'upsertFlock'),
              upsertHatchery: any(named: 'upsertHatchery'),
              upsertHatcheryMachine: captureAny(named: 'upsertHatcheryMachine'),
              upsertAuditSession: any(named: 'upsertAuditSession'),
              upsertPhoto: any(named: 'upsertPhoto'),
              upsertBmkBreed: any(named: 'upsertBmkBreed'),
              upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
              upsertBmkOperationalStandard: any(
                named: 'upsertBmkOperationalStandard',
              ),
              upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
              upsertDashboardAction: any(named: 'upsertDashboardAction'),
              upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
              upsertPanelRow: any(named: 'upsertPanelRow'),
              upsertChickObservation: any(named: 'upsertChickObservation'),
              upsertEggGradingCount: any(named: 'upsertEggGradingCount'),
              upsertPanelSamplingRow: any(named: 'upsertPanelSamplingRow'),
              upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
            ),
          ).captured.single
          as Future<void> Function(Map<String, dynamic>);

  test(
    'pushes only dirty sessions/panels and never legacy audit or sample tables',
    () async {
      when(() => customers.getDirtyRows()).thenAnswer(
        (_) async => [
          {'id': 'customer-1', 'name': 'Customer 1', 'syncStatus': 'pending'},
        ],
      );
      when(() => hatcheries.getDirtyRows()).thenAnswer(
        (_) async => [
          {'id': 'hatchery-1', 'name': 'Hatchery 1', 'syncStatus': 'pending'},
        ],
      );
      when(() => flocks.getDirtyRows()).thenAnswer(
        (_) async => [
          {'id': 'flock-1', 'flockId': 'Flock 1', 'syncStatus': 'pending'},
        ],
      );

      await service().run();

      // Reference rows use strict, confirmed uploads so a silently cancelled
      // customer insert cannot be reported as pushed.
      verify(() => supabase.upsertRowsStrict('customers', any())).called(1);
      verify(() => customers.markRowsSynced(['customer-1'])).called(1);
      verify(() => supabase.upsertRowsStrict('hatcheries', any())).called(1);
      verify(() => hatcheries.markRowsSynced(['hatchery-1'])).called(1);
      verify(() => supabase.upsertRowsStrict('flocks', any())).called(1);
      verify(() => flocks.markRowsSynced(['flock-1'])).called(1);

      // Audit data uses the strict (confirmable) dirty-row push, then is marked
      // synced.
      verify(
        () => supabase.upsertRowsStrict('audit_sessions', any()),
      ).called(1);
      verify(() => sessions.markSessionsSynced(any())).called(1);
      verify(() => supabase.upsertRowsStrict('egg_storage', any())).called(1);
      verify(() => panels.markRowsSynced('egg_storage', any())).called(1);

      // Sessions/panels are never sent via the silent bulk push.
      verifyNever(() => supabase.upsertRows('audit_sessions', any()));
      verifyNever(() => supabase.upsertRows('egg_storage', any()));

      verifyNever(() => supabase.upsertRows('audits', any()));
      verifyNever(() => supabase.upsertRowsStrict('audits', any()));
      verifyNever(() => supabase.upsertRows('sample_records', any()));
      for (final panel in PanelSampleSchema.panels) {
        verifyNever(
          () => supabase.upsertRows('${panel.tableName}_samples', any()),
        );
      }
    },
  );

  test(
    'pushes dirty hatchery machines after hatcheries and before audits',
    () async {
      when(() => hatcheries.getDirtyRows()).thenAnswer(
        (_) async => [
          {
            'id': 'hatchery-1',
            'customerId': 'customer-1',
            'syncStatus': 'pending',
          },
        ],
      );
      when(() => hatcheryMachines.getDirtyRows()).thenAnswer(
        (_) async => [
          {
            'id': 'machine-1',
            'hatcheryId': 'hatchery-1',
            'kind': 'setter',
            'code': 'S-01',
            'name': 'Setter 1',
            'batchSize': 120000,
            'trolleyCapacity': 120,
            'traySize': 150,
            'trolleyCount': 80,
            'traysPerTrolley': 100,
            'syncStatus': 'pending',
            'dirtyAt': '2026-10-05T09:00:00Z',
          },
        ],
      );

      await service().run();

      final order = verifyInOrder([
        () => supabase.upsertRowsStrict('hatcheries', any()),
        () => supabase.upsertRowsStrict('hatchery_machines', captureAny()),
        () => supabase.upsertRowsStrict('audit_sessions', any()),
      ]);
      final payload = order[1].captured.single as List<Map<String, dynamic>>;
      expect(payload.single['hatcheryId'], 'hatchery-1');
      expect(payload.single['batchSize'], 120000);
      expect(payload.single, isNot(contains('syncStatus')));
      expect(payload.single, isNot(contains('dirtyAt')));
      verify(() => hatcheryMachines.markRowsSynced(['machine-1'])).called(1);
    },
  );

  test(
    'isolates a rejected hatchery row so valid hatchery and session still push',
    () async {
      final events = <String>[];
      when(() => hatcheries.getDirtyRows()).thenAnswer(
        (_) async => [
          {
            'id': 'hatchery-bad',
            'customerId': 'missing-customer',
            'name': 'Orphan hatchery',
            'syncStatus': 'pending',
            'dirtyAt': '2026-10-05T09:00:00Z',
          },
          {
            'id': 'hatchery-qa',
            'customerId': 'customer-1',
            'name': 'QA hatchery',
            'syncStatus': 'pending',
            'dirtyAt': '2026-10-05T09:01:00Z',
          },
        ],
      );
      when(() => sessions.getDirtySessionRows()).thenAnswer(
        (_) async => [
          AuditSessionModel(
            id: 'session-qa',
            customerId: 'customer-1',
            flockId: 'flock-1',
            hatcheryId: 'hatchery-qa',
            date: DateTime(2026, 10, 5),
            createdAt: DateTime(2026, 10, 5),
            updatedAt: DateTime(2026, 10, 5),
          ),
        ],
      );
      when(() => supabase.upsertRowsStrict(any(), any())).thenAnswer((
        invocation,
      ) async {
        final table = invocation.positionalArguments[0] as String;
        final rows =
            invocation.positionalArguments[1] as List<Map<String, dynamic>>;
        if (table == 'hatcheries') {
          events.add('hatcheries:${rows.map((row) => row['id']).join(',')}');
          if (rows.length > 1 || rows.single['id'] == 'hatchery-bad') {
            throw StateError('missing customer foreign key');
          }
        } else if (table == 'audit_sessions') {
          events.add('audit_sessions');
        }
      });

      final outcome = await service().run();

      expect(outcome.failed, 1);
      expect(outcome.failedTables, contains('hatcheries'));
      verify(
        () => hatcheries.markRowsFailed(['hatchery-bad'], any()),
      ).called(1);
      verify(() => hatcheries.markRowsSynced(['hatchery-qa'])).called(1);
      verify(() => sessions.markSessionsSynced(['session-qa'])).called(1);
      expect(events, contains('hatcheries:hatchery-bad,hatchery-qa'));
      expect(events, contains('hatcheries:hatchery-qa'));
      expect(
        events.indexOf('hatcheries:hatchery-qa'),
        lessThan(events.indexOf('audit_sessions')),
      );
    },
  );

  test(
    'push-capable pulls keep a dirty local hatchery machine for retry',
    () async {
      when(
        () => hatcheryMachines.getRowSyncStatus('machine-1'),
      ).thenAnswer((_) async => 'pending');

      await service().run();

      await hatcheryMachinePullCallback()({
        'id': 'machine-1',
        'hatchery_id': 'hatchery-1',
        'kind': 'setter',
        'code': 'S-01',
        'name': 'Old remote name',
      });

      verify(() => hatcheryMachines.getRowSyncStatus('machine-1')).called(1);
      verifyNever(() => hatcheryMachines.upsertRemoteRow(any()));
    },
  );

  test(
    'pull-only devices apply remote hatchery machines despite local dirt',
    () async {
      when(
        () => hatcheryMachines.getRowSyncStatus('machine-1'),
      ).thenAnswer((_) async => 'pending');

      await service().run(canPush: false);

      final remoteRow = {
        'id': 'machine-1',
        'hatchery_id': 'hatchery-1',
        'kind': 'setter',
        'code': 'S-01',
        'name': 'Remote name',
      };
      await hatcheryMachinePullCallback()(remoteRow);

      verifyNever(() => hatcheryMachines.getRowSyncStatus('machine-1'));
      verify(() => hatcheryMachines.upsertRemoteRow(remoteRow)).called(1);
    },
  );

  test(
    'pushes dirty sampling rows after sessions and before measurements',
    () async {
      when(() => sampling.getDirtyRows('panel_sampling_states')).thenAnswer(
        (_) async => [
          {
            'id': 'session-1:egg_storage',
            'sessionId': 'session-1',
            'panelKey': 'egg_storage',
            'serialHighWatermark': 1,
            'syncStatus': 'pending',
            'dirtyAt': '2026-09-01T00:00:00Z',
          },
        ],
      );
      when(() => sampling.getDirtyRows('panel_sampling_nodes')).thenAnswer(
        (_) async => [
          {
            'id': 'node-1',
            'sessionId': 'session-1',
            'panelKey': 'egg_storage',
            'sampleId': 'sample-1',
            'sampleNumber': 1,
            'isTerminal': 1,
            'syncStatus': 'pending',
            'dirtyAt': '2026-09-01T00:00:00Z',
          },
        ],
      );
      when(
        () => sampling.getDirtyRows('panel_sample_serial_reservations'),
      ).thenAnswer((_) async => const []);
      final events = <String>[];
      when(() => supabase.upsertRowsStrict(any(), any())).thenAnswer((
        invocation,
      ) async {
        events.add(invocation.positionalArguments.first as String);
      });

      await service().run();

      verify(
        () => supabase.upsertRowsStrict('panel_sampling_states', any()),
      ).called(2);
      verify(
        () => supabase.upsertRowsStrict('panel_sampling_nodes', any()),
      ).called(2);
      verify(
        () => sampling.markRowsSynced('panel_sampling_states', [
          'session-1:egg_storage',
        ]),
      ).called(1);
      expect(
        events.indexOf('audit_sessions'),
        lessThan(events.indexOf('panel_sampling_states')),
      );
      expect(
        events.indexOf('panel_sampling_nodes'),
        lessThan(events.indexOf('egg_storage')),
      );
    },
  );

  test('isolates sampling upload failures by session and panel', () async {
    final dirtyStates = [
      {
        'id': 'orphan:egg_storage',
        'sessionId': 'orphan-session',
        'panelKey': 'egg_storage',
        'serialHighWatermark': 1,
        'syncStatus': 'pending',
        'dirtyAt': '2026-09-01T00:00:00Z',
      },
      {
        'id': 'valid:egg_storage',
        'sessionId': 'valid-session',
        'panelKey': 'egg_storage',
        'serialHighWatermark': 1,
        'syncStatus': 'pending',
        'dirtyAt': '2026-09-01T00:00:00Z',
      },
    ];
    final dirtyNodes = [
      {
        'id': 'orphan-node',
        'sessionId': 'orphan-session',
        'panelKey': 'egg_storage',
        'sampleId': 'orphan-sample',
        'sampleNumber': 1,
        'isTerminal': 1,
        'syncStatus': 'pending',
        'dirtyAt': '2026-09-01T00:00:00Z',
      },
      {
        'id': 'valid-node',
        'sessionId': 'valid-session',
        'panelKey': 'egg_storage',
        'sampleId': 'valid-sample',
        'sampleNumber': 1,
        'isTerminal': 1,
        'syncStatus': 'pending',
        'dirtyAt': '2026-09-01T00:00:00Z',
      },
    ];
    when(
      () => sampling.getDirtyRows('panel_sampling_states'),
    ).thenAnswer((_) async => dirtyStates);
    when(
      () => sampling.getDirtyRows('panel_sampling_nodes'),
    ).thenAnswer((_) async => dirtyNodes);
    when(
      () => sampling.getDirtyRows('panel_sample_serial_reservations'),
    ).thenAnswer((_) async => const []);
    when(() => panels.getDirtyRows('egg_storage')).thenAnswer(
      (_) async => [
        {
          'id': 'orphan-measurement',
          'sessionId': 'orphan-session',
          'customerId': 'customer-1',
          'date': '2026-05-01',
          'syncStatus': 'pending',
        },
        {
          'id': 'valid-measurement',
          'sessionId': 'valid-session',
          'customerId': 'customer-1',
          'date': '2026-05-01',
          'syncStatus': 'pending',
        },
      ],
    );
    final attempts = <String, List<List<Map<String, dynamic>>>>{};
    when(() => supabase.upsertRowsStrict(any(), any())).thenAnswer((
      invocation,
    ) async {
      final table = invocation.positionalArguments[0] as String;
      final rows = (invocation.positionalArguments[1] as List)
          .cast<Map<String, dynamic>>();
      attempts.putIfAbsent(table, () => []).add(rows);
      if (rows.any((row) => row['sessionId'] == 'orphan-session')) {
        throw StateError('orphan session violates RLS');
      }
    });

    final outcome = await service().run();

    expect(outcome.hasFailures, isTrue);
    expect(attempts['panel_sampling_states'], hasLength(3));
    expect(attempts['panel_sampling_nodes'], hasLength(3));
    for (final table in ['panel_sampling_states', 'panel_sampling_nodes']) {
      expect(
        attempts[table]!.every((group) => group.length == 1),
        isTrue,
        reason: 'Each $table upload must contain only one session/panel.',
      );
      expect(
        attempts[table]!.any(
          (group) => group.single['sessionId'] == 'valid-session',
        ),
        isTrue,
        reason: 'A failed orphan group must not block valid-session rows.',
      );
    }
    verify(
      () => sampling.markRowsSynced('panel_sampling_states', [
        'valid:egg_storage',
      ]),
    ).called(1);
    verify(
      () => sampling.markRowsSynced('panel_sampling_nodes', ['valid-node']),
    ).called(1);
    verifyNever(
      () => sampling.markRowsSynced('panel_sampling_states', [
        'orphan:egg_storage',
      ]),
    );
    expect(attempts['egg_storage'], [
      [
        {
          'id': 'valid-measurement',
          'sessionId': 'valid-session',
          'customerId': 'customer-1',
          'date': '2026-05-01',
        },
      ],
    ]);
  });

  test(
    'sampling retry backoff stays scoped to the failed session and panel',
    () async {
      final dirtyNodes = [
        {
          'id': 'unrelated-node',
          'sessionId': 'unrelated-session',
          'panelKey': 'egg_storage',
          'sampleId': 'unrelated-sample',
          'sampleNumber': 1,
          'isTerminal': 1,
          'syncStatus': 'pending',
        },
        {
          'id': 'qa-node',
          'sessionId': 'qa-session',
          'panelKey': 'egg_storage',
          'sampleId': 'qa-sample',
          'sampleNumber': 1,
          'isTerminal': 1,
          'syncStatus': 'pending',
        },
      ];
      when(
        () => sampling.getDirtyRows('panel_sampling_nodes'),
      ).thenAnswer((_) async => dirtyNodes);

      final attemptsBySession = <String, int>{};
      when(() => supabase.upsertRowsStrict(any(), any())).thenAnswer((
        invocation,
      ) async {
        if (invocation.positionalArguments.first != 'panel_sampling_nodes') {
          return;
        }
        final rows = (invocation.positionalArguments[1] as List)
            .cast<Map<String, dynamic>>();
        final sessionId = rows.single['sessionId'] as String;
        attemptsBySession.update(
          sessionId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        if (sessionId == 'unrelated-session') {
          throw StateError('unrelated session violates RLS');
        }
      });

      await service().run();
      final qaAttemptsAfterFirstRun = attemptsBySession['qa-session'];
      expect(qaAttemptsAfterFirstRun, 2);

      await service().run();

      expect(
        attemptsBySession['unrelated-session'],
        1,
        reason: 'the failed group should remain in its backoff window',
      );
      expect(
        attemptsBySession['qa-session'],
        greaterThan(qaAttemptsAfterFirstRun!),
        reason: 'the successful QA group should remain immediately retryable',
      );
    },
  );

  test('isolates failures during reconciled sampling uploads', () async {
    when(() => sampling.getDirtyRows('panel_sampling_states')).thenAnswer(
      (_) async => [
        {
          'id': 'session-a:egg_storage',
          'sessionId': 'session-a',
          'panelKey': 'egg_storage',
          'serialHighWatermark': 1,
          'syncStatus': 'pending',
        },
        {
          'id': 'session-b:egg_storage',
          'sessionId': 'session-b',
          'panelKey': 'egg_storage',
          'serialHighWatermark': 1,
          'syncStatus': 'pending',
        },
      ],
    );
    when(
      () => sampling.getDirtyRows('panel_sampling_nodes'),
    ).thenAnswer((_) async => const []);
    when(
      () => sampling.getDirtyRows('panel_sample_serial_reservations'),
    ).thenAnswer((_) async => const []);
    var sessionBPushes = 0;
    final attempts = <List<Map<String, dynamic>>>[];
    when(
      () => supabase.upsertRowsStrict('panel_sampling_states', any()),
    ).thenAnswer((invocation) async {
      final rows = (invocation.positionalArguments[1] as List)
          .cast<Map<String, dynamic>>();
      attempts.add(rows);
      if (rows.single['sessionId'] == 'session-b' && ++sessionBPushes == 2) {
        throw StateError('session-b rejected after reconciliation');
      }
    });

    final outcome = await service().run();

    expect(outcome.hasFailures, isTrue);
    expect(attempts, hasLength(4));
    expect(attempts.every((group) => group.length == 1), isTrue);
    verify(
      () => sampling.markRowsSynced('panel_sampling_states', [
        'session-a:egg_storage',
      ]),
    ).called(1);
    verifyNever(
      () => sampling.markRowsSynced('panel_sampling_states', [
        'session-b:egg_storage',
      ]),
    );
  });

  test(
    'pull-only sync never writes sampling rows or calls serial RPC',
    () async {
      await service().run(canPush: false);

      verifyNever(() => supabase.upsertRowsStrict(any(), any()));
      verifyNever(
        () => supabase.reconcilePanelSampleSerials(
          sessionId: any(named: 'sessionId'),
          panelKey: any(named: 'panelKey'),
        ),
      );
      verifyNever(() => sampling.getDirtyRows(any()));
    },
  );

  test(
    'applies server serial assignments before measurement panel push',
    () async {
      when(() => sampling.getDirtyRows('panel_sampling_nodes')).thenAnswer(
        (_) async => [
          {
            'id': 'node-1',
            'sessionId': 'session-1',
            'panelKey': 'egg_storage',
            'sampleId': 'sample-1',
            'sampleNumber': 1,
            'isTerminal': 1,
            'syncStatus': 'pending',
            'dirtyAt': '2026-09-01T00:00:00Z',
          },
        ],
      );
      when(
        () => sampling.getActiveSerialRows(
          sessionId: 'session-1',
          panelKey: 'egg_storage',
        ),
      ).thenAnswer(
        (_) async => const [
          {'sampleId': 'sample-1', 'sampleNumber': 1},
        ],
      );
      final events = <String>[];
      when(
        () => supabase.reconcilePanelSampleSerials(
          sessionId: 'session-1',
          panelKey: 'egg_storage',
        ),
      ).thenAnswer((_) async {
        events.add('rpc');
        return const [
          {'sample_id': 'sample-1', 'sample_number': 2},
        ];
      });
      when(
        () => sampling.applySerialAssignments(
          sessionId: 'session-1',
          panelKey: 'egg_storage',
          assignments: {'sample-1': 2},
        ),
      ).thenAnswer((_) async {
        events.add('apply');
      });
      when(() => supabase.upsertRowsStrict(any(), any())).thenAnswer((
        invocation,
      ) async {
        events.add(invocation.positionalArguments.first as String);
      });

      await service().run();

      verify(
        () => sampling.applySerialAssignments(
          sessionId: 'session-1',
          panelKey: 'egg_storage',
          assignments: {'sample-1': 2},
        ),
      ).called(1);
      expect(events.indexOf('rpc'), lessThan(events.indexOf('apply')));
      expect(events.indexOf('apply'), lessThan(events.indexOf('egg_storage')));
    },
  );

  test(
    'serial reconciliation failure keeps that panel measurements pending',
    () async {
      when(() => sampling.getDirtyRows('panel_sampling_nodes')).thenAnswer(
        (_) async => [
          {
            'id': 'node-1',
            'sessionId': 'session-1',
            'panelKey': 'egg_storage',
            'sampleId': 'sample-1',
            'sampleNumber': 1,
            'isTerminal': 1,
            'syncStatus': 'pending',
            'dirtyAt': '2026-09-01T00:00:00Z',
          },
        ],
      );
      when(
        () => supabase.reconcilePanelSampleSerials(
          sessionId: 'session-1',
          panelKey: 'egg_storage',
        ),
      ).thenThrow(StateError('RPC unavailable'));

      final outcome = await service().run();

      expect(outcome.hasFailures, isTrue);
      verifyNever(() => supabase.upsertRowsStrict('egg_storage', any()));
    },
  );

  test('failed reconciled node upload keeps measurements pending', () async {
    when(() => sampling.getDirtyRows('panel_sampling_nodes')).thenAnswer(
      (_) async => [
        {
          'id': 'node-1',
          'sessionId': 'session-1',
          'panelKey': 'egg_storage',
          'sampleId': 'sample-1',
          'sampleNumber': 1,
          'isTerminal': 1,
          'syncStatus': 'pending',
          'dirtyAt': '2026-09-01T00:00:00Z',
        },
      ],
    );
    when(
      () => sampling.getActiveSerialRows(
        sessionId: 'session-1',
        panelKey: 'egg_storage',
      ),
    ).thenAnswer(
      (_) async => const [
        {'sampleId': 'sample-1', 'sampleNumber': 1},
      ],
    );
    when(
      () => supabase.reconcilePanelSampleSerials(
        sessionId: 'session-1',
        panelKey: 'egg_storage',
      ),
    ).thenAnswer(
      (_) async => const [
        {'sample_id': 'sample-1', 'sample_number': 2},
      ],
    );
    when(
      () => sampling.applySerialAssignments(
        sessionId: 'session-1',
        panelKey: 'egg_storage',
        assignments: {'sample-1': 2},
      ),
    ).thenAnswer((_) async {});
    var nodePushes = 0;
    when(
      () => supabase.upsertRowsStrict('panel_sampling_nodes', any()),
    ).thenAnswer((_) async {
      nodePushes++;
      if (nodePushes == 2) throw StateError('reconciled node push failed');
    });

    final outcome = await service().run();

    expect(outcome.hasFailures, isTrue);
    expect(nodePushes, 2);
    verifyNever(() => supabase.upsertRowsStrict('egg_storage', any()));
  });

  test(
    'backoff-skipped reconciled node upload keeps measurements pending',
    () async {
      when(() => sampling.getDirtyRows('panel_sampling_nodes')).thenAnswer(
        (_) async => [
          {
            'id': 'node-1',
            'sessionId': 'session-1',
            'panelKey': 'egg_storage',
            'sampleId': 'sample-1',
            'sampleNumber': 1,
            'isTerminal': 1,
            'syncStatus': 'pending',
            'dirtyAt': '2026-09-01T00:00:00Z',
          },
        ],
      );
      when(
        () => sampling.getActiveSerialRows(
          sessionId: 'session-1',
          panelKey: 'egg_storage',
        ),
      ).thenAnswer(
        (_) async => const [
          {'sampleId': 'sample-1', 'sampleNumber': 1},
        ],
      );
      when(
        () => supabase.reconcilePanelSampleSerials(
          sessionId: 'session-1',
          panelKey: 'egg_storage',
        ),
      ).thenAnswer((_) async {
        retryPolicy.recordFailure(
          'sampling:panel_sampling_nodes:session-1\u0000egg_storage',
        );
        return const [
          {'sample_id': 'sample-1', 'sample_number': 2},
        ];
      });
      when(
        () => sampling.applySerialAssignments(
          sessionId: 'session-1',
          panelKey: 'egg_storage',
          assignments: {'sample-1': 2},
        ),
      ).thenAnswer((_) async {});

      final outcome = await service().run();

      expect(outcome.hasFailures, isTrue);
      verify(
        () => supabase.upsertRowsStrict('panel_sampling_nodes', any()),
      ).called(1);
      verifyNever(() => supabase.upsertRowsStrict('egg_storage', any()));
    },
  );

  test('pending sampling-node tombstone blocks pull resurrection', () async {
    final deleted = SyncTombstone(
      id: 'panel_sampling_nodes:node-1',
      tableName: 'panel_sampling_nodes',
      rowId: 'node-1',
      deletedAt: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1),
    );
    when(
      () => tombstones.getPendingDeletes(),
    ).thenAnswer((_) async => [deleted]);
    when(
      () => supabase.pullFromSupabase(
        upsertCustomer: any(named: 'upsertCustomer'),
        upsertFlock: any(named: 'upsertFlock'),
        upsertHatchery: any(named: 'upsertHatchery'),
        upsertHatcheryMachine: any(named: 'upsertHatcheryMachine'),
        upsertPhoto: any(named: 'upsertPhoto'),
        upsertBmkBreed: any(named: 'upsertBmkBreed'),
        upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
        upsertBmkOperationalStandard: any(
          named: 'upsertBmkOperationalStandard',
        ),
        upsertAuditSession: any(named: 'upsertAuditSession'),
        upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
        upsertDashboardAction: any(named: 'upsertDashboardAction'),
        upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
        upsertPanelRow: any(named: 'upsertPanelRow'),
        upsertChickObservation: any(named: 'upsertChickObservation'),
        upsertEggGradingCount: any(named: 'upsertEggGradingCount'),
        upsertPanelSamplingRow: any(named: 'upsertPanelSamplingRow'),
        upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
      ),
    ).thenAnswer((invocation) async {
      final upsert =
          invocation.namedArguments[#upsertPanelSamplingRow]
              as Future<void> Function(String, Map<String, dynamic>);
      await upsert('panel_sampling_nodes', {
        'id': 'node-1',
        'session_id': 'session-1',
        'panel_key': 'egg_storage',
        'sample_id': 'sample-1',
        'sample_number': 1,
      });
      return const SupabasePullSummary(panelSamplingRows: 1);
    });

    await service().run(canPush: false);

    verifyNever(
      () => sampling.upsertRemoteRow(
        tableName: 'panel_sampling_nodes',
        row: any(named: 'row'),
      ),
    );
  });

  test('reconciles a cloud-reallocated Chick identity before pull', () async {
    when(() => panels.getDirtyRows('chick_quality')).thenAnswer(
      (_) async => [
        {
          'id': 'quality-device-b',
          'sessionId': 'session-1',
          'customerId': 'customer-1',
          'date': '2026-08-24',
          'domain': 'chicks.legacy_combined',
          'schemaVersion': 1,
          'scopeType': 'pool',
          'scopeKey': '{}',
          'replicate': 1,
          'sampleKey': 'device-local-replicate-1',
          'syncStatus': 'pending',
        },
      ],
    );
    when(
      () => supabase.upsertRowsReturningStrict('chick_quality', any()),
    ).thenAnswer(
      (_) async => [
        {
          'id': 'quality-device-b',
          'replicate': 2,
          'sample_key': 'cloud-reallocated-replicate-2',
        },
      ],
    );
    when(
      () => panels.reconcileChickIdentityAssignments('chick_quality', any()),
    ).thenAnswer((_) async {});

    await service().run();

    verify(
      () => panels.reconcileChickIdentityAssignments('chick_quality', [
        {
          'id': 'quality-device-b',
          'replicate': 2,
          'sample_key': 'cloud-reallocated-replicate-2',
        },
      ]),
    ).called(1);
    verify(
      () => panels.markRowsSynced('chick_quality', ['quality-device-b']),
    ).called(1);
  });

  test('applies remote tombstones before uploading reference rows', () async {
    final events = <String>[];

    when(() => customers.getDirtyRows()).thenAnswer(
      (_) async => [
        {'id': 'customer-1', 'name': 'Customer 1', 'syncStatus': 'pending'},
      ],
    );
    when(
      () => supabase.pullSyncTombstones(
        upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
      ),
    ).thenAnswer((invocation) async {
      events.add('pull tombstones');
      final callback =
          invocation.namedArguments[#upsertSyncTombstone]
              as Future<void> Function(Map<String, dynamic>);
      await callback({
        'id': 'cloud-delete-customers-old',
        'table_name': 'customers',
        'row_id': 'old-customer',
        'deleted_at': '2026-06-23T00:00:00.000Z',
        'created_at': '2026-06-23T00:00:00.000Z',
        'synced_at': '2026-06-23T00:00:00.000Z',
      });
      return 1;
    });
    when(() => tombstones.upsertRemoteTombstone(any())).thenAnswer((_) async {
      events.add('store tombstone');
    });
    when(() => tombstones.applyRemoteDeletes()).thenAnswer((_) async {
      events.add('apply deletes');
    });
    when(() => supabase.upsertRowsStrict('customers', any())).thenAnswer((
      _,
    ) async {
      events.add('upload customers');
    });

    await service().run();

    expect(
      events,
      containsAllInOrder([
        'pull tombstones',
        'store tombstone',
        'apply deletes',
        'upload customers',
      ]),
    );
  });

  test(
    'a failed customer push marks rows failed and the sync continues',
    () async {
      when(() => customers.getDirtyRows()).thenAnswer(
        (_) async => [
          {'id': 'customer-1', 'name': 'Customer 1', 'syncStatus': 'pending'},
        ],
      );
      when(
        () => supabase.upsertRowsStrict('customers', any()),
      ).thenThrow(StateError('customer insert was not persisted'));

      final outcome = await service().run();

      expect(outcome.online, isTrue);
      verify(() => customers.markRowsFailed(['customer-1'], any())).called(1);
      // The pull still ran:
      verify(
        () => supabase.pullFromSupabase(
          upsertCustomer: any(named: 'upsertCustomer'),
          upsertFlock: any(named: 'upsertFlock'),
          upsertHatchery: any(named: 'upsertHatchery'),
          upsertHatcheryMachine: any(named: 'upsertHatcheryMachine'),
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertBmkOperationalStandard: any(
            named: 'upsertBmkOperationalStandard',
          ),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertDashboardAction: any(named: 'upsertDashboardAction'),
          upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
          upsertChickObservation: any(named: 'upsertChickObservation'),
          upsertEggGradingCount: any(named: 'upsertEggGradingCount'),
          upsertPanelSamplingRow: any(named: 'upsertPanelSamplingRow'),
          upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
        ),
      ).called(1);
    },
  );

  test('clean reference rows are not pushed', () async {
    // all three getDirtyRows return [] (default stubs)
    await service().run();
    verifyNever(() => supabase.upsertRowsStrict('customers', any()));
    verifyNever(() => supabase.upsertRowsStrict('hatcheries', any()));
    verifyNever(() => supabase.upsertRowsStrict('flocks', any()));
  });

  test(
    'locally dirty reference rows are not overwritten by the pull',
    () async {
      when(
        () => customers.getRowSyncStatus('customer-1'),
      ).thenAnswer((_) async => 'pending');
      when(
        () => supabase.pullFromSupabase(
          upsertCustomer: any(named: 'upsertCustomer'),
          upsertFlock: any(named: 'upsertFlock'),
          upsertHatchery: any(named: 'upsertHatchery'),
          upsertHatcheryMachine: any(named: 'upsertHatcheryMachine'),
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertBmkOperationalStandard: any(
            named: 'upsertBmkOperationalStandard',
          ),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertDashboardAction: any(named: 'upsertDashboardAction'),
          upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
          upsertChickObservation: any(named: 'upsertChickObservation'),
          upsertEggGradingCount: any(named: 'upsertEggGradingCount'),
          upsertPanelSamplingRow: any(named: 'upsertPanelSamplingRow'),
          upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
        ),
      ).thenAnswer((invocation) async {
        final callback =
            invocation.namedArguments[#upsertCustomer]
                as Future<void> Function(Map<String, dynamic>);
        await callback({'id': 'customer-1', 'name': 'Remote Customer 1'});
        return const SupabasePullSummary(panelRows: 1);
      });

      await service().run();

      verifyNever(() => customers.upsertCustomer(any()));
    },
  );

  test(
    'flock push payload drops local-only updatedAt (no cloud column)',
    () async {
      when(() => flocks.getDirtyRows()).thenAnswer(
        (_) async => [
          {
            'id': 'flock-1',
            'flockId': 'Flock 1',
            'customerId': 'customer-1',
            'updatedAt': '2026-05-01T00:00:00.000Z',
            'syncStatus': 'pending',
            'dirtyAt': '2026-05-01T00:00:00.000Z',
            'lastSyncedAt': null,
            'syncError': null,
          },
        ],
      );

      await service().run();

      final payload =
          verify(
                () => supabase.upsertRowsStrict('flocks', captureAny()),
              ).captured.single
              as List<Map<String, dynamic>>;
      expect(payload, isNotEmpty);
      for (final key in [
        'updatedAt',
        'syncStatus',
        'dirtyAt',
        'lastSyncedAt',
        'syncError',
      ]) {
        expect(payload.single.keys, isNot(contains(key)));
      }
      expect(payload.single['id'], 'flock-1');
    },
  );

  test(
    'canPush:false applies a remote customer row even when local status is pending',
    () async {
      when(
        () => customers.getRowSyncStatus('customer-1'),
      ).thenAnswer((_) async => 'pending');
      when(() => customers.upsertCustomer(any())).thenAnswer((_) async {});
      when(
        () => supabase.pullFromSupabase(
          upsertCustomer: any(named: 'upsertCustomer'),
          upsertFlock: any(named: 'upsertFlock'),
          upsertHatchery: any(named: 'upsertHatchery'),
          upsertHatcheryMachine: any(named: 'upsertHatcheryMachine'),
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertBmkOperationalStandard: any(
            named: 'upsertBmkOperationalStandard',
          ),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertDashboardAction: any(named: 'upsertDashboardAction'),
          upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
          upsertChickObservation: any(named: 'upsertChickObservation'),
          upsertEggGradingCount: any(named: 'upsertEggGradingCount'),
          upsertPanelSamplingRow: any(named: 'upsertPanelSamplingRow'),
          upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
        ),
      ).thenAnswer((invocation) async {
        final callback =
            invocation.namedArguments[#upsertCustomer]
                as Future<void> Function(Map<String, dynamic>);
        await callback({'id': 'customer-1', 'name': 'Remote Customer 1'});
        return const SupabasePullSummary(panelRows: 1);
      });

      await service().run(canPush: false);

      verify(
        () => customers.upsertCustomer(
          any(that: containsPair('id', 'customer-1')),
        ),
      ).called(1);
    },
  );

  test(
    'canPush:true applies a remote customer row when local status is synced',
    () async {
      when(
        () => customers.getRowSyncStatus('customer-1'),
      ).thenAnswer((_) async => 'synced');
      when(() => customers.upsertCustomer(any())).thenAnswer((_) async {});
      when(
        () => supabase.pullFromSupabase(
          upsertCustomer: any(named: 'upsertCustomer'),
          upsertFlock: any(named: 'upsertFlock'),
          upsertHatchery: any(named: 'upsertHatchery'),
          upsertHatcheryMachine: any(named: 'upsertHatcheryMachine'),
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertBmkOperationalStandard: any(
            named: 'upsertBmkOperationalStandard',
          ),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertDashboardAction: any(named: 'upsertDashboardAction'),
          upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
          upsertChickObservation: any(named: 'upsertChickObservation'),
          upsertEggGradingCount: any(named: 'upsertEggGradingCount'),
          upsertPanelSamplingRow: any(named: 'upsertPanelSamplingRow'),
          upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
        ),
      ).thenAnswer((invocation) async {
        final callback =
            invocation.namedArguments[#upsertCustomer]
                as Future<void> Function(Map<String, dynamic>);
        await callback({'id': 'customer-1', 'name': 'Remote Customer 1'});
        return const SupabasePullSummary(panelRows: 1);
      });

      await service().run(canPush: true);

      verify(
        () => customers.upsertCustomer(
          any(that: containsPair('id', 'customer-1')),
        ),
      ).called(1);
    },
  );

  test('pushes dirty Govee captures and marks them synced', () async {
    when(() => govee.getDirtyCaptureRows()).thenAnswer(
      (_) async => [
        GoveeDailyCaptureModel(
          id: 'g1',
          customerId: 'customer-1',
          hatcheryId: 'hatchery-1',
          place: TemperaturePlace.setterRoom,
          captureDate: '2026-05-01',
          status: 'completed',
          readingCount: 5,
          createdAt: DateTime(2026, 5, 1),
          updatedAt: DateTime(2026, 5, 1),
        ),
      ],
    );

    await service().run();

    verify(
      () => supabase.upsertRowsStrict('govee_daily_captures', any()),
    ).called(1);
    verify(() => govee.markCapturesSynced(any())).called(1);
    verifyNever(() => supabase.upsertRows('govee_daily_captures', any()));
  });

  test('marks dirty rows failed when the strict push throws', () async {
    when(
      () => supabase.upsertRowsStrict('audit_sessions', any()),
    ).thenThrow(StateError('offline'));
    when(
      () => supabase.upsertRowsStrict('egg_storage', any()),
    ).thenThrow(StateError('offline'));
    when(
      () => sessions.markSessionsFailed(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => panels.markRowsFailed(any(), any(), any()),
    ).thenAnswer((_) async {});

    await service().run();

    verify(() => sessions.markSessionsFailed(any(), any())).called(1);
    verify(() => panels.markRowsFailed('egg_storage', any(), any())).called(1);
    verifyNever(() => sessions.markSessionsSynced(any()));
  });

  test('strips device-local sync columns from pushed payloads', () async {
    await service().run();

    final captured =
        verify(
              () => supabase.upsertRowsStrict('audit_sessions', captureAny()),
            ).captured.single
            as List<Map<String, dynamic>>;
    expect(captured, isNotEmpty);
    for (final key in ['syncStatus', 'dirtyAt', 'lastSyncedAt', 'syncError']) {
      expect(captured.single.keys, isNot(contains(key)));
    }
  });

  test('pushes dirty dashboard actions and marks them synced', () async {
    final now = DateTime.utc(2026, 7, 12);
    when(() => actions.getDirtyRows()).thenAnswer(
      (_) async => [
        DashboardActionModel(
          id: 'action-1',
          findingKey: 'finding-1',
          customerId: 'customer-1',
          hatcheryId: 'hatchery-1',
          title: 'Correct ventilation',
          createdAt: now,
          updatedAt: now,
          dirtyAt: now,
        ),
      ],
    );
    when(() => actions.markSynced(any())).thenAnswer((_) async {});

    await service().run();

    final payload =
        verify(
              () =>
                  supabase.upsertRowsStrict('dashboard_actions', captureAny()),
            ).captured.single
            as List<Map<String, dynamic>>;
    expect(payload.single['findingKey'], 'finding-1');
    expect(payload.single, isNot(contains('dirtyAt')));
    verify(() => actions.markSynced(['action-1'])).called(1);
  });

  test('pushes and marks every changed agent review table synced', () async {
    const approvalTables = [
      'hatchery_draft_batches',
      'hatchery_draft_rows',
      'hatchery_agent_audit_events',
      'hatchery_daily_records',
      'agent_intake_sessions',
      'agent_intake_turns',
      'agent_intake_values',
    ];
    when(() => operational.getDirtyRows(any())).thenAnswer((invocation) async {
      final table = invocation.positionalArguments.first as String;
      if (!approvalTables.contains(table)) return const [];
      return [
        {
          'id': '$table-1',
          'syncStatus': 'pending',
          'dirtyAt': '2026-07-27T10:00:00.000Z',
        },
      ];
    });

    await service().run();

    for (final table in approvalTables) {
      verify(() => supabase.upsertRowsStrict(table, any())).called(1);
      verify(() => operational.markRowsSynced(table, ['$table-1'])).called(1);
    }
  });

  test('never pushes server-authored conversation or tool evidence', () async {
    await service().run();

    for (final table in const [
      'agent_conversations',
      'agent_conversation_turns',
      'agent_tool_events',
      'agent_intake_visits',
    ]) {
      verifyNever(() => operational.getDirtyRows(table));
      verifyNever(() => supabase.upsertRowsStrict(table, any()));
    }
  });

  test('pulls every agent review table through operational storage', () async {
    await service().run();

    final captured = verify(
      () => supabase.pullOperationalRows(
        upsertOperationalRow: captureAny(named: 'upsertOperationalRow'),
      ),
    ).captured.single;
    final callback =
        captured
            as Future<void> Function(String table, Map<String, dynamic> row);
    for (final table in const [
      'hatchery_draft_batches',
      'hatchery_draft_rows',
      'hatchery_agent_audit_events',
      'hatchery_daily_records',
      'agent_conversations',
      'agent_conversation_turns',
      'agent_tool_events',
      'agent_intake_visits',
      'agent_intake_sessions',
      'agent_intake_turns',
      'agent_intake_values',
    ]) {
      await callback(table, {
        'id': '$table-remote',
        'updated_at': '2026-07-27T10:00:00.000Z',
      });
      verify(() => operational.getRowById(table, '$table-remote')).called(1);
      verify(
        () => operational.upsertRemoteRow(
          table,
          any(that: containsPair('id', '$table-remote')),
        ),
      ).called(1);
    }
  });

  test(
    'failed local customer sector push survives stale operational pull',
    () async {
      var appliedRemoteRows = 0;
      when(() => operational.upsertRemoteRow(any(), any())).thenAnswer((_) {
        appliedRemoteRows++;
        return Future<void>.value();
      });
      const localUpdatedAt = '2026-08-16T09:00:00.000Z';
      when(() => operational.getDirtyRows('customer_sectors')).thenAnswer(
        (_) async => [
          {
            'id': 'sector-1',
            'customerId': 'customer-1',
            'sectorKey': 'breeder',
            'isActive': 1,
            'updatedAt': localUpdatedAt,
            'syncStatus': 'pending',
            'dirtyAt': localUpdatedAt,
          },
        ],
      );
      when(
        () => supabase.upsertRowsStrict('customer_sectors', any()),
      ).thenThrow(StateError('simulated sector push failure'));
      when(
        () => operational.getRowById('customer_sectors', 'sector-1'),
      ).thenAnswer(
        (_) async => {
          'id': 'sector-1',
          'customerId': 'customer-1',
          'sectorKey': 'breeder',
          'isActive': 1,
          // Equal timestamps make the old behavior choose the remote row.
          'updatedAt': localUpdatedAt,
          'syncStatus': 'failed',
          'dirtyAt': localUpdatedAt,
        },
      );
      when(
        () => supabase.pullOperationalRows(
          upsertOperationalRow: any(named: 'upsertOperationalRow'),
        ),
      ).thenAnswer((invocation) async {
        final callback =
            invocation.namedArguments[#upsertOperationalRow]
                as Future<void> Function(String, Map<String, dynamic>);
        await callback('customer_sectors', {
          'id': 'sector-1',
          'customer_id': 'customer-1',
          'sector_key': 'breeder',
          'is_active': 0,
          'updated_at': localUpdatedAt,
        });
        return 1;
      });

      final outcome = await service().run();

      expect(outcome.failedTables, contains('customer_sectors'));
      verify(
        () =>
            operational.markRowsFailed('customer_sectors', ['sector-1'], any()),
      ).called(1);
      expect(appliedRemoteRows, 0);
    },
  );

  test(
    'pull-only operational sync still applies remote customer sector',
    () async {
      var appliedRemoteRows = 0;
      when(() => operational.upsertRemoteRow(any(), any())).thenAnswer((_) {
        appliedRemoteRows++;
        return Future<void>.value();
      });
      when(
        () => operational.getRowById('customer_sectors', 'sector-1'),
      ).thenAnswer(
        (_) async => {
          'id': 'sector-1',
          'customerId': 'customer-1',
          'sectorKey': 'breeder',
          'isActive': 0,
          'updatedAt': '2026-08-16T09:00:00.000Z',
          'syncStatus': 'pending',
          'dirtyAt': '2026-08-16T09:00:00.000Z',
        },
      );
      when(
        () => supabase.pullOperationalRows(
          upsertOperationalRow: any(named: 'upsertOperationalRow'),
        ),
      ).thenAnswer((invocation) async {
        final callback =
            invocation.namedArguments[#upsertOperationalRow]
                as Future<void> Function(String, Map<String, dynamic>);
        await callback('customer_sectors', {
          'id': 'sector-1',
          'customer_id': 'customer-1',
          'sector_key': 'breeder',
          'is_active': 1,
          'updated_at': '2026-08-16T09:01:00.000Z',
        });
        return 1;
      });

      await service().run(canPush: false);

      expect(appliedRemoteRows, 1);
    },
  );

  test(
    'dirty pull-only operational rows still accept remote child updates',
    () async {
      var appliedRemoteRows = 0;
      when(() => operational.upsertRemoteRow(any(), any())).thenAnswer((_) {
        appliedRemoteRows++;
        return Future<void>.value();
      });
      when(
        () => operational.getRowById('breeder_bird_movements', 'movement-1'),
      ).thenAnswer(
        (_) async => {
          'id': 'movement-1',
          'updatedAt': '2026-08-16T09:00:00.000Z',
          'syncStatus': 'pending',
        },
      );
      when(
        () => supabase.pullOperationalRows(
          upsertOperationalRow: any(named: 'upsertOperationalRow'),
        ),
      ).thenAnswer((invocation) async {
        final callback =
            invocation.namedArguments[#upsertOperationalRow]
                as Future<void> Function(String, Map<String, dynamic>);
        await callback('breeder_bird_movements', {
          'id': 'movement-1',
          'updated_at': '2026-08-16T09:01:00.000Z',
        });
        return 1;
      });

      await service().run();

      expect(appliedRemoteRows, 1);
    },
  );

  test(
    'pull callback exposes panel tables without legacy audit callbacks',
    () async {
      await service().run();

      final verification = verify(
        () => supabase.pullFromSupabase(
          upsertCustomer: captureAny(named: 'upsertCustomer'),
          upsertFlock: captureAny(named: 'upsertFlock'),
          upsertHatchery: captureAny(named: 'upsertHatchery'),
          upsertHatcheryMachine: any(named: 'upsertHatcheryMachine'),
          upsertPhoto: captureAny(named: 'upsertPhoto'),
          upsertBmkBreed: captureAny(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: captureAny(named: 'upsertBmkEggBreakout'),
          // Matched but NOT captured, so the captured[] indices below stay put.
          upsertBmkOperationalStandard: any(
            named: 'upsertBmkOperationalStandard',
          ),
          upsertAuditSession: captureAny(named: 'upsertAuditSession'),
          upsertGoveeDailyCapture: captureAny(named: 'upsertGoveeDailyCapture'),
          upsertDashboardAction: captureAny(named: 'upsertDashboardAction'),
          upsertLabAnalysisRow: captureAny(named: 'upsertLabAnalysisRow'),
          upsertPanelRow: captureAny(named: 'upsertPanelRow'),
          upsertChickObservation: any(named: 'upsertChickObservation'),
          upsertEggGradingCount: any(named: 'upsertEggGradingCount'),
          upsertPanelSamplingRow: any(named: 'upsertPanelSamplingRow'),
          upsertSyncTombstone: captureAny(named: 'upsertSyncTombstone'),
        ),
      );
      final callback =
          verification.captured[10]
              as Future<void> Function(String, Map<String, dynamic>);
      await callback('egg_storage', {
        'id': 'row-remote',
        'updatedAt': '2026-05-02T00:00:00.000Z',
      });

      verify(() => panels.getRowById('egg_storage', 'row-remote')).called(1);
      verify(
        () => panels.upsertPanelRow(
          'egg_storage',
          any(that: containsPair('id', 'row-remote')),
        ),
      ).called(1);

      final actionCallback =
          verification.captured[8]
              as Future<void> Function(Map<String, dynamic>);
      await actionCallback({
        'id': 'action-remote',
        'updatedAt': '2026-05-02T00:00:00.000Z',
      });
      verify(() => actions.getRowById('action-remote')).called(1);
      verify(
        () => actions.upsertRemoteRow(
          any(that: containsPair('id', 'action-remote')),
        ),
      ).called(1);
    },
  );

  test('reports pending deletes when remote row deletion fails', () async {
    final tombstone = SyncTombstone(
      id: 'customers:customer-1',
      tableName: 'customers',
      rowId: 'customer-1',
      deletedAt: DateTime(2026, 7, 5),
      createdAt: DateTime(2026, 7, 5),
    );
    when(
      () => tombstones.getPendingDeletes(),
    ).thenAnswer((_) async => [tombstone]);
    when(
      () => supabase.deleteRows('customers', ['customer-1']),
    ).thenThrow(StateError('network down'));

    final outcome = await service().run();

    expect(outcome.online, isTrue);
    expect(outcome.pendingDeletes, 1);
    verify(() => tombstones.markFailed(tombstone.id, any())).called(1);
  });

  test(
    'reports no pending deletes after remote row deletion succeeds',
    () async {
      final tombstone = SyncTombstone(
        id: 'customers:customer-1',
        tableName: 'customers',
        rowId: 'customer-1',
        deletedAt: DateTime(2026, 7, 5),
        createdAt: DateTime(2026, 7, 5),
      );
      var pendingRead = 0;
      when(() => tombstones.getPendingDeletes()).thenAnswer((_) async {
        pendingRead++;
        return pendingRead == 1 ? [tombstone] : const <SyncTombstone>[];
      });

      final outcome = await service().run();

      expect(outcome.online, isTrue);
      expect(outcome.pendingDeletes, 0);
      verify(() => tombstones.markSynced(tombstone.id)).called(1);
    },
  );

  // ---------------------------------------------------------------------
  // Push failures must never be reported as a clean sync.
  // ---------------------------------------------------------------------

  /// Makes the operational table `houses` dirty with [rows] rows.
  void makeHousesDirty({int rows = 1}) {
    when(() => operational.getDirtyRows('houses')).thenAnswer(
      (_) async => [
        for (var index = 0; index < rows; index++)
          {
            'id': 'house-$index',
            'customerId': 'customer-1',
            'name': 'House $index',
            'syncStatus': 'pending',
          },
      ],
    );
  }

  test('a rejected table push is reported as failed, not as a clean sync', () {
    makeHousesDirty();
    when(
      () => supabase.upsertRowsStrict('houses', any()),
    ).thenThrow(StateError('relation "houses" does not exist'));

    return service().run().then((outcome) {
      expect(outcome.online, isTrue);
      expect(outcome.failed, 1);
      expect(outcome.failedTables, ['houses']);
      expect(outcome.hasFailures, isTrue);
      expect(outcome.fullySynced, isFalse);
      expect(outcome.failureSummary, contains('houses'));
      expect(outcome.statusMessage, startsWith('Sync incomplete'));
      verify(
        () => operational.markRowsFailed('houses', ['house-0'], any()),
      ).called(1);
    });
  });

  test('other tables in a run with a failing table still succeed', () async {
    makeHousesDirty();
    when(
      () => supabase.upsertRowsStrict('houses', any()),
    ).thenThrow(StateError('relation "houses" does not exist'));
    when(() => customers.getDirtyRows()).thenAnswer(
      (_) async => [
        {'id': 'customer-1', 'name': 'Customer 1', 'syncStatus': 'pending'},
      ],
    );

    final outcome = await service().run();

    // customers + audit session + egg_storage row all still went up.
    expect(outcome.pushed, 3);
    expect(outcome.failed, 1);
    verify(() => customers.markRowsSynced(['customer-1'])).called(1);
    verify(() => sessions.markSessionsSynced(any())).called(1);
    verify(() => panels.markRowsSynced('egg_storage', any())).called(1);
  });

  test(
    'a run with failures does not finish on the clean "Ready" note',
    () async {
      makeHousesDirty(rows: 2);
      when(
        () => supabase.upsertRowsStrict('houses', any()),
      ).thenThrow(StateError('relation "houses" does not exist'));
      final messages = <String>[];

      await service().run(
        onProgress: (progress) => messages.add(progress.message),
      );

      expect(messages, isNot(contains('Ready')));
      expect(messages.last, contains('2 not uploaded'));
    },
  );

  test('a clean run still reports Ready and no failures', () async {
    final messages = <String>[];

    final outcome = await service().run(
      onProgress: (progress) => messages.add(progress.message),
    );

    expect(outcome.failed, 0);
    expect(outcome.failedTables, isEmpty);
    expect(outcome.hasFailures, isFalse);
    expect(outcome.fullySynced, isTrue);
    expect(outcome.statusMessage, startsWith('Sync complete'));
    expect(messages.last, 'Ready');
  });

  test(
    'a failed remote delete is counted as failed, not just pending',
    () async {
      final tombstone = SyncTombstone(
        id: 'customers:customer-1',
        tableName: 'customers',
        rowId: 'customer-1',
        deletedAt: DateTime(2026, 7, 5),
        createdAt: DateTime(2026, 7, 5),
      );
      when(
        () => tombstones.getPendingDeletes(),
      ).thenAnswer((_) async => [tombstone]);
      when(
        () => supabase.deleteRows('customers', ['customer-1']),
      ).thenThrow(StateError('network down'));

      final outcome = await service().run();

      expect(outcome.pendingDeletes, 1);
      expect(outcome.failed, 1);
      expect(outcome.failedTables, contains('customers'));
      expect(outcome.fullySynced, isFalse);
    },
  );

  test('only server-accepted tombstones proceed to remote deletion', () async {
    final missingTarget = SyncTombstone(
      id: 'hatcheries:missing-hatchery',
      tableName: 'hatcheries',
      rowId: 'missing-customer',
      deletedAt: DateTime(2026, 10, 5),
      createdAt: DateTime(2026, 10, 5),
    );
    final qaTarget = SyncTombstone(
      id: 'hatcheries:qa-hatchery',
      tableName: 'hatcheries',
      rowId: 'qa-hatchery',
      deletedAt: DateTime(2026, 10, 5),
      createdAt: DateTime(2026, 10, 5),
    );
    when(
      () => tombstones.getPendingDeletes(),
    ).thenAnswer((_) async => [missingTarget, qaTarget]);
    when(() => supabase.upsertRowsStrict('sync_tombstones', any())).thenAnswer((
      invocation,
    ) async {
      final rows =
          invocation.positionalArguments[1] as List<Map<String, dynamic>>;
      if (rows.length > 1 || rows.single['rowId'] == 'missing-customer') {
        throw StateError('Tombstone target is missing or has no scope');
      }
    });

    final outcome = await service().run();

    expect(outcome.failed, 1);
    expect(outcome.failedTables, contains('sync_tombstones'));
    verify(() => tombstones.markFailed(missingTarget.id, any())).called(1);
    verifyNever(() => tombstones.markSynced(missingTarget.id));
    verify(() => tombstones.markSynced(qaTarget.id)).called(1);
    verify(() => supabase.deleteRows('hatcheries', ['qa-hatchery'])).called(1);
    verifyNever(() => supabase.deleteRows('customers', ['missing-customer']));
    verifyNever(() => supabase.deleteRows('hatcheries', ['missing-customer']));
    verifyNever(
      () => supabase.deleteRows('hatcheries', ['missing-customer', 'qa-hatchery']),
    );
  });

  // ---------------------------------------------------------------------
  // Retry bound: a permanently failing table must not re-attempt its doomed
  // upload on every single run.
  // ---------------------------------------------------------------------

  test(
    'a failing table is not re-attempted while inside its backoff',
    () async {
      makeHousesDirty();
      when(
        () => supabase.upsertRowsStrict('houses', any()),
      ).thenThrow(StateError('relation "houses" does not exist'));

      final first = await service().run();
      final second = await service().run();

      // One doomed round-trip, not two — but the failure stays visible.
      verify(() => supabase.upsertRowsStrict('houses', any())).called(1);
      verify(
        () => operational.markRowsFailed('houses', any(), any()),
      ).called(1);
      expect(first.failed, 1);
      expect(second.failed, 1);
      expect(second.failedTables, ['houses']);
    },
  );

  test('a failing table is re-attempted once its backoff expires', () async {
    makeHousesDirty();
    when(
      () => supabase.upsertRowsStrict('houses', any()),
    ).thenThrow(StateError('relation "houses" does not exist'));

    await service().run();
    clock = clock.add(SyncRetryPolicy.baseBackoff);
    await service().run();

    verify(() => supabase.upsertRowsStrict('houses', any())).called(2);
    // Two consecutive failures → the next window is twice as long.
    expect(retryPolicy.consecutiveFailures('houses'), 2);
    expect(retryPolicy.shouldAttempt('houses'), isFalse);
  });

  test('a successful push clears a table\'s backoff state', () async {
    makeHousesDirty();
    var attempt = 0;
    when(() => supabase.upsertRowsStrict('houses', any())).thenAnswer((
      _,
    ) async {
      attempt++;
      if (attempt == 1) throw StateError('transient');
    });

    final first = await service().run();
    clock = clock.add(SyncRetryPolicy.baseBackoff);
    final second = await service().run();

    expect(first.failed, 1);
    expect(second.failed, 0);
    expect(second.fullySynced, isTrue);
    expect(retryPolicy.consecutiveFailures('houses'), 0);
    expect(retryPolicy.shouldAttempt('houses'), isTrue);
  });

  test('backoff grows exponentially and is capped', () {
    expect(SyncRetryPolicy.backoffFor(1), const Duration(minutes: 1));
    expect(SyncRetryPolicy.backoffFor(2), const Duration(minutes: 2));
    expect(SyncRetryPolicy.backoffFor(3), const Duration(minutes: 4));
    expect(SyncRetryPolicy.backoffFor(4), const Duration(minutes: 8));
    expect(SyncRetryPolicy.backoffFor(5), const Duration(minutes: 16));
    expect(SyncRetryPolicy.backoffFor(6), SyncRetryPolicy.maxBackoff);
    expect(SyncRetryPolicy.backoffFor(50), SyncRetryPolicy.maxBackoff);
  });

  test('sync tombstones delete panel tables before owning tables', () {
    final order = SyncTombstoneRepository.deleteOrder;

    expect(order, contains('egg_storage'));
    expect(order, isNot(contains('audits')));
    expect(order, isNot(contains('sample_records')));
    // Panel sample child tables (e.g. `chick_weights`'s own `_samples`
    // table) use a different deletion mechanism and must never appear here
    // — but breeder-flock-performance ticket 15's legitimately registered
    // `breeder_weighing_samples` also happens to end in `_samples`, so this
    // must check the panel names specifically rather than the suffix.
    for (final panel in PanelSampleSchema.panels) {
      expect(order, isNot(contains(panel.sampleTableName)));
    }
    expect(order, contains('breeder_weighing_samples'));
    expect(order, isNot(contains('agent_conversations')));
    expect(order, isNot(contains('agent_conversation_turns')));
    expect(order, isNot(contains('agent_tool_events')));
    expect(order, isNot(contains('agent_intake_visits')));
    expect(
      order.indexOf('egg_storage'),
      lessThan(order.indexOf('audit_sessions')),
    );
    expect(
      order.indexOf('hatchery_machines'),
      lessThan(order.indexOf('hatcheries')),
    );
  });

  test('sync tombstones delete sampling nodes and states before sessions', () {
    final order = SyncTombstoneRepository.deleteOrder;

    expect(order.indexOf('photos'), lessThan(order.indexOf('egg_storage')));
    expect(
      order.indexOf('photos'),
      lessThan(order.indexOf('panel_sampling_nodes')),
    );
    expect(
      order.indexOf('panel_sampling_nodes'),
      lessThan(order.indexOf('panel_sampling_states')),
    );
    expect(
      order.indexOf('panel_sampling_states'),
      lessThan(order.indexOf('audit_sessions')),
    );
    // Reservations are append-only for a panel and disappear only with the
    // owning session's database cascade.
    expect(order, isNot(contains('panel_sample_serial_reservations')));
  });
}
