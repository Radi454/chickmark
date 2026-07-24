import 'dart:math' as math;

import 'package:hatchaudit/localized_material.dart';

import '../providers/performance_provider.dart';

class PerformanceTrendPanel extends StatelessWidget {
  const PerformanceTrendPanel({super.key, required this.points});

  final List<PerformanceTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(child: Text(context.tr('No trend data for this period'))),
      );
    }
    final availableKeys = <String>{
      for (final point in points)
        for (final entry in point.values.entries)
          if (entry.value != null) entry.key,
    };
    if (availableKeys.isEmpty) {
      return Center(child: Text(context.tr('No valid trend values')));
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final key in availableKeys)
          SizedBox(
            width: 280,
            child: _TrendCard(
              label: _trendLabel(key),
              values: [
                for (final point in points)
                  if (point.values[key] != null) point.values[key]!,
              ],
            ),
          ),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.label, required this.values});

  final String label;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(label),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              width: double.infinity,
              child: CustomPaint(
                painter: _LinePainter(
                  values,
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${context.tr('Latest')} ${_format(values.last)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue - minValue;
    final path = Path();
    for (var index = 0; index < values.length; index += 1) {
      final x = values.length == 1
          ? size.width / 2
          : index / (values.length - 1) * size.width;
      final normalized = range == 0 ? 0.5 : (values[index] - minValue) / range;
      final y = size.height - (normalized * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

String _trendLabel(String key) {
  const labels = <String, String>{
    'daily_mortality_pct': 'Daily mortality trend',
    'cumulative_mortality_pct': 'Cumulative mortality trend',
    'feed_kg': 'Daily feed consumption',
    'water_l': 'Daily water consumption',
    'weight_g': 'Body weight trend',
    'uniformity_pct': 'Uniformity trend',
    'fcr': 'Estimated FCR trend',
  };
  return labels[key] ?? key.replaceAll('_', ' ');
}

String _format(double value) =>
    value.abs() >= 100 ? value.toStringAsFixed(1) : value.toStringAsFixed(2);
