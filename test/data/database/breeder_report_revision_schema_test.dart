import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:hatchaudit/data/database/database_helper.dart';

import '../../support/test_database.dart';

/// Schema-level guarantees for `breeder_report_revisions`
/// (breeder-flock-performance ticket 12): the database itself, not just the
/// application layer, rejects a revision entry with no reason or actor, and
/// unconditionally refuses any UPDATE or DELETE against an already-written
/// row — a revision entry is immutable from the instant it exists, with no
/// draft state to begin in (design doc section 12: "immutable approved
/// revision entries").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  String iso(DateTime d) => d.toIso8601String();

  Future<void> seedFlock(String flockId) async {
    final db = await DatabaseHelper().db;
    await db.insert('flocks', {
      'id': flockId,
      'flockId': flockId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> seedReport(String id, String flockId, String date) async {
    await seedFlock(flockId);
    final db = await DatabaseHelper().db;
    final now = iso(DateTime(2026, 1, 1));
    await db.insert('breeder_daily_reports', {
      'id': id,
      'flockId': flockId,
      'reportDate': date,
      'state': 'approved',
      'revision': 2,
      'createdAt': now,
      'updatedAt': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Map<String, Object?> baseRevision({
    required String id,
    required String reportId,
    String reason = 'Corrected a typo',
    String actorUserId = 'user-1',
  }) {
    final now = iso(DateTime(2026, 1, 5));
    return {
      'id': id,
      'reportId': reportId,
      'tableName': 'breeder_daily_reports',
      'rowId': reportId,
      'fieldName': 'notes',
      'oldValue': 'old note',
      'newValue': 'new note',
      'reason': reason,
      'actorUserId': actorUserId,
      'revisionAfter': 2,
      'changedAt': now,
      'createdAt': now,
      'updatedAt': now,
    };
  }

  test('a normal revision row inserts cleanly', () async {
    await seedReport('report-rev-ok', 'flock-rev-ok', '2026-01-01');
    final db = await DatabaseHelper().db;
    await db.insert(
      'breeder_report_revisions',
      baseRevision(id: 'rev-ok-1', reportId: 'report-rev-ok'),
    );
    final rows = await db.query(
      'breeder_report_revisions',
      where: 'id = ?',
      whereArgs: ['rev-ok-1'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['reason'], 'Corrected a typo');
    expect(rows.single['actorUserId'], 'user-1');
    expect(rows.single['revisionAfter'], 2);
  });

  test('an empty reason is rejected by CHECK', () async {
    await seedReport('report-rev-noreason', 'flock-rev-noreason', '2026-01-02');
    final db = await DatabaseHelper().db;
    await expectLater(
      db.insert(
        'breeder_report_revisions',
        baseRevision(
          id: 'rev-noreason-1',
          reportId: 'report-rev-noreason',
          reason: '',
        ),
      ),
      throwsA(anything),
    );
  });

  test('an empty actorUserId is rejected by CHECK', () async {
    await seedReport('report-rev-noactor', 'flock-rev-noactor', '2026-01-03');
    final db = await DatabaseHelper().db;
    await expectLater(
      db.insert(
        'breeder_report_revisions',
        baseRevision(
          id: 'rev-noactor-1',
          reportId: 'report-rev-noactor',
          actorUserId: '',
        ),
      ),
      throwsA(anything),
    );
  });

  test('a revision row cannot be UPDATEd', () async {
    await seedReport('report-rev-noupdate', 'flock-rev-noupdate', '2026-01-04');
    final db = await DatabaseHelper().db;
    await db.insert(
      'breeder_report_revisions',
      baseRevision(id: 'rev-noupdate-1', reportId: 'report-rev-noupdate'),
    );
    await expectLater(
      db.update(
        'breeder_report_revisions',
        {'newValue': 'tampered'},
        where: 'id = ?',
        whereArgs: ['rev-noupdate-1'],
      ),
      throwsA(anything),
    );
  });

  test('a revision row cannot be DELETEd', () async {
    await seedReport('report-rev-nodelete', 'flock-rev-nodelete', '2026-01-05');
    final db = await DatabaseHelper().db;
    await db.insert(
      'breeder_report_revisions',
      baseRevision(id: 'rev-nodelete-1', reportId: 'report-rev-nodelete'),
    );
    await expectLater(
      db.delete(
        'breeder_report_revisions',
        where: 'id = ?',
        whereArgs: ['rev-nodelete-1'],
      ),
      throwsA(anything),
    );
  });

  test('a revision row on a Draft-state report still inserts and is immutable', () async {
    // Design section 5: "Draft reports edit normally with no revision
    // history — history begins at approval." This table places no CHECK on
    // the parent report's own state (nothing stops a caller from writing a
    // row against a draft report), but the application layer
    // (`BreederBirdLedgerService.correctHeader`) never does so in practice
    // for anything but an Approved report. The immutability guarantee
    // itself does not depend on the parent's state either way.
    await seedFlock('flock-rev-draft');
    final db = await DatabaseHelper().db;
    final now = iso(DateTime(2026, 1, 6));
    await db.insert('breeder_daily_reports', {
      'id': 'report-rev-draft',
      'flockId': 'flock-rev-draft',
      'reportDate': '2026-01-06',
      'state': 'draft',
      'revision': 1,
      'createdAt': now,
      'updatedAt': now,
    });
    await db.insert(
      'breeder_report_revisions',
      baseRevision(id: 'rev-draft-1', reportId: 'report-rev-draft'),
    );
    await expectLater(
      db.delete(
        'breeder_report_revisions',
        where: 'id = ?',
        whereArgs: ['rev-draft-1'],
      ),
      throwsA(anything),
    );
  });
}
