import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../data/models/hatchery_agent_models.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../widgets/app_card.dart';
import '../providers/agent_monitor_provider.dart';
import '../widgets/agent_submission_card.dart';
import '../widgets/hatchery_draft_row_card.dart';

class AgentMonitorScreen extends StatefulWidget {
  const AgentMonitorScreen({super.key});

  @override
  State<AgentMonitorScreen> createState() => _AgentMonitorScreenState();
}

class _AgentMonitorScreenState extends State<AgentMonitorScreen> {
  bool _loadRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadRequested) return;
    _loadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AgentMonitorProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AgentMonitorProvider, AuthProvider>(
      builder: (context, provider, auth, _) {
        final enabled = provider.settings.telegramEnabled;
        final adminUserId = auth.user?.isAdmin == true ? auth.user!.id : null;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: GradientAppBar(
            title: 'Agent Monitor',
            actions: [
              IconButton(
                tooltip: context.tr('Refresh'),
                onPressed: provider.isLoading ? null : provider.load,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                key: const ValueKey('telegram-agent-toggle'),
                tooltip: context.tr(
                  enabled ? 'Pause Telegram agent' : 'Resume Telegram agent',
                ),
                onPressed: provider.isLoading
                    ? null
                    : () => provider.setTelegramEnabled(!enabled),
                icon: Icon(
                  enabled ? Icons.pause_circle_outline : Icons.play_circle,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              _AgentStateBar(enabled: enabled),
              if (provider.isLoading)
                const LinearProgressIndicator(minHeight: 2),
              if (provider.error != null)
                _ErrorBanner(
                  message: provider.error!,
                  onRetry: provider.isLoading ? null : provider.load,
                ),
              Expanded(
                child: _MonitorWorkspace(
                  provider: provider,
                  adminUserId: adminUserId,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AgentStateBar extends StatelessWidget {
  const _AgentStateBar({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.statusGood : AppColors.statusWarning;
    final background = enabled
        ? AppColors.statusGoodBg
        : AppColors.statusWarningBg;
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceLg,
          vertical: AppSizes.spaceSm,
        ),
        color: background,
        child: Row(
          children: [
            Icon(
              enabled ? Icons.telegram : Icons.pause_circle_outline,
              color: color,
              size: AppSizes.iconSm,
            ),
            const SizedBox(width: AppSizes.spaceSm),
            Text(
              enabled ? 'Telegram running' : 'Telegram paused',
              style: AppTextStyles.subtitle.copyWith(color: color),
            ),
            if (constraints.maxWidth >= 600) ...[
              const Spacer(),
              Text(
                enabled
                    ? 'New submissions are accepted'
                    : 'New submissions paused',
                style: AppTextStyles.caption.copyWith(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.statusErrorBg,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceLg,
        vertical: AppSizes.spaceSm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.statusError,
            size: AppSizes.iconSm,
          ),
          const SizedBox(width: AppSizes.spaceSm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body.copyWith(color: AppColors.statusError),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _MonitorWorkspace extends StatelessWidget {
  const _MonitorWorkspace({required this.provider, this.adminUserId});

  final AgentMonitorProvider provider;
  final String? adminUserId;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading && provider.batches.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.batches.isEmpty) {
      return const _EmptyMonitor();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 960) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 340,
                child: _BatchList(
                  provider: provider,
                  padding: const EdgeInsets.all(AppSizes.spaceMd),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _BatchDetails(
                  details: provider.selectedBatch,
                  provider: provider,
                  adminUserId: adminUserId,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            SizedBox(
              height: 230,
              child: _BatchList(
                provider: provider,
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.spaceMd,
                  AppSizes.spaceMd,
                  AppSizes.spaceMd,
                  AppSizes.spaceSm,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _BatchDetails(
                details: provider.selectedBatch,
                provider: provider,
                adminUserId: adminUserId,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BatchList extends StatelessWidget {
  const _BatchList({required this.provider, required this.padding});

  final AgentMonitorProvider provider;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final selectedId = provider.selectedBatch?.batch.id;
    return ListView.builder(
      key: const ValueKey('agent-batch-list'),
      padding: padding,
      itemCount: provider.batches.length,
      itemBuilder: (context, index) {
        final summary = provider.batches[index];
        return AgentSubmissionCard(
          summary: summary,
          isSelected: summary.id == selectedId,
          onTap: () => provider.selectBatch(summary.id),
        );
      },
    );
  }
}

class _BatchDetails extends StatelessWidget {
  const _BatchDetails({
    required this.details,
    required this.provider,
    this.adminUserId,
  });

  final HatcheryDraftBatchDetails? details;
  final AgentMonitorProvider provider;
  final String? adminUserId;

  @override
  Widget build(BuildContext context) {
    final value = details;
    if (value == null) {
      return const Center(child: Text('Select a submission to review'));
    }

    return SingleChildScrollView(
      key: const ValueKey('agent-batch-details'),
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SourceEvidenceCard(details: value),
          if (value.questions.isNotEmpty) ...[
            const SizedBox(height: AppSizes.spaceMd),
            _QuestionsCard(questions: value.questions),
          ],
          const SizedBox(height: AppSizes.spaceLg),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Extracted rows',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              Text('${value.rows.length} rows', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          ...value.rows.map(
            (row) => HatcheryDraftRowCard(
              row: row,
              onEdit: adminUserId == null ? null : () => _editRow(context, row),
              onApprove: adminUserId == null
                  ? null
                  : () => provider.approveRow(row.id, adminUserId!),
              onReject: adminUserId == null
                  ? null
                  : () => _rejectRow(context, row),
            ),
          ),
          const SizedBox(height: AppSizes.spaceMd),
          _AuditHistoryCard(events: value.events),
          const SizedBox(height: AppSizes.spaceXl),
        ],
      ),
    );
  }

  Future<void> _editRow(BuildContext context, HatcheryDraftRow row) async {
    final edited = await showDialog<HatcheryDraftRow>(
      context: context,
      builder: (_) => _EditDraftRowDialog(row: row),
    );
    if (edited != null) {
      await provider.saveRowEdit(edited);
    }
  }

  Future<void> _rejectRow(BuildContext context, HatcheryDraftRow row) async {
    final decision = await showDialog<_RejectRowDecision>(
      context: context,
      builder: (_) => const _RejectDraftRowDialog(),
    );
    final reviewerId = adminUserId;
    if (decision != null && reviewerId != null) {
      await provider.rejectRow(row.id, reviewerId, reason: decision.reason);
    }
  }
}

class _RejectRowDecision {
  const _RejectRowDecision(this.reason);

  final String? reason;
}

class _RejectDraftRowDialog extends StatefulWidget {
  const _RejectDraftRowDialog();

  @override
  State<_RejectDraftRowDialog> createState() => _RejectDraftRowDialogState();
}

class _RejectDraftRowDialogState extends State<_RejectDraftRowDialog> {
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject row'),
      content: TextField(
        key: const ValueKey('agent-rejection-reason'),
        controller: _reasonController,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Rejection reason (optional)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('agent-confirm-rejection'),
          onPressed: () {
            final reason = _reasonController.text.trim();
            Navigator.of(
              context,
            ).pop(_RejectRowDecision(reason.isEmpty ? null : reason));
          },
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

enum _DraftInputKind { text, integer, decimal, date }

class _DraftFieldSpec {
  const _DraftFieldSpec({
    required this.keyName,
    required this.label,
    this.kind = _DraftInputKind.text,
    this.widgetKey,
  });

  final String keyName;
  final String label;
  final _DraftInputKind kind;
  final String? widgetKey;
}

const _draftFieldSpecs = <_DraftFieldSpec>[
  _DraftFieldSpec(keyName: 'customerName', label: 'Customer'),
  _DraftFieldSpec(keyName: 'customerId', label: 'Customer ID'),
  _DraftFieldSpec(keyName: 'flockName', label: 'Flock'),
  _DraftFieldSpec(keyName: 'flockId', label: 'Flock ID'),
  _DraftFieldSpec(keyName: 'hatcheryId', label: 'Hatchery ID'),
  _DraftFieldSpec(
    keyName: 'stationName',
    label: 'Station',
    widgetKey: 'agent-edit-station-name',
  ),
  _DraftFieldSpec(keyName: 'breed', label: 'Breed'),
  _DraftFieldSpec(
    keyName: 'eggsPlaced',
    label: 'Eggs placed',
    kind: _DraftInputKind.integer,
  ),
  _DraftFieldSpec(
    keyName: 'productionDate',
    label: 'Production date',
    kind: _DraftInputKind.date,
  ),
  _DraftFieldSpec(
    keyName: 'placementDate',
    label: 'Placement date',
    kind: _DraftInputKind.date,
  ),
  _DraftFieldSpec(
    keyName: 'eggWeightG',
    label: 'Egg weight',
    kind: _DraftInputKind.decimal,
  ),
  _DraftFieldSpec(
    keyName: 'fertilityPct',
    label: 'Fertility',
    kind: _DraftInputKind.decimal,
  ),
  _DraftFieldSpec(
    keyName: 'transferWeightG',
    label: 'Transfer weight',
    kind: _DraftInputKind.decimal,
  ),
  _DraftFieldSpec(keyName: 'setterNumber', label: 'Setter'),
  _DraftFieldSpec(keyName: 'hatcherNumber', label: 'Hatcher'),
  _DraftFieldSpec(
    keyName: 'hatchDate',
    label: 'Hatch date',
    kind: _DraftInputKind.date,
    widgetKey: 'agent-edit-hatch-date',
  ),
  _DraftFieldSpec(
    keyName: 'healthyChicks',
    label: 'Healthy chicks',
    kind: _DraftInputKind.integer,
  ),
  _DraftFieldSpec(
    keyName: 'secondGradeChicks',
    label: 'Second grade',
    kind: _DraftInputKind.integer,
  ),
  _DraftFieldSpec(
    keyName: 'condemnedChicks',
    label: 'Condemned',
    kind: _DraftInputKind.integer,
  ),
  _DraftFieldSpec(
    keyName: 'totalProduction',
    label: 'Total production',
    kind: _DraftInputKind.integer,
  ),
  _DraftFieldSpec(
    keyName: 'hatchabilityPct',
    label: 'Hatchability',
    kind: _DraftInputKind.decimal,
  ),
  _DraftFieldSpec(
    keyName: 'confidencePct',
    label: 'Confidence',
    kind: _DraftInputKind.decimal,
  ),
  _DraftFieldSpec(
    keyName: 'proposedFlockAgeWeeks',
    label: 'Proposed flock age',
    kind: _DraftInputKind.integer,
  ),
];

class _EditDraftRowDialog extends StatefulWidget {
  const _EditDraftRowDialog({required this.row});

  final HatcheryDraftRow row;

  @override
  State<_EditDraftRowDialog> createState() => _EditDraftRowDialogState();
}

class _EditDraftRowDialogState extends State<_EditDraftRowDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final row = widget.row;
    _controllers = {
      'customerName': _controller(row.customerName),
      'customerId': _controller(row.customerId),
      'flockName': _controller(row.flockName),
      'flockId': _controller(row.flockId),
      'hatcheryId': _controller(row.hatcheryId),
      'stationName': _controller(row.stationName),
      'breed': _controller(row.breed),
      'eggsPlaced': _controller(row.eggsPlaced),
      'productionDate': _controller(_dateInput(row.productionDate)),
      'placementDate': _controller(_dateInput(row.placementDate)),
      'eggWeightG': _controller(row.eggWeightG),
      'fertilityPct': _controller(row.fertilityPct),
      'transferWeightG': _controller(row.transferWeightG),
      'setterNumber': _controller(row.setterNumber),
      'hatcherNumber': _controller(row.hatcherNumber),
      'hatchDate': _controller(_dateInput(row.hatchDate)),
      'healthyChicks': _controller(row.healthyChicks),
      'secondGradeChicks': _controller(row.secondGradeChicks),
      'condemnedChicks': _controller(row.condemnedChicks),
      'totalProduction': _controller(row.totalProduction),
      'hatchabilityPct': _controller(row.hatchabilityPct),
      'confidencePct': _controller(row.confidencePct),
      'proposedFlockAgeWeeks': _controller(row.proposedFlockAgeWeeks),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit row'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Use YYYY-MM-DD for dates.'),
                const SizedBox(height: AppSizes.spaceMd),
                for (final field in _draftFieldSpecs) ...[
                  TextFormField(
                    key: field.widgetKey == null
                        ? null
                        : ValueKey(field.widgetKey!),
                    controller: _controllers[field.keyName],
                    keyboardType: _keyboardType(field.kind),
                    decoration: InputDecoration(labelText: field.label),
                    validator: (value) =>
                        _validateField(context, field.kind, value),
                  ),
                  const SizedBox(height: AppSizes.spaceSm),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('agent-save-row-edit'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    final row = widget.row;
    Navigator.of(context).pop(
      HatcheryDraftRow(
        id: row.id,
        batchId: row.batchId,
        rowOrdinal: row.rowOrdinal,
        status: row.status,
        customerId: _textValue('customerId'),
        customerName: _textValue('customerName'),
        flockId: _textValue('flockId'),
        flockName: _textValue('flockName'),
        hatcheryId: _textValue('hatcheryId'),
        stationName: _textValue('stationName'),
        breed: _textValue('breed'),
        eggsPlaced: _intValue('eggsPlaced'),
        productionDate: _dateValue('productionDate'),
        placementDate: _dateValue('placementDate'),
        eggWeightG: _doubleValue('eggWeightG'),
        fertilityPct: _doubleValue('fertilityPct'),
        transferWeightG: _doubleValue('transferWeightG'),
        setterNumber: _textValue('setterNumber'),
        hatcherNumber: _textValue('hatcherNumber'),
        hatchDate: _dateValue('hatchDate'),
        healthyChicks: _intValue('healthyChicks'),
        secondGradeChicks: _intValue('secondGradeChicks'),
        condemnedChicks: _intValue('condemnedChicks'),
        totalProduction: _intValue('totalProduction'),
        hatchabilityPct: _doubleValue('hatchabilityPct'),
        confidencePct: _doubleValue('confidencePct'),
        extractionJson: row.extractionJson,
        warningsJson: row.warningsJson,
        proposedFlockAgeWeeks: _intValue('proposedFlockAgeWeeks'),
        approvedRecordId: row.approvedRecordId,
        reviewedBy: row.reviewedBy,
        reviewedAt: row.reviewedAt,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      ),
    );
  }

  String? _textValue(String key) {
    final value = _controllers[key]!.text.trim();
    return value.isEmpty ? null : value;
  }

  int? _intValue(String key) => int.tryParse(_controllers[key]!.text.trim());

  double? _doubleValue(String key) {
    return double.tryParse(_controllers[key]!.text.trim());
  }

  DateTime? _dateValue(String key) {
    return _parseDateInput(_controllers[key]!.text);
  }
}

TextEditingController _controller(Object? value) {
  return TextEditingController(text: value?.toString() ?? '');
}

TextInputType _keyboardType(_DraftInputKind kind) {
  return switch (kind) {
    _DraftInputKind.integer => TextInputType.number,
    _DraftInputKind.decimal => const TextInputType.numberWithOptions(
      decimal: true,
    ),
    _DraftInputKind.text || _DraftInputKind.date => TextInputType.text,
  };
}

String? _validateField(
  BuildContext context,
  _DraftInputKind kind,
  String? source,
) {
  final value = source?.trim() ?? '';
  if (value.isEmpty) return null;
  final valid = switch (kind) {
    _DraftInputKind.text => true,
    _DraftInputKind.integer => int.tryParse(value) != null,
    _DraftInputKind.decimal => double.tryParse(value) != null,
    _DraftInputKind.date => _parseDateInput(value) != null,
  };
  return valid ? null : context.tr('Enter a valid value');
}

DateTime? _parseDateInput(String source) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(source.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

String? _dateInput(DateTime? value) {
  if (value == null) return null;
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

class _SourceEvidenceCard extends StatelessWidget {
  const _SourceEvidenceCard({required this.details});

  final HatcheryDraftBatchDetails details;

  @override
  Widget build(BuildContext context) {
    final submission = details.submission;
    final batch = details.batch;
    final source =
        submission.sourceText ??
        submission.sourceFileName ??
        submission.sourceRemotePath ??
        'Source unavailable';
    final submitter = submission.telegramUserId == null
        ? 'Unknown staff'
        : 'Telegram user ${submission.telegramUserId}';
    final status = agentSubmissionStatusPresentation(batch.status);

    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  batch.sourceSummary ?? 'Original Telegram source',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              AgentStatusChip(presentation: status),
            ],
          ),
          const SizedBox(height: AppSizes.spaceLg),
          _EvidenceLine(
            icon: Icons.person_outline,
            label: 'Staff submitter',
            value: submitter,
          ),
          _EvidenceLine(
            icon: Icons.attach_file,
            label: 'Source type',
            value: _sourceKindLabel(submission.sourceKind),
          ),
          _EvidenceLine(
            icon: Icons.schedule,
            label: 'Submitted',
            value: _formatTimestamp(submission.submittedAt),
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text('Original source', style: AppTextStyles.caption),
          const SizedBox(height: AppSizes.spaceXs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSizes.spaceMd),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
              border: Border.all(color: AppColors.borderDefault),
            ),
            child: Text(source, style: AppTextStyles.body),
          ),
        ],
      ),
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      child: Row(
        children: [
          Icon(icon, size: AppSizes.iconSm, color: AppColors.textSecondary),
          const SizedBox(width: AppSizes.spaceSm),
          SizedBox(
            width: 110,
            child: Text(label, style: AppTextStyles.caption),
          ),
          Expanded(child: Text(value, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}

class _QuestionsCard extends StatelessWidget {
  const _QuestionsCard({required this.questions});

  final List<HatcheryAgentQuestion> questions;

  @override
  Widget build(BuildContext context) {
    final isArabic = context.l10n.isArabic;
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Questions and answers', style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSizes.spaceMd),
          ...questions.map((question) {
            final prompt = isArabic
                ? question.questionTextAr
                : question.questionTextEn;
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: AppSizes.spaceSm),
              padding: const EdgeInsets.all(AppSizes.spaceMd),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(prompt, style: AppTextStyles.body),
                  const SizedBox(height: AppSizes.spaceXs),
                  Text(
                    question.answerText ?? 'Waiting for answer',
                    style: AppTextStyles.subtitle.copyWith(
                      color: question.answerText == null
                          ? AppColors.statusWarning
                          : AppColors.statusGood,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AuditHistoryCard extends StatelessWidget {
  const _AuditHistoryCard({required this.events});

  final List<HatcheryAgentAuditEvent> events;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Admin action history', style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSizes.spaceMd),
          if (events.isEmpty)
            Text('No admin actions yet', style: AppTextStyles.caption)
          else
            ...events.map(
              (event) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.history),
                title: Text(_eventLabel(event.eventType)),
                subtitle: Text(
                  '${event.actorId ?? event.actorType} · '
                  '${_formatTimestamp(event.createdAt)}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyMonitor extends StatelessWidget {
  const _EmptyMonitor();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.smart_toy_outlined,
              size: AppSizes.iconLg,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: AppSizes.spaceMd),
            Text('No agent submissions', style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSizes.spaceXs),
            Text(
              'Telegram submissions will appear here for review.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _sourceKindLabel(AgentSourceKind kind) {
  return switch (kind) {
    AgentSourceKind.text => 'Text',
    AgentSourceKind.image => 'Image',
    AgentSourceKind.pdf => 'PDF',
    AgentSourceKind.spreadsheet => 'Spreadsheet',
    AgentSourceKind.file => 'File',
  };
}

String _eventLabel(String value) {
  if (value == 'row_extracted') return 'Row extracted';
  if (value.isEmpty) return 'Agent event';
  final words = value.split('_');
  final label = words.join(' ');
  return '${label[0].toUpperCase()}${label.substring(1)}';
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
