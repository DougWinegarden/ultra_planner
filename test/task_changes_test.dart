import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/data/models.dart';
import 'package:ultra_planner/data/task_changes.dart';
import 'package:ultra_planner/gemini_quackers_service.dart';

/// A task state as the server sends it.
Map<String, Object?> wire({
  String name = 'Math homework',
  String listId = 'school',
  String? date = '2026-10-02',
  String? time = '17:00',
  int? durationMinutes,
  bool done = false,
}) {
  return <String, Object?>{
    'name': name,
    'listId': listId,
    'listName': 'School',
    'date': date,
    'time': time,
    'durationMinutes': durationMinutes,
    'done': done,
  };
}

void main() {
  group('TaskState', () {
    test('a timed task keeps its time of day', () {
      final TaskState state = TaskState.fromTask(
        TaskItem(
          name: 'Soccer',
          listId: 'home',
          dueDate: DateTime(2026, 10, 3, 16, 30),
          hasTime: true,
          durationMinutes: 90,
        ),
      );

      expect(state.date, DateTime(2026, 10, 3));
      expect(state.startMinute, 16 * 60 + 30);
      expect(state.toJson(), <String, Object?>{
        'name': 'Soccer',
        'listId': 'home',
        'date': '2026-10-03',
        'time': '16:30',
        'durationMinutes': 90,
        'done': false,
      });
    });

    test('an all-day task sends no time, whatever its timestamp holds', () {
      // Tasks from before times existed were saved with DateTime.now().
      final TaskState state = TaskState.fromTask(
        TaskItem(name: 'Old', dueDate: DateTime(2026, 10, 3, 14, 7)),
      );
      expect(state.toJson()['time'], isNull);
      expect(state.dueDate, DateTime(2026, 10, 3));
    });

    test('parsing rebuilds the local due date', () {
      final TaskState state = TaskState.fromJson(wire());
      expect(state.hasTime, isTrue);
      expect(state.dueDate, DateTime(2026, 10, 2, 17));
    });

    test('a time without a date is ignored', () {
      final TaskState state = TaskState.fromJson(wire(date: null));
      expect(state.hasTime, isFalse);
      expect(state.dueDate, isNull);
    });

    test('a state without a name is rejected', () {
      expect(() => TaskState.fromJson(wire(name: '  ')), throwsFormatException);
    });

    test('schedule labels cover every shape of task', () {
      expect(TaskState.fromJson(wire()).scheduleLabel, 'Fri, Oct 2, 5:00 PM');
      expect(
        TaskState.fromJson(wire(durationMinutes: 90)).scheduleLabel,
        'Fri, Oct 2, 5:00–6:30 PM',
      );
      expect(TaskState.fromJson(wire(time: null)).scheduleLabel, 'Fri, Oct 2');
      expect(TaskState.fromJson(wire(date: null)).scheduleLabel, 'No date');
    });
  });

  group('TaskChange', () {
    test('each kind parses', () {
      final TaskChange create = TaskChange.fromJson(<String, Object?>{
        'type': 'create',
        'after': wire(),
      });
      final TaskChange update = TaskChange.fromJson(<String, Object?>{
        'type': 'update',
        'taskId': 't1',
        'before': wire(),
        'after': wire(date: '2026-10-03'),
      });
      final TaskChange delete = TaskChange.fromJson(<String, Object?>{
        'type': 'delete',
        'taskId': 't1',
        'before': wire(),
      });

      expect(create.kind, TaskChangeKind.create);
      expect(update.taskId, 't1');
      expect(delete.after, isNull);
    });

    test('anything the app could not apply is rejected', () {
      expect(
        () => TaskChange.fromJson(<String, Object?>{'type': 'explode'}),
        throwsFormatException,
      );
      expect(
        () => TaskChange.fromJson(<String, Object?>{
          'type': 'update',
          'before': wire(),
          'after': wire(),
        }),
        throwsFormatException,
      );
      expect(
        () => TaskChange.fromJson(<String, Object?>{'type': 'create'}),
        throwsFormatException,
      );
    });

    test('a move describes where from and where to', () {
      final TaskChange change = TaskChange.update(
        taskId: 't1',
        before: TaskState.fromJson(wire()),
        after: TaskState.fromJson(wire(date: '2026-10-03')),
      );
      expect(change.title, 'Move “Math homework”');
      expect(change.detail, 'Fri, Oct 2, 5:00 PM → Sat, Oct 3, 5:00 PM');
    });

    test('a same-day move names the day once', () {
      final TaskChange change = TaskChange.update(
        taskId: 't1',
        before: TaskState.fromJson(wire(durationMinutes: 60)),
        after: TaskState.fromJson(wire(time: '19:15', durationMinutes: 60)),
      );
      expect(change.detail, 'Fri, Oct 2: 5:00–6:00 PM → 7:15–8:15 PM');
    });

    test('completing a task reads as one action', () {
      final TaskChange change = TaskChange.update(
        taskId: 't1',
        before: TaskState.fromJson(wire()),
        after: TaskState.fromJson(wire(done: true)),
      );
      expect(change.title, 'Mark “Math homework” done');
      expect(change.detail, isEmpty);
    });

    test('an untimed task spells out a new length', () {
      final TaskChange change = TaskChange.update(
        taskId: 't1',
        before: TaskState.fromJson(wire(time: null)),
        after: TaskState.fromJson(wire(time: null, durationMinutes: 45)),
      );
      expect(change.detail, 'Takes 45 min');
    });

    test('a new task shows when and where', () {
      final TaskChange change = TaskChange.create(
        TaskState.fromJson(wire(name: 'Gym', durationMinutes: 30)),
      );
      expect(change.title, 'Add “Gym”');
      expect(change.detail, 'Fri, Oct 2, 5:00–5:30 PM · in School');
    });
  });

  group('ChangeProposal', () {
    final TaskChange create = TaskChange.create(TaskState.fromJson(wire()));
    final TaskChange delete = TaskChange.delete(
      taskId: 't1',
      before: TaskState.fromJson(wire()),
    );

    test('one harmless change applies straight away', () {
      expect(ChangeProposal(<TaskChange>[create]).appliesImmediately, isTrue);
    });

    test('deletes and bigger edits wait for Apply', () {
      expect(ChangeProposal(<TaskChange>[delete]).appliesImmediately, isFalse);
      expect(
        ChangeProposal(<TaskChange>[create, create]).appliesImmediately,
        isFalse,
      );
    });

    test('unticked changes are left out', () {
      final ChangeProposal proposal = ChangeProposal(<TaskChange>[
        create,
        delete,
      ]);
      proposal.selected[1] = false;
      expect(proposal.selectedChanges, <TaskChange>[create]);
    });
  });

  test('the snapshot carries every task in local terms', () {
    final TaskListData school = TaskListData(
      id: 'school',
      name: 'School',
      tasks: <TaskItem>[
        TaskItem(
          id: 't1',
          name: 'Essay',
          listId: 'school',
          dueDate: DateTime(2026, 10, 5, 9),
          hasTime: true,
          durationMinutes: 60,
        ),
        TaskItem(id: 't2', name: 'Read', listId: 'school'),
      ],
    );

    final Map<String, Object?> snapshot = buildPlannerSnapshot(
      <TaskListData>[school],
      now: DateTime(2026, 10, 2, 14, 5),
      defaultListId: 'school',
    );

    expect(snapshot['now'], '2026-10-02T14:05');
    expect(snapshot['lists'], <Object?>[
      <String, Object?>{'id': 'school', 'name': 'School'},
    ]);
    final List<Object?> tasks = snapshot['tasks']! as List<Object?>;
    expect(tasks.first, <String, Object?>{
      'id': 't1',
      'name': 'Essay',
      'listId': 'school',
      'date': '2026-10-05',
      'time': '09:00',
      'durationMinutes': 60,
      'done': false,
    });
    expect((tasks.last! as Map<String, Object?>)['date'], isNull);
  });

  group('QuackersReply', () {
    test('reads text and changes from the function result', () {
      final QuackersReply reply = QuackersReply.fromData(<Object?, Object?>{
        'text': ' Moved it. ',
        'actions': <Object?>[
          <Object?, Object?>{'type': 'create', 'after': wire()},
        ],
      });
      expect(reply.text, 'Moved it.');
      expect(reply.changes.single.kind, TaskChangeKind.create);
    });

    test('a malformed change is dropped, not fatal', () {
      final QuackersReply reply = QuackersReply.fromData(<Object?, Object?>{
        'text': 'Here you go.',
        'actions': <Object?>[
          <Object?, Object?>{'type': 'nonsense'},
          'not even a map',
          <Object?, Object?>{'type': 'create', 'after': wire()},
        ],
      });
      expect(reply.changes, hasLength(1));
    });

    test('an older server reply without changes still works', () {
      final QuackersReply reply = QuackersReply.fromData(<Object?, Object?>{
        'text': 'Hi!',
      });
      expect(reply.text, 'Hi!');
      expect(reply.changes, isEmpty);
    });
  });
}
