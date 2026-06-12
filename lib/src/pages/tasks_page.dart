import 'package:flutter/material.dart';

import '../app_repository.dart';
import '../date_helpers.dart';
import '../models.dart';
import '../widgets/page_frame.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.repository});

  final AppRepository repository;

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

  bool _loading = true;
  String _activeList = 'mustDo';
  String _activeTab = 'today';

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

    final visibleTasks = _activeTab == 'today' ? _todayTasks : _missedTasks;
    final tasks = visibleTasks[_activeList] ?? [];

    return Stack(
      children: [
        PageFrame(
          title: 'আজকের কাজ',
          subtitle: 'অবশ্যই করতে হবে এবং করা ভালো কাজ আলাদা করে রাখুন',
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
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        Chip(label: Text('${tasks.length}')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (tasks.isEmpty)
                      EmptyState(
                        icon: _activeTab == 'today'
                            ? Icons.task_alt_outlined
                            : Icons.history_toggle_off_outlined,
                        message: _activeTab == 'today'
                            ? 'এখনো কোন কাজ যোগ করা হয়নি'
                            : 'কোন মিসড কাজ নেই',
                      )
                    else
                      ...tasks.map(
                        (task) => _TaskTile(
                          task: task,
                          onToggle: () => _toggleTask(task.id),
                          onDelete: () => _deleteTask(task.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 22,
          bottom: 22,
          child: FloatingActionButton.extended(
            onPressed: _activeTab == 'today' ? _showAddTaskDialog : null,
            icon: const Icon(Icons.add),
            label: const Text('কাজ যোগ'),
          ),
        ),
      ],
    );
  }

  String get _sectionTitle {
    final prefix = _activeTab == 'today' ? 'আজকের' : 'মিসড';
    final section = _activeList == 'mustDo' ? 'অবশ্যই করতে হবে' : 'করা ভালো';
    return '$prefix $section';
  }

  Future<void> _load() async {
    try {
      final data = await widget.repository.loadTasks();
      if (data != null) {
        _replaceBuckets(_todayTasks, _parseTaskBuckets(data['todayTasks']));
        _replaceBuckets(_missedTasks, _parseTaskBuckets(data['missedTasks']));
        final moved = _moveOldTasksToMissed();
        if (moved) {
          await _save();
        }
      }
    } catch (_) {
      _showMessage('কাজ লোড করতে সমস্যা হয়েছে');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showAddTaskDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('নতুন কাজ যোগ করুন'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText:
                  _activeList == 'mustDo' ? 'অবশ্যই করতে হবে' : 'করা ভালো',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('যোগ করুন'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    final text = result?.trim() ?? '';
    if (text.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final task = TaskItem(
      id: '${now.microsecondsSinceEpoch}',
      text: text,
      completed: false,
      createdAt: now.toIso8601String(),
      dateCreated: dateKey(now),
    );

    setState(() {
      _todayTasks[_activeList] = [...?_todayTasks[_activeList], task];
    });
    await _save();
  }

  Future<void> _toggleTask(String id) async {
    final bucket = _activeTab == 'today' ? _todayTasks : _missedTasks;
    final tasks = bucket[_activeList] ?? [];
    bucket[_activeList] = tasks
        .map((task) =>
            task.id == id ? task.copyWith(completed: !task.completed) : task)
        .toList();
    setState(() {});
    await _save();
  }

  Future<void> _deleteTask(String id) async {
    final bucket = _activeTab == 'today' ? _todayTasks : _missedTasks;
    bucket[_activeList] =
        (bucket[_activeList] ?? []).where((task) => task.id != id).toList();
    setState(() {});
    await _save();
  }

  Future<void> _save() async {
    try {
      await widget.repository.saveTasks(
        todayTasks: _todayTasks,
        missedTasks: _missedTasks,
      );
    } catch (_) {
      _showMessage('সিঙ্ক করতে সমস্যা হয়েছে');
    }
  }

  bool _moveOldTasksToMissed() {
    var moved = false;
    final today = dateKey();

    for (final section in ['mustDo', 'goodToDo']) {
      final retained = <TaskItem>[];
      final missed = [...?_missedTasks[section]];

      for (final task in _todayTasks[section] ?? <TaskItem>[]) {
        final createdToday =
            task.dateCreated.isEmpty || task.dateCreated == today;
        if (createdToday) {
          retained.add(task);
        } else if (!task.completed) {
          missed.add(task);
          moved = true;
        } else {
          moved = true;
        }
      }

      _todayTasks[section] = retained;
      _missedTasks[section] = missed;
    }

    return moved;
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
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        ChoiceChip(
          label: const Text('আজকের কাজ'),
          selected: activeTab == 'today',
          onSelected: (_) => onTabChanged('today'),
        ),
        ChoiceChip(
          label: const Text('মিসড কাজ'),
          selected: activeTab == 'missed',
          onSelected: (_) => onTabChanged('missed'),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Must do'),
          selected: activeList == 'mustDo',
          onSelected: (_) => onListChanged('mustDo'),
        ),
        ChoiceChip(
          label: const Text('Good to do'),
          selected: activeList == 'goodToDo',
          onSelected: (_) => onListChanged('goodToDo'),
        ),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  final TaskItem task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          leading:
              Checkbox(value: task.completed, onChanged: (_) => onToggle()),
          title: Text(
            task.text,
            style: TextStyle(
              decoration: task.completed ? TextDecoration.lineThrough : null,
              color: task.completed ? Colors.grey.shade600 : null,
            ),
          ),
          trailing: IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            color: Colors.red.shade500,
          ),
        ),
      ),
    );
  }
}
