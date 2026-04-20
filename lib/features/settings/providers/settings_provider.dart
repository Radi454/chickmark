import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  int _pasgarSampleSize = 40;
  int _weightsSampleSize = 100;
  int _traySize = 150;
  int _storageDays = 0;
  String? _lastSyncTimestamp;

  static const String _keyPasgarSampleSize = 'pref_pasgar_sample_size';
  static const String _keyWeightsSampleSize = 'pref_weights_sample_size';
  static const String _keyTraySize = 'pref_tray_size';
  static const String _keyStorageDays = 'pref_storage_days';
  static const String _keyLastSyncTimestamp = 'last_sync_timestamp';

  int get pasgarSampleSize => _pasgarSampleSize;
  int get weightsSampleSize => _weightsSampleSize;
  int get traySize => _traySize;
  int get storageDays => _storageDays;
  String? get lastSyncTimestamp => _lastSyncTimestamp;

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _pasgarSampleSize = prefs.getInt(_keyPasgarSampleSize) ?? 40;
    _weightsSampleSize = prefs.getInt(_keyWeightsSampleSize) ?? 100;
    _traySize = prefs.getInt(_keyTraySize) ?? 150;
    _storageDays = prefs.getInt(_keyStorageDays) ?? 0;
    _lastSyncTimestamp = prefs.getString(_keyLastSyncTimestamp);
    notifyListeners();
  }

  Future<void> setPasgarSampleSize(int value) async {
    _pasgarSampleSize = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPasgarSampleSize, value);
    notifyListeners();
  }

  Future<void> setWeightsSampleSize(int value) async {
    _weightsSampleSize = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyWeightsSampleSize, value);
    notifyListeners();
  }

  Future<void> setTraySize(int value) async {
    _traySize = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTraySize, value);
    notifyListeners();
  }

  Future<void> setStorageDays(int value) async {
    _storageDays = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyStorageDays, value);
    notifyListeners();
  }

  Future<void> updateLastSync(String timestamp) async {
    _lastSyncTimestamp = timestamp;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSyncTimestamp, timestamp);
    notifyListeners();
  }
}
