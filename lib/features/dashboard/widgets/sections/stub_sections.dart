import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/constants/app_thresholds.dart';
import 'package:hatchaudit/core/theme/app_page_route.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_line_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_bar_chart.dart';
import 'package:hatchaudit/widgets/photo_grid.dart';
import 'package:hatchaudit/features/dashboard/screens/photo_fullscreen_screen.dart';

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
      const Icon(Icons.bar_chart_outlined, size: 48, color: AppColors.textDisabled),
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
          AppPageRoute(
            builder: (_) => PhotoFullscreenScreen(filePath: path),
          ),
        ),
      ),
    ],
  );
}

// ─── Chick Quality ───────────────────────────────────────────────────────────

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
            title: const Text('Chick Quality'),
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
                  Tab(text: 'CHA Env'),
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
                    _ChaTab(provider: provider),
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
        _metricRow(
          'Uniformity',
          '${latest.uniformityPct.toStringAsFixed(1)}%',
        ),
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

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricRow(
          'Reflexes',
          '${avg.reflexesPct.toStringAsFixed(1)}%',
          color: _threshold(avg.reflexesPct, AppThresholds.pasgarAlertPct),
        ),
        _metricRow(
          'Beak',
          '${avg.beakPct.toStringAsFixed(1)}%',
          color: _threshold(avg.beakPct, AppThresholds.pasgarAlertPct),
        ),
        _metricRow(
          'Navel',
          '${avg.navelPct.toStringAsFixed(1)}%',
          color: _threshold(avg.navelPct, AppThresholds.pasgarAlertPct),
        ),
        _metricRow(
          'Belly',
          '${avg.bellyPct.toStringAsFixed(1)}%',
          color: _threshold(avg.bellyPct, AppThresholds.pasgarAlertPct),
        ),
        _metricRow(
          'Leg',
          '${avg.legPct.toStringAsFixed(1)}%',
          color: _threshold(avg.legPct, AppThresholds.pasgarAlertPct),
        ),
        _metricRow(
          'Feather Development',
          '${avg.featherDevPct.toStringAsFixed(1)}%',
          color: _threshold(avg.featherDevPct, AppThresholds.pasgarAlertPct),
        ),
        const Divider(),
        _metricRow(
          'Final Score',
          avg.score.toStringAsFixed(1),
          color: _threshold(avg.score * 10, AppThresholds.pasgarAlertPct),
        ),
      ],
    );
  }
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

class _ChaTab extends StatelessWidget {
  final DashboardProvider provider;
  const _ChaTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final trend = provider.chaTrend;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (trend.isEmpty) return _emptySection('CHA environmental');

    final latest = trend.last;
    final co2Spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.co2))
        .toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _sectionHeader(context, 'CO₂ (ppm)'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 100,
            child: BmkLineChart(
              dataPoints: co2Spots,
              bmkValue: 3000,
              yLabel: 'ppm',
            ),
          ),
        ),
        const Divider(),
        _metricRow('Latest PM10', latest.pm10.toStringAsFixed(1)),
        _metricRow('Latest PM2.5', latest.pm25.toStringAsFixed(1)),
        _metricRow('Air Velocity Avg', latest.airVelocity.toStringAsFixed(2)),
        _metricRow('Noise', latest.noiseLevel.toStringAsFixed(1)),
        _photoSection(context, provider.chaPhotos),
      ],
    );
  }
}

// ─── Egg Storage ─────────────────────────────────────────────────────────────

class EggStorageSection extends StatefulWidget {
  const EggStorageSection({super.key});

  @override
  State<EggStorageSection> createState() => _EggStorageSectionState();
}

class _EggStorageSectionState extends State<EggStorageSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
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
            title: const Text('Egg Storage'),
            initiallyExpanded: true,
            children: [
              TabBar(
                controller: _tab,
                tabs: const [
                  Tab(text: 'Uniformity'),
                  Tab(text: 'Shell Temp'),
                  Tab(text: 'UV'),
                  Tab(text: 'CO₂'),
                ],
              ),
              SizedBox(
                height: 320,
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _EggUniformityTab(provider: provider),
                    _ShellTempTab(provider: provider),
                    _UvTab(provider: provider),
                    _Co2Tab(provider: provider),
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

class _ShellTempTab extends StatelessWidget {
  final DashboardProvider provider;
  const _ShellTempTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final trend = provider.eggStorageTrend;
    final latest = provider.eggStorageLatest;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (latest == null) return _emptySection('shell temperature');

    final spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.shellTempC))
        .toList();

    return ListView(
      padding: EdgeInsets.zero,
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
        _photoSection(context, provider.shellTempPhotos),
      ],
    );
  }
}

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

class _Co2Tab extends StatelessWidget {
  final DashboardProvider provider;
  const _Co2Tab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final trend = provider.eggStorageTrend;
    final latest = provider.eggStorageLatest;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (latest == null) return _emptySection('CO₂');

    final spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.co2))
        .toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricRow(
          'CO₂ (ppm)',
          latest.co2.toStringAsFixed(0),
          color: latest.co2 > 0
              ? _threshold(latest.co2, AppThresholds.co2Max, lowerIsBetter: true)
              : null,
        ),
        _metricRow(
          'Target',
          '< ${AppThresholds.co2Max.toStringAsFixed(0)} ppm',
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 150,
            child: BmkLineChart(
              dataPoints: spots.isEmpty ? [FlSpot(0, latest.co2)] : spots,
              bmkValue: AppThresholds.co2Max,
              yLabel: 'ppm',
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Setter Optimizing ───────────────────────────────────────────────────────

class SetterOptimizingSection extends StatelessWidget {
  const SetterOptimizingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final hasData = provider.setterComparisons.isNotEmpty;
        return Card(
          child: ExpansionTile(
            title: const Text('Setter Optimizing'),
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
          Text(
            'Turning Angle',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          ...comparisons
              .where((c) => c.turningAngle > 0)
              .map((c) => _metricRow(
                    'Setter ${c.setterId}',
                    '${c.turningAngle.toStringAsFixed(1)}°',
                  )),
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
                        getDrawingHorizontalLine: (v) =>
                            const FlLine(
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

// ─── Hatcher Optimizing ──────────────────────────────────────────────────────

class HatcherOptimizingSection extends StatelessWidget {
  const HatcherOptimizingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final hasData = provider.hatcherComparisons.isNotEmpty;
        return Card(
          child: ExpansionTile(
            title: const Text('Hatcher Optimizing'),
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
                        getDrawingHorizontalLine: (v) =>
                            const FlLine(
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
                        getDrawingHorizontalLine: (v) =>
                            const FlLine(
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
