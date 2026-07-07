import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../widgets/app_card.dart';
import '../../../../widgets/photo_grid.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import '../../scope/scope_station_items.dart';
import '../../screens/photo_fullscreen_screen.dart';
import '../sections/egg_storage_station_section.dart';
import 'alarm_triage_feed.dart';
import 'scope_cumulative_view.dart';
import 'scope_mode_toggle.dart';
import 'scope_sector_widget.dart';
import 'scope_triage_builder.dart';
import 'station_icon.dart';

/// "Scopes & Parameters" — the full audit comparison, grouped by station, each
/// station an expandable card of sector widgets. Ported from the prototype.
class ScopeInsightsSection extends StatelessWidget {
  const ScopeInsightsSection({
    super.key,
    required this.collapsedStations,
    required this.onStationToggle,
  });

  final Set<String> collapsedStations;
  final ValueChanged<String> onStationToggle;

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select<ScopeComparisonProvider, bool>(
      (p) => p.isLoading,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLoading)
          const Padding(
            padding: EdgeInsets.all(AppSizes.spaceXl),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final station in ScopeConfigRegistry.stations)
            _StationCard(
              station: station,
              expanded: !collapsedStations.contains(station),
              onToggle: () => onStationToggle(station),
            ),
      ],
    );
  }
}

class _StationCard extends StatelessWidget {
  final String station;
  final bool expanded;
  final VoidCallback onToggle;

  const _StationCard({
    required this.station,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<ScopeComparisonProvider>();
    final sectors = ScopeConfigRegistry.forStation(station);
    final done = completedItemsFor(scope, station);
    // Mirror the Govee card: a full-bleed brand-gradient header with rounded
    // top corners, then the body. Built by hand (not ExpansionTile) so the
    // header band spans edge-to-edge instead of being inset by ListTile's
    // leading/trailing gutter.
    return AppCard(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceXs,
        vertical: AppSizes.spaceXs,
      ),
      padding: EdgeInsets.zero,
      border: Border.all(color: AppColors.borderDefault),
      // Clip so the header's square bottom corners (when collapsed) and the
      // body both round to the card radius.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggle,
                child: _StationHeader(station: station, expanded: expanded),
              ),
            ),
            // Completed-item chips — a quick "what's recorded" summary that stays
            // visible even when the station is collapsed.
            if (done.isNotEmpty) _DoneChips(labels: done),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.spaceXs,
                  AppSizes.spaceSm,
                  AppSizes.spaceXs,
                  AppSizes.spaceSm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _bodyChildren(sectors, scope),
                ),
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }

  /// Most stations are a plain stack of their sectors, each fronted by a
  /// three-level "Alarms & Actions Required" banner. Two are bespoke: Egg Storage
  /// is laid out like the audit station (it carries its own richer alarms card),
  /// and Hatch has a standalone "Hatch Result" sector above a "Breakout" tabset.
  List<Widget> _bodyChildren(
    List<ScopeSectorConfig> sectors,
    ScopeComparisonProvider scope,
  ) {
    if (station == ScopeConfigRegistry.stationStorage) {
      return const [_StorageStationBody()];
    }
    final alarms = AlarmTriageFeed(items: stationTriageItems(scope, station));
    if (station == ScopeConfigRegistry.stationHatch) {
      return [
        alarms,
        const SizedBox(height: AppSizes.spaceMd),
        const ScopeSectorWidget(sectorId: 'hatch_results'),
        const SizedBox(height: AppSizes.spaceMd),
        const _BreakoutTabs(
          sectorIds: [
            'fresh_egg_breakout',
            'candled_egg_breakout',
            'residue_breakout',
          ],
        ),
      ];
    }
    return [
      alarms,
      const SizedBox(height: AppSizes.spaceMd),
      for (final s in sectors) ScopeSectorWidget(sectorId: s.id),
    ];
  }
}

/// Egg-Storage station body: the bespoke latest-audit view plus BMK-age history.
class _StorageStationBody extends StatelessWidget {
  const _StorageStationBody();

  @override
  Widget build(BuildContext context) {
    final cumulative = context.watch<ScopeComparisonProvider>().isCumulative(
      'egg_storage',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: ScopeModeToggle(
            sectorId: 'egg_storage',
            axis: CumulativeAxis.age,
          ),
        ),
        const SizedBox(height: AppSizes.spaceSm),
        if (!cumulative)
          const EggStorageStationSection()
        else ...[
          _cumHeader(context, 'Egg Storage', 'by BMK age', 'egg_storage'),
          const ScopeCumulativeView(sectorId: 'egg_storage'),
          const SizedBox(height: AppSizes.spaceLg),
          _cumHeader(context, 'Egg Quality', 'by BMK age', 'egg_quality'),
          const ScopeCumulativeView(sectorId: 'egg_quality'),
        ],
      ],
    );
  }

  Widget _cumHeader(
    BuildContext context,
    String title,
    String sub,
    String sectorId,
  ) {
    final provider = context.watch<ScopeComparisonProvider>();
    final isChart = provider.isChartMode(sectorId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 15,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
            ),
          ),
          const Spacer(),
          Tooltip(
            message: isChart ? 'Show table' : 'Show chart',
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              onTap: () => provider.toggleChartMode(sectorId),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  isChart ? Icons.table_chart_outlined : Icons.bar_chart,
                  size: 18,
                  color: AppColors.statusActive,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Station headline: a full-bleed brand-gradient band with the station name in
/// white, a one-line subtitle of what it measures, and a collapse chevron.
class _StationHeader extends StatelessWidget {
  final String station;
  final bool expanded;

  const _StationHeader({required this.station, required this.expanded});

  @override
  Widget build(BuildContext context) {
    final subtitle = StationIcon.subtitleFor(station);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.cardRadius),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceMd,
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
                  station,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    letterSpacing: 0.1,
                    color: Colors.white,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSizes.spaceSm),
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }
}

/// Green "done" pills for the items recorded under a station.
class _DoneChips extends StatelessWidget {
  final List<String> labels;

  const _DoneChips({required this.labels});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.spaceMd,
        AppSizes.spaceSm,
        AppSizes.spaceMd,
        0,
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final label in labels)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.completedBg,
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 13,
                    color: AppColors.completedText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.completedText,
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

/// "Breakout" tabset: pill tabs (Fresh / Candled / Residue) over the selected
/// breakout sector, rendered title-less since the tab already names it.
class _BreakoutTabs extends StatefulWidget {
  final List<String> sectorIds;

  const _BreakoutTabs({required this.sectorIds});

  @override
  State<_BreakoutTabs> createState() => _BreakoutTabsState();
}

class _BreakoutTabsState extends State<_BreakoutTabs> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<ScopeComparisonProvider>();
    final visibleSectorIds = widget.sectorIds
        .where((id) => !scope.isDummyFor(id) && !scope.isEmptyFor(id))
        .toList();
    if (visibleSectorIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final selected = _selected.clamp(0, visibleSectorIds.length - 1).toInt();
    final sectorId = visibleSectorIds[selected];
    final selectedLabel = ScopeConfigRegistry.byId(
      sectorId,
    ).title.replaceAll(' Breakout', '');
    final photoPaths = scope.photoPathsFor(sectorId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3.5,
              height: 15,
              margin: const EdgeInsets.only(top: 1, right: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Breakout',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            if (visibleSectorIds.length == 1) ...[
              const SizedBox(width: 6),
              Text(
                selectedLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ],
        ),
        if (visibleSectorIds.length > 1) ...[
          const SizedBox(height: AppSizes.spaceSm),
          // SingleChildScrollView + Row (not ListView) — mirrors _GoveePlaceTabs
          // and keeps the dashboard's only ListView the outer vertical scroll.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < visibleSectorIds.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: i == visibleSectorIds.length - 1 ? 0 : 6,
                    ),
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = i),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: i == selected
                              ? AppColors.statusActive
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(
                            AppSizes.pillRadius,
                          ),
                          border: Border.all(
                            color: i == selected
                                ? AppColors.statusActive
                                : AppColors.borderDefault,
                          ),
                        ),
                        child: Text(
                          ScopeConfigRegistry.byId(
                            visibleSectorIds[i],
                          ).title.replaceAll(' Breakout', ''),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: i == selected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSizes.spaceSm),
        ScopeSectorWidget(
          key: ValueKey('breakout-$sectorId'),
          sectorId: sectorId,
          showTitle: false,
        ),
        if (photoPaths.isNotEmpty) ...[
          const SizedBox(height: AppSizes.spaceSm),
          AppCard(
            padding: const EdgeInsets.all(AppSizes.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Photos',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSizes.spaceSm),
                PhotoGrid(
                  filePaths: photoPaths,
                  onTap: (path) => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PhotoFullscreenScreen(filePath: path),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
