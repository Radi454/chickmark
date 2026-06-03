import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/security/security_policy.dart';

void main() {
  group('AuthSecurityPolicy', () {
    test('blocks debug auth bypass in release builds', () {
      expect(
        AuthSecurityPolicy.allowsDebugAuthBypass(
          isNonReleaseMode: false,
          explicitFlag: true,
        ),
        isFalse,
      );
    });

    test('allows debug auth bypass on localhost previews', () {
      expect(
        AuthSecurityPolicy.allowsDebugAuthBypass(
          isNonReleaseMode: false,
          isLocalPreviewHost: true,
          explicitFlag: true,
        ),
        isTrue,
      );
    });

    test('honors the debug auth bypass flag in non-release builds', () {
      expect(
        AuthSecurityPolicy.allowsDebugAuthBypass(
          isNonReleaseMode: true,
          explicitFlag: false,
        ),
        isFalse,
      );
      expect(
        AuthSecurityPolicy.allowsDebugAuthBypass(
          isNonReleaseMode: true,
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
