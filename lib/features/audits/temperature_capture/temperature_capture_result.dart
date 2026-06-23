/// What [TemperatureCaptureScreen] returns to its caller via `Navigator.pop`.
///
/// Contains ONLY the cells the user added or changed during the session
/// (dirty-only) so the caller's per-cell save primitive runs the minimum number
/// of persistence writes. Values are in the caller's display unit.
class TemperatureCaptureResult {
  const TemperatureCaptureResult({
    required this.readings,
    required this.photos,
  });

  /// Changed cell key -> reading (display unit).
  final Map<String, double> readings;

  /// Changed cell key -> saved photo path. May omit a key present in [readings]
  /// when the user entered a value manually without a photo.
  final Map<String, String> photos;

  bool get isEmpty => readings.isEmpty && photos.isEmpty;
}
