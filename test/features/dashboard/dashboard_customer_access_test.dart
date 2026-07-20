import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';

void main() {
  UserModel user({
    required String id,
    required String role,
    String? customerId,
  }) {
    return UserModel(
      id: id,
      fullName: id,
      email: '$id@example.com',
      role: role,
      status: 'approved',
      customerId: customerId,
      createdAt: DateTime(2026),
    );
  }

  test(
    'customer dashboard scope is fixed and action management is disabled',
    () {
      final provider = DashboardProvider();

      provider.prepareForUser(
        user(id: 'customer-user', role: 'customer', customerId: 'customer-1'),
      );

      expect(provider.selectedCustomerId, 'customer-1');
      expect(provider.canUseAllCustomers, isFalse);
      expect(provider.canManageActions, isFalse);
      expect(provider.isLoading, isTrue);
    },
  );

  test(
    'unknown identity fails closed for dashboard actions and portfolio scope',
    () {
      final provider = DashboardProvider();

      expect(provider.canUseAllCustomers, isFalse);
      expect(provider.canManageActions, isFalse);
    },
  );

  test('switching accounts clears the previous dashboard tenant selection', () {
    final provider = DashboardProvider();
    provider.prepareForUser(
      user(id: 'customer-a', role: 'customer', customerId: 'customer-1'),
    );

    provider.prepareForUser(
      user(id: 'customer-b', role: 'customer', customerId: 'customer-2'),
    );

    expect(provider.selectedCustomerId, 'customer-2');
    expect(provider.selectedHatcheryId, isNull);
    expect(provider.selectedFlockId, isNull);
    expect(provider.customers, isEmpty);
    expect(provider.flocks, isEmpty);
  });
}
