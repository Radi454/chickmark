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
import 'package:hatchaudit/data/repositories/dashboard_action_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/repositories/lab_analysis_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/performance_sync_repository.dart';
import 'package:hatchaudit/data/repositories/photo_repository.dart';
import 'package:hatchaudit/data/repositories/sync_tombstone_repository.dart';
import 'package:hatchaudit/services/photo/photo_sync_service.dart';
import 'package:hatchaudit/services/supabase/startup_sync_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

class _MockCustomerRepository extends Mock implements CustomerRepository {}

class _MockDashboardActionRepository extends Mock
    implements DashboardActionRepository {}

class _MockFlockRepository extends Mock implements FlockRepository {}

class _MockHatcheryRepository extends Mock implements HatcheryRepository {}

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

class _MockPerformanceSyncRepository extends Mock
    implements PerformanceSyncRepository {}

class _MockSyncTombstoneRepository extends Mock
    implements SyncTombstoneRepository {}

class _MockPhotoSyncService extends Mock implements PhotoSyncService {}

void main() {
  late _MockSupabaseService supabase;
  late _MockCustomerRepository customers;
  late _MockDashboardActionRepository actions;
  late _MockFlockRepository flocks;
  late _MockHatcheryRepository hatcheries;
  late _MockLabAnalysisRepository labAnalysis;
  late _MockActivityLogRepository activityLog;
  late _MockPhotoRepository photos;
  late _MockBmkRepository bmk;
  late _MockAuditSessionRepository sessions;
  late _MockGoveeCaptureRepository govee;
  late _MockPanelSampleRepository panels;
  late _MockPerformanceSyncRepository operational;
  late _MockSyncTombstoneRepository tombstones;
  late _MockPhotoSyncService photoSync;

  setUpAll(() {
    registerFallbackValue(<Map<String, dynamic>>[]);
    registerFallbackValue(<String>[]);
    registerFallbackValue(Object());
  });

  setUp(() {
    supabase = _MockSupabaseService();
    customers = _MockCustomerRepository();
    actions = _MockDashboardActionRepository();
    flocks = _MockFlockRepository();
    hatcheries = _MockHatcheryRepository();
    labAnalysis = _MockLabAnalysisRepository();
    activityLog = _MockActivityLogRepository();
    photos = _MockPhotoRepository();
    bmk = _MockBmkRepository();
    sessions = _MockAuditSessionRepository();
    govee = _MockGoveeCaptureRepository();
    panels = _MockPanelSampleRepository();
    operational = _MockPerformanceSyncRepository();
    tombstones = _MockSyncTombstoneRepository();
    photoSync = _MockPhotoSyncService();

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
    when(() => customers.markRowsSynced(any())).thenAnswer((_) async {});
    when(() => customers.markRowsFailed(any(), any())).thenAnswer((_) async {});
    when(
      () => customers.getRowSyncStatus(any()),
    ).thenAnswer((_) async => 'synced');
    when(() => hatcheries.getDirtyRows()).thenAnswer((_) async => const []);
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
    when(() => supabase.deleteRows(any(), any())).thenAnswer((_) async {});
    when(
      () => activityLog.log(any(), any(), details: any(named: 'details')),
    ).thenAnswer((_) async {});
    when(
      () => supabase.pullFromSupabase(
        upsertCustomer: any(named: 'upsertCustomer'),
        upsertFlock: any(named: 'upsertFlock'),
        upsertHatchery: any(named: 'upsertHatchery'),
        upsertPhoto: any(named: 'upsertPhoto'),
        upsertBmkBreed: any(named: 'upsertBmkBreed'),
        upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
        upsertAuditSession: any(named: 'upsertAuditSession'),
        upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
        upsertDashboardAction: any(named: 'upsertDashboardAction'),
        upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
        upsertPanelRow: any(named: 'upsertPanelRow'),
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
    labAnalysisRepository: labAnalysis,
    activityLogRepository: activityLog,
    photoRepository: photos,
    bmkRepository: bmk,
    auditSessionRepository: sessions,
    goveeCaptureRepository: govee,
    panelSampleRepository: panels,
    performanceSyncRepository: operational,
    syncTombstoneRepository: tombstones,
    photoSyncService: photoSync,
  );

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
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertDashboardAction: any(named: 'upsertDashboardAction'),
          upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
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
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertDashboardAction: any(named: 'upsertDashboardAction'),
          upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
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
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertDashboardAction: any(named: 'upsertDashboardAction'),
          upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
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
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertDashboardAction: any(named: 'upsertDashboardAction'),
          upsertLabAnalysisRow: any(named: 'upsertLabAnalysisRow'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
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
    'pull callback exposes panel tables without legacy audit callbacks',
    () async {
      await service().run();

      final verification = verify(
        () => supabase.pullFromSupabase(
          upsertCustomer: captureAny(named: 'upsertCustomer'),
          upsertFlock: captureAny(named: 'upsertFlock'),
          upsertHatchery: captureAny(named: 'upsertHatchery'),
          upsertPhoto: captureAny(named: 'upsertPhoto'),
          upsertBmkBreed: captureAny(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: captureAny(named: 'upsertBmkEggBreakout'),
          upsertAuditSession: captureAny(named: 'upsertAuditSession'),
          upsertGoveeDailyCapture: captureAny(named: 'upsertGoveeDailyCapture'),
          upsertDashboardAction: captureAny(named: 'upsertDashboardAction'),
          upsertLabAnalysisRow: captureAny(named: 'upsertLabAnalysisRow'),
          upsertPanelRow: captureAny(named: 'upsertPanelRow'),
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

  test('sync tombstones delete panel tables before owning tables', () {
    final order = SyncTombstoneRepository.deleteOrder;

    expect(order, contains('egg_storage'));
    expect(order, isNot(contains('audits')));
    expect(order, isNot(contains('sample_records')));
    expect(order.where((table) => table.endsWith('_samples')), isEmpty);
    expect(order, isNot(contains('agent_conversations')));
    expect(order, isNot(contains('agent_conversation_turns')));
    expect(order, isNot(contains('agent_tool_events')));
    expect(order, isNot(contains('agent_intake_visits')));
    expect(
      order.indexOf('egg_storage'),
      lessThan(order.indexOf('audit_sessions')),
    );
  });
}
