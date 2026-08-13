/// How long the two auth gates stay open.
///
/// The login gate (real Supabase credentials) is unchanged by these values.
/// These govern only the usage gate: how long a device that has *already*
/// proven a successful login may keep working while it cannot reach the
/// server.
class AuthSessionPolicy {
  const AuthSessionPolicy._();

  /// A device that authenticated successfully may keep working offline for
  /// this long before it must prove itself again.
  ///
  /// Deliberately shorter than the Supabase inactivity timeout (90 days) so a
  /// device returning from the longest permitted offline stretch can still
  /// refresh instead of meeting a dead refresh token.
  static const Duration offlineGrace = Duration(days: 30);
}
