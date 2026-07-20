import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/lab_analysis_models.dart';
import '../models/lab_analysis_trend_models.dart';

enum _LabTrendMetric { gmt, cv, positive }

class LabAnalysisTrendPanel extends StatefulWidget {
  const LabAnalysisTrendPanel({super.key, required this.series});

  final LabElisaTrendSeries series;

  @override
  State<LabAnalysisTrendPanel> createState() => _LabAnalysisTrendPanelState();
}

class _LabAnalysisTrendPanelState extends State<LabAnalysisTrendPanel> {
  _LabTrendMetric _metric = _LabTrendMetric.gmt;

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final latest = series.points.last;
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceLg),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius + 4),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSizes.spaceMd,
            runSpacing: AppSizes.spaceSm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${series.analyte} · flock trend',
                      style: AppTextStyles.title,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${series.points.length} dates · '
                      '${series.scopes.length} tracked scopes',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              _MetricChoices(
                selected: _metric,
                onSelected: (metric) => setState(() => _metric = metric),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          _InsightStrip(series: series),
          const SizedBox(height: AppSizes.spaceLg),
          LayoutBuilder(
            builder: (context, constraints) {
              final chart = _TrendChart(series: series, metric: _metric);
              final snapshot = _LatestSnapshot(point: latest);
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 250, child: chart),
                    const SizedBox(height: AppSizes.spaceMd),
                    snapshot,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: SizedBox(height: 250, child: chart)),
                  const SizedBox(width: AppSizes.spaceLg),
                  SizedBox(width: 190, height: 250, child: snapshot),
                ],
              );
            },
          ),
          const SizedBox(height: AppSizes.spaceLg),
          Row(
            children: [
              const Icon(
                Icons.grid_view_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Text(
                  'House comparison · GMT and uniformity',
                  style: AppTextStyles.subtitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          _ScopeHeatmap(series: series),
          const SizedBox(height: AppSizes.spaceSm),
          Container(
            padding: const EdgeInsets.all(AppSizes.spaceSm),
            decoration: BoxDecoration(
              color: AppColors.statusNeutralBg,
              borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.copy_all_outlined,
                  size: 17,
                  color: AppColors.statusNeutralText,
                ),
                const SizedBox(width: AppSizes.spaceSm),
                Expanded(
                  child: Text(
                    'Pooled repeat plates are shown as a separate dashed '
                    'series and are excluded from house averages.',
                    style: AppTextStyles.caption,
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

class _MetricChoices extends StatelessWidget {
  const _MetricChoices({required this.selected, required this.onSelected});

  final _LabTrendMetric selected;
  final ValueChanged<_LabTrendMetric> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_LabTrendMetric>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: _LabTrendMetric.gmt, label: Text('GMT')),
          ButtonSegment(value: _LabTrendMetric.cv, label: Text('CV%')),
          ButtonSegment(
            value: _LabTrendMetric.positive,
            label: Text('Positive'),
          ),
        ],
        selected: {selected},
        onSelectionChanged: (value) => onSelected(value.first),
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _InsightStrip extends StatelessWidget {
  const _InsightStrip({required this.series});

  final LabElisaTrendSeries series;

  @override
  Widget build(BuildContext context) {
    final first = series.points.first;
    final latest = series.points.last;
    final gmtChange = _percentChange(first.averageGmt, latest.averageGmt);
    final cvChange = _difference(first.averageCv, latest.averageCv);
    return Wrap(
      spacing: AppSizes.spaceSm,
      runSpacing: AppSizes.spaceSm,
      children: [
        _InsightChip(
          icon: Icons.trending_up_rounded,
          label: 'GMT change',
          value: gmtChange == null
              ? '—'
              : '${gmtChange >= 0 ? '+' : ''}${gmtChange.toStringAsFixed(0)}%',
          color: gmtChange != null && gmtChange >= 0
              ? AppColors.statusGood
              : AppColors.statusWarning,
        ),
        _InsightChip(
          icon: Icons.tune_rounded,
          label: 'CV improvement',
          value: cvChange == null
              ? '—'
              : '${cvChange >= 0 ? '-' : '+'}${cvChange.abs().toStringAsFixed(0)} pts',
          color: cvChange != null && cvChange >= 0
              ? AppColors.statusGood
              : AppColors.statusWarning,
        ),
        _InsightChip(
          icon: Icons.verified_outlined,
          label: 'Latest positive',
          value: latest.positivePct == null
              ? '—'
              : '${latest.positivePct!.toStringAsFixed(0)}%',
          color: AppColors.primary,
        ),
      ],
    );
  }

  double? _percentChange(double? first, double? last) {
    if (first == null || last == null || first == 0) return null;
    return (last - first) * 100 / first;
  }

  double? _difference(double? first, double? last) {
    if (first == null || last == null) return null;
    return first - last;
  }
}

class _InsightChip extends StatelessWidget {
  const _InsightChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text('$label  ', style: AppTextStyles.caption),
          Text(
            value,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.series, required this.metric});

  final LabElisaTrendSeries series;
  final _LabTrendMetric metric;

  @override
  Widget build(BuildContext context) {
    final points = series.points;
    final averageSpots = _spots(points, _average);
    final minSpots = _spots(points, _minimum);
    final maxSpots = _spots(points, _maximum);
    final pooledSpots = _spots(points, _pooled);
    final yValues = [
      ...averageSpots.map((spot) => spot.y),
      ...minSpots.map((spot) => spot.y),
      ...maxSpots.map((spot) => spot.y),
      ...pooledSpots.map((spot) => spot.y),
    ];
    final highest = yValues.isEmpty
        ? 100.0
        : yValues.reduce((left, right) => math.max(left, right));
    final maxY = metric == _LabTrendMetric.positive
        ? 110.0
        : math.max(
            highest * 1.16,
            metric == _LabTrendMetric.cv ? 10.0 : 1000.0,
          );
    final interval = _interval(maxY);

    final lines = [
      LineChartBarData(
        spots: averageSpots,
        isCurved: true,
        curveSmoothness: 0.28,
        color: AppColors.primary,
        barWidth: 3,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 4,
            color: AppColors.surface,
            strokeWidth: 2.5,
            strokeColor: AppColors.primary,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          color: AppColors.primary.withValues(alpha: 0.05),
        ),
      ),
      LineChartBarData(
        spots: minSpots,
        color: Colors.transparent,
        barWidth: 0,
        dotData: const FlDotData(show: false),
      ),
      LineChartBarData(
        spots: maxSpots,
        color: Colors.transparent,
        barWidth: 0,
        dotData: const FlDotData(show: false),
      ),
      if (pooledSpots.isNotEmpty)
        LineChartBarData(
          spots: pooledSpots,
          isCurved: false,
          color: AppColors.chart4,
          barWidth: 2,
          dashArray: const [6, 4],
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 3,
              color: AppColors.chart4,
              strokeWidth: 1.5,
              strokeColor: AppColors.surface,
            ),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSizes.spaceMd,
          runSpacing: AppSizes.spaceXs,
          children: [
            const _ChartLegend(color: AppColors.primary, label: 'House avg'),
            _ChartLegend(
              color: AppColors.primary.withValues(alpha: 0.15),
              label: 'House range',
            ),
            if (pooledSpots.isNotEmpty)
              const _ChartLegend(
                color: AppColors.chart4,
                label: 'Pooled repeat',
              ),
          ],
        ),
        const SizedBox(height: AppSizes.spaceSm),
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (points.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              lineBarsData: lines,
              betweenBarsData: [
                BetweenBarsData(
                  fromIndex: 1,
                  toIndex: 2,
                  color: AppColors.primary.withValues(alpha: 0.10),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.textPrimary,
                  getTooltipItems: (spots) {
                    return [
                      for (final spot in spots)
                        if (spot.barIndex == 1 || spot.barIndex == 2)
                          null
                        else
                          LineTooltipItem(
                            '${spot.barIndex == 0 ? 'Average' : 'Pooled'}\n'
                            '${_formatValue(spot.y)}',
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                    ];
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: AppColors.chartGridH, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 43,
                    interval: interval,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.max) return const SizedBox.shrink();
                      return Text(
                        _axisValue(value),
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.textTertiary,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 ||
                          index >= points.length ||
                          (value - index).abs() > 0.01) {
                        return const SizedBox.shrink();
                      }
                      final date = points[index].date;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${date.day}/${date.month}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        ),
      ],
    );
  }

  List<FlSpot> _spots(
    List<LabElisaTrendPoint> points,
    double? Function(LabElisaTrendPoint point) select,
  ) {
    return [
      for (var index = 0; index < points.length; index++)
        if (select(points[index]) case final value?)
          FlSpot(index.toDouble(), value),
    ];
  }

  double? _average(LabElisaTrendPoint point) => switch (metric) {
    _LabTrendMetric.gmt => point.averageGmt,
    _LabTrendMetric.cv => point.averageCv,
    _LabTrendMetric.positive => point.positivePct,
  };

  double? _minimum(LabElisaTrendPoint point) => switch (metric) {
    _LabTrendMetric.gmt => point.minGmt,
    _LabTrendMetric.cv => point.minCv,
    _LabTrendMetric.positive => point.minPositivePct,
  };

  double? _maximum(LabElisaTrendPoint point) => switch (metric) {
    _LabTrendMetric.gmt => point.maxGmt,
    _LabTrendMetric.cv => point.maxCv,
    _LabTrendMetric.positive => point.maxPositivePct,
  };

  double? _pooled(LabElisaTrendPoint point) => switch (metric) {
    _LabTrendMetric.gmt => point.pooledGmt,
    _LabTrendMetric.cv => point.pooledCv,
    _LabTrendMetric.positive => point.pooledPositivePct,
  };

  double _interval(double maxY) {
    if (metric == _LabTrendMetric.positive) return 25;
    if (metric == _LabTrendMetric.cv) {
      if (maxY <= 50) return 10;
      return maxY <= 100 ? 20 : 25;
    }
    if (maxY <= 5000) return 1000;
    if (maxY <= 12000) return 2000;
    return 5000;
  }

  String _axisValue(double value) {
    if (metric == _LabTrendMetric.gmt) {
      return value >= 1000
          ? '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k'
          : value.toStringAsFixed(0);
    }
    return '${value.toStringAsFixed(0)}%';
  }

  String _formatValue(double value) {
    if (metric == _LabTrendMetric.gmt) return value.toStringAsFixed(0);
    return '${value.toStringAsFixed(1)}%';
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}

class _LatestSnapshot extends StatelessWidget {
  const _LatestSnapshot({required this.point});

  final LabElisaTrendPoint point;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEEF6FF), Color(0xFFF7F4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius + 2),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('LATEST SNAPSHOT', style: AppTextStyles.caption),
          const SizedBox(height: AppSizes.spaceSm),
          _SnapshotValue(
            label: 'Average GMT',
            value: point.averageGmt?.toStringAsFixed(0) ?? '—',
            color: AppColors.primary,
          ),
          const Divider(height: AppSizes.spaceLg),
          _SnapshotValue(
            label: 'Average CV',
            value: point.averageCv == null
                ? '—'
                : '${point.averageCv!.toStringAsFixed(1)}%',
            color: AppColors.chart5,
          ),
          const Divider(height: AppSizes.spaceLg),
          _SnapshotValue(
            label: 'Positive',
            value: point.positivePct == null
                ? '—'
                : '${point.positivePct!.toStringAsFixed(1)}%',
            color: AppColors.statusGood,
          ),
        ],
      ),
    );
  }
}

class _SnapshotValue extends StatelessWidget {
  const _SnapshotValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: AppSizes.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              Text(value, style: AppTextStyles.title.copyWith(color: color)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScopeHeatmap extends StatelessWidget {
  const _ScopeHeatmap({required this.series});

  final LabElisaTrendSeries series;

  @override
  Widget build(BuildContext context) {
    final allGmt = series.scopePoints
        .map((point) => point.gmtTiter)
        .whereType<double>()
        .toList(growable: false);
    final minGmt = allGmt.isEmpty
        ? 0.0
        : allGmt.reduce((left, right) => math.min(left, right));
    final maxGmt = allGmt.isEmpty
        ? 1.0
        : allGmt.reduce((left, right) => math.max(left, right));
    final byKey = {
      for (final point in series.scopePoints)
        '${point.scope}|${point.date.toIso8601String()}': point,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 92),
              for (final date in series.points.map((point) => point.date))
                SizedBox(
                  width: 112,
                  child: Text(
                    '${date.day}/${date.month}/${date.year}',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceXs),
          for (final scope in series.scopes) ...[
            Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    scope,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final date in series.points.map((point) => point.date))
                  _HeatCell(
                    point: byKey['$scope|${date.toIso8601String()}'],
                    minGmt: minGmt,
                    maxGmt: maxGmt,
                  ),
              ],
            ),
            const SizedBox(height: AppSizes.spaceXs),
          ],
        ],
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.point,
    required this.minGmt,
    required this.maxGmt,
  });

  final LabElisaScopePoint? point;
  final double minGmt;
  final double maxGmt;

  @override
  Widget build(BuildContext context) {
    final gmt = point?.gmtTiter;
    final ratio = gmt == null || maxGmt <= minGmt
        ? 0.0
        : ((gmt - minGmt) / (maxGmt - minGmt)).clamp(0.0, 1.0);
    final color = gmt == null
        ? AppColors.statusNeutralBg
        : Color.lerp(AppColors.accentBg, AppColors.statusActiveBg, ratio)!;
    return Container(
      width: 106,
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: point == null
              ? AppColors.borderDefault
              : _severityBorder(point!.severity),
        ),
      ),
      child: point == null
          ? const Center(child: Text('—'))
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  gmt == null ? '—' : '${(gmt / 1000).toStringAsFixed(1)}k',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  point!.cvPct == null
                      ? 'CV —'
                      : 'CV ${point!.cvPct!.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
    );
  }

  Color _severityBorder(LabSeverity severity) {
    return switch (severity) {
      LabSeverity.normal => AppColors.statusGood.withValues(alpha: 0.28),
      LabSeverity.watch => AppColors.statusWarning.withValues(alpha: 0.32),
      LabSeverity.alert => AppColors.statusError.withValues(alpha: 0.42),
    };
  }
}
