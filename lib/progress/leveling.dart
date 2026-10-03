/// Levels, XP, prestige badges and tree stages.
///
/// The server decides every award (functions/progress.js). These are the app's
/// copy of the same numbers, so it can draw the XP bar and label tasks without
/// asking; a test checks every level against the server's table.
library;

import 'dart:math' as math;

const int maxLevel = 100;

/// Most XP one player can earn in a day: 89.9 days to level 100.
const int dailyXpCap = 160000;

/// A task with no length, or one of 30 minutes or less.
const int baseTaskXp = 20000;

/// Added for each further half hour a task takes.
const int xpPerExtraHalfHour = 5000;

/// No single task is worth more than this.
const int maxTaskXp = 40000;

/// XP needed to reach each level, indexed by level; [1] is 0.
///
/// The RuneScape curve: the step from level n to n+1 costs
/// floor(n + 300 * 2^(n/7)) / 4. Each level costs about 10% more than the
/// last, which is what makes level 92 half of level 99.
final List<int> _xpTable = () {
  final List<int> table = <int>[0, 0];
  int points = 0;
  for (int level = 1; level < maxLevel; level++) {
    points += (level + 300 * math.pow(2, level / 7)).floor();
    table.add(points ~/ 4);
  }
  return table;
}();

/// Total XP needed to reach [level].
int xpForLevel(int level) => _xpTable[level.clamp(1, maxLevel)];

/// The level an XP total gives, capped at [maxLevel]. XP beyond it is kept and
/// carries over into the next prestige.
int levelForXp(int xp) {
  int level = 1;
  while (level < maxLevel && _xpTable[level + 1] <= xp) {
    level++;
  }
  return level;
}

/// What finishing a task is worth: more for longer tasks, up to a limit.
int taskXp(int? durationMinutes) {
  if (durationMinutes == null || durationMinutes <= 30) return baseTaskXp;
  final int extraHalfHours = ((durationMinutes - 30) / 30).ceil();
  return math.min(maxTaskXp, baseTaskXp + extraHalfHours * xpPerExtraHalfHour);
}

/// Where an XP total sits within its level.
class LevelProgress {
  LevelProgress._({
    required this.level,
    required this.xpIntoLevel,
    required this.xpForLevelUp,
  });

  factory LevelProgress.of(int xp) {
    final int level = levelForXp(xp);
    if (level == maxLevel) {
      // Nothing left to fill: the bar stays full and the surplus is what
      // carries over on prestige.
      return LevelProgress._(
        level: level,
        xpIntoLevel: xp - xpForLevel(maxLevel),
        xpForLevelUp: 0,
      );
    }
    return LevelProgress._(
      level: level,
      xpIntoLevel: xp - xpForLevel(level),
      xpForLevelUp: xpForLevel(level + 1) - xpForLevel(level),
    );
  }

  final int level;

  /// XP earned since reaching [level]. At [maxLevel], the surplus.
  final int xpIntoLevel;

  /// The size of this level's step; 0 at [maxLevel].
  final int xpForLevelUp;

  bool get isMax => level == maxLevel;

  int get xpToNextLevel => isMax ? 0 : xpForLevelUp - xpIntoLevel;

  /// How full the bar is, 0 to 1.
  double get fraction => isMax ? 1 : xpIntoLevel / xpForLevelUp;
}

/// "20,000".
String formatXp(int xp) {
  final String digits = xp.abs().toString();
  final StringBuffer out = StringBuffer(xp < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// "20k", "1.4M": for tight spaces like a task card.
String formatXpShort(int xp) {
  if (xp >= 1000000) {
    final String millions = (xp / 1000000).toStringAsFixed(1);
    return '${millions.endsWith('.0') ? millions.substring(0, millions.length - 2) : millions}M';
  }
  if (xp >= 1000) return '${(xp / 1000).round()}k';
  return '$xp';
}

/// One prestige badge.
class PrestigeBadge {
  const PrestigeBadge(this.emoji, this.name);

  final String emoji;
  final String name;
}

/// A badge for each prestige, each cooler than the last. Past the end of the
/// list every further prestige earns another of the last one.
const List<PrestigeBadge> prestigeBadges = <PrestigeBadge>[
  PrestigeBadge('🐚', 'Seashell'),
  PrestigeBadge('🦀', 'Crab'),
  PrestigeBadge('🐠', 'Tropical fish'),
  PrestigeBadge('🐢', 'Sea turtle'),
  PrestigeBadge('🐙', 'Octopus'),
  PrestigeBadge('🐬', 'Dolphin'),
  PrestigeBadge('🦈', 'Shark'),
  PrestigeBadge('🐋', 'Whale'),
  PrestigeBadge('🧜', 'Merfolk'),
  PrestigeBadge('🔱', 'Trident'),
  PrestigeBadge('👑', 'Crown of the Sea'),
  PrestigeBadge('💎', 'Ocean Diamond'),
];

/// The badge earned at a prestige, counting from 1.
PrestigeBadge badgeForPrestige(int prestige) =>
    prestigeBadges[(prestige - 1).clamp(0, prestigeBadges.length - 1)];

/// Every badge a player holds, oldest first.
List<PrestigeBadge> badgesUpTo(int prestige) => <PrestigeBadge>[
  for (int p = 1; p <= prestige; p++) badgeForPrestige(p),
];

/// What the tree on the profile page is called at a level.
String treeStageName(int level) {
  if (level >= maxLevel) return 'Fully grown';
  if (level >= 90) return 'Fruiting';
  if (level >= 70) return 'Blossoming';
  if (level >= 45) return 'Mature tree';
  if (level >= 20) return 'Young tree';
  if (level >= 6) return 'Sapling';
  return 'Seedling';
}
