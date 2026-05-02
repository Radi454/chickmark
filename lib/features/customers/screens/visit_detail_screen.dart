import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/audit_type_labels.dart';
import '../../../core/utils/scorecard_formatter.dart';
import '../../../data/models/audit_session_model.dart';
import '../../../data/models/audit_model.dart';
import '../../../features/dashboard/models/govee_capture_summary.dart';
import '../../../features/dashboard/models/visit_session_summary.dart';
import '../../../features/dashboard/providers/dashboard_provider.dart';
import '../../../features/dashboard/widgets/govee_capture_chart.dart';

import '../../../providers/customers_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';

/// A read-only visit summary screen for both customer and internal users.
///
/// This screen intentionally contains no edit affordances. Staff who need to
/// edit an individual station audit should open the legacy audit editor from
/// the audit history list instead.
class VisitDetailScreen extends StatelessWidget {
  final VisitSessionSummary visit;

  const VisitDetailScreen({super.key, required this.visit});

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<AuthProvider>().user?.canEditAudits ?? false;
    final customersProvider = context.watch<CustomersProvider>();
    final dashboardProvider = context.watch<DashboardProvider>();
    final session = visit.session;
    final goveeSummaries =
        dashboardProvider.selectedVisitSession?.session.id == session.id
        ? dashboardProvider.goveeCaptures
        : const <GoveeCaptureSummary>[];
    final customerName =
        customersProvider.customerById(session.customerId)?.name ??
        session.customerId;
    final flockLabel =
        customersProvider.flockById(session.flockId)?.flockId ??
        session.flockId;

    return Scaffold(
      appBar: GradientAppBar(title: 'Visit Summary'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOverviewCard(session, customerName, flockLabel),
          const SizedBox(height: 16),
          _buildScorecardsSection(visit),
          if (visit.findingsSummary != null &&
              !visit.findingsSummary!.isEmpty) ...[
            const SizedBox(height: 16),
            _buildFindingsCard(visit.findingsSummary!),
          ],
          if (visit.pmScoreSummary != null) ...[
            const SizedBox(height: 16),
            _buildPmCard(visit.pmScoreSummary!),
          ],
          if (visit.hatchBudgetSummary != null) ...[
            const SizedBox(height: 16),
            _buildHatchBudgetCard(visit.hatchBudgetSummary!),
          ],
          if (goveeSummaries.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildGoveeCard(goveeSummaries),
          ],
          if (visit.stationAudits.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildStationAuditsSection(visit.stationAudits, canEdit),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewCard(
    AuditSessionModel session,
    String customerName,
    String flockLabel,
  ) {
    final completed = session.stationsCompleted.length;
    final total = session.selectedStationKeys.length;

    return Card(
      elevation: 0,
      color: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Visit ${session.date.day}/${session.date.month}/${session.date.year}',
                        style: AppTextStyles.heading.copyWith(fontSize: 22),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$completed of $total stations completed',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(session.status),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoPill(label: 'Customer', value: customerName),
                _InfoPill(label: 'Flock', value: flockLabel),
                if (session.breed != null)
                  _InfoPill(label: 'Breed', value: session.breed!),
                if (session.flockAgeWeeks != null)
                  _InfoPill(
                    label: 'Flock age',
                    value: '${session.flockAgeWeeks} weeks',
                  ),
              ],
            ),
            if (session.notes != null && session.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Notes', style: AppTextStyles.caption),
              const SizedBox(height: 4),
              Text(session.notes!, style: AppTextStyles.body),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final isComplete = status == 'completed';
    final color = isComplete ? const Color(0xFF3a9a5c) : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        isComplete ? 'Complete' : 'In progress',
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildScorecardsSection(VisitSessionSummary visit) {
    if (visit.scorecards.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Station Scorecards',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: visit.scorecards.map((sc) {
                final color = ScorecardFormatter.statusColor(sc.status);
                return Chip(
                  avatar: CircleAvatar(backgroundColor: color, radius: 8),
                  label: Text(
                    '${sc.stationLabel}: ${ScorecardFormatter.statusLabel(sc.status)}',
                  ),
                  backgroundColor: color.withValues(alpha: 0.10),
                  side: BorderSide(color: color.withValues(alpha: 0.18)),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFindingsCard(SessionFindingsSummary findings) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Findings',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (findings.greenCount > 0)
                  _findingChip(
                    'Good',
                    findings.greenCount,
                    const Color(0xFF3a9a5c),
                  ),
                if (findings.amberCount > 0)
                  _findingChip(
                    'Caution',
                    findings.amberCount,
                    const Color(0xFFE6A23C),
                  ),
                if (findings.redCount > 0)
                  _findingChip(
                    'Critical',
                    findings.redCount,
                    const Color(0xFFE24B4A),
                  ),
              ],
            ),
            if (findings.findings.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...findings.findings.take(5).map((f) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${f.title}${f.recommendedAction != null ? ' — ${f.recommendedAction}' : ''}',
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _findingChip(String label, int count, Color color) {
    return Chip(
      label: Text('$label: $count'),
      backgroundColor: color.withValues(alpha: 0.10),
      side: BorderSide(color: color.withValues(alpha: 0.18)),
    );
  }

  Widget _buildPmCard(PmScoreSummary pm) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PM Necropsy',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _MetricChip(label: 'Lesions', value: '${pm.totalLesions}'),
                _MetricChip(
                  label: 'Deformities',
                  value: '${pm.totalDeformities}',
                ),
                if (pm.gaspingPresent)
                  _MetricChip(label: 'Gasping', value: pm.gaspingType ?? 'Yes'),
                if (pm.overallSeverity != null)
                  _MetricChip(label: 'Severity', value: pm.overallSeverity!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHatchBudgetCard(HatchBudgetSummary hb) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hatch Budget',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _MetricChip(label: 'Set', value: '${hb.totalEggsSet}'),
                _MetricChip(label: 'Hatched', value: '${hb.healthyHatched}'),
                _MetricChip(label: 'Culled', value: '${hb.culled}'),
                _MetricChip(label: 'Dead', value: '${hb.deadAtHatch}'),
                if (hb.hatchabilityPct != null)
                  _MetricChip(
                    label: 'Hatch%',
                    value: '${hb.hatchabilityPct!.toStringAsFixed(1)}%',
                  ),
                if (hb.fertilityPct != null)
                  _MetricChip(
                    label: 'Fertility%',
                    value: '${hb.fertilityPct!.toStringAsFixed(1)}%',
                  ),
                if (hb.hofPct != null)
                  _MetricChip(
                    label: 'HOF%',
                    value: '${hb.hofPct!.toStringAsFixed(1)}%',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoveeCard(List<GoveeCaptureSummary> summaries) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Govee Readings',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...summaries.map(
              (summary) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GoveeCaptureChart(summary: summary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationAuditsSection(List<AuditModel> audits, bool canEdit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Station Details',
          style: AppTextStyles.heading.copyWith(fontSize: 18),
        ),
        const SizedBox(height: 10),
        ...audits.map((audit) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _StationAuditReadOnlyCard(audit: audit),
          );
        }),
      ],
    );
  }
}

class _StationAuditReadOnlyCard extends StatelessWidget {
  final AuditModel audit;

  const _StationAuditReadOnlyCard({required this.audit});

  @override
  Widget build(BuildContext context) {
    final metrics = _metricsForAudit();
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AuditTypeLabels.forAuditType(audit.auditType),
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (metrics.isEmpty)
              Text('No values recorded yet', style: AppTextStyles.caption)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: metrics
                    .map((m) => _MetricChip(label: m.label, value: m.value))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  List<_Metric> _metricsForAudit() {
    final List<_Metric> metrics = [];
    switch (audit.auditType) {
      case 'Chick Quality':
        if (audit.pasgarFinalScore != null) {
          metrics.add(
            _Metric('Pasgar', audit.pasgarFinalScore!.toStringAsFixed(1)),
          );
        }
        if (audit.chickAvgWeight != null) {
          metrics.add(
            _Metric(
              'Avg weight',
              '${audit.chickAvgWeight!.toStringAsFixed(1)}g',
            ),
          );
        }
        if (audit.chickCvPct != null) {
          metrics.add(
            _Metric('CV%', '${audit.chickCvPct!.toStringAsFixed(1)}%'),
          );
        }
        if (audit.cvtAvg != null) {
          metrics.add(
            _Metric('CVT avg', '${audit.cvtAvg!.toStringAsFixed(1)}°F'),
          );
        }
      case 'Hatch Analysis':
        if (audit.haHatchability != null) {
          metrics.add(
            _Metric(
              'Hatchability',
              '${audit.haHatchability!.toStringAsFixed(1)}%',
            ),
          );
        }
        if (audit.haFertility != null) {
          metrics.add(
            _Metric('Fertility', '${audit.haFertility!.toStringAsFixed(1)}%'),
          );
        }
        if (audit.haHof != null) {
          metrics.add(_Metric('HOF', '${audit.haHof!.toStringAsFixed(1)}%'));
        }
        if (audit.haTotalEggsSet != null) {
          metrics.add(_Metric('Eggs set', '${audit.haTotalEggsSet}'));
        }
      case 'Setter Optimizing':
        if (audit.soSetterId != null) {
          metrics.add(_Metric('Setter', audit.soSetterId!));
        }
        if (audit.soEstAvg != null) {
          metrics.add(
            _Metric('EST avg', '${audit.soEstAvg!.toStringAsFixed(1)}°F'),
          );
        }
        if (audit.soCo2 != null) {
          metrics.add(_Metric('CO2', '${audit.soCo2!.toStringAsFixed(0)} ppm'));
        }
      case 'Hatcher Optimizing':
        if (audit.hoHatcherId != null) {
          metrics.add(_Metric('Hatcher', audit.hoHatcherId!));
        }
        if (audit.hoCvtAvg != null) {
          metrics.add(
            _Metric('CVT avg', '${audit.hoCvtAvg!.toStringAsFixed(1)}°F'),
          );
        }
        if (audit.hoCo2 != null) {
          metrics.add(_Metric('CO2', '${audit.hoCo2!.toStringAsFixed(0)} ppm'));
        }
      case 'Egg Storage':
        if (audit.esShellTemp != null) {
          metrics.add(
            _Metric('Shell temp', '${audit.esShellTemp!.toStringAsFixed(1)}°F'),
          );
        }
        if (audit.esTurningTimes != null) {
          metrics.add(_Metric('Turning', '${audit.esTurningTimes}'));
        }
        if (audit.esEggAvgWeight != null) {
          metrics.add(
            _Metric(
              'Avg weight',
              '${audit.esEggAvgWeight!.toStringAsFixed(1)}g',
            ),
          );
        }
    }
    return metrics;
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: RichText(
        text: TextSpan(
          style: AppTextStyles.caption.copyWith(color: Colors.black87),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric {
  final String label;
  final String value;

  const _Metric(this.label, this.value);
}
