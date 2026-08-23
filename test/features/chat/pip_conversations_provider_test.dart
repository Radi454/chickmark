import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/chat/models/pip_conversation_summary.dart';
import 'package:hatchaudit/features/chat/providers/pip_conversations_provider.dart';
import 'package:hatchaudit/services/supabase/assistant_chat_service.dart';

import 'fake_assistant_chat_port.dart';

PipConversationSummary summaryAt(
  String key,
  DateTime updatedAt, {
  String? title,
}) => PipConversationSummary(
  conversationKey: key,
  updatedAt: updatedAt,
  createdAt: updatedAt,
  title: title,
);

void main() {
  group('groupConversationsByDay', () {
    // A fixed "now" (local) so every test pins the today/yesterday boundary
    // itself rather than depending on the wall clock.
    final now = DateTime(2026, 8, 14, 15, 30);

    test('buckets a same-day conversation as today', () {
      final conversation = summaryAt('app', DateTime(2026, 8, 14, 9, 0));

      final grouped = groupConversationsByDay([conversation], now);

      expect(grouped[PipConversationDayBucket.today], [conversation]);
      expect(grouped[PipConversationDayBucket.yesterday], isEmpty);
      expect(grouped[PipConversationDayBucket.earlier], isEmpty);
    });

    test('buckets the previous calendar day as yesterday', () {
      final conversation = summaryAt('app', DateTime(2026, 8, 13, 23, 59));

      final grouped = groupConversationsByDay([conversation], now);

      expect(grouped[PipConversationDayBucket.yesterday], [conversation]);
      expect(grouped[PipConversationDayBucket.today], isEmpty);
      expect(grouped[PipConversationDayBucket.earlier], isEmpty);
    });

    test('buckets anything older than yesterday as earlier', () {
      final conversation = summaryAt('app', DateTime(2026, 8, 12, 23, 59));

      final grouped = groupConversationsByDay([conversation], now);

      expect(grouped[PipConversationDayBucket.earlier], [conversation]);
      expect(grouped[PipConversationDayBucket.today], isEmpty);
      expect(grouped[PipConversationDayBucket.yesterday], isEmpty);
    });

    test('the midnight boundary flips a conversation from today to yesterday', () {
      // One minute before midnight relative to `now`'s day is still "today"
      // for `now`, but "now" itself sitting at 00:00 makes yesterday's
      // 23:59 fall into the yesterday bucket, not today.
      final justBeforeMidnight = DateTime(2026, 8, 13, 23, 59, 59);
      final nowAtMidnight = DateTime(2026, 8, 14, 0, 0, 0);
      final conversation = summaryAt('app', justBeforeMidnight);

      final grouped = groupConversationsByDay([conversation], nowAtMidnight);

      expect(grouped[PipConversationDayBucket.yesterday], [conversation]);
      expect(grouped[PipConversationDayBucket.today], isEmpty);
    });

    test('a conversation exactly at midnight today is bucketed as today', () {
      final atMidnight = DateTime(2026, 8, 14, 0, 0, 0);
      final conversation = summaryAt('app', atMidnight);

      final grouped = groupConversationsByDay([conversation], now);

      expect(grouped[PipConversationDayBucket.today], [conversation]);
    });

    test('preserves arrival order within a bucket', () {
      final first = summaryAt('a', DateTime(2026, 8, 14, 9, 0));
      final second = summaryAt('b', DateTime(2026, 8, 14, 8, 0));

      final grouped = groupConversationsByDay([first, second], now);

      expect(grouped[PipConversationDayBucket.today], [first, second]);
    });

    test('an empty list produces empty buckets', () {
      final grouped = groupConversationsByDay(const [], now);

      expect(grouped[PipConversationDayBucket.today], isEmpty);
      expect(grouped[PipConversationDayBucket.yesterday], isEmpty);
      expect(grouped[PipConversationDayBucket.earlier], isEmpty);
    });
  });

  group('PipConversationsProvider', () {
    test('load populates conversations and lands in loaded', () async {
      final port = FakeAssistantChatPort(
        conversations: [summaryAt('app', DateTime.utc(2026, 8, 14, 10))],
      );
      final provider = PipConversationsProvider(port: port);

      expect(provider.loadState, PipConversationsLoadState.uninitialized);
      await provider.load();

      expect(provider.loadState, PipConversationsLoadState.loaded);
      expect(provider.conversations, hasLength(1));
      expect(provider.error, isNull);
    });

    test('a second load() is a no-op once already loaded', () async {
      final port = FakeAssistantChatPort(
        conversations: [summaryAt('app', DateTime.utc(2026, 8, 14, 10))],
      );
      final provider = PipConversationsProvider(port: port);

      await provider.load();
      await provider.load();

      expect(port.listConversationsCount, 1);
    });

    test('refresh always re-fetches', () async {
      final port = FakeAssistantChatPort(
        conversations: [summaryAt('app', DateTime.utc(2026, 8, 14, 10))],
      );
      final provider = PipConversationsProvider(port: port);

      await provider.load();
      await provider.refresh();

      expect(port.listConversationsCount, 2);
    });

    test('a failed load sets the error state', () async {
      final port = FakeAssistantChatPort(
        conversationsError: const AssistantChatException(
          'The assistant is unavailable right now. Try again shortly.',
          'agent_unavailable',
        ),
      );
      final provider = PipConversationsProvider(port: port);

      await provider.load();

      expect(provider.loadState, PipConversationsLoadState.error);
      expect(provider.error, contains('unavailable right now'));
      expect(provider.conversations, isEmpty);
    });

    test('refresh after a failure clears the error on success', () async {
      final port = FakeAssistantChatPort(
        conversationsError: const AssistantChatException('nope', 'server_error'),
      );
      final provider = PipConversationsProvider(port: port);
      await provider.load();
      expect(provider.loadState, PipConversationsLoadState.error);

      port.conversationsError = null;
      port.conversations = [summaryAt('app', DateTime.utc(2026, 8, 14, 10))];
      await provider.refresh();

      expect(provider.loadState, PipConversationsLoadState.loaded);
      expect(provider.error, isNull);
      expect(provider.conversations, hasLength(1));
    });
  });
}
