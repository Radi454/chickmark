import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/app.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/govee/widgets/govee_global_overlay.dart';

void main() {
  group('App Govee launcher route gate', () {
    test('redirects unauthenticated users back to login from app routes', () {
      expect(
        authRedirectRouteForState(
          state: AuthState.unauthenticated,
          topRouteName: '/main',
        ),
        '/login',
      );
      expect(
        authRedirectRouteForState(state: AuthState.error, topRouteName: null),
        '/login',
      );
      expect(
        authRedirectRouteForState(
          state: AuthState.unauthenticated,
          topRouteName: '/login',
        ),
        isNull,
      );
    });

    test('hides the launcher until the main app shell is entered', () {
      expect(
        shouldShowGoveeGlobalLauncher(
          launcherReady: true,
          canUseGoveeLauncher: true,
          hasEnteredMainShell: false,
          topRouteName: '/login',
        ),
        isFalse,
      );
      expect(
        shouldShowGoveeGlobalLauncher(
          launcherReady: true,
          canUseGoveeLauncher: true,
          hasEnteredMainShell: false,
          topRouteName: '/startup-sync',
        ),
        isFalse,
      );
    });

    test('shows the launcher in and beyond the main app shell', () {
      expect(
        shouldShowGoveeGlobalLauncher(
          launcherReady: true,
          canUseGoveeLauncher: true,
          hasEnteredMainShell: true,
          topRouteName: '/main',
        ),
        isTrue,
      );
      expect(
        shouldShowGoveeGlobalLauncher(
          launcherReady: true,
          canUseGoveeLauncher: true,
          hasEnteredMainShell: true,
          topRouteName: null,
        ),
        isTrue,
      );
    });
  });

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
      final launcherTapTarget = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const ValueKey('govee-global-launcher')),
          matching: find.byType(InkWell),
        ),
      );
      expect(launcherTapTarget.canRequestFocus, isFalse);
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

    testWidgets('keeps the launcher visible above pushed audit routes', (
      tester,
    ) async {
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) {
            return GoveeGlobalOverlay(
              showLauncher: true,
              panelContextBuilder: () => navigatorKey.currentContext,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) {
                            return const Scaffold(
                              body: Center(child: Text('Audit station')),
                            );
                          },
                        ),
                      );
                    },
                    child: const Text('Open audit'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('govee-global-launcher')),
        findsOneWidget,
      );

      await tester.tap(find.text('Open audit'));
      await tester.pumpAndSettle();

      expect(find.text('Audit station'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('govee-global-launcher')),
        findsOneWidget,
      );
    });

    testWidgets('uses recording colors and shape while capture is active', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GoveeGlobalOverlay(
            showLauncher: true,
            isRecording: true,
            panelContextBuilder: _nullPanelContext,
            child: Scaffold(body: Text('Home')),
          ),
        ),
      );

      final material = tester.widget<Material>(
        find.byKey(const ValueKey('govee-global-launcher')),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.stop_rounded));

      expect(material.color, AppColors.statusError);
      expect(material.shape, isA<RoundedRectangleBorder>());
      expect(material.shape, isNot(isA<CircleBorder>()));
      expect(icon.color, AppColors.statusErrorBg);
    });

    testWidgets('moves and tucks into the left screen edge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: GoveeGlobalOverlay(
            showLauncher: true,
            panelContextBuilder: _nullPanelContext,
            child: Scaffold(body: Text('Home')),
          ),
        ),
      );

      final launcherFinder = find.byKey(
        const ValueKey('govee-global-launcher'),
      );
      final initialTopLeft = tester.getTopLeft(launcherFinder);

      await tester.drag(launcherFinder, const Offset(-500, -120));
      await tester.pumpAndSettle();

      final tuckedRect = tester.getRect(launcherFinder);
      expect(tuckedRect.left, lessThan(0));
      expect(tuckedRect.right, greaterThan(0));
      expect(tuckedRect.top, lessThan(initialTopLeft.dy));
    });

    testWidgets('tucks into the right screen edge', (tester) async {
      const surfaceSize = Size(390, 844);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: GoveeGlobalOverlay(
            showLauncher: true,
            panelContextBuilder: _nullPanelContext,
            child: Scaffold(body: Text('Home')),
          ),
        ),
      );

      final launcherFinder = find.byKey(
        const ValueKey('govee-global-launcher'),
      );

      await tester.drag(launcherFinder, const Offset(160, -80));
      await tester.pumpAndSettle();

      final tuckedRect = tester.getRect(launcherFinder);
      expect(tuckedRect.left, lessThan(surfaceSize.width));
      expect(tuckedRect.right, greaterThan(surfaceSize.width));
    });
  });
}

BuildContext? _nullPanelContext() => null;
