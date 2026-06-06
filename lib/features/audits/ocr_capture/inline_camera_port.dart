import 'package:flutter/widgets.dart';

import '../../../services/ocr/ocr_service.dart' show ThermoScanCropFrame;
import '../widgets/inline_camera_capture.dart';
import 'ocr_camera_port.dart';

/// Production [OcrCameraPort] that forwards to a live [InlineCameraCapture]
/// addressed by its [GlobalKey]. Lives apart from [OcrCaptureController] so the
/// controller's import graph never reaches `package:camera`.
class InlineCameraPort implements OcrCameraPort {
  InlineCameraPort(this._key);

  final GlobalKey<InlineCameraCaptureState> _key;
  InlineCameraCaptureState? get _state => _key.currentState;

  @override
  Future<String?> takePicture() async => _state?.takePicture();

  @override
  Future<String?> takePictureForAutoScan() async =>
      _state?.takePictureForAutoScan();

  @override
  ThermoScanCropFrame? get ocrCropFrame => _state?.ocrCropFrame;

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
