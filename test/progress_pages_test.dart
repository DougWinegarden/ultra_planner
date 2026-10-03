import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/progress/leaderboard_page.dart';
import 'package:ultra_planner/progress/leveling.dart';
import 'package:ultra_planner/progress/player_profile.dart';
import 'package:ultra_planner/progress/profile_page.dart';
import 'package:ultra_planner/progress/progress_repository.dart';
import 'package:ultra_planner/widgets/ocean_xp_bar.dart';

/// Stands in for the Cloud Functions, recording what was asked of it.
class FakeProgressService implements ProgressService {
  final List<String> calls = <String>[];
  ProgressException? failWith;

  @override
  Future<void> setUsername(String adjective, String creature) async {
    calls.add('setUsername $adjective $creature');
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> prestige() async => calls.add('prestige');

  @override
  Future<void> ensureProfile() async => calls.add('ensureProfile');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final DateTime now = DateTime(2026, 10, 2, 15);

Map<String, dynamic> profileDoc({
  String name = 'Brave Otter',
  String initials = 'BO',
  int xp = 0,
  int? totalXp,
  int prestige = 0,
  int todayXp = 0,
}) {
  return <String, dynamic>{
    'displayName': name,
    'adjective': name.split(' ').first,
    'creature': name.split(' ').last,
    'initials': initials,
    'xp': xp,
    'totalXp': totalXp ?? xp,
    'prestige': prestige,
    'todayXp': todayXp,
    'xpDay': '2026-10-02',
    'xpDayEndsAt': Timestamp.fromDate(DateTime(2026, 10, 3)),
  };
}

void main() {
  late FakeFirebaseFirestore db;
  late ProgressRepository repo;
  late FakeProgressService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = ProgressRepository(uid: 'me', firestore: db);
    service = FakeProgressService();
  });

  /// Pumps [page] with a still sea, so the XP bar's waves do not keep the
  /// test from settling.
  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('PlayerProfile', () {
    test('missing fields read as a fresh level-1 player', () async {
      await db.collection('profiles').doc('me').set(<String, dynamic>{});
      final PlayerProfile profile = PlayerProfile.fromDoc(
        await db.collection('profiles').doc('me').get(),
      );
      expect(profile.level, 1);
      expect(profile.displayName, 'New sailor');
      expect(profile.initials, '?');
    });

    test('today\'s XP stops counting once its day is over', () {
      final PlayerProfile profile = PlayerProfile(
        uid: 'me',
        displayName: 'Brave Otter',
        initials: 'BO',
        todayXp: dailyXpCap,
        xpDayEndsAt: DateTime(2026, 10, 3),
      );
      expect(profile.dailyCapReachedAt(DateTime(2026, 10, 2, 23)), isTrue);
      expect(profile.todayXpAt(DateTime(2026, 10, 3, 0, 1)), 0);
    });
  });

  group('profile page', () {
    testWidgets('shows name, level, progress and today\'s XP', (
      WidgetTester tester,
    ) async {
      final int xp = xpForLevel(54) + 1000;
      await db
          .collection('profiles')
          .doc('me')
          .set(profileDoc(xp: xp, todayXp: 40000));

      await pump(
        tester,
        ProfilePage(repository: repo, service: service, clock: () => now),
      );

      expect(find.text('Brave Otter'), findsOneWidget);
      expect(find.text('BO'), findsOneWidget);
      expect(find.text('Level 54'), findsOneWidget);
      expect(
        find.text('${formatXp(xpForLevel(55) - xp)} XP to level 55'),
        findsOneWidget,
      );
      expect(find.text('Today: 40,000 / 160,000 XP'), findsOneWidget);
      expect(find.text('Mature tree'), findsOneWidget);
      // Not at level 100, so no way to prestige yet.
      expect(find.text('Prestige'), findsNothing);
    });

    testWidgets('a capped day says so', (WidgetTester tester) async {
      await db
          .collection('profiles')
          .doc('me')
          .set(profileDoc(xp: 500000, todayXp: dailyXpCap));

      await pump(
        tester,
        ProfilePage(repository: repo, service: service, clock: () => now),
      );

      expect(find.textContaining('Daily limit reached'), findsOneWidget);
    });

    testWidgets('level 100 can prestige, after confirming', (
      WidgetTester tester,
    ) async {
      await db
          .collection('profiles')
          .doc('me')
          .set(profileDoc(xp: xpForLevel(maxLevel) + 2500));

      await pump(
        tester,
        ProfilePage(repository: repo, service: service, clock: () => now),
      );

      expect(find.text('MAX LEVEL'), findsOneWidget);
      expect(find.text('Fully grown'), findsOneWidget);
      expect(find.textContaining('2,500 XP banked'), findsOneWidget);

      final Finder button = find.text('Prestige');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Prestige for 🐚 Seashell?'), findsOneWidget);

      // The page's button and the dialog's: confirm in the dialog.
      await tester.tap(find.text('Prestige').last);
      await tester.pumpAndSettle();
      expect(service.calls, <String>['prestige']);
    });

    testWidgets('prestige badges show on the profile', (
      WidgetTester tester,
    ) async {
      await db
          .collection('profiles')
          .doc('me')
          .set(profileDoc(xp: 100, prestige: 3));

      await pump(
        tester,
        ProfilePage(repository: repo, service: service, clock: () => now),
      );

      expect(find.text('🐚'), findsOneWidget);
      expect(find.text('🦀'), findsOneWidget);
      expect(find.text('🐠'), findsOneWidget);
    });

    testWidgets('the name is chosen from the lists, never typed', (
      WidgetTester tester,
    ) async {
      await db.collection('profiles').doc('me').set(profileDoc());
      await pump(
        tester,
        ProfilePage(repository: repo, service: service, clock: () => now),
      );

      await tester.tap(find.byTooltip('Change your name'));
      await tester.pumpAndSettle();

      expect(find.text('Choose your sailor name'), findsOneWidget);
      // The whole point: there is nowhere to type a name.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);

      await tester.tap(find.text('Otter').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Narwhal').last);
      await tester.pumpAndSettle();
      expect(find.text('Brave Narwhal'), findsOneWidget);
      expect(find.text('BN'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(service.calls, <String>['setUsername Brave Narwhal']);
      expect(find.text('Choose your sailor name'), findsNothing);
    });

    testWidgets('a taken name keeps the picker open with the reason', (
      WidgetTester tester,
    ) async {
      service.failWith = const ProgressException(
        'Someone is already Brave Otter. Try another.',
        nameTaken: true,
      );
      await db.collection('profiles').doc('me').set(profileDoc());
      await pump(
        tester,
        ProfilePage(repository: repo, service: service, clock: () => now),
      );

      await tester.tap(find.byTooltip('Change your name'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Choose your sailor name'), findsOneWidget);
      expect(
        find.text('Someone is already Brave Otter. Try another.'),
        findsOneWidget,
      );
    });
  });

  group('leaderboard', () {
    testWidgets('ranks by lifetime XP, with medals and badges', (
      WidgetTester tester,
    ) async {
      final CollectionReference<Map<String, dynamic>> profiles = db.collection(
        'profiles',
      );
      // A prestiged player at a low level still outranks a level-99 player:
      // their lifetime XP is higher.
      await profiles
          .doc('a')
          .set(
            profileDoc(
              name: 'Swift Orca',
              initials: 'SO',
              xp: 5000,
              totalXp: xpForLevel(maxLevel) + 5000,
              prestige: 1,
            ),
          );
      await profiles
          .doc('b')
          .set(
            profileDoc(name: 'Calm Crab', initials: 'CC', xp: xpForLevel(99)),
          );
      await profiles
          .doc('me')
          .set(profileDoc(xp: xpForLevel(30), initials: 'BO'));

      await pump(tester, LeaderboardPage(repository: repo));

      final List<String> order = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .where(
            (String s) =>
                s == 'Swift Orca' ||
                s == 'Calm Crab' ||
                s == 'Brave Otter (you)',
          )
          .toList();
      expect(order, <String>['Swift Orca', 'Calm Crab', 'Brave Otter (you)']);
      expect(find.text('🥇'), findsOneWidget);
      expect(find.text('🐚'), findsOneWidget);
      expect(find.text('Lv ${levelForXp(5000)}'), findsOneWidget);
      expect(find.text('Lv 99'), findsOneWidget);
    });

    testWidgets('shows a friendly note when nobody has played yet', (
      WidgetTester tester,
    ) async {
      await pump(tester, LeaderboardPage(repository: repo));
      expect(find.textContaining('No sailors yet'), findsOneWidget);
    });
  });

  group('XP bar', () {
    testWidgets('shows its label and level, and opens on tap', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pump(
        tester,
        Scaffold(
          body: OceanXpBar(
            level: 12,
            fraction: 0.4,
            label: '400 / 1,000 XP',
            onTap: () => taps++,
          ),
        ),
      );

      expect(find.text('12'), findsOneWidget);
      expect(find.text('400 / 1,000 XP'), findsOneWidget);
      await tester.tap(find.byType(OceanXpBar));
      expect(taps, 1);
    });

    testWidgets('the sea moves unless motion is turned down', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OceanXpBar(level: 3, fraction: 0.5, label: 'x')),
        ),
      );
      final WaterTubePainter first = _tubePainter(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(_tubePainter(tester).phase, isNot(first.phase));
    });
  });
}

WaterTubePainter _tubePainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((CustomPaint p) => p.painter)
    .whereType<WaterTubePainter>()
    .single;
