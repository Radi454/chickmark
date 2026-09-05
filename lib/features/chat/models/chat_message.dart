import 'package:flutter/foundation.dart';

/// Who authored a chat turn. Mirrors the `role` field of the
/// `app-hatchery-agent` history contract (`"user" | "assistant"`).
enum ChatMessageRole { user, assistant }

/// Delivery state of a locally-composed turn. Server-loaded history is always
/// [ChatMessageStatus.sent]; only messages the user just typed pass through
/// [ChatMessageStatus.sending] and possibly [ChatMessageStatus.failed].
enum ChatMessageStatus { sending, sent, failed }

/// One immutable turn in the assistant conversation.
///
/// [id] is the server turn id once the server has acknowledged the turn. For an
/// optimistically-rendered user message it is the locally generated
/// `clientMessageId`, which doubles as the server-side idempotency key — so a
/// retry of a failed send reuses it and can never produce a duplicate turn.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.status = ChatMessageStatus.sent,
    this.language,
    this.clientMessageId,
    this.audioBase64,
    this.source,
  });

  final String id;
  final ChatMessageRole role;
  final String text;
  final DateTime createdAt;
  final ChatMessageStatus status;

  /// `"en" | "ar" | "mixed"` as classified by the server. Advisory only — the
  /// UI renders every bubble with the ambient text direction so mixed-script
  /// replies lay out correctly.
  final String? language;

  /// Idempotency key sent with `action: "send"`. Null for assistant turns and
  /// for history loaded from the server.
  final String? clientMessageId;

  /// TTS audio for an assistant reply to a voice question, base64 mp3.
  /// Memory-only: never parsed from history (`fromJson` leaves it null), so
  /// only replies received in this session are replayable.
  final String? audioBase64;

  /// `"text" | "voice" | null` as classified by the server: `"voice"` marks a
  /// historical turn that originated as a live-call transcript (from the
  /// retired Pip Live feature) rather than a typed or recorded-and-sent
  /// message. Null for locally-composed turns not yet round-tripped through
  /// history.
  final String? source;

  bool get isUser => role == ChatMessageRole.user;
  bool get isAssistant => role == ChatMessageRole.assistant;
  bool get isFailed => status == ChatMessageStatus.failed;
  bool get isSending => status == ChatMessageStatus.sending;
  bool get hasAudio => audioBase64 != null && audioBase64!.isNotEmpty;
  bool get isVoice => source == 'voice';

  /// Parses one entry of the `messages` array from `action: "history"`.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    if (id == null || id.isEmpty) {
      throw const FormatException('Chat turn id is required');
    }
    final text = json['text'];
    if (text is! String) {
      throw const FormatException('Chat turn text is required');
    }
    return ChatMessage(
      id: id,
      role: _roleFromJson(json['role']),
      text: text,
      createdAt: _createdAtFromJson(json['createdAt']),
      language: json['language']?.toString(),
      source: json['source']?.toString(),
    );
  }

  ChatMessage copyWith({
    String? id,
    ChatMessageRole? role,
    String? text,
    DateTime? createdAt,
    ChatMessageStatus? status,
    String? language,
    String? clientMessageId,
    String? audioBase64,
    String? source,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      language: language ?? this.language,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      audioBase64: audioBase64 ?? this.audioBase64,
      source: source ?? this.source,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChatMessage &&
        other.id == id &&
        other.role == role &&
        other.text == text &&
        other.createdAt == createdAt &&
        other.status == status &&
        other.language == language &&
        other.clientMessageId == clientMessageId &&
        other.audioBase64 == audioBase64 &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(
    id,
    role,
    text,
    createdAt,
    status,
    language,
    clientMessageId,
    audioBase64,
    source,
  );
}

ChatMessageRole _roleFromJson(Object? value) {
  switch (value?.toString()) {
    case 'user':
      return ChatMessageRole.user;
    case 'assistant':
      return ChatMessageRole.assistant;
    default:
      throw FormatException('Unknown chat role: $value');
  }
}

DateTime _createdAtFromJson(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) {
    throw const FormatException('Chat turn createdAt is required');
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException('Chat turn createdAt is invalid: $raw');
  }
  return parsed.toUtc();
}
