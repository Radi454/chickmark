import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/network/network_status_monitor.dart';
import '../../../core/security/safe_debug_log.dart';

/// Fires a silent session re-validation when the app resumes or the network
/// comes back. Never shows UI and never blocks anything.
class SessionRevalidationTrigger with WidgetsBindingObserver {
  final Future<void> Function() _onRevalidate;
  final NetworkStatusMonitor _networkStatus;

  bool _started = false;
  NetworkStatus _lastNetworkStatus;

  SessionRevalidationTrigger({
    required Future<void> Function() onRevalidate,
    required NetworkStatusMonitor networkStatus,
  }) : _onRevalidate = onRevalidate,
       _networkStatus = networkStatus,
       _lastNetworkStatus = networkStatus.status;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _lastNetworkStatus = _networkStatus.status;
    _networkStatus.addListener(_handleNetworkStatusChanged);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _networkStatus.removeListener(_handleNetworkStatusChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAfterResume());
    }
  }

  Future<void> _refreshAfterResume() async {
    final before = _networkStatus.status;
    final after = await _networkStatus.refresh();
    if (!_started) return;
    // An offline/unknown -> online transition is handled by the listener.
    // When the monitor was already online, resume still gets one silent
    // revalidation without creating a duplicate call.
    if (before == NetworkStatus.online && after == NetworkStatus.online) {
      _fire();
    }
  }

  void _handleNetworkStatusChanged() {
    if (!_started) return;
    final current = _networkStatus.status;
    final previous = _lastNetworkStatus;
    _lastNetworkStatus = current;
    if (current == NetworkStatus.online && previous != NetworkStatus.online) {
      _fire();
    }
  }

  void _fire() {
    unawaited(
      _onRevalidate().catchError((Object error) {
        safeDebugLog('Session revalidation failed', error: error);
      }),
    );
  }
}
