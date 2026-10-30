import 'dart:async';

import 'package:flutter/material.dart';

import '../core/records.dart';
import '../data/task_repository.dart';
import '../domain/calendar_day.dart';
import '../domain/experience_options.dart';
import '../domain/planning_time_zone.dart';
import '../domain/project.dart';
import '../domain/task.dart';
import '../domain/task_occurrence.dart';
import 'experience_strings.dart';
import 'task_editor_page.dart';

enum TaskWorkspaceView { inbox, today, upcoming, all, completed, trash }

class TaskWorkspacePage extends StatefulWidget {
  const TaskWorkspacePage(
      {super.key,
      required this.repository,
      required this.options,
      required this.workspaceId,
      this.clock});
  final TaskRepository repository;
  final ExperienceOptions options;
  final String workspaceId;
  final DateTime Function()? clock;
  @override
  State<TaskWorkspacePage> createState() => _TaskWorkspacePageState();
}

class _TaskWorkspacePageState extends State<TaskWorkspacePage> {
  late Stream<List<WorkspaceRecord>> _records;
  TaskWorkspaceView _view = TaskWorkspaceView.inbox;
  String _query = '';
  String? _projectId;
  Timer? _dayTimer;
  final _pending = <String>{};
  ExperienceStrings get strings => ExperienceStrings(widget.options.language);
  CalendarDay get today => CalendarDay.fromDate(PlanningTimeZone.inZone(
      (widget.clock ?? DateTime.now)(), widget.options.timeZone));
  @override
  void initState() {
    super.initState();
    _watch();
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _watch() => _records = widget.repository.database
      .watch(workspaceId: widget.workspaceId, includeDeleted: true);
  @override
  void didUpdateWidget(TaskWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId ||
        oldWidget.repository != widget.repository) {
      _projectId = null;
      _watch();
    }
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    super.dispose();
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_pending.contains(id)) return;
    setState(() => _pending.add(id));
    try {
      await action();
    } on TaskEditFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.taskError(error.code))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.taskError('save-failed'))));
      }
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  Future<void> _editor(
      List<ProductivityTask> tasks, List<ProductivityProject> projects,
      {ProductivityTask? task, String? parentId}) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => ProductivityTaskEditorPage(
            repository: widget.repository,
            options: widget.options,
            workspaceId: widget.workspaceId,
            task: task,
            tasks: tasks,
            projects: projects,
            parentId: parentId)));
  }

  Future<void> _project() async {
    final id = newRecordId();
    final created = await showDialog<bool>(
        context: context,
        builder: (context) => _ProjectNameDialog(
            strings: strings,
            onCreate: (name) async {
              await widget.repository.createProject(ProductivityProject(
                  id: id, workspaceId: widget.workspaceId, name: name));
            }));
    if (created == true && mounted) setState(() => _projectId = id);
  }

  bool _visible(
      ProductivityTask task, TaskStatus status, bool deleted, CalendarDay day) {
    if (_view == TaskWorkspaceView.trash) return deleted;
    if (deleted || task.archived) return false;
    if (_view == TaskWorkspaceView.completed) {
      return status == TaskStatus.completed;
    }
    if (_view != TaskWorkspaceView.all && status == TaskStatus.completed) {
      return false;
    }
    final scheduled = task.scheduledDay ??
        (task.scheduledAt == null
            ? null
            : CalendarDay.fromDate(PlanningTimeZone.inZone(
                task.scheduledAt!, widget.options.timeZone)));
    final deadline = task.deadline == null
        ? null
        : CalendarDay.fromDate(
            PlanningTimeZone.inZone(task.deadline!, widget.options.timeZone));
    return switch (_view) {
      TaskWorkspaceView.inbox => task.inbox,
      TaskWorkspaceView.today => task.recurrence != null
          ? task.recurrence!.between(day, day).isNotEmpty
          : (scheduled != null && !scheduled.isAfter(day)) ||
              (deadline != null && !deadline.isAfter(day)),
      TaskWorkspaceView.upcoming => task.recurrence != null
          ? task.recurrence!.between(day.addDays(1), day.addDays(7)).isNotEmpty
          : (scheduled != null &&
                  scheduled.isAfter(day) &&
                  !scheduled.isAfter(day.addDays(7))) ||
              (deadline != null &&
                  deadline.isAfter(day) &&
                  !deadline.isAfter(day.addDays(7))),
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<WorkspaceRecord>>(
      stream: _records,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(strings.text(
                'Could not open your workspace.', 'কর্মপরিসর খোলা যায়নি।')),
            TextButton(
                onPressed: () => setState(_watch),
                child: Text(strings.text('Try again', 'আবার চেষ্টা করুন'))),
          ]));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        try {
          return _content(context, snapshot.data!);
        } on FormatException {
          return Center(
              child: Text(strings.text(
                  'Some saved data needs recovery. Open Settings to export a backup.',
                  'কিছু তথ্য পুনরুদ্ধার করতে হবে। সেটিংস থেকে ব্যাকআপ নিন।')));
        }
      });

  Widget _content(BuildContext context, List<WorkspaceRecord> records) {
    final day = today;
    final tasks = records
        .where((r) => r.kind == RecordKind.task && !r.deleted)
        .map(ProductivityTask.fromRecord)
        .toList();
    final projects = records
        .where((r) => r.kind == RecordKind.project && !r.deleted)
        .map(ProductivityProject.fromRecord)
        .toList();
    final occurrences = {
      for (final record in records
          .where((r) => r.kind == RecordKind.taskOccurrence && !r.deleted))
        record.id: TaskOccurrence.fromRecord(record)
    };
    TaskStatus status(ProductivityTask task) => task.recurrence == null
        ? task.status
        : occurrences[TaskRepository.occurrenceId(task.id, day)]?.status ??
            TaskStatus.notStarted;
    final visible = records
        .where((r) => r.kind == RecordKind.task)
        .map((record) => (record, ProductivityTask.fromRecord(record)))
        .where((entry) =>
            _visible(entry.$2, status(entry.$2), entry.$1.deleted, day) &&
            (_projectId == null || entry.$2.projectId == _projectId) &&
            '${entry.$2.title} ${entry.$2.description} ${entry.$2.tags.join(' ')}'
                .toLowerCase()
                .contains(_query.toLowerCase()))
        .toList();
    visible.sort((a, b) {
      final priority = b.$2.priority.index.compareTo(a.$2.priority.index);
      if (priority != 0) return priority;
      if (a.$2.deadline != null || b.$2.deadline != null) {
        final deadline = (a.$2.deadline ?? DateTime.utc(9999))
            .compareTo(b.$2.deadline ?? DateTime.utc(9999));
        if (deadline != 0) return deadline;
      }
      final order = a.$2.order.compareTo(b.$2.order);
      return order == 0 ? a.$2.id.compareTo(b.$2.id) : order;
    });
    String viewLabel(TaskWorkspaceView view) => switch (view) {
          TaskWorkspaceView.inbox => strings.text('Inbox', 'ইনবক্স'),
          TaskWorkspaceView.today => strings.text('Today', 'আজ'),
          TaskWorkspaceView.upcoming =>
            strings.text('Next 7 days', 'আগামী ৭ দিন'),
          TaskWorkspaceView.all => strings.text('All tasks', 'সব কাজ'),
          TaskWorkspaceView.completed => strings.text('Completed', 'সম্পন্ন'),
          TaskWorkspaceView.trash => strings.text('Trash', 'ট্র্যাশ'),
        };
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _editor(tasks, projects),
          icon: const Icon(Icons.add),
          label: Text(strings.text('Add task', 'কাজ যোগ করুন'))),
      body: CustomScrollView(slivers: [
        SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            sliver: SliverToBoxAdapter(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(strings.text('Your tasks', 'আপনার কাজ'),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  MergeSemantics(
                      child: SearchBar(
                          elevation: const WidgetStatePropertyAll(0),
                          backgroundColor: WidgetStatePropertyAll(
                              Theme.of(context).colorScheme.surface),
                          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant))),
                          leading: const Icon(Icons.search),
                          hintText: strings.text(
                              'Search tasks and tags', 'কাজ ও ট্যাগ খুঁজুন'),
                          onChanged: (value) =>
                              setState(() => _query = value))),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final view in TaskWorkspaceView.values)
                      ChoiceChip(
                          label: Text(viewLabel(view)),
                          selected: _view == view,
                          onSelected: (_) => setState(() => _view = view))
                  ]),
                  const SizedBox(height: 12),
                  Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChoiceChip(
                            label: Text(
                                strings.text('All projects', 'সব প্রকল্প')),
                            selected: _projectId == null,
                            onSelected: (_) =>
                                setState(() => _projectId = null)),
                        for (final project
                            in projects.where((p) => !p.archived))
                          ChoiceChip(
                              label: Text(project.name),
                              selected: _projectId == project.id,
                              onSelected: (_) =>
                                  setState(() => _projectId = project.id)),
                        TextButton.icon(
                            onPressed: _project,
                            icon: const Icon(Icons.create_new_folder_outlined),
                            label: Text(strings.text('Project', 'প্রকল্প'))),
                      ]),
                  const SizedBox(height: 16),
                  Text(
                      '${viewLabel(_view)} · ${strings.number(visible.length)}',
                      style: Theme.of(context).textTheme.titleMedium),
                ]))),
        if (visible.isEmpty)
          SliverPadding(
              padding: const EdgeInsets.all(28),
              sliver: SliverToBoxAdapter(
                  child: Column(children: [
                const Icon(Icons.checklist_rounded, size: 48),
                const SizedBox(height: 12),
                Text(_query.isNotEmpty
                    ? strings.text('No matching tasks.', 'মিলে যাওয়া কাজ নেই।')
                    : strings.text('A clear space for your next step.',
                        'পরের পদক্ষেপের জন্য জায়গা তৈরি।')),
                const SizedBox(height: 8),
                Text(
                    strings.text(
                        'Add a task now. Organize it when you are ready.',
                        'এখন কাজ লিখে রাখুন। পরে সময় নিয়ে গুছিয়ে নিন।'),
                    textAlign: TextAlign.center),
              ]))),
        SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final (record, task) = visible[index];
                  final currentStatus = status(task);
                  final disabled = _pending.contains(task.id);
                  final canCheck = task.recurrence == null ||
                      task.recurrence!.between(day, day).isNotEmpty ||
                      occurrences.containsKey(
                          TaskRepository.occurrenceId(task.id, day));
                  Future<void> setStatus(TaskStatus value) => _run(
                      task.id,
                      () => task.recurrence == null
                          ? widget.repository.setStatus(task.id, value)
                          : widget.repository
                              .setOccurrenceStatus(task.id, day, value));
                  return Card(
                      child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    leading: record.deleted
                        ? const Icon(Icons.delete_outline)
                        : Checkbox(
                            value: currentStatus == TaskStatus.completed,
                            semanticLabel: strings.text(
                                'Complete ${task.title}',
                                '${task.title} সম্পন্ন করুন'),
                            onChanged: disabled || !canCheck
                                ? null
                                : (complete) => setStatus(complete == true
                                    ? TaskStatus.completed
                                    : TaskStatus.notStarted)),
                    title: Text(task.title,
                        style: TextStyle(
                            decoration: currentStatus == TaskStatus.completed
                                ? TextDecoration.lineThrough
                                : null)),
                    subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(spacing: 10, runSpacing: 4, children: [
                          Text(strings.status(currentStatus)),
                          if (task.priority != TaskPriority.none)
                            Text(strings.priority(task.priority)),
                          if (task.estimatedMinutes > 0)
                            Text(strings.text(
                                '${strings.number(task.estimatedMinutes)} min',
                                '${strings.number(task.estimatedMinutes)} মিনিট')),
                          if (task.recurrence != null)
                            Icon(Icons.repeat,
                                size: 16,
                                semanticLabel: strings.text(
                                    'Recurring task', 'পুনরাবৃত্ত কাজ')),
                          for (final tag in task.tags) Text('#$tag'),
                        ])),
                    onTap: record.deleted
                        ? null
                        : () => _editor(tasks, projects, task: task),
                    trailing: PopupMenuButton<String>(
                        enabled: !disabled,
                        tooltip: strings.text('Task actions', 'কাজের বিকল্প'),
                        onSelected: (action) async {
                          final messenger = ScaffoldMessenger.of(context);
                          if (action == 'restore') {
                            await _run(task.id,
                                () => widget.repository.restore(task.id));
                          } else if (action == 'trash') {
                            TaskTrashReceipt? receipt;
                            await _run(task.id, () async {
                              receipt = await widget.repository
                                  .trashWithReceipt(task.id);
                            });
                            if (mounted &&
                                messenger.mounted &&
                                receipt != null) {
                              messenger.showSnackBar(SnackBar(
                                  content: Text(strings.text(
                                      'Moved to trash, including subtasks.',
                                      'উপকাজসহ ট্র্যাশে রাখা হয়েছে।')),
                                  action: SnackBarAction(
                                      label:
                                          strings.text('Undo', 'ফিরিয়ে আনুন'),
                                      onPressed: () => _run(
                                          task.id,
                                          () => widget.repository
                                              .undoTrash(receipt!)))));
                            }
                          } else if (action == 'subtask') {
                            await _editor(tasks, projects, parentId: task.id);
                          } else if (action.startsWith('status:')) {
                            await setStatus(
                                TaskStatus.values.byName(action.substring(7)));
                          }
                        },
                        itemBuilder: (context) => record.deleted
                            ? [
                                PopupMenuItem(
                                    value: 'restore',
                                    child: Text(strings.text(
                                        'Restore', 'ফিরিয়ে আনুন')))
                              ]
                            : [
                                for (final value in TaskStatus.values)
                                  PopupMenuItem(
                                      value: 'status:${value.name}',
                                      enabled: canCheck,
                                      child: Text(strings.status(value))),
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                    value: 'subtask',
                                    child: Text(strings.text(
                                        'Add subtask', 'উপকাজ যোগ করুন'))),
                                PopupMenuItem(
                                    value: 'trash',
                                    child: Text(strings.text(
                                        'Move to trash', 'ট্র্যাশে রাখুন')))
                              ]),
                  ));
                })),
        const SliverToBoxAdapter(child: SizedBox(height: 112)),
      ]),
    );
  }
}

class _ProjectNameDialog extends StatefulWidget {
  const _ProjectNameDialog({required this.strings, required this.onCreate});
  final ExperienceStrings strings;
  final Future<void> Function(String) onCreate;
  @override
  State<_ProjectNameDialog> createState() => _ProjectNameDialogState();
}

class _ProjectNameDialogState extends State<_ProjectNameDialog> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(widget.strings.text('New project', 'নতুন প্রকল্প')),
        content: TextField(
            controller: _controller,
            enabled: !_saving,
            autofocus: true,
            maxLength: 200,
            buildCounter: (context,
                    {required currentLength,
                    required maxLength,
                    required isFocused}) =>
                Text(
                    '${widget.strings.number(currentLength)} / ${widget.strings.number(maxLength ?? 0)}',
                    style: Theme.of(context).textTheme.bodySmall),
            decoration: InputDecoration(
                errorText: _error,
                errorMaxLines: 4,
                labelText:
                    widget.strings.text('Project name', 'প্রকল্পের নাম'))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: Text(widget.strings.text('Cancel', 'বাতিল'))),
          FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final name = _controller.text.trim();
                      if (name.isEmpty) return;
                      setState(() {
                        _saving = true;
                        _error = null;
                      });
                      try {
                        await widget.onCreate(name);
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (_) {
                        if (mounted) {
                          setState(() =>
                              _error = widget.strings.taskError('save-failed'));
                        }
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: Text(_saving
                  ? widget.strings.text('Saving…', 'সংরক্ষণ হচ্ছে…')
                  : widget.strings.text('Create', 'তৈরি করুন')))
        ],
      ));
}
