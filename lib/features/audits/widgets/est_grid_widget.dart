import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/calculation_utils.dart';
import '../models/est_grid_data.dart';
import 'audit_numeric_keyboard.dart';
import 'photo_button.dart';

class EstGridWidget extends StatelessWidget {
  static const String _navigationGroup = 'est-grid';

  final Map<String, TextEditingController> controllers;
  final Map<String, FocusNode> focusNodes;
  final Map<String, String?> photos;
  final bool enabled;
  final String? highlightedKey;
  final bool showPhotoCapture;
  final Function(String key, String value) onValueChanged;
  final Function(String key, String path) onPhotoCaptured;
  final ValueChanged<String>? onMissingPhotoRequested;
  final ValueChanged<String>? onClearRequested;

  /// When non-null, tapping a cell reports its key (tap-to-select). Used by the
  /// full-screen capture flow; null on the inline audit-screen grids so
  /// taps keep focusing the field for manual entry (unchanged behaviour).
  final ValueChanged<String>? onCellSelected;

  /// Display label shown above the grid, e.g. 'Shell Temperature (°C) - Optimum: 19-21 °C'
  final String? title;

  /// Temperature zone evaluator. Defaults to EST (°F 100-101).
  /// Pass [CalculationUtils.shellTempStatus] for Egg °C grids.
  final TemperatureStatus Function(double)? tempStatusFn;

  /// Optional zone label builder. Defaults to [CalculationUtils.estZone].
  /// Pass [CalculationUtils.shellTempZone] for Egg °C grids.
  final String Function(double)? tempZoneFn;

  /// Unit suffix shown in each grid cell, e.g. '°C' or '°F'.
  final String unitSuffix;

  /// Compact density: shorter cells, no per-cell evidence thumbnail/add button.
  /// Used by the full-screen capture flow so the grid fits without scroll.
  final bool compact;

  /// Display-only cells render values and evidence photos without text fields.
  /// Tapping still works through [onCellSelected], so station grids can route
  /// edits into the full-screen photo-backed capture flow.
  final bool displayOnly;

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
    this.onMissingPhotoRequested,
    this.onClearRequested,
    this.onCellSelected,
    this.title,
    this.tempStatusFn,
    this.tempZoneFn,
    this.unitSuffix = '°F',
    this.compact = false,
    this.displayOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return AuditNumericKeyboardScope(
      child: Column(
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
            padding: EdgeInsets.all(compact ? 8 : 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                _buildHeaderRow(),
                SizedBox(height: compact ? 4 : 8),
                ...EstGridData.levels.map(
                  (level) => Padding(
                    padding: EdgeInsets.only(bottom: compact ? 4 : 8),
                    child: _buildLevelRow(context, level),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    final rowIndex = EstGridData.levels.indexOf(level);
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
        ...EstGridData.locations.asMap().entries.map((entry) {
          final location = entry.value;
          final key = EstGridData.key(location, level);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _buildGridCell(context, key, rowIndex, entry.key),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildGridCell(
    BuildContext context,
    String key,
    int rowIndex,
    int columnIndex,
  ) {
    final controller = controllers[key];
    final focusNode = focusNodes[key];
    final photo = photos[key];
    if (controller == null || focusNode == null) {
      return const SizedBox.shrink();
    }
    final hasValue = controller.text.trim().isNotEmpty;
    final hasPhoto = photo != null && photo.trim().isNotEmpty;

    final value = double.tryParse(controller.text);
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
    final valueText = controller.text.trim();
    final numberField = displayOnly
        ? _DisplayReading(value: valueText, unitSuffix: unitSuffix)
        : AuditNumericField(
            key: ValueKey('est-grid-input-$key'),
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            allowDecimal: true,
            maxDecimalPlaces: 1,
            navigationGroup: _navigationGroup,
            navigationRow: rowIndex,
            navigationColumn: columnIndex,
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
            onChanged: (value) => onValueChanged(key, value),
          );

    final canClear =
        !displayOnly &&
        enabled &&
        onClearRequested != null &&
        (hasValue || hasPhoto);
    final showEvidenceThumb = hasPhoto && (!showPhotoCapture || displayOnly);
    final showMissingPhotoAction =
        !displayOnly &&
        !compact &&
        !showPhotoCapture &&
        hasValue &&
        !hasPhoto &&
        onMissingPhotoRequested != null;

    final cell = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      constraints: BoxConstraints(
        minHeight: compact
            ? (showEvidenceThumb ? 76 : 40)
            : (showPhotoCapture ? 52 : 82),
      ),
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: compact ? 3 : 6),
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(top: canClear ? 8 : 0),
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
                              fieldKey: key,
                              onPhotoCaptured: (path) =>
                                  onPhotoCaptured(key, path),
                            ),
                            if (hasValue)
                              Positioned(
                                right: 1,
                                bottom: 1,
                                child: Icon(
                                  statusIcon,
                                  color: borderColor,
                                  size: 12,
                                ),
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
                      if (showEvidenceThumb) ...[
                        const SizedBox(height: 4),
                        _EvidenceThumbnail(path: photo, compact: compact),
                      ] else if (showMissingPhotoAction) ...[
                        const SizedBox(height: 4),
                        _AddEvidencePhotoButton(
                          enabled: enabled,
                          onPressed: () => onMissingPhotoRequested!(key),
                        ),
                      ],
                    ],
                  ),
          ),
          if (canClear)
            Positioned(
              top: -5,
              right: -5,
              child: _ClearEvidenceButton(
                onPressed: () => onClearRequested!(key),
              ),
            ),
        ],
      ),
    );

    if (onCellSelected == null) return cell;
    return GestureDetector(
      key: ValueKey('est-grid-cell-$key'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onCellSelected!(key),
      child: cell,
    );
  }

  String _title(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}

class _DisplayReading extends StatelessWidget {
  const _DisplayReading({required this.value, required this.unitSuffix});

  final String value;
  final String unitSuffix;

  @override
  Widget build(BuildContext context) {
    final hasValue = value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        hasValue ? '$value$unitSuffix' : '--',
        textAlign: TextAlign.center,
        style: AppTextStyles.body.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: hasValue ? Colors.black87 : Colors.grey[500],
        ),
      ),
    );
  }
}

class _ClearEvidenceButton extends StatelessWidget {
  const _ClearEvidenceButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Clear reading and photo',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.red.withAlpha(90)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(18),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: const Icon(Icons.close, size: 14, color: Colors.red),
        ),
      ),
    );
  }
}

class _AddEvidencePhotoButton extends StatelessWidget {
  const _AddEvidencePhotoButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Add evidence photo',
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 54,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[300]!),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.add_photo_alternate_outlined,
            size: 16,
            color: enabled ? Colors.grey[700] : Colors.grey,
          ),
        ),
      ),
    );
  }
}

class _EvidenceThumbnail extends StatelessWidget {
  const _EvidenceThumbnail({required this.path, this.compact = false});

  final String path;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 62.0 : 54.0;
    final height = compact ? 34.0 : 30.0;
    return Tooltip(
      message: 'Evidence photo',
      child: Container(
        width: width,
        height: height,
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
              cacheWidth: 120,
              cacheHeight: 80,
              filterQuality: FilterQuality.low,
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
