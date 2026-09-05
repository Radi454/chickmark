import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/flock_model.dart';
import '../../../services/breeder/breeder_flock_lifecycle_service.dart';

/// Minimal, in-style surface for a flock's lifecycle state
/// (breeder-flock-performance ticket 06): total age, official production
/// week (or a pre-production indicator), and — only when the flock's
/// recorded 5%-production milestone runs off the official schedule by more
/// than a week — the milestone-aligned comparison axis shown beside the
/// official one. All calculations come from
/// `BreederFlockLifecycleService`, never re-derived here.
class BreederFlockLifecycleSummary extends StatefulWidget {
  final FlockModel flock;
  final BreederFlockLifecycleService? service;

  const BreederFlockLifecycleSummary({
    super.key,
    required this.flock,
    this.service,
  });

  @override
  State<BreederFlockLifecycleSummary> createState() =>
      _BreederFlockLifecycleSummaryState();
}

class _BreederFlockLifecycleSummaryState
    extends State<BreederFlockLifecycleSummary> {
  late final BreederFlockLifecycleService _service;
  late Future<ComparisonAxisOffer> _future;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? BreederFlockLifecycleService();
    _future = _service.comparisonAxes(widget.flock);
  }

  @override
  void didUpdateWidget(covariant BreederFlockLifecycleSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flock.id != widget.flock.id ||
        oldWidget.flock.entryDate != widget.flock.entryDate ||
        oldWidget.flock.breed != widget.flock.breed) {
      _future = _service.comparisonAxes(widget.flock);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ComparisonAxisOffer>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final offer = snapshot.data!;
        final official = offer.official;
        final milestoneAligned = offer.milestoneAligned;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(
              'Total age',
              '${official.ageDays} days (${official.ageWeeks}w)',
            ),
            const SizedBox(height: 8),
            _row(
              'Production week',
              official.isPreProduction
                  ? 'Pre-production'
                  : 'Week ${official.productionWeek}',
            ),
            if (milestoneAligned != null) ...[
              const SizedBox(height: 8),
              _row(
                'Milestone-aligned week',
                milestoneAligned.isPreProduction
                    ? 'Pre-production'
                    : 'Week ${milestoneAligned.productionWeek}',
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(color: Colors.grey[600]),
          ),
        ),
        Expanded(
          child: Text(value, style: AppTextStyles.body),
        ),
      ],
    );
  }
}
