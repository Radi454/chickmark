import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import '../../scope/scope_models.dart';
import 'scope_severity_style.dart';

/// The comparison matrix: a frozen "Parameter" column + a horizontally
/// scrolling pane (⌀ Avg column, highlighted blue, then one column per shown
/// group). Per-cell severity coloring. Sticky first column via a split layout
/// (DataTable can't freeze a column or paint per-cell backgrounds edge-to-edge).
class ScopeMatrixTable extends StatelessWidget {
  final String sectorId;

  const ScopeMatrixTable({super.key, required this.sectorId});

  static const double _rowH = 40;
  static const double _headH = 36;
  static const double _paramW = 132;
  static const double _avgW = 86;
  static const double _dataW = 112;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScopeComparisonProvider>();
    final sector = ScopeConfigRegistry.byId(sectorId);
    final params = sector.params;
    final groups = provider.groupsFor(sectorId);
    final visible = provider.visibleColumnIndexes(sectorId);
    final showAvg = provider.isAvgVisible(sectorId);
    final stats = provider.columnStatsFor(sectorId);

    if (!showAvg && visible.isEmpty) {
      return _empty();
    }

    return Container(
      margin: const EdgeInsets.only(top: AppSizes.spaceMd),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Frozen Parameter column.
          _column(
            width: _paramW,
            header: _headerCell(
              width: _paramW,
              bg: AppColors.surfaceVariant,
              child: Text('Parameter', style: _headStyle, textAlign: TextAlign.left),
              align: Alignment.centerLeft,
            ),
            cells: [
              for (final p in params)
                _bodyCell(
                  width: _paramW,
                  bg: AppColors.surfaceRaised,
                  align: Alignment.centerLeft,
                  child: Text(
                    p.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
          // Scrolling data pane.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showAvg) _avgColumn(params, stats),
                  for (final i in visible) _dataColumn(params, groups[i]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avgColumn(List<ScopeParam> params, List<ColumnStat> stats) {
    return _column(
      width: _avgW,
      header: _headerCell(
        width: _avgW,
        bg: AppColors.statusActive,
        align: Alignment.centerRight,
        child: const Text(
          '⌀ Avg',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
      cells: [
        for (var j = 0; j < params.length; j++)
          _bodyCell(
            width: _avgW,
            bg: AppColors.statusActiveBg,
            align: Alignment.centerRight,
            child: Text(
              j < stats.length ? stats[j].avgText : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.statusActive,
              ),
            ),
          ),
      ],
    );
  }

  Widget _dataColumn(List<ScopeParam> params, ScopeGroup group) {
    return _column(
      width: _dataW,
      header: _headerCell(
        width: _dataW,
        bg: AppColors.surfaceVariant,
        align: Alignment.centerRight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                group.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: _headStyle,
              ),
            ),
            const SizedBox(width: 5),
            StatusDot(ScopeSeverityStyle.dotColor(group.severity)),
          ],
        ),
      ),
      cells: [
        for (var j = 0; j < params.length; j++)
          _dataBodyCell(group.cells[j]),
      ],
    );
  }

  Widget _dataBodyCell(ScopeCell cell) {
    final style = ScopeSeverityStyle.of(cell.severity);
    return _bodyCell(
      width: _dataW,
      bg: style.cellBg == Colors.transparent ? null : style.cellBg,
      align: Alignment.centerRight,
      child: Text(
        cell.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: style.weight,
          color: style.cellText,
        ),
      ),
    );
  }

  // ── primitives ───────────────────────────────────────────────────────────

  Widget _column({
    required double width,
    required Widget header,
    required List<Widget> cells,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, ...cells],
    );
  }

  Widget _headerCell({
    required double width,
    required Widget child,
    required Color bg,
    Alignment align = Alignment.centerLeft,
  }) {
    return Container(
      width: width,
      height: _headH,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        border: const Border(
          bottom: BorderSide(color: AppColors.borderDefault),
        ),
      ),
      child: child,
    );
  }

  Widget _bodyCell({
    required double width,
    required Widget child,
    Color? bg,
    Alignment align = Alignment.centerLeft,
  }) {
    return Container(
      width: width,
      height: _rowH,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        border: const Border(
          bottom: BorderSide(color: AppColors.borderDefault, width: 0.5),
        ),
      ),
      child: child,
    );
  }

  Widget _empty() {
    return Container(
      margin: const EdgeInsets.only(top: AppSizes.spaceMd),
      padding: const EdgeInsets.all(18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      child: const Text(
        'Pick at least one column to compare.',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  static const TextStyle _headStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.4,
    color: AppColors.textSecondary,
  );
}
