import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/security/safe_debug_log.dart';

void main() {
  test('sanitizeLogValue redacts JWT tokens', () {
    final sanitized = sanitizeLogValue(
      'auth token eyJhbGciOiJIUzI1NiJ9.fakePayload.fakeSignature',
    );

    expect(sanitized, isNot(contains('fakePayload')));
    expect(sanitized, contains('[redacted-jwt]'));
  });

  test('sanitizeLogValue redacts Supabase keys', () {
    final sanitized = sanitizeLogValue(
      'keys sb_publishable_fakePublicKey sb_secret_fakeSecretKey',
    );

    expect(sanitized, isNot(contains('fakePublicKey')));
    expect(sanitized, isNot(contains('fakeSecretKey')));
    expect(sanitized, contains('sb_[redacted]'));
  });

  test(
    'sanitizeLogValue redacts access and refresh tokens in key-value format',
    () {
      final sanitized = sanitizeLogValue(
        'Exception: access_token=fakeAccess&refresh_token=fakeRefresh',
      );

      expect(sanitized, isNot(contains('fakeAccess')));
      expect(sanitized, isNot(contains('fakeRefresh')));
      expect(sanitized, contains('access_token=[redacted]'));
      expect(sanitized, contains('refresh_token=[redacted]'));
    },
  );

  test('sanitizeLogValue redacts password in JSON format', () {
    final sanitized = sanitizeLogValue(
      '{"password":"fakePassword","username":"demo"}',
    );

    expect(sanitized, isNot(contains('fakePassword')));
    expect(sanitized, contains('"password":"[redacted]"'));
    expect(sanitized, contains('"username":"demo"'));
  });

  test('sanitizeLogValue redacts api keys in query and JSON formats', () {
    final sanitized = sanitizeLogValue(
      'apikey=fakeQueryKey&api_key=fakeSnakeKey {"apikey":"fakeJsonKey","api_key":"fakeJsonSnakeKey"}',
    );

    expect(sanitized, isNot(contains('fakeQueryKey')));
    expect(sanitized, isNot(contains('fakeSnakeKey')));
    expect(sanitized, isNot(contains('fakeJsonKey')));
    expect(sanitized, isNot(contains('fakeJsonSnakeKey')));
    expect(sanitized, contains('apikey=[redacted]'));
    expect(sanitized, contains('api_key=[redacted]'));
    expect(sanitized, contains('"apikey":"[redacted]"'));
    expect(sanitized, contains('"api_key":"[redacted]"'));
  });

  test('sanitizeLogValue preserves ordinary messages', () {
    const message = 'Sync skipped for 3 rows due to offline mode';

    expect(sanitizeLogValue(message), message);
  });
}
