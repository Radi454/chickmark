import 'package:hatchaudit/localized_material.dart';
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../constants/app_strings.dart';
import '../navigation/shell_navigation_scope.dart';
import 'app_elevation.dart';

class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? titleLeading;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;

  /// When supplied, renders in place of the default `Text(title, ...)` —
  /// [title] is still required (used as the `Semantics`/window title source
  /// and as the fallback when this is null) but is not itself put on screen.
  ///
  /// This exists so a caller can show user/model content as the title (a
  /// conversation's derived name, say) without it passing through this app's
  /// localized `Text` wrapper, which runs every string through the Arabic UI
  /// phrasebook — fine for static labels, wrong for someone else's words.
  /// Build the widget with the app's raw `material.Text` in that case.
  final Widget? titleWidget;

  const GradientAppBar({
    super.key,
    required this.title,
    this.titleLeading,
    this.leading,
    this.actions,
    this.bottom,
    this.toolbarHeight = kToolbarHeight,
    this.titleWidget,
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
                    tooltip: context.tr(AppStrings.back),
                    icon: const Icon(Icons.arrow_back),
                    onPressed: canPop
                        ? () => Navigator.of(context).maybePop()
                        : shellNavigation?.goBack,
                  )
                : null) ??
            (showMenuButton
                ? IconButton(
                    tooltip: context.tr('Open navigation'),
                    icon: const Icon(Icons.menu),
                    onPressed: shellNavigation!.openDrawer,
                  )
                : null),
        title: titleLeading == null
            ? (titleWidget ??
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis))
            : Row(
                children: [
                  titleLeading!,
                  const SizedBox(width: AppSizes.spaceSm),
                  Expanded(
                    child:
                        titleWidget ??
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  ),
                ],
              ),
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
