import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../widgets/app_card.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import '../../scope/scope_station_items.dart';
import '../sections/egg_storage_station_section.dart';
import 'scope_sector_widget.dart';
import 'station_icon.dart';

/// "Scopes & Parameters" — the full audit comparison, grouped by station, each
/// station an expandable card of sector widgets. Ported from the prototype.
class ScopeInsightsSection extends StatelessWidget {
  const ScopeInsightsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isLoading =
        context.select<ScopeComparisonProvider, bool>((p) => p.isLoading);

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
            _StationCard(station: station),
      ],
    );
  }
}

class _StationCard extends StatefulWidget {
  final String station;

  const _StationCard({required this.station});

  @override
  State<_StationCard> createState() => _StationCardState();
}

class _StationCardState extends State<_StationCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final sectors = ScopeConfigRegistry.forStation(widget.station);
    final done = completedItemsFor(
      context.watch<ScopeComparisonProvider>(),
      widget.station,
    );
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
                onTap: () => setState(() => _expanded = !_expanded),
                child: _StationHeader(
                  station: widget.station,
                  expanded: _expanded,
                ),
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
                  children: _bodyChildren(sectors),
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }

  /// Most stations are a plain stack of their sectors. Two are bespoke: Egg
  /// Storage is laid out like the audit station (alarms → EST grid → upside down
  /// → checklist → per-house Egg Quality tabs), and Hatch has a standalone "Hatch
  /// Result" sector above a "Breakout" tabset.
  List<Widget> _bodyChildren(List<ScopeSectorConfig> sectors) {
    if (widget.station == ScopeConfigRegistry.stationStorage) {
      return const [EggStorageStationSection()];
    }
    if (widget.station == ScopeConfigRegistry.stationHatch) {
      return const [
        ScopeSectorWidget(sectorId: 'hatch_results'),
        SizedBox(height: AppSizes.spaceMd),
        _BreakoutTabs(
          sectorIds: [
            'fresh_egg_breakout',
            'candled_egg_breakout',
            'residue_breakout',
          ],
        ),
      ];
    }
    return [for (final s in sectors) ScopeSectorWidget(sectorId: s.id)];
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
    final selected = _selected.clamp(0, widget.sectorIds.length - 1);
    final sectorId = widget.sectorIds[selected];
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
          ],
        ),
        const SizedBox(height: AppSizes.spaceSm),
        // SingleChildScrollView + Row (not ListView) — mirrors _GoveePlaceTabs
        // and keeps the dashboard's only ListView the outer vertical scroll.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < widget.sectorIds.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    right: i == widget.sectorIds.length - 1 ? 0 : 6,
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
                        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                        border: Border.all(
                          color: i == selected
                              ? AppColors.statusActive
                              : AppColors.borderDefault,
                        ),
                      ),
                      child: Text(
                        ScopeConfigRegistry.byId(widget.sectorIds[i])
                            .title
                            .replaceAll(' Breakout', ''),
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
        const SizedBox(height: AppSizes.spaceSm),
        ScopeSectorWidget(
          key: ValueKey('breakout-$sectorId'),
          sectorId: sectorId,
          showTitle: false,
        ),
      ],
    );
  }
}
