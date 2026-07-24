import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../data/models/corrective_action_models.dart';
import '../providers/farm_visit_provider.dart';
import '../widgets/action_evaluation_card.dart';

class CorrectiveActionScreen extends StatefulWidget {
  const CorrectiveActionScreen({
    super.key,
    this.actionId,
    this.provider,
    this.concernId,
    this.visitId,
    this.causeAssessmentId,
    this.createdBy = 'local-user',
  });

  final String? actionId;
  final FarmVisitProvider? provider;
  final String? concernId;
  final String? visitId;
  final String? causeAssessmentId;
  final String createdBy;

  @override
  State<CorrectiveActionScreen> createState() => _CorrectiveActionScreenState();
}

class _CorrectiveActionScreenState extends State<CorrectiveActionScreen> {
  late final FarmVisitProvider _provider;
  late final bool _ownsProvider;

  @override
  void initState() {
    super.initState();
    _ownsProvider = widget.provider == null;
    _provider = widget.provider ?? FarmVisitProvider();
    if (_provider.action == null && widget.actionId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _provider.loadAction(widget.actionId!),
      );
    }
  }

  @override
  void dispose() {
    if (_ownsProvider) _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: _CorrectiveActionView(
        concernId: widget.concernId,
        visitId: widget.visitId,
        causeAssessmentId: widget.causeAssessmentId,
        createdBy: widget.createdBy,
      ),
    );
  }
}

class _CorrectiveActionView extends StatelessWidget {
  const _CorrectiveActionView({
    required this.concernId,
    required this.visitId,
    required this.causeAssessmentId,
    required this.createdBy,
  });

  final String? concernId;
  final String? visitId;
  final String? causeAssessmentId;
  final String createdBy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Corrective action'),
      body: Consumer<FarmVisitProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.action == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final action = provider.action;
          if (action == null) {
            if (concernId != null) {
              return _NewActionForm(
                provider: provider,
                concernId: concernId!,
                visitId: visitId,
                causeAssessmentId: causeAssessmentId,
                createdBy: createdBy,
              );
            }
            return Center(
              child: Text(
                context.tr(provider.error ?? 'No corrective action selected'),
              ),
            );
          }
          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _ActionSummary(action: action),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.analytics_outlined),
                      const SizedBox(width: 7),
                      Text(
                        context.tr('KPI effectiveness'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final evaluation in action.evaluations)
                    ActionEvaluationCard(
                      evaluation: evaluation,
                      onRecordDecision: () =>
                          _recordDecision(context, provider, evaluation),
                    ),
                  if (action.implementationConfirmedBy == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FilledButton.icon(
                        onPressed: () => provider.confirmActionImplementation(
                          confirmedBy: createdBy,
                          implementedAt: DateTime.now(),
                        ),
                        icon: const Icon(Icons.verified_outlined),
                        label: Text(context.tr('Confirm implementation')),
                      ),
                    ),
                ],
              ),
              if (provider.isLoading)
                const Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _recordDecision(
    BuildContext context,
    FarmVisitProvider provider,
    ActionKpiEvaluation evaluation,
  ) async {
    var effectiveness = evaluation.effectiveness;
    final observed = TextEditingController(
      text: evaluation.observedValue?.toString() ?? '',
    );
    final reason = TextEditingController(
      text: evaluation.evaluationReason ?? '',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('Record evaluation decision')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ActionEffectiveness>(
                initialValue: effectiveness,
                decoration: InputDecoration(
                  labelText: context.tr('Effectiveness'),
                ),
                items: [
                  for (final item in ActionEffectiveness.values)
                    DropdownMenuItem(
                      value: item,
                      child: Text(context.tr(_effectivenessLabel(item))),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => effectiveness = value);
                  }
                },
              ),
              TextField(
                controller: observed,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.tr('Observed value'),
                ),
              ),
              TextField(
                controller: reason,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.tr('Evaluation reason'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.tr('Save')),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await provider.recordEvaluation(
        evaluationId: evaluation.id,
        result: ActionEvaluationResult(
          effectiveness: effectiveness,
          baselineValue: evaluation.baselineValue,
          observedValue: double.tryParse(observed.text),
          reason: reason.text.trim().isEmpty
              ? 'Evaluation decision recorded by user.'
              : reason.text.trim(),
        ),
        evaluatedBy: createdBy,
        evaluatedAt: DateTime.now(),
      );
    }
    observed.dispose();
    reason.dispose();
  }
}

class _ActionSummary extends StatelessWidget {
  const _ActionSummary({required this.action});

  final CorrectiveAction action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action.instruction,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              '${context.tr('Owner')}: '
              '${action.ownerName ?? action.ownerId ?? '—'}',
            ),
            Text(
              '${context.tr('Due')}: '
              '${action.dueAt == null ? '—' : _dateLabel(action.dueAt!)}',
            ),
            Text(
              '${context.tr('Status')}: '
              '${context.tr(_actionStatus(action.status))}',
            ),
            if (action.implementationConfirmedBy != null)
              Text(
                '${context.tr('Implementation confirmed by')}: '
                '${action.implementationConfirmedBy}',
              ),
          ],
        ),
      ),
    );
  }
}

class _NewActionForm extends StatefulWidget {
  const _NewActionForm({
    required this.provider,
    required this.concernId,
    required this.visitId,
    required this.causeAssessmentId,
    required this.createdBy,
  });

  final FarmVisitProvider provider;
  final String concernId;
  final String? visitId;
  final String? causeAssessmentId;
  final String createdBy;

  @override
  State<_NewActionForm> createState() => _NewActionFormState();
}

class _NewActionFormState extends State<_NewActionForm> {
  final _formKey = GlobalKey<FormState>();
  final _instruction = TextEditingController();
  final _owner = TextEditingController();
  final _kpi = TextEditingController();
  final _baseline = TextEditingController();
  final _target = TextEditingController();

  @override
  void dispose() {
    _instruction.dispose();
    _owner.dispose();
    _kpi.dispose();
    _baseline.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _instruction,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.tr('Corrective action instruction'),
            ),
            validator: _required,
          ),
          TextFormField(
            controller: _owner,
            decoration: InputDecoration(labelText: context.tr('Owner')),
            validator: _required,
          ),
          TextFormField(
            controller: _kpi,
            decoration: InputDecoration(labelText: context.tr('Target KPI')),
            validator: _required,
          ),
          TextFormField(
            controller: _baseline,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.tr('Baseline value'),
            ),
            validator: _number,
          ),
          TextFormField(
            controller: _target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: context.tr('Target value')),
            validator: _number,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: widget.provider.isLoading ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(context.tr('Issue corrective action')),
          ),
        ],
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _number(String? value) =>
      double.tryParse(value ?? '') == null ? 'Enter a valid number' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    await widget.provider.createAction(
      CorrectiveActionDraft(
        concernId: widget.concernId,
        visitId: widget.visitId,
        causeAssessmentId: widget.causeAssessmentId,
        instruction: _instruction.text.trim(),
        ownerName: _owner.text.trim(),
        dueAt: now.add(const Duration(days: 1)),
        createdBy: widget.createdBy,
      ),
      evaluations: [
        ActionKpiEvaluationDefinition(
          kpiKey: _kpi.text.trim(),
          scope: const {},
          baselineWindowStart: now.subtract(const Duration(days: 3)),
          baselineWindowEnd: now,
          baselineValue: double.parse(_baseline.text),
          targetRule: ActionTargetRule.atLeast,
          targetValue: double.parse(_target.text),
          evaluationStart: now.add(const Duration(days: 1)),
          evaluationEnd: now.add(const Duration(days: 4)),
        ),
      ],
    );
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
