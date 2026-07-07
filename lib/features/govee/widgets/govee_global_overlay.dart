import 'dart:math' as math;

import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import 'govee_floating_launcher.dart';

class GoveeGlobalOverlay extends StatefulWidget {
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
  State<GoveeGlobalOverlay> createState() => _GoveeGlobalOverlayState();
}

class _GoveeGlobalOverlayState extends State<GoveeGlobalOverlay> {
  static const double _launcherSize = 64;
  static const double _edgeMargin = 18;
  static const double _tuckedVisibleWidth = 22;
  static const double _tuckTriggerDistance = 18;
  static const double _tuckFlingVelocity = 600;
  static const Duration _settleDuration = Duration(milliseconds: 180);

  Offset? _launcherTopLeft;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.showLauncher) return widget.child;

    final launcherShape = widget.isRecording
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))
        : const CircleBorder();
    final launcherColor = widget.isRecording
        ? AppColors.statusError
        : AppColors.primary;
    final iconColor = widget.isRecording
        ? AppColors.statusErrorBg
        : AppColors.textOnPrimary;
    final icon = widget.isRecording
        ? Icons.stop_rounded
        : Icons.device_thermostat_outlined;

    return LayoutBuilder(
      builder: (context, constraints) {
        final overlaySize = Size(constraints.maxWidth, constraints.maxHeight);
        final safePadding = MediaQuery.paddingOf(context);
        final launcherTopLeft = _resolvedLauncherTopLeft(
          overlaySize,
          safePadding,
        );

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(child: widget.child),
            AnimatedPositioned(
              duration: _isDragging ? Duration.zero : _settleDuration,
              curve: Curves.easeOutCubic,
              left: launcherTopLeft.dx,
              top: launcherTopLeft.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => setState(() => _isDragging = true),
                onPanUpdate: (details) {
                  _moveLauncher(
                    delta: details.delta,
                    overlaySize: overlaySize,
                    safePadding: safePadding,
                  );
                },
                onPanCancel: () {
                  _settleLauncher(
                    velocity: Velocity.zero,
                    overlaySize: overlaySize,
                    safePadding: safePadding,
                  );
                },
                onPanEnd: (details) {
                  _settleLauncher(
                    velocity: details.velocity,
                    overlaySize: overlaySize,
                    safePadding: safePadding,
                  );
                },
                child: Semantics(
                  label: context.tr(
                    widget.isRecording
                        ? 'Govee recording in progress'
                        : 'Govee readings',
                  ),
                  button: true,
                  child: Material(
                    key: const ValueKey('govee-global-launcher'),
                    color: launcherColor,
                    elevation: 8,
                    shadowColor: widget.isRecording
                        ? const Color(0x47DC2626)
                        : const Color(0x47193FC2),
                    shape: launcherShape,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      canRequestFocus: false,
                      customBorder: launcherShape,
                      onTap: () => _openGoveePanel(context),
                      child: SizedBox.square(
                        dimension: _launcherSize,
                        child: Icon(icon, color: iconColor, size: 30),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openGoveePanel(BuildContext context) async {
    final panelContext = widget.panelContextBuilder() ?? context;
    await openGoveeFloatingCapturePanel(
      context,
      panelContext: panelContext,
    );
  }

  Offset _resolvedLauncherTopLeft(Size overlaySize, EdgeInsets safePadding) {
    final current =
        _launcherTopLeft ?? _defaultLauncherTopLeft(overlaySize, safePadding);
    final clamped = _clampLauncherTopLeft(
      current,
      overlaySize,
      safePadding,
      allowTucked: true,
    );
    _launcherTopLeft = clamped;
    return clamped;
  }

  void _moveLauncher({
    required Offset delta,
    required Size overlaySize,
    required EdgeInsets safePadding,
  }) {
    final current =
        _launcherTopLeft ?? _defaultLauncherTopLeft(overlaySize, safePadding);
    setState(() {
      _launcherTopLeft = _clampLauncherTopLeft(
        current + delta,
        overlaySize,
        safePadding,
        allowTucked: true,
      );
    });
  }

  void _settleLauncher({
    required Velocity velocity,
    required Size overlaySize,
    required EdgeInsets safePadding,
  }) {
    final current =
        _launcherTopLeft ?? _defaultLauncherTopLeft(overlaySize, safePadding);
    final visibleLeft = _visibleLeft(safePadding);
    final visibleRight = _visibleRight(overlaySize, safePadding);
    final flingX = velocity.pixelsPerSecond.dx;
    final tuckLeft =
        flingX <= -_tuckFlingVelocity ||
        current.dx <= visibleLeft - _tuckTriggerDistance;
    final tuckRight =
        flingX >= _tuckFlingVelocity ||
        current.dx >= visibleRight + _tuckTriggerDistance;
    final top = _clampTop(current.dy, overlaySize, safePadding);

    setState(() {
      _isDragging = false;
      if (tuckLeft) {
        _launcherTopLeft = Offset(_tuckedLeft(), top);
      } else if (tuckRight) {
        _launcherTopLeft = Offset(_tuckedRight(overlaySize), top);
      } else {
        _launcherTopLeft = _clampLauncherTopLeft(
          current,
          overlaySize,
          safePadding,
          allowTucked: false,
        );
      }
    });
  }

  Offset _defaultLauncherTopLeft(Size overlaySize, EdgeInsets safePadding) {
    return Offset(
      _visibleRight(overlaySize, safePadding),
      _visibleBottom(overlaySize, safePadding),
    );
  }

  Offset _clampLauncherTopLeft(
    Offset offset,
    Size overlaySize,
    EdgeInsets safePadding, {
    required bool allowTucked,
  }) {
    final minLeft = allowTucked ? _tuckedLeft() : _visibleLeft(safePadding);
    final maxLeft = allowTucked
        ? _tuckedRight(overlaySize)
        : _visibleRight(overlaySize, safePadding);

    return Offset(
      offset.dx.clamp(minLeft, maxLeft).toDouble(),
      _clampTop(offset.dy, overlaySize, safePadding),
    );
  }

  double _clampTop(double top, Size overlaySize, EdgeInsets safePadding) {
    return top
        .clamp(
          _visibleTop(safePadding),
          _visibleBottom(overlaySize, safePadding),
        )
        .toDouble();
  }

  double _visibleTop(EdgeInsets safePadding) {
    return safePadding.top + _edgeMargin;
  }

  double _visibleBottom(Size overlaySize, EdgeInsets safePadding) {
    return math.max(
      _visibleTop(safePadding),
      overlaySize.height - safePadding.bottom - _edgeMargin - _launcherSize,
    );
  }

  double _visibleLeft(EdgeInsets safePadding) {
    return safePadding.left + _edgeMargin;
  }

  double _visibleRight(Size overlaySize, EdgeInsets safePadding) {
    return math.max(
      _visibleLeft(safePadding),
      overlaySize.width - safePadding.right - _edgeMargin - _launcherSize,
    );
  }

  double _tuckedLeft() {
    return -(_launcherSize - _tuckedVisibleWidth);
  }

  double _tuckedRight(Size overlaySize) {
    return math.max(_tuckedVisibleWidth, overlaySize.width) -
        _tuckedVisibleWidth;
  }
}
