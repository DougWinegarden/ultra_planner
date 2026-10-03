import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_gate.dart';
import 'auth/auth_service.dart';
import 'data/models.dart';
import 'data/calendar_layout.dart';
import 'data/planner_repository.dart';
import 'data/task_changes.dart';
import 'data/task_time.dart';
import 'data/us_holidays.dart';
import 'firebase_options.dart';
import 'gemini_quackers_service.dart';
import 'widgets/app_background.dart';
import 'widgets/change_proposal_card.dart';
import 'widgets/holiday_theme.dart';
import 'widgets/ocean_background.dart';

//hello this is a test

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A failed init must not take the whole app down: AuthGate turns this message
  // into a readable setup screen instead of a red error page.
  String? startupError;
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (error) {
      startupError = describeFirebaseStartupError(error);
    }
  }

  runApp(OceanListsApp(startupError: startupError));
}

class OceanListsApp extends StatelessWidget {
  const OceanListsApp({super.key, this.startupError});

  final String? startupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ocean Lists',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0077B6)),
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: AuthGate(startupError: startupError),
    );
  }
}

/// Task status colours, used everywhere a task's state is shown so the same
/// task reads the same way in the list, the calendar and the legend.
///
/// Chosen dark enough to stay legible as text and icons on the app's pale
/// background; a literal lemon yellow would wash out.
abstract final class TaskStatusColors {
  /// Not done, not yet late.
  static const Color unfinished = Color(0xFFD99400);

  /// Completed.
  static const Color finished = Color(0xFF1B8A3F);

  /// Past its due date and still not done.
  static const Color overdue = Color(0xFFCC2A22);

  /// Soft fills for card backgrounds, tinted from the colours above.
  static const Color finishedSurface = Color(0xFFE4F5E8);
  static const Color overdueSurface = Color(0xFFFDEAE8);
}

/// Size of the holiday emoji in a month cell. Three times the old 11pt, which
/// is large enough to read the day at a glance from across the grid.
const double _holidayEmojiSize = 33;

enum AppSection { lists, calendar }

enum CalendarMode { year, month, day }

class OceanListsPage extends StatefulWidget {
  const OceanListsPage({
    super.key,
    required this.user,
    required this.authService,
  });

  final User user;
  final AuthService authService;

  @override
  State<OceanListsPage> createState() => _OceanListsPageState();
}

class _OceanListsPageState extends State<OceanListsPage> {
  final GeminiQuackersService _quackers = GeminiQuackersService();
  late final PlannerRepository _planner;

  StreamSubscription<List<TaskListData>>? _listSub;
  List<TaskListData> _lists = <TaskListData>[];

  /// Selection is held as a document id, not an index: the Firestore stream can
  /// reorder or remove lists underneath us at any time.
  String? _selectedListId;
  AppSection _section = AppSection.lists;
  CalendarMode _calendarMode = CalendarMode.month;
  DateTime _calendarDate = DateTime.now();

  bool _isLoading = true;
  String? _loadError;

  /// Theme for the day currently in focus. Driven by [_calendarDate] rather
  /// than today, so selecting Halloween in the calendar previews its look.
  HolidayTheme get _theme => HolidayTheme.forDate(_calendarDate);

  /// Last four characters of the saved Gemini key, or null when none is set.
  /// The key itself never reaches the client.
  String? _apiKeyHint;
  bool _hasApiKey = false;

  @override
  void initState() {
    super.initState();
    _planner = PlannerRepository(uid: widget.user.uid);
    _subscribeToLists();
    _refreshKeyStatus();
  }

  @override
  void dispose() {
    _listSub?.cancel();
    super.dispose();
  }

  void _subscribeToLists() {
    _listSub = _planner.watchLists().listen(
      (List<TaskListData> lists) async {
        // A brand-new account has nothing to show, so give it a starting point.
        if (lists.isEmpty && _isLoading) {
          await _planner.seedStarterLists();
          if (!mounted) return;
          setState(() => _isLoading = false);
          return;
        }

        if (!mounted) return;
        setState(() {
          _lists = lists;
          _isLoading = false;
          _loadError = null;
          if (_selectedListId == null ||
              !lists.any((TaskListData list) => list.id == _selectedListId)) {
            _selectedListId = lists.isEmpty ? null : lists.first.id;
          }
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _loadError = _describeFirestoreError(error);
        });
      },
    );
  }

  /// Asks the server whether this account has a key saved.
  Future<void> _refreshKeyStatus() async {
    try {
      final QuackersKeyStatus status = await _quackers.keyStatus();
      if (!mounted) return;
      setState(() {
        _hasApiKey = status.hasKey;
        _apiKeyHint = status.hint;
      });
    } catch (_) {
      // Not fatal: the assistant falls back to its setup panel on first use.
    }
  }

  /// Collects a Gemini key and hands it to the function to be encrypted.
  Future<void> _showApiKeyDialog() async {
    final TextEditingController controller = TextEditingController();
    bool obscured = true;

    final String? key = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setDialogState,
              ) {
                return AlertDialog(
                  title: Text(
                    _hasApiKey ? 'Change Gemini API key' : 'Add Gemini API key',
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_apiKeyHint != null) ...<Widget>[
                        Text(
                          'Currently saved: $_apiKeyHint',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF41708A),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const Text(
                        'Your key is encrypted before it is stored, and is '
                        'never sent back to this app. Get one free at '
                        'aistudio.google.com/apikey.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF41708A),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        obscureText: obscured,
                        decoration: InputDecoration(
                          labelText: 'API key',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: obscured ? 'Show key' : 'Hide key',
                            icon: Icon(
                              obscured
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setDialogState(() => obscured = !obscured),
                          ),
                        ),
                        onSubmitted: (String value) {
                          if (value.trim().isNotEmpty) {
                            Navigator.of(dialogContext).pop(value.trim());
                          }
                        },
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    if (_hasApiKey)
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop('__delete__'),
                        child: const Text('Remove key'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final String value = controller.text.trim();
                        if (value.isNotEmpty) {
                          Navigator.of(dialogContext).pop(value);
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                );
              },
        );
      },
    );

    if (key == null || !mounted) return;

    try {
      if (key == '__delete__') {
        await _quackers.deleteApiKey();
        if (!mounted) return;
        setState(() {
          _hasApiKey = false;
          _apiKeyHint = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gemini key removed.')),
        );
        return;
      }

      final String? hint = await _quackers.saveApiKey(key);
      if (!mounted) return;
      setState(() {
        _hasApiKey = true;
        _apiKeyHint = hint;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemini key saved and encrypted.')),
      );
    } on QuackersException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  static String _describeFirestoreError(Object error) {
    final String text = error.toString();
    if (text.contains('permission-denied')) {
      return 'Firestore denied access. Deploy the rules in firestore.rules, '
          'then try again.';
    }
    if (text.contains('unavailable') || text.contains('UNAVAILABLE')) {
      return 'Cannot reach Firestore. Check your internet connection.';
    }
    return text;
  }

  Future<void> _signOut() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text('Your tasks stay saved to your account.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await _listSub?.cancel();
    _listSub = null;
    await widget.authService.signOut();
  }

  /// The list currently on screen, or null while the account has none.
  TaskListData? get _currentListOrNull {
    if (_lists.isEmpty) return null;
    for (final TaskListData list in _lists) {
      if (list.id == _selectedListId) return list;
    }
    return _lists.first;
  }

  TaskListData get _currentList => _currentListOrNull!;

  List<DatedTask> get _allDatedTasks {
    final List<DatedTask> result = <DatedTask>[];

    for (final TaskListData list in _lists) {
      for (final TaskItem task in list.tasks) {
        if (task.dueDate != null) {
          result.add(DatedTask(list: list, task: task));
        }
      }
    }

    return result;
  }

  Future<void> _createList() async {
    final TextEditingController controller = TextEditingController();

    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Create a list'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'List name',
              hintText: 'Example: Vacation',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (String value) {
              final String name = value.trim();
              if (name.isNotEmpty) {
                Navigator.of(dialogContext).pop(name);
              }
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final String name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.of(dialogContext).pop(name);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null || result.trim().isEmpty) {
      return;
    }

    final String newId = await _planner.createList(
      result.trim(),
      order: _lists.length,
    );
    if (!mounted) return;

    // The stream delivers the new document a moment later; selecting the id now
    // means it is already the active list when it arrives.
    setState(() {
      _selectedListId = newId;
      _section = AppSection.lists;
    });
  }

  Future<void> _renameList() async {
    final TextEditingController controller = TextEditingController(
      text: _currentList.name,
    );

    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Rename list'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'List name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final String name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.of(dialogContext).pop(name);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null || result.trim().isEmpty) {
      return;
    }

    await _planner.renameList(_currentList.id, result.trim());
  }

  Future<void> _deleteList() async {
    if (_lists.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need at least one list.')),
      );
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete this list?'),
          content: Text(
            'This will delete "${_currentList.name}" and all its tasks.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    await _planner.deleteList(_currentList.id);
  }

  Future<void> _addTask({
    TaskListData? targetList,
    DateTime? initialDate,
  }) async {
    final TaskListData list = targetList ?? _currentList;
    final TextEditingController controller = TextEditingController();
    DateTime? selectedDate = initialDate;
    int? selectedMinute;
    int? selectedDuration;

    final TaskItem? task = await showDialog<TaskItem>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setDialogState,
              ) {
                return AlertDialog(
                  title: Text('Add task to ${list.name}'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: controller,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Task',
                          hintText: 'What do you need to do?',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final DateTime now = DateTime.now();
                            final DateTime? date = await showDatePicker(
                              context: dialogContext,
                              initialDate: selectedDate ?? now,
                              firstDate: DateTime(now.year - 10),
                              lastDate: DateTime(now.year + 20),
                            );

                            if (date != null) {
                              setDialogState(() {
                                selectedDate = date;
                              });
                            }
                          },
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            selectedDate == null
                                ? 'Choose due date'
                                : _formatDate(selectedDate!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              // A time of day needs a day to sit on.
                              onPressed: selectedDate == null
                                  ? null
                                  : () async {
                                      final TimeOfDay? time =
                                          await showTimePicker(
                                            context: dialogContext,
                                            initialTime: _timeOfDay(
                                              selectedMinute ?? 9 * 60,
                                            ),
                                          );
                                      if (time != null) {
                                        setDialogState(() {
                                          selectedMinute =
                                              time.hour * 60 + time.minute;
                                        });
                                      }
                                    },
                              icon: const Icon(Icons.schedule),
                              label: Text(
                                selectedMinute == null
                                    ? 'Time'
                                    : formatClock(selectedMinute!),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          DropdownButton<int?>(
                            value: selectedDuration,
                            onChanged: (int? minutes) {
                              setDialogState(() => selectedDuration = minutes);
                            },
                            items: <int?>[null, 15, 30, 45, 60, 90, 120, 180]
                                .map(
                                  (int? minutes) => DropdownMenuItem<int?>(
                                    value: minutes,
                                    child: Text(
                                      minutes == null
                                          ? 'Any length'
                                          : formatDuration(minutes),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final String taskName = controller.text.trim();
                        if (taskName.isNotEmpty) {
                          Navigator.of(dialogContext).pop(
                            TaskItem(
                              name: taskName,
                              dueDate: selectedDate == null
                                  ? null
                                  : atMinute(selectedDate!, selectedMinute),
                              hasTime:
                                  selectedDate != null &&
                                  selectedMinute != null,
                              durationMinutes: selectedDuration,
                            ),
                          );
                        }
                      },
                      child: const Text('Add Task'),
                    ),
                  ],
                );
              },
        );
      },
    );

    if (!mounted || task == null) {
      return;
    }

    await _planner.addTask(
      listId: list.id,
      name: task.name,
      dueDate: task.dueDate,
      hasTime: task.hasTime,
      durationMinutes: task.durationMinutes,
    );
    if (!mounted) return;

    if (task.dueDate != null) {
      setState(() => _calendarDate = task.dueDate!);
    }
  }

  /// Picks a new day for [task]. A timed task also offers its time for
  /// change, so it does not quietly turn into an all-day task at midnight;
  /// dismissing the time picker keeps the time it had.
  Future<void> _changeDueDate(TaskItem task) async {
    final DateTime now = DateTime.now();

    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: task.dueDate ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );

    if (!mounted || date == null) {
      return;
    }

    int? minute;
    if (task.hasTime && task.dueDate != null) {
      minute = minuteOfDay(task.dueDate!);
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: _timeOfDay(minute),
      );
      if (!mounted) return;
      if (time != null) minute = time.hour * 60 + time.minute;
    }

    final DateTime due = atMinute(date, minute);
    await _planner.setTaskDueDate(task.id, due);
    if (!mounted) return;
    setState(() => _calendarDate = due);
  }

  static TimeOfDay _timeOfDay(int minuteOfDay) =>
      TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60);

  /// "2026-10-03 · 5:00 PM · 30 min", or just the date for an all-day task.
  static String _dueLabel(TaskItem task) {
    return <String>[
      _formatDate(task.dueDate!),
      if (task.hasTime) formatClock(minuteOfDay(task.dueDate!)),
      if (task.durationMinutes != null) formatDuration(task.durationMinutes!),
    ].join(' · ');
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String _monthName(int month) {
    const List<String> names = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }

  static String _weekdayName(int weekday) {
    const List<String> names = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[weekday - 1];
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isOverdue(TaskItem task) {
    if (task.dueDate == null || task.isDone) {
      return false;
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime due = DateTime(
      task.dueDate!.year,
      task.dueDate!.month,
      task.dueDate!.day,
    );

    return due.isBefore(today);
  }

  Color _taskColor(TaskItem task) {
    if (_isOverdue(task)) {
      return TaskStatusColors.overdue;
    }
    if (task.isDone) {
      return TaskStatusColors.finished;
    }
    return TaskStatusColors.unfinished;
  }

  void _goToToday() {
    setState(() {
      _calendarDate = DateTime.now();
    });
  }

  void _moveCalendar(int amount) {
    setState(() {
      switch (_calendarMode) {
        case CalendarMode.year:
          _calendarDate = DateTime(
            _calendarDate.year + amount,
            _calendarDate.month,
            math.min(
              _calendarDate.day,
              DateTime(
                _calendarDate.year + amount,
                _calendarDate.month + 1,
                0,
              ).day,
            ),
          );
          break;
        case CalendarMode.month:
          _calendarDate = DateTime(
            _calendarDate.year,
            _calendarDate.month + amount,
            1,
          );
          break;
        case CalendarMode.day:
          _calendarDate = _calendarDate.add(Duration(days: amount));
          break;
      }
    });
  }

  DatedTask? get _assistantPick {
    final List<DatedTask> unfinished =
        _allDatedTasks.where((DatedTask item) => !item.task.isDone).toList()
          ..sort((DatedTask a, DatedTask b) {
            final DateTime aDate = a.task.dueDate ?? DateTime(9999);
            final DateTime bDate = b.task.dueDate ?? DateTime(9999);
            return aDate.compareTo(bDate);
          });
    return unfinished.isEmpty ? null : unfinished.first;
  }

  String get _assistantTip {
    final DatedTask? pick = _assistantPick;
    if (pick == null) {
      return 'Your list is clear! Add one small next step to keep your momentum.';
    }
    if (_isOverdue(pick.task)) {
      return 'A tiny start counts: spend five minutes making a first move on this overdue task.';
    }
    if (pick.task.dueDate == null) {
      return 'No rush on this one. Pick a 10-minute version and get it out of your head.';
    }
    return 'Start with the nearest deadline, then give yourself a small, specific first step.';
  }

  /// What Quackers plans with, rebuilt for every question so it always sees
  /// changes made since the chat opened, including its own.
  Map<String, Object?> _plannerSnapshot() => buildPlannerSnapshot(
    _lists,
    now: DateTime.now(),
    defaultListId: _currentListOrNull?.id,
  );

  void _showAssistant() {
    final DatedTask? pick = _assistantPick;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF4FCFF),
      builder: (BuildContext sheetContext) {
        return QuackersChatSheet(
          service: _quackers,
          planner: _planner,
          plannerSnapshot: _plannerSnapshot,
          suggestedTask: pick?.task.name,
          suggestedTip: _assistantTip,
          userId: widget.user.uid,
          hasApiKey: _hasApiKey,
          onSetUpApiKey: () async {
            await _showApiKeyDialog();
            return _hasApiKey;
          },
          onStartSuggestedTask: pick == null
              ? null
              : () {
                  Navigator.of(sheetContext).pop();
                  setState(() {
                    _selectedListId = pick.list.id;
                    _section = AppSection.lists;
                  });
                },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: AnimatedAppBackground(theme: _theme)),
          SafeArea(
            child: Column(
              children: <Widget>[
                _buildTopBar(),
                if (!_isLoading && _loadError == null && _lists.isNotEmpty)
                  _buildMainNavigation(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _isLoading || _loadError != null || _lists.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                if (_section == AppSection.calendar) {
                  _addTask(initialDate: _calendarDate);
                } else {
                  _addTask();
                }
              },
              backgroundColor: _theme.accent,
              foregroundColor: _theme.onAccent,
              icon: const Icon(Icons.add),
              label: Text(
                _section == AppSection.calendar
                    ? 'Add on ${_calendarDate.month}/${_calendarDate.day}'
                    : 'Add Task',
              ),
            ),
    );
  }

  /// Loading / error / empty / normal, in that order of precedence.
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0077B6)),
      );
    }

    if (_loadError != null) {
      return _buildMessagePanel(
        icon: Icons.cloud_off,
        title: 'Could not load your tasks',
        message: _loadError!,
        actionLabel: 'Try again',
        onAction: () {
          setState(() {
            _isLoading = true;
            _loadError = null;
          });
          _listSub?.cancel();
          _subscribeToLists();
        },
      );
    }

    if (_lists.isEmpty) {
      return _buildMessagePanel(
        icon: Icons.waves,
        title: 'No lists yet',
        message: 'Create your first list to start adding tasks.',
        actionLabel: 'Create a list',
        onAction: _createList,
      );
    }

    return _section == AppSection.lists
        ? _buildListsSection()
        : _buildCalendarSection();
  }

  Widget _buildMessagePanel({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 44, color: const Color(0xFF0077B6)),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF003B5C),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF33607A),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0077B6),
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.water_drop, color: _theme.subheading, size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _theme.isOcean ? 'Ocean Lists' : _theme.name,
              style: TextStyle(
                color: _theme.heading,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_lists.isNotEmpty)
            if (_section == AppSection.lists) ...<Widget>[
              IconButton(
                tooltip: 'Rename current list',
                onPressed: _renameList,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Delete current list',
                onPressed: _deleteList,
                icon: const Icon(Icons.delete_outline),
              ),
            ] else
              IconButton(
                tooltip: 'Go to today',
                onPressed: _goToToday,
                icon: const Icon(Icons.today),
              ),
          _buildAccountMenu(),
        ],
      ),
    );
  }

  /// Avatar menu: shows who is signed in, plus Gemini key and log-out actions.
  Widget _buildAccountMenu() {
    final String email = widget.user.email ?? 'Signed in';
    final String display = widget.user.displayName?.trim().isNotEmpty == true
        ? widget.user.displayName!.trim()
        : email;
    final String initial = display.isEmpty ? '?' : display[0].toUpperCase();

    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 44),
      onSelected: (String value) {
        switch (value) {
          case 'signout':
            _signOut();
          case 'apikey':
            _showApiKeyDialog();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                display,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003B5C),
                ),
              ),
              if (display != email)
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF41708A),
                  ),
                ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'apikey',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key_outlined, size: 20),
            title: Text(
              _hasApiKey ? 'Change Gemini API key' : 'Add Gemini API key',
            ),
            subtitle: _apiKeyHint == null ? null : Text(_apiKeyHint!),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'signout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, size: 20),
            title: Text('Log out'),
          ),
        ),
      ],
      child: CircleAvatar(
        radius: 17,
        backgroundColor: _theme.accent,
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildMainNavigation() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<AppSection>(
        segments: const <ButtonSegment<AppSection>>[
          ButtonSegment<AppSection>(
            value: AppSection.lists,
            icon: Icon(Icons.checklist),
            label: Text('Lists'),
          ),
          ButtonSegment<AppSection>(
            value: AppSection.calendar,
            icon: Icon(Icons.calendar_month),
            label: Text('Calendar'),
          ),
        ],
        selected: <AppSection>{_section},
        onSelectionChanged: (Set<AppSection> value) {
          setState(() {
            _section = value.first;
          });
        },
      ),
    );
  }

  Widget _buildListsSection() {
    return Column(
      children: <Widget>[
        _buildListSelector(),
        _buildAssistantCard(),
        _buildProgressCard(),
        Expanded(child: _buildTaskArea()),
      ],
    );
  }

  Widget _buildAssistantCard() {
    final DatedTask? pick = _assistantPick;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFFF5C7), Color(0xFFFFE59B)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0C94D)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF9A6A00).withValues(alpha: .10),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          const DuckSuitCapybara(size: 68),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Quackers says',
                  style: TextStyle(
                    color: Color(0xFF7B5700),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pick == null
                      ? 'You did it — enjoy your clear list!'
                      : 'Start with “${pick.task.name}”.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF493600),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _assistantTip,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7B630E),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Ask Quackers for help',
            onPressed: _showAssistant,
            icon: const Icon(Icons.auto_awesome, color: Color(0xFF7B5700)),
          ),
        ],
      ),
    );
  }

  Widget _buildListSelector() {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _lists.length + 1,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          if (index == _lists.length) {
            return ActionChip(
              avatar: const Icon(Icons.add, size: 19),
              label: const Text('New List'),
              onPressed: _createList,
              backgroundColor: Colors.white.withValues(alpha: 0.92),
              side: const BorderSide(color: Color(0xFF00A8E8)),
            );
          }

          final bool selected = _lists[index].id == _currentListOrNull?.id;

          return ChoiceChip(
            selected: selected,
            label: Text(_lists[index].name),
            avatar: Icon(
              selected ? Icons.check_circle : Icons.list_alt,
              size: 19,
            ),
            selectedColor: const Color(0xFF0077B6),
            backgroundColor: Colors.white.withValues(alpha: 0.92),
            labelStyle: TextStyle(
              color: selected ? Colors.white : const Color(0xFF004D73),
              fontWeight: FontWeight.w600,
            ),
            side: const BorderSide(color: Color(0xFF74C9EE)),
            onSelected: (_) {
              setState(() {
                _selectedListId = _lists[index].id;
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildProgressCard() {
    final int completed = _currentList.tasks
        .where((TaskItem task) => task.isDone)
        .length;
    final int total = _currentList.tasks.length;
    final double progress = total == 0 ? 0 : completed / total;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF90E0EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _currentList.name,
            style: const TextStyle(
              color: Color(0xFF003B5C),
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '$completed of $total tasks completed',
            style: const TextStyle(color: Color(0xFF35677D)),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: const Color(0xFFCDEFFF),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF0077B6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskArea() {
    if (_currentList.tasks.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.fromLTRB(28, 8, 28, 90),
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF90E0EF)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.set_meal, size: 72, color: Color(0xFF00A8E8)),
              SizedBox(height: 12),
              Text(
                'No tasks in this list yet',
                style: TextStyle(
                  color: Color(0xFF003B5C),
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Press “Add Task” to add one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF456D7F)),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: _currentList.tasks.length,
      itemBuilder: (BuildContext context, int index) {
        final TaskItem task = _currentList.tasks[index];
        return _buildTaskCard(_currentList, task, index);
      },
    );
  }

  Widget _buildTaskCard(
    TaskListData list,
    TaskItem task,
    int index, {
    bool showListName = false,
  }) {
    final bool overdue = _isOverdue(task);

    return Dismissible(
      key: ValueKey<String>(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 22),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        // Drop it locally right away so the row does not spring back while the
        // delete is in flight.
        setState(() => list.tasks.remove(task));
        _planner.deleteTask(task.id);
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        color: task.isDone
            ? TaskStatusColors.finishedSurface.withValues(alpha: 0.97)
            : overdue
            ? TaskStatusColors.overdueSurface.withValues(alpha: 0.97)
            : Colors.white.withValues(alpha: 0.93),
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: overdue
                ? TaskStatusColors.overdue
                : task.isDone
                ? TaskStatusColors.finished
                : const Color(0xFF90E0EF),
            width: overdue ? 2 : 1,
          ),
        ),
        child: Column(
          children: <Widget>[
            if (overdue)
              const SizedBox(
                height: 17,
                width: double.infinity,
                child: CustomPaint(
                  painter: TsunamiStripPainter(
                    color: TaskStatusColors.overdue,
                  ),
                ),
              ),
            CheckboxListTile(
              value: task.isDone,
              activeColor: TaskStatusColors.finished,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (bool? value) {
                final bool isDone = value ?? false;
                // Update locally first so the checkbox does not lag behind the
                // Firestore round-trip; the stream confirms it a moment later.
                setState(() => task.isDone = isDone);
                _planner.setTaskDone(task.id, isDone);
              },
              title: Text(
                task.name,
                style: TextStyle(
                  color: const Color(0xFF003B5C),
                  fontWeight: FontWeight.w600,
                  decoration: task.isDone ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (showListName)
                    Text(
                      list.name,
                      style: const TextStyle(
                        color: Color(0xFF0077B6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    task.dueDate == null
                        ? 'No due date'
                        : overdue
                        ? '🌊 Tsunami overdue: ${_dueLabel(task)}'
                        : 'Due: ${_dueLabel(task)}',
                    style: TextStyle(
                      color: overdue
                          ? TaskStatusColors.overdue
                          : const Color(0xFF28789D),
                      fontWeight: overdue ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              secondary: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Change due date',
                    onPressed: () => _changeDueDate(task),
                    icon: const Icon(
                      Icons.edit_calendar,
                      color: Color(0xFF0077B6),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete task',
                    onPressed: () {
                      setState(() => list.tasks.remove(task));
                      _planner.deleteTask(task.id);
                    },
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFF0077B6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarSection() {
    return Column(
      children: <Widget>[
        _buildCalendarToolbar(),
        _buildCalendarLegend(),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: switch (_calendarMode) {
              CalendarMode.year => _buildYearView(),
              CalendarMode.month => _buildMonthView(),
              CalendarMode.day => _buildDayView(),
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarToolbar() {
    String title;

    switch (_calendarMode) {
      case CalendarMode.year:
        title = '${_calendarDate.year}';
        break;
      case CalendarMode.month:
        title = '${_monthName(_calendarDate.month)} ${_calendarDate.year}';
        break;
      case CalendarMode.day:
        title =
            '${_weekdayName(_calendarDate.weekday)}, ${_monthName(_calendarDate.month)} ${_calendarDate.day}, ${_calendarDate.year}';
        break;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF90E0EF)),
      ),
      child: Column(
        children: <Widget>[
          SegmentedButton<CalendarMode>(
            segments: const <ButtonSegment<CalendarMode>>[
              ButtonSegment<CalendarMode>(
                value: CalendarMode.year,
                label: Text('Year'),
              ),
              ButtonSegment<CalendarMode>(
                value: CalendarMode.month,
                label: Text('Month'),
              ),
              ButtonSegment<CalendarMode>(
                value: CalendarMode.day,
                label: Text('Day'),
              ),
            ],
            selected: <CalendarMode>{_calendarMode},
            onSelectionChanged: (Set<CalendarMode> selected) {
              setState(() {
                _calendarMode = selected.first;
              });
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Previous',
                onPressed: () => _moveCalendar(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF003B5C),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed: () => _moveCalendar(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: <Widget>[
          CalendarLegendDot(
            color: TaskStatusColors.unfinished,
            label: 'Unfinished',
            textColor: _theme.subheading,
          ),
          CalendarLegendDot(
            color: TaskStatusColors.finished,
            label: 'Finished',
            textColor: _theme.subheading,
          ),
          CalendarLegendDot(
            color: TaskStatusColors.overdue,
            label: '🌊 Tsunami overdue',
            textColor: _theme.subheading,
          ),
        ],
      ),
    );
  }

  Widget _buildYearView() {
    return GridView.builder(
      key: ValueKey<String>('year-${_calendarDate.year}'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemCount: 12,
      itemBuilder: (BuildContext context, int index) {
        final int month = index + 1;
        final List<DatedTask> monthTasks = _allDatedTasks.where((
          DatedTask item,
        ) {
          final DateTime due = item.task.dueDate!;
          return due.year == _calendarDate.year && due.month == month;
        }).toList();

        final int unfinished = monthTasks
            .where(
              (DatedTask item) => !item.task.isDone && !_isOverdue(item.task),
            )
            .length;
        final int finished = monthTasks
            .where((DatedTask item) => item.task.isDone)
            .length;
        final int overdue = monthTasks
            .where((DatedTask item) => _isOverdue(item.task))
            .length;

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            setState(() {
              _calendarDate = DateTime(_calendarDate.year, month, 1);
              _calendarMode = CalendarMode.month;
            });
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF90E0EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _monthName(month).substring(0, 3),
                  style: const TextStyle(
                    color: Color(0xFF003B5C),
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                _yearCountRow(
                  TaskStatusColors.unfinished,
                  unfinished,
                  Icons.pending_actions,
                ),
                const SizedBox(height: 4),
                _yearCountRow(
                  TaskStatusColors.finished,
                  finished,
                  Icons.task_alt,
                ),
                const SizedBox(height: 4),
                _yearCountRow(
                  TaskStatusColors.overdue,
                  overdue,
                  Icons.waves,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _yearCountRow(Color color, int count, IconData icon) {
    return Row(
      children: <Widget>[
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 5),
        Text(
          '$count',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildMonthView() {
    final DateTime firstDay = DateTime(
      _calendarDate.year,
      _calendarDate.month,
      1,
    );
    final int monthLength = daysInMonth(firstDay);
    final int leadingEmptyDays = leadingBlankDays(firstDay);
    final int rowCount = weekRowsInMonth(firstDay);
    final int totalCells = rowCount * 7;

    return Column(
      key: ValueKey<String>(
        'month-${_calendarDate.year}-${_calendarDate.month}',
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              for (final String day in <String>[
                'Sun',
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
              ])
                CalendarWeekdayLabel(day, color: _theme.subheading),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: rowCount <= 5 ? 0.72 : 0.62,
            ),
            itemCount: totalCells,
            itemBuilder: (BuildContext context, int index) {
              final int dayNumber = index - leadingEmptyDays + 1;

              if (dayNumber < 1 || dayNumber > monthLength) {
                return const SizedBox.shrink();
              }

              final DateTime date = DateTime(
                _calendarDate.year,
                _calendarDate.month,
                dayNumber,
              );

              final List<DatedTask> tasks = _allDatedTasks.where((
                DatedTask item,
              ) {
                return _isSameDay(item.task.dueDate!, date);
              }).toList();

              final bool selected = _isSameDay(date, _calendarDate);
              final bool today = _isSameDay(date, DateTime.now());
              final List<Holiday> holidays = UsHolidays.on(date);
              final Holiday? holiday = holidays.isEmpty ? null : holidays.first;

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _calendarDate = date;
                    _calendarMode = CalendarMode.day;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFD8F3FC)
                        : Colors.white.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: today
                          ? const Color(0xFF0077B6)
                          : const Color(0xFFA9DDED),
                      width: today ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '$dayNumber',
                            style: TextStyle(
                              color: today
                                  ? const Color(0xFF0077B6)
                                  : holiday != null
                                  ? const Color(0xFF9A3412)
                                  : const Color(0xFF003B5C),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (holiday != null) ...<Widget>[
                            const Spacer(),
                            // Sized to sit in the corner at a glance. The row
                            // grows to fit it, so the task bars below are
                            // pushed down rather than covered.
                            Tooltip(
                              message: holidays
                                  .map((Holiday h) => h.name)
                                  .join(' · '),
                              child: Text(
                                holiday.emoji,
                                style: const TextStyle(
                                  fontSize: _holidayEmojiSize,
                                  height: 1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Expanded(
                        child: ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: math.min(tasks.length, 3),
                          itemBuilder: (BuildContext context, int taskIndex) {
                            final TaskItem task = tasks[taskIndex].task;
                            return Container(
                              height: 7,
                              margin: const EdgeInsets.only(bottom: 2),
                              decoration: BoxDecoration(
                                color: _taskColor(task),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            );
                          },
                        ),
                      ),
                      if (tasks.length > 3)
                        Text(
                          '+${tasks.length - 3}',
                          style: const TextStyle(
                            color: Color(0xFF005F8F),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (tasks.any((DatedTask item) => _isOverdue(item.task)))
                        const Align(
                          alignment: Alignment.bottomRight,
                          child: Icon(
                            Icons.waves,
                            color: TaskStatusColors.overdue,
                            size: 13,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDayView() {
    final List<Holiday> holidays = UsHolidays.on(_calendarDate);

    return Column(
      children: <Widget>[
        if (holidays.isNotEmpty) _buildHolidayBanner(holidays),
        Expanded(child: _buildDayContent()),
      ],
    );
  }

  /// Names the day's observances above the task list.
  ///
  /// Warm tones rather than the app's blues, so a holiday reads as something
  /// about the day itself rather than another task status.
  Widget _buildHolidayBanner(List<Holiday> holidays) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8C77A)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            holidays.first.emoji,
            style: const TextStyle(fontSize: 26),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  // Two can share a day, e.g. Juneteenth and Father's Day.
                  holidays.map((Holiday h) => h.name).join(' · '),
                  style: const TextStyle(
                    color: Color(0xFF7A4B00),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (holidays.any((Holiday h) => h.isFederal))
                  const Text(
                    'Federal holiday',
                    style: TextStyle(color: Color(0xFF9A6B1F), fontSize: 12),
                  ),
                if (holidays.any((Holiday h) => h.isApproximate))
                  const Text(
                    'Date follows a moon sighting and may differ locally',
                    style: TextStyle(color: Color(0xFF9A6B1F), fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayContent() {
    final List<DatedTask> dayTasks = _allDatedTasks.where((DatedTask item) {
      return _isSameDay(item.task.dueDate!, _calendarDate);
    }).toList();

    dayTasks.sort((DatedTask a, DatedTask b) {
      if (_isOverdue(a.task) != _isOverdue(b.task)) {
        return _isOverdue(a.task) ? -1 : 1;
      }
      if (a.task.isDone != b.task.isDone) {
        return a.task.isDone ? 1 : -1;
      }
      // The day's timed tasks in time order, ahead of its all-day ones.
      if (a.task.hasTime != b.task.hasTime) {
        return a.task.hasTime ? -1 : 1;
      }
      if (a.task.hasTime) {
        final int byTime = a.task.dueDate!.compareTo(b.task.dueDate!);
        if (byTime != 0) return byTime;
      }
      return a.task.name.compareTo(b.task.name);
    });

    if (dayTasks.isEmpty) {
      return Center(
        key: ValueKey<String>('day-empty-${_formatDate(_calendarDate)}'),
        child: Container(
          margin: const EdgeInsets.fromLTRB(28, 10, 28, 100),
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF90E0EF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.calendar_today,
                size: 64,
                color: Color(0xFF00A8E8),
              ),
              const SizedBox(height: 12),
              const Text(
                'No tasks on this day',
                style: TextStyle(
                  color: Color(0xFF003B5C),
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _addTask(initialDate: _calendarDate),
                icon: const Icon(Icons.add),
                label: const Text('Add a task here'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      key: ValueKey<String>('day-${_formatDate(_calendarDate)}'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: dayTasks.length,
      itemBuilder: (BuildContext context, int index) {
        final DatedTask item = dayTasks[index];

        return GestureDetector(
          onLongPress: () => _changeDueDate(item.task),
          child: _buildTaskCard(
            item.list,
            item.task,
            item.list.tasks.indexOf(item.task),
            showListName: true,
          ),
        );
      },
    );
  }
}

class CalendarLegendDot extends StatelessWidget {
  const CalendarLegendDot({
    super.key,
    required this.color,
    required this.label,
    required this.textColor,
  });

  final Color color;
  final String label;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class QuackersChatSheet extends StatefulWidget {
  const QuackersChatSheet({
    super.key,
    required this.service,
    required this.planner,
    required this.plannerSnapshot,
    required this.suggestedTip,
    required this.userId,
    required this.hasApiKey,
    required this.onSetUpApiKey,
    this.suggestedTask,
    this.onStartSuggestedTask,
  });

  final GeminiQuackersService service;

  /// Writes the changes the user approves.
  final PlannerRepository planner;

  /// Called for every question, so Quackers sees the planner as it is now.
  final Map<String, Object?> Function() plannerSnapshot;
  final String suggestedTip;

  /// Scopes locally-cached chat history so two accounts on one device do not
  /// read each other's conversations.
  final String userId;

  /// Whether this account already has a Gemini key stored server-side.
  final bool hasApiKey;

  /// Opens the key dialog; resolves to whether a key is set afterwards.
  final Future<bool> Function() onSetUpApiKey;

  final String? suggestedTask;
  final VoidCallback? onStartSuggestedTask;

  @override
  State<QuackersChatSheet> createState() => _QuackersChatSheetState();
}

class _QuackersChatSheetState extends State<QuackersChatSheet> {
  static const String _chatStoragePrefix = 'quackers_chat_history_v2';

  /// Shown on a fresh chat so it is obvious Quackers can change things too.
  static const List<String> _examples = <String>[
    'What’s overdue?',
    'Plan my day tomorrow',
    'Give me 2 hours Saturday for homework',
  ];

  String get _chatStorageKey => '$_chatStoragePrefix.${widget.userId}';
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<QuackersChatMessage> _messages = <QuackersChatMessage>[];
  bool _isSending = false;
  bool _isLoadingHistory = true;
  late bool _hasKey = widget.hasApiKey;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _saveHistory();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String question = _controller.text.trim();
    if (question.isEmpty || _isSending) return;
    setState(() {
      _messages.add(QuackersChatMessage(text: question, isUser: true));
      _controller.clear();
      _isSending = true;
    });
    _scrollToBottom();
    try {
      final QuackersReply reply = await _askWithRetry(
        question: question,
        conversation: _messages.length > 1
            ? _messages.sublist(0, _messages.length - 1)
            : const <QuackersChatMessage>[],
      );
      if (!mounted) return;
      final ChangeProposal? proposal = reply.changes.isEmpty
          ? null
          : ChangeProposal(reply.changes);
      setState(
        () => _messages.add(
          QuackersChatMessage(
            text: reply.text,
            isUser: false,
            proposal: proposal,
          ),
        ),
      );
      _saveHistory();
      if (proposal != null && proposal.appliesImmediately) {
        await _applyProposal(proposal);
      }
    } on QuackersException catch (error) {
      if (!mounted) return;
      if (error.needsApiKey) {
        // The saved key is missing or Gemini rejected it; the setup panel is
        // the only thing the user can act on.
        setState(() => _hasKey = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      } else if (error.retryable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Quackers is still busy. Your question is saved—please try again shortly.',
            ),
          ),
        );
      } else {
        setState(
          () => _messages.add(
            QuackersChatMessage(
              text: 'Aww, I could not answer that: ${error.message}',
              isUser: false,
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          const QuackersChatMessage(
            text:
                'My duck radio lost its signal. Please check your connection and try again.',
            isUser: false,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  Future<QuackersReply> _askWithRetry({
    required String question,
    required List<QuackersChatMessage> conversation,
  }) async {
    const List<Duration> delays = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ];
    for (int attempt = 0; attempt <= delays.length; attempt++) {
      try {
        return await widget.service.respond(
          question: question,
          planner: widget.plannerSnapshot(),
          conversation: conversation,
        );
      } on QuackersException catch (error) {
        if (!error.retryable || attempt == delays.length) rethrow;
        await Future<void>.delayed(delays[attempt]);
      }
    }
    throw const QuackersException('Quackers could not respond.');
  }

  /// Writes the ticked changes in one batch, keeping what Undo needs.
  Future<void> _applyProposal(ChangeProposal proposal) async {
    final List<TaskChange> chosen = proposal.selectedChanges;
    if (chosen.isEmpty) return;

    setState(() {
      proposal.status = ProposalStatus.applying;
      proposal.error = null;
    });
    try {
      final TaskRestorePoint point = await widget.planner.applyTaskChanges(
        chosen,
      );
      if (!mounted) return;
      setState(() {
        proposal.status = ProposalStatus.applied;
        proposal.restorePoint = point;
      });
      _revealIfLatest(proposal);
    } on StaleTaskChangeException catch (error) {
      if (!mounted) return;
      // Left pending so the user can untick that one and apply the rest.
      setState(() {
        proposal.status = ProposalStatus.pending;
        proposal.error =
            '“${error.taskName}” was changed or removed since Quackers '
            'looked. Untick it, or ask again for a fresh plan.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        proposal.status = ProposalStatus.pending;
        proposal.error =
            'Could not save those changes. Check your connection and try '
            'again.';
      });
    }
  }

  Future<void> _undoProposal(ChangeProposal proposal) async {
    final TaskRestorePoint? point = proposal.restorePoint;
    if (point == null) return;

    setState(() {
      proposal.status = ProposalStatus.undoing;
      proposal.error = null;
    });
    try {
      await widget.planner.restore(point);
      if (!mounted) return;
      setState(() => proposal.status = ProposalStatus.undone);
      _revealIfLatest(proposal);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        proposal.status = ProposalStatus.applied;
        proposal.error = 'Could not undo. Check your connection and try again.';
      });
    }
  }

  /// The card changes height as it changes state; keep the newest one in
  /// view, but leave the scroll alone for an older one the user scrolled to.
  void _revealIfLatest(ChangeProposal proposal) {
    if (_messages.isNotEmpty && identical(_messages.last.proposal, proposal)) {
      _scrollToBottom();
    }
  }

  void _askExample(String example) {
    if (_isSending) return;
    _controller.text = example;
    _send();
  }

  Future<void> _loadHistory() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? raw = preferences.getString(_chatStorageKey);
    if (raw != null) {
      try {
        final List<dynamic> saved = jsonDecode(raw) as List<dynamic>;
        _messages.addAll(
          saved.map((dynamic item) {
            final Map<String, dynamic> message = item as Map<String, dynamic>;
            return QuackersChatMessage(
              text: message['text'] as String,
              isUser: message['isUser'] as bool,
            );
          }),
        );
      } catch (_) {
        await preferences.remove(_chatStorageKey);
      }
    }
    if (mounted) setState(() => _isLoadingHistory = false);
  }

  Future<void> _saveHistory() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _chatStorageKey,
      jsonEncode(
        _messages
            .map(
              (QuackersChatMessage message) => <String, dynamic>{
                'text': message.text,
                'isUser': message.isUser,
              },
            )
            .toList(),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Column(
            children: <Widget>[
              const Row(
                children: <Widget>[
                  DuckSuitCapybara(size: 54),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Chat with Quackers',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF003B5C),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!_hasKey)
                Expanded(child: _buildApiKeySetup())
              else if (_isLoadingHistory)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...<Widget>[
                if (_messages.isEmpty) _buildWelcome(),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 8),
                    itemCount: _messages.length + (_isSending ? 1 : 0),
                    itemBuilder: (BuildContext context, int index) {
                      if (index == _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final QuackersChatMessage message = _messages[index];
                      final ChangeProposal? proposal = message.proposal;
                      final Widget bubble = Align(
                        alignment: message.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 10,
                          ),
                          constraints: const BoxConstraints(maxWidth: 310),
                          decoration: BoxDecoration(
                            color: message.isUser
                                ? const Color(0xFF0077B6)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            message.text,
                            style: TextStyle(
                              color: message.isUser
                                  ? Colors.white
                                  : const Color(0xFF174E68),
                            ),
                          ),
                        ),
                      );
                      if (proposal == null) return bubble;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          bubble,
                          ChangeProposalCard(
                            proposal: proposal,
                            onApply: () => _applyProposal(proposal),
                            onCancel: () => setState(
                              () => proposal.status = ProposalStatus.cancelled,
                            ),
                            onUndo: () => _undoProposal(proposal),
                            onToggle: (int i) => setState(
                              () =>
                                  proposal.selected[i] = !proposal.selected[i],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Ask or plan something…',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _isSending ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                      tooltip: 'Send question',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Shown until this account has a Gemini key stored server-side.
  Widget _buildApiKeySetup() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const DuckSuitCapybara(size: 84),
          const SizedBox(height: 14),
          const Text(
            'Quackers needs your Gemini key',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF003B5C),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Get a free key at aistudio.google.com/apikey. It is encrypted '
            'before it is stored and never sent back to this app, so you only '
            'enter it once.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Color(0xFF41708A),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () async {
              final bool ready = await widget.onSetUpApiKey();
              if (ready && mounted) setState(() => _hasKey = true);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0077B6),
            ),
            icon: const Icon(Icons.key_outlined),
            label: const Text('Add API key'),
          ),
        ],
      ),
    ),
  );

  Widget _buildWelcome() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4BF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.suggestedTask == null
              ? 'Your list is clear — nicely done!'
              : 'I’d start with “${widget.suggestedTask}”.',
          style: const TextStyle(
            color: Color(0xFF493600),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.suggestedTip,
          style: const TextStyle(color: Color(0xFF6A5200)),
        ),
        if (widget.onStartSuggestedTask != null) ...<Widget>[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: widget.onStartSuggestedTask,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start this task'),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'I can change your planner too. Try:',
          style: TextStyle(color: Color(0xFF6A5200), fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final String example in _examples)
              ActionChip(
                label: Text(example),
                onPressed: () => _askExample(example),
              ),
          ],
        ),
      ],
    ),
  );
}

class CalendarWeekdayLabel extends StatelessWidget {
  const CalendarWeekdayLabel(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

