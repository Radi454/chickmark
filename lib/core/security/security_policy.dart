import 'package:flutter/foundation.dart';

class AuthSecurityPolicy {
  static const bool _debugAuthBypassFlag = bool.fromEnvironment(
    'CHICKMARK_DEBUG_AUTH_BYPASS',
    defaultValue: true,
  );

  static const bool _localFallbackAuthFlag = bool.fromEnvironment(
    'CHICKMARK_ENABLE_LOCAL_FALLBACK_AUTH',
    defaultValue: false,
  );

  static bool get isDebugAuthBypassEnabled => allowsDebugAuthBypass(
    isNonReleaseMode: !kReleaseMode,
    isLocalPreviewHost: _isLocalPreviewHost(Uri.base.host),
    explicitFlag: _debugAuthBypassFlag,
  );

  static bool get isLocalFallbackAuthEnabled => allowsLocalFallbackAuth(
    isReleaseMode: kReleaseMode,
    explicitFlag: _localFallbackAuthFlag,
  );

  @visibleForTesting
  static bool allowsDebugAuthBypass({
    required bool isNonReleaseMode,
    bool isLocalPreviewHost = false,
    required bool explicitFlag,
  }) {
    return (isNonReleaseMode || isLocalPreviewHost) && explicitFlag;
  }

  static bool _isLocalPreviewHost(String host) =>
      host == '127.0.0.1' || host == 'localhost' || host == '::1';

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
