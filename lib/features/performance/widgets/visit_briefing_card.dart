import 'package:hatchaudit/localized_material.dart';

import '../../../data/models/farm_visit_models.dart';

class VisitBriefingCard extends StatelessWidget {
  const VisitBriefingCard({
    super.key,
    required this.briefing,
    required this.houseIds,
  });

  final VisitBriefingSnapshot briefing;
  final List<String> houseIds;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_outlined),
                const SizedBox(width: 8),
                Text(
                  context.tr('Visit briefing'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final houseId in houseIds)
                  Chip(label: Text('${context.tr('House')} $houseId')),
                if (briefing.targetVersion != null)
                  Chip(
                    label: Text(
                      '${context.tr('Target version')}: '
                      '${briefing.targetVersion}',
                    ),
                  ),
                if (briefing.ruleVersion != null)
                  Chip(
                    label: Text(
                      '${context.tr('Rule version')}: ${briefing.ruleVersion}',
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            Text(
              context.tr('Daily performance evidence'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 7),
            Container(
              key: const ValueKey('visit-daily-data-readonly'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: briefing.evidence.isEmpty
                  ? Text(context.tr('No daily evidence in this briefing'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in briefing.evidence.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              _evidenceSummary(entry.key, entry.value),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 7),
            Text(
              context.tr(
                'Daily facts are read-only here; record only visit evidence.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _evidenceSummary(String key, Object? value) {
  if (value is Map) {
    final summary = value['evidenceSummary'];
    if (summary != null && summary.toString().isNotEmpty) {
      return summary.toString();
    }
    final metric = value['metricKey']?.toString() ?? key;
    final actual = value['actualValue'];
    final target = value['targetValue'];
    return [
      metric.replaceAll('_', ' '),
      if (actual != null) 'actual $actual',
      if (target != null) 'target $target',
    ].join(' · ');
  }
  return '$key · $value';
}
