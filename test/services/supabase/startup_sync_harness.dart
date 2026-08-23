import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/repositories/egg_grading_repository.dart';
import 'package:hatchaudit/services/photo/photo_sync_service.dart';
import 'package:hatchaudit/services/supabase/startup_sync_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

/// Minimal hand-rolled fake used by the startup-sync push tests. Unlike the
/// mocktail mocks in `startup_sync_service_test.dart` (which stub each call
/// site individually), this fake records every pushed batch by table name so
/// tests can assert on the exact payload shape, and lets a test simulate a
/// remote failure for one or more tables.
///
/// Only [BmkRepository] talks to a real (isolated, per-test) sqlite database;
/// every other repository used by [buildService] is the real repository too,
/// wired to the same test database via `useIsolatedAppDatabase()`. None of
/// them have dirty rows in these tests, so their push/pull passes are no-ops.
class FakeSupabaseService extends Fake implements SupabaseService {
  FakeSupabaseService({
    Set<String> failUpsertsFor = const {},
    Map<String, List<Map<String, dynamic>>> remoteRows = const {},
  }) : _failUpsertsFor = failUpsertsFor,
       _remoteRows = remoteRows;

  final Set<String> _failUpsertsFor;

  /// Rows a test wants the pull pass to "receive" from the cloud, keyed by
  /// table name. Only tables with a wired callback below actually get
  /// delivered; add a table here as pull tests need it.
  final Map<String, List<Map<String, dynamic>>> _remoteRows;

  /// Every batch handed to [upsertRowsStrict], keyed by table name.
  final Map<String, List<Map<String, dynamic>>> upserts = {};

  /// Every remote delete request, keyed by table name.
  final Map<String, List<String>> deletes = {};

  /// Pull callback order, so child-table tests can assert FK-safe delivery.
  final List<String> pulledTables = [];

  @override
  Future<bool> refreshAvailability() async => true;

  @override
  Future<void> upsertRowsStrict(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (_failUpsertsFor.contains(table)) {
      throw StateError('simulated upsert failure for $table');
    }
    upserts.putIfAbsent(table, () => []).addAll(rows);
  }

  @override
  Future<void> upsertRows(String table, List<Map<String, dynamic>> rows) async {
    upserts.putIfAbsent(table, () => []).addAll(rows);
  }

  @override
  Future<void> deleteRows(String table, List<String> ids) async {
    deletes.putIfAbsent(table, () => []).addAll(ids);
  }

  @override
  Future<int> pullSyncTombstones({
    required Future<void> Function(Map<String, dynamic>) upsertSyncTombstone,
  }) async => 0;

  @override
  Future<SupabasePullSummary> pullFromSupabase({
    required Future<void> Function(Map<String, dynamic>) upsertCustomer,
    required Future<void> Function(Map<String, dynamic>) upsertFlock,
    Future<void> Function(Map<String, dynamic>)? upsertHatchery,
    Future<void> Function(Map<String, dynamic>)? upsertAuditSession,
    Future<void> Function(Map<String, dynamic>)? upsertPhoto,
    Future<void> Function(Map<String, dynamic>)? upsertBmkBreed,
    Future<void> Function(Map<String, dynamic>)? upsertBmkEggBreakout,
    Future<void> Function(Map<String, dynamic>)? upsertBmkOperationalStandard,
    Future<void> Function(Map<String, dynamic>)? upsertGoveeDailyCapture,
    Future<void> Function(Map<String, dynamic>)? upsertDashboardAction,
    Future<void> Function(String table, Map<String, dynamic> row)?
    upsertLabAnalysisRow,
    Future<void> Function(String table, Map<String, dynamic> row)?
    upsertPanelRow,
    Future<void> Function(Map<String, dynamic>)? upsertEggGradingCount,
    Future<void> Function(Map<String, dynamic>)? upsertSyncTombstone,
  }) async {
    if (upsertBmkOperationalStandard != null) {
      for (final row in _remoteRows['bmk_operational_standards'] ?? const []) {
        await upsertBmkOperationalStandard(row);
      }
    }
    var panelRows = 0;
    if (upsertPanelRow != null) {
      for (final panel in PanelSampleSchema.panels) {
        for (final row in _remoteRows[panel.tableName] ?? const []) {
          pulledTables.add(panel.tableName);
          await upsertPanelRow(panel.tableName, row);
          panelRows++;
        }
      }
    }
    var eggGradingCounts = 0;
    if (upsertEggGradingCount != null) {
      for (final row in _remoteRows['egg_quality_defect_counts'] ?? const []) {
        pulledTables.add('egg_quality_defect_counts');
        await upsertEggGradingCount(row);
        eggGradingCounts++;
      }
    }
    return SupabasePullSummary(
      panelRows: panelRows,
      eggGradingCounts: eggGradingCounts,
    );
  }

  @override
  Future<int> pullOperationalRows({
    required Future<void> Function(String table, Map<String, dynamic> row)
    upsertOperationalRow,
  }) async => 0;
}

class _FakePhotoSyncService extends Fake implements PhotoSyncService {
  @override
  Future<void> syncDownloaded() async {}

  @override
  Future<void> syncPending() async {}
}

late FakeSupabaseService fakeSupabase;

/// Builds a [StartupSyncService] wired to a fresh [FakeSupabaseService] (so
/// each call starts with an empty `upserts` map) and real repositories
/// pointed at the current test database. Call `useIsolatedAppDatabase()` in
/// `setUpAll` and `resetAppDatabase()` in `tearDown` before using this.
StartupSyncService buildService({
  Set<String> failUpsertsFor = const {},
  Map<String, List<Map<String, dynamic>>> remoteRows = const {},
  EggGradingRepository? eggGradingRepository,
  // Accepted for readability at call sites (tests already default to
  // pushing); StartupSyncService.run() defaults canPush to true on its own,
  // so this isn't threaded through separately.
  bool canPush = true,
}) {
  fakeSupabase = FakeSupabaseService(
    failUpsertsFor: failUpsertsFor,
    remoteRows: remoteRows,
  );
  return StartupSyncService(
    supabaseService: fakeSupabase,
    eggGradingRepository: eggGradingRepository,
    photoSyncService: _FakePhotoSyncService(),
  );
}
