import 'package:flutter/foundation.dart';

import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/audit_repository.dart';
import '../../data/repositories/audit_session_repository.dart';
import '../../data/repositories/bmk_repository.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/flock_repository.dart';
import '../../data/repositories/govee_capture_repository.dart';
import '../../data/repositories/hatchery_repository.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/temperature_rh_repository.dart';
import '../photo/photo_sync_service.dart';
import 'supabase_service.dart';

class StartupSyncProgress {
  final double value;
  final String message;

  const StartupSyncProgress({required this.value, required this.message});
}

class StartupSyncService {
  final SupabaseService _supabaseService;
  final CustomerRepository _customerRepository;
  final FlockRepository _flockRepository;
  final HatcheryRepository _hatcheryRepository;
  final AuditRepository _auditRepository;
  final ActivityLogRepository _activityLogRepository;
  final PhotoRepository _photoRepository;
  final BmkRepository _bmkRepository;
  final AuditSessionRepository _auditSessionRepository;
  final TemperatureRhRepository _temperatureRepository;
  final GoveeCaptureRepository _goveeCaptureRepository;
  final PhotoSyncService _photoSyncService;

  StartupSyncService({
    SupabaseService? supabaseService,
    CustomerRepository? customerRepository,
    FlockRepository? flockRepository,
    HatcheryRepository? hatcheryRepository,
    AuditRepository? auditRepository,
    ActivityLogRepository? activityLogRepository,
    PhotoRepository? photoRepository,
    BmkRepository? bmkRepository,
    AuditSessionRepository? auditSessionRepository,
    TemperatureRhRepository? temperatureRepository,
    GoveeCaptureRepository? goveeCaptureRepository,
    PhotoSyncService? photoSyncService,
  }) : _supabaseService = supabaseService ?? SupabaseService(),
       _customerRepository = customerRepository ?? CustomerRepository(),
       _flockRepository = flockRepository ?? FlockRepository(),
       _hatcheryRepository = hatcheryRepository ?? HatcheryRepository(),
       _auditRepository = auditRepository ?? AuditRepository(),
       _activityLogRepository =
           activityLogRepository ?? ActivityLogRepository(),
       _photoRepository = photoRepository ?? PhotoRepository(),
       _bmkRepository = bmkRepository ?? BmkRepository(),
       _auditSessionRepository =
           auditSessionRepository ?? AuditSessionRepository(),
       _temperatureRepository =
           temperatureRepository ?? TemperatureRhRepository(),
       _goveeCaptureRepository =
           goveeCaptureRepository ?? GoveeCaptureRepository(),
       _photoSyncService = photoSyncService ?? PhotoSyncService();

  Future<void> run({
    ValueChanged<StartupSyncProgress>? onProgress,
    String? userId,
  }) async {
    void progress(double value, String message) {
      onProgress?.call(StartupSyncProgress(value: value, message: message));
    }

    progress(0.04, 'Checking connection');
    final available = await _supabaseService.refreshAvailability();
    if (!available) {
      progress(1, 'Opening offline data');
      return;
    }

    final pushed = await _pushLocalData(progress);
    final pulled = await _pullRemoteData(progress);
    progress(0.96, 'Syncing photos');
    await _photoSyncService.syncPending();
    if (userId != null && userId.isNotEmpty) {
      await _activityLogRepository.log(
        userId,
        'sync',
        details: '$pushed pushed, $pulled pulled',
      );
    }
    progress(1, 'Ready');
  }

  Future<int> _pushLocalData(
    void Function(double value, String message) progress,
  ) async {
    var pushed = 0;
    progress(0.12, 'Uploading customers');
    final customers = await _customerRepository.getAllCustomers();
    await _supabaseService.upsertRows(
      'customers',
      customers.map((customer) => customer.toMap()).toList(),
    );
    pushed += customers.length;

    progress(0.22, 'Uploading flocks');
    final flocks = await _flockRepository.getAllFlocks();
    await _supabaseService.upsertRows(
      'flocks',
      flocks.map((flock) => flock.toMap()).toList(),
    );
    pushed += flocks.length;

    progress(0.32, 'Uploading hatcheries');
    final hatcheries = await _hatcheryRepository.getAllHatcheries();
    await _supabaseService.upsertRows(
      'hatcheries',
      hatcheries.map((hatchery) => hatchery.toMap()).toList(),
    );
    pushed += hatcheries.length;

    progress(0.42, 'Uploading audits');
    final audits = await _auditRepository.getAllAudits(limit: 100000);
    await _supabaseService.upsertRows(
      'audits',
      audits.map((audit) => audit.toMap()).toList(),
    );
    pushed += audits.length;

    progress(0.47, 'Uploading audit sessions');
    final auditSessions = await _auditSessionRepository.getAllSessions(
      limit: 100000,
    );
    await _supabaseService.upsertRows(
      'audit_sessions',
      auditSessions.map((session) => session.toMap()).toList(),
    );
    pushed += auditSessions.length;

    progress(0.52, 'Preparing photo sync queue');
    final photos = await _photoRepository.getAllPhotos();
    pushed += photos.length;

    progress(0.62, 'Uploading temperature logs');
    final sessions = await _temperatureRepository.getAllSessions();
    await _supabaseService.upsertRows(
      'temperature_sessions',
      sessions.map((session) => session.toMap()).toList(),
    );
    pushed += sessions.length;
    final readings = await _temperatureRepository.getAllReadings();
    await _supabaseService.upsertRows(
      'temperature_readings',
      readings.map((reading) => reading.toMap()).toList(),
    );
    pushed += readings.length;

    progress(0.64, 'Uploading Govee captures');
    final goveeCaptures = await _goveeCaptureRepository.getAllCaptures();
    await _supabaseService.upsertRows(
      'govee_daily_captures',
      goveeCaptures.map((capture) => capture.toMap()).toList(),
    );
    pushed += goveeCaptures.length;
    final goveeReadings = await _goveeCaptureRepository.getAllReadings();
    await _supabaseService.upsertRows(
      'govee_place_readings',
      goveeReadings.map((reading) => reading.toMap()).toList(),
    );
    pushed += goveeReadings.length;
    return pushed;
  }

  Future<int> _pullRemoteData(
    void Function(double value, String message) progress,
  ) async {
    progress(0.72, 'Downloading shared data');
    final summary = await _supabaseService.pullFromSupabase(
      upsertCustomer: (row) => _customerRepository.upsertCustomer(row),
      upsertFlock: (row) => _flockRepository.upsertFlock(row),
      upsertHatchery: (row) => _hatcheryRepository.upsertHatchery(row),
      upsertAudit: (row) => _upsertAuditWithConflictCheck(row),
      upsertPhoto: (row) => _photoRepository.upsertPhoto(row),
      upsertBmkBreed: (row) => _bmkRepository.upsertBmkBreed(row),
      upsertBmkEggBreakout: (row) => _bmkRepository.upsertBmkEggBreakout(row),
      upsertAuditSession: (row) =>
          _auditSessionRepository.upsertSessionRow(row),
      upsertTemperatureSession: (row) =>
          _temperatureRepository.upsertSessionRow(row),
      upsertTemperatureReading: (row) =>
          _temperatureRepository.upsertReadingRow(row),
      upsertGoveeDailyCapture: (row) =>
          _goveeCaptureRepository.upsertCaptureRow(row),
      upsertGoveePlaceReading: (row) =>
          _goveeCaptureRepository.upsertReadingRow(row),
    );
    progress(0.92, 'Preparing workspace');
    return summary.total;
  }

  Future<void> _upsertAuditWithConflictCheck(
    Map<String, dynamic> remoteRow,
  ) async {
    await _upsertWithConflictCheck(
      remoteRow,
      getLocal: (id) => _auditRepository.getAuditRowById(id),
      upsert: (row) => _auditRepository.upsertAudit(row),
    );
  }

  Future<void> _upsertWithConflictCheck(
    Map<String, dynamic> remoteRow, {
    required Future<Map<String, dynamic>?> Function(String id) getLocal,
    required Future<void> Function(Map<String, dynamic>) upsert,
  }) async {
    final id = remoteRow['id'] as String?;
    if (id == null || id.isEmpty) {
      await upsert(remoteRow);
      return;
    }

    final localRow = await getLocal(id);
    if (localRow != null) {
      final localTime = DateTime.tryParse('${localRow['updatedAt'] ?? ''}');
      final remoteTime = DateTime.tryParse('${remoteRow['updatedAt'] ?? ''}');
      if (localTime != null &&
          remoteTime != null &&
          localTime.isAfter(remoteTime)) {
        debugPrint(
          '[SYNC CONFLICT] id=$id local=$localTime remote=$remoteTime -> keeping local',
        );
        return;
      }
    }

    await upsert(remoteRow);
  }
}
