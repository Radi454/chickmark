import 'package:flutter/foundation.dart';

import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/audit_session_repository.dart';
import '../../data/repositories/bmk_repository.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/dashboard_action_repository.dart';
import '../../data/repositories/flock_repository.dart';
import '../../data/repositories/govee_capture_repository.dart';
import '../../data/repositories/hatchery_repository.dart';
import '../../data/repositories/lab_analysis_repository.dart';
import '../../data/repositories/panel_sample_repository.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/sync_conflict_repository.dart';
import '../../data/repositories/sync_tombstone_repository.dart';
import '../../data/models/panel_sample_schema.dart';
import '../../data/models/incoming_change.dart';
import '../photo/photo_sync_service.dart';
import 'sync_meta.dart';
import 'supabase_service.dart';

class StartupSyncProgress {
  final double value;
  final String message;

  const StartupSyncProgress({required this.value, required this.message});
}

/// Result of a sync run, surfaced to the UI so the status sector can show
/// connectivity and how many rows moved each direction.
class SyncOutcome {
  final bool online;
  final int pushed;
  final int pulled;
  final int conflicts;
  final int pendingDeletes;

  /// Audit sessions that arrived from the cloud this run (created/edited on
  /// another device). Empty on the first sync / after a DB reset (baseline).
  final List<IncomingChange> incomingSessions;

  /// Count of other cloud-origin records this run (panel rows, Govee captures)
  /// — surfaced as an aggregate line rather than itemized.
  final int otherIncomingCount;

  const SyncOutcome({
    required this.online,
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.pendingDeletes = 0,
    this.incomingSessions = const [],
    this.otherIncomingCount = 0,
  });

  static const SyncOutcome offline = SyncOutcome(online: false);
}

/// Outcome of applying one pulled row. Lets the pull path tell a cloud-origin
/// change (created/edited on another device) apart from the echo of our own
/// just-pushed row (equal `updatedAt`).
enum _UpsertResult { keptLocal, appliedNew, appliedUpdate, appliedUnchanged }

class StartupSyncService {
  static Future<SyncOutcome>? _activeRun;

  final SupabaseService _supabaseService;
  final CustomerRepository _customerRepository;
  final DashboardActionRepository _dashboardActionRepository;
  final FlockRepository _flockRepository;
  final HatcheryRepository _hatcheryRepository;
  final LabAnalysisRepository _labAnalysisRepository;
  final ActivityLogRepository _activityLogRepository;
  final PhotoRepository _photoRepository;
  final BmkRepository _bmkRepository;
  final AuditSessionRepository _auditSessionRepository;
  final GoveeCaptureRepository _goveeCaptureRepository;
  final PanelSampleRepository _panelSampleRepository;
  final SyncTombstoneRepository _syncTombstoneRepository;
  final SyncConflictRepository _syncConflictRepository;
  final PhotoSyncService _photoSyncService;
  final Set<String> _pendingLocalDeleteTargets = {};
  int _conflictsThisRun = 0;
  final List<IncomingChange> _incomingSessionsThisRun = [];
  int _otherIncomingThisRun = 0;
  bool _collectIncoming = false;

  StartupSyncService({
    SupabaseService? supabaseService,
    CustomerRepository? customerRepository,
    DashboardActionRepository? dashboardActionRepository,
    FlockRepository? flockRepository,
    HatcheryRepository? hatcheryRepository,
    LabAnalysisRepository? labAnalysisRepository,
    ActivityLogRepository? activityLogRepository,
    PhotoRepository? photoRepository,
    BmkRepository? bmkRepository,
    AuditSessionRepository? auditSessionRepository,
    GoveeCaptureRepository? goveeCaptureRepository,
    PanelSampleRepository? panelSampleRepository,
    SyncTombstoneRepository? syncTombstoneRepository,
    SyncConflictRepository? syncConflictRepository,
    PhotoSyncService? photoSyncService,
  }) : _supabaseService = supabaseService ?? SupabaseService(),
       _customerRepository = customerRepository ?? CustomerRepository(),
       _dashboardActionRepository =
           dashboardActionRepository ?? DashboardActionRepository(),
       _flockRepository = flockRepository ?? FlockRepository(),
       _hatcheryRepository = hatcheryRepository ?? HatcheryRepository(),
       _labAnalysisRepository =
           labAnalysisRepository ?? LabAnalysisRepository(),
       _activityLogRepository =
           activityLogRepository ?? ActivityLogRepository(),
       _photoRepository = photoRepository ?? PhotoRepository(),
       _bmkRepository = bmkRepository ?? BmkRepository(),
       _auditSessionRepository =
           auditSessionRepository ?? AuditSessionRepository(),
       _goveeCaptureRepository =
           goveeCaptureRepository ?? GoveeCaptureRepository(),
       _panelSampleRepository =
           panelSampleRepository ?? PanelSampleRepository(),
       _syncTombstoneRepository =
           syncTombstoneRepository ?? SyncTombstoneRepository(),
       _syncConflictRepository =
           syncConflictRepository ?? SyncConflictRepository(),
       _photoSyncService = photoSyncService ?? PhotoSyncService();

  Future<SyncOutcome> run({
    ValueChanged<StartupSyncProgress>? onProgress,
    String? userId,
    bool canPush = true,
    bool collectIncoming = false,
  }) {
    final activeRun = _activeRun;
    if (activeRun != null) return activeRun;

    final operation = _run(
      onProgress: onProgress,
      userId: userId,
      canPush: canPush,
      collectIncoming: collectIncoming,
    );
    _activeRun = operation;
    return operation.whenComplete(() {
      if (identical(_activeRun, operation)) {
        _activeRun = null;
      }
    });
  }

  Future<SyncOutcome> _run({
    ValueChanged<StartupSyncProgress>? onProgress,
    String? userId,
    required bool canPush,
    required bool collectIncoming,
  }) async {
    void progress(double value, String message) {
      onProgress?.call(StartupSyncProgress(value: value, message: message));
    }

    progress(0.04, 'Checking connection');
    final available = await _supabaseService.refreshAvailability();
    if (!available) {
      progress(1, 'Opening offline data');
      return SyncOutcome.offline;
    }

    // Read-only roles (customer) never push: RLS rejects their writes anyway,
    // so skip the upload passes and just pull their scoped slice.
    var pushed = 0;
    _conflictsThisRun = 0;
    _incomingSessionsThisRun.clear();
    _otherIncomingThisRun = 0;
    _collectIncoming = collectIncoming;
    if (canPush) {
      await _applyRemoteDeletesBeforePush(progress);
      pushed = await _pushLocalData(progress);
      await _pushPendingDeletes(progress);
    }
    final pulled = await _pullRemoteData(progress);
    progress(0.96, 'Syncing photos');
    await _photoSyncService.syncDownloaded();
    await _photoSyncService.syncPending();
    if (userId != null && userId.isNotEmpty) {
      await _activityLogRepository.log(
        userId,
        'sync',
        details: '$pushed pushed, $pulled pulled, $_conflictsThisRun conflicts',
      );
    }
    final pendingDeletes =
        (await _syncTombstoneRepository.getPendingDeletes()).length;
    progress(1, 'Ready');
    return SyncOutcome(
      online: true,
      pushed: pushed,
      pulled: pulled,
      conflicts: _conflictsThisRun,
      pendingDeletes: pendingDeletes,
      incomingSessions: List.unmodifiable(_incomingSessionsThisRun),
      otherIncomingCount: _otherIncomingThisRun,
    );
  }

  Future<void> _applyRemoteDeletesBeforePush(
    void Function(double value, String message) progress,
  ) async {
    progress(0.08, 'Checking remote deletes');
    await _supabaseService.pullSyncTombstones(
      upsertSyncTombstone: (row) =>
          _syncTombstoneRepository.upsertRemoteTombstone(row),
    );
    await _syncTombstoneRepository.applyRemoteDeletes();
  }

  Future<int> _pushLocalData(
    void Function(double value, String message) progress,
  ) async {
    var pushed = 0;
    progress(0.12, 'Uploading customers');
    final customers = await _customerRepository.getAllCustomers();
    await _supabaseService.upsertRowsStrict(
      'customers',
      customers.map((customer) => customer.toMap()).toList(),
    );
    pushed += customers.length;

    progress(0.22, 'Uploading hatcheries');
    final hatcheries = await _hatcheryRepository.getAllHatcheries();
    await _supabaseService.upsertRowsStrict(
      'hatcheries',
      hatcheries.map((hatchery) => hatchery.toMap()).toList(),
    );
    pushed += hatcheries.length;

    progress(0.32, 'Uploading flocks');
    final flocks = await _flockRepository.getAllFlocks();
    await _supabaseService.upsertRowsStrict(
      'flocks',
      flocks.map((flock) => flock.toMap()).toList(),
    );
    pushed += flocks.length;

    progress(0.42, 'Uploading audit sessions');
    pushed += await _pushDirtySessions();

    progress(0.52, 'Uploading panel rows');
    pushed += await _pushDirtyPanelRows();

    progress(0.64, 'Uploading Govee captures');
    pushed += await _pushDirtyGoveeCaptures();

    progress(0.66, 'Uploading dashboard actions');
    pushed += await _pushDirtyDashboardActions();

    progress(0.68, 'Uploading lab analysis');
    pushed += await _pushDirtyLabAnalysis();

    progress(0.69, 'Preparing photo sync queue');
    final photos = await _photoRepository.getAllPhotos();
    pushed += photos.length;
    return pushed;
  }

  /// Push only sessions whose rows are dirty (pending/failed). On success the
  /// rows are marked synced; on failure they are marked failed (and retried on
  /// the next sync). Device-local sync columns are stripped before upload.
  Future<int> _pushDirtySessions() async {
    final dirty = await _auditSessionRepository.getDirtySessionRows();
    if (dirty.isEmpty) return 0;
    final ids = dirty.map((session) => session.id).toList(growable: false);
    try {
      await _supabaseService.upsertRowsStrict(
        'audit_sessions',
        dirty.map((session) => stripSyncMeta(session.toMap())).toList(),
      );
      await _auditSessionRepository.markSessionsSynced(ids);
      return dirty.length;
    } catch (error) {
      await _auditSessionRepository.markSessionsFailed(ids, error);
      return 0;
    }
  }

  /// Push only dirty panel rows, per table, marking synced/failed per batch.
  Future<int> _pushDirtyPanelRows() async {
    var pushed = 0;
    for (final panel in PanelSampleSchema.panels) {
      final dirty = await _panelSampleRepository.getDirtyRows(panel.tableName);
      if (dirty.isEmpty) continue;
      final ids = dirty
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList(growable: false);
      try {
        await _supabaseService.upsertRowsStrict(
          panel.tableName,
          dirty.map(stripSyncMeta).toList(),
        );
        await _panelSampleRepository.markRowsSynced(panel.tableName, ids);
        pushed += dirty.length;
      } catch (error) {
        await _panelSampleRepository.markRowsFailed(
          panel.tableName,
          ids,
          error,
        );
      }
    }
    return pushed;
  }

  /// Push only dirty Govee captures, marking synced/failed per batch.
  Future<int> _pushDirtyGoveeCaptures() async {
    final dirty = await _goveeCaptureRepository.getDirtyCaptureRows();
    if (dirty.isEmpty) return 0;
    final ids = dirty.map((capture) => capture.id).toList(growable: false);
    try {
      await _supabaseService.upsertRowsStrict(
        'govee_daily_captures',
        dirty.map((capture) => stripSyncMeta(capture.toMap())).toList(),
      );
      await _goveeCaptureRepository.markCapturesSynced(ids);
      return dirty.length;
    } catch (error) {
      await _goveeCaptureRepository.markCapturesFailed(ids, error);
      return 0;
    }
  }

  Future<int> _pushDirtyDashboardActions() async {
    final dirty = await _dashboardActionRepository.getDirtyRows();
    if (dirty.isEmpty) return 0;
    final ids = dirty.map((action) => action.id).toList(growable: false);
    try {
      await _supabaseService.upsertRowsStrict(
        'dashboard_actions',
        dirty.map((action) => stripSyncMeta(action.toMap())).toList(),
      );
      await _dashboardActionRepository.markSynced(ids);
      return dirty.length;
    } catch (error) {
      await _dashboardActionRepository.markFailed(ids, error);
      return 0;
    }
  }

  Future<int> _pushDirtyLabAnalysis() async {
    var pushed = 0;
    for (final table in LabAnalysisRepository.syncTables) {
      final dirty = await _labAnalysisRepository.getDirtyRows(table);
      if (dirty.isEmpty) continue;
      final ids = dirty
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList(growable: false);
      try {
        final prepared = await _prepareDirtyLabAnalysisRows(table, dirty);
        await _supabaseService.upsertRowsStrict(
          table,
          prepared.map(stripSyncMeta).toList(),
        );
        await _labAnalysisRepository.markRowsSynced(table, ids);
        pushed += dirty.length;
      } catch (error) {
        await _labAnalysisRepository.markRowsFailed(table, ids, error);
      }
    }
    return pushed;
  }

  Future<List<Map<String, dynamic>>> _prepareDirtyLabAnalysisRows(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (table != LabAnalysisRepository.reportsTable) return rows;
    final prepared = <Map<String, dynamic>>[];
    for (final row in rows) {
      final copy = Map<String, dynamic>.from(row);
      final localPath = copy['reportFilePath']?.toString();
      final remotePath = copy['reportFileRemotePath']?.toString();
      if ((remotePath == null || remotePath.isEmpty) &&
          localPath != null &&
          localPath.isNotEmpty) {
        final uploaded = await _supabaseService.uploadLabAnalysisReportPdf(
          localPath: localPath,
          customerId: copy['customerId']?.toString() ?? '',
          flockId: copy['flockId']?.toString() ?? '',
          reportDate:
              DateTime.tryParse(copy['reportDate']?.toString() ?? '') ??
              DateTime.now(),
          fileName: copy['reportFileName']?.toString(),
        );
        if (uploaded != null && uploaded.isNotEmpty) {
          copy['reportFileRemotePath'] = uploaded;
          await _labAnalysisRepository.updateReportFileRemotePath(
            reportId: copy['id']?.toString() ?? '',
            fileName: copy['reportFileName']?.toString(),
            remotePath: uploaded,
          );
        }
      }
      prepared.add(copy);
    }
    return prepared;
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
    // Baseline guard: on the first sync / after a DB reset there are no local
    // sessions yet, so the whole pull would look "new". Suppress incoming
    // detection for that run so we don't flood the home screen on first populate.
    if (_collectIncoming) {
      final existing = await _auditSessionRepository.getAllSessions(limit: 1);
      if (existing.isEmpty) _collectIncoming = false;
    }
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
      upsertPhoto: (row) => _upsertRemoteRow(
        'photos',
        row,
        (value) => _photoRepository.upsertPhoto(value),
      ),
      upsertBmkBreed: (row) => _bmkRepository.upsertBmkBreed(row),
      upsertBmkEggBreakout: (row) => _bmkRepository.upsertBmkEggBreakout(row),
      upsertAuditSession: (row) => _upsertSessionWithConflictCheck(row),
      upsertGoveeDailyCapture: (row) => _upsertGoveeWithConflictCheck(row),
      upsertDashboardAction: (row) =>
          _upsertDashboardActionWithConflictCheck(row),
      upsertLabAnalysisRow: (table, row) =>
          _upsertLabAnalysisWithConflictCheck(table, row),
      upsertPanelRow: (table, row) => _upsertPanelWithConflictCheck(table, row),
      upsertSyncTombstone: (row) =>
          _syncTombstoneRepository.upsertRemoteTombstone(row),
    );
    await _syncTombstoneRepository.applyRemoteDeletes();
    progress(0.92, 'Preparing workspace');
    return summary.total;
  }

  Future<void> _upsertSessionWithConflictCheck(
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete('audit_sessions', remoteRow)) return;
    final result = await _upsertWithConflictCheck(
      'audit_sessions',
      remoteRow,
      getLocal: (id) => _auditSessionRepository.getSessionRowById(id),
      upsert: (row) => _auditSessionRepository.upsertSessionRow(row),
    );
    if (_collectIncoming &&
        (result == _UpsertResult.appliedNew ||
            result == _UpsertResult.appliedUpdate)) {
      await _recordIncomingSession(
        remoteRow,
        isNew: result == _UpsertResult.appliedNew,
      );
    }
  }

  Future<void> _upsertGoveeWithConflictCheck(
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete('govee_daily_captures', remoteRow)) return;
    final result = await _upsertWithConflictCheck(
      'govee_daily_captures',
      remoteRow,
      getLocal: (id) => _goveeCaptureRepository.getCaptureRowById(id),
      upsert: (row) => _goveeCaptureRepository.upsertCaptureRow(row),
    );
    _countOtherIncoming(result);
  }

  Future<void> _upsertDashboardActionWithConflictCheck(
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete('dashboard_actions', remoteRow)) return;
    final result = await _upsertWithConflictCheck(
      'dashboard_actions',
      remoteRow,
      getLocal: (id) => _dashboardActionRepository.getRowById(id),
      upsert: (row) => _dashboardActionRepository.upsertRemoteRow(row),
    );
    _countOtherIncoming(result);
  }

  Future<void> _upsertLabAnalysisWithConflictCheck(
    String table,
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete(table, remoteRow)) return;
    final result = await _upsertWithConflictCheck(
      table,
      remoteRow,
      getLocal: (id) => _labAnalysisRepository.getRowById(table, id),
      upsert: (row) => _labAnalysisRepository.upsertRemoteRow(table, row),
    );
    _countOtherIncoming(result);
  }

  Future<void> _upsertPanelWithConflictCheck(
    String table,
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete(table, remoteRow)) return;
    final result = await _upsertWithConflictCheck(
      table,
      remoteRow,
      getLocal: (id) => _panelSampleRepository.getRowById(table, id),
      upsert: (row) => _panelSampleRepository.upsertPanelRow(table, row),
    );
    _countOtherIncoming(result);
  }

  void _countOtherIncoming(_UpsertResult result) {
    if (_collectIncoming &&
        (result == _UpsertResult.appliedNew ||
            result == _UpsertResult.appliedUpdate)) {
      _otherIncomingThisRun++;
    }
  }

  /// Build a home-screen summary for one session that arrived from the cloud.
  /// Customer/flock names resolve from local tables — both are pulled earlier in
  /// this same pass, so the rows already exist. Remote rows are snake_case.
  Future<void> _recordIncomingSession(
    Map<String, dynamic> row, {
    required bool isNew,
  }) async {
    final id = _rowId(row);
    if (id == null) return;
    final customerId = _rowValue(row, 'customer_id');
    final flockId = _rowValue(row, 'flock_id');
    final dateRaw = _rowValue(row, 'date');
    final createdBy = _rowValue(row, 'created_by');
    final updatedAt = (row['updatedAt'] ?? row['updated_at'])?.toString() ?? '';

    var customerName = customerId ?? 'Unknown customer';
    if (customerId != null) {
      final customer = await _customerRepository.getCustomerById(customerId);
      if (customer != null) customerName = customer.name;
    }
    var flockLabel = '';
    if (flockId != null) {
      final flock = await _flockRepository.getFlockById(flockId);
      flockLabel = flock?.flockId ?? '';
    }

    final label = flockLabel.isEmpty
        ? customerName
        : '$customerName · $flockLabel';
    final datePart = dateRaw == null ? '' : dateRaw.split('T').first;
    final by = (createdBy == null || createdBy.isEmpty)
        ? ''
        : ' · by $createdBy';
    final subtitle = (datePart.isEmpty ? 'Audit' : 'Audit $datePart') + by;

    _incomingSessionsThisRun.add(
      IncomingChange(
        table: 'audit_sessions',
        rowId: id,
        isNew: isNew,
        label: label,
        subtitle: subtitle,
        updatedAt: updatedAt,
      ),
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

  Future<_UpsertResult> _upsertWithConflictCheck(
    String table,
    Map<String, dynamic> remoteRow, {
    required Future<Map<String, dynamic>?> Function(String id) getLocal,
    required Future<void> Function(Map<String, dynamic>) upsert,
  }) async {
    final id = _rowId(remoteRow);
    if (id == null || id.isEmpty) {
      await upsert(remoteRow);
      return _UpsertResult.appliedUnchanged;
    }

    final localRow = await getLocal(id);
    if (localRow != null) {
      final localTime = _parseUpdatedAt(localRow);
      final remoteTime = _parseUpdatedAt(remoteRow);
      if (localTime != null &&
          (remoteTime == null || localTime.isAfter(remoteTime))) {
        debugPrint(
          '[SYNC CONFLICT] table=$table id=$id local=$localTime remote=$remoteTime -> keeping local',
        );
        await _recordConflict(
          table: table,
          rowId: id,
          localUpdatedAt: localTime,
          remoteUpdatedAt: remoteTime,
          winner: 'local',
        );
        return _UpsertResult.keptLocal;
      }
      await upsert(remoteRow);
      // Strictly-newer remote = a real edit from another device. Equal
      // timestamps are the echo of our own just-pushed row → not a change.
      if (remoteTime != null &&
          (localTime == null || remoteTime.isAfter(localTime))) {
        return _UpsertResult.appliedUpdate;
      }
      return _UpsertResult.appliedUnchanged;
    }

    await upsert(remoteRow);
    return _UpsertResult.appliedNew;
  }

  Future<void> _recordConflict({
    required String table,
    required String rowId,
    required DateTime? localUpdatedAt,
    required DateTime? remoteUpdatedAt,
    required String winner,
  }) async {
    try {
      await _syncConflictRepository.recordConflict(
        table: table,
        rowId: rowId,
        localUpdatedAt: localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
        winner: winner,
      );
      _conflictsThisRun++;
    } catch (e) {
      debugPrint('[SYNC CONFLICT] persist failed: $e');
    }
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

  DateTime? _parseUpdatedAt(Map<String, dynamic> row) {
    final raw = row['updatedAt'] ?? row['updated_at'];
    if (raw is DateTime) return raw;
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }
}
