import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_sizes.dart';
import '../core/theme/app_elevation.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final AppElevationLevel elevation;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.elevation = AppElevationLevel.level1,
    this.borderRadius,
    this.border,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final radius =
        borderRadius ?? BorderRadius.circular(AppSizes.cardRadius);
    final shadows = AppElevation.fromLevel(elevation);

    return Container(
      margin: margin ?? const EdgeInsets.all(AppSizes.cardMargin),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: radius,
        boxShadow: shadows,
        border: border,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                borderRadius: radius,
                child: Padding(
                  padding:
                      padding ?? const EdgeInsets.all(AppSizes.cardPadding),
                  child: child,
                ),
              )
            : Padding(
                padding:
                    padding ?? const EdgeInsets.all(AppSizes.cardPadding),
                child: child,
              ),
      ),
    );
  }
}