import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/app.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/govee/providers/govee_capture_provider.dart';
import 'package:hatchaudit/features/govee/widgets/govee_global_overlay.dart';
import 'package:provider/provider.dart';

void main() {
  group('Govee launcher route visibility', () {
    test(
      'uses the authenticated initial route when observed route is null',
      () {
        expect(
          shouldShowGoveeLauncher(
            state: AuthState.authenticated,
            hasObservedRoute: false,
            currentRoute: null,
            currentRouteIsPageRoute: true,
          ),
          isTrue,
        );
      },
    );

    test('hides on modal routes even when route names are null', () {
      expect(
        shouldShowGoveeLauncher(
          state: AuthState.authenticated,
          hasObservedRoute: true,
          currentRoute: null,
          currentRouteIsPageRoute: false,
        ),
        isFalse,
      );
    });
  });

  group('Govee launcher visibility', () {
    testWidgets('shows the floating launcher when enabled', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => GoveeCaptureProvider(),
          child: const MaterialApp(
            home: GoveeGlobalOverlay(
              showLauncher: true,
              panelContextBuilder: _nullPanelContext,
              child: Scaffold(body: Text('Home')),
            ),
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
        ChangeNotifierProvider(
          create: (_) => GoveeCaptureProvider(),
          child: const MaterialApp(
            home: GoveeGlobalOverlay(
              showLauncher: false,
              panelContextBuilder: _nullPanelContext,
              child: Scaffold(body: Text('Home')),
            ),
          ),
        ),
      );

      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const ValueKey('govee-global-launcher')), findsNothing);
    });
  });
}

BuildContext? _nullPanelContext() => null;
