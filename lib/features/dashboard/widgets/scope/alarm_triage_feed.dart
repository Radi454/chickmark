import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../scope/scope_models.dart';

/// One row in an [AlarmTriageFeed]. Severity picks the tier — `err` → Critical,
/// `warn` → Watch, `good` → In Target. All text is pre-formatted by the builder
/// so this stays pure presentation (mirrors the V5 triage prototype card).
class TriageItem {
  final ScopeSeverity severity;

  /// Blue chip — the source sector / place (e.g. "Hatch Result", "Hatcher room").
  final String primaryTag;

  /// Optional grey chip — the scope within the source ("Pooled", "S-03", "H1·…").
  final String? secondaryTag;

  /// Bold metric name ("Hatchability", "EST CV%", "CO₂").
  final String metric;

  /// Formatted reading ("84.2%", "3,100 ppm").
  final String value;

  /// Threshold context ("BMK 86.0% · −1.8 vs benchmark", "Limit ≤ 8.0%").
  final String context;

  /// Optional one-line action; shown on Critical / Watch cards only.
  final String? advice;

  const TriageItem({
    required this.severity,
    required this.primaryTag,
    this.secondaryTag,
    required this.metric,
    required this.value,
    required this.context,
    this.advice,
  });

  bool get isCritical => severity == ScopeSeverity.err;
  bool get isWatch => severity == ScopeSeverity.warn;
}

/// Triage feed: a "Critical — Action Required" section, a "Watch — Near
/// Threshold" section, and a collapsed-by-default green "In Target" section.
/// Renders nothing when there is nothing to report.
class AlarmTriageFeed extends StatefulWidget {
  final List<TriageItem> items;

  const AlarmTriageFeed({super.key, required this.items});

  @override
  State<AlarmTriageFeed> createState() => _AlarmTriageFeedState();
}

class _AlarmTriageFeedState extends State<AlarmTriageFeed> {
  bool _showGood = false;

  @override
  Widget build(BuildContext context) {
    final critical = widget.items.where((i) => i.isCritical).toList();
    final watch = widget.items.where((i) => i.isWatch).toList();
    final good = widget.items
        .where((i) => i.severity == ScopeSeverity.good)
        .toList();

    if (critical.isEmpty && watch.isEmpty && good.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (critical.isNotEmpty) ...[
          const _SectionLabel('Critical — Action Required'),
          for (final item in critical) _AlertCard(item: item),
        ],
        if (watch.isNotEmpty) ...[
          if (critical.isNotEmpty) const SizedBox(height: AppSizes.spaceMd),
          const _SectionLabel('Watch — Near Threshold'),
          for (final item in watch) _AlertCard(item: item),
        ],
        if (critical.isEmpty && watch.isEmpty)
          _AllClearCard(inTarget: good.length),
        if (good.isNotEmpty) ...[
          const SizedBox(height: AppSizes.spaceSm),
          _GoodToggle(
            count: good.length,
            open: _showGood,
            onTap: () => setState(() => _showGood = !_showGood),
          ),
          if (_showGood)
            for (final item in good) _GoodRow(item: item),
        ],
      ],
    );
  }
}

// ── tier styling ──────────────────────────────────────────────────────────────

class _Tier {
  final String pill;
  final Color accent;
  final Color bg;
  final Color value;
  final Color advice;

  const _Tier(this.pill, this.accent, this.bg, this.value, this.advice);
}

_Tier _tierFor(ScopeSeverity severity) {
  switch (severity) {
    case ScopeSeverity.err:
      return const _Tier(
        'Critical',
        AppColors.statusError,
        AppColors.statusErrorBg,
        AppColors.statusError,
        Color(0xFF7F1D1D),
      );
    case ScopeSeverity.warn:
      return const _Tier(
        'Watch',
        AppColors.statusWarning,
        AppColors.statusWarningBg,
        Color(0xFF92400E),
        Color(0xFF78350F),
      );
    case ScopeSeverity.good:
    case ScopeSeverity.pool:
      return const _Tier(
        'In target',
        AppColors.statusGood,
        AppColors.statusGoodBg,
        AppColors.statusGood,
        AppColors.statusGood,
      );
  }
}

// ── section header ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ── critical / watch card ─────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final TriageItem item;

  const _AlertCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final tier = _tierFor(item.severity);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tier.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: tier.accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SevPill(label: tier.pill, color: tier.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    item.metric,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: tier.value,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Chip(label: item.primaryTag, primary: true),
              if (item.secondaryTag != null)
                _Chip(label: item.secondaryTag!, primary: false),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                item.value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: tier.value,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.context,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (item.advice != null) ...[
            const SizedBox(height: 6),
            Text(
              item.advice!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: tier.advice,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SevPill extends StatelessWidget {
  final String label;
  final Color color;

  const _SevPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool primary;

  const _Chip({required this.label, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: primary
            ? AppColors.primary.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(
          color: primary
              ? AppColors.primary.withValues(alpha: 0.22)
              : AppColors.borderDefault,
        ),
      ),
      child: Text(
        primary ? label.toUpperCase() : label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: primary ? FontWeight.w900 : FontWeight.w700,
          letterSpacing: primary ? 0.4 : 0,
          color: primary ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ── all-clear + collapsible "In Target" ───────────────────────────────────────

class _AllClearCard extends StatelessWidget {
  final int inTarget;

  const _AllClearCard({required this.inTarget});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.statusGoodBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.statusGood.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 20, color: AppColors.statusGood),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              inTarget == 0
                  ? 'All recorded readings are within target.'
                  : 'All $inTarget monitored readings are within target.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.completedText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoodToggle extends StatelessWidget {
  final int count;
  final bool open;
  final VoidCallback onTap;

  const _GoodToggle({
    required this.count,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 16,
              color: AppColors.statusGood,
            ),
            const SizedBox(width: 6),
            Text(
              '$count in target',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.statusGood,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              open ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: AppColors.statusGood,
            ),
          ],
        ),
      ),
    );
  }
}

class _GoodRow extends StatelessWidget {
  final TriageItem item;

  const _GoodRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.statusGoodBg,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border(
          left: BorderSide(color: AppColors.statusGood, width: 3),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              item.primaryTag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const Text(
            '  ·  ',
            style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
          ),
          Flexible(
            child: Text(
              item.metric,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Spacer(),
          const SizedBox(width: 8),
          Text(
            item.value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppColors.statusGood,
            ),
          ),
        ],
      ),
    );
  }
}
