import 'package:hatchaudit/localized_material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/data/models/breeder_benchmark_models.dart';
import 'package:hatchaudit/data/repositories/breeder_benchmark_repository.dart';
import 'package:hatchaudit/features/bmk/widgets/bmk_reference_widgets.dart';
import 'package:hatchaudit/features/breeder/screens/breeder_benchmark_detail_screen.dart';

/// The BMK screen's Breeder Farm sector.
///
/// Presents the official parent-stock benchmarks the same way the Hatchery
/// sector presents breed benchmarks: pick a line, pick an age, read the
/// values off a grid of tiles — no navigation required. The per-age tables
/// behind these numbers stay one tap away on
/// [BreederBenchmarkDetailScreen].
///
/// Read-only. Benchmarks come only from the checked-in asset importer (see
/// lib/data/database/seeds/breeder_benchmark_seeds.dart); nothing here writes.
///
/// Coverage is deliberately uneven and must stay visible: Hubbard publishes
/// no male table and no liveability, Cobb publishes no hen-housed production.
/// Every unpublished value renders as [kBmkNoValue], never as zero.
///
/// The sex toggle applies to every tile, with no exceptions. Only body weight
/// and daily feed intake are published for males; production, egg, hatch,
/// liveability and fertility describe the hen. With Male selected those tiles
/// read as [kBmkNoValue] rather than repeating the hen's figure under a Male
/// heading.
class BreederBmkSectorView extends StatefulWidget {
  final BreederBenchmarkRepository? repository;

  const BreederBmkSectorView({super.key, this.repository});

  @override
  State<BreederBmkSectorView> createState() => _BreederBmkSectorViewState();
}

/// Short pill labels for the benchmark lines.
///
/// The guides name their lines verbosely ("Hubbard Conventional (EDGE)") and
/// a pill is one ellipsized line, so truncation would make them ambiguous.
/// Anything unrecognised falls back to the guide's own breed name rather than
/// being silently shortened.
const Map<String, String> _kBreedPillLabels = {
  'Ross 308': 'Ross 308',
  'Arbor Acres Plus': 'Arbor Acres',
  'Indian River': 'Indian River',
  'Cobb500 Fast Feather': 'Cobb500 FF',
  'Hubbard Conventional (EDGE)': 'Hubbard EDGE',
};

const String _kSexFemale = 'female';
const String _kSexMale = 'male';

class _BreederBmkSectorViewState extends State<BreederBmkSectorView> {
  late final BreederBenchmarkRepository _repository =
      widget.repository ?? BreederBenchmarkRepository();

  late final Future<_SectorData> _sectorFuture = _loadSector();

  /// Per-profile value indexes, built once each and kept for the life of the
  /// sector so switching back to a line is instant.
  final Map<String, _ProfileIndex> _indexes = {};

  BreederBenchmarkProfile? _profile;
  String _sex = _kSexFemale;
  int? _ageWeek;
  bool _cumulative = false;
  bool _loadingProfile = false;

  Future<_SectorData> _loadSector() async {
    final profiles = await _repository.getProfiles();
    final metricsById = await _repository.getMetricDefinitionsById();
    final metricsByCode = {
      for (final def in metricsById.values) def.code: def,
    };
    final data = _SectorData(
      profiles: profiles,
      metricsById: metricsById,
      metricsByCode: metricsByCode,
    );
    if (profiles.isNotEmpty) {
      await _selectProfile(profiles.first, data, notify: false);
    }
    return data;
  }

  Future<void> _selectProfile(
    BreederBenchmarkProfile profile,
    _SectorData data, {
    bool notify = true,
  }) async {
    if (notify) setState(() => _loadingProfile = true);

    var index = _indexes[profile.id];
    if (index == null) {
      final values = await _repository.getValuesForProfile(profile.id);
      index = _ProfileIndex.build(values, data.metricsById);
      _indexes[profile.id] = index;
    }

    final sex = index.hasMale ? _sex : _kSexFemale;
    final age = index.defaultAgeWeek;

    if (!mounted) return;
    void apply() {
      _profile = profile;
      _sex = sex;
      _ageWeek = age;
      _loadingProfile = false;
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  double? _value(_ProfileIndex index, String code) {
    final week = _ageWeek;
    if (week == null) return null;
    return index.value(code: code, sex: _sex, ageWeek: week);
  }

  /// Builds one tile for [code] at the selected line, sex and age.
  ///
  /// Every tile follows the selected sex. Production, egg and hatch metrics
  /// describe the hen and are published for females only, so with Male
  /// selected they have no value and correctly read as [kBmkNoValue] —
  /// showing the hen's figure under a Male heading would be wrong.
  BmkMetric _metric(
    _SectorData data,
    _ProfileIndex index,
    String code, {
    bool stripPeriod = false,
  }) {
    final def = data.metricsByCode[code];
    var label = def?.label ?? code;
    // On the production card the Weekly/Cumulative pill already states the
    // period, so the label's own "(Weekly)" suffix is noise that pushes the
    // meaningful part of a long name out of the tile.
    if (stripPeriod) {
      label = label
          .replaceAll(' (Weekly)', '')
          .replaceAll(' (Cumulative)', '');
    }
    return BmkMetric(
      // Metric labels come from the imported guides, not from app copy.
      label: label,
      value: formatBmkBenchmark(
        _value(index, code),
        unit: def == null || def.unit.isEmpty ? '' : ' ${def.unit}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SectorData>(
      future: _sectorFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        final profile = _profile;
        if (data == null || data.profiles.isEmpty || profile == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.cardPadding),
              child: Text(
                context.tr('No published benchmark profiles yet.'),
                style: AppTextStyles.body,
              ),
            ),
          );
        }

        final index = _indexes[profile.id];
        final isCompact = MediaQuery.sizeOf(context).width < 520;

        return SingleChildScrollView(
          key: const ValueKey('breeder-bmk-sector-scroll'),
          padding: EdgeInsets.fromLTRB(
            isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
            isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
            isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
            AppSizes.spaceXl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBenchmarkCard(data, profile, index, isCompact),
                  SizedBox(
                    height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
                  ),
                  _buildProductionCard(data, index),
                  SizedBox(
                    height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
                  ),
                  _buildLivabilityCard(data, index),
                  SizedBox(
                    height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
                  ),
                  _buildSourceCard(profile),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBenchmarkCard(
    _SectorData data,
    BreederBenchmarkProfile profile,
    _ProfileIndex? index,
    bool isCompact,
  ) {
    return BmkSectorCard(
      title: 'Breeder Benchmarks',
      icon: Icons.analytics_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BmkControlShelf(
            primary: BmkPillBar(
              key: const ValueKey('breeder-bmk-profile-bar'),
              labels: data.profiles.map(_pillLabel).toList(),
              selected: _pillLabel(profile),
              onSelected: (label) {
                final next = data.profiles.firstWhere(
                  (p) => _pillLabel(p) == label,
                  orElse: () => profile,
                );
                if (next.id != profile.id) _selectProfile(next, data);
              },
              wideColumns: 6,
            ),
            secondary: BmkAgeControl(
              label: 'Reference age',
              value: index != null && index.ageWeeks.contains(_ageWeek)
                  ? _ageWeek
                  : null,
              ages: index?.ageWeeks ?? const [],
              onChanged: (age) {
                if (age != null) setState(() => _ageWeek = age);
              },
            ),
          ),
          SizedBox(height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg),
          if (index != null && index.hasMale) ...[
            BmkPillBar(
              key: const ValueKey('breeder-bmk-sex-bar'),
              labels: const ['Female', 'Male'],
              selected: _sex == _kSexMale ? 'Male' : 'Female',
              onSelected: (label) => setState(
                () => _sex = label == 'Male' ? _kSexMale : _kSexFemale,
              ),
              wideColumns: 2,
            ),
            SizedBox(height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg),
          ],
          if (_loadingProfile || index == null)
            const Center(child: CircularProgressIndicator())
          else
            BmkMetricGrid(
              key: const ValueKey('breeder-bmk-headline-grid'),
              metrics: [
                _metric(data, index, 'body_weight_g'),
                _metric(data, index, 'daily_feed_intake_g'),
                _metric(data, index, 'hen_week_production_pct'),
                _metric(data, index, 'egg_weight_g'),
                _metric(data, index, 'eggs_per_hen_housed_cumulative'),
                _metric(data, index, 'hatchability_cumulative_pct'),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildProductionCard(_SectorData data, _ProfileIndex? index) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;
    final codes = _cumulative
        ? const [
            'eggs_per_hen_housed_cumulative',
            'hatching_eggs_per_hen_housed_cumulative',
            'hatching_egg_utilization_cumulative_pct',
            'hatchability_cumulative_pct',
            'chicks_per_hen_housed_cumulative',
            'fertility_cumulative_pct',
          ]
        : const [
            'hen_housed_production_pct',
            'eggs_per_hen_housed_weekly',
            'hatching_eggs_per_hen_housed_weekly',
            'hatching_egg_utilization_weekly_pct',
            'hatchability_all_eggs_weekly_pct',
            'chicks_per_hen_housed_weekly',
            'egg_mass_g',
          ];

    return BmkSectorCard(
      title: 'Production BMK',
      icon: Icons.egg_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BmkPillBar(
            key: const ValueKey('breeder-bmk-period-bar'),
            labels: const ['Weekly', 'Cumulative'],
            selected: _cumulative ? 'Cumulative' : 'Weekly',
            onSelected: (label) =>
                setState(() => _cumulative = label == 'Cumulative'),
            wideColumns: 2,
          ),
          SizedBox(height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg),
          if (index == null)
            const Center(child: CircularProgressIndicator())
          else
            BmkMetricGrid(
              key: const ValueKey('breeder-bmk-production-grid'),
              metrics: [
                for (final code in codes)
                  _metric(data, index, code, stripPeriod: true),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLivabilityCard(_SectorData data, _ProfileIndex? index) {
    return BmkSectorCard(
      title: 'Liveability & Fertility',
      icon: Icons.monitor_heart_outlined,
      child: index == null
          ? const Center(child: CircularProgressIndicator())
          : BmkMetricGrid(
              key: const ValueKey('breeder-bmk-livability-grid'),
              metrics: [
                _metric(data, index, 'liveability_rearing_pct'),
                _metric(data, index, 'liveability_laying_pct'),
                _metric(data, index, 'fertility_weekly_pct'),
                _metric(data, index, 'flock_mortality_cumulative_pct'),
                _metric(data, index, 'chick_weight_g'),
              ],
            ),
    );
  }

  Widget _buildSourceCard(BreederBenchmarkProfile profile) {
    return BmkSectorCard(
      title: 'Source',
      icon: Icons.menu_book_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(profile.displayName, style: AppTextStyles.title),
          const SizedBox(height: AppSizes.spaceXs),
          Text(profile.guideVersion, style: AppTextStyles.body),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            '${context.tr('Published')}: ${_formatDate(profile.publicationDate)}',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSizes.spaceMd),
          Wrap(
            spacing: AppSizes.spaceSm,
            runSpacing: AppSizes.spaceSm,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('breeder-bmk-view-tables'),
                icon: const Icon(Icons.table_chart_outlined),
                label: Text(context.tr('View full tables')),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BreederBenchmarkDetailScreen(
                        profile: profile,
                        repository: _repository,
                      ),
                    ),
                  );
                },
              ),
              if (profile.sourceUrl.trim().isNotEmpty)
                OutlinedButton.icon(
                  key: const ValueKey('breeder-bmk-open-source'),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(context.tr('Open source')),
                  onPressed: () => _openSourceUrl(profile.sourceUrl),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openSourceUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failureMessage = context.tr('Could not open the source link.');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && messenger != null) {
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  String _pillLabel(BreederBenchmarkProfile profile) =>
      _kBreedPillLabels[profile.breed] ?? profile.breed;

  String _formatDate(DateTime? date) {
    if (date == null) return context.tr('Not stated');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}

class _SectorData {
  final List<BreederBenchmarkProfile> profiles;
  final Map<String, BreederMetricDefinition> metricsById;
  final Map<String, BreederMetricDefinition> metricsByCode;

  const _SectorData({
    required this.profiles,
    required this.metricsById,
    required this.metricsByCode,
  });
}

/// One profile's values, indexed for constant-time tile lookup.
class _ProfileIndex {
  /// metric code -> sex -> age week -> target value.
  final Map<String, Map<String, Map<int, double?>>> _byMetric;
  final List<int> ageWeeks;
  final bool hasMale;
  final int? _firstProductionWeek;

  const _ProfileIndex._(
    this._byMetric,
    this.ageWeeks,
    this.hasMale,
    this._firstProductionWeek,
  );

  factory _ProfileIndex.build(
    List<BreederBenchmarkValue> values,
    Map<String, BreederMetricDefinition> metricsById,
  ) {
    final byMetric = <String, Map<String, Map<int, double?>>>{};
    final weeks = <int>{};
    var hasMale = false;
    int? firstProduction;

    for (final value in values) {
      final code = metricsById[value.metricId]?.code;
      if (code == null) continue;
      weeks.add(value.ageWeek);
      if (value.sex == _kSexMale) hasMale = true;
      byMetric
          .putIfAbsent(code, () => {})
          .putIfAbsent(value.sex, () => {})[value.ageWeek] = value.targetValue;

      // The default age should land on a week the reader cares about, which
      // is the start of lay rather than day-old.
      if (code == 'hen_week_production_pct' &&
          (value.targetValue ?? 0) > 0 &&
          (firstProduction == null || value.ageWeek < firstProduction)) {
        firstProduction = value.ageWeek;
      }
    }

    final sorted = weeks.toList()..sort();
    return _ProfileIndex._(byMetric, sorted, hasMale, firstProduction);
  }

  int? get defaultAgeWeek =>
      _firstProductionWeek ?? (ageWeeks.isEmpty ? null : ageWeeks.first);

  /// Looks up the requested sex, falling back to values the guide publishes
  /// for both sexes at once. Returns null when the guide publishes nothing —
  /// callers must render that as [kBmkNoValue], never as zero.
  double? value({
    required String code,
    required String sex,
    required int ageWeek,
  }) {
    final bySex = _byMetric[code];
    if (bySex == null) return null;
    return bySex[sex]?[ageWeek] ?? bySex['both']?[ageWeek];
  }
}
