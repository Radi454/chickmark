import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/breeder_bird_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_daily_report_model.dart';
import 'package:hatchaudit/data/repositories/breeder_bird_movement_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_daily_report_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_report_aggregate_repository.dart';
import 'package:hatchaudit/data/repositories/performance_sync_repository.dart';
import 'package:hatchaudit/data/repositories/sync_conflict_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_report_sync_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

import '../../support/test_database.dart';

/// Records every aggregate-push call and mirrors
/// `push_breeder_daily_report_aggregate` (0013's Postgres function): a cloud
/// `breeder_daily_reports` row store gated on its own `sync_token`, kept
/// deliberately separate from the client's `revision` audit column, exactly
/// like the real RPC. `sync_token` advances by exactly one on every
/// successful push and is returned to the caller — this is the mechanism
/// the real bug report was about: gating concurrency on `revision` instead
/// (which does not move on an ordinary edit) lets two devices at the same
/// `revision` both "match" and silently overwrite one another.
class FakeAggregateSupabaseService extends Fake implements SupabaseService {
  final List<Map<String, dynamic>> calls = [];
  final Map<String, CloudReportFixture> cloud = {};

  @override
  Future<bool> refreshAvailability() async => true;

  /// Seeds a cloud row directly, as if another device had already pushed it
  /// successfully — the setup step for the "stale child" race tests.
  /// [syncToken] is the cloud's concurrency counter, distinct from whatever
  /// `revision` [header] carries.
  void seedCloud(
    String reportId, {
    required int syncToken,
    required Map<String, dynamic> header,
    List<Map<String, dynamic>> movements = const [],
  }) {
    cloud[reportId] = CloudReportFixture(
      syncToken: syncToken,
      header: {...header, 'sync_token': syncToken},
      movements: movements,
    );
  }

  @override
  Future<Map<String, dynamic>> pushBreederDailyReportAggregate(
    Map<String, dynamic> payload, {
    required int baseRevision,
  }) async {
    calls.add({'payload': payload, 'baseRevision': baseRevision});
    final header = Map<String, dynamic>.from(payload['header'] as Map);
    final reportId = header['id'] as String;
    final existing = cloud[reportId];

    if (existing != null && existing.syncToken != baseRevision) {
      return {
        'conflict': true,
        'cloud': {
          'header': existing.header,
          'movements': existing.movements,
          'feed_entries': const [],
          'egg_production_entries': const [],
          'inventory_movements': const [],
        },
      };
    }

    final newToken = (existing?.syncToken ?? 0) + 1;
    cloud[reportId] = CloudReportFixture(
      syncToken: newToken,
      header: {...header, 'sync_token': newToken},
      movements: List<Map<String, dynamic>>.from(
        payload['movements'] as List? ?? const [],
      ),
    );
    return {'conflict': false, 'sync_token': newToken};
  }
}

class CloudReportFixture {
  CloudReportFixture({
    required this.syncToken,
    required this.header,
    required this.movements,
  });
  final int syncToken;
  final Map<String, dynamic> header;
  final List<Map<String, dynamic>> movements;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BreederReportSyncService (breeder-flock-performance ticket 15)', () {
    setUpAll(() async {
      await useIsolatedAppDatabase();
    });

    tearDownAll(() async {
      await DatabaseHelper().close();
    });

    late BreederDailyReportRepository reportRepository;
    late BreederBirdMovementRepository movementRepository;
    late BreederReportAggregateRepository aggregateRepository;
    late SyncConflictRepository conflictRepository;
    late FakeAggregateSupabaseService fakeSupabase;
    late BreederReportSyncService syncService;

    setUp(() {
      reportRepository = BreederDailyReportRepository();
      movementRepository = BreederBirdMovementRepository();
      aggregateRepository = BreederReportAggregateRepository();
      conflictRepository = SyncConflictRepository();
      fakeSupabase = FakeAggregateSupabaseService();
      syncService = BreederReportSyncService(
        supabaseService: fakeSupabase,
        aggregateRepository: aggregateRepository,
        reportRepository: reportRepository,
        conflictRepository: conflictRepository,
      );
    });

    Future<void> seedFlock(String flockId) async {
      final db = await DatabaseHelper().db;
      await db.insert('flocks', {'id': flockId, 'flockId': flockId});
    }

    Future<void> seedHouse(String flockId, String houseId) async {
      final db = await DatabaseHelper().db;
      await db.insert('houses', {
        'id': houseId,
        'flockId': flockId,
        'name': houseId,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }

    test(
      'aggregate push carries header and every child row in one call, and '
      'strips local sync bookkeeping from the payload',
      () async {
        await seedFlock('flock-agg-1');
        await seedHouse('flock-agg-1', 'house-agg-1');
        final report = await reportRepository.createDraft(
          flockId: 'flock-agg-1',
          reportDate: DateTime(2026, 1, 1),
        );
        await movementRepository.upsert(
          BreederBirdMovement(
            id: 'm-agg-1',
            reportId: report.id,
            houseId: 'house-agg-1',
            sex: BreederBirdMovementSex.female,
            opening: 10,
            closing: 10,
          ),
        );

        final result = await syncService.pushReport(report.id);

        expect(result.conflicted, isFalse);
        expect(fakeSupabase.calls, hasLength(1));
        final payload = fakeSupabase.calls.single['payload'] as Map;
        final header = payload['header'] as Map;
        final movements = payload['movements'] as List;
        expect(header['id'], report.id);
        expect(movements, hasLength(1));
        expect((movements.single as Map)['id'], 'm-agg-1');

        // Local sync bookkeeping never appears in the cloud payload, in
        // either camelCase or snake_case form.
        for (final forbidden in [
          'syncStatus',
          'sync_status',
          'dirtyAt',
          'dirty_at',
          'lastSyncedAt',
          'last_synced_at',
          'syncError',
          'sync_error',
          'lastSyncedRevision',
          'last_synced_revision',
          'previousState',
          'previous_state',
        ]) {
          expect(header.containsKey(forbidden), isFalse, reason: forbidden);
          expect(
            (movements.single as Map).containsKey(forbidden),
            isFalse,
            reason: forbidden,
          );
        }

        // Header + child row both marked synced by the one push.
        final refreshed = await reportRepository.getRawById(report.id);
        expect(refreshed!['syncStatus'], 'synced');
        expect(refreshed['lastSyncedRevision'], 1);
        final movementRows = await (await DatabaseHelper().db).query(
          'breeder_bird_movements',
          where: 'id = ?',
          whereArgs: ['m-agg-1'],
        );
        expect(movementRows.single['syncStatus'], 'synced');
      },
    );

    test(
      'a stale child row cannot land after a winning header (design doc '
      'section 13.1) — the base-revision mismatch is rejected, both '
      'versions are preserved in sync_conflicts, and the report enters '
      'Sync Conflict',
      () async {
        await seedFlock('flock-agg-2');
        await seedHouse('flock-agg-2', 'house-agg-2');
        final report = await reportRepository.createDraft(
          flockId: 'flock-agg-2',
          reportDate: DateTime(2026, 1, 2),
        );
        await movementRepository.upsert(
          BreederBirdMovement(
            id: 'm-winning-origin',
            reportId: report.id,
            houseId: 'house-agg-2',
            sex: BreederBirdMovementSex.female,
            opening: 10,
            closing: 10,
          ),
        );

        // This device already synced once — lastSyncedRevision now matches
        // the cloud's sync_token of 1.
        await reportRepository.setLastSyncedRevision(report.id, 1);

        // Meanwhile, ANOTHER device submitted this same report and its push
        // already won, advancing the cloud's sync_token to 2 with
        // `m-winning` as the only child row. This device has no idea that
        // happened yet.
        fakeSupabase.seedCloud(
          report.id,
          syncToken: 2,
          header: {'id': report.id, 'flock_id': 'flock-agg-2', 'state': 'submitted'},
          movements: [
            {'id': 'm-winning', 'report_id': report.id, 'closing': 999},
          ],
        );

        // This device, still unaware, edits its own (stale) child row —
        // dirtying it — without ever bumping its local header revision.
        await movementRepository.upsert(
          BreederBirdMovement(
            id: 'm-stale',
            reportId: report.id,
            houseId: 'house-agg-2',
            sex: BreederBirdMovementSex.male,
            opening: 5,
            closing: 5,
          ),
        );

        final result = await syncService.pushReport(report.id);

        expect(result.conflicted, isTrue);
        expect(result.pushedRowCount, 0);

        // The cloud's winning child set must be untouched — the stale local
        // aggregate (which still carries `m-stale`) never landed.
        final cloudReport = fakeSupabase.cloud[report.id]!;
        expect(cloudReport.syncToken, 2);
        expect(cloudReport.movements.single['id'], 'm-winning');

        // The report is now in Sync Conflict locally, remembering its
        // pre-conflict state so resolution can restore it.
        final updatedReport = await reportRepository.getById(report.id);
        expect(updatedReport!.isSyncConflict, isTrue);
        expect(updatedReport.previousState, BreederDailyReportState.draft);

        // Both versions are preserved in the EXISTING sync_conflicts table.
        final conflict = await conflictRepository.getOpenConflictFor(
          BreederReportAggregateRepository.headerTable,
          report.id,
        );
        expect(conflict, isNotNull);
        expect(conflict!.localDataJson, contains('m-stale'));
        expect(conflict.remoteDataJson, contains('m-winning'));

        // The still-dirty local child row was never marked synced.
        final staleRow = await (await DatabaseHelper().db).query(
          'breeder_bird_movements',
          where: 'id = ?',
          whereArgs: ['m-stale'],
        );
        expect(staleRow.single['syncStatus'], 'pending');
      },
    );

    test(
      'a push whose base revision no longer matches is rejected even with '
      'no local child edits at all',
      () async {
        await seedFlock('flock-agg-3');
        final report = await reportRepository.createDraft(
          flockId: 'flock-agg-3',
          reportDate: DateTime(2026, 1, 3),
        );
        await reportRepository.setLastSyncedRevision(report.id, 1);
        fakeSupabase.seedCloud(
          report.id,
          syncToken: 5,
          header: {'id': report.id, 'flock_id': 'flock-agg-3', 'state': 'approved'},
        );
        // Force the header itself dirty so it is picked up for push.
        await reportRepository.updateHeader(report.copyWith(notes: 'edited'));

        final result = await syncService.pushReport(report.id);

        expect(result.conflicted, isTrue);
      },
    );

    test('benchmarks and egg-grade reference data never push upward', () {
      for (final table in PerformanceSyncRepository.breederReferencePullOnly) {
        expect(PerformanceSyncRepository.allPushTables.contains(table), isFalse);
        expect(
          () => PerformanceSyncRepository().getDirtyRows(table),
          throwsA(isA<ArgumentError>()),
        );
      }
    });

    test(
      'the daily-report sync aggregate tables push through the dedicated '
      'transaction, never the generic per-row path, but still pull '
      'generically',
      () {
        for (final table in PerformanceSyncRepository.breederAggregatePullOnly) {
          expect(
            PerformanceSyncRepository.allPushTables.contains(table),
            isFalse,
          );
          expect(
            PerformanceSyncRepository.allPullTables.contains(table),
            isTrue,
          );
        }
      },
    );

    test('FK-safe push ordering holds for the newly registered tables', () {
      final order = PerformanceSyncRepository.allPushTables;
      int at(String table) => order.indexOf(table);

      expect(at('houses'), lessThan(at('breeder_weighing_sessions')));
      expect(at('houses'), lessThan(at('egg_batch_house_sources')));
      expect(
        at('breeder_weighing_sessions'),
        lessThan(at('breeder_weighing_samples')),
      );
      expect(at('egg_batches'), lessThan(at('egg_batch_house_sources')));
      expect(at('egg_shipments'), lessThan(at('egg_shipment_batches')));
      expect(at('egg_shipment_batches'), lessThan(at('egg_batch_receipts')));

      // Revisions/shipments push only after the aggregate has landed —
      // they must sort after every postFlockPushOrder table.
      for (final aggregateDependent
          in PerformanceSyncRepository.postAggregatePushOrder) {
        for (final earlier in PerformanceSyncRepository.postFlockPushOrder) {
          expect(at(earlier), lessThan(at(aggregateDependent)));
        }
      }
    });

    test(
      'two pushes at the same base token with DIFFERENT child edits: the '
      'first wins, the second is rejected into conflict, and the first '
      "device's rows survive intact in the cloud — proving the concurrency "
      'guard actually advances on an ordinary sync push',
      () async {
        await seedFlock('flock-race-1');
        await seedHouse('flock-race-1', 'house-race-a');
        await seedHouse('flock-race-1', 'house-race-b');
        final report = await reportRepository.createDraft(
          flockId: 'flock-race-1',
          reportDate: DateTime(2026, 3, 1),
        );
        await movementRepository.upsert(
          BreederBirdMovement(
            id: 'm-race-a',
            reportId: report.id,
            houseId: 'house-race-a',
            sex: BreederBirdMovementSex.female,
            opening: 10,
            closing: 10,
          ),
        );
        await movementRepository.upsert(
          BreederBirdMovement(
            id: 'm-race-b',
            reportId: report.id,
            houseId: 'house-race-b',
            sex: BreederBirdMovementSex.female,
            opening: 20,
            closing: 20,
          ),
        );

        // Establish a shared synced baseline — both "devices" now hold the
        // report at the same sync_token, with neither a transition nor a
        // correction in sight (so the audit `revision` never moves either).
        final baseline = await syncService.pushReport(report.id);
        expect(baseline.conflicted, isFalse);
        final afterBaseline = await reportRepository.getRawById(report.id);
        final sharedBaseToken = afterBaseline!['lastSyncedRevision'] as int;
        expect(sharedBaseToken, 1);

        // This device (device A) edits house A's mortality — an ordinary
        // child edit, not a transition or correction — while still offline
        // and still at the shared base token.
        await movementRepository.upsert(
          BreederBirdMovement(
            id: 'm-race-a',
            reportId: report.id,
            houseId: 'house-race-a',
            sex: BreederBirdMovementSex.female,
            opening: 10,
            mortality: 2,
            closing: 8,
          ),
        );

        // Device A pushes first and wins.
        final aResult = await syncService.pushReport(report.id);
        expect(aResult.conflicted, isFalse);
        final afterAPush = await reportRepository.getRawById(report.id);
        final newToken = afterAPush!['lastSyncedRevision'] as int;
        expect(
          newToken,
          sharedBaseToken + 1,
          reason:
              'the stored concurrency token must advance on a successful '
              'push, or a second push at the same base token could never '
              'be rejected',
        );
        // The audit revision counter (ticket 12) never moved.
        expect(afterAPush['revision'], 1);

        // Device B independently edited house B's figure from the SAME
        // shared base token — it never saw device A's push. Represented as
        // a hand-built competing payload submitted at that same stale
        // token, exactly mirroring what device B's own
        // BreederReportSyncService would have sent.
        final deviceBPayload = <String, dynamic>{
          'header': {
            'id': report.id,
            'flock_id': 'flock-race-1',
            'report_date': report.reportDateKey,
            'state': 'draft',
            'revision': 1,
          },
          'movements': [
            {
              'id': 'm-race-a',
              'report_id': report.id,
              'house_id': 'house-race-a',
              'sex': 'female',
              'opening': 10,
              'mortality': 0,
              'culls': 0,
              'sale': 0,
              'kitchen_removal': 0,
              'euthanasia': 0,
              'transfer_in': 0,
              'transfer_out': 0,
              'closing': 10,
            },
            {
              'id': 'm-race-b',
              'report_id': report.id,
              'house_id': 'house-race-b',
              'sex': 'female',
              'opening': 20,
              'mortality': 0,
              'culls': 0,
              'sale': 1,
              'kitchen_removal': 0,
              'euthanasia': 0,
              'transfer_in': 0,
              'transfer_out': 0,
              'closing': 19,
            },
          ],
          'feed_entries': [],
          'egg_production_entries': [],
          'inventory_movements': [],
        };
        final bResult = await fakeSupabase.pushBreederDailyReportAggregate(
          deviceBPayload,
          baseRevision: sharedBaseToken,
        );

        expect(
          bResult['conflict'],
          isTrue,
          reason:
              "device B's stale token must be rejected now that device A "
              'already advanced it',
        );

        // Device A's rows survive intact in the cloud — not overwritten by
        // device B's stale delete-then-reinsert. Assert the actual
        // surviving rows, not just the conflict flag.
        final cloudMovements = fakeSupabase.cloud[report.id]!.movements;
        final cloudHouseA = cloudMovements.firstWhere(
          (m) => m['id'] == 'm-race-a',
        );
        final cloudHouseB = cloudMovements.firstWhere(
          (m) => m['id'] == 'm-race-b',
        );
        expect(cloudHouseA['mortality'], 2, reason: "device A's edit stuck");
        expect(cloudHouseA['closing'], 8);
        expect(
          cloudHouseB['closing'],
          20,
          reason:
              "device B's edit (closing 19) must NOT have landed — it was "
              'rejected before it ever reached the child tables',
        );

        // The winner's own next push, using the token it received back,
        // succeeds.
        await movementRepository.upsert(
          BreederBirdMovement(
            id: 'm-race-a',
            reportId: report.id,
            houseId: 'house-race-a',
            sex: BreederBirdMovementSex.female,
            opening: 10,
            mortality: 3,
            closing: 7,
          ),
        );
        final secondPush = await syncService.pushReport(report.id);
        expect(secondPush.conflicted, isFalse);
        final afterSecondPush = await reportRepository.getRawById(report.id);
        expect(afterSecondPush!['lastSyncedRevision'], newToken + 1);
        // Still untouched by two ordinary syncs.
        expect(afterSecondPush['revision'], 1);
      },
    );

    test(
      "a successful aggregate push never advances ticket 12's audit "
      '`revision` counter — only the local-only sync-token bookkeeping '
      'moves',
      () async {
        await seedFlock('flock-audit-1');
        final report = await reportRepository.createDraft(
          flockId: 'flock-audit-1',
          reportDate: DateTime(2026, 3, 5),
        );
        expect(report.revision, 1);

        await reportRepository.updateHeader(report.copyWith(notes: 'edit 1'));
        final first = await syncService.pushReport(report.id);
        expect(first.conflicted, isFalse);
        var refreshed = await reportRepository.getRawById(report.id);
        expect(refreshed!['revision'], 1);
        expect(refreshed['lastSyncedRevision'], 1);

        final current = (await reportRepository.getById(report.id))!;
        await reportRepository.updateHeader(current.copyWith(notes: 'edit 2'));
        final second = await syncService.pushReport(report.id);
        expect(second.conflicted, isFalse);
        refreshed = await reportRepository.getRawById(report.id);
        expect(
          refreshed!['revision'],
          1,
          reason:
              'plain header edits and background syncs are neither a state '
              'transition nor a post-approval correction, so the audit '
              'counter must not move',
        );
        expect(
          refreshed['lastSyncedRevision'],
          2,
          reason: 'the sync-only token still advances on every push',
        );
      },
    );
  });
}
