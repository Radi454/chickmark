import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../features/chat/models/chat_message.dart';

/// Injectable seam over `functions.invoke('app-hatchery-agent', body: ...)`.
///
/// Returns the decoded response body and throws [FunctionException] for any
/// non-2xx status, exactly as `functions_client` does — so tests exercise the
/// same failure shape the real transport produces. The function name, project
/// URL, anon key and model are all resolved by the Supabase client and the
/// Edge Function; none of them is ever a literal in this file.
typedef AssistantChatRpc = Future<dynamic> Function(Map<String, dynamic> body);

/// Generates the `clientMessageId` idempotency key. Injectable so tests can
/// assert the exact value that reaches the wire.
typedef AssistantClientMessageIdFactory = String Function();

/// The one edge function this feature talks to.
const String _assistantFunctionName = 'app-hatchery-agent';

/// Server-imposed ceiling on a single message, per the frozen contract.
const int assistantMessageMaxLength = 4000;

/// Client-side ceiling on a single base64-encoded voice clip, matching the
/// server's MAX_AUDIO_BASE64_CHARS.
const int assistantAudioMaxBase64Chars = 8000000;

abstract interface class AssistantChatPort {
  /// Sends one user turn and returns the assistant's reply.
  ///
  /// [clientMessageId] is optional; when omitted the implementation mints a
  /// fresh v4 uuid. Passing the same id twice returns the same stored reply
  /// rather than producing a second turn, which is what makes retry safe.
  Future<AssistantChatReply> sendMessage(String message, {String? clientMessageId});

  /// Sends one recorded question as base64 audio and returns the assistant's
  /// reply, including the Whisper [AssistantChatReply.transcript] and TTS
  /// [AssistantChatReply.audioBase64] when available.
  Future<AssistantChatReply> sendVoice(String audioBase64, {String? clientMessageId});

  /// Loads the visible conversation, oldest turn first.
  Future<AssistantChatHistory> loadHistory({int limit = 50});

  /// Clears the visible conversation. Prior turns are retained server-side but
  /// are no longer shown or sent to the model.
  Future<void> resetConversation();
}

class AssistantChatReply {
  const AssistantChatReply({
    required this.conversationId,
    required this.userTurnId,
    required this.replyTurnId,
    required this.reply,
    required this.createdAt,
    required this.language,
    this.transcript,
    this.audioBase64,
  });

  final String conversationId;
  final String userTurnId;
  final String replyTurnId;
  final String reply;
  final DateTime createdAt;
  final String? language;

  /// The Whisper transcript of the user's audio, present only when the turn
  /// originated as a voice message.
  final String? transcript;

  /// Base64-encoded TTS audio for [reply], present only when the turn
  /// originated as a voice message and speech synthesis succeeded.
  final String? audioBase64;

  /// The assistant turn as it should appear in the message list.
  ChatMessage toAssistantMessage() => ChatMessage(
    id: replyTurnId,
    role: ChatMessageRole.assistant,
    text: reply,
    createdAt: createdAt,
    language: language,
  );
}

class AssistantChatHistory {
  const AssistantChatHistory({
    required this.conversationId,
    required this.messages,
  });

  final String conversationId;
  final List<ChatMessage> messages;
}

/// A failure the chat UI can show verbatim: [message] is one finished
/// user-facing sentence, [code] is the machine code from the contract (or a
/// local stand-in) for branching and tests.
class AssistantChatException implements Exception {
  const AssistantChatException(this.message, this.code);

  final String message;
  final String code;

  @override
  String toString() => message;
}

class AssistantChatService implements AssistantChatPort {
  AssistantChatService({
    AssistantChatRpc? rpc,
    AssistantClientMessageIdFactory? clientMessageIdFactory,
  }) : _rpc =
           rpc ??
           ((body) async {
             final response = await Supabase.instance.client.functions.invoke(
               _assistantFunctionName,
               body: body,
             );
             return response.data;
           }),
       _newClientMessageId =
           clientMessageIdFactory ?? (() => const Uuid().v4());

  final AssistantChatRpc _rpc;
  final AssistantClientMessageIdFactory _newClientMessageId;

  @override
  Future<AssistantChatReply> sendMessage(
    String message, {
    String? clientMessageId,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      throw const AssistantChatException(
        'Type a message before sending.',
        'invalid_request',
      );
    }
    if (trimmed.length > assistantMessageMaxLength) {
      throw const AssistantChatException(
        'That message is too long. Shorten it and try again.',
        'invalid_request',
      );
    }

    final payload = await _invoke({
      'action': 'send',
      'message': trimmed,
      'clientMessageId': clientMessageId ?? _newClientMessageId(),
    });
    final row = _object(payload);
    return AssistantChatReply(
      conversationId: _requiredText(row['conversationId'], 'conversationId'),
      userTurnId: _requiredText(row['userTurnId'], 'userTurnId'),
      replyTurnId: _requiredText(row['replyTurnId'], 'replyTurnId'),
      reply: _requiredText(row['reply'], 'reply'),
      createdAt: _timestamp(row['createdAt']),
      language: row['language']?.toString(),
    );
  }

  @override
  Future<AssistantChatReply> sendVoice(
    String audioBase64, {
    String? clientMessageId,
  }) async {
    final trimmed = audioBase64.trim();
    if (trimmed.isEmpty) {
      throw const AssistantChatException(
        'Record a question before sending.',
        'invalid_request',
      );
    }
    if (trimmed.length > assistantAudioMaxBase64Chars) {
      throw const AssistantChatException(
        'That recording is too long. Try a shorter question.',
        'invalid_request',
      );
    }

    final payload = await _invoke({
      'action': 'send',
      'audioBase64': trimmed,
      'clientMessageId': clientMessageId ?? _newClientMessageId(),
    });
    final row = _object(payload);
    return AssistantChatReply(
      conversationId: _requiredText(row['conversationId'], 'conversationId'),
      userTurnId: _requiredText(row['userTurnId'], 'userTurnId'),
      replyTurnId: _requiredText(row['replyTurnId'], 'replyTurnId'),
      reply: _requiredText(row['reply'], 'reply'),
      createdAt: _timestamp(row['createdAt']),
      language: row['language']?.toString(),
      transcript: row['transcript']?.toString(),
      audioBase64: row['audioBase64']?.toString(),
    );
  }

  @override
  Future<AssistantChatHistory> loadHistory({int limit = 50}) async {
    final payload = await _invoke({
      'action': 'history',
      'limit': limit.clamp(1, 100),
    });
    final row = _object(payload);
    final rawMessages = row['messages'];
    if (rawMessages is! List) {
      throw const FormatException('History response must contain messages');
    }
    return AssistantChatHistory(
      conversationId: _requiredText(row['conversationId'], 'conversationId'),
      messages: List.unmodifiable(
        rawMessages.map((entry) => ChatMessage.fromJson(_object(entry))),
      ),
    );
  }

  @override
  Future<void> resetConversation() async {
    await _invoke({'action': 'reset'});
  }

  /// Single choke point where every transport/decoding failure becomes one
  /// user-facing sentence plus a machine code.
  Future<dynamic> _invoke(Map<String, dynamic> body) async {
    try {
      return await _rpc(body);
    } on FunctionException catch (error) {
      throw _fromStatus(error.status, _codeOf(error.details));
    } on AssistantChatException {
      rethrow;
    } catch (_) {
      throw const AssistantChatException(
        'The assistant could not be reached. Check your connection and try again.',
        'network_error',
      );
    }
  }
}

AssistantChatException _fromStatus(int status, String? code) {
  switch (status) {
    case 400:
      return AssistantChatException(
        'That message could not be sent. Edit it and try again.',
        code ?? 'invalid_request',
      );
    case 401:
      return AssistantChatException(
        'Your sign-in expired. Sign in again to keep chatting.',
        code ?? 'unauthenticated',
      );
    case 403:
      return AssistantChatException(
        'Your account is not approved for the assistant yet.',
        code ?? 'not_approved',
      );
    case 429:
      return AssistantChatException(
        'Too many messages just now. Wait a moment and try again.',
        code ?? 'rate_limited',
      );
    case 502:
      return AssistantChatException(
        'The assistant is unavailable right now. Try again shortly.',
        code ?? 'agent_unavailable',
      );
    default:
      return AssistantChatException(
        'Something went wrong. Please try again.',
        code ?? 'server_error',
      );
  }
}

String? _codeOf(Object? details) {
  if (details is Map) {
    final code = details['code']?.toString().trim();
    if (code != null && code.isNotEmpty) return code;
  }
  return null;
}

Map<String, dynamic> _object(Object? payload) {
  if (payload is! Map) {
    throw const FormatException('Assistant response must be an object');
  }
  return payload.map((key, value) => MapEntry(key.toString(), value));
}

String _requiredText(Object? value, String field) {
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) {
    throw FormatException('$field is required');
  }
  return text;
}

DateTime _timestamp(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    throw const FormatException('createdAt is invalid');
  }
  return parsed.toUtc();
}
