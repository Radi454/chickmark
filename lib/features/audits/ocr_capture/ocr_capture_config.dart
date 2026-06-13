import '../../../core/utils/calculation_utils.dart';
import '../../../services/ocr/ocr_service.dart' show ThermoScanUnit;
import '../models/est_grid_data.dart';

/// Declarative input to the reusable [OcrCaptureScreen].
///
/// Each OCR site (egg storage EST, setter EST, hatcher/CVT) passes one of these
/// to describe units, conversion, the grid's status/zone colouring, and the
/// already-entered values to pre-populate. The capture flow itself is
/// site-agnostic; everything that differs between sites lives here.
class OcrCaptureConfig {
  const OcrCaptureConfig({
    required this.title,
    this.cellKeys = EstGridData.scanKeys,
    this.unitSuffix = '°C',
    this.convertCelsiusToFahrenheit = false,
    this.selectedUnit,
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

  /// When true, OCR's Celsius reading is converted to Fahrenheit for display +
  /// the returned result. OCR is ALWAYS Celsius in; conversion happens once, at
  /// the controller boundary.
  final bool convertCelsiusToFahrenheit;

  /// Unit selected by the user for this capture session. When omitted, legacy
  /// callers keep the previous Celsius-in / optional-Fahrenheit conversion.
  final ThermoScanUnit? selectedUnit;

  /// Existing readings to pre-populate (display unit). Not marked dirty.
  final Map<String, double> initialReadings;

  /// Existing photo paths to pre-populate. Not marked dirty.
  final Map<String, String> initialPhotos;

  /// Cell colour/zone evaluator. Defaults applied by [OcrCaptureScreen]'s grid.
  final TemperatureStatus Function(double)? tempStatusFn;
  final String Function(double)? tempZoneFn;

  /// Optional override for a cell's display label (else 'Front - Top' style).
  final String Function(String key)? targetLabelBuilder;

  /// When true the flow is view-only (no capture/edit).
  final bool readOnly;
}
