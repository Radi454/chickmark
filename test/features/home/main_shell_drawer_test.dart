import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/home/widgets/main_shell.dart';

void main() {
  testWidgets('compact macOS drawer scrolls every navigation destination', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int? selectedIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildMainShellNavigationDrawerForTest(
            onDestinationSelected: (index) => selectedIndex = index,
            labels: const [
              'Home',
              'Dashboard',
              'Customers',
              'Audits',
              'Govee',
              'Lab analysis',
              'BMK',
              'Performance',
              'Agent Monitor',
              'Settings',
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('main-shell-drawer-list')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Settings'),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('main-shell-drawer-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomRight(find.text('Settings')).dy,
      lessThanOrEqualTo(320),
    );
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(selectedIndex, 9);
  });
}
