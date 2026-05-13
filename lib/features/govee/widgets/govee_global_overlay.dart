import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../screens/govee_screen.dart';

class GoveeGlobalOverlay extends StatelessWidget {
  final Widget child;
  final bool showLauncher;
  final bool isRecording;
  final BuildContext? Function() panelContextBuilder;

  const GoveeGlobalOverlay({
    super.key,
    required this.child,
    required this.showLauncher,
    this.isRecording = false,
    required this.panelContextBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (!showLauncher) return child;

    final launcherShape = isRecording
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))
        : const CircleBorder();
    final launcherColor = isRecording
        ? AppColors.statusError
        : AppColors.primary;
    final iconColor = isRecording
        ? AppColors.statusErrorBg
        : AppColors.textOnPrimary;
    final icon = isRecording
        ? Icons.stop_rounded
        : Icons.device_thermostat_outlined;

    return Stack(
      children: [
        Positioned.fill(child: child),
        Align(
          alignment: Alignment.bottomRight,
          child: SafeArea(
            minimum: const EdgeInsets.all(18),
            child: Semantics(
              label: isRecording
                  ? 'Govee recording in progress'
                  : 'Govee readings',
              button: true,
              child: Material(
                key: const ValueKey('govee-global-launcher'),
                color: launcherColor,
                elevation: 8,
                shadowColor: isRecording
                    ? const Color(0x47DC2626)
                    : const Color(0x47193FC2),
                shape: launcherShape,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  canRequestFocus: false,
                  customBorder: launcherShape,
                  onTap: () => _openGoveePanel(context),
                  child: SizedBox.square(
                    dimension: 64,
                    child: Icon(icon, color: iconColor, size: 30),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openGoveePanel(BuildContext context) async {
    final panelContext = panelContextBuilder() ?? context;
    await showModalBottomSheet<void>(
      context: panelContext,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final height = MediaQuery.sizeOf(sheetContext).height * 0.92;
        return SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: const GoveeScreen(),
          ),
        );
      },
    );
  }
}
