import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../providers/govee_capture_provider.dart';

class GoveePlaceRecorder extends StatelessWidget {
  const GoveePlaceRecorder({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoveeCaptureProvider>();

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
              Icon(
                provider.isRecording
                    ? Icons.radio_button_checked
                    : Icons.device_thermostat_outlined,
                color: provider.isRecording
                    ? AppColors.statusError
                    : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _phaseLabel(provider.phase),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _RecordingContext(provider: provider),
          const SizedBox(height: 14),
          _RecordingState(provider: provider),
          if (provider.error != null) ...[
            const SizedBox(height: 12),
            Text(
              provider.error!,
              style: const TextStyle(
                color: AppColors.statusError,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (provider.syncFailureDetails != null ||
              provider.syncFailureDiagnostics.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SyncDiagnostics(provider: provider),
          ],
          const SizedBox(height: 14),
          if (provider.phase == GoveeCapturePhase.syncFailed ||
              provider.phase == GoveeCapturePhase.saveFailed)
            FilledButton.icon(
              onPressed: provider.canStopRecording
                  ? () => context
                        .read<GoveeCaptureProvider>()
                        .stopAndSavePlaceCapture()
                  : null,
              icon: Icon(
                provider.phase == GoveeCapturePhase.saveFailed
                    ? Icons.save_outlined
                    : Icons.sync,
              ),
              label: Text(
                provider.phase == GoveeCapturePhase.saveFailed
                    ? 'Retry save'
                    : 'Retry sync',
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: provider.canStartRecording
                        ? () => context
                              .read<GoveeCaptureProvider>()
                              .startRecording()
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start recording'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: provider.canStopRecording
                        ? () => context
                              .read<GoveeCaptureProvider>()
                              .stopAndSavePlaceCapture()
                        : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop and save'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _phaseLabel(GoveeCapturePhase phase) {
    return switch (phase) {
      GoveeCapturePhase.validRecording => 'Place recording',
      GoveeCapturePhase.syncing => 'Syncing Govee history',
      GoveeCapturePhase.syncFailed => 'History sync failed',
      GoveeCapturePhase.saving => 'Saving place capture',
      GoveeCapturePhase.saveFailed => 'Save failed',
      GoveeCapturePhase.saved => 'Place capture saved',
      _ => 'Place recorder',
    };
  }
}

class _SyncDiagnostics extends StatelessWidget {
  final GoveeCaptureProvider provider;

  const _SyncDiagnostics({required this.provider});

  @override
  Widget build(BuildContext context) {
    final details = provider.syncFailureDetails;
    final diagnostics = provider.syncFailureDiagnostics;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.bug_report_outlined,
                color: AppColors.textSecondary,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Sync diagnostics',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (details != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              details,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (diagnostics.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...diagnostics.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText(
                  entry,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordingContext extends StatelessWidget {
  final GoveeCaptureProvider provider;

  const _RecordingContext({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.ageBadgeBg,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.place_outlined, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.place?.label ?? 'Choose a place',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  _machineText(provider),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _machineText(GoveeCaptureProvider provider) {
    if (provider.captureTarget == GoveeCaptureTarget.insideMachine) {
      return provider.machineDisplayLabel ?? 'Inside machine';
    }
    return 'Room environment';
  }
}

class _RecordingState extends StatelessWidget {
  final GoveeCaptureProvider provider;

  const _RecordingState({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: provider.isRecording
            ? AppColors.statusWarningBg
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Text(
        _stateText(provider),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _stateText(GoveeCaptureProvider provider) {
    return switch (provider.phase) {
      GoveeCapturePhase.validRecording =>
        'Recording length ${_formatElapsed(provider.recordingElapsedSeconds)}. Live readings are preview only. Stop will sync the full Govee history window.',
      GoveeCapturePhase.syncing =>
        'Syncing saved history from the Govee device.',
      GoveeCapturePhase.syncFailed =>
        'Reconnect and retry this place recording.',
      GoveeCapturePhase.saving =>
        'Saving LTTB chart points and full summary stats.',
      GoveeCapturePhase.saveFailed =>
        'Retry save using the synced Govee history already captured.',
      GoveeCapturePhase.saved => 'Saved. Choose another place when ready.',
      _ =>
        'Start once for this place, then stop when the place window is complete.',
    };
  }

  String _formatElapsed(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }
}
