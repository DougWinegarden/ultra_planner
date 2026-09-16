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
import 'data/planner_repository.dart';
import 'data/user_settings_repository.dart';
import 'firebase_options.dart';
import 'gemini_quackers_service.dart';
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
  late final UserSettingsRepository _settings;

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

  @override
  void initState() {
    super.initState();
    _planner = PlannerRepository(uid: widget.user.uid);
    _settings = UserSettingsRepository(uid: widget.user.uid);
    _subscribeToLists();
    _restoreGeminiApiKey();
  }

  @override
  void dispose() {
    _listSub?.cancel();
    _quackers.dispose();
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

  /// Pulls the saved Gemini key so the assistant is ready without re-entry.
  Future<void> _restoreGeminiApiKey() async {
    try {
      final String? key = await _settings.loadGeminiApiKey();
      if (key != null) {
        _quackers.setApiKey(key);
        if (mounted) setState(() {});
      }
    } catch (_) {
      // Not fatal -- the assistant just falls back to its setup screen.
    }
  }

  Future<void> _persistGeminiApiKey(String apiKey) async {
    _quackers.setApiKey(apiKey);
    await _settings.saveGeminiApiKey(apiKey);
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
                            TaskItem(name: taskName, dueDate: selectedDate),
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
    );
    if (!mounted) return;

    if (task.dueDate != null) {
      setState(() => _calendarDate = task.dueDate!);
    }
  }

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

    await _planner.setTaskDueDate(task.id, date);
    if (!mounted) return;
    setState(() => _calendarDate = date);
  }

  Future<void> _editTaskDate(DatedTask datedTask) async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: datedTask.task.dueDate ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );

    if (!mounted || date == null) {
      return;
    }

    await _planner.setTaskDueDate(datedTask.task.id, date);
    if (!mounted) return;
    setState(() => _calendarDate = date);
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
      return const Color(0xFF006994);
    }
    if (task.isDone) {
      return const Color(0xFF023E8A);
    }
    return const Color(0xFF00BCD4);
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

  String get _taskContext => _lists
      .map((TaskListData list) {
        final String tasks = list.tasks
            .map(
              (TaskItem task) =>
                  '- ${task.name} | ${task.isDone ? 'completed' : 'not completed'} | ${task.dueDate == null ? 'no due date' : 'due ${_formatDate(task.dueDate!)}'}',
            )
            .join('\n');
        return 'List: ${list.name}\n${tasks.isEmpty ? '- no tasks' : tasks}';
      })
      .join('\n\n');

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
          taskContext: _taskContext,
          suggestedTask: pick?.task.name,
          suggestedTip: _assistantTip,
          userId: widget.user.uid,
          onSaveApiKey: _persistGeminiApiKey,
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
          const Positioned.fill(child: AnimatedOceanBackground()),
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
              backgroundColor: const Color(0xFF0077B6),
              foregroundColor: Colors.white,
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
          const Icon(Icons.water_drop, color: Color(0xFF005F8F), size: 30),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Ocean Lists',
              style: TextStyle(
                color: Color(0xFF003B5C),
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
              _quackers.isConfigured
                  ? 'Change Gemini API key'
                  : 'Add Gemini API key',
            ),
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
        backgroundColor: const Color(0xFF0077B6),
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

  /// Lets the key be set (or replaced) without going through the chat sheet.
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
                  title: const Text('Gemini API key'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(
                        'Saved to your account, so you only set it up once.',
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
                            icon: Icon(
                              obscured
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setDialogState(
                              () => obscured = !obscured,
                            ),
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
      await _persistGeminiApiKey(key);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemini key saved to your account.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save key: $error')),
      );
    }
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
            ? const Color(0xFFD8E5FA).withValues(alpha: 0.97)
            : overdue
            ? const Color(0xFFD7F4FF).withValues(alpha: 0.97)
            : Colors.white.withValues(alpha: 0.93),
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: overdue ? const Color(0xFF006994) : const Color(0xFF90E0EF),
            width: overdue ? 2 : 1,
          ),
        ),
        child: Column(
          children: <Widget>[
            if (overdue)
              const SizedBox(
                height: 17,
                width: double.infinity,
                child: CustomPaint(painter: TsunamiStripPainter()),
              ),
            CheckboxListTile(
              value: task.isDone,
              activeColor: const Color(0xFF023E8A),
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
                        ? '🌊 Tsunami overdue: ${_formatDate(task.dueDate!)}'
                        : 'Due: ${_formatDate(task.dueDate!)}',
                    style: TextStyle(
                      color: overdue
                          ? const Color(0xFF006994)
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
        children: const <Widget>[
          CalendarLegendDot(color: Color(0xFF00BCD4), label: 'Unfinished'),
          CalendarLegendDot(color: Color(0xFF023E8A), label: 'Finished'),
          CalendarLegendDot(
            color: Color(0xFF006994),
            label: '🌊 Tsunami overdue',
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
                  const Color(0xFF00BCD4),
                  unfinished,
                  Icons.pending_actions,
                ),
                const SizedBox(height: 4),
                _yearCountRow(
                  const Color(0xFF023E8A),
                  finished,
                  Icons.task_alt,
                ),
                const SizedBox(height: 4),
                _yearCountRow(const Color(0xFF006994), overdue, Icons.waves),
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
    final int daysInMonth = DateTime(
      _calendarDate.year,
      _calendarDate.month + 1,
      0,
    ).day;
    final int leadingEmptyDays = firstDay.weekday - 1;
    final int cellCount = leadingEmptyDays + daysInMonth;
    final int rowCount = (cellCount / 7).ceil();
    final int totalCells = rowCount * 7;

    return Column(
      key: ValueKey<String>(
        'month-${_calendarDate.year}-${_calendarDate.month}',
      ),
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              CalendarWeekdayLabel('Mon'),
              CalendarWeekdayLabel('Tue'),
              CalendarWeekdayLabel('Wed'),
              CalendarWeekdayLabel('Thu'),
              CalendarWeekdayLabel('Fri'),
              CalendarWeekdayLabel('Sat'),
              CalendarWeekdayLabel('Sun'),
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

              if (dayNumber < 1 || dayNumber > daysInMonth) {
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
                      Text(
                        '$dayNumber',
                        style: TextStyle(
                          color: today
                              ? const Color(0xFF0077B6)
                              : const Color(0xFF003B5C),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
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
                            color: Color(0xFF006994),
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
          onLongPress: () => _editTaskDate(item),
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
  });

  final Color color;
  final String label;

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
          style: const TextStyle(
            color: Color(0xFF174E68),
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
    required this.taskContext,
    required this.suggestedTip,
    required this.userId,
    required this.onSaveApiKey,
    this.suggestedTask,
    this.onStartSuggestedTask,
  });

  final GeminiQuackersService service;
  final String taskContext;
  final String suggestedTip;

  /// Scopes locally-cached chat history so two accounts on one device do not
  /// read each other's conversations.
  final String userId;

  /// Persists the key to the user's Firestore settings document.
  final Future<void> Function(String apiKey) onSaveApiKey;

  final String? suggestedTask;
  final VoidCallback? onStartSuggestedTask;

  @override
  State<QuackersChatSheet> createState() => _QuackersChatSheetState();
}

class _QuackersChatSheetState extends State<QuackersChatSheet> {
  static const String _chatStoragePrefix = 'quackers_chat_history_v2';

  String get _chatStorageKey => '$_chatStoragePrefix.${widget.userId}';
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<QuackersChatMessage> _messages = <QuackersChatMessage>[];
  bool _isSending = false;
  bool _isApiKeyVisible = false;
  late bool _isReady;
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _isReady = widget.service.isConfigured;
    _loadHistory();
  }

  @override
  void dispose() {
    _saveHistory();
    _controller.dispose();
    _apiKeyController.dispose();
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
      final String answer = await _askWithRetry(
        question: question,
        conversation: _messages.length > 1
            ? _messages.sublist(0, _messages.length - 1)
            : const <QuackersChatMessage>[],
      );
      if (!mounted) return;
      setState(
        () => _messages.add(QuackersChatMessage(text: answer, isUser: false)),
      );
      _saveHistory();
    } on QuackersException catch (error) {
      if (!mounted) return;
      if (error.retryable) {
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

  Future<String> _askWithRetry({
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
          taskContext: widget.taskContext,
          conversation: conversation,
        );
      } on QuackersException catch (error) {
        if (!error.retryable || attempt == delays.length) rethrow;
        await Future<void>.delayed(delays[attempt]);
      }
    }
    throw const QuackersException('Quackers could not respond.');
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

  Future<void> _saveApiKey() async {
    final String key = _apiKeyController.text.trim();
    if (key.isEmpty) return;

    setState(() {
      _isReady = true;
      _apiKeyController.clear();
    });

    try {
      await widget.onSaveApiKey(key);
    } catch (error) {
      // The key still works for this session; it just did not persist.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Key saved for now, but could not sync to your account: $error',
          ),
        ),
      );
    }
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
              if (!_isReady)
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
                      return Align(
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
                          hintText: 'Ask about your tasks…',
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
      ],
    ),
  );

  Widget _buildApiKeySetup() => Center(
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF90E0EF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.key_rounded, size: 36, color: Color(0xFF0077B6)),
          const SizedBox(height: 10),
          const Text(
            'Connect Quackers to Gemini',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: Color(0xFF003B5C),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Paste your Gemini API key to start chatting. It is used only for this app session.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF456D7F)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            obscureText: !_isApiKeyVisible,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _saveApiKey(),
            decoration: InputDecoration(
              labelText: 'Gemini API key',
              hintText: 'AIza…',
              filled: true,
              fillColor: const Color(0xFFF4FCFF),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _isApiKeyVisible ? 'Hide key' : 'Show key',
                icon: Icon(
                  _isApiKeyVisible ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _isApiKeyVisible = !_isApiKeyVisible),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saveApiKey,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Start chatting'),
            ),
          ),
        ],
      ),
    ),
  );
}

class CalendarWeekdayLabel extends StatelessWidget {
  const CalendarWeekdayLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF005F8F),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

