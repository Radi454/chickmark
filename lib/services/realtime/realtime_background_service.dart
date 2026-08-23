import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps a user-started Android voice call eligible to continue while the app
/// is backgrounded. It never owns call media, credentials, or session state.
abstract interface class RealtimeBackgroundPort {
  Stream<void> get endRequests;
  Future<void> activate();
  Future<void> deactivate();
  void dispose();
}

class PlatformRealtimeBackgroundService implements RealtimeBackgroundPort {
  PlatformRealtimeBackgroundService()
    : _usesAndroidChannel =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android {
    if (_usesAndroidChannel) {
      channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  static const MethodChannel channel = MethodChannel(
    'com.chickmark/realtime_background',
  );

  final StreamController<void> _endRequests =
      StreamController<void>.broadcast();
  final bool _usesAndroidChannel;
  bool _disposed = false;

  @override
  Stream<void> get endRequests => _endRequests.stream;

  @override
  Future<void> activate() => _invokeForAndroid('activate');

  @override
  Future<void> deactivate() => _invokeForAndroid('deactivate');

  Future<void> _invokeForAndroid(String method) async {
    if (!_usesAndroidChannel) return;
    await channel.invokeMethod<void>(method);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'requestEnd' && !_disposed && !_endRequests.isClosed) {
      _endRequests.add(null);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_usesAndroidChannel) {
      channel.setMethodCallHandler(null);
    }
    _endRequests.close();
  }
}
