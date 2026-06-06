import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hatchaudit/core/security/security_policy.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/audits/widgets/audit_access_guard.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

// The guard intentionally returns allowed=true under the debug auth bypass.
// These tests stay correct whether or not the bypass is on: the negative cases
// only assert "denied" when the bypass is disabled. Run the strict version with
//   flutter test --dart-define=CHICKMARK_DEBUG_AUTH_BYPASS=false
final bool _bypass = AuthSecurityPolicy.isDebugAuthBypassEnabled;

SupabaseService _stubSupa() => SupabaseService(
      isConfiguredForTesting: () => false,
      initializeSupabaseForTesting: () async => false,
      checkNetworkAvailableForTesting: () async => false,
    );

/// Minimal AuthProvider whose `user` we control, without real auth/network.
class _StubAuth extends AuthProvider {
  final UserModel? _u;
  _StubAuth(this._u) : super(supabaseService: _stubSupa());

  @override
  UserModel? get user => _u;
}

UserModel _user(String role, {String status = 'approved'}) => UserModel(
      id: 'u',
      fullName: 'Test User',
      email: 'u@example.com',
      role: role,
      status: status,
      createdAt: DateTime(2020, 1, 1),
    );

Widget _harness(UserModel? u) => ChangeNotifierProvider<AuthProvider>.value(
      value: _StubAuth(u),
      child: MaterialApp(
        home: Builder(
          builder: (context) => AuditAccess.allowed(context)
              ? const Scaffold(body: Text('ALLOWED'))
              : const AuditAccessDenied(),
        ),
      ),
    );

void _expectDeniedUnlessBypass(WidgetTester tester) {
  if (_bypass) {
    expect(find.text('ALLOWED'), findsOneWidget);
  } else {
    expect(find.byType(AuditAccessDenied), findsOneWidget);
    expect(find.text('ALLOWED'), findsNothing);
  }
}

void main() {
  testWidgets('approved auditor may audit', (tester) async {
    await tester.pumpWidget(_harness(_user('auditor')));
    expect(find.text('ALLOWED'), findsOneWidget);
    expect(find.byType(AuditAccessDenied), findsNothing);
  });

  testWidgets('admin may audit', (tester) async {
    await tester.pumpWidget(_harness(_user('admin')));
    expect(find.text('ALLOWED'), findsOneWidget);
  });

  testWidgets('customer is blocked (read-only)', (tester) async {
    await tester.pumpWidget(_harness(_user('customer')));
    _expectDeniedUnlessBypass(tester);
    if (!_bypass) {
      expect(find.textContaining('read-only'), findsOneWidget);
    }
  });

  testWidgets('unapproved auditor is blocked', (tester) async {
    await tester.pumpWidget(_harness(_user('auditor', status: 'pending')));
    _expectDeniedUnlessBypass(tester);
  });

  testWidgets('signed-out (null) is blocked', (tester) async {
    await tester.pumpWidget(_harness(null));
    _expectDeniedUnlessBypass(tester);
  });
}
