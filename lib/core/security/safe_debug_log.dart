import 'package:flutter/foundation.dart';

void safeDebugLog(String message, {Object? error}) {
  if (!kDebugMode) return;
  if (error == null) {
    debugPrint(message);
    return;
  }
  debugPrint('$message: ${sanitizeLogValue(error)}');
}

@visibleForTesting
String sanitizeLogValue(Object value) {
  final text = value.toString().replaceFirst(
    RegExp(r'^(Exception|Error):\s*'),
    '',
  );
  return text
      .replaceAll(
        RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
        '[redacted-jwt]',
      )
      .replaceAll(
        RegExp(r'sb_(publishable|secret)_[A-Za-z0-9_-]+'),
        'sb_[redacted]',
      )
      .replaceAllMapped(
        RegExp(
          r'(access[_-]?token|refresh[_-]?token|password)=\S+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}=[redacted]',
      );
}
