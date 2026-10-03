import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The XP bar: a glass tube that fills with sea water as XP comes in, with a
/// rolling wavefront and rising bubbles, next to a life-ring level badge.
///
/// [fraction] is how far through the current level the player is. Changes
/// animate, so finishing a task visibly tops the water up.
class OceanXpBar extends StatefulWidget {
  const OceanXpBar({
    super.key,
    required this.level,
    required this.fraction,
    required this.label,
    this.height = 26,
    this.onTap,
  });

  final int level;
  final double fraction;

  /// Shown on the bar, e.g. "4,210 / 18,000 XP".
  final String label;
  final double height;
  final VoidCallback? onTap;

  @override
  State<OceanXpBar> createState() => _OceanXpBarState();
}

class _OceanXpBarState extends State<OceanXpBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sea = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A still sea for anyone who has asked for less motion.
    if (MediaQuery.of(context).disableAnimations) {
      _sea.stop();
    } else if (!_sea.isAnimating) {
      _sea.repeat();
    }
  }

  @override
  void dispose() {
    _sea.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double fraction = widget.fraction.clamp(0.0, 1.0);
    final double badge = widget.height + 12;

    return Semantics(
      label:
          'Level ${widget.level}, ${(fraction * 100).round()} percent of the '
          'way to the next level. ${widget.label}',
      button: widget.onTap != null,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: <Widget>[
            LifeRingBadge(level: widget.level, size: badge),
            const SizedBox(width: 6),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: fraction),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (BuildContext context, double fill, Widget? child) {
                  return AnimatedBuilder(
                    animation: _sea,
                    builder: (BuildContext context, Widget? child) {
                      return CustomPaint(
                        painter: WaterTubePainter(
                          fill: fill,
                          phase: _sea.value,
                        ),
                        child: child,
                      );
                    },
                    child: child,
                  );
                },
                child: SizedBox(
                  height: widget.height,
                  child: Center(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF002A40),
                        fontSize: math.max(11, widget.height * 0.42),
                        fontWeight: FontWeight.w800,
                        shadows: const <Shadow>[
                          // A white halo keeps the label readable over both the
                          // deep water and the pale empty glass.
                          Shadow(color: Colors.white, blurRadius: 3),
                          Shadow(color: Colors.white, blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The glass tube and the water in it.
class WaterTubePainter extends CustomPainter {
  WaterTubePainter({required this.fill, required this.phase});

  /// 0 to 1.
  final double fill;

  /// 0 to 1, looping: drives the wave and the bubbles.
  final double phase;

  static const Color _glassTop = Color(0xFFF2FBFE);
  static const Color _glassBottom = Color(0xFFD3F0F8);
  static const Color _rim = Color(0xFF90E0EF);
  static const Color _shallow = Color(0xFF48CAE4);
  static const Color _deep = Color(0xFF0077B6);

  @override
  void paint(Canvas canvas, Size size) {
    final RRect tube = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );

    canvas.save();
    canvas.clipRRect(tube);

    // Empty glass.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[_glassTop, _glassBottom],
        ).createShader(Offset.zero & size),
    );

    final double front = size.width * fill;
    if (fill > 0) {
      final double wave = 2 * math.pi * phase;
      // The leading edge rolls like a wave front. It flattens to nothing as the
      // tube fills, so a full bar meets the glass cleanly.
      final double swell = math.min(5, size.height * 0.18) * (1 - fill * 0.6);

      double edge(double y) =>
          front + swell * math.sin(y / size.height * 2 * math.pi + wave * 2);

      final Path water = Path()..moveTo(0, 0);
      for (double y = 0; y <= size.height; y += 1) {
        water.lineTo(edge(y), y);
      }
      water
        ..lineTo(0, size.height)
        ..close();

      canvas.drawPath(
        water,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[_shallow, _deep],
          ).createShader(Offset.zero & size),
      );

      // A lighter band along the top, where light hits the surface.
      canvas.drawRect(
        Rect.fromLTWH(0, size.height * 0.12, front, size.height * 0.16),
        Paint()..color = Colors.white.withValues(alpha: 0.22),
      );

      // Foam along the front.
      final Path foam = Path()..moveTo(edge(0), 0);
      for (double y = 1; y <= size.height; y += 1) {
        foam.lineTo(edge(y), y);
      }
      canvas.drawPath(
        foam,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: 0.75),
      );

      // Bubbles rise through the water and wrap back to the bottom.
      final Paint bubble = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.7);
      for (int i = 0; i < 9; i++) {
        final double x = (0.07 + i * 0.113) * size.width;
        if (x > front - 4) break;
        final double rise = (phase * (0.8 + i % 3 * 0.35) + i * 0.37) % 1;
        final double y = size.height * (1.05 - rise * 1.1);
        final double r = size.height * (0.06 + (i % 3) * 0.025);
        canvas.drawCircle(Offset(x + math.sin(wave + i) * 2, y), r, bubble);
      }
    }

    canvas.restore();

    // Glass rim and a highlight, drawn over the water.
    canvas.drawRRect(
      tube,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _rim,
    );
    canvas.drawLine(
      Offset(size.height / 2, size.height * 0.22),
      Offset(size.width - size.height / 2, size.height * 0.22),
      Paint()
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(WaterTubePainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.phase != phase;
}

/// The level number inside a red-and-white life ring.
class LifeRingBadge extends StatelessWidget {
  const LifeRingBadge({super.key, required this.level, this.size = 38});

  final int level;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _LifeRingPainter(),
        child: Center(
          child: Text(
            '$level',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              // Three digits still fit inside the ring at level 100.
              fontSize: size * (level >= 100 ? 0.28 : 0.34),
            ),
          ),
        ),
      ),
    );
  }
}

class _LifeRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;
    final double ring = radius * 0.3;

    // Navy centre for the number.
    canvas.drawCircle(
      center,
      radius - ring,
      Paint()..color = const Color(0xFF003B5C),
    );

    // Eight alternating segments make the ring.
    final Rect arc = Rect.fromCircle(center: center, radius: radius - ring / 2);
    for (int i = 0; i < 8; i++) {
      canvas.drawArc(
        arc,
        i * math.pi / 4 - math.pi / 8,
        math.pi / 4,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring
          ..color = i.isEven ? const Color(0xFFE63946) : Colors.white,
      );
    }

    canvas.drawCircle(
      center,
      radius - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF9B2226),
    );
  }

  @override
  bool shouldRepaint(_LifeRingPainter oldDelegate) => false;
}
