bool auditNumericBrowserPrefersSystemKeyboard({
  required String platform,
  required String userAgent,
  required bool hasDesktopPointer,
}) {
  final normalizedPlatform = platform.toLowerCase();
  final normalizedUserAgent = userAgent.toLowerCase();

  final isAppleMobilePlatform =
      normalizedPlatform.contains('iphone') ||
      normalizedPlatform.contains('ipad') ||
      normalizedPlatform.contains('ipod');
  if (isAppleMobilePlatform || normalizedUserAgent.contains('android')) {
    return false;
  }

  final isDesktopPlatform =
      normalizedPlatform.startsWith('mac') ||
      normalizedPlatform.startsWith('win') ||
      normalizedPlatform.startsWith('linux');
  if (isDesktopPlatform) return true;

  if (normalizedUserAgent.contains('mobile')) return false;

  return hasDesktopPointer;
}
