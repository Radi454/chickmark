import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_utils.dart';
import '../../dashboard/models/govee_capture_summary.dart';
import '../../dashboard/widgets/govee_capture_chart.dart';
import '../providers/govee_capture_provider.dart';
import 'govee_chart_preview.dart';
import 'govee_live_reading_card.dart';
import 'govee_place_recorder.dart';
import 'govee_scope_picker.dart';

class GoveeActiveCaptureContent extends StatelessWidget {
  final EdgeInsets padding;

  const GoveeActiveCaptureContent({
    super.key,
    this.padding = const EdgeInsets.all(AppSizes.spaceMd),
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GoveeCaptureProvider>(
      builder: (context, provider, _) {
        final previewReadings = provider.livePreviewReadings;

        return ListView(
          padding: padding,
          children: [
            const GoveeLiveReadingCard(),
            if (previewReadings.isNotEmpty) ...[
              const SizedBox(height: AppSizes.spaceSm),
              GoveeChartPreview(
                readings: previewReadings,
                machineId: provider.machineId,
              ),
            ],
            const SizedBox(height: AppSizes.spaceSm),
            const GoveeScopePicker(),
            if (provider.hasExistingCapture) ...[
              const SizedBox(height: AppSizes.spaceSm),
              _ExistingCaptureNotice(
                date: HatchDateUtils.formatDisplayDateKey(
                  provider.captureDate ?? '',
                ),
                placeLabel: provider.place?.label ?? 'Selected place',
              ),
            ],
            const SizedBox(height: AppSizes.spaceSm),
            const GoveePlaceRecorder(),
            if (provider.finishedCapture != null) ...[
              const SizedBox(height: AppSizes.spaceSm),
              GoveeCaptureChart(
                summary: GoveeCaptureSummary(
                  capture: provider.finishedCapture!,
                  readings: provider.finishedReadings,
                ),
              ),
            ],
            if (provider.phase == GoveeCapturePhase.saved) ...[
              const SizedBox(height: AppSizes.spaceSm),
              _SavedNotice(nextLabel: provider.suggestedNextPlace?.label),
            ],
          ],
        );
      },
    );
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
              '$placeLabel already has a Govee capture for $date. Saving a new recording replaces the older records for this scope.',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textBody,
                fontWeight: FontWeight.w700,
              ),
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
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textBody,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
