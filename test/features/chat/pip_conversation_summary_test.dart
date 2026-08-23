import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/chat/models/pip_conversation_summary.dart';

void main() {
  group('PipConversationSummary.tryParse', () {
    test('parses a full row', () {
      final summary = PipConversationSummary.tryParse({
        'conversationKey': 'app:11111111-1111-4111-8111-111111111111',
        'title': 'Hatch rate this week',
        'lastMessageText': 'Hatch was 84%.',
        'lastMessageAt': '2026-08-14T10:00:00.000Z',
        'updatedAt': '2026-08-14T10:00:00.000Z',
        'createdAt': '2026-08-14T09:00:00.000Z',
      });

      expect(summary, isNotNull);
      expect(
        summary!.conversationKey,
        'app:11111111-1111-4111-8111-111111111111',
      );
      expect(summary.title, 'Hatch rate this week');
      expect(summary.lastMessageText, 'Hatch was 84%.');
      expect(summary.lastMessageAt, DateTime.utc(2026, 8, 14, 10));
      expect(summary.updatedAt, DateTime.utc(2026, 8, 14, 10));
      expect(summary.createdAt, DateTime.utc(2026, 8, 14, 9));
    });

    test('a null title, lastMessageText, and lastMessageAt parse as null', () {
      final summary = PipConversationSummary.tryParse({
        'conversationKey': 'app',
        'title': null,
        'lastMessageText': null,
        'lastMessageAt': null,
        'updatedAt': '2026-08-14T10:00:00.000Z',
        'createdAt': '2026-08-01T09:00:00.000Z',
      });

      expect(summary, isNotNull);
      expect(summary!.title, isNull);
      expect(summary.lastMessageText, isNull);
      expect(summary.lastMessageAt, isNull);
    });

    test('an empty-string title or lastMessageText also parses as null', () {
      final summary = PipConversationSummary.tryParse({
        'conversationKey': 'app',
        'title': '',
        'lastMessageText': '',
        'updatedAt': '2026-08-14T10:00:00.000Z',
        'createdAt': '2026-08-01T09:00:00.000Z',
      });

      expect(summary, isNotNull);
      expect(summary!.title, isNull);
      expect(summary.lastMessageText, isNull);
    });

    test('returns null when conversationKey is missing or empty', () {
      expect(
        PipConversationSummary.tryParse({
          'updatedAt': '2026-08-14T10:00:00.000Z',
          'createdAt': '2026-08-01T09:00:00.000Z',
        }),
        isNull,
      );
      expect(
        PipConversationSummary.tryParse({
          'conversationKey': '',
          'updatedAt': '2026-08-14T10:00:00.000Z',
          'createdAt': '2026-08-01T09:00:00.000Z',
        }),
        isNull,
      );
    });

    test('returns null when updatedAt is missing or unparsable', () {
      expect(
        PipConversationSummary.tryParse({
          'conversationKey': 'app',
          'createdAt': '2026-08-01T09:00:00.000Z',
        }),
        isNull,
      );
      expect(
        PipConversationSummary.tryParse({
          'conversationKey': 'app',
          'updatedAt': 'not-a-date',
          'createdAt': '2026-08-01T09:00:00.000Z',
        }),
        isNull,
      );
    });

    test('returns null when createdAt is missing or unparsable', () {
      expect(
        PipConversationSummary.tryParse({
          'conversationKey': 'app',
          'updatedAt': '2026-08-14T10:00:00.000Z',
        }),
        isNull,
      );
    });

    test('returns null for a row that is not a map', () {
      expect(PipConversationSummary.tryParse('not a map'), isNull);
      expect(PipConversationSummary.tryParse(null), isNull);
      expect(PipConversationSummary.tryParse(42), isNull);
    });
  });
}
