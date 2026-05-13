import 'package:flutter/foundation.dart';

class AuthSecurityPolicy {
  static const bool _debugAuthBypassFlag = bool.fromEnvironment(
    'CHICKMARK_DEBUG_AUTH_BYPASS',
    defaultValue: false,
  );

  static const bool _localFallbackAuthFlag = bool.fromEnvironment(
    'CHICKMARK_ENABLE_LOCAL_FALLBACK_AUTH',
    defaultValue: false,
  );

  static bool get isDebugAuthBypassEnabled => allowsDebugAuthBypass(
    isDebugMode: kDebugMode,
    explicitFlag: _debugAuthBypassFlag,
  );

  static bool get isLocalFallbackAuthEnabled => allowsLocalFallbackAuth(
    isReleaseMode: kReleaseMode,
    explicitFlag: _localFallbackAuthFlag,
  );

  @visibleForTesting
  static bool allowsDebugAuthBypass({
    required bool isDebugMode,
    required bool explicitFlag,
  }) {
    return isDebugMode && explicitFlag;
  }

  @visibleForTesting
  static bool allowsLocalFallbackAuth({
    required bool isReleaseMode,
    required bool explicitFlag,
  }) {
    return !isReleaseMode || explicitFlag;
  }
}

class SupabaseSecurityPolicy {
  static const bool _publicPhotoUrlFlag = bool.fromEnvironment(
    'CHICKMARK_ALLOW_PUBLIC_PHOTO_URLS',
    defaultValue: false,
  );

  static bool get isPublicPhotoUrlEnabled =>
      allowsPublicPhotoUrls(explicitFlag: _publicPhotoUrlFlag);

  @visibleForTesting
  static bool allowsPublicPhotoUrls({required bool explicitFlag}) {
    return explicitFlag;
  }
}
