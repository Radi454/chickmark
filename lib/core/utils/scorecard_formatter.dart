import 'package:flutter/material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';

/// Formatting helpers for scorecard states and benchmark wording.
class ScorecardFormatter {
  static const _green = AppColors.statusGood;
  static const _amber = AppColors.statusWarning;
  static const _red = AppColors.statusError;
  static const _unknown = AppColors.statusNeutralText;

  static Color statusColor(String status) {
    switch (status) {
      case 'green':
        return _green;
      case 'amber':
        return _amber;
      case 'red':
        return _red;
      default:
        return _unknown;
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'green':
        return 'Good';
      case 'amber':
        return 'Review';
      case 'red':
        return 'Alert';
      default:
        return 'Pending';
    }
  }

  static String statusEmoji(String status) {
    switch (status) {
      case 'green':
        return '✓';
      case 'amber':
        return '◆';
      case 'red':
        return '!';
      default:
        return '○';
    }
  }

  static Color benchmarkColor(String state) {
    switch (state) {
      case 'OK':
        return _green;
      case 'Medium':
        return _amber;
      case 'High':
        return _red;
      default:
        return _unknown;
    }
  }

  static String benchmarkLabel(String state) {
    switch (state) {
      case 'OK':
        return 'On target';
      case 'Medium':
        return 'Above target';
      case 'High':
        return 'Well above target';
      default:
        return 'Unknown';
    }
  }

  /// Returns a compact severity chip label for dashboard use.
  static String severityChip(String severity) {
    switch (severity) {
      case 'green':
        return 'Good';
      case 'amber':
        return 'Caution';
      case 'red':
        return 'Critical';
      default:
        return 'Pending';
    }
  }

  /// Formats a station completion count into a readable fraction.
  static String completionLabel(int completed, int total) {
    return '$completed / $total stations';
  }
}
