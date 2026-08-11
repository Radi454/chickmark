import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_thresholds.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/data/models/troubleshooting_model.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/utils/pasgar_interpretation.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_line_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/section_shared.dart';

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
                tabs: [
                  Tab(text: context.tr('Weights')),
                  Tab(text: context.tr('Pasgar')),
                  Tab(text: context.tr('CVT')),
                  Tab(text: context.tr('YFBM')),
                  Tab(text: context.tr('Culled')),
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
      return emptySection('weights');
    }
    final spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.avgWeightG))
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
    if (avg == null) return emptySection('Pasgar');
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
        metricRow(
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
    if (avg == null) return emptySection('CVT');

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        metricRow(
          'Avg Temp (°F)',
          avg.avgTempF.toStringAsFixed(1),
          color: thresholdRange(
            avg.avgTempF,
            AppThresholds.cvtMin,
            AppThresholds.cvtMax,
          ),
        ),
        metricRow(
          'CV%',
          '${avg.cvPct.toStringAsFixed(1)}%',
          color: threshold(
            avg.cvPct,
            AppThresholds.cvAlertPct,
            lowerIsBetter: true,
          ),
        ),
        photoSection(context, provider.cvtPhotos),
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
    if (trend.isEmpty) return emptySection('YFBM');

    final spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.avgPct))
        .toList();
    final latest = trend.last;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        metricRow(
          'Latest Avg%',
          '${latest.avgPct.toStringAsFixed(1)}%',
          color: thresholdRange(
            latest.avgPct,
            AppThresholds.yfbmMin,
            AppThresholds.yfbmMax,
          ),
        ),
        metricRow(
          'Target Band',
          '${AppThresholds.yfbmMin.toStringAsFixed(0)}-${AppThresholds.yfbmMax.toStringAsFixed(0)}%',
        ),
        metricRow('Latest CV%', '${latest.cvPct.toStringAsFixed(1)}%'),
        sectionHeader(context, 'YFBM Avg%'),
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
        photoSection(context, provider.yfbmPhotos),
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
    if (summary == null) return emptySection('culled chicks analysis');

    final topDefect = summary.topDefect;
    final statusColor = summary.needsReview
        ? AppColors.statusWarning
        : AppColors.statusGood;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        sectionHeader(context, 'Culled Chicks Analysis'),
        metricRow(
          'Status',
          summary.needsReview ? 'Review' : 'Clear',
          color: statusColor,
        ),
        metricRow('Egg set', summary.totalEggSet.toString()),
        metricRow('Affected', '${summary.affectedPct.toStringAsFixed(3)}%'),
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
