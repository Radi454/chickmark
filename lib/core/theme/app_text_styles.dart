import 'package:hatchaudit/localized_material.dart';
import '../constants/app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static const List<String> fontFallback = ['Arial', 'Noto Sans Arabic'];

  static const TextStyle heading = TextStyle(
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 1.2,
    color: AppColors.textPrimary,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w700,
    fontSize: 17,
    height: 1.25,
    color: AppColors.textPrimary,
  );
  static const TextStyle title = TextStyle(
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    height: 1.3,
    color: AppColors.textPrimary,
  );
  static const TextStyle subtitle = TextStyle(
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w600,
    fontSize: 13,
    height: 1.3,
    color: AppColors.textSecondary,
  );
  static const TextStyle body = TextStyle(
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 1.4,
    color: AppColors.textBody,
  );
  static const TextStyle caption = TextStyle(
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 1.35,
    color: AppColors.textSecondary,
  );
  static const TextStyle badge = TextStyle(
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    height: 1.2,
    color: AppColors.textOnPrimary,
  );
  static const TextStyle badgeLabel = TextStyle(
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    height: 1.2,
    color: AppColors.textPrimary,
  );
  static const TextStyle metricLarge = TextStyle(
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w700,
    fontSize: 24,
    height: 1.1,
    color: AppColors.textPrimary,
  );
  static const TextStyle wordmark = TextStyle(
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w700,
    fontSize: 24,
    color: AppColors.textPrimary,
    letterSpacing: 0,
  );

  static TextTheme get textTheme => const TextTheme(
    displayLarge: TextStyle(
      fontFamilyFallback: fontFallback,
      fontWeight: FontWeight.w700,
      fontSize: 28,
      height: 1.12,
      color: AppColors.textPrimary,
    ),
    displayMedium: TextStyle(
      fontFamilyFallback: fontFallback,
      fontWeight: FontWeight.w700,
      fontSize: 24,
      height: 1.14,
      color: AppColors.textPrimary,
    ),
    displaySmall: TextStyle(
      fontFamilyFallback: fontFallback,
      fontWeight: FontWeight.w700,
      fontSize: 22,
      height: 1.18,
      color: AppColors.textPrimary,
    ),
    headlineLarge: TextStyle(
      fontFamilyFallback: fontFallback,
      fontWeight: FontWeight.w700,
      fontSize: 22,
      height: 1.2,
      color: AppColors.textPrimary,
    ),
    headlineMedium: heading,
    headlineSmall: sectionTitle,
    titleLarge: sectionTitle,
    titleMedium: title,
    titleSmall: TextStyle(
      fontFamilyFallback: fontFallback,
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
      fontFamilyFallback: fontFallback,
      fontWeight: FontWeight.w700,
      fontSize: 12,
      height: 1.2,
      color: AppColors.textPrimary,
    ),
    labelSmall: caption,
  );
}
