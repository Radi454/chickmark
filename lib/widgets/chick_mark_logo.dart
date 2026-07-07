import 'dart:math' as math;

import 'package:hatchaudit/localized_material.dart';

class ChickMarkLogo extends StatefulWidget {
  static const String assetPath = 'assets/branding/chickmark-icon.png';

  final double? logoSize;
  final bool showWordmark;
  final bool showTagline;
  final bool compact;
  final bool animated;

  const ChickMarkLogo({
    super.key,
    this.logoSize,
    this.showWordmark = true,
    this.showTagline = true,
    this.compact = false,
    this.animated = false,
  });

  @override
  State<ChickMarkLogo> createState() => _ChickMarkLogoState();
}

class _ChickMarkLogoState extends State<ChickMarkLogo>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant ChickMarkLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animated != widget.animated) {
      _syncController();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _syncController() {
    if (!widget.animated) {
      _controller?.dispose();
      _controller = null;
      return;
    }

    _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    final baseSize = widget.logoSize ?? 96.0;
    final width = widget.compact || !widget.showWordmark
        ? baseSize
        : baseSize * 2.55;
    final logo = Image.asset(
      ChickMarkLogo.assetPath,
      width: width,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      label: context.tr('ChickMark logo'),
      image: true,
      child: _controller == null || disableAnimations
          ? logo
          : _AnimatedChickMarkLogo(
              controller: _controller!,
              width: width,
              child: logo,
            ),
    );
  }
}

class _AnimatedChickMarkLogo extends StatelessWidget {
  final AnimationController controller;
  final double width;
  final Widget child;

  const _AnimatedChickMarkLogo({
    required this.controller,
    required this.width,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final cycle = controller.value * math.pi * 2;
        final bob = math.sin(cycle) * 2.2;
        final tilt = math.sin(cycle * 0.8) * 0.035;
        final bounce = 1 + (math.sin(cycle + math.pi / 2) * 0.012);
        final wink = _pulse(controller.value, 0.58, 0.72);

        return SizedBox(
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: Offset(0, bob),
                child: Transform.rotate(
                  angle: tilt,
                  child: Transform.scale(scale: bounce, child: child),
                ),
              ),
              Positioned(
                top: width * 0.42,
                right: width * 0.36,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: wink,
                    child: _WinkGlint(size: math.max(8, width * 0.07)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _pulse(double value, double start, double end) {
    if (value < start || value > end) return 0;
    final local = (value - start) / (end - start);
    return math.sin(local * math.pi).clamp(0, 1).toDouble();
  }
}

class _WinkGlint extends StatelessWidget {
  final double size;

  const _WinkGlint({required this.size});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.55,
      child: Container(
        width: size,
        height: math.max(3, size * 0.15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(size),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.65),
              blurRadius: size * 0.35,
            ),
          ],
        ),
      ),
    );
  }
}
