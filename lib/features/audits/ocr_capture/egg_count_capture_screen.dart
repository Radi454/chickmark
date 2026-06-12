import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/ocr/egg_count_ocr_service.dart';
import '../../../services/photo/photo_service.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/inline_camera_capture.dart';
import 'egg_count_capture_controller.dart';
import 'egg_count_capture_result.dart';
import 'inline_camera_port.dart';

class EggCountCaptureScreen extends StatefulWidget {
  const EggCountCaptureScreen({
    super.key,
    this.title = 'Egg count',
    this.initialCount = 0,
    this.initialPhotos = const [],
    this.ocrService,
    this.photoService,
    this.controller,
    this.cameraBuilder,
  });

  final String title;
  final int initialCount;
  final List<String> initialPhotos;
  final EggCountOcrService? ocrService;
  final PhotoService? photoService;
  final EggCountCaptureController? controller;
  final Widget Function(GlobalKey<InlineCameraCaptureState> key)? cameraBuilder;

  @override
  State<EggCountCaptureScreen> createState() => _EggCountCaptureScreenState();
}

class _EggCountCaptureScreenState extends State<EggCountCaptureScreen> {
  final GlobalKey<InlineCameraCaptureState> _cameraKey = GlobalKey();
  final TextEditingController _manualController = TextEditingController();
  late final EggCountCaptureController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    final provided = widget.controller;
    if (provided != null) {
      _controller = provided;
      _ownsController = false;
    } else {
      final service = widget.ocrService ?? const EggCountOcrService();
      _controller = EggCountCaptureController(
        title: widget.title,
        initialCount: widget.initialCount,
        initialPhotos: widget.initialPhotos,
        analyzeEggCount: service.analyzeEggCount,
        photoService: widget.photoService ?? PhotoService(),
        cameraPort: InlineCameraPort(_cameraKey),
      );
      _ownsController = true;
    }
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _finishAndPop() async {
    await _cameraKey.currentState?.closeCameraForStationExit();
    if (mounted) Navigator.of(context).pop(_controller.result());
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return PopScope<EggCountCaptureResult>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _finishAndPop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(c.title)),
        bottomNavigationBar: _buildBottomBar(c),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cameraHeight = (constraints.maxHeight * 0.35).clamp(
                160.0,
                430.0,
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
                        child: _buildCamera(c),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildTotalHeader(c),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _buildStateArea(c),
                    ),
                    const SizedBox(height: 10),
                    Expanded(child: _buildPhotoStrip(c)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCamera(EggCountCaptureController c) {
    if (widget.cameraBuilder != null) return widget.cameraBuilder!(_cameraKey);
    return InlineCameraCapture(
      key: _cameraKey,
      capturedImagePath: c.pendingPhotoPath,
      isScanning: !c.isProcessing,
    );
  }

  Widget _buildTotalHeader(EggCountCaptureController c) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Total ${c.totalCount} eggs',
            style: AppTextStyles.heading.copyWith(fontSize: 20),
          ),
        ),
        Text(
          '${c.photos.length} photo${c.photos.length == 1 ? '' : 's'}',
          style: AppTextStyles.caption.copyWith(
            color: Colors.grey[700],
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildStateArea(EggCountCaptureController c) {
    if (c.manualEntryActive) return _buildManualEntry(c);
    if (c.isProcessing) return _hint('Counting eggs…');
    if (c.pendingPhotoPath != null && c.pendingCount != null) {
      return _buildReviewCard(c);
    }
    return _buildCaptureCard(c);
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

  Widget _hint(String text) {
    return _card(
      key: const ValueKey('egg-count-state-hint'),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(
          color: Colors.grey[800],
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCaptureCard(EggCountCaptureController c) {
    return _card(
      key: const ValueKey('egg-count-state-capture'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            c.message ?? 'Capture each photo for this breakout item.',
            style: AppTextStyles.caption.copyWith(
              color: Colors.grey[800],
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: c.captureOnce,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Capture'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: c.captureViaNativeCamera,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Camera app'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: () => _enterManual(c, c.totalCount.toString()),
              icon: const Icon(Icons.keyboard, size: 18),
              label: const Text('Set total manually'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(EggCountCaptureController c) {
    final confidence = switch (c.pendingConfidence) {
      EggCountOcrConfidence.high => 'high',
      EggCountOcrConfidence.medium => 'medium',
      EggCountOcrConfidence.low => 'low',
      EggCountOcrConfidence.none => 'manual',
    };
    return _card(
      key: const ValueKey('egg-count-state-review'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              'Is this count correct?',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${c.pendingCount} eggs',
              style: AppTextStyles.heading.copyWith(
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Center(
            child: Text(
              'Confidence: $confidence',
              style: AppTextStyles.caption.copyWith(color: Colors.grey[700]),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    c.confirmPending();
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
              onPressed: () => _enterManual(c, c.pendingCount.toString()),
              icon: const Icon(Icons.keyboard, size: 18),
              label: const Text('Enter manually'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntry(EggCountCaptureController c) {
    return _card(
      key: const ValueKey('egg-count-state-manual'),
      child: AuditNumericKeyboardScope(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.pendingPhotoPath == null
                  ? 'Set total count manually'
                  : 'Enter this photo count',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            AuditNumericField(
              controller: _manualController,
              allowDecimal: false,
              decoration: InputDecoration(
                suffixText: 'eggs',
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

  Widget _buildPhotoStrip(EggCountCaptureController c) {
    if (c.photos.isEmpty) {
      return Center(
        child: Text(
          'No confirmed photos yet.',
          style: AppTextStyles.caption.copyWith(color: Colors.grey[700]),
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 96,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: c.photos.length,
      itemBuilder: (context, index) {
        final path = c.photos[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: IconButton.filled(
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                onPressed: () => c.removePhoto(index),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(EggCountCaptureController c) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: c.isProcessing ? null : c.captureOnce,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add photo'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _finishAndPop,
                icon: const Icon(Icons.done),
                label: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _enterManual(EggCountCaptureController c, String initial) {
    _manualController.text = initial;
    c.pendingPhotoPath == null ? c.beginManualEntry() : c.rejectToManual();
  }

  void _saveManual(EggCountCaptureController c) {
    final value = int.tryParse(_manualController.text.trim());
    if (value == null) return;
    c.commitManualCount(value);
  }
}
