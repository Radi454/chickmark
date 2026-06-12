import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../models/scope_cumulative.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import '../../scope/scope_models.dart';
import 'scope_severity_style.dart';

/// Cumulative view for one sector: the same pooled parameter values spread across
/// the sector's axis (flock ages or audit visits) — axis chips, a params×period
/// table (severity-colored, with a trend arrow), and an Act-vs-BMK line chart for
/// the selected parameter. Read-only; data comes pre-built from the provider.
class ScopeCumulativeView extends StatefulWidget {
  final String sectorId;

  const ScopeCumulativeView({super.key, required this.sectorId});

  @override
  State<ScopeCumulativeView> createState() => _ScopeCumulativeViewState();
}

class _ScopeCumulativeViewState extends State<ScopeCumulativeView> {
  int? _selectedParam;

  @override
  void initState() {
    super.initState();
    // Kick the lazy load if the toggle didn't (e.g. view built directly).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ScopeComparisonProvider>().loadCumulative(widget.sectorId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScopeComparisonProvider>();
    final series = provider.cumulativeSeriesFor(widget.sectorId);
    final loading = provider.isCumulativeLoading(widget.sectorId);

    if (series == null || loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (series.isEmpty) {
      return const _CumNote('No cumulative data for this customer / flock yet.');
    }

    final sector = ScopeConfigRegistry.byId(widget.sectorId);
    final headline = _headlineIndex(series);
    final selected = (_selectedParam ?? headline)
        .clamp(0, series.params.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSizes.spaceMd),
        _AxisChips(periods: series.periods, axis: sector.cumulativeAxis),
        const SizedBox(height: AppSizes.spaceSm),
        _CumTable(
          series: series,
          selected: selected,
          onPick: (i) => setState(() => _selectedParam = i),
        ),
        const SizedBox(height: AppSizes.spaceMd),
        _CumChart(series: series, paramIndex: selected, axis: sector.cumulativeAxis),
      ],
    );
  }

  /// Default the chart to the first benchmarked param (else the first param).
  int _headlineIndex(CumulativeSeries s) {
    for (var i = 0; i < s.params.length; i++) {
      if (s.params[i].hasBmk) return i;
    }
    return 0;
  }
}

// ── axis chips ────────────────────────────────────────────────────────────────
class _AxisChips extends StatelessWidget {
  final List<ScopePeriod> periods;
  final CumulativeAxis axis;

  const _AxisChips({required this.periods, required this.axis});

  @override
  Widget build(BuildContext context) {
    final isAge = axis == CumulativeAxis.age;
    final bg = isAge ? AppColors.statusActiveBg : AppColors.accentBg;
    final fg = isAge ? AppColors.statusActive : AppColors.accent;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in periods)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              border: Border.all(color: fg.withValues(alpha: 0.22)),
            ),
            child: Text(
              p.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
      ],
    );
  }
}

// ── params × period table ─────────────────────────────────────────────────────
class _CumTable extends StatelessWidget {
  final CumulativeSeries series;
  final int selected;
  final ValueChanged<int> onPick;

  const _CumTable({
    required this.series,
    required this.selected,
    required this.onPick,
  });

  static const double _paramW = 96;
  static const double _periodW = 62;
  static const double _trendW = 34;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerRow(),
            for (var i = 0; i < series.params.length; i++)
              _paramRow(i, i == selected, i == series.params.length - 1),
          ],
        ),
      ),
    );
  }

  Widget _headerRow() {
    return Container(
      color: AppColors.surfaceVariant,
      child: Row(
        children: [
          _cell('PARAM', _paramW, header: true, align: TextAlign.left),
          for (final p in series.periods)
            _cell(p.label, _periodW, header: true),
          _cell('TREND', _trendW, header: true),
        ],
      ),
    );
  }

  Widget _paramRow(int i, bool isSelected, bool isLast) {
    final cp = series.params[i];
    return Material(
      color: isSelected ? AppColors.statusActiveBg : Colors.transparent,
      child: InkWell(
        onTap: () => onPick(i),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isLast ? Colors.transparent : AppColors.borderDefault,
              ),
              left: BorderSide(
                color: isSelected ? AppColors.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            children: [
              _cell(
                cp.param.label,
                _paramW - 2.5,
                align: TextAlign.left,
                weight: FontWeight.w800,
              ),
              for (var pi = 0; pi < series.periods.length; pi++)
                _severityCell(cp, pi),
              SizedBox(
                width: _trendW,
                height: 34,
                child: Center(child: _trendArrow(cp)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _severityCell(CumulativeParam cp, int pi) {
    final style = ScopeSeverityStyle.of(cp.severities[pi]);
    return Container(
      width: _periodW,
      height: 34,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      color: style.cellBg,
      child: Text(
        cp.texts[pi],
        style: TextStyle(
          fontSize: 12,
          fontWeight: style.weight == FontWeight.w500
              ? FontWeight.w700
              : style.weight,
          color: style.cellText,
        ),
      ),
    );
  }

  Widget _trendArrow(CumulativeParam cp) {
    final t = cp.trend;
    if (t == 0) {
      return const Icon(Icons.trending_flat, size: 16, color: AppColors.textTertiary);
    }
    // Direction is just up/down; color reflects better/worse given higherIsBetter.
    final better = cp.param.higherIsBetter ? t > 0 : t < 0;
    return Icon(
      t > 0 ? Icons.north : Icons.south,
      size: 14,
      color: better ? AppColors.statusGood : AppColors.statusError,
    );
  }

  Widget _cell(
    String text,
    double width, {
    bool header = false,
    TextAlign align = TextAlign.right,
    FontWeight? weight,
  }) {
    return Container(
      width: width,
      height: header ? 30 : 34,
      alignment:
          align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: header ? 9.5 : 12,
          fontWeight: weight ?? (header ? FontWeight.w900 : FontWeight.w700),
          letterSpacing: header ? 0.3 : 0,
          color: header ? AppColors.textSecondary : AppColors.textPrimary,
        ),
      ),
    );
  }
}

// ── Act vs BMK line chart ─────────────────────────────────────────────────────
class _CumChart extends StatelessWidget {
  final CumulativeSeries series;
  final int paramIndex;
  final CumulativeAxis axis;

  const _CumChart({
    required this.series,
    required this.paramIndex,
    required this.axis,
  });

  @override
  Widget build(BuildContext context) {
    final cp = series.params[paramIndex];
    final n = series.periods.length;

    // Spots (skip null values so a gap doesn't crash the line).
    final actSpots = <FlSpot>[];
    final actSev = <ScopeSeverity>[];
    for (var i = 0; i < n; i++) {
      final v = cp.values[i];
      if (v != null) {
        actSpots.add(FlSpot(i.toDouble(), v.toDouble()));
        actSev.add(cp.severities[i]);
      }
    }
    final bmkSpots = <FlSpot>[];
    for (var i = 0; i < n; i++) {
      final b = cp.bmks[i];
      if (b != null) bmkSpots.add(FlSpot(i.toDouble(), b.toDouble()));
    }

    final all = [
      ...actSpots.map((s) => s.y),
      ...bmkSpots.map((s) => s.y),
    ];
    if (all.isEmpty) {
      return const _CumNote('Nothing to chart for this parameter.');
    }
    var minY = all.reduce(math.min);
    var maxY = all.reduce(math.max);
    final pad = (maxY - minY) * 0.22;
    minY -= pad == 0 ? (maxY.abs() * 0.05 + 1) : pad;
    maxY += pad == 0 ? (maxY.abs() * 0.05 + 1) : pad;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: cp.param.label),
                        TextSpan(
                          text:
                              '  across ${axis == CumulativeAxis.age ? 'ages' : 'visits'}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const _ChartLegend(),
              ],
            ),
          ),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (n - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                lineTouchData: const LineTouchData(enabled: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
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
                      reservedSize: 34,
                      getTitlesWidget: (v, meta) {
                        if (v == meta.max || v == meta.min) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          v.toStringAsFixed(maxY - minY >= 10 ? 0 : 1),
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
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) {
                        final i = v.round();
                        if (i < 0 || i >= n || (v - i).abs() > 0.01) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            series.periods[i].label,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  if (bmkSpots.isNotEmpty)
                    LineChartBarData(
                      spots: bmkSpots,
                      isCurved: false,
                      color: AppColors.chartBenchmark,
                      barWidth: 2,
                      dashArray: const [5, 4],
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                          radius: 2.5,
                          color: AppColors.chartBenchmark,
                          strokeWidth: 0,
                        ),
                      ),
                    ),
                  LineChartBarData(
                    spots: actSpots,
                    isCurved: false,
                    color: AppColors.primary,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                        radius: 3.6,
                        color: ScopeSeverityStyle.dotColor(
                          i < actSev.length ? actSev[i] : ScopeSeverity.good,
                        ),
                        strokeColor: Colors.white,
                        strokeWidth: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8),
            child: Text(
              cp.hasBmk
                  ? 'Act vs Standard (BMK) per ${axis == CumulativeAxis.age ? 'age' : 'visit'}.'
                  : 'No benchmark for this metric — actual trend only.',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        _Swatch(color: AppColors.primary, label: 'Actual'),
        SizedBox(width: 10),
        _Swatch(color: AppColors.chartBenchmark, label: 'Standard'),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final String label;

  const _Swatch({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _CumNote extends StatelessWidget {
  final String text;

  const _CumNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
