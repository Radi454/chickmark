import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

class ChickMarkLogo extends StatelessWidget {
  final double? logoSize;
  final bool showWordmark;
  final bool showTagline;
  final bool compact;

  const ChickMarkLogo({
    super.key,
    this.logoSize,
    this.showWordmark = true,
    this.showTagline = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = logoSize ?? 80.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLogo(size),
        if (!compact && showWordmark) ...[
          const SizedBox(height: 8),
          _buildWordmark(),
        ],
        if (!compact && showTagline) ...[
          const SizedBox(height: 4),
          _buildTagline(),
        ],
      ],
    );
  }

  Widget _buildLogo(double size) {
    return CustomPaint(
      size: Size(size, size * 1.2),
      painter: ChickMarkPainter(),
    );
  }

  Widget _buildWordmark() {
    return Text(
      'CHICKMARK',
      style: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        letterSpacing: 2.0,
      ),
    );
  }

  Widget _buildTagline() {
    return Text(
      'HATCHERY AUDIT',
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey[600],
        letterSpacing: 1.5,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class ChickMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final centerX = size.width / 2;
    final centerY = size.height * 0.55;
    final eggWidth = size.width * 0.5;
    final eggHeight = size.height * 0.55;

    final eggRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: eggWidth,
      height: eggHeight,
    );

    canvas.drawOval(eggRect, paint);

    final checkPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.04
      ..strokeCap = StrokeCap.round;

    final checkStart = Offset(centerX - eggWidth * 0.15, centerY);
    final checkMid = Offset(
      centerX - eggWidth * 0.02,
      centerY + eggHeight * 0.15,
    );
    final checkEnd = Offset(
      centerX + eggWidth * 0.2,
      centerY - eggHeight * 0.15,
    );

    final checkPath = Path()
      ..moveTo(checkStart.dx, checkStart.dy)
      ..lineTo(checkMid.dx, checkMid.dy)
      ..lineTo(checkEnd.dx, checkEnd.dy);

    canvas.drawPath(checkPath, checkPaint);

    final headCenter = Offset(
      centerX + eggWidth * 0.25,
      centerY - eggHeight * 0.45,
    );
    final headRadius = size.width * 0.12;

    final headPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(headCenter, headRadius, headPaint);

    final eyePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;

    final eyeOffset = Offset(
      headCenter.dx + headRadius * 0.3,
      headCenter.dy - headRadius * 0.2,
    );
    canvas.drawCircle(eyeOffset, size.width * 0.015, eyePaint);

    final beakPath = Path()
      ..moveTo(
        headCenter.dx + headRadius * 0.5,
        headCenter.dy - headRadius * 0.1,
      )
      ..lineTo(headCenter.dx + headRadius * 0.8, headCenter.dy)
      ..lineTo(
        headCenter.dx + headRadius * 0.5,
        headCenter.dy + headRadius * 0.1,
      );

    canvas.drawPath(beakPath, headPaint);

    final combStart = Offset(
      headCenter.dx - headRadius * 0.5,
      headCenter.dy - headRadius,
    );
    for (var i = 0; i < 3; i++) {
      final arcPath = Path()
        ..moveTo(combStart.dx + i * headRadius * 0.4, combStart.dy)
        ..quadraticBezierTo(
          combStart.dx + i * headRadius * 0.4 + headRadius * 0.1,
          combStart.dy - headRadius * 0.3,
          combStart.dx + i * headRadius * 0.4 + headRadius * 0.2,
          combStart.dy - headRadius * 0.1,
        );
      canvas.drawPath(arcPath, headPaint);
    }

    final wingStart = Offset(
      headCenter.dx - headRadius * 0.3,
      headCenter.dy + headRadius * 0.3,
    );
    final wingPath = Path()
      ..moveTo(wingStart.dx, wingStart.dy)
      ..quadraticBezierTo(
        wingStart.dx - headRadius * 0.5,
        wingStart.dy + headRadius * 0.3,
        wingStart.dx - headRadius * 0.4,
        wingStart.dy + headRadius * 0.5,
      );
    canvas.drawPath(wingPath, headPaint);

    for (var i = 0; i < 3; i++) {
      final featherY = wingStart.dy + headRadius * 0.1 + i * headRadius * 0.15;
      canvas.drawLine(
        Offset(wingStart.dx - headRadius * 0.2, featherY),
        Offset(wingStart.dx - headRadius * 0.5, featherY + headRadius * 0.1),
        headPaint,
      );
    }

    final tailStart = Offset(
      centerX - eggWidth * 0.3,
      centerY - eggHeight * 0.2,
    );
    for (var i = 0; i < 3; i++) {
      final tailPath = Path()
        ..moveTo(tailStart.dx, tailStart.dy)
        ..quadraticBezierTo(
          tailStart.dx - eggWidth * 0.2 - i * eggWidth * 0.08,
          tailStart.dy - eggHeight * 0.15 - i * eggHeight * 0.05,
          tailStart.dx - eggWidth * 0.3 - i * eggWidth * 0.08,
          tailStart.dy - eggHeight * 0.25 - i * eggHeight * 0.05,
        );
      canvas.drawPath(tailPath, headPaint);
    }

    final legStart1 = Offset(
      centerX - eggWidth * 0.15,
      centerY + eggHeight * 0.45,
    );
    final legStart2 = Offset(
      centerX + eggWidth * 0.15,
      centerY + eggHeight * 0.45,
    );

    canvas.drawLine(
      legStart1,
      Offset(legStart1.dx, legStart1.dy + headRadius * 0.4),
      headPaint,
    );
    canvas.drawLine(
      legStart2,
      Offset(legStart2.dx, legStart2.dy + headRadius * 0.4),
      headPaint,
    );

    final toeOffset = headRadius * 0.15;
    for (final start in [legStart1, legStart2]) {
      final base = Offset(start.dx, start.dy + headRadius * 0.4);
      canvas.drawLine(
        base,
        Offset(base.dx - toeOffset, base.dy + toeOffset),
        headPaint,
      );
      canvas.drawLine(base, base, headPaint);
      canvas.drawLine(
        base,
        Offset(base.dx + toeOffset, base.dy + toeOffset),
        headPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
