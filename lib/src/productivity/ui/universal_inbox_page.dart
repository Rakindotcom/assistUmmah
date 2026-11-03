import 'package:flutter/material.dart';

import '../core/records.dart';
import '../data/task_repository.dart';
import '../domain/experience_options.dart';
import '../domain/project.dart';
import '../domain/task.dart';
import 'experience_strings.dart';
import 'task_editor_page.dart';

/// One capture and review surface across every enabled non-Faith workspace.
class UniversalInboxPage extends StatefulWidget {
  const UniversalInboxPage({
    super.key,
    required this.repository,
    required this.options,
  });

  final TaskRepository repository;
  final ExperienceOptions options;

  @override
  State<UniversalInboxPage> createState() => _UniversalInboxPageState();
}

class _UniversalInboxPageState extends State<UniversalInboxPage> {
  late Stream<List<WorkspaceRecord>> _records;
  String _query = '';
  String? _filterWorkspace;
  String? _captureWorkspace;

  ExperienceStrings get strings => ExperienceStrings(widget.options.language);

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(UniversalInboxPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository.database != widget.repository.database) _watch();
  }

  void _watch() => _records = widget.repository.database.watch();

  Future<void> _edit({
    required String workspaceId,
    required List<ProductivityTask> tasks,
    required List<ProductivityProject> projects,
    ProductivityTask? task,
  }) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => ProductivityTaskEditorPage(
            repository: widget.repository,
            options: widget.options,
            workspaceId: workspaceId,
            task: task,
            tasks: tasks
                .where((value) => value.workspaceId == workspaceId)
                .toList(),
            projects: projects
                .where((value) => value.workspaceId == workspaceId)
                .toList())));
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<WorkspaceRecord>>(
      stream: _records,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(strings.text(
                'Could not open your Inbox.', 'ইনবক্স খোলা যায়নি।')),
            TextButton(
                onPressed: () => setState(_watch),
                child: Text(strings.text('Try again', 'আবার চেষ্টা করুন')))
          ]));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        try {
          return _content(snapshot.data!);
        } on FormatException {
          return Center(
              child: Text(strings.text(
                  'Some saved tasks need recovery. Open Settings to export a backup.',
                  'কিছু সংরক্ষিত কাজ পুনরুদ্ধার করতে হবে। সেটিংস থেকে ব্যাকআপ নিন।')));
        }
      });

  Widget _content(List<WorkspaceRecord> records) {
    final modules = WorkspaceModule.values
        .where((module) =>
            module != WorkspaceModule.faith &&
            widget.options.modules.contains(module))
        .toList(growable: false);
    final enabled = modules.map((module) => module.name).toSet();
    final tasks = records
        .where((record) => record.kind == RecordKind.task && !record.deleted)
        .map(ProductivityTask.fromRecord)
        .toList(growable: false);
    final projects = records
        .where((record) => record.kind == RecordKind.project && !record.deleted)
        .map(ProductivityProject.fromRecord)
        .toList(growable: false);
    final filterWorkspace =
        enabled.contains(_filterWorkspace) ? _filterWorkspace : null;
    final query = _query.trim().toLowerCase();
    final inbox = tasks
        .where((task) =>
            enabled.contains(task.workspaceId) &&
            task.inbox &&
            !task.archived &&
            task.status != TaskStatus.completed &&
            (filterWorkspace == null || task.workspaceId == filterWorkspace) &&
            (query.isEmpty ||
                '${task.title} ${task.description} ${task.tags.join(' ')}'
                    .toLowerCase()
                    .contains(query)))
        .toList(growable: false)
      ..sort((a, b) {
        final priority = b.priority.index.compareTo(a.priority.index);
        if (priority != 0) return priority;
        final order = a.order.compareTo(b.order);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
    final targetWorkspace = enabled.contains(_captureWorkspace)
        ? _captureWorkspace!
        : widget.options.activeWorkspace;
    final moduleByName = {for (final module in modules) module.name: module};

    return Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(
                workspaceId: targetWorkspace, tasks: tasks, projects: projects),
            icon: const Icon(Icons.add),
            label: Text(strings.text('Add task', 'কাজ যোগ করুন'))),
        body: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
            itemCount: inbox.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(strings.text('Inbox', 'ইনবক্স'),
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      Text(strings.text(
                          'Capture first. Organize when you are ready.',
                          'আগে লিখে রাখুন। পরে সময় নিয়ে গুছিয়ে নিন।')),
                      const SizedBox(height: 20),
                      TextField(
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                              labelText: strings.text(
                                  'Search Inbox', 'ইনবক্সে খুঁজুন'),
                              prefixIcon: const Icon(Icons.search))),
                      const SizedBox(height: 14),
                      SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                    label: Text(strings.text('All', 'সব')),
                                    selected: filterWorkspace == null,
                                    onSelected: (_) => setState(
                                        () => _filterWorkspace = null))),
                            for (final module in modules)
                              Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                      label: Text(strings.module(module)),
                                      selected: filterWorkspace == module.name,
                                      onSelected: (_) => setState(() =>
                                          _filterWorkspace = module.name))),
                          ])),
                      if (modules.length > 1) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                            key: ValueKey('capture-$targetWorkspace'),
                            initialValue: targetWorkspace,
                            isExpanded: true,
                            decoration: InputDecoration(
                                labelText: strings.text(
                                    'Save new tasks to', 'নতুন কাজ রাখুন')),
                            items: [
                              for (final module in modules)
                                DropdownMenuItem(
                                    value: module.name,
                                    child: Text(strings.module(module)))
                            ],
                            onChanged: (value) =>
                                setState(() => _captureWorkspace = value)),
                      ],
                      const SizedBox(height: 18),
                      Text(strings.text('${strings.number(inbox.length)} items',
                          '${strings.number(inbox.length)}টি কাজ')),
                      const SizedBox(height: 12),
                      if (inbox.isEmpty)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(query.isNotEmpty
                                    ? strings.text('No matching tasks.',
                                        'মিলে এমন কোনো কাজ নেই।')
                                    : strings.text(
                                        'Your Inbox is clear. Add a thought or task whenever it comes to mind.',
                                        'ইনবক্স খালি। মনে এলে যে কোনো ভাবনা বা কাজ লিখে রাখুন।')))),
                    ]);
              }
              final task = inbox[index - 1];
              final module = moduleByName[task.workspaceId]!;
              return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                      child: ListTile(
                          title: Text(task.title),
                          subtitle: Text(strings.module(module)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _edit(
                              workspaceId: task.workspaceId,
                              tasks: tasks,
                              projects: projects,
                              task: task))));
            }));
  }
}
