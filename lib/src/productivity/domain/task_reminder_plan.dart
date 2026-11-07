import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/records.dart';
import 'calendar_day.dart';
import 'experience_options.dart';
import 'planning_time_zone.dart';
import 'task.dart';
import 'task_occurrence.dart';

// This namespace is disjoint from the legacy daily and prayer notifications.
// iOS shares 64 pending slots across all features. The transport allocates the
// remaining slots dynamically; Android is bounded below vendor alarm limits.
const taskAlertIdBase = 3000;
const taskAlertSlotCount = 200;
const taskAlertRenewalId = taskAlertIdBase + taskAlertSlotCount - 1;

String taskReminderOwner(String uid) =>
    sha256.convert(utf8.encode(uid)).toString();

class PlannedTaskReminder {
  const PlannedTaskReminder(
      {required this.taskId,
      required this.workspaceId,
      required this.title,
      required this.time});
  final String taskId, workspaceId, title;
  final DateTime time;

  Map<String, Object?> toJson() => {
        'taskId': taskId,
        'workspaceId': workspaceId,
        'title': title,
        'time': time.toUtc().toIso8601String(),
      };
}

class TaskReminderPlan {
  TaskReminderPlan(
      {required this.owner,
      required this.language,
      required Iterable<PlannedTaskReminder> reminders,
      required this.totalCount})
      : reminders = List.unmodifiable(reminders) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(owner) ||
        !const ['bn', 'en'].contains(language) ||
        totalCount < this.reminders.length ||
        this.reminders.length > taskAlertSlotCount) {
      throw const FormatException('Invalid task notification plan.');
    }
  }
  final String owner, language;
  final List<PlannedTaskReminder> reminders;
  final int totalCount;
  String get fingerprint => canonicalJson({
        'owner': owner,
        'language': language,
        'reminders': reminders.map((value) => value.toJson()).toList(),
        'totalCount': totalCount,
      });
}

/// Reminder timestamps are explicit one-off instants. On a recurring task,
/// each timestamp targets the occurrence on its date in the workspace zone;
/// viewing a date never invents a reminder or writes an occurrence.
TaskReminderPlan planTaskReminders(
    {required String uid,
    required Iterable<WorkspaceRecord> records,
    required ExperienceOptions options,
    required DateTime now}) {
  final occurrences = <String, TaskOccurrence>{};
  for (final record in records) {
    if (record.ownerId != uid) throw StateError('Wrong reminder account.');
    if (!record.deleted && record.kind == RecordKind.taskOccurrence) {
      final occurrence = TaskOccurrence.fromRecord(record);
      occurrences[
              '${occurrence.workspaceId}/${occurrence.taskId}/${occurrence.day}'] =
          occurrence;
    }
  }
  int compare(PlannedTaskReminder a, PlannedTaskReminder b) {
    var result = a.time.compareTo(b.time);
    if (result == 0) result = a.workspaceId.compareTo(b.workspaceId);
    if (result == 0) result = a.taskId.compareTo(b.taskId);
    return result;
  }

  // Count every eligible reminder while retaining only the nearest transport
  // window. A large backlog keeps at most 200 candidates in memory here.
  final nearest = SplayTreeSet<PlannedTaskReminder>(compare);
  var total = 0;
  final enabled = options.modules
      .where((module) => module != WorkspaceModule.faith)
      .map((module) => module.name)
      .toSet();
  for (final record in records) {
    if (record.deleted || record.kind != RecordKind.task) continue;
    final task = ProductivityTask.fromRecord(record);
    if (!enabled.contains(task.workspaceId) ||
        task.archived ||
        task.status == TaskStatus.completed) {
      continue;
    }
    for (final time in task.reminders.map((value) => value.toUtc()).toSet()) {
      if (!time.isAfter(now)) continue;
      if (task.recurrence != null) {
        final day = CalendarDay.fromDate(
            PlanningTimeZone.inZone(time, options.timeZone));
        if (task.recurrence!.between(day, day).isEmpty ||
            occurrences['${task.workspaceId}/${task.id}/$day']?.status ==
                TaskStatus.completed) {
          continue;
        }
      }
      total++;
      nearest.add(PlannedTaskReminder(
          taskId: task.id,
          workspaceId: task.workspaceId,
          title: task.title,
          time: time));
      if (nearest.length > taskAlertSlotCount) nearest.remove(nearest.last);
    }
  }
  return TaskReminderPlan(
      owner: taskReminderOwner(uid),
      language: options.language,
      reminders: nearest,
      totalCount: total);
}
