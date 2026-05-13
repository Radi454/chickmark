import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';

class SupabaseInitializer {
  static Future<bool>? _initialization;
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static Future<bool> ensureInitialized() async {
    if (!SupabaseConfig.isConfigured) {
      _initialized = false;
      return false;
    }
    if (_initialized) return true;

    final inFlight = _initialization;
    if (inFlight != null) {
      return inFlight;
    }

    final initialization =
        Supabase.initialize(
              url: SupabaseConfig.url,
              anonKey: SupabaseConfig.anonKey,
            )
            .then((_) {
              _initialized = true;
              return true;
            })
            .catchError((Object error) {
              _initialized = false;
              throw error;
            })
            .whenComplete(() {
              if (!_initialized) {
                _initialization = null;
              }
            });

    _initialization = initialization;
    return initialization;
  }

  @visibleForTesting
  static void resetForTesting() {
    _initialization = null;
    _initialized = false;
  }
}
