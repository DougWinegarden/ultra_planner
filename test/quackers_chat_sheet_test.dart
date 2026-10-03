import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ultra_planner/data/models.dart';
import 'package:ultra_planner/data/planner_repository.dart';
import 'package:ultra_planner/data/task_changes.dart';
import 'package:ultra_planner/gemini_quackers_service.dart';
import 'package:ultra_planner/main.dart';

/// Stands in for the Cloud Function: returns a scripted reply and records the
/// snapshot it was sent.
class FakeQuackers implements GeminiQuackersService {
  FakeQuackers(this.reply);

  final QuackersReply Function(Map<String, Object?> planner) reply;
  final List<Map<String, Object?>> snapshots = <Map<String, Object?>>[];

  @override
  Future<QuackersReply> respond({
    required String question,
    required Map<String, Object?> planner,
    required List<QuackersChatMessage> conversation,
  }) async {
    snapshots.add(planner);
    return reply(planner);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeFirebaseFirestore db;
  late PlannerRepository repo;
  late String listId;
  late String mathId;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = FakeFirebaseFirestore();
    repo = PlannerRepository(uid: 'user-a', firestore: db);
    listId = await repo.createList('School');
    mathId = await repo.addTask(
      listId: listId,
      name: 'Math homework',
      dueDate: DateTime(2026, 10, 2, 17),
      hasTime: true,
    );
  });

  Future<TaskItem?> read(String id) async {
    final DocumentSnapshot<Map<String, dynamic>> doc = await db
        .collection('tasks')
        .doc(id)
        .get();
    return doc.exists ? TaskItem.fromDoc(doc) : null;
  }

  Future<void> openSheet(WidgetTester tester, FakeQuackers quackers) async {
    final List<TaskListData> lists = await repo.watchLists().first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuackersChatSheet(
            service: quackers,
            planner: repo,
            plannerSnapshot: () => buildPlannerSnapshot(
              lists,
              now: DateTime(2026, 10, 2, 14, 5),
              defaultListId: listId,
            ),
            suggestedTip: 'Start small.',
            userId: 'user-a',
            hasApiKey: true,
            onSetUpApiKey: () async => true,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets real Firestore work finish, then rebuilds. Only valid inside
  /// runAsync, where time actually passes.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  }

  Future<void> ask(WidgetTester tester, String question) async {
    await tester.enterText(find.byType(TextField), question);
    await tester.tap(find.byTooltip('Send question'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a reviewed plan is applied, then undone', (
    WidgetTester tester,
  ) async {
    final FakeQuackers quackers = FakeQuackers((Map<String, Object?> planner) {
      final Map<dynamic, dynamic> math =
          (planner['tasks']! as List<Object?>).single! as Map<dynamic, dynamic>;
      return QuackersReply(
        text: 'Moved math to tomorrow and added a workout.',
        changes: <TaskChange>[
          TaskChange.update(
            taskId: math['id'] as String,
            before: TaskState.fromJson(math),
            after: TaskState.fromJson(<String, Object?>{
              ...math,
              'date': '2026-10-03',
            }),
          ),
          TaskChange.create(
            TaskState(
              name: 'Workout',
              listId: listId,
              date: DateTime(2026, 10, 3),
              startMinute: 9 * 60,
              durationMinutes: 30,
            ),
          ),
        ],
      );
    });

    await tester.runAsync(() async {
      await openSheet(tester, quackers);
      await ask(tester, 'Move math to tomorrow and add a workout');
    });

    // Quackers saw the planner as it is, in local terms.
    final Map<dynamic, dynamic> sent =
        (quackers.snapshots.single['tasks']! as List<Object?>).single!
            as Map<dynamic, dynamic>;
    expect(sent['time'], '17:00');

    // Two changes wait for approval; nothing is written yet.
    expect(find.text('Proposed changes (2)'), findsOneWidget);
    expect(find.text('Move “Math homework”'), findsOneWidget);
    expect((await read(mathId))!.dueDate, DateTime(2026, 10, 2, 17));

    await tester.runAsync(() async {
      await tester.ensureVisible(find.text('Apply'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await settle(tester);
    });

    expect(find.text('Saved to your planner'), findsOneWidget);
    expect((await read(mathId))!.dueDate, DateTime(2026, 10, 3, 17));
    expect(
      (await db.collection('tasks').where('name', isEqualTo: 'Workout').get())
          .docs,
      hasLength(1),
    );

    await tester.runAsync(() async {
      await tester.ensureVisible(find.text('Undo'));
      await tester.pump();
      await tester.tap(find.text('Undo'));
      await settle(tester);
    });

    expect(find.text('Undone'), findsOneWidget);
    expect((await read(mathId))!.dueDate, DateTime(2026, 10, 2, 17));
    expect((await db.collection('tasks').get()).docs, hasLength(1));
  });

  testWidgets('one small change is applied without asking', (
    WidgetTester tester,
  ) async {
    final FakeQuackers quackers = FakeQuackers(
      (_) => QuackersReply(
        text: 'Added it.',
        changes: <TaskChange>[
          TaskChange.create(TaskState(name: 'Buy milk', listId: listId)),
        ],
      ),
    );

    await tester.runAsync(() async {
      await openSheet(tester, quackers);
      await ask(tester, 'Remind me to buy milk');
      await settle(tester);
    });

    expect(find.text('Saved to your planner'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(
      (await db.collection('tasks').where('name', isEqualTo: 'Buy milk').get())
          .docs,
      hasLength(1),
    );
  });

  testWidgets('cancelling writes nothing', (WidgetTester tester) async {
    final FakeQuackers quackers = FakeQuackers(
      (_) => QuackersReply(
        text: 'I would delete it.',
        changes: <TaskChange>[
          TaskChange.delete(
            taskId: mathId,
            before: TaskState(name: 'Math homework', listId: listId),
          ),
        ],
      ),
    );

    await tester.runAsync(() async {
      await openSheet(tester, quackers);
      await ask(tester, 'Delete math');
    });

    // A delete always waits, even on its own.
    expect(find.text('Proposed change'), findsOneWidget);

    await tester.ensureVisible(find.text('Cancel'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(find.text('Not applied'), findsOneWidget);
    expect(await read(mathId), isNotNull);
  });
}
