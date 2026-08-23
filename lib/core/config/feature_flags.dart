import 'package:flutter/foundation.dart';

/// App-wide feature flags. Compile-time defaults, runtime-overridable so
/// tests can flip a flag back on without a rebuild.
class FeatureFlags {
  /// Pip Live (OpenAI Realtime voice) is PARKED during the text-agent
  /// stabilization phase. The implementation is intact; only the UI entry
  /// points are gated. Restore with
  /// `--dart-define=PIP_REALTIME_ENABLED=true` or by flipping the default.
  static const bool realtimeEnabledDefault = bool.fromEnvironment(
    'PIP_REALTIME_ENABLED',
  );

  static bool realtimeEnabled = realtimeEnabledDefault;

  @visibleForTesting
  static void resetForTest() => realtimeEnabled = realtimeEnabledDefault;
}
