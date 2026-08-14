import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/home/widgets/main_shell.dart';

void main() {
  test('Agent Monitor is available only to approved admins', () {
    final admin = UserModel(
      id: 'admin-1',
      fullName: 'Admin',
      email: 'admin@example.test',
      role: 'admin',
      status: 'approved',
      createdAt: DateTime.utc(2026, 1, 1),
    );
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

    expect(mainShellTabKeysForUser(admin), [
      'home',
      'dashboard',
      'customers',
      'audits',
      'govee',
      'lab_analysis',
      'bmk',
      'performance',
      'agent',
      'assistant',
      'settings',
    ]);
    expect(mainShellTabKeysForUser(auditor), [
      'home',
      'dashboard',
      'customers',
      'audits',
      'govee',
      'lab_analysis',
      'bmk',
      'performance',
      'assistant',
      'settings',
    ]);
    // The assistant is open to every approved role, customers included.
    expect(mainShellTabKeysForUser(customer), [
      'dashboard',
      'assistant',
      'settings',
    ]);
  });
}
