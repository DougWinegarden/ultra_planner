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
  const TsunamiStripPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
    );

    final Paint paint = Paint()
      ..color = const Color(0xFF006994)
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
  bool shouldRepaint(covariant TsunamiStripPainter oldDelegate) => false;
}

class AnimatedOceanBackground extends StatefulWidget {
  const AnimatedOceanBackground({super.key});

  @override
  State<AnimatedOceanBackground> createState() =>
      _AnimatedOceanBackgroundState();
}

class _AnimatedOceanBackgroundState extends State<AnimatedOceanBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: OceanBackgroundPainter(_controller.value),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class OceanBackgroundPainter extends CustomPainter {
  OceanBackgroundPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint waterPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFFE8F9FF),
          Color(0xFFBDEBFA),
          Color(0xFF78CFF0),
        ],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, waterPaint);

    _drawBubble(canvas, size, 0.12, 0.24, 8);
    _drawBubble(canvas, size, 0.80, 0.18, 11);
    _drawBubble(canvas, size, 0.23, 0.72, 6);
    _drawBubble(canvas, size, 0.88, 0.63, 9);
    _drawBubble(canvas, size, 0.55, 0.87, 7);

    _drawFish(
      canvas,
      size,
      yFraction: 0.20,
      offset: 0.00,
      fishSize: 34,
      reverse: false,
      color: const Color(0x5574C0FC),
    );
    _drawFish(
      canvas,
      size,
      yFraction: 0.38,
      offset: 0.35,
      fishSize: 27,
      reverse: true,
      color: const Color(0x555AABD8),
    );
    _drawFish(
      canvas,
      size,
      yFraction: 0.58,
      offset: 0.63,
      fishSize: 42,
      reverse: false,
      color: const Color(0x5564B5F6),
    );
    _drawFish(
      canvas,
      size,
      yFraction: 0.78,
      offset: 0.18,
      fishSize: 31,
      reverse: true,
      color: const Color(0x554C9FD2),
    );
  }

  void _drawBubble(
    Canvas canvas,
    Size size,
    double xFraction,
    double yFraction,
    double radius,
  ) {
    final double bob = math.sin(progress * math.pi * 2 + xFraction * 9) * 10;

    canvas.drawCircle(
      Offset(size.width * xFraction, size.height * yFraction + bob),
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawFish(
    Canvas canvas,
    Size size, {
    required double yFraction,
    required double offset,
    required double fishSize,
    required bool reverse,
    required Color color,
  }) {
    final double travel = (progress + offset) % 1.0;
    final double fullTravel = size.width + fishSize * 3;
    final double x = reverse
        ? size.width + fishSize - travel * fullTravel
        : -fishSize * 2 + travel * fullTravel;
    final double y =
        size.height * yFraction +
        math.sin(progress * math.pi * 4 + offset * 8) * 8;

    canvas.save();
    canvas.translate(x, y);

    if (reverse) {
      canvas.scale(-1, 1);
    }

    final Paint fishPaint = Paint()..color = color;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: fishSize * 1.5,
        height: fishSize,
      ),
      fishPaint,
    );

    final Path tail = Path()
      ..moveTo(-fishSize * 0.65, 0)
      ..lineTo(-fishSize * 1.12, -fishSize * 0.48)
      ..lineTo(-fishSize * 1.12, fishSize * 0.48)
      ..close();
    canvas.drawPath(tail, fishPaint);

    final Path fin = Path()
      ..moveTo(-fishSize * 0.08, fishSize * 0.10)
      ..lineTo(-fishSize * 0.25, fishSize * 0.58)
      ..lineTo(fishSize * 0.22, fishSize * 0.26)
      ..close();
    canvas.drawPath(fin, fishPaint);

    canvas.drawCircle(
      Offset(fishSize * 0.43, -fishSize * 0.16),
      fishSize * 0.08,
      Paint()..color = Colors.white.withValues(alpha: 0.82),
    );
    canvas.drawCircle(
      Offset(fishSize * 0.46, -fishSize * 0.16),
      fishSize * 0.035,
      Paint()..color = const Color(0xAA003B5C),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant OceanBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
