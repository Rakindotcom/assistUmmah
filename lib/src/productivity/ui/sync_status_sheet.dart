import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/records.dart';
import '../data/calendar_event_repository.dart';
import '../data/productivity_session.dart';
import '../data/task_repository.dart';
import '../data/workspace_backup.dart';
import '../domain/calendar_day.dart';
import '../domain/calendar_event.dart';
import '../domain/experience_options.dart';
import '../domain/planning_time_zone.dart';
import '../domain/project.dart';
import '../domain/task.dart';
import 'calendar_page.dart';
import 'experience_strings.dart';
import 'task_editor_page.dart';

typedef _AttentionItem = ({SyncOperation operation, WorkspaceRecord? record});
typedef _ReviewState = ({
  List<_AttentionItem> operations,
  List<FieldConflict> conflicts
});

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
  late Future<_ReviewState> _attention;
  StreamSubscription<SyncSnapshot>? _statusSubscription;
  bool _busy = false;
  ExperienceStrings get strings => ExperienceStrings(widget.options.language);

  @override
  void initState() {
    super.initState();
    _refresh();
    _statusSubscription = widget.session.database.watchSync().listen((_) {
      if (mounted) setState(_refresh);
    });
  }

  @override
  void dispose() {
    unawaited(_statusSubscription?.cancel());
    super.dispose();
  }

  void _refresh() {
    _attention = _loadAttention();
  }

  Future<_ReviewState> _loadAttention() async {
    final database = widget.session.database;
    final operations = await database.attention();
    final attention = await Future.wait(operations.map((operation) async => (
          operation: operation,
          record: await database.get(operation.kind, operation.recordId),
        )));
    return (operations: attention, conflicts: await database.fieldConflicts());
  }

  String _fieldName(String field) => switch (field) {
        'title' => strings.text('Title', 'শিরোনাম'),
        'description' => strings.text('Description', 'বিবরণ'),
        'status' => strings.text('Status', 'অবস্থা'),
        'priority' => strings.text('Priority', 'অগ্রাধিকার'),
        'scheduledAt' => strings.text('Scheduled time', 'নির্ধারিত সময়'),
        'interval' => strings.text('Event time', 'ইভেন্টের সময়'),
        'deadlineAt' => strings.text('Deadline', 'শেষ সময়'),
        'dependencies' => strings.text('Prerequisites', 'পূর্বশর্ত'),
        'parentId' => strings.text('Parent task', 'মূল কাজ'),
        '_deleted' => strings.text('Deletion', 'মুছে ফেলা'),
        _ => field,
      };

  String _value(Object? value) {
    if (value == null) return strings.text('Empty', 'খালি');
    if (value is Map &&
        value['start'] is String &&
        value['end'] is String &&
        value['timeZone'] is String) {
      try {
        final zone = value['timeZone'] as String;
        final start = PlanningTimeZone.inZone(
            DateTime.parse(value['start'] as String), zone);
        final end = PlanningTimeZone.inZone(
            DateTime.parse(value['end'] as String), zone);
        String label(DateTime local) =>
            '${strings.date(local)} ${strings.time(local, use24HourClock: widget.options.use24HourClock)} ${local.timeZoneName}';
        return '${label(start)} – ${label(end)}';
      } catch (_) {
        // Keep the raw value reviewable if an old or forged record is invalid.
      }
    }
    if (value is bool) {
      return value ? strings.text('Yes', 'হ্যাঁ') : strings.text('No', 'না');
    }
    return value is String ? value : jsonEncode(value);
  }

  Future<void> _reviewField(FieldConflict conflict) async {
    if (_busy) return;
    final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(strings.text(
                  'Review conflicting values', 'ভিন্ন তথ্য পর্যালোচনা করুন')),
              content: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fieldName(conflict.field),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Text(strings.text('On this device', 'এই ডিভাইসে')),
                      SelectableText(_value(conflict.localValue)),
                      const SizedBox(height: 12),
                      Text(strings.text('In the cloud', 'ক্লাউডে')),
                      SelectableText(_value(conflict.cloudValue)),
                    ]),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(strings.text('Cancel', 'বাতিল'))),
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, 'cloud'),
                    child:
                        Text(strings.text('Keep cloud', 'ক্লাউডেরটি রাখুন'))),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, 'mine'),
                    child: Text(strings.text('Use mine', 'আমারটি রাখুন'))),
              ],
            ));
    if (!mounted || choice == null) return;
    setState(() => _busy = true);
    try {
      if (choice == 'cloud') {
        await widget.session.database.keepCloudValue(conflict);
      } else {
        await widget.session.database.retryMyValue(conflict,
            validate: (candidate, records) {
          if (candidate.kind == RecordKind.task) {
            widget.repository.validateTaskConflictCandidate(candidate, records);
          } else {
            WorkspaceBackup.validateRecords([candidate]);
          }
        });
      }
      await widget.session.sync?.sync(force: true);
      if (mounted) setState(_refresh);
    } on TaskEditFailure catch (error) {
      _message(strings.taskError(error.code));
    } catch (_) {
      _message(strings.text(
          'These values changed or could not be applied. Review them again.',
          'তথ্য বদলে গেছে বা প্রয়োগ করা যায়নি। আবার পর্যালোচনা করুন।'));
      if (mounted) setState(_refresh);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    if (_busy) return;
    if (operation.kind == RecordKind.calendarEvent) {
      await _reviewEvent(operation);
      return;
    }
    if (operation.kind != RecordKind.task) return;
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

  Future<void> _reviewEvent(SyncOperation operation) async {
    final db = widget.session.database;
    final record = await db.get(RecordKind.calendarEvent, operation.recordId);
    if (!mounted) return;
    if (record == null) {
      _message(strings.text('This event is missing from local storage.',
          'এই ইভেন্টটি স্থানীয় সংরক্ষণে পাওয়া যায়নি।'));
      return;
    }
    if (!record.deleted) {
      CalendarEvent event;
      try {
        event = CalendarEvent.fromRecord(record);
      } catch (_) {
        _message(strings.text('Export a backup before repairing this event.',
            'ইভেন্টটি ঠিক করার আগে ব্যাকআপ নিন।'));
        return;
      }
      final day = CalendarDay.fromDate(
          PlanningTimeZone.inZone(event.start, widget.options.timeZone));
      final edited = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => CalendarEventEditorPage(
              repository: CalendarEventRepository(db),
              options: widget.options,
              day: day,
              event: event)));
      if (!mounted || edited != true) return;
    }
    final current = await db.get(RecordKind.calendarEvent, operation.recordId);
    if (!mounted || current == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(current.deleted
                  ? strings.text('Sync this event deletion?',
                      'ইভেন্ট মোছার তথ্য সিঙ্ক করবেন?')
                  : strings.text(
                      'Send reviewed event?', 'পর্যালোচিত ইভেন্ট পাঠাবেন?')),
              content: Text(current.deleted
                  ? strings.text(
                      'This event was deleted on this device. Its deletion will be sent again.',
                      'এই ডিভাইসে ইভেন্টটি মোছা হয়েছে। মোছার তথ্য আবার পাঠানো হবে।')
                  : strings.text(
                      'Your corrected event will be sent again. Changes to the same fields on another device may be replaced.',
                      'সংশোধিত ইভেন্ট আবার পাঠানো হবে। অন্য ডিভাইসে একই অংশ বদলে থাকলে তা প্রতিস্থাপিত হতে পারে।')),
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
      await db.resubmitCalendarEventFailure(operation.recordId);
      await widget.session.sync?.sync(force: true);
      if (mounted) setState(_refresh);
    } catch (_) {
      _message(strings.text(
          'Could not resubmit this event. Your edits are saved.',
          'ইভেন্টটি আবার পাঠানো যায়নি। আপনার পরিবর্তন সংরক্ষিত আছে।'));
      if (mounted) setState(_refresh);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              child: FutureBuilder<_ReviewState>(
                  future: _attention,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final review = snapshot.data!;
                    if (review.operations.isEmpty && review.conflicts.isEmpty) {
                      return Center(
                          child: Text(strings.text('No changes need review.',
                              'কোনো পরিবর্তন পর্যালোচনার অপেক্ষায় নেই।')));
                    }
                    return ListView.builder(
                        itemCount:
                            review.operations.length + review.conflicts.length,
                        itemBuilder: (context, index) {
                          if (index >= review.operations.length) {
                            final conflict = review
                                .conflicts[index - review.operations.length];
                            return Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              strings.text(
                                                  'Values differ between devices',
                                                  'ডিভাইসগুলোর তথ্য ভিন্ন'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium),
                                          Text(_fieldName(conflict.field)),
                                          Text(_value(conflict.localValue),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis),
                                          TextButton.icon(
                                              onPressed: _busy
                                                  ? null
                                                  : () =>
                                                      _reviewField(conflict),
                                              icon: const Icon(
                                                  Icons.compare_arrows),
                                              label: Text(strings.text(
                                                  'Review values',
                                                  'তথ্য পর্যালোচনা করুন'))),
                                        ])));
                          }
                          final item = review.operations[index];
                          final operation = item.operation;
                          return Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            operation.kind ==
                                                    RecordKind.calendarEvent
                                                ? strings.text(
                                                    'Calendar event needs review',
                                                    'ক্যালেন্ডার ইভেন্ট পর্যালোচনা দরকার')
                                                : strings.text(
                                                    'Task needs review',
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
                                        if (operation.kind == RecordKind.task ||
                                            operation.kind ==
                                                RecordKind.calendarEvent)
                                          TextButton.icon(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _review(operation),
                                              icon: const Icon(
                                                  Icons.edit_outlined),
                                              label: Text(operation.kind ==
                                                      RecordKind.calendarEvent
                                                  ? strings.text('Review event',
                                                      'ইভেন্ট পর্যালোচনা করুন')
                                                  : strings.text('Review task',
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
