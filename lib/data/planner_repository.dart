import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'models.dart';
import 'task_changes.dart';

/// Reads and writes the signed-in user's lists and tasks.
///
/// Firestore layout (see SETUP.md):
///
///   lists/{listId}  { ownerId, name, order, createdAt }
///   tasks/{taskId}  { ownerId, listId, name, dueDate, hasTime,
///                     durationMinutes, isDone, createdAt }
///
/// Both are top-level collections scoped by an `ownerId` field, which is what
/// firestore.rules matches against `request.auth.uid`.
class PlannerRepository {
  PlannerRepository({required this.uid, FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _lists =>
      _db.collection('lists');
  CollectionReference<Map<String, dynamic>> get _tasks =>
      _db.collection('tasks');

  Query<Map<String, dynamic>> get _myLists =>
      _lists.where('ownerId', isEqualTo: uid);
  Query<Map<String, dynamic>> get _myTasks =>
      _tasks.where('ownerId', isEqualTo: uid);

  /// Emits the user's lists with their tasks attached, updating whenever either
  /// underlying collection changes.
  ///
  /// The two queries are merged manually rather than with `rxdart` to keep the
  /// dependency list small. Nothing is emitted until both have delivered a first
  /// snapshot, so the UI never briefly renders lists with no tasks.
  Stream<List<TaskListData>> watchLists() {
    final StreamController<List<TaskListData>> controller =
        StreamController<List<TaskListData>>.broadcast();

    List<TaskListData>? lists;
    List<TaskItem>? tasks;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? listSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? taskSub;

    void emit() {
      if (lists == null || tasks == null || controller.isClosed) {
        return;
      }
      controller.add(_stitch(lists!, tasks!));
    }

    controller.onListen = () {
      listSub = _myLists.snapshots().listen(
        (QuerySnapshot<Map<String, dynamic>> snapshot) {
          lists = snapshot.docs.map(TaskListData.fromDoc).toList();
          emit();
        },
        onError: controller.addError,
      );
      taskSub = _myTasks.snapshots().listen(
        (QuerySnapshot<Map<String, dynamic>> snapshot) {
          tasks = snapshot.docs.map(TaskItem.fromDoc).toList();
          emit();
        },
        onError: controller.addError,
      );
    };

    controller.onCancel = () async {
      await listSub?.cancel();
      await taskSub?.cancel();
    };

    return controller.stream;
  }

  /// Groups [tasks] under their parent list and applies a stable sort order.
  ///
  /// Sorting happens on the client so that neither query needs a composite
  /// Firestore index, which would otherwise have to be deployed by hand.
  List<TaskListData> _stitch(List<TaskListData> lists, List<TaskItem> tasks) {
    // Rebuild each list instead of reusing the cached instances. `lists` is
    // held between emissions, so appending into those same objects stacked
    // another copy of every task onto the previous stitch each time a
    // tasks-only snapshot arrived: Firestore stayed correct while the UI showed
    // duplicates until the next full reload.
    final Map<String, TaskListData> byId = <String, TaskListData>{
      for (final TaskListData list in lists)
        list.id: TaskListData(
          id: list.id,
          name: list.name,
          order: list.order,
          createdAt: list.createdAt,
        ),
    };

    for (final TaskItem task in tasks) {
      byId[task.listId]?.tasks.add(task);
    }

    for (final TaskListData list in byId.values) {
      list.tasks.sort((TaskItem a, TaskItem b) {
        // Undated tasks sink below dated ones; ties break on creation time.
        if (a.dueDate == null && b.dueDate != null) return 1;
        if (a.dueDate != null && b.dueDate == null) return -1;
        if (a.dueDate != null && b.dueDate != null) {
          final int byDate = a.dueDate!.compareTo(b.dueDate!);
          if (byDate != 0) return byDate;
        }
        final DateTime aMade = a.createdAt ?? DateTime(1970);
        final DateTime bMade = b.createdAt ?? DateTime(1970);
        return aMade.compareTo(bMade);
      });
    }

    final List<TaskListData> ordered = byId.values.toList()
      ..sort((TaskListData a, TaskListData b) {
        final int byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return ordered;
  }

  Future<String> createList(String name, {int order = 0}) async {
    final DocumentReference<Map<String, dynamic>> doc = await _lists.add(
      TaskListData(name: name, order: order).toFirestore(uid),
    );
    return doc.id;
  }

  Future<void> renameList(String listId, String name) {
    return _lists.doc(listId).update(<String, dynamic>{'name': name});
  }

  /// Deletes a list along with every task that points at it.
  ///
  /// Firestore has no cascading delete, so orphaned tasks would otherwise keep
  /// showing up in the calendar views.
  Future<void> deleteList(String listId) async {
    final QuerySnapshot<Map<String, dynamic>> owned = await _tasks
        .where('ownerId', isEqualTo: uid)
        .where('listId', isEqualTo: listId)
        .get();

    // A write batch caps out at 500 operations, so delete in chunks and leave
    // room for the parent list document itself.
    final List<DocumentSnapshot<Map<String, dynamic>>> docs = owned.docs;
    for (int start = 0; start < docs.length; start += 400) {
      final WriteBatch batch = _db.batch();
      for (final DocumentSnapshot<Map<String, dynamic>> doc
          in docs.skip(start).take(400)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    await _lists.doc(listId).delete();
  }

  Future<String> addTask({
    required String listId,
    required String name,
    DateTime? dueDate,
    bool hasTime = false,
    int? durationMinutes,
  }) async {
    final DocumentReference<Map<String, dynamic>> doc = await _tasks.add(
      TaskItem(
        name: name,
        dueDate: dueDate,
        hasTime: hasTime,
        durationMinutes: durationMinutes,
        listId: listId,
      ).toFirestore(uid),
    );
    return doc.id;
  }

  Future<void> setTaskDone(String taskId, bool isDone) {
    return _tasks.doc(taskId).update(<String, dynamic>{'isDone': isDone});
  }

  Future<void> setTaskDueDate(String taskId, DateTime? dueDate) {
    return _tasks.doc(taskId).update(<String, dynamic>{
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate),
    });
  }

  Future<void> deleteTask(String taskId) => _tasks.doc(taskId).delete();

  /// Writes a set of Quackers' proposed changes as one batch, so they land
  /// together or not at all, and returns what [restore] needs to undo them.
  ///
  /// Every task being updated or deleted is read first. That both captures it
  /// for undo and catches a task deleted since Quackers looked, which would
  /// otherwise fail the whole batch with a less helpful error.
  ///
  /// Throws [StaleTaskChangeException] if a task is gone.
  Future<TaskRestorePoint> applyTaskChanges(List<TaskChange> changes) async {
    final Map<String, Map<String, dynamic>?> prior =
        <String, Map<String, dynamic>?>{};
    final WriteBatch batch = _db.batch();

    for (final TaskChange change in changes) {
      if (change.kind == TaskChangeKind.create) {
        final TaskState after = change.after!;
        final DocumentReference<Map<String, dynamic>> ref = _tasks.doc();
        prior[ref.id] = null;
        batch.set(
          ref,
          TaskItem(
            name: after.name,
            listId: after.listId,
            dueDate: after.dueDate,
            hasTime: after.hasTime,
            durationMinutes: after.durationMinutes,
            isDone: after.done,
          ).toFirestore(uid),
        );
        continue;
      }

      final DocumentReference<Map<String, dynamic>> ref = _tasks.doc(
        change.taskId,
      );
      Map<String, dynamic>? current;
      try {
        current = (await ref.get()).data();
      } on FirebaseException catch (error) {
        // The rules match on the document's ownerId, and a deleted document
        // has none, so reading one is denied rather than coming back empty.
        if (error.code != 'permission-denied') rethrow;
      }
      if (current == null || current['ownerId'] != uid) {
        throw StaleTaskChangeException(change.before!.name);
      }
      prior.putIfAbsent(ref.id, () => current);

      if (change.kind == TaskChangeKind.delete) {
        batch.delete(ref);
      } else {
        final Map<String, dynamic> fields = _changedFields(change);
        if (fields.isNotEmpty) batch.update(ref, fields);
      }
    }

    await batch.commit();
    return TaskRestorePoint(prior);
  }

  /// Puts every task an apply touched back the way it was: created tasks are
  /// deleted, and changed or deleted ones are rewritten from their saved copy.
  Future<void> restore(TaskRestorePoint point) async {
    final WriteBatch batch = _db.batch();
    point.priorDocs.forEach((String id, Map<String, dynamic>? data) {
      if (data == null) {
        batch.delete(_tasks.doc(id));
      } else {
        batch.set(_tasks.doc(id), data);
      }
    });
    await batch.commit();
  }

  /// Only the fields an update actually changes, so anything the user edited
  /// by hand while the proposal sat on screen survives it.
  Map<String, dynamic> _changedFields(TaskChange change) {
    final TaskState before = change.before!;
    final TaskState after = change.after!;
    return <String, dynamic>{
      if (after.name != before.name) 'name': after.name,
      if (after.listId != before.listId) 'listId': after.listId,
      if (after.done != before.done) 'isDone': after.done,
      if (!after.sameScheduleAs(before)) ...<String, dynamic>{
        'dueDate': after.dueDate == null
            ? null
            : Timestamp.fromDate(after.dueDate!),
        'hasTime': after.hasTime,
      },
      if (after.durationMinutes != before.durationMinutes)
        'durationMinutes': after.durationMinutes,
    };
  }

  /// Gives a brand-new account something to look at on first sign-in.
  Future<void> seedStarterLists() async {
    final QuerySnapshot<Map<String, dynamic>> existing = await _myLists
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      return;
    }

    final String schoolId = await createList('School', order: 0);
    await createList('Shopping', order: 1);
    await addTask(
      listId: schoolId,
      name: 'Add your first task',
      dueDate: DateTime.now(),
    );
  }
}

/// A proposed change refers to a task that no longer exists, usually because
/// it was deleted after Quackers looked at the planner.
class StaleTaskChangeException implements Exception {
  const StaleTaskChangeException(this.taskName);

  final String taskName;

  @override
  String toString() => 'StaleTaskChangeException: $taskName';
}
