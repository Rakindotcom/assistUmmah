import 'package:flutter/material.dart';

import '../core/records.dart';
import '../data/productivity_session.dart';
import '../data/task_repository.dart';
import '../domain/experience_options.dart';
import '../domain/project.dart';
import '../domain/task.dart';
import 'experience_strings.dart';
import 'task_editor_page.dart';

typedef _AttentionItem = ({SyncOperation operation, WorkspaceRecord? record});

class ProductivitySyncStatusSheet extends StatefulWidget {
  const ProductivitySyncStatusSheet({
    super.key,
    required this.session,
    required this.repository,
    required this.options,
  });

  final ProductivitySession session;
  final TaskRepository repository;
  final ExperienceOptions options;

  @override
  State<ProductivitySyncStatusSheet> createState() =>
      _ProductivitySyncStatusSheetState();
}

class _ProductivitySyncStatusSheetState
    extends State<ProductivitySyncStatusSheet> {
  late Future<List<_AttentionItem>> _attention;
  bool _busy = false;
  ExperienceStrings get strings => ExperienceStrings(widget.options.language);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _attention = _loadAttention();
  }

  Future<List<_AttentionItem>> _loadAttention() async {
    final database = widget.session.database;
    final operations = await database.attention();
    return Future.wait(operations.map((operation) async => (
          operation: operation,
          record: await database.get(operation.kind, operation.recordId),
        )));
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 5)));
  }

  Future<void> _sync() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.session.sync?.sync(force: true);
      if (mounted) setState(_refresh);
    } catch (_) {
      _message(strings.text('Sync could not finish. Your changes are saved.',
          'সিঙ্ক শেষ হয়নি। আপনার পরিবর্তন সংরক্ষিত আছে।'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(SyncOperation operation) async {
    if (_busy || operation.kind != RecordKind.task) return;
    final db = widget.session.database;
    final record = await db.get(RecordKind.task, operation.recordId);
    if (!mounted) return;
    if (record == null) {
      _message(strings.text('This task is missing from local storage.',
          'এই কাজটি স্থানীয় সংরক্ষণে পাওয়া যায়নি।'));
      return;
    }
    if (record.deleted) {
      await _confirmAndResubmit(record.id, deleted: true);
      return;
    }
    final task = ProductivityTask.fromRecord(record);
    final tasks =
        (await db.list(kind: RecordKind.task, workspaceId: task.workspaceId))
            .map(ProductivityTask.fromRecord)
            .toList(growable: false);
    final projects =
        (await db.list(kind: RecordKind.project, workspaceId: task.workspaceId))
            .map(ProductivityProject.fromRecord)
            .toList(growable: false);
    if (!mounted) return;
    final edited = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => ProductivityTaskEditorPage(
            repository: widget.repository,
            workspaceId: task.workspaceId,
            options: widget.options,
            task: task,
            tasks: tasks,
            projects: projects)));
    if (!mounted || edited != true) return;
    await _confirmAndResubmit(task.id);
  }

  Future<void> _confirmAndResubmit(String taskId,
      {bool deleted = false}) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(deleted
                  ? strings.text(
                      'Sync this deletion?', 'মুছে ফেলা কাজটি সিঙ্ক করবেন?')
                  : strings.text(
                      'Send corrected task?', 'সংশোধিত কাজ পাঠাবেন?')),
              content: Text(deleted
                  ? strings.text(
                      'This task is in Trash on this device. Its deletion will be sent again.',
                      'এই ডিভাইসে কাজটি ট্র্যাশে আছে। মুছে ফেলার তথ্য আবার পাঠানো হবে।')
                  : strings.text(
                      'The changed fields on this device will be sent again. If the same fields changed elsewhere, your reviewed values may replace them.',
                      'এই ডিভাইসে পরিবর্তিত অংশগুলো আবার পাঠানো হবে। অন্য ডিভাইসে একই অংশ বদলে থাকলে আপনার পর্যালোচিত তথ্য সেগুলোর জায়গায় যেতে পারে।')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(strings.text('Cancel', 'বাতিল'))),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(strings.text('Send', 'পাঠান'))),
              ],
            ));
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.repository.resubmitGraphConflict(taskId);
      await widget.session.sync?.sync(force: true);
      if (mounted) setState(_refresh);
    } on TaskEditFailure catch (error) {
      _message(strings.taskError(error.code));
    } catch (_) {
      _message(strings.text(
          'Could not resubmit this task. Your edits are saved.',
          'কাজটি আবার পাঠানো যায়নি। আপনার পরিবর্তন সংরক্ষিত আছে।'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(strings.text('Sync status', 'সিঙ্কের অবস্থা'),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            StreamBuilder<SyncSnapshot>(
                stream: widget.session.database.watchSync(),
                builder: (context, snapshot) {
                  final status = snapshot.data;
                  if (status == null) return const LinearProgressIndicator();
                  return Text(strings.text(
                      '${strings.number(status.pending)} changes waiting · ${strings.number(status.needsAttention)} need review',
                      '${strings.number(status.pending)}টি পরিবর্তন অপেক্ষায় · ${strings.number(status.needsAttention)}টি পর্যালোচনা দরকার'));
                }),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _busy ? null : _sync,
                icon: const Icon(Icons.sync),
                label: Text(strings.text('Sync now', 'এখন সিঙ্ক করুন'))),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<_AttentionItem>>(
                  future: _attention,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final operations = snapshot.data!;
                    if (operations.isEmpty) {
                      return Center(
                          child: Text(strings.text('No changes need review.',
                              'কোনো পরিবর্তন পর্যালোচনার অপেক্ষায় নেই।')));
                    }
                    return ListView.builder(
                        itemCount: operations.length,
                        itemBuilder: (context, index) {
                          final item = operations[index];
                          final operation = item.operation;
                          return Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            strings.text('Task needs review',
                                                'কাজটি পর্যালোচনা দরকার'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium),
                                        Text(item.record?.fields['title']
                                                as String? ??
                                            operation.recordId),
                                        const SizedBox(height: 4),
                                        Text(strings.taskError(
                                            operation.errorCode ??
                                                'save-failed')),
                                        const SizedBox(height: 8),
                                        TextButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : () => _review(operation),
                                            icon:
                                                const Icon(Icons.edit_outlined),
                                            label: Text(strings.text(
                                                'Review task',
                                                'কাজ পর্যালোচনা করুন'))),
                                      ])));
                        });
                  }),
            ),
          ]),
        ),
      ),
    );
  }
}
