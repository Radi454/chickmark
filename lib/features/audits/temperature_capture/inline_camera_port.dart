import 'package:flutter/widgets.dart';

import '../widgets/inline_camera_capture.dart';
import 'temperature_camera_port.dart';

/// Production [TemperatureCameraPort] that forwards to a live [InlineCameraCapture]
/// addressed by its [GlobalKey]. Lives apart from [TemperatureCaptureController] so the
/// controller's import graph never reaches `package:camera`.
class InlineCameraPort implements TemperatureCameraPort {
  InlineCameraPort(this._key);

  final GlobalKey<InlineCameraCaptureState> _key;
  InlineCameraCaptureState? get _state => _key.currentState;

  @override
  Future<String?> takePicture() async => _state?.takePicture();

  @override
  bool get isCameraReady => _state?.isCameraReady ?? false;

  @override
  bool get hasCameraError => _state?.hasCameraError ?? false;

  @override
  Future<void> closeCameraForStationExit() async =>
      _state?.closeCameraForStationExit();

  @override
  Future<void> pauseCameraForIdle() async => _state?.pauseCameraForIdle();
}
