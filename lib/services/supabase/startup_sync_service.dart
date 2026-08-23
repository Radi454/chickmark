import 'package:flutter/foundation.dart';

import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/audit_session_repository.dart';
import '../../data/repositories/bmk_repository.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/dashboard_action_repository.dart';
import '../../data/repositories/egg_grading_repository.dart';
import '../../data/repositories/flock_repository.dart';
import '../../data/repositories/govee_capture_repository.dart';
import '../../data/repositories/hatchery_repository.dart';
import '../../data/repositories/lab_analysis_repository.dart';
import '../../data/repositories/panel_sample_repository.dart';
import '../../data/repositories/performance_sync_repository.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/sync_conflict_repository.dart';
import '../../data/repositories/sync_tombstone_repository.dart';
import '../../data/models/panel_sample_schema.dart';
import '../../data/models/incoming_change.dart';
import '../photo/photo_sync_service.dart';
import 'sync_meta.dart';
import 'sync_retry_policy.dart';
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

  /// Rows that did not reach the cloud this run — a rejected push batch, or a
  /// batch skipped because its table is inside its retry backoff window. Rows
  /// stay dirty locally and are retried later; nothing is lost, but the run is
  /// *not* fully successful and must not be reported as such.
  final int failed;

  /// The tables behind [failed], de-duplicated and sorted. Cheap to collect
  /// (the push loop already knows the table name) and the only thing that makes
  /// a failure diagnosable without digging through logs.
  final List<String> failedTables;

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
    this.failed = 0,
    this.failedTables = const [],
    this.incomingSessions = const [],
    this.otherIncomingCount = 0,
  });

  static const SyncOutcome offline = SyncOutcome(online: false);

  bool get hasFailures => failed > 0 || failedTables.isNotEmpty;

  /// True only when everything this run intended to move actually moved.
  bool get fullySynced => online && !hasFailures && pendingDeletes == 0;

  /// Human-readable one-liner for the failure, or null when there is none.
  /// Suitable for `SettingsProvider.recordSync(error: ...)` and snackbars.
  String? get failureSummary {
    if (!hasFailures) return null;
    const shown = 3;
    final tables = failedTables.length <= shown
        ? failedTables.join(', ')
        : '${failedTables.take(shown).join(', ')} +${failedTables.length - shown} more';
    final rows = failed == 1 ? '1 row' : '$failed rows';
    return tables.isEmpty
        ? '$rows could not reach the cloud'
        : '$rows could not reach the cloud ($tables)';
  }

  /// One-line result for a user-initiated sync (the "Sync now" snackbars).
  String get statusMessage {
    if (!online) return 'Offline — using local data';
    if (hasFailures) {
      return 'Sync incomplete · ↑$pushed ↓$pulled · $failureSummary';
    }
    return 'Sync complete · ↑$pushed ↓$pulled';
  }
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
  final EggGradingRepository _eggGradingRepository;
  final PerformanceSyncRepository _performanceSyncRepository;
  final SyncTombstoneRepository _syncTombstoneRepository;
  final SyncConflictRepository _syncConflictRepository;
  final PhotoSyncService _photoSyncService;
  final SyncRetryPolicy _retryPolicy;
  final Set<String> _pendingLocalDeleteTargets = {};
  int _conflictsThisRun = 0;
  int _failedRowsThisRun = 0;
  final Set<String> _failedTablesThisRun = {};
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
    EggGradingRepository? eggGradingRepository,
    PerformanceSyncRepository? performanceSyncRepository,
    SyncTombstoneRepository? syncTombstoneRepository,
    SyncConflictRepository? syncConflictRepository,
    PhotoSyncService? photoSyncService,
    SyncRetryPolicy? retryPolicy,
  }) : _retryPolicy = retryPolicy ?? SyncRetryPolicy.shared,
       _supabaseService = supabaseService ?? SupabaseService(),
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
       _eggGradingRepository = eggGradingRepository ?? EggGradingRepository(),
       _performanceSyncRepository =
           performanceSyncRepository ?? PerformanceSyncRepository(),
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
    _failedRowsThisRun = 0;
    _failedTablesThisRun.clear();
    _incomingSessionsThisRun.clear();
    _otherIncomingThisRun = 0;
    _collectIncoming = collectIncoming;
    if (canPush) {
      await _applyRemoteDeletesBeforePush(progress);
      pushed = await _pushLocalData(progress);
      await _pushPendingDeletes(progress);
    }
    final pulled = await _pullRemoteData(progress, canPush: canPush);
    progress(0.96, 'Syncing photos');
    await _photoSyncService.syncDownloaded();
    await _photoSyncService.syncPending();
    final failedTables = _failedTablesThisRun.toList()..sort();
    if (userId != null && userId.isNotEmpty) {
      await _activityLogRepository.log(
        userId,
        'sync',
        details:
            '$pushed pushed, $pulled pulled, $_conflictsThisRun conflicts, '
            '$_failedRowsThisRun failed',
      );
    }
    final pendingDeletes =
        (await _syncTombstoneRepository.getPendingDeletes()).length;
    // A run with failures must never end on the same "all done" note as a
    // clean one — that is exactly what hid unreachable tables from the user.
    progress(
      1,
      _failedRowsThisRun == 0
          ? 'Ready'
          : 'Ready — $_failedRowsThisRun not uploaded',
    );
    return SyncOutcome(
      online: true,
      pushed: pushed,
      pulled: pulled,
      conflicts: _conflictsThisRun,
      pendingDeletes: pendingDeletes,
      failed: _failedRowsThisRun,
      failedTables: List.unmodifiable(failedTables),
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
    pushed += await _pushDirtyReferenceRows(
      'customers',
      getDirtyRows: _customerRepository.getDirtyRows,
      markSynced: _customerRepository.markRowsSynced,
      markFailed: _customerRepository.markRowsFailed,
    );

    progress(0.18, 'Uploading operational setup');
    pushed += await _pushDirtyOperationalRows(
      PerformanceSyncRepository.preFlockPushOrder,
    );

    progress(0.22, 'Uploading hatcheries');
    pushed += await _pushDirtyReferenceRows(
      'hatcheries',
      getDirtyRows: _hatcheryRepository.getDirtyRows,
      markSynced: _hatcheryRepository.markRowsSynced,
      markFailed: _hatcheryRepository.markRowsFailed,
    );

    progress(0.24, 'Uploading benchmark standards');
    pushed += await _pushDirtyReferenceRows(
      'bmk_operational_standards',
      getDirtyRows: () async {
        final rows = await _bmkRepository.getDirtyOperationalRows();
        return rows.map(_operationalStandardToRemote).toList(growable: false);
      },
      markSynced: _bmkRepository.markOperationalRowsSynced,
      markFailed: _bmkRepository.markOperationalRowsFailed,
    );

    // FK-ordering note: if the customers push above failed, this and later
    // dependent pushes (flocks/sessions/panels) may fail remotely on FK
    // violations against the still-missing remote customer row. Each push
    // marks only its own rows failed, and everything retries next sync once
    // customers goes through. That is intended degradation, not a bug.
    progress(0.32, 'Uploading flocks');
    pushed += await _pushDirtyReferenceRows(
      'flocks',
      getDirtyRows: () async {
        final rows = await _flockRepository.getDirtyRows();
        // Cloud `flocks` has no updatedAt column — the local SQLite table
        // does. Sending it makes PostgREST reject the whole batch (unknown
        // column), so every dirty flock would fail and then get stuck
        // forever behind the pull's dirty-status guard. Strip it here only;
        // the local column and cloud schema are both untouched.
        return rows
            .map((row) => Map<String, dynamic>.from(row)..remove('updatedAt'))
            .toList(growable: false);
      },
      markSynced: _flockRepository.markRowsSynced,
      markFailed: _flockRepository.markRowsFailed,
    );

    progress(0.38, 'Uploading operational records');
    pushed += await _pushDirtyOperationalRows(
      PerformanceSyncRepository.postFlockPushOrder,
    );

    progress(0.42, 'Uploading audit sessions');
    pushed += await _pushDirtySessions();

    progress(0.52, 'Uploading panel rows');
    pushed += await _pushDirtyPanelRows();

    // The grading counts are children of `egg_quality`, so their parent panel
    // rows must have reached Supabase before this batch can satisfy its FK.
    progress(0.54, 'Uploading egg grading');
    pushed += await _pushDirtyEggGrading();

    progress(0.64, 'Uploading Govee captures');
    pushed += await _pushDirtyGoveeCaptures();

    progress(0.66, 'Uploading dashboard actions');
    pushed += await _pushDirtyDashboardActions();

    progress(0.68, 'Uploading lab analysis');
    pushed += await _pushDirtyLabAnalysis();

    progress(0.69, 'Preparing photo sync queue');
    return pushed;
  }

  /// Record rows that did not reach the cloud this run, so `_run` can report
  /// a failure instead of a clean bill of health.
  void _recordFailedRows(String table, int rows) {
    _failedRowsThisRun += rows;
    _failedTablesThisRun.add(table);
  }

  /// Push one already-collected dirty batch for [table].
  ///
  /// Returns the number of rows that actually reached the cloud — 0 when the
  /// upload was rejected, and 0 when the table is inside its retry backoff
  /// window and the upload was skipped entirely. A failure here never aborts
  /// the sync: the batch's rows are marked failed, the run continues to the
  /// next table and eventually the pull, and the failure is counted so the
  /// caller can surface it.
  Future<int> _pushBatch(
    String table,
    int rowCount, {
    required Future<void> Function() upload,
    required Future<void> Function() markSynced,
    required Future<void> Function(Object error) markFailed,
  }) async {
    if (rowCount == 0) return 0;
    if (!_retryPolicy.shouldAttempt(table)) {
      // Rows keep their existing dirty status; only the doomed round-trip is
      // skipped. Still reported as failed — backing off must not re-hide it.
      _recordFailedRows(table, rowCount);
      return 0;
    }
    try {
      await upload();
      await markSynced();
      _retryPolicy.recordSuccess(table);
      return rowCount;
    } catch (error) {
      await markFailed(error);
      _retryPolicy.recordFailure(table);
      _recordFailedRows(table, rowCount);
      return 0;
    }
  }

  /// Push only dirty reference rows (customers/hatcheries/flocks), marking
  /// synced/failed per batch. Device-local sync columns are stripped before
  /// upload.
  Future<int> _pushDirtyReferenceRows(
    String table, {
    required Future<List<Map<String, dynamic>>> Function() getDirtyRows,
    required Future<void> Function(List<String> ids) markSynced,
    required Future<void> Function(List<String> ids, Object error) markFailed,
  }) async {
    final dirty = await getDirtyRows();
    if (dirty.isEmpty) return 0;
    final ids = dirty
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toList(growable: false);
    return _pushBatch(
      table,
      dirty.length,
      upload: () => _supabaseService.upsertRowsStrict(
        table,
        dirty.map(stripSyncMeta).toList(growable: false),
      ),
      markSynced: () => markSynced(ids),
      markFailed: (error) => markFailed(ids, error),
    );
  }

  Future<int> _pushDirtyOperationalRows(Iterable<String> tables) async {
    var pushed = 0;
    for (final table in tables) {
      final dirty = await _performanceSyncRepository.getDirtyRows(table);
      if (dirty.isEmpty) continue;
      final ids = dirty
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList(growable: false);
      pushed += await _pushBatch(
        table,
        dirty.length,
        upload: () => _supabaseService.upsertRowsStrict(
          table,
          dirty
              .map(
                (row) =>
                    _performanceSyncRepository.prepareRemoteRow(table, row),
              )
              .toList(growable: false),
        ),
        markSynced: () => _performanceSyncRepository.markRowsSynced(table, ids),
        markFailed: (error) =>
            _performanceSyncRepository.markRowsFailed(table, ids, error),
      );
    }
    return pushed;
  }

  /// Push only sessions whose rows are dirty (pending/failed). On success the
  /// rows are marked synced; on failure they are marked failed (and retried on
  /// the next sync). Device-local sync columns are stripped before upload.
  Future<int> _pushDirtySessions() async {
    final dirty = await _auditSessionRepository.getDirtySessionRows();
    if (dirty.isEmpty) return 0;
    final ids = dirty.map((session) => session.id).toList(growable: false);
    return _pushBatch(
      'audit_sessions',
      dirty.length,
      upload: () => _supabaseService.upsertRowsStrict(
        'audit_sessions',
        dirty.map((session) => stripSyncMeta(session.toMap())).toList(),
      ),
      markSynced: () => _auditSessionRepository.markSessionsSynced(ids),
      markFailed: (error) =>
          _auditSessionRepository.markSessionsFailed(ids, error),
    );
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
      pushed += await _pushBatch(
        panel.tableName,
        dirty.length,
        upload: () => _supabaseService.upsertRowsStrict(
          panel.tableName,
          dirty.map(stripSyncMeta).toList(),
        ),
        markSynced: () =>
            _panelSampleRepository.markRowsSynced(panel.tableName, ids),
        markFailed: (error) =>
            _panelSampleRepository.markRowsFailed(panel.tableName, ids, error),
      );
    }
    return pushed;
  }

  Future<int> _pushDirtyEggGrading() async {
    final dirty = await _eggGradingRepository.getDirtyRows();
    if (dirty.isEmpty) return 0;
    final ids = dirty
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toList(growable: false);
    return _pushBatch(
      EggGradingRepository.table,
      dirty.length,
      upload: () => _supabaseService.upsertRowsStrict(
        EggGradingRepository.table,
        dirty.map(stripSyncMeta).toList(growable: false),
      ),
      markSynced: () => _eggGradingRepository.markRowsSynced(ids),
      markFailed: (error) => _eggGradingRepository.markRowsFailed(ids, error),
    );
  }

  /// Push only dirty Govee captures, marking synced/failed per batch.
  Future<int> _pushDirtyGoveeCaptures() async {
    final dirty = await _goveeCaptureRepository.getDirtyCaptureRows();
    if (dirty.isEmpty) return 0;
    final ids = dirty.map((capture) => capture.id).toList(growable: false);
    return _pushBatch(
      'govee_daily_captures',
      dirty.length,
      upload: () => _supabaseService.upsertRowsStrict(
        'govee_daily_captures',
        dirty.map((capture) => stripSyncMeta(capture.toMap())).toList(),
      ),
      markSynced: () => _goveeCaptureRepository.markCapturesSynced(ids),
      markFailed: (error) =>
          _goveeCaptureRepository.markCapturesFailed(ids, error),
    );
  }

  Future<int> _pushDirtyDashboardActions() async {
    final dirty = await _dashboardActionRepository.getDirtyRows();
    if (dirty.isEmpty) return 0;
    final ids = dirty.map((action) => action.id).toList(growable: false);
    return _pushBatch(
      'dashboard_actions',
      dirty.length,
      upload: () => _supabaseService.upsertRowsStrict(
        'dashboard_actions',
        dirty.map((action) => stripSyncMeta(action.toMap())).toList(),
      ),
      markSynced: () => _dashboardActionRepository.markSynced(ids),
      markFailed: (error) => _dashboardActionRepository.markFailed(ids, error),
    );
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
      pushed += await _pushBatch(
        table,
        dirty.length,
        upload: () async {
          final prepared = await _prepareDirtyLabAnalysisRows(table, dirty);
          await _supabaseService.upsertRowsStrict(
            table,
            prepared.map(stripSyncMeta).toList(),
          );
        },
        markSynced: () => _labAnalysisRepository.markRowsSynced(table, ids),
        markFailed: (error) =>
            _labAnalysisRepository.markRowsFailed(table, ids, error),
      );
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

  /// The local `bmk_operational_standards` table is camelCase, the cloud
  /// table is snake_case. Only the mirrored columns are sent; the sync
  /// columns (syncStatus/dirtyAt/lastSyncedAt/syncError) are dropped by
  /// stripSyncMeta in _pushDirtyReferenceRows.
  static const _operationalRemoteColumns = <String, String>{
    'id': 'id',
    'hatcheryId': 'hatchery_id',
    'stationKey': 'station_key',
    'sectorKey': 'sector_key',
    'metricKey': 'metric_key',
    'metricLabel': 'metric_label',
    'unit': 'unit',
    'minValue': 'min_value',
    'maxValue': 'max_value',
    'targetValue': 'target_value',
    'source': 'source',
    'sourceUrl': 'source_url',
    'sourcePhotoPath': 'source_photo_path',
    'sourcePhotoRemotePath': 'source_photo_remote_path',
    'notes': 'notes',
    'sortOrder': 'sort_order',
    'updatedAt': 'updated_at',
  };

  Map<String, dynamic> _operationalStandardToRemote(Map<String, dynamic> row) {
    final remote = <String, dynamic>{};
    for (final entry in _operationalRemoteColumns.entries) {
      if (row.containsKey(entry.key)) remote[entry.value] = row[entry.key];
    }
    return remote;
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
      _recordFailedRows(SyncTombstoneRepository.tableName, pending.length);
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
        _recordFailedRows(table, tombstones.length);
      }
    }
  }

  Future<int> _pullRemoteData(
    void Function(double value, String message) progress, {
    required bool canPush,
  }) async {
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
      upsertCustomer: (row) => _upsertReferenceRow(
        'customers',
        row,
        canPush: canPush,
        getSyncStatus: _customerRepository.getRowSyncStatus,
        upsert: (value) => _customerRepository.upsertCustomer(value),
      ),
      upsertFlock: (row) => _upsertReferenceRow(
        'flocks',
        row,
        canPush: canPush,
        getSyncStatus: _flockRepository.getRowSyncStatus,
        upsert: (value) => _flockRepository.upsertFlock(value),
      ),
      upsertHatchery: (row) => _upsertReferenceRow(
        'hatcheries',
        row,
        canPush: canPush,
        getSyncStatus: _hatcheryRepository.getRowSyncStatus,
        upsert: (value) => _hatcheryRepository.upsertHatchery(value),
      ),
      upsertPhoto: (row) => _upsertRemoteRow(
        'photos',
        row,
        (value) => _photoRepository.upsertPhoto(value),
      ),
      upsertBmkBreed: (row) => _bmkRepository.upsertBmkBreed(row),
      upsertBmkEggBreakout: (row) => _bmkRepository.upsertBmkEggBreakout(row),
      upsertBmkOperationalStandard: (row) => _upsertReferenceRow(
        'bmk_operational_standards',
        row,
        canPush: canPush,
        getSyncStatus: _bmkRepository.getOperationalRowSyncStatus,
        upsert: (value) => _bmkRepository.upsertOperationalStandardRow(value),
      ),
      upsertAuditSession: (row) => _upsertSessionWithConflictCheck(row),
      upsertGoveeDailyCapture: (row) => _upsertGoveeWithConflictCheck(row),
      upsertDashboardAction: (row) =>
          _upsertDashboardActionWithConflictCheck(row),
      upsertLabAnalysisRow: (table, row) =>
          _upsertLabAnalysisWithConflictCheck(table, row),
      upsertPanelRow: (table, row) => _upsertPanelWithConflictCheck(table, row),
      upsertEggGradingCount: _upsertEggGradingWithConflictCheck,
      upsertSyncTombstone: (row) =>
          _syncTombstoneRepository.upsertRemoteTombstone(row),
    );
    final operationalRows = await _supabaseService.pullOperationalRows(
      upsertOperationalRow: _upsertOperationalWithConflictCheck,
    );
    await _syncTombstoneRepository.applyRemoteDeletes();
    progress(0.92, 'Preparing workspace');
    return summary.total + operationalRows;
  }

  Future<void> _upsertOperationalWithConflictCheck(
    String table,
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete(table, remoteRow)) return;
    final result = await _upsertWithConflictCheck(
      table,
      remoteRow,
      getLocal: (id) => _performanceSyncRepository.getRowById(table, id),
      upsert: (row) => _performanceSyncRepository.upsertRemoteRow(table, row),
    );
    _countOtherIncoming(result);
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

  Future<void> _upsertEggGradingWithConflictCheck(
    Map<String, dynamic> remoteRow,
  ) async {
    if (_hasPendingLocalDelete(EggGradingRepository.table, remoteRow)) return;
    final result = await _upsertWithConflictCheck(
      EggGradingRepository.table,
      remoteRow,
      getLocal: _eggGradingRepository.getRowById,
      upsert: _eggGradingRepository.upsertRemoteRow,
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

  /// Reference tables have no updatedAt conflict check (customers/hatcheries
  /// don't carry updatedAt). Guard instead: while a local edit is pending or
  /// failed, the local row wins; it will be pushed on this or the next run.
  ///
  /// That guard only protects an edit this device can actually push. A
  /// device that can never push (canPush: false, e.g. the customer role)
  /// would otherwise sit behind a 'pending'/'failed' status forever — v57
  /// defaults every pre-existing row to 'pending', so a read-only device
  /// would never receive another reference update. When canPush is false,
  /// bypass the dirty-status guard and always apply the remote row; the
  /// repo upsert stamps it synced, so the local status self-heals.
  Future<void> _upsertReferenceRow(
    String table,
    Map<String, dynamic> remoteRow, {
    required bool canPush,
    required Future<String?> Function(String id) getSyncStatus,
    required Future<void> Function(Map<String, dynamic> row) upsert,
  }) async {
    if (_hasPendingLocalDelete(table, remoteRow)) return;
    if (canPush) {
      final id = _rowId(remoteRow);
      if (id != null) {
        final status = await getSyncStatus(id);
        if (status == 'pending' || status == 'failed') return;
      }
    }
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
