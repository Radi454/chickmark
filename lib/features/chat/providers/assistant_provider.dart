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
       _providedAudioRecorder = audioRecorder,
       _providedAudioPlayer = audioPlayer;

  final AssistantChatPort _port;
  final AssistantClientMessageIdFactory _newClientMessageId;
  // record 7 eagerly opens its platform channel from AudioRecorder's
  // constructor. Keep the default recorder lazy so opening text chat does not
  // initialize microphone infrastructure, and pure provider tests can run
  // without a Flutter services binding. Injected recorders are used as-is.
  final AssistantAudioRecorder? _providedAudioRecorder;
  AssistantAudioRecorder? _lazyDefaultAudioRecorder;
  AssistantAudioRecorder get _audioRecorder =>
      _providedAudioRecorder ??
      (_lazyDefaultAudioRecorder ??= RecordAssistantAudioRecorder());

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

  /// Ceiling on how long a single voice turn may record, so "ask a quick
  /// question" can't turn into minutes of audio burning the TTS/Whisper
  /// budget. Recording auto-stops (and sends) once this elapses.
  static const Duration maxRecordingDuration = Duration(seconds: 60);

  final List<ChatMessage> _messages = <ChatMessage>[];
  AssistantLoadState _loadState = AssistantLoadState.uninitialized;
  bool _isSending = false;
  bool _isRecording = false;
  bool _isAwaitingVoiceReply = false;
  bool _isSpeaking = false;
  String? _playingMessageId;
  bool _isPaused = false;
  String? _error;
  bool _disposed = false;
  Timer? _recordingTimeoutTimer;

  /// Ids of user turns that originated as a voice recording. The audio clip
  /// is discarded the moment it is sent, so a failed voice turn can never be
  /// resent — only tracked so [canRetry] can hide the (otherwise misleading)
  /// retry action for it.
  final Set<String> _voiceMessageIds = <String>{};

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  AssistantLoadState get loadState => _loadState;
  bool get isLoading => _loadState == AssistantLoadState.loading;
  bool get isSending => _isSending;
  bool get isRecording => _isRecording;
  bool get isAwaitingVoiceReply => _isAwaitingVoiceReply;
  bool get isSpeaking => _isSpeaking;

  /// Id of the assistant message whose audio is loaded in the player (playing
  /// or paused), or null when nothing is. Drives the per-bubble controls.
  String? get playingMessageId => _playingMessageId;
  bool get isPaused => _isPaused;
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
    } catch (_) {
      _error = 'Could not start recording. Please try again.';
      _notify();
      return;
    }
    _isRecording = true;
    _error = null;
    _recordingTimeoutTimer?.cancel();
    _recordingTimeoutTimer = Timer(maxRecordingDuration, () {
      unawaited(stopRecordingAndSend());
    });
    _notify();
  }

  /// Stops recording, sends the clip, and auto-plays whatever comes back:
  /// a filler chime while waiting, then the TTS reply audio.
  Future<void> stopRecordingAndSend() async {
    if (!_isRecording) return;
    _isRecording = false;
    _recordingTimeoutTimer?.cancel();
    _recordingTimeoutTimer = null;

    String? audioBase64;
    try {
      audioBase64 = await _audioRecorder.stop();
    } catch (_) {
      _error = 'Could not save that recording. Please try again.';
      _notify();
      return;
    }
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
    _voiceMessageIds.add(pending.id);
    _isAwaitingVoiceReply = true;
    _error = null;
    _notify();
    unawaited(_playChimeBestEffort());

    ChatMessage? assistantMessage;
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
      assistantMessage = reply.toAssistantMessage();
      _messages.add(assistantMessage);
      _loadState = AssistantLoadState.loaded;
    } on AssistantChatException catch (error) {
      _failMessage(pending.id, error.message);
    } catch (_) {
      _failMessage(pending.id, 'Could not send that recording. Please try again.');
    } finally {
      _isAwaitingVoiceReply = false;
      _notify();
    }

    // Auto-play routes through the same per-message path the bubble controls
    // use, so the bubble shows pause/replay while the reply speaks.
    if (assistantMessage != null && assistantMessage.hasAudio) {
      await playMessageAudio(assistantMessage);
    }
  }

  /// Plays (or restarts) a message's attached reply audio. Playing one
  /// message stops any other. Best-effort: playback failure never surfaces
  /// as an error — the reply text is already visible.
  Future<void> playMessageAudio(ChatMessage message) async {
    final audio = message.audioBase64;
    if (audio == null || audio.isEmpty) return;
    _playingMessageId = message.id;
    _isPaused = false;
    _isSpeaking = true;
    _notify();
    try {
      await _audioPlayer.playBase64(audio);
    } catch (_) {
      // Swallow: the reply text is already delivered and visible.
    } finally {
      // A later playMessageAudio call may already own the player; only the
      // still-current owner clears the state.
      if (_playingMessageId == message.id) {
        _playingMessageId = null;
        _isPaused = false;
        _isSpeaking = false;
        _notify();
      }
    }
  }

  Future<void> pausePlayback() async {
    if (_playingMessageId == null || _isPaused) return;
    _isPaused = true;
    _isSpeaking = false;
    _notify();
    try {
      await _audioPlayer.pause();
    } catch (_) {
      // Best-effort, like all playback control.
    }
  }

  Future<void> resumePlayback() async {
    if (_playingMessageId == null || !_isPaused) return;
    _isPaused = false;
    _isSpeaking = true;
    _notify();
    try {
      await _audioPlayer.resume();
    } catch (_) {
      // Best-effort, like all playback control.
    }
  }

  /// Whether [retry] can meaningfully re-send this turn. A voice-originated
  /// turn's audio clip is discarded the moment it is sent, so there is
  /// nothing left to resend — [retry] would just fire the placeholder text
  /// ("Voice message") at the agent, which is never what the user meant.
  bool canRetry(ChatMessage message) =>
      message.isFailed && !_voiceMessageIds.contains(message.id);

  /// Re-sends a previously failed user turn, reusing its `clientMessageId`.
  Future<void> retry(ChatMessage message) async {
    if (_isSending || !message.isUser || !canRetry(message)) return;
    final index = _messages.indexWhere((entry) => entry.id == message.id);
    if (index < 0) return;
    _messages[index] = _messages[index].copyWith(
      status: ChatMessageStatus.sending,
    );
    await _deliver(_messages[index]);
  }

  Future<void> clear() async {
    if (_isSending || _isRecording || _isAwaitingVoiceReply) return;
    _error = null;
    _notify();
    try {
      await _port.resetConversation();
      _messages.clear();
      // The bubble owning any in-flight playback just vanished; stop the
      // audio with it. stop() also resolves playMessageAudio's pending
      // future, which then resets the playing/paused/speaking state.
      if (_playingMessageId != null) {
        final player = _providedAudioPlayer ?? _lazyDefaultAudioPlayer;
        if (player != null) unawaited(player.stop().catchError((_) {}));
      }
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

  /// Best-effort filler chime: `unawaited()` only skips the await, it does
  /// NOT swallow errors, so a chime failure (missing asset, no output
  /// device) would otherwise become an unhandled zone error. It is purely
  /// decorative while the reply is fetched, so any failure here is silently
  /// dropped rather than surfaced through [_error].
  Future<void> _playChimeBestEffort() async {
    try {
      await _audioPlayer.playAsset(_fillerChimeAsset);
    } catch (_) {
      // Swallow: the chime is decorative only.
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
    _recordingTimeoutTimer?.cancel();
    _recordingTimeoutTimer = null;
    // Best-effort release of platform resources: if the user navigates away
    // mid-recording the mic must stop (and its temp file get cleaned up), and
    // any in-flight reply playback must stop too. Fire-and-forget — dispose()
    // cannot be async — and swallowed so a platform failure can never throw
    // out of dispose().
    if (_isRecording) {
      unawaited(_audioRecorder.stop().catchError((_) => null));
    }
    // Only touch the audio player if one was ever created: the default
    // player is lazy specifically so plain unit tests never construct a real
    // platform AudioPlayer, and dispose() must not undo that.
    final player = _providedAudioPlayer ?? _lazyDefaultAudioPlayer;
    if (player != null) {
      unawaited(player.stop().catchError((_) {}));
    }
    super.dispose();
  }
}
