import 'package:hatchaudit/localized_material.dart';

class FlockPairIcon extends StatelessWidget {
  final Color color;
  final double size;

  const FlockPairIcon({super.key, required this.color, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FlockPairIconPainter(color),
    );
  }
}

class _FlockPairIconPainter extends CustomPainter {
  final Color color;

  const _FlockPairIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Hen in front.
    canvas.drawOval(
      Rect.fromLTWH(3.2 * scale, 11 * scale, 8.5 * scale, 6 * scale),
      stroke,
    );
    canvas.drawCircle(Offset(10.7 * scale, 9.2 * scale), 2.4 * scale, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(12.9 * scale, 8.9 * scale)
        ..lineTo(15.1 * scale, 9.8 * scale)
        ..lineTo(12.9 * scale, 10.5 * scale)
        ..close(),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(8.9 * scale, 7 * scale)
        ..quadraticBezierTo(9.7 * scale, 5.5 * scale, 10.6 * scale, 7 * scale)
        ..quadraticBezierTo(
          11.5 * scale,
          5.5 * scale,
          12.2 * scale,
          7.3 * scale,
        ),
      stroke,
    );
    canvas.drawLine(
      Offset(6 * scale, 17.1 * scale),
      Offset(5 * scale, 20 * scale),
      stroke,
    );
    canvas.drawLine(
      Offset(9.4 * scale, 17.1 * scale),
      Offset(9.8 * scale, 20 * scale),
      stroke,
    );

    // Rooster behind, with taller comb and tail feathers.
    canvas.drawPath(
      Path()
        ..moveTo(10.4 * scale, 14.2 * scale)
        ..quadraticBezierTo(
          13.8 * scale,
          8.5 * scale,
          19.1 * scale,
          10.8 * scale,
        )
        ..quadraticBezierTo(
          22.5 * scale,
          12.3 * scale,
          20.4 * scale,
          16.8 * scale,
        )
        ..quadraticBezierTo(
          16.8 * scale,
          19.4 * scale,
          11.7 * scale,
          16.8 * scale,
        )
        ..quadraticBezierTo(
          10.2 * scale,
          16 * scale,
          10.4 * scale,
          14.2 * scale,
        ),
      stroke,
    );
    canvas.drawCircle(Offset(17.3 * scale, 7.5 * scale), 2.5 * scale, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(19.7 * scale, 7.1 * scale)
        ..lineTo(22.2 * scale, 8.1 * scale)
        ..lineTo(19.8 * scale, 9.1 * scale)
        ..close(),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(15.5 * scale, 5.3 * scale)
        ..quadraticBezierTo(15.9 * scale, 3 * scale, 17.2 * scale, 5 * scale)
        ..quadraticBezierTo(
          18.1 * scale,
          2.8 * scale,
          18.9 * scale,
          5.2 * scale,
        )
        ..quadraticBezierTo(20 * scale, 4 * scale, 20.3 * scale, 6.2 * scale),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(11 * scale, 13 * scale)
        ..quadraticBezierTo(7.6 * scale, 8.5 * scale, 5.4 * scale, 12.2 * scale)
        ..moveTo(10.8 * scale, 14.7 * scale)
        ..quadraticBezierTo(
          6.8 * scale,
          12.5 * scale,
          5.1 * scale,
          16.7 * scale,
        ),
      stroke,
    );
    canvas.drawLine(
      Offset(15.2 * scale, 18.3 * scale),
      Offset(14.3 * scale, 21 * scale),
      stroke,
    );
    canvas.drawLine(
      Offset(18.4 * scale, 18.1 * scale),
      Offset(19.2 * scale, 21 * scale),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_FlockPairIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
