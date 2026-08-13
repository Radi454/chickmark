import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Proof that this install completed a successful online authentication.
///
/// This is *not* a credential — it grants nothing on its own. It only records
/// that the login gate was passed, so the usage gate can stay open while the
/// device is offline.
@immutable
class SessionTrust {
  final String userId;
  final DateTime lastVerifiedAt;

  const SessionTrust({required this.userId, required this.lastVerifiedAt});
}

/// Keychain-backed store for the [SessionTrust] record.
///
/// Lives in secure storage rather than SQLite so it cannot be read or edited
/// from the app's database file.
class SessionTrustStore {
  static const String storageKey = 'session_trust_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final Map<String, String> _webFallback = <String, String>{};

  final Future<String?> Function(String key) _readValue;
  final Future<void> Function(String key, String value) _writeValue;
  final Future<void> Function(String key) _deleteValue;

  SessionTrustStore({
    Future<String?> Function(String key)? readValue,
    Future<void> Function(String key, String value)? writeValue,
    Future<void> Function(String key)? deleteValue,
  }) : _readValue = readValue ?? _defaultRead,
       _writeValue = writeValue ?? _defaultWrite,
       _deleteValue = deleteValue ?? _defaultDelete;

  static Future<String?> _defaultRead(String key) async {
    if (kIsWeb) return _webFallback[key];
    return _storage.read(key: key);
  }

  static Future<void> _defaultWrite(String key, String value) async {
    if (kIsWeb) {
      _webFallback[key] = value;
      return;
    }
    await _storage.write(key: key, value: value);
  }

  static Future<void> _defaultDelete(String key) async {
    if (kIsWeb) {
      _webFallback.remove(key);
      return;
    }
    await _storage.delete(key: key);
  }

  Future<SessionTrust?> read() async {
    final raw = await _readValue(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final userId = decoded['userId'];
      final verifiedAt = decoded['lastVerifiedAt'];
      if (userId is! String || userId.isEmpty || verifiedAt is! String) {
        return null;
      }
      final parsed = DateTime.tryParse(verifiedAt);
      if (parsed == null) return null;
      return SessionTrust(userId: userId, lastVerifiedAt: parsed);
    } catch (_) {
      return null;
    }
  }

  Future<void> record(String userId, DateTime verifiedAt) async {
    await _writeValue(
      storageKey,
      jsonEncode({
        'userId': userId,
        'lastVerifiedAt': verifiedAt.toIso8601String(),
      }),
    );
  }

  Future<void> clear() => _deleteValue(storageKey);
}
