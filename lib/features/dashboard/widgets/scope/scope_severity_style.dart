import 'package:hatchaudit/localized_material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../scope/scope_models.dart';

/// Maps [ScopeSeverity] to the table-cell roles the prototype uses
/// (background / text color / weight / dot). Flutter equivalent of the CSS
/// `cell-err` / `cell-warn` / `hdot.*` classes.
class ScopeSeverityStyle {
  final Color cellBg;
  final Color cellText;
  final FontWeight weight;
  final Color dot;

  const ScopeSeverityStyle({
    required this.cellBg,
    required this.cellText,
    required this.weight,
    required this.dot,
  });

  static ScopeSeverityStyle of(ScopeSeverity severity) {
    switch (severity) {
      case ScopeSeverity.err:
        return const ScopeSeverityStyle(
          cellBg: AppColors.statusErrorBg,
          cellText: AppColors.statusError,
          weight: FontWeight.w900,
          dot: AppColors.statusError,
        );
      case ScopeSeverity.warn:
        return const ScopeSeverityStyle(
          cellBg: AppColors.statusWarningBg,
          cellText: AppColors.scopeWarnText,
          weight: FontWeight.w800,
          dot: AppColors.statusWarning,
        );
      case ScopeSeverity.good:
        return const ScopeSeverityStyle(
          cellBg: Colors.transparent,
          cellText: AppColors.textPrimary,
          weight: FontWeight.w500,
          dot: AppColors.statusGood,
        );
      case ScopeSeverity.pool:
        return const ScopeSeverityStyle(
          cellBg: Colors.transparent,
          cellText: AppColors.textPrimary,
          weight: FontWeight.w500,
          dot: AppColors.textTertiary,
        );
    }
  }

  static Color dotColor(ScopeSeverity severity) => of(severity).dot;
}

/// A small status dot (severity / header indicator).
class StatusDot extends StatelessWidget {
  final Color color;
  final double size;

  const StatusDot(this.color, {super.key, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
