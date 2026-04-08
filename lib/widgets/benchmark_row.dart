import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class BenchmarkRow extends StatelessWidget {
  final String label;
  final double? value;
  final String unit;
  final double? benchmark;
  final bool higherIsBetter;

  const BenchmarkRow({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.benchmark,
    this.higherIsBetter = true,
  });

  String _flagColor() {
    if (value == null || benchmark == null) return 'none';
    final delta = value! - benchmark!;
    if (higherIsBetter) {
      if (delta >= 0) return 'green';
      if (delta >= -3) return 'amber';
      return 'red';
    } else {
      if (delta <= 0) return 'green';
      if (delta <= 3) return 'amber';
      return 'red';
    }
  }

  @override
  Widget build(BuildContext context) {
    final flag = _flagColor();
    Color flagColor;
    IconData flagIcon;
    switch (flag) {
      case 'green':
        flagColor = AppTheme.green;
        flagIcon = Icons.check_circle;
        break;
      case 'amber':
        flagColor = AppTheme.amber;
        flagIcon = Icons.warning_amber;
        break;
      case 'red':
        flagColor = AppTheme.red;
        flagIcon = Icons.cancel;
        break;
      default:
        flagColor = AppTheme.textSecondary;
        flagIcon = Icons.remove;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textPrimary)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value != null
                  ? '${value!.toStringAsFixed(1)}$unit'
                  : '—',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              benchmark != null
                  ? '${benchmark!.toStringAsFixed(1)}$unit'
                  : '—',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 32,
            child: Icon(flagIcon, color: flagColor, size: 20),
          ),
        ],
      ),
    );
  }
}

class BenchmarkRowHeader extends StatelessWidget {
  const BenchmarkRowHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: const [
          Expanded(
              flex: 3,
              child: Text('Parameter',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary))),
          Expanded(
              flex: 2,
              child: Text('Actual',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary))),
          Expanded(
              flex: 2,
              child: Text('Target',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary))),
          SizedBox(width: 32),
        ],
      ),
    );
  }
}
