import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureTokenStore {
  static const _prefix = 'token_';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static final Map<String, String> _webFallback = <String, String>{};

  static Future<void> saveToken(String userId, String token) async {
    final key = '$_prefix$userId';
    if (kIsWeb) {
      _webFallback[key] = token;
      return;
    }
    await _storage.write(key: key, value: token);
  }

  static Future<String?> getToken(String userId) async {
    final key = '$_prefix$userId';
    if (kIsWeb) {
      return _webFallback[key];
    }
    return _storage.read(key: key);
  }

  static Future<void> deleteToken(String userId) async {
    final key = '$_prefix$userId';
    if (kIsWeb) {
      _webFallback.remove(key);
      return;
    }
    await _storage.delete(key: key);
  }

  static Future<void> deleteAll() async {
    if (kIsWeb) {
      _webFallback.clear();
      return;
    }
    final all = await _storage.readAll();
    for (final key in all.keys.where((key) => key.startsWith(_prefix))) {
      await _storage.delete(key: key);
    }
  }
}
