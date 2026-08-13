import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/core/security/auth_session_policy.dart';
import 'package:hatchaudit/features/auth/services/startup_auth_decision.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

void main() {
  StartupAuthDecision decide({
    bool hasRememberedUser = true,
    bool isLocalAccount = false,
    bool localTokenValid = false,
    SessionRestoreStatus? sessionStatus,
    Duration? sinceLastVerified = const Duration(days: 1),
  }) {
    return decideStartupAuth(
      hasRememberedUser: hasRememberedUser,
      isLocalAccount: isLocalAccount,
      localTokenValid: localTokenValid,
      sessionStatus: sessionStatus,
      sinceLastVerified: sinceLastVerified,
    );
  }

  test('a fresh install with nothing remembered goes to login', () {
    expect(
      decide(hasRememberedUser: false, sessionStatus: null),
      StartupAuthDecision.goToLogin,
    );
  });

  test('a still-valid session enters the app', () {
    expect(
      decide(sessionStatus: SessionRestoreStatus.valid),
      StartupAuthDecision.enterApp,
    );
  });

  test('a silently refreshed session enters the app', () {
    expect(
      decide(sessionStatus: SessionRestoreStatus.refreshed),
      StartupAuthDecision.enterApp,
    );
  });

  test('a server rejection while online goes to login', () {
    expect(
      decide(sessionStatus: SessionRestoreStatus.rejected),
      StartupAuthDecision.goToLogin,
    );
  });

  test('offline inside the grace window enters the app pending revalidation', () {
    expect(
      decide(
        sessionStatus: SessionRestoreStatus.offline,
        sinceLastVerified: const Duration(days: 29, hours: 23),
      ),
      StartupAuthDecision.enterAppPendingRevalidation,
    );
  });

  test('offline exactly at the grace boundary still enters the app', () {
    expect(
      decide(
        sessionStatus: SessionRestoreStatus.offline,
        sinceLastVerified: AuthSessionPolicy.offlineGrace,
      ),
      StartupAuthDecision.enterAppPendingRevalidation,
    );
  });

  test('offline past the grace window goes to login', () {
    expect(
      decide(
        sessionStatus: SessionRestoreStatus.offline,
        sinceLastVerified: AuthSessionPolicy.offlineGrace +
            const Duration(seconds: 1),
      ),
      StartupAuthDecision.goToLogin,
    );
  });

  test('offline with no recorded successful login goes to login', () {
    expect(
      decide(
        sessionStatus: SessionRestoreStatus.offline,
        sinceLastVerified: null,
      ),
      StartupAuthDecision.goToLogin,
    );
  });

  test('a clock that jumped backwards is treated as within grace', () {
    expect(
      decide(
        sessionStatus: SessionRestoreStatus.offline,
        sinceLastVerified: const Duration(days: -2),
      ),
      StartupAuthDecision.enterAppPendingRevalidation,
    );
  });

  test('a valid local account enters the app without asking Supabase', () {
    expect(
      decide(
        isLocalAccount: true,
        localTokenValid: true,
        sessionStatus: null,
        sinceLastVerified: null,
      ),
      StartupAuthDecision.enterApp,
    );
  });

  test('an expired local account goes to login', () {
    expect(
      decide(
        isLocalAccount: true,
        localTokenValid: false,
        sessionStatus: null,
        sinceLastVerified: const Duration(days: 1),
      ),
      StartupAuthDecision.goToLogin,
    );
  });
}
