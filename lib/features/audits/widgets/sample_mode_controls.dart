import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/station_sample_model.dart';
import '../providers/audit_provider.dart';

class StationSampleModeControls extends StatelessWidget {
  final AuditProvider provider;
  final EdgeInsetsGeometry padding;
  final VoidCallback? afterAddSample;

  const StationSampleModeControls({
    super.key,
    required this.provider,
    this.padding = const EdgeInsets.fromLTRB(
      AppSizes.cardPadding,
      AppSizes.cardPadding,
      AppSizes.cardPadding,
      8,
    ),
    this.afterAddSample,
  });

  @override
  Widget build(BuildContext context) {
    final isComparison =
        provider.stationSampleMode == StationSampleModel.sampleModeComparison;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sample Mode', style: AppTextStyles.title),
              const SizedBox(width: 4),
              Semantics(
                label: 'Help: Sample Mode explanation',
                button: true,
                child: IconButton(
                  tooltip: 'Help: Sample Mode explanation',
                  icon: const Icon(Icons.help_outline, size: 20),
                  color: AppColors.textSecondary,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () => _showSampleModeHelp(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: StationSampleModel.sampleModePooled,
                icon: Icon(Icons.all_inclusive),
                label: Text('Single Sample'),
              ),
              ButtonSegment(
                value: StationSampleModel.sampleModeComparison,
                icon: Icon(Icons.compare_arrows),
                label: Text('Compare Samples'),
              ),
            ],
            selected: {provider.stationSampleMode},
            onSelectionChanged: provider.isReadOnly || provider.isLoading
                ? null
                : (selection) => provider.setStationSampleMode(selection.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? Colors.white
                    : AppColors.primary;
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? AppColors.primary
                    : Colors.white;
              }),
            ),
          ),
          if (isComparison) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(provider.sampleCount, (index) {
                        final selected = provider.activeSampleIndex == index;
                        final sample = provider.stationSamples[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(sample.sampleLabel),
                            selected: selected,
                            showCheckmark: false,
                            onSelected:
                                provider.isReadOnly || provider.isLoading
                                ? null
                                : (_) => provider.switchSample(index),
                            labelStyle: AppTextStyles.caption.copyWith(
                              color: selected
                                  ? Colors.white
                                  : AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                            selectedColor: AppColors.primary,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.borderDefault,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove active sample',
                  icon: const Icon(Icons.remove_circle_outline),
                  color: AppColors.statusError,
                  onPressed:
                      provider.isReadOnly ||
                          provider.isLoading ||
                          provider.sampleCount <= 1
                      ? null
                      : provider.removeActiveSample,
                ),
                IconButton(
                  tooltip: 'Add sample',
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppColors.primary,
                  onPressed: provider.isReadOnly || provider.isLoading
                      ? null
                      : () {
                          provider.addSample();
                          afterAddSample?.call();
                        },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showSampleModeHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Understanding Sample Mode'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Single Sample', style: AppTextStyles.title),
                const SizedBox(height: 4),
                const Text('One sample representing the overall condition.'),
                const SizedBox(height: 14),
                Text('Compare Samples', style: AppTextStyles.title),
                const SizedBox(height: 4),
                const Text(
                  'Add separate samples and compare their results side by side.\n'
                  'Each sample is entered and saved separately.',
                ),
                const SizedBox(height: 18),
                const _SampleModeHelpSection(
                  title: 'Batch Level:',
                  description: 'Compare different egg batches.',
                ),
                const _SampleModeHelpSection(
                  title: 'House Level:',
                  description: 'Compare houses within the same batch.',
                ),
                const _SampleModeHelpSection(
                  title: 'Machine Level:',
                  description:
                      'Compare machines (Setter + Hatcher) within the same batch.',
                ),
                const _SampleModeHelpSection(
                  title: 'Tray Level:',
                  description: 'Compare trays within the same machine.',
                ),
                const SizedBox(height: 10),
                const Text('Each level represents a deeper level of detail.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _SampleModeHelpSection extends StatelessWidget {
  final String title;
  final String description;

  const _SampleModeHelpSection({
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.title),
          const SizedBox(height: 4),
          Text(description),
        ],
      ),
    );
  }
}
