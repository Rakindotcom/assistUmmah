import '../core/records.dart';
import 'calendar_day.dart';
import 'task.dart';
import 'stored_instant.dart';

/// An occurrence has its own completion; completing it never closes a series.
class TaskOccurrence {
  TaskOccurrence({
    required this.id,
    required this.workspaceId,
    required this.taskId,
    required this.day,
    this.status = TaskStatus.notStarted,
    this.completedAt,
    this.notes = '',
    this.postponements = 0,
    this.scheduledAt,
  }) {
    validateRecordId(id);
    validateRecordId(workspaceId);
    validateRecordId(taskId);
    if (postponements < 0 ||
        notes.length > 100000 ||
        (completedAt != null && status != TaskStatus.completed)) {
      throw const FormatException('Invalid task occurrence.');
    }
  }
  final String id, workspaceId, taskId, notes;
  final CalendarDay day;
  final TaskStatus status;
  final DateTime? completedAt, scheduledAt;
  final int postponements;

  Map<String, Object?> toFields() => {
        'workspaceId': workspaceId,
        'taskId': taskId,
        'day': day.toString(),
        'status': status.name,
        'completedAt': completedAt?.toUtc().toIso8601String(),
        'notes': notes,
        'postponements': postponements,
        'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
      };

  factory TaskOccurrence.fromRecord(WorkspaceRecord record) {
    if (record.kind != RecordKind.taskOccurrence) {
      throw const FormatException('Not a task occurrence.');
    }
    final fields = record.fields;
    DateTime? instant(String key) =>
        fields[key] == null ? null : parseStoredInstant(fields[key] as String);
    return TaskOccurrence(
        id: record.id,
        workspaceId: record.workspaceId,
        taskId: fields['taskId'] as String,
        day: CalendarDay.parse(fields['day'] as String),
        status: TaskStatus.values.byName(fields['status'] as String),
        completedAt: instant('completedAt'),
        scheduledAt: instant('scheduledAt'),
        notes: fields['notes'] as String? ?? '',
        postponements: fields['postponements'] as int? ?? 0);
  }
}
