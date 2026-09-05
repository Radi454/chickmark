import 'package:hatchaudit/localized_material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/data/models/breeder_benchmark_models.dart';
import 'package:hatchaudit/data/repositories/breeder_benchmark_repository.dart';
import 'package:hatchaudit/widgets/section_card.dart';

/// Read-only detail view of one official benchmark profile: source, guide
/// version, publication date, effective ages, and every published value
/// grouped by metric. There is no edit affordance anywhere on this screen —
/// benchmarks are versioned reference data (see
/// docs/superpowers/specs/2026-08-27-breeder-flock-performance-design.md
/// section 4).
class BreederBenchmarkDetailScreen extends StatefulWidget {
  final BreederBenchmarkProfile profile;
  final BreederBenchmarkRepository? repository;

  const BreederBenchmarkDetailScreen({
    super.key,
    required this.profile,
    this.repository,
  });

  @override
  State<BreederBenchmarkDetailScreen> createState() =>
      _BreederBenchmarkDetailScreenState();
}

class _BreederBenchmarkDetailScreenState
    extends State<BreederBenchmarkDetailScreen> {
  late final BreederBenchmarkRepository _repository =
      widget.repository ?? BreederBenchmarkRepository();
  late final Future<_DetailData> _dataFuture = _load();

  Future<_DetailData> _load() async {
    final metrics = await _repository.getMetricDefinitionsById();
    final values = await _repository.getValuesForProfile(widget.profile.id);
    final byMetric = <String, List<BreederBenchmarkValue>>{};
    for (final value in values) {
      byMetric.putIfAbsent(value.metricId, () => []).add(value);
    }
    return _DetailData(metrics: metrics, byMetric: byMetric);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not stated';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Scaffold(
      appBar: GradientAppBar(title: profile.displayName),
      body: FutureBuilder<_DetailData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final metricIds = data.byMetric.keys.toList()
            ..sort((a, b) {
              final labelA = data.metrics[a]?.label ?? a;
              final labelB = data.metrics[b]?.label ?? b;
              return labelA.compareTo(labelB);
            });
          return ListView(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            children: [
              SectionCard(
                title: 'Source',
                icon: Icons.menu_book_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('Company', profile.company),
                    _infoRow('Breed', profile.breed),
                    _infoRow('Product', profile.product),
                    _infoRow('Guide version', profile.guideVersion),
                    _infoRow(
                      'Publication date',
                      _formatDate(profile.publicationDate),
                    ),
                    _infoRow(
                      'Effective ages',
                      '${profile.effectiveAgeStartDays}'
                          '${profile.effectiveAgeEndDays != null ? ' – ${profile.effectiveAgeEndDays} days' : '+ days'}',
                    ),
                    _infoRow('Lifecycle', profile.lifecycleCoverage),
                    const SizedBox(height: AppSizes.spaceSm),
                    InkWell(
                      onTap: () async {
                        final uri = Uri.tryParse(profile.sourceUrl);
                        if (uri == null) return;
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      child: Text(
                        profile.sourceUrl,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.spaceMd),
              for (final metricId in metricIds) ...[
                _MetricSection(
                  metric: data.metrics[metricId],
                  values: data.byMetric[metricId]!,
                ),
                const SizedBox(height: AppSizes.spaceMd),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: Text(value, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}

class _DetailData {
  final Map<String, BreederMetricDefinition> metrics;
  final Map<String, List<BreederBenchmarkValue>> byMetric;

  _DetailData({required this.metrics, required this.byMetric});
}

class _MetricSection extends StatelessWidget {
  final BreederMetricDefinition? metric;
  final List<BreederBenchmarkValue> values;

  const _MetricSection({required this.metric, required this.values});

  @override
  Widget build(BuildContext context) {
    final sorted = [...values]
      ..sort((a, b) {
        final ageCompare = a.ageDays.compareTo(b.ageDays);
        if (ageCompare != 0) return ageCompare;
        return a.sex.compareTo(b.sex);
      });
    final unit = metric?.unit ?? '';
    return SectionCard(
      title: metric?.label ?? 'Unknown metric',
      icon: Icons.show_chart,
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('${sorted.length} values ($unit)', style: AppTextStyles.body),
        children: [
          SizedBox(
            height: 320,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Age (d)')),
                  DataColumn(label: Text('Age (wk)')),
                  DataColumn(label: Text('Prod. wk')),
                  DataColumn(label: Text('Sex')),
                  DataColumn(label: Text('Target')),
                  DataColumn(label: Text('Range')),
                ],
                rows: sorted
                    .map(
                      (value) => DataRow(
                        cells: [
                          DataCell(Text('${value.ageDays}')),
                          DataCell(Text('${value.ageWeek}')),
                          DataCell(Text('${value.productionWeek ?? '—'}')),
                          DataCell(Text(value.sex)),
                          DataCell(
                            Text(metric?.format(value.targetValue) ?? '—'),
                          ),
                          DataCell(
                            Text(
                              (value.lowerBound != null || value.upperBound != null)
                                  ? '${value.lowerBound ?? '—'}–${value.upperBound ?? '—'}'
                                  : '—',
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
