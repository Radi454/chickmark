import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../features/audits/widgets/troubleshooting_sheet.dart';

class TroubleshootingIcon extends StatelessWidget {
  final String parameterId;
  final bool visible;

  const TroubleshootingIcon({
    super.key,
    required this.parameterId,
    this.visible = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: const Icon(Icons.lightbulb_outline),
      color: AppColors.primary,
      tooltip: 'View Troubleshooting Guide',
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => TroubleshootingSheet(parameterId: parameterId),
        );
      },
    );
  }
}
