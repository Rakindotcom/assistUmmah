import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:ummah_assist/src/prayer_times_service.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/recurrence.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';

void main() {
  CalendarDay day(String value) => CalendarDay.parse(value);
  List<String> dates(RecurrenceRule rule, String from, String to) =>
      rule.between(day(from), day(to)).map((date) => date.toString()).toList();

  test('civil dates reject normalization and count dates rather than DST hours',
      () {
    expect(() => day('2026-02-30'), throwsFormatException);
    expect(() => day('2026-2-3'), throwsFormatException);
    final zone = PrayerTimeService.location('America/New_York');
    final before = tz.TZDateTime(zone, 2026, 3, 7);
    final after = tz.TZDateTime(zone, 2026, 3, 9);
    expect(after.difference(before).inHours, 47);
    expect(CalendarDay.fromDate(after).difference(CalendarDay.fromDate(before)),
        2);
    final rule = RecurrenceRule(
        start: CalendarDay.fromDate(before),
        frequency: RecurrenceFrequency.daily);
    expect(dates(rule, '2026-03-07', '2026-03-10'),
        ['2026-03-07', '2026-03-08', '2026-03-09', '2026-03-10']);
  });

  test(
      'weekly intervals anchor to a calendar week, including a partial first week',
      () {
    final rule = RecurrenceRule(
        start: day('2026-10-28'),
        frequency: RecurrenceFrequency.weekly,
        interval: 2,
        weekdays: [1, 3, 5]);
    expect(dates(rule, '2026-10-26', '2026-11-13'),
        ['2026-10-28', '2026-10-30', '2026-11-09', '2026-11-11', '2026-11-13']);
  });

  test('monthly day 31 has explicit skip and last-day policies', () {
    final skip = RecurrenceRule(
        start: day('2026-01-31'), frequency: RecurrenceFrequency.monthly);
    final clamp = RecurrenceRule(
        start: day('2026-01-31'),
        frequency: RecurrenceFrequency.monthly,
        missingMonthDay: MissingMonthDay.lastDay);
    expect(
        dates(skip, '2026-01-01', '2026-04-30'), ['2026-01-31', '2026-03-31']);
    expect(dates(clamp, '2026-01-01', '2026-04-30'),
        ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);
  });

  test('negative monthly days support a final-day schedule', () {
    final rule = RecurrenceRule(
        start: day('2026-01-01'),
        frequency: RecurrenceFrequency.monthly,
        monthDays: [-1]);
    expect(dates(rule, '2026-01-01', '2026-03-31'),
        ['2026-01-31', '2026-02-28', '2026-03-31']);
  });

  test('leap-day yearly schedules remain stable across leap and non-leap years',
      () {
    final skip = RecurrenceRule(
        start: day('2024-02-29'), frequency: RecurrenceFrequency.yearly);
    final clamp = RecurrenceRule(
        start: day('2024-02-29'),
        frequency: RecurrenceFrequency.yearly,
        missingMonthDay: MissingMonthDay.lastDay);
    expect(
        dates(skip, '2024-01-01', '2028-03-01'), ['2024-02-29', '2028-02-29']);
    expect(dates(clamp, '2024-01-01', '2028-03-01'),
        ['2024-02-29', '2025-02-28', '2026-02-28', '2027-02-28', '2028-02-29']);
  });

  test('count limits refer to scheduled occurrences before exceptions', () {
    final rule = RecurrenceRule(
        start: day('2026-10-01'),
        frequency: RecurrenceFrequency.daily,
        count: 5,
        excludedDates: [day('2026-10-03')]);
    expect(dates(rule, '2026-10-01', '2026-10-30'),
        ['2026-10-01', '2026-10-02', '2026-10-04', '2026-10-05']);
    expect(dates(rule, '2026-10-05', '2026-10-30'), ['2026-10-05']);
    expect(dates(rule, '2026-10-06', '2026-10-30'), isEmpty);
  });

  test('pause, resume date, interval and end bound survive serialization', () {
    final rule = RecurrenceRule(
        start: day('2026-10-01'),
        frequency: RecurrenceFrequency.daily,
        interval: 2,
        end: day('2026-10-09'),
        pauseUntil: day('2026-10-04'));
    final copy = RecurrenceRule.fromJson(rule.toJson());
    expect(dates(copy, '2026-10-01', '2026-10-31'),
        ['2026-10-05', '2026-10-07', '2026-10-09']);
    expect(
        dates(
            RecurrenceRule(
                start: day('2026-10-01'),
                frequency: RecurrenceFrequency.daily,
                paused: true),
            '2026-10-01',
            '2026-10-31'),
        isEmpty);
  });

  test(
      'ranges are bounded and the final supported calendar day does not overflow',
      () {
    final rule = RecurrenceRule(
        start: day('9999-12-30'), frequency: RecurrenceFrequency.daily);
    expect(
        dates(rule, '9999-12-30', '9999-12-31'), ['9999-12-30', '9999-12-31']);
    expect(() => dates(rule, '2026-01-01', '2025-01-01'), throwsArgumentError);
    expect(
        () => RecurrenceRule(
            start: day('2026-01-01'),
            frequency: RecurrenceFrequency.daily,
            interval: 0),
        throwsFormatException);
  });

  test(
      'task round-trip preserves planning, relationships, reminders and recurrence',
      () {
    final value = ProductivityTask(
        id: 'task',
        workspaceId: 'work',
        title: ' Proposal ',
        description: '## Outline',
        status: TaskStatus.inProgress,
        priority: TaskPriority.urgent,
        projectId: 'project',
        parentId: 'parent',
        goalId: 'goal',
        milestoneId: 'milestone',
        startDate: day('2026-10-30'),
        scheduledAt: DateTime.utc(2026, 10, 30, 8),
        deadline: DateTime.utc(2026, 11, 2, 17),
        estimatedMinutes: 180,
        tags: ['writing', 'work'],
        dependencies: ['research'],
        reminders: [
          DateTime.utc(2026, 10, 30, 7),
          DateTime.utc(2026, 11, 2, 12)
        ],
        recurrence: RecurrenceRule(
            start: day('2026-10-30'), frequency: RecurrenceFrequency.monthly));
    final fields = {...value.toFields(), '_deleted': false};
    final record = WorkspaceRecord(
        ownerId: 'alice',
        kind: RecordKind.task,
        id: value.id,
        fields: fields,
        clocks: {for (final key in fields.keys) key: VersionStamp(1, 'device')},
        modifiedAtMillis: 1);
    final copy = ProductivityTask.fromRecord(record);
    expect(copy.title, 'Proposal');
    expect(copy.priority, TaskPriority.urgent);
    expect(copy.dependencies, ['research']);
    expect(copy.reminders, hasLength(2));
    expect(canonicalJson(copy.toFields()), canonicalJson(value.toFields()));
  });

  test('overdue work can be replanned while retaining its missed deadline', () {
    final task = ProductivityTask(
        id: 'task',
        workspaceId: 'work',
        title: 'Overdue',
        scheduledAt: DateTime.utc(2026, 11, 2),
        deadline: DateTime.utc(2026, 10, 30));
    expect(task.scheduledPastDeadline, isTrue);
    expect(
        () => ProductivityTask(
            id: 'task', workspaceId: 'work', title: '', estimatedMinutes: -1),
        throwsFormatException);
    expect(
        () => ProductivityTask(
            id: 'task',
            workspaceId: 'work',
            title: 'Self dependency',
            dependencies: ['task']),
        throwsFormatException);
  });
}
