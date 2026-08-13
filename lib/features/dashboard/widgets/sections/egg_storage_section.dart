import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/constants/app_thresholds.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_bar_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_line_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/section_shared.dart';
import 'package:hatchaudit/features/audits/models/temperature_entry_unit.dart';
import 'package:hatchaudit/widgets/app_card.dart';
import 'package:hatchaudit/widgets/photo_grid.dart';

class EggStorageSection extends StatelessWidget {
  const EggStorageSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final latest = provider.eggStorageLatest;
        final evidence = provider.eggStorageEstEvidence;
        if (provider.isLoading) {
          return const AppCard(
            margin: EdgeInsets.zero,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (latest == null && evidence == null) {
          return AppCard(
            margin: EdgeInsets.zero,
            child: emptySection('egg storage'),
          );
        }

        final estEvidence = evidence ?? EggStorageEstEvidence.fromJsonStrings();
        final target = _EggStorageTarget.fromStorageDays(latest?.storageDays);
        final compact = MediaQuery.sizeOf(context).width < 430;

        return AppCard(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.all(
            compact ? AppSizes.spaceMd : AppSizes.spaceLg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EggStorageHero(
                target: target,
                completed: _hasAllReadings(estEvidence),
              ),
              const SizedBox(height: AppSizes.spaceLg),
              _EstReadingsGridCard(
                evidence: estEvidence,
                latest: latest,
                target: target,
                onPhotoTap: (path) => openPhoto(context, path),
              ),
              const SizedBox(height: AppSizes.spaceMd),
              _EggInfoRowCard(
                title: 'Upside Down Egg',
                values: [
                  EggInfoValue(
                    label: 'Count',
                    value: '${latest?.upsideDownCount ?? 0} eggs',
                  ),
                  EggInfoValue(
                    label: 'Rate',
                    value: '${one(latest?.upsideDownPct ?? 0)}%',
                  ),
                  const EggInfoValue(label: 'Status', value: 'Recorded'),
                ],
              ),
              const SizedBox(height: AppSizes.spaceMd),
              _EggInfoRowCard(
                title: 'Storage Info',
                values: [
                  EggInfoValue(
                    label: 'Storage',
                    value: latest?.storageDays == null
                        ? '--'
                        : '${latest!.storageDays} days',
                  ),
                  EggInfoValue(
                    label: 'Turning',
                    value: _turningLabel(latest?.turningTimes),
                  ),
                  EggInfoValue(
                    label: 'Tray spacing',
                    value: _text(latest?.traySpacing),
                  ),
                  EggInfoValue(
                    label: 'Cooler',
                    value: _text(latest?.coolerProximity),
                  ),
                  EggInfoValue(
                    label: 'Condensation',
                    value: latest?.condensationPresent == null
                        ? '--'
                        : latest!.condensationPresent!
                        ? 'Yes'
                        : 'No',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EggStorageHero extends StatelessWidget {
  final _EggStorageTarget target;
  final bool completed;

  const _EggStorageHero({required this.target, required this.completed});

  @override
  Widget build(BuildContext context) {
    final statusColor = completed
        ? AppColors.statusGood
        : AppColors.textTertiary;
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
              completed ? 'Completed' : 'Partial',
              style: AppTextStyles.badgeLabel.copyWith(color: statusColor),
            ),
          ],
        ),
      );
    }

    Widget titleBlock({double titleSize = 22}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Egg Storage & Handling',
            style: AppTextStyles.sectionTitle.copyWith(
              fontSize: titleSize,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            '${target.label} • ${target.rangeLabel} • 9-Point Check',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
          final icon = Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.thermostat_outlined,
              color: AppColors.primary,
              size: 30,
            ),
          );

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

class _EstReadingsGridCard extends StatelessWidget {
  final EggStorageEstEvidence evidence;
  final EggStorageTrend? latest;
  final _EggStorageTarget target;
  final ValueChanged<String> onPhotoTap;

  const _EstReadingsGridCard({
    required this.evidence,
    required this.latest,
    required this.target,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final avg = latest?.estAvgF;
    final cv = latest?.estCvPct;
    final unit = evidence.points.isEmpty
        ? TemperatureEntryUnit.celsius
        : evidence.points.first.unit;
    final avgC = avg == null
        ? null
        : unit.toCanonical(avg, canonicalUnit: TemperatureEntryUnit.celsius);
    final temperatureStatus = _EstTemperatureStatus.from(avgC, target);
    final cvIsAlarm = cv != null && cv > AppThresholds.cvAlertPct;
    final unitSuffix = unit.suffix;
    return EggDashboardPanel(
      title: 'Temperature Readings ($unitSuffix)',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = _EstSummaryCard(
            avg: avg,
            target: target,
            cv: cv,
            unitSuffix: unitSuffix,
            temperatureStatus: temperatureStatus,
            cvIsAlarm: cvIsAlarm,
          );
          final grid = _EstGrid(evidence: evidence, onPhotoTap: onPhotoTap);

          if (constraints.maxWidth < 760) {
            return Column(
              children: [
                summary,
                const SizedBox(height: AppSizes.spaceMd),
                grid,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: grid),
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

class _EstSummaryCard extends StatelessWidget {
  final double? avg;
  final _EggStorageTarget target;
  final double? cv;
  final String unitSuffix;
  final _EstTemperatureStatus temperatureStatus;
  final bool cvIsAlarm;

  const _EstSummaryCard({
    required this.avg,
    required this.target,
    required this.cv,
    required this.unitSuffix,
    required this.temperatureStatus,
    required this.cvIsAlarm,
  });

  @override
  Widget build(BuildContext context) {
    final hasAlarm = temperatureStatus.isAlarm || cvIsAlarm;
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
                    Expanded(
                      child: EstSummaryMetric(
                        label: 'Average',
                        value: avg == null || avg == 0
                            ? '--'
                            : '${one(avg!)}$unitSuffix',
                        note: temperatureStatus.label,
                        isAlarm: temperatureStatus.isAlarm,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: AppSizes.spaceSm),
                    Expanded(
                      child: EstSummaryMetric(
                        label: 'Target',
                        value: target.rangeLabel,
                        note: target.label,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: AppSizes.spaceSm),
                    Expanded(
                      child: EstSummaryMetric(
                        label: 'CV%',
                        value: cv == null ? '--' : '${one(cv!)}%',
                        note:
                            'Limit <= ${AppThresholds.cvAlertPct.toStringAsFixed(1)}%',
                        isAlarm: cvIsAlarm,
                        compact: true,
                      ),
                    ),
                  ],
                )
              else ...[
                EstSummaryMetric(
                  label: 'Average',
                  value: avg == null || avg == 0
                      ? '--'
                      : '${one(avg!)}$unitSuffix',
                  note: temperatureStatus.label,
                  isAlarm: temperatureStatus.isAlarm,
                ),
                const SizedBox(height: AppSizes.spaceLg),
                EstSummaryMetric(
                  label: 'Target',
                  value: target.rangeLabel,
                  note: target.label,
                ),
                const SizedBox(height: AppSizes.spaceLg),
                EstSummaryMetric(
                  label: 'CV%',
                  value: cv == null ? '--' : '${one(cv!)}%',
                  note:
                      'Limit <= ${AppThresholds.cvAlertPct.toStringAsFixed(1)}%',
                  isAlarm: cvIsAlarm,
                ),
              ],
              if (hasAlarm) ...[
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
                        _alarmMessage(temperatureStatus, cvIsAlarm),
                        style: AppTextStyles.caption.copyWith(
                          color: const Color(0xFF991B1B),
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

  String _alarmMessage(
    _EstTemperatureStatus temperatureStatus,
    bool cvIsAlarm,
  ) {
    if (temperatureStatus.isAlarm && cvIsAlarm) {
      return 'Average is ${temperatureStatus.direction} target, and CV% is above the app limit.';
    }
    if (temperatureStatus.isAlarm) {
      return 'Average is ${temperatureStatus.direction} target.';
    }
    return 'CV% is above the app limit.';
  }
}

class _EstGrid extends StatelessWidget {
  final EggStorageEstEvidence evidence;
  final ValueChanged<String> onPhotoTap;

  const _EstGrid({required this.evidence, required this.onPhotoTap});

  static const _columns = ['Front', 'Middle', 'Back'];
  static const _rows = ['Top', 'Middle', 'Bottom'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final sideWidth = compact ? 58.0 : 78.0;
        final cellPadding = compact ? 3.0 : 5.0;
        return Container(
          padding: EdgeInsets.all(
            compact ? AppSizes.spaceSm : AppSizes.spaceMd,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            border: Border.all(color: AppColors.borderDefault),
            color: AppColors.surface,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(width: sideWidth),
                  for (final column in _columns)
                    Expanded(
                      child: Text(
                        column,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body.copyWith(
                          fontSize: compact ? 13 : null,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSizes.spaceSm),
              for (final row in _rows) ...[
                _EstGridRow(
                  row: row,
                  points: [for (final column in _columns) _point(column, row)],
                  onPhotoTap: onPhotoTap,
                  compact: compact,
                  sideWidth: sideWidth,
                  cellPadding: cellPadding,
                ),
                if (row != _rows.last) const Divider(height: AppSizes.spaceLg),
              ],
            ],
          ),
        );
      },
    );
  }

  EggStorageEstEvidencePoint _point(String column, String row) {
    final key = '${column.toLowerCase()}_${row.toLowerCase()}';
    return evidence.points.firstWhere(
      (point) => point.key == key,
      orElse: () => EggStorageEstEvidencePoint(
        key: key,
        positionLabel: column,
        levelLabel: row,
      ),
    );
  }
}

class _EstGridRow extends StatelessWidget {
  final String row;
  final List<EggStorageEstEvidencePoint> points;
  final ValueChanged<String> onPhotoTap;
  final bool compact;
  final double sideWidth;
  final double cellPadding;

  const _EstGridRow({
    required this.row,
    required this.points,
    required this.onPhotoTap,
    required this.compact,
    required this.sideWidth,
    required this.cellPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: sideWidth,
          child: Text(
            row,
            style: AppTextStyles.body.copyWith(
              fontSize: compact ? 13 : null,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        for (final point in points)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: cellPadding),
              child: _EstReadingCell(
                point: point,
                onPhotoTap: onPhotoTap,
                compact: compact,
              ),
            ),
          ),
      ],
    );
  }
}

class _EstReadingCell extends StatelessWidget {
  final EggStorageEstEvidencePoint point;
  final ValueChanged<String> onPhotoTap;
  final bool compact;

  const _EstReadingCell({
    required this.point,
    required this.onPhotoTap,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final path = point.photoPath;
    final hasPhoto = isPhotoPathDisplayable(path);
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 86 : 104),
      padding: EdgeInsets.all(compact ? AppSizes.spaceXs : AppSizes.spaceSm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
        color: AppColors.surfaceVariant.withValues(alpha: 0.42),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              point.readingLabel,
              maxLines: 1,
              style: AppTextStyles.sectionTitle.copyWith(
                color: AppColors.textPrimary,
                fontSize: compact ? 16 : null,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.spaceSm),
          InkWell(
            key: ValueKey('est-evidence-${point.key}'),
            borderRadius: BorderRadius.circular(8),
            onTap: hasPhoto ? () => onPhotoTap(path!) : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: compact ? 34 : 46,
                width: double.infinity,
                child: hasPhoto
                    ? PhotoImage(
                        filePath: path!,
                        fit: BoxFit.cover,
                        cacheWidth: 220,
                        placeholderBuilder: (_) =>
                            _EstPhotoPlaceholder(hasPhoto: point.hasPhoto),
                      )
                    : _EstPhotoPlaceholder(hasPhoto: point.hasPhoto),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstPhotoPlaceholder extends StatelessWidget {
  final bool hasPhoto;

  const _EstPhotoPlaceholder({required this.hasPhoto});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hasPhoto
            ? AppColors.activeBg.withValues(alpha: 0.78)
            : AppColors.surfaceVariant.withValues(alpha: 0.85),
      ),
      child: Icon(
        Icons.add_photo_alternate_outlined,
        color: hasPhoto ? AppColors.primary : AppColors.textTertiary,
        size: 18,
      ),
    );
  }
}

class _EggInfoRowCard extends StatelessWidget {
  final String title;
  final List<EggInfoValue> values;

  const _EggInfoRowCard({required this.title, required this.values});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceLg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius + 4),
        border: Border.all(color: AppColors.borderDefault),
        color: AppColors.surface,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final valueGrid = EggInfoValueGrid(values: values);
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.title.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AppSizes.spaceMd),
                valueGrid,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: Text(
                  title,
                  style: AppTextStyles.title.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.spaceMd),
              Expanded(child: valueGrid),
            ],
          );
        },
      ),
    );
  }
}

class _EstTemperatureStatus {
  final String label;
  final String direction;
  final bool isAlarm;

  const _EstTemperatureStatus({
    required this.label,
    required this.direction,
    required this.isAlarm,
  });

  factory _EstTemperatureStatus.from(double? avg, _EggStorageTarget target) {
    if (avg == null || avg == 0) {
      return const _EstTemperatureStatus(
        label: 'No reading',
        direction: 'outside',
        isAlarm: false,
      );
    }
    if (avg < target.minC) {
      return const _EstTemperatureStatus(
        label: 'Low vs target',
        direction: 'below',
        isAlarm: true,
      );
    }
    if (avg > target.maxC) {
      return const _EstTemperatureStatus(
        label: 'High vs target',
        direction: 'above',
        isAlarm: true,
      );
    }
    return const _EstTemperatureStatus(
      label: 'Within target',
      direction: 'inside',
      isAlarm: false,
    );
  }
}

class _EggStorageTarget {
  final String label;
  final int minC;
  final int maxC;

  const _EggStorageTarget({
    required this.label,
    required this.minC,
    required this.maxC,
  });

  String get rangeLabel => '$minC-$maxC°C';

  factory _EggStorageTarget.fromStorageDays(int? storageDays) {
    final days = storageDays ?? 0;
    if (days <= 4) {
      return const _EggStorageTarget(
        label: 'Short storage',
        minC: 19,
        maxC: 21,
      );
    }
    if (days <= 7) {
      return const _EggStorageTarget(
        label: 'Medium storage',
        minC: 18,
        maxC: 20,
      );
    }
    return const _EggStorageTarget(label: 'Long storage', minC: 16, maxC: 18);
  }
}

bool _hasAllReadings(EggStorageEstEvidence evidence) {
  return evidence.points.isNotEmpty &&
      evidence.points.every((point) => point.readingC != null);
}

String _text(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? '--' : text;
}

String _turningLabel(int? turningTimes) {
  if (turningTimes == null) return '--';
  if (turningTimes == 0) return 'No Turning';
  if (turningTimes == 1) return '1 time';
  return '$turningTimes times';
}

// ignore: unused_element
class _EggUniformityTab extends StatelessWidget {
  final DashboardProvider provider;
  const _EggUniformityTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final trend = provider.eggStorageTrend;
    final latest = provider.eggStorageLatest;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (latest == null) return emptySection('egg storage');

    final spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.uniformityPct))
        .toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        metricRow('Avg Weight', '${latest.avgWeightG.toStringAsFixed(1)} g'),
        metricRow('Uniformity', '${latest.uniformityPct.toStringAsFixed(1)}%'),
        metricRow(
          'CV%',
          '${latest.cvPct.toStringAsFixed(1)}%',
          color: threshold(
            latest.cvPct,
            AppThresholds.cvAlertPct,
            lowerIsBetter: true,
          ),
        ),
        metricRow(
          'EST Avg (°F)',
          latest.estAvgF.toStringAsFixed(1),
          color: latest.estAvgF > 0
              ? thresholdRange(
                  latest.estAvgF,
                  AppThresholds.estMin,
                  AppThresholds.estMax,
                )
              : null,
        ),
        metricRow(
          'EST CV%',
          '${latest.estCvPct.toStringAsFixed(1)}%',
          color: latest.estCvPct > 0
              ? threshold(
                  latest.estCvPct,
                  AppThresholds.cvAlertPct,
                  lowerIsBetter: true,
                )
              : null,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 160,
            child: BmkLineChart(
              dataPoints: spots.isEmpty
                  ? [FlSpot(0, latest.uniformityPct)]
                  : spots,
              bmkValue: 0,
              yLabel: '%',
            ),
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _UvTab extends StatelessWidget {
  final DashboardProvider provider;
  const _UvTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final latest = provider.eggStorageLatest;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (latest == null) return emptySection('UV');

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        metricRow(
          'UV Affected',
          '${latest.uvAffectedPct.toStringAsFixed(1)}%',
          color: threshold(latest.uvAffectedPct, 5, lowerIsBetter: true),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 150,
            child: BmkBarChart(
              barGroups: [BmkBarChart.createGroup(0, latest.uvAffectedPct)],
              bmkValue: 5,
              xLabel: '',
              xLabels: const ['UV%'],
            ),
          ),
        ),
        photoSection(context, provider.uvPhotos),
      ],
    );
  }
}
