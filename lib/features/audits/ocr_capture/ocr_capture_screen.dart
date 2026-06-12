import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/ocr/ocr_service.dart';
import '../../../services/photo/photo_service.dart';
import '../models/est_grid_data.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/est_grid_widget.dart';
import '../widgets/inline_camera_capture.dart';
import 'inline_camera_port.dart';
import 'ocr_capture_config.dart';
import 'ocr_capture_controller.dart';
import 'ocr_capture_result.dart';

/// Reusable full-screen OCR capture flow: live camera + tappable grid + confirm
/// /manual entry + Prev/Next, returning an [OcrCaptureResult] via `Navigator.pop`.
///
/// All sites (egg storage EST, setter EST, hatcher/CVT) push this with a
/// site-specific [OcrCaptureConfig]; persistence stays in the caller.
class OcrCaptureScreen extends StatefulWidget {
  const OcrCaptureScreen({
    super.key,
    required this.config,
    this.ocrService,
    this.photoService,
    this.controller,
    this.cameraBuilder,
  });

  final OcrCaptureConfig config;

  /// Used to build the controller when [controller] is not supplied.
  final OcrService? ocrService;
  final PhotoService? photoService;

  /// Test/override hook — when supplied, the screen drives this controller
  /// instead of constructing one (and skips building the real camera port).
  final OcrCaptureController? controller;

  /// Test/override hook — replaces the live camera widget (avoids `package:camera`).
  final Widget Function(GlobalKey<InlineCameraCaptureState> key)? cameraBuilder;

  @override
  State<OcrCaptureScreen> createState() => _OcrCaptureScreenState();
}

class _OcrCaptureScreenState extends State<OcrCaptureScreen> {
  final GlobalKey<InlineCameraCaptureState> _cameraKey = GlobalKey();
  late final OcrCaptureController _controller;
  late final bool _ownsController;
  final TextEditingController _manualController = TextEditingController();
  final Map<String, TextEditingController> _gridControllers = {};
  final Map<String, FocusNode> _gridFocus = {};

  @override
  void initState() {
    super.initState();
    final provided = widget.controller;
    if (provided != null) {
      _controller = provided;
      _ownsController = false;
    } else {
      final ocr = widget.ocrService ?? OcrService();
      _controller = OcrCaptureController(
        config: widget.config,
        recognizeCelsius: (path, crop) => ocr.recognizeThermoScanReadingCelsius(
          path,
          cropFrame: crop,
          fanOutVariants: false,
        ),
        photoService: widget.photoService ?? PhotoService(),
        cameraPort: InlineCameraPort(_cameraKey),
      );
      _ownsController = true;
    }

    for (final key in EstGridData.scanKeys) {
      _gridControllers[key] = TextEditingController(
        text: _formatReading(_controller.readings[key]),
      );
      _gridFocus[key] = FocusNode();
    }
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    _manualController.dispose();
    for (final c in _gridControllers.values) {
      c.dispose();
    }
    for (final f in _gridFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _onControllerChanged() {
    for (final key in EstGridData.scanKeys) {
      final text = _formatReading(_controller.readings[key]);
      if (_gridControllers[key]!.text != text) {
        _gridControllers[key]!.text = text;
      }
    }
    if (mounted) setState(() {});
  }

  String _formatReading(double? value) =>
      value == null ? '' : value.toStringAsFixed(1);

  void _onCameraReady(bool ready) {
    if (ready) _controller.startAutoScan();
  }

  void _onCameraError(String _) {
    if (mounted) setState(() {});
  }

  Future<void> _finishAndPop() async {
    final result = _controller.result();
    await _cameraKey.currentState?.closeCameraForStationExit();
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return PopScope<OcrCaptureResult>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _finishAndPop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.config.title)),
        bottomNavigationBar: _buildBottomBar(c),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Camera sized so the header, controls card, and full grid all
              // fit the lower half without scrolling.
              final cameraHeight = (constraints.maxHeight * 0.36).clamp(
                190.0,
                380.0,
              );
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: cameraHeight,
                        width: double.infinity,
                        child: _buildCamera(c),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildHeader(c),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _buildStateArea(c),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: EstGridWidget(
                          controllers: _gridControllers,
                          focusNodes: _gridFocus,
                          photos: Map<String, String?>.from(c.photos),
                          enabled: false,
                          highlightedKey: c.currentKey,
                          showPhotoCapture: false,
                          compact: true,
                          onValueChanged: (_, _) {},
                          onPhotoCaptured: (_, _) {},
                          onCellSelected: c.isReadOnly ? null : c.selectKey,
                          tempStatusFn: widget.config.tempStatusFn,
                          tempZoneFn: widget.config.tempZoneFn,
                          unitSuffix: widget.config.unitSuffix,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCamera(OcrCaptureController c) {
    if (widget.cameraBuilder != null) return widget.cameraBuilder!(_cameraKey);
    return InlineCameraCapture(
      key: _cameraKey,
      capturedImagePath: c.capture.capturedImagePath,
      isScanning: c.capture.capturedImagePath == null,
      onCameraReadyChanged: _onCameraReady,
      onCameraError: _onCameraError,
    );
  }

  Widget _buildHeader(OcrCaptureController c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      c.labelFor(c.currentKey),
                      style: AppTextStyles.heading.copyWith(fontSize: 18),
                    ),
                  ),
                  Text(
                    'Step ${c.activeIndex + 1} of ${c.totalCells}',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: c.totalCells == 0
                    ? 0
                    : (c.activeIndex + 1) / c.totalCells,
                minHeight: 4,
                borderRadius: BorderRadius.circular(999),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStateArea(OcrCaptureController c) {
    if (c.isReadOnly) {
      return _hint(c, 'View only.');
    }
    if (c.manualEntryActive) return _buildManualEntry(c);

    final cap = c.capture;
    final isReview = cap.capturedImagePath != null && c.pendingValue != null;
    if (isReview) return _buildReviewCard(c);

    final savedValue = c.readings[c.currentKey];
    if (savedValue != null) return _buildSavedCard(c, savedValue);

    return _buildScanningCard(c);
  }

  Widget _card({required Key key, required Widget child}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withAlpha(60)),
      ),
      child: child,
    );
  }

  Widget _hint(OcrCaptureController c, String fallback) {
    return _card(
      key: const ValueKey('ocr-state-readonly'),
      child: Text(
        c.capture.errorMessage ?? fallback,
        style: AppTextStyles.caption.copyWith(color: Colors.grey[700]),
      ),
    );
  }

  Widget _buildScanningCard(OcrCaptureController c) {
    final scanning = c.capture.isAutoScanning;
    return _card(
      key: const ValueKey('ocr-state-scanning'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.capture.errorMessage ?? 'Scanning for temperature…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: scanning ? c.stopAutoScan : c.startAutoScan,
                  icon: Icon(
                    scanning ? Icons.pause : Icons.play_arrow,
                    size: 18,
                  ),
                  label: Text(scanning ? 'Pause' : 'Resume'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: c.captureOnce,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Capture'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: c.captureViaNativeCamera,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Camera app'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _enterManual(c, ''),
                  icon: const Icon(Icons.keyboard, size: 18),
                  label: const Text('Manual'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(OcrCaptureController c) {
    return _card(
      key: const ValueKey('ocr-state-review'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              'Is this reading correct?',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              '${c.pendingValue!.toStringAsFixed(1)}${widget.config.unitSuffix}',
              style: AppTextStyles.heading.copyWith(
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    c.confirm();
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: c.retake,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: () => _enterManual(
                c,
                c.pendingValue!.toStringAsFixed(1),
                reject: true,
              ),
              icon: const Icon(Icons.keyboard, size: 18),
              label: const Text('Enter manually'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedCard(OcrCaptureController c, double value) {
    return _card(
      key: const ValueKey('ocr-state-saved'),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.greenTab),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Saved ${value.toStringAsFixed(1)}${widget.config.unitSuffix}',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton.icon(
            onPressed: () => _enterManual(c, value.toStringAsFixed(1)),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
          TextButton.icon(
            onPressed: c.retake,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Rescan'),
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntry(OcrCaptureController c) {
    return _card(
      key: const ValueKey('ocr-state-manual'),
      child: AuditNumericKeyboardScope(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter reading manually',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            AuditNumericField(
              controller: _manualController,
              allowDecimal: true,
              maxDecimalPlaces: 1,
              decoration: InputDecoration(
                suffixText: widget.config.unitSuffix,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _saveManual(c),
                    icon: const Icon(Icons.check),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: c.cancelManualEntry,
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(OcrCaptureController c) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: c.hasPrevious ? c.previous : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: c.hasNext ? c.next : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Next'),
              ),
              const SizedBox(width: 24),
              FilledButton.icon(
                onPressed: _finishAndPop,
                icon: const Icon(Icons.done),
                label: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _enterManual(
    OcrCaptureController c,
    String initial, {
    bool reject = false,
  }) {
    _manualController.text = initial;
    if (reject) {
      c.rejectToManual();
    } else {
      c.beginManualEntry();
    }
  }

  void _saveManual(OcrCaptureController c) {
    final value = double.tryParse(_manualController.text.trim());
    if (value == null) return;
    c.commitManualEntry(value);
  }
}
