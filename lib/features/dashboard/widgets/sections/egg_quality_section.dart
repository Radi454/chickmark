import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/constants/app_thresholds.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/section_shared.dart';
import 'package:hatchaudit/widgets/app_card.dart';
import 'package:hatchaudit/widgets/photo_grid.dart';

class EggQualitySection extends StatelessWidget {
  const EggQualitySection({super.key});

  static const double _uvAffectedLimitPct = 5.0;

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final latest = provider.eggStorageLatest;
        final compact = MediaQuery.sizeOf(context).width < 430;

        if (provider.isLoading) {
          return const AppCard(
            margin: EdgeInsets.zero,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final hasData = latest != null && _hasEggQualityData(latest);
        return AppCard(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.all(
            compact ? AppSizes.spaceMd : AppSizes.spaceLg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EggQualityHero(completed: hasData),
              const SizedBox(height: AppSizes.spaceLg),
              if (!hasData)
                emptySection('egg quality')
              else ...[
                _EggWeightsQualityCard(latest: latest),
                const SizedBox(height: AppSizes.spaceMd),
                _EggUvQualityCard(
                  latest: latest,
                  photos: provider.uvPhotos,
                  onPhotoTap: (path) => openPhoto(context, path),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  bool _hasEggQualityData(EggStorageTrend latest) {
    return latest.eggSampleSize > 0 ||
        latest.avgWeightG > 0 ||
        latest.uvTrayEggCount > 0 ||
        latest.uvAffectedPct > 0 ||
        latest.uvCuticleDamagePct > 0 ||
        latest.uvWashedPct > 0 ||
        latest.uvDirtyPct > 0;
  }
}

class _EggQualityHero extends StatelessWidget {
  final bool completed;

  const _EggQualityHero({required this.completed});

  @override
  Widget build(BuildContext context) {
    final statusColor = completed
        ? AppColors.statusGood
        : AppColors.textTertiary;
    final icon = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.egg_alt_outlined,
        color: AppColors.primary,
        size: 28,
      ),
    );

    Widget titleBlock({double titleSize = 22}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Egg Quality',
            style: AppTextStyles.sectionTitle.copyWith(
              fontSize: titleSize,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            'Weights & uniformity • Shell UV',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    Widget statusBadge() {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceMd,
          vertical: AppSizes.spaceSm,
        ),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: statusColor.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              completed ? Icons.check : Icons.pending_outlined,
              color: statusColor,
              size: 18,
            ),
            const SizedBox(width: AppSizes.spaceSm),
            Text(
              completed ? 'Recorded' : 'No data',
              style: AppTextStyles.badgeLabel.copyWith(color: statusColor),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
        color: AppColors.surface,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 430) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: AppSizes.spaceMd),
                    Expanded(child: titleBlock(titleSize: 20)),
                  ],
                ),
                const SizedBox(height: AppSizes.spaceMd),
                statusBadge(),
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: AppSizes.spaceMd),
              Expanded(child: titleBlock()),
              statusBadge(),
            ],
          );
        },
      ),
    );
  }
}

class _EggWeightsQualityCard extends StatelessWidget {
  final EggStorageTrend latest;

  const _EggWeightsQualityCard({required this.latest});

  @override
  Widget build(BuildContext context) {
    final lowMargin = latest.avgWeightG > 0 ? latest.avgWeightG * 0.9 : 0.0;
    final highMargin = latest.avgWeightG > 0 ? latest.avgWeightG * 1.1 : 0.0;
    final cvIsAlarm = latest.cvPct > AppThresholds.cvAlertPct;
    final uniformityIsAlarm =
        latest.uniformityPct > 0 &&
        latest.uniformityPct < AppThresholds.uniformityGood;
    final hasAlarm = cvIsAlarm || uniformityIsAlarm;

    return EggDashboardPanel(
      title: 'Egg Weights & Uniformity',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = _QualitySummaryCard(
            metrics: [
              _QualitySummaryMetric(
                label: 'Average',
                value: latest.avgWeightG == 0
                    ? '--'
                    : '${one(latest.avgWeightG)}g',
                note: 'Egg weight',
              ),
              _QualitySummaryMetric(
                label: 'Uniformity',
                value: latest.uniformityPct == 0
                    ? '--'
                    : '${one(latest.uniformityPct)}%',
                note:
                    'Target >= ${AppThresholds.uniformityGood.toStringAsFixed(1)}%',
                isAlarm: uniformityIsAlarm,
              ),
              _QualitySummaryMetric(
                label: 'C.V',
                value: latest.cvPct == 0 ? '--' : '${one(latest.cvPct)}%',
                note:
                    'Limit <= ${AppThresholds.cvAlertPct.toStringAsFixed(1)}%',
                isAlarm: cvIsAlarm,
              ),
            ],
            alarmMessage: hasAlarm
                ? _weightAlarmMessage(cvIsAlarm, uniformityIsAlarm)
                : null,
          );
          final details = EggInfoValueGrid(
            values: [
              EggInfoValue(
                label: 'Sample Size',
                value: latest.eggSampleSize == 0
                    ? '--'
                    : '${latest.eggSampleSize}/100',
              ),
              EggInfoValue(
                label: 'BMK Egg Weight',
                value: latest.eggBmkWeight == 0
                    ? '--'
                    : '${one(latest.eggBmkWeight)}g',
              ),
              EggInfoValue(
                label: 'Low Margin',
                value: lowMargin == 0 ? '--' : '${one(lowMargin)}g',
              ),
              EggInfoValue(
                label: 'High Margin',
                value: highMargin == 0 ? '--' : '${one(highMargin)}g',
              ),
            ],
          );

          if (constraints.maxWidth < 760) {
            return Column(
              children: [
                summary,
                const SizedBox(height: AppSizes.spaceMd),
                details,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: AppSizes.spaceLg),
              SizedBox(
                width: constraints.maxWidth.clamp(280.0, 320.0),
                child: summary,
              ),
            ],
          );
        },
      ),
    );
  }

  String _weightAlarmMessage(bool cvIsAlarm, bool uniformityIsAlarm) {
    if (cvIsAlarm && uniformityIsAlarm) {
      return 'C.V is above the app limit, and uniformity is below target.';
    }
    if (cvIsAlarm) return 'C.V is above the app limit.';
    return 'Uniformity is below target.';
  }
}

class _EggUvQualityCard extends StatelessWidget {
  final EggStorageTrend latest;
  final List<String> photos;
  final ValueChanged<String> onPhotoTap;

  const _EggUvQualityCard({
    required this.latest,
    required this.photos,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final affectedIsAlarm =
        latest.uvAffectedPct > EggQualitySection._uvAffectedLimitPct;
    return EggDashboardPanel(
      title: 'Shell Quality UV',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = _QualitySummaryCard(
            metrics: [
              _QualitySummaryMetric(
                label: 'Affected',
                value: '${one(latest.uvAffectedPct)}%',
                note: affectedIsAlarm ? 'High vs target' : 'Within target',
                isAlarm: affectedIsAlarm,
              ),
              const _QualitySummaryMetric(
                label: 'Target',
                value: '<= 5.0%',
                note: 'UV affected',
              ),
              _QualitySummaryMetric(
                label: 'Status',
                value: affectedIsAlarm ? 'Alarm' : 'Clear',
                note: latest.uvTrayEggCount == 0
                    ? 'Recorded'
                    : '${latest.uvTrayEggCount} eggs',
                isAlarm: affectedIsAlarm,
              ),
            ],
            alarmMessage: affectedIsAlarm
                ? 'UV affected is above the app limit.'
                : null,
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EggInfoValueGrid(
                values: [
                  EggInfoValue(
                    label: 'Cuticle Damage',
                    value: '${one(latest.uvCuticleDamagePct)}%',
                  ),
                  EggInfoValue(
                    label: 'Washed',
                    value: '${one(latest.uvWashedPct)}%',
                  ),
                  EggInfoValue(
                    label: 'Dirty',
                    value: '${one(latest.uvDirtyPct)}%',
                  ),
                ],
              ),
              if (photos.isNotEmpty) ...[
                const SizedBox(height: AppSizes.spaceMd),
                PhotoGrid(filePaths: photos, onTap: onPhotoTap),
              ],
            ],
          );

          if (constraints.maxWidth < 760) {
            return Column(
              children: [
                summary,
                const SizedBox(height: AppSizes.spaceMd),
                details,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: AppSizes.spaceLg),
              SizedBox(
                width: constraints.maxWidth.clamp(280.0, 320.0),
                child: summary,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QualitySummaryMetric {
  final String label;
  final String value;
  final String note;
  final bool isAlarm;

  const _QualitySummaryMetric({
    required this.label,
    required this.value,
    required this.note,
    this.isAlarm = false,
  });
}

class _QualitySummaryCard extends StatelessWidget {
  final List<_QualitySummaryMetric> metrics;
  final String? alarmMessage;

  const _QualitySummaryCard({required this.metrics, this.alarmMessage});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return Container(
          padding: EdgeInsets.all(
            compact ? AppSizes.spaceMd : AppSizes.spaceLg,
          ),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppSizes.cardRadius + 6),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2A193FC2),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSizes.spaceSm),
                      Expanded(
                        child: EstSummaryMetric(
                          label: metrics[i].label,
                          value: metrics[i].value,
                          note: metrics[i].note,
                          isAlarm: metrics[i].isAlarm,
                          compact: true,
                        ),
                      ),
                    ],
                  ],
                )
              else
                for (var i = 0; i < metrics.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSizes.spaceLg),
                  EstSummaryMetric(
                    label: metrics[i].label,
                    value: metrics[i].value,
                    note: metrics[i].note,
                    isAlarm: metrics[i].isAlarm,
                  ),
                ],
              if (alarmMessage != null) ...[
                SizedBox(height: compact ? AppSizes.spaceSm : AppSizes.spaceLg),
                Container(
                  padding: EdgeInsets.all(
                    compact ? AppSizes.spaceSm : AppSizes.spaceMd,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.statusErrorBg,
                    borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                    border: Border.all(
                      color: AppColors.statusError.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alarm',
                        style: AppTextStyles.badgeLabel.copyWith(
                          color: AppColors.statusError,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: AppSizes.spaceXs),
                      Text(
                        alarmMessage!,
                        style: AppTextStyles.caption.copyWith(
                          color: const Color(0xFF7C2D12),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
