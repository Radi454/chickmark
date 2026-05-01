import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/notifications/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'requestPermissions' => true,
            'show' => null,
            _ => null,
          };
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    NotificationService.resetForTest();
  });

  test('initializes and shows notifications with macOS settings', () async {
    await NotificationService.init();
    await NotificationService.showAlert(title: 'Alert', body: 'Body');

    final initializeCall = calls.firstWhere(
      (call) => call.method == 'initialize',
    );
    final initializeArgs = Map<String, Object?>.from(
      initializeCall.arguments as Map,
    );
    expect(initializeArgs['defaultPresentAlert'], isTrue);
    expect(initializeArgs['defaultPresentSound'], isTrue);
    expect(initializeArgs['defaultPresentBadge'], isTrue);
    expect(initializeArgs['defaultPresentBanner'], isTrue);
    expect(initializeArgs['defaultPresentList'], isTrue);

    final showCall = calls.firstWhere((call) => call.method == 'show');
    final showArgs = Map<String, Object?>.from(showCall.arguments as Map);
    expect(showArgs['platformSpecifics'], isA<Map>());
  });
}
