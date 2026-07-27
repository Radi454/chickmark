import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/home/widgets/main_shell.dart';

void main() {
  test('staff tools are added without changing customer role destinations', () {
    final auditor = UserModel(
      id: 'auditor-1',
      fullName: 'Auditor',
      email: 'auditor@example.test',
      role: 'auditor',
      status: 'approved',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final customer = UserModel(
      id: 'customer-user',
      fullName: 'Customer',
      email: 'customer@example.test',
      role: 'customer',
      status: 'approved',
      customerId: 'customer-1',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    expect(mainShellTabKeysForUser(auditor), [
      'home',
      'dashboard',
      'customers',
      'audits',
      'govee',
      'lab_analysis',
      'bmk',
      'performance',
      'agent',
      'settings',
    ]);
    expect(mainShellTabKeysForUser(customer), ['dashboard', 'settings']);
  });
}
