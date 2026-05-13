import 'package:flutter/foundation.dart';

import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/audit_repository.dart';
import '../../data/repositories/audit_session_repository.dart';
import '../../data/repositories/bmk_repository.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/flock_repository.dart';
import '../../data/repositories/govee_capture_repository.dart';
import '../../data/repositories/hatchery_repository.dart';
import '../../data/repositories/panel_sample_repository.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/station_sample_repository.dart';
import '../../data/repositories/sync_tombstone_repository.dart';
import '../../data/models/panel_sample_schema.dart';
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
  final GoveeCaptureRepository _goveeCaptureRepository;
  final StationSampleRepository _stationSampleRepository;
  final PanelSampleRepository _panelSampleRepository;
  final SyncTombstoneRepository _syncTombstoneRepository;
  final PhotoSyncService _photoSyncService;
  final Set<String> _preservedLocalSampleIds = {};
  final Set<String> _pendingLocalDeleteTargets = {};

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
    GoveeCaptureRepository? goveeCaptureRepository,
    StationSampleRepository? stationSampleRepository,
    PanelSampleRepository? panelSampleRepository,
    SyncTombstoneRepository? syncTombstoneRepository,
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
       _goveeCaptureRepository =
           goveeCaptureRepository ?? GoveeCaptureRepository(),
       _stationSampleRepository =
           stationSampleRepository ?? StationSampleRepository(),
       _panelSampleRepository =
           panelSampleRepository ?? PanelSampleRepository(),
       _syncTombstoneRepository =
           syncTombstoneRepository ?? SyncTombstoneRepository(),
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
    await _pushPendingDeletes(progress);
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

    progress(0.22, 'Uploading hatcheries');
    final hatcheries = await _hatcheryRepository.getAllHatcheries();
    await _supabaseService.upsertRows(
      'hatcheries',
      hatcheries.map((hatchery) => hatchery.toMap()).toList(),
    );
    pushed += hatcheries.length;

    progress(0.32, 'Uploading flocks');
    final flocks = await _flockRepository.getAllFlocks();
    await _supabaseService.upsertRows(
      'flocks',
      flocks.map((flock) => flock.toMap()).toList(),
    );
    pushed += flocks.length;

    progress(0.42, 'Uploading audit sessions');
    final auditSessions = await _auditSessionRepository.getAllSessions(
      limit: 100000,
    );
    await _supabaseService.upsertRows(
      'audit_sessions',
      auditSessions.map((session) => session.toMap()).toList(),
    );
    pushed += auditSessions.length;

    progress(0.47, 'Uploading audits');
    final audits = await _auditRepository.getAllAudits(limit: 100000);
    final syncableAudits = audits
        .where((audit) => audit.status.toLowerCase() != 'draft')
        .toList();
    await _supabaseService.upsertRows(
      'audits',
      syncableAudits.map((audit) => audit.toMap()).toList(),
    );
    pushed += syncableAudits.length;

    progress(0.52, 'Uploading sample records');
    final sampleRecords = await _stationSampleRepository
        .getAllSampleRecordRows();
    await _supabaseService.upsertRows('sample_records', sampleRecords);
    pushed += sampleRecords.length;

    progress(0.56, 'Uploading sample details');
    for (final table in StationSampleRepository.detailTables) {
      final rows = await _stationSampleRepository.getAllDetailRows(table);
      await _supabaseService.upsertRows(table, rows);
      pushed += rows.length;
    }

    progress(0.60, 'Uploading panel samples');
    for (final panel in PanelSampleSchema.panels) {
      final panelRows = await _panelSampleRepository.getAllPanelRows(
        panel.tableName,
      );
      await _supabaseService.upsertRows(panel.tableName, panelRows);
      pushed += panelRows.length;

      final sampleRows = await _panelSampleRepository.getAllPanelSampleRows(
        panel.tableName,
      );
      await _supabaseService.upsertRows(panel.sampleTableName, sampleRows);
      pushed += sampleRows.length;
    }

    progress(0.64, 'Uploading Govee captures');
    final goveeCaptures = await _goveeCaptureRepository.getAllCaptures();
    await _supabaseService.upsertRows(
      'govee_daily_captures',
      goveeCaptures.map((capture) => capture.toMap()).toList(),
    );
    pushed += goveeCaptures.length;

    progress(0.68, 'Preparing photo sync queue');
    final photos = await _photoRepository.getAllPhotos();
    pushed += photos.length;
    return pushed;
  }

  Future<void> _pushPendingDeletes(
    void Function(double value, String message) progress,
  ) async {
    progress(0.70, 'Syncing deletes');
    final pending = await _syncTombstoneRepository.getPendingDeletes();
    if (pending.isEmpty) return;
    try {
      await _supabaseService.upsertRowsStrict(
        SyncTombstoneRepository.tableName,
        pending.map((tombstone) => tombstone.toMap()).toList(),
      );
    } catch (error) {
      for (final tombstone in pending) {
        await _syncTombstoneRepository.markFailed(tombstone.id, error);
      }
      return;
    }
    for (final table in SyncTombstoneRepository.deleteOrder) {
      final tombstones = pending
          .where((tombstone) => tombstone.tableName == table)
          .toList();
      if (tombstones.isEmpty) continue;
      try {
        await _supabaseService.deleteRows(
          table,
          tombstones.map((tombstone) => tombstone.rowId).toList(),
        );
        for (final tombstone in tombstones) {
          await _syncTombstoneRepository.markSynced(tombstone.id);
        }
      } catch (error) {
        for (final tombstone in tombstones) {
          await _syncTombstoneRepository.markFailed(tombstone.id, error);
        }
      }
    }
  }

  Future<int> _pullRemoteData(
    void Function(double value, String message) progress,
  ) async {
    progress(0.72, 'Downloading shared data');
    _preservedLocalSampleIds.clear();
    _pendingLocalDeleteTargets
      ..clear()
      ..addAll(
        (await _syncTombstoneRepository.getPendingDeletes()).map(
          (tombstone) => '${tombstone.tableName}:${tombstone.rowId}',
        ),
      );
    final summary = await _supabaseService.pullFromSupabase(
      upsertCustomer: (row) => _upsertRemoteRow(
        'customers',
        row,
        (value) => _customerRepository.upsertCustomer(value),
      ),
      upsertFlock: (row) => _upsertRemoteRow(
        'flocks',
        row,
        (value) => _flockRepository.upsertFlock(value),
      ),
      upsertHatchery: (row) => _upsertRemoteRow(
        'hatcheries',
        row,
        (value) => _hatcheryRepository.upsertHatchery(value),
      ),
      upsertAudit: (row) => _upsertAuditWithConflictCheck(row),
      upsertPhoto: (row) => _upsertRemoteRow(
        'photos',
        row,
        (value) => _photoRepository.upsertPhoto(value),
      ),
      upsertBmkBreed: (row) => _bmkRepository.upsertBmkBreed(row),
      upsertBmkEggBreakout: (row) => _bmkRepository.upsertBmkEggBreakout(row),
      upsertAuditSession: (row) => _upsertSessionWithConflictCheck(row),
      upsertGoveeDailyCapture: (row) => _upsertGoveeWithConflictCheck(row),
      upsertSampleRecord: (row) => _upsertSampleWithConflictCheck(row),
      upsertSampleHouseDetail: (row) =>
          _upsertSampleDetailUnlessParentPreserved('sample_house_details', row),
      upsertSampleMachineDetail: (row) =>
          _upsertSampleDetailUnlessParentPreserved(
            'sample_machine_details',
            row,
          ),
      upsertSampleBatchDetail: (row) =>
          _upsertSampleDetailUnlessParentPreserved('sample_batch_details', row),
      upsertSampleTimingDetail: (row) =>
          _upsertSampleDetailUnlessParentPreserved(
            'sample_timing_details',
            row,
          ),
      upsertPanelRow: (table, row) =>
          _upsertPanelWithConflictCheck(table, row, isSampleRow: false),
      upsertPanelSampleRow: (table, row) =>
          _upsertPanelWithConflictCheck(table, row, isSampleRow: true),
      upsertSyncTombstone: (row) =>
          _syncTombstoneRepository.upsertRemoteTombstone(row),
    );
    await _syncTombstoneRepository.applyRemoteDeletes();
    progress(0.92, 'Preparing workspace');
    return summary.total;
  }

  Future<void> _upsertAuditWithConflictCheck(
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete('audits', remoteRow)) return;
    await _upsertWithConflictCheck(
      remoteRow,
      getLocal: (id) => _auditRepository.getAuditRowById(id),
      upsert: (row) => _auditRepository.upsertAudit(row),
    );
  }

  Future<void> _upsertSessionWithConflictCheck(
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete('audit_sessions', remoteRow)) return;
    await _upsertWithConflictCheck(
      remoteRow,
      getLocal: (id) => _auditSessionRepository.getSessionRowById(id),
      upsert: (row) => _auditSessionRepository.upsertSessionRow(row),
    );
  }

  Future<void> _upsertGoveeWithConflictCheck(
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete('govee_daily_captures', remoteRow)) return;
    await _upsertWithConflictCheck(
      remoteRow,
      getLocal: (id) => _goveeCaptureRepository.getCaptureRowById(id),
      upsert: (row) => _goveeCaptureRepository.upsertCaptureRow(row),
    );
  }

  Future<void> _upsertSampleWithConflictCheck(
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete('sample_records', remoteRow)) return;
    final applied = await _upsertWithConflictCheck(
      remoteRow,
      getLocal: (id) => _stationSampleRepository.getSampleRecordRowById(id),
      upsert: (row) => _stationSampleRepository.upsertSampleRow(row),
    );
    final id = _rowId(remoteRow);
    if (!applied && id != null) {
      _preservedLocalSampleIds.add(id);
    }
  }

  Future<void> _upsertSampleDetailUnlessParentPreserved(
    String table,
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete(table, remoteRow)) return;
    final sampleId = _sampleRecordId(remoteRow);
    if (sampleId != null && _preservedLocalSampleIds.contains(sampleId)) {
      debugPrint(
        '[SYNC CONFLICT] sample=$sampleId detail=$table -> keeping local',
      );
      return;
    }
    await _stationSampleRepository.upsertDetailRow(table, remoteRow);
  }

  Future<void> _upsertPanelWithConflictCheck(
    String table,
    Map<String, dynamic> remoteRow, {
    required bool isSampleRow,
  }) async {
    if (_hasPendingLocalDelete(table, remoteRow)) return;
    await _upsertWithConflictCheck(
      remoteRow,
      getLocal: (id) => _panelSampleRepository.getRowById(table, id),
      upsert: (row) => isSampleRow
          ? _panelSampleRepository.upsertPanelSampleRow(table, row)
          : _panelSampleRepository.upsertPanelRow(table, row),
    );
  }

  Future<void> _upsertRemoteRow(
    String table,
    Map<String, dynamic> remoteRow,
    Future<void> Function(Map<String, dynamic> row) upsert,
  ) async {
    if (_hasPendingLocalDelete(table, remoteRow)) return;
    await upsert(remoteRow);
  }

  Future<bool> _upsertWithConflictCheck(
    Map<String, dynamic> remoteRow, {
    required Future<Map<String, dynamic>?> Function(String id) getLocal,
    required Future<void> Function(Map<String, dynamic>) upsert,
  }) async {
    final id = _rowId(remoteRow);
    if (id == null || id.isEmpty) {
      await upsert(remoteRow);
      return true;
    }

    final localRow = await getLocal(id);
    if (localRow != null) {
      final localTime = _parseUpdatedAt(localRow);
      final remoteTime = _parseUpdatedAt(remoteRow);
      if (localTime != null &&
          (remoteTime == null || localTime.isAfter(remoteTime))) {
        debugPrint(
          '[SYNC CONFLICT] id=$id local=$localTime remote=$remoteTime -> keeping local',
        );
        return false;
      }
    }

    await upsert(remoteRow);
    return true;
  }

  bool _hasPendingLocalDelete(String table, Map<String, dynamic> row) {
    final idColumn = SyncTombstoneRepository.idColumnForTable(table);
    final rowId = _rowValue(row, idColumn) ?? _rowId(row);
    if (rowId == null) return false;
    return _pendingLocalDeleteTargets.contains('$table:$rowId');
  }

  String? _rowValue(Map<String, dynamic> row, String column) {
    final value = row[column] ?? row[_camelize(column)];
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  String? _rowId(Map<String, dynamic> row) {
    final id = row['id'] ?? row['ID'];
    final value = id?.toString();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String _camelize(String column) {
    final parts = column.split('_');
    if (parts.length <= 1) return column;
    return parts.first +
        parts
            .skip(1)
            .map(
              (part) => part.isEmpty
                  ? part
                  : part[0].toUpperCase() + part.substring(1),
            )
            .join();
  }

  String? _sampleRecordId(Map<String, dynamic> row) {
    final id = row['sampleRecordId'] ?? row['sample_record_id'];
    final value = id?.toString();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  DateTime? _parseUpdatedAt(Map<String, dynamic> row) {
    final raw = row['updatedAt'] ?? row['updated_at'];
    if (raw is DateTime) return raw;
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }
}
