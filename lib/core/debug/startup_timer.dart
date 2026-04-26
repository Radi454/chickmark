import 'package:flutter/foundation.dart';

class StartupTimer {
  static final Stopwatch _stopwatch = Stopwatch()..start();
  static final List<String> _laps = [];

  static void lap(String name) {
    final elapsed = _stopwatch.elapsedMilliseconds;
    _laps.add('$name: ${elapsed}ms');
    debugPrint('[STARTUP] $name: ${elapsed}ms');
  }

  static void report() {
    debugPrint('[STARTUP] === Full Startup Report ===');
    for (final entry in _laps) {
      debugPrint('[STARTUP] $entry');
    }
    debugPrint('[STARTUP] Total: ${_stopwatch.elapsedMilliseconds}ms');
  }

  static void reset() {
    _stopwatch.reset();
    _laps.clear();
  }
}