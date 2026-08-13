import '../../../core/security/auth_session_policy.dart';
import '../../../services/supabase/supabase_service.dart';

/// What the app should do with a startup (or resume) auth check.
enum StartupAuthDecision {
  /// Show the real login screen. Credentials are required.
  goToLogin,

  /// Proceed into the app with a session known to be good.
  enterApp,

  /// Proceed into the app on the strength of a previous successful login.
  /// The session still needs re-validating once the network returns.
  enterAppPendingRevalidation,
}

/// The three-case gate from the offline-auth requirement.
///
/// Authentication guards the door, not the data: a device that has already
/// proven a successful login keeps working while it cannot reach the server.
/// Only a definitive rejection *while online*, or the absence of any prior
/// successful login, sends the user back to `/login`.
///
/// - [sessionStatus] is null when Supabase was never consulted (local-only
///   account).
/// - [sinceLastVerified] is null when this install has never recorded a
///   successful online authentication.
StartupAuthDecision decideStartupAuth({
  required bool hasRememberedUser,
  required bool isLocalAccount,
  required bool localTokenValid,
  required SessionRestoreStatus? sessionStatus,
  required Duration? sinceLastVerified,
  Duration offlineGrace = AuthSessionPolicy.offlineGrace,
}) {
  if (!hasRememberedUser) {
    return StartupAuthDecision.goToLogin;
  }

  // Local-only accounts never had a Supabase session; their own expiry rules.
  if (isLocalAccount) {
    return localTokenValid
        ? StartupAuthDecision.enterApp
        : StartupAuthDecision.goToLogin;
  }

  switch (sessionStatus) {
    case SessionRestoreStatus.valid:
    case SessionRestoreStatus.refreshed:
      return StartupAuthDecision.enterApp;
    case SessionRestoreStatus.rejected:
      return StartupAuthDecision.goToLogin;
    case SessionRestoreStatus.offline:
    case null:
      if (sinceLastVerified == null) {
        return StartupAuthDecision.goToLogin;
      }
      // A device whose clock moved backwards yields a negative duration; that
      // is a clock problem, not a stale session, so keep the user working.
      return sinceLastVerified <= offlineGrace
          ? StartupAuthDecision.enterAppPendingRevalidation
          : StartupAuthDecision.goToLogin;
  }
}
