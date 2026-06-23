import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/temp_converter.dart';
import '../../../../providers/app_provider.dart';
import '../../models/govee_capture_summary.dart';

/// Cumulative (by-visit) view for Govee environmental captures: average
/// temperature / RH across each capture date — axis chips, a metric×date table,
/// and a line chart for the selected metric. Self-contained (Govee is outside
/// the scope/param system), built client-side from the already-loaded captures.
class GoveeCumulativeView extends StatefulWidget {
  final List<GoveeCaptureSummary> captures;

  const GoveeCumulativeView({super.key, required this.captures});

  @override
  State<GoveeCumulativeView> createState() => _GoveeCumulativeViewState();
}

class _GoveeMetric {
  final String label;
  final int decimals;
  final bool percent;
  final double? Function(GoveeCaptureSummary) of;
  const _GoveeMetric(this.label, this.decimals, this.percent, this.of);
}

class _GoveeCumulativeViewState extends State<GoveeCumulativeView> {
  int _metric = 0;

  List<_GoveeMetric> _metrics(bool showCelsius) => [
    _GoveeMetric(
      showCelsius ? 'Temp °C' : 'Temp °F',
      1,
      false,
      (c) => _temperatureValue(c.capture.tempAvg, showCelsius),
    ),
    _GoveeMetric('RH %', 0, true, (c) => c.capture.rhAvg),
    _GoveeMetric('Temp CV%', 1, true, (c) => c.capture.tempCvPct),
    _GoveeMetric('RH CV%', 1, true, (c) => c.capture.rhCvPct),
  ];

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _dateLabel(String raw) {
    final d = DateTime.tryParse(raw);
    if (d != null) return '${d.day} ${_months[d.month - 1]}';
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final showCelsius =
        context.watch<AppProvider?>()?.tempUnit == TempUnit.celsius;
    final metrics = _metrics(showCelsius);
    // Group captures by date, oldest→newest (captureDate is ISO YYYY-MM-DD).
    final byDate = <String, List<GoveeCaptureSummary>>{};
    for (final c in widget.captures) {
      byDate.putIfAbsent(c.capture.captureDate, () => []).add(c);
    }
    final dates = byDate.keys.toList()..sort();
    if (dates.isEmpty) {
      return const _Note('No Govee captures to chart yet.');
    }

    // Per-metric average per date (null when no readings that date).
    num? avg(String date, _GoveeMetric m) {
      final vals = byDate[date]!.map(m.of).whereType<double>().toList();
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a + b) / vals.length;
    }

    final selected = _metric.clamp(0, metrics.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSizes.spaceSm),
        _chips(dates, byDate),
        const SizedBox(height: AppSizes.spaceSm),
        _table(dates, avg, metrics, selected),
        const SizedBox(height: AppSizes.spaceMd),
        _chart(dates, avg, metrics, selected),
      ],
    );
  }

  Widget _chips(
    List<String> dates,
    Map<String, List<GoveeCaptureSummary>> byDate,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final d in dates)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accentBg,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              _dateLabel(d),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
          ),
      ],
    );
  }

  String _fmt(_GoveeMetric m, num? v) => v == null
      ? '—'
      : '${v.toStringAsFixed(m.decimals)}${m.percent ? '%' : ''}';

  Widget _table(
    List<String> dates,
    num? Function(String, _GoveeMetric) avg,
    List<_GoveeMetric> metrics,
    int selected,
  ) {
    const paramW = 96.0;
    const dateW = 64.0;
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
            Container(
              color: AppColors.surfaceVariant,
              child: Row(
                children: [
                  _cell('METRIC', paramW, header: true, left: true),
                  for (final d in dates)
                    _cell(_dateLabel(d), dateW, header: true),
                ],
              ),
            ),
            for (var i = 0; i < metrics.length; i++)
              Material(
                color: i == selected ? AppColors.accentBg : Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _metric = i),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: i == metrics.length - 1
                              ? Colors.transparent
                              : AppColors.borderDefault,
                        ),
                        left: BorderSide(
                          color: i == selected
                              ? AppColors.accent
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        _cell(
                          metrics[i].label,
                          paramW - 2.5,
                          left: true,
                          weight: FontWeight.w800,
                        ),
                        for (final d in dates)
                          _cell(_fmt(metrics[i], avg(d, metrics[i])), dateW),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    String text,
    double width, {
    bool header = false,
    bool left = false,
    FontWeight? weight,
  }) {
    return Container(
      width: width,
      height: header ? 30 : 34,
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Text(
        text,
        style: TextStyle(
          fontSize: header ? 9.5 : 12,
          fontWeight: weight ?? (header ? FontWeight.w900 : FontWeight.w700),
          letterSpacing: header ? 0.3 : 0,
          color: header ? AppColors.textSecondary : AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _chart(
    List<String> dates,
    num? Function(String, _GoveeMetric) avg,
    List<_GoveeMetric> metrics,
    int selected,
  ) {
    final m = metrics[selected];
    final spots = <FlSpot>[];
    for (var i = 0; i < dates.length; i++) {
      final v = avg(dates[i], m);
      if (v != null) spots.add(FlSpot(i.toDouble(), v.toDouble()));
    }
    if (spots.isEmpty) {
      return const _Note('Nothing to chart for this metric.');
    }
    final ys = spots.map((s) => s.y).toList();
    var minY = ys.reduce(math.min);
    var maxY = ys.reduce(math.max);
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
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: m.label),
                  const TextSpan(
                    text: '  across visits',
                    style: TextStyle(
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
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (dates.length - 1).toDouble(),
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
                        if (i < 0 ||
                            i >= dates.length ||
                            (v - i).abs() > 0.01) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _dateLabel(dates[i]),
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
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    color: AppColors.accent,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                        radius: 3.6,
                        color: AppColors.accent,
                        strokeColor: Colors.white,
                        strokeWidth: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double? _temperatureValue(double? fahrenheit, bool showCelsius) {
  if (fahrenheit == null) return null;
  return showCelsius ? TempConverter.toCelsius(fahrenheit) : fahrenheit;
}

class _Note extends StatelessWidget {
  final String text;

  const _Note(this.text);

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
