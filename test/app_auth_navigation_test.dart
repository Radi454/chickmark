import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/app.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';

void main() {
  test('unauthenticated auth state redirects app routes back to login', () {
    expect(
      authRedirectRouteForState(
        state: AuthState.unauthenticated,
        topRouteName: '/main',
      ),
      '/login',
    );
  });

  test('unauthenticated auth state does not redirect pre-app routes', () {
    for (final routeName in [
      '/login',
      '/register',
      '/pending-approval',
      '/startup-sync',
    ]) {
      expect(
        authRedirectRouteForState(
          state: AuthState.unauthenticated,
          topRouteName: routeName,
        ),
        isNull,
      );
    }
  });

  test('error auth state redirects protected app routes back to login', () {
    expect(
      authRedirectRouteForState(state: AuthState.error, topRouteName: '/main'),
      '/login',
    );
  });

  test('loading and authenticated auth states do not force login redirect', () {
    expect(
      authRedirectRouteForState(
        state: AuthState.loading,
        topRouteName: '/main',
      ),
      isNull,
    );
    expect(
      authRedirectRouteForState(
        state: AuthState.authenticated,
        topRouteName: '/main',
      ),
      isNull,
    );
  });
}
