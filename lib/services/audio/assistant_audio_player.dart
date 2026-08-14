import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';

/// Plays short assistant audio clips: the bundled filler chime and the TTS
/// reply returned by the server. Abstracted so tests never touch a real
/// audio device.
abstract interface class AssistantAudioPlayer {
  /// [assetPath] is relative to the `assets/` prefix, e.g. `audio/filler_chime.wav`.
  ///
  /// Resolves only once playback finishes (or is interrupted by [stop]),
  /// never merely once it has started.
  Future<void> playAsset(String assetPath);

  /// Resolves only once playback finishes (or is interrupted by [stop]),
  /// never merely once it has started.
  Future<void> playBase64(String base64Audio);
  Future<void> stop();
}

class AudioplayersAssistantAudioPlayer implements AssistantAudioPlayer {
  AudioplayersAssistantAudioPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  StreamSubscription<void>? _completeSub;
  Completer<void>? _pendingCompletion;

  @override
  Future<void> playAsset(String assetPath) {
    return _playAndAwaitCompletion(
      () => _player.play(AssetSource(assetPath)),
    );
  }

  @override
  Future<void> playBase64(String base64Audio) {
    return _playAndAwaitCompletion(
      () => _player.play(BytesSource(base64Decode(base64Audio))),
    );
  }

  /// `AudioPlayer.play()`'s Future completes once playback *starts*, not
  /// once it finishes. Callers (e.g. the mic re-enabling only after the
  /// reply has finished speaking) need the latter, so this listens for the
  /// player's own completion event and resolves a separate [Completer] then
  /// — or as soon as [stop] cuts playback short, so a caller can never hang.
  Future<void> _playAndAwaitCompletion(
    Future<void> Function() startPlayback,
  ) async {
    await _player.stop();
    await _completeSub?.cancel();

    // A second play call (e.g. the reply audio cutting off the filler chime)
    // must resolve whatever the previous call's completer was waiting on —
    // audioplayers does not emit onPlayerComplete for a programmatic stop(),
    // so without this the earlier completer would never resolve and stay
    // permanently pending.
    final previous = _pendingCompletion;
    if (previous != null && !previous.isCompleted) {
      previous.complete();
    }

    final completer = Completer<void>();
    _pendingCompletion = completer;
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await startPlayback();
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
    return completer.future;
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await _completeSub?.cancel();
    _completeSub = null;
    final pending = _pendingCompletion;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    _pendingCompletion = null;
  }
}
