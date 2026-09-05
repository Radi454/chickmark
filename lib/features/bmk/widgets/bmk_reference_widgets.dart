/// Shared presentation widgets for the BMK screen's reference sectors.
///
/// Both sectors of the BMK screen — Hatchery and Breeder Farm — present
/// benchmarks the same way: a selector row, an age control, and a grid of
/// value tiles. These widgets are the single implementation of that layout so
/// the two sectors cannot drift apart. They hold no state and know nothing
/// about either sector's data source.
library;

import 'package:hatchaudit/localized_material.dart';

import 'package:hatchaudit/core/theme/app_elevation.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';

/// Placeholder for a benchmark the source guide does not publish.
///
/// Never render `0` for a missing benchmark: a zero target is
/// indistinguishable from a real one to the reader, and none of the reference
/// metrics has a legitimate zero.
const String kBmkNoValue = '—';

String formatBmkNumber(double? value) {
  if (value == null) return '';
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

/// Formats a reference benchmark, rendering [kBmkNoValue] when the guide
/// publishes no value at this age.
///
/// `treatZeroAsMissing` exists for the hatchery breed benchmarks: their
/// `bmk_breeds` columns default to `0.0` and cannot express "no value", so a
/// stored zero always means "not published at this age" (a benchmark of 0%
/// hatchability or 0 g egg weight is not a thing). Breeder benchmarks store
/// real nulls and must not enable it.
String formatBmkBenchmark(
  double? value, {
  String unit = '',
  bool treatZeroAsMissing = false,
}) {
  if (value == null) return kBmkNoValue;
  if (treatZeroAsMissing && value == 0) return kBmkNoValue;
  return '${formatBmkNumber(value)}$unit';
}

class BmkMetric {
  final String label;
  final String value;
  final String? source;
  final String? sourceUrl;
  final String? sourcePhotoPath;
  final String? sourcePhotoRemotePath;
  final String? notes;
  final String? citationKey;

  const BmkMetric({
    required this.label,
    required this.value,
    this.source,
    this.sourceUrl,
    this.sourcePhotoPath,
    this.sourcePhotoRemotePath,
    this.notes,
    this.citationKey,
  });

  bool get hasCitation =>
      (source ?? '').trim().isNotEmpty ||
      (sourceUrl ?? '').trim().isNotEmpty ||
      hasSourcePhoto;

  bool get hasSourcePhoto =>
      (sourcePhotoPath ?? '').trim().isNotEmpty ||
      (sourcePhotoRemotePath ?? '').trim().isNotEmpty;
}

/// Card shell used by every BMK reference sector.
class BmkSectorCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const BmkSectorCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;
    final padding = isCompact ? AppSizes.spaceSm : AppSizes.spaceLg;
    final iconSize = isCompact ? 32.0 : AppSizes.iconContainerSm;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
        boxShadow: AppElevation.level1,
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: AppColors.activeBg,
                    borderRadius: BorderRadius.circular(AppSizes.iconRadius),
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.primary,
                    size: isCompact ? 18 : AppSizes.iconSm,
                  ),
                ),
                SizedBox(
                  width: isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.sectionTitle.copyWith(
                      fontSize: isCompact ? 16 : null,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg),
            child,
          ],
        ),
      ),
    );
  }
}

/// Lays a selector out beside its age control on wide screens and stacks them
/// on narrow ones.
class BmkControlShelf extends StatelessWidget {
  final Widget primary;
  final Widget secondary;

  const BmkControlShelf({
    super.key,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: AppSizes.spaceSm),
              secondary,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: primary),
            const SizedBox(width: AppSizes.spaceMd),
            secondary,
          ],
        );
      },
    );
  }
}

class BmkAgeControl extends StatelessWidget {
  final String label;
  final int? value;
  final List<int> ages;
  final ValueChanged<int?> onChanged;

  const BmkAgeControl({
    super.key,
    required this.label,
    required this.value,
    required this.ages,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;

    return Container(
      constraints: BoxConstraints(minHeight: isCompact ? 34 : 44),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
        vertical: isCompact ? 2 : AppSizes.spaceXs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              fontSize: isCompact ? 11 : null,
            ),
          ),
          const SizedBox(width: AppSizes.spaceSm),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              style: AppTextStyles.title.copyWith(
                fontSize: isCompact ? 14 : null,
              ),
              items: ages.map((age) {
                return DropdownMenuItem(value: age, child: Text('${age}w'));
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class BmkSelectablePill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const BmkSelectablePill({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;
    final foreground = selected ? AppColors.textOnPrimary : AppColors.textBody;
    final borderColor = selected ? AppColors.primary : AppColors.borderDefault;
    final background = selected ? AppColors.primary : AppColors.surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: BoxConstraints(minHeight: isCompact ? 34 : 44),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
            vertical: isCompact ? AppSizes.spaceXs : AppSizes.spaceSm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: isCompact ? 15 : 18, color: foreground),
                SizedBox(
                  width: isCompact ? AppSizes.spaceXs : AppSizes.spaceSm,
                ),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title.copyWith(
                    color: foreground,
                    fontSize: isCompact ? 13 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A responsive row of selectable pills, sized so each run fills the width.
class BmkPillBar extends StatelessWidget {
  final List<String> labels;
  final String? selected;
  final ValueChanged<String> onSelected;

  /// Column counts for wide / medium / narrow layouts. The hatchery breed bar
  /// packs six breeds across a wide screen; smaller bars want fewer.
  final int wideColumns;

  const BmkPillBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.wideColumns = 6,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? wideColumns
            : width >= 300
            ? 3
            : 2;
        const spacing = AppSizes.spaceXs;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: labels.map((label) {
            final isSelected = selected == label;
            return SizedBox(
              width: itemWidth,
              child: BmkSelectablePill(
                label: label,
                icon: isSelected ? Icons.check : null,
                selected: isSelected,
                onTap: () => onSelected(label),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class BmkMetricGrid extends StatelessWidget {
  final List<BmkMetric> metrics;
  final void Function(BmkMetric metric)? onCitationTap;

  const BmkMetricGrid({super.key, required this.metrics, this.onCitationTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 820
            ? 3
            : width >= 300
            ? 2
            : 1;
        final spacing = width < 520 ? AppSizes.spaceXs : AppSizes.spaceSm;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: metrics.map((metric) {
            return SizedBox(
              width: itemWidth,
              child: BmkMetricTile(
                metric: metric,
                onCitationTap: onCitationTap,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class BmkMetricTile extends StatelessWidget {
  final BmkMetric metric;
  final void Function(BmkMetric metric)? onCitationTap;

  const BmkMetricTile({super.key, required this.metric, this.onCitationTap});

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;
    final isMissing = metric.value == kBmkNoValue;
    final showCitation = metric.hasCitation && onCitationTap != null;

    return Container(
      constraints: BoxConstraints(minHeight: isCompact ? 54 : 76),
      padding: EdgeInsets.all(isCompact ? AppSizes.spaceSm : AppSizes.spaceMd),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        metric.label,
                        // Breeder metric labels come from the guides and run
                        // long ("Hatching Eggs per Hen-Housed"); one line
                        // ellipsizes them into ambiguity.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: isCompact ? 11 : null,
                        ),
                      ),
                    ),
                    if (showCitation) ...[
                      const SizedBox(width: AppSizes.spaceXs),
                      SizedBox.square(
                        dimension: isCompact ? 24 : 28,
                        child: IconButton(
                          key: metric.citationKey == null
                              ? null
                              : ValueKey('bmk-citation-${metric.citationKey}'),
                          tooltip: context.tr('Source'),
                          padding: EdgeInsets.zero,
                          iconSize: isCompact ? 16 : 18,
                          icon: const Icon(Icons.format_quote_rounded),
                          color: AppColors.primary,
                          onPressed: () => onCitationTap!(metric),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: isCompact ? 1 : AppSizes.spaceXs),
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.metricLarge.copyWith(
                    // A missing benchmark is not a reading; it must not carry
                    // the same visual weight as a published one.
                    color: isMissing
                        ? AppColors.textTertiary
                        : AppColors.primary,
                    fontSize: isCompact ? 18 : 22,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
