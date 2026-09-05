/// Conflict review and resolution for the daily-report sync aggregate
/// (breeder-flock-performance ticket 15, design doc section 5.3 and 13.1):
/// "Conflicting versions are both preserved, in the EXISTING sync_conflicts
/// table ... The report enters a Sync Conflict state, reachable from any
/// state, which BLOCKS approval until resolved ... Resolving returns the
/// report to the state it held before the conflict ... A production
/// manager picks or merges the correct data."
///
/// `BreederBirdLedgerService.submit`/`approve` already refuse a report
/// whose `state` is not exactly `draft`/`submitted` respectively, so a
/// report sitting in `Sync Conflict` is blocked from both transitions for
/// free the moment `BreederDailyReportRepository.enterConflict` sets that
/// state — no separate guard is needed there. This service owns the other
/// half: listing what is unresolved, and applying a production manager's
/// choice.
library;

import 'dart:convert';

import '../../data/repositories/breeder_daily_report_repository.dart';
import '../../data/repositories/breeder_report_aggregate_repository.dart';
import '../../data/repositories/sync_conflict_repository.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/breeder_daily_report_model.dart';

/// Which side of a conflict wins when a production manager resolves it.
/// There is no separate "merged" branch: a merge is simply choosing
/// [keepLocal] after hand-editing the local rows (in the Draft-like state
/// resolution restores) to match what the manager decided the report
/// should say — the resolution UI supports that by not requiring
/// [keepRemote] to be all-or-nothing at the field level before calling
/// this service, only afterward, for which side's ledger to keep as the
/// basis.
enum BreederConflictResolution { keepLocal, keepRemote }

class BreederReportConflictService {
  BreederReportConflictService({
    SyncConflictRepository? conflictRepository,
    BreederDailyReportRepository? reportRepository,
    DatabaseHelper? dbHelper,
  }) : _conflictRepository = conflictRepository ?? SyncConflictRepository(),
       _reportRepository = reportRepository ?? BreederDailyReportRepository(),
       _dbHelper = dbHelper ?? DatabaseHelper();

  final SyncConflictRepository _conflictRepository;
  final BreederDailyReportRepository _reportRepository;
  final DatabaseHelper _dbHelper;

  /// The open (unresolved) conflict for [reportId], if any.
  Future<SyncConflict?> openConflictFor(String reportId) {
    return _conflictRepository.getOpenConflictFor(
      BreederReportAggregateRepository.headerTable,
      reportId,
    );
  }

  Future<List<SyncConflict>> openConflicts({int limit = 100}) async {
    final all = await _conflictRepository.getOpenConflicts(limit: limit);
    return all
        .where(
          (c) => c.tableName == BreederReportAggregateRepository.headerTable,
        )
        .toList(growable: false);
  }

  /// Applies [resolution] to the open conflict on [reportId], restores the
  /// report to its pre-conflict state, and marks the conflict reviewed.
  /// Throws [StateError] if the report has no open conflict.
  Future<BreederDailyReport> resolve({
    required String reportId,
    required BreederConflictResolution resolution,
    required String reviewedBy,
  }) async {
    final conflict = await openConflictFor(reportId);
    if (conflict == null) {
      throw StateError('No open sync conflict for report $reportId');
    }
    final report = await _reportRepository.getById(reportId);
    if (report == null) {
      throw StateError('Report $reportId no longer exists');
    }
    if (!report.isSyncConflict) {
      throw StateError(
        'Report $reportId is not in Sync Conflict (was ${report.state})',
      );
    }

    if (resolution == BreederConflictResolution.keepRemote) {
      await _applyRemote(reportId, conflict);
    }
    // keepLocal: local rows are already exactly what they were when the
    // conflict was detected — nothing to write back. The next push must
    // still be re-armed (see resolveConflict's markDirtyForRetry) with a
    // `base_revision` the cloud will now actually accept: the cloud's
    // current `sync_token`, NOT its `revision`. `revision` is ticket 12's
    // audit counter and can be identical across both sides of this very
    // conflict (neither device transitioned or corrected the report) —
    // adopting it as a concurrency token would defeat the whole guard.
    // Crucially, this resolution never writes to the local `revision`
    // column at all: resolving a sync conflict is neither a state
    // transition nor a post-approval correction, so ticket 12's audit
    // counter must not move as a side effect of it.
    final cloudHeader = _decodeHeader(conflict.remoteDataJson);
    final cloudSyncToken = (cloudHeader?['sync_token'] as num?)?.toInt();

    if (resolution == BreederConflictResolution.keepLocal &&
        cloudSyncToken != null) {
      await _reportRepository.setLastSyncedRevision(reportId, cloudSyncToken);
      await _reportRepository.resolveConflict(
        report,
        markDirtyForRetry: true,
      );
    } else {
      final refreshed = await _reportRepository.getById(reportId) ?? report;
      await _reportRepository.resolveConflict(
        refreshed,
        markDirtyForRetry: resolution == BreederConflictResolution.keepLocal,
      );
    }

    await _conflictRepository.markReviewed(conflict.id, reviewedBy: reviewedBy);
    return (await _reportRepository.getById(reportId))!;
  }

  Map<String, dynamic>? _decodeHeader(String? remoteDataJson) {
    if (remoteDataJson == null || remoteDataJson.isEmpty) return null;
    final decoded = jsonDecode(remoteDataJson);
    if (decoded is! Map) return null;
    final header = decoded['header'];
    return header is Map ? Map<String, dynamic>.from(header) : null;
  }

  /// Overwrites the local header's business columns and replaces the local
  /// child rows for [reportId] with the cloud's version recorded in
  /// [conflict] — the "remote wins" resolution. The report is left synced
  /// (its content now matches the cloud exactly), never re-queued for
  /// push.
  Future<void> _applyRemote(String reportId, SyncConflict conflict) async {
    final decoded = jsonDecode(conflict.remoteDataJson ?? '{}');
    if (decoded is! Map) return;
    final cloudHeader = decoded['header'];
    if (cloudHeader is! Map) return;

    final db = await _dbHelper.db;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        BreederReportAggregateRepository.headerTable,
        {
          'insideTemperature': cloudHeader['inside_temperature'],
          'outsideTemperature': cloudHeader['outside_temperature'],
          'lightHours': cloudHeader['light_hours'],
          'notes': cloudHeader['notes'],
          'revision': cloudHeader['revision'],
          'submittedBy': cloudHeader['submitted_by'],
          'submittedAt': cloudHeader['submitted_at'],
          'approvedBy': cloudHeader['approved_by'],
          'approvedAt': cloudHeader['approved_at'],
          'eggProductionDenominatorFemales':
              cloudHeader['egg_production_denominator_females'],
          'benchmarkProfileVersionAtApproval':
              cloudHeader['benchmark_profile_version_at_approval'],
          'comparisonAxisAtApproval': cloudHeader['comparison_axis_at_approval'],
          'updatedAt': now,
          'syncStatus': 'synced',
          'dirtyAt': null,
          'lastSyncedAt': now,
          'syncError': null,
          // `sync_token`, not `revision` — see the header comment on why
          // these two counters must stay separate.
          'lastSyncedRevision': cloudHeader['sync_token'],
        },
        where: 'id = ?',
        whereArgs: [reportId],
      );

      const childTableKeys = <String, String>{
        'breeder_bird_movements': 'movements',
        'breeder_feed_entries': 'feed_entries',
        'breeder_egg_production_entries': 'egg_production_entries',
        'breeder_egg_inventory_movements': 'inventory_movements',
      };
      for (final entry in childTableKeys.entries) {
        await txn.delete(
          entry.key,
          where: 'reportId = ?',
          whereArgs: [reportId],
        );
        final rows = decoded[entry.value];
        if (rows is! List) continue;
        for (final row in rows) {
          if (row is! Map) continue;
          final camelRow = _camelizeRow(Map<String, dynamic>.from(row));
          await txn.insert(entry.key, {
            ...camelRow,
            'reportId': reportId,
            'syncStatus': 'synced',
            'dirtyAt': null,
            'lastSyncedAt': now,
            'syncError': null,
          });
        }
      }
    });
  }

  Map<String, dynamic> _camelizeRow(Map<String, dynamic> row) {
    return row.map((key, value) => MapEntry(_camelize(key), value));
  }

  String _camelize(String key) {
    if (!key.contains('_')) return key;
    final parts = key.split('_');
    return parts.first +
        parts
            .skip(1)
            .map(
              (part) =>
                  part.isEmpty ? part : part[0].toUpperCase() + part.substring(1),
            )
            .join();
  }
}
