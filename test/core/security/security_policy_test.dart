import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/security/security_policy.dart';

void main() {
  group('AuthSecurityPolicy', () {
    test('blocks debug auth bypass outside debug builds', () {
      expect(
        AuthSecurityPolicy.allowsDebugAuthBypass(
          isDebugMode: false,
          explicitFlag: true,
        ),
        isFalse,
      );
    });

    test('requires an explicit compile-time flag for debug auth bypass', () {
      expect(
        AuthSecurityPolicy.allowsDebugAuthBypass(
          isDebugMode: true,
          explicitFlag: false,
        ),
        isFalse,
      );
      expect(
        AuthSecurityPolicy.allowsDebugAuthBypass(
          isDebugMode: true,
          explicitFlag: true,
        ),
        isTrue,
      );
    });

    test(
      'disables local fallback auth in release unless explicitly enabled',
      () {
        expect(
          AuthSecurityPolicy.allowsLocalFallbackAuth(
            isReleaseMode: true,
            explicitFlag: false,
          ),
          isFalse,
        );
        expect(
          AuthSecurityPolicy.allowsLocalFallbackAuth(
            isReleaseMode: true,
            explicitFlag: true,
          ),
          isTrue,
        );
      },
    );
  });

  group('SupabaseSecurityPolicy', () {
    test('does not expose public photo URLs unless explicitly enabled', () {
      expect(
        SupabaseSecurityPolicy.allowsPublicPhotoUrls(explicitFlag: false),
        isFalse,
      );
      expect(
        SupabaseSecurityPolicy.allowsPublicPhotoUrls(explicitFlag: true),
        isTrue,
      );
    });
  });
}
