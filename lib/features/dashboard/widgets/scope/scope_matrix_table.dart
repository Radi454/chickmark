import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import '../../scope/scope_models.dart';
import '../../scope/scope_severity.dart';
import 'scope_severity_style.dart';

/// The comparison matrix: a frozen "Parameter" column + a horizontally
/// scrolling pane (⌀ Avg column, highlighted blue, then one column per shown
/// group). Per-cell severity coloring. Sticky first column via a split layout
/// (DataTable can't freeze a column or paint per-cell backgrounds edge-to-edge).
///
/// Column widths are responsive; group headers (full scope names like
/// `H1·S1H1·Tr2·Ty5`) wrap to two lines instead of truncating.
class ScopeMatrixTable extends StatelessWidget {
  final String sectorId;
  final String avgLabel;
  final bool avgUsesPoolGroup;

  const ScopeMatrixTable({
    super.key,
    required this.sectorId,
    this.avgLabel = '⌀ Avg',
    this.avgUsesPoolGroup = false,
  });

  static const double _rowH = 40;
  static const double _headH = 46;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScopeComparisonProvider>();
    final sector = ScopeConfigRegistry.byId(sectorId);
    final params = sector.params;
    final groups = provider.groupsFor(sectorId);
    final visible = provider.visibleColumnIndexes(sectorId);
    final showAvg = provider.isAvgVisible(sectorId);
    final stats = provider.columnStatsFor(sectorId);
    final poolGroup = avgUsesPoolGroup ? provider.poolGroupFor(sectorId) : null;

    if (!showAvg && visible.isEmpty) {
      return _empty();
    }

    // Each param shows its benchmark under the label; taller rows fit two lines.
    final bmk = provider.bmkFor(sectorId);
    final hasBmk = params.any((p) => p.bmkField != null);
    final rowH = hasBmk ? 54.0 : _rowH;

    final screenW = MediaQuery.sizeOf(context).width;
    final phone = screenW < 600;
    final paramW = phone ? 112.0 : 150.0;
    final avgW = phone ? 74.0 : 88.0;
    final dataW = phone ? 128.0 : 144.0;

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
            children: [
              _headerCell(
                width: paramW,
                bg: AppColors.surfaceVariant,
                align: Alignment.centerLeft,
                child: const Text('Parameter', style: _headStyle),
              ),
              for (final p in params)
                _bodyCell(
                  width: paramW,
                  height: rowH,
                  bg: AppColors.surfaceRaised,
                  align: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (p.bmkField != null && bmk != null)
                        Text(
                          'BMK ${p.formatValue(bmkLookup(bmk, p.bmkField))}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.statusNeutralText,
                          ),
                        ),
                    ],
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
                  if (showAvg)
                    if (avgUsesPoolGroup && poolGroup != null)
                      _dataColumn(params, poolGroup, avgW, rowH)
                    else
                      _avgColumn(params, stats, avgW, rowH),
                  for (final i in visible)
                    _dataColumn(params, groups[i], dataW, rowH),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avgColumn(
    List<ScopeParam> params,
    List<ColumnStat> stats,
    double w,
    double rowH,
  ) {
    return _column(
      children: [
        _headerCell(
          width: w,
          bg: AppColors.statusActive,
          align: Alignment.centerRight,
          child: Text(
            avgLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        for (var j = 0; j < params.length; j++)
          _bodyCell(
            width: w,
            height: rowH,
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

  Widget _dataColumn(
    List<ScopeParam> params,
    ScopeGroup group,
    double w,
    double rowH,
  ) {
    return _column(
      children: [
        _headerCell(
          width: w,
          bg: AppColors.surfaceVariant,
          align: Alignment.centerRight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  group.label,
                  maxLines: 2,
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
        for (var j = 0; j < params.length; j++)
          _dataBodyCell(group.cells[j], w, rowH),
      ],
    );
  }

  Widget _dataBodyCell(ScopeCell cell, double w, double rowH) {
    final style = ScopeSeverityStyle.of(cell.severity);
    return _bodyCell(
      width: w,
      height: rowH,
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

  Widget _column({required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
    double height = _rowH,
  }) {
    return Container(
      width: width,
      height: height,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
    letterSpacing: 0.3,
    color: AppColors.textSecondary,
  );
}
