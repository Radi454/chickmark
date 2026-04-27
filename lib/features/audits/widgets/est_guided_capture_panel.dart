import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/est_guided_capture_state.dart';
import '../models/est_grid_data.dart';

class EstGuidedCapturePanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isReview = state.capturedImagePath != null && state.ocrValue != null;
    final isBusy = state.isProcessing || state.isOcrProcessing;

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
              final previewHeight = constraints.maxWidth >= 640 ? 240.0 : 188.0;
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: double.infinity,
                  height: previewHeight,
                  child: preview,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _TargetHeader(
            targetLabel: _targetLabel(state.currentKey),
            currentStep: state.currentStep,
            totalSteps: state.totalSteps,
            onFinish: isBusy ? null : onFinish,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: state.currentStep / state.totalSteps,
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
    final showAutoScan = canAutoScan && !useCameraAppForCapture;

    return Column(
      key: ValueKey('scanning-${state.currentKey}-${state.isAutoScanning}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scanning for temperature...',
          style: AppTextStyles.body.copyWith(
            color: Colors.grey[700],
            fontWeight: FontWeight.w700,
          ),
        ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 4),
          Text(
            state.errorMessage!,
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
                onPressed: isBusy || state.isAutoScanning ? null : onAutoScan,
                icon: isBusy || state.isAutoScanning
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.center_focus_strong),
                label: const Text('Auto scan'),
              ),
            FilledButton.icon(
              onPressed: isBusy ? null : onCapture,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Capture'),
            ),
            TextButton.icon(
              onPressed: isBusy ? null : onUseNativeCamera,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Camera app'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: isBusy ? null : onSkip,
            icon: const Icon(Icons.skip_next, size: 18),
            label: const Text('Skip'),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewState(BuildContext context, bool isBusy) {
    final canConfirm = state.canConfirm && !isBusy && !isConfirming;

    return Column(
      key: ValueKey('review-${state.currentKey}-${state.capturedImagePath}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            'Confirm reading',
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                state.ocrValue!.toStringAsFixed(1),
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
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: canConfirm
                    ? () {
                        HapticFeedback.lightImpact();
                        onConfirm();
                      }
                    : null,
                icon: isConfirming
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Right'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isBusy || isConfirming
                    ? null
                    : onRejectAutoScanReading,
                icon: const Icon(Icons.close),
                label: const Text('Wrong'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(
            onPressed: isBusy || isConfirming ? null : onRetake,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retake'),
          ),
        ),
      ],
    );
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
