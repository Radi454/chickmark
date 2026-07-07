import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:hatchaudit/localized_material.dart';

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
    if (normalized.contains('timed out')) {
      return 'Camera took too long to start. Resume camera or use the camera app.';
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
  static const Duration _cameraInitTimeout = Duration(seconds: 5);
  static const Duration _captureCooldown = Duration(milliseconds: 400);

  CameraController? _controller;
  Future<void>? _initializeFuture;
  Timer? _initializationTimeoutTimer;
  String? _errorMessage;
  Size? _previewLayoutSize;
  DateTime? _lastCaptureAt;
  bool? _lastReadyNotification;
  bool _isInitializing = true;
  bool _cameraPaused = false;
  int _cameraGeneration = 0;

  bool get hasCameraError => _errorMessage != null;
  bool get isCameraPaused => _cameraPaused;
  bool get isCameraReady =>
      !_cameraPaused &&
      !_isInitializing &&
      _controller?.value.isInitialized == true &&
      _errorMessage == null;
  bool get isPreviewActive => isCameraReady && _previewLayoutSize != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera(notifyState: false));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_pauseCamera());
    }
  }

  Future<String?> takePicture() async {
    try {
      if (_cameraPaused || _isInitializing || _errorMessage != null) {
        return null;
      }
      await _initializeFuture;
      final controller = _controller;
      if (!mounted ||
          _cameraPaused ||
          _errorMessage != null ||
          controller == null ||
          !controller.value.isInitialized) {
        return null;
      }
      await _waitForCaptureCooldown();
      if (!mounted || _cameraPaused || _errorMessage != null) return null;
      final file = await controller.takePicture();
      _lastCaptureAt = DateTime.now();
      return file.path;
    } on CameraException catch (error) {
      _setError(error.description ?? error.code);
      return null;
    } catch (_) {
      _setError('Camera capture failed.');
      return null;
    }
  }

  Future<void> closeCameraForStationExit() async {
    _cameraGeneration++;
    _cancelInitializationTimeout();
    _initializeFuture = null;
    _notifyCameraReady(false);
    final controller = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _cameraPaused = true;
        _isInitializing = false;
        _errorMessage = null;
      });
    }
    await controller?.dispose();
  }

  Future<void> pauseCameraForIdle() => _pauseCamera();

  Future<void> _waitForCaptureCooldown() async {
    final lastCaptureAt = _lastCaptureAt;
    if (lastCaptureAt == null) return;
    final elapsed = DateTime.now().difference(lastCaptureAt);
    if (elapsed >= _captureCooldown) return;
    await Future.delayed(_captureCooldown - elapsed);
  }

  /// Configures focus/exposure near the capture frame center once after init.
  Future<void> _configureCameraForCapture(CameraController controller) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (_) {
      // Focus APIs are device-dependent; capture should still continue.
    }
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {
      // Exposure APIs are device-dependent; capture should still continue.
    }
    try {
      await controller.setFocusPoint(const Offset(0.5, 0.5));
    } catch (_) {
      // Focus point APIs are device-dependent; capture should still continue.
    }
    try {
      await controller.setExposurePoint(const Offset(0.5, 0.5));
    } catch (_) {
      // Exposure point APIs are device-dependent; capture should still continue.
    }
  }

  Future<void> _initializeCamera({bool notifyState = true}) async {
    final generation = ++_cameraGeneration;
    _notifyCameraReady(false);
    if (notifyState && mounted) {
      setState(() {
        _cameraPaused = false;
        _isInitializing = true;
        _errorMessage = null;
      });
    } else {
      _cameraPaused = false;
      _isInitializing = true;
      _errorMessage = null;
    }

    _cancelInitializationTimeout();
    _initializationTimeoutTimer = Timer(_cameraInitTimeout, () {
      if (!_isActiveGeneration(generation)) return;
      _cameraGeneration++;
      unawaited(_disposeController(notifyReady: false));
      _setError('Camera initialization timed out.');
    });
    _initializeFuture = _doInitializeCamera(generation);
    await _initializeFuture;
  }

  Future<void> _doInitializeCamera(int generation) async {
    try {
      final cameras = await availableCameras();
      if (!_isActiveGeneration(generation)) return;
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
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();

      if (!_isActiveGeneration(generation)) {
        await controller.dispose();
        return;
      }

      await _disposeController(notifyReady: false);
      if (!_isActiveGeneration(generation)) {
        await controller.dispose();
        return;
      }
      await _configureCameraForCapture(controller);
      if (!_isActiveGeneration(generation)) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _errorMessage = null;
        _isInitializing = false;
        _cameraPaused = false;
      });
      _notifyCameraReady(true);
    } on CameraException catch (error) {
      if (!_isActiveGeneration(generation)) return;
      _setError(error.description ?? error.code);
    } catch (error) {
      if (!_isActiveGeneration(generation)) return;
      _setError(error.toString());
    } finally {
      _cancelInitializationTimeout(generation);
    }
  }

  bool _isActiveGeneration(int generation) =>
      mounted && generation == _cameraGeneration && !_cameraPaused;

  void _cancelInitializationTimeout([int? generation]) {
    if (generation != null && generation != _cameraGeneration) return;
    _initializationTimeoutTimer?.cancel();
    _initializationTimeoutTimer = null;
  }

  Future<void> _disposeController({bool notifyReady = true}) async {
    final controller = _controller;
    _controller = null;
    if (notifyReady) _notifyCameraReady(false);
    await controller?.dispose();
  }

  void _setError(String message) {
    if (!mounted) return;
    _cancelInitializationTimeout();
    final friendlyMessage = InlineCameraCapture.cameraErrorMessage(message);
    setState(() {
      _errorMessage = friendlyMessage;
      _isInitializing = false;
      _cameraPaused = false;
    });
    _notifyCameraReady(false);
    widget.onCameraError?.call(friendlyMessage);
  }

  Future<void> _pauseCamera() async {
    _cameraGeneration++;
    _cancelInitializationTimeout();
    _initializeFuture = null;
    _notifyCameraReady(false);
    final controller = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _cameraPaused = true;
        _isInitializing = false;
        _errorMessage = null;
      });
    }
    await controller?.dispose();
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
    if (_cameraPaused) return _buildPausedState();
    if (_errorMessage != null) return _buildErrorState(_errorMessage!);

    if (_isInitializing ||
        controller == null ||
        !controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _previewLayoutSize = Size(constraints.maxWidth, constraints.maxHeight);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 140;
        return Container(
          color: const Color(0xFF111827),
          padding: EdgeInsets.all(compact ? 8 : 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: compact ? 24 : 36,
              ),
              SizedBox(height: compact ? 4 : 8),
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: compact ? 2 : 3,
                  style: AppTextStyles.caption.copyWith(color: Colors.white),
                ),
              ),
              SizedBox(height: compact ? 6 : 10),
              OutlinedButton(
                onPressed: () => unawaited(_initializeCamera()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withAlpha(150)),
                  minimumSize: Size(0, compact ? 30 : 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Resume camera'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPausedState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 140;
        return Container(
          color: const Color(0xFF111827),
          padding: EdgeInsets.all(compact ? 8 : 16),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.pause_circle_outline,
                    color: Colors.white,
                    size: compact ? 24 : 38,
                  ),
                  SizedBox(height: compact ? 4 : 8),
                  Text(
                    'Camera paused',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Resume when you are ready.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                  SizedBox(height: compact ? 6 : 12),
                  FilledButton(
                    onPressed: () => unawaited(_initializeCamera()),
                    style: FilledButton.styleFrom(
                      minimumSize: Size(0, compact ? 30 : 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Resume camera'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    _cameraGeneration++;
    _cancelInitializationTimeout();
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

  static const double _frameWidth = 190;
  static const double _frameHeight = 110;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _frameWidth,
      height: _frameHeight,
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
