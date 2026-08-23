import 'package:flutter/foundation.dart';

/// One row of the `action: "conversations"` list — a summary of one Pip
/// conversation, never the full turn history.
///
/// [title] is server-derived from the first user message and may be null
/// (e.g. a voice-only conversation that never got a typed opener).
/// [lastMessageText] and [lastMessageAt] describe the most recent turn with
/// text, and are also null for a conversation with no turns yet.
@immutable
class PipConversationSummary {
  const PipConversationSummary({
    required this.conversationKey,
    required this.updatedAt,
    required this.createdAt,
    this.title,
    this.lastMessageText,
    this.lastMessageAt,
  });

  final String conversationKey;
  final String? title;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final DateTime updatedAt;
  final DateTime createdAt;

  /// Parses one entry of the `conversations` array. Tolerant of a malformed
  /// row: returns null instead of throwing, so one bad row does not blank
  /// the whole list.
  static PipConversationSummary? tryParse(Object? json) {
    if (json is! Map) return null;
    final map = json.map((key, value) => MapEntry(key.toString(), value));
    final conversationKey = map['conversationKey']?.toString().trim();
    if (conversationKey == null || conversationKey.isEmpty) return null;
    final updatedAt = DateTime.tryParse(map['updatedAt']?.toString() ?? '');
    if (updatedAt == null) return null;
    final createdAt = DateTime.tryParse(map['createdAt']?.toString() ?? '');
    if (createdAt == null) return null;

    final title = map['title']?.toString();
    final lastMessageText = map['lastMessageText']?.toString();
    final lastMessageAt = DateTime.tryParse(
      map['lastMessageAt']?.toString() ?? '',
    );

    return PipConversationSummary(
      conversationKey: conversationKey,
      title: (title == null || title.isEmpty) ? null : title,
      lastMessageText: (lastMessageText == null || lastMessageText.isEmpty)
          ? null
          : lastMessageText,
      lastMessageAt: lastMessageAt,
      updatedAt: updatedAt.toUtc(),
      createdAt: createdAt.toUtc(),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PipConversationSummary &&
        other.conversationKey == conversationKey &&
        other.title == title &&
        other.lastMessageText == lastMessageText &&
        other.lastMessageAt == lastMessageAt &&
        other.updatedAt == updatedAt &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
    conversationKey,
    title,
    lastMessageText,
    lastMessageAt,
    updatedAt,
    createdAt,
  );
}
