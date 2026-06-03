import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/date_utils.dart';
import '../providers/govee_capture_provider.dart';
import '../widgets/govee_chart_preview.dart';
import '../widgets/govee_live_reading_card.dart';
import '../widgets/govee_place_recorder.dart';
import '../widgets/govee_scope_picker.dart';

class GoveeScreen extends StatefulWidget {
  const GoveeScreen({super.key});

  @override
  State<GoveeScreen> createState() => _GoveeScreenState();
}

class _GoveeScreenState extends State<GoveeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!kIsWeb) return;
      unawaited(context.read<GoveeCaptureProvider>().ensureBleReady());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Govee'),
      body: Consumer<GoveeCaptureProvider>(
        builder: (context, provider, _) {
          final livePreviewReadings = provider.livePreviewReadings;
          return ListView(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            children: [
              const GoveeLiveReadingCard(key: ValueKey('govee-live-header')),
              const SizedBox(height: 12),
              if (livePreviewReadings.isNotEmpty) ...[
                GoveeChartPreview(
                  readings: livePreviewReadings,
                  machineId: provider.machineId,
                ),
                const SizedBox(height: 12),
              ],
              const GoveeScopePicker(),
              if (provider.hasExistingCapture) ...[
                const SizedBox(height: 12),
                _ExistingCaptureNotice(
                  date: HatchDateUtils.formatDisplayDateKey(
                    provider.captureDate ?? '',
                  ),
                  placeLabel: provider.place?.label ?? 'Selected place',
                ),
              ],
              const SizedBox(height: 12),
              const GoveePlaceRecorder(),
              if (provider.phase == GoveeCapturePhase.saved) ...[
                const SizedBox(height: 12),
                _SavedNotice(nextLabel: provider.suggestedNextPlace?.label),
              ],
            ],
          );
        },
      ),
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
