import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/recurrence.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';
import 'package:ummah_assist/src/productivity/domain/task_occurrence.dart';
import 'package:ummah_assist/src/productivity/domain/task_reminder_plan.dart';

void main() {
  final now = DateTime.utc(2026, 11, 6, 0);
  final tomorrow = now.add(const Duration(days: 1));
  final options = ExperienceOptions(
      language: 'bn',
      timeZone: 'Asia/Dhaka',
      modules: [WorkspaceModule.personal, WorkspaceModule.work]);
  WorkspaceRecord record(
      RecordKind kind, String id, Map<String, Object?> fields,
      {bool deleted = false, String uid = 'owner'}) {
    final data = {...fields, '_deleted': deleted};
    return WorkspaceRecord(
        ownerId: uid,
        kind: kind,
        id: id,
        fields: data,
        clocks: {for (final key in data.keys) key: VersionStamp(1, 'device')},
        modifiedAtMillis: 0);
  }

  WorkspaceRecord task(String id,
          {String workspace = 'personal',
          bool deleted = false,
          bool archived = false,
          TaskStatus status = TaskStatus.notStarted,
          List<DateTime>? reminders,
          RecurrenceRule? recurrence}) =>
      record(
          RecordKind.task,
          id,
          ProductivityTask(
                  id: id,
                  workspaceId: workspace,
                  title: id,
                  archived: archived,
                  status: status,
                  reminders: reminders ?? [tomorrow],
                  recurrence: recurrence)
              .toFields(),
          deleted: deleted);
  TaskReminderPlan plan(Iterable<WorkspaceRecord> values) => planTaskReminders(
      uid: 'owner', records: values, options: options, now: now);

  test(
      'selects explicit future dates across enabled workspaces without duplicates',
      () {
    final result = plan([
      task('work', workspace: 'work'),
      task('past', reminders: [now.subtract(const Duration(seconds: 1)), now]),
      task('done', status: TaskStatus.completed),
      task('trashed', deleted: true),
      task('archived', archived: true),
      task('disabled', workspace: 'study'),
      task('personal', reminders: [
        tomorrow,
        tomorrow,
        tomorrow.subtract(const Duration(hours: 1))
      ]),
    ]);
    expect(result.totalCount, 3);
    expect(result.reminders.map((r) => r.taskId),
        ['personal', 'personal', 'work']);
    expect(result.reminders.first.time,
        tomorrow.subtract(const Duration(hours: 1)));
    expect(result.owner, taskReminderOwner('owner'));
  });

  test(
      'recurring reminder dates respect local days, exceptions and completions',
      () {
    final first = CalendarDay(2026, 11, 7), second = first.addDays(1);
    // UTC 23:30 on the sixth is the seventh in Dhaka.
    final firstTime = DateTime.utc(2026, 11, 6, 23, 30);
    final nextTime = firstTime.add(const Duration(days: 1));
    final series = task('series',
        recurrence:
            RecurrenceRule(start: first, frequency: RecurrenceFrequency.daily),
        reminders: [firstTime, nextTime]);
    final completed = TaskOccurrence(
        id: 'occurrence',
        workspaceId: 'personal',
        taskId: 'series',
        day: first,
        status: TaskStatus.completed);
    final result = plan([
      series,
      record(RecordKind.taskOccurrence, completed.id, completed.toFields())
    ]);
    expect(result.reminders.single.time, nextTime);
    expect(
        plan([
          task('excluded',
              recurrence: RecurrenceRule(
                  start: first,
                  frequency: RecurrenceFrequency.daily,
                  excludedDates: [second]),
              reminders: [nextTime])
        ]).totalCount,
        0);
    expect(
        plan([
          task('paused',
              recurrence: RecurrenceRule(
                  start: first,
                  frequency: RecurrenceFrequency.daily,
                  paused: true))
        ]).totalCount,
        0);
    // A stale tombstone is not a current completed occurrence.
    expect(
        plan([
          series,
          record(RecordKind.taskOccurrence, completed.id, completed.toFields(),
              deleted: true)
        ]).totalCount,
        2);
  });

  test('keeps a bounded nearest window while reporting all remaining reminders',
      () {
    final records = [
      for (var i = 0; i < 450; i++)
        task('task_$i', reminders: [tomorrow.add(Duration(minutes: i))])
    ];
    final first = plan(records.reversed), second = plan(records);
    expect(first.totalCount, 450);
    expect(first.reminders.length, taskAlertSlotCount);
    expect(first.reminders.first.taskId, 'task_0');
    expect(first.reminders.last.taskId, 'task_199');
    expect(first.fingerprint, second.fingerprint);
  });

  test('never mixes another account into a device plan', () {
    final foreign = record(
        RecordKind.task,
        'other',
        ProductivityTask(
            id: 'other',
            workspaceId: 'personal',
            title: 'Private',
            reminders: [tomorrow]).toFields(),
        uid: 'another-owner');
    expect(() => plan([foreign]), throwsStateError);
  });
}
