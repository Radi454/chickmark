/// Push orchestration for the daily-report sync aggregate
/// (breeder-flock-performance ticket 15, design doc section 13.1).
///
/// This is deliberately a separate mover from `StartupSyncService`'s
/// generic per-row push (`PerformanceSyncRepository`/
/// `_pushDirtyOperationalRows`): "a daily report is not a row ... the
/// report is therefore pushed as one aggregate: header and all child rows
/// travel in a single transaction guarded by the header revision, and the
/// cloud side replaces the whole child set for that report within that
/// transaction. A child row is never individually dirty-pushed." Reusing
/// the generic per-row path for these five tables would silently violate
/// that — it pushes each table's dirty rows independently, with no
/// transaction spanning them and no shared revision check, which is
/// exactly the hole design section 13.1 calls out: "a stale child could
/// land after a winning header."
library;

import 'dart:convert';

import '../../data/repositories/breeder_daily_report_repository.dart';
import '../../data/repositories/breeder_report_aggregate_repository.dart';
import '../../data/repositories/sync_conflict_repository.dart';
import '../../services/supabase/supabase_service.dart';

/// One push attempt's outcome for a single report.
class BreederReportPushResult {
  const BreederReportPushResult({
    required this.reportId,
    required this.pushedRowCount,
    required this.conflicted,
    required this.failed,
  });

  final String reportId;

  /// Header + child rows marked synced by this push. Zero when [conflicted]
  /// or when the push failed.
  final int pushedRowCount;
  final bool conflicted;

  /// True on a transport/server error (not a conflict) — the header was
  /// marked failed and will retry on the next sync.
  final bool failed;
}

/// Aggregate result of one [BreederReportSyncService.pushDirtyReportsDetailed]
/// call, in the same shape `StartupSyncService` already tracks per table
/// (pushed rows / conflicts / failures) so it can be folded into the run's
/// overall [SyncOutcome] instead of silently vanishing behind a bare row
/// count.
class BreederReportSyncRunResult {
  const BreederReportSyncRunResult({
    required this.pushedRowCount,
    required this.conflictCount,
    required this.failedReportIds,
  });

  final int pushedRowCount;
  final int conflictCount;
  final List<String> failedReportIds;
}

class BreederReportSyncService {
  BreederReportSyncService({
    SupabaseService? supabaseService,
    BreederReportAggregateRepository? aggregateRepository,
    BreederDailyReportRepository? reportRepository,
    SyncConflictRepository? conflictRepository,
  }) : _supabaseService = supabaseService ?? SupabaseService(),
       _aggregateRepository =
           aggregateRepository ?? BreederReportAggregateRepository(),
       _reportRepository = reportRepository ?? BreederDailyReportRepository(),
       _conflictRepository = conflictRepository ?? SyncConflictRepository();

  final SupabaseService _supabaseService;
  final BreederReportAggregateRepository _aggregateRepository;
  final BreederDailyReportRepository _reportRepository;
  final SyncConflictRepository _conflictRepository;

  static const _childPayloadKeys = <String, String>{
    'breeder_bird_movements': 'movements',
    'breeder_feed_entries': 'feed_entries',
    'breeder_egg_production_entries': 'egg_production_entries',
    'breeder_egg_inventory_movements': 'inventory_movements',
  };

  /// Pushes every report whose aggregate is dirty. Returns the total number
  /// of rows (header + children, across every pushed report) that reached
  /// the cloud — mirroring `StartupSyncService._pushBatch`'s return
  /// convention, so it can simply be added into the same running total.
  /// Use [pushDirtyReportsDetailed] instead when the caller also needs to
  /// fold conflicts/failures into its own run-level counters.
  Future<int> pushDirtyReports() async {
    final result = await pushDirtyReportsDetailed();
    return result.pushedRowCount;
  }

  Future<BreederReportSyncRunResult> pushDirtyReportsDetailed() async {
    final reportIds = await _aggregateRepository.reportIdsNeedingPush();
    var pushed = 0;
    var conflicts = 0;
    final failed = <String>[];
    for (final reportId in reportIds) {
      final result = await pushReport(reportId);
      pushed += result.pushedRowCount;
      if (result.conflicted) conflicts++;
      if (result.failed) failed.add(reportId);
    }
    return BreederReportSyncRunResult(
      pushedRowCount: pushed,
      conflictCount: conflicts,
      failedReportIds: List.unmodifiable(failed),
    );
  }

  /// Pushes one report's aggregate. Never throws on a rejected push
  /// (recorded as a conflict instead) or on a transport failure (the
  /// header is marked failed and this returns a zero-row result) — the
  /// caller's retry loop is the same "count it, move on" contract
  /// `StartupSyncService._pushBatch` uses for every other table.
  Future<BreederReportPushResult> pushReport(String reportId) async {
    final snapshot = await _aggregateRepository.buildSnapshot(reportId);
    if (snapshot == null) {
      return BreederReportPushResult(
        reportId: reportId,
        pushedRowCount: 0,
        conflicted: false,
        failed: false,
      );
    }

    final header = snapshot.header;
    // `lastSyncedRevision` is local-only bookkeeping that tracks the
    // CLOUD's `sync_token` — a concurrency counter kept deliberately
    // separate from the `revision` audit column (ticket 12's user-facing
    // correction counter, which this service never reads or writes). See
    // `push_breeder_daily_report_aggregate`'s header comment
    // (supabase/migrations_unapplied/0013_...sql) for why the two must
    // never be conflated: `revision` can be identical across two devices
    // that never transitioned or corrected the report, so gating
    // concurrency on it would let a second push silently overwrite a
    // first one's already-accepted children with no conflict raised.
    final baseRevision = (header['lastSyncedRevision'] as num?)?.toInt() ?? 0;

    final payload = <String, dynamic>{
      'header': toSupabaseUpsertPayload('breeder_daily_reports', header),
    };
    for (final entry in _childPayloadKeys.entries) {
      final rows = snapshot.children[entry.key] ?? const [];
      payload[entry.value] = rows
          .map((row) => toSupabaseUpsertPayload(entry.key, row))
          .toList(growable: false);
    }

    try {
      final result = await _supabaseService.pushBreederDailyReportAggregate(
        payload,
        baseRevision: baseRevision,
      );
      final conflicted = result['conflict'] == true;
      if (!conflicted) {
        // The RPC returns the NEW `sync_token` it just wrote — that is
        // what this device must present as `base_revision` on its next
        // push, not its own `revision` value (see comment above).
        final syncToken = (result['sync_token'] as num).toInt();
        await _aggregateRepository.markSynced(
          snapshot,
          syncToken: syncToken,
        );
        return BreederReportPushResult(
          reportId: reportId,
          pushedRowCount: snapshot.rowCount,
          conflicted: false,
          failed: false,
        );
      }

      final cloud = Map<String, dynamic>.from(
        (result['cloud'] as Map?) ?? const {},
      );
      await _recordConflict(reportId: reportId, payload: payload, cloud: cloud);
      return BreederReportPushResult(
        reportId: reportId,
        pushedRowCount: 0,
        conflicted: true,
        failed: false,
      );
    } catch (error) {
      await _aggregateRepository.markFailed(reportId, error);
      return BreederReportPushResult(
        reportId: reportId,
        pushedRowCount: 0,
        conflicted: false,
        failed: true,
      );
    }
  }

  Future<void> _recordConflict({
    required String reportId,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> cloud,
  }) async {
    final report = await _reportRepository.getById(reportId);
    if (report == null) return;

    final cloudHeader = Map<String, dynamic>.from(
      (cloud['header'] as Map?) ?? const {},
    );
    final remoteUpdatedAt = DateTime.tryParse(
      (cloudHeader['updated_at'] ?? cloudHeader['updatedAt'])?.toString() ??
          '',
    );
    final localUpdatedAtRaw = (payload['header'] as Map)['updated_at'];
    final localUpdatedAt = DateTime.tryParse(localUpdatedAtRaw?.toString() ?? '');

    await _conflictRepository.recordConflictWithPayload(
      table: BreederReportAggregateRepository.headerTable,
      rowId: reportId,
      localUpdatedAt: localUpdatedAt,
      remoteUpdatedAt: remoteUpdatedAt,
      localDataJson: jsonEncode(payload),
      remoteDataJson: jsonEncode(cloud),
    );
    await _reportRepository.enterConflict(report);
  }
}
