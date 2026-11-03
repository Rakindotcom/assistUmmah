import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/records.dart';
import '../domain/calendar_day.dart';
import '../domain/project.dart';
import '../domain/task.dart';
import '../domain/task_graph.dart';
import '../domain/task_occurrence.dart';
import 'productivity_database.dart';

class TaskEditFailure implements Exception {
  const TaskEditFailure(this.code);
  final String code;
  @override
  String toString() => 'TaskEditFailure($code)';
}

class TaskTrashReceipt {
  TaskTrashReceipt._(this.ownerId, Map<String, VersionStamp> deletedClocks)
      : deletedClocks = Map.unmodifiable(deletedClocks);
  final String ownerId;
  final Map<String, VersionStamp> deletedClocks;
}

/// All read/validate/write commands run inside the account database transaction.
/// UI forms send only fields actually edited, not stale full-object snapshots.
class TaskRepository {
  TaskRepository(this.database, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final ProductivityDatabase database;
  final DateTime Function() _clock;
  static const _kinds = {
    RecordKind.task,
    RecordKind.taskOccurrence,
    RecordKind.project,
    RecordKind.goal,
    RecordKind.milestone,
  };

  Stream<List<ProductivityTask>> watchTasks(String workspaceId,
          {bool trash = false}) =>
      database
          .watch(
              kind: RecordKind.task,
              workspaceId: workspaceId,
              includeDeleted: trash)
          .map((records) => records
              .where((record) => record.deleted == trash)
              .map(ProductivityTask.fromRecord)
              .toList(growable: false));

  Stream<List<ProductivityProject>> watchProjects(String workspaceId) =>
      database.watch(kind: RecordKind.project, workspaceId: workspaceId).map(
          (records) => records
              .map(ProductivityProject.fromRecord)
              .toList(growable: false));

  /// The caller presents the current local task for review before invoking
  /// this. It replaces only rejected, unsent task fields with a fresh clock.
  Future<void> resubmitGraphConflict(String taskId) async {
    await database.resubmitTaskGraphConflict(taskId,
        validate: (record, records) {
      final task = ProductivityTask.fromRecord(record);
      if (!record.deleted) {
        _validateTask(task, records);
      } else {
        try {
          TaskGraph(records
              .where((value) => value.kind == RecordKind.task && !value.deleted)
              .map((value) => TaskGraphNode.fromTask(
                  ProductivityTask.fromRecord(value)))).validate();
        } on TaskGraphConflict catch (error) {
          throw TaskEditFailure(error.code);
        }
      }
    });
  }

  /// Reuse task invariants when a user chooses a previously rejected value.
  /// This runs inside the database's conflict-resolution transaction.
  void validateTaskConflictCandidate(
      WorkspaceRecord candidate, List<WorkspaceRecord> records) {
    if (candidate.kind != RecordKind.task) {
      throw const TaskEditFailure('invalid-field');
    }
    final task = ProductivityTask.fromRecord(candidate);
    if (!candidate.deleted) {
      _validateTask(task, [
        for (final record in records)
          if (record.key != candidate.key) record,
        candidate,
      ]);
      return;
    }
    if (records.any((record) =>
        record.kind == RecordKind.task &&
        !record.deleted &&
        record.id != candidate.id &&
        record.fields['parentId'] == candidate.id)) {
      throw const TaskEditFailure('children-open');
    }
    try {
      TaskGraph([
        for (final record in records)
          if (record.kind == RecordKind.task &&
              record.id != candidate.id &&
              !record.deleted)
            TaskGraphNode.fromTask(ProductivityTask.fromRecord(record)),
      ]).validate();
    } on TaskGraphConflict catch (error) {
      throw TaskEditFailure(error.code);
    }
  }

  Future<ProductivityTask> createTask(ProductivityTask task) async {
    ProductivityTask? existing;
    final result = await database.changeRecords(
        kinds: _kinds,
        plan: (records) {
          final previous = _find(records, RecordKind.task, task.id);
          if (previous != null) {
            if (!previous.deleted &&
                _different(previous.fields, task.toFields()).isEmpty) {
              existing = ProductivityTask.fromRecord(previous);
              return [];
            }
            throw const TaskEditFailure('already-exists');
          }
          _validateTask(task, records);
          return [
            RecordMutation(
                kind: RecordKind.task,
                id: task.id,
                workspaceId: task.workspaceId,
                patch: task.toFields()),
          ];
        });
    return existing ?? ProductivityTask.fromRecord(result.single);
  }

  Future<ProductivityProject> createProject(ProductivityProject project) async {
    ProductivityProject? existing;
    final result = await database.changeRecords(
        kinds: _kinds,
        plan: (records) {
          final previous = _find(records, RecordKind.project, project.id);
          if (previous != null) {
            if (!previous.deleted &&
                _different(previous.fields, project.toFields()).isEmpty) {
              existing = ProductivityProject.fromRecord(previous);
              return [];
            }
            throw const TaskEditFailure('already-exists');
          }
          return [
            RecordMutation(
                kind: RecordKind.project,
                id: project.id,
                workspaceId: project.workspaceId,
                patch: project.toFields()),
          ];
        });
    return existing ?? ProductivityProject.fromRecord(result.single);
  }

  Future<ProductivityTask> editTask(
      String id, Map<String, Object?> patch) async {
    ProductivityTask? unchanged;
    final result = await database.changeRecords(
        kinds: _kinds,
        plan: (records) {
          final previous = _require(records, RecordKind.task, id);
          final before = ProductivityTask.fromRecord(previous);
          final allowed = before.toFields().keys.toSet()
            ..removeAll(
                ['workspaceId', 'status', 'completedAt', 'postponements']);
          if (patch.keys.any((key) => !allowed.contains(key))) {
            throw const TaskEditFailure('invalid-field');
          }
          final updated = _taskWith(previous, patch);
          _validateTask(updated, records);
          final changes = _different(previous.fields, patch);
          if (changes.isEmpty) {
            unchanged = before;
            return [];
          }
          return [_mutation(previous, changes)];
        });
    return unchanged ?? ProductivityTask.fromRecord(result.single);
  }

  Future<void> setStatus(String id, TaskStatus status) async {
    final now = _clock().toUtc().toIso8601String();
    await database.changeRecords(
        kinds: _kinds,
        plan: (records) {
          final previous = _require(records, RecordKind.task, id);
          final task = ProductivityTask.fromRecord(previous);
          if (task.recurrence != null && status == TaskStatus.completed) {
            throw const TaskEditFailure('choose-occurrence');
          }
          if (task.status == status) return [];
          if (status != TaskStatus.completed &&
              task.parentId != null &&
              _require(records, RecordKind.task, task.parentId!)
                      .fields['status'] ==
                  TaskStatus.completed.name) {
            throw const TaskEditFailure('parent-completed');
          }
          if (status == TaskStatus.completed) _assertUnblocked(task, records);
          return [
            _mutation(previous, {
              'status': status.name,
              'completedAt': status == TaskStatus.completed ? now : null,
            })
          ];
        });
  }

  Future<void> postpone(String id, DateTime scheduledAt) async {
    await database.changeRecords(
        kinds: _kinds,
        plan: (records) {
          final previous = _require(records, RecordKind.task, id);
          final task = ProductivityTask.fromRecord(previous);
          if (task.status == TaskStatus.completed || task.recurrence != null) {
            throw const TaskEditFailure('choose-open-task');
          }
          return [
            _mutation(previous, {
              'scheduledAt': scheduledAt.toUtc().toIso8601String(),
              'scheduledDay': null,
              'postponements': task.postponements + 1,
              'inbox': false,
            })
          ];
        });
  }

  /// Parent and every live descendant move to trash in the same commit. Linked
  /// dependent tasks stay visible and cannot complete until resolved/restored.
  Future<void> trash(String id) async {
    await trashWithReceipt(id);
  }

  Future<TaskTrashReceipt> trashWithReceipt(String id) async {
    final deleted = await database.changeRecords(
        kinds: _kinds,
        plan: (records) {
          final parent = _require(records, RecordKind.task, id);
          final descendants = <String>{id};
          final tasks = records.where((record) =>
              record.kind == RecordKind.task &&
              !record.deleted &&
              record.workspaceId == parent.workspaceId);
          var added = true;
          while (added) {
            added = false;
            for (final task in tasks) {
              if (descendants.contains(task.fields['parentId']) &&
                  descendants.add(task.id)) {
                added = true;
              }
            }
          }
          return [
            for (final record in tasks)
              if (descendants.contains(record.id))
                RecordMutation(
                    kind: record.kind,
                    id: record.id,
                    workspaceId: record.workspaceId,
                    patch: const {},
                    deleted: true),
          ];
        });
    return TaskTrashReceipt._(database.uid, {
      for (final record in deleted) record.id: record.clocks['_deleted']!,
    });
  }

  /// Undo restores exactly this deletion, including descendants. A later delete
  /// on another device has a different clock and is never undone accidentally.
  Future<void> undoTrash(TaskTrashReceipt receipt) async {
    if (receipt.ownerId != database.uid) {
      throw const TaskEditFailure('different-account');
    }
    await database.changeRecords(
        kinds: _kinds,
        plan: (records) {
          final restoring = records
              .where((record) =>
                  record.kind == RecordKind.task &&
                  record.deleted &&
                  receipt.deletedClocks[record.id] == record.clocks['_deleted'])
              .toList();
          final ids = restoring.map((record) => record.id).toSet();
          final after = records.map((record) {
            if (record.kind != RecordKind.task || !ids.contains(record.id)) {
              return record;
            }
            return WorkspaceRecord(
                ownerId: record.ownerId,
                kind: record.kind,
                id: record.id,
                fields: {...record.fields, '_deleted': false},
                clocks: record.clocks,
                modifiedAtMillis: record.modifiedAtMillis,
                revision: record.revision);
          }).toList(growable: false);
          for (final record in restoring) {
            _validateTask(ProductivityTask.fromRecord(record), after);
          }
          return [
            for (final record in restoring)
              RecordMutation(
                  kind: record.kind,
                  id: record.id,
                  workspaceId: record.workspaceId,
                  patch: const {},
                  deleted: false)
          ];
        });
  }

  Future<void> restore(String id) async {
    await database.changeRecords(
        kinds: _kinds,
        plan: (records) {
          final record = _find(records, RecordKind.task, id);
          if (record == null) throw const TaskEditFailure('not-found');
          if (!record.deleted) return [];
          _validateTask(ProductivityTask.fromRecord(record), records);
          return [
            RecordMutation(
                kind: record.kind,
                id: id,
                workspaceId: record.workspaceId,
                patch: const {},
                deleted: false)
          ];
        });
  }

  static String occurrenceId(String taskId, CalendarDay day) =>
      sha256.convert(utf8.encode('task:$taskId:${day.toString()}')).toString();

  /// Missing occurrences are virtual. Viewing a date does not enqueue writes.
  Future<List<TaskOccurrence>> occurrences(
      String workspaceId, CalendarDay from, CalendarDay to) async {
    if (to.isBefore(from) || to.difference(from) > 366) {
      throw ArgumentError('Choose at most one year.');
    }
    final records = await database.list(workspaceId: workspaceId);
    final stored = {
      for (final record
          in records.where((r) => r.kind == RecordKind.taskOccurrence))
        record.id: TaskOccurrence.fromRecord(record)
    };
    final result = <TaskOccurrence>[];
    for (final record in records.where((r) => r.kind == RecordKind.task)) {
      final task = ProductivityTask.fromRecord(record);
      if (task.archived || task.recurrence == null) continue;
      final scheduled = task.recurrence!.between(from, to).toSet();
      // Keep previous check-ins visible even if a series is later paused or edited.
      scheduled.addAll(stored.values
          .where((o) =>
              o.taskId == task.id &&
              !o.day.isBefore(from) &&
              !o.day.isAfter(to))
          .map((o) => o.day));
      for (final day in scheduled) {
        final id = occurrenceId(task.id, day);
        result.add(stored[id] ??
            TaskOccurrence(
                id: id, workspaceId: workspaceId, taskId: task.id, day: day));
      }
    }
    result.sort((a, b) {
      final day = a.day.compareTo(b.day);
      return day != 0 ? day : a.id.compareTo(b.id);
    });
    return List.unmodifiable(result);
  }

  Future<void> setOccurrenceStatus(
      String taskId, CalendarDay day, TaskStatus status) async {
    final now = _clock().toUtc();
    await database.changeRecords(
        kinds: _kinds,
        plan: (records) {
          final task = ProductivityTask.fromRecord(
              _require(records, RecordKind.task, taskId));
          final id = occurrenceId(taskId, day);
          final previous = _find(records, RecordKind.taskOccurrence, id);
          if (previous?.deleted == true) {
            throw const TaskEditFailure('in-trash');
          }
          if (task.recurrence == null ||
              (previous == null &&
                  task.recurrence!.between(day, day).isEmpty)) {
            throw const TaskEditFailure('not-scheduled');
          }
          if (status == TaskStatus.completed) {
            _assertUnblocked(task, records, day: day);
          }
          if (previous?.fields['status'] == status.name) return [];
          final fields = previous == null
              ? TaskOccurrence(
                      id: id,
                      workspaceId: task.workspaceId,
                      taskId: taskId,
                      day: day,
                      status: status,
                      completedAt: status == TaskStatus.completed ? now : null)
                  .toFields()
              : <String, Object?>{
                  'status': status.name,
                  'completedAt': status == TaskStatus.completed
                      ? now.toIso8601String()
                      : null
                };
          return [
            RecordMutation(
                kind: RecordKind.taskOccurrence,
                id: id,
                workspaceId: task.workspaceId,
                patch: fields)
          ];
        });
  }

  void _validateTask(ProductivityTask task, List<WorkspaceRecord> records) {
    void reference(RecordKind kind, String? id) {
      if (id == null) return;
      final record = _require(records, kind, id);
      if (record.workspaceId != task.workspaceId) {
        throw const TaskEditFailure('different-workspace');
      }
    }

    reference(RecordKind.project, task.projectId);
    reference(RecordKind.goal, task.goalId);
    reference(RecordKind.milestone, task.milestoneId);
    reference(RecordKind.task, task.parentId);
    if (task.parentId != null &&
        task.status != TaskStatus.completed &&
        _require(records, RecordKind.task, task.parentId!).fields['status'] ==
            TaskStatus.completed.name) {
      throw const TaskEditFailure('parent-completed');
    }
    for (final id in task.dependencies) {
      reference(RecordKind.task, id);
    }
    final tasks = <String, ProductivityTask>{
      for (final record in records.where((r) =>
          r.kind == RecordKind.task &&
          !r.deleted &&
          r.workspaceId == task.workspaceId))
        record.id: ProductivityTask.fromRecord(record),
      task.id: task,
    };
    try {
      TaskGraph(tasks.values.map((value) => TaskGraphNode.fromTask(value)))
          .validate();
    } on TaskGraphConflict catch (error) {
      throw TaskEditFailure(error.code);
    }
    if (task.status == TaskStatus.completed) _assertUnblocked(task, records);
  }

  void _assertUnblocked(ProductivityTask task, List<WorkspaceRecord> records,
      {CalendarDay? day}) {
    for (final id in task.dependencies) {
      final dependency =
          ProductivityTask.fromRecord(_require(records, RecordKind.task, id));
      var complete = dependency.status == TaskStatus.completed;
      if (dependency.recurrence != null && day != null) {
        complete =
            _find(records, RecordKind.taskOccurrence, occurrenceId(id, day))
                    ?.fields['status'] ==
                TaskStatus.completed.name;
      }
      if (!complete) throw const TaskEditFailure('dependencies-open');
    }
    for (final child in records.where((r) =>
        r.kind == RecordKind.task &&
        !r.deleted &&
        r.fields['parentId'] == task.id)) {
      if (child.fields['status'] != TaskStatus.completed.name) {
        throw const TaskEditFailure('subtasks-open');
      }
    }
  }

  static WorkspaceRecord? _find(
      List<WorkspaceRecord> records, RecordKind kind, String id) {
    for (final record in records) {
      if (record.kind == kind && record.id == id) return record;
    }
    return null;
  }

  static WorkspaceRecord _require(
      List<WorkspaceRecord> records, RecordKind kind, String id) {
    final record = _find(records, kind, id);
    if (record == null) throw const TaskEditFailure('not-found');
    if (record.deleted) throw const TaskEditFailure('in-trash');
    return record;
  }

  static RecordMutation _mutation(
          WorkspaceRecord previous, Map<String, Object?> patch) =>
      RecordMutation(
          kind: previous.kind,
          id: previous.id,
          workspaceId: previous.workspaceId,
          patch: patch);

  static Map<String, Object?> _different(
          Map<String, Object?> before, Map<String, Object?> patch) =>
      {
        for (final entry in patch.entries)
          if (canonicalJson(before[entry.key]) != canonicalJson(entry.value))
            entry.key: entry.value
      };
  static ProductivityTask _taskWith(
      WorkspaceRecord before, Map<String, Object?> patch) {
    final fields = {...before.fields, ...validatedFields(patch)};
    return ProductivityTask.fromRecord(WorkspaceRecord(
        ownerId: before.ownerId,
        kind: before.kind,
        id: before.id,
        fields: fields,
        clocks: {
          for (final key in fields.keys) key: before.clocks.values.first
        },
        modifiedAtMillis: before.modifiedAtMillis));
  }
}
