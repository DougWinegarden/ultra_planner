import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/progress/leveling.dart';
import 'package:ultra_planner/widgets/level_tree.dart';

void main() {
  const Size canvas = Size(300, 300);

  test('the trunk grows taller and thicker at every level', () {
    for (int level = 2; level <= maxLevel; level++) {
      final TreeShape before = TreeShape.at(level - 1, canvas);
      final TreeShape after = TreeShape.at(level, canvas);
      expect(
        after.trunkHeight,
        greaterThan(before.trunkHeight),
        reason: 'level $level',
      );
      expect(
        after.branches.first.width,
        greaterThan(before.branches.first.width),
        reason: 'level $level',
      );
    }
  });

  test('the tree never loses branches as it grows', () {
    int previous = 0;
    for (int level = 1; level <= maxLevel; level++) {
      final int branches = TreeShape.at(level, canvas).branches.length;
      expect(branches, greaterThanOrEqualTo(previous), reason: 'level $level');
      previous = branches;
    }
  });

  test('it starts as a bare stem and ends as a full tree', () {
    expect(TreeShape.at(1, canvas).branches, hasLength(1));
    expect(TreeShape.at(maxLevel, canvas).branches.length, greaterThan(150));
    expect(TreeShape.at(maxLevel, canvas).tips.length, greaterThan(80));
  });

  test('a prestige back to level 1 shows the seedling again', () {
    final TreeShape seedling = TreeShape.at(1, canvas);
    expect(TreeShape.at(0, canvas).branches.length, seedling.branches.length);
  });

  test('the tree stays inside its picture at full size', () {
    final TreeShape tree = TreeShape.at(maxLevel, canvas);
    for (final TreeBranch branch in tree.branches) {
      expect(branch.end.dx, inInclusiveRange(0, canvas.width));
      expect(branch.end.dy, inInclusiveRange(0, canvas.height));
    }
  });

  test('every stage paints', () {
    for (int level = 1; level <= maxLevel; level++) {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      LevelTreePainter(level: level).paint(Canvas(recorder), canvas);
      recorder.endRecording().dispose();
    }
  });

  test('it repaints only when the level changes', () {
    expect(
      LevelTreePainter(level: 5).shouldRepaint(LevelTreePainter(level: 5)),
      isFalse,
    );
    expect(
      LevelTreePainter(level: 6).shouldRepaint(LevelTreePainter(level: 5)),
      isTrue,
    );
  });

  testWidgets('it describes itself for screen readers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: LevelTree(level: 54))),
    );
    expect(
      find.bySemanticsLabel('Your tree, stage 54 of 100: Mature tree'),
      findsOneWidget,
    );
  });
}
