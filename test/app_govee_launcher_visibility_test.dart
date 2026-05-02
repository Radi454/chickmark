import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/app.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';

void main() {
  group('Govee launcher route visibility', () {
    test('uses the authenticated initial route when observed route is null', () {
      expect(
        shouldShowGoveeLauncher(
          state: AuthState.authenticated,
          currentRoute: null,
          currentPageRouteDepth: 1,
        ),
        isTrue,
      );
    });

    test('hides on pushed page routes even when route names are null', () {
      expect(
        shouldShowGoveeLauncher(
          state: AuthState.authenticated,
          currentRoute: null,
          currentPageRouteDepth: 2,
        ),
        isFalse,
      );
    });
  });
}
