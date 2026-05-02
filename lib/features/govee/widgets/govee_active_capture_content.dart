import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../providers/govee_capture_provider.dart';
import 'govee_live_reading_card.dart';
import 'govee_review_sheet.dart';
import 'govee_scope_picker.dart';
import 'govee_spot_recorder.dart';

class GoveeActiveCaptureContent extends StatelessWidget {
  final EdgeInsets padding;

  const GoveeActiveCaptureContent({
    super.key,
    this.padding = const EdgeInsets.all(AppSizes.cardPadding),
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GoveeCaptureProvider>(
      builder: (context, provider, _) {
        return ListView(
          padding: padding,
          children: [
            const GoveeLiveReadingCard(),
            const SizedBox(height: 12),
            const GoveeScopePicker(),
            if (provider.hasExistingCapture) ...[
              const SizedBox(height: 12),
              _ExistingCaptureNotice(
                date: provider.captureDate ?? '',
                placeLabel: provider.place?.label ?? 'Selected place',
              ),
            ],
            const SizedBox(height: 12),
            const GoveeSpotRecorder(),
            if (provider.phase == GoveeSpotPhase.review) ...[
              const SizedBox(height: 12),
              GoveeReviewSheet(
                initialLabels: const ['Spot 1', 'Spot 2', 'Spot 3'],
                onSave: (labels) =>
                    _saveWithReplacementConfirmation(context, provider, labels),
              ),
            ],
            if (provider.phase == GoveeSpotPhase.saved) ...[
              const SizedBox(height: 12),
              _SavedNotice(nextLabel: provider.suggestedNextPlace?.label),
            ],
          ],
        );
      },
    );
  }

  Future<void> _saveWithReplacementConfirmation(
    BuildContext context,
    GoveeCaptureProvider provider,
    List<String> labels,
  ) async {
    if (provider.hasExistingCapture) {
      final shouldReplace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace existing Govee capture?'),
          content: Text(
            '${provider.place?.label ?? 'This place'} already has saved '
            'records for ${provider.captureDate ?? 'this date'}. Delete the '
            'older records and save this new capture?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (shouldReplace != true) return;
    }
    if (!context.mounted) return;
    await provider.savePlaceCapture(spotLabels: labels);
  }
}

class _ExistingCaptureNotice extends StatelessWidget {
  final String date;
  final String placeLabel;

  const _ExistingCaptureNotice({required this.date, required this.placeLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.statusWarningBg,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.statusWarning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$placeLabel already has a Govee capture for $date. You will be asked before older records are replaced.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedNotice extends StatelessWidget {
  final String? nextLabel;

  const _SavedNotice({required this.nextLabel});

  @override
  Widget build(BuildContext context) {
    final text = nextLabel == null
        ? 'Capture saved. Choose the next place when ready.'
        : 'Capture saved. Next place: $nextLabel.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.statusGoodBg,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.statusGood),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
