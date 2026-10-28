import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../display_formatters.dart';
import '../app_calendar_delegate.dart';
import '../date_helpers.dart';
import '../daily_logic.dart';
import '../models.dart';
import '../widgets/page_frame.dart';
import '../widgets/load_failure_state.dart';
import '../widgets/status_badge.dart';
import 'task_entry_dialog.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.repository,
    required this.day,
    this.active = true,
  });

  final AppRepository repository;
  final DateTime day;
  final bool active;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with WidgetsBindingObserver {
  final Map<String, List<TaskItem>> _todayTasks = {
    'mustDo': [],
    'goodToDo': [],
  };
  final Map<String, List<TaskItem>> _missedTasks = {
    'mustDo': [],
    'goodToDo': [],
  };
  final List<RecurringTask> _recurringTasks = [];
  final List<TaskItem> _scheduledTasks = [];

  bool _loading = true;
  bool _refreshing = false;
  bool _hasLoaded = false;
  bool _loadFailed = false;
  String _activeList = 'mustDo';
  String _activeTab = 'today';
  Future<void> _writeQueue = Future<void>.value();
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant TasksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contextChanged = oldWidget.repository.uid != widget.repository.uid ||
        dateKey(oldWidget.day) != dateKey(widget.day);
    if (contextChanged) {
      _hasLoaded = false;
      _writeQueue = Future<void>.value();
      _todayTasks['mustDo'] = [];
      _todayTasks['goodToDo'] = [];
      _missedTasks['mustDo'] = [];
      _missedTasks['goodToDo'] = [];
      _recurringTasks.clear();
      _scheduledTasks.clear();
    }
    if (!identical(oldWidget.repository, widget.repository) ||
        contextChanged ||
        (!oldWidget.active && widget.active && widget.repository.canSync)) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.active &&
        widget.repository.canSync) {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed && !_hasLoaded) {
      return LoadFailureState(title: 'কাজ লোড করা যায়নি', onRetry: _load);
    }

    final tasks = _activeTab == 'scheduled'
        ? (_scheduledTasks.where((task) => task.section == _activeList).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate)))
        : (_activeTab == 'today' ? _todayTasks : _missedTasks)[_activeList] ??
            [];
    final wide = MediaQuery.sizeOf(context).width >= 820;

    return Stack(
      children: [
        PageFrame(
          title: 'আজকের কাজ',
          subtitle: 'প্রয়োজনীয় ও ভালো কাজ আলাদা রাখুন',
          action: wide && _activeTab != 'missed'
              ? FilledButton.icon(
                  onPressed: _showAddTaskDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('কাজ যোগ'))
              : null,
          children: [
            if (_refreshing) const LinearProgressIndicator(),
            if (_loadFailed)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.sync_problem_outlined),
                  title: const Text('সর্বশেষ কাজ আনা যায়নি'),
                  trailing: TextButton(
                    onPressed: _load,
                    child: const Text('রিট্রাই'),
                  ),
                ),
              ),
            _FilterBar(
              activeTab: _activeTab,
              activeList: _activeList,
              onTabChanged: (value) => setState(() => _activeTab = value),
              onListChanged: (value) => setState(() => _activeList = value),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _sectionTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        StatusBadge(
                            label: '${banglaNumber(tasks.length)}টি কাজ'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (tasks.isEmpty)
                      EmptyState(
                        icon: _activeTab == 'today'
                            ? Icons.task_alt_outlined
                            : Icons.history_toggle_off_outlined,
                        message: switch (_activeTab) {
                          'today' => 'এখনো কোন কাজ যোগ করা হয়নি',
                          'scheduled' => 'কোন নির্ধারিত কাজ নেই',
                          _ => 'কোন মিসড কাজ নেই',
                        },
                      )
                    else
                      ...tasks.map(
                        (task) => _TaskTile(
                          task: task,
                          currentDate: dateKey(widget.day),
                          repeat: _recurringTasks
                              .where((item) => item.id == task.recurrenceId)
                              .firstOrNull
                              ?.repeat,
                          onToggle: _activeTab == 'scheduled'
                              ? null
                              : () => _toggleTask(task.id),
                          onReschedule: () => _rescheduleTask(task),
                          onDelete: () => _deleteTask(task.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (!wide && _activeTab != 'missed')
          Positioned(
            right: 22,
            bottom: 22,
            child: FloatingActionButton.extended(
              onPressed: _activeTab == 'missed' ? null : _showAddTaskDialog,
              icon: const Icon(Icons.add),
              label: const Text('কাজ যোগ'),
            ),
          ),
      ],
    );
  }

  String get _sectionTitle {
    return _activeList == 'mustDo' ? 'অবশ্যই করতে হবে' : 'করা ভালো';
  }

  Future<void> _load() async {
    final requestId = ++_loadRequestId;
    final repository = widget.repository;
    final day = dateKey(widget.day);
    setState(() {
      _loading = !_hasLoaded;
      _refreshing = _hasLoaded;
      _loadFailed = false;
    });
    try {
      await _writeQueue;
      if (!mounted || requestId != _loadRequestId) return;
      final data = await repository.loadTasksForDate(day);
      if (!mounted ||
          requestId != _loadRequestId ||
          !identical(repository, widget.repository) ||
          day != dateKey(widget.day)) {
        return;
      }
      if (data != null) {
        _applySnapshot(data);
      }
      _hasLoaded = true;
    } catch (_) {
      if (!mounted || requestId != _loadRequestId) return;
      _loadFailed = true;
    } finally {
      if (mounted && requestId == _loadRequestId) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _showAddTaskDialog() async {
    final section = _activeList;
    // Reuse the same identity if the server commits but the response is lost.
    // The repository transaction can then recognize a retry as the same task.
    final createdAt = DateTime.now();
    final taskId = '${createdAt.microsecondsSinceEpoch}';
    await showDialog<void>(
      context: context,
      builder: (_) => TaskEntryDialog(
        section: section,
        day: widget.day,
        onSave: (text, repeat, dueDate) async {
          if (!mounted) throw StateError('The task page was closed.');
          final task = TaskItem(
            id: taskId,
            text: text,
            completed: false,
            createdAt: createdAt.toIso8601String(),
            dateCreated: dateKey(widget.day),
            dueDate: dateKey(dueDate),
            section: section,
          );
          final isFuture = dateKey(dueDate) != dateKey(widget.day);
          await _runChange((today, missed, recurring, scheduled) {
            if (repeat case final frequency?) {
              if (!recurring.any((item) => item.id == task.id)) {
                recurring.add(RecurringTask(
                  id: task.id,
                  text: text,
                  section: section,
                  repeat: frequency,
                  startDate: dateKey(dueDate),
                ));
              }
              if (isFuture &&
                  !scheduled
                      .any((item) => item.id == '${task.id}:${task.dueDate}')) {
                scheduled.add(TaskItem(
                  id: '${task.id}:${task.dueDate}',
                  text: text,
                  completed: false,
                  createdAt: task.createdAt,
                  dateCreated: task.dueDate,
                  dueDate: task.dueDate,
                  section: section,
                  recurrenceId: task.id,
                ));
              }
            } else if (isFuture &&
                !scheduled.any((item) => item.id == task.id)) {
              scheduled.add(task);
            } else if (!isFuture &&
                !today[section]!.any((item) => item.id == task.id)) {
              today[section]!.add(task);
            }
          }, propagateError: true);
        },
      ),
    );
  }

  Future<void> _toggleTask(String id) async {
    final tab = _activeTab;
    final section = _activeList;
    await _runChange((today, missed, recurring, scheduled) {
      final bucket = tab == 'today' ? today : missed;
      bucket[section] = bucket[section]!
          .map(
            (task) => task.id == id
                ? task.copyWith(completed: !task.completed)
                : task,
          )
          .toList();
    });
  }

  Future<void> _deleteTask(String id) async {
    final tab = _activeTab;
    final section = _activeList;
    final task = (tab == 'scheduled'
            ? _scheduledTasks
            : (tab == 'today' ? _todayTasks : _missedTasks)[section]!)
        .where((item) => item.id == id)
        .firstOrNull;
    if (task == null) return;
    if (tab != 'missed' && task.recurrenceId.isNotEmpty) {
      final removeSeries = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('পুনরাবৃত্ত কাজ মুছবেন?'),
          content: const Text('এই কাজটি আজ এবং ভবিষ্যতের দিন থেকে সরানো হবে।'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('মুছুন'),
            ),
          ],
        ),
      );
      if (removeSeries != true || !mounted) return;
    }
    await _runChange((today, missed, recurring, scheduled) {
      if (tab == 'scheduled') {
        scheduled.removeWhere((item) => item.id == id);
      } else {
        final bucket = tab == 'today' ? today : missed;
        bucket[section] =
            bucket[section]!.where((item) => item.id != id).toList();
      }
      if (tab != 'missed' && task.recurrenceId.isNotEmpty) {
        recurring.removeWhere((item) => item.id == task.recurrenceId);
        scheduled.removeWhere((item) => item.recurrenceId == task.recurrenceId);
      }
    });
  }

  Future<void> _rescheduleTask(TaskItem task) async {
    final tab = _activeTab;
    final section = _activeList;
    final current = DateTime.tryParse(task.dueDate) ?? dateOnly(widget.day);
    final selected = await showDatePicker(
      calendarDelegate: AppCalendarDelegate(Localizations.localeOf(context)),
      context: context,
      initialDate: current.isBefore(dateOnly(widget.day))
          ? dateOnly(widget.day)
          : current,
      firstDate: dateOnly(widget.day),
      lastDate: DateTime(widget.day.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    final nextDate = dateKey(selected);
    await _runChange((today, missed, recurring, scheduled) {
      if (tab == 'scheduled') {
        for (var i = 0; i < scheduled.length; i++) {
          if (scheduled[i].id == task.id) {
            scheduled[i] = scheduled[i].copyWith(dueDate: nextDate);
            break;
          }
        }
        return;
      }
      final bucket = tab == 'today' ? today : missed;
      final existing =
          bucket[section]!.where((item) => item.id == task.id).firstOrNull;
      if (existing == null) return;
      if (tab == 'today' && nextDate == dateKey(widget.day)) return;
      bucket[section]!.removeWhere((item) => item.id == task.id);
      final changed = existing.copyWith(
        dateCreated:
            nextDate == dateKey(widget.day) ? nextDate : existing.dateCreated,
        dueDate: nextDate,
        section: section,
      );
      if (nextDate == dateKey(widget.day)) {
        today[section]!.add(changed);
      } else {
        scheduled.add(changed.copyWith(completed: false));
      }
    });
  }

  Future<void> _runChange(
    void Function(
      Map<String, List<TaskItem>> today,
      Map<String, List<TaskItem>> missed,
      List<RecurringTask> recurring,
      List<TaskItem> scheduled,
    ) apply, {
    bool propagateError = false,
  }) {
    if (!widget.repository.canSync) {
      setState(() {
        apply(_todayTasks, _missedTasks, _recurringTasks, _scheduledTasks);
        materializeScheduledTasks(
            _todayTasks, _scheduledTasks, dateKey(widget.day));
        materializeRecurringTasks(
            _todayTasks, _recurringTasks, dateKey(widget.day),
            scheduled: _scheduledTasks);
      });
      return Future<void>.value();
    }

    final repository = widget.repository;
    final day = dateKey(widget.day);
    ++_loadRequestId;
    if (_loading || _refreshing) {
      setState(() {
        _loading = false;
        _refreshing = false;
        _loadFailed = false;
      });
    }
    final operation = _writeQueue.then((_) async {
      final data = await repository.changeTasks(
        date: day,
        apply: apply,
      );
      if (mounted &&
          data != null &&
          identical(repository, widget.repository) &&
          day == dateKey(widget.day)) {
        setState(() {
          _applySnapshot(data);
        });
      }
    });
    _writeQueue = operation.catchError((Object _) {
      if (!propagateError) _showMessage('সিঙ্ক করতে সমস্যা হয়েছে');
    });
    return propagateError ? operation : _writeQueue;
  }

  void _applySnapshot(Map<String, dynamic> data) {
    _replaceBuckets(_todayTasks, _parseTaskBuckets(data['todayTasks']));
    _replaceBuckets(_missedTasks, _parseTaskBuckets(data['missedTasks']));
    _recurringTasks
      ..clear()
      ..addAll(_parseRecurringTasks(data['recurringTasks']));
    _scheduledTasks
      ..clear()
      ..addAll(_parseTaskList(data['scheduledTasks']));
  }

  Map<String, List<TaskItem>> _parseTaskBuckets(Object? raw) {
    final map = asStringMap(raw);
    return {
      'mustDo': _parseTaskList(map['mustDo']),
      'goodToDo': _parseTaskList(map['goodToDo']),
    };
  }

  List<TaskItem> _parseTaskList(Object? raw) {
    if (raw is Iterable) {
      return raw
          .map(TaskItem.fromMap)
          .where((task) => task.text.isNotEmpty)
          .toList();
    }
    return [];
  }

  List<RecurringTask> _parseRecurringTasks(Object? raw) {
    if (raw is! Iterable) return [];
    return raw
        .where((value) =>
            asStringMap(value)['repeat'] == 'daily' ||
            asStringMap(value)['repeat'] == 'weekly')
        .map(RecurringTask.fromMap)
        .where((task) => task.id.isNotEmpty && task.text.isNotEmpty)
        .toList();
  }

  void _replaceBuckets(
    Map<String, List<TaskItem>> target,
    Map<String, List<TaskItem>> source,
  ) {
    target['mustDo'] = source['mustDo'] ?? [];
    target['goodToDo'] = source['goodToDo'] ?? [];
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.activeTab,
    required this.activeList,
    required this.onTabChanged,
    required this.onListChanged,
  });

  final String activeTab;
  final String activeList;
  final ValueChanged<String> onTabChanged;
  final ValueChanged<String> onListChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('আজকের কাজ'),
              selected: activeTab == 'today',
              onSelected: (_) => onTabChanged('today'),
            ),
            const SizedBox(width: 10),
            ChoiceChip(
              label: const Text('মিসড কাজ'),
              selected: activeTab == 'missed',
              onSelected: (_) => onTabChanged('missed'),
            ),
            const SizedBox(width: 10),
            ChoiceChip(
              label: const Text('নির্ধারিত কাজ'),
              selected: activeTab == 'scheduled',
              onSelected: (_) => onTabChanged('scheduled'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text('অগ্রাধিকার',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 4),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('অবশ্যই করতে হবে'),
            selected: activeList == 'mustDo',
            onSelected: (_) => onListChanged('mustDo'),
          ),
          ChoiceChip(
            label: const Text('করা ভালো'),
            selected: activeList == 'goodToDo',
            onSelected: (_) => onListChanged('goodToDo'),
          ),
        ],
      )
    ]);
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.currentDate,
    required this.repeat,
    required this.onToggle,
    required this.onReschedule,
    required this.onDelete,
  });

  final TaskItem task;
  final String currentDate;
  final TaskRepeat? repeat;
  final VoidCallback? onToggle;
  final VoidCallback onReschedule;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final detail = task.dueDate.isNotEmpty &&
            task.dueDate != currentDate &&
            DateTime.tryParse(task.dueDate) != null
        ? 'তারিখ: ${compactDateLabel(DateTime.parse(task.dueDate))}'
            '${repeat == null ? '' : ' • ${repeat == TaskRepeat.daily ? 'প্রতিদিন' : 'প্রতি সপ্তাহে'}'}'
        : repeat == null
            ? null
            : repeat == TaskRepeat.daily
                ? 'প্রতিদিন'
                : 'প্রতি সপ্তাহে';
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 520 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Material(
            color: Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 48,
                    height: 48,
                    child: onToggle == null
                        ? const Icon(Icons.event_outlined)
                        : Checkbox(
                            value: task.completed,
                            semanticLabel: '${task.text}: সম্পন্ন',
                            onChanged: (_) => onToggle?.call())),
                const SizedBox(width: 8),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(task.text,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                        decoration: task.completed
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: task.completed
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant
                                            : null)),
                            if (detail != null) ...[
                              const SizedBox(height: 4),
                              Text(detail,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant))
                            ],
                          ],
                        ))),
                if (compact)
                  PopupMenuButton<String>(
                    tooltip: 'কাজের অপশন',
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (value) =>
                        value == 'date' ? onReschedule() : onDelete(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'date', child: Text('তারিখ পরিবর্তন')),
                      PopupMenuItem(value: 'delete', child: Text('কাজ মুছুন')),
                    ],
                  )
                else ...[
                  IconButton(
                      tooltip: 'তারিখ পরিবর্তন',
                      onPressed: onReschedule,
                      icon: const Icon(Icons.event_outlined)),
                  IconButton(
                      tooltip: 'কাজ মুছুন',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                      color: Theme.of(context).colorScheme.error),
                ],
              ]),
            ),
          ));
    });
  }
}
