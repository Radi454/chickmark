import 'package:hatchaudit/localized_material.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/breeder_daily_report_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/repositories/breeder_daily_report_repository.dart';
import '../../../widgets/section_card.dart';
import 'breeder_daily_report_entry_screen.dart';
import 'breeder_daily_report_review_screen.dart';

/// Daily-report list for one flock (breeder-flock-performance ticket 07,
/// design doc section 11: "Daily Reports: list, create, continue, submit,
/// approve ... view daily or weekly output"). Reached from the flock's
/// Breeder Performance Overview (ticket 18's
/// `BreederFlockOverviewScreen`, now the actual landing point) — a missing
/// calendar day simply does not appear here, and this screen never creates
/// one on its own.
class BreederDailyReportListScreen extends StatefulWidget {
  final FlockModel flock;
  final BreederDailyReportRepository? repository;

  const BreederDailyReportListScreen({
    super.key,
    required this.flock,
    this.repository,
  });

  @override
  State<BreederDailyReportListScreen> createState() =>
      _BreederDailyReportListScreenState();
}

class _BreederDailyReportListScreenState
    extends State<BreederDailyReportListScreen> {
  late final BreederDailyReportRepository _repository =
      widget.repository ?? BreederDailyReportRepository();
  late Future<List<BreederDailyReport>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = _repository.listForFlock(widget.flock.id);
  }

  void _reload() {
    setState(() {
      _reportsFuture = _repository.listForFlock(widget.flock.id);
    });
  }

  Future<void> _createReport() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: widget.flock.entryDate,
      lastDate: today,
    );
    if (picked == null || !mounted) return;

    try {
      final report = await _repository.createDraft(
        flockId: widget.flock.id,
        reportDate: picked,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BreederDailyReportEntryScreen(
            flock: widget.flock,
            report: report,
          ),
        ),
      );
      if (mounted) _reload();
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _openReport(BreederDailyReport report) {
    final destination = report.isDraft
        ? BreederDailyReportEntryScreen(flock: widget.flock, report: report)
        : BreederDailyReportReviewScreen(flock: widget.flock, report: report);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => destination),
    ).then((_) {
      if (mounted) _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Breeder Performance — ${widget.flock.flockId}',
        actions: [
          IconButton(
            tooltip: context.tr('New report'),
            icon: const Icon(Icons.add),
            onPressed: _createReport,
          ),
        ],
      ),
      body: FutureBuilder<List<BreederDailyReport>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final reports = snapshot.data ?? const [];
          if (reports.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                child: Text(
                  context.tr(
                    'No daily reports yet. Tap + to record today\'s report.',
                  ),
                  style: AppTextStyles.body,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.cardPadding),
                child: SectionCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      HatchDateUtils.formatDisplayDate(report.reportDate),
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(_stateLabel(report.state)),
                    trailing: _stateBadge(report.state),
                    onTap: () => _openReport(report),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _stateLabel(String state) {
    switch (state) {
      case BreederDailyReportState.draft:
        return 'Draft';
      case BreederDailyReportState.submitted:
        return 'Submitted';
      case BreederDailyReportState.approved:
        return 'Approved';
      default:
        return state;
    }
  }

  Widget _stateBadge(String state) {
    final color = switch (state) {
      BreederDailyReportState.approved => AppColors.completedText,
      BreederDailyReportState.submitted => Colors.orange.shade800,
      _ => Colors.grey.shade700,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _stateLabel(state),
        style: AppTextStyles.body.copyWith(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
