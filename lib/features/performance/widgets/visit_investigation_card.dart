import 'package:hatchaudit/localized_material.dart';

import '../../../data/models/farm_visit_models.dart';

class VisitInvestigationCard extends StatelessWidget {
  const VisitInvestigationCard({
    super.key,
    required this.investigation,
    required this.findings,
    this.onComplete,
    this.onAddFinding,
  });

  final VisitInvestigation investigation;
  final List<VisitFinding> findings;
  final VoidCallback? onComplete;
  final VoidCallback? onAddFinding;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  investigation.origin == InvestigationOrigin.suggested
                      ? Icons.auto_awesome_outlined
                      : Icons.person_add_alt_outlined,
                  size: 20,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    investigation.instruction,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Chip(
                  label: Text(context.tr(_statusLabel(investigation.status))),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              [
                context.tr(
                  investigation.origin == InvestigationOrigin.suggested
                      ? 'Suggested'
                      : 'Manual',
                ),
                if (investigation.houseId != null)
                  '${context.tr('House')} ${investigation.houseId}',
                if (investigation.location != null) investigation.location!,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (investigation.resultSummary != null) ...[
              const SizedBox(height: 8),
              Text(investigation.resultSummary!),
            ],
            for (final finding in findings) ...[
              const Divider(height: 18),
              Row(
                children: [
                  const Icon(Icons.science_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_findingSummary(finding))),
                ],
              ),
              if (finding.staffExplanation != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${context.tr('Staff explanation')}: '
                    '${finding.staffExplanation}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (finding.attachmentRefs.isNotEmpty)
                Text(
                  '${finding.attachmentRefs.length} '
                  '${context.tr('attachments')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (investigation.status != InvestigationStatus.completed &&
                    onComplete != null)
                  TextButton.icon(
                    onPressed: onComplete,
                    icon: const Icon(Icons.check_outlined),
                    label: Text(context.tr('Complete investigation')),
                  ),
                if (onAddFinding != null)
                  TextButton.icon(
                    onPressed: onAddFinding,
                    icon: const Icon(Icons.add_chart_outlined),
                    label: Text(context.tr('Add finding')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _findingSummary(VisitFinding finding) {
  final measurement = finding.measuredValue == null
      ? null
      : '${finding.measuredValue} ${finding.unit ?? ''}'.trim();
  return [
    finding.findingType.replaceAll('_', ' '),
    if (finding.location != null) finding.location!,
    ?measurement,
  ].join(' · ');
}

String _statusLabel(InvestigationStatus status) {
  switch (status) {
    case InvestigationStatus.pending:
      return 'Pending';
    case InvestigationStatus.inProgress:
      return 'In progress';
    case InvestigationStatus.completed:
      return 'Completed';
    case InvestigationStatus.notApplicable:
      return 'Not applicable';
  }
}
