import 'package:hatchaudit/localized_material.dart';

import '../../../services/photo/photo_service.dart';
import 'temperature_capture_config.dart';
import 'temperature_capture_result.dart';
import 'temperature_capture_screen.dart';

/// Thin entry point each audit screen uses: push the reusable capture screen and
/// fan the returned result back through the caller's own per-cell save primitive.
class TemperatureCaptureLauncher {
  const TemperatureCaptureLauncher._();

  /// Open the full-screen flow; resolves to the dirty-only result, or null if
  /// the route was dismissed without one.
  static Future<TemperatureCaptureResult?> push(
    BuildContext context,
    TemperatureCaptureConfig config, {
    PhotoService? photoService,
  }) {
    return Navigator.of(context).push<TemperatureCaptureResult>(
      MaterialPageRoute(
        builder: (_) => TemperatureCaptureScreen(
          config: config,
          photoService: photoService,
        ),
      ),
    );
  }

  /// Invoke [saveOne] for every changed cell. Unit/PhotoModel/provider concerns
  /// stay in the caller's closure; this only loops. [photoPath] is '' when the
  /// user entered a value manually without a photo.
  static void apply(
    TemperatureCaptureResult result,
    void Function(String key, String photoPath, double value) saveOne,
  ) {
    for (final entry in result.readings.entries) {
      saveOne(entry.key, result.photos[entry.key] ?? '', entry.value);
    }
  }
}
