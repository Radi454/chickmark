import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/realtime/realtime_background_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(
      PlatformRealtimeBackgroundService.channel,
      null,
    );
  });

  test(
    'forwards Android activation and deactivation over its channel',
    () async {
      final nativeCalls = <String>[];
      messenger.setMockMethodCallHandler(
        PlatformRealtimeBackgroundService.channel,
        (call) async {
          nativeCalls.add(call.method);
          return null;
        },
      );
      final service = PlatformRealtimeBackgroundService();

      await service.activate();
      expect(nativeCalls, <String>['activate']);

      await service.deactivate();
      expect(nativeCalls, <String>['activate', 'deactivate']);
      service.dispose();
    },
  );

  test('emits one end request forwarded by native', () async {
    final service = PlatformRealtimeBackgroundService();
    final requests = <void>[];
    final subscription = service.endRequests.listen(requests.add);

    await messenger.handlePlatformMessage(
      'com.chickmark/realtime_background',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('requestEnd'),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(requests, hasLength(1));
    await subscription.cancel();
    service.dispose();
  });

  test('is a safe no-op outside Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final service = PlatformRealtimeBackgroundService();

    await service.activate();
    await service.deactivate();

    service.dispose();
  });
}
