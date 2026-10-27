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

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.repository, required this.day});

  final AppRepository repository;
  final DateTime day;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
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
  bool _loadFailed = false;
  String _activeList = 'mustDo';
  String _activeTab = 'today';
  Future<void> _writeQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed) {
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
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final data = await widget.repository.loadTasksForDate(
        dateKey(widget.day),
      );
      if (data != null) {
        _replaceBuckets(_todayTasks, _parseTaskBuckets(data['todayTasks']));
        _replaceBuckets(_missedTasks, _parseTaskBuckets(data['missedTasks']));
        _recurringTasks
          ..clear()
          ..addAll(_parseRecurringTasks(data['recurringTasks']));
        _scheduledTasks
          ..clear()
          ..addAll(_parseTaskList(data['scheduledTasks']));
      }
    } catch (_) {
      _loadFailed = true;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showAddTaskDialog() async {
    var draftText = '';
    TaskRepeat? repeat;
    var selectedDate = dateOnly(widget.day);
    final result =
        await showDialog<({String text, TaskRepeat? repeat, DateTime date})>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
            builder: (context, updateDialog) => AlertDialog(
                  title: const Text('নতুন কাজ যোগ করুন'),
                  content: SingleChildScrollView(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        autofocus: true,
                        minLines: 1,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: _activeList == 'mustDo'
                              ? 'অবশ্যই করতে হবে'
                              : 'করা ভালো',
                        ),
                        onChanged: (value) => draftText = value,
                        onSubmitted: (value) => Navigator.of(context).pop(
                            (text: value, repeat: repeat, date: selectedDate)),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<TaskRepeat?>(
                        initialValue: repeat,
                        decoration:
                            const InputDecoration(labelText: 'পুনরাবৃত্তি'),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('একবার')),
                          DropdownMenuItem(
                              value: TaskRepeat.daily, child: Text('প্রতিদিন')),
                          DropdownMenuItem(
                              value: TaskRepeat.weekly,
                              child: Text('প্রতি সপ্তাহে')),
                        ],
                        onChanged: (value) =>
                            updateDialog(() => repeat = value),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            calendarDelegate: AppCalendarDelegate(
                                Localizations.localeOf(context)),
                            context: context,
                            initialDate: selectedDate,
                            firstDate: dateOnly(widget.day),
                            lastDate: DateTime(widget.day.year + 10, 12, 31),
                          );
                          if (picked != null) {
                            updateDialog(() => selectedDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text('তারিখ: ${compactDateLabel(selectedDate)}'),
                      ),
                      if (repeat == TaskRepeat.weekly)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                              '${compactDateLabel(selectedDate)} তারিখের বারেই প্রতি সপ্তাহে যোগ হবে'),
                        ),
                    ],
                  )),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('বাতিল'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop((
                        text: draftText,
                        repeat: repeat,
                        date: selectedDate
                      )),
                      child: const Text('যোগ করুন'),
                    ),
                  ],
                ));
      },
    );

    if (!mounted) return;

    final text = result?.text.trim() ?? '';
    if (text.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final task = TaskItem(
      id: '${now.microsecondsSinceEpoch}',
      text: text,
      completed: false,
      createdAt: now.toIso8601String(),
      dateCreated: dateKey(widget.day),
      dueDate: dateKey(result!.date),
      section: _activeList,
    );

    final section = _activeList;
    final isFuture = dateKey(result.date) != dateKey(widget.day);
    await _runChange((today, missed, recurring, scheduled) {
      if (result.repeat case final frequency?) {
        if (!recurring.any((item) => item.id == task.id)) {
          recurring.add(RecurringTask(
            id: task.id,
            text: text,
            section: section,
            repeat: frequency,
            startDate: dateKey(result.date),
          ));
        }
        if (isFuture &&
            !scheduled.any((item) => item.id == '${task.id}:${task.dueDate}')) {
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
      } else if (isFuture && !scheduled.any((item) => item.id == task.id)) {
        scheduled.add(task);
      } else if (!isFuture &&
          !today[section]!.any((item) => item.id == task.id)) {
        today[section]!.add(task);
      }
    });
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
    ) apply,
  ) {
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

    final operation = _writeQueue.then((_) async {
      final data = await widget.repository.changeTasks(
        date: dateKey(widget.day),
        apply: apply,
      );
      if (mounted && data != null) {
        setState(() {
          _replaceBuckets(_todayTasks, _parseTaskBuckets(data['todayTasks']));
          _replaceBuckets(_missedTasks, _parseTaskBuckets(data['missedTasks']));
          _recurringTasks
            ..clear()
            ..addAll(_parseRecurringTasks(data['recurringTasks']));
          _scheduledTasks
            ..clear()
            ..addAll(_parseTaskList(data['scheduledTasks']));
        });
      }
    });
    _writeQueue = operation.catchError((Object _) {
      _showMessage('সিঙ্ক করতে সমস্যা হয়েছে');
    });
    return _writeQueue;
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
