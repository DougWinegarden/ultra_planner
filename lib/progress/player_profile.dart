import 'package:cloud_firestore/cloud_firestore.dart';

import 'leveling.dart';

/// A player's public progress, from `profiles/{uid}`.
///
/// Written only by the progress Cloud Functions; the app just reads it. Level
/// and bar position are worked out from [xp] here rather than trusted from the
/// stored `level`, so the two can never disagree on screen.
class PlayerProfile {
  const PlayerProfile({
    required this.uid,
    required this.displayName,
    required this.initials,
    this.adjective,
    this.creature,
    this.xp = 0,
    this.totalXp = 0,
    this.prestige = 0,
    this.todayXp = 0,
    this.xpDayEndsAt,
  });

  factory PlayerProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    int count(String field) {
      final Object? value = data[field];
      return value is num && value > 0 ? value.toInt() : 0;
    }

    final String name = data['displayName'] is String
        ? data['displayName'] as String
        : '';
    return PlayerProfile(
      uid: doc.id,
      displayName: name.isEmpty ? 'New sailor' : name,
      initials: data['initials'] is String && name.isNotEmpty
          ? data['initials'] as String
          : '?',
      adjective: data['adjective'] as String?,
      creature: data['creature'] as String?,
      xp: count('xp'),
      totalXp: count('totalXp'),
      prestige: count('prestige'),
      todayXp: count('todayXp'),
      xpDayEndsAt: (data['xpDayEndsAt'] as Timestamp?)?.toDate(),
    );
  }

  /// A player who has no profile yet: level 1, nothing earned.
  factory PlayerProfile.starting(String uid) =>
      PlayerProfile(uid: uid, displayName: 'New sailor', initials: '?');

  final String uid;
  final String displayName;
  final String initials;
  final String? adjective;
  final String? creature;

  /// XP in the current prestige cycle; may exceed level 100's requirement.
  final int xp;

  /// Lifetime XP across every prestige. The leaderboard ranks by this, so a
  /// prestige never drops anyone down it.
  final int totalXp;
  final int prestige;

  /// XP earned in the XP day that ends at [xpDayEndsAt].
  final int todayXp;
  final DateTime? xpDayEndsAt;

  int get level => levelForXp(xp);

  LevelProgress get progress => LevelProgress.of(xp);

  bool get canPrestige => xp >= xpForLevel(maxLevel);

  /// XP earned today as of [now]: zero once the stored day has ended, even
  /// before the next award rolls the counter over.
  int todayXpAt(DateTime now) {
    final DateTime? endsAt = xpDayEndsAt;
    return endsAt != null && now.isBefore(endsAt) ? todayXp : 0;
  }

  bool dailyCapReachedAt(DateTime now) => todayXpAt(now) >= dailyXpCap;
}
