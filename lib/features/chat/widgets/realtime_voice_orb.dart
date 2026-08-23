import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../providers/realtime_voice_controller.dart';

/// A deliberately presentation-only pulse for the Live surface.
///
/// One [AnimationController] drives every ring: it never listens to an audio
/// level stream, so its motion is bounded and identical on every device. What
/// changes with call state is only [intensityFor] (how far the pulse swings)
/// and, in the error state, the color family — everything else is the same
/// breathing loop, eased so it reads as slow and calm rather than mechanical.
class RealtimeVoiceOrb extends StatefulWidget {
  const RealtimeVoiceOrb({super.key, required this.state});

  final RealtimeVoiceState state;

  @override
  State<RealtimeVoiceOrb> createState() => _RealtimeVoiceOrbState();
}

class _RealtimeVoiceOrbState extends State<RealtimeVoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  static double intensityFor(RealtimeVoiceState state) => switch (state) {
    RealtimeVoiceState.userSpeaking => 1.0,
    RealtimeVoiceState.assistantSpeaking => 0.85,
    RealtimeVoiceState.thinking => 0.55,
    RealtimeVoiceState.listening => 0.25,
    _ => 0.1,
  };

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isError = widget.state == RealtimeVoiceState.error;
    final baseColor = isError ? AppColors.statusError : AppColors.primary;
    final intensity = intensityFor(widget.state);
    return Semantics(
      label: context.tr('Pip Live'),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          // easeInOutSine rounds off the top and bottom of the swing, so at
          // low intensity (idle/listening) the breathing reads as slow and
          // soft rather than a linear metronome.
          final eased = Curves.easeInOutSine.transform(_animation.value);
          final pulse = eased * intensity;
          return SizedBox.square(
            key: const ValueKey('pip-live-orb'),
            dimension: 220,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _glow(200 + (pulse * 22), baseColor, 0.16 + (pulse * 0.12)),
                  _ring(178 + (pulse * 16), baseColor, 0.08 + (pulse * 0.10)),
                  _ring(138 + (pulse * 12), baseColor, 0.14 + (pulse * 0.12)),
                  _core(94 + (pulse * 10), baseColor, isError),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _glow(double size, Color color, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          color.withValues(alpha: opacity.clamp(0.0, 1.0)),
          color.withValues(alpha: 0),
        ],
      ),
    ),
  );

  Widget _ring(double size, Color color, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
        width: 1.5,
      ),
    ),
  );

  Widget _core(double size, Color color, bool isError) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.24),
          blurRadius: 30,
          spreadRadius: 4,
        ),
      ],
    ),
    child: Icon(
      isError ? Icons.mic_off : Icons.graphic_eq,
      color: Colors.white,
      size: 40,
    ),
  );
}
