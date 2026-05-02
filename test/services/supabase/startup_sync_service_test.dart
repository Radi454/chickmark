import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/repositories/photo_repository.dart';
import 'package:hatchaudit/data/repositories/temperature_rh_repository.dart';
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

class _MockTemperatureRhRepository extends Mock
    implements TemperatureRhRepository {}

class _MockGoveeCaptureRepository extends Mock
    implements GoveeCaptureRepository {}

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
      final temperatureRepo = _MockTemperatureRhRepository();
      final goveeRepo = _MockGoveeCaptureRepository();
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
          upsertTemperatureSession: any(named: 'upsertTemperatureSession'),
          upsertTemperatureReading: any(named: 'upsertTemperatureReading'),
          upsertGoveeDailyCapture: any(named: 'upsertGoveeDailyCapture'),
          upsertGoveeSpotCapture: any(named: 'upsertGoveeSpotCapture'),
          upsertGoveeSpotReading: any(named: 'upsertGoveeSpotReading'),
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
      when(() => temperatureRepo.getAllSessions()).thenAnswer((_) async => []);
      when(() => temperatureRepo.getAllReadings()).thenAnswer((_) async => []);
      when(
        () => goveeRepo.getAllCaptures(),
      ).thenAnswer((_) async => [_capture]);
      when(() => goveeRepo.getAllSpots()).thenAnswer((_) async => [_spot]);
      when(
        () => goveeRepo.getAllReadings(),
      ).thenAnswer((_) async => [_reading]);
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
        temperatureRepository: temperatureRepo,
        goveeCaptureRepository: goveeRepo,
        photoSyncService: photoSync,
      );

      await service.run(
        onProgress: (progress) => progressMessages.add(progress.message),
      );

      verifyInOrder([
        () => supabase.upsertRows('govee_daily_captures', any()),
        () => supabase.upsertRows('govee_spot_captures', any()),
        () => supabase.upsertRows('govee_spot_readings', any()),
      ]);
      expect(progressMessages, contains('Uploading Govee captures'));
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
  spotCount: 1,
  readingCount: 1,
  createdAt: _now,
  updatedAt: _now,
);

final _spot = GoveeSpotCaptureModel(
  id: 'spot-1',
  captureId: 'capture-1',
  spotIndex: 1,
  spotLabel: 'Spot 1',
  warmupStartedAt: _now,
  validStartedAt: _now.add(const Duration(seconds: 60)),
  validEndedAt: _now.add(const Duration(seconds: 120)),
  validDurationSeconds: 60,
  readingCount: 1,
  createdAt: _now,
  updatedAt: _now,
);

final _reading = GoveeSpotReadingModel(
  id: 'reading-1',
  captureId: 'capture-1',
  spotId: 'spot-1',
  readingIndex: 0,
  recordedAt: _now.add(const Duration(seconds: 60)),
  temperatureFahrenheit: 72,
  humidity: 55,
  createdAt: _now,
);
