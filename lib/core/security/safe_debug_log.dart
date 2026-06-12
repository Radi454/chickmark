import 'package:flutter/foundation.dart';

void safeDebugLog(String message, {Object? error, StackTrace? stackTrace}) {
  if (!kDebugMode) return;
  if (error == null) {
    debugPrint(message);
  } else {
    debugPrint('$message: ${sanitizeLogValue(error)}');
  }
  if (stackTrace != null) {
    debugPrint(sanitizeLogValue(stackTrace));
  }
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
          r'''"(access[_-]?token|refresh[_-]?token|password|api[_-]?key|apikey)"(\s*:\s*)"([^"]*)"''',
          caseSensitive: false,
        ),
        (match) => '"${match.group(1)}"${match.group(2)}"[redacted]"',
      )
      .replaceAllMapped(
        RegExp(
          r'''\b(access[_-]?token|refresh[_-]?token|password|api[_-]?key|apikey)(\s*=\s*)([^&\s;,"')]+)''',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}${match.group(2)}[redacted]',
      );
}
