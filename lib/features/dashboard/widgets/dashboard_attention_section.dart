import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/models/dashboard_action_model.dart';
import '../../../widgets/app_card.dart';
import '../models/dashboard_intelligence_models.dart';
import '../providers/dashboard_provider.dart';
import '../providers/scope_comparison_provider.dart';
import '../scope/scope_config.dart';
import '../scope/scope_models.dart';
import 'dashboard_action_sheet.dart';
import 'scope/govee_triage_builder.dart';
import 'scope/scope_triage_builder.dart';

class DashboardAttentionSection extends StatelessWidget {
  const DashboardAttentionSection({super.key, required this.onOpenSource});

  final ValueChanged<DashboardFinding> onOpenSource;

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<ScopeComparisonProvider>();
    final dashboard = context.watch<DashboardProvider>();
    final findings = _findings(scope, dashboard);
    final critical = findings
        .where((finding) => finding.severity == ScopeSeverity.err)
        .length;
    final watch = findings.length - critical;
    return AppCard(
      key: const ValueKey('dashboard-attention-section'),
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.crisis_alert, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('What needs attention'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _SummaryPill(
                label: context.tr('$critical critical'),
                color: AppColors.statusError,
              ),
              const SizedBox(width: 6),
              _SummaryPill(
                label: context.tr('$watch watch'),
                color: AppColors.statusWarning,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              'Ranked by severity, persistence, freshness, and data confidence.',
            ),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSizes.spaceMd),
          if (findings.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSizes.spaceMd),
              decoration: BoxDecoration(
                color: AppColors.statusGoodBg,
                borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
              ),
              child: Text(
                context.tr(
                  'No current critical or watch findings in this operational scope.',
                ),
                style: const TextStyle(
                  color: AppColors.completedText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            for (final finding in findings.take(6)) ...[
              _FindingCard(
                finding: finding,
                action: dashboard.actionForFinding(finding.key),
                onOpenSource: () => onOpenSource(finding),
                onAction: dashboard.canManageActions
                    ? () => showDashboardActionSheet(
                        context,
                        finding: finding,
                        action: dashboard.actionForFinding(finding.key),
                      )
                    : null,
              ),
              if (finding != findings.take(6).last)
                const SizedBox(height: AppSizes.spaceSm),
            ],
        ],
      ),
    );
  }

  List<DashboardFinding> _findings(
    ScopeComparisonProvider scope,
    DashboardProvider dashboard,
  ) {
    final items = [
      for (final station in ScopeConfigRegistry.stations)
        ...stationTriageItems(scope, station),
      ...goveeTriageItems(dashboard.goveeCaptures),
    ].where((item) => item.isCritical || item.isWatch);
    final selected = <String, dynamic>{};
    for (final item in items) {
      final mergeKey = item.metricKey.isEmpty ? item.metric : item.metricKey;
      final current = selected[mergeKey];
      if (current == null ||
          _severityRank(item.severity) > _severityRank(current.severity)) {
        selected[mergeKey] = item;
      }
    }
    final customer = dashboard.selectedCustomerId ?? '';
    final hatchery = dashboard.selectedHatcheryId ?? '';
    final flock = dashboard.selectedFlockId ?? 'all-flocks';
    final out = <DashboardFinding>[];
    for (final entry in selected.entries) {
      final item = entry.value;
      final quality = item.sectorId.startsWith('govee_')
          ? const DashboardDataQuality()
          : scope.qualityFor(item.sectorId);
      final confidence = quality.expectedMetricCount == 0
          ? 0.7
          : quality.coverage.clamp(0.2, 1.0);
      final historyBoost = switch (item.history?.state) {
        MetricTrendState.worsening => 20,
        MetricTrendState.persistent => 12,
        MetricTrendState.newIssue => 8,
        _ => 0,
      };
      out.add(
        DashboardFinding(
          key: '$customer|$hatchery|$flock|${entry.key}',
          station: item.station,
          sectorId: item.sectorId,
          metricKey: item.metricKey,
          metricLabel: item.metric,
          valueText: item.value,
          severity: item.severity,
          rank: _severityRank(item.severity) * 100 + historyBoost + confidence,
          context: item.context,
          advice: item.advice,
          latestAt: item.observedAt,
          confidence: confidence,
          history: item.history,
          sessionId: item.sessionId,
          panelName: item.panelName,
          panelRowId: item.panelRowId,
        ),
      );
    }
    out.sort((a, b) => b.rank.compareTo(a.rank));
    return out;
  }

  int _severityRank(ScopeSeverity severity) => switch (severity) {
    ScopeSeverity.err => 3,
    ScopeSeverity.warn => 2,
    ScopeSeverity.good => 1,
    ScopeSeverity.pool => 0,
  };
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({
    required this.finding,
    required this.action,
    required this.onOpenSource,
    required this.onAction,
  });

  final DashboardFinding finding;
  final DashboardActionModel? action;
  final VoidCallback onOpenSource;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final color = finding.severity == ScopeSeverity.err
        ? AppColors.statusError
        : AppColors.statusWarning;
    final history = finding.history;
    return Semantics(
      button: true,
      label:
          '${context.tr(finding.metricLabel)}, ${finding.valueText}, ${context.tr(_historyLabel(history?.state))}',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _SummaryPill(
                  label: finding.severity == ScopeSeverity.err
                      ? context.tr('Critical')
                      : context.tr('Watch'),
                  color: color,
                ),
                _SummaryPill(label: finding.station, color: AppColors.primary),
                if (history != null)
                  _SummaryPill(
                    label: context.tr(_historyLabel(history.state)),
                    color: _historyColor(history.state),
                  ),
                if (action != null)
                  _SummaryPill(
                    label: context.tr(_actionStatusLabel(action!.status)),
                    color: AppColors.statusActive,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    context.tr(finding.metricLabel),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  finding.valueText,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
            if (finding.context.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                context.tr(finding.context),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (history?.delta != null) ...[
              const SizedBox(height: 4),
              Text(
                context.tr(
                  'Latest vs previous: ${history!.delta! >= 0 ? '+' : ''}${history.delta!.toStringAsFixed(1)}',
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onOpenSource,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(context.tr('View source')),
                ),
                if (onAction != null) ...[
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
                    onPressed: onAction,
                    icon: Icon(
                      action == null ? Icons.add_task : Icons.edit_note,
                      size: 17,
                    ),
                    label: Text(
                      context.tr(
                        action == null ? 'Create action' : 'Update action',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _historyLabel(MetricTrendState? state) => switch (state) {
    MetricTrendState.newIssue => 'New issue',
    MetricTrendState.persistent => 'Persistent',
    MetricTrendState.improving => 'Improving',
    MetricTrendState.worsening => 'Worsening',
    MetricTrendState.resolved => 'Resolved',
    MetricTrendState.stable => 'Stable',
    MetricTrendState.insufficient || null => 'First comparable result',
  };

  Color _historyColor(MetricTrendState state) => switch (state) {
    MetricTrendState.worsening ||
    MetricTrendState.newIssue => AppColors.statusError,
    MetricTrendState.persistent => AppColors.statusWarning,
    MetricTrendState.improving ||
    MetricTrendState.resolved => AppColors.statusGood,
    _ => AppColors.textSecondary,
  };

  String _actionStatusLabel(DashboardActionStatus status) => switch (status) {
    DashboardActionStatus.open => 'Action open',
    DashboardActionStatus.inProgress => 'Action in progress',
    DashboardActionStatus.resolved => 'Action resolved',
    DashboardActionStatus.reopened => 'Action reopened',
  };
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}
