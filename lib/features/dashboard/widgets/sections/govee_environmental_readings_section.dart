import 'package:hatchaudit/localized_material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_intelligence_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/govee_capture_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/alarm_triage_feed.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/govee_cumulative_view.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/govee_triage_builder.dart';
import 'package:hatchaudit/providers/app_provider.dart';
import 'package:hatchaudit/widgets/app_card.dart';
import 'package:provider/provider.dart';

class GoveeEnvironmentalReadingsSection extends StatefulWidget {
  final List<GoveeCaptureSummary> captures;
  final bool isLoading;
  final bool expanded;
  final VoidCallback onToggle;
  final String? error;

  const GoveeEnvironmentalReadingsSection({
    super.key,
    required this.captures,
    required this.isLoading,
    required this.expanded,
    required this.onToggle,
    this.error,
  });

  @override
  State<GoveeEnvironmentalReadingsSection> createState() =>
      _GoveeEnvironmentalReadingsSectionState();
}

class _GoveeEnvironmentalReadingsSectionState
    extends State<GoveeEnvironmentalReadingsSection> {
  int _selected = 0;
  // Cumulative is per place (keyed by the place enum, not the tab index, so it
  // survives filter changes): Setter Room can be cumulative while Outside
  // Hatchery stays incremental.
  final Set<TemperaturePlace> _cumulativePlaces = <TemperaturePlace>{};

  @override
  Widget build(BuildContext context) {
    final placeGroups = _placeGroups(widget.captures);
    final isLoading = widget.isLoading;
    final triage = goveeTriageItems(widget.captures);
    final now = DateTime.now();
    final staleCount = widget.captures.where((summary) {
      final freshness = summary.freshnessAt(now);
      return freshness == DashboardFreshness.stale ||
          freshness == DashboardFreshness.invalid;
    }).length;
    final selected = placeGroups.isEmpty
        ? 0
        : _selected.clamp(0, placeGroups.length - 1);

    return AppCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      // Clip so the header's square bottom corners (when collapsed) and the
      // body both round to the card radius.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: Semantics(
                button: true,
                expanded: widget.expanded,
                label:
                    '${context.tr('Govee Environmental Readings')} ${context.tr(widget.expanded ? 'expanded' : 'collapsed')}',
                child: InkWell(
                  onTap: widget.onToggle,
                  child: Container(
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
                        if (isLoading) ...[
                          const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ],
                        const SizedBox(width: AppSizes.spaceSm),
                        AnimatedRotation(
                          turns: widget.expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.captures.isNotEmpty) ...[
                      _GoveeQualityStrip(captures: widget.captures),
                      const SizedBox(height: AppSizes.spaceMd),
                    ],
                    if (widget.error != null) ...[
                      const _SectionLoadError(),
                      const SizedBox(height: AppSizes.spaceMd),
                    ],
                    if (staleCount > 0) ...[
                      _HistoricalDataNotice(count: staleCount),
                      const SizedBox(height: AppSizes.spaceMd),
                    ],
                    if (triage.isNotEmpty) ...[
                      AlarmTriageFeed(items: triage),
                      const SizedBox(height: AppSizes.spaceMd),
                    ],
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
                      _GoveeControlBar(
                        cumulative: _cumulativePlaces.contains(
                          placeGroups[selected].place,
                        ),
                        onModeChanged: (v) => setState(() {
                          final place = placeGroups[selected].place;
                          if (v) {
                            _cumulativePlaces.add(place);
                          } else {
                            _cumulativePlaces.remove(place);
                          }
                        }),
                      ),
                      const SizedBox(height: AppSizes.spaceMd),
                      if (!_cumulativePlaces.contains(
                        placeGroups[selected].place,
                      ))
                        _GoveePlaceGroup(
                          placeGroups[selected],
                          showLabel: placeGroups.length == 1,
                        )
                      else
                        _GoveePlaceCumulative(placeGroups[selected]),
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
              crossFadeState: widget.expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
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
    return b.effectiveRecordedAt.compareTo(a.effectiveRecordedAt);
  }
}

class _HistoricalDataNotice extends StatelessWidget {
  const _HistoricalDataNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final message =
        '$count stale environmental captures are shown as history and excluded from active alerts.';
    return Semantics(
      label: context.tr(message),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Row(
          children: [
            const Icon(Icons.history, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoveeQualityStrip extends StatelessWidget {
  const _GoveeQualityStrip({required this.captures});

  final List<GoveeCaptureSummary> captures;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final latest = captures
        .map((summary) => summary.effectiveRecordedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final readings = captures.fold<int>(
      0,
      (sum, summary) => sum + summary.readings.length,
    );
    final current = captures
        .where(
          (summary) => summary.freshnessAt(now) == DashboardFreshness.current,
        )
        .length;
    final labels = [
      'Latest capture ${_relativeAge(now.difference(latest))}',
      '${captures.length} environmental captures',
      '$readings environmental readings',
      '$current current captures',
    ];
    return Semantics(
      label: labels.map(context.tr).join(', '),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final label in labels)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.statusActiveBg,
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.statusActive,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _relativeAge(Duration age) {
    if (age.inMinutes < 60) return '${age.inMinutes} min ago';
    if (age.inHours < 48) return '${age.inHours} h ago';
    return '${age.inDays} d ago';
  }
}

class _SectionLoadError extends StatelessWidget {
  const _SectionLoadError();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.statusErrorBg,
          borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
          border: Border.all(
            color: AppColors.statusError.withValues(alpha: 0.3),
          ),
        ),
        child: const Text(
          'Environmental readings could not refresh.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.statusError,
          ),
        ),
      ),
    );
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

/// Cumulative (by-visit) trend for the selected place: the place header (label +
/// record count) over [GoveeCumulativeView], which charts temp / RH averages
/// across this place's capture dates. Same Incremental ⇄ Cumulative concept the
/// scope audit stations use, scoped to one Govee place.
class _GoveePlaceCumulative extends StatelessWidget {
  final _GoveePlaceCaptures group;

  const _GoveePlaceCumulative(this.group);

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('govee-place-cumulative-${group.place.name}'),
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
          GoveeCumulativeView(captures: group.captures),
        ],
      ),
    );
  }
}

class _GoveeControlBar extends StatelessWidget {
  final bool cumulative;
  final ValueChanged<bool> onModeChanged;

  const _GoveeControlBar({
    required this.cumulative,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSizes.spaceSm,
      runSpacing: AppSizes.spaceSm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _GoveeModeToggle(cumulative: cumulative, onChanged: onModeChanged),
        const _GoveeTemperatureUnitToggle(),
      ],
    );
  }
}

/// Incremental ⇄ Cumulative segmented switch for the selected Govee place.
/// Incremental shows the per-capture detail charts; Cumulative tints to the
/// by-visit accent and shows the trend. Mirrors [ScopeModeToggle].
class _GoveeModeToggle extends StatelessWidget {
  final bool cumulative;
  final ValueChanged<bool> onChanged;

  const _GoveeModeToggle({required this.cumulative, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _seg(
              label: 'Incremental',
              on: !cumulative,
              onColor: AppColors.primary,
              onTap: () => onChanged(false),
            ),
            _seg(
              label: 'Cumulative',
              icon: Icons.show_chart,
              on: cumulative,
              onColor: AppColors.accent,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seg({
    required String label,
    required bool on,
    required Color onColor,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on ? onColor : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: on ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoveeTemperatureUnitToggle extends StatelessWidget {
  const _GoveeTemperatureUnitToggle();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isCelsius = provider.tempUnit == TempUnit.celsius;
    return Container(
      key: const ValueKey('govee-temperature-unit-toggle'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(
            label: '°F',
            on: !isCelsius,
            onTap: () => provider.setTempUnit(TempUnit.fahrenheit),
          ),
          _seg(
            label: '°C',
            on: isCelsius,
            onTap: () => provider.setTempUnit(TempUnit.celsius),
          ),
        ],
      ),
    );
  }

  Widget _seg({
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        onTap: onTap,
        child: Container(
          width: 34,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: on ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: on ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
