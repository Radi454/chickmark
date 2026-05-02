import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../providers/govee_capture_provider.dart';

class GoveeSpotRecorder extends StatelessWidget {
  const GoveeSpotRecorder({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoveeCaptureProvider>();
    final phase = provider.phase;
    final currentSpot = provider.currentSpotIndex;
    final scopeReady =
        provider.customerId != null &&
        provider.hatcheryId != null &&
        provider.place != null &&
        provider.captureDate != null;

    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.device_thermostat_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _phaseLabel(phase, currentSpot),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${provider.completedSpotCount}/${GoveeCaptureProvider.spotCount}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.ageBadgeBg,
                borderRadius: BorderRadius.circular(AppSizes.cardRadius),
              ),
              child: Center(
                child: Icon(
                  phase == GoveeSpotPhase.autoEnded
                      ? Icons.notifications_active_outlined
                      : Icons.show_chart,
                  color: AppColors.primary,
                  size: 34,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (provider.error != null) ...[
            Text(
              provider.error!,
              style: const TextStyle(
                color: AppColors.statusError,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: scopeReady && _canStart(phase)
                      ? () => context
                            .read<GoveeCaptureProvider>()
                            .startCurrentSpot()
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Start Spot $currentSpot'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: provider.canFinishCurrentSpot
                      ? () => context
                            .read<GoveeCaptureProvider>()
                            .finishCurrentSpot()
                      : null,
                  icon: const Icon(Icons.skip_next_outlined),
                  label: Text(_finishLabel(phase, currentSpot)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _canStart(GoveeSpotPhase phase) {
    return phase == GoveeSpotPhase.idle ||
        phase == GoveeSpotPhase.complete ||
        phase == GoveeSpotPhase.saved;
  }

  String _phaseLabel(GoveeSpotPhase phase, int spot) {
    return switch (phase) {
      GoveeSpotPhase.idle => 'Spot $spot',
      GoveeSpotPhase.warmup => 'Spot $spot warmup',
      GoveeSpotPhase.validRecording => 'Spot $spot recording',
      GoveeSpotPhase.readyForNext => 'Spot $spot ready',
      GoveeSpotPhase.autoEnded => 'Move device',
      GoveeSpotPhase.syncing => 'Syncing Spot $spot',
      GoveeSpotPhase.complete => 'Spot saved',
      GoveeSpotPhase.review => 'Review capture',
      GoveeSpotPhase.saving => 'Saving capture',
      GoveeSpotPhase.saved => 'Capture saved',
    };
  }

  String _finishLabel(GoveeSpotPhase phase, int spot) {
    if (phase == GoveeSpotPhase.autoEnded) return 'Sync Spot $spot';
    return 'Finish Spot $spot';
  }
}
