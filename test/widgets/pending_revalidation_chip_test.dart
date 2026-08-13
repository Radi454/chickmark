import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/network/network_status_monitor.dart';
import 'package:hatchaudit/features/home/widgets/main_shell.dart';
import 'package:provider/provider.dart';

NetworkStatusMonitor _monitor(bool offline) => NetworkStatusMonitor(
  checkReachability: () async => !offline,
  connectivityStream: const Stream.empty(),
  initialStatus: offline ? NetworkStatus.offline : NetworkStatus.online,
  startImmediately: false,
);

Future<void> _pumpChip(WidgetTester tester, {required bool offline}) {
  return tester.pumpWidget(
    ChangeNotifierProvider<NetworkStatusMonitor>(
      create: (_) => _monitor(offline),
      child: const MaterialApp(home: Scaffold(body: PendingRevalidationChip())),
    ),
  );
}

void main() {
  testWidgets('renders the offline chip when the network is offline', (
    tester,
  ) async {
    await _pumpChip(tester, offline: true);
    await tester.pump();

    expect(find.text('Offline — will reconnect automatically'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });

  testWidgets('renders nothing when the network is online', (tester) async {
    await _pumpChip(tester, offline: false);
    await tester.pump();

    expect(find.text('Offline — will reconnect automatically'), findsNothing);
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
    await _pumpChip(tester, offline: true);
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
        ChangeNotifierProvider<NetworkStatusMonitor>(
          create: (_) => _monitor(true),
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
          child: ChangeNotifierProvider<NetworkStatusMonitor>(
            create: (_) => _monitor(true),
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
          ChangeNotifierProvider<NetworkStatusMonitor>(
            create: (_) => _monitor(true),
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
