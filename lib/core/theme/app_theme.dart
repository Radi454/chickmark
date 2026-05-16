import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import 'app_text_styles.dart';

class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.primaryLight,
      surface: AppColors.surface,
      error: AppColors.statusError,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: AppTextStyles.textTheme,
      visualDensity: VisualDensity.standard,
      dividerColor: AppColors.divider,
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: AppSizes.dividerThickness,
        space: AppSizes.spaceLg,
      ),
      appBarTheme: const AppBarTheme(
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppSizes.cardRadius)),
        ),
        elevation: 0,
        shadowColor: AppColors.cardShadow,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.all(AppSizes.cardMargin),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.spaceLg,
            vertical: AppSizes.spaceMd,
          ),
          textStyle: AppTextStyles.badge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.spaceLg,
            vertical: AppSizes.spaceMd,
          ),
          textStyle: AppTextStyles.badge.copyWith(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTextStyles.badge.copyWith(color: AppColors.primary),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: AppTextStyles.caption,
        hintStyle: AppTextStyles.caption,
        floatingLabelStyle: AppTextStyles.caption.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceLg,
          vertical: AppSizes.spaceMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.inputRadius),
          borderSide: const BorderSide(color: AppColors.borderDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.inputRadius),
          borderSide: const BorderSide(color: AppColors.borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.inputRadius),
          borderSide: const BorderSide(
            color: AppColors.borderFocused,
            width: 1.5,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary,
        checkmarkColor: Colors.white,
        side: const BorderSide(color: AppColors.borderDefault),
        labelStyle: AppTextStyles.badgeLabel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.inactiveTab,
        selectedLabelStyle: AppTextStyles.caption.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: AppTextStyles.caption,
      ),
    );
  }
}
