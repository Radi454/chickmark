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

class FakeAssistantAudioPlayer implements AssistantAudioPlayer {
  Object? playBase64Error;
  final List<String> playedAssets = [];
  final List<String> playedBase64 = [];

  @override
  Future<void> playAsset(String assetPath) async {
    playedAssets.add(assetPath);
  }

  @override
  Future<void> playBase64(String base64Audio) async {
    playedBase64.add(base64Audio);
    final error = playBase64Error;
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async {}
}
