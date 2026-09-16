import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/widgets/app_background.dart';

void main() {
  /// Samples a full cycle and checks a sprite never travels backwards relative
  /// to the way it faces. This is the bug that shipped: `reverse` was applied
  /// to the facing instead of the starting direction, so half the lanes
  /// moonwalked.
  void expectNeverMovesBackwards({
    required double offset,
    required bool startReversed,
  }) {
    const int samples = 720;
    const double step = 1 / 4000;

    for (int i = 0; i <= samples; i++) {
      final double progress = i / samples;
      final ({double leg, bool facingRight}) now = drifterMotion(
        progress: progress,
        offset: offset,
        startReversed: startReversed,
      );
      final ({double leg, bool facingRight}) next = drifterMotion(
        progress: (progress + step) % 1.0,
        offset: offset,
        startReversed: startReversed,
      );

      // Skip any step that contains a turn: the direction genuinely changes
      // there, so a before/after comparison says nothing.
      if (next.facingRight != now.facingRight) continue;

      final double delta = next.leg - now.leg;
      if (delta.abs() < 1e-9) continue;

      expect(
        delta > 0,
        now.facingRight,
        reason:
            'offset $offset reversed $startReversed at progress $progress: '
            'moving ${delta > 0 ? "right" : "left"} while facing '
            '${now.facingRight ? "right" : "left"}',
      );
    }
  }

  test('a sprite always faces the way it is travelling', () {
    for (final double offset in <double>[0.0, 0.18, 0.35, 0.63, 0.9]) {
      for (final bool reversed in <bool>[false, true]) {
        expectNeverMovesBackwards(offset: offset, startReversed: reversed);
      }
    }
  });

  test('reversed lanes set off the other way', () {
    final ({double leg, bool facingRight}) forward = drifterMotion(
      progress: 0.1,
      offset: 0,
      startReversed: false,
    );
    final ({double leg, bool facingRight}) reversed = drifterMotion(
      progress: 0.1,
      offset: 0,
      startReversed: true,
    );

    expect(forward.facingRight, isTrue);
    expect(reversed.facingRight, isFalse);
  });

  test('the leg stays within its lane', () {
    for (int i = 0; i <= 500; i++) {
      final ({double leg, bool facingRight}) motion = drifterMotion(
        progress: i / 500,
        offset: 0.37,
        startReversed: true,
      );
      expect(motion.leg, inInclusiveRange(0.0, 1.0));
    }
  });

  test('a full cycle returns to where it started', () {
    // Otherwise the sprite would jump when the animation controller wraps.
    final ({double leg, bool facingRight}) start = drifterMotion(
      progress: 0,
      offset: 0.2,
      startReversed: false,
    );
    final ({double leg, bool facingRight}) end = drifterMotion(
      progress: 0.999999,
      offset: 0.2,
      startReversed: false,
    );
    expect((end.leg - start.leg).abs(), lessThan(0.001));
  });

  test('turning points sit off-screen at both ends', () {
    // The flip is instant, so it must happen where nobody can see it: leg 0 and
    // leg 1 place the sprite past the edge of the viewport.
    final Set<double> extremes = <double>{};
    for (int i = 0; i <= 2000; i++) {
      final double leg = drifterMotion(
        progress: i / 2000,
        offset: 0,
        startReversed: false,
      ).leg;
      if (leg < 0.001 || leg > 0.999) extremes.add(leg.roundToDouble());
    }
    expect(extremes, containsAll(<double>[0.0, 1.0]));
  });
}
