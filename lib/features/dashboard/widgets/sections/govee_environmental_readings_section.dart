import 'package:flutter/material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/dashboard/widgets/govee_capture_chart.dart';
import 'package:hatchaudit/widgets/app_card.dart';

class GoveeEnvironmentalReadingsSection extends StatelessWidget {
  final List<GoveeCaptureSummary> captures;
  final bool isLoading;

  const GoveeEnvironmentalReadingsSection({
    super.key,
    required this.captures,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final placeGroups = _placeGroups(captures);

    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Govee Environmental Readings',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              if (isLoading)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (isLoading) ...[
            const SizedBox(height: AppSizes.spaceSm),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (placeGroups.isNotEmpty) ...[
            const SizedBox(height: AppSizes.spaceMd),
            ...placeGroups.map(_GoveePlaceGroup.new),
          ] else if (!isLoading) ...[
            const SizedBox(height: AppSizes.spaceMd),
            Text(
              'No saved Govee readings yet',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
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

class _GoveePlaceGroup extends StatelessWidget {
  final _GoveePlaceCaptures group;

  const _GoveePlaceGroup(this.group);

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
                child: Text(group.place.label, style: AppTextStyles.title),
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
