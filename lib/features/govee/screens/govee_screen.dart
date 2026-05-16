import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../dashboard/widgets/govee_capture_chart.dart';
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
          final selectedSavedSummary = provider.selectedSavedSummary;
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
                  date: provider.captureDate ?? '',
                  placeLabel: provider.place?.label ?? 'Selected place',
                ),
              ],
              const SizedBox(height: 12),
              const GoveePlaceRecorder(),
              if (provider.savedSummaries.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SavedCapturesCard(provider: provider),
              ],
              if (selectedSavedSummary != null) ...[
                const SizedBox(height: 12),
                GoveeCaptureChart(summary: selectedSavedSummary),
              ],
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

class _SavedCapturesCard extends StatelessWidget {
  final GoveeCaptureProvider provider;

  const _SavedCapturesCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final selectedId = provider.selectedSavedSummary?.capture.id;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: AppSizes.cardShadowBlur,
            offset: Offset(0, AppSizes.cardShadowOffsetY),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('govee-saved-captures-card'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: const Icon(
            Icons.inventory_2_outlined,
            color: AppColors.primary,
          ),
          title: const Text(
            'Saved captures',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            '${provider.savedSummaries.length} saved',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          children: [
            SizedBox(
              height: 68,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: provider.savedSummaries.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final summary = provider.savedSummaries[index];
                  final capture = summary.capture;
                  final selected = capture.id == selectedId;
                  return _SavedStationChip(
                    captureId: capture.id,
                    title: capture.place.label,
                    subtitle: '${capture.readingCount} readings',
                    selected: selected,
                    onTap: () => context
                        .read<GoveeCaptureProvider>()
                        .selectSavedCapture(capture.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedStationChip extends StatelessWidget {
  final String captureId;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SavedStationChip({
    required this.captureId,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.statusActiveBg : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('govee-saved-station-$captureId'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 168,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderDefault,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.circle_outlined,
                color: selected ? AppColors.primary : AppColors.textTertiary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
