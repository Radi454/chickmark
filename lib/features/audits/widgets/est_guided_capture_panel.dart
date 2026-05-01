import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/est_guided_capture_state.dart';
import '../models/est_grid_data.dart';
import 'audit_numeric_keyboard.dart';

class EstGuidedCapturePanel extends StatefulWidget {
  const EstGuidedCapturePanel({
    super.key,
    required this.state,
    required this.valueController,
    required this.preview,
    required this.onCapture,
    required this.onUseNativeCamera,
    required this.onAutoScan,
    required this.onStopAutoScan,
    required this.onRetake,
    required this.onSkip,
    required this.onFinish,
    required this.onValueChanged,
    required this.onConfirm,
    required this.onRejectAutoScanReading,
    this.useCameraAppForCapture = false,
    this.canAutoScan = true,
    this.isConfirming = false,
  });

  final EstGuidedCaptureState state;
  final TextEditingController valueController;
  final Widget preview;
  final VoidCallback onCapture;
  final VoidCallback onUseNativeCamera;
  final VoidCallback onAutoScan;
  final VoidCallback onStopAutoScan;
  final VoidCallback onRetake;
  final VoidCallback onSkip;
  final VoidCallback onFinish;
  final ValueChanged<double?> onValueChanged;
  final VoidCallback onConfirm;
  final VoidCallback onRejectAutoScanReading;
  final bool useCameraAppForCapture;
  final bool canAutoScan;
  final bool isConfirming;

  @override
  State<EstGuidedCapturePanel> createState() => _EstGuidedCapturePanelState();
}

class _EstGuidedCapturePanelState extends State<EstGuidedCapturePanel> {
  bool _isEditingReading = false;
  String? _editError;

  @override
  void didUpdateWidget(covariant EstGuidedCapturePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.currentKey != widget.state.currentKey ||
        oldWidget.state.capturedImagePath != widget.state.capturedImagePath) {
      _isEditingReading = false;
      _editError = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReview =
        widget.state.capturedImagePath != null && widget.state.ocrValue != null;
    final isBusy = widget.state.isProcessing || widget.state.isOcrProcessing;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final previewHeight = constraints.maxWidth >= 640 ? 232.0 : 196.0;
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: double.infinity,
                  height: previewHeight,
                  child: widget.preview,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _TargetHeader(
            targetLabel: _targetLabel(widget.state.currentKey),
            currentStep: widget.state.currentStep,
            totalSteps: widget.state.totalSteps,
            onFinish: isBusy ? null : widget.onFinish,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: widget.state.currentStep / widget.state.totalSteps,
            minHeight: 5,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: isReview
                ? _buildReviewState(context, isBusy)
                : _buildScanningState(isBusy),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningState(bool isBusy) {
    final showAutoScan = widget.canAutoScan && !widget.useCameraAppForCapture;
    final isAutoScanning = widget.state.isAutoScanning;
    final canToggleScan =
        showAutoScan && !isBusy && !widget.state.isCurrentPointConfirmed;

    return Column(
      key: ValueKey(
        'scanning-${widget.state.currentKey}-${widget.state.isAutoScanning}',
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scanning for temperature...',
          style: AppTextStyles.body.copyWith(
            color: Colors.grey[700],
            fontWeight: FontWeight.w700,
          ),
        ),
        if (widget.state.errorMessage != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.state.errorMessage!,
            style: AppTextStyles.caption.copyWith(color: Colors.grey[600]),
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text(
            'Hold steady · keep display sharp',
            style: AppTextStyles.caption.copyWith(color: Colors.grey[600]),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (showAutoScan)
              FilledButton.icon(
                onPressed: canToggleScan
                    ? (isAutoScanning
                          ? widget.onStopAutoScan
                          : widget.onAutoScan)
                    : null,
                icon: isBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(isAutoScanning ? Icons.pause : Icons.play_arrow),
                label: Text(isAutoScanning ? 'Pause' : 'Resume'),
              ),
            TextButton.icon(
              onPressed: isBusy ? null : widget.onCapture,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Capture once'),
            ),
            TextButton.icon(
              onPressed: isBusy ? null : widget.onUseNativeCamera,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Camera app'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: isBusy ? null : widget.onSkip,
            icon: const Icon(Icons.skip_next, size: 18),
            label: const Text('Skip'),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewState(BuildContext context, bool isBusy) {
    final parsedEditedValue = double.tryParse(
      widget.valueController.text.trim(),
    );
    final hasInvalidEdit = _isEditingReading && parsedEditedValue == null;
    final effectiveEditError = hasInvalidEdit
        ? (_editError ?? 'Enter a valid temperature')
        : _editError;
    final canConfirm =
        widget.state.canConfirm &&
        !hasInvalidEdit &&
        !isBusy &&
        !widget.isConfirming;

    return Column(
      key: ValueKey(
        'review-${widget.state.currentKey}-${widget.state.capturedImagePath}',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            'Is this reading correct?',
            style: AppTextStyles.body.copyWith(
              color: Colors.grey[700],
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.greenTab.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.greenTab.withAlpha(80)),
          ),
          child: _isEditingReading
              ? _buildEditableReading()
              : _buildReadOnlyReading(),
        ),
        if (_isEditingReading && effectiveEditError != null) ...[
          const SizedBox(height: 6),
          Text(
            effectiveEditError,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: Colors.red[700]),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: canConfirm
                    ? () {
                        HapticFeedback.lightImpact();
                        widget.onConfirm();
                      }
                    : null,
                icon: widget.isConfirming
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Confirm'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isBusy || widget.isConfirming
                    ? null
                    : widget.onRejectAutoScanReading,
                icon: const Icon(Icons.close),
                label: const Text('Try again'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(
            onPressed: isBusy || widget.isConfirming ? null : widget.onRetake,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retake'),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyReading() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          widget.state.ocrValue!.toStringAsFixed(1),
          style: AppTextStyles.heading.copyWith(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            '°C',
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Tooltip(
            message: 'Edit reading',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: () {
                widget.valueController.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: widget.valueController.text.length,
                );
                setState(() {
                  _isEditingReading = true;
                  _editError = _validateEditedReading();
                });
              },
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditableReading() {
    return AuditNumericKeyboardScope(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: AuditNumericField(
          controller: widget.valueController,
          allowDecimal: true,
          maxDecimalPlaces: 1,
          textAlign: TextAlign.center,
          style: AppTextStyles.heading.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
          decoration: InputDecoration(
            suffixText: '°C',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          onChanged: (_) {
            final parsed = double.tryParse(widget.valueController.text.trim());
            setState(() {
              _editError = parsed == null ? 'Enter a valid temperature' : null;
            });
            if (parsed != null) widget.onValueChanged(parsed);
          },
        ),
      ),
    );
  }

  String? _validateEditedReading() {
    return double.tryParse(widget.valueController.text.trim()) == null
        ? 'Enter a valid temperature'
        : null;
  }

  String _targetLabel(String key) {
    final parts = key.split('_');
    if (parts.length != 2) return key;
    return '${EstGridData.label(parts[0])} - ${EstGridData.label(parts[1])}';
  }
}

class _TargetHeader extends StatelessWidget {
  const _TargetHeader({
    required this.targetLabel,
    required this.currentStep,
    required this.totalSteps,
    required this.onFinish,
  });

  final String targetLabel;
  final int currentStep;
  final int totalSteps;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(targetLabel),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  targetLabel,
                  style: AppTextStyles.heading.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 2),
                Text(
                  'Step $currentStep of $totalSteps',
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        TextButton(onPressed: onFinish, child: const Text('Finish')),
      ],
    );
  }
}
