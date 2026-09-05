import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/breeder_alert_models.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/repositories/breeder_performance_alert_repository.dart';
import '../../../services/breeder/breeder_alert_evaluation_service.dart';
import '../../../widgets/section_card.dart';

/// Watch/Critical performance-alert list for one flock
/// (breeder-flock-performance ticket 17, design doc section 10 and 11).
/// Shows actual value, official target, deviation, which benchmark profile
/// version and comparison axis produced the comparison, and — the rule
/// design section 10 cares most about — whether the cited threshold is
/// official or the app's own operational judgement. Acknowledge and close
/// are the only actions here: this screen never creates a visit,
/// investigation, cause assessment, or corrective action (ticket 01
/// deliberately removed that machinery).
class BreederPerformanceAlertsScreen extends StatefulWidget {
  final FlockModel flock;
  final BreederPerformanceAlertRepository? alertRepository;
  final BreederAlertEvaluationService? evaluationService;

  const BreederPerformanceAlertsScreen({
    super.key,
    required this.flock,
    this.alertRepository,
    this.evaluationService,
  });

  @override
  State<BreederPerformanceAlertsScreen> createState() =>
      _BreederPerformanceAlertsScreenState();
}

class _BreederPerformanceAlertsScreenState
    extends State<BreederPerformanceAlertsScreen> {
  late final BreederPerformanceAlertRepository _alertRepository =
      widget.alertRepository ?? BreederPerformanceAlertRepository();
  late final BreederAlertEvaluationService _evaluationService =
      widget.evaluationService ??
      BreederAlertEvaluationService(alertRepository: _alertRepository);
  late Future<List<BreederPerformanceAlert>> _alertsFuture;

  @override
  void initState() {
    super.initState();
    _alertsFuture = _alertRepository.listForFlock(widget.flock.id);
  }

  void _reload() {
    setState(() {
      _alertsFuture = _alertRepository.listForFlock(widget.flock.id);
    });
  }

  Future<void> _acknowledge(BreederPerformanceAlert alert) async {
    await _evaluationService.acknowledge(alert.id, actorUserId: 'current-user');
    if (mounted) _reload();
  }

  Future<void> _close(BreederPerformanceAlert alert) async {
    final reason = await _promptCloseReason();
    if (reason == null || reason.trim().isEmpty) return;
    await _evaluationService.close(alert.id, reason: reason.trim());
    if (mounted) _reload();
  }

  Future<String?> _promptCloseReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Close alert')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: context.tr('Reason for closing'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(context.tr('Close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Alerts — ${widget.flock.flockId}',
      ),
      body: FutureBuilder<List<BreederPerformanceAlert>>(
        future: _alertsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final alerts = snapshot.data ?? const [];
          if (alerts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                child: Text(
                  context.tr('No performance alerts for this flock.'),
                  style: AppTextStyles.body,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            itemCount: alerts.length,
            itemBuilder: (context, index) =>
                _AlertCard(
                  alert: alerts[index],
                  onAcknowledge: _acknowledge,
                  onClose: _close,
                ),
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final BreederPerformanceAlert alert;
  final ValueChanged<BreederPerformanceAlert> onAcknowledge;
  final ValueChanged<BreederPerformanceAlert> onClose;

  const _AlertCard({
    required this.alert,
    required this.onAcknowledge,
    required this.onClose,
  });

  bool get _isCritical => alert.severity == BreederAlertSeverity.critical;

  Color get _badgeBg =>
      _isCritical ? AppColors.statusErrorBg : AppColors.statusWarningBg;
  Color get _badgeText =>
      _isCritical ? AppColors.statusError : AppColors.statusWarning;

  String _severityLabel(BuildContext context) => _isCritical
      ? context.tr('Critical')
      : context.tr('Watch');

  String _thresholdSourceLabel(BuildContext context) => alert.thresholdIsOfficial
      ? context.tr('Official guide limit')
      : context.tr('App-defined threshold');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.cardPadding),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _badgeBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _severityLabel(context),
                    style: AppTextStyles.body.copyWith(
                      color: _badgeText,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alert.metricCode,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${context.tr("Period")}: '
              '${HatchDateUtils.formatDisplayDate(alert.periodStart)} – '
              '${HatchDateUtils.formatDisplayDate(alert.periodEnd)}',
            ),
            const SizedBox(height: 4),
            Text(
              '${context.tr("Actual")}: ${alert.actualValue} · '
              '${context.tr("Official target")}: '
              '${alert.officialTargetValue ?? alert.officialLowerBound ?? alert.officialUpperBound ?? "—"} · '
              '${context.tr("Deviation")}: ${alert.deviationValue.toStringAsFixed(1)}',
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  alert.thresholdIsOfficial
                      ? Icons.verified_outlined
                      : Icons.tune_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  _thresholdSourceLabel(context),
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (alert.benchmarkProfileVersion != null) ...[
              const SizedBox(height: 2),
              Text(
                '${context.tr("Guide version")}: '
                '${alert.benchmarkProfileVersion} · '
                '${context.tr("Axis")}: '
                '${alert.comparisonAxisKind ?? context.tr("official")}',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (alert.state == BreederPerformanceAlertState.closed &&
                alert.closedReason != null) ...[
              const SizedBox(height: 4),
              Text(
                '${context.tr("Closed")}: ${alert.closedReason}',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (alert.isOpen) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (alert.state == BreederPerformanceAlertState.new_)
                    OutlinedButton(
                      onPressed: () => onAcknowledge(alert),
                      child: Text(context.tr('Acknowledge')),
                    ),
                  OutlinedButton(
                    onPressed: () => onClose(alert),
                    child: Text(context.tr('Close')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
