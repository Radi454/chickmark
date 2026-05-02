import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import 'govee_floating_launcher.dart';

class GoveeGlobalOverlay extends StatefulWidget {
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
  State<GoveeGlobalOverlay> createState() => _GoveeGlobalOverlayState();
}

class _GoveeGlobalOverlayState extends State<GoveeGlobalOverlay> {
  static const double _launcherWidth = 64;
  static const double _launcherHeight = 64;
  static const double _edgePadding = 34;
  static const double _defaultBottomOffset = 96;
  static const double _dockHandleWidth = 38;
  static const double _dockHandleHeight = 72;
  static const double _dockThreshold = 42;

  bool _panelOpen = false;
  Offset? _launcherOffset;
  _DockSide? _dockSide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = MediaQuery.paddingOf(context);
        final overlaySize = Size(constraints.maxWidth, constraints.maxHeight);
        final offset = _resolvedOffset(overlaySize, padding);

        return Stack(
          children: [
            widget.child,
            if (widget.showLauncher && !_panelOpen)
              if (_dockSide == null)
                Positioned(
                  left: offset.dx,
                  top: offset.dy,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanUpdate: (details) =>
                        _moveLauncher(details.delta, overlaySize, padding),
                    onPanEnd: (_) => _settleLauncher(overlaySize, padding),
                    child: GoveeFloatingLauncher(
                      panelContextBuilder: widget.panelContextBuilder,
                      onPanelVisibilityChanged: _setPanelOpen,
                    ),
                  ),
                )
              else
                Positioned(
                  left: _dockSide == _DockSide.left ? 0 : null,
                  right: _dockSide == _DockSide.right ? 0 : null,
                  top: offset.dy + (_launcherHeight - _dockHandleHeight) / 2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pullLauncherBack(overlaySize, padding),
                    onHorizontalDragEnd: (_) =>
                        _pullLauncherBack(overlaySize, padding),
                    child: _GoveePullTab(side: _dockSide!),
                  ),
                ),
          ],
        );
      },
    );
  }

  void _setPanelOpen(bool isOpen) {
    if (_panelOpen == isOpen || !mounted) return;
    setState(() => _panelOpen = isOpen);
  }

  Offset _resolvedOffset(Size overlaySize, EdgeInsets padding) {
    return _clampOffset(
      _launcherOffset ??
          Offset(
            overlaySize.width - _launcherWidth - _edgePadding,
            overlaySize.height -
                padding.bottom -
                _launcherHeight -
                _defaultBottomOffset,
          ),
      overlaySize,
      padding,
      allowDockRange: _dockSide == null,
    );
  }

  Offset _clampOffset(
    Offset offset,
    Size overlaySize,
    EdgeInsets padding, {
    required bool allowDockRange,
  }) {
    final minTop = padding.top + _edgePadding;
    final rawMaxTop =
        overlaySize.height - padding.bottom - _launcherHeight - _edgePadding;
    final minLeft = allowDockRange ? -_launcherWidth + _dockHandleWidth : 0.0;
    final rawMaxLeft = allowDockRange
        ? overlaySize.width - _dockHandleWidth
        : overlaySize.width - _launcherWidth;
    final maxTop = rawMaxTop < minTop ? minTop : rawMaxTop;
    final maxLeft = rawMaxLeft < minLeft ? minLeft : rawMaxLeft;

    return Offset(
      offset.dx.clamp(minLeft, maxLeft).toDouble(),
      offset.dy.clamp(minTop, maxTop).toDouble(),
    );
  }

  void _moveLauncher(Offset delta, Size overlaySize, EdgeInsets padding) {
    setState(() {
      _dockSide = null;
      _launcherOffset = _clampOffset(
        _resolvedOffset(overlaySize, padding) + delta,
        overlaySize,
        padding,
        allowDockRange: true,
      );
    });
  }

  void _settleLauncher(Size overlaySize, EdgeInsets padding) {
    final offset = _resolvedOffset(overlaySize, padding);
    final shouldDockLeft = offset.dx <= _dockThreshold;
    final shouldDockRight =
        offset.dx + _launcherWidth >= overlaySize.width - _dockThreshold;

    setState(() {
      if (shouldDockLeft) {
        _dockSide = _DockSide.left;
        _launcherOffset = Offset(-_launcherWidth + _dockHandleWidth, offset.dy);
      } else if (shouldDockRight) {
        _dockSide = _DockSide.right;
        _launcherOffset = Offset(
          overlaySize.width - _dockHandleWidth,
          offset.dy,
        );
      } else {
        _dockSide = null;
        _launcherOffset = _clampOffset(
          offset,
          overlaySize,
          padding,
          allowDockRange: false,
        );
      }
    });
  }

  void _pullLauncherBack(Size overlaySize, EdgeInsets padding) {
    final side = _dockSide;
    if (side == null) return;

    setState(() {
      _dockSide = null;
      _launcherOffset = _clampOffset(
        Offset(
          side == _DockSide.left
              ? _edgePadding
              : overlaySize.width - _launcherWidth - _edgePadding,
          _resolvedOffset(overlaySize, padding).dy,
        ),
        overlaySize,
        padding,
        allowDockRange: false,
      );
    });
  }
}

enum _DockSide { left, right }

class _GoveePullTab extends StatelessWidget {
  final _DockSide side;

  const _GoveePullTab({required this.side});

  @override
  Widget build(BuildContext context) {
    final isLeft = side == _DockSide.left;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _GoveeGlobalOverlayState._dockHandleWidth,
        height: _GoveeGlobalOverlayState._dockHandleHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.horizontal(
            left: isLeft ? Radius.zero : const Radius.circular(24),
            right: isLeft ? const Radius.circular(24) : Radius.zero,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x240B2D5C),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          isLeft ? Icons.chevron_right : Icons.chevron_left,
          color: AppColors.primary,
          size: 30,
        ),
      ),
    );
  }
}
