import 'package:hatchaudit/localized_material.dart';

import '../../../data/models/corrective_action_models.dart';
import '../../../data/models/farm_visit_models.dart';

class PerformanceActionsPanel extends StatelessWidget {
  const PerformanceActionsPanel({
    super.key,
    required this.visits,
    required this.actions,
    this.onVisitTap,
    this.onActionTap,
  });

  final List<FarmVisitSession> visits;
  final List<CorrectiveAction> actions;
  final ValueChanged<FarmVisitSession>? onVisitTap;
  final ValueChanged<CorrectiveAction>? onActionTap;

  @override
  Widget build(BuildContext context) {
    if (visits.isEmpty && actions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(context.tr('No visits or corrective actions yet')),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (visits.isNotEmpty) ...[
          Text(context.tr('Farm visits')),
          const SizedBox(height: 6),
          for (final visit in visits)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: onVisitTap == null ? null : () => onVisitTap!(visit),
                leading: const Icon(Icons.fact_check_outlined),
                title: Text(_dateLabel(visit.visitDate)),
                subtitle: Text(context.tr(_visitStatus(visit.status))),
              ),
            ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(context.tr('Corrective actions')),
          const SizedBox(height: 6),
          for (final action in actions)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: onActionTap == null ? null : () => onActionTap!(action),
                leading: const Icon(Icons.task_alt_outlined),
                title: Text(action.instruction),
                subtitle: Text(
                  [
                    if (action.ownerName != null) action.ownerName!,
                    context.tr(_actionStatus(action.status)),
                  ].join(' · '),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

String _visitStatus(FarmVisitStatus status) {
  switch (status) {
    case FarmVisitStatus.planned:
      return 'Planned';
    case FarmVisitStatus.inProgress:
      return 'In progress';
    case FarmVisitStatus.completed:
      return 'Completed';
    case FarmVisitStatus.cancelled:
      return 'Cancelled';
  }
}

String _actionStatus(CorrectiveActionStatus status) {
  switch (status) {
    case CorrectiveActionStatus.open:
      return 'Open';
    case CorrectiveActionStatus.inProgress:
      return 'In progress';
    case CorrectiveActionStatus.implemented:
      return 'Implemented';
    case CorrectiveActionStatus.completed:
      return 'Completed';
    case CorrectiveActionStatus.cancelled:
      return 'Cancelled';
  }
}

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.year}';
