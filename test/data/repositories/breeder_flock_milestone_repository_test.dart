import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/breeder_flock_milestone_model.dart';
import 'package:hatchaudit/data/repositories/breeder_flock_milestone_repository.dart';

import '../../support/test_database.dart';

/// `breeder_flock_milestones` (breeder-flock-performance ticket 06): dated
/// operational events per flock, restricted to a fixed vocabulary of event
/// types rather than free text.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  final repo = BreederFlockMilestoneRepository();

  test('rejects an event type outside the constrained vocabulary', () {
    expect(
      () => repo.recordMilestone(
        flockId: 'flock-x',
        eventType: 'not_a_real_milestone',
        eventDate: DateTime(2026, 1, 1),
      ),
      throwsArgumentError,
    );
  });

  test('the database itself rejects an invalid eventType via CHECK', () async {
    final db = await DatabaseHelper().db;
    await expectLater(
      db.insert('breeder_flock_milestones', {
        'id': 'bad-1',
        'flockId': 'flock-x',
        'eventType': 'not_a_real_milestone',
        'eventDate': DateTime(2026, 1, 1).toIso8601String(),
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 1, 1).toIso8601String(),
      }),
      throwsA(anything),
    );
  });

  test('records every event type in the constrained set', () async {
    for (final eventType in BreederFlockMilestoneType.all) {
      final milestone = await repo.recordMilestone(
        flockId: 'flock-all-types',
        eventType: eventType,
        eventDate: DateTime(2026, 1, 1),
      );
      expect(milestone.eventType, eventType);
    }
    final rows = await repo.getForFlock('flock-all-types');
    expect(rows, hasLength(BreederFlockMilestoneType.all.length));
  });

  test('getByType returns the single row for a flock/eventType pair', () async {
    await repo.recordMilestone(
      flockId: 'flock-y',
      eventType: BreederFlockMilestoneType.lightStimulation,
      eventDate: DateTime(2026, 2, 1),
      notes: 'first pass',
    );
    final found = await repo.getByType(
      'flock-y',
      BreederFlockMilestoneType.lightStimulation,
    );
    expect(found, isNotNull);
    expect(found!.notes, 'first pass');
    expect(
      await repo.getByType('flock-y', BreederFlockMilestoneType.firstEgg),
      isNull,
    );
  });

  test('correcting an event date updates the same row instead of duplicating', () async {
    final first = await repo.recordMilestone(
      flockId: 'flock-z',
      eventType: BreederFlockMilestoneType.peakProduction,
      eventDate: DateTime(2026, 3, 1),
    );
    final second = await repo.recordMilestone(
      flockId: 'flock-z',
      eventType: BreederFlockMilestoneType.peakProduction,
      eventDate: DateTime(2026, 3, 8),
      notes: 'corrected',
    );

    expect(second.id, first.id);
    final rows = await repo.getForFlock('flock-z');
    expect(rows, hasLength(1));
    expect(rows.single.eventDate, DateTime(2026, 3, 8));
    expect(rows.single.notes, 'corrected');
  });

  test('deleteMilestone removes the row', () async {
    final milestone = await repo.recordMilestone(
      flockId: 'flock-delete',
      eventType: BreederFlockMilestoneType.finalDepletion,
      eventDate: DateTime(2026, 4, 1),
    );
    await repo.deleteMilestone(milestone.id);
    expect(await repo.getForFlock('flock-delete'), isEmpty);
  });

  group('dirty tracking', () {
    test('new milestones are pending and become synced after markRowsSynced', () async {
      final milestone = await repo.recordMilestone(
        flockId: 'flock-dirty',
        eventType: BreederFlockMilestoneType.startOfDepletion,
        eventDate: DateTime(2026, 5, 1),
      );

      final dirty = await repo.getDirtyRows();
      expect(dirty.map((r) => r['id']), contains(milestone.id));

      await repo.markRowsSynced([milestone.id]);

      final db = await DatabaseHelper().db;
      final row = (await db.query(
        'breeder_flock_milestones',
        where: 'id = ?',
        whereArgs: [milestone.id],
      )).single;
      expect(row['syncStatus'], 'synced');
      expect(row['dirtyAt'], isNull);
    });
  });
}
