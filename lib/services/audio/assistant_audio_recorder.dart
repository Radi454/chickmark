import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records short voice questions and returns them as base64-encoded audio.
///
/// Abstracted behind this interface so widget/provider tests never touch the
/// real microphone.
abstract interface class AssistantAudioRecorder {
  /// Requests mic permission if needed and starts recording. Throws
  /// [AssistantAudioException] if permission is denied or recording could
  /// not start.
  Future<void> start();

  /// Stops recording and returns the clip as base64. Returns null if no
  /// recording was in progress, or if the clip could not be read back.
  Future<String?> stop();

  /// True while a recording is in progress.
  bool get isRecording;
}

class AssistantAudioException implements Exception {
  const AssistantAudioException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RecordAssistantAudioRecorder implements AssistantAudioRecorder {
  RecordAssistantAudioRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;

  @override
  bool get isRecording => _path != null;

  @override
  Future<void> start() async {
    if (_path != null) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const AssistantAudioException(
        'Microphone access is needed to ask by voice.',
      );
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/assistant-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _path = path;
  }

  @override
  Future<String?> stop() async {
    final wasRecording = _path != null;
    _path = null;
    if (!wasRecording) return null;
    final path = await _recorder.stop();
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    await file.delete();
    return base64Encode(bytes);
  }
}
