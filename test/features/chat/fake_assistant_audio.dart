import 'dart:async';

import 'package:hatchaudit/services/audio/assistant_audio_player.dart';
import 'package:hatchaudit/services/audio/assistant_audio_recorder.dart';

class FakeAssistantAudioRecorder implements AssistantAudioRecorder {
  Object? startError;
  String? nextClip = 'ZmFrZS1hdWRpbw==';
  bool _recording = false;
  int startCount = 0;
  int stopCount = 0;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> start() async {
    startCount++;
    final error = startError;
    if (error != null) throw error;
    _recording = true;
  }

  @override
  Future<String?> stop() async {
    stopCount++;
    _recording = false;
    return nextClip;
  }
}

/// Fake for [AssistantAudioPlayer] matching the real contract: both play
/// methods resolve only once "playback" completes, not merely once it
/// starts. By default that completion is instantaneous (a zero-duration
/// clip); set [manualCompletion] to hold the returned future open until
/// [completePlayback] or [stop] is called, so a test can observe state (e.g.
/// `isSpeaking`) while playback is still in progress.
class FakeAssistantAudioPlayer implements AssistantAudioPlayer {
  Object? playBase64Error;
  bool manualCompletion = false;
  final List<String> playedAssets = [];
  final List<String> playedBase64 = [];

  Completer<void>? _pending;

  @override
  Future<void> playAsset(String assetPath) async {
    playedAssets.add(assetPath);
    await _awaitCompletion();
  }

  @override
  Future<void> playBase64(String base64Audio) async {
    playedBase64.add(base64Audio);
    final error = playBase64Error;
    if (error != null) throw error;
    await _awaitCompletion();
  }

  Future<void> _awaitCompletion() {
    if (!manualCompletion) return Future<void>.value();
    final completer = Completer<void>();
    _pending = completer;
    return completer.future;
  }

  /// Resolves an in-flight `manualCompletion` playback, as if it finished.
  void completePlayback() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete();
    _pending = null;
  }

  @override
  Future<void> stop() async {
    completePlayback();
  }
}
