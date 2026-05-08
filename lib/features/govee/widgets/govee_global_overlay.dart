import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../screens/govee_screen.dart';

class GoveeGlobalOverlay extends StatelessWidget {
  final Widget child;
  final bool showLauncher;
  final BuildContext? Function() panelContextBuilder;

  const GoveeGlobalOverlay({
    super.key,
    required this.child,
    required this.showLauncher,
    required this.panelContextBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (!showLauncher) return child;

    return Stack(
      children: [
        Positioned.fill(child: child),
        Align(
          alignment: Alignment.bottomRight,
          child: SafeArea(
            minimum: const EdgeInsets.all(18),
            child: Semantics(
              label: 'Govee readings',
              button: true,
              child: Material(
                key: const ValueKey('govee-global-launcher'),
                color: AppColors.primary,
                elevation: 8,
                shadowColor: const Color(0x47193FC2),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _openGoveePanel(context),
                  child: const SizedBox.square(
                    dimension: 64,
                    child: Icon(
                      Icons.device_thermostat_outlined,
                      color: AppColors.textOnPrimary,
                      size: 30,
                    ),
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
