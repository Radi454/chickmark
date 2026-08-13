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

  // Regression guard for the shell wiring itself, not just the chip in
  // isolation: pumps buildMainShellTabAreaForTest(), the same composition
  // MainShell.build() uses for chip + active tab content, so a future edit
  // that drops the chip from that composition or reorders it after the tab
  // content fails here — without pumping the real, sqflite-backed
  // MainShell (which hangs testWidgets under FakeAsync).
  testWidgets(
    'the shell composes the chip above the active tab content, in order',
    (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => _FakeAuthProvider(pending: true),
          child: MaterialApp(
            home: Scaffold(
              body: buildMainShellTabAreaForTest(
                content: const Text('main-shell-tab-content'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final column = tester.widget<Column>(find.byType(Column));
      expect(column.children.length, 2);
      expect(column.children.first, isA<PendingRevalidationChip>());
      expect(column.children.last, isA<Expanded>());

      // And the chip actually renders above the content on screen.
      final chipTop = tester
          .getTopLeft(find.text('Offline — will reconnect automatically'))
          .dy;
      final contentTop = tester
          .getTopLeft(find.text('main-shell-tab-content'))
          .dy;
      expect(chipTop, lessThan(contentTop));
    },
  );
}
