import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/config/feature_flags.dart';
import 'package:hatchaudit/core/network/network_status_monitor.dart';
import 'package:hatchaudit/features/chat/providers/assistant_provider.dart';
import 'package:hatchaudit/features/chat/providers/realtime_voice_controller.dart';
import 'package:hatchaudit/features/chat/screens/assistant_chat_screen.dart';
import 'package:hatchaudit/features/chat/screens/realtime_voice_screen.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';
import 'package:hatchaudit/services/realtime/realtime_background_service.dart';
import 'package:hatchaudit/services/supabase/assistant_chat_service.dart'
    show defaultConversationKey;
import 'package:provider/provider.dart';

import 'fake_assistant_chat_port.dart';
import 'fake_realtime.dart';

// Same discipline as assistant_chat_screen_test.dart: no sqflite, everything
// injected, bounded pump() only — never pumpAndSettle().

const _micKey = ValueKey('assistant-mic');
const _liveKey = ValueKey('assistant-live');
const _inputKey = ValueKey('assistant-input');

/// The default [RealtimeVoiceController] background port talks to a native
/// platform channel; `flutter test` runs with an Android target platform by
/// default (see `realtime_voice_screen_test.dart`), which sends setup into a
/// call this test host never answers. Every test here injects this instead,
/// exactly as `realtime_voice_screen_test.dart` does.
class _FakeBackgroundPort implements RealtimeBackgroundPort {
  final StreamController<void> _endRequests =
      StreamController<void>.broadcast();

  @override
  Stream<void> get endRequests => _endRequests.stream;

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}

  @override
  void dispose() {
    _endRequests.close();
  }
}

NetworkStatusMonitor _monitor(bool offline) => NetworkStatusMonitor(
  checkReachability: () async => !offline,
  connectivityStream: const Stream.empty(),
  initialStatus: offline ? NetworkStatus.offline : NetworkStatus.online,
  startImmediately: false,
);

void main() {
  late FakeRealtimeSessionPort sessionPort;
  late FakeRealtimeSignaling signaling;
  late List<FakeRealtimeTransport> transports;
  late List<FakeRealtimeSideband> sidebands;

  RealtimeVoiceController buildController() => RealtimeVoiceController(
    sessionPort: sessionPort,
    signaling: signaling,
    transportFactory: () {
      final transport = FakeRealtimeTransport();
      transports.add(transport);
      return transport;
    },
    sidebandFactory: () {
      final sideband = FakeRealtimeSideband();
      sidebands.add(sideband);
      return sideband;
    },
    backgroundPort: _FakeBackgroundPort(),
  );

  Future<AssistantProvider> pumpScreen(
    WidgetTester tester, {
    RealtimeVoiceController? realtime,
    bool offline = false,
    FakeAssistantChatPort? chatPort,
    String conversationKey = defaultConversationKey,
    void Function(String conversationKey)? onOpenLive,
  }) async {
    final provider = AssistantProvider(
      port: chatPort ?? FakeAssistantChatPort(),
      conversationKey: conversationKey,
    );
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ChangeNotifierProvider<NetworkStatusMonitor>.value(
          value: _monitor(offline),
          child: AssistantChatScreen(
            provider: provider,
            realtimeController: realtime,
            loadOnInit: false,
            conversationKey: conversationKey,
            onOpenLive: onOpenLive,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return provider;
  }

  setUp(() {
    // Pip Live is parked behind FeatureFlags.realtimeEnabled by default —
    // this suite exercises the (still fully intact) Realtime UI directly, so
    // it opts back in explicitly rather than relying on the default.
    FeatureFlags.realtimeEnabled = true;
    sessionPort = FakeRealtimeSessionPort();
    signaling = FakeRealtimeSignaling();
    transports = <FakeRealtimeTransport>[];
    sidebands = <FakeRealtimeSideband>[];
  });

  tearDown(() {
    FeatureFlags.resetForTest();
  });

  testWidgets('no live control when no controller is registered', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.byKey(_liveKey), findsNothing);
    expect(find.byKey(_micKey), findsOneWidget);
  });

  testWidgets('the live control is separate from the recorded-voice mic', (
    tester,
  ) async {
    final controller = buildController();
    await pumpScreen(tester, realtime: controller);

    expect(find.byKey(_liveKey), findsOneWidget);
    expect(find.byKey(_micKey), findsOneWidget);
    controller.dispose();
  });

  testWidgets(
    'when the shell supplies onOpenLive, tapping live hands it this '
    'screen\'s conversationKey instead of pushing a route directly',
    (tester) async {
      final controller = buildController();
      String? openedKey;
      await pumpScreen(
        tester,
        realtime: controller,
        conversationKey: 'app:11111111-1111-4111-8111-111111111111',
        onOpenLive: (key) => openedKey = key,
      );

      await tester.tap(find.byKey(_liveKey));
      await tester.pump();

      expect(openedKey, 'app:11111111-1111-4111-8111-111111111111');
      expect(find.byType(RealtimeVoiceScreen), findsNothing);
      controller.dispose();
    },
  );

  testWidgets('tapping live opens the dedicated call screen', (tester) async {
    final controller = buildController();
    await pumpScreen(tester, realtime: controller);

    await tester.tap(find.byKey(_liveKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(RealtimeVoiceScreen), findsOneWidget);
    expect(controller.isRealtimeActive, isTrue);
    controller.dispose();
  });

  testWidgets('a live call disables the recorded mic and the composer', (
    tester,
  ) async {
    final controller = buildController();
    await pumpScreen(tester, realtime: controller);

    await tester.tap(find.byKey(_liveKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const ValueKey('pip-live-minimize')));
    await tester.pump(const Duration(milliseconds: 350));

    final mic = tester.widget<IconButton>(find.byKey(_micKey));
    final input = tester.widget<TextField>(find.byKey(_inputKey));
    expect(
      mic.onPressed,
      isNull,
      reason: 'recorded voice must not contend with the live audio session',
    );
    expect(input.enabled, isFalse);
    controller.dispose();
  });

  testWidgets('tapping active Live reopens the call without ending it', (
    tester,
  ) async {
    final controller = buildController();
    await pumpScreen(tester, realtime: controller);
    await tester.tap(find.byKey(_liveKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    await tester.tap(find.byKey(const ValueKey('pip-live-minimize')));
    await tester.pump();

    await tester.tap(find.byKey(_liveKey));
    await tester.pump();

    expect(find.byType(RealtimeVoiceScreen), findsOneWidget);
    expect(controller.isRealtimeActive, isTrue);
    expect(transports.single.disposed, isFalse);
    expect(sidebands.single.closed, isFalse);
    controller.dispose();
  });

  testWidgets(
    'starting Live never touches the recorded-voice port',
    (tester) async {
      final controller = buildController();
      final chatPort = FakeAssistantChatPort();
      await pumpScreen(tester, realtime: controller, chatPort: chatPort);

      await tester.tap(find.byKey(_liveKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      sidebands.single.emitReady(sessionId: 'session-1');
      await tester.pump();
      await tester.pump();

      expect(
        chatPort.sentAudio,
        isEmpty,
        reason:
            'a live call and the legacy recorded-voice path must never both '
            'send audio for the same session',
      );
      expect(controller.isTransmitting, isTrue);
      controller.dispose();
    },
  );

  testWidgets('the live control is unavailable while offline', (tester) async {
    final controller = buildController();
    await pumpScreen(tester, realtime: controller, offline: true);

    expect(tester.widget<IconButton>(find.byKey(_liveKey)).onPressed, isNull);
    controller.dispose();
  });

  testWidgets(
    'when a call bound to this conversation ends, its transcript is '
    'reloaded exactly once',
    (tester) async {
      final controller = buildController();
      final chatPort = FakeAssistantChatPort();
      const key = 'app:22222222-2222-4222-8222-222222222222';
      await pumpScreen(
        tester,
        realtime: controller,
        chatPort: chatPort,
        conversationKey: key,
      );
      expect(chatPort.historyCount, 0);

      // The call need not have been opened from this screen — the shell
      // could have started it — only that the controller was bound to this
      // screen's conversation while it was up.
      await controller.start(conversationKey: key);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      sidebands.single.emitReady(sessionId: 'session-1');
      await tester.pump();
      await tester.pump();

      await controller.stop();
      await tester.pump();
      await tester.pump();

      expect(chatPort.historyCount, 1);
      expect(chatPort.historyConversationKeys, [key]);
      controller.dispose();
    },
  );

  testWidgets(
    'a call bound to a different conversation ending does not reload this '
    'screen',
    (tester) async {
      final controller = buildController();
      final chatPort = FakeAssistantChatPort();
      const thisKey = 'app:33333333-3333-4333-8333-333333333333';
      const otherKey = 'app:44444444-4444-4444-8444-444444444444';
      await pumpScreen(
        tester,
        realtime: controller,
        chatPort: chatPort,
        conversationKey: thisKey,
      );

      await controller.start(conversationKey: otherKey);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      sidebands.single.emitReady(sessionId: 'session-1');
      await tester.pump();

      await controller.stop();
      await tester.pump();
      await tester.pump();

      expect(chatPort.historyCount, 0);
      controller.dispose();
    },
  );

  testWidgets('leaving the screen mid-setup never enables transmission', (
    tester,
  ) async {
    final controller = buildController();
    await pumpScreen(tester, realtime: controller);
    await tester.tap(find.byKey(_liveKey));
    await tester.pump();

    // Navigate away by replacing the whole tree, then dispose the controller
    // exactly as the shell would.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    controller.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(transports.every((t) => t.startTransmittingCount == 0), isTrue);
    expect(transports.every((t) => t.disposed), isTrue);
  });

  testWidgets(
    'the live error banner only shows for the conversation the failed call '
    "belongs to, and Retry rebinds to this screen's conversation (F5)",
    (tester) async {
      sessionPort.createSessionError = Exception('unavailable');
      final controller = buildController();
      const keyA = 'app:11111111-1111-4111-8111-111111111111';
      const keyB = 'app:22222222-2222-4222-8222-222222222222';

      // A call bound to conversation A fails.
      await controller.start(conversationKey: keyA);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(controller.state, RealtimeVoiceState.error);
      expect(controller.activeConversationKey, keyA);

      // Viewing a different conversation (B) must never show this failed
      // call's banner — its Retry would otherwise restart the call bound to
      // the wrong thread.
      await pumpScreen(tester, realtime: controller, conversationKey: keyB);
      expect(
        find.byKey(const ValueKey('assistant-live-error')),
        findsNothing,
      );

      // Viewing the conversation the call actually belongs to (A) shows it,
      // and tapping Retry rebinds to A.
      await pumpScreen(tester, realtime: controller, conversationKey: keyA);
      expect(
        find.byKey(const ValueKey('assistant-live-error')),
        findsOneWidget,
      );

      sessionPort.createSessionError = null;
      await tester.tap(find.byKey(const ValueKey('assistant-error-retry')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(sessionPort.requestedConversationKeys.last, keyA);
      controller.dispose();
    },
  );

  testWidgets(
    'the clear action is disabled only while a live call bound to THIS '
    'conversation is up (F7)',
    (tester) async {
      final controller = buildController();
      const keyA = 'app:33333333-3333-4333-8333-333333333333';
      const keyB = 'app:44444444-4444-4444-8444-444444444444';

      // A live call for conversation B is up and ready.
      await controller.start(conversationKey: keyB);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      sidebands.single.emitReady(sessionId: 'session-1');
      await tester.pump();
      await tester.pump();
      expect(controller.isRealtimeActive, isTrue);
      expect(controller.activeConversationKey, keyB);

      // Viewing a different conversation (A, with turns of its own): the
      // call belongs elsewhere, so clear stays enabled.
      final providerA = await pumpScreen(
        tester,
        realtime: controller,
        chatPort: FakeAssistantChatPort(history: twoTurnHistory()),
        conversationKey: keyA,
      );
      await providerA.load();
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('assistant-clear-action')),
            )
            .onPressed,
        isNotNull,
      );

      // Viewing the conversation the live call actually belongs to (B):
      // clear must be disabled — clearing bumps context_epoch server-side,
      // which would orphan the rest of this call's transcript.
      final providerB = await pumpScreen(
        tester,
        realtime: controller,
        chatPort: FakeAssistantChatPort(history: twoTurnHistory()),
        conversationKey: keyB,
      );
      await providerB.load();
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('assistant-clear-action')),
            )
            .onPressed,
        isNull,
      );
      controller.dispose();
    },
  );
}
