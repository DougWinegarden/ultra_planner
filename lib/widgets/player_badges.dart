import 'package:flutter/material.dart';

import '../progress/leveling.dart';

/// A player's avatar: their initials on sea-blue. No pictures, by design.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.initials, this.radius = 20});

  final String initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF48CAE4), Color(0xFF0077B6)],
        ),
        border: Border.all(color: Colors.white, width: radius * 0.08),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.75,
        ),
      ),
    );
  }
}

/// The prestige badges a player holds, oldest first.
///
/// With [maxShown], only the newest ones fit and the rest are counted, which
/// keeps a long-time player's leaderboard row tidy.
class PrestigeBadges extends StatelessWidget {
  const PrestigeBadges({
    super.key,
    required this.prestige,
    this.size = 18,
    this.maxShown,
  });

  final int prestige;
  final double size;
  final int? maxShown;

  @override
  Widget build(BuildContext context) {
    if (prestige <= 0) return const SizedBox.shrink();

    final List<PrestigeBadge> all = badgesUpTo(prestige);
    final int hidden = maxShown == null
        ? 0
        : (all.length - maxShown!).clamp(0, all.length);
    final List<PrestigeBadge> shown = all.sublist(hidden);

    return Semantics(
      label: 'Prestige $prestige',
      child: Wrap(
        spacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          if (hidden > 0)
            Text(
              '+$hidden',
              style: TextStyle(
                fontSize: size * 0.6,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0077B6),
              ),
            ),
          for (final PrestigeBadge badge in shown)
            Tooltip(
              message: badge.name,
              child: Text(badge.emoji, style: TextStyle(fontSize: size)),
            ),
        ],
      ),
    );
  }
}
