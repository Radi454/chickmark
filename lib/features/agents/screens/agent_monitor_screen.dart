import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../data/models/hatchery_agent_models.dart';
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
    return Consumer<AgentMonitorProvider>(
      builder: (context, provider, _) {
        final enabled = provider.settings.telegramEnabled;
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
              Expanded(child: _MonitorWorkspace(provider: provider)),
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
  const _MonitorWorkspace({required this.provider});

  final AgentMonitorProvider provider;

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
              Expanded(child: _BatchDetails(details: provider.selectedBatch)),
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
            Expanded(child: _BatchDetails(details: provider.selectedBatch)),
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
  const _BatchDetails({required this.details});

  final HatcheryDraftBatchDetails? details;

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
          ...value.rows.map((row) => HatcheryDraftRowCard(row: row)),
          const SizedBox(height: AppSizes.spaceMd),
          _AuditHistoryCard(events: value.events),
          const SizedBox(height: AppSizes.spaceXl),
        ],
      ),
    );
  }
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
