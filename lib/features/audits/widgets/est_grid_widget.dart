import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/calculation_utils.dart';
import '../models/est_grid_data.dart';
import 'photo_button.dart';

class EstGridWidget extends StatelessWidget {
  final Map<String, TextEditingController> controllers;
  final Map<String, FocusNode> focusNodes;
  final Map<String, String?> photos;
  final bool enabled;
  final String? highlightedKey;
  final bool showPhotoCapture;
  final Function(String key, String value) onValueChanged;
  final Function(String key, String path) onPhotoCaptured;

  /// Display label shown above the grid, e.g. 'Shell Temperature (°C) - Optimum: 19-21 °C'
  final String? title;

  /// Temperature zone evaluator. Defaults to EST (°F 100-101).
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
    required this.focusNodes,
    required this.photos,
    required this.enabled,
    this.highlightedKey,
    this.showPhotoCapture = true,
    required this.onValueChanged,
    required this.onPhotoCaptured,
    this.title,
    this.tempStatusFn,
    this.tempZoneFn,
    this.unitSuffix = '°F',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              title!,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: [
              _buildHeaderRow(),
              const SizedBox(height: 8),
              ...EstGridData.levels.map(
                (level) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildLevelRow(context, level),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        const SizedBox(width: 58),
        ...EstGridData.locations.map(
          (location) => Expanded(
            child: Center(
              child: Text(
                _title(location),
                style: AppTextStyles.caption.copyWith(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLevelRow(BuildContext context, String level) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            _title(level),
            style: AppTextStyles.caption.copyWith(
              color: Colors.grey[700],
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        ...EstGridData.locations.map((location) {
          final key = EstGridData.key(location, level);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _buildGridCell(context, key),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildGridCell(BuildContext context, String key) {
    final controller = controllers[key];
    final focusNode = focusNodes[key];
    final photo = photos[key];
    final hasValue = controller?.text.trim().isNotEmpty ?? false;

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

    final isHighlighted = highlightedKey == key;
    final numberField = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      style: AppTextStyles.body.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        hintText: '--',
        suffixText: unitSuffix,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        border: InputBorder.none,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
      ],
      textInputAction: _isLastKey(key)
          ? TextInputAction.done
          : TextInputAction.next,
      onSubmitted: (_) => _focusNext(context, key),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      onChanged: (value) => onValueChanged(key, value),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      constraints: BoxConstraints(minHeight: showPhotoCapture ? 52 : 82),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: isHighlighted
            ? AppColors.greenTab.withAlpha(42)
            : hasValue
            ? borderColor.withAlpha(14)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isHighlighted ? AppColors.greenTab : borderColor,
          width: isHighlighted ? 2.2 : (hasValue ? 1.5 : 1),
        ),
      ),
      child: showPhotoCapture
          ? Row(
              children: [
                Expanded(child: numberField),
                const SizedBox(width: 2),
                Tooltip(
                  message: hasValue && zoneLabel != null
                      ? zoneLabel
                      : 'Capture',
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PhotoButton(
                        photoPath: photo,
                        enabled: enabled,
                        size: 32,
                        onPhotoCaptured: (path) => onPhotoCaptured(key, path),
                      ),
                      if (hasValue)
                        Positioned(
                          right: 1,
                          bottom: 1,
                          child: Icon(statusIcon, color: borderColor, size: 12),
                        ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                numberField,
                if (photo != null && photo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _EvidenceThumbnail(path: photo),
                ],
              ],
            ),
    );
  }

  List<String> get _fieldOrder => EstGridData.scanKeys;

  bool _isLastKey(String key) => _fieldOrder.last == key;

  void _focusNext(BuildContext context, String key) {
    final index = _fieldOrder.indexOf(key);
    if (index == -1 || index == _fieldOrder.length - 1) {
      FocusScope.of(context).unfocus();
      return;
    }
    FocusScope.of(context).requestFocus(focusNodes[_fieldOrder[index + 1]]);
  }

  String _title(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}

class _EvidenceThumbnail extends StatelessWidget {
  const _EvidenceThumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Evidence photo',
      child: Container(
        width: 54,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[300]!),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey[200],
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  size: 16,
                  color: Colors.grey,
                ),
              ),
            ),
            Positioned(
              left: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(120),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.photo_library_outlined,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
