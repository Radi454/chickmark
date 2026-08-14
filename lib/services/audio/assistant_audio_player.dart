import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';

/// Plays short assistant audio clips: the bundled filler chime and the TTS
/// reply returned by the server. Abstracted so tests never touch a real
/// audio device.
abstract interface class AssistantAudioPlayer {
  /// [assetPath] is relative to the `assets/` prefix, e.g. `audio/filler_chime.wav`.
  Future<void> playAsset(String assetPath);
  Future<void> playBase64(String base64Audio);
  Future<void> stop();
}

class AudioplayersAssistantAudioPlayer implements AssistantAudioPlayer {
  AudioplayersAssistantAudioPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> playAsset(String assetPath) async {
    await _player.stop();
    await _player.play(AssetSource(assetPath));
  }

  @override
  Future<void> playBase64(String base64Audio) async {
    await _player.stop();
    await _player.play(BytesSource(base64Decode(base64Audio)));
  }

  @override
  Future<void> stop() => _player.stop();
}
