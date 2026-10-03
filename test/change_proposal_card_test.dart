import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/data/task_changes.dart';
import 'package:ultra_planner/widgets/change_proposal_card.dart';

void main() {
  final TaskState essay = TaskState(
    name: 'Essay',
    listId: 'school',
    date: DateTime(2026, 10, 2),
  );

  ChangeProposal twoChanges() => ChangeProposal(<TaskChange>[
    TaskChange.create(const TaskState(name: 'Gym', listId: 'school')),
    TaskChange.delete(taskId: 't1', before: essay),
  ]);

  Future<List<String>> pump(
    WidgetTester tester,
    ChangeProposal proposal,
  ) async {
    final List<String> calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return ChangeProposalCard(
                proposal: proposal,
                onApply: () => calls.add('apply'),
                onCancel: () => calls.add('cancel'),
                onUndo: () => calls.add('undo'),
                onToggle: (int i) => setState(
                  () => proposal.selected[i] = !proposal.selected[i],
                ),
              );
            },
          ),
        ),
      ),
    );
    return calls;
  }

  testWidgets('a pending proposal lists its changes with Apply and Cancel', (
    WidgetTester tester,
  ) async {
    final List<String> calls = await pump(tester, twoChanges());

    expect(find.text('Proposed changes (2)'), findsOneWidget);
    expect(find.text('Add “Gym”'), findsOneWidget);
    expect(find.text('Delete “Essay”'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.tap(find.text('Cancel'));
    expect(calls, <String>['apply', 'cancel']);
  });

  testWidgets('unticking a change applies only the rest', (
    WidgetTester tester,
  ) async {
    final ChangeProposal proposal = twoChanges();
    await pump(tester, proposal);

    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();

    expect(find.text('Apply 1 of 2'), findsOneWidget);
    expect(proposal.selectedChanges.single.kind, TaskChangeKind.create);
  });

  testWidgets('nothing ticked means nothing to apply', (
    WidgetTester tester,
  ) async {
    final ChangeProposal proposal = twoChanges();
    proposal.selected.fillRange(0, 2, false);
    await pump(tester, proposal);

    final FilledButton apply = tester.widget(find.byType(FilledButton));
    expect(apply.onPressed, isNull);
  });

  testWidgets('an applied proposal offers Undo', (WidgetTester tester) async {
    final ChangeProposal proposal = twoChanges()
      ..status = ProposalStatus.applied;
    final List<String> calls = await pump(tester, proposal);

    expect(find.text('Saved to your planner'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);

    await tester.tap(find.text('Undo'));
    expect(calls, <String>['undo']);
  });

  testWidgets('a single change has no checkbox', (WidgetTester tester) async {
    await pump(
      tester,
      ChangeProposal(<TaskChange>[
        TaskChange.create(const TaskState(name: 'Gym', listId: 'school')),
      ]),
    );

    expect(find.text('Proposed change'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });
}
