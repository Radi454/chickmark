import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

enum EggCountOcrConfidence { none, low, medium, high }

class EggCountOcrResult {
  const EggCountOcrResult({
    this.count,
    this.confidence = EggCountOcrConfidence.none,
    this.confidenceScore = 0,
    this.componentCount = 0,
    this.hint,
  });

  final int? count;
  final EggCountOcrConfidence confidence;
  final double confidenceScore;
  final int componentCount;
  final String? hint;
}

class EggCountOcrService {
  const EggCountOcrService();

  Future<EggCountOcrResult> analyzeEggCount(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final source = image.decodeImage(bytes);
      if (source == null) {
        return const EggCountOcrResult(hint: 'Could not read image.');
      }
      return estimateEggCount(source);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Egg count OCR failed for $imagePath: $error');
      }
      return const EggCountOcrResult(hint: 'Could not count eggs.');
    }
  }

  @visibleForTesting
  EggCountOcrResult estimateEggCount(image.Image source) {
    final working = _resizeForAnalysis(source);
    final width = working.width;
    final height = working.height;
    final area = width * height;
    final mask = List<bool>.filled(area, false);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = working.getPixel(x, y);
        if (_isLikelyEggPixel(p.r.toInt(), p.g.toInt(), p.b.toInt())) {
          mask[y * width + x] = true;
        }
      }
    }

    final cleaned = _closeMask(_openMask(mask, width, height), width, height);
    final components = _connectedComponents(cleaned, width, height);
    if (components.isEmpty) {
      return const EggCountOcrResult(
        hint: 'No eggs detected. Capture again or enter manually.',
      );
    }

    final typicalArea = _typicalEggArea(components);
    var count = 0;
    for (final component in components) {
      final byArea = typicalArea == null ? 1 : component.area / typicalArea;
      final elongated =
          math.max(component.width, component.height) /
          math.max(1, math.min(component.width, component.height));
      final extra = byArea >= 1.65 || elongated >= 2.15
          ? byArea.round().clamp(1, 8)
          : 1;
      count += extra;
    }

    final score = (components.length / math.max(1, count)).clamp(0.35, 1.0);
    final confidence = score >= 0.78
        ? EggCountOcrConfidence.high
        : score >= 0.55
        ? EggCountOcrConfidence.medium
        : EggCountOcrConfidence.low;
    return EggCountOcrResult(
      count: count,
      confidence: confidence,
      confidenceScore: score.toDouble(),
      componentCount: components.length,
    );
  }

  image.Image _resizeForAnalysis(image.Image source) {
    const maxSide = 900;
    final longest = math.max(source.width, source.height);
    if (longest <= maxSide) return source;
    final scale = maxSide / longest;
    return image.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: image.Interpolation.average,
    );
  }

  bool _isLikelyEggPixel(int r, int g, int b) {
    final maxChannel = math.max(r, math.max(g, b));
    final minChannel = math.min(r, math.min(g, b));
    final saturation = maxChannel == 0
        ? 0.0
        : (maxChannel - minChannel) / maxChannel;
    final hue = _hueDegrees(r, g, b);

    final yellowInterior =
        maxChannel >= 95 &&
        saturation >= 0.18 &&
        hue >= 12 &&
        hue <= 72 &&
        r >= g - 28 &&
        g >= b + 12;
    final creamShell =
        maxChannel >= 145 &&
        saturation >= 0.045 &&
        hue >= 22 &&
        hue <= 68 &&
        r >= b + 12 &&
        g >= b + 8;
    return yellowInterior || creamShell;
  }

  double _hueDegrees(int r, int g, int b) {
    final rf = r / 255.0;
    final gf = g / 255.0;
    final bf = b / 255.0;
    final maxValue = math.max(rf, math.max(gf, bf));
    final minValue = math.min(rf, math.min(gf, bf));
    final delta = maxValue - minValue;
    if (delta == 0) return 0;
    final hue = maxValue == rf
        ? 60 * (((gf - bf) / delta) % 6)
        : maxValue == gf
        ? 60 * (((bf - rf) / delta) + 2)
        : 60 * (((rf - gf) / delta) + 4);
    return hue < 0 ? hue + 360 : hue;
  }

  List<bool> _openMask(List<bool> source, int width, int height) {
    return _dilate(_erode(source, width, height), width, height);
  }

  List<bool> _closeMask(List<bool> source, int width, int height) {
    return _erode(_dilate(source, width, height), width, height);
  }

  List<bool> _erode(List<bool> source, int width, int height) {
    final next = List<bool>.filled(source.length, false);
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        var keep = true;
        for (var dy = -1; dy <= 1 && keep; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (!source[(y + dy) * width + x + dx]) {
              keep = false;
              break;
            }
          }
        }
        next[y * width + x] = keep;
      }
    }
    return next;
  }

  List<bool> _dilate(List<bool> source, int width, int height) {
    final next = List<bool>.filled(source.length, false);
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        if (!source[y * width + x]) continue;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            next[(y + dy) * width + x + dx] = true;
          }
        }
      }
    }
    return next;
  }

  List<_EggComponent> _connectedComponents(
    List<bool> mask,
    int width,
    int height,
  ) {
    final visited = List<bool>.filled(mask.length, false);
    final components = <_EggComponent>[];
    final minArea = math.max(120, (width * height * 0.0012).round());
    final queue = <int>[];

    for (var i = 0; i < mask.length; i++) {
      if (!mask[i] || visited[i]) continue;
      queue
        ..clear()
        ..add(i);
      visited[i] = true;
      var cursor = 0;
      var count = 0;
      var minX = width;
      var maxX = 0;
      var minY = height;
      var maxY = 0;

      while (cursor < queue.length) {
        final current = queue[cursor++];
        final x = current % width;
        final y = current ~/ width;
        count++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;

        void visit(int next) {
          if (next < 0 || next >= mask.length) return;
          if (!mask[next] || visited[next]) return;
          visited[next] = true;
          queue.add(next);
        }

        if (x > 0) visit(current - 1);
        if (x < width - 1) visit(current + 1);
        if (y > 0) visit(current - width);
        if (y < height - 1) visit(current + width);
      }

      final component = _EggComponent(
        area: count,
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
      );
      if (component.area >= minArea &&
          component.width >= 16 &&
          component.height >= 16) {
        components.add(component);
      }
    }

    return components;
  }

  double? _typicalEggArea(List<_EggComponent> components) {
    if (components.isEmpty) return null;
    final areas = components.map((c) => c.area).toList()..sort();
    return areas[areas.length ~/ 2].toDouble();
  }
}

class _EggComponent {
  const _EggComponent({
    required this.area,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final int area;
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;

  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;
}
