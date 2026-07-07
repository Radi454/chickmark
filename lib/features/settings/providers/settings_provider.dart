import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/network_reachability.dart';
import '../../../data/models/incoming_change.dart';

/// Cloud connectivity / sync lifecycle. Drives the home-screen "Sync & Offline"
/// card and the offline banner. `online` = last sync OK and network reachable;
/// `offline` = no network or last sync returned offline; `syncing` = sync in
/// flight; `error` = last sync threw.
enum CloudStatus { online, offline, syncing, error }

class SettingsProvider extends ChangeNotifier {
  int _pasgarSampleSize = 40;
  int _weightsSampleSize = 100;
  int _traySize = 150;
  int _storageDays = 0;
  String _languageCode = 'en';
  String? _lastSyncTimestamp;
  bool _isSyncing = false;
  int _lastSyncPushed = 0;
  int _lastSyncPulled = 0;
  bool _lastSyncOnline = true;
  String? _lastSyncError;
  List<IncomingChange> _incomingChanges = const [];
  int _otherIncomingCount = 0;
  CloudStatus _cloudStatus = CloudStatus.online;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _disposed = false;

  static const String _keyPasgarSampleSize = 'pref_pasgar_sample_size';
  static const String _keyWeightsSampleSize = 'pref_weights_sample_size';
  static const String _keyTraySize = 'pref_tray_size';
  static const String _keyStorageDays = 'pref_storage_days';
  static const String _keyLanguageCode = 'pref_language_code';
  static const String _keyLastSyncTimestamp = 'last_sync_timestamp';
  static const String _keyLastSyncPushed = 'last_sync_pushed';
  static const String _keyLastSyncPulled = 'last_sync_pulled';
  static const String _keyLastSyncOnline = 'last_sync_online';
  static const String _keyIncomingChanges = 'incoming_changes_json';
  static const String _keyIncomingOther = 'incoming_other_count';

  /// Max itemized incoming sessions kept across runs (bounds prefs size).
  static const int _incomingCap = 50;

  int get pasgarSampleSize => _pasgarSampleSize;
  int get weightsSampleSize => _weightsSampleSize;
  int get traySize => _traySize;
  int get storageDays => _storageDays;
  String get languageCode => _languageCode;
  String? get lastSyncTimestamp => _lastSyncTimestamp;
  bool get isSyncing => _isSyncing;
  int get lastSyncPushed => _lastSyncPushed;
  int get lastSyncPulled => _lastSyncPulled;
  bool get lastSyncOnline => _lastSyncOnline;
  String? get lastSyncError => _lastSyncError;
  bool get hasSyncedBefore => _lastSyncTimestamp != null;
  CloudStatus get cloudStatus => _cloudStatus;
  bool get isOffline => _cloudStatus == CloudStatus.offline;

  /// Sessions synced from another device, not yet acknowledged.
  List<IncomingChange> get incomingChanges => _incomingChanges;

  /// Non-session cloud-origin records (panel rows / Govee) awaiting ack.
  int get otherIncomingCount => _otherIncomingCount;

  bool get hasIncomingChanges =>
      _incomingChanges.isNotEmpty || _otherIncomingCount > 0;

  SettingsProvider() {
    _load();
    _initConnectivity();
  }

  @override
  void dispose() {
    _disposed = true;
    _connectivitySub?.cancel();
    super.dispose();
  }

  void _safeNotifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  Future<void> _initConnectivity() async {
    await _refreshConnectivity();
    try {
      _connectivitySub = Connectivity().onConnectivityChanged.listen(
        (_) => _refreshConnectivity(),
      );
    } catch (_) {
      // connectivity_plus throws on unsupported platforms (tests). The initial
      // refresh already left cloudStatus at its default; skip live updates.
    }
  }

  Future<void> _refreshConnectivity() async {
    // connectivity_plus alone reports a false `none` on macOS until its
    // NWPathMonitor settles; NetworkReachability confirms with a real probe.
    final online = await NetworkReachability.isOnline();
    // Don't override an in-flight sync's status — let recordSync() finalize it.
    if (_cloudStatus == CloudStatus.syncing) return;
    final next = online ? CloudStatus.online : CloudStatus.offline;
    if (next == _cloudStatus) return;
    _cloudStatus = next;
    _safeNotifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _pasgarSampleSize = prefs.getInt(_keyPasgarSampleSize) ?? 40;
    _weightsSampleSize = prefs.getInt(_keyWeightsSampleSize) ?? 100;
    _traySize = prefs.getInt(_keyTraySize) ?? 150;
    _storageDays = prefs.getInt(_keyStorageDays) ?? 0;
    _languageCode = _normalizeLanguageCode(
      prefs.getString(_keyLanguageCode) ?? 'en',
    );
    _lastSyncTimestamp = prefs.getString(_keyLastSyncTimestamp);
    _lastSyncPushed = prefs.getInt(_keyLastSyncPushed) ?? 0;
    _lastSyncPulled = prefs.getInt(_keyLastSyncPulled) ?? 0;
    _lastSyncOnline = prefs.getBool(_keyLastSyncOnline) ?? true;
    _incomingChanges = IncomingChange.decodeList(
      prefs.getString(_keyIncomingChanges),
    );
    _otherIncomingCount = prefs.getInt(_keyIncomingOther) ?? 0;
    _safeNotifyListeners();
  }

  Future<void> setPasgarSampleSize(int value) async {
    _pasgarSampleSize = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPasgarSampleSize, value);
    _safeNotifyListeners();
  }

  Future<void> setWeightsSampleSize(int value) async {
    _weightsSampleSize = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyWeightsSampleSize, value);
    _safeNotifyListeners();
  }

  Future<void> setTraySize(int value) async {
    _traySize = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTraySize, value);
    _safeNotifyListeners();
  }

  Future<void> setStorageDays(int value) async {
    _storageDays = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyStorageDays, value);
    _safeNotifyListeners();
  }

  Future<void> setLanguageCode(String value) async {
    final normalized = _normalizeLanguageCode(value);
    if (_languageCode == normalized) return;
    _languageCode = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguageCode, normalized);
    _safeNotifyListeners();
  }

  String _normalizeLanguageCode(String value) {
    return value == 'ar' ? 'ar' : 'en';
  }

  Future<void> updateLastSync(String timestamp) async {
    _lastSyncTimestamp = timestamp;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSyncTimestamp, timestamp);
    _safeNotifyListeners();
  }

  /// Flag the start of a sync so the status sector can show a live spinner.
  void markSyncing() {
    _isSyncing = true;
    _lastSyncError = null;
    _cloudStatus = CloudStatus.syncing;
    _safeNotifyListeners();
  }

  /// Record the result of a sync run (clears the syncing flag and persists
  /// the last push/pull counts + connectivity for the status sector).
  Future<void> recordSync({
    required bool online,
    required int pushed,
    required int pulled,
    String? error,
    List<IncomingChange> incoming = const [],
    int otherIncoming = 0,
    bool acknowledgeIncoming = false,
  }) async {
    _isSyncing = false;
    _lastSyncOnline = online;
    _lastSyncPushed = pushed;
    _lastSyncPulled = pulled;
    _lastSyncError = error;
    // Capture into a local first — _load() may concurrently overwrite the
    // field with `prefs.getString(...)` (null in tests with an empty mock),
    // which used to NPE when we then passed `_lastSyncTimestamp!` to prefs.
    final timestamp = DateTime.now().toIso8601String();
    _lastSyncTimestamp = timestamp;
    if (error != null) {
      _cloudStatus = CloudStatus.error;
    } else if (online) {
      _cloudStatus = CloudStatus.online;
    } else {
      _cloudStatus = CloudStatus.offline;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLastSyncOnline, online);
    await prefs.setInt(_keyLastSyncPushed, pushed);
    await prefs.setInt(_keyLastSyncPulled, pulled);
    await prefs.setString(_keyLastSyncTimestamp, timestamp);
    final shouldAcknowledgeIncoming =
        acknowledgeIncoming && online && error == null;
    if (shouldAcknowledgeIncoming) {
      _incomingChanges = const [];
      _otherIncomingCount = 0;
      await prefs.remove(_keyIncomingChanges);
      await prefs.remove(_keyIncomingOther);
    }
    // Merge cloud-origin changes into the unacknowledged set (dedupe by key,
    // newest wins, capped). Merging an empty batch is a no-op, so an offline /
    // error sync never wipes a pending notice.
    if (!shouldAcknowledgeIncoming &&
        (incoming.isNotEmpty || otherIncoming > 0)) {
      final byKey = <String, IncomingChange>{
        for (final change in _incomingChanges) change.key: change,
      };
      for (final change in incoming) {
        byKey[change.key] = change;
      }
      var merged = byKey.values.toList();
      if (merged.length > _incomingCap) {
        merged = merged.sublist(merged.length - _incomingCap);
      }
      _incomingChanges = merged;
      _otherIncomingCount += otherIncoming;
      await prefs.setString(
        _keyIncomingChanges,
        IncomingChange.encodeList(_incomingChanges),
      );
      await prefs.setInt(_keyIncomingOther, _otherIncomingCount);
    }
    _safeNotifyListeners();
  }

  /// Acknowledge one synced-from-cloud session (e.g. the user opened it).
  /// Removes only that item; the rest of the notice stays.
  Future<void> acknowledgeIncomingChange(String key) async {
    if (!_incomingChanges.any((change) => change.key == key)) return;
    _incomingChanges = _incomingChanges
        .where((change) => change.key != key)
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyIncomingChanges,
      IncomingChange.encodeList(_incomingChanges),
    );
    _safeNotifyListeners();
  }

  /// "Dismiss all": clear every pending cloud-origin notice.
  Future<void> clearIncomingChanges() async {
    if (_incomingChanges.isEmpty && _otherIncomingCount == 0) return;
    _incomingChanges = const [];
    _otherIncomingCount = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIncomingChanges);
    await prefs.remove(_keyIncomingOther);
    _safeNotifyListeners();
  }
}
