import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/sync_conflict_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  setUp(() async {
    await _resetDatabase();
    // Touch the DB to provoke onCreate so sync_conflicts exists.
    await DatabaseHelper().db;
  });

  tearDown(() async {
    await DatabaseHelper().close();
  });

  group('SyncConflictRepository', () {
    test('recordConflict persists a row and getOpenCount returns 1', () async {
      final repo = SyncConflictRepository();
      await repo.recordConflict(
        table: 'audit_sessions',
        rowId: 'session-1',
        localUpdatedAt: DateTime.parse('2026-06-06T10:00:00.000Z'),
        remoteUpdatedAt: DateTime.parse('2026-06-06T09:00:00.000Z'),
        winner: 'local',
      );
      expect(await repo.getOpenCount(), 1);
      final open = await repo.getOpenConflicts();
      expect(open, hasLength(1));
      expect(open.first.tableName, 'audit_sessions');
      expect(open.first.rowId, 'session-1');
      expect(open.first.winner, 'local');
    });

    test(
      'recording the same conflict event twice does not duplicate rows',
      () async {
        final repo = SyncConflictRepository();
        final remoteTime = DateTime.parse('2026-06-06T09:00:00.000Z');
        for (var i = 0; i < 3; i++) {
          await repo.recordConflict(
            table: 'audit_sessions',
            rowId: 'session-1',
            localUpdatedAt: DateTime.parse('2026-06-06T10:00:00.000Z'),
            remoteUpdatedAt: remoteTime,
            winner: 'local',
          );
        }
        expect(await repo.getOpenCount(), 1);
      },
    );

    test(
      'conflicts with different remoteUpdatedAt yield separate rows',
      () async {
        final repo = SyncConflictRepository();
        await repo.recordConflict(
          table: 'audit_sessions',
          rowId: 'session-1',
          localUpdatedAt: DateTime.parse('2026-06-06T10:00:00.000Z'),
          remoteUpdatedAt: DateTime.parse('2026-06-06T09:00:00.000Z'),
          winner: 'local',
        );
        await repo.recordConflict(
          table: 'audit_sessions',
          rowId: 'session-1',
          localUpdatedAt: DateTime.parse('2026-06-06T11:00:00.000Z'),
          remoteUpdatedAt: DateTime.parse('2026-06-06T09:30:00.000Z'),
          winner: 'local',
        );
        expect(await repo.getOpenCount(), 2);
      },
    );

    test('markReviewed flips one row out of the open count', () async {
      final repo = SyncConflictRepository();
      await repo.recordConflict(
        table: 'audit_sessions',
        rowId: 'session-1',
        localUpdatedAt: DateTime.parse('2026-06-06T10:00:00.000Z'),
        remoteUpdatedAt: DateTime.parse('2026-06-06T09:00:00.000Z'),
        winner: 'local',
      );
      final open = await repo.getOpenConflicts();
      expect(open, hasLength(1));
      await repo.markReviewed(open.first.id, reviewedBy: 'admin');
      expect(await repo.getOpenCount(), 0);
    });

    test('markAllReviewed clears every open row at once', () async {
      final repo = SyncConflictRepository();
      for (var i = 0; i < 3; i++) {
        await repo.recordConflict(
          table: 'audit_sessions',
          rowId: 'session-$i',
          localUpdatedAt: DateTime.parse('2026-06-06T10:00:00.000Z'),
          remoteUpdatedAt: DateTime.parse('2026-06-06T09:0$i:00.000Z'),
          winner: 'local',
        );
      }
      expect(await repo.getOpenCount(), 3);
      await repo.markAllReviewed(reviewedBy: 'admin');
      expect(await repo.getOpenCount(), 0);
    });

    test(
      'pruneReviewedOlderThan deletes only old reviewed rows',
      () async {
        final repo = SyncConflictRepository();
        // Two conflicts; review one of them.
        await repo.recordConflict(
          table: 'audit_sessions',
          rowId: 'session-A',
          localUpdatedAt: DateTime.parse('2026-06-06T10:00:00.000Z'),
          remoteUpdatedAt: DateTime.parse('2026-06-06T09:00:00.000Z'),
          winner: 'local',
        );
        await repo.recordConflict(
          table: 'audit_sessions',
          rowId: 'session-B',
          localUpdatedAt: DateTime.parse('2026-06-06T10:00:00.000Z'),
          remoteUpdatedAt: DateTime.parse('2026-06-06T09:01:00.000Z'),
          winner: 'local',
        );
        final open = await repo.getOpenConflicts();
        await repo.markReviewed(open.first.id, reviewedBy: 'admin');

        // Backdate the reviewed row so it falls outside the prune window.
        final db = await DatabaseHelper().db;
        await db.update(
          SyncConflictRepository.tableName,
          {'reviewedAt': '2020-01-01T00:00:00.000Z'},
          where: 'id = ?',
          whereArgs: [open.first.id],
        );

        final deleted = await repo.pruneReviewedOlderThan(
          const Duration(days: 30),
        );
        expect(deleted, 1, reason: 'one stale reviewed row should be pruned');

        // Open conflict survives the prune.
        expect(await repo.getOpenCount(), 1);
      },
    );

    test('pruneReviewedOlderThan never deletes open conflicts', () async {
      final repo = SyncConflictRepository();
      await repo.recordConflict(
        table: 'audit_sessions',
        rowId: 'session-1',
        localUpdatedAt: DateTime.parse('2026-06-06T10:00:00.000Z'),
        remoteUpdatedAt: DateTime.parse('2026-06-06T09:00:00.000Z'),
        winner: 'local',
      );
      final deleted = await repo.pruneReviewedOlderThan(Duration.zero);
      expect(deleted, 0);
      expect(await repo.getOpenCount(), 1);
    });
  });
}

Future<void> _resetDatabase() async {
  await DatabaseHelper().close();
  final dbPath = p.join(
    await databaseFactory.getDatabasesPath(),
    'hatchaudit.db',
  );
  await databaseFactory.deleteDatabase(dbPath);
}
