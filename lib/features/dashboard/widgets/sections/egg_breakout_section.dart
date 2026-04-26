import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/features/dashboard/models/egg_breakout_models.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/widgets/photo_grid.dart';
import 'package:hatchaudit/features/dashboard/screens/photo_fullscreen_screen.dart';

class EggBreakoutSection extends StatelessWidget {
  const EggBreakoutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, child) {
        final avg = provider.eggBreakoutAvg;
        final bmk = provider.bmkReference;

        return Card(
          child: ExpansionTile(
            title: const Text('21-Day Hatch Residue Breakout'),
            initiallyExpanded: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tray size: 750 eggs'),
                ),
              ),
              if (provider.isLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                )
              else if (avg == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No data'),
                )
              else ...[
                _buildMetrics(avg, bmk),
                if (provider.eggBreakoutPhotos.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Photos',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  PhotoGrid(
                    filePaths: provider.eggBreakoutPhotos,
                    onTap: (path) => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PhotoFullscreenScreen(filePath: path),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetrics(EggBreakoutAvg avg, BmkReference? bmk) {
    final metrics = [
      _EggBreakoutMetric(
        'Infertile',
        avg.infertileCount,
        avg.infertilePct,
        bmk?.infertilePct ?? 0,
      ),
      _EggBreakoutMetric(
        'Early Dead',
        avg.earlyDeadCount,
        avg.earlyDeadPct,
        bmk?.earlyDeadPct ?? 0,
      ),
      _EggBreakoutMetric(
        'Mid Black Eye',
        avg.midDeadCount,
        avg.midDeadPct,
        bmk?.midBlackEyePct ?? 0,
      ),
      _EggBreakoutMetric(
        'Late Dead',
        avg.lateDeadCount,
        avg.lateDeadPct,
        bmk?.lateDeadPct ?? 0,
      ),
      _EggBreakoutMetric(
        'Internal Pip',
        avg.internalPipCount,
        avg.internalPipPct,
        bmk?.internalPipPct ?? 0,
      ),
      _EggBreakoutMetric(
        'External Pip',
        avg.externalPipCount,
        avg.externalPipPct,
        bmk?.externalPipPct ?? 0,
      ),
      _EggBreakoutMetric(
        'Cracked',
        avg.crackedCount,
        avg.crackedPct,
        bmk?.crackedPct ?? 0,
      ),
      _EggBreakoutMetric(
        'Contaminated',
        avg.contaminatedCount,
        avg.contamPct,
        bmk?.contamPct ?? 0,
      ),
      _EggBreakoutMetric(
        'Malposition',
        avg.malpositionCount,
        avg.malpositionPct,
        bmk?.turnedPct ?? 0,
      ),
      _EggBreakoutMetric(
        'Exposed Brain',
        avg.exposedBrainCount,
        avg.exposedBrainPct,
        bmk?.exposedBrainPct ?? 0,
      ),
      _EggBreakoutMetric(
        'Crossed Beak',
        avg.crossedBeakCount,
        avg.crossedBeakPct,
        bmk?.crossedBeakPct ?? 0,
      ),
      _EggBreakoutMetric(
        'Culled / Dead',
        avg.culledDeadCount,
        avg.cullPct,
        bmk?.cullPct ?? 0,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          const _BreakoutHeader(),
          const Divider(height: 16),
          ...metrics.map(_BreakoutMetricRow.new),
        ],
      ),
    );
  }
}

class _BreakoutHeader extends StatelessWidget {
  const _BreakoutHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Row(
      children: [
        Expanded(flex: 3, child: Text('Parameter', style: style)),
        Expanded(
          child: Text('Eggs', textAlign: TextAlign.end, style: style),
        ),
        Expanded(
          child: Text('Actual', textAlign: TextAlign.end, style: style),
        ),
        Expanded(
          child: Text('BMK', textAlign: TextAlign.end, style: style),
        ),
        const SizedBox(width: 18),
      ],
    );
  }
}

class _BreakoutMetricRow extends StatelessWidget {
  final _EggBreakoutMetric metric;

  const _BreakoutMetricRow(this.metric);

  @override
  Widget build(BuildContext context) {
    final hasBmk = metric.bmkPct > 0;
    final isHigh = hasBmk && metric.actualPct > metric.bmkPct;
    final statusColor = hasBmk
        ? (isHigh ? const Color(0xFFE24B4A) : const Color(0xFF3A9A5C))
        : AppColors.inactiveTab;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(metric.label)),
          Expanded(
            child: Text(
              metric.eggCount.toStringAsFixed(0),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              '${metric.actualPct.toStringAsFixed(1)}%',
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            child: Text(
              hasBmk ? '${metric.bmkPct.toStringAsFixed(1)}%' : '--',
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _EggBreakoutMetric {
  final String label;
  final double eggCount;
  final double actualPct;
  final double bmkPct;

  const _EggBreakoutMetric(
    this.label,
    this.eggCount,
    this.actualPct,
    this.bmkPct,
  );
}
