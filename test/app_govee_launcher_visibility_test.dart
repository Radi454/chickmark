import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/govee/widgets/govee_global_overlay.dart';

void main() {
  group('Govee launcher visibility', () {
    testWidgets('shows the floating launcher when enabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GoveeGlobalOverlay(
            showLauncher: true,
            panelContextBuilder: _nullPanelContext,
            child: Scaffold(body: Text('Home')),
          ),
        ),
      );

      expect(find.text('Home'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('govee-global-launcher')),
        findsOneWidget,
      );
    });

    testWidgets('hides the floating launcher when disabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GoveeGlobalOverlay(
            showLauncher: false,
            panelContextBuilder: _nullPanelContext,
            child: Scaffold(body: Text('Home')),
          ),
        ),
      );

      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const ValueKey('govee-global-launcher')), findsNothing);
    });
  });
}

BuildContext? _nullPanelContext() => null;
