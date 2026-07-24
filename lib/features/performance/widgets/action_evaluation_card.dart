import 'package:hatchaudit/localized_material.dart';

import '../../../data/models/corrective_action_models.dart';

class ActionEvaluationCard extends StatelessWidget {
  const ActionEvaluationCard({
    super.key,
    required this.evaluation,
    this.onRecordDecision,
  });

  final ActionKpiEvaluation evaluation;
  final VoidCallback? onRecordDecision;

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
                Expanded(
                  child: Text(
                    evaluation.kpiKey.replaceAll('_', ' '),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(_effectivenessLabel(evaluation.effectiveness)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _EvidenceChip(
                  label: 'Before',
                  value: _format(evaluation.baselineValue),
                ),
                _EvidenceChip(
                  label: 'Target',
                  value: _format(evaluation.targetValue),
                ),
                _EvidenceChip(
                  label: 'After',
                  value: evaluation.observedValue == null
                      ? '—'
                      : _format(evaluation.observedValue!),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_dateLabel(evaluation.evaluationStart)} – '
              '${_dateLabel(evaluation.evaluationEnd)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (evaluation.evaluationReason != null) ...[
              const SizedBox(height: 6),
              Text(evaluation.evaluationReason!),
            ],
            if (onRecordDecision != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: onRecordDecision,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(context.tr('Record evaluation decision')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('${context.tr(label)} $value'));
  }
}

String _effectivenessLabel(ActionEffectiveness effectiveness) {
  switch (effectiveness) {
    case ActionEffectiveness.effective:
      return 'Effective';
    case ActionEffectiveness.partiallyEffective:
      return 'Partially effective';
    case ActionEffectiveness.ineffective:
      return 'Ineffective';
    case ActionEffectiveness.notEvaluated:
      return 'Not evaluated';
  }
}

String _format(double value) => value.toStringAsFixed(2);

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.year}';
