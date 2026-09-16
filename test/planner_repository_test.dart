import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/data/models.dart';
import 'package:ultra_planner/data/planner_repository.dart';

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
}
