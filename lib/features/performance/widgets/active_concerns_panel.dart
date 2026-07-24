import 'package:hatchaudit/localized_material.dart';

import '../../../data/models/performance_concern_models.dart';

class ActiveConcernsPanel extends StatelessWidget {
  const ActiveConcernsPanel({
    super.key,
    required this.concerns,
    this.onConcernTap,
  });

  final List<PerformanceConcern> concerns;
  final ValueChanged<PerformanceConcern>? onConcernTap;

  @override
  Widget build(BuildContext context) {
    if (concerns.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(child: Text(context.tr('No active concerns'))),
      );
    }
    return Column(
      children: [
        for (final concern in concerns)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: onConcernTap == null ? null : () => onConcernTap!(concern),
              leading: Icon(
                concern.severity == ConcernSeverity.critical
                    ? Icons.error_outline
                    : Icons.warning_amber_outlined,
                color: concern.severity == ConcernSeverity.critical
                    ? Theme.of(context).colorScheme.error
                    : Colors.orange.shade800,
              ),
              title: Text(
                context.tr(_metricLabel(concern.metricKey)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _evidenceText(context, concern),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Chip(
                label: Text(
                  context.tr(
                    concern.severity == ConcernSeverity.critical
                        ? 'Critical'
                        : 'Watch',
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _metricLabel(String key) => key
    .split('_')
    .map(
      (part) => part.isEmpty
          ? part
          : '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

String _evidenceText(BuildContext context, PerformanceConcern concern) {
  final actual = concern.actualValue;
  final target = concern.targetValue;
  if (actual == null) return context.tr('Evidence retained for investigation');
  if (target == null) return '${context.tr('Actual')} ${_format(actual)}';
  return '${context.tr('Actual')} ${_format(actual)} · '
      '${context.tr('Target')} ${_format(target)}';
}

String _format(double value) => value.toStringAsFixed(2);
