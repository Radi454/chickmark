import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';

enum AppElevationLevel { none, level1, level2, level3 }

class AppElevation {
  AppElevation._();

  static List<BoxShadow> fromLevel(AppElevationLevel level) {
    return switch (level) {
      AppElevationLevel.none => none,
      AppElevationLevel.level1 => level1,
      AppElevationLevel.level2 => level2,
      AppElevationLevel.level3 => level3,
    };
  }

  static List<BoxShadow> get none => [];

  static List<BoxShadow> get level1 => [
    BoxShadow(
      color: const Color(0x0A000000),
      blurRadius: AppSizes.spaceMd,
      offset: const Offset(0, 3),
    ),
  ];

  static List<BoxShadow> get level2 => [
    BoxShadow(
      color: const Color(0x14000000),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get level3 => [
    BoxShadow(
      color: const Color(0x14000000),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}
