import 'dart:convert';

import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/hatchery_agent_models.dart';
import '../../../widgets/app_card.dart';
import '../services/hatchery_agent_rules.dart';

class HatcheryDraftRowCard extends StatelessWidget {
  const HatcheryDraftRowCard({
    super.key,
    required this.row,
    this.onEdit,
    this.onApprove,
    this.onReject,
  });

  final HatcheryDraftRow row;
  final VoidCallback? onEdit;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final warnings = _parseWarnings(row.warningsJson);
    final status = _rowStatusPresentation(row.status);

    return AppCard(
      key: ValueKey('agent-draft-row-${row.id}'),
      margin: const EdgeInsets.only(bottom: AppSizes.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Row ${row.rowOrdinal}',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              _RowStatusChip(presentation: status),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          Wrap(
            spacing: AppSizes.spaceLg,
            runSpacing: AppSizes.spaceMd,
            children: _extractedValues(row)
                .map(
                  (value) => SizedBox(
                    width: 150,
                    child: _FieldValue(label: value.label, value: value.value!),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: AppSizes.spaceLg),
          const Divider(height: 1),
          const SizedBox(height: AppSizes.spaceMd),
          Text('Confidence', style: AppTextStyles.title),
          const SizedBox(height: AppSizes.spaceXs),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: row.confidencePct == null
                      ? 0
                      : (row.confidencePct! / 100).clamp(0, 1),
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  color: _confidenceColor(row.confidencePct),
                  backgroundColor: AppColors.statusNeutralBg,
                ),
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Text(_percentage(row.confidencePct), style: AppTextStyles.title),
            ],
          ),
          const SizedBox(height: AppSizes.spaceLg),
          Text('Warnings', style: AppTextStyles.title),
          const SizedBox(height: AppSizes.spaceSm),
          if (warnings.isEmpty)
            Text('No warnings', style: AppTextStyles.caption)
          else
            ...warnings.map((warning) => _WarningRow(warning: warning)),
          if (_hasActions) ...[
            const SizedBox(height: AppSizes.spaceLg),
            const Divider(height: 1),
            const SizedBox(height: AppSizes.spaceMd),
            Wrap(
              spacing: AppSizes.spaceSm,
              runSpacing: AppSizes.spaceSm,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('agent-edit-row-${row.id}'),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                FilledButton.icon(
                  key: ValueKey('agent-approve-row-${row.id}'),
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Approve'),
                ),
                OutlinedButton.icon(
                  key: ValueKey('agent-reject-row-${row.id}'),
                  onPressed: onReject,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Reject'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool get _hasActions {
    final reviewable =
        row.status == HatcheryDraftRowStatus.pending ||
        row.status == HatcheryDraftRowStatus.needsReview;
    return reviewable &&
        (onEdit != null || onApprove != null || onReject != null);
  }
}

class _FieldValue extends StatelessWidget {
  const _FieldValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.body),
      ],
    );
  }
}

class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.warning});

  final HatcheryRowWarning warning;

  @override
  Widget build(BuildContext context) {
    final isReview =
        warning.severity == HatcheryRowWarningSeverity.review ||
        warning.severity == HatcheryRowWarningSeverity.critical;
    final color = isReview ? AppColors.statusWarning : AppColors.statusActive;
    final background = isReview
        ? AppColors.statusWarningBg
        : AppColors.statusActiveBg;
    final severity = switch (warning.severity) {
      HatcheryRowWarningSeverity.info => 'Info',
      HatcheryRowWarningSeverity.review => 'Review',
      HatcheryRowWarningSeverity.critical => 'Critical',
    };
    final message = context.l10n.isArabic
        ? warning.messageAr
        : warning.messageEn;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isReview ? Icons.warning_amber_outlined : Icons.info_outline,
            color: color,
            size: AppSizes.iconSm,
          ),
          const SizedBox(width: AppSizes.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  severity,
                  style: AppTextStyles.badgeLabel.copyWith(color: color),
                ),
                const SizedBox(height: AppSizes.spaceXs),
                Text(message, style: AppTextStyles.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RowStatusChip extends StatelessWidget {
  const _RowStatusChip({required this.presentation});

  final _RowStatusPresentation presentation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: AppSizes.spaceXs,
      ),
      decoration: BoxDecoration(
        color: presentation.background,
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      child: Text(
        presentation.label,
        style: AppTextStyles.badgeLabel.copyWith(
          color: presentation.foreground,
        ),
      ),
    );
  }
}

class _RowStatusPresentation {
  const _RowStatusPresentation({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;
}

_RowStatusPresentation _rowStatusPresentation(HatcheryDraftRowStatus status) {
  return switch (status) {
    HatcheryDraftRowStatus.pending => const _RowStatusPresentation(
      label: 'Pending',
      foreground: AppColors.statusNeutralText,
      background: AppColors.statusNeutralBg,
    ),
    HatcheryDraftRowStatus.needsReview => const _RowStatusPresentation(
      label: 'Needs review',
      foreground: AppColors.statusWarning,
      background: AppColors.statusWarningBg,
    ),
    HatcheryDraftRowStatus.approved => const _RowStatusPresentation(
      label: 'Approved',
      foreground: AppColors.statusGood,
      background: AppColors.statusGoodBg,
    ),
    HatcheryDraftRowStatus.rejected => const _RowStatusPresentation(
      label: 'Rejected',
      foreground: AppColors.statusError,
      background: AppColors.statusErrorBg,
    ),
  };
}

List<HatcheryRowWarning> _parseWarnings(String? source) {
  if (source == null || source.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(source);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map(
          (warning) =>
              HatcheryRowWarning.fromJson(Map<String, Object?>.from(warning)),
        )
        .toList(growable: false);
  } on FormatException {
    return const [];
  }
}

List<_ExtractedValue> _extractedValues(HatcheryDraftRow row) {
  final values = <_ExtractedValue>[
    _ExtractedValue('Customer', row.customerName),
    _ExtractedValue('Flock', row.flockName),
    _ExtractedValue('Station', row.stationName),
    _ExtractedValue('Breed', row.breed),
    _ExtractedValue('Eggs placed', _integer(row.eggsPlaced)),
    _ExtractedValue('Production date', _date(row.productionDate)),
    _ExtractedValue('Placement date', _date(row.placementDate)),
    _ExtractedValue('Egg weight', _decimal(row.eggWeightG, suffix: ' g')),
    _ExtractedValue('Fertility', _decimal(row.fertilityPct, suffix: '%')),
    _ExtractedValue(
      'Transfer weight',
      _decimal(row.transferWeightG, suffix: ' g'),
    ),
    _ExtractedValue('Setter', row.setterNumber),
    _ExtractedValue('Hatcher', row.hatcherNumber),
    _ExtractedValue('Hatch date', _date(row.hatchDate)),
    _ExtractedValue('Healthy chicks', _integer(row.healthyChicks)),
    _ExtractedValue('Second grade', _integer(row.secondGradeChicks)),
    _ExtractedValue('Condemned', _integer(row.condemnedChicks)),
    _ExtractedValue('Total production', _integer(row.totalProduction)),
    _ExtractedValue('Hatchability', _decimal(row.hatchabilityPct, suffix: '%')),
    _ExtractedValue(
      'Proposed flock age',
      row.proposedFlockAgeWeeks == null
          ? null
          : '${row.proposedFlockAgeWeeks} weeks',
    ),
  ];
  return values
      .where((value) => value.value != null)
      .map((value) => _ExtractedValue(value.label, value.value!))
      .toList(growable: false);
}

class _ExtractedValue {
  const _ExtractedValue(this.label, this.value);

  final String label;
  final String? value;
}

String _percentage(double? value) {
  return value == null ? '—' : '${value.toStringAsFixed(1)}%';
}

String? _integer(int? value) => value?.toString();

String? _decimal(double? value, {required String suffix}) {
  if (value == null) return null;
  return '${value.toStringAsFixed(1)}$suffix';
}

String? _date(DateTime? value) {
  if (value == null) return null;
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

Color _confidenceColor(double? value) {
  if (value == null) return AppColors.statusNeutralText;
  if (value >= 85) return AppColors.statusGood;
  if (value >= 60) return AppColors.statusWarning;
  return AppColors.statusError;
}
