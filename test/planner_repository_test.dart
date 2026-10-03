import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/data/models.dart';
import 'package:ultra_planner/data/planner_repository.dart';
import 'package:ultra_planner/data/task_changes.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PlannerRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = PlannerRepository(uid: 'user-a', firestore: db);
  });

  test('createList writes an owned document', () async {
    final String id = await repo.createList('School', order: 2);

    final DocumentSnapshot<Map<String, dynamic>> doc = await db
        .collection('lists')
        .doc(id)
        .get();

    expect(doc.data()!['name'], 'School');
    expect(doc.data()!['ownerId'], 'user-a');
    expect(doc.data()!['order'], 2);
  });

  test('watchLists attaches tasks to their parent list', () async {
    final String listId = await repo.createList('School');
    await repo.addTask(listId: listId, name: 'Read chapter 8');

    final List<TaskListData> lists = await repo.watchLists().first;

    expect(lists, hasLength(1));
    expect(lists.single.name, 'School');
    expect(lists.single.tasks.map((TaskItem t) => t.name), <String>[
      'Read chapter 8',
    ]);
  });

  test('watchLists excludes other users data', () async {
    await repo.createList('Mine');
    final PlannerRepository other = PlannerRepository(
      uid: 'user-b',
      firestore: db,
    );
    await other.createList('Theirs');
    await other.addTask(listId: 'nonexistent', name: 'Their task');

    final List<TaskListData> lists = await repo.watchLists().first;

    expect(lists.map((TaskListData l) => l.name), <String>['Mine']);
  });

  test('lists are ordered by order field, then name', () async {
    await repo.createList('Zebra', order: 0);
    await repo.createList('Apple', order: 0);
    await repo.createList('First', order: -1);

    final List<TaskListData> lists = await repo.watchLists().first;

    expect(lists.map((TaskListData l) => l.name), <String>[
      'First',
      'Apple',
      'Zebra',
    ]);
  });

  test('dated tasks sort before undated ones', () async {
    final String listId = await repo.createList('Mixed');
    await repo.addTask(listId: listId, name: 'No date');
    await repo.addTask(
      listId: listId,
      name: 'Later',
      dueDate: DateTime(2026, 3, 2),
    );
    await repo.addTask(
      listId: listId,
      name: 'Sooner',
      dueDate: DateTime(2026, 3, 1),
    );

    final List<TaskListData> lists = await repo.watchLists().first;

    expect(lists.single.tasks.map((TaskItem t) => t.name), <String>[
      'Sooner',
      'Later',
      'No date',
    ]);
  });

  test('setTaskDone and setTaskDueDate persist', () async {
    final String listId = await repo.createList('School');
    final String taskId = await repo.addTask(listId: listId, name: 'Essay');

    await repo.setTaskDone(taskId, true);
    await repo.setTaskDueDate(taskId, DateTime(2026, 5, 4));

    final TaskItem task = TaskItem.fromDoc(
      await db.collection('tasks').doc(taskId).get(),
    );

    expect(task.isDone, isTrue);
    expect(task.dueDate, DateTime(2026, 5, 4));
  });

  test('deleteList removes the list and cascades to its tasks', () async {
    final String keptId = await repo.createList('Keep');
    final String doomedId = await repo.createList('Doomed');
    await repo.addTask(listId: doomedId, name: 'Goes away');
    await repo.addTask(listId: doomedId, name: 'Also goes away');
    await repo.addTask(listId: keptId, name: 'Survives');

    await repo.deleteList(doomedId);

    final List<TaskListData> lists = await repo.watchLists().first;
    expect(lists.map((TaskListData l) => l.name), <String>['Keep']);

    // The cascade matters: orphaned tasks would still show in calendar views.
    final QuerySnapshot<Map<String, dynamic>> tasks = await db
        .collection('tasks')
        .get();
    expect(tasks.docs, hasLength(1));
    expect(tasks.docs.single.data()['name'], 'Survives');
  });

  test('seedStarterLists only seeds an empty account', () async {
    await repo.seedStarterLists();
    final int afterFirst = (await repo.watchLists().first).length;

    await repo.seedStarterLists();
    final int afterSecond = (await repo.watchLists().first).length;

    expect(afterFirst, 2);
    expect(afterSecond, afterFirst);
  });

  group('stream stays consistent across updates', () {
    // Regression: _stitch used to append into the cached TaskListData objects,
    // so every tasks-only snapshot stacked another copy of every task onto the
    // previous result. Firestore stayed correct, which is why a refresh looked
    // fine while adding or deleting duplicated rows on screen.

    test('adding a task does not duplicate the existing ones', () async {
      final String listId = await repo.createList('School');
      await repo.addTask(listId: listId, name: 'First');

      final List<List<TaskListData>> seen = <List<TaskListData>>[];
      final StreamSubscription<List<TaskListData>> sub = repo
          .watchLists()
          .listen(seen.add);
      await pumpEventQueue();

      await repo.addTask(listId: listId, name: 'Second');
      await pumpEventQueue();

      expect(seen.last.single.tasks.map((TaskItem t) => t.name), <String>[
        'First',
        'Second',
      ]);
      await sub.cancel();
    });

    test('deleting a task leaves the survivors intact', () async {
      final String listId = await repo.createList('School');
      final String doomed = await repo.addTask(listId: listId, name: 'Doomed');
      await repo.addTask(listId: listId, name: 'Survivor');

      final List<List<TaskListData>> seen = <List<TaskListData>>[];
      final StreamSubscription<List<TaskListData>> sub = repo
          .watchLists()
          .listen(seen.add);
      await pumpEventQueue();

      await repo.deleteTask(doomed);
      await pumpEventQueue();

      expect(seen.last.single.tasks.map((TaskItem t) => t.name), <String>[
        'Survivor',
      ]);
      await sub.cancel();
    });

    test('many updates in a row do not accumulate copies', () async {
      final String listId = await repo.createList('School');

      final List<List<TaskListData>> seen = <List<TaskListData>>[];
      final StreamSubscription<List<TaskListData>> sub = repo
          .watchLists()
          .listen(seen.add);
      await pumpEventQueue();

      for (int i = 0; i < 4; i++) {
        await repo.addTask(listId: listId, name: 'Task $i');
        await pumpEventQueue();
      }

      expect(seen.last.single.tasks, hasLength(4));
      await sub.cancel();
    });
  });

  test('a task keeps its time of day and duration', () async {
    final String listId = await repo.createList('Home');
    final String taskId = await repo.addTask(
      listId: listId,
      name: 'Soccer',
      dueDate: DateTime(2026, 10, 3, 16, 30),
      hasTime: true,
      durationMinutes: 90,
    );

    final TaskItem task = TaskItem.fromDoc(
      await db.collection('tasks').doc(taskId).get(),
    );

    expect(task.hasTime, isTrue);
    expect(task.dueDate, DateTime(2026, 10, 3, 16, 30));
    expect(task.durationMinutes, 90);
  });

  test('a task saved before times existed reads as all-day', () async {
    final DocumentReference<Map<String, dynamic>> ref = await db
        .collection('tasks')
        .add(<String, dynamic>{
          'ownerId': 'user-a',
          'listId': 'l',
          'name': 'Legacy',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 3, 14, 7)),
          'isDone': false,
        });

    final TaskItem task = TaskItem.fromDoc(await ref.get());

    expect(task.hasTime, isFalse);
    expect(task.durationMinutes, isNull);
  });

  group('applying Quackers changes', () {
    late String listId;

    setUp(() async {
      listId = await repo.createList('School');
    });

    Future<TaskItem> read(String taskId) async =>
        TaskItem.fromDoc(await db.collection('tasks').doc(taskId).get());

    TaskState stateOf(TaskItem task) => TaskState.fromTask(task);

    test('create, update and delete land together', () async {
      final String moving = await repo.addTask(
        listId: listId,
        name: 'Math',
        dueDate: DateTime(2026, 10, 2, 17),
        hasTime: true,
      );
      final String doomed = await repo.addTask(listId: listId, name: 'Old');
      final TaskState mathBefore = stateOf(await read(moving));

      await repo.applyTaskChanges(<TaskChange>[
        TaskChange.create(
          TaskState(
            name: 'Gym',
            listId: listId,
            date: DateTime(2026, 10, 5),
            startMinute: 15 * 60,
            durationMinutes: 30,
          ),
        ),
        TaskChange.update(
          taskId: moving,
          before: mathBefore,
          after: TaskState(
            name: 'Math',
            listId: listId,
            date: DateTime(2026, 10, 3),
            startMinute: 17 * 60,
          ),
        ),
        TaskChange.delete(taskId: doomed, before: stateOf(await read(doomed))),
      ]);

      final List<TaskItem> tasks = (await repo.watchLists().first).single.tasks;
      expect(tasks.map((TaskItem t) => t.name), <String>['Math', 'Gym']);
      expect(tasks.first.dueDate, DateTime(2026, 10, 3, 17));
      expect(tasks.last.hasTime, isTrue);
      expect(tasks.last.durationMinutes, 30);
      expect(tasks.last.dueDate, DateTime(2026, 10, 5, 15));
    });

    test('undo puts every task back as it was', () async {
      final String kept = await repo.addTask(
        listId: listId,
        name: 'Essay',
        dueDate: DateTime(2026, 10, 2),
      );
      final String doomed = await repo.addTask(listId: listId, name: 'Old');
      final Map<String, dynamic> essayBefore =
          (await db.collection('tasks').doc(kept).get()).data()!;
      final TaskState essayState = stateOf(await read(kept));

      final TaskRestorePoint point = await repo.applyTaskChanges(<TaskChange>[
        TaskChange.create(TaskState(name: 'New', listId: listId)),
        TaskChange.update(
          taskId: kept,
          before: essayState,
          after: TaskState(
            name: 'Essay',
            listId: listId,
            date: DateTime(2026, 10, 9),
            done: true,
          ),
        ),
        TaskChange.delete(taskId: doomed, before: stateOf(await read(doomed))),
      ]);
      await repo.restore(point);

      final QuerySnapshot<Map<String, dynamic>> all = await db
          .collection('tasks')
          .get();
      expect(all.docs.map((d) => d.data()['name']).toSet(), <String>{
        'Essay',
        'Old',
      });
      // The doomed task comes back under its own id, not as a copy.
      expect(all.docs.map((d) => d.id), contains(doomed));
      expect(
        (await db.collection('tasks').doc(kept).get()).data(),
        essayBefore,
      );
    });

    test('an update writes only what it changes', () async {
      final String taskId = await repo.addTask(
        listId: listId,
        name: 'Essay',
        dueDate: DateTime(2026, 10, 2),
      );
      final TaskState before = stateOf(await read(taskId));

      // The user ticks it off by hand while the proposal is still on screen.
      await repo.setTaskDone(taskId, true);

      await repo.applyTaskChanges(<TaskChange>[
        TaskChange.update(
          taskId: taskId,
          before: before,
          after: TaskState(
            name: 'Essay',
            listId: listId,
            date: DateTime(2026, 10, 4),
          ),
        ),
      ]);

      final TaskItem task = await read(taskId);
      expect(task.dueDate, DateTime(2026, 10, 4));
      expect(task.isDone, isTrue, reason: 'the move must not reopen it');
    });

    test('a task deleted in the meantime stops the whole apply', () async {
      final String gone = await repo.addTask(listId: listId, name: 'Gone');
      final String other = await repo.addTask(listId: listId, name: 'Other');
      final TaskState goneState = stateOf(await read(gone));
      final TaskState otherState = stateOf(await read(other));
      await repo.deleteTask(gone);

      await expectLater(
        repo.applyTaskChanges(<TaskChange>[
          TaskChange.update(
            taskId: other,
            before: otherState,
            after: TaskState(name: 'Other', listId: listId, done: true),
          ),
          TaskChange.update(
            taskId: gone,
            before: goneState,
            after: TaskState(name: 'Gone', listId: listId, done: true),
          ),
        ]),
        throwsA(isA<StaleTaskChangeException>()),
      );
      // Nothing was written: the batch never committed.
      expect((await read(other)).isDone, isFalse);
    });

    test("another account's task is treated as missing", () async {
      final PlannerRepository other = PlannerRepository(
        uid: 'user-b',
        firestore: db,
      );
      final String theirs = await other.addTask(listId: 'x', name: 'Theirs');

      await expectLater(
        repo.applyTaskChanges(<TaskChange>[
          TaskChange.delete(
            taskId: theirs,
            before: const TaskState(name: 'Theirs', listId: 'x'),
          ),
        ]),
        throwsA(isA<StaleTaskChangeException>()),
      );
    });
  });
}
