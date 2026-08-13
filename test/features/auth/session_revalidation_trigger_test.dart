import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/features/auth/services/session_revalidation_trigger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an interface coming up triggers revalidation', () {
    expect(
      shouldRevalidateOnConnectivity([ConnectivityResult.wifi]),
      isTrue,
    );
    expect(
      shouldRevalidateOnConnectivity([ConnectivityResult.mobile]),
      isTrue,
    );
  });

  test('losing all connectivity does not trigger revalidation', () {
    expect(shouldRevalidateOnConnectivity([ConnectivityResult.none]), isFalse);
    expect(shouldRevalidateOnConnectivity([]), isFalse);
  });

  test('connectivity events fire the callback', () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var calls = 0;
    final trigger = SessionRevalidationTrigger(
      onRevalidate: () async => calls++,
      connectivityStream: controller.stream,
    );
    trigger.start();

    controller.add([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);

    controller.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    trigger.stop();
    controller.add([ConnectivityResult.mobile]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    await controller.close();
  });

  test('app resume fires the callback, other lifecycle states do not', () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var calls = 0;
    final trigger = SessionRevalidationTrigger(
      onRevalidate: () async => calls++,
      connectivityStream: controller.stream,
    );
    trigger.start();

    trigger.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);

    trigger.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    trigger.stop();
    await controller.close();
  });

  test('a callback that throws does not break later triggers', () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var calls = 0;
    final trigger = SessionRevalidationTrigger(
      onRevalidate: () async {
        calls++;
        throw StateError('boom');
      },
      connectivityStream: controller.stream,
    );
    trigger.start();

    controller.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    controller.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);

    expect(calls, 2);

    trigger.stop();
    await controller.close();
  });
}
