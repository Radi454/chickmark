import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../services/audio/assistant_audio_player.dart';
import '../../../services/audio/assistant_audio_recorder.dart';
import '../../../services/supabase/assistant_chat_service.dart';
import '../models/chat_message.dart';

enum AssistantLoadState { uninitialized, loading, loaded, error }

/// Conversation state for the in-app assistant.
///
/// The list is the single source of truth for what the user sees, and a user
/// turn is appended *before* the network call so typed text is on screen
/// immediately. If the call fails the turn stays in the list marked
/// [ChatMessageStatus.failed] — the text is never discarded — and [retry]
/// re-sends it under the same `clientMessageId`, which the server treats as an
/// idempotency key, so a retry can never create a duplicate turn.
class AssistantProvider extends ChangeNotifier {
  AssistantProvider({
    AssistantChatPort? port,
    AssistantClientMessageIdFactory? clientMessageIdFactory,
    AssistantAudioRecorder? audioRecorder,
    AssistantAudioPlayer? audioPlayer,
  }) : _port = port ?? AssistantChatService(),
       _newClientMessageId =
           clientMessageIdFactory ?? (() => const Uuid().v4()),
       _audioRecorder = audioRecorder ?? RecordAssistantAudioRecorder(),
       _providedAudioPlayer = audioPlayer;

  final AssistantChatPort _port;
  final AssistantClientMessageIdFactory _newClientMessageId;
  final AssistantAudioRecorder _audioRecorder;

  // The default AudioplayersAssistantAudioPlayer's constructor eagerly builds
  // a real audioplayers `AudioPlayer`, which touches a platform channel. That
  // must not happen just from constructing an AssistantProvider — otherwise
  // every plain unit test that never touches voice (no Flutter binding) would
  // throw. So the default is only ever created lazily, on first actual use;
  // an injected player (e.g. a test fake) is used as-is.
  final AssistantAudioPlayer? _providedAudioPlayer;
  AssistantAudioPlayer? _lazyDefaultAudioPlayer;
  AssistantAudioPlayer get _audioPlayer =>
      _providedAudioPlayer ??
      (_lazyDefaultAudioPlayer ??= AudioplayersAssistantAudioPlayer());

  static const String _fillerChimeAsset = 'audio/filler_chime.wav';

  final List<ChatMessage> _messages = <ChatMessage>[];
  AssistantLoadState _loadState = AssistantLoadState.uninitialized;
  bool _isSending = false;
  bool _isRecording = false;
  bool _isAwaitingVoiceReply = false;
  bool _isSpeaking = false;
  String? _error;
  bool _disposed = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  AssistantLoadState get loadState => _loadState;
  bool get isLoading => _loadState == AssistantLoadState.loading;
  bool get isSending => _isSending;
  bool get isRecording => _isRecording;
  bool get isAwaitingVoiceReply => _isAwaitingVoiceReply;
  bool get isSpeaking => _isSpeaking;
  String? get error => _error;
  bool get isEmpty => _messages.isEmpty;

  /// Character ceiling enforced before the request leaves the device, so an
  /// over-long message fails instantly instead of round-tripping to a 400.
  static const int maxMessageLength = assistantMessageMaxLength;

  Future<void> load() async {
    if (_loadState == AssistantLoadState.loading) return;
    _loadState = AssistantLoadState.loading;
    _error = null;
    _notify();
    try {
      final history = await _port.loadHistory();
      _messages
        ..clear()
        ..addAll(history.messages);
      _loadState = AssistantLoadState.loaded;
    } on AssistantChatException catch (error) {
      _error = error.message;
      _loadState = AssistantLoadState.error;
    } catch (_) {
      _error = 'Could not load the conversation. Please try again.';
      _loadState = AssistantLoadState.error;
    }
    _notify();
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) return;
    if (trimmed.length > maxMessageLength) {
      _error = 'That message is too long. Shorten it and try again.';
      _notify();
      return;
    }

    final clientMessageId = _newClientMessageId();
    final pending = ChatMessage(
      id: clientMessageId,
      role: ChatMessageRole.user,
      text: trimmed,
      createdAt: DateTime.now().toUtc(),
      status: ChatMessageStatus.sending,
      clientMessageId: clientMessageId,
    );
    _messages.add(pending);
    await _deliver(pending);
  }

  Future<void> startRecording() async {
    if (_isSending || _isRecording || _isAwaitingVoiceReply) return;
    try {
      await _audioRecorder.start();
    } on AssistantAudioException catch (error) {
      _error = error.message;
      _notify();
      return;
    }
    _isRecording = true;
    _error = null;
    _notify();
  }

  /// Stops recording, sends the clip, and auto-plays whatever comes back:
  /// a filler chime while waiting, then the TTS reply audio.
  Future<void> stopRecordingAndSend() async {
    if (!_isRecording) return;
    _isRecording = false;
    final audioBase64 = await _audioRecorder.stop();
    if (audioBase64 == null || audioBase64.isEmpty) {
      _notify();
      return;
    }

    final clientMessageId = _newClientMessageId();
    final pending = ChatMessage(
      id: clientMessageId,
      role: ChatMessageRole.user,
      text: 'Voice message',
      createdAt: DateTime.now().toUtc(),
      status: ChatMessageStatus.sending,
      clientMessageId: clientMessageId,
    );
    _messages.add(pending);
    _isAwaitingVoiceReply = true;
    _error = null;
    _notify();
    unawaited(_audioPlayer.playAsset(_fillerChimeAsset));

    String? replyAudio;
    try {
      final reply = await _port.sendVoice(
        audioBase64,
        clientMessageId: clientMessageId,
      );
      _replace(pending.id, (current) => current.copyWith(
        id: reply.userTurnId,
        text: reply.transcript ?? current.text,
        status: ChatMessageStatus.sent,
      ));
      _messages.add(reply.toAssistantMessage());
      _loadState = AssistantLoadState.loaded;
      replyAudio = reply.audioBase64;
    } on AssistantChatException catch (error) {
      _failMessage(pending.id, error.message);
    } catch (_) {
      _failMessage(pending.id, 'Could not send that recording. Please try again.');
    } finally {
      _isAwaitingVoiceReply = false;
      _notify();
    }

    // Playback of an already-successful reply is best-effort: a codec, output
    // device, or decode failure here must not overwrite the send outcome
    // above (the text reply is already visible either way).
    if (replyAudio != null && replyAudio.isNotEmpty) {
      _isSpeaking = true;
      _notify();
      try {
        await _audioPlayer.playBase64(replyAudio);
      } catch (_) {
        // Swallow: the reply text is already delivered and visible.
      } finally {
        _isSpeaking = false;
        _notify();
      }
    }
  }

  /// Re-sends a previously failed user turn, reusing its `clientMessageId`.
  Future<void> retry(ChatMessage message) async {
    if (_isSending || !message.isUser) return;
    final index = _messages.indexWhere((entry) => entry.id == message.id);
    if (index < 0) return;
    _messages[index] = _messages[index].copyWith(
      status: ChatMessageStatus.sending,
    );
    await _deliver(_messages[index]);
  }

  Future<void> clear() async {
    if (_isSending) return;
    _error = null;
    _notify();
    try {
      await _port.resetConversation();
      _messages.clear();
      _loadState = AssistantLoadState.loaded;
    } on AssistantChatException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Could not clear the conversation. Please try again.';
    }
    _notify();
  }

  /// Dismisses the visible error banner without touching the conversation.
  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  Future<void> _deliver(ChatMessage pending) async {
    _isSending = true;
    _error = null;
    _notify();
    try {
      final reply = await _port.sendMessage(
        pending.text,
        clientMessageId: pending.clientMessageId ?? pending.id,
      );
      _replace(pending.id, (current) => current.copyWith(
        id: reply.userTurnId,
        status: ChatMessageStatus.sent,
      ));
      _messages.add(reply.toAssistantMessage());
      _loadState = AssistantLoadState.loaded;
    } on AssistantChatException catch (error) {
      _failMessage(pending.id, error.message);
    } catch (_) {
      _failMessage(pending.id, 'Could not send that message. Please try again.');
    } finally {
      _isSending = false;
      _notify();
    }
  }

  void _failMessage(String id, String message) {
    _replace(id, (current) => current.copyWith(
      status: ChatMessageStatus.failed,
    ));
    _error = message;
  }

  void _replace(String id, ChatMessage Function(ChatMessage current) update) {
    final index = _messages.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    _messages[index] = update(_messages[index]);
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
