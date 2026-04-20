import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_line_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_bar_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/bmk_donut_chart.dart';
import 'package:hatchaudit/widgets/photo_grid.dart';
import 'package:hatchaudit/features/dashboard/screens/photo_fullscreen_screen.dart';

// ─── helpers ────────────────────────────────────────────────────────────────

Widget _sectionHeader(BuildContext context, String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );

Widget _metricRow(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (color != null) ...[
            const SizedBox(width: 8),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );

Color _threshold(double value, double good, {bool lowerIsBetter = false}) {
  if (good == 0) return Colors.grey;
  return lowerIsBetter
      ? (value <= good ? const Color(0xFF3a9a5c) : const Color(0xFFE24B4A))
      : (value >= good ? const Color(0xFF3a9a5c) : const Color(0xFFE24B4A));
}

Widget _photoSection(
  BuildContext context,
  List<String> photos,
) {
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
          MaterialPageRoute(
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
    final bmk = provider.bmkReference;
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (trend == null) {
      return const Center(child: Text('No data'));
    }
    final bmkWeight = bmk?.chickWeightG ?? 0;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricRow(
          'Avg Weight',
          '${trend.avgWeightG.toStringAsFixed(1)} g',
          color: _threshold(trend.avgWeightG, bmkWeight),
        ),
        if (bmkWeight > 0)
          _metricRow('BMK Weight', '${bmkWeight.toStringAsFixed(1)} g'),
        _metricRow('Uniformity', '${trend.uniformityPct.toStringAsFixed(1)}%'),
        _metricRow('CV%', '${trend.cvPct.toStringAsFixed(1)}%'),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 160,
            child: BmkLineChart(
              dataPoints: [FlSpot(0, trend.avgWeightG)],
              bmkValue: bmkWeight,
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
    if (provider.isLoading) return const Center(child: CircularProgressIndicator());
    if (avg == null) return const Center(child: Text('No data'));

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 140,
            child: Row(
              children: [
                Expanded(
                  child: BmkDonutChart(actualPct: avg.score * 10, bmkPct: 90),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        avg.score.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 36, fontWeight: FontWeight.bold),
                      ),
                      const Text('/ 10', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 140,
            child: BmkBarChart(
              barGroups: [
                BmkBarChart.createGroup(0, avg.reflexesPct),
                BmkBarChart.createGroup(1, avg.beakPct),
                BmkBarChart.createGroup(2, avg.navelPct),
                BmkBarChart.createGroup(3, avg.bellyPct),
                BmkBarChart.createGroup(4, avg.legPct),
                BmkBarChart.createGroup(5, avg.featherDevPct),
              ],
              bmkValue: 90,
              xLabel: '',
              xLabels: const [
                'Refl',
                'Beak',
                'Nav',
                'Bell',
                'Leg',
                'Feath',
              ],
            ),
          ),
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
    if (provider.isLoading) return const Center(child: CircularProgressIndicator());
    if (avg == null) return const Center(child: Text('No data'));

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 140,
            child: BmkDonutChart(
              actualPct: (100 - avg.cvPct).clamp(0, 100),
              bmkPct: 95,
            ),
          ),
        ),
        _metricRow('Avg Temp (°F)', avg.avgTempF.toStringAsFixed(1)),
        _metricRow(
          'CV%',
          '${avg.cvPct.toStringAsFixed(1)}%',
          color: _threshold(avg.cvPct, 5, lowerIsBetter: true),
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
    if (provider.isLoading) return const Center(child: CircularProgressIndicator());
    if (trend.isEmpty) return const Center(child: Text('No data'));

    final spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.avgPct))
        .toList();
    final cvSpots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.cvPct))
        .toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _sectionHeader(context, 'YFBM Avg%'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 130,
            child: BmkLineChart(dataPoints: spots, bmkValue: 0, yLabel: '%'),
          ),
        ),
        _sectionHeader(context, 'CV%'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 100,
            child: BmkLineChart(dataPoints: cvSpots, bmkValue: 5, yLabel: '%'),
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
    if (provider.isLoading) return const Center(child: CircularProgressIndicator());
    if (trend.isEmpty) return const Center(child: Text('No data'));

    final co2Spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.co2))
        .toList();
    final pm10Spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.pm10))
        .toList();
    final velSpots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.airVelocity))
        .toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _sectionHeader(context, 'CO₂ (ppm)'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 100,
            child: BmkLineChart(dataPoints: co2Spots, bmkValue: 3000, yLabel: 'ppm'),
          ),
        ),
        _sectionHeader(context, 'PM10 (µg/m³)'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 100,
            child: BmkLineChart(dataPoints: pm10Spots, bmkValue: 0, yLabel: 'µg'),
          ),
        ),
        _sectionHeader(context, 'Air Velocity (m/s)'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 100,
            child: BmkLineChart(dataPoints: velSpots, bmkValue: 0, yLabel: 'm/s'),
          ),
        ),
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
    _tab = TabController(length: 3, vsync: this);
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
    if (provider.isLoading) return const Center(child: CircularProgressIndicator());
    if (trend == null) return const Center(child: Text('No data'));

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricRow('Avg Weight', '${trend.avgWeightG.toStringAsFixed(1)} g'),
        _metricRow('Uniformity', '${trend.uniformityPct.toStringAsFixed(1)}%'),
        _metricRow('CV%', '${trend.cvPct.toStringAsFixed(1)}%'),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 160,
            child: BmkLineChart(
              dataPoints: [
                FlSpot(0, trend.uniformityPct),
              ],
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
    if (provider.isLoading) return const Center(child: CircularProgressIndicator());
    if (trend == null) return const Center(child: Text('No data'));

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricRow(
          'Shell Temp (°C)',
          trend.shellTempC.toStringAsFixed(1),
          color: _threshold(trend.shellTempC, 18, lowerIsBetter: true),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 150,
            child: BmkLineChart(
              dataPoints: [FlSpot(0, trend.shellTempC)],
              bmkValue: 18,
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
    final trend = provider.eggStorageTrend;
    if (provider.isLoading) return const Center(child: CircularProgressIndicator());
    if (trend == null) return const Center(child: Text('No data'));

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _metricRow(
          'UV Affected',
          '${trend.uvAffectedPct.toStringAsFixed(1)}%',
          color: _threshold(trend.uvAffectedPct, 5, lowerIsBetter: true),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 150,
            child: BmkBarChart(
              barGroups: [BmkBarChart.createGroup(0, trend.uvAffectedPct)],
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

// ─── Setter Optimizing ───────────────────────────────────────────────────────

class SetterOptimizingSection extends StatelessWidget {
  const SetterOptimizingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        return Card(
          child: ExpansionTile(
            title: const Text('Setter Optimizing'),
            initiallyExpanded: true,
            children: [
              if (provider.availableSetterIds.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No setter data available'),
                )
              else ...[
                _buildCheckboxes(context, provider),
                if (provider.setterComparisons.isNotEmpty) ...[
                  _buildComparisonTable(context, provider),
                  const Divider(),
                  _buildEstChart(context, provider),
                  const Divider(),
                  _buildCo2Chart(context, provider),
                ],
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

  Widget _buildComparisonTable(
      BuildContext context, DashboardProvider provider) {
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
              (c) => DataRow(cells: [
                DataCell(Text(c.setterId)),
                DataCell(Text(c.hatchabilityPct.toStringAsFixed(1))),
                DataCell(Text(c.fertilityPct.toStringAsFixed(1))),
                DataCell(Text(c.hofPct.toStringAsFixed(1))),
                DataCell(Text(c.estAvgF.toStringAsFixed(1))),
                DataCell(Text(c.estCvPct.toStringAsFixed(1))),
              ]),
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
      child: Text('EST Comparison',
          style: Theme.of(context).textTheme.titleSmall),
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
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: BmkBarChart(
              barGroups: groups,
              bmkValue: 100,
              xLabel: '',
              xLabels:
                  comparisons.map((c) => 'S${c.setterId}').toList(),
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
      const Color(0xFFE24B4A),
      const Color(0xFF3a9a5c),
      const Color(0xFFF65C00),
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
          Text('CO₂ Trend (ppm)',
              style: Theme.of(context).textTheme.titleSmall),
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
                            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                      ),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true, reservedSize: 40)),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: lineBars,
                    ),
                  ),
          ),
          _buildLegend(comparisons
              .asMap()
              .entries
              .map((e) => MapEntry('Setter ${e.value.setterId}',
                  colors[e.key % colors.length]))
              .toList()),
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
            .map((e) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 3, color: e.value),
                    const SizedBox(width: 4),
                    Text(e.key, style: const TextStyle(fontSize: 12)),
                  ],
                ))
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
        return Card(
          child: ExpansionTile(
            title: const Text('Hatcher Optimizing'),
            initiallyExpanded: true,
            children: [
              if (provider.availableHatcherIds.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No hatcher data available'),
                )
              else ...[
                _buildCheckboxes(context, provider),
                if (provider.hatcherComparisons.isNotEmpty) ...[
                  _buildComparisonTable(context, provider),
                  const Divider(),
                  _buildCvtChart(context, provider),
                  const Divider(),
                  _buildCo2Chart(context, provider),
                  const Divider(),
                  _buildPantingChart(context, provider),
                ],
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
      BuildContext context, DashboardProvider provider) {
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
        ],
        rows: comparisons
            .map(
              (c) => DataRow(cells: [
                DataCell(Text(c.hatcherId)),
                DataCell(Text(c.hatchabilityPct.toStringAsFixed(1))),
                DataCell(Text(c.hofPct.toStringAsFixed(1))),
                DataCell(Text(c.culledPct.toStringAsFixed(1))),
                DataCell(Text(c.cvtAvgF.toStringAsFixed(1))),
                DataCell(Text(c.cvtCvPct.toStringAsFixed(1))),
              ]),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCvtChart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.hatcherComparisons;
    final colors = [
      AppColors.primary,
      const Color(0xFFE24B4A),
      const Color(0xFF3a9a5c),
      const Color(0xFFF65C00),
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
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: BmkBarChart(
              barGroups: groups,
              bmkValue: 100,
              xLabel: '',
              xLabels: comparisons.map((c) => 'H${c.hatcherId}').toList(),
            ),
          ),
          _buildLegend(comparisons
              .asMap()
              .entries
              .map((e) => MapEntry('Hatcher ${e.value.hatcherId}',
                  colors[e.key % colors.length]))
              .toList()),
        ],
      ),
    );
  }


  Widget _buildCo2Chart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.hatcherComparisons;
    final colors = [
      AppColors.primary,
      const Color(0xFFE24B4A),
      const Color(0xFF3a9a5c),
      const Color(0xFFF65C00),
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
          Text('CO₂ Trend (ppm)',
              style: Theme.of(context).textTheme.titleSmall),
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
                            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                      ),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true, reservedSize: 40)),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: lineBars,
                    ),
                  ),
          ),
          _buildLegend(comparisons
              .asMap()
              .entries
              .map((e) => MapEntry('Hatcher ${e.value.hatcherId}',
                  colors[e.key % colors.length]))
              .toList()),
        ],
      ),
    );
  }

  Widget _buildPantingChart(BuildContext context, DashboardProvider provider) {
    final comparisons = provider.hatcherComparisons;
    final colors = [
      AppColors.primary,
      const Color(0xFFE24B4A),
      const Color(0xFF3a9a5c),
      const Color(0xFFF65C00),
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
          Text('Chick Panting Trend',
              style: Theme.of(context).textTheme.titleSmall),
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
                            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                      ),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true, reservedSize: 40)),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
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
          _buildLegend(comparisons
              .asMap()
              .entries
              .map((e) => MapEntry('Hatcher ${e.value.hatcherId}',
                  colors[e.key % colors.length]))
              .toList()),
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
            .map((e) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 3, color: e.value),
                    const SizedBox(width: 4),
                    Text(e.key, style: const TextStyle(fontSize: 12)),
                  ],
                ))
            .toList(),
      ),
    );
  }
}
