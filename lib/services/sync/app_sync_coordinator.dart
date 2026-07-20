import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../core/security/safe_debug_log.dart';

typedef AppSyncCallback = Future<void> Function();

/// Coalesces local-write, reconnect, and app-resume sync requests into a single
/// foreground-safe sync pass.
///
/// Repositories can call [nudge] without depending on authentication or UI
/// providers. [MainShell] owns the callback and enables the coordinator only
/// while an authenticated workspace is mounted.
class AppSyncCoordinator {
  AppSyncCoordinator._({
    required AppSyncCallback sync,
    required Duration debounce,
    required bool listenForConnectivity,
  }) : _sync = sync,
       _debounce = debounce {
    if (listenForConnectivity) {
      try {
        _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
          (_) => _schedule(),
        );
      } catch (error) {
        safeDebugLog(
          'Automatic sync connectivity listener unavailable',
          error: error,
        );
      }
    }
  }

  final AppSyncCallback _sync;
  final Duration _debounce;

  static AppSyncCoordinator? _instance;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _timer;
  bool _running = false;
  bool _pendingAgain = false;
  bool _disposed = false;

  static void enable({
    required AppSyncCallback sync,
    Duration debounce = const Duration(seconds: 2),
    bool listenForConnectivity = true,
  }) {
    disable();
    _instance = AppSyncCoordinator._(
      sync: sync,
      debounce: debounce,
      listenForConnectivity: listenForConnectivity,
    );
  }

  static void disable() {
    _instance?._dispose();
    _instance = null;
  }

  /// Request a sync after the current local write burst settles.
  ///
  /// Calls are safe before [enable] and are coalesced while a sync is running.
  static void nudge({bool immediate = false}) {
    _instance?._schedule(immediate ? Duration.zero : null);
  }

  @visibleForTesting
  static bool get isEnabled => _instance != null;

  void _schedule([Duration? delay]) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(delay ?? _debounce, () {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_disposed) return;
    if (_running) {
      _pendingAgain = true;
      return;
    }

    _running = true;
    try {
      await _sync();
    } catch (error) {
      // The sync service records the visible failure state. Keep this
      // coordinator best-effort so local writes are never rolled back.
      safeDebugLog('Automatic sync pass failed', error: error);
    } finally {
      _running = false;
      if (!_disposed && _pendingAgain) {
        _pendingAgain = false;
        _schedule();
      }
    }
  }

  void _dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;
  }
}
