import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/photo_repository.dart';
import 'package:hatchaudit/data/repositories/sync_conflict_repository.dart';
import 'package:hatchaudit/data/repositories/sync_tombstone_repository.dart';
import 'package:hatchaudit/services/photo/photo_sync_service.dart';
import 'package:hatchaudit/services/supabase/startup_sync_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

class _MockCustomerRepository extends Mock implements CustomerRepository {}

class _MockFlockRepository extends Mock implements FlockRepository {}

class _MockHatcheryRepository extends Mock implements HatcheryRepository {}

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

class _MockSyncTombstoneRepository extends Mock
    implements SyncTombstoneRepository {}

class _MockSyncConflictRepository extends Mock
    implements SyncConflictRepository {}

class _MockPhotoSyncService extends Mock implements PhotoSyncService {}

void main() {
  late _MockSupabaseService supabase;
  late _MockCustomerRepository customers;
  late _MockFlockRepository flocks;
  late _MockHatcheryRepository hatcheries;
  late _MockActivityLogRepository activityLog;
  late _MockPhotoRepository photos;
  late _MockBmkRepository bmk;
  late _MockAuditSessionRepository sessions;
  late _MockGoveeCaptureRepository govee;
  late _MockPanelSampleRepository panels;
  late _MockSyncTombstoneRepository tombstones;
  late _MockSyncConflictRepository conflicts;
  late _MockPhotoSyncService photoSync;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    supabase = _MockSupabaseService();
    customers = _MockCustomerRepository();
    flocks = _MockFlockRepository();
    hatcheries = _MockHatcheryRepository();
    activityLog = _MockActivityLogRepository();
    photos = _MockPhotoRepository();
    bmk = _MockBmkRepository();
    sessions = _MockAuditSessionRepository();
    govee = _MockGoveeCaptureRepository();
    panels = _MockPanelSampleRepository();
    tombstones = _MockSyncTombstoneRepository();
    conflicts = _MockSyncConflictRepository();
    photoSync = _MockPhotoSyncService();

    when(() => supabase.refreshAvailability()).thenAnswer((_) async => true);
    // Baseline guard sees a non-empty local table → detection stays enabled.
    when(() => sessions.getAllSessions(limit: any(named: 'limit'))).thenAnswer(
      (_) async => [
        AuditSessionModel(
          id: 'existing',
          customerId: 'c1',
          flockId: 'f1',
          hatcheryId: 'h1',
          date: DateTime(2026, 5, 1),
          createdAt: DateTime(2026, 5, 1),
          updatedAt: DateTime(2026, 5, 1),
        ),
      ],
    );
    when(() => sessions.upsertSessionRow(any())).thenAnswer((_) async {});
    when(() => customers.getCustomerById(any())).thenAnswer(
      (_) async => CustomerModel(
        id: 'c1',
        name: 'Acme',
        createdAt: DateTime(2026, 1, 1),
        createdBy: 'tester',
      ),
    );
    when(() => flocks.getFlockById(any())).thenAnswer(
      (_) async => FlockModel(
        id: 'f1',
        customerId: 'c1',
        flockId: 'Flock 1',
        breed: 'Ross308',
        entryDate: DateTime(2026, 1, 1),
      ),
    );
    when(
      () => tombstones.getPendingDeletes(),
    ).thenAnswer((_) async => const []);
    when(() => tombstones.applyRemoteDeletes()).thenAnswer((_) async {});
    when(() => photoSync.syncDownloaded()).thenAnswer((_) async {});
    when(() => photoSync.syncPending()).thenAnswer((_) async {});
    when(
      () => supabase.pullOperationalRows(
        upsertOperationalRow: any(named: 'upsertOperationalRow'),
      ),
    ).thenAnswer((_) async => 0);
    when(
      () => conflicts.recordConflict(
        table: any(named: 'table'),
        rowId: any(named: 'rowId'),
        localUpdatedAt: any(named: 'localUpdatedAt'),
        remoteUpdatedAt: any(named: 'remoteUpdatedAt'),
        winner: any(named: 'winner'),
      ),
    ).thenAnswer((_) async {});
  });

  StartupSyncService service() => StartupSyncService(
    supabaseService: supabase,
    customerRepository: customers,
    flockRepository: flocks,
    hatcheryRepository: hatcheries,
    activityLogRepository: activityLog,
    photoRepository: photos,
    bmkRepository: bmk,
    auditSessionRepository: sessions,
    goveeCaptureRepository: govee,
    panelSampleRepository: panels,
    syncTombstoneRepository: tombstones,
    syncConflictRepository: conflicts,
    photoSyncService: photoSync,
  );

  // Stub the pull so it drives exactly one audit-session row through the
  // detection path, then returns.
  void stubPull(Map<String, dynamic> remoteRow) {
    when(
      () => supabase.pullFromSupabase(
        upsertCustomer: any(named: 'upsertCustomer'),
        upsertFlock: any(named: 'upsertFlock'),
        upsertHatchery: any(named: 'upsertHatchery'),
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
        upsertEggGradingCount: any(named: 'upsertEggGradingCount'),
        upsertSyncTombstone: any(named: 'upsertSyncTombstone'),
      ),
    ).thenAnswer((invocation) async {
      final cb =
          invocation.namedArguments[#upsertAuditSession]
              as Future<void> Function(Map<String, dynamic>);
      await cb(remoteRow);
      return const SupabasePullSummary(auditSessions: 1);
    });
  }

  Map<String, dynamic> remoteSession({required String updatedAt}) => {
    'id': 's1',
    'customer_id': 'c1',
    'flock_id': 'f1',
    'hatchery_id': 'h1',
    'date': '2026-06-05',
    'created_by': 'jane@x.com',
    'updated_at': updatedAt,
  };

  test('a session with no local copy is flagged as incoming NEW', () async {
    when(() => sessions.getSessionRowById('s1')).thenAnswer((_) async => null);
    stubPull(remoteSession(updatedAt: '2026-06-05T00:00:00.000Z'));

    final outcome = await service().run(canPush: false, collectIncoming: true);

    expect(outcome.incomingSessions, hasLength(1));
    final change = outcome.incomingSessions.single;
    expect(change.isNew, isTrue);
    expect(change.rowId, 's1');
    expect(change.label, 'Acme · Flock 1');
    expect(change.subtitle, contains('jane@x.com'));
  });

  test('a remote row newer than local is flagged as incoming UPDATE', () async {
    when(() => sessions.getSessionRowById('s1')).thenAnswer(
      (_) async => <String, dynamic>{
        'id': 's1',
        'updatedAt': '2026-06-01T00:00:00.000Z',
      },
    );
    stubPull(remoteSession(updatedAt: '2026-06-05T00:00:00.000Z'));

    final outcome = await service().run(canPush: false, collectIncoming: true);

    expect(outcome.incomingSessions, hasLength(1));
    expect(outcome.incomingSessions.single.isNew, isFalse);
  });

  test('equal timestamp (our own push echo) is NOT flagged', () async {
    when(() => sessions.getSessionRowById('s1')).thenAnswer(
      (_) async => <String, dynamic>{
        'id': 's1',
        'updatedAt': '2026-06-05T00:00:00.000Z',
      },
    );
    stubPull(remoteSession(updatedAt: '2026-06-05T00:00:00.000Z'));

    final outcome = await service().run(canPush: false, collectIncoming: true);

    expect(outcome.incomingSessions, isEmpty);
  });

  test(
    'local newer (kept-local conflict) is NOT flagged as incoming',
    () async {
      when(() => sessions.getSessionRowById('s1')).thenAnswer(
        (_) async => <String, dynamic>{
          'id': 's1',
          'updatedAt': '2026-06-09T00:00:00.000Z',
        },
      );
      stubPull(remoteSession(updatedAt: '2026-06-05T00:00:00.000Z'));

      final outcome = await service().run(
        canPush: false,
        collectIncoming: true,
      );

      expect(outcome.incomingSessions, isEmpty);
      verify(
        () => conflicts.recordConflict(
          table: 'audit_sessions',
          rowId: 's1',
          localUpdatedAt: any(named: 'localUpdatedAt'),
          remoteUpdatedAt: any(named: 'remoteUpdatedAt'),
          winner: 'local',
        ),
      ).called(1);
    },
  );

  test('collectIncoming=false collects nothing', () async {
    when(() => sessions.getSessionRowById('s1')).thenAnswer((_) async => null);
    stubPull(remoteSession(updatedAt: '2026-06-05T00:00:00.000Z'));

    final outcome = await service().run(canPush: false);

    expect(outcome.incomingSessions, isEmpty);
  });

  test('baseline guard: no local sessions suppresses detection', () async {
    when(
      () => sessions.getAllSessions(limit: any(named: 'limit')),
    ).thenAnswer((_) async => const []);
    when(() => sessions.getSessionRowById('s1')).thenAnswer((_) async => null);
    stubPull(remoteSession(updatedAt: '2026-06-05T00:00:00.000Z'));

    final outcome = await service().run(canPush: false, collectIncoming: true);

    expect(outcome.incomingSessions, isEmpty);
  });
}
