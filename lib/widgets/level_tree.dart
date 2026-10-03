import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../progress/leveling.dart';

/// The tree on the profile page: a seedling on a little island at level 1, a
/// full, fruiting tree at level 100, and a new seedling after each prestige.
///
/// Every level looks different. The trunk lengthens and thickens a little at
/// each one, and new branches grow in gradually rather than appearing all at
/// once, so even the slow levels in the 90s visibly change something.
class LevelTree extends StatelessWidget {
  const LevelTree({super.key, required this.level, this.size = 240});

  final int level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final int stage = level.clamp(1, maxLevel);
    return Semantics(
      image: true,
      label: 'Your tree, stage $stage of $maxLevel: ${treeStageName(stage)}',
      child: CustomPaint(
        size: Size.square(size),
        painter: LevelTreePainter(level: stage),
      ),
    );
  }
}

/// One limb of the tree.
class TreeBranch {
  const TreeBranch(this.start, this.end, this.width, this.depth);

  final Offset start;
  final Offset end;
  final double width;
  final int depth;
}

/// Where a cluster of leaves sits, and how grown-in it is (0 to 1).
class TreeTip {
  const TreeTip(this.position, this.maturity, this.seed);

  final Offset position;
  final double maturity;
  final int seed;
}

/// The tree's geometry at a level, separate from the painting so it can be
/// tested.
class TreeShape {
  TreeShape._(this.level, this.trunkHeight, this.branches, this.tips);

  /// Grows a tree for [level] in a canvas of [size].
  ///
  /// Branch angles come from a seed per branch, not one shared random
  /// sequence. Growing a new generation therefore extends the tree instead of
  /// reshuffling the branches it already had.
  factory TreeShape.at(int level, Size size) {
    final int stage = level.clamp(1, maxLevel);
    final double growth = (stage - 1) / (maxLevel - 1);
    // Sized so the finished canopy -- about three trunk-lengths tall and
    // three and a half wide -- still fits the picture.
    final double trunkHeight =
        size.height * (0.07 + 0.13 * math.pow(growth, 0.7));
    final double trunkWidth = (1.6 + 11 * growth) * _scaleFor(size);
    // From a bare stem to six generations of branches. The fractional part is
    // the newest generation, partly grown.
    final double generations = 6 * math.pow(growth, 0.8).toDouble();

    final List<TreeBranch> branches = <TreeBranch>[];
    final List<TreeTip> tips = <TreeTip>[];

    void grow(
      Offset start,
      double angle,
      double length,
      double width,
      int depth,
      int seed,
      double maturity,
    ) {
      // Branches always reach upwards; without this, a limb that kept
      // turning the same way would droop below the island.
      final double heading = angle.clamp(-math.pi + 0.35, -0.35);
      final Offset end =
          start + Offset(math.cos(heading), math.sin(heading)) * length;
      branches.add(TreeBranch(start, end, width, depth));

      final double childGrowth = (generations - depth).clamp(0.0, 1.0);
      if (childGrowth <= 0) {
        tips.add(TreeTip(end, maturity, seed));
        return;
      }

      final math.Random random = math.Random(seed);
      // The trunk splits three ways once the tree is established.
      final int children = depth == 0 && growth > 0.3 ? 3 : 2;
      for (int i = 0; i < children; i++) {
        final double side = children == 3
            ? (i - 1).toDouble()
            : (i == 0 ? -1 : 1);
        final double spread = 0.32 + random.nextDouble() * 0.28;
        final double lean = (random.nextDouble() - 0.5) * 0.18;
        grow(
          end,
          heading + side * spread + lean,
          length * (0.66 + random.nextDouble() * 0.10) * childGrowth,
          math.max(0.8, width * 0.68),
          depth + 1,
          seed * 31 + i + 7,
          childGrowth,
        );
      }
      // Leaves along the older limbs too, so the canopy fills in.
      if (depth >= 2 && growth > 0.45) {
        tips.add(TreeTip(end, maturity * 0.7, seed * 17 + 3));
      }
    }

    final Offset ground = Offset(size.width / 2, size.height * 0.76);
    grow(ground, -math.pi / 2, trunkHeight, trunkWidth, 0, 1, 1);

    return TreeShape._(stage, trunkHeight, branches, tips);
  }

  final int level;
  final double trunkHeight;
  final List<TreeBranch> branches;
  final List<TreeTip> tips;

  double get growth => (level - 1) / (maxLevel - 1);
}

/// Bark and leaves are designed for a 240-pixel picture and scale with it, so
/// the tree looks equally full as a thumbnail and on the profile page.
double _scaleFor(Size size) => size.shortestSide / 240;

class LevelTreePainter extends CustomPainter {
  LevelTreePainter({required this.level});

  final int level;

  static const List<Color> _leafGreens = <Color>[
    Color(0xFF2D9E5B),
    Color(0xFF3CB371),
    Color(0xFF52B788),
    Color(0xFF1B7A43),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final TreeShape tree = TreeShape.at(level, size);
    final Rect bounds = Offset.zero & size;

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(size.width * 0.08)),
    );
    _paintScenery(canvas, size);

    // Fully grown: a warm glow behind the canopy.
    if (level >= maxLevel) {
      final Offset crown = Offset(
        size.width / 2,
        size.height * 0.76 - tree.trunkHeight * 1.6,
      );
      canvas.drawCircle(
        crown,
        size.width * 0.42,
        Paint()
          ..shader =
              RadialGradient(
                colors: <Color>[
                  const Color(0xFFFFE066).withValues(alpha: 0.55),
                  const Color(0xFFFFE066).withValues(alpha: 0),
                ],
              ).createShader(
                Rect.fromCircle(center: crown, radius: size.width * 0.42),
              ),
      );
    }

    // Bark, darker at the base.
    for (final TreeBranch branch in tree.branches) {
      canvas.drawLine(
        branch.start,
        branch.end,
        Paint()
          ..strokeWidth = branch.width
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(
            const Color(0xFF6B4226),
            const Color(0xFF9C6B3C),
            (branch.depth / 6).clamp(0.0, 1.0),
          )!,
      );
    }

    // Until the first branches grow, it is a stem with a pair of leaves.
    if (tree.branches.length == 1) {
      _paintSeedlingLeaves(canvas, tree);
    } else {
      _paintCanopy(canvas, tree, size);
    }

    canvas.restore();
  }

  void _paintScenery(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFFEAF9FF), Color(0xFFBDEBFA)],
        ).createShader(Offset.zero & size),
    );

    // The sea, with a gentle wave along its surface.
    final double seaTop = h * 0.74;
    final Path sea = Path()..moveTo(0, seaTop);
    for (double x = 0; x <= w; x += 2) {
      sea.lineTo(x, seaTop + math.sin(x / w * 4 * math.pi) * h * 0.012);
    }
    sea
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      sea,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const <Color>[Color(0xFF48CAE4), Color(0xFF0077B6)],
        ).createShader(Rect.fromLTWH(0, seaTop, w, h - seaTop)),
    );

    // The island.
    final Rect island = Rect.fromCenter(
      center: Offset(w / 2, h * 0.79),
      width: w * 0.6,
      height: h * 0.15,
    );
    canvas.drawOval(island, Paint()..color = const Color(0xFFF2D49B));
    canvas.drawOval(
      island.deflate(h * 0.012).translate(0, -h * 0.01),
      Paint()..color = const Color(0xFFF7E3B5),
    );
    // A tuft of grass where the tree stands.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.765),
        width: w * 0.24,
        height: h * 0.04,
      ),
      Paint()..color = const Color(0xFF7CC47F),
    );
  }

  /// Level 1: a stem with two small leaves.
  void _paintSeedlingLeaves(Canvas canvas, TreeShape tree) {
    final Offset top = tree.branches.first.end;
    final double leaf = 4 + tree.trunkHeight * 0.25;
    final Paint paint = Paint()..color = _leafGreens[1];
    for (final double turn in <double>[-0.6, 0.6]) {
      canvas.save();
      canvas.translate(top.dx, top.dy);
      canvas.rotate(turn);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(turn.sign * leaf * 0.6, 0),
          width: leaf * 1.4,
          height: leaf * 0.7,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  void _paintCanopy(Canvas canvas, TreeShape tree, Size size) {
    final double growth = tree.growth;
    final double scale = _scaleFor(size);
    final double cluster = (3 + 11 * growth) * scale;

    for (final TreeTip tip in tree.tips) {
      final math.Random random = math.Random(tip.seed);
      final double radius = cluster * (0.55 + 0.45 * tip.maturity);
      final Color green = _leafGreens[random.nextInt(_leafGreens.length)];
      // A few overlapping blobs read as a leafy clump rather than a ball.
      for (int i = 0; i < 3; i++) {
        canvas.drawCircle(
          tip.position +
              Offset(
                (random.nextDouble() - 0.5) * radius,
                (random.nextDouble() - 0.5) * radius,
              ),
          radius * (0.6 + random.nextDouble() * 0.3),
          Paint()..color = green.withValues(alpha: 0.92),
        );
      }
    }

    // Blossoms from level 70, fruit from 90: a few more each level.
    final int blossoms = level >= 70
        ? ((level - 69) / 31 * tree.tips.length * 0.6).ceil()
        : 0;
    final int fruit = level >= 90
        ? ((level - 89) / 11 * tree.tips.length * 0.35).ceil()
        : 0;
    // Tips are listed left to right as the branches were grown, so taking the
    // first N would bunch every blossom on one side. Ordering by a hash of each
    // tip's own seed spreads them over the canopy, and a tip keeps its place in
    // that order as others grow in, so earlier blossoms stay put.
    int scatter(TreeTip tip) => (tip.seed * 2654435761) & 0x7fffffff;
    final List<TreeTip> scattered = List<TreeTip>.of(tree.tips)
      ..sort((TreeTip a, TreeTip b) => scatter(a).compareTo(scatter(b)));
    for (int i = 0; i < scattered.length; i++) {
      final TreeTip tip = scattered[i];
      final math.Random random = math.Random(tip.seed * 7 + 1);
      final Offset jitter = Offset(
        (random.nextDouble() - 0.5) * cluster,
        (random.nextDouble() - 0.5) * cluster,
      );
      if (i < blossoms) {
        canvas.drawCircle(
          tip.position + jitter,
          2.4 * scale,
          Paint()..color = const Color(0xFFFFB3C6),
        );
        canvas.drawCircle(
          tip.position + jitter,
          0.9 * scale,
          Paint()..color = const Color(0xFFFFE066),
        );
      }
      if (i < fruit) {
        final Offset at = tip.position - jitter * 0.6;
        canvas.drawCircle(
          at,
          3.2 * scale,
          Paint()..color = const Color(0xFFFF9F1C),
        );
        canvas.drawCircle(
          at + Offset(-scale, -scale),
          scale,
          Paint()..color = Colors.white.withValues(alpha: 0.7),
        );
      }
    }

    // Fully grown: sparkles.
    if (level >= maxLevel) {
      final Paint sparkle = Paint()
        ..color = const Color(0xFFFFF3B0)
        ..strokeWidth = 1.4 * scale
        ..strokeCap = StrokeCap.round;
      final double arm = 3 * scale;
      for (int i = 0; i < scattered.length; i += 5) {
        final Offset at = scattered[i].position + Offset(0, -6 * scale);
        canvas.drawLine(at - Offset(arm, 0), at + Offset(arm, 0), sparkle);
        canvas.drawLine(at - Offset(0, arm), at + Offset(0, arm), sparkle);
      }
    }
  }

  @override
  bool shouldRepaint(LevelTreePainter oldDelegate) =>
      oldDelegate.level != level;
}
