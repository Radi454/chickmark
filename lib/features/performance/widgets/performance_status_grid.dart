import 'package:hatchaudit/localized_material.dart';

import '../models/broiler_performance_models.dart';

class PerformanceStatusGrid extends StatelessWidget {
  const PerformanceStatusGrid({super.key, required this.metrics});

  final Map<String, PerformanceMetric> metrics;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) {
      return const _EmptyMessage(
        message: 'No daily performance data for this period',
      );
    }
    final ordered = [
      for (final key in _preferredMetricOrder)
        if (metrics.containsKey(key)) metrics[key]!,
      for (final entry in metrics.entries)
        if (!_preferredMetricOrder.contains(entry.key)) entry.value,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final metric in ordered)
              SizedBox(
                width: width,
                child: _MetricCard(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final PerformanceMetric metric;

  @override
  Widget build(BuildContext context) {
    final value = metric.value;
    final color = _directionColor(context, metric.direction);
    return Semantics(
      label: context.tr(_metricLabel(metric.key)),
      value: value == null
          ? context.tr(metric.missingReason ?? 'Unavailable')
          : '${_format(value)} ${metric.unit}',
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(_metricLabel(metric.key)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value == null ? '—' : _format(value),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: value == null ? null : color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (value != null && metric.unit.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(metric.unit),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 5),
              Text(
                value == null
                    ? context.tr(metric.missingReason ?? 'Unavailable')
                    : _targetText(context, metric),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _targetText(BuildContext context, PerformanceMetric metric) {
    if (metric.targetValue == null) return context.tr('Current value');
    return '${context.tr('Target')} ${_format(metric.targetValue!)} '
        '${metric.unit}';
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(child: Text(context.tr(message))),
    );
  }
}

const _preferredMetricOrder = <String>[
  'age_day',
  'average_live_birds',
  'weight_deviation_pct',
  'daily_mortality_pct',
  'cumulative_mortality_pct',
  'livability_pct',
  'feed_per_live_bird_g',
  'water_to_feed_ratio',
  'uniformity_pct',
  'fcr',
];

String _metricLabel(String key) {
  const labels = <String, String>{
    'age_day': 'Current age',
    'average_live_birds': 'Live population',
    'weight_deviation_pct': 'Weight versus target',
    'daily_mortality_pct': 'Daily mortality',
    'cumulative_mortality_pct': 'Cumulative mortality',
    'livability_pct': 'Livability',
    'feed_per_live_bird_g': 'Feed per live bird',
    'cumulative_feed_kg': 'Cumulative feed',
    'cumulative_feed_per_placed_bird_g': 'Feed per placed bird',
    'water_per_live_bird_ml': 'Water per live bird',
    'water_to_feed_ratio': 'Water-to-feed ratio',
    'average_daily_gain_g': 'Average daily gain',
    'uniformity_pct': 'Uniformity',
    'cv_pct': 'CV',
    'target_adjusted_cumulative_feed_kg': 'Expected cumulative feed',
    'cumulative_feed_deviation_pct': 'Feed versus target',
    'fcr': 'Estimated FCR',
    'epef': 'EPEF',
  };
  return labels[key] ?? key.replaceAll('_', ' ');
}

String _format(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.abs() >= 100
      ? value.toStringAsFixed(1)
      : value.toStringAsFixed(2);
}

Color _directionColor(BuildContext context, PerformanceDirection direction) {
  switch (direction) {
    case PerformanceDirection.improving:
      return Colors.green.shade700;
    case PerformanceDirection.worsening:
      return Theme.of(context).colorScheme.error;
    case PerformanceDirection.stable:
    case PerformanceDirection.neutral:
    case PerformanceDirection.unknown:
      return Theme.of(context).colorScheme.onSurface;
  }
}
