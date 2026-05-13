import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/data/models/sync_tombstone_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/photo_repository.dart';
import 'package:hatchaudit/data/repositories/station_sample_repository.dart';
import 'package:hatchaudit/data/repositories/sync_tombstone_repository.dart';
import 'package:hatchaudit/services/photo/photo_sync_service.dart';
import 'package:hatchaudit/services/supabase/startup_sync_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

class _MockCustomerRepository extends Mock implements CustomerRepository {}

class _MockFlockRepository extends Mock implements FlockRepository {}

class _MockHatcheryRepository extends Mock implements HatcheryRepository {}

class _MockAuditRepository extends Mock implements AuditRepository {}

class _MockActivityLogRepository extends Mock
    implements ActivityLogRepository {}

class _MockPhotoRepository extends Mock implements PhotoRepository {}

class _MockBmkRepository extends Mock implements BmkRepository {}

class _MockAuditSessionRepository extends Mock
    implements AuditSessionRepository {}

class _MockGoveeCaptureRepository extends Mock
    implements GoveeCaptureRepository {}

class _MockStationSampleRepository extends Mock
    implements StationSampleRepository {}

class _MockPanelSampleRepository extends Mock
    implements PanelSampleRepository {}

class _MockSyncTombstoneRepository extends Mock
    implements SyncTombstoneRepository {}

class _MockPhotoSyncService extends Mock implements PhotoSyncService {}

void main() {
  test(
    'startup sync uploads Govee capture tables in dependency order',
    () async {
      final supabase = _MockSupabaseService();
      final customerRepo = _MockCustomerRepository();
      final flockRepo = _MockFlockRepository();
      final hatcheryRepo = _MockHatcheryRepository();
      final auditRepo = _MockAuditRepository();
      final activityLogRepo = _MockActivityLogRepository();
      final photoRepo = _MockPhotoRepository();
      final bmkRepo = _MockBmkRepository();
      final auditSessionRepo = _MockAuditSessionRepository();
      final goveeRepo = _MockGoveeCaptureRepository();
      final stationSampleRepo = _MockStationSampleRepository();
      final panelSampleRepo = _MockPanelSampleRepository();
      final tombstoneRepo = _MockSyncTombstoneRepository();
      final photoSync = _MockPhotoSyncService();
      final progressMessages = <String>[];

      when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
      when(() => supabase.upsertRows(any(), any())).thenAnswer((_) async {});
      when(
        () => supabase.pullFromSupabase(
          upsertCustomer: any(named: 'upsertCustomer'),
          upsertFlock: any(named: 'upsertFlock'),
          upsertAudit: any(named: 'upsertAudit'),
          upsertHatchery: any(named: 'upsertHatchery'),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertSampleRecord: any(named: 'upsertSampleRecord'),
          upsertSampleHouseDetail: any(named: 'upsertSampleHouseDetail'),
          upsertSampleMachineDetail: any(named: 'upsertSampleMachineDetail'),
          upsertSampleBatchDetail: any(named: 'upsertSampleBatchDetail'),
          upsertSampleTimingDetail: any(named: 'upsertSampleTimingDetail'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
          upsertPanelSampleRow: any(named: 'upsertPanelSampleRow'),
          upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
        ),
      ).thenAnswer((_) async => const SupabasePullSummary());

      when(() => customerRepo.getAllCustomers()).thenAnswer((_) async => []);
      when(() => flockRepo.getAllFlocks()).thenAnswer((_) async => []);
      when(() => hatcheryRepo.getAllHatcheries()).thenAnswer((_) async => []);
      when(
        () => auditRepo.getAllAudits(limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(
        () => auditSessionRepo.getAllSessions(limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(() => photoRepo.getAllPhotos()).thenAnswer((_) async => []);
      when(
        () => goveeRepo.getAllCaptures(),
      ).thenAnswer((_) async => [_capture]);
      when(
        () => stationSampleRepo.getAllSampleRecordRows(),
      ).thenAnswer((_) async => []);
      when(
        () => stationSampleRepo.getAllDetailRows(any()),
      ).thenAnswer((_) async => []);
      when(
        () => panelSampleRepo.getAllPanelRows(any()),
      ).thenAnswer((_) async => []);
      when(
        () => panelSampleRepo.getAllPanelSampleRows(any()),
      ).thenAnswer((_) async => []);
      when(() => tombstoneRepo.getPendingDeletes()).thenAnswer((_) async => []);
      when(() => tombstoneRepo.applyRemoteDeletes()).thenAnswer((_) async {});
      when(() => photoSync.syncPending()).thenAnswer((_) async {});

      final service = StartupSyncService(
        supabaseService: supabase,
        customerRepository: customerRepo,
        flockRepository: flockRepo,
        hatcheryRepository: hatcheryRepo,
        auditRepository: auditRepo,
        activityLogRepository: activityLogRepo,
        photoRepository: photoRepo,
        bmkRepository: bmkRepo,
        auditSessionRepository: auditSessionRepo,
        goveeCaptureRepository: goveeRepo,
        stationSampleRepository: stationSampleRepo,
        panelSampleRepository: panelSampleRepo,
        syncTombstoneRepository: tombstoneRepo,
        photoSyncService: photoSync,
      );

      await service.run(
        onProgress: (progress) => progressMessages.add(progress.message),
      );

      verify(
        () => supabase.upsertRows('govee_daily_captures', any()),
      ).called(1);
      verifyNever(() => supabase.upsertRows('temperature_sessions', any()));
      verifyNever(() => supabase.upsertRows('temperature_readings', any()));
      verifyNever(() => supabase.upsertRows('govee_place_readings', any()));
      expect(progressMessages, contains('Uploading Govee captures'));
    },
  );

  test('startup sync does not upload local draft audit rows', () async {
    final supabase = _MockSupabaseService();
    final customerRepo = _MockCustomerRepository();
    final flockRepo = _MockFlockRepository();
    final hatcheryRepo = _MockHatcheryRepository();
    final auditRepo = _MockAuditRepository();
    final activityLogRepo = _MockActivityLogRepository();
    final photoRepo = _MockPhotoRepository();
    final bmkRepo = _MockBmkRepository();
    final auditSessionRepo = _MockAuditSessionRepository();
    final goveeRepo = _MockGoveeCaptureRepository();
    final stationSampleRepo = _MockStationSampleRepository();
    final panelSampleRepo = _MockPanelSampleRepository();
    final tombstoneRepo = _MockSyncTombstoneRepository();
    final photoSync = _MockPhotoSyncService();

    when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
    when(() => supabase.upsertRows(any(), any())).thenAnswer((_) async {});
    when(
      () => supabase.pullFromSupabase(
        upsertCustomer: any(named: 'upsertCustomer'),
        upsertFlock: any(named: 'upsertFlock'),
        upsertAudit: any(named: 'upsertAudit'),
        upsertHatchery: any(named: 'upsertHatchery'),
        upsertAuditSession: any(named: 'upsertAuditSession'),
        upsertPhoto: any(named: 'upsertPhoto'),
        upsertBmkBreed: any(named: 'upsertBmkBreed'),
        upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
        upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
        upsertSampleRecord: any(named: 'upsertSampleRecord'),
        upsertSampleHouseDetail: any(named: 'upsertSampleHouseDetail'),
        upsertSampleMachineDetail: any(named: 'upsertSampleMachineDetail'),
        upsertSampleBatchDetail: any(named: 'upsertSampleBatchDetail'),
        upsertSampleTimingDetail: any(named: 'upsertSampleTimingDetail'),
        upsertPanelRow: any(named: 'upsertPanelRow'),
        upsertPanelSampleRow: any(named: 'upsertPanelSampleRow'),
        upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
      ),
    ).thenAnswer((_) async => const SupabasePullSummary());

    when(() => customerRepo.getAllCustomers()).thenAnswer((_) async => []);
    when(() => flockRepo.getAllFlocks()).thenAnswer((_) async => []);
    when(() => hatcheryRepo.getAllHatcheries()).thenAnswer((_) async => []);
    when(() => auditRepo.getAllAudits(limit: any(named: 'limit'))).thenAnswer(
      (_) async => [
        _audit('draft-audit', 'draft'),
        _audit('active-audit', 'active'),
      ],
    );
    when(
      () => auditSessionRepo.getAllSessions(limit: any(named: 'limit')),
    ).thenAnswer((_) async => []);
    when(() => photoRepo.getAllPhotos()).thenAnswer((_) async => []);
    when(() => goveeRepo.getAllCaptures()).thenAnswer((_) async => []);
    when(
      () => stationSampleRepo.getAllSampleRecordRows(),
    ).thenAnswer((_) async => []);
    when(
      () => stationSampleRepo.getAllDetailRows(any()),
    ).thenAnswer((_) async => []);
    when(
      () => panelSampleRepo.getAllPanelRows(any()),
    ).thenAnswer((_) async => []);
    when(
      () => panelSampleRepo.getAllPanelSampleRows(any()),
    ).thenAnswer((_) async => []);
    when(() => tombstoneRepo.getPendingDeletes()).thenAnswer((_) async => []);
    when(() => tombstoneRepo.applyRemoteDeletes()).thenAnswer((_) async {});
    when(() => photoSync.syncPending()).thenAnswer((_) async {});

    final service = StartupSyncService(
      supabaseService: supabase,
      customerRepository: customerRepo,
      flockRepository: flockRepo,
      hatcheryRepository: hatcheryRepo,
      auditRepository: auditRepo,
      activityLogRepository: activityLogRepo,
      photoRepository: photoRepo,
      bmkRepository: bmkRepo,
      auditSessionRepository: auditSessionRepo,
      goveeCaptureRepository: goveeRepo,
      stationSampleRepository: stationSampleRepo,
      panelSampleRepository: panelSampleRepo,
      syncTombstoneRepository: tombstoneRepo,
      photoSyncService: photoSync,
    );

    await service.run();

    final rows =
        verify(
              () => supabase.upsertRows('audits', captureAny()),
            ).captured.single
            as List<Map<String, dynamic>>;
    expect(rows.map((row) => row['id']), ['active-audit']);
  });

  test(
    'startup sync pushes normalized sample records before details and photos',
    () async {
      final supabase = _MockSupabaseService();
      final customerRepo = _MockCustomerRepository();
      final flockRepo = _MockFlockRepository();
      final hatcheryRepo = _MockHatcheryRepository();
      final auditRepo = _MockAuditRepository();
      final activityLogRepo = _MockActivityLogRepository();
      final photoRepo = _MockPhotoRepository();
      final bmkRepo = _MockBmkRepository();
      final auditSessionRepo = _MockAuditSessionRepository();
      final goveeRepo = _MockGoveeCaptureRepository();
      final stationSampleRepo = _MockStationSampleRepository();
      final panelSampleRepo = _MockPanelSampleRepository();
      final tombstoneRepo = _MockSyncTombstoneRepository();
      final photoSync = _MockPhotoSyncService();

      when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
      when(() => supabase.upsertRows(any(), any())).thenAnswer((_) async {});
      _stubEmptyPull(supabase);
      when(() => customerRepo.getAllCustomers()).thenAnswer((_) async => []);
      when(() => hatcheryRepo.getAllHatcheries()).thenAnswer((_) async => []);
      when(() => flockRepo.getAllFlocks()).thenAnswer((_) async => []);
      when(
        () => auditSessionRepo.getAllSessions(limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(
        () => auditRepo.getAllAudits(limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(() => photoRepo.getAllPhotos()).thenAnswer((_) async => []);
      when(() => goveeRepo.getAllCaptures()).thenAnswer((_) async => []);
      when(
        () => stationSampleRepo.getAllSampleRecordRows(),
      ).thenAnswer((_) async => [_sample.toMap()]);
      when(
        () => stationSampleRepo.getAllDetailRows('sample_house_details'),
      ).thenAnswer(
        (_) async => [
          {'sampleRecordId': _sample.id, 'houseNo': 'H-1'},
        ],
      );
      when(
        () => stationSampleRepo.getAllDetailRows(any()),
      ).thenAnswer((_) async => []);
      when(
        () => panelSampleRepo.getAllPanelRows(any()),
      ).thenAnswer((_) async => []);
      when(
        () => panelSampleRepo.getAllPanelSampleRows(any()),
      ).thenAnswer((_) async => []);
      when(() => tombstoneRepo.getPendingDeletes()).thenAnswer((_) async => []);
      when(() => tombstoneRepo.applyRemoteDeletes()).thenAnswer((_) async {});
      when(() => photoSync.syncPending()).thenAnswer((_) async {});

      final service = StartupSyncService(
        supabaseService: supabase,
        customerRepository: customerRepo,
        flockRepository: flockRepo,
        hatcheryRepository: hatcheryRepo,
        auditRepository: auditRepo,
        activityLogRepository: activityLogRepo,
        photoRepository: photoRepo,
        bmkRepository: bmkRepo,
        auditSessionRepository: auditSessionRepo,
        goveeCaptureRepository: goveeRepo,
        stationSampleRepository: stationSampleRepo,
        panelSampleRepository: panelSampleRepo,
        syncTombstoneRepository: tombstoneRepo,
        photoSyncService: photoSync,
      );

      await service.run();

      verifyInOrder([
        () => supabase.upsertRows('customers', any()),
        () => supabase.upsertRows('hatcheries', any()),
        () => supabase.upsertRows('flocks', any()),
        () => supabase.upsertRows('audit_sessions', any()),
        () => supabase.upsertRows('audits', any()),
        () => supabase.upsertRows('sample_records', any()),
        () => supabase.upsertRows('sample_house_details', any()),
        () => photoSync.syncPending(),
      ]);
    },
  );

  test(
    'pull keeps a newer local sample when remote timestamp is older or invalid',
    () async {
      final supabase = _MockSupabaseService();
      final customerRepo = _MockCustomerRepository();
      final flockRepo = _MockFlockRepository();
      final hatcheryRepo = _MockHatcheryRepository();
      final auditRepo = _MockAuditRepository();
      final activityLogRepo = _MockActivityLogRepository();
      final photoRepo = _MockPhotoRepository();
      final bmkRepo = _MockBmkRepository();
      final auditSessionRepo = _MockAuditSessionRepository();
      final goveeRepo = _MockGoveeCaptureRepository();
      final stationSampleRepo = _MockStationSampleRepository();
      final panelSampleRepo = _MockPanelSampleRepository();
      final tombstoneRepo = _MockSyncTombstoneRepository();
      final photoSync = _MockPhotoSyncService();

      when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
      when(() => supabase.upsertRows(any(), any())).thenAnswer((_) async {});
      when(() => customerRepo.getAllCustomers()).thenAnswer((_) async => []);
      when(() => hatcheryRepo.getAllHatcheries()).thenAnswer((_) async => []);
      when(() => flockRepo.getAllFlocks()).thenAnswer((_) async => []);
      when(
        () => auditSessionRepo.getAllSessions(limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(
        () => auditRepo.getAllAudits(limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(() => photoRepo.getAllPhotos()).thenAnswer((_) async => []);
      when(() => goveeRepo.getAllCaptures()).thenAnswer((_) async => []);
      when(
        () => stationSampleRepo.getAllSampleRecordRows(),
      ).thenAnswer((_) async => []);
      when(
        () => stationSampleRepo.getAllDetailRows(any()),
      ).thenAnswer((_) async => []);
      when(
        () => panelSampleRepo.getAllPanelRows(any()),
      ).thenAnswer((_) async => []);
      when(
        () => panelSampleRepo.getAllPanelSampleRows(any()),
      ).thenAnswer((_) async => []);
      when(() => tombstoneRepo.getPendingDeletes()).thenAnswer((_) async => []);
      when(() => tombstoneRepo.applyRemoteDeletes()).thenAnswer((_) async {});
      when(() => photoSync.syncPending()).thenAnswer((_) async {});
      when(
        () => stationSampleRepo.getSampleRecordRowById(_sample.id),
      ).thenAnswer((_) async => _sample.toMap());
      when(
        () => stationSampleRepo.upsertSampleRow(any()),
      ).thenAnswer((_) async {});

      when(
        () => supabase.pullFromSupabase(
          upsertCustomer: any(named: 'upsertCustomer'),
          upsertFlock: any(named: 'upsertFlock'),
          upsertAudit: any(named: 'upsertAudit'),
          upsertHatchery: any(named: 'upsertHatchery'),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertSampleRecord: any(named: 'upsertSampleRecord'),
          upsertSampleHouseDetail: any(named: 'upsertSampleHouseDetail'),
          upsertSampleMachineDetail: any(named: 'upsertSampleMachineDetail'),
          upsertSampleBatchDetail: any(named: 'upsertSampleBatchDetail'),
          upsertSampleTimingDetail: any(named: 'upsertSampleTimingDetail'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
          upsertPanelSampleRow: any(named: 'upsertPanelSampleRow'),
          upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
        ),
      ).thenAnswer((invocation) async {
        final upsertSampleRecord =
            invocation.namedArguments[#upsertSampleRecord]
                as Future<void> Function(Map<String, dynamic>);
        await upsertSampleRecord({
          ..._sample.toMap(),
          'notes': 'stale remote',
          'updatedAt': 'not-a-date',
        });
        return const SupabasePullSummary(sampleRecords: 1);
      });

      final service = StartupSyncService(
        supabaseService: supabase,
        customerRepository: customerRepo,
        flockRepository: flockRepo,
        hatcheryRepository: hatcheryRepo,
        auditRepository: auditRepo,
        activityLogRepository: activityLogRepo,
        photoRepository: photoRepo,
        bmkRepository: bmkRepo,
        auditSessionRepository: auditSessionRepo,
        goveeCaptureRepository: goveeRepo,
        stationSampleRepository: stationSampleRepo,
        panelSampleRepository: panelSampleRepo,
        syncTombstoneRepository: tombstoneRepo,
        photoSyncService: photoSync,
      );

      await service.run();

      verifyNever(() => stationSampleRepo.upsertSampleRow(any()));
    },
  );

  test(
    'pending local deletes are not resurrected when tombstone upload fails',
    () async {
      final supabase = _MockSupabaseService();
      final customerRepo = _MockCustomerRepository();
      final flockRepo = _MockFlockRepository();
      final hatcheryRepo = _MockHatcheryRepository();
      final auditRepo = _MockAuditRepository();
      final activityLogRepo = _MockActivityLogRepository();
      final photoRepo = _MockPhotoRepository();
      final bmkRepo = _MockBmkRepository();
      final auditSessionRepo = _MockAuditSessionRepository();
      final goveeRepo = _MockGoveeCaptureRepository();
      final stationSampleRepo = _MockStationSampleRepository();
      final panelSampleRepo = _MockPanelSampleRepository();
      final tombstoneRepo = _MockSyncTombstoneRepository();
      final photoSync = _MockPhotoSyncService();
      final tombstones = [_tombstone('audits', 'audit-1')];

      when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
      when(() => supabase.upsertRows(any(), any())).thenAnswer((_) async {});
      when(
        () => supabase.upsertRowsStrict(any(), any()),
      ).thenThrow(Exception('remote tombstone table unavailable'));
      when(() => supabase.deleteRows(any(), any())).thenAnswer((_) async {});
      when(() => customerRepo.getAllCustomers()).thenAnswer((_) async => []);
      when(() => hatcheryRepo.getAllHatcheries()).thenAnswer((_) async => []);
      when(() => flockRepo.getAllFlocks()).thenAnswer((_) async => []);
      when(
        () => auditSessionRepo.getAllSessions(limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(
        () => auditRepo.getAllAudits(limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(() => photoRepo.getAllPhotos()).thenAnswer((_) async => []);
      when(() => goveeRepo.getAllCaptures()).thenAnswer((_) async => []);
      when(
        () => stationSampleRepo.getAllSampleRecordRows(),
      ).thenAnswer((_) async => []);
      when(
        () => stationSampleRepo.getAllDetailRows(any()),
      ).thenAnswer((_) async => []);
      when(
        () => panelSampleRepo.getAllPanelRows(any()),
      ).thenAnswer((_) async => []);
      when(
        () => panelSampleRepo.getAllPanelSampleRows(any()),
      ).thenAnswer((_) async => []);
      when(
        () => tombstoneRepo.getPendingDeletes(),
      ).thenAnswer((_) async => tombstones);
      when(
        () => tombstoneRepo.markFailed(any(), any()),
      ).thenAnswer((_) async {});
      when(() => tombstoneRepo.applyRemoteDeletes()).thenAnswer((_) async {});
      when(() => photoSync.syncPending()).thenAnswer((_) async {});

      when(
        () => supabase.pullFromSupabase(
          upsertCustomer: any(named: 'upsertCustomer'),
          upsertFlock: any(named: 'upsertFlock'),
          upsertAudit: any(named: 'upsertAudit'),
          upsertHatchery: any(named: 'upsertHatchery'),
          upsertAuditSession: any(named: 'upsertAuditSession'),
          upsertPhoto: any(named: 'upsertPhoto'),
          upsertBmkBreed: any(named: 'upsertBmkBreed'),
          upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertSampleRecord: any(named: 'upsertSampleRecord'),
          upsertSampleHouseDetail: any(named: 'upsertSampleHouseDetail'),
          upsertSampleMachineDetail: any(named: 'upsertSampleMachineDetail'),
          upsertSampleBatchDetail: any(named: 'upsertSampleBatchDetail'),
          upsertSampleTimingDetail: any(named: 'upsertSampleTimingDetail'),
          upsertPanelRow: any(named: 'upsertPanelRow'),
          upsertPanelSampleRow: any(named: 'upsertPanelSampleRow'),
          upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
        ),
      ).thenAnswer((invocation) async {
        final upsertAudit =
            invocation.namedArguments[#upsertAudit]
                as Future<void> Function(Map<String, dynamic>);
        await upsertAudit(_audit('audit-1', 'complete').toMap());
        return const SupabasePullSummary(audits: 1);
      });

      final service = StartupSyncService(
        supabaseService: supabase,
        customerRepository: customerRepo,
        flockRepository: flockRepo,
        hatcheryRepository: hatcheryRepo,
        auditRepository: auditRepo,
        activityLogRepository: activityLogRepo,
        photoRepository: photoRepo,
        bmkRepository: bmkRepo,
        auditSessionRepository: auditSessionRepo,
        goveeCaptureRepository: goveeRepo,
        stationSampleRepository: stationSampleRepo,
        panelSampleRepository: panelSampleRepo,
        syncTombstoneRepository: tombstoneRepo,
        photoSyncService: photoSync,
      );

      await service.run();

      verify(() => tombstoneRepo.markFailed('audits:audit-1', any())).called(1);
      verifyNever(() => supabase.deleteRows(any(), any()));
      verifyNever(() => auditRepo.upsertAudit(any()));
    },
  );

  test(
    'startup sync pushes queued deletes in child-before-parent order',
    () async {
      final supabase = _MockSupabaseService();
      final customerRepo = _MockCustomerRepository();
      final flockRepo = _MockFlockRepository();
      final hatcheryRepo = _MockHatcheryRepository();
      final auditRepo = _MockAuditRepository();
      final activityLogRepo = _MockActivityLogRepository();
      final photoRepo = _MockPhotoRepository();
      final bmkRepo = _MockBmkRepository();
      final auditSessionRepo = _MockAuditSessionRepository();
      final goveeRepo = _MockGoveeCaptureRepository();
      final stationSampleRepo = _MockStationSampleRepository();
      final panelSampleRepo = _MockPanelSampleRepository();
      final tombstoneRepo = _MockSyncTombstoneRepository();
      final photoSync = _MockPhotoSyncService();

      when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
      when(() => supabase.upsertRows(any(), any())).thenAnswer((_) async {});
      when(
        () => supabase.upsertRowsStrict(any(), any()),
      ).thenAnswer((_) async {});
      when(() => supabase.deleteRows(any(), any())).thenAnswer((_) async {});
      _stubEmptyPull(supabase);
      when(() => customerRepo.getAllCustomers()).thenAnswer((_) async => []);
      when(() => hatcheryRepo.getAllHatcheries()).thenAnswer((_) async => []);
      when(() => flockRepo.getAllFlocks()).thenAnswer((_) async => []);
      when(
        () => auditSessionRepo.getAllSessions(limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(
        () => auditRepo.getAllAudits(limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(() => photoRepo.getAllPhotos()).thenAnswer((_) async => []);
      when(() => goveeRepo.getAllCaptures()).thenAnswer((_) async => []);
      when(
        () => stationSampleRepo.getAllSampleRecordRows(),
      ).thenAnswer((_) async => []);
      when(
        () => stationSampleRepo.getAllDetailRows(any()),
      ).thenAnswer((_) async => []);
      when(
        () => panelSampleRepo.getAllPanelRows(any()),
      ).thenAnswer((_) async => []);
      when(
        () => panelSampleRepo.getAllPanelSampleRows(any()),
      ).thenAnswer((_) async => []);
      when(() => tombstoneRepo.getPendingDeletes()).thenAnswer(
        (_) async => [
          _tombstone('audits', 'audit-1'),
          _tombstone('sample_records', 'sample-1'),
          _tombstone('sample_house_details', 'sample-1'),
          _tombstone('customers', 'customer-1'),
        ],
      );
      when(() => tombstoneRepo.markSynced(any())).thenAnswer((_) async {});
      when(() => tombstoneRepo.applyRemoteDeletes()).thenAnswer((_) async {});
      when(() => photoSync.syncPending()).thenAnswer((_) async {});

      final service = StartupSyncService(
        supabaseService: supabase,
        customerRepository: customerRepo,
        flockRepository: flockRepo,
        hatcheryRepository: hatcheryRepo,
        auditRepository: auditRepo,
        activityLogRepository: activityLogRepo,
        photoRepository: photoRepo,
        bmkRepository: bmkRepo,
        auditSessionRepository: auditSessionRepo,
        goveeCaptureRepository: goveeRepo,
        stationSampleRepository: stationSampleRepo,
        panelSampleRepository: panelSampleRepo,
        syncTombstoneRepository: tombstoneRepo,
        photoSyncService: photoSync,
      );

      await service.run();

      verifyInOrder([
        () => supabase.deleteRows('sample_house_details', ['sample-1']),
        () => supabase.deleteRows('sample_records', ['sample-1']),
        () => supabase.deleteRows('audits', ['audit-1']),
        () => supabase.deleteRows('customers', ['customer-1']),
      ]);
      verify(() => tombstoneRepo.markSynced(any())).called(4);
    },
  );
}

final _now = DateTime(2026, 5, 2, 12);

final _capture = GoveeDailyCaptureModel(
  id: 'capture-1',
  customerId: 'customer-1',
  hatcheryId: 'hatchery-1',
  place: TemperaturePlace.eggStorageRoom,
  captureDate: '2026-05-02',
  status: 'completed',
  readingCount: 1,
  chartPointsJson: GoveePlaceReadingModel.listToJson([_reading]),
  createdAt: _now,
  updatedAt: _now,
);

final _sample = StationSampleModel(
  id: 'sample-1',
  auditSessionId: 'session-1',
  legacyAuditId: 'audit-1',
  stationType: 'chicks',
  sectorType: StationSampleModel.sectorChickWeights,
  sampleKind: StationSampleModel.sampleKindHouse,
  sampleMode: StationSampleModel.sampleModeComparison,
  comparisonType: StationSampleModel.comparisonTypeHouse,
  sampleIndex: 1,
  sampleLabel: 'H1',
  houseNo: 'H-1',
  createdAt: _now.subtract(const Duration(days: 1)),
  updatedAt: _now,
);

final _reading = GoveePlaceReadingModel(
  id: 'reading-1',
  captureId: 'capture-1',
  readingIndex: 0,
  recordedAt: _now.add(const Duration(seconds: 60)),
  temperatureFahrenheit: 72,
  humidity: 55,
  createdAt: _now,
);

AuditModel _audit(String id, String status) {
  return AuditModel(
    id: id,
    auditType: 'Egg',
    customerId: 'customer-1',
    flockId: 'flock-1',
    date: DateTime(2026, 5, 2),
    hatchNumber: 1,
    status: status,
    createdBy: 'auditor-1',
    createdAt: _now,
    updatedAt: _now,
  );
}

SyncTombstone _tombstone(String tableName, String rowId) {
  return SyncTombstone(
    id: '$tableName:$rowId',
    tableName: tableName,
    rowId: rowId,
    deletedAt: _now,
    createdAt: _now,
  );
}

void _stubEmptyPull(_MockSupabaseService supabase) {
  when(
    () => supabase.pullFromSupabase(
      upsertCustomer: any(named: 'upsertCustomer'),
      upsertFlock: any(named: 'upsertFlock'),
      upsertAudit: any(named: 'upsertAudit'),
      upsertHatchery: any(named: 'upsertHatchery'),
      upsertAuditSession: any(named: 'upsertAuditSession'),
      upsertPhoto: any(named: 'upsertPhoto'),
      upsertBmkBreed: any(named: 'upsertBmkBreed'),
      upsertBmkEggBreakout: any(named: 'upsertBmkEggBreakout'),
      upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
      upsertSampleRecord: any(named: 'upsertSampleRecord'),
      upsertSampleHouseDetail: any(named: 'upsertSampleHouseDetail'),
      upsertSampleMachineDetail: any(named: 'upsertSampleMachineDetail'),
      upsertSampleBatchDetail: any(named: 'upsertSampleBatchDetail'),
      upsertSampleTimingDetail: any(named: 'upsertSampleTimingDetail'),
      upsertPanelRow: any(named: 'upsertPanelRow'),
      upsertPanelSampleRow: any(named: 'upsertPanelSampleRow'),
      upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
    ),
  ).thenAnswer((_) async => const SupabasePullSummary());
}
