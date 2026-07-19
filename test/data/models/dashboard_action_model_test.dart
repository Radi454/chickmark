import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/dashboard_action_model.dart';

void main() {
  test('dashboard action round-trips and nullable fields can be cleared', () {
    final now = DateTime.utc(2026, 7, 12, 10);
    final action = DashboardActionModel(
      id: 'action-1',
      findingKey: 'customer|hatchery|metric',
      customerId: 'customer-1',
      hatcheryId: 'hatchery-1',
      title: 'High CVT',
      status: DashboardActionStatus.resolved,
      ownerName: 'Operations',
      dueAt: now,
      resolvedAt: now,
      dirtyAt: now,
      syncError: 'offline',
      createdAt: now,
      updatedAt: now,
    );

    final cleared = action.copyWith(
      status: DashboardActionStatus.reopened,
      ownerName: null,
      dueAt: null,
      resolvedAt: null,
      dirtyAt: null,
      syncError: null,
    );
    expect(cleared.ownerName, isNull);
    expect(cleared.dueAt, isNull);
    expect(cleared.resolvedAt, isNull);
    expect(cleared.dirtyAt, isNull);
    expect(cleared.syncError, isNull);

    final restored = DashboardActionModel.fromMap(cleared.toMap());
    expect(restored.status, DashboardActionStatus.reopened);
    expect(restored.findingKey, action.findingKey);
    expect(restored.updatedAt.toUtc(), now);
  });
}
