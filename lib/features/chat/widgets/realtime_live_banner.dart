import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../providers/realtime_voice_controller.dart';

class RealtimeLiveBanner extends StatelessWidget {
  const RealtimeLiveBanner({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final RealtimeVoiceController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isRealtimeActive) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.spaceMd),
            child: Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppSizes.cardRadius),
              child: InkWell(
                key: const ValueKey('pip-live-banner'),
                onTap: onOpen,
                borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 16,
                    end: 6,
                    top: 8,
                    bottom: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.graphic_eq, color: Colors.white),
                      const SizedBox(width: AppSizes.spaceSm),
                      Expanded(
                        child: Text(
                          context.tr('Live voice conversation in progress'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('End live conversation'),
                        color: Colors.white,
                        onPressed: () => controller.stop(),
                        icon: const Icon(Icons.call_end_outlined),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
