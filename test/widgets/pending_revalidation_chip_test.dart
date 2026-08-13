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

  // Fix-round-2 regression guard: on a real device with no app-level
  // Scaffold appBar, the tab area used to render at the physical top of the
  // screen with nothing accounting for the status bar / notch — the chip
  // overlapped it, and the active tab's own (nested, `primary`) AppBar
  // double-padded for the same inset, getting pushed further down than the
  // chip's height alone explains. Simulates a device top inset via an
  // ancestor MediaQuery (the standard widget-test technique for this,
  // since no real notch exists under the test binding) and asserts both
  // halves of the fix: the chip clears the inset, and the inset is fully
  // consumed here rather than handed down again to `content`.
  testWidgets(
    'the tab area respects the top safe area and does not hand the inset '
    'down to content a second time',
    (tester) async {
      const topInset = 59.0; // Dynamic Island-class notch, in logical px.
      double? contentTopPadding;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: topInset)),
          child: ChangeNotifierProvider<AuthProvider>(
            create: (_) => _FakeAuthProvider(pending: true),
            child: MaterialApp(
              home: Scaffold(
                body: buildMainShellTabAreaForTest(
                  content: Builder(
                    builder: (context) {
                      contentTopPadding = MediaQuery.paddingOf(context).top;
                      return const Text('main-shell-tab-content');
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The composition must be wrapped in a top-only SafeArea — the
      // structural fix — not just happen to clear the inset by accident.
      final safeArea = tester.widget<SafeArea>(find.byType(SafeArea));
      expect(safeArea.top, isTrue);
      expect(safeArea.bottom, isFalse);
      expect(
        find.descendant(
          of: find.byType(SafeArea),
          matching: find.byType(PendingRevalidationChip),
        ),
        findsOneWidget,
      );

      // The chip must never render under the notch/status bar.
      final chipTop = tester
          .getTopLeft(find.text('Offline — will reconnect automatically'))
          .dy;
      expect(chipTop, greaterThanOrEqualTo(topInset));

      // The inset must be fully consumed by the SafeArea here, not hand it
      // down again — otherwise a real per-screen GradientAppBar (which is
      // `primary` and pads itself for MediaQuery.padding.top) would
      // double-pad and get pushed further down than the chip's own height
      // explains, which is exactly the bug this test guards against.
      expect(contentTopPadding, 0);
    },
  );

  // Review finding: the previous shell-wiring test above only proved the
  // chip is wired into _MainShellTabArea in isolation — nothing proved
  // _MainShellState.build() actually *uses* _MainShellTabArea rather than
  // bypassing it. Confirmed empirically: editing the real call site
  // (`Expanded(child: _MainShellTabArea(content: ...))` ->
  // `Expanded(child: ...)`) left every existing test green.
  //
  // buildMainShellBodyForTest() closes that gap because it does not
  // reconstruct the composition in parallel — it calls the exact same
  // private _buildMainShellBody() function that _MainShellState.build()
  // calls for its Scaffold body. There is only one place in the source
  // that wires the rail + _MainShellTabArea together; this test and the
  // real shell both go through it, so a regression there is a regression
  // here. Verified by deliberately reverting _buildMainShellBody() to
  // bypass _MainShellTabArea (`Expanded(child: content)`) and confirming
  // this test fails — see the fix-round-2 report for that experiment.
  testWidgets(
    'the real shell body composition wires the chip in, on both layouts',
    (tester) async {
      for (final useNavigationRail in [false, true]) {
        await tester.pumpWidget(
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => _FakeAuthProvider(pending: true),
            child: MaterialApp(
              home: Scaffold(
                body: buildMainShellBodyForTest(
                  useNavigationRail: useNavigationRail,
                  content: const Text('main-shell-tab-content'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text('Offline — will reconnect automatically'),
          findsOneWidget,
          reason: 'useNavigationRail: $useNavigationRail',
        );

        final chipTop = tester
            .getTopLeft(find.text('Offline — will reconnect automatically'))
            .dy;
        final contentTop = tester
            .getTopLeft(find.text('main-shell-tab-content'))
            .dy;
        expect(
          chipTop,
          lessThan(contentTop),
          reason: 'useNavigationRail: $useNavigationRail',
        );
      }
    },
  );
}
