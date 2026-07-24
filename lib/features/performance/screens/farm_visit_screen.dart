import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../data/models/farm_visit_models.dart';
import '../providers/farm_visit_provider.dart';
import '../widgets/cause_assessment_card.dart';
import '../widgets/visit_briefing_card.dart';
import '../widgets/visit_investigation_card.dart';

class FarmVisitScreen extends StatefulWidget {
  const FarmVisitScreen({super.key, this.visitId, this.provider});

  final String? visitId;
  final FarmVisitProvider? provider;

  @override
  State<FarmVisitScreen> createState() => _FarmVisitScreenState();
}

class _FarmVisitScreenState extends State<FarmVisitScreen> {
  late final FarmVisitProvider _provider;
  late final bool _ownsProvider;

  @override
  void initState() {
    super.initState();
    _ownsProvider = widget.provider == null;
    _provider = widget.provider ?? FarmVisitProvider();
    if (_provider.visit == null && widget.visitId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _provider.loadVisit(widget.visitId!),
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
      child: const _FarmVisitView(),
    );
  }
}

class _FarmVisitView extends StatelessWidget {
  const _FarmVisitView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Diagnostic farm visit'),
      body: Consumer<FarmVisitProvider>(
        builder: (context, provider, _) {
          final visit = provider.visit;
          if (provider.isLoading && visit == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (visit == null) {
            return Center(
              child: Text(
                context.tr(provider.error ?? 'No farm visit selected'),
              ),
            );
          }
          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  VisitBriefingCard(
                    briefing: visit.briefing,
                    houseIds: visit.houseIds,
                  ),
                  const SizedBox(height: 14),
                  _SectionHeader(
                    title: 'Investigations',
                    icon: Icons.search_outlined,
                    action: TextButton.icon(
                      onPressed: () => _addInvestigation(context, provider),
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('Add investigation')),
                    ),
                  ),
                  if (visit.investigations.isEmpty)
                    _EmptyText(message: 'No investigations added')
                  else
                    for (final investigation in visit.investigations)
                      VisitInvestigationCard(
                        investigation: investigation,
                        findings: visit.findings
                            .where(
                              (finding) =>
                                  finding.investigationId == investigation.id,
                            )
                            .toList(),
                        onComplete:
                            investigation.status ==
                                InvestigationStatus.completed
                            ? null
                            : () => _completeInvestigation(
                                context,
                                provider,
                                investigation,
                              ),
                        onAddFinding: () =>
                            _addFinding(context, provider, investigation),
                      ),
                  const SizedBox(height: 14),
                  _SectionHeader(
                    title: 'Probable causes',
                    icon: Icons.account_tree_outlined,
                    action: TextButton.icon(
                      onPressed: () => _addCause(context, provider),
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('Add cause')),
                    ),
                  ),
                  if (visit.causeAssessments.isEmpty)
                    _EmptyText(message: 'No causes assessed')
                  else
                    for (final cause in visit.causeAssessments)
                      CauseAssessmentCard(
                        cause: cause,
                        onStatusChanged: (status) =>
                            provider.setCauseStatus(cause.id, status),
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
      bottomNavigationBar: Consumer<FarmVisitProvider>(
        builder: (context, provider, _) {
          final visit = provider.visit;
          if (visit == null || visit.status == FarmVisitStatus.completed) {
            return const SizedBox.shrink();
          }
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: provider.isLoading
                    ? null
                    : visit.status == FarmVisitStatus.planned
                    ? provider.startVisit
                    : provider.completeVisit,
                icon: Icon(
                  visit.status == FarmVisitStatus.planned
                      ? Icons.play_arrow_outlined
                      : Icons.check_circle_outline,
                ),
                label: Text(
                  context.tr(
                    visit.status == FarmVisitStatus.planned
                        ? 'Start visit'
                        : 'Complete visit',
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addInvestigation(
    BuildContext context,
    FarmVisitProvider provider,
  ) async {
    final type = TextEditingController();
    final instruction = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Add manual investigation')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: type,
              decoration: InputDecoration(
                labelText: context.tr('Investigation type'),
              ),
            ),
            TextField(
              controller: instruction,
              maxLines: 3,
              decoration: InputDecoration(labelText: context.tr('Instruction')),
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
            child: Text(context.tr('Add')),
          ),
        ],
      ),
    );
    if (accepted == true &&
        type.text.trim().isNotEmpty &&
        instruction.text.trim().isNotEmpty) {
      await provider.addManualInvestigation(
        investigationType: type.text.trim(),
        instruction: instruction.text.trim(),
      );
    }
    type.dispose();
    instruction.dispose();
  }

  Future<void> _completeInvestigation(
    BuildContext context,
    FarmVisitProvider provider,
    VisitInvestigation investigation,
  ) async {
    final result = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Complete investigation')),
        content: TextField(
          controller: result,
          maxLines: 4,
          decoration: InputDecoration(labelText: context.tr('Result summary')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('Complete')),
          ),
        ],
      ),
    );
    if (accepted == true && result.text.trim().isNotEmpty) {
      await provider.completeInvestigation(
        investigation.id,
        result.text.trim(),
      );
    }
    result.dispose();
  }

  Future<void> _addFinding(
    BuildContext context,
    FarmVisitProvider provider,
    VisitInvestigation investigation,
  ) async {
    final type = TextEditingController(text: investigation.investigationType);
    final value = TextEditingController();
    final unit = TextEditingController();
    final location = TextEditingController(text: investigation.location);
    final explanation = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Add visit finding')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: type,
                decoration: InputDecoration(
                  labelText: context.tr('Finding type'),
                ),
              ),
              TextField(
                controller: value,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.tr('Measured value'),
                ),
              ),
              TextField(
                controller: unit,
                decoration: InputDecoration(labelText: context.tr('Unit')),
              ),
              TextField(
                controller: location,
                decoration: InputDecoration(labelText: context.tr('Location')),
              ),
              TextField(
                controller: explanation,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.tr('Staff explanation'),
                ),
              ),
            ],
          ),
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
    );
    final visit = provider.visit;
    if (accepted == true && visit != null && type.text.trim().isNotEmpty) {
      await provider.addFinding(
        VisitFindingDraft(
          visitId: visit.id,
          investigationId: investigation.id,
          findingType: type.text.trim(),
          measuredValue: double.tryParse(value.text),
          unit: unit.text.trim().isEmpty ? null : unit.text.trim(),
          houseId: investigation.houseId,
          location: location.text.trim().isEmpty ? null : location.text.trim(),
          staffExplanation: explanation.text.trim().isEmpty
              ? null
              : explanation.text.trim(),
        ),
      );
    }
    for (final controller in [type, value, unit, location, explanation]) {
      controller.dispose();
    }
  }

  Future<void> _addCause(
    BuildContext context,
    FarmVisitProvider provider,
  ) async {
    final visit = provider.visit;
    if (visit == null || visit.briefing.concernIds.isEmpty) return;
    var concernId = visit.briefing.concernIds.first;
    final cause = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('Add suspected cause')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: concernId,
                decoration: InputDecoration(
                  labelText: context.tr('Performance concern'),
                ),
                items: [
                  for (final id in visit.briefing.concernIds)
                    DropdownMenuItem(value: id, child: Text(id)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => concernId = value);
                  }
                },
              ),
              TextField(
                controller: cause,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.tr('Suspected cause'),
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
              child: Text(context.tr('Add')),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && cause.text.trim().isNotEmpty) {
      await provider.addCauseAssessment(
        CauseAssessmentDraft(
          visitId: visit.id,
          concernId: concernId,
          probableCause: cause.text.trim(),
        ),
      );
    }
    cause.dispose();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.action,
  });

  final String title;
  final IconData icon;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            context.tr(title),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        action,
      ],
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(context.tr(message)),
    );
  }
}
