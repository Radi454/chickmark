import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../scope/scope_config.dart';

/// Hand-painted station glyphs ported 1:1 from the prototype dashboard's inline
/// SVGs (24×24 viewBox). One painter per station so each headline carries its
/// own recognizable symbol — egg+tray, chick, breakout chart, turning setter,
/// peeking hatcher.
class StationIcon extends StatelessWidget {
  final String station;
  final double size;

  const StationIcon({super.key, required this.station, this.size = 30});

  /// Govee isn't a scope station (it's its own dashboard section), but shares
  /// the same glyph-headline treatment via this key.
  static const String govee = 'Govee Environmental';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _painterFor(station)),
    );
  }

  static CustomPainter _painterFor(String station) {
    switch (station) {
      case ScopeConfigRegistry.stationStorage:
        return _EggStoragePainter();
      case ScopeConfigRegistry.stationChicks:
        return _ChickPainter();
      case ScopeConfigRegistry.stationHatch:
        return _BreakoutChartPainter();
      case ScopeConfigRegistry.stationSetters:
        return _SetterPainter();
      case ScopeConfigRegistry.stationHatchers:
        return _HatcherPainter();
      case govee:
        return _ThermoPainter();
      default:
        return _BreakoutChartPainter();
    }
  }

  /// Soft tint behind the glyph, keyed to the station's dominant hue so the
  /// headline reads as distinct at a glance.
  static Color bgFor(String station) {
    switch (station) {
      case ScopeConfigRegistry.stationStorage:
        return const Color(0xFFFBF3DF);
      case ScopeConfigRegistry.stationChicks:
        return const Color(0xFFFEF3C9);
      case ScopeConfigRegistry.stationHatch:
        return const Color(0xFFE8F2FF);
      case ScopeConfigRegistry.stationSetters:
        return const Color(0xFFFCEDED);
      case ScopeConfigRegistry.stationHatchers:
        return const Color(0xFFFFF1E0);
      case govee:
        return const Color(0xFFEEF2F7);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  /// One-line descriptor of what the station measures (mirrors the prototype's
  /// hero subtitle, generalized to the station's parameters).
  static String subtitleFor(String station) {
    switch (station) {
      case ScopeConfigRegistry.stationStorage:
        return 'Storage temps · EST · shell · turning · 9-point';
      case ScopeConfigRegistry.stationChicks:
        return 'Weights · Pasgar · CVT · YFBM';
      case ScopeConfigRegistry.stationHatch:
        return 'Hatchability · fertility · HOF · residue breakouts';
      case ScopeConfigRegistry.stationSetters:
        return 'Setpoint vs actual · EST · CO₂ · turning';
      case ScopeConfigRegistry.stationHatchers:
        return 'Setpoint · CVT · CO₂ · transfer window';
      case govee:
        return 'Continuous temp & RH · monitored places · 24h captures';
      default:
        return '';
    }
  }
}

/// Shared helpers for painting against a 24×24 design grid.
abstract class _GlyphPainter extends CustomPainter {
  double _u = 1; // px per design unit

  /// Scaled point on the 24-grid.
  Offset p(double x, double y) => Offset(x * _u, y * _u);

  /// Scaled scalar (stroke widths, radii).
  double s(double v) => v * _u;

  Paint fill(Color c) => Paint()
    ..style = PaintingStyle.fill
    ..color = c
    ..isAntiAlias = true;

  Paint stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..color = c
    ..strokeWidth = s(w)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    _u = size.shortestSide / 24.0;
    paintGlyph(canvas);
  }

  void paintGlyph(Canvas canvas);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Egg Storage & Handling — egg resting in a storage tray ────────────────
class _EggStoragePainter extends _GlyphPainter {
  @override
  void paintGlyph(Canvas canvas) {
    // egg
    final egg = Path()
      ..moveTo(p(12, 2.6).dx, p(12, 2.6).dy)
      ..cubicTo(p(8.7, 2.6).dx, p(8.7, 2.6).dy, p(6.6, 7.8).dx, p(6.6, 7.8).dy,
          p(6.6, 11.6).dx, p(6.6, 11.6).dy)
      ..cubicTo(p(6.6, 15.3).dx, p(6.6, 15.3).dy, p(9, 18.3).dx, p(9, 18.3).dy,
          p(12, 18.3).dx, p(12, 18.3).dy)
      ..cubicTo(p(15, 18.3).dx, p(15, 18.3).dy, p(17.4, 15.3).dx,
          p(17.4, 15.3).dy, p(17.4, 11.6).dx, p(17.4, 11.6).dy)
      ..cubicTo(p(17.4, 7.8).dx, p(17.4, 7.8).dy, p(15.3, 2.6).dx,
          p(15.3, 2.6).dy, p(12, 2.6).dx, p(12, 2.6).dy)
      ..close();
    canvas.drawPath(egg, fill(const Color(0xFFFFF8E8)));
    canvas.drawPath(egg, stroke(const Color(0xFFE0A94B), 1.2));

    // shine
    final shine = Path()
      ..moveTo(p(9.7, 12.6).dx, p(9.7, 12.6).dy)
      ..cubicTo(p(9.7, 10.0).dx, p(9.7, 10.0).dy, p(10.6, 7.4).dx,
          p(10.6, 7.4).dy, p(12, 5.8).dx, p(12, 5.8).dy);
    canvas.drawPath(shine, stroke(const Color(0xFFF3D286), 1.3));

    // storage tray (egg sits in front; tray drawn last to cradle it)
    final tray = RRect.fromLTRBAndCorners(
      p(2.6, 18.2).dx, p(2.6, 18.2).dy, p(21.4, 21.7).dx, p(21.4, 21.7).dy,
      topLeft: Radius.circular(s(1.4)),
      topRight: Radius.circular(s(1.4)),
      bottomLeft: Radius.circular(s(1.8)),
      bottomRight: Radius.circular(s(1.8)),
    );
    canvas.drawRRect(tray, fill(const Color(0xFFEAD9B0)));
    canvas.drawRRect(tray, stroke(const Color(0xFFC99A3E), 1.0));
  }
}

// ── Chicks — fluffy day-old chick ─────────────────────────────────────────
class _ChickPainter extends _GlyphPainter {
  @override
  void paintGlyph(Canvas canvas) {
    final feet = stroke(const Color(0xFFEF8A1C), 0.9);
    // left foot (3 toes)
    for (final t in [
      [9.4, 20.6],
      [10.5, 20.9],
      [11.4, 20.6],
    ]) {
      canvas.drawLine(p(10.4, 19.2), p(t[0], t[1]), feet);
    }
    // right foot
    for (final t in [
      [12.6, 20.6],
      [13.5, 20.9],
      [14.6, 20.6],
    ]) {
      canvas.drawLine(p(13.6, 19.2), p(t[0], t[1]), feet);
    }

    // body
    final body = Rect.fromCenter(
        center: p(12, 13.1), width: s(12.4), height: s(13.0));
    canvas.drawOval(body, fill(const Color(0xFFFFCE3A)));
    canvas.drawOval(body, stroke(const Color(0xFFEBA92E), 0.8));

    // wing
    final wing = Path()
      ..moveTo(p(17, 12.5).dx, p(17, 12.5).dy)
      ..cubicTo(p(16, 11.7).dx, p(16, 11.7).dy, p(14.7, 12.2).dx,
          p(14.7, 12.2).dy, p(14.6, 13.8).dx, p(14.6, 13.8).dy)
      ..cubicTo(p(15.9, 14.1).dx, p(15.9, 14.1).dy, p(16.9, 13.8).dx,
          p(16.9, 13.8).dy, p(17, 12.5).dx, p(17, 12.5).dy)
      ..close();
    canvas.drawPath(wing, fill(const Color(0xFFF4B62B)));

    // head tuft (two little quadratic plumes)
    final tuft = stroke(const Color(0xFFFFCE3A), 1.7);
    final t1 = Path()
      ..moveTo(p(10.3, 7.2).dx, p(10.3, 7.2).dy)
      ..quadraticBezierTo(p(11, 5.2).dx, p(11, 5.2).dy, p(11.9, 6.9).dx,
          p(11.9, 6.9).dy);
    final t2 = Path()
      ..moveTo(p(12.1, 6.9).dx, p(12.1, 6.9).dy)
      ..quadraticBezierTo(p(13, 5.4).dx, p(13, 5.4).dy, p(13.7, 7.3).dx,
          p(13.7, 7.3).dy);
    canvas.drawPath(t1, tuft);
    canvas.drawPath(t2, tuft);

    // eyes + shine
    canvas.drawCircle(p(9.9, 11.4), s(1.0), fill(const Color(0xFF2B2118)));
    canvas.drawCircle(p(14.1, 11.4), s(1.0), fill(const Color(0xFF2B2118)));
    canvas.drawCircle(p(10.25, 11.05), s(0.32), fill(Colors.white));
    canvas.drawCircle(p(14.45, 11.05), s(0.32), fill(Colors.white));

    // beak
    final beak = Path()
      ..moveTo(p(12, 12.5).dx, p(12, 12.5).dy)
      ..lineTo(p(13.35, 13.5).dx, p(13.35, 13.5).dy)
      ..lineTo(p(12, 14.45).dx, p(12, 14.45).dy)
      ..lineTo(p(10.65, 13.5).dx, p(10.65, 13.5).dy)
      ..close();
    canvas.drawPath(beak, fill(const Color(0xFFF39A1B)));

    // cheeks
    final cheek = fill(const Color(0xFFF79289))..color = const Color(0x8CF79289);
    canvas.drawCircle(p(8.5, 13.5), s(0.95), cheek);
    canvas.drawCircle(p(15.5, 13.5), s(0.95), cheek);
  }
}

// ── Hatch Analysis & Egg Breakouts — breakout bar chart ───────────────────
class _BreakoutChartPainter extends _GlyphPainter {
  @override
  void paintGlyph(Canvas canvas) {
    // baseline
    canvas.drawLine(
        p(3.5, 19.5), p(20.5, 19.5), stroke(const Color(0xFFB6C2D1), 1.2));

    void bar(double x, double top, Color c) {
      final r = RRect.fromLTRBAndCorners(
        p(x, top).dx, p(x, top).dy, p(x + 3.6, 19.5).dx, p(x + 3.6, 19.5).dy,
        topLeft: Radius.circular(s(0.9)),
        topRight: Radius.circular(s(0.9)),
      );
      canvas.drawRRect(r, fill(c));
    }

    bar(4.6, 12.5, const Color(0xFF1769D8));
    bar(10.2, 8.5, const Color(0xFF388E3C));
    bar(15.8, 5.0, const Color(0xFFE67E22));
  }
}

// ── Setters — egg with rotating turn arrows ───────────────────────────────
class _SetterPainter extends _GlyphPainter {
  @override
  void paintGlyph(Canvas canvas) {
    // egg
    final egg = Path()
      ..moveTo(p(12, 7.2).dx, p(12, 7.2).dy)
      ..cubicTo(p(9.6, 7.2).dx, p(9.6, 7.2).dy, p(8.1, 10.1).dx,
          p(8.1, 10.1).dy, p(8.1, 12.8).dx, p(8.1, 12.8).dy)
      ..cubicTo(p(8.1, 15.5).dx, p(8.1, 15.5).dy, p(9.85, 17.5).dx,
          p(9.85, 17.5).dy, p(12, 17.5).dx, p(12, 17.5).dy)
      ..cubicTo(p(14.15, 17.5).dx, p(14.15, 17.5).dy, p(15.9, 15.5).dx,
          p(15.9, 15.5).dy, p(15.9, 12.8).dx, p(15.9, 12.8).dy)
      ..cubicTo(p(15.9, 10.1).dx, p(15.9, 10.1).dy, p(14.4, 7.2).dx,
          p(14.4, 7.2).dy, p(12, 7.2).dx, p(12, 7.2).dy)
      ..close();
    canvas.drawPath(egg, fill(const Color(0xFFFFF3DA)));
    canvas.drawPath(egg, stroke(const Color(0xFFE0A94B), 1.1));

    // turn arrows (top sweeps right, bottom sweeps left)
    final arm = stroke(const Color(0xFFE11D2E), 1.6);
    final topArc = Path()
      ..moveTo(p(5.23, 9.94).dx, p(5.23, 9.94).dy)
      ..arcToPoint(p(18.77, 9.94),
          radius: Radius.circular(s(7.2)), clockwise: true);
    canvas.drawPath(topArc, arm);
    canvas.drawLine(p(18.77, 9.94), p(19.39, 7.62), arm);
    canvas.drawLine(p(18.77, 9.94), p(16.80, 8.56), arm);

    final botArc = Path()
      ..moveTo(p(18.77, 14.86).dx, p(18.77, 14.86).dy)
      ..arcToPoint(p(5.23, 14.86),
          radius: Radius.circular(s(7.2)), clockwise: true);
    canvas.drawPath(botArc, arm);
    canvas.drawLine(p(5.23, 14.86), p(4.61, 17.18), arm);
    canvas.drawLine(p(5.23, 14.86), p(7.20, 16.24), arm);
  }
}

// ── Hatchers — chick peeking from a cracked egg ───────────────────────────
class _HatcherPainter extends _GlyphPainter {
  @override
  void paintGlyph(Canvas canvas) {
    // chick head (behind the cracked shell)
    canvas.drawCircle(p(12, 11), s(3.0), fill(const Color(0xFFFFCE3A)));
    canvas.drawCircle(p(12, 11), s(3.0), stroke(const Color(0xFFEBA92E), 0.7));
    canvas.drawCircle(p(10.95, 10.7), s(0.55), fill(const Color(0xFF2B2118)));
    canvas.drawCircle(p(13.05, 10.7), s(0.55), fill(const Color(0xFF2B2118)));
    final beak = Path()
      ..moveTo(p(12, 11.4).dx, p(12, 11.4).dy)
      ..lineTo(p(13.0, 12.2).dx, p(13.0, 12.2).dy)
      ..lineTo(p(12, 13.0).dx, p(12, 13.0).dy)
      ..lineTo(p(11.0, 12.2).dx, p(11.0, 12.2).dy)
      ..close();
    canvas.drawPath(beak, fill(const Color(0xFFF39A1B)));

    // bottom shell (zigzag rim — chick peeks above it)
    final bottom = Path()
      ..moveTo(p(6.7, 13.4).dx, p(6.7, 13.4).dy)
      ..cubicTo(p(6.7, 17.2).dx, p(6.7, 17.2).dy, p(9.0, 19.8).dx,
          p(9.0, 19.8).dy, p(12, 19.8).dx, p(12, 19.8).dy)
      ..cubicTo(p(15, 19.8).dx, p(15, 19.8).dy, p(17.3, 17.2).dx,
          p(17.3, 17.2).dy, p(17.3, 13.4).dx, p(17.3, 13.4).dy)
      ..lineTo(p(15.5, 14.2).dx, p(15.5, 14.2).dy)
      ..lineTo(p(13.6, 13.1).dx, p(13.6, 13.1).dy)
      ..lineTo(p(11.8, 14.2).dx, p(11.8, 14.2).dy)
      ..lineTo(p(10.0, 13.1).dx, p(10.0, 13.1).dy)
      ..lineTo(p(8.5, 14.2).dx, p(8.5, 14.2).dy)
      ..close();
    canvas.drawPath(bottom, fill(const Color(0xFFFFF3DA)));
    canvas.drawPath(bottom, stroke(const Color(0xFFE0A94B), 1.1));

    // top shell cap (the lifted-off lid, tilted ~-10°)
    canvas.save();
    final pivot = p(12, 6.5);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(-10 * math.pi / 180);
    canvas.translate(-pivot.dx, -pivot.dy);
    final top = Path()
      ..moveTo(p(9.6, 8.0).dx, p(9.6, 8.0).dy)
      ..lineTo(p(10.9, 8.6).dx, p(10.9, 8.6).dy)
      ..lineTo(p(12.1, 7.9).dx, p(12.1, 7.9).dy)
      ..lineTo(p(13.3, 8.6).dx, p(13.3, 8.6).dy)
      ..lineTo(p(14.6, 8.0).dx, p(14.6, 8.0).dy)
      ..cubicTo(p(14.2, 6.0).dx, p(14.2, 6.0).dy, p(13.2, 4.7).dx,
          p(13.2, 4.7).dy, p(12, 4.7).dx, p(12, 4.7).dy)
      ..cubicTo(p(10.7, 4.7).dx, p(10.7, 4.7).dy, p(9.8, 6.0).dx, p(9.8, 6.0).dy,
          p(9.6, 8.0).dx, p(9.6, 8.0).dy)
      ..close();
    canvas.drawPath(top, fill(const Color(0xFFFFF8E8)));
    canvas.drawPath(top, stroke(const Color(0xFFE0A94B), 1.0));
    canvas.restore();
  }
}

// ── Govee Environmental — thermometer ─────────────────────────────────────
class _ThermoPainter extends _GlyphPainter {
  @override
  void paintGlyph(Canvas canvas) {
    // body
    final body = RRect.fromLTRBR(
      p(9, 2.5).dx, p(9, 2.5).dy, p(15, 17.3).dx, p(15, 17.3).dy,
      Radius.circular(s(3)),
    );
    canvas.drawRRect(body, fill(const Color(0xFFEEF2F7)));
    canvas.drawRRect(body, stroke(const Color(0xFF9CA3AF), 1.2));

    // scale ticks
    final tick = stroke(const Color(0xFFC2CAD6), 1.0);
    canvas.drawLine(p(14.6, 6), p(13.1, 6), tick);
    canvas.drawLine(p(14.6, 9), p(13.4, 9), tick);
    canvas.drawLine(p(14.6, 12), p(13.1, 12), tick);

    // mercury column + bulb
    final red = fill(const Color(0xFFE11D2E));
    final mercury = RRect.fromLTRBR(
      p(10.6, 6).dx, p(10.6, 6).dy, p(13.4, 16.8).dx, p(13.4, 16.8).dy,
      Radius.circular(s(1.4)),
    );
    canvas.drawRRect(mercury, red);
    canvas.drawCircle(p(12, 19), s(3.7), red);
  }
}
