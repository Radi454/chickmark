import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/chat/models/pip_conversation_summary.dart';
import 'package:hatchaudit/features/chat/providers/pip_conversations_provider.dart';
import 'package:hatchaudit/features/chat/screens/pip_conversations_screen.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';
import 'package:hatchaudit/services/supabase/assistant_chat_service.dart';

import 'fake_assistant_chat_port.dart';

// Same discipline as assistant_chat_screen_test.dart: no sqflite, everything
// injected through a fake port, bounded pump() calls only.

const _fabKey = ValueKey('pip-new-conversation');
const _uuidV4KeyPattern =
    r'^app:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

Future<PipConversationsProvider> _pumpScreen(
  WidgetTester tester, {
  required FakeAssistantChatPort port,
  Locale locale = const Locale('en'),
  Future<void> Function(String key, String? title)? openConversation,
}) async {
  final provider = PipConversationsProvider(port: port);
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
      home: PipConversationsScreen(
        provider: provider,
        openConversation: openConversation,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return provider;
}

PipConversationSummary summaryAt(
  String key,
  DateTime updatedAt, {
  String? title,
  String? lastMessageText,
  DateTime? lastMessageAt,
}) => PipConversationSummary(
  conversationKey: key,
  updatedAt: updatedAt,
  createdAt: updatedAt,
  title: title,
  lastMessageText: lastMessageText,
  lastMessageAt: lastMessageAt ?? updatedAt,
);

void main() {
  testWidgets('an empty conversation list shows the empty state', (
    tester,
  ) async {
    await _pumpScreen(tester, port: FakeAssistantChatPort());

    expect(find.text('Pip'), findsOneWidget);
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(
      find.text('Start your first conversation with Pip'),
      findsOneWidget,
    );
    expect(find.byKey(_fabKey), findsOneWidget);
  });

  testWidgets('conversations render grouped under Today/Yesterday/Earlier', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final today = now.subtract(const Duration(hours: 1));
    final earlier = now.subtract(const Duration(days: 10));
    final port = FakeAssistantChatPort(
      conversations: [
        summaryAt(
          'app:11111111-1111-4111-8111-111111111111',
          today,
          title: 'Hatch rate this week',
          lastMessageText: 'Hatch was 84%.',
        ),
        summaryAt('app', earlier, title: 'Old thread'),
      ],
    );

    await _pumpScreen(tester, port: port);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('Yesterday'), findsNothing);
    expect(find.text('Hatch rate this week'), findsOneWidget);
    expect(find.text('Hatch was 84%.'), findsOneWidget);
    expect(find.text('Old thread'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
          'pip-conversation-tile-app:11111111-1111-4111-8111-111111111111',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a titleless conversation falls back to its preview, then to "Voice conversation"',
    (tester) async {
      final now = DateTime.now().toUtc();
      final port = FakeAssistantChatPort(
        conversations: [
          summaryAt(
            'app:11111111-1111-4111-8111-111111111111',
            now,
            lastMessageText: 'What is the hatch rate?',
          ),
          summaryAt('app:22222222-2222-4222-8222-222222222222', now),
        ],
      );

      await _pumpScreen(tester, port: port);

      expect(find.text('What is the hatch rate?'), findsOneWidget);
      expect(find.text('Voice conversation'), findsOneWidget);
    },
  );

  testWidgets('tapping the FAB opens a fresh app:<uuid> conversation', (
    tester,
  ) async {
    String? openedKey;
    String? openedTitle;
    await _pumpScreen(
      tester,
      port: FakeAssistantChatPort(),
      openConversation: (key, title) async {
        openedKey = key;
        openedTitle = title;
      },
    );

    await tester.tap(find.byKey(_fabKey));
    await tester.pump();
    await tester.pump();

    expect(openedKey, isNotNull);
    expect(RegExp(_uuidV4KeyPattern).hasMatch(openedKey!), isTrue);
    expect(openedTitle, isNull);
  });

  testWidgets('tapping a tile opens it with its conversationKey and title', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    String? openedKey;
    String? openedTitle;
    final port = FakeAssistantChatPort(
      conversations: [
        summaryAt(
          'app:11111111-1111-4111-8111-111111111111',
          now,
          title: 'Hatch rate this week',
        ),
      ],
    );

    await _pumpScreen(
      tester,
      port: port,
      openConversation: (key, title) async {
        openedKey = key;
        openedTitle = title;
      },
    );

    await tester.tap(find.text('Hatch rate this week'));
    await tester.pump();
    await tester.pump();

    expect(openedKey, 'app:11111111-1111-4111-8111-111111111111');
    expect(openedTitle, 'Hatch rate this week');
  });

  testWidgets('returning from a pushed conversation refreshes the list', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final port = FakeAssistantChatPort(
      conversations: [summaryAt('app', now, title: 'First')],
    );

    await _pumpScreen(
      tester,
      port: port,
      openConversation: (key, title) async {},
    );
    expect(port.listConversationsCount, 1);

    await tester.tap(find.text('First'));
    await tester.pump();
    await tester.pump();

    expect(port.listConversationsCount, 2);
  });

  testWidgets('a failed load shows the error state with a retry button', (
    tester,
  ) async {
    final port = FakeAssistantChatPort(
      conversationsError: const AssistantChatException(
        'The assistant is unavailable right now. Try again shortly.',
        'agent_unavailable',
      ),
    );

    await _pumpScreen(tester, port: port);

    expect(
      find.text('The assistant is unavailable right now. Try again shortly.'),
      findsOneWidget,
    );

    port.conversationsError = null;
    port.conversations = [
      summaryAt('app', DateTime.now().toUtc(), title: 'Recovered'),
    ];
    await tester.tap(find.byKey(const ValueKey('pip-conversations-retry')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Recovered'), findsOneWidget);
  });

  testWidgets(
    'Arabic locale renders an Arabic title/preview with no overflow',
    (tester) async {
      final now = DateTime.now().toUtc();
      final port = FakeAssistantChatPort(
        conversations: [
          summaryAt(
            'app:11111111-1111-4111-8111-111111111111',
            now,
            title: 'ما نسبة الفقس هذا الأسبوع؟',
            lastMessageText: 'نسبة الفقس كانت 84 بالمئة وهذا رقم جيد جدًا.',
          ),
        ],
      );

      await _pumpScreen(tester, port: port, locale: const Locale('ar'));

      expect(find.text('ما نسبة الفقس هذا الأسبوع؟'), findsOneWidget);
      expect(
        find.text('نسبة الفقس كانت 84 بالمئة وهذا رقم جيد جدًا.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final title = tester.widget<Text>(
        find.text('ما نسبة الفقس هذا الأسبوع؟'),
      );
      expect(title.textDirection, TextDirection.rtl);
    },
  );

  testWidgets(
    'Arabic locale: a title/preview equal to a known UI phrasebook key '
    'renders verbatim, not translated (F11)',
    (tester) async {
      final now = DateTime.now().toUtc();
      // 'Refresh' -> 'تحديث' is a real entry in the app's Arabic phrasebook
      // (see lib/l10n/app_localizations.dart). A user/model message or a
      // server-derived title that happens to equal it must still render as
      // typed, not as that unrelated UI label's Arabic translation.
      final port = FakeAssistantChatPort(
        conversations: [
          summaryAt(
            'app:55555555-5555-4555-8555-555555555555',
            now,
            title: 'Refresh',
            lastMessageText: 'Refresh',
          ),
        ],
      );

      await _pumpScreen(tester, port: port, locale: const Locale('ar'));

      expect(find.text('Refresh'), findsNWidgets(2));
      expect(find.text('تحديث'), findsNothing);
    },
  );
}
