import 'package:flutter/material.dart';

class AppTextStyles {
  static const TextStyle heading = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 24,
    color: Colors.black,
  );
  static const TextStyle body = TextStyle(
    fontWeight: FontWeight.normal,
    fontSize: 16,
    color: Colors.black,
  );
  static const TextStyle caption = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    color: Colors.grey,
  );
  static const TextStyle badge = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 14,
    color: Colors.white,
  );
  static const TextStyle wordmark = TextStyle(
    fontFamily: 'Georgia',
    fontWeight: FontWeight.bold,
    fontSize: 28,
    color: Colors.black,
    letterSpacing: 2.0,
  );

  static TextTheme get textTheme => const TextTheme(
    displayLarge: heading,
    displayMedium: heading,
    displaySmall: heading,
    headlineLarge: heading,
    headlineMedium: heading,
    headlineSmall: heading,
    titleLarge: heading,
    titleMedium: body,
    titleSmall: body,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: badge,
    labelMedium: badge,
    labelSmall: caption,
  );
}
