import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../navigation/shell_navigation_scope.dart';
import 'app_elevation.dart';

class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;

  const GradientAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.toolbarHeight = kToolbarHeight,
  });

  @override
  Widget build(BuildContext context) {
    final shellNavigation = ShellNavigationScope.maybeOf(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final showBackButton =
        leading == null && (canPop || (shellNavigation?.canGoBack ?? false));
    final showMenuButton =
        leading == null &&
        !showBackButton &&
        (shellNavigation?.hasDrawer ?? false);

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppSizes.cardRadius),
        ),
        boxShadow: AppElevation.level3,
      ),
      child: AppBar(
        automaticallyImplyLeading: false,
        leading:
            leading ??
            (showBackButton
                ? IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: canPop
                        ? () => Navigator.of(context).maybePop()
                        : shellNavigation?.goBack,
                  )
                : null) ??
            (showMenuButton
                ? IconButton(
                    tooltip: 'Open navigation',
                    icon: const Icon(Icons.menu),
                    onPressed: shellNavigation!.openDrawer,
                  )
                : null),
        title: Text(title),
        centerTitle: true,
        toolbarHeight: toolbarHeight,
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: actions,
        bottom: bottom,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));
}
