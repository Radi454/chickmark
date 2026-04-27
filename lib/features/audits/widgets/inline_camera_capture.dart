import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class InlineCameraCapture extends StatefulWidget {
  const InlineCameraCapture({
    super.key,
    this.capturedImagePath,
    this.isScanning = true,
    this.successPulse = 0,
    this.onCameraReadyChanged,
    this.onCameraError,
  });

  final String? capturedImagePath;
  final bool isScanning;
  final int successPulse;
  final ValueChanged<bool>? onCameraReadyChanged;
  final ValueChanged<String>? onCameraError;

  static String cameraErrorMessage(String rawMessage) {
    final normalized = rawMessage.toLowerCase();
    if (normalized.contains('unable to establish connection on channel') ||
        normalized.contains('missingpluginexception') ||
        normalized.contains('cameraapi.getavailablecameras')) {
      return 'Inline camera is unavailable. Capture will open the camera app.';
    }
    if (normalized.contains('denied') || normalized.contains('permission')) {
      return 'Camera permission is needed. Use the camera app or enable camera access.';
    }
    if (normalized.contains('no camera')) {
      return 'No camera found. Use the camera app fallback.';
    }
    if (normalized.contains('capture failed')) {
      return 'Camera capture failed. Try again or use the camera app.';
    }
    return 'Camera unavailable. Capture will open the camera app.';
  }

  @override
  State<InlineCameraCapture> createState() => InlineCameraCaptureState();
}

class InlineCameraCaptureState extends State<InlineCameraCapture>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  String? _errorMessage;
  bool? _lastReadyNotification;

  bool get hasCameraError => _errorMessage != null;
  bool get isCameraReady =>
      _controller?.value.isInitialized == true && _errorMessage == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null) return;

    if (state == AppLifecycleState.inactive) {
      _disposeController();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<String?> takePicture() async {
    try {
      await _initializeFuture;
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return null;
      final file = await controller.takePicture();
      return file.path;
    } on CameraException catch (error) {
      _setError(error.description ?? error.code);
      return null;
    } catch (_) {
      _setError('Camera capture failed.');
      return null;
    }
  }

  Future<String?> takePictureForAutoScan() => takePicture();

  Future<void> _initializeCamera() async {
    _initializeFuture = _doInitializeCamera();
    await _initializeFuture;
  }

  Future<void> _doInitializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setError('No camera found. Use the camera app fallback.');
        return;
      }

      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      await _disposeController(notifyReady: false);
      setState(() {
        _controller = controller;
        _errorMessage = null;
      });
      _notifyCameraReady(true);
    } on CameraException catch (error) {
      _setError(error.description ?? error.code);
    } catch (error) {
      _setError(error.toString());
    }
  }

  Future<void> _disposeController({bool notifyReady = true}) async {
    final controller = _controller;
    _controller = null;
    if (notifyReady) _notifyCameraReady(false);
    await controller?.dispose();
  }

  void _setError(String message) {
    if (!mounted) return;
    final friendlyMessage = InlineCameraCapture.cameraErrorMessage(message);
    setState(() => _errorMessage = friendlyMessage);
    _notifyCameraReady(false);
    widget.onCameraError?.call(friendlyMessage);
  }

  void _notifyCameraReady(bool isReady) {
    if (_lastReadyNotification == isReady) return;
    _lastReadyNotification = isReady;
    widget.onCameraReadyChanged?.call(isReady);
  }

  @override
  Widget build(BuildContext context) {
    final capturedImagePath = widget.capturedImagePath;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (capturedImagePath != null)
          Image.file(File(capturedImagePath), fit: BoxFit.cover)
        else
          _buildLivePreview(),
        _buildScanFrame(isScanning: widget.isScanning),
        if (widget.successPulse > 0)
          _SuccessPulse(key: ValueKey(widget.successPulse)),
      ],
    );
  }

  Widget _buildLivePreview() {
    final controller = _controller;
    if (_errorMessage != null) return _buildErrorState(_errorMessage!);

    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = controller.value.previewSize;
        if (previewSize == null) return CameraPreview(controller);

        final isPortrait =
            MediaQuery.orientationOf(context) == Orientation.portrait;
        final previewWidth = isPortrait
            ? previewSize.height
            : previewSize.width;
        final previewHeight = isPortrait
            ? previewSize.width
            : previewSize.height;

        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewWidth,
              height: previewHeight,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildScanFrame({required bool isScanning}) {
    return IgnorePointer(
      child: Center(
        child: isScanning
            ? const _PulsingScanFrame()
            : const _StaticScanFrame(),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeController(notifyReady: false);
    super.dispose();
  }
}

class _PulsingScanFrame extends StatefulWidget {
  const _PulsingScanFrame();

  @override
  State<_PulsingScanFrame> createState() => _PulsingScanFrameState();
}

class _PulsingScanFrameState extends State<_PulsingScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = Curves.easeInOut.transform(_controller.value);
        return Transform.scale(
          scale: 0.985 + (value * 0.035),
          child: Opacity(opacity: 0.82 + (value * 0.18), child: child),
        );
      },
      child: const _StaticScanFrame(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _StaticScanFrame extends StatelessWidget {
  const _StaticScanFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 128,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.greenTab, width: 2.4),
        boxShadow: [
          BoxShadow(
            color: AppColors.greenTab.withAlpha(90),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _SuccessPulse extends StatelessWidget {
  const _SuccessPulse({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      builder: (context, value, child) {
        final opacity = value < 0.2 ? value / 0.2 : 1 - ((value - 0.2) / 0.8);
        return Opacity(
          opacity: opacity.clamp(0, 1).toDouble(),
          child: Transform.scale(scale: 0.78 + (0.28 * value), child: child),
        );
      },
      child: Center(
        child: Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: AppColors.greenTab,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.greenTab.withAlpha(110),
                blurRadius: 28,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(Icons.check, color: Colors.white, size: 46),
        ),
      ),
    );
  }
}
