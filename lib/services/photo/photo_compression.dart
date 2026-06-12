import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Input for [resizeJpeg]. Kept as a single immutable value so the work can be
/// handed to a background isolate via `compute`.
@immutable
class JpegResizeJob {
  const JpegResizeJob(this.bytes, {this.maxEdge = 2000, this.quality = 90});

  final Uint8List bytes;

  /// Longest edge of the output in pixels. Images are only ever scaled down.
  final int maxEdge;

  /// JPEG encode quality (0–100).
  final int quality;
}

/// Decode [job.bytes], downscale so the longest edge is at most [job.maxEdge]
/// (aspect ratio preserved, never upscales), then re-encode as JPEG at
/// [job.quality].
///
/// Returns null if the bytes can't be decoded so callers can fall back to the
/// original file. Pure + top-level so it is safe to run under `compute`.
///
/// Downscaling uniformly is safe for the ThermoScan OCR crop: the crop maps
/// preview→image coordinates by a scale ratio, so the same physical region is
/// selected at any resolution as long as the aspect ratio is unchanged.
Uint8List? resizeJpeg(JpegResizeJob job) {
  // decodeImage sniffs the format and can THROW on corrupt/short input (not
  // just return null), so guard it to keep the null contract and stay safe
  // when run inside a `compute` isolate.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(job.bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;

  final longest =
      decoded.width > decoded.height ? decoded.width : decoded.height;
  final resized = longest > job.maxEdge
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? job.maxEdge : null,
          height: decoded.height > decoded.width ? job.maxEdge : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;

  return img.encodeJpg(resized, quality: job.quality);
}
