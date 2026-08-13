import 'dart:async';

import 'package:hatchaudit/features/chat/models/chat_message.dart';
import 'package:hatchaudit/services/supabase/assistant_chat_service.dart';

/// In-memory [AssistantChatPort] shared by the provider and widget tests.
///
/// Keeps every request it received so a test can assert what would have gone
/// on the wire, and can hold a send open ([manualSend]) so the optimistic
/// "sending" window and the thinking indicator are observable.
class FakeAssistantChatPort implements AssistantChatPort {
  FakeAssistantChatPort({
    this.history,
    this.historyError,
    this.sendError,
    this.resetError,
    this.manualSend = false,
    AssistantChatReply? nextReply,
  }) : nextReply = nextReply ?? reply('Hatch was 84%.');

  AssistantChatHistory? history;
  Object? historyError;
  Object? sendError;
  Object? resetError;
  final bool manualSend;
  AssistantChatReply nextReply;

  final List<String> sentMessages = [];
  final List<String?> sentClientMessageIds = [];
  final List<String> sentAudio = [];
  int historyCount = 0;
  int resetCount = 0;

  Completer<AssistantChatReply>? _pendingSend;

  @override
  Future<AssistantChatReply> sendMessage(
    String message, {
    String? clientMessageId,
  }) {
    sentMessages.add(message);
    sentClientMessageIds.add(clientMessageId);
    final error = sendError;
    if (error != null) return Future.error(error);
    if (!manualSend) return Future.value(nextReply);
    final completer = Completer<AssistantChatReply>();
    _pendingSend = completer;
    return completer.future;
  }

  @override
  Future<AssistantChatReply> sendVoice(
    String audioBase64, {
    String? clientMessageId,
  }) {
    sentAudio.add(audioBase64);
    sentClientMessageIds.add(clientMessageId);
    final error = sendError;
    if (error != null) return Future.error(error);
    if (!manualSend) return Future.value(nextReply);
    final completer = Completer<AssistantChatReply>();
    _pendingSend = completer;
    return completer.future;
  }

  void completeSend(AssistantChatReply value) {
    _pendingSend!.complete(value);
    _pendingSend = null;
  }

  void failSend(Object error) {
    _pendingSend!.completeError(error);
    _pendingSend = null;
  }

  @override
  Future<AssistantChatHistory> loadHistory({int limit = 50}) {
    historyCount++;
    final error = historyError;
    if (error != null) return Future.error(error);
    return Future.value(
      history ??
          const AssistantChatHistory(conversationId: 'conv-1', messages: []),
    );
  }

  @override
  Future<void> resetConversation() {
    resetCount++;
    final error = resetError;
    if (error != null) return Future.error(error);
    history = const AssistantChatHistory(
      conversationId: 'conv-1',
      messages: [],
    );
    return Future.value();
  }
}

AssistantChatReply reply(String text) => AssistantChatReply(
  conversationId: 'conv-1',
  userTurnId: 'turn-user',
  replyTurnId: 'turn-reply',
  reply: text,
  createdAt: DateTime.utc(2026, 8, 14, 10),
  language: 'en',
);

AssistantChatHistory twoTurnHistory() => AssistantChatHistory(
  conversationId: 'conv-1',
  messages: [
    ChatMessage(
      id: 'turn-1',
      role: ChatMessageRole.user,
      text: 'ما نسبة الفقس؟',
      createdAt: DateTime.utc(2026, 8, 14, 9, 59),
      language: 'ar',
    ),
    ChatMessage(
      id: 'turn-2',
      role: ChatMessageRole.assistant,
      text: 'Hatch was 84%.',
      createdAt: DateTime.utc(2026, 8, 14, 10),
      language: 'en',
    ),
  ],
);
