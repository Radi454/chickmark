import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static const TextStyle heading = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 22,
    height: 1.18,
    color: AppColors.textPrimary,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 18,
    height: 1.25,
    color: AppColors.textPrimary,
  );
  static const TextStyle title = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 16,
    height: 1.3,
    color: AppColors.textPrimary,
  );
  static const TextStyle subtitle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 14,
    height: 1.3,
    color: AppColors.textSecondary,
  );
  static const TextStyle body = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 15,
    height: 1.4,
    color: AppColors.textBody,
  );
  static const TextStyle caption = TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 1.35,
    color: AppColors.textSecondary,
  );
  static const TextStyle badge = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 13,
    height: 1.2,
    color: AppColors.textOnPrimary,
  );
  static const TextStyle badgeLabel = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 12,
    height: 1.2,
    color: AppColors.textPrimary,
  );
  static const TextStyle metricLarge = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 28,
    height: 1.1,
    color: AppColors.textPrimary,
  );
  static const TextStyle wordmark = TextStyle(
    fontFamily: 'Georgia',
    fontWeight: FontWeight.w700,
    fontSize: 28,
    color: AppColors.textPrimary,
    letterSpacing: 2.0,
  );

  static TextTheme get textTheme => const TextTheme(
    displayLarge: TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 32,
      height: 1.12,
      color: AppColors.textPrimary,
    ),
    displayMedium: TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 28,
      height: 1.14,
      color: AppColors.textPrimary,
    ),
    displaySmall: TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 24,
      height: 1.18,
      color: AppColors.textPrimary,
    ),
    headlineLarge: TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 24,
      height: 1.2,
      color: AppColors.textPrimary,
    ),
    headlineMedium: heading,
    headlineSmall: sectionTitle,
    titleLarge: sectionTitle,
    titleMedium: title,
    titleSmall: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 14,
      height: 1.3,
      color: AppColors.textBody,
    ),
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: badge,
    labelMedium: TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 12,
      height: 1.2,
      color: AppColors.textPrimary,
    ),
    labelSmall: caption,
  );
}