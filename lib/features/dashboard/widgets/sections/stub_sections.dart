import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/constants/app_thresholds.dart';
import 'package:hatchaudit/core/theme/app_page_route.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/data/models/troubleshooting_model.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/utils/pasgar_interpretation.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_line_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_bar_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/est_evidence_photos_card.dart';
import 'package:hatchaudit/widgets/photo_grid.dart';
import 'package:hatchaudit/features/dashboard/screens/photo_fullscreen_screen.dart';
import 'package:hatchaudit/widgets/app_card.dart';

// ─── helpers ────────────────────────────────────────────────────────────────

Widget _sectionHeader(BuildContext context, String label) => Padding(
  padding: const EdgeInsets.fromLTRB(
    AppSizes.spaceLg,
    AppSizes.spaceMd,
    AppSizes.spaceLg,
    AppSizes.spaceXs,
  ),
  child: Text(label, style: AppTextStyles.sectionTitle),
);

Widget _metricRow(String label, String value, {Color? color}) => Padding(
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

Color _threshold(double value, double good, {bool lowerIsBetter = false}) {
  if (good == 0) return AppColors.inactiveTab;
  return lowerIsBetter
      ? (value <= good ? AppColors.statusGood : AppColors.statusError)
      : (value >= good ? AppColors.statusGood : AppColors.statusError);
}

Color _thresholdRange(double value, double min, double max) {
  return value >= min && value <= max
      ? AppColors.statusGood
      : AppColors.statusError;
}

Widget _emptySection(String label) => Padding(
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

Widget _photoSection(BuildContext context, List<String> photos) {
  if (photos.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(),
      _sectionHeader(context, 'Photos'),
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

// ─── Chicks ───────────────────────────────────────────────────────────

class ChickQualitySection extends StatefulWidget {
  const ChickQualitySection({super.key});

  @override
  State<ChickQualitySection> createState() => _ChickQualitySectionState();
}

class _ChickQualitySectionState extends State<ChickQualitySection>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        return Card(
          child: ExpansionTile(
            title: const Text('Chicks'),
            initiallyExpanded: true,
            children: [
              TabBar(
                controller: _tab,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'Weights'),
                  Tab(text: 'Pasgar'),
                  Tab(text: 'CVT'),
                  Tab(text: 'YFBM'),
                  Tab(text: 'Culled'),
                ],
              ),
              SizedBox(
                height: 380,
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _WeightsTab(provider: provider),
                    _PasgarTab(provider: provider),
                    _CvtTab(provider: provider),
                    _YfbmTab(provider: provider),
                    _CulledChicksTab(provider: provider),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WeightsTab extends StatelessWidget {
  final DashboardProvider provider;
  const _WeightsTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final trend = provider.chickWeightTrend;
    final latest = provider.chickWeightLatest;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (latest == null) {
      return _emptySection('weights');
    }
    final spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.avgWeightG))
        .toList();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricRow('Avg Weight', '${latest.avgWeightG.toStringAsFixed(1)} g'),
        _metricRow('Uniformity', '${latest.uniformityPct.toStringAsFixed(1)}%'),
        _metricRow(
          'CV%',
          '${latest.cvPct.toStringAsFixed(1)}%',
          color: _threshold(
            latest.cvPct,
            AppThresholds.cvAlertPct,
            lowerIsBetter: true,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 160,
            child: BmkLineChart(
              dataPoints: spots.isEmpty
                  ? [FlSpot(0, latest.avgWeightG)]
                  : spots,
              bmkValue: provider.bmkReference?.chickWeightG ?? 0,
              yLabel: 'g',
            ),
          ),
        ),
      ],
    );
  }
}

class _PasgarTab extends StatelessWidget {
  final DashboardProvider provider;
  const _PasgarTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final avg = provider.pasgarAvg;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (avg == null) return _emptySection('Pasgar');
    final refs = provider.pasgarReferences;
    final scoreRef = refs['pasgar_final_score'];
    final scoreColor = _pasgarScoreColor(avg.score);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _PasgarInterpretationCard(
            score: avg.score,
            reference: scoreRef,
          ),
        ),
        _metricRow(
          'Final Score',
          avg.score.toStringAsFixed(1),
          color: scoreColor,
        ),
        const Divider(),
        _PasgarDefectRow(
          label: 'Reflexes',
          value: avg.reflexesPct,
          reference: refs['pasgar_reflexes'],
        ),
        _PasgarDefectRow(
          label: 'Beak',
          value: avg.beakPct,
          reference: refs['pasgar_beak'],
        ),
        _PasgarDefectRow(
          label: 'Navel',
          value: avg.navelPct,
          reference: refs['pasgar_navel'],
        ),
        _PasgarDefectRow(
          label: 'Belly',
          value: avg.bellyPct,
          reference: refs['pasgar_belly'],
        ),
        _PasgarDefectRow(
          label: 'Leg',
          value: avg.legPct,
          reference: refs['pasgar_leg'],
        ),
        _PasgarDefectRow(
          label: 'Feather Development',
          value: avg.featherDevPct,
          reference: refs['pasgar_feather_dev'],
        ),
      ],
    );
  }
}

Color _pasgarScoreColor(double score) {
  final interpretation = PasgarScoreInterpretation.fromScore(score);
  return switch (interpretation.band) {
    PasgarInterpretationBand.excellent => AppColors.statusGood,
    PasgarInterpretationBand.acceptable => AppColors.statusWarning,
    PasgarInterpretationBand.investigate => AppColors.statusError,
  };
}

class _PasgarInterpretationCard extends StatelessWidget {
  final double score;
  final TroubleshootingModel? reference;

  const _PasgarInterpretationCard({required this.score, this.reference});

  @override
  Widget build(BuildContext context) {
    final interpretation = PasgarScoreInterpretation.fromScore(score);
    final color = _pasgarScoreColor(score);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            interpretation.label,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(interpretation.message, style: AppTextStyles.caption),
          if (reference != null && reference!.sourceRefs.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _sourceLabels(reference!),
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PasgarDefectRow extends StatelessWidget {
  final String label;
  final double value;
  final TroubleshootingModel? reference;

  const _PasgarDefectRow({
    required this.label,
    required this.value,
    this.reference,
  });

  @override
  Widget build(BuildContext context) {
    final isAlert = value > AppThresholds.pasgarAlertPct;
    final color = isAlert ? AppColors.statusError : AppColors.statusGood;
    final causes = reference?.hatcheryCauses.take(2).toList() ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: AppTextStyles.body)),
                Text(
                  '${value.toStringAsFixed(1)}%',
                  style: AppTextStyles.badgeLabel,
                ),
                const SizedBox(width: 8),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            if (isAlert && causes.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...causes.map((cause) {
                return Text('- $cause', style: AppTextStyles.caption);
              }),
            ],
            if (reference != null && reference!.sourceRefs.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _sourceLabels(reference!),
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _sourceLabels(TroubleshootingModel reference) {
  final labels = reference.sourceRefs
      .map((source) => source['label'] ?? source['publisher'] ?? '')
      .where((label) => label.isNotEmpty)
      .toList();
  if (labels.isEmpty) return '';
  return 'Ref: ${labels.join(', ')}';
}

class _CvtTab extends StatelessWidget {
  final DashboardProvider provider;
  const _CvtTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final avg = provider.cvtAvg;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (avg == null) return _emptySection('CVT');

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricRow(
          'Avg Temp (°F)',
          avg.avgTempF.toStringAsFixed(1),
          color: _thresholdRange(
            avg.avgTempF,
            AppThresholds.cvtMin,
            AppThresholds.cvtMax,
          ),
        ),
        _metricRow(
          'CV%',
          '${avg.cvPct.toStringAsFixed(1)}%',
          color: _threshold(
            avg.cvPct,
            AppThresholds.cvAlertPct,
            lowerIsBetter: true,
          ),
        ),
        _photoSection(context, provider.cvtPhotos),
      ],
    );
  }
}

class _YfbmTab extends StatelessWidget {
  final DashboardProvider provider;
  const _YfbmTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final trend = provider.yfbmTrend;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (trend.isEmpty) return _emptySection('YFBM');

    final spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.avgPct))
        .toList();
    final latest = trend.last;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricRow(
          'Latest Avg%',
          '${latest.avgPct.toStringAsFixed(1)}%',
          color: _thresholdRange(
            latest.avgPct,
            AppThresholds.yfbmMin,
            AppThresholds.yfbmMax,
          ),
        ),
        _metricRow(
          'Target Band',
          '${AppThresholds.yfbmMin.toStringAsFixed(0)}-${AppThresholds.yfbmMax.toStringAsFixed(0)}%',
        ),
        _metricRow('Latest CV%', '${latest.cvPct.toStringAsFixed(1)}%'),
        _sectionHeader(context, 'YFBM Avg%'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 130,
            child: BmkLineChart(
              dataPoints: spots,
              bmkValue: (AppThresholds.yfbmMin + AppThresholds.yfbmMax) / 2,
              yLabel: '%',
            ),
          ),
        ),
        _photoSection(context, provider.yfbmPhotos),
      ],
    );
  }
}

class _CulledChicksTab extends StatelessWidget {
  final DashboardProvider provider;

  const _CulledChicksTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final summary = provider.culledChicksAnalysis;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (summary == null) return _emptySection('culled chicks analysis');

    final topDefect = summary.topDefect;
    final statusColor = summary.needsReview
        ? AppColors.statusWarning
        : AppColors.statusGood;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _sectionHeader(context, 'Culled Chicks Analysis'),
        _metricRow(
          'Status',
          summary.needsReview ? 'Review' : 'Clear',
          color: statusColor,
        ),
        _metricRow('Egg set', summary.totalEggSet.toString()),
        _metricRow('Affected', '${summary.affectedPct.toStringAsFixed(3)}%'),
        if (topDefect != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topDefect.subtype,
                    style: AppTextStyles.body.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${summary.topCategory ?? topDefect.category} - ${topDefect.description}',
                    style: AppTextStyles.caption,
                  ),
                  if (summary.hasDominantCategory) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${summary.topCategory} dominates the recorded defect mix.',
                      style: AppTextStyles.caption,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'Likely causes: ${topDefect.commonCauses.join(', ')}',
                    style: AppTextStyles.caption,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ref: ${topDefect.sources.map((source) => source.label).join(', ')}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Egg ─────────────────────────────────────────────────────────────

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
            child: _emptySection('egg storage'),
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
                onPhotoTap: (path) => _openPhoto(context, path),
              ),
              const SizedBox(height: AppSizes.spaceMd),
              _EggInfoRowCard(
                title: 'Upside Down Egg',
                values: [
                  _EggInfoValue(
                    label: 'Count',
                    value: '${latest?.upsideDownCount ?? 0} eggs',
                  ),
                  _EggInfoValue(
                    label: 'Rate',
                    value: '${_one(latest?.upsideDownPct ?? 0)}%',
                  ),
                  const _EggInfoValue(label: 'Status', value: 'Recorded'),
                ],
              ),
              const SizedBox(height: AppSizes.spaceMd),
              _EggInfoRowCard(
                title: 'Storage Info',
                values: [
                  _EggInfoValue(
                    label: 'Storage',
                    value: latest?.storageDays == null
                        ? '--'
                        : '${latest!.storageDays} days',
                  ),
                  _EggInfoValue(
                    label: 'Turning',
                    value: _turningLabel(latest?.turningTimes),
                  ),
                  _EggInfoValue(
                    label: 'Tray spacing',
                    value: _text(latest?.traySpacing),
                  ),
                  _EggInfoValue(
                    label: 'Cooler',
                    value: _text(latest?.coolerProximity),
                  ),
                  _EggInfoValue(
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
                _emptySection('egg quality')
              else ...[
                _EggWeightsQualityCard(latest: latest),
                const SizedBox(height: AppSizes.spaceMd),
                _EggUvQualityCard(
                  latest: latest,
                  photos: provider.uvPhotos,
                  onPhotoTap: (path) => _openPhoto(context, path),
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

    return _EggDashboardPanel(
      title: 'Egg Weights & Uniformity',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = _QualitySummaryCard(
            metrics: [
              _QualitySummaryMetric(
                label: 'Average',
                value: latest.avgWeightG == 0
                    ? '--'
                    : '${_one(latest.avgWeightG)}g',
                note: 'Egg weight',
              ),
              _QualitySummaryMetric(
                label: 'Uniformity',
                value: latest.uniformityPct == 0
                    ? '--'
                    : '${_one(latest.uniformityPct)}%',
                note:
                    'Target >= ${AppThresholds.uniformityGood.toStringAsFixed(1)}%',
                isAlarm: uniformityIsAlarm,
              ),
              _QualitySummaryMetric(
                label: 'C.V',
                value: latest.cvPct == 0 ? '--' : '${_one(latest.cvPct)}%',
                note:
                    'Limit <= ${AppThresholds.cvAlertPct.toStringAsFixed(1)}%',
                isAlarm: cvIsAlarm,
              ),
            ],
            alarmMessage: hasAlarm
                ? _weightAlarmMessage(cvIsAlarm, uniformityIsAlarm)
                : null,
          );
          final details = _EggInfoValueGrid(
            values: [
              _EggInfoValue(
                label: 'Sample Size',
                value: latest.eggSampleSize == 0
                    ? '--'
                    : '${latest.eggSampleSize}/100',
              ),
              _EggInfoValue(
                label: 'BMK Egg Weight',
                value: latest.eggBmkWeight == 0
                    ? '--'
                    : '${_one(latest.eggBmkWeight)}g',
              ),
              _EggInfoValue(
                label: 'Low Margin',
                value: lowMargin == 0 ? '--' : '${_one(lowMargin)}g',
              ),
              _EggInfoValue(
                label: 'High Margin',
                value: highMargin == 0 ? '--' : '${_one(highMargin)}g',
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
    return _EggDashboardPanel(
      title: 'Shell Quality UV',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = _QualitySummaryCard(
            metrics: [
              _QualitySummaryMetric(
                label: 'Affected',
                value: '${_one(latest.uvAffectedPct)}%',
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
              _EggInfoValueGrid(
                values: [
                  _EggInfoValue(
                    label: 'Cuticle Damage',
                    value: '${_one(latest.uvCuticleDamagePct)}%',
                  ),
                  _EggInfoValue(
                    label: 'Washed',
                    value: '${_one(latest.uvWashedPct)}%',
                  ),
                  _EggInfoValue(
                    label: 'Dirty',
                    value: '${_one(latest.uvDirtyPct)}%',
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
                        child: _EstSummaryMetric(
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
                  _EstSummaryMetric(
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
    final avg = latest?.estAvgF != 0 ? latest?.estAvgF : latest?.shellTempC;
    final cv = latest?.estCvPct;
    final temperatureStatus = _EstTemperatureStatus.from(avg, target);
    final cvIsAlarm = cv != null && cv > AppThresholds.cvAlertPct;
    return _EggDashboardPanel(
      title: 'Temperature Readings (°C)',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = _EstSummaryCard(
            avg: avg,
            target: target,
            cv: cv,
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
  final _EstTemperatureStatus temperatureStatus;
  final bool cvIsAlarm;

  const _EstSummaryCard({
    required this.avg,
    required this.target,
    required this.cv,
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
                      child: _EstSummaryMetric(
                        label: 'Average',
                        value: avg == null || avg == 0
                            ? '--'
                            : '${_one(avg!)}°C',
                        note: temperatureStatus.label,
                        isAlarm: temperatureStatus.isAlarm,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: AppSizes.spaceSm),
                    Expanded(
                      child: _EstSummaryMetric(
                        label: 'Target',
                        value: target.rangeLabel,
                        note: target.label,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: AppSizes.spaceSm),
                    Expanded(
                      child: _EstSummaryMetric(
                        label: 'CV%',
                        value: cv == null ? '--' : '${_one(cv!)}%',
                        note:
                            'Limit <= ${AppThresholds.cvAlertPct.toStringAsFixed(1)}%',
                        isAlarm: cvIsAlarm,
                        compact: true,
                      ),
                    ),
                  ],
                )
              else ...[
                _EstSummaryMetric(
                  label: 'Average',
                  value: avg == null || avg == 0 ? '--' : '${_one(avg!)}°C',
                  note: temperatureStatus.label,
                  isAlarm: temperatureStatus.isAlarm,
                ),
                const SizedBox(height: AppSizes.spaceLg),
                _EstSummaryMetric(
                  label: 'Target',
                  value: target.rangeLabel,
                  note: target.label,
                ),
                const SizedBox(height: AppSizes.spaceLg),
                _EstSummaryMetric(
                  label: 'CV%',
                  value: cv == null ? '--' : '${_one(cv!)}%',
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

class _EstSummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final bool isAlarm;
  final bool compact;

  const _EstSummaryMetric({
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
    final hasPhoto =
        path != null && path.trim().isNotEmpty && File(path).existsSync();
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
              point.readingC == null ? '--' : '${_one(point.readingC!)}°C',
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
            onTap: hasPhoto ? () => onPhotoTap(path) : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: compact ? 34 : 46,
                width: double.infinity,
                child: hasPhoto
                    ? Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        cacheWidth: 220,
                        errorBuilder: (context, error, stackTrace) =>
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

class _EggInfoValue {
  final String label;
  final String value;

  const _EggInfoValue({required this.label, required this.value});
}

class _EggInfoRowCard extends StatelessWidget {
  final String title;
  final List<_EggInfoValue> values;

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
          final valueGrid = _EggInfoValueGrid(values: values);
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

class _EggInfoValueGrid extends StatelessWidget {
  final List<_EggInfoValue> values;

  const _EggInfoValueGrid({required this.values});

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

class _EggDashboardPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const _EggDashboardPanel({required this.title, required this.child});

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

void _openPhoto(BuildContext context, String path) {
  Navigator.push(
    context,
    AppPageRoute(builder: (_) => PhotoFullscreenScreen(filePath: path)),
  );
}

String _one(double value) => value.toStringAsFixed(1);

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
    if (latest == null) return _emptySection('egg storage');

    final spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.uniformityPct))
        .toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricRow('Avg Weight', '${latest.avgWeightG.toStringAsFixed(1)} g'),
        _metricRow('Uniformity', '${latest.uniformityPct.toStringAsFixed(1)}%'),
        _metricRow(
          'CV%',
          '${latest.cvPct.toStringAsFixed(1)}%',
          color: _threshold(
            latest.cvPct,
            AppThresholds.cvAlertPct,
            lowerIsBetter: true,
          ),
        ),
        _metricRow(
          'EST Avg (°F)',
          latest.estAvgF.toStringAsFixed(1),
          color: latest.estAvgF > 0
              ? _thresholdRange(
                  latest.estAvgF,
                  AppThresholds.estMin,
                  AppThresholds.estMax,
                )
              : null,
        ),
        _metricRow(
          'EST CV%',
          '${latest.estCvPct.toStringAsFixed(1)}%',
          color: latest.estCvPct > 0
              ? _threshold(
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
class _ShellTempTab extends StatelessWidget {
  final DashboardProvider provider;
  const _ShellTempTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final trend = provider.eggStorageTrend;
    final latest = provider.eggStorageLatest;
    final evidence = provider.eggStorageEstEvidence;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (latest == null) return _emptySection('shell temperature');

    final spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.shellTempC))
        .toList();

    final metrics = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metricRow(
          'Shell Temp (°C)',
          latest.shellTempC.toStringAsFixed(1),
          color: _thresholdRange(
            latest.shellTempC,
            AppThresholds.shellTempMin,
            AppThresholds.shellTempMax,
          ),
        ),
        _metricRow(
          'Target Band',
          '${AppThresholds.shellTempMin.toStringAsFixed(0)}-${AppThresholds.shellTempMax.toStringAsFixed(0)}°C',
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 150,
            child: BmkLineChart(
              dataPoints: spots.isEmpty
                  ? [FlSpot(0, latest.shellTempC)]
                  : spots,
              bmkValue:
                  (AppThresholds.shellTempMin + AppThresholds.shellTempMax) / 2,
              yLabel: '°C',
            ),
          ),
        ),
      ],
    );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (evidence == null) ...[
          metrics,
          _photoSection(context, provider.shellTempPhotos),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 720) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: metrics),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 340,
                        child: EstEvidencePhotosCard(
                          evidence: evidence,
                          onPhotoTap: (path) => Navigator.push(
                            context,
                            AppPageRoute(
                              builder: (_) =>
                                  PhotoFullscreenScreen(filePath: path),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    metrics,
                    const SizedBox(height: 12),
                    EstEvidencePhotosCard(
                      evidence: evidence,
                      onPhotoTap: (path) => Navigator.push(
                        context,
                        AppPageRoute(
                          builder: (_) => PhotoFullscreenScreen(filePath: path),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
    if (latest == null) return _emptySection('UV');

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricRow(
          'UV Affected',
          '${latest.uvAffectedPct.toStringAsFixed(1)}%',
          color: _threshold(latest.uvAffectedPct, 5, lowerIsBetter: true),
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
        _photoSection(context, provider.uvPhotos),
      ],
    );
  }
}

// ─── Setters ───────────────────────────────────────────────────────

class SetterOptimizingSection extends StatelessWidget {
  const SetterOptimizingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final hasData = provider.setterComparisons.isNotEmpty;
        return Card(
          child: ExpansionTile(
            title: const Text('Setters'),
            initiallyExpanded: true,
            children: [
              if (provider.availableSetterIds.isEmpty)
                _emptySection('setter optimizing')
              else ...[
                _buildCheckboxes(context, provider),
                if (hasData) ...[
                  _buildComparisonTable(context, provider),
                  _buildTurningAngleRow(context, provider),
                  const Divider(),
                  _buildEstChart(context, provider),
                  const Divider(),
                  _buildCo2Chart(context, provider),
                ] else
                  _emptySection('setter optimizing'),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCheckboxes(BuildContext context, DashboardProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: provider.availableSetterIds.map((id) {
          final selected = provider.selectedSetterIds.contains(id);
          return FilterChip(
            label: Text('Setter $id'),
            selected: selected,
            onSelected: (_) => provider.toggleSetter(id),
            selectedColor: AppColors.primary.withAlpha(60),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTurningAngleRow(
    BuildContext context,
    DashboardProvider provider,
  ) {
    final comparisons = provider.setterComparisons;
    final hasTurning = comparisons.any((c) => c.turningAngle > 0);
    if (!hasTurning) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text('Turning Angle', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          ...comparisons
              .where((c) => c.turningAngle > 0)
              .map(
                (c) => _metricRow(
                  'Setter ${c.setterId}',
                  '${c.turningAngle.toStringAsFixed(1)}°',
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildComparisonTable(
    BuildContext context,
    DashboardProvider provider,
  ) {
    final comparisons = provider.setterComparisons;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DataTable(
        columnSpacing: 16,
        columns: [
          const DataColumn(label: Text('Setter')),
          const DataColumn(label: Text('Hatch%')),
          const DataColumn(label: Text('Fert%')),
          const DataColumn(label: Text('HOF%')),
          const DataColumn(label: Text('EST°F')),
          const DataColumn(label: Text('EST CV%')),
        ],
        rows: comparisons
            .map(
              (c) => DataRow(
                cells: [
                  DataCell(Text(c.setterId)),
                  DataCell(Text(c.hatchabilityPct.toStringAsFixed(1))),
                  DataCell(Text(c.fertilityPct.toStringAsFixed(1))),
                  DataCell(Text(c.hofPct.toStringAsFixed(1))),
                  DataCell(Text(c.estAvgF.toStringAsFixed(1))),
                  DataCell(Text(c.estCvPct.toStringAsFixed(1))),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildEstChart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.setterComparisons;
    if (comparisons.isEmpty) return const SizedBox.shrink();

    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'EST Comparison',
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );

    final groups = comparisons
        .asMap()
        .entries
        .map((e) => BmkBarChart.createGroup(e.key, e.value.estAvgF))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EST (°F)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Target: ${AppThresholds.estMin.toStringAsFixed(0)}-${AppThresholds.estMax.toStringAsFixed(0)}°F',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: BmkBarChart(
              barGroups: groups,
              bmkValue: (AppThresholds.estMin + AppThresholds.estMax) / 2,
              xLabel: '',
              xLabels: comparisons.map((c) => 'S${c.setterId}').toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCo2Chart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.setterComparisons;
    final colors = [
      AppColors.primary,
      AppColors.statusError,
      AppColors.statusGood,
      AppColors.primaryLight,
    ];

    final lineBars = comparisons.asMap().entries.map((entry) {
      final c = entry.value;
      final color = colors[entry.key % colors.length];
      final spots = c.co2Trend.entries
          .toList()
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value.value))
          .toList();
      return LineChartBarData(
        spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
        color: color,
        barWidth: 2,
        isCurved: true,
        dotData: const FlDotData(show: false),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CO₂ Trend (ppm)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: lineBars.isEmpty
                ? const Center(child: Text('No CO₂ data'))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => const FlLine(
                          color: AppColors.chartGridH,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: lineBars,
                    ),
                  ),
          ),
          _buildLegend(
            comparisons
                .asMap()
                .entries
                .map(
                  (e) => MapEntry(
                    'Setter ${e.value.setterId}',
                    colors[e.key % colors.length],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(List<MapEntry<String, Color>> items) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 12,
        children: items
            .map(
              (e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 3, color: e.value),
                  const SizedBox(width: 4),
                  Text(e.key, style: const TextStyle(fontSize: 12)),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

// ─── Hatchers ──────────────────────────────────────────────────────

class HatcherOptimizingSection extends StatelessWidget {
  const HatcherOptimizingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final hasData = provider.hatcherComparisons.isNotEmpty;
        return Card(
          child: ExpansionTile(
            title: const Text('Hatchers'),
            initiallyExpanded: true,
            children: [
              if (provider.availableHatcherIds.isEmpty)
                _emptySection('hatcher optimizing')
              else ...[
                _buildCheckboxes(context, provider),
                if (hasData) ...[
                  _buildComparisonTable(context, provider),
                  const Divider(),
                  _buildCvtChart(context, provider),
                  const Divider(),
                  _buildCo2Chart(context, provider),
                  const Divider(),
                  _buildPantingChart(context, provider),
                ] else
                  _emptySection('hatcher optimizing'),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCheckboxes(BuildContext context, DashboardProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: provider.availableHatcherIds.map((id) {
          final selected = provider.selectedHatcherIds.contains(id);
          return FilterChip(
            label: Text('Hatcher $id'),
            selected: selected,
            onSelected: (_) => provider.toggleHatcher(id),
            selectedColor: AppColors.primary.withAlpha(60),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildComparisonTable(
    BuildContext context,
    DashboardProvider provider,
  ) {
    final comparisons = provider.hatcherComparisons;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DataTable(
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('Hatcher')),
          DataColumn(label: Text('Hatch%')),
          DataColumn(label: Text('HOF%')),
          DataColumn(label: Text('Culled%')),
          DataColumn(label: Text('CVT°F')),
          DataColumn(label: Text('CVT CV%')),
          DataColumn(label: Text('Meconium')),
          DataColumn(label: Text('Trans. Day')),
        ],
        rows: comparisons
            .map(
              (c) => DataRow(
                cells: [
                  DataCell(Text(c.hatcherId)),
                  DataCell(Text(c.hatchabilityPct.toStringAsFixed(1))),
                  DataCell(Text(c.hofPct.toStringAsFixed(1))),
                  DataCell(Text(c.culledPct.toStringAsFixed(1))),
                  DataCell(Text(c.cvtAvgF.toStringAsFixed(1))),
                  DataCell(Text(c.cvtCvPct.toStringAsFixed(1))),
                  DataCell(Text(c.meconium ?? '--')),
                  DataCell(Text(c.transferDay?.toString() ?? '--')),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCvtChart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.hatcherComparisons;
    final colors = [
      AppColors.primary,
      AppColors.statusError,
      AppColors.statusGood,
      AppColors.primaryLight,
    ];

    final groups = comparisons
        .asMap()
        .entries
        .map((e) => BmkBarChart.createGroup(e.key, e.value.cvtAvgF))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CVT Avg (°F)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Target: ${AppThresholds.cvtMin.toStringAsFixed(0)}-${AppThresholds.cvtMax.toStringAsFixed(0)}°F',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: BmkBarChart(
              barGroups: groups,
              bmkValue: (AppThresholds.cvtMin + AppThresholds.cvtMax) / 2,
              xLabel: '',
              xLabels: comparisons.map((c) => 'H${c.hatcherId}').toList(),
            ),
          ),
          _buildLegend(
            comparisons
                .asMap()
                .entries
                .map(
                  (e) => MapEntry(
                    'Hatcher ${e.value.hatcherId}',
                    colors[e.key % colors.length],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCo2Chart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.hatcherComparisons;
    final colors = [
      AppColors.primary,
      AppColors.statusError,
      AppColors.statusGood,
      AppColors.primaryLight,
    ];

    final lineBars = comparisons.asMap().entries.map((entry) {
      final c = entry.value;
      final color = colors[entry.key % colors.length];
      final spots = c.co2Trend.entries
          .toList()
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value.value))
          .toList();
      return LineChartBarData(
        spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
        color: color,
        barWidth: 2,
        isCurved: true,
        dotData: const FlDotData(show: false),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CO₂ Trend (ppm)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: lineBars.isEmpty
                ? const Center(child: Text('No CO₂ data'))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => const FlLine(
                          color: AppColors.chartGridH,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: lineBars,
                    ),
                  ),
          ),
          _buildLegend(
            comparisons
                .asMap()
                .entries
                .map(
                  (e) => MapEntry(
                    'Hatcher ${e.value.hatcherId}',
                    colors[e.key % colors.length],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPantingChart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.hatcherComparisons;
    final colors = [
      AppColors.primary,
      AppColors.statusError,
      AppColors.statusGood,
      AppColors.primaryLight,
    ];

    final lineBars = comparisons.asMap().entries.map((entry) {
      final c = entry.value;
      final color = colors[entry.key % colors.length];
      final spots = c.pantingTrend.entries
          .toList()
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value.value))
          .toList();
      return LineChartBarData(
        spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
        color: color,
        barWidth: 2,
        isCurved: true,
        dotData: const FlDotData(show: false),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chick Panting Trend',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: lineBars.isEmpty
                ? const Center(child: Text('No panting data'))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => const FlLine(
                          color: AppColors.chartGridH,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: lineBars,
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: 20,
                            color: Colors.orange,
                            strokeWidth: 1,
                            dashArray: [5, 5],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          _buildLegend(
            comparisons
                .asMap()
                .entries
                .map(
                  (e) => MapEntry(
                    'Hatcher ${e.value.hatcherId}',
                    colors[e.key % colors.length],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(List<MapEntry<String, Color>> items) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 12,
        children: items
            .map(
              (e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 3, color: e.value),
                  const SizedBox(width: 4),
                  Text(e.key, style: const TextStyle(fontSize: 12)),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}
