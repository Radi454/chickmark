import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/chat/providers/realtime_voice_controller.dart';
import 'package:hatchaudit/features/chat/screens/realtime_voice_screen.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';
import 'package:hatchaudit/services/realtime/realtime_background_service.dart';
import 'package:hatchaudit/services/realtime/realtime_transport.dart';
import 'package:hatchaudit/services/supabase/assistant_chat_service.dart'
    show defaultConversationKey;
import 'package:provider/provider.dart';

import 'fake_realtime.dart';

class _FakeBackgroundPort implements RealtimeBackgroundPort {
  final StreamController<void> _endRequests =
      StreamController<void>.broadcast();

  @override
  Stream<void> get endRequests => _endRequests.stream;

  @override
  Future<bool> activate() async => true;

  @override
  Future<void> deactivate() async {}

  @override
  void dispose() {
    _endRequests.close();
  }
}

void main() {
  late FakeRealtimeSessionPort session;
  late FakeRealtimeSignaling signaling;
  late List<FakeRealtimeTransport> transports;
  late List<FakeRealtimeSideband> sidebands;

  RealtimeVoiceController buildController() => RealtimeVoiceController(
    sessionPort: session,
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

  Future<void> pumpLive(
    WidgetTester tester,
    RealtimeVoiceController controller, {
    bool autoStart = false,
    Locale locale = const Locale('en'),
    String conversationKey = defaultConversationKey,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: RealtimeVoiceScreen(
            autoStart: autoStart,
            conversationKey: conversationKey,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> ready(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    sidebands.single.emitReady(sessionId: 'session-1');
    await tester.pump();
    await tester.pump();
  }

  setUp(() {
    session = FakeRealtimeSessionPort();
    signaling = FakeRealtimeSignaling();
    transports = <FakeRealtimeTransport>[];
    sidebands = <FakeRealtimeSideband>[];
  });

  testWidgets('autoStart opens one call and shows connecting before READY', (
    tester,
  ) async {
    final controller = buildController();
    await pumpLive(tester, controller, autoStart: true);

    expect(find.byKey(const ValueKey('pip-live-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('pip-live-orb')), findsOneWidget);
    expect(find.text('Connecting securely'), findsOneWidget);
    expect(
      session.calls.where((call) => call == 'createSession'),
      hasLength(1),
    );
    controller.dispose();
  });

  testWidgets(
    'READY shows listening and transcript deltas replace unfinished rows',
    (tester) async {
      final controller = buildController();
      await pumpLive(tester, controller, autoStart: true);
      await ready(tester);
      transports.single.eventController.add({
        'type': 'conversation.item.input_audio_transcription.delta',
        'delta': 'First',
      });
      await tester.pump();
      expect(find.text('First'), findsOneWidget);
      // Terminal frames carry the FULL transcript, which replaces the
      // streamed line rather than extending it.
      transports.single.eventController.add({
        'type': 'conversation.item.input_audio_transcription.completed',
        'transcript': 'First caption',
      });
      transports.single.eventController.add({
        'type': 'response.audio_transcript.delta',
        'delta': 'Reply',
      });
      transports.single.eventController.add({
        'type': 'response.audio_transcript.done',
        'transcript': 'Reply complete',
      });
      await tester.pump();

      expect(find.text('Listening'), findsOneWidget);
      expect(find.byKey(const ValueKey('pip-live-transcript')), findsOneWidget);
      expect(find.text('First caption'), findsOneWidget);
      expect(find.text('First'), findsNothing);
      expect(find.text('Reply complete'), findsOneWidget);
      controller.dispose();
    },
  );

  testWidgets('Arabic captions use right-to-left direction', (tester) async {
    final controller = buildController();
    await pumpLive(tester, controller, autoStart: true);
    await ready(tester);
    transports.single.eventController.add({
      'type': 'response.audio_transcript.done',
      'transcript': 'مرحبا بك',
    });
    await tester.pump();

    expect(
      tester.widget<Text>(find.text('مرحبا بك')).textDirection,
      TextDirection.rtl,
    );
    controller.dispose();
  });

  testWidgets('mute toggles the controller and semantics label', (
    tester,
  ) async {
    final controller = buildController();
    await pumpLive(tester, controller, autoStart: true);
    await ready(tester);
    await tester.tap(find.byKey(const ValueKey('pip-live-mute')));
    await tester.pump();

    expect(controller.isMuted, isTrue);
    expect(find.bySemanticsLabel('Unmute'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('minimize pops without stopping', (tester) async {
    final controller = buildController();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RealtimeVoiceScreen(autoStart: true),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const ValueKey('pip-live-minimize')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.isRealtimeActive, isTrue);
    controller.dispose();
  });

  testWidgets('End stops the active call', (tester) async {
    final controller = buildController();
    await pumpLive(tester, controller, autoStart: true);
    await ready(tester);
    await tester.tap(find.byKey(const ValueKey('pip-live-end')));
    for (var i = 0; i < 4; i++) await tester.pump();
    expect(controller.state, RealtimeVoiceState.idle);
    controller.dispose();
  });

  testWidgets('error and reconnecting show localized status with retry', (
    tester,
  ) async {
    session.createSessionError = Exception('unavailable');
    final controller = buildController();
    await pumpLive(
      tester,
      controller,
      autoStart: true,
      locale: const Locale('ar'),
    );
    for (var i = 0; i < 5; i++) await tester.pump();

    expect(find.byKey(const ValueKey('pip-live-retry')), findsOneWidget);
    expect(
      find.text(
        AppLocalizations(
          const Locale('ar'),
        ).translate('Live voice is unavailable right now. Please try again.'),
      ),
      findsOneWidget,
    );
    controller.dispose();
  });

  testWidgets(
    'reconnecting state exposes retry that stops recovery then starts fresh',
    (tester) async {
      final controller = buildController();
      await pumpLive(tester, controller, autoStart: true);
      await ready(tester);
      signaling.gate = Completer<void>();
      transports.single.connectionController.add(
        RealtimeConnectionState.failed,
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(controller.state, RealtimeVoiceState.reconnectingMuted);
      expect(find.byKey(const ValueKey('pip-live-retry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pip-live-retry')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(
        session.calls.where((call) => call == 'createSession'),
        hasLength(3),
      );
      expect(controller.state, isNot(RealtimeVoiceState.reconnectingMuted));
      signaling.gate!.complete();
      controller.dispose();
    },
  );

  testWidgets(
    'the collapsed strip shows only the latest user and assistant turn',
    (tester) async {
      final controller = buildController();
      await pumpLive(tester, controller, autoStart: true);
      await ready(tester);

      transports.single.eventController.add({
        'type': 'conversation.item.input_audio_transcription.completed',
        'transcript': 'What was the first hatch?',
      });
      transports.single.eventController.add({
        'type': 'response.audio_transcript.done',
        'transcript': '84 percent.',
      });
      transports.single.eventController.add({
        'type': 'conversation.item.input_audio_transcription.completed',
        'transcript': 'And the second one?',
      });
      transports.single.eventController.add({
        'type': 'response.audio_transcript.done',
        'transcript': '81 percent.',
      });
      await tester.pump();

      expect(find.byKey(const ValueKey('pip-live-transcript')), findsOneWidget);
      // Only the latest turn of each speaker is visible while collapsed.
      expect(find.text('And the second one?'), findsOneWidget);
      expect(find.text('81 percent.'), findsOneWidget);
      expect(find.text('What was the first hatch?'), findsNothing);
      expect(find.text('84 percent.'), findsNothing);
      controller.dispose();
    },
  );

  testWidgets(
    'tapping the strip expands it to the full caption history',
    (tester) async {
      final controller = buildController();
      await pumpLive(tester, controller, autoStart: true);
      await ready(tester);

      transports.single.eventController.add({
        'type': 'conversation.item.input_audio_transcription.completed',
        'transcript': 'What was the first hatch?',
      });
      transports.single.eventController.add({
        'type': 'response.audio_transcript.done',
        'transcript': '84 percent.',
      });
      transports.single.eventController.add({
        'type': 'conversation.item.input_audio_transcription.completed',
        'transcript': 'And the second one?',
      });
      transports.single.eventController.add({
        'type': 'response.audio_transcript.done',
        'transcript': '81 percent.',
      });
      await tester.pump();
      expect(find.text('What was the first hatch?'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('pip-live-transcript')));
      await tester.pump();

      expect(find.text('What was the first hatch?'), findsOneWidget);
      expect(find.text('84 percent.'), findsOneWidget);
      expect(find.text('And the second one?'), findsOneWidget);
      expect(find.text('81 percent.'), findsOneWidget);

      // The dedicated toggle collapses it back.
      await tester.tap(find.byKey(const ValueKey('pip-live-transcript-toggle')));
      await tester.pump();
      expect(find.text('What was the first hatch?'), findsNothing);
      controller.dispose();
    },
  );

  testWidgets('an empty transcript keeps the strip and toggle hidden', (
    tester,
  ) async {
    final controller = buildController();
    await pumpLive(tester, controller, autoStart: true);
    await ready(tester);

    expect(find.byKey(const ValueKey('pip-live-transcript')), findsNothing);
    controller.dispose();
  });

  testWidgets('the end-call control shows no visible text label', (
    tester,
  ) async {
    final controller = buildController();
    await pumpLive(tester, controller, autoStart: true);
    await ready(tester);

    expect(find.byKey(const ValueKey('pip-live-end')), findsOneWidget);
    expect(find.text('End live conversation'), findsNothing);
    expect(
      find.bySemanticsLabel('End live conversation'),
      findsOneWidget,
    );
    controller.dispose();
  });

  testWidgets(
    'a per-conversation key is threaded through autoStart to controller.start',
    (tester) async {
      const key = 'app:11111111-1111-4111-8111-111111111111';
      final controller = buildController();
      await pumpLive(
        tester,
        controller,
        autoStart: true,
        conversationKey: key,
      );
      await tester.pump();

      expect(controller.activeConversationKey, key);
      expect(session.requestedConversationKeys, <String>[key]);
      controller.dispose();
    },
  );

  testWidgets(
    'the default conversationKey is used when the screen is opened without one',
    (tester) async {
      final controller = buildController();
      await pumpLive(tester, controller, autoStart: true);
      await tester.pump();

      expect(controller.activeConversationKey, defaultConversationKey);
      expect(session.requestedConversationKeys, <String>[defaultConversationKey]);
      controller.dispose();
    },
  );

  testWidgets(
    "retry uses the controller's own active conversation key, not the "
    "screen's possibly-stale conversationKey (F6)",
    (tester) async {
      session.createSessionError = Exception('unavailable');
      final controller = buildController();
      const activeKey = 'app:11111111-1111-4111-8111-111111111111';

      // The call is bound to `activeKey` directly (as if opened from that
      // conversation's chat screen) and fails.
      await controller.start(conversationKey: activeKey);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(controller.state, RealtimeVoiceState.error);
      expect(controller.activeConversationKey, activeKey);

      // The screen is (re)opened with a *different* conversationKey — the
      // shell overwriting `_liveConversationKey` to the default while the
      // call was up is exactly the bug this guards against.
      await pumpLive(
        tester,
        controller,
        autoStart: false,
        conversationKey: defaultConversationKey,
      );
      session.createSessionError = null;

      await tester.tap(find.byKey(const ValueKey('pip-live-retry')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(
        session.requestedConversationKeys.last,
        activeKey,
        reason:
            "retry must rebind to the call's own conversation, never the "
            "screen's conversationKey when it disagrees",
      );
      controller.dispose();
    },
  );

  testWidgets(
    'autoStart also prefers the active key over a differing screen '
    'conversationKey when one is still set from a prior failed call (F6)',
    (tester) async {
      session.createSessionError = Exception('unavailable');
      final controller = buildController();
      const activeKey = 'app:22222222-2222-4222-8222-222222222222';

      // A call bound to `activeKey` fails; `activeConversationKey` survives
      // the error state (see its own doc in the controller).
      await controller.start(conversationKey: activeKey);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(controller.state, RealtimeVoiceState.error);
      expect(controller.activeConversationKey, activeKey);

      session.createSessionError = null;
      session.requestedConversationKeys.clear();

      // A fresh mount with autoStart:true and a *different* conversationKey
      // (e.g. main_shell's default) — the effective-key computation must
      // still prefer the controller's own active key.
      await pumpLive(
        tester,
        controller,
        autoStart: true,
        conversationKey: defaultConversationKey,
      );
      await tester.pump();

      expect(session.requestedConversationKeys, <String>[activeKey]);
      controller.dispose();
    },
  );
}
