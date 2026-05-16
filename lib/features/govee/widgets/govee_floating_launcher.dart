import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/temperature_rh_model.dart';
import '../../../features/audits/providers/audit_session_provider.dart';
import '../providers/govee_capture_provider.dart';
import 'govee_active_capture_content.dart';

class GoveeFloatingLauncher extends StatefulWidget {
  final BuildContext? Function()? panelContextBuilder;
  final ValueChanged<bool>? onPanelVisibilityChanged;
  final bool initializeLiveCardOnOpen;

  const GoveeFloatingLauncher({
    super.key,
    this.panelContextBuilder,
    this.onPanelVisibilityChanged,
    this.initializeLiveCardOnOpen = true,
  });

  @override
  State<GoveeFloatingLauncher> createState() => _GoveeFloatingLauncherState();
}

Future<void> openGoveeFloatingCapturePanel(
  BuildContext context, {
  BuildContext? panelContext,
  ValueChanged<bool>? onPanelVisibilityChanged,
  bool initializeLiveCardOnOpen = true,
}) async {
  if (initializeLiveCardOnOpen) {
    await _tryInitializeLiveCard(context);
  }
  if (!context.mounted) return;
  await _seedFirstScopeFromAudit(context);
  if (!context.mounted) return;
  await showGoveeFloatingCapturePanel(
    panelContext ?? context,
    onPanelVisibilityChanged: onPanelVisibilityChanged,
  );
}

Future<void> showGoveeFloatingCapturePanel(
  BuildContext context, {
  ValueChanged<bool>? onPanelVisibilityChanged,
}) async {
  onPanelVisibilityChanged?.call(true);
  final width = MediaQuery.sizeOf(context).width;
  try {
    if (width >= 900) {
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          alignment: Alignment.centerRight,
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 520,
            height: MediaQuery.sizeOf(context).height - 80,
            child: const GoveeFloatingCapturePanel(),
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.92,
        child: const GoveeFloatingCapturePanel(),
      ),
    );
  } finally {
    onPanelVisibilityChanged?.call(false);
  }
}

Future<void> _tryInitializeLiveCard(BuildContext context) async {
  try {
    await context.read<GoveeCaptureProvider>().ensureBleReady();
  } catch (_) {
    // BLE plugins may be unavailable in tests or on unsupported platforms.
    // The live card still renders and offers scan/retry controls.
  }
}

Future<void> _seedFirstScopeFromAudit(BuildContext context) async {
  final govee = context.read<GoveeCaptureProvider>();
  if (govee.customerId != null || govee.hatcheryId != null) return;
  final auditSession = context.read<AuditSessionProvider>().currentSession;
  if (auditSession == null) return;
  await govee.configure(
    customerId: auditSession.customerId,
    hatcheryId: auditSession.hatcheryId,
    place: govee.place ?? TemperaturePlace.eggStorageRoom,
  );
}

class _GoveeFloatingLauncherState extends State<GoveeFloatingLauncher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _autoEndSoundPlayed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoveeCaptureProvider>();
    final phase = provider.phase;
    final attention = phase == GoveeCapturePhase.syncFailed;
    final active = _isActive(phase);
    _syncAnimation(active: active, attention: attention);
    _maybePlayAutoEndSound(attention);

    final color = attention
        ? AppColors.statusWarning
        : active
        ? AppColors.greenTab
        : AppColors.primary;

    final launcher = Semantics(
      label: 'Open Govee',
      button: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final pulse = active ? _controller.value : 0.0;
          final ringScale = attention
              ? 1.08 + (pulse * 0.16)
              : 1.02 + (pulse * 0.08);
          final ringOpacity = attention
              ? 0.34 + (pulse * 0.26)
              : active
              ? 0.20 + (pulse * 0.18)
              : 0.0;

          return Stack(
            alignment: Alignment.center,
            children: [
              if (active)
                Transform.scale(
                  scale: ringScale,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: ringOpacity),
                        width: attention ? 5 : 4,
                      ),
                    ),
                  ),
                ),
              child!,
            ],
          );
        },
        child: Material(
          key: const ValueKey('govee-global-launcher'),
          color: color,
          elevation: 8,
          shadowColor: const Color(0x47193FC2),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              unawaited(_openPanel(context));
            },
            child: SizedBox.square(
              dimension: 64,
              child: Icon(
                attention
                    ? Icons.notification_important_outlined
                    : active
                    ? Icons.device_thermostat
                    : Icons.device_thermostat_outlined,
                color: Colors.white,
                size: attention ? 31 : 30,
              ),
            ),
          ),
        ),
      ),
    );

    return Overlay.maybeOf(context) == null
        ? launcher
        : Tooltip(message: 'Govee', child: launcher);
  }

  void _syncAnimation({required bool active, required bool attention}) {
    if (active || attention) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  void _maybePlayAutoEndSound(bool attention) {
    if (!attention) {
      _autoEndSoundPlayed = false;
      return;
    }
    if (_autoEndSoundPlayed) return;
    _autoEndSoundPlayed = true;
    unawaited(SystemSound.play(SystemSoundType.alert));
  }

  bool _isActive(GoveeCapturePhase phase) {
    return switch (phase) {
      GoveeCapturePhase.idle => false,
      GoveeCapturePhase.saved => false,
      _ => true,
    };
  }

  Future<void> _openPanel(BuildContext context) async {
    await openGoveeFloatingCapturePanel(
      context,
      panelContext: widget.panelContextBuilder?.call(),
      onPanelVisibilityChanged: widget.onPanelVisibilityChanged,
      initializeLiveCardOnOpen: widget.initializeLiveCardOnOpen,
    );
  }
}

class GoveeFloatingCapturePanel extends StatelessWidget {
  const GoveeFloatingCapturePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.device_thermostat_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Govee capture',
                    style: AppTextStyles.heading.copyWith(fontSize: 20),
                  ),
                ),
                IconButton(
                  tooltip: 'Close Govee',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(child: GoveeActiveCaptureContent()),
        ],
      ),
    );
  }
}
