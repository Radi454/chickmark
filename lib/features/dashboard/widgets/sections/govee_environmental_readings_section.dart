import 'package:flutter/material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/dashboard/widgets/govee_capture_chart.dart';
import 'package:hatchaudit/widgets/app_card.dart';

class GoveeEnvironmentalReadingsSection extends StatefulWidget {
  final List<GoveeCaptureSummary> captures;
  final bool isLoading;

  const GoveeEnvironmentalReadingsSection({
    super.key,
    required this.captures,
    required this.isLoading,
  });

  @override
  State<GoveeEnvironmentalReadingsSection> createState() =>
      _GoveeEnvironmentalReadingsSectionState();
}

class _GoveeEnvironmentalReadingsSectionState
    extends State<GoveeEnvironmentalReadingsSection> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final placeGroups = _placeGroups(widget.captures);
    final isLoading = widget.isLoading;
    final selected = placeGroups.isEmpty
        ? 0
        : _selected.clamp(0, placeGroups.length - 1);

    return AppCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppSizes.cardRadius),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.cardPadding,
              vertical: AppSizes.spaceMd,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Govee Environmental Readings',
                        style: AppTextStyles.sectionTitle.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Continuous temp & RH · monitored places · 24h captures',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isLoading) ...[
                  const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: AppSizes.spaceMd),
                ],
                if (placeGroups.isNotEmpty) ...[
                  if (placeGroups.length > 1) ...[
                    _GoveePlaceTabs(
                      groups: placeGroups,
                      selected: selected,
                      onSelected: (i) => setState(() => _selected = i),
                    ),
                    const SizedBox(height: AppSizes.spaceMd),
                  ],
                  _GoveePlaceGroup(
                    placeGroups[selected],
                    showLabel: placeGroups.length == 1,
                  ),
                ] else if (!isLoading)
                  Text(
                    'No saved Govee readings yet',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_GoveePlaceCaptures> _placeGroups(List<GoveeCaptureSummary> captures) {
    final byPlace = <TemperaturePlace, List<GoveeCaptureSummary>>{};
    for (final summary in captures) {
      byPlace.putIfAbsent(summary.capture.place, () => []).add(summary);
    }
    final places = byPlace.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return places
        .map((place) {
          final summaries = List<GoveeCaptureSummary>.from(byPlace[place]!)
            ..sort(_compareCaptures);
          return _GoveePlaceCaptures(place: place, captures: summaries);
        })
        .toList(growable: false);
  }

  int _compareCaptures(GoveeCaptureSummary a, GoveeCaptureSummary b) {
    final machineCompare = (a.capture.machineId ?? '').compareTo(
      b.capture.machineId ?? '',
    );
    if (machineCompare != 0) return machineCompare;
    final dateCompare = b.capture.captureDate.compareTo(a.capture.captureDate);
    if (dateCompare != 0) return dateCompare;
    return b.capture.updatedAt.compareTo(a.capture.updatedAt);
  }
}

class _GoveePlaceCaptures {
  final TemperaturePlace place;
  final List<GoveeCaptureSummary> captures;

  const _GoveePlaceCaptures({required this.place, required this.captures});
}

class _GoveePlaceTabs extends StatelessWidget {
  final List<_GoveePlaceCaptures> groups;
  final int selected;
  final ValueChanged<int> onSelected;

  const _GoveePlaceTabs({
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          for (var i = 0; i < groups.length; i++)
            Padding(
              key: ValueKey('govee-place-tab-${groups[i].place.name}'),
              padding: EdgeInsets.only(
                right: i == groups.length - 1 ? 0 : AppSizes.spaceSm,
              ),
              child: _GoveePlaceTab(
                label: groups[i].place.label,
                count: groups[i].captures.length,
                isActive: i == selected,
                onTap: () => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _GoveePlaceTab extends StatelessWidget {
  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _GoveePlaceTab({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? AppColors.primary : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.spaceMd,
            vertical: AppSizes.spaceSm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.borderDefault,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isActive
                      ? AppColors.textOnPrimary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: isActive
                      ? AppColors.textOnPrimary.withValues(alpha: 0.85)
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoveePlaceGroup extends StatelessWidget {
  final _GoveePlaceCaptures group;
  final bool showLabel;

  const _GoveePlaceGroup(this.group, {this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('govee-place-group-${group.place.name}'),
      padding: const EdgeInsets.only(bottom: AppSizes.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: showLabel
                    ? Text(group.place.label, style: AppTextStyles.title)
                    : const SizedBox.shrink(),
              ),
              Text(
                '${group.captures.length} record${group.captures.length == 1 ? '' : 's'}',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          ...group.captures.map(
            (summary) => Padding(
              key: ValueKey('govee-capture-card-${summary.capture.id}'),
              padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
              child: GoveeCaptureChart(summary: summary),
            ),
          ),
        ],
      ),
    );
  }
}
