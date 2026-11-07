import 'package:characters/characters.dart';

import '../core/records.dart';
import 'calendar_day.dart';
import 'recurrence.dart';
import 'stored_instant.dart';

enum TaskStatus { notStarted, inProgress, waiting, blocked, completed }

enum TaskPriority { none, low, normal, high, urgent }

class ProductivityTask {
  ProductivityTask(
      {required this.id,
      required this.workspaceId,
      required String title,
      this.description = '',
      this.status = TaskStatus.notStarted,
      this.priority = TaskPriority.normal,
      this.projectId,
      this.parentId,
      this.goalId,
      this.milestoneId,
      this.startDate,
      this.scheduledDay,
      this.scheduledAt,
      this.deadline,
      this.estimatedMinutes = 0,
      Iterable<String> tags = const [],
      Iterable<String> dependencies = const [],
      Iterable<DateTime> reminders = const [],
      this.recurrence,
      this.archived = false,
      this.inbox = true,
      this.order = 0,
      this.postponements = 0,
      this.completedAt})
      : title = title.trim(),
        tags = List.unmodifiable(tags.toSet()),
        dependencies = List.unmodifiable(dependencies.toSet()),
        reminders = List.unmodifiable(reminders) {
    validateRecordId(id);
    validateRecordId(workspaceId);
    if (this.title.isEmpty ||
        this.title.characters.length > 500 ||
        description.length > 100000 ||
        estimatedMinutes < 0 ||
        estimatedMinutes > 525600 ||
        postponements < 0 ||
        order < 0 ||
        this.tags.length > 50 ||
        this.tags.any((tag) => tag.trim().isEmpty || tag.length > 60) ||
        this.dependencies.length > 200 ||
        this.reminders.length > 20 ||
        (scheduledDay != null && scheduledAt != null) ||
        parentId == id ||
        this.dependencies.contains(id) ||
        (completedAt != null && status != TaskStatus.completed)) {
      throw const FormatException('Invalid task details.');
    }
    for (final reference in [
      projectId,
      parentId,
      goalId,
      milestoneId,
      ...this.dependencies
    ]) {
      if (reference != null) validateRecordId(reference);
    }
  }
  final String id, workspaceId, title, description;
  final TaskStatus status;
  final TaskPriority priority;
  final String? projectId, parentId, goalId, milestoneId;
  final CalendarDay? startDate, scheduledDay;
  final DateTime? scheduledAt, deadline, completedAt;
  final int estimatedMinutes, order, postponements;
  final List<String> tags, dependencies;
  final List<DateTime> reminders;
  final RecurrenceRule? recurrence;
  final bool archived, inbox;

  bool get scheduledPastDeadline =>
      scheduledAt != null &&
      deadline != null &&
      scheduledAt!.isAfter(deadline!);

  Map<String, Object?> toFields() => {
        'workspaceId': workspaceId,
        'title': title,
        'description': description,
        'status': status.name,
        'priority': priority.index,
        'projectId': projectId,
        'parentId': parentId,
        'goalId': goalId,
        'milestoneId': milestoneId,
        'startDate': startDate?.toString(),
        'scheduledDay': scheduledDay?.toString(),
        'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
        'deadline': deadline?.toUtc().toIso8601String(),
        'estimatedMinutes': estimatedMinutes,
        'tags': tags,
        'dependencies': dependencies,
        'reminders':
            reminders.map((time) => time.toUtc().toIso8601String()).toList(),
        'recurrence': recurrence?.toJson(),
        'archived': archived,
        'inbox': inbox,
        'order': order,
        'postponements': postponements,
        'completedAt': completedAt?.toUtc().toIso8601String(),
      };
  factory ProductivityTask.fromRecord(WorkspaceRecord record) {
    if (record.kind != RecordKind.task) {
      throw const FormatException('Not a task.');
    }
    return ProductivityTask.fromFields(
        id: record.id, workspaceId: record.workspaceId, fields: record.fields);
  }
  factory ProductivityTask.fromFields(
      {required String id,
      required String workspaceId,
      required Map<String, Object?> fields}) {
    final data = validatedFields(fields);
    DateTime? instant(String key) =>
        data[key] == null ? null : parseStoredInstant(data[key] as String);
    final priority = data['priority'] as int? ?? 2;
    if (priority < 0 || priority >= TaskPriority.values.length) {
      throw const FormatException('Invalid task priority.');
    }
    return ProductivityTask(
        id: id,
        workspaceId: workspaceId,
        title: data['title'] as String,
        description: data['description'] as String? ?? '',
        status:
            TaskStatus.values.byName(data['status'] as String? ?? 'notStarted'),
        priority: TaskPriority.values[priority],
        projectId: data['projectId'] as String?,
        parentId: data['parentId'] as String?,
        goalId: data['goalId'] as String?,
        milestoneId: data['milestoneId'] as String?,
        startDate: data['startDate'] == null
            ? null
            : CalendarDay.parse(data['startDate'] as String),
        scheduledDay: data['scheduledDay'] == null
            ? null
            : CalendarDay.parse(data['scheduledDay'] as String),
        scheduledAt: instant('scheduledAt'),
        deadline: instant('deadline'),
        estimatedMinutes: data['estimatedMinutes'] as int? ?? 0,
        tags: List<String>.from(data['tags'] as List? ?? []),
        dependencies: List<String>.from(data['dependencies'] as List? ?? []),
        reminders: (data['reminders'] as List? ?? [])
            .map((time) => parseStoredInstant(time as String)),
        recurrence: data['recurrence'] == null
            ? null
            : RecurrenceRule.fromJson(
                Map<String, dynamic>.from(data['recurrence'] as Map)),
        archived: data['archived'] == true,
        inbox: data['inbox'] != false,
        order: data['order'] as int? ?? 0,
        postponements: data['postponements'] as int? ?? 0,
        completedAt: instant('completedAt'));
  }
}
