import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/lab_analysis_models.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../services/supabase/supabase_service.dart';
import '../../../widgets/app_card.dart';
import '../providers/lab_analysis_provider.dart';

class LabAnalysisScreen extends StatefulWidget {
  const LabAnalysisScreen({super.key});

  @override
  State<LabAnalysisScreen> createState() => _LabAnalysisScreenState();
}

class _LabAnalysisScreenState extends State<LabAnalysisScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = context.read<AuthProvider>().user;
      context.read<LabAnalysisProvider>().init(currentUser: user);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LabAnalysisProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: GradientAppBar(
            title: 'Lab Analysis',
            titleLeading: const Icon(
              Icons.biotech_outlined,
              color: Colors.white,
            ),
            actions: [
              IconButton(
                tooltip: context.tr('Add lab result'),
                onPressed:
                    provider.selectedCustomerId == null ||
                        provider.selectedFlockId == null
                    ? null
                    : () => _openAddSheet(context),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: provider.reload,
            child: provider.isLoading
                ? ListView(
                    padding: const EdgeInsets.all(AppSizes.spaceMd),
                    children: const [
                      _FilterSkeleton(),
                      SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  )
                : _buildContent(context, provider),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, LabAnalysisProvider provider) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: AppSizes.spaceMd,
      ),
      children: [
        _LabFilterCard(provider: provider, onAdd: () => _openAddSheet(context)),
        const SizedBox(height: AppSizes.spaceLg),
        if (provider.batches.isEmpty)
          AppCard(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceXl),
              child: Column(
                children: [
                  const Icon(
                    Icons.biotech_outlined,
                    size: 52,
                    color: AppColors.textDisabled,
                  ),
                  const SizedBox(height: AppSizes.spaceMd),
                  Text('No lab results yet', style: AppTextStyles.title),
                  const SizedBox(height: AppSizes.spaceXs),
                  Text(
                    'Add ELISA, PCR, HI, bacterial culture, or sensitivity results for the selected flock.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
          )
        else
          ...provider.batches.map((batch) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.spaceMd),
              child: _LabBatchCard(
                batch: batch,
                onDelete: () =>
                    _confirmDelete(context, provider, batch.report.id),
              ),
            );
          }),
      ],
    );
  }

  void _openAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<LabAnalysisProvider>(),
        child: const _AddLabResultSheet(),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    LabAnalysisProvider provider,
    String reportId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete lab report?'),
        content: const Text(
          'This removes the report, result groups, and sample rows.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await provider.deleteReport(reportId);
  }
}

class _LabFilterCard extends StatelessWidget {
  const _LabFilterCard({required this.provider, required this.onAdd});

  final LabAnalysisProvider provider;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final customerEntries = [
      if (provider.canUseAllCustomers) (value: null, label: 'All customers'),
      ...provider.customers.map((customer) {
        return (value: customer.id, label: customer.name);
      }),
    ];
    final flockEntries = [
      (value: null, label: 'All flocks'),
      ...provider.flocks.map((flock) {
        return (value: flock.id, label: flock.flockId);
      }),
    ];

    return AppCard(
      margin: EdgeInsets.zero,
      color: AppColors.surfaceVariant,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final controls = [
            DropdownButtonFormField<String>(
              initialValue: provider.selectedCustomerId,
              isExpanded: true,
              decoration: _decoration(context, 'Customer'),
              items: [
                for (final entry in customerEntries)
                  DropdownMenuItem(
                    value: entry.value,
                    child: _menuText(entry.label),
                  ),
              ],
              onChanged: provider.setCustomer,
            ),
            DropdownButtonFormField<String>(
              initialValue: provider.selectedFlockId,
              isExpanded: true,
              decoration: _decoration(context, 'Flock'),
              items: [
                for (final entry in flockEntries)
                  DropdownMenuItem(
                    value: entry.value,
                    child: _menuText(entry.label),
                  ),
              ],
              onChanged: provider.selectedCustomerId == null
                  ? null
                  : provider.setFlock,
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: provider.selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) provider.setDate(picked);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(
                HatchDateUtils.formatDisplayDate(provider.selectedDate),
              ),
            ),
            FilledButton.icon(
              onPressed:
                  provider.selectedCustomerId == null ||
                      provider.selectedFlockId == null
                  ? null
                  : onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add result'),
            ),
          ];
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < controls.length; i++) ...[
                  controls[i],
                  if (i != controls.length - 1)
                    const SizedBox(height: AppSizes.spaceSm),
                ],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: controls[0]),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(child: controls[1]),
              const SizedBox(width: AppSizes.spaceSm),
              controls[2],
              const SizedBox(width: AppSizes.spaceSm),
              controls[3],
            ],
          );
        },
      ),
    );
  }

  InputDecoration _decoration(BuildContext context, String label) {
    return InputDecoration(
      labelText: context.tr(label),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: AppSizes.spaceSm,
      ),
    );
  }

  Widget _menuText(String value) {
    return Text(value, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

class _LabBatchCard extends StatelessWidget {
  const _LabBatchCard({required this.batch, required this.onDelete});

  final LabAnalysisBatch batch;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final report = batch.report;
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, color: AppColors.primary),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.labName.isEmpty ? 'Lab report' : report.labName,
                      style: AppTextStyles.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${HatchDateUtils.formatDisplayDate(report.reportDate)} · ${report.sampleType.isEmpty ? 'Sample' : report.sampleType}',
                      style: AppTextStyles.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (report.flockAgeWeeks != null)
                _TinyPill(label: '${report.flockAgeWeeks}w'),
              if (_hasReportPdf(report))
                IconButton(
                  tooltip: context.tr('View PDF'),
                  onPressed: () => _openReportPdf(context, report),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
              IconButton(
                tooltip: context.tr('Delete'),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          for (final group in batch.groups) ...[
            _LabGroupCard(
              group: group,
              rows: batch.rowsByGroupId[group.id] ?? const [],
            ),
            if (group != batch.groups.last)
              const SizedBox(height: AppSizes.spaceMd),
          ],
        ],
      ),
    );
  }
}

class _LabGroupCard extends StatefulWidget {
  const _LabGroupCard({required this.group, required this.rows});

  final LabAnalysisGroupModel group;
  final List<LabAnalysisRowModel> rows;

  @override
  State<_LabGroupCard> createState() => _LabGroupCardState();
}

class _LabGroupCardState extends State<_LabGroupCard> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final rows = widget.rows;
    final severityColor = _severityColor(group.severity);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius + 2),
        border: Border.all(color: severityColor.withValues(alpha: 0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.spaceMd,
              AppSizes.spaceMd,
              AppSizes.spaceMd,
              AppSizes.spaceSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TypePill(type: group.testType),
                          const SizedBox(height: AppSizes.spaceSm),
                          Text(
                            _groupTitle(group),
                            style: AppTextStyles.sectionTitle,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSizes.spaceSm),
                    _SeverityPill(severity: group.severity),
                  ],
                ),
                if (group.interpretation.isNotEmpty) ...[
                  const SizedBox(height: AppSizes.spaceSm),
                  Container(
                    padding: const EdgeInsets.all(AppSizes.spaceSm),
                    decoration: BoxDecoration(
                      color: _severityBg(
                        group.severity,
                      ).withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _severityIcon(group.severity),
                          size: 17,
                          color: severityColor,
                        ),
                        const SizedBox(width: AppSizes.spaceSm),
                        Expanded(
                          child: Text(
                            group.interpretation,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textBody,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSizes.spaceLg),
                Text(
                  'Summary',
                  style: AppTextStyles.subtitle.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSizes.spaceSm),
                _GroupMetrics(group: group, rows: rows),
              ],
            ),
          ),
          if (rows.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.divider),
            Semantics(
              button: true,
              toggled: _showDetails,
              label: context.tr(
                _showDetails ? 'Hide sample details' : 'View sample details',
              ),
              child: InkWell(
                key: ValueKey('lab-sample-details-${group.id}'),
                onTap: () => setState(() => _showDetails = !_showDetails),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.spaceMd,
                    vertical: AppSizes.spaceSm,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.format_list_bulleted_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSizes.spaceSm),
                      Expanded(
                        child: Text(
                          'Sample details',
                          style: AppTextStyles.subtitle.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      _TinyPill(
                        label: _formatInteger(context, rows.length),
                        color: AppColors.primary,
                        background: AppColors.statusActiveBg,
                      ),
                      const SizedBox(width: AppSizes.spaceXs),
                      AnimatedRotation(
                        turns: _showDetails ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: _showDetails
                  ? Container(
                      key: ValueKey('lab-sample-table-${group.id}'),
                      padding: const EdgeInsets.fromLTRB(
                        AppSizes.spaceSm,
                        0,
                        AppSizes.spaceSm,
                        AppSizes.spaceSm,
                      ),
                      color: AppColors.surfaceVariant.withValues(alpha: 0.55),
                      child: _RowsView(group: group, rows: rows),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }

  String _groupTitle(LabAnalysisGroupModel group) {
    final scope = group.groupLabel.isEmpty
        ? group.sampleScope
        : group.groupLabel;
    final analyte = group.testType == LabTestType.hi
        ? group.antigen
        : group.analyte;
    if (scope.isEmpty) return analyte.isEmpty ? group.testType.label : analyte;
    if (analyte.isEmpty) return scope;
    return '$scope · $analyte';
  }
}

class _GroupMetrics extends StatelessWidget {
  const _GroupMetrics({required this.group, required this.rows});

  final LabAnalysisGroupModel group;
  final List<LabAnalysisRowModel> rows;

  @override
  Widget build(BuildContext context) {
    final metrics = <({String label, String value, bool emphasized})>[];
    switch (group.testType) {
      case LabTestType.elisa:
        final sampleCount = group.sampleCount ?? rows.length;
        final positive = group.positiveCount ?? _positiveCount(rows);
        final negative =
            group.negativeCount ??
            _negativeCount(rows, sampleCount: sampleCount, positive: positive);
        final titers = rows.map((row) => row.titer).whereType<double>();
        _add(
          metrics,
          'Sample size',
          _formatInteger(context, sampleCount),
          emphasized: true,
        );
        _add(
          metrics,
          'Mean',
          _formatNumber(context, group.meanTiter, decimals: 0),
        );
        _add(
          metrics,
          'GMT',
          _formatNumber(context, group.gmtTiter, decimals: 0),
        );
        _add(
          metrics,
          'CV%',
          _formatNumber(context, group.cvPct, decimals: 1, suffix: '%'),
        );
        _add(
          metrics,
          'Positive / Negative',
          '${_formatInteger(context, positive)} / ${_formatInteger(context, negative)}',
          emphasized: true,
        );
        _add(
          metrics,
          'Minimum',
          _formatNumber(
            context,
            group.minTiter ?? _minimum(titers),
            decimals: 0,
          ),
        );
        _add(
          metrics,
          'Maximum',
          _formatNumber(
            context,
            group.maxTiter ?? _maximum(titers),
            decimals: 0,
          ),
        );
      case LabTestType.pcr:
        final sampleCount = group.sampleCount ?? rows.length;
        final positive = rows.isEmpty
            ? group.positiveCount ?? 0
            : _positiveCount(rows);
        final negative = rows.isEmpty
            ? group.negativeCount ??
                  (sampleCount > positive ? sampleCount - positive : 0)
            : _negativeCount(
                rows,
                sampleCount: sampleCount,
                positive: positive,
              );
        final ctValues = rows.map((row) => row.ctValue).whereType<double>();
        _add(
          metrics,
          'Sample size',
          _formatInteger(context, sampleCount),
          emphasized: true,
        );
        _add(
          metrics,
          'Positive / Negative',
          '${_formatInteger(context, positive)} / ${_formatInteger(context, negative)}',
          emphasized: true,
        );
        _add(
          metrics,
          'Minimum Ct',
          _formatNumber(context, _minimum(ctValues), decimals: 1),
        );
        _add(
          metrics,
          'Maximum Ct',
          _formatNumber(context, _maximum(ctValues), decimals: 1),
        );
      case LabTestType.hi:
        final sampleCount = group.sampleCount ?? _hiSampleCount(rows);
        final protected = group.protectiveCount ?? 0;
        final notProtected = (sampleCount - protected).clamp(0, sampleCount);
        final populatedBins = rows
            .where((row) => (row.count ?? 0) > 0)
            .map((row) => row.hiLog2?.toDouble())
            .whereType<double>();
        _add(
          metrics,
          'Sample size',
          _formatInteger(context, sampleCount),
          emphasized: true,
        );
        _add(
          metrics,
          'G.M.',
          _formatNumber(context, group.gmLog2, decimals: 1),
        );
        _add(
          metrics,
          'Protected / Not protected',
          '${_formatInteger(context, protected)} / ${_formatInteger(context, notProtected)}',
          emphasized: true,
        );
        _add(
          metrics,
          'Minimum',
          _formatNumber(context, _minimum(populatedBins), decimals: 0),
        );
        _add(
          metrics,
          'Maximum',
          _formatNumber(context, _maximum(populatedBins), decimals: 0),
        );
      case LabTestType.culture:
        final tested = group.sampleCount ?? rows.length;
        final positive = group.positiveCount ?? _positiveCount(rows);
        final negative = group.negativeCount ?? (tested - positive);
        _add(
          metrics,
          'Organisms tested',
          _formatInteger(context, tested),
          emphasized: true,
        );
        _add(
          metrics,
          'Positive / Negative',
          '${_formatInteger(context, positive)} / ${_formatInteger(context, negative)}',
          emphasized: true,
        );
      case LabTestType.sensitivity:
        _add(
          metrics,
          'Antibiotics',
          _formatInteger(context, group.sampleCount ?? rows.length),
          emphasized: true,
        );
        _add(
          metrics,
          'Sensitive',
          _formatInteger(context, _sensitivityCount(rows, 'S')),
        );
        _add(
          metrics,
          'Intermediate',
          _formatInteger(context, _sensitivityCount(rows, 'I')),
        );
        _add(
          metrics,
          'Resistant',
          _formatInteger(context, _sensitivityCount(rows, 'R')),
        );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          final emphasized = metrics
              .where((metric) => metric.emphasized)
              .toList();
          final supporting = metrics
              .where((metric) => !metric.emphasized)
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (emphasized.isNotEmpty)
                _MetricWrap(metrics: emphasized, columns: 2),
              if (emphasized.isNotEmpty && supporting.isNotEmpty)
                const SizedBox(height: AppSizes.spaceSm),
              if (supporting.isNotEmpty)
                _MetricWrap(metrics: supporting, columns: 3),
            ],
          );
        }
        final columns = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 480
            ? 3
            : 2;
        return _MetricWrap(metrics: metrics, columns: columns);
      },
    );
  }

  void _add(
    List<({String label, String value, bool emphasized})> metrics,
    String label,
    String value, {
    bool emphasized = false,
  }) {
    metrics.add((label: label, value: value, emphasized: emphasized));
  }

  int _positiveCount(List<LabAnalysisRowModel> rows) {
    return rows.where((row) => _resultPolarity(row.result) > 0).length;
  }

  int _negativeCount(
    List<LabAnalysisRowModel> rows, {
    required int sampleCount,
    required int positive,
  }) {
    final explicit = rows
        .where((row) => _resultPolarity(row.result) < 0)
        .length;
    if (explicit > 0) return explicit;
    return (sampleCount - positive).clamp(0, sampleCount);
  }

  int _resultPolarity(String result) {
    return switch (result.trim().toUpperCase()) {
      'P' ||
      '+VE' ||
      'POSITIVE' ||
      'DETECTED' ||
      'ISOLATED' ||
      'MIXED GROWTH' => 1,
      'N' ||
      '-VE' ||
      'NEGATIVE' ||
      'NOT DETECTED' ||
      'NOT ISOLATED' ||
      'NO GROWTH' => -1,
      _ => 0,
    };
  }

  int _hiSampleCount(List<LabAnalysisRowModel> rows) {
    return rows.fold<int>(0, (sum, row) => sum + (row.count ?? 0));
  }

  int _sensitivityCount(List<LabAnalysisRowModel> rows, String category) {
    return rows.where((row) {
      return row.sensitivityCategory.trim().toUpperCase() == category;
    }).length;
  }

  double? _minimum(Iterable<double> values) {
    double? minimum;
    for (final value in values) {
      minimum = minimum == null || value < minimum ? value : minimum;
    }
    return minimum;
  }

  double? _maximum(Iterable<double> values) {
    double? maximum;
    for (final value in values) {
      maximum = maximum == null || value > maximum ? value : maximum;
    }
    return maximum;
  }
}

class _MetricWrap extends StatelessWidget {
  const _MetricWrap({required this.metrics, required this.columns});

  final List<({String label, String value, bool emphasized})> metrics;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth - (AppSizes.spaceSm * (columns - 1))) /
            columns;
        return Wrap(
          spacing: AppSizes.spaceSm,
          runSpacing: AppSizes.spaceSm,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _MetricTile(
                  label: metric.label,
                  value: metric.value,
                  emphasized: metric.emphasized,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RowsView extends StatelessWidget {
  const _RowsView({required this.group, required this.rows});

  final LabAnalysisGroupModel group;
  final List<LabAnalysisRowModel> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    switch (group.testType) {
      case LabTestType.elisa:
        return _SimpleTable(
          columns: const ['Sample', 'OD', 'S/P', 'Result', 'Titer'],
          rows: [
            for (final row in rows)
              [
                row.rowLabel,
                _num(context, row.odValue),
                _num(context, row.spRatio),
                row.result,
                _num(context, row.titer, decimals: 0),
              ],
          ],
        );
      case LabTestType.pcr:
        return _SimpleTable(
          columns: const ['Analyte', 'Result', 'Ct', 'Signal'],
          rows: [
            for (final row in rows)
              [
                row.analyte,
                row.result,
                _num(context, row.ctValue),
                row.interpretation,
              ],
          ],
        );
      case LabTestType.hi:
        return _HiDistribution(rows: rows);
      case LabTestType.culture:
        return _SimpleTable(
          columns: const ['Organism', 'Result', 'Interpretation'],
          rows: [
            for (final row in rows)
              [row.analyte, row.result, row.interpretation],
          ],
        );
      case LabTestType.sensitivity:
        return _SensitivityChips(rows: rows);
    }
  }

  String _num(BuildContext context, double? value, {int decimals = 2}) {
    return _formatNumber(context, value, decimals: decimals);
  }
}

class _HiDistribution extends StatelessWidget {
  const _HiDistribution({required this.rows});

  final List<LabAnalysisRowModel> rows;

  @override
  Widget build(BuildContext context) {
    final maxCount = rows.fold<int>(1, (max, row) {
      final count = row.count ?? 0;
      return count > max ? count : max;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Text(row.rowLabel, style: AppTextStyles.caption),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: ((row.count ?? 0) / maxCount).clamp(0, 1),
                      color: AppColors.primary,
                      backgroundColor: AppColors.borderDefault,
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.spaceSm),
                SizedBox(
                  width: 30,
                  child: Text('${row.count ?? 0}', textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SensitivityChips extends StatelessWidget {
  const _SensitivityChips({required this.rows});

  final List<LabAnalysisRowModel> rows;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSizes.spaceXs,
      runSpacing: AppSizes.spaceXs,
      children: [
        for (final row in rows)
          Chip(
            label: Text('${row.antibiotic} · ${row.sensitivityCategory}'),
            visualDensity: VisualDensity.compact,
            backgroundColor: _severityBg(row.severity),
            side: BorderSide(
              color: _severityColor(row.severity).withValues(alpha: 0.38),
            ),
          ),
      ],
    );
  }
}

class _SimpleTable extends StatelessWidget {
  const _SimpleTable({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 48,
        columns: [
          for (final column in columns)
            DataColumn(label: Text(column, style: AppTextStyles.caption)),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                for (final value in row)
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        value.isEmpty ? '-' : value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AddLabResultSheet extends StatefulWidget {
  const _AddLabResultSheet();

  @override
  State<_AddLabResultSheet> createState() => _AddLabResultSheetState();
}

const _sampleTypeOptions = [
  'Broiler chicks',
  'Blood samples',
  'Serum / Plasma',
  'Egg yolk',
  'Tissue samples',
  'Swabs',
  'Tracheal swabs',
  'Cloacal swabs',
  'Organ samples',
  'Isolate',
];

const _scopeOptions = [
  'House 1',
  'House 2',
  'House 3',
  'House 4',
  'House 5',
  'House 6',
  'House 7',
  'House 8',
  'Isolation',
  'Whole flock / pooled',
];
const _elisaAnalyteOptions = [
  'Mycoplasma gallisepticum',
  'Mycoplasma synoviae',
  'Infectious Bronchitis',
  'Newcastle Disease',
  'Infectious Bursal Disease',
  'Avian Influenza H5',
  'Avian Influenza H9',
  'Reovirus',
  'Chicken Anemia Virus',
  'Egg Drop Syndrome',
];
const _elisaKitOptions = ['IDvet', 'IDEXX', 'Other'];
const _pcrAnalyteOptions = [
  'MG',
  'MS',
  'IBV',
  'NDV',
  'IBDV',
  'H5',
  'H9',
  'ILT',
  'CAV',
  'Reovirus',
];
const _organismOptions = [
  'Escherichia coli',
  'Salmonella spp.',
  'Staphylococcus spp.',
  'Enterococcus spp.',
  'Pasteurella multocida',
  'Ornithobacterium rhinotracheale',
  'Mycoplasma gallisepticum',
  'Mycoplasma synoviae',
  'Other',
];
const _cultureMethodOptions = [
  'Salmonella isolation',
  'General bacterial culture',
  'Other',
];
const _cultureResultOptions = [
  'Negative',
  'Positive',
  'Not isolated',
  'Isolated',
  'No growth',
  'Mixed growth',
  'Other',
];
const _antibioticOptions = [
  'Amikacin',
  'Amoxicillin',
  'Ampicillin',
  'Ceftiofur',
  'Ciprofloxacin',
  'Difloxacin',
  'Doxycycline',
  'Enrofloxacin',
  'Erythromycin',
  'Florfenicol',
  'Gentamicin',
  'Levofloxacin',
  'Lincomycin',
  'Neomycin',
  'Oxytetracycline',
  'Spectinomycin',
  'Tiamulin',
  'Tilmicosin',
  'Tylosin',
];
const _elisaResultOptions = ['P', 'N'];
const _pcrResultOptions = ['+VE', '-VE', 'Detected', 'Not detected'];
const _hiAntigenOptions = ['NDV LASOTA', 'H5 (RE-14)', 'H9'];
const _sensitivityCategoryOptions = ['S', 'I', 'R'];

class _AddLabResultSheetState extends State<_AddLabResultSheet> {
  final SupabaseService _supabaseService = SupabaseService();
  LabTestType _type = LabTestType.elisa;
  bool _showElisaSamples = false;
  bool _isSaving = false;
  final _formKey = GlobalKey<FormState>();
  final _labName = TextEditingController(text: 'IDvet');
  final _sampleType = TextEditingController(text: 'Serum / Plasma');
  final _groupLabel = TextEditingController(text: 'House 1');
  final _notes = TextEditingController();
  final _analyte = TextEditingController(text: 'Mycoplasma gallisepticum');
  final _kitName = TextEditingController(text: 'IDvet');
  final _productCode = TextEditingController(text: 'MG/0416');
  final _sampleCount = TextEditingController();
  final _mean = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  final _gmt = TextEditingController();
  final _cv = TextEditingController();
  final _positive = TextEditingController();
  final _negative = TextEditingController();
  final _cutoffSp = TextEditingController(text: '0.5');
  final _cutoffTiter = TextEditingController(text: '843');
  final _hiAntigen = TextEditingController(text: 'NDV LASOTA');
  final _hiSera = TextEditingController(text: '20');
  final _hiGm = TextEditingController();
  final _cultureMethod = TextEditingController(text: 'Salmonella isolation');
  final List<_ElisaSampleDraft> _elisaSamples = [];
  final List<_PcrDraft> _pcrRows = [];
  final List<_CultureDraft> _cultureRows = [];
  final List<_SensitivityDraft> _sensitivityRows = [];
  final Map<int, TextEditingController> _hiBins = {};
  String? _reportFileName;
  String? _reportFilePath;
  String? _reportFileRemotePath;
  Uint8List? _reportFileBytes;

  @override
  void initState() {
    super.initState();
    _pcrRows.addAll([
      _PcrDraft(analyte: 'MG', result: '+VE'),
      _PcrDraft(analyte: 'IBV', result: '+VE'),
      _PcrDraft(analyte: 'H9', result: '-VE'),
    ]);
    _cultureRows.add(
      _CultureDraft(organism: 'Salmonella spp.', result: 'Negative'),
    );
    _sensitivityRows.add(_SensitivityDraft());
    for (var bin = 0; bin <= 12; bin++) {
      _hiBins[bin] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _labName,
      _sampleType,
      _groupLabel,
      _notes,
      _analyte,
      _kitName,
      _productCode,
      _sampleCount,
      _mean,
      _min,
      _max,
      _gmt,
      _cv,
      _positive,
      _negative,
      _cutoffSp,
      _cutoffTiter,
      _hiAntigen,
      _hiSera,
      _hiGm,
      _cultureMethod,
    ]) {
      controller.dispose();
    }
    for (final sample in _elisaSamples) {
      sample.dispose();
    }
    for (final row in _pcrRows) {
      row.dispose();
    }
    for (final row in _cultureRows) {
      row.dispose();
    }
    for (final row in _sensitivityRows) {
      row.dispose();
    }
    for (final controller in _hiBins.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final provider = context.watch<LabAnalysisProvider>();
    return ColoredBox(
      color: AppColors.background,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
            child: Form(
              key: _formKey,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(
                            AppSizes.iconRadius,
                          ),
                        ),
                        child: const Icon(
                          Icons.biotech_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: AppSizes.spaceMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'New lab report',
                              style: AppTextStyles.sectionTitle,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${HatchDateUtils.formatDisplayDate(provider.selectedDate)}'
                              ' · choose the test first, then enter only its '
                              'relevant fields',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('Close'),
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.spaceLg),
                  _TestTypePicker(selected: _type, onSelected: _selectTestType),
                  const SizedBox(height: AppSizes.spaceLg),
                  _FormSection(
                    number: '1',
                    title: 'Report context',
                    subtitle:
                        'Who performed the test and what flock material was tested.',
                    child: _FieldGrid(
                      children: [
                        _TextInput(
                          controller: _labName,
                          label: 'Laboratory',
                          required: true,
                        ),
                        _DropdownInput(
                          controller: _sampleType,
                          label: 'Sample type',
                          options: _sampleTypeOptions,
                          required: true,
                        ),
                        _DropdownInput(
                          controller: _groupLabel,
                          label: _type == LabTestType.sensitivity
                              ? 'House / isolate scope'
                              : 'House / sample scope',
                          options: _scopeOptions,
                          required: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceMd),
                  _FormSection(
                    number: '2',
                    title: '${_type.label} results',
                    subtitle: _typeGuidance(_type),
                    child: _buildTypeFields(),
                  ),
                  const SizedBox(height: AppSizes.spaceMd),
                  _FormSection(
                    number: '3',
                    title: 'Source report',
                    subtitle:
                        'Attach the original PDF so every saved result remains auditable.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ReportPdfPicker(
                          fileName: _reportFileName,
                          hasRemoteFile:
                              (_reportFileRemotePath ?? '').isNotEmpty,
                          onPick: _pickReportPdf,
                          onClear: _clearReportPdf,
                        ),
                        _TextInput(
                          controller: _notes,
                          label: 'Notes / clinical context',
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceLg),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      _isSaving ? 'Saving report…' : 'Save report and results',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectTestType(LabTestType type) {
    setState(() {
      _type = type;
      switch (type) {
        case LabTestType.elisa:
        case LabTestType.hi:
          _sampleType.text = 'Serum / Plasma';
        case LabTestType.pcr:
          _sampleType.text = 'Tracheal swabs';
        case LabTestType.culture:
          _sampleType.text = 'Broiler chicks';
          _groupLabel.text = 'Whole flock / pooled';
        case LabTestType.sensitivity:
          _sampleType.text = 'Isolate';
          _groupLabel.text = 'Isolation';
      }
    });
  }

  String _typeGuidance(LabTestType type) {
    return switch (type) {
      LabTestType.elisa =>
        'Save the plate summary first. Individual sera are optional and useful for distribution analysis.',
      LabTestType.pcr =>
        'Record one row per target with the reported detected status and Ct when available.',
      LabTestType.hi =>
        'Record the antigen, geometric mean, and number of sera at each log₂ titer.',
      LabTestType.culture =>
        'Record the culture or isolation method, each organism tested, and whether it was isolated.',
      LabTestType.sensitivity =>
        'Record only the laboratory S / I / R category for each tested antimicrobial.',
    };
  }

  Widget _buildTypeFields() {
    switch (_type) {
      case LabTestType.elisa:
        return _buildElisaFields();
      case LabTestType.pcr:
        return _buildPcrFields();
      case LabTestType.hi:
        return _buildHiFields();
      case LabTestType.culture:
        return _buildCultureFields();
      case LabTestType.sensitivity:
        return _buildSensitivityFields();
    }
  }

  Future<void> _pickReportPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    setState(() {
      _reportFileName = file.name;
      _reportFilePath = file.path;
      _reportFileBytes = file.bytes;
      _reportFileRemotePath = null;
    });
  }

  void _clearReportPdf() {
    setState(() {
      _reportFileName = null;
      _reportFilePath = null;
      _reportFileBytes = null;
      _reportFileRemotePath = null;
    });
  }

  Future<String?> _uploadReportPdfIfNeeded(LabAnalysisProvider provider) async {
    if ((_reportFileRemotePath ?? '').isNotEmpty) return _reportFileRemotePath;
    if (_reportFileBytes == null && (_reportFilePath ?? '').isEmpty) {
      return null;
    }
    final customerId = provider.selectedCustomerId;
    final flockId = provider.selectedFlockId;
    if (customerId == null || flockId == null) return null;

    try {
      final bytes = _reportFileBytes;
      final uploaded = bytes != null
          ? await _supabaseService.uploadLabAnalysisReportPdfBytes(
              bytes: bytes,
              customerId: customerId,
              flockId: flockId,
              reportDate: provider.selectedDate,
              fileName: _reportFileName,
            )
          : await _supabaseService.uploadLabAnalysisReportPdf(
              localPath: _reportFilePath!,
              customerId: customerId,
              flockId: flockId,
              reportDate: provider.selectedDate,
              fileName: _reportFileName,
            );
      if (uploaded != null && mounted) {
        setState(() => _reportFileRemotePath = uploaded);
      }
      return uploaded;
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not upload PDF: $error')));
      return null;
    }
  }

  Widget _buildElisaFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldGrid(
          children: [
            _DropdownInput(
              controller: _analyte,
              label: 'Analyte / antibody',
              options: _elisaAnalyteOptions,
              required: true,
              onChanged: _applyElisaPreset,
            ),
            _DropdownInput(
              controller: _kitName,
              label: 'Assay kit',
              options: _elisaKitOptions,
              required: true,
            ),
            _TextInput(controller: _productCode, label: 'Product / kit code'),
          ],
        ),
        const _SubsectionLabel(
          title: 'Plate summary',
          caption: 'Enter the statistics printed on the laboratory report.',
        ),
        _FieldGrid(
          children: [
            _TextInput(
              controller: _sampleCount,
              label: 'Number of samples',
              number: true,
            ),
            _TextInput(
              controller: _positive,
              label: 'Positive samples',
              number: true,
            ),
            _TextInput(
              controller: _negative,
              label: 'Negative samples',
              number: true,
            ),
          ],
        ),
        _FieldGrid(
          children: [
            _TextInput(controller: _mean, label: 'Mean titer', number: true),
            _TextInput(
              controller: _gmt,
              label: 'Geometric mean titer (GMT)',
              number: true,
            ),
            _TextInput(
              controller: _cv,
              label: 'Coefficient of variation (CV%)',
              number: true,
            ),
          ],
        ),
        _FieldGrid(
          children: [
            _TextInput(controller: _min, label: 'Minimum titer', number: true),
            _TextInput(controller: _max, label: 'Maximum titer', number: true),
            _TextInput(
              controller: _cutoffSp,
              label: 'Positive cut-off S/P',
              number: true,
            ),
            _TextInput(
              controller: _cutoffTiter,
              label: 'Positive cut-off titer',
              number: true,
            ),
          ],
        ),
        const SizedBox(height: AppSizes.spaceSm),
        Material(
          color: AppColors.surfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            side: const BorderSide(color: AppColors.borderDefault),
          ),
          child: SwitchListTile.adaptive(
            value: _showElisaSamples,
            title: Text(
              'Enter individual sample rows',
              style: AppTextStyles.subtitle,
            ),
            subtitle: Text(
              'Optional. Turn this on when OD, S/P, titer, and result are available.',
              style: AppTextStyles.caption,
            ),
            onChanged: (value) {
              setState(() {
                _showElisaSamples = value;
                if (value && _elisaSamples.isEmpty) {
                  _elisaSamples.addAll(
                    List.generate(
                      5,
                      (index) => _ElisaSampleDraft(
                        sampleNo: (index + 1).toString().padLeft(2, '0'),
                      ),
                    ),
                  );
                }
              });
            },
          ),
        ),
        if (_showElisaSamples) ...[
          const SizedBox(height: AppSizes.spaceSm),
          _SectionHeader(
            title: 'Individual sera',
            onAdd: () => setState(() {
              _elisaSamples.add(
                _ElisaSampleDraft(
                  sampleNo: (_elisaSamples.length + 1).toString().padLeft(
                    2,
                    '0',
                  ),
                ),
              );
            }),
          ),
          for (var i = 0; i < _elisaSamples.length; i++)
            _ElisaSampleEditor(
              index: i,
              draft: _elisaSamples[i],
              onRemove: _elisaSamples.length <= 1
                  ? null
                  : () => setState(() => _elisaSamples.removeAt(i).dispose()),
            ),
        ],
      ],
    );
  }

  void _applyElisaPreset(String analyte) {
    if (analyte == 'Mycoplasma gallisepticum') {
      _kitName.text = 'IDvet';
      _productCode.text = 'MG/0416';
      _cutoffSp.text = '0.5';
      _cutoffTiter.text = '843';
    } else if (analyte == 'Mycoplasma synoviae') {
      _kitName.text = 'IDvet';
      _productCode.clear();
      _cutoffSp.clear();
      _cutoffTiter.clear();
    } else if (analyte == 'Infectious Bronchitis') {
      _kitName.text = 'IDvet';
      _productCode.clear();
      _cutoffSp.clear();
      _cutoffTiter.clear();
    }
  }

  Widget _buildPcrFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'PCR targets',
          onAdd: () => setState(() => _pcrRows.add(_PcrDraft())),
        ),
        for (var i = 0; i < _pcrRows.length; i++)
          _PcrRowEditor(
            draft: _pcrRows[i],
            onRemove: _pcrRows.length <= 1
                ? null
                : () => setState(() => _pcrRows.removeAt(i).dispose()),
          ),
      ],
    );
  }

  Widget _buildHiFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldGrid(
          children: [
            _DropdownInput(
              controller: _hiAntigen,
              label: 'Antigen',
              options: _hiAntigenOptions,
              required: true,
            ),
            _TextInput(
              controller: _hiSera,
              label: 'Number of sera',
              number: true,
            ),
            _TextInput(
              controller: _hiGm,
              label: 'Geometric mean (log₂)',
              number: true,
            ),
          ],
        ),
        const SizedBox(height: AppSizes.spaceSm),
        const _SubsectionLabel(
          title: 'Titer distribution',
          caption: 'Enter the number of sera observed at each log₂ titer.',
        ),
        const SizedBox(height: AppSizes.spaceXs),
        Wrap(
          spacing: AppSizes.spaceXs,
          runSpacing: AppSizes.spaceXs,
          children: [
            for (final entry in _hiBins.entries)
              SizedBox(
                width: 74,
                child: TextFormField(
                  controller: entry.value,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: entry.key >= 12 ? '>=12' : '${entry.key}',
                    isDense: true,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSensitivityFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Antibiotics',
          onAdd: () =>
              setState(() => _sensitivityRows.add(_SensitivityDraft())),
        ),
        for (var i = 0; i < _sensitivityRows.length; i++)
          _SensitivityRowEditor(
            draft: _sensitivityRows[i],
            onRemove: _sensitivityRows.length <= 1
                ? null
                : () => setState(() => _sensitivityRows.removeAt(i).dispose()),
          ),
      ],
    );
  }

  Widget _buildCultureFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldGrid(
          children: [
            _DropdownInput(
              controller: _cultureMethod,
              label: 'Culture / isolation test',
              options: _cultureMethodOptions,
              required: true,
            ),
          ],
        ),
        _SectionHeader(
          title: 'Culture findings',
          onAdd: () => setState(() => _cultureRows.add(_CultureDraft())),
        ),
        for (var i = 0; i < _cultureRows.length; i++)
          _CultureRowEditor(
            draft: _cultureRows[i],
            onRemove: _cultureRows.length <= 1
                ? null
                : () => setState(() => _cultureRows.removeAt(i).dispose()),
          ),
      ],
    );
  }

  Future<void> _save() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    final provider = context.read<LabAnalysisProvider>();
    try {
      final reportFileRemotePath = await _uploadReportPdfIfNeeded(provider);
      switch (_type) {
        case LabTestType.elisa:
          await provider.saveElisa(
            labName: _labName.text,
            sampleType: _sampleType.text,
            groupLabel: _groupLabel.text.trim(),
            analyte: _analyte.text.trim(),
            kitName: _kitName.text.trim(),
            productCode: _productCode.text.trim(),
            sampleCount: _int(_sampleCount.text),
            meanTiter: _double(_mean.text),
            minTiter: _double(_min.text),
            maxTiter: _double(_max.text),
            gmtTiter: _double(_gmt.text),
            cvPct: _double(_cv.text),
            positiveCount: _int(_positive.text),
            negativeCount: _int(_negative.text),
            cutoffValue: _double(_cutoffSp.text),
            cutoffTiter: _double(_cutoffTiter.text),
            samples: _showElisaSamples
                ? [
                    for (final sample in _elisaSamples)
                      if (sample.sampleNo.text.trim().isNotEmpty &&
                          (sample.od.text.trim().isNotEmpty ||
                              sample.sp.text.trim().isNotEmpty ||
                              sample.titer.text.trim().isNotEmpty))
                        ElisaSampleInput(
                          sampleNo: sample.sampleNo.text.trim(),
                          od: _double(sample.od.text),
                          spRatio: _double(sample.sp.text),
                          result: sample.result.text.trim(),
                          titer: _double(sample.titer.text),
                          titerGroup: _int(sample.group.text),
                        ),
                  ]
                : const [],
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            reportFileName: _reportFileName,
            reportFilePath: _reportFilePath,
            reportFileRemotePath: reportFileRemotePath,
          );
        case LabTestType.pcr:
          await provider.savePcr(
            labName: _labName.text,
            sampleType: _sampleType.text,
            groupLabel: _groupLabel.text.trim(),
            results: [
              for (final row in _pcrRows)
                if (row.analyte.text.trim().isNotEmpty)
                  PcrResultInput(
                    analyte: row.analyte.text.trim(),
                    result: row.result.text.trim(),
                    ctValue: _double(row.ct.text),
                  ),
            ],
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            reportFileName: _reportFileName,
            reportFilePath: _reportFilePath,
            reportFileRemotePath: reportFileRemotePath,
          );
        case LabTestType.hi:
          await provider.saveHi(
            labName: _labName.text,
            sampleType: _sampleType.text,
            groupLabel: _groupLabel.text.trim(),
            antigen: _hiAntigen.text.trim(),
            seraCount: _int(_hiSera.text) ?? 0,
            gmLog2: _double(_hiGm.text),
            distribution: {
              for (final entry in _hiBins.entries)
                if ((_int(entry.value.text) ?? 0) > 0)
                  entry.key: _int(entry.value.text) ?? 0,
            },
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            reportFileName: _reportFileName,
            reportFilePath: _reportFilePath,
            reportFileRemotePath: reportFileRemotePath,
          );
        case LabTestType.culture:
          await provider.saveCulture(
            labName: _labName.text,
            sampleType: _sampleType.text,
            groupLabel: _groupLabel.text.trim(),
            method: _cultureMethod.text.trim(),
            findings: [
              for (final row in _cultureRows)
                if (row.organism.text.trim().isNotEmpty)
                  CultureResultInput(
                    organism: row.organism.text.trim(),
                    result: row.result.text.trim(),
                  ),
            ],
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            reportFileName: _reportFileName,
            reportFilePath: _reportFilePath,
            reportFileRemotePath: reportFileRemotePath,
          );
        case LabTestType.sensitivity:
          await provider.saveSensitivity(
            labName: _labName.text,
            sampleType: _sampleType.text,
            groupLabel: _groupLabel.text.trim(),
            antibiotics: [
              for (final row in _sensitivityRows)
                if (row.antibiotic.text.trim().isNotEmpty)
                  SensitivityInput(
                    antibiotic: row.antibiotic.text.trim(),
                    category: row.category,
                  ),
            ],
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            reportFileName: _reportFileName,
            reportFilePath: _reportFilePath,
            reportFileRemotePath: reportFileRemotePath,
          );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save lab result: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  int? _int(String value) => int.tryParse(value.trim());

  double? _double(String value) {
    return double.tryParse(value.trim().replaceAll(',', ''));
  }
}

class _TestTypePicker extends StatelessWidget {
  const _TestTypePicker({required this.selected, required this.onSelected});

  final LabTestType selected;
  final ValueChanged<LabTestType> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 860
            ? 5
            : constraints.maxWidth >= 680
            ? 3
            : constraints.maxWidth >= 420
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - AppSizes.spaceSm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSizes.spaceSm,
          runSpacing: AppSizes.spaceSm,
          children: [
            for (final type in LabTestType.values)
              SizedBox(
                width: width,
                child: _TestTypeOption(
                  type: type,
                  selected: selected == type,
                  onTap: () => onSelected(type),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TestTypeOption extends StatelessWidget {
  const _TestTypeOption({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final LabTestType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, caption) = switch (type) {
      LabTestType.elisa => (Icons.water_drop_outlined, 'Antibodies & titers'),
      LabTestType.pcr => (Icons.hub_outlined, 'Targets & Ct values'),
      LabTestType.hi => (Icons.scatter_plot_outlined, 'Log₂ distribution'),
      LabTestType.culture => (
        Icons.science_outlined,
        'Isolation & identification',
      ),
      LabTestType.sensitivity => (
        Icons.medication_outlined,
        'Antibiotic S / I / R',
      ),
    };
    return Material(
      color: selected ? AppColors.statusActiveBg : AppColors.surface,
      borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(AppSizes.spaceMd),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderDefault,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : AppColors.statusNeutralBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: selected ? Colors.white : AppColors.statusNeutralText,
                ),
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: AppTextStyles.subtitle.copyWith(
                        color: selected
                            ? AppColors.primaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle,
                  size: 18,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String number;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceLg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius + 4),
        border: Border.all(color: AppColors.borderDefault),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.statusActiveBg,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  number,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.title),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceLg),
          child,
        ],
      ),
    );
  }
}

class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680
            ? 3
            : constraints.maxWidth >= 420
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - AppSizes.spaceSm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSizes.spaceSm,
          runSpacing: 0,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _SubsectionLabel extends StatelessWidget {
  const _SubsectionLabel({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSizes.spaceSm,
        bottom: AppSizes.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.subtitle),
          const SizedBox(height: 2),
          Text(caption, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    required this.label,
    this.required = false,
    this.number = false,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final bool number;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        validator: required
            ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return context.tr('Required');
                }
                return null;
              }
            : null,
        decoration: InputDecoration(
          labelText: context.tr(label),
          isDense: true,
        ),
      ),
    );
  }
}

class _ReportPdfPicker extends StatelessWidget {
  const _ReportPdfPicker({
    required this.fileName,
    required this.hasRemoteFile,
    required this.onPick,
    required this.onClear,
  });

  final String? fileName;
  final bool hasRemoteFile;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasFile = (fileName ?? '').isNotEmpty || hasRemoteFile;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf_outlined, color: AppColors.primary),
          const SizedBox(width: AppSizes.spaceSm),
          Expanded(
            child: Text(
              hasFile
                  ? fileName ?? context.tr('PDF saved in cloud')
                  : context.tr('No PDF attached'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body,
            ),
          ),
          TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.attach_file),
            label: Text(context.tr(hasFile ? 'Replace PDF' : 'Attach PDF')),
          ),
          if (hasFile)
            IconButton(
              tooltip: context.tr('Remove'),
              onPressed: onClear,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

class _DropdownInput extends StatelessWidget {
  const _DropdownInput({
    required this.controller,
    required this.label,
    required this.options,
    this.required = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final List<String> options;
  final bool required;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedDropdownValue(controller, options);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$selected'),
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.tr(label),
          isDense: true,
        ),
        validator: required
            ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return context.tr('Required');
                }
                return null;
              }
            : null,
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(context.tr(option))),
        ],
        onChanged: (value) {
          if (value == null) return;
          controller.text = value;
          onChanged?.call(value);
        },
      ),
    );
  }
}

bool _hasReportPdf(LabAnalysisReportModel report) {
  return (report.reportFilePath ?? '').trim().isNotEmpty ||
      (report.reportFileRemotePath ?? '').trim().isNotEmpty;
}

Future<void> _openReportPdf(
  BuildContext context,
  LabAnalysisReportModel report,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final localPath = report.reportFilePath?.trim();
  final remotePath = report.reportFileRemotePath?.trim();
  final previewUnavailable = context.tr('PDF preview is not available');
  final couldNotOpen = context.tr('Could not open PDF');

  Uri? uri;
  LaunchMode mode = LaunchMode.inAppBrowserView;
  if (localPath != null && localPath.isNotEmpty) {
    uri = Uri.file(localPath);
    mode = LaunchMode.externalApplication;
  } else if (remotePath != null && remotePath.startsWith('http')) {
    uri = Uri.tryParse(remotePath);
  } else if (remotePath != null && remotePath.isNotEmpty) {
    final url = await SupabaseService().createLabAnalysisReportPdfUrl(
      remotePath,
    );
    uri = url == null ? null : Uri.tryParse(url);
  }

  if (uri == null) {
    messenger.showSnackBar(SnackBar(content: Text(previewUnavailable)));
    return;
  }
  final opened = await launchUrl(uri, mode: mode);
  if (!opened && context.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(couldNotOpen)));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onAdd});

  final String title;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: AppTextStyles.subtitle)),
        IconButton.filledTonal(
          tooltip: context.tr('Add'),
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    );
  }
}

class _ElisaSampleEditor extends StatelessWidget {
  const _ElisaSampleEditor({
    required this.index,
    required this.draft,
    this.onRemove,
  });

  final int index;
  final _ElisaSampleDraft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sample ${index + 1}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: context.tr('Remove'),
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline, size: 19),
              ),
            ],
          ),
          Wrap(
            spacing: AppSizes.spaceXs,
            runSpacing: AppSizes.spaceXs,
            children: [
              SizedBox(
                width: 72,
                child: _MiniInput(controller: draft.sampleNo, label: 'No.'),
              ),
              SizedBox(
                width: 100,
                child: _MiniInput(
                  controller: draft.od,
                  label: 'OD',
                  number: true,
                ),
              ),
              SizedBox(
                width: 100,
                child: _MiniInput(
                  controller: draft.sp,
                  label: 'S/P',
                  number: true,
                ),
              ),
              SizedBox(
                width: 94,
                child: _MiniDropdown(
                  controller: draft.result,
                  label: 'Result',
                  options: _elisaResultOptions,
                ),
              ),
              SizedBox(
                width: 120,
                child: _MiniInput(
                  controller: draft.titer,
                  label: 'Titer',
                  number: true,
                ),
              ),
              SizedBox(
                width: 84,
                child: _MiniInput(
                  controller: draft.group,
                  label: 'Group',
                  number: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PcrRowEditor extends StatelessWidget {
  const _PcrRowEditor({required this.draft, this.onRemove});

  final _PcrDraft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Wrap(
        spacing: AppSizes.spaceSm,
        runSpacing: AppSizes.spaceXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 190,
            child: _MiniDropdown(
              controller: draft.analyte,
              label: 'Target',
              options: _pcrAnalyteOptions,
            ),
          ),
          SizedBox(
            width: 130,
            child: _MiniDropdown(
              controller: draft.result,
              label: 'Result',
              options: _pcrResultOptions,
            ),
          ),
          SizedBox(
            width: 120,
            child: _MiniInput(
              controller: draft.ct,
              label: 'Ct value',
              number: true,
            ),
          ),
          IconButton(
            tooltip: context.tr('Remove'),
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _CultureRowEditor extends StatelessWidget {
  const _CultureRowEditor({required this.draft, this.onRemove});

  final _CultureDraft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Wrap(
        spacing: AppSizes.spaceSm,
        runSpacing: AppSizes.spaceXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 250,
            child: _MiniDropdown(
              controller: draft.organism,
              label: 'Bacterial organism',
              options: _organismOptions,
            ),
          ),
          SizedBox(
            width: 170,
            child: _MiniDropdown(
              controller: draft.result,
              label: 'Culture result',
              options: _cultureResultOptions,
            ),
          ),
          IconButton(
            tooltip: context.tr('Remove'),
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _SensitivityRowEditor extends StatelessWidget {
  const _SensitivityRowEditor({required this.draft, this.onRemove});

  final _SensitivityDraft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Wrap(
        spacing: AppSizes.spaceSm,
        runSpacing: AppSizes.spaceXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: _MiniDropdown(
              controller: draft.antibiotic,
              label: 'Antimicrobial',
              options: _antibioticOptions,
            ),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              initialValue: _sensitivityCategoryOptions.contains(draft.category)
                  ? draft.category
                  : _sensitivityCategoryOptions.first,
              decoration: const InputDecoration(
                labelText: 'Interpretation',
                isDense: true,
              ),
              items: [
                for (final option in _sensitivityCategoryOptions)
                  DropdownMenuItem(
                    value: option,
                    child: Text(context.tr(option)),
                  ),
              ],
              onChanged: (value) => draft.category = value ?? draft.category,
            ),
          ),
          IconButton(
            tooltip: context.tr('Remove'),
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _MiniInput extends StatelessWidget {
  const _MiniInput({
    required this.controller,
    required this.label,
    this.number = false,
  });

  final TextEditingController controller;
  final String label;
  final bool number;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: context.tr(label), isDense: true),
    );
  }
}

class _MiniDropdown extends StatelessWidget {
  const _MiniDropdown({
    required this.controller,
    required this.label,
    required this.options,
  });

  final TextEditingController controller;
  final String label;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedDropdownValue(controller, options);
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$selected'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: context.tr(label), isDense: true),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(context.tr(option))),
      ],
      onChanged: (value) {
        if (value != null) controller.text = value;
      },
    );
  }
}

String _selectedDropdownValue(
  TextEditingController controller,
  List<String> options,
) {
  final current = controller.text.trim();
  final selected = options.contains(current) ? current : options.first;
  if (controller.text != selected) controller.text = selected;
  return selected;
}

class _ElisaSampleDraft {
  _ElisaSampleDraft({String sampleNo = ''})
    : sampleNo = TextEditingController(text: sampleNo),
      od = TextEditingController(),
      sp = TextEditingController(),
      result = TextEditingController(text: 'P'),
      titer = TextEditingController(),
      group = TextEditingController();

  final TextEditingController sampleNo;
  final TextEditingController od;
  final TextEditingController sp;
  final TextEditingController result;
  final TextEditingController titer;
  final TextEditingController group;

  void dispose() {
    sampleNo.dispose();
    od.dispose();
    sp.dispose();
    result.dispose();
    titer.dispose();
    group.dispose();
  }
}

class _PcrDraft {
  _PcrDraft({String analyte = '', String result = ''})
    : analyte = TextEditingController(text: analyte),
      result = TextEditingController(text: result),
      ct = TextEditingController();

  final TextEditingController analyte;
  final TextEditingController result;
  final TextEditingController ct;

  void dispose() {
    analyte.dispose();
    result.dispose();
    ct.dispose();
  }
}

class _CultureDraft {
  _CultureDraft({String organism = '', String result = ''})
    : organism = TextEditingController(text: organism),
      result = TextEditingController(text: result);

  final TextEditingController organism;
  final TextEditingController result;

  void dispose() {
    organism.dispose();
    result.dispose();
  }
}

class _SensitivityDraft {
  _SensitivityDraft() : antibiotic = TextEditingController(), category = 'S';

  final TextEditingController antibiotic;
  String category;

  void dispose() => antibiotic.dispose();
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: AppSizes.spaceSm,
      ),
      decoration: BoxDecoration(
        color: emphasized ? AppColors.statusActiveBg : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(
          color: emphasized
              ? AppColors.primary.withValues(alpha: 0.26)
              : AppColors.borderDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.metricLarge.copyWith(
              fontSize: 20,
              color: emphasized ? AppColors.primaryDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.type});

  final LabTestType type;

  @override
  Widget build(BuildContext context) {
    return _TinyPill(
      label: type.label,
      color: AppColors.primary,
      background: AppColors.statusActiveBg,
    );
  }
}

class _SeverityPill extends StatelessWidget {
  const _SeverityPill({required this.severity});

  final LabSeverity severity;

  @override
  Widget build(BuildContext context) {
    final label = switch (severity) {
      LabSeverity.normal => 'OK',
      LabSeverity.watch => 'Watch',
      LabSeverity.alert => 'Alert',
    };
    return _TinyPill(
      label: label,
      color: _severityColor(severity),
      background: _severityBg(severity),
    );
  }
}

class _TinyPill extends StatelessWidget {
  const _TinyPill({
    required this.label,
    this.color = AppColors.statusNeutralText,
    this.background = AppColors.statusNeutralBg,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FilterSkeleton extends StatelessWidget {
  const _FilterSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      color: AppColors.surfaceVariant,
      child: Row(
        children: [
          Expanded(
            child: Container(height: 44, color: AppColors.borderDefault),
          ),
          const SizedBox(width: AppSizes.spaceSm),
          Expanded(
            child: Container(height: 44, color: AppColors.borderDefault),
          ),
        ],
      ),
    );
  }
}

Color _severityColor(LabSeverity severity) {
  return switch (severity) {
    LabSeverity.normal => AppColors.statusGood,
    LabSeverity.watch => AppColors.statusWarning,
    LabSeverity.alert => AppColors.statusError,
  };
}

Color _severityBg(LabSeverity severity) {
  return switch (severity) {
    LabSeverity.normal => AppColors.statusGoodBg,
    LabSeverity.watch => AppColors.statusWarningBg,
    LabSeverity.alert => AppColors.statusErrorBg,
  };
}

IconData _severityIcon(LabSeverity severity) {
  return switch (severity) {
    LabSeverity.normal => Icons.check_circle_outline_rounded,
    LabSeverity.watch => Icons.visibility_outlined,
    LabSeverity.alert => Icons.error_outline_rounded,
  };
}

String _formatInteger(BuildContext context, int? value) {
  return _formatNumber(context, value, decimals: 0);
}

String _formatNumber(
  BuildContext context,
  num? value, {
  required int decimals,
  String suffix = '',
}) {
  if (value == null) return '—';
  final fixed = value.toStringAsFixed(decimals);
  final negative = fixed.startsWith('-');
  final unsigned = negative ? fixed.substring(1) : fixed;
  final parts = unsigned.split('.');
  final digits = parts.first;
  final separator = Localizations.localeOf(context).languageCode == 'ar'
      ? '٬'
      : ',';
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => separator,
  );
  final decimal = parts.length > 1 ? '.${parts[1]}' : '';
  return '${negative ? '-' : ''}$grouped$decimal$suffix';
}
