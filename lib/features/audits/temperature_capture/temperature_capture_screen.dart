import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/photo/photo_service.dart';
import '../models/est_grid_data.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/est_grid_widget.dart';
import '../widgets/inline_camera_capture.dart';
import 'inline_camera_port.dart';
import 'temperature_capture_config.dart';
import 'temperature_capture_controller.dart';
import 'temperature_capture_result.dart';

/// Reusable full-screen temperature capture flow: live camera, tappable grid,
/// manual reading entry, serial auto-advance, and dirty-only result return.
class TemperatureCaptureScreen extends StatefulWidget {
  const TemperatureCaptureScreen({
    super.key,
    required this.config,
    this.photoService,
    this.controller,
    this.cameraBuilder,
  });

  final TemperatureCaptureConfig config;
  final PhotoService? photoService;

  /// Test/override hook. When supplied, the screen drives this controller
  /// instead of constructing one with the live camera adapter.
  final TemperatureCaptureController? controller;

  /// Test/override hook that replaces the live camera widget.
  final Widget Function(GlobalKey<InlineCameraCaptureState> key)? cameraBuilder;

  @override
  State<TemperatureCaptureScreen> createState() =>
      _TemperatureCaptureScreenState();
}

class _TemperatureCaptureScreenState extends State<TemperatureCaptureScreen> {
  final GlobalKey<InlineCameraCaptureState> _cameraKey = GlobalKey();
  late final TemperatureCaptureController _controller;
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
      _controller = TemperatureCaptureController(
        config: widget.config,
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
    if (_controller.manualEntryActive) {
      _manualController.text = _formatReading(
        _controller.readings[_controller.currentKey],
      );
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

  Future<void> _finishAndPop() async {
    final result = _controller.result();
    final cameraState = _cameraKey.currentState;
    if (mounted) Navigator.of(context).pop(result);
    unawaited(cameraState?.closeCameraForStationExit() ?? Future.value());
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return PopScope<TemperatureCaptureResult>(
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
              final cameraHeight = (constraints.maxHeight * 0.30).clamp(
                150.0,
                340.0,
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

  Widget _buildCamera(TemperatureCaptureController c) {
    if (widget.cameraBuilder != null) return widget.cameraBuilder!(_cameraKey);
    return InlineCameraCapture(
      key: _cameraKey,
      capturedImagePath: c.pendingPhotoPath,
      isScanning: c.capture.capturedImagePath == null,
      onCameraError: (_) {
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildHeader(TemperatureCaptureController c) {
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

  Widget _buildStateArea(TemperatureCaptureController c) {
    if (c.isReadOnly) return _hint(c, 'View only.');
    if (c.manualEntryActive) return _buildManualEntry(c);

    final savedValue = c.readings[c.currentKey];
    if (savedValue != null) return _buildSavedCard(c, savedValue);

    return _buildReadyCard(c);
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

  Widget _hint(TemperatureCaptureController c, String fallback) {
    return _card(
      key: const ValueKey('temperature-state-readonly'),
      child: Text(
        c.capture.errorMessage ?? fallback,
        style: AppTextStyles.caption.copyWith(color: Colors.grey[700]),
      ),
    );
  }

  Widget _buildReadyCard(TemperatureCaptureController c) {
    return _card(
      key: const ValueKey('temperature-state-ready'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.capture.errorMessage ?? 'Take a photo, then enter the reading.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _manualController.clear();
                c.captureOnce();
              },
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Take photo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedCard(TemperatureCaptureController c, double value) {
    return _card(
      key: const ValueKey('temperature-state-saved'),
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
            label: const Text('Retake'),
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntry(TemperatureCaptureController c) {
    final hasPhoto =
        c.pendingPhotoPath != null && c.pendingPhotoPath!.isNotEmpty;
    return _card(
      key: const ValueKey('temperature-state-manual'),
      child: AuditNumericKeyboardScope(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter reading manually',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              hasPhoto ? 'Photo captured for this point.' : 'Photo required.',
              style: AppTextStyles.caption.copyWith(
                color: hasPhoto ? AppColors.greenTab : Colors.orange[800],
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            AuditNumericField(
              controller: _manualController,
              allowDecimal: true,
              maxDecimalPlaces: 1,
              doneAction: true,
              onSubmitted: (_) => _saveManual(c),
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
                    label: const Text('Save point'),
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

  Widget _buildBottomBar(TemperatureCaptureController c) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _finishAndPop,
            icon: const Icon(Icons.done),
            label: const Text('Done'),
          ),
        ),
      ),
    );
  }

  void _enterManual(TemperatureCaptureController c, String initial) {
    _manualController.text = initial;
    c.beginManualEntry();
  }

  void _saveManual(TemperatureCaptureController c) {
    final value = double.tryParse(_manualController.text.trim());
    if (value == null) return;
    c.commitManualEntry(value);
  }
}
