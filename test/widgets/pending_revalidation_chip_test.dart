import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/home/widgets/main_shell.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

// A real AuthProvider() would hit sqflite via UserRepository the moment any
// auth flow runs, which hangs testWidgets under FakeAsync (see
// test/features/auth/auth_provider_test.dart's Fake* stores for the full
// version of this workaround). This chip only ever reads
// `isPendingRevalidation`, so a thin subclass that overrides just that
// getter — and never calls checkCachedToken/login — sidesteps the DB
// entirely while still being a real AuthProvider for `context.select`.
class _MockSupabaseService extends Mock implements SupabaseService {}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider({required bool pending})
    : _pending = pending,
      super(supabaseService: _MockSupabaseService());

  final bool _pending;

  @override
  bool get isPendingRevalidation => _pending;
}

Future<void> _pumpChip(WidgetTester tester, {required bool pending}) {
  return tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => _FakeAuthProvider(pending: pending),
      child: const MaterialApp(
        home: Scaffold(body: PendingRevalidationChip()),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the offline chip while revalidation is pending', (
    tester,
  ) async {
    await _pumpChip(tester, pending: true);
    await tester.pump();

    expect(
      find.text('Offline — will reconnect automatically'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });

  testWidgets('renders nothing once revalidation is no longer pending', (
    tester,
  ) async {
    await _pumpChip(tester, pending: false);
    await tester.pump();

    expect(
      find.text('Offline — will reconnect automatically'),
      findsNothing,
    );
    expect(find.byType(PendingRevalidationChip), findsOneWidget);
    expect(
      tester.widget<PendingRevalidationChip>(
        find.byType(PendingRevalidationChip),
      ),
      isNotNull,
    );
  });

  testWidgets('the chip is purely informational — no tap target', (
    tester,
  ) async {
    await _pumpChip(tester, pending: true);
    await tester.pump();

    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });
}
