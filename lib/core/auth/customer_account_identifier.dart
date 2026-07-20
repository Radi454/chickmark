class CustomerAccountIdentifier {
  const CustomerAccountIdentifier._();

  static const emailDomain = 'customers.chickmark.app';
  static const emailSuffix = '@$emailDomain';

  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,39}$');

  /// Supabase password auth is email-based. Customer-facing usernames are
  /// mapped to deterministic, non-mailbox identities behind the scenes.
  static String loginEmail(String identifier) {
    final normalized = identifier.trim().toLowerCase();
    if (normalized.contains('@')) return normalized;
    return '$normalized$emailSuffix';
  }

  static String normalizeUsername(String username) =>
      username.trim().toLowerCase();

  static String? validateUsername(String? username) {
    if (username == null || username.trim().isEmpty) {
      return 'Enter a username';
    }
    final normalized = normalizeUsername(username);
    if (!_usernamePattern.hasMatch(normalized)) {
      return 'Use 3–40 letters, numbers, dots, dashes, or underscores';
    }
    return null;
  }

  static bool isCustomerLoginEmail(String email) =>
      email.trim().toLowerCase().endsWith(emailSuffix);

  static String displayIdentifier(String email) {
    final normalized = email.trim().toLowerCase();
    if (!isCustomerLoginEmail(normalized)) return email;
    return normalized.substring(0, normalized.length - emailSuffix.length);
  }
}
