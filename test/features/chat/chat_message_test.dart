import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/chat/models/chat_message.dart';

void main() {
  group('ChatMessage.source / isVoice', () {
    test('fromJson parses source and isVoice reflects it', () {
      final voiceMessage = ChatMessage.fromJson({
        'id': 'turn-1',
        'role': 'user',
        'text': 'What is the hatch rate?',
        'createdAt': '2026-08-14T10:00:00.000Z',
        'source': 'voice',
      });
      final textMessage = ChatMessage.fromJson({
        'id': 'turn-2',
        'role': 'assistant',
        'text': 'Hatch was 84%.',
        'createdAt': '2026-08-14T10:00:01.000Z',
        'source': 'text',
      });
      final noSourceMessage = ChatMessage.fromJson({
        'id': 'turn-3',
        'role': 'user',
        'text': 'legacy turn',
        'createdAt': '2026-08-14T10:00:02.000Z',
      });

      expect(voiceMessage.source, 'voice');
      expect(voiceMessage.isVoice, isTrue);
      expect(textMessage.source, 'text');
      expect(textMessage.isVoice, isFalse);
      expect(noSourceMessage.source, isNull);
      expect(noSourceMessage.isVoice, isFalse);
    });

    test('copyWith preserves source when not overridden', () {
      final message = ChatMessage(
        id: 'turn-1',
        role: ChatMessageRole.user,
        text: 'hi',
        createdAt: DateTime.utc(2026, 8, 14, 10),
        source: 'voice',
      );

      final copy = message.copyWith(status: ChatMessageStatus.sent);

      expect(copy.source, 'voice');
      expect(copy.isVoice, isTrue);
    });

    test('copyWith can override source explicitly', () {
      final message = ChatMessage(
        id: 'turn-1',
        role: ChatMessageRole.user,
        text: 'hi',
        createdAt: DateTime.utc(2026, 8, 14, 10),
        source: 'voice',
      );

      final copy = message.copyWith(source: 'text');

      expect(copy.source, 'text');
      expect(copy.isVoice, isFalse);
    });
  });
}
