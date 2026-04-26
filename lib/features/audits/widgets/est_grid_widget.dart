import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../core/theme/app_text_styles.dart';
import 'photo_button.dart';

class EstGridWidget extends StatelessWidget {
  final Map<String, TextEditingController> controllers;
  final Map<String, String?> photos;
  final bool enabled;
  final Function(String key, String value) onValueChanged;
  final Function(String key, String path) onPhotoCaptured;

  /// Display label shown above the grid, e.g. 'Shell Temperature (°C) – Optimum: 19–21 °C'
  final String? title;

  /// Temperature zone evaluator. Defaults to EST (°F 100–101).
  /// Pass [CalculationUtils.shellTempStatus] for Egg Storage °C grids.
  final TemperatureStatus Function(double)? tempStatusFn;

  /// Optional zone label builder. Defaults to [CalculationUtils.estZone].
  /// Pass [CalculationUtils.shellTempZone] for Egg Storage °C grids.
  final String Function(double)? tempZoneFn;

  /// Unit suffix shown in each grid cell, e.g. '°C' or '°F'.
  final String unitSuffix;

  const EstGridWidget({
    super.key,
    required this.controllers,
    required this.photos,
    required this.enabled,
    required this.onValueChanged,
    required this.onPhotoCaptured,
    this.title,
    this.tempStatusFn,
    this.tempZoneFn,
    this.unitSuffix = '°F',
  });

  @override
  Widget build(BuildContext context) {
    final rows = ['Door', 'Middle', 'Back'];
    final cols = ['Top', 'Middle', 'Bottom'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title!, style: AppTextStyles.body),
          ),
        Row(
          children: [
            const SizedBox(width: 60),
            ...cols.map(
              (col) => Expanded(
                child: Center(
                  child: Text(
                    col,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...rows.map((row) => _buildGridRow(row, cols)),
      ],
    );
  }

  Widget _buildGridRow(String row, List<String> cols) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              row,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          ...cols.map((col) {
            final key = '${row.toLowerCase()}_${col.toLowerCase()}';
            return Expanded(child: _buildGridCell(key));
          }),
        ],
      ),
    );
  }

  Widget _buildGridCell(String key) {
    final controller = controllers[key];
    final photo = photos[key];
    final hasValue = controller?.text.isNotEmpty ?? false;

    final value = double.tryParse(controller?.text ?? '');
    final statusFn = tempStatusFn ?? CalculationUtils.estStatus;
    final zoneFn = tempZoneFn ?? CalculationUtils.estZone;
    TemperatureStatus? status;
    String? zoneLabel;
    if (value != null) {
      status = statusFn(value);
      zoneLabel = zoneFn(value);
    }

    final borderColor = status == null
        ? Colors.grey[300]!
        : status == TemperatureStatus.optimal
        ? AppColors.greenTab
        : (status == TemperatureStatus.high ? Colors.red : Colors.orange);
    final statusIcon = status == null
        ? Icons.circle_outlined
        : status == TemperatureStatus.optimal
        ? Icons.check_circle
        : (status == TemperatureStatus.high ? Icons.error : Icons.warning);
    final bgColor = hasValue && status == TemperatureStatus.optimal
        ? AppColors.completedBg
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          border: Border.all(color: borderColor, width: hasValue ? 2 : 1),
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: status == TemperatureStatus.optimal
                    ? AppColors.completedText
                    : status == TemperatureStatus.high
                    ? Colors.red
                    : status == TemperatureStatus.low
                    ? Colors.orange
                    : Colors.transparent,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppSizes.cardRadius - 1),
                  topRight: Radius.circular(AppSizes.cardRadius - 1),
                ),
              ),
              child: Icon(
                statusIcon,
                color: status == null ? Colors.grey : Colors.white,
                size: 16,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: TextField(
                controller: controller,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ).copyWith(suffixText: unitSuffix),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                ],
                onChanged: (value) => onValueChanged(key, value),
              ),
            ),
            if (zoneLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  zoneLabel,
                  style: AppTextStyles.caption.copyWith(
                    color: borderColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PhotoButton(
                photoPath: photo,
                enabled: enabled,
                onPhotoCaptured: (path) => onPhotoCaptured(key, path),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
