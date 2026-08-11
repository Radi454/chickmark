import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/dashboard_action_model.dart';
import 'package:hatchaudit/data/repositories/dashboard_action_repository.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });
  setUp(resetAppDatabase);
  tearDown(resetAppDatabase);

  test('action lifecycle is persisted, scoped, and queued for sync', () async {
    final db = await DatabaseHelper().db;
    await db.insert('customers', {'id': 'c1', 'name': 'Customer'});
    await db.insert('hatcheries', {
      'id': 'h1',
      'customerId': 'c1',
      'name': 'Hatchery',
    });
    final repository = DashboardActionRepository();
    final now = DateTime.utc(2026, 7, 12, 10);
    final action = DashboardActionModel(
      id: 'a1',
      findingKey: 'c1|h1|cvt',
      customerId: 'c1',
      hatcheryId: 'h1',
      metricKey: 'cvtAvg',
      title: 'High chick body temperature',
      ownerName: 'Shift lead',
      dueAt: now.add(const Duration(days: 1)),
      createdAt: now,
      updatedAt: now,
    );

    await repository.save(action);
    var saved = (await repository.getForScope(
      customerId: 'c1',
      hatcheryId: 'h1',
    )).single;
    expect(saved.syncStatus, 'pending');
    expect(saved.dirtyAt, isNotNull);

    await repository.save(
      saved.copyWith(
        status: DashboardActionStatus.resolved,
        ownerName: null,
        dueAt: null,
        resolvedAt: now,
        resolutionNotes: 'Ventilation corrected',
      ),
    );
    saved = (await repository.getForScope(
      customerId: 'c1',
      hatcheryId: 'h1',
    )).single;
    expect(saved.status, DashboardActionStatus.resolved);
    expect(saved.ownerName, isNull);
    expect(saved.dueAt, isNull);
    expect(saved.resolutionNotes, 'Ventilation corrected');

    await repository.markSynced(['a1']);
    expect(await repository.getDirtyRows(), isEmpty);
  });

  test('remote upsert clears stale local nullable values', () async {
    final db = await DatabaseHelper().db;
    await db.insert('customers', {'id': 'c2', 'name': 'Customer'});
    await db.insert('hatcheries', {
      'id': 'h2',
      'customerId': 'c2',
      'name': 'Hatchery',
    });
    final repository = DashboardActionRepository();
    final now = DateTime.utc(2026, 7, 12, 10);
    await repository.save(
      DashboardActionModel(
        id: 'a1',
        findingKey: 'finding',
        customerId: 'c2',
        hatcheryId: 'h2',
        title: 'Finding',
        ownerName: 'Old owner',
        dueAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await repository.upsertRemoteRow({
      'id': 'a1',
      'finding_key': 'finding',
      'customer_id': 'c2',
      'hatchery_id': 'h2',
      'title': 'Finding',
      'owner_name': null,
      'due_at': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.add(const Duration(hours: 1)).toIso8601String(),
    });

    final saved = (await repository.getForScope(
      customerId: 'c2',
      hatcheryId: 'h2',
    )).single;
    expect(saved.ownerName, isNull);
    expect(saved.dueAt, isNull);
    expect(saved.syncStatus, 'synced');
    expect(saved.dirtyAt, isNull);
  });

  group('mark-synced race protection', () {
    test('an action edited mid-push stays pending after markSynced', () async {
      final db = await DatabaseHelper().db;
      await db.insert('customers', {'id': 'c3', 'name': 'Customer'});
      await db.insert('hatcheries', {
        'id': 'h3',
        'customerId': 'c3',
        'name': 'Hatchery',
      });
      final repository = DashboardActionRepository();
      final now = DateTime.utc(2026, 7, 12, 10);
      final action = DashboardActionModel(
        id: 'a-race',
        findingKey: 'c3|h3|cvt',
        customerId: 'c3',
        hatcheryId: 'h3',
        metricKey: 'cvtAvg',
        title: 'Race test',
        createdAt: now,
        updatedAt: now,
      );

      await repository.save(action);
      await repository.getDirtyRows(); // capture cutoff
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repository.save(action); // mid-push edit
      await repository.markSynced(['a-race']);

      final saved = (await repository.getForScope(
        customerId: 'c3',
        hatcheryId: 'h3',
      )).single;
      expect(saved.syncStatus, 'pending');
      expect(saved.dirtyAt, isNotNull);
    });

    test('an unedited action is cleared by markSynced', () async {
      final db = await DatabaseHelper().db;
      await db.insert('customers', {'id': 'c4', 'name': 'Customer'});
      await db.insert('hatcheries', {
        'id': 'h4',
        'customerId': 'c4',
        'name': 'Hatchery',
      });
      final repository = DashboardActionRepository();
      final now = DateTime.utc(2026, 7, 12, 10);
      final action = DashboardActionModel(
        id: 'a-race-2',
        findingKey: 'c4|h4|cvt',
        customerId: 'c4',
        hatcheryId: 'h4',
        metricKey: 'cvtAvg',
        title: 'Race test',
        createdAt: now,
        updatedAt: now,
      );

      await repository.save(action);
      await repository.getDirtyRows();
      await repository.markSynced(['a-race-2']);

      final saved = (await repository.getForScope(
        customerId: 'c4',
        hatcheryId: 'h4',
      )).single;
      expect(saved.syncStatus, 'synced');
    });
  });
}
