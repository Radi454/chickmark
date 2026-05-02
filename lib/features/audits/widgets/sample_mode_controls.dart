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
  final bool centered;
  final String title;
  final String pooledLabel;
  final String comparisonLabel;

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
    this.centered = false,
    this.title = 'Sample Mode',
    this.pooledLabel = 'Single Sample',
    this.comparisonLabel = 'Compare Samples',
  });

  @override
  Widget build(BuildContext context) {
    final isComparison =
        provider.stationSampleMode == StationSampleModel.sampleModeComparison;
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: centered ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: centered
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.title.copyWith(
                  fontSize: centered ? 26 : null,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
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
          SizedBox(height: centered ? 20 : 6),
          _SampleModeSwitch(
            value: provider.stationSampleMode,
            enabled: !provider.isReadOnly && !provider.isLoading,
            expanded: centered,
            pooledLabel: pooledLabel,
            comparisonLabel: comparisonLabel,
            onChanged: provider.setStationSampleMode,
          ),
          if (isComparison) ...[
            SizedBox(height: centered ? 18 : 10),
            Row(
              mainAxisAlignment: centered
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
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

    if (!centered) return content;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: content,
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

class _SampleModeSwitch extends StatelessWidget {
  final String value;
  final bool enabled;
  final bool expanded;
  final String pooledLabel;
  final String comparisonLabel;
  final ValueChanged<String> onChanged;

  const _SampleModeSwitch({
    required this.value,
    required this.enabled,
    required this.expanded,
    required this.pooledLabel,
    required this.comparisonLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final height = expanded ? 64.0 : 44.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fillWidth =
            expanded ||
            (constraints.hasBoundedWidth && constraints.maxWidth < 560);
        final large = expanded;

        return Opacity(
          opacity: enabled ? 1 : 0.62,
          child: IgnorePointer(
            ignoring: !enabled,
            child: Container(
              width: fillWidth ? double.infinity : null,
              height: height,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(height / 2),
                border: Border.all(color: AppColors.textSecondary),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  _SampleModeButton(
                    icon: Icons.all_inclusive,
                    label: pooledLabel,
                    active: value == StationSampleModel.sampleModePooled,
                    fillWidth: fillWidth,
                    large: large,
                    onTap: () => onChanged(StationSampleModel.sampleModePooled),
                  ),
                  Container(width: 1, color: AppColors.textSecondary),
                  _SampleModeButton(
                    icon: Icons.compare_arrows,
                    label: comparisonLabel,
                    active: value == StationSampleModel.sampleModeComparison,
                    fillWidth: fillWidth,
                    large: large,
                    onTap: () =>
                        onChanged(StationSampleModel.sampleModeComparison),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SampleModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool fillWidth;
  final bool large;
  final VoidCallback onTap;

  const _SampleModeButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.fillWidth,
    required this.large,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gap = large ? 12.0 : 8.0;
    final horizontalPadding = large ? 22.0 : (fillWidth ? 8.0 : 14.0);
    final fontSize = large ? 21.0 : 14.0;

    final child = InkWell(
      onTap: onTap,
      child: Container(
        height: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        color: active ? AppColors.primary : Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? Colors.white : AppColors.primary,
              size: large ? 28 : 20,
            ),
            SizedBox(width: gap),
            if (fillWidth)
              Flexible(
                child: _SampleModeLabel(
                  label: label,
                  active: active,
                  fontSize: fontSize,
                ),
              )
            else
              _SampleModeLabel(
                label: label,
                active: active,
                fontSize: fontSize,
              ),
          ],
        ),
      ),
    );

    return fillWidth ? Expanded(child: child) : child;
  }
}

class _SampleModeLabel extends StatelessWidget {
  final String label;
  final bool active;
  final double fontSize;

  const _SampleModeLabel({
    required this.label,
    required this.active,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: active ? Colors.white : AppColors.primary,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
      ),
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
