import 'package:flutter/material.dart';

import '../widgets/level_tree.dart';
import '../widgets/ocean_xp_bar.dart';
import '../widgets/player_badges.dart';
import 'leaderboard_page.dart';
import 'leveling.dart';
import 'player_profile.dart';
import 'progress_repository.dart';
import 'username_picker.dart';

/// Your progress: name, level, XP bar, today's XP, your tree, prestige.
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.repository,
    required this.service,
    this.clock = DateTime.now,
  });

  final ProgressRepository repository;
  final ProgressService service;

  /// For tests; the daily counter depends on what time it is.
  final DateTime Function() clock;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final Stream<PlayerProfile?> _profile = widget.repository.watchProfile();
  bool _prestiging = false;

  static const Color _ink = Color(0xFF003B5C);
  static const Color _muted = Color(0xFF41708A);
  static const Color _sea = Color(0xFF0077B6);

  Future<void> _changeName(PlayerProfile profile) async {
    final bool saved = await showUsernamePicker(
      context,
      service: widget.service,
      currentAdjective: profile.adjective,
      currentCreature: profile.creature,
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name saved. Ahoy!')));
    }
  }

  Future<void> _prestige(PlayerProfile profile) async {
    final PrestigeBadge badge = badgeForPrestige(profile.prestige + 1);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Prestige for ${badge.emoji} ${badge.name}?'),
        content: Text(
          'You go back to level 1 and your tree starts again as a seedling. '
          'You keep the ${badge.name} badge for good, your place on the '
          'leaderboard, and the ${formatXp(profile.progress.xpIntoLevel)} XP '
          'you have earned past level $maxLevel.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Prestige'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _prestiging = true);
    try {
      await widget.service.prestige();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${badge.emoji} Prestige ${profile.prestige + 1}! A new seedling '
            'is planted.',
          ),
        ),
      );
    } on ProgressException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _prestiging = false);
    }
  }

  void _openLeaderboard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            LeaderboardPage(repository: widget.repository),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9F8FD),
      appBar: AppBar(
        title: const Text('Your progress'),
        backgroundColor: const Color(0xFFE9F8FD),
        foregroundColor: _ink,
        actions: <Widget>[
          IconButton(
            tooltip: 'Leaderboard',
            onPressed: _openLeaderboard,
            icon: const Icon(Icons.leaderboard_outlined),
          ),
        ],
      ),
      body: StreamBuilder<PlayerProfile?>(
        stream: _profile,
        builder: (BuildContext context, AsyncSnapshot<PlayerProfile?> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final PlayerProfile profile =
              snap.data ?? PlayerProfile.starting(widget.repository.uid);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: <Widget>[
                  _buildHeader(profile),
                  const SizedBox(height: 12),
                  _buildLevelCard(profile),
                  const SizedBox(height: 12),
                  _buildTreeCard(profile),
                  const SizedBox(height: 12),
                  _buildPrestigeCard(profile),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _openLeaderboard,
                    icon: const Icon(Icons.leaderboard_outlined),
                    label: const Text('See the leaderboard'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFBDE7F3)),
    ),
    child: child,
  );

  Widget _buildHeader(PlayerProfile profile) {
    return _card(
      child: Row(
        children: <Widget>[
          InitialsAvatar(initials: profile.initials, radius: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  profile.displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _ink,
                  ),
                ),
                Text(
                  '${formatXp(profile.totalXp)} XP all time',
                  style: const TextStyle(color: _muted),
                ),
                if (profile.prestige > 0) ...<Widget>[
                  const SizedBox(height: 4),
                  PrestigeBadges(prestige: profile.prestige, size: 22),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Change your name',
            onPressed: () => _changeName(profile),
            icon: const Icon(Icons.edit_outlined, color: _sea),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelCard(PlayerProfile profile) {
    final LevelProgress progress = profile.progress;
    final DateTime now = widget.clock();
    final int today = profile.todayXpAt(now);
    final bool capped = today >= dailyXpCap;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Level ${progress.level}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: _ink,
            ),
          ),
          const SizedBox(height: 10),
          OceanXpBar(
            level: progress.level,
            fraction: progress.fraction,
            height: 34,
            label: progress.isMax
                ? 'MAX LEVEL'
                : '${formatXp(progress.xpIntoLevel)} / '
                      '${formatXp(progress.xpForLevelUp)} XP',
          ),
          const SizedBox(height: 8),
          Text(
            progress.isMax
                ? '${formatXp(progress.xpIntoLevel)} XP banked past level '
                      '$maxLevel. It carries over when you prestige.'
                : '${formatXp(progress.xpToNextLevel)} XP to level '
                      '${progress.level + 1}',
            style: const TextStyle(color: _muted),
          ),
          const Divider(height: 24),
          Row(
            children: <Widget>[
              const Text('🌊 ', style: TextStyle(fontSize: 16)),
              Expanded(
                child: Text(
                  'Today: ${formatXp(today)} / ${formatXp(dailyXpCap)} XP',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: today / dailyXpCap,
              minHeight: 8,
              color: capped ? const Color(0xFF1B8A3F) : _sea,
              backgroundColor: const Color(0xFFDDF3FA),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            capped
                ? 'Daily limit reached. Tasks earn XP again after midnight.'
                : 'Up to ${formatXp(dailyXpCap)} XP a day. Finishing a task '
                      'earns ${formatXp(baseTaskXp)}–${formatXp(maxTaskXp)} '
                      'XP, more for longer ones.',
            style: const TextStyle(fontSize: 12.5, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeCard(PlayerProfile profile) {
    final int level = profile.level;
    return _card(
      child: Column(
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                LevelTree(
                  level: level,
                  size: constraints.maxWidth.clamp(160.0, 320.0),
                ),
          ),
          const SizedBox(height: 10),
          Text(
            treeStageName(level),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _ink,
            ),
          ),
          Text(
            level >= maxLevel
                ? 'Fully grown! Prestige to plant a new seedling.'
                : 'Stage $level of $maxLevel. It grows with every level.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _buildPrestigeCard(PlayerProfile profile) {
    final PrestigeBadge next = badgeForPrestige(profile.prestige + 1);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(next.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  profile.canPrestige
                      ? 'Ready to prestige!'
                      : 'Prestige at level $maxLevel',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Prestiging starts you over at level 1 with a new seedling and '
            'earns the ${next.name} badge. It is optional: XP keeps counting '
            'at level $maxLevel, and any past it carries over when you do.',
            style: const TextStyle(color: _muted),
          ),
          if (profile.canPrestige) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _prestiging ? null : () => _prestige(profile),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Prestige'),
            ),
          ],
        ],
      ),
    );
  }
}
