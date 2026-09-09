import 'package:cloud_firestore/cloud_firestore.dart';

/// A single to-do inside a [TaskListData].
///
/// Backed by a document in the top-level `tasks` collection. [id] is empty only
/// for an item that has not been written to Firestore yet.
class TaskItem {
  TaskItem({
    this.id = '',
    required this.name,
    this.dueDate,
    this.isDone = false,
    this.listId = '',
    this.createdAt,
  });

  factory TaskItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return TaskItem(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      isDone: (data['isDone'] as bool?) ?? false,
      listId: (data['listId'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  String name;
  DateTime? dueDate;
  bool isDone;
  String listId;
  DateTime? createdAt;

  Map<String, dynamic> toFirestore(String ownerId) {
    return <String, dynamic>{
      'ownerId': ownerId,
      'listId': listId,
      'name': name,
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
      'isDone': isDone,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
    };
  }
}

/// A named list of tasks, backed by a document in the top-level `lists`
/// collection. Tasks are stitched in by [PlannerRepository].
class TaskListData {
  TaskListData({
    this.id = '',
    required this.name,
    List<TaskItem>? tasks,
    this.order = 0,
    this.createdAt,
  }) : tasks = tasks ?? <TaskItem>[];

  factory TaskListData.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return TaskListData(
      id: doc.id,
      name: (data['name'] as String?) ?? 'Untitled list',
      order: (data['order'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  String name;
  final List<TaskItem> tasks;
  int order;
  DateTime? createdAt;

  Map<String, dynamic> toFirestore(String ownerId) {
    return <String, dynamic>{
      'ownerId': ownerId,
      'name': name,
      'order': order,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
    };
  }
}

/// Pairing of a task with the list it belongs to, used by the calendar views.
class DatedTask {
  const DatedTask({required this.list, required this.task});

  final TaskListData list;
  final TaskItem task;
}
