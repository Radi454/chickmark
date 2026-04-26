import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../providers/temperature_rh_provider.dart';
import 'temperature_rh_panel.dart';

class TemperatureRhLauncher extends StatelessWidget {
  final BuildContext? Function()? panelContextBuilder;
  final ValueChanged<bool>? onPanelVisibilityChanged;

  const TemperatureRhLauncher({
    super.key,
    this.panelContextBuilder,
    this.onPanelVisibilityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TemperatureRhProvider>();
    final isActive = provider.isInitialized && provider.isActive;
    final color = isActive ? AppColors.greenTab : AppColors.primary;
    final label = isActive ? 'Temperature & R.H.' : 'Measure';
    final isWarmup = provider.isInWarmup;
    final launcher = Material(
      color: color,
      elevation: 8,
      shadowColor: const Color(0x47193FC2),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (!provider.isInitialized) {
            context.read<TemperatureRhProvider>().ensureInitialized();
          }
          _showPanel(panelContextBuilder?.call() ?? context);
        },
        customBorder: const CircleBorder(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: 64,
              child: Icon(
                isActive ? Icons.thermostat : Icons.thermostat_auto,
                color: Colors.white,
                size: 30,
              ),
            ),
            if (isActive)
              Positioned(
                bottom: 4,
                child: Container(
                  width: isWarmup ? 10 : 8,
                  height: isWarmup ? 10 : 8,
                  decoration: BoxDecoration(
                    color: isWarmup ? Colors.orange : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isWarmup ? Colors.orange : Colors.green,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (Overlay.maybeOf(context) == null) {
      return Semantics(label: label, button: true, child: launcher);
    }

    return Tooltip(message: label, child: launcher);
  }

  Future<void> _showPanel(BuildContext context) async {
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
              width: 420,
              height: MediaQuery.sizeOf(context).height - 80,
              child: const TemperatureRhPanel(compact: true),
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
          height: MediaQuery.sizeOf(context).height * 0.86,
          child: const TemperatureRhPanel(compact: true),
        ),
      );
    } finally {
      onPanelVisibilityChanged?.call(false);
    }
  }
}
