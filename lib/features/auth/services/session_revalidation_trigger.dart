import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../../core/security/safe_debug_log.dart';

/// A connectivity event is worth acting on only when some interface is up.
bool shouldRevalidateOnConnectivity(List<ConnectivityResult> results) {
  if (results.isEmpty) return false;
  return results.any((result) => result != ConnectivityResult.none);
}

/// Fires a silent session re-validation when the app resumes or the network
/// comes back. Never shows UI and never blocks anything.
class SessionRevalidationTrigger with WidgetsBindingObserver {
  final Future<void> Function() _onRevalidate;
  final Stream<List<ConnectivityResult>> _connectivityStream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _started = false;

  SessionRevalidationTrigger({
    required Future<void> Function() onRevalidate,
    Stream<List<ConnectivityResult>>? connectivityStream,
  }) : _onRevalidate = onRevalidate,
       _connectivityStream =
           connectivityStream ?? Connectivity().onConnectivityChanged;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _subscription = _connectivityStream.listen((results) {
      if (shouldRevalidateOnConnectivity(results)) {
        _fire();
      }
    }, onError: (Object error) {
      safeDebugLog('Connectivity stream error', error: error);
    });
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
