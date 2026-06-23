/// The narrow camera surface the [TemperatureCaptureController] depends on.
///
/// Keeping this an interface (rather than referencing `InlineCameraCapture`
/// directly) is what lets the controller be unit-tested without pulling in
/// `package:camera`. The production adapter over `InlineCameraCaptureState`
/// lives next to the screen (see `inline_camera_port.dart`); tests supply a fake.
abstract class TemperatureCameraPort {
  Future<String?> takePicture();
  bool get isCameraReady;
  bool get hasCameraError;
  Future<void> closeCameraForStationExit();
  Future<void> pauseCameraForIdle();
}
