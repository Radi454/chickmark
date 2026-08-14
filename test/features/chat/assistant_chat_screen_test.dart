import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/network/network_status_monitor.dart';
import 'package:hatchaudit/features/chat/providers/assistant_provider.dart';
import 'package:hatchaudit/features/chat/screens/assistant_chat_screen.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';
import 'package:hatchaudit/localized_material.dart' as localized;
import 'package:hatchaudit/services/audio/assistant_audio_player.dart';
import 'package:hatchaudit/services/audio/assistant_audio_recorder.dart';
import 'package:hatchaudit/services/supabase/assistant_chat_service.dart';
import 'package:provider/provider.dart';

import 'fake_assistant_audio.dart';
import 'fake_assistant_chat_port.dart';

// The screen never touches sqflite: it is driven entirely through an injected
// AssistantChatPort and an injected NetworkStatusMonitor, so nothing here can
// deadlock under FakeAsync. Where a spinner may be on screen we pump bounded
// frames rather than pumpAndSettle().

const _inputKey = ValueKey('assistant-input');
const _sendKey = ValueKey('assistant-send');
const _clearKey = ValueKey('assistant-clear-action');
const _errorBannerKey = ValueKey('assistant-error-banner');
const _thinkingKey = ValueKey('assistant-thinking');
const _micKey = ValueKey('assistant-mic');
const _headerAvatarKey = ValueKey('assistant-header-avatar');
const _emptyAvatarKey = ValueKey('assistant-empty-avatar');
const _emptyTitleKey = ValueKey('assistant-empty-title');
const _messageAvatarKey = ValueKey('assistant-message-avatar');
const _thinkingAvatarKey = ValueKey('assistant-thinking-avatar');

NetworkStatusMonitor _monitor(bool offline) => NetworkStatusMonitor(
  checkReachability: () async => !offline,
  connectivityStream: const Stream.empty(),
  initialStatus: offline ? NetworkStatus.offline : NetworkStatus.online,
  startImmediately: false,
);

Future<AssistantProvider> _pumpScreen(
  WidgetTester tester, {
  required FakeAssistantChatPort port,
  bool offline = false,
  bool loadOnInit = true,
  Locale locale = const Locale('en'),
  AssistantAudioRecorder? audioRecorder,
  AssistantAudioPlayer? audioPlayer,
}) async {
  var counter = 0;
  final provider = AssistantProvider(
    port: port,
    clientMessageIdFactory: () => 'cid-${++counter}',
    audioRecorder: audioRecorder,
    audioPlayer: audioPlayer,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ChangeNotifierProvider<NetworkStatusMonitor>.value(
        value: _monitor(offline),
        child: AssistantChatScreen(provider: provider, loadOnInit: loadOnInit),
      ),
    ),
  );
  // Bounded frames: enough for the post-frame load() and its microtask to
  // land, never pumpAndSettle() — a spinner would keep that pumping forever.
  await tester.pump();
  await tester.pump();
  return provider;
}

void main() {
  testWidgets('an empty conversation shows the suggestion empty state', (
    tester,
  ) async {
    await _pumpScreen(tester, port: FakeAssistantChatPort());

    expect(find.text('Pip'), findsOneWidget);
    expect(find.byKey(_emptyTitleKey), findsOneWidget);
    expect(
      tester.widget<localized.Text>(find.byKey(_emptyTitleKey)).data,
      'Ask Pip',
    );
    expect(find.byKey(_headerAvatarKey), findsOneWidget);
    expect(find.byKey(_emptyAvatarKey), findsOneWidget);
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
    expect(
      find.text(
        'Ask about flock performance, hatch results, or a recent audit.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(_errorBannerKey), findsNothing);
  });

  testWidgets('Arabic history mirrors assistant avatars and message bubbles', (
    tester,
  ) async {
    final port = FakeAssistantChatPort(history: twoTurnHistory());

    await _pumpScreen(tester, port: port, locale: const Locale('ar'));

    expect(port.historyCount, 1);
    expect(find.byKey(_emptyTitleKey), findsNothing);
    expect(find.text('ما نسبة الفقس؟'), findsWidgets);
    expect(find.text('Hatch was 84%.'), findsWidgets);
    expect(find.byKey(_messageAvatarKey), findsOneWidget);

    // Arabic reading-start is on the right: Pip's avatar and bubble occupy
    // that edge, while the user's bubble is aligned to reading-end.
    final userBubble = tester.getRect(find.text('ما نسبة الفقس؟').first);
    final assistantBubble = tester.getRect(find.text('Hatch was 84%.').first);
    final assistantAvatar = tester.getRect(find.byKey(_messageAvatarKey));
    expect(assistantAvatar.left, greaterThan(userBubble.right));
    expect(assistantAvatar.left, greaterThan(assistantBubble.right));
    expect(assistantBubble.right, greaterThan(userBubble.right));
  });

  testWidgets('typing and sending shows the assistant reply', (tester) async {
    final port = FakeAssistantChatPort();
    await _pumpScreen(tester, port: port);

    await tester.enterText(find.byKey(_inputKey), 'How did last hatch go?');
    await tester.pump();
    await tester.tap(find.byKey(_sendKey));
    await tester.pump();
    await tester.pump();

    expect(port.sentMessages, ['How did last hatch go?']);
    expect(port.sentClientMessageIds, ['cid-1']);
    expect(find.text('How did last hatch go?'), findsWidgets);
    expect(find.text('Hatch was 84%.'), findsWidgets);

    // The composer is emptied so the sent text is not re-sent by accident.
    final field = tester.widget<TextField>(find.byKey(_inputKey));
    expect(field.controller!.text, isEmpty);
    expect(field.decoration?.hintText, 'Ask Pip');
  });

  testWidgets('the thinking indicator shows only while a send is in flight', (
    tester,
  ) async {
    final port = FakeAssistantChatPort(manualSend: true);
    await _pumpScreen(tester, port: port);

    expect(find.byKey(_thinkingKey), findsNothing);
    expect(find.byKey(_thinkingAvatarKey), findsNothing);

    await tester.enterText(find.byKey(_inputKey), 'slow one');
    await tester.pump();
    await tester.tap(find.byKey(_sendKey));
    await tester.pump();

    expect(find.byKey(_thinkingKey), findsOneWidget);
    expect(find.text('Pip is thinking'), findsOneWidget);
    expect(find.byKey(_thinkingAvatarKey), findsOneWidget);
    expect(find.text('slow one'), findsWidgets);

    port.completeSend(reply('Done.'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(_thinkingKey), findsNothing);
    expect(find.byKey(_thinkingAvatarKey), findsNothing);
    expect(find.text('Done.'), findsWidgets);
  });

  testWidgets('a failed load shows the error banner and retry reloads', (
    tester,
  ) async {
    final port = FakeAssistantChatPort(
      historyError: const AssistantChatException(
        'The assistant is unavailable right now. Try again shortly.',
        'agent_unavailable',
      ),
    );
    await _pumpScreen(tester, port: port);

    expect(find.byKey(_errorBannerKey), findsOneWidget);
    expect(
      find.text('The assistant is unavailable right now. Try again shortly.'),
      findsOneWidget,
    );

    port.historyError = null;
    port.history = twoTurnHistory();
    await tester.tap(find.byKey(const ValueKey('assistant-error-retry')));
    await tester.pump();
    await tester.pump();

    expect(port.historyCount, 2);
    expect(find.byKey(_errorBannerKey), findsNothing);
    expect(find.text('Hatch was 84%.'), findsWidgets);
  });

  testWidgets('a failed send keeps the text and offers retry on the bubble', (
    tester,
  ) async {
    final port = FakeAssistantChatPort(
      sendError: const AssistantChatException('nope', 'server_error'),
    );
    await _pumpScreen(tester, port: port);

    await tester.enterText(find.byKey(_inputKey), 'keep me');
    await tester.pump();
    await tester.tap(find.byKey(_sendKey));
    await tester.pump();
    await tester.pump();

    expect(find.text('keep me'), findsWidgets);
    expect(find.text('Not sent'), findsOneWidget);
    expect(find.byKey(_errorBannerKey), findsOneWidget);

    port.sendError = null;
    port.nextReply = reply('Recovered.');
    await tester.tap(find.widgetWithText(TextButton, 'Retry').last);
    await tester.pump();
    await tester.pump();

    expect(port.sentClientMessageIds, ['cid-1', 'cid-1']);
    expect(find.text('Recovered.'), findsWidgets);
  });

  testWidgets('offline disables the composer and explains why', (tester) async {
    await _pumpScreen(
      tester,
      port: FakeAssistantChatPort(history: twoTurnHistory()),
      offline: true,
    );

    expect(
      find.text(
        'The assistant needs a connection. Your other work still saves offline.',
      ),
      findsOneWidget,
    );

    final field = tester.widget<TextField>(find.byKey(_inputKey));
    expect(field.enabled, isFalse);

    final send = tester.widget<IconButton>(find.byKey(_sendKey));
    expect(send.onPressed, isNull);
  });

  testWidgets('clearing asks for confirmation before resetting', (
    tester,
  ) async {
    final port = FakeAssistantChatPort(history: twoTurnHistory());
    await _pumpScreen(tester, port: port);

    // Cancel leaves the conversation alone.
    await tester.tap(find.byKey(_clearKey));
    await tester.pump();
    expect(find.text('Clear this conversation?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
    await tester.pump();
    expect(port.resetCount, 0);
    expect(find.text('Hatch was 84%.'), findsWidgets);

    // Confirming clears it.
    await tester.tap(find.byKey(_clearKey));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pump();
    await tester.pump();

    expect(port.resetCount, 1);
    expect(find.byKey(_emptyTitleKey), findsOneWidget);
  });

  testWidgets('the clear action is disabled while the conversation is empty', (
    tester,
  ) async {
    await _pumpScreen(tester, port: FakeAssistantChatPort());

    final action = tester.widget<IconButton>(find.byKey(_clearKey));
    expect(action.onPressed, isNull);
  });

  testWidgets('Arabic keeps Pip in Latin script', (tester) async {
    await _pumpScreen(
      tester,
      port: FakeAssistantChatPort(),
      locale: const Locale('ar'),
    );

    expect(find.text('Pip'), findsOneWidget);
    expect(find.byKey(_emptyTitleKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_emptyTitleKey),
        matching: find.text('اسأل Pip'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('بيب'), findsNothing);
  });

  testWidgets('Arabic tooltips and semantics describe the chat actions', (
    tester,
  ) async {
    final recorder = FakeAssistantAudioRecorder();
    await _pumpScreen(
      tester,
      port: FakeAssistantChatPort(history: twoTurnHistory()),
      locale: const Locale('ar'),
      audioRecorder: recorder,
      audioPlayer: FakeAssistantAudioPlayer(),
    );
    final semantics = tester.ensureSemantics();
    try {
      expect(
        tester.widget<IconButton>(find.byKey(_clearKey)).tooltip,
        'مسح المحادثة',
      );
      expect(
        tester.widget<IconButton>(find.byKey(_sendKey)).tooltip,
        'إرسال رسالة',
      );
      expect(
        tester.widget<IconButton>(find.byKey(_micKey)).tooltip,
        'اسأل صوتيًا',
      );
      expect(
        tester.getSemantics(find.byKey(_clearKey)).tooltip,
        'مسح المحادثة',
      );
      expect(tester.getSemantics(find.byKey(_sendKey)).tooltip, 'إرسال رسالة');
      expect(tester.getSemantics(find.byKey(_micKey)).tooltip, 'اسأل صوتيًا');

      await tester.tap(find.byKey(_micKey));
      await tester.pump();

      expect(recorder.startCount, 1);
      expect(
        tester.widget<IconButton>(find.byKey(_micKey)).tooltip,
        'إيقاف التسجيل',
      );
      expect(tester.getSemantics(find.byKey(_micKey)).tooltip, 'إيقاف التسجيل');

      // Stop the recording so the provider's 60-second safety timer does not
      // outlive this widget test. A null clip keeps this a tooltip-only test.
      recorder.nextClip = null;
      await tester.tap(find.byKey(_micKey));
      await tester.pump();
      expect(recorder.stopCount, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('tapping the mic starts recording, tapping again sends it', (
    tester,
  ) async {
    final recorder = FakeAssistantAudioRecorder();
    final player = FakeAssistantAudioPlayer();
    final port = FakeAssistantChatPort(
      nextReply: AssistantChatReply(
        conversationId: 'conv-1',
        userTurnId: 'turn-user',
        replyTurnId: 'turn-reply',
        reply: 'Hatch was 84%.',
        createdAt: DateTime.utc(2026, 8, 14, 10),
        language: 'en',
        transcript: 'What is the hatch rate?',
        audioBase64: 'YXVkaW8=',
      ),
    );
    await _pumpScreen(
      tester,
      port: port,
      audioRecorder: recorder,
      audioPlayer: player,
    );

    await tester.tap(find.byKey(_micKey));
    await tester.pump();
    expect(recorder.startCount, 1);

    await tester.tap(find.byKey(_micKey));
    await tester.pump();
    await tester.pump();

    expect(port.sentAudio, ['ZmFrZS1hdWRpbw==']);
    expect(find.text('What is the hatch rate?'), findsOneWidget);
    expect(find.text('Hatch was 84%.'), findsOneWidget);
  });

  testWidgets('mic button is disabled while offline', (tester) async {
    await _pumpScreen(
      tester,
      port: FakeAssistantChatPort(),
      offline: true,
      audioRecorder: FakeAssistantAudioRecorder(),
      audioPlayer: FakeAssistantAudioPlayer(),
    );

    final button = tester.widget<IconButton>(find.byKey(_micKey));
    expect(button.onPressed, isNull);
  });
}
