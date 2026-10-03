import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/progress/leveling.dart';

/// xpForLevel(1..100) as functions/progress.js computes it. The server grants
/// XP and the app draws the bar, so the two must agree on every level.
const List<int> serverXpTable = <int>[
  0, 83, 174, 276, 388, 512, 650, 801, 969, 1154, 1358, 1584, 1833, 2107, //
  2411, 2746, 3115, 3523, 3973, 4470, 5018, 5624, 6291, 7028, 7842, 8740,
  9730, 10824, 12031, 13363, 14833, 16456, 18247, 20224, 22406, 24815, 27473,
  30408, 33648, 37224, 41171, 45529, 50339, 55649, 61512, 67983, 75127, 83014,
  91721, 101333, 111945, 123660, 136594, 150872, 166636, 184040, 203254,
  224466, 247886, 273742, 302288, 333804, 368599, 407015, 449428, 496254,
  547953, 605032, 668051, 737627, 814445, 899257, 992895, 1096278, 1210421,
  1336443, 1475581, 1629200, 1798808, 1986068, 2192818, 2421087, 2673114,
  2951373, 3258594, 3597792, 3972294, 4385776, 4842295, 5346332, 5902831,
  6517253, 7195629, 7944614, 8771558, 9684577, 10692629, 11805606, 13034431,
  14391160,
];

void main() {
  group('the level curve', () {
    test('matches the server at every level', () {
      for (int level = 1; level <= maxLevel; level++) {
        expect(
          xpForLevel(level),
          serverXpTable[level - 1],
          reason: 'level $level',
        );
      }
    });

    test('level 92 is half of level 99', () {
      expect(xpForLevel(92) / xpForLevel(99), closeTo(0.5, 0.001));
    });

    test('the cap every day reaches level 100 in about three months', () {
      expect(xpForLevel(maxLevel) / dailyXpCap, inInclusiveRange(88, 92));
    });

    test('levels change exactly at their thresholds', () {
      expect(levelForXp(0), 1);
      expect(levelForXp(82), 1);
      expect(levelForXp(83), 2);
      expect(levelForXp(xpForLevel(57) - 1), 56);
      expect(levelForXp(xpForLevel(57)), 57);
      expect(levelForXp(xpForLevel(maxLevel) * 2), maxLevel);
    });
  });

  test('task values match the server', () {
    expect(taskXp(null), 20000);
    expect(taskXp(30), 20000);
    expect(taskXp(45), 25000);
    expect(taskXp(60), 25000);
    expect(taskXp(120), 35000);
    expect(taskXp(600), maxTaskXp);
  });

  group('LevelProgress', () {
    test('measures progress within the current level', () {
      final int start = xpForLevel(40);
      final int step = xpForLevel(41) - start;
      final LevelProgress progress = LevelProgress.of(start + step ~/ 4);

      expect(progress.level, 40);
      expect(progress.xpForLevelUp, step);
      expect(progress.fraction, closeTo(0.25, 0.001));
      expect(progress.xpToNextLevel, step - step ~/ 4);
    });

    test('a full bar at level 100 counts the surplus', () {
      final LevelProgress progress = LevelProgress.of(
        xpForLevel(maxLevel) + 5000,
      );
      expect(progress.isMax, isTrue);
      expect(progress.fraction, 1);
      expect(progress.xpIntoLevel, 5000);
      expect(progress.xpToNextLevel, 0);
    });
  });

  test('XP formats for reading and for tight spaces', () {
    expect(formatXp(0), '0');
    expect(formatXp(20000), '20,000');
    expect(formatXp(14391160), '14,391,160');
    expect(formatXpShort(950), '950');
    expect(formatXpShort(20000), '20k');
    expect(formatXpShort(1000000), '1M');
    expect(formatXpShort(14391160), '14.4M');
  });

  group('prestige badges', () {
    test('each prestige earns the next badge in the list', () {
      expect(badgeForPrestige(1).emoji, '🐚');
      expect(badgeForPrestige(2).emoji, '🦀');
      expect(badgesUpTo(3).map((PrestigeBadge b) => b.emoji), <String>[
        '🐚',
        '🦀',
        '🐠',
      ]);
    });

    test('past the end of the list the best badge repeats', () {
      final PrestigeBadge best = prestigeBadges.last;
      expect(badgeForPrestige(prestigeBadges.length + 5), best);
      expect(badgesUpTo(prestigeBadges.length + 2), hasLength(14));
    });

    test('no prestige, no badges', () {
      expect(badgesUpTo(0), isEmpty);
    });
  });

  test('the tree has a name at every stage', () {
    expect(treeStageName(1), 'Seedling');
    expect(treeStageName(10), 'Sapling');
    expect(treeStageName(50), 'Mature tree');
    expect(treeStageName(95), 'Fruiting');
    expect(treeStageName(100), 'Fully grown');
  });
}
