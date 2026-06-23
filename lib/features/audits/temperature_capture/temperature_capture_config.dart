import '../../../core/utils/calculation_utils.dart';
import '../models/est_grid_data.dart';

/// Declarative input to the reusable [TemperatureCaptureScreen].
///
/// Each temperature site (egg storage EST, setter EST, hatcher/CVT) passes one
/// of these
/// to describe units, conversion, the grid's status/zone colouring, and the
/// already-entered values to pre-populate. The capture flow itself is
/// site-agnostic; everything that differs between sites lives here.
class TemperatureCaptureConfig {
  const TemperatureCaptureConfig({
    required this.title,
    this.cellKeys = EstGridData.scanKeys,
    this.unitSuffix = '°C',
    this.initialKey,
    this.initialReadings = const {},
    this.initialPhotos = const {},
    this.tempStatusFn,
    this.tempZoneFn,
    this.targetLabelBuilder,
    this.readOnly = false,
  });

  /// App-bar title, e.g. 'Eggshell Temperature'.
  final String title;

  /// Ordered cell keys. Today always [EstGridData.scanKeys] (the 9-point grid);
  /// kept configurable so a future flat-list measurement can reuse the flow.
  final List<String> cellKeys;

  /// Display unit suffix shown in the grid/card, '°C' or '°F'.
  final String unitSuffix;

  /// Optional cell to focus when opening from an existing grid cell.
  final String? initialKey;

  /// Existing readings to pre-populate (display unit). Not marked dirty.
  final Map<String, double> initialReadings;

  /// Existing photo paths to pre-populate. Not marked dirty.
  final Map<String, String> initialPhotos;

  /// Cell colour/zone evaluator. Defaults applied by [TemperatureCaptureScreen]'s grid.
  final TemperatureStatus Function(double)? tempStatusFn;
  final String Function(double)? tempZoneFn;

  /// Optional override for a cell's display label (else 'Front - Top' style).
  final String Function(String key)? targetLabelBuilder;

  /// When true the flow is view-only (no capture/edit).
  final bool readOnly;
}
