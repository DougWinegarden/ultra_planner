import 'package:flutter/material.dart';

import '../widgets/player_badges.dart';
import 'leveling.dart';
import 'player_profile.dart';
import 'progress_repository.dart';

/// The top players, ranked by lifetime XP, so a prestige never costs a place.
class LeaderboardPage extends StatelessWidget {
  const LeaderboardPage({super.key, required this.repository});

  final ProgressRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9F8FD),
      appBar: AppBar(
        title: const Text('Leaderboard'),
        backgroundColor: const Color(0xFFE9F8FD),
        foregroundColor: const Color(0xFF003B5C),
      ),
      body: StreamBuilder<List<PlayerProfile>>(
        stream: repository.watchLeaderboard(),
        builder:
            (BuildContext context, AsyncSnapshot<List<PlayerProfile>> snap) {
              if (snap.hasError) {
                return const _Message(
                  'The leaderboard could not load. Check your connection.',
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final List<PlayerProfile> players = snap.data!;
              if (players.isEmpty) {
                return const _Message(
                  'No sailors yet. Finish a task to get on the board!',
                );
              }

              final bool meListed = players.any(
                (PlayerProfile p) => p.uid == repository.uid,
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: <Widget>[
                  for (int i = 0; i < players.length; i++)
                    _LeaderboardRow(
                      rank: _rankAt(players, i),
                      player: players[i],
                      isMe: players[i].uid == repository.uid,
                    ),
                  if (!meListed) _MyRank(repository: repository),
                ],
              );
            },
      ),
    );
  }

  /// Players with the same XP share a place.
  static int _rankAt(List<PlayerProfile> players, int index) {
    int rank = index;
    while (rank > 0 && players[rank - 1].totalXp == players[index].totalXp) {
      rank--;
    }
    return rank + 1;
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.player,
    required this.isMe,
  });

  final int rank;
  final PlayerProfile player;
  final bool isMe;

  static const List<String> _medals = <String>['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isMe ? const Color(0xFFCDEFFA) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isMe ? const Color(0xFF0077B6) : const Color(0xFFBDE7F3),
          width: isMe ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 34,
              child: Text(
                rank <= 3 ? _medals[rank - 1] : '#$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: rank <= 3 ? 22 : 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF41708A),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InitialsAvatar(initials: player.initials, radius: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isMe ? '${player.displayName} (you)' : player.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF003B5C),
                    ),
                  ),
                  PrestigeBadges(
                    prestige: player.prestige,
                    size: 16,
                    maxShown: 5,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  'Lv ${player.level}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0077B6),
                  ),
                ),
                Text(
                  '${formatXpShort(player.totalXp)} XP',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF41708A),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Your own place, when you are not in the top of the list.
class _MyRank extends StatelessWidget {
  const _MyRank({required this.repository});

  final ProgressRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerProfile?>(
      stream: repository.watchProfile(),
      builder: (BuildContext context, AsyncSnapshot<PlayerProfile?> me) {
        if (me.data == null) return const SizedBox.shrink();
        return FutureBuilder<int>(
          future: repository.rankOf(me.data!),
          builder: (BuildContext context, AsyncSnapshot<int> rank) {
            if (!rank.hasData) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _LeaderboardRow(
                rank: rank.data!,
                player: me.data!,
                isMe: true,
              ),
            );
          },
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Color(0xFF41708A)),
        ),
      ),
    );
  }
}
