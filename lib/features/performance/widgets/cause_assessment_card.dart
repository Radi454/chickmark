import 'package:hatchaudit/localized_material.dart';

import '../../../data/models/farm_visit_models.dart';

class CauseAssessmentCard extends StatelessWidget {
  const CauseAssessmentCard({
    super.key,
    required this.cause,
    required this.onStatusChanged,
  });

  final CauseAssessment cause;
  final ValueChanged<CauseAssessmentStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cause.probableCause,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${context.tr('Concern')}: ${cause.concernId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (cause.supportingEvidenceIds.isNotEmpty)
              Text(
                '${cause.supportingEvidenceIds.length} '
                '${context.tr('supporting evidence items')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 10),
            DropdownButtonFormField<CauseAssessmentStatus>(
              key: ValueKey('cause-status-${cause.id}'),
              initialValue: cause.status,
              decoration: InputDecoration(
                labelText: context.tr('Cause status'),
              ),
              items: [
                for (final status in CauseAssessmentStatus.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(context.tr(_statusLabel(status))),
                  ),
              ],
              onChanged: (status) {
                if (status != null && status != cause.status) {
                  onStatusChanged(status);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(CauseAssessmentStatus status) {
  switch (status) {
    case CauseAssessmentStatus.suspected:
      return 'Suspected';
    case CauseAssessmentStatus.probable:
      return 'Probable';
    case CauseAssessmentStatus.confirmed:
      return 'Confirmed';
    case CauseAssessmentStatus.ruledOut:
      return 'Ruled out';
  }
}
