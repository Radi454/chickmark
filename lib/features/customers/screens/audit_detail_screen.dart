import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/security/security_policy.dart';
import '../../../core/utils/audit_type_labels.dart';
import '../../../data/models/audit_model.dart';

import '../../../widgets/status_badge.dart';
import '../../../providers/customers_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../audits/providers/audit_provider.dart';
import '../../audits/screens/audit_context_screen.dart';
import '../../audits/screens/chick_quality_screen.dart';
import '../../audits/screens/egg_storage_screen.dart';
import '../../audits/screens/hatch_analysis_screen.dart';
import '../../audits/screens/hatcher_optimizing_screen.dart';
import '../../audits/screens/setter_optimizing_screen.dart';

Future<void> openAuditEditor(
  BuildContext context,
  AuditModel audit, {
  int sectionIndex = 0,
}) {
  final flock = context.read<CustomersProvider>().flockById(audit.flockId);
  final contextData = AuditContextData(
    auditType: audit.auditType,
    customerId: audit.customerId,
    flockId: audit.flockId ?? '',
    breed: audit.soBreed ?? audit.hoBreed ?? flock?.breed,
    setterId: audit.setterId ?? audit.soSetterId,
    hatcherId: audit.hatcherId ?? audit.hoHatcherId,
    flockEntryDate: flock?.entryDate,
    flockAgeWeeks: flock?.currentAgeWeeks.toInt(),
    date: audit.date.toIso8601String().split('T')[0],
  );

  final screen = switch (audit.auditType) {
    'Chicks' => ChickQualityScreen(
      context: contextData,
      initialAudit: audit,
      initialTabIndex: sectionIndex,
    ),
    'Hatch Analysis & Egg Breakouts' => HatchAnalysisScreen(
      context: contextData,
      initialAudit: audit,
      initialSectionIndex: sectionIndex,
    ),
    'Setters' => SetterOptimizingScreen(
      context: contextData,
      initialAudit: audit,
      initialSectionIndex: sectionIndex,
    ),
    'Hatchers' => HatcherOptimizingScreen(
      context: contextData,
      initialAudit: audit,
      initialSectionIndex: sectionIndex,
    ),
    'Egg' => EggStorageScreen(
      context: contextData,
      initialAudit: audit,
      initialSectionIndex: sectionIndex,
    ),
    _ => null,
  };

  if (screen == null) return Future<void>.value();
  return Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (context) =>
          ChangeNotifierProvider(create: (_) => AuditProvider(), child: screen),
    ),
  );
}

class AuditDetailScreen extends StatelessWidget {
  final AuditModel audit;

  const AuditDetailScreen({super.key, required this.audit});

  @override
  Widget build(BuildContext context) {
    final canEdit =
        AuthSecurityPolicy.isDebugAuthBypassEnabled ||
        (context.watch<AuthProvider>().user?.canEditAudits ?? false);
    final sections = _sectionsForAudit();

    return Scaffold(
      appBar: GradientAppBar(
        title: 'Audit Summary',
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Edit audit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _openAuditScreen(context),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOverviewCard(context),
          const SizedBox(height: 16),
          Text(
            'Audit Sections',
            style: AppTextStyles.heading.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 10),
          if (sections.isEmpty)
            _emptySection()
          else
            ...sections.map(
              (section) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SummarySectionCard(
                  section: section,
                  actionLabel: canEdit ? 'Edit' : null,
                  onEdit: canEdit
                      ? () => _openAuditScreen(
                          context,
                          sectionIndex: section.sectionIndex,
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(BuildContext context) {
    final setterId = audit.setterId ?? audit.soSetterId;
    final hatcherId = audit.hatcherId ?? audit.hoHatcherId;
    final breed = audit.soBreed ?? audit.hoBreed;

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
                        AuditTypeLabels.forAuditType(audit.auditType),
                        style: AppTextStyles.heading.copyWith(fontSize: 22),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(audit.date),
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                StatusBadge(status: audit.status),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoPill(label: 'Customer', value: audit.customerId),
                _InfoPill(label: 'Flock', value: audit.flockId ?? '--'),
                if (breed != null) _InfoPill(label: 'Breed', value: breed),
                if (setterId != null)
                  _InfoPill(label: 'Setter', value: setterId),
                if (hatcherId != null)
                  _InfoPill(label: 'Hatcher', value: hatcherId),
                _InfoPill(label: 'Hatch', value: '${audit.hatchNumber}'),
                if (audit.sessionId != null)
                  _InfoPill(label: 'Visit', value: 'Session-linked'),
              ],
            ),
            if (audit.notes != null && audit.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Notes', style: AppTextStyles.caption),
              const SizedBox(height: 4),
              Text(audit.notes!, style: AppTextStyles.body),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptySection() {
    return Card(
      elevation: 0,
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No summary values have been recorded for this audit yet.',
          style: AppTextStyles.body,
        ),
      ),
    );
  }

  List<_AuditSummarySection> _sectionsForAudit() {
    return switch (audit.auditType) {
      'Chicks' => _chickQualitySections(),
      'Hatch Analysis & Egg Breakouts' => _hatchAnalysisSections(),
      'Setters' => _setterSections(),
      'Hatchers' => _hatcherSections(),
      'Egg' => _eggStorageSections(),
      _ => [],
    };
  }

  List<_AuditSummarySection> _chickQualitySections() {
    return [
      _section(
        title: 'CHA Environmental',
        icon: Icons.air,
        sectionIndex: 0,
        metrics: [
          _metric('CO2', _ppm(audit.chaCo2)),
          _metric('PM10', _unit(audit.chaPm10, 'ug/m3')),
          _metric('PM2.5', _unit(audit.chaPm25, 'ug/m3')),
          _metric('Air inlet', _celsius(audit.chaAirInlet)),
          _metric('Air outlet', _celsius(audit.chaAirOutlet)),
          _metric('Noise', _unit(audit.chaNoiseLevel, 'dB')),
        ],
      ),
      _section(
        title: 'Pasgar',
        icon: Icons.fact_check_outlined,
        sectionIndex: 1,
        metrics: [
          _metric('Sample', audit.pasgarSampleSize?.toString()),
          _metric('Final score', _fixed(audit.pasgarFinalScore)),
          _metric('Reflexes', audit.pasgarReflexes?.toString()),
          _metric('Navel', audit.pasgarNavel?.toString()),
        ],
      ),
      _section(
        title: 'Weights',
        icon: Icons.monitor_weight_outlined,
        sectionIndex: 2,
        metrics: [
          _metric('Avg weight', _grams(audit.chickAvgWeight)),
          _metric('Uniformity', _percent(audit.chickUniformityPct)),
          _metric('CV', _percent(audit.chickCvPct)),
          _metric('Sample', audit.chickSampleSize?.toString()),
        ],
      ),
      _section(
        title: 'YFBM',
        icon: Icons.percent,
        sectionIndex: 3,
        metrics: [
          _metric('Average', _percent(audit.yfbmAvgPct)),
          _metric('CV', _percent(audit.yfbmCvPct)),
          _metric('Entries', _jsonListCount(audit.yfbmEntries)),
        ],
      ),
      _section(
        title: 'CVT',
        icon: Icons.thermostat_outlined,
        sectionIndex: 4,
        metrics: [
          _metric('Average', _celsius(audit.cvtAvg)),
          _metric('CV', _percent(audit.cvtCvPct)),
          _metric('Top', _celsius(audit.cvtTopTemp)),
          _metric('Middle', _celsius(audit.cvtMiddleTemp)),
          _metric('Bottom', _celsius(audit.cvtBottomTemp)),
        ],
      ),
    ];
  }

  List<_AuditSummarySection> _hatchAnalysisSections() {
    return [
      _section(
        title: 'Hatch Results',
        icon: Icons.query_stats,
        sectionIndex: 0,
        metrics: [
          _metric('Eggs set', audit.haTotalEggsSet?.toString()),
          _metric('Hatched', audit.haHatched?.toString()),
          _metric('Culled', audit.haCulled?.toString()),
          _metric('Dead', audit.haDead?.toString()),
          _metric('Hatchability', _percent(audit.haHatchability)),
        ],
      ),
      _section(
        title: 'Egg Breakout',
        icon: Icons.egg_alt_outlined,
        sectionIndex: 1,
        metrics: [
          _metric('Trays', _jsonListCount(audit.haTrays ?? audit.ebTrays)),
          _metric('Breakout type', audit.ebBreakoutType),
          _metric('Infertile', audit.ebInfertileCount?.toString()),
          _metric('Fertility', _percent(audit.haFertility)),
          _metric('HOF', _percent(audit.haHof)),
        ],
      ),
    ];
  }

  List<_AuditSummarySection> _setterSections() {
    return [
      _section(
        title: 'Setup',
        icon: Icons.tune,
        sectionIndex: 0,
        metrics: [
          _metric('Breed', audit.soBreed),
          _metric('Setter', audit.soSetterId ?? audit.setterId),
          _metric('Incubation age', _days(audit.soIncubationAge)),
        ],
      ),
      _section(
        title: 'Environment',
        icon: Icons.sensors,
        sectionIndex: 1,
        metrics: [_metric('CO2', _ppm(audit.soCo2))],
      ),
      _section(
        title: 'Egg Shell Temperature',
        icon: Icons.device_thermostat,
        sectionIndex: 2,
        metrics: [
          _metric('Average', _celsius(audit.soEstAvg)),
          _metric('CV', _percent(audit.soEstCv)),
          _metric('Readings', _jsonMapValueCount(audit.soEstReadings)),
        ],
      ),
    ];
  }

  List<_AuditSummarySection> _hatcherSections() {
    return [
      _section(
        title: 'Setup',
        icon: Icons.tune,
        sectionIndex: 0,
        metrics: [
          _metric('Breed', audit.hoBreed),
          _metric('Hatcher', audit.hoHatcherId ?? audit.hatcherId),
          _metric('Incubation age', _days(audit.hoIncubationAge)),
        ],
      ),
      _section(
        title: 'Environment',
        icon: Icons.sensors,
        sectionIndex: 1,
        metrics: [_metric('CO2', _ppm(audit.hoCo2))],
      ),
      _section(
        title: 'Chick Vent Temperature',
        icon: Icons.device_thermostat,
        sectionIndex: 2,
        metrics: [
          _metric('Average', _celsius(audit.hoCvtAvg)),
          _metric('CV', _percent(audit.hoCvtCv)),
          _metric('Readings', _jsonMapValueCount(audit.hoCvtReadings)),
        ],
      ),
      _section(
        title: 'Chick Panting',
        icon: Icons.air_outlined,
        sectionIndex: 3,
        metrics: [_metric('Observed', _yesNo(audit.hoChickPanting))],
      ),
    ];
  }

  List<_AuditSummarySection> _eggStorageSections() {
    return [
      _section(
        title: 'Egg Shell Temperature (EST)',
        icon: Icons.thermostat_outlined,
        sectionIndex: 0,
        metrics: [
          _metric('Storage days', audit.esEggStorageDays?.toString()),
          _metric('Average', _celsius(audit.esEstAvg ?? audit.esShellTemp)),
          _metric('CV', _percent(audit.esEstCv)),
          _metric('Readings', _jsonMapValueCount(audit.esEstReadingsJson)),
        ],
      ),
      _section(
        title: 'UV Tray Inspection',
        icon: Icons.grid_on,
        sectionIndex: 1,
        metrics: [_metric('Trays', _jsonListCount(audit.esUvTrays))],
      ),
      _section(
        title: 'Upside Down Score',
        icon: Icons.flip_to_back,
        sectionIndex: 2,
        metrics: [_metric('Trays', _jsonListCount(audit.esUvTrays))],
      ),
      _section(
        title: 'Egg Uniformity',
        icon: Icons.monitor_weight_outlined,
        sectionIndex: 3,
        metrics: [
          _metric('Avg weight', _grams(audit.esEggAvgWeight)),
          _metric('Min range', _grams(_eggUniformityMinRange())),
          _metric('Max range', _grams(_eggUniformityMaxRange())),
          _metric('Uniformity', _percent(audit.esEggUniformityPct)),
          _metric('CV', _percent(audit.esEggCvPct)),
          _metric('Sample', audit.esEggSampleSize?.toString()),
        ],
      ),
      _section(
        title: 'Storage Checklist',
        icon: Icons.checklist,
        sectionIndex: 4,
        metrics: [
          _metric('Turning times', audit.esTurningTimes?.toString()),
          _metric('Tray spacing', audit.esTraySpacing),
          _metric('Cooler proximity', audit.esCoolerProximity),
          _metric('Condensation', _yesNo(audit.esCondensation)),
        ],
      ),
    ];
  }

  _AuditSummarySection _section({
    required String title,
    required IconData icon,
    required int sectionIndex,
    required List<_SummaryMetric> metrics,
  }) {
    return _AuditSummarySection(
      title: title,
      icon: icon,
      sectionIndex: sectionIndex,
      metrics: metrics.where((metric) => metric.value != null).toList(),
    );
  }

  _SummaryMetric _metric(String label, String? value) {
    final trimmed = value?.trim();
    return _SummaryMetric(
      label: label,
      value: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
  }

  String? _fixed(double? value, {int decimals = 1}) {
    if (value == null) return null;
    return value.toStringAsFixed(decimals);
  }

  String? _percent(double? value) {
    final formatted = _fixed(value);
    return formatted == null ? null : '$formatted%';
  }

  String? _celsius(double? value) {
    final formatted = _fixed(value);
    return formatted == null ? null : '$formatted C';
  }

  String? _grams(double? value) {
    final formatted = _fixed(value);
    return formatted == null ? null : '${formatted}g';
  }

  double? _eggUniformityMinRange() {
    final avg = audit.esEggAvgWeight;
    return avg == null ? null : avg * 0.9;
  }

  double? _eggUniformityMaxRange() {
    final avg = audit.esEggAvgWeight;
    return avg == null ? null : avg * 1.1;
  }

  String? _ppm(double? value) {
    final formatted = _fixed(value, decimals: 0);
    return formatted == null ? null : '$formatted ppm';
  }

  String? _unit(double? value, String unit) {
    final formatted = _fixed(value);
    return formatted == null ? null : '$formatted $unit';
  }

  String? _days(int? value) => value == null ? null : '$value days';

  String? _yesNo(bool? value) {
    if (value == null) return null;
    return value ? 'Yes' : 'No';
  }

  String? _jsonListCount(String? jsonText) {
    if (jsonText == null || jsonText.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is List) return decoded.length.toString();
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _jsonMapValueCount(String? jsonText) {
    if (jsonText == null || jsonText.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map) {
        final count = decoded.values.where((value) => value != null).length;
        return count == 0 ? null : count.toString();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')} '
        '${_monthAbbreviation(date.month)} '
        '${date.year}';
  }

  String _monthAbbreviation(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Future<void> _openAuditScreen(BuildContext context, {int sectionIndex = 0}) =>
      openAuditEditor(context, audit, sectionIndex: sectionIndex);
}

class _SummarySectionCard extends StatelessWidget {
  final _AuditSummarySection section;
  final String? actionLabel;
  final VoidCallback? onEdit;

  const _SummarySectionCard({
    required this.section,
    this.actionLabel,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(section.icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (actionLabel != null && onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(actionLabel!),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (section.metrics.isEmpty)
              Text('No values recorded yet', style: AppTextStyles.caption)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: section.metrics
                    .map(
                      (metric) => _MetricChip(
                        label: metric.label,
                        value: metric.value!,
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
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

class _AuditSummarySection {
  final String title;
  final IconData icon;
  final int sectionIndex;
  final List<_SummaryMetric> metrics;

  const _AuditSummarySection({
    required this.title,
    required this.icon,
    required this.sectionIndex,
    required this.metrics,
  });
}

class _SummaryMetric {
  final String label;
  final String? value;

  const _SummaryMetric({required this.label, required this.value});
}
