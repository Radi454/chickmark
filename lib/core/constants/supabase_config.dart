import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

/// Supabase configuration constants.
///
/// Credentials come from one of two sources, in priority order:
///   1. Compile-time `--dart-define` / `--dart-define-from-file` (production,
///      CI). These win and skip the runtime load entirely.
///   2. The bundled `.env.json` asset, loaded at runtime via [ensureLoaded].
///      This lets a plain `flutter run` (no --dart-define) still reach the
///      cloud during local development.
///
/// The committed `.env.json` contains placeholders only. Real credentials
/// should be supplied with `--dart-define` / `--dart-define-from-file`, or kept
/// local and never committed.
class SupabaseConfig {
  static const String _compileTimeUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String _compileTimeAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static String _url = _compileTimeUrl;
  static String _anonKey = _compileTimeAnonKey;

  /// Supabase project URL.
  static String get url => _url;

  /// Supabase anonymous (publishable) key.
  static String get anonKey => _anonKey;

  /// Whether usable credentials are present.
  static bool get isConfigured =>
      _url.isNotEmpty &&
      _anonKey.isNotEmpty &&
      !_url.startsWith('YOUR_') &&
      !_anonKey.startsWith('YOUR_');

  /// Loads credentials from the bundled `.env.json` asset when they were not
  /// supplied at compile time. Safe to call multiple times. Never throws — a
  /// missing/unreadable asset just leaves the config unset (surfaced as "Cloud
  /// not configured" in the UI).
  static Future<void> ensureLoaded() async {
    final credentials = await _resolveCredentials(
      compileTimeUrl: _compileTimeUrl,
      compileTimeAnonKey: _compileTimeAnonKey,
      loadAsset: () => rootBundle.loadString('.env.json'),
    );

    _url = credentials.url;
    _anonKey = credentials.anonKey;
  }

  @visibleForTesting
  static Future<SupabaseCredentials> resolveForTesting({
    required String compileTimeUrl,
    required String compileTimeAnonKey,
    required Future<String> Function() loadAsset,
  }) {
    return _resolveCredentials(
      compileTimeUrl: compileTimeUrl,
      compileTimeAnonKey: compileTimeAnonKey,
      loadAsset: loadAsset,
    );
  }

  static Future<SupabaseCredentials> _resolveCredentials({
    required String compileTimeUrl,
    required String compileTimeAnonKey,
    required Future<String> Function() loadAsset,
  }) async {
    final normalizedCompileUrl = compileTimeUrl.trim();
    final normalizedCompileAnonKey = compileTimeAnonKey.trim();

    if (_hasUsableCredentials(normalizedCompileUrl, normalizedCompileAnonKey)) {
      return SupabaseCredentials(
        url: normalizedCompileUrl,
        anonKey: normalizedCompileAnonKey,
      );
    }

    final canUseAssetFallback =
        _isEmptyOrPlaceholder(normalizedCompileUrl) &&
        _isEmptyOrPlaceholder(normalizedCompileAnonKey);
    if (!canUseAssetFallback) {
      return SupabaseCredentials.empty;
    }

    try {
      final raw = await loadAsset();
      final map = json.decode(raw) as Map<String, dynamic>;
      final url = (map['SUPABASE_URL'] as String?)?.trim();
      final key = (map['SUPABASE_ANON_KEY'] as String?)?.trim();
      if (_hasUsableCredentials(url, key)) {
        return SupabaseCredentials(url: url!, anonKey: key!);
      }
    } catch (_) {
      // No bundled config available — leave credentials unset.
    }

    return SupabaseCredentials.empty;
  }

  static bool _hasUsableCredentials(String? url, String? anonKey) =>
      !_isEmptyOrPlaceholder(url) && !_isEmptyOrPlaceholder(anonKey);

  static bool _isEmptyOrPlaceholder(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty || normalized.startsWith('YOUR_');
  }
}

@visibleForTesting
class SupabaseCredentials {
  const SupabaseCredentials({required this.url, required this.anonKey});

  static const empty = SupabaseCredentials(url: '', anonKey: '');

  final String url;
  final String anonKey;
}
