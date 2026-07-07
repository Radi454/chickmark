import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import '../../scope/scope_engine.dart';
import '../../scope/scope_models.dart';
import 'scope_severity_style.dart';
import 'station_icon.dart';

/// At-a-glance KPI strip: one compact card per audit station, summarizing its
/// headline metric, overall status (OK / Watch / Action), and how many readings
/// are off-spec. Static (no tap) — the full breakdown lives in the station cards
/// below. Reads [ScopeComparisonProvider], so it tracks the dashboard filter and
/// reuses the same count-weighted aggregation + BMK severity as the matrix.
class StationKpiStrip extends StatelessWidget {
  const StationKpiStrip({super.key});

  /// Per-station signature: the one metric shown big, plus a short headline.
  static const Map<String, _Signature> _signatures = {
    ScopeConfigRegistry.stationStorage:
        _Signature(name: 'Egg Storage', sectorId: 'egg_storage', column: 'estAvg', caption: 'EST °F'),
    ScopeConfigRegistry.stationChicks:
        _Signature(name: 'Chicks', sectorId: 'chick_quality', column: 'pasgarFinalScore', caption: 'Pasgar'),
    ScopeConfigRegistry.stationHatch:
        _Signature(name: 'Hatch', sectorId: 'hatch_results', column: 'hatchabilityPct', caption: 'Hatch %'),
    ScopeConfigRegistry.stationSetters:
        _Signature(name: 'Setters', sectorId: 'setter_optimizing', column: 'estAvg', caption: 'EST °F'),
    ScopeConfigRegistry.stationHatchers:
        _Signature(name: 'Hatchers', sectorId: 'hatcher_optimizing', column: 'cvtAvg', caption: 'CVT °F'),
  };

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScopeComparisonProvider>();
    final metrics = [
      for (final station in ScopeConfigRegistry.stations)
        _metricFor(provider, station),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSizes.spaceSm;
        // 2 cols on phone, up to 5 across on wide layouts.
        final cols = (constraints.maxWidth ~/ 200).clamp(2, metrics.length);
        final cardWidth =
            (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final m in metrics)
              SizedBox(width: cardWidth, child: _StationKpiCard(metric: m)),
          ],
        );
      },
    );
  }

  _StationMetric _metricFor(ScopeComparisonProvider provider, String station) {
    final sig = _signatures[station]!;
    final sector = ScopeConfigRegistry.byId(sig.sectorId);
    final paramIndex =
        sector.params.indexWhere((p) => p.column == sig.column);

    // Headline value: count-weighted across all groups (single number even when
    // the sector is broken down by layer).
    String value = '—';
    var headlineSeverity = ScopeSeverity.good;
    final sectorGroups = provider.groupsFor(sig.sectorId);
    if (paramIndex >= 0 && sectorGroups.isNotEmpty) {
      final stats = ScopeEngine.columnStats(
        sector,
        sectorGroups,
        provider.bmkFor(sig.sectorId),
      );
      value = stats[paramIndex].avgText;
      headlineSeverity = stats[paramIndex].worst;
    }

    // Station status + off-spec tally: scan every cell in every sector/group.
    var worst = ScopeSeverity.good;
    var offSpec = 0;
    for (final s in ScopeConfigRegistry.forStation(station)) {
      for (final group in provider.groupsFor(s.id)) {
        for (final cell in group.cells) {
          if (cell.severity == ScopeSeverity.warn ||
              cell.severity == ScopeSeverity.err) {
            offSpec++;
          }
          worst = worstSeverity(worst, cell.severity);
        }
      }
    }

    return _StationMetric(
      station: station,
      name: sig.name,
      caption: sig.caption,
      value: value,
      headlineSeverity: headlineSeverity,
      worst: worst,
      offSpec: offSpec,
    );
  }
}

class _Signature {
  final String name;
  final String sectorId;
  final String column;
  final String caption;

  const _Signature({
    required this.name,
    required this.sectorId,
    required this.column,
    required this.caption,
  });
}

class _StationMetric {
  final String station;
  final String name;
  final String caption;
  final String value;
  final ScopeSeverity headlineSeverity;
  final ScopeSeverity worst;
  final int offSpec;

  const _StationMetric({
    required this.station,
    required this.name,
    required this.caption,
    required this.value,
    required this.headlineSeverity,
    required this.worst,
    required this.offSpec,
  });
}

class _StationKpiCard extends StatelessWidget {
  final _StationMetric metric;

  const _StationKpiCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    final status = _StatusStyle.of(metric.worst);
    final valueColor = ScopeSeverityStyle.of(metric.headlineSeverity).cellText;

    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: StationIcon.bgFor(metric.station),
                  borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
                ),
                alignment: Alignment.center,
                child: StationIcon(station: metric.station, size: 22),
              ),
              const SizedBox(width: AppSizes.spaceXs),
              Expanded(
                child: Text(
                  metric.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(
            metric.caption.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.05,
              color: valueColor,
            ),
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Row(
            children: [
              _StatusPill(label: status.label, fg: status.fg, bg: status.bg),
              const SizedBox(width: AppSizes.spaceXs),
              Expanded(
                child: _OffSpecLabel(count: metric.offSpec, worst: metric.worst),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;

  const _StatusPill({required this.label, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          color: fg,
        ),
      ),
    );
  }
}

class _OffSpecLabel extends StatelessWidget {
  final int count;
  final ScopeSeverity worst;

  const _OffSpecLabel({required this.count, required this.worst});

  @override
  Widget build(BuildContext context) {
    final onSpec = count == 0;
    final color = onSpec ? AppColors.statusGood : ScopeSeverityStyle.dotColor(worst);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        StatusDot(color, size: 7),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            onSpec ? 'On spec' : '$count off-spec',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Station-level status banding from the worst cell severity.
class _StatusStyle {
  final String label;
  final Color fg;
  final Color bg;

  const _StatusStyle({required this.label, required this.fg, required this.bg});

  static _StatusStyle of(ScopeSeverity worst) {
    switch (worst) {
      case ScopeSeverity.err:
        return const _StatusStyle(
          label: 'ACTION',
          fg: AppColors.statusError,
          bg: AppColors.statusErrorBg,
        );
      case ScopeSeverity.warn:
        return const _StatusStyle(
          label: 'WATCH',
          fg: AppColors.scopeWarnText,
          bg: AppColors.statusWarningBg,
        );
      case ScopeSeverity.good:
      case ScopeSeverity.pool:
        return const _StatusStyle(
          label: 'OK',
          fg: AppColors.statusGood,
          bg: AppColors.statusGoodBg,
        );
    }
  }
}
