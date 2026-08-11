import 'package:hatchaudit/localized_material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_page_route.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/features/dashboard/screens/photo_fullscreen_screen.dart';
import 'package:hatchaudit/widgets/photo_grid.dart';

// ─── helpers shared across dashboard sections ────────────────────────────────

Widget sectionHeader(BuildContext context, String label) => Padding(
  padding: const EdgeInsets.fromLTRB(
    AppSizes.spaceLg,
    AppSizes.spaceMd,
    AppSizes.spaceLg,
    AppSizes.spaceXs,
  ),
  child: Text(label, style: AppTextStyles.sectionTitle),
);

Widget metricRow(String label, String value, {Color? color}) => Padding(
  padding: const EdgeInsets.symmetric(
    vertical: AppSizes.spaceXs,
    horizontal: AppSizes.spaceLg,
  ),
  child: Row(
    children: [
      Expanded(child: Text(label, style: AppTextStyles.body)),
      Text(value, style: AppTextStyles.badgeLabel),
      if (color != null) ...[
        const SizedBox(width: AppSizes.spaceSm),
        Container(
          width: AppSizes.spaceMd,
          height: AppSizes.spaceMd,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ],
    ],
  ),
);

Color threshold(double value, double good, {bool lowerIsBetter = false}) {
  if (good == 0) return AppColors.inactiveTab;
  return lowerIsBetter
      ? (value <= good ? AppColors.statusGood : AppColors.statusError)
      : (value >= good ? AppColors.statusGood : AppColors.statusError);
}

Color thresholdRange(double value, double min, double max) {
  return value >= min && value <= max
      ? AppColors.statusGood
      : AppColors.statusError;
}

Widget emptySection(String label) => Padding(
  padding: const EdgeInsets.all(AppSizes.spaceXl),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(
        Icons.bar_chart_outlined,
        size: 48,
        color: AppColors.textDisabled,
      ),
      const SizedBox(height: AppSizes.spaceSm),
      Text(
        'No $label data yet',
        style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
        textAlign: TextAlign.center,
      ),
    ],
  ),
);

Widget photoSection(BuildContext context, List<String> photos) {
  if (photos.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(),
      sectionHeader(context, 'Photos'),
      PhotoGrid(
        filePaths: photos,
        onTap: (path) => Navigator.push(
          context,
          AppPageRoute(builder: (_) => PhotoFullscreenScreen(filePath: path)),
        ),
      ),
    ],
  );
}

void openPhoto(BuildContext context, String path) {
  Navigator.push(
    context,
    AppPageRoute(builder: (_) => PhotoFullscreenScreen(filePath: path)),
  );
}

String one(double value) => value.toStringAsFixed(1);

// ─── shared egg widgets (used by both EggStorageSection and EggQualitySection) ─

class EggInfoValue {
  final String label;
  final String value;

  const EggInfoValue({required this.label, required this.value});
}

class EggInfoValueGrid extends StatelessWidget {
  final List<EggInfoValue> values;

  const EggInfoValueGrid({super.key, required this.values});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 480
            ? values.length
            : constraints.maxWidth >= 300
            ? 2
            : 1;
        final gap = AppSizes.spaceSm;
        final tileWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in values)
              SizedBox(
                width: tileWidth,
                child: _MetadataTile(label: item.label, value: item.value),
              ),
          ],
        );
      },
    );
  }
}

class _MetadataTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetadataTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class EggDashboardPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const EggDashboardPanel({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
        color: AppColors.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.title.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSizes.spaceMd),
          child,
        ],
      ),
    );
  }
}

class EstSummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final bool isAlarm;
  final bool compact;

  const EstSummaryMetric({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    this.isAlarm = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isAlarm
            ? Colors.white.withValues(alpha: 0.13)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSizes.spaceXs : AppSizes.spaceSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: compact ? 10 : null,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: AppSizes.spaceXs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppTextStyles.metricLarge.copyWith(
                  color: AppColors.textOnPrimary,
                  fontSize: compact ? 17 : 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: AppSizes.spaceXs),
            Text(
              note,
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: compact ? 10 : null,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
