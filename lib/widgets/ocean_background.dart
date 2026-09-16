import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A cheerful capybara wearing a duck hood, drawn in-app so it works offline.
class DuckSuitCapybara extends StatelessWidget {
  const DuckSuitCapybara({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: DuckSuitCapybaraPainter()),
    );
  }
}

class DuckSuitCapybaraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 72;
    void oval(Rect rect, Color color) =>
        canvas.drawOval(rect, Paint()..color = color);
    void circle(Offset center, double radius, Color color) =>
        canvas.drawCircle(center, radius, Paint()..color = color);

    // Little duck feet and the yellow duck-suit body.
    oval(Rect.fromLTWH(13 * u, 58 * u, 20 * u, 8 * u), const Color(0xFFF29D38));
    oval(Rect.fromLTWH(39 * u, 58 * u, 20 * u, 8 * u), const Color(0xFFF29D38));
    oval(
      Rect.fromLTWH(12 * u, 26 * u, 48 * u, 37 * u),
      const Color(0xFFFFD94A),
    );
    circle(Offset(17 * u, 42 * u), 7 * u, const Color(0xFFFFD94A));
    circle(Offset(55 * u, 42 * u), 7 * u, const Color(0xFFFFD94A));

    // Capybara face inside the hood.
    oval(
      Rect.fromLTWH(17 * u, 15 * u, 38 * u, 40 * u),
      const Color(0xFF9A684A),
    );
    circle(Offset(24 * u, 17 * u), 7 * u, const Color(0xFF765039));
    circle(Offset(48 * u, 17 * u), 7 * u, const Color(0xFF765039));
    oval(
      Rect.fromLTWH(20 * u, 34 * u, 32 * u, 17 * u),
      const Color(0xFFBC8A67),
    );
    circle(Offset(30 * u, 32 * u), 2.3 * u, const Color(0xFF30221C));
    circle(Offset(43 * u, 32 * u), 2.3 * u, const Color(0xFF30221C));
    oval(Rect.fromLTWH(32 * u, 39 * u, 8 * u, 5 * u), const Color(0xFF50352B));

    // Duck hood, bill, and a small wing patch.
    final Paint outline = Paint()
      ..color = const Color(0xFFDAA61D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * u;
    canvas.drawArc(
      Rect.fromLTWH(12 * u, 8 * u, 48 * u, 50 * u),
      math.pi,
      math.pi,
      false,
      outline,
    );
    oval(Rect.fromLTWH(27 * u, 7 * u, 18 * u, 8 * u), const Color(0xFFFFD94A));
    oval(Rect.fromLTWH(28 * u, 42 * u, 16 * u, 8 * u), const Color(0xFFF29D38));
    oval(Rect.fromLTWH(42 * u, 49 * u, 12 * u, 8 * u), const Color(0xFFF0B91C));
    circle(Offset(47 * u, 52 * u), 1.2 * u, const Color(0xFFCF8B17));
  }

  @override
  bool shouldRepaint(covariant DuckSuitCapybaraPainter oldDelegate) => false;
}

class TsunamiStripPainter extends CustomPainter {
  /// [color] is passed in rather than fixed so the strip matches whatever the
  /// app uses for "overdue" -- it marks a late task, not the sea.
  const TsunamiStripPainter({this.color = const Color(0xFFCC2A22)});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
    );

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Path path = Path()..moveTo(0, size.height);
    const double waveWidth = 24;

    for (double x = 0; x < size.width; x += waveWidth) {
      final double half = math.min(x + waveWidth * 0.50, size.width);
      final double end = math.min(x + waveWidth, size.width);

      path.quadraticBezierTo(
        math.min(x + waveWidth * 0.25, size.width),
        0,
        half,
        size.height * 0.55,
      );
      path.quadraticBezierTo(
        math.min(x + waveWidth * 0.75, size.width),
        size.height,
        end,
        size.height * 0.40,
      );
    }

    path
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(path, paint);

    final Paint foamPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    final Path foam = Path();

    for (double x = 0; x < size.width; x += waveWidth) {
      foam.moveTo(x, size.height * 0.65);
      foam.quadraticBezierTo(
        math.min(x + waveWidth * 0.25, size.width),
        size.height * 0.10,
        math.min(x + waveWidth * 0.50, size.width),
        size.height * 0.60,
      );
    }

    canvas.drawPath(foam, foamPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TsunamiStripPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
