import 'models.dart';
import 'task_time.dart';

/// A task's editable fields, as exchanged with Quackers' server.
///
/// Wire format (see functions/plannerTools.js):
///
///   { name, listId, listName, date: "YYYY-MM-DD" | null,
///     time: "HH:MM" | null, durationMinutes: int | null, done: bool }
///
/// Dates and times are local wall-clock values; [dueDate] is where they become
/// a [DateTime], on this device and in its time zone.
class TaskState {
  const TaskState({
    required this.name,
    required this.listId,
    this.listName = '',
    this.date,
    this.startMinute,
    this.durationMinutes,
    this.done = false,
  });

  factory TaskState.fromTask(TaskItem task, {String listName = ''}) {
    final DateTime? due = task.dueDate;
    return TaskState(
      name: task.name,
      listId: task.listId,
      listName: listName,
      date: due == null ? null : DateTime(due.year, due.month, due.day),
      startMinute: due != null && task.hasTime ? minuteOfDay(due) : null,
      durationMinutes: task.durationMinutes,
      done: task.isDone,
    );
  }

  /// Throws [FormatException] when a required field is missing.
  factory TaskState.fromJson(Map<dynamic, dynamic> json) {
    final Object? name = json['name'];
    final Object? listId = json['listId'];
    if (name is! String || name.trim().isEmpty || listId is! String) {
      throw const FormatException('A task change is missing its name or list.');
    }
    final DateTime? date = parseWireDate(json['date']);
    final Object? duration = json['durationMinutes'];
    return TaskState(
      name: name.trim(),
      listId: listId,
      listName: json['listName'] is String ? json['listName'] as String : '',
      date: date,
      // A time of day means nothing without a day to put it on.
      startMinute: date == null ? null : parseWireTime(json['time']),
      durationMinutes: duration is num && duration > 0
          ? duration.toInt()
          : null,
      done: json['done'] == true,
    );
  }

  final String name;
  final String listId;

  /// For display only; [listId] is what gets written.
  final String listName;

  /// Midnight on the task's day, or null for an undated task.
  final DateTime? date;

  /// Minutes after midnight, or null when the task has no time of day.
  final int? startMinute;
  final int? durationMinutes;
  final bool done;

  bool get hasTime => date != null && startMinute != null;

  /// The value for [TaskItem.dueDate].
  DateTime? get dueDate => date == null ? null : atMinute(date!, startMinute);

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'listId': listId,
    'date': date == null ? null : formatWireDate(date!),
    'time': hasTime ? formatWireTime(startMinute!) : null,
    'durationMinutes': durationMinutes,
    'done': done,
  };

  /// "Sat, Oct 3, 5:00–6:30 PM", "Sat, Oct 3" or "No date".
  String get scheduleLabel {
    if (date == null) return 'No date';
    final String day = formatShortDate(date!);
    if (!hasTime) return day;
    return '$day, $_clockLabel';
  }

  /// The time part of [scheduleLabel] alone, e.g. "5:00–6:30 PM".
  String get _clockLabel => durationMinutes == null
      ? formatClock(startMinute!)
      : formatClockRange(startMinute!, durationMinutes!);

  bool sameScheduleAs(TaskState other) =>
      date == other.date && startMinute == other.startMinute;
}

enum TaskChangeKind { create, update, delete }

/// One change Quackers proposes. The user approves it before it is written.
///
/// [before] is the task as the server saw it; [after] is what it should
/// become. An update writes only the fields that differ between the two, so a
/// field the user changed by hand in the meantime is left alone.
class TaskChange {
  const TaskChange.create(TaskState this.after)
    : kind = TaskChangeKind.create,
      taskId = null,
      before = null;

  const TaskChange.update({
    required String this.taskId,
    required TaskState this.before,
    required TaskState this.after,
  }) : kind = TaskChangeKind.update;

  const TaskChange.delete({
    required String this.taskId,
    required TaskState this.before,
  }) : kind = TaskChangeKind.delete,
       after = null;

  /// Throws [FormatException] for anything the app could not apply.
  factory TaskChange.fromJson(Map<dynamic, dynamic> json) {
    TaskState state(String key) {
      final Object? value = json[key];
      if (value is! Map) throw FormatException('A task change has no $key.');
      return TaskState.fromJson(value);
    }

    String taskId() {
      final Object? id = json['taskId'];
      if (id is! String || id.isEmpty) {
        throw const FormatException('A task change has no task id.');
      }
      return id;
    }

    switch (json['type']) {
      case 'create':
        return TaskChange.create(state('after'));
      case 'update':
        return TaskChange.update(
          taskId: taskId(),
          before: state('before'),
          after: state('after'),
        );
      case 'delete':
        return TaskChange.delete(taskId: taskId(), before: state('before'));
      default:
        throw FormatException('Unknown task change type: ${json['type']}');
    }
  }

  final TaskChangeKind kind;

  /// Null for a create.
  final String? taskId;

  /// Null for a create.
  final TaskState? before;

  /// Null for a delete.
  final TaskState? after;

  /// One line for the preview, e.g. 'Move “Math homework”'.
  String get title {
    switch (kind) {
      case TaskChangeKind.create:
        return 'Add “${after!.name}”';
      case TaskChangeKind.delete:
        return 'Delete “${before!.name}”';
      case TaskChangeKind.update:
        final TaskState b = before!;
        final TaskState a = after!;
        if (a.done != b.done && _onlyDoneChanged) {
          return a.done ? 'Mark “${b.name}” done' : 'Reopen “${b.name}”';
        }
        if (!a.sameScheduleAs(b)) return 'Move “${b.name}”';
        return 'Change “${b.name}”';
    }
  }

  /// What exactly changes, e.g. 'Fri, Oct 2, 5:00 PM → Sat, Oct 3, 5:00 PM'.
  /// Empty when the title says it all.
  String get detail {
    switch (kind) {
      case TaskChangeKind.create:
        final TaskState a = after!;
        final List<String> parts = <String>[a.scheduleLabel];
        if (!a.hasTime && a.durationMinutes != null) {
          parts.add(formatDuration(a.durationMinutes!));
        }
        if (a.listName.isNotEmpty) parts.add('in ${a.listName}');
        return parts.join(' · ');
      case TaskChangeKind.delete:
        return before!.scheduleLabel;
      case TaskChangeKind.update:
        final TaskState b = before!;
        final TaskState a = after!;
        final List<String> parts = <String>[];
        final bool moved = !a.sameScheduleAs(b);
        final bool resized = a.durationMinutes != b.durationMinutes;
        if (a.name != b.name) parts.add('Rename to “${a.name}”');
        // A timed task shows its length in the schedule label; an untimed one
        // needs it spelled out.
        if (moved || (resized && a.hasTime)) {
          // Same day, new time: say the day once.
          parts.add(
            a.date != null && a.date == b.date && a.hasTime && b.hasTime
                ? '${formatShortDate(a.date!)}: '
                      '${b._clockLabel} → ${a._clockLabel}'
                : '${b.scheduleLabel} → ${a.scheduleLabel}',
          );
        }
        if (resized && !a.hasTime) {
          parts.add(
            a.durationMinutes == null
                ? 'No set length'
                : 'Takes ${formatDuration(a.durationMinutes!)}',
          );
        }
        if (a.listId != b.listId) parts.add('Move to ${a.listName}');
        if (a.done != b.done && !_onlyDoneChanged) {
          parts.add(a.done ? 'Mark done' : 'Mark not done');
        }
        return parts.join(' · ');
    }
  }

  bool get _onlyDoneChanged {
    final TaskState b = before!;
    final TaskState a = after!;
    return a.name == b.name &&
        a.listId == b.listId &&
        a.sameScheduleAs(b) &&
        a.durationMinutes == b.durationMinutes;
  }
}

/// Every task document an apply touched, as it was beforehand, so the whole
/// apply can be undone in one go.
class TaskRestorePoint {
  const TaskRestorePoint(this.priorDocs);

  /// Task id -> its document before the apply, or null if the apply created it.
  final Map<String, Map<String, dynamic>?> priorDocs;
}

enum ProposalStatus { pending, applying, applied, undoing, cancelled, undone }

/// A set of changes from one Quackers reply, and where the user is with them.
class ChangeProposal {
  ChangeProposal(this.changes)
    : selected = List<bool>.filled(changes.length, true);

  final List<TaskChange> changes;

  /// Which changes the user has left ticked; all of them to begin with.
  final List<bool> selected;

  ProposalStatus status = ProposalStatus.pending;

  /// Set once applied; what Undo restores from.
  TaskRestorePoint? restorePoint;

  /// Shown under the changes when applying or undoing failed.
  String? error;

  List<TaskChange> get selectedChanges => <TaskChange>[
    for (int i = 0; i < changes.length; i++)
      if (selected[i]) changes[i],
  ];

  /// A single change that deletes nothing is applied straight away, with Undo;
  /// anything bigger waits for the user to press Apply.
  bool get appliesImmediately =>
      changes.length == 1 && changes.single.kind != TaskChangeKind.delete;
}

/// What the app sends Quackers' server with each question: the current time,
/// the user's lists, and every task, all in local wall-clock terms.
///
/// The server reads tasks from this rather than from Firestore, which is what
/// lets it work without knowing the device's time zone.
Map<String, Object?> buildPlannerSnapshot(
  List<TaskListData> lists, {
  required DateTime now,
  String? defaultListId,
}) {
  return <String, Object?>{
    'now': '${formatWireDate(now)}T${formatWireTime(minuteOfDay(now))}',
    'defaultListId': defaultListId,
    'lists': <Map<String, Object?>>[
      for (final TaskListData list in lists)
        <String, Object?>{'id': list.id, 'name': list.name},
    ],
    'tasks': <Map<String, Object?>>[
      for (final TaskListData list in lists)
        for (final TaskItem task in list.tasks)
          <String, Object?>{
            'id': task.id,
            ...TaskState.fromTask(task).toJson(),
          },
    ],
  };
}
