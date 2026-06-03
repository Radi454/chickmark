import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/security/safe_debug_log.dart';

void main() {
  test('sanitizeLogValue redacts tokens and passwords without throwing', () {
    final sanitized = sanitizeLogValue(
      'Exception: access_token=abc refresh-token=def password=swordfish',
    );

    expect(sanitized, isNot(contains('abc')));
    expect(sanitized, isNot(contains('def')));
    expect(sanitized, isNot(contains('swordfish')));
    expect(sanitized, contains('access_token=[redacted]'));
    expect(sanitized, contains('refresh-token=[redacted]'));
    expect(sanitized, contains('password=[redacted]'));
  });
}
