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
  AudioplayersAssistantAudioPlayer({AudioPlayer? player}) : _injected = player;

  final AudioPlayer? _injected;

  // Created lazily (rather than in the initializer list) so constructing an
  // AssistantProvider with the default audio player never touches a platform
  // channel until playback is actually requested — otherwise every provider
  // built without an injected fake (including in plain, non-widget unit
  // tests) would throw for lack of a Flutter binding.
  AudioPlayer? _player;
  AudioPlayer get _playerInstance => _injected ?? (_player ??= AudioPlayer());

  @override
  Future<void> playAsset(String assetPath) async {
    await _playerInstance.stop();
    await _playerInstance.play(AssetSource(assetPath));
  }

  @override
  Future<void> playBase64(String base64Audio) async {
    await _playerInstance.stop();
    await _playerInstance.play(BytesSource(base64Decode(base64Audio)));
  }

  @override
  Future<void> stop() => _playerInstance.stop();
}
