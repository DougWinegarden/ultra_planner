import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/player_badges.dart';
import 'progress_repository.dart';
import 'username_words.dart';

/// Lets the player choose a new name from the word lists.
///
/// There is deliberately no text field: names are built from two vetted words,
/// so there is nothing to type that could be inappropriate. Resolves to true
/// once the server has accepted the new name.
Future<bool> showUsernamePicker(
  BuildContext context, {
  required ProgressService service,
  String? currentAdjective,
  String? currentCreature,
}) async {
  final bool? saved = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => _UsernamePickerDialog(
      service: service,
      adjective: currentAdjective,
      creature: currentCreature,
    ),
  );
  return saved ?? false;
}

class _UsernamePickerDialog extends StatefulWidget {
  const _UsernamePickerDialog({
    required this.service,
    this.adjective,
    this.creature,
  });

  final ProgressService service;
  final String? adjective;
  final String? creature;

  @override
  State<_UsernamePickerDialog> createState() => _UsernamePickerDialogState();
}

class _UsernamePickerDialogState extends State<_UsernamePickerDialog> {
  final math.Random _random = math.Random();
  late String _adjective;
  late String _creature;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.adjective != null &&
        widget.creature != null &&
        isAllowedUsername(widget.adjective!, widget.creature!)) {
      _adjective = widget.adjective!;
      _creature = widget.creature!;
    } else {
      _shuffle();
    }
  }

  void _shuffle() {
    _adjective = usernameAdjectives[_random.nextInt(usernameAdjectives.length)];
    final List<String> creatures = creaturesFor(_adjective);
    _creature = creatures[_random.nextInt(creatures.length)];
    _error = null;
  }

  void _pickAdjective(String adjective) {
    _adjective = adjective;
    // Keep the creature unless the new pair's initials are blocked.
    final List<String> creatures = creaturesFor(adjective);
    if (!creatures.contains(_creature)) _creature = creatures.first;
    _error = null;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.setUsername(_adjective, _creature);
      if (mounted) Navigator.of(context).pop(true);
    } on ProgressException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save your name. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose your sailor name'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                InitialsAvatar(
                  initials: usernameInitials(_adjective, _creature),
                  radius: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$_adjective $_creature',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF003B5C),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('adjective'),
              initialValue: _adjective,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Describe yourself',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final String word in usernameAdjectives)
                  DropdownMenuItem<String>(value: word, child: Text(word)),
              ],
              onChanged: _saving
                  ? null
                  : (String? word) {
                      if (word != null) setState(() => _pickAdjective(word));
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // Rebuilt when the adjective changes, since that changes which
              // creatures are allowed.
              key: ValueKey<String>('creature-$_adjective'),
              initialValue: _creature,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Pick a sea creature',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final String word in creaturesFor(_adjective))
                  DropdownMenuItem<String>(value: word, child: Text(word)),
              ],
              onChanged: _saving
                  ? null
                  : (String? word) {
                      if (word != null) {
                        setState(() {
                          _creature = word;
                          _error = null;
                        });
                      }
                    },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving ? null : () => setState(_shuffle),
                icon: const Icon(Icons.shuffle),
                label: const Text('Surprise me'),
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Color(0xFFCC2A22))),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
