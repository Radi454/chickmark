import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/breeder_alert_models.dart';
import '../../../data/models/breeder_weighing_session_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/repositories/breeder_performance_alert_repository.dart';
import '../../../services/breeder/breeder_flock_lifecycle_service.dart';
import '../../../services/breeder/breeder_flock_overview_service.dart';
import '../../../services/breeder/breeder_weighing_service.dart';
import '../../../widgets/section_card.dart';
import '../widgets/breeder_incomplete_data_label.dart';
import 'breeder_daily_report_list_screen.dart';
import 'breeder_performance_alerts_screen.dart';
import 'breeder_weighing_session_list_screen.dart';
import 'egg_batch_shipment_list_screen.dart';

/// The Overview tab of a flock's Breeder Performance area
/// (breeder-flock-performance ticket 18, design doc section 11: "Overview:
/// current inventory, production, feed, mortality, benchmark comparisons,
/// data completeness, and open alerts"). This is the landing point for the
/// whole feature — every figure here is composed by
/// [BreederFlockOverviewService] from the domain services tickets 06-17
/// already built; this screen only lays the results out.
///
/// This screen never recomputes a balance, percentage, or completeness
/// count itself — see [BreederFlockOverviewService]'s own doc comment for
/// exactly which service produced each figure.
class BreederFlockOverviewScreen extends StatefulWidget {
  final FlockModel flock;
  final BreederFlockOverviewService? overviewService;

  /// Passed through to the "View all alerts" navigation target
  /// ([BreederPerformanceAlertsScreen]) so a test can inject the same fake
  /// repository the rest of the screen's data came from, rather than that
  /// screen touching the real database.
  final BreederPerformanceAlertRepository? alertRepository;

  /// Overrides "now" for the age/period calculations this screen composes
  /// (test-only hook — production callers never pass this, matching every
  /// other breeder screen's `now`-parameterized services).
  final DateTime? now;

  const BreederFlockOverviewScreen({
    super.key,
    required this.flock,
    this.overviewService,
    this.alertRepository,
    this.now,
  });

  @override
  State<BreederFlockOverviewScreen> createState() =>
      _BreederFlockOverviewScreenState();
}

class _BreederFlockOverviewScreenState
    extends State<BreederFlockOverviewScreen> {
  late final BreederFlockOverviewService _service =
      widget.overviewService ?? BreederFlockOverviewService();
  late Future<BreederFlockOverview> _overviewFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _overviewFuture = _service.loadOverview(
      flock: widget.flock,
      now: widget.now,
    );
  }

  Future<void> _reload() async {
    setState(_load);
    await _overviewFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Overview — ${widget.flock.flockId}',
      ),
      body: FutureBuilder<BreederFlockOverview>(
        future: _overviewFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                child: Text(
                  context.tr('Could not load the flock overview.'),
                  style: AppTextStyles.body,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final overview = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(AppSizes.cardPadding),
              children: [
                _LifecycleCard(overview: overview),
                const SizedBox(height: AppSizes.cardPadding),
                _CompletenessCard(overview: overview),
                const SizedBox(height: AppSizes.cardPadding),
                _BirdsCard(overview: overview),
                const SizedBox(height: AppSizes.cardPadding),
                _ProductionCard(overview: overview),
                const SizedBox(height: AppSizes.cardPadding),
                _FeedAndMortalityCard(overview: overview),
                const SizedBox(height: AppSizes.cardPadding),
                _EggStockCard(overview: overview),
                const SizedBox(height: AppSizes.cardPadding),
                _WeighingCard(overview: overview),
                const SizedBox(height: AppSizes.cardPadding),
                _AlertsCard(
                  overview: overview,
                  flock: widget.flock,
                  alertRepository: widget.alertRepository,
                ),
                const SizedBox(height: AppSizes.cardPadding),
                _NavigationRow(flock: widget.flock),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// `null` reads as blank (a horizontal dash) everywhere a figure's
/// denominator was empty, zero, or negative — never `0`, per design doc
/// section 7.2.
String _blankOr(String? value) => value ?? '—';

String _num(num? value, {String suffix = ''}) {
  if (value == null) return '—';
  final rounded = value is int ? value.toString() : value.toStringAsFixed(1);
  return '$rounded$suffix';
}

String _axisLabel(BuildContext context, ComparisonAxis? axis) {
  if (axis == null) return _blankOr(null);
  return axis.kind == ComparisonAxisKind.official
      ? context.tr('official')
      : context.tr('Milestone-aligned');
}

class _LifecycleCard extends StatelessWidget {
  final BreederFlockOverview overview;

  const _LifecycleCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    final week = overview.productionWeek;
    final profile = overview.axisOffer.profile;
    return SectionCard(
      title: context.tr('Breeder Performance'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${context.tr("Current age")}: ${overview.age.ageWeeks} '
            '${context.tr("wk")} (${overview.age.ageDays} '
            '${context.tr("days")})',
          ),
          const SizedBox(height: 4),
          Text(
            overview.isPreProduction
                ? context.tr('Pre-production')
                : '${context.tr("Production week")}: ${week.productionWeek}',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${context.tr("Guide version")}: '
            '${profile?.guideVersion ?? context.tr("No official benchmark for this breed")} '
            '· ${context.tr("Axis")}: ${_axisLabel(context, week.axis)}',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletenessCard extends StatelessWidget {
  final BreederFlockOverview overview;

  const _CompletenessCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    final completeness = overview.completeness;
    return SectionCard(
      title: context.tr('Data completeness'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${HatchDateUtils.formatDisplayDate(overview.periodStart)} – '
            '${HatchDateUtils.formatDisplayDate(overview.periodEnd)}',
          ),
          const SizedBox(height: 4),
          Text(
            '${context.tr("Recorded")}: ${completeness.recordedDayCount} / '
            '${completeness.totalDayCount}   '
            '${context.tr("Missing")}: ${completeness.missingDayCount}',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          BreederIncompleteDataLabel(completeness: completeness),
        ],
      ),
    );
  }
}

class _BirdsCard extends StatelessWidget {
  final BreederFlockOverview overview;

  const _BirdsCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    final birds = overview.birds;
    return SectionCard(
      title: context.tr('Current inventory'),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2)},
        children: [
          _headerRow(context),
          _birdRow(
            context,
            context.tr('Females'),
            birds.houseFemales,
            birds.isolationFemales,
            birds.totalFemales,
          ),
          _birdRow(
            context,
            context.tr('Males'),
            birds.houseMales,
            birds.isolationMales,
            birds.totalMales,
          ),
        ],
      ),
    );
  }

  TableRow _headerRow(BuildContext context) {
    TextStyle style = AppTextStyles.body.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: AppColors.textSecondary,
    );
    return TableRow(
      children: [
        const SizedBox(),
        Text(context.tr('Houses'), style: style, textAlign: TextAlign.end),
        Text(context.tr('Isolation'), style: style, textAlign: TextAlign.end),
        Text(context.tr('Total'), style: style, textAlign: TextAlign.end),
      ],
    );
  }

  TableRow _birdRow(
    BuildContext context,
    String label,
    int house,
    int isolation,
    int total,
  ) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label, style: AppTextStyles.body),
        ),
        Text('$house', textAlign: TextAlign.end),
        Text('$isolation', textAlign: TextAlign.end),
        Text(
          '$total',
          textAlign: TextAlign.end,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _ProductionCard extends StatelessWidget {
  final BreederFlockOverview overview;

  const _ProductionCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    final totals = overview.periodTotals;
    final comparison = overview.productionBenchmark;
    return SectionCard(
      title: context.tr('Hen-Week Production'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${context.tr("Total eggs")}: ${_num(totals.totalEggs)}',
          ),
          const SizedBox(height: 4),
          if (overview.isPreProduction)
            Text(
              context.tr('Pre-production'),
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            Text(
              '${context.tr("Actual")}: ${_num(comparison.actualValue, suffix: "%")}  '
              '${context.tr("Official target")}: '
              '${_num(comparison.benchmarkValue, suffix: "%")}',
            ),
          const SizedBox(height: 8),
          BreederPartialDataWarning(comparison: comparison),
        ],
      ),
    );
  }
}

class _FeedAndMortalityCard extends StatelessWidget {
  final BreederFlockOverview overview;

  const _FeedAndMortalityCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    final totals = overview.periodTotals;
    return SectionCard(
      title: context.tr('Feed'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${context.tr("Total feed (kg)")}: ${_num(totals.feedKgTotal)}'),
          const SizedBox(height: 4),
          Text(
            '${context.tr("Feed per female")}: '
            '${_num(totals.avgFeedGramsPerFemale, suffix: " g")}   '
            '${context.tr("Feed per male")}: '
            '${_num(totals.avgFeedGramsPerMale, suffix: " g")}',
          ),
          const Divider(height: 20),
          Text(
            '${context.tr("Mortality")}: ${_num(totals.mortalityTotal)}',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _EggStockCard extends StatelessWidget {
  final BreederFlockOverview overview;

  const _EggStockCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: context.tr('Egg inventory'),
      child: overview.eggStock.isEmpty
          ? Text(context.tr('No egg grades are configured yet.'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final grade in overview.eggStock)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(grade.gradeName),
                        Text(
                          '${grade.closingBalance}',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _WeighingCard extends StatelessWidget {
  final BreederFlockOverview overview;

  const _WeighingCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: context.tr('Weighing'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sessionRow(
            context,
            context.tr('Females'),
            overview.latestFemaleWeighingSession,
            overview.latestFemaleWeighingComparison,
          ),
          const SizedBox(height: 8),
          _sessionRow(
            context,
            context.tr('Males'),
            overview.latestMaleWeighingSession,
            overview.latestMaleWeighingComparison,
          ),
        ],
      ),
    );
  }

  Widget _sessionRow(
    BuildContext context,
    String sexLabel,
    BreederWeighingSession? session,
    BreederWeighingComparison? comparison,
  ) {
    if (session == null) {
      return Text(
        '$sexLabel — ${context.tr("No weighing sessions yet")}',
        style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sexLabel,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          '${context.tr("Mean weight")}: ${_num(session.derivedMeanWeightG, suffix: " g")}   '
          '${context.tr("Official target")}: '
          '${_num(comparison?.targetWeightG, suffix: " g")}',
        ),
        Text(
          '${context.tr("Uniformity")}: '
          '${_num(session.derivedUniformityPct, suffix: "%")}   '
          'CV: ${_num(session.derivedCvPct, suffix: "%")}',
          style: AppTextStyles.body.copyWith(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        if (comparison?.profile != null)
          Text(
            '${context.tr("Guide version")}: ${comparison!.profile!.guideVersion} '
            '· ${context.tr("Axis")}: ${_axisLabel(context, comparison.axis)}',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
      ],
    );
  }
}

class _AlertsCard extends StatelessWidget {
  final BreederFlockOverview overview;
  final FlockModel flock;
  final BreederPerformanceAlertRepository? alertRepository;

  const _AlertsCard({
    required this.overview,
    required this.flock,
    this.alertRepository,
  });

  bool _isCritical(BreederPerformanceAlert alert) =>
      alert.severity == BreederAlertSeverity.critical;

  @override
  Widget build(BuildContext context) {
    final alerts = overview.openAlerts;
    return SectionCard(
      title: context.tr('Alerts'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alerts.isEmpty)
            Text(
              context.tr('No open alerts'),
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            for (final alert in alerts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _isCritical(alert)
                            ? AppColors.statusErrorBg
                            : AppColors.statusWarningBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _isCritical(alert)
                            ? context.tr('Critical')
                            : context.tr('Watch'),
                        style: AppTextStyles.body.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isCritical(alert)
                              ? AppColors.statusError
                              : AppColors.statusWarning,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        alert.metricCode,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      alert.thresholdIsOfficial
                          ? context.tr('Official guide limit')
                          : context.tr('App-defined threshold'),
                      style: AppTextStyles.body.copyWith(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BreederPerformanceAlertsScreen(
                    flock: flock,
                    alertRepository: alertRepository,
                  ),
                ),
              ),
              child: Text(context.tr('View all alerts')),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationRow extends StatelessWidget {
  final FlockModel flock;

  const _NavigationRow({required this.flock});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BreederDailyReportListScreen(flock: flock),
            ),
          ),
          icon: const Icon(Icons.assignment_outlined, size: 18),
          label: Text(context.tr('Daily Reports')),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BreederWeighingSessionListScreen(flock: flock),
            ),
          ),
          icon: const Icon(Icons.monitor_weight_outlined, size: 18),
          label: Text(context.tr('Weighing Sessions')),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EggBatchShipmentListScreen(flock: flock),
            ),
          ),
          icon: const Icon(Icons.egg_outlined, size: 18),
          label: Text(context.tr('Egg Stock & Shipments')),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BreederPerformanceAlertsScreen(flock: flock),
            ),
          ),
          icon: const Icon(Icons.notifications_active_outlined, size: 18),
          label: Text(context.tr('Alerts')),
        ),
      ],
    );
  }
}
