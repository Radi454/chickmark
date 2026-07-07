import 'package:hatchaudit/localized_material.dart';

class ChickIcon extends StatelessWidget {
  final Color color;
  final double size;

  const ChickIcon({super.key, required this.color, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ChickIconPainter(color),
    );
  }
}

class _ChickIconPainter extends CustomPainter {
  final Color color;

  const _ChickIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 20;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawOval(
      Rect.fromLTWH(4 * scale, 8.4 * scale, 9.8 * scale, 7.4 * scale),
      stroke,
    );
    canvas.drawCircle(Offset(12.2 * scale, 7 * scale), 3.6 * scale, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(15.4 * scale, 6.4 * scale)
        ..lineTo(18.8 * scale, 7.8 * scale)
        ..lineTo(15.4 * scale, 9.1 * scale)
        ..close(),
      fill,
    );
    canvas.drawArc(
      Rect.fromLTWH(6.4 * scale, 10.3 * scale, 4.8 * scale, 3.8 * scale),
      0.2,
      2.5,
      false,
      stroke,
    );
    canvas.drawLine(
      Offset(7.2 * scale, 16.1 * scale),
      Offset(6.2 * scale, 18 * scale),
      stroke,
    );
    canvas.drawLine(
      Offset(10.8 * scale, 16.1 * scale),
      Offset(11.8 * scale, 18 * scale),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_ChickIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
