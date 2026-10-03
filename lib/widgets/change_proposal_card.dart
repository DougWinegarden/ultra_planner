import 'package:flutter/material.dart';

import '../data/task_changes.dart';

/// Shows the planner changes Quackers proposed in one reply, with the buttons
/// to apply, cancel or undo them.
///
/// Stateless: the chat sheet owns the [ChangeProposal] and rebuilds this card
/// as it moves from pending to applied or cancelled.
class ChangeProposalCard extends StatelessWidget {
  const ChangeProposalCard({
    super.key,
    required this.proposal,
    required this.onApply,
    required this.onCancel,
    required this.onUndo,
    required this.onToggle,
  });

  final ChangeProposal proposal;
  final VoidCallback onApply;
  final VoidCallback onCancel;
  final VoidCallback onUndo;

  /// Ticks or unticks the change at an index, while still pending.
  final ValueChanged<int> onToggle;

  static const Color _ink = Color(0xFF003B5C);
  static const Color _muted = Color(0xFF41708A);
  static const Color _accent = Color(0xFF0077B6);
  static const Color _saved = Color(0xFF1B8A3F);
  static const Color _removed = Color(0xFFCC2A22);

  @override
  Widget build(BuildContext context) {
    final bool pending = proposal.status == ProposalStatus.pending;
    final bool choosable = pending && proposal.changes.length > 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      constraints: const BoxConstraints(maxWidth: 340),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: proposal.status == ProposalStatus.applied
              ? _saved
              : const Color(0xFF90E0EF),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _heading,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < proposal.changes.length; i++)
            _buildChange(proposal.changes[i], i, choosable),
          if (proposal.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                proposal.error!,
                style: const TextStyle(color: _removed, fontSize: 13),
              ),
            ),
          _buildActions(),
        ],
      ),
    );
  }

  String get _heading {
    final int count = proposal.changes.length;
    switch (proposal.status) {
      case ProposalStatus.pending:
      case ProposalStatus.applying:
        return count == 1 ? 'Proposed change' : 'Proposed changes ($count)';
      case ProposalStatus.applied:
        return 'Saved to your planner';
      case ProposalStatus.undoing:
        return 'Undoing…';
      case ProposalStatus.cancelled:
        return 'Not applied';
      case ProposalStatus.undone:
        return 'Undone';
    }
  }

  Widget _buildChange(TaskChange change, int index, bool choosable) {
    final bool included = proposal.selected[index];
    final bool struck =
        proposal.status == ProposalStatus.cancelled ||
        proposal.status == ProposalStatus.undone ||
        (proposal.status != ProposalStatus.pending && !included);
    final String detail = change.detail;

    final Widget text = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            change.title,
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w600,
              decoration: struck ? TextDecoration.lineThrough : null,
            ),
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: TextStyle(
                color: _muted,
                fontSize: 12.5,
                decoration: struck ? TextDecoration.lineThrough : null,
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (choosable)
            SizedBox(
              width: 32,
              height: 24,
              child: Checkbox(
                value: included,
                activeColor: _accent,
                visualDensity: VisualDensity.compact,
                onChanged: (_) => onToggle(index),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 1),
              child: Icon(_iconFor(change), size: 20, color: _colorFor(change)),
            ),
          text,
        ],
      ),
    );
  }

  Widget _buildActions() {
    switch (proposal.status) {
      case ProposalStatus.pending:
        final int chosen = proposal.selectedChanges.length;
        // Wraps rather than overflowing when "Apply 3 of 12" meets a narrow
        // phone or a large text size.
        return Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: <Widget>[
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
              FilledButton(
                onPressed: chosen == 0 ? null : onApply,
                style: FilledButton.styleFrom(backgroundColor: _accent),
                child: Text(
                  chosen == proposal.changes.length
                      ? 'Apply'
                      : 'Apply $chosen of ${proposal.changes.length}',
                ),
              ),
            ],
          ),
        );
      case ProposalStatus.applying:
      case ProposalStatus.undoing:
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case ProposalStatus.applied:
        return Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onUndo,
            icon: const Icon(Icons.undo_rounded, size: 18),
            label: const Text('Undo'),
          ),
        );
      case ProposalStatus.cancelled:
      case ProposalStatus.undone:
        return const SizedBox(height: 4);
    }
  }

  static IconData _iconFor(TaskChange change) {
    switch (change.kind) {
      case TaskChangeKind.create:
        return Icons.add_circle_outline;
      case TaskChangeKind.delete:
        return Icons.delete_outline;
      case TaskChangeKind.update:
        return change.after!.done && !change.before!.done
            ? Icons.check_circle_outline
            : Icons.edit_calendar_outlined;
    }
  }

  static Color _colorFor(TaskChange change) {
    switch (change.kind) {
      case TaskChangeKind.create:
        return _saved;
      case TaskChangeKind.delete:
        return _removed;
      case TaskChangeKind.update:
        return _accent;
    }
  }
}
