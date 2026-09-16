import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'holiday_theme.dart';

/// The app's living background: a gradient sky, drifting ambient specks, and a
/// handful of sprites tracking back and forth across it.
///
/// The sprites and palette come from [theme], so the whole app changes
/// character on a holiday without any other widget knowing about it.
class AnimatedAppBackground extends StatefulWidget {
  const AnimatedAppBackground({super.key, this.theme = HolidayTheme.ocean});

  final HolidayTheme theme;

  @override
  State<AnimatedAppBackground> createState() => _AnimatedAppBackgroundState();
}

class _AnimatedAppBackgroundState extends State<AnimatedAppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: AppBackgroundPainter(
            progress: _controller.value,
            theme: widget.theme,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class AppBackgroundPainter extends CustomPainter {
  const AppBackgroundPainter({required this.progress, required this.theme});

  final double progress;
  final HolidayTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: theme.gradient,
        ).createShader(Offset.zero & size),
    );

    _paintAmbient(canvas, size);
    _paintDrifters(canvas, size);
  }

  // --- Ambient specks --------------------------------------------------------

  void _paintAmbient(Canvas canvas, Size size) {
    const List<List<double>> spots = <List<double>>[
      <double>[0.12, 0.24, 8],
      <double>[0.80, 0.18, 11],
      <double>[0.23, 0.72, 6],
      <double>[0.88, 0.63, 9],
      <double>[0.55, 0.87, 7],
      <double>[0.38, 0.45, 7],
      <double>[0.68, 0.36, 6],
    ];

    for (final List<double> spot in spots) {
      _paintSpeck(canvas, size, spot[0], spot[1], spot[2]);
    }
  }

  void _paintSpeck(
    Canvas canvas,
    Size size,
    double xFraction,
    double yFraction,
    double radius,
  ) {
    final double bob = math.sin(progress * math.pi * 2 + xFraction * 9) * 10;
    final Offset centre = Offset(
      size.width * xFraction,
      size.height * yFraction + bob,
    );
    final Color colour = theme.ambientColor;

    switch (theme.ambient) {
      case AmbientStyle.bubble:
        canvas.drawCircle(
          centre,
          radius,
          Paint()
            ..color = colour.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );

      case AmbientStyle.snow:
        // Snow falls rather than bobbing, wrapping around at the bottom.
        final double fall =
            (yFraction + progress * 1.4) % 1.2 - 0.1;
        canvas.drawCircle(
          Offset(size.width * xFraction + bob * 0.4, size.height * fall),
          radius * 0.45,
          Paint()..color = colour.withValues(alpha: 0.85),
        );

      case AmbientStyle.sparkle:
        _paintSparkle(canvas, centre, radius, colour);

      case AmbientStyle.petal:
        canvas.save();
        canvas.translate(centre.dx, centre.dy);
        canvas.rotate(progress * math.pi * 2 + xFraction * 4);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: radius * 1.6,
            height: radius * 0.9,
          ),
          Paint()..color = colour.withValues(alpha: 0.7),
        );
        canvas.restore();

      case AmbientStyle.leaf:
        canvas.save();
        canvas.translate(centre.dx, centre.dy);
        canvas.rotate(math.sin(progress * math.pi * 2 + xFraction * 6) * 0.9);
        final Path leaf = Path()
          ..moveTo(0, -radius)
          ..quadraticBezierTo(radius, 0, 0, radius)
          ..quadraticBezierTo(-radius, 0, 0, -radius);
        canvas.drawPath(leaf, Paint()..color = colour.withValues(alpha: 0.65));
        canvas.restore();

      case AmbientStyle.mist:
        canvas.drawCircle(
          centre,
          radius * 2.4,
          Paint()
            ..color = colour.withValues(alpha: 0.10)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
    }
  }

  void _paintSparkle(Canvas canvas, Offset centre, double radius, Color colour) {
    final double twinkle =
        0.4 + 0.6 * (0.5 + 0.5 * math.sin(progress * math.pi * 4 + centre.dx));
    final Paint paint = Paint()
      ..color = colour.withValues(alpha: 0.75 * twinkle)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final double arm = radius * twinkle;
    canvas.drawLine(
      centre.translate(-arm, 0),
      centre.translate(arm, 0),
      paint,
    );
    canvas.drawLine(
      centre.translate(0, -arm),
      centre.translate(0, arm),
      paint,
    );
  }

  // --- Drifters --------------------------------------------------------------

  /// Where each sprite sits, how big, and which way it faces.
  static const List<({double y, double offset, double size, bool reverse})>
  _lanes = <({double y, double offset, double size, bool reverse})>[
    (y: 0.20, offset: 0.00, size: 34, reverse: false),
    (y: 0.38, offset: 0.35, size: 27, reverse: true),
    (y: 0.58, offset: 0.63, size: 42, reverse: false),
    (y: 0.78, offset: 0.18, size: 31, reverse: true),
  ];

  void _paintDrifters(Canvas canvas, Size size) {
    // The rainbow is scenery, not a traveller, so it is drawn once behind
    // everything else.
    if (theme.drifter == DrifterStyle.rainbowPot) {
      _paintRainbowScene(canvas, size);
      return;
    }

    if (theme.drifter == DrifterStyle.fireworks) {
      _paintFireworks(canvas, size);
      return;
    }

    for (int i = 0; i < _lanes.length; i++) {
      final ({double y, double offset, double size, bool reverse}) lane =
          _lanes[i];
      final Color colour =
          theme.drifterColors[i % theme.drifterColors.length];

      // Back and forth: the sprite crosses, turns, and crosses back, so a
      // triangle wave rather than a saw.
      final double cycle = (progress + lane.offset) % 1.0;
      final bool goingRight = cycle < 0.5;
      final double leg = goingRight ? cycle * 2 : (1 - cycle) * 2;

      final double span = size.width + lane.size * 3;
      final double x = -lane.size * 1.5 + span * leg;
      final double bob =
          math.sin(progress * math.pi * 6 + lane.offset * 7) * lane.size * 0.12;
      final double y = size.height * lane.y + bob;

      canvas.save();
      canvas.translate(x, y);
      // Sprites are drawn facing right; flip when travelling the other way.
      if (!goingRight != lane.reverse) {
        canvas.scale(-1, 1);
      }
      _paintSprite(canvas, lane.size, colour, i);
      canvas.restore();
    }
  }

  void _paintSprite(Canvas canvas, double unit, Color colour, int index) {
    switch (theme.drifter) {
      case DrifterStyle.fish:
        _paintFish(canvas, unit, colour);
      case DrifterStyle.sleigh:
        _paintSleigh(canvas, unit);
      case DrifterStyle.reaper:
        _paintReaper(canvas, unit);
      case DrifterStyle.turkey:
        _paintTurkey(canvas, unit);
      case DrifterStyle.heart:
        _paintHeart(canvas, unit, colour);
      case DrifterStyle.bunny:
        _paintBunny(canvas, unit, colour);
      case DrifterStyle.flower:
        _paintFlower(canvas, unit, colour);
      case DrifterStyle.tie:
        _paintTie(canvas, unit, colour);
      case DrifterStyle.star:
        _paintStar(canvas, unit, colour);
      case DrifterStyle.tool:
        _paintTool(canvas, unit, colour, index);
      case DrifterStyle.rainbowPot:
      case DrifterStyle.fireworks:
        break; // handled as whole scenes
    }
  }

  // --- Individual sprites ----------------------------------------------------

  void _paintFish(Canvas canvas, double unit, Color colour) {
    final Paint paint = Paint()..color = colour;

    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: unit, height: unit * 0.55),
      paint,
    );

    final Path tail = Path()
      ..moveTo(-unit * 0.5, 0)
      ..lineTo(-unit * 0.85, -unit * 0.28)
      ..lineTo(-unit * 0.85, unit * 0.28)
      ..close();
    canvas.drawPath(tail, paint);

    canvas.drawCircle(
      Offset(unit * 0.28, -unit * 0.06),
      unit * 0.05,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  void _paintSleigh(Canvas canvas, double unit) {
    final Color sleighColour = theme.drifterColors[0];
    final Color deerColour = theme.drifterColors[1];
    final Color trim = theme.drifterColors[2];

    // Two reindeer out front, then the sleigh behind them.
    for (int i = 0; i < 2; i++) {
      canvas.save();
      canvas.translate(unit * (0.95 + i * 0.75), 0);
      _paintReindeer(canvas, unit * 0.55, deerColour);
      canvas.restore();
    }

    final Paint body = Paint()..color = sleighColour;
    final Path sleigh = Path()
      ..moveTo(-unit * 0.75, unit * 0.1)
      ..lineTo(unit * 0.35, unit * 0.1)
      ..lineTo(unit * 0.35, -unit * 0.22)
      ..quadraticBezierTo(-unit * 0.1, -unit * 0.3, -unit * 0.5, -unit * 0.05)
      ..close();
    canvas.drawPath(sleigh, body);

    // Runner, curling up at the front.
    final Path runner = Path()
      ..moveTo(-unit * 0.8, unit * 0.28)
      ..lineTo(unit * 0.4, unit * 0.28)
      ..quadraticBezierTo(
        unit * 0.62,
        unit * 0.28,
        unit * 0.58,
        unit * 0.08,
      );
    canvas.drawPath(
      runner,
      Paint()
        ..color = trim
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.07
        ..strokeCap = StrokeCap.round,
    );

    // A sack of presents.
    canvas.drawCircle(
      Offset(-unit * 0.35, -unit * 0.18),
      unit * 0.16,
      Paint()..color = trim,
    );
  }

  void _paintReindeer(Canvas canvas, double unit, Color colour) {
    final Paint paint = Paint()..color = colour;

    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: unit, height: unit * 0.5),
      paint,
    );

    // Head and neck.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(unit * 0.55, -unit * 0.3),
        width: unit * 0.42,
        height: unit * 0.3,
      ),
      paint,
    );

    final Paint stroke = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.08
      ..strokeCap = StrokeCap.round;

    // Antlers.
    canvas.drawLine(
      Offset(unit * 0.55, -unit * 0.42),
      Offset(unit * 0.45, -unit * 0.72),
      stroke,
    );
    canvas.drawLine(
      Offset(unit * 0.62, -unit * 0.42),
      Offset(unit * 0.78, -unit * 0.7),
      stroke,
    );

    // Legs.
    for (final double dx in <double>[-0.3, 0.05, 0.3]) {
      canvas.drawLine(
        Offset(unit * dx, unit * 0.2),
        Offset(unit * dx, unit * 0.55),
        stroke,
      );
    }
  }

  void _paintReaper(Canvas canvas, double unit) {
    final Color robe = theme.drifterColors[0];
    final Color hood = theme.drifterColors[1];
    final Color scythe = theme.drifterColors[2];

    // Robe: a hooded silhouette with a ragged hem.
    final Path cloak = Path()
      ..moveTo(0, -unit * 0.62)
      ..quadraticBezierTo(unit * 0.42, -unit * 0.45, unit * 0.36, unit * 0.6)
      ..lineTo(unit * 0.2, unit * 0.44)
      ..lineTo(unit * 0.04, unit * 0.62)
      ..lineTo(-unit * 0.12, unit * 0.44)
      ..lineTo(-unit * 0.3, unit * 0.6)
      ..quadraticBezierTo(-unit * 0.4, -unit * 0.45, 0, -unit * 0.62)
      ..close();
    canvas.drawPath(cloak, Paint()..color = robe);

    // Hood opening, left dark and empty.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, -unit * 0.38),
        width: unit * 0.34,
        height: unit * 0.4,
      ),
      Paint()..color = hood,
    );

    // Scythe: a staff with a curved blade.
    final Paint staff = Paint()
      ..color = scythe
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.07
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(unit * 0.5, -unit * 0.75),
      Offset(unit * 0.5, unit * 0.6),
      staff,
    );

    final Path blade = Path()
      ..moveTo(unit * 0.5, -unit * 0.72)
      ..quadraticBezierTo(
        unit * 1.05,
        -unit * 0.66,
        unit * 0.92,
        -unit * 0.22,
      )
      ..quadraticBezierTo(unit * 0.86, -unit * 0.56, unit * 0.5, -unit * 0.58)
      ..close();
    canvas.drawPath(blade, Paint()..color = scythe);
  }

  void _paintTurkey(Canvas canvas, double unit) {
    final Color body = theme.drifterColors[0];
    final Color feathers = theme.drifterColors[1];
    final Color wattle = theme.drifterColors[2];

    // Fan of tail feathers behind the body.
    for (int i = -3; i <= 3; i++) {
      canvas.save();
      canvas.translate(-unit * 0.18, 0);
      canvas.rotate(i * 0.26);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(-unit * 0.42, 0),
          width: unit * 0.62,
          height: unit * 0.24,
        ),
        Paint()..color = i.isEven ? feathers : body,
      );
      canvas.restore();
    }

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: unit * 0.72,
        height: unit * 0.6,
      ),
      Paint()..color = body,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(unit * 0.36, -unit * 0.26),
        width: unit * 0.3,
        height: unit * 0.34,
      ),
      Paint()..color = body,
    );

    // Beak and wattle.
    final Path beak = Path()
      ..moveTo(unit * 0.48, -unit * 0.28)
      ..lineTo(unit * 0.68, -unit * 0.22)
      ..lineTo(unit * 0.48, -unit * 0.16)
      ..close();
    canvas.drawPath(beak, Paint()..color = wattle);
    canvas.drawCircle(
      Offset(unit * 0.46, -unit * 0.08),
      unit * 0.07,
      Paint()..color = wattle,
    );

    final Paint legs = Paint()
      ..color = wattle
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.06
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(unit * 0.05, unit * 0.28),
      Offset(unit * 0.05, unit * 0.52),
      legs,
    );
    canvas.drawLine(
      Offset(unit * 0.24, unit * 0.28),
      Offset(unit * 0.24, unit * 0.52),
      legs,
    );
  }

  void _paintHeart(Canvas canvas, double unit, Color colour) {
    // A gentle pulse, so the hearts feel alive rather than pasted on.
    final double beat =
        1 + 0.08 * math.sin(progress * math.pi * 8 + unit);
    canvas.save();
    canvas.scale(beat, beat);

    final double s = unit * 0.5;
    final Path heart = Path()
      ..moveTo(0, s * 0.75)
      ..cubicTo(-s * 1.6, -s * 0.3, -s * 0.55, -s * 1.2, 0, -s * 0.45)
      ..cubicTo(s * 0.55, -s * 1.2, s * 1.6, -s * 0.3, 0, s * 0.75)
      ..close();
    canvas.drawPath(heart, Paint()..color = colour);
    canvas.restore();
  }

  void _paintBunny(Canvas canvas, double unit, Color colour) {
    // Hop: a bounce twice as fast as the drift, easing at the top.
    final double hop =
        -(math.sin(progress * math.pi * 10 + unit).abs()) * unit * 0.35;
    canvas.save();
    canvas.translate(0, hop);

    final Paint paint = Paint()..color = colour;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: unit * 0.8,
        height: unit * 0.58,
      ),
      paint,
    );

    canvas.drawCircle(Offset(unit * 0.4, -unit * 0.3), unit * 0.22, paint);

    // Ears.
    for (final double dx in <double>[0.32, 0.5]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(unit * dx, -unit * 0.62),
          width: unit * 0.13,
          height: unit * 0.42,
        ),
        paint,
      );
    }

    // Cotton tail.
    canvas.drawCircle(
      Offset(-unit * 0.42, -unit * 0.04),
      unit * 0.14,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    canvas.restore();
  }

  void _paintFlower(Canvas canvas, double unit, Color colour) {
    final Color stem = theme.drifterColors.last;

    canvas.drawLine(
      Offset(0, unit * 0.15),
      Offset(0, unit * 0.7),
      Paint()
        ..color = stem
        ..strokeWidth = unit * 0.07
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(unit * 0.2, unit * 0.45),
        width: unit * 0.3,
        height: unit * 0.16,
      ),
      Paint()..color = stem,
    );

    for (int i = 0; i < 6; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 3 + progress * math.pi);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, -unit * 0.26),
          width: unit * 0.2,
          height: unit * 0.4,
        ),
        Paint()..color = colour,
      );
      canvas.restore();
    }

    canvas.drawCircle(
      Offset.zero,
      unit * 0.13,
      Paint()..color = const Color(0xFFFFE082),
    );
  }

  void _paintTie(Canvas canvas, double unit, Color colour) {
    final Paint paint = Paint()..color = colour;

    // Knot.
    final Path knot = Path()
      ..moveTo(-unit * 0.15, -unit * 0.5)
      ..lineTo(unit * 0.15, -unit * 0.5)
      ..lineTo(unit * 0.1, -unit * 0.26)
      ..lineTo(-unit * 0.1, -unit * 0.26)
      ..close();
    canvas.drawPath(knot, paint);

    // Blade.
    final Path blade = Path()
      ..moveTo(-unit * 0.1, -unit * 0.24)
      ..lineTo(unit * 0.1, -unit * 0.24)
      ..lineTo(unit * 0.22, unit * 0.36)
      ..lineTo(0, unit * 0.62)
      ..lineTo(-unit * 0.22, unit * 0.36)
      ..close();
    canvas.drawPath(blade, paint);
  }

  void _paintStar(Canvas canvas, double unit, Color colour) {
    final Path star = Path();
    const int points = 5;
    final double outer = unit * 0.5;
    final double inner = outer * 0.42;

    for (int i = 0; i < points * 2; i++) {
      final double radius = i.isEven ? outer : inner;
      final double angle = i * math.pi / points - math.pi / 2;
      final Offset point = Offset(
        math.cos(angle) * radius,
        math.sin(angle) * radius,
      );
      if (i == 0) {
        star.moveTo(point.dx, point.dy);
      } else {
        star.lineTo(point.dx, point.dy);
      }
    }
    star.close();

    canvas.drawPath(star, Paint()..color = colour.withValues(alpha: 0.85));
  }

  void _paintTool(Canvas canvas, double unit, Color colour, int index) {
    final Paint paint = Paint()..color = colour;

    if (index.isEven) {
      // Hammer.
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(0, unit * 0.2),
          width: unit * 0.12,
          height: unit * 0.7,
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(0, -unit * 0.28),
            width: unit * 0.6,
            height: unit * 0.26,
          ),
          Radius.circular(unit * 0.06),
        ),
        paint,
      );
    } else {
      // Wrench.
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(0, unit * 0.1),
          width: unit * 0.14,
          height: unit * 0.8,
        ),
        paint,
      );
      canvas.drawCircle(
        Offset(0, -unit * 0.34),
        unit * 0.2,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * 0.12,
      );
    }
  }

  // --- Whole scenes ----------------------------------------------------------

  /// A rainbow arcing over two pots of gold, with coins bobbing above them.
  void _paintRainbowScene(Canvas canvas, Size size) {
    const List<Color> bands = <Color>[
      Color(0xFFE53935),
      Color(0xFFFB8C00),
      Color(0xFFFDD835),
      Color(0xFF43A047),
      Color(0xFF1E88E5),
      Color(0xFF8E24AA),
    ];

    final double radius = size.width * 0.42;
    final Offset centre = Offset(size.width * 0.5, size.height * 0.92);
    final double band = radius * 0.055;

    for (int i = 0; i < bands.length; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius - i * band),
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = bands[i].withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = band,
      );
    }

    for (final double xFraction in <double>[0.16, 0.84]) {
      _paintPotOfGold(canvas, size, xFraction);
    }
  }

  void _paintPotOfGold(Canvas canvas, Size size, double xFraction) {
    final double unit = size.width * 0.055;
    final Offset base = Offset(size.width * xFraction, size.height * 0.82);
    final Color gold = theme.drifterColors[0];
    final Color pot = theme.drifterColors[2];

    // Coins drifting up out of the pot.
    for (int i = 0; i < 3; i++) {
      final double lift = ((progress * 1.6 + i * 0.33) % 1.0);
      canvas.drawCircle(
        Offset(
          base.dx + math.sin(lift * math.pi * 2 + i) * unit * 0.5,
          base.dy - unit * 0.8 - lift * unit * 1.6,
        ),
        unit * 0.16,
        Paint()..color = gold.withValues(alpha: (1 - lift).clamp(0.0, 1.0)),
      );
    }

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(base.dx, base.dy - unit * 0.55),
        width: unit * 1.5,
        height: unit * 0.5,
      ),
      Paint()..color = gold,
    );

    final Path body = Path()
      ..moveTo(base.dx - unit * 0.75, base.dy - unit * 0.55)
      ..quadraticBezierTo(
        base.dx - unit * 0.95,
        base.dy + unit * 0.55,
        base.dx,
        base.dy + unit * 0.55,
      )
      ..quadraticBezierTo(
        base.dx + unit * 0.95,
        base.dy + unit * 0.55,
        base.dx + unit * 0.75,
        base.dy - unit * 0.55,
      )
      ..close();
    canvas.drawPath(body, Paint()..color = pot);
  }

  /// Shells rising and bursting, staggered so the sky is never empty.
  void _paintFireworks(Canvas canvas, Size size) {
    const List<List<double>> shells = <List<double>>[
      <double>[0.22, 0.28, 0.00],
      <double>[0.52, 0.18, 0.28],
      <double>[0.78, 0.34, 0.55],
      <double>[0.38, 0.42, 0.74],
    ];

    for (int i = 0; i < shells.length; i++) {
      final double apexX = size.width * shells[i][0];
      final double apexY = size.height * shells[i][1];
      final double phase = (progress + shells[i][2]) % 1.0;
      final Color colour =
          theme.drifterColors[i % theme.drifterColors.length];

      if (phase < 0.35) {
        // Rising: a streak climbing towards the burst point.
        final double climb = phase / 0.35;
        final double y = size.height * 0.95 - (size.height * 0.95 - apexY) * climb;
        canvas.drawLine(
          Offset(apexX, y),
          Offset(apexX, y + size.height * 0.05),
          Paint()
            ..color = colour.withValues(alpha: 0.8)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
      } else {
        // Bursting: spokes expanding and fading.
        final double burst = (phase - 0.35) / 0.65;
        final double reach = size.width * 0.1 * Curves.easeOut.transform(burst);
        final double fade = (1 - burst).clamp(0.0, 1.0);

        for (int spoke = 0; spoke < 12; spoke++) {
          final double angle = spoke * math.pi / 6;
          final Offset outer = Offset(
            apexX + math.cos(angle) * reach,
            apexY + math.sin(angle) * reach,
          );
          canvas.drawLine(
            Offset(
              apexX + math.cos(angle) * reach * 0.55,
              apexY + math.sin(angle) * reach * 0.55,
            ),
            outer,
            Paint()
              ..color = colour.withValues(alpha: 0.85 * fade)
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawCircle(
            outer,
            2.4 * fade,
            Paint()..color = colour.withValues(alpha: fade),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant AppBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.theme != theme;
  }
}
