import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'models.dart';

/// Reads and writes the signed-in user's lists and tasks.
///
/// Firestore layout (see FIREBASE_SETUP.md):
///
///   lists/{listId}  { ownerId, name, order, createdAt }
///   tasks/{taskId}  { ownerId, listId, name, dueDate, isDone, createdAt }
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
    final Map<String, TaskListData> byId = <String, TaskListData>{
      for (final TaskListData list in lists) list.id: list,
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
  }) async {
    final DocumentReference<Map<String, dynamic>> doc = await _tasks.add(
      TaskItem(name: name, dueDate: dueDate, listId: listId).toFirestore(uid),
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
