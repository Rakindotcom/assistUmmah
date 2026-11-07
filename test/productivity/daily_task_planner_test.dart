import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_day.dart';
import 'package:ummah_assist/src/productivity/domain/calendar_event.dart';
import 'package:ummah_assist/src/productivity/domain/daily_task_planner.dart';
import 'package:ummah_assist/src/productivity/domain/experience_options.dart';
import 'package:ummah_assist/src/productivity/domain/recurrence.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';

void main() {
  final day = CalendarDay(2026, 11, 5);
  final morning = DateTime.utc(2026, 11, 5, 8);

  ProductivityTask task(String id,
          {TaskPriority priority = TaskPriority.normal,
          TaskStatus status = TaskStatus.notStarted,
          int minutes = 30,
          int order = 0,
          String workspace = 'personal',
          String? parent,
          Iterable<String> dependencies = const [],
          DateTime? at,
          DateTime? deadline,
          CalendarDay? scheduledDay,
          CalendarDay? startDate,
          RecurrenceRule? recurrence,
          bool inbox = false,
          bool archived = false}) =>
      ProductivityTask(
          id: id,
          workspaceId: workspace,
          title: id,
          priority: priority,
          status: status,
          estimatedMinutes: minutes,
          order: order,
          parentId: parent,
          dependencies: dependencies,
          scheduledAt: at,
          scheduledDay: scheduledDay,
          startDate: startDate,
          deadline: deadline,
          recurrence: recurrence,
          inbox: inbox,
          archived: archived);

  ExperienceOptions options({
    String zone = 'UTC',
    int start = 9 * 60,
    int end = 17 * 60,
    int capacity = 480,
    Iterable<int> workingDays = const [1, 2, 3, 4, 5],
    Iterable<WorkspaceModule> modules = const [WorkspaceModule.personal],
  }) =>
      ExperienceOptions(
          language: 'en',
          timeZone: zone,
          workdayStartsAt: start,
          workdayEndsAt: end,
          dailyCapacityMinutes: capacity,
          workingDays: workingDays,
          modules: modules);

  CalendarEvent event(String id, DateTime from, DateTime to,
          {String workspace = 'personal', String zone = 'UTC'}) =>
      CalendarEvent(
          id: id,
          workspaceId: workspace,
          title: id,
          start: from,
          end: to,
          timeZone: zone);

  DailyTaskPlan plan(Iterable<ProductivityTask> tasks,
          {Iterable<CalendarEvent> events = const [],
          ExperienceOptions? preferences,
          CalendarDay? on,
          DateTime? now,
          bool Function(ProductivityTask)? isCompleted,
          int maxPlacements = 500}) =>
      DailyTaskPlanner.plan(
          tasks: tasks,
          events: events,
          options: preferences ?? options(),
          day: on ?? day,
          now: now ?? morning,
          isCompleted: isCompleted,
          maxPlacements: maxPlacements);

  Map<String, DailyTaskUnscheduledReason> reasons(DailyTaskPlan value) => {
        for (final item in value.unscheduled) item.taskId: item.reason,
      };

  test(
      'priority, deadline, planned day, order, ID give deterministic proposals',
      () {
    final tasks = [
      task('none', priority: TaskPriority.none),
      task('low', priority: TaskPriority.low),
      task('z'),
      task('b', order: 1),
      task('a', order: 1),
      task('planned', scheduledDay: day),
      task('overdue', scheduledDay: day.addDays(-1)),
      task('due', deadline: DateTime.utc(2026, 11, 5, 17)),
      task('urgent', priority: TaskPriority.urgent),
    ];
    final first = plan(tasks);
    final second = plan(tasks.reversed);
    expect(first.placements.map((p) => p.taskId),
        ['urgent', 'due', 'overdue', 'planned', 'z', 'a', 'b', 'low', 'none']);
    expect(first.placements.map((p) => (p.taskId, p.start, p.end)),
        second.placements.map((p) => (p.taskId, p.start, p.end)));
    expect(first.placements.first.start, DateTime.utc(2026, 11, 5, 9));
    expect(first.plannedMinutes, 270);
    expect(first.remainingCapacityMinutes, 210);
    expect(tasks.every((t) => t.scheduledAt == null), isTrue);
    expect(() => first.placements.clear(), throwsUnsupportedError);
    expect(() => first.unscheduled.clear(), throwsUnsupportedError);
    expect(() => first.excludedTaskIds.clear(), throwsUnsupportedError);
    expect(() => first.fixedTaskIds.clear(), throwsUnsupportedError);
  });

  test('events and fixed tasks reserve time without moving existing records',
      () {
    final fixed = task('fixed', minutes: 60, at: DateTime.utc(2026, 11, 5, 11));
    final result = plan([
      fixed,
      task('first', minutes: 60, priority: TaskPriority.high),
      task('second', minutes: 90),
    ], events: [
      event('meeting', DateTime.utc(2026, 11, 5, 9, 30),
          DateTime.utc(2026, 11, 5, 10, 30)),
      event('overlap', DateTime.utc(2026, 11, 5, 10),
          DateTime.utc(2026, 11, 5, 11)),
    ]);
    expect(result.capacityMinutes, 390);
    expect(result.fixedTaskMinutes, 60);
    expect(result.fixedTaskIds, ['fixed']);
    expect(result.placements.map((p) => (p.taskId, p.start, p.end)), [
      ('first', DateTime.utc(2026, 11, 5, 12), DateTime.utc(2026, 11, 5, 13)),
      (
        'second',
        DateTime.utc(2026, 11, 5, 13),
        DateTime.utc(2026, 11, 5, 14, 30)
      ),
    ]);
    expect(fixed.scheduledAt, DateTime.utc(2026, 11, 5, 11));
  });

  test(
      'daily budget counts fixed effort and can reject despite free clock time',
      () {
    final result = plan([
      task('fixed', minutes: 45, at: DateTime.utc(2026, 11, 5, 7)),
      task('fits', minutes: 60, priority: TaskPriority.high),
      task('too-much', minutes: 30),
    ], preferences: options(capacity: 120));
    expect(result.placements.map((p) => p.taskId), ['fits']);
    expect(result.remainingCapacityMinutes, 15);
    expect(reasons(result), {
      'too-much': DailyTaskUnscheduledReason.capacityExceeded,
    });
  });

  test('a timed inbox record still reserves its visible calendar commitment',
      () {
    final result = plan([
      task('timed-inbox',
          inbox: true, minutes: 60, at: DateTime.utc(2026, 11, 5, 9)),
      task('candidate', minutes: 60),
      task('untimed-inbox', inbox: true),
    ]);
    expect(result.fixedTaskIds, ['timed-inbox']);
    expect(result.excludedTaskIds, ['untimed-inbox']);
    expect(result.fixedTaskMinutes, 60);
    expect(result.placements.single.taskId, 'candidate');
    expect(result.placements.single.start, DateTime.utc(2026, 11, 5, 10));
  });

  test(
      'uses the selected zone day, enabled workspaces, and overnight spillover',
      () {
    final result = plan(
        [
          task('spillover', minutes: 720, at: DateTime.utc(2026, 11, 4, 17)),
          task('future-fixed', at: DateTime.utc(2026, 11, 6, 3)),
          task('work-disabled', workspace: 'work'),
          task('personal', minutes: 60),
        ],
        preferences: options(zone: 'Asia/Dhaka'),
        now: DateTime.utc(2026, 11, 5),
        events: [
          event('disabled', DateTime.utc(2026, 11, 5, 5),
              DateTime.utc(2026, 11, 5, 11),
              workspace: 'work'),
        ]);
    expect(result.workdayStart, DateTime.utc(2026, 11, 5, 3));
    expect(result.fixedTaskIds, ['spillover']);
    expect(result.fixedTaskMinutes, 120);
    expect(result.placements.single.start, DateTime.utc(2026, 11, 5, 5));
    expect(result.excludedTaskIds, ['future-fixed', 'work-disabled']);
  });

  test(
      'now is an explicit clock, rounded forward to a minute, deadline inclusive',
      () {
    final result = plan([
      task('fits', minutes: 30, deadline: DateTime.utc(2026, 11, 5, 12, 31)),
      task('due-now', deadline: DateTime.utc(2026, 11, 5, 12)),
      task('deadline-short',
          minutes: 60, deadline: DateTime.utc(2026, 11, 5, 13)),
    ], now: DateTime.utc(2026, 11, 5, 12, 0, 1));
    expect(result.placements.single.taskId, 'fits');
    expect(result.placements.single.start, DateTime.utc(2026, 11, 5, 12, 1));
    expect(result.placements.single.end, DateTime.utc(2026, 11, 5, 12, 31));
    expect(reasons(result), {
      'due-now': DailyTaskUnscheduledReason.deadlinePassed,
      'deadline-short': DailyTaskUnscheduledReason.deadlineCannotFit,
    });
  });

  test(
      'states, dependencies, start dates and unfinished child groups need review',
      () {
    final result = plan([
      task('waiting', status: TaskStatus.waiting),
      task('blocked', status: TaskStatus.blocked),
      task('future-start', startDate: day.addDays(1)),
      task('missing-estimate', minutes: 0),
      task('parent'),
      task('child', parent: 'parent'),
      task('dependent', dependencies: ['child']),
      task('missing-dependency', dependencies: ['missing']),
      task('done-dependency', status: TaskStatus.completed),
      task('allowed', dependencies: ['done-dependency']),
      task('callback-done'),
    ], isCompleted: (task) => task.id == 'callback-done');
    expect(result.placements.map((p) => p.taskId), ['allowed', 'child']);
    expect(reasons(result), {
      'waiting': DailyTaskUnscheduledReason.waiting,
      'blocked': DailyTaskUnscheduledReason.blocked,
      'future-start': DailyTaskUnscheduledReason.startsAfterDay,
      'missing-estimate': DailyTaskUnscheduledReason.missingEstimate,
      'parent': DailyTaskUnscheduledReason.incompleteSubtasks,
      'dependent': DailyTaskUnscheduledReason.incompleteDependencies,
      'missing-dependency': DailyTaskUnscheduledReason.incompleteDependencies,
    });
    expect(result.excludedTaskIds, ['callback-done', 'done-dependency']);
  });

  test('excludes archived, completed, inbox, disabled, future and paused tasks',
      () {
    final result = plan([
      task('archive', archived: true),
      task('complete', status: TaskStatus.completed),
      task('inbox', inbox: true),
      task('disabled', workspace: 'study'),
      task('future', scheduledDay: day.addDays(1)),
      task('paused',
          recurrence: RecurrenceRule(
              start: day, frequency: RecurrenceFrequency.daily, paused: true)),
    ]);
    expect(result.placements, isEmpty);
    expect(result.unscheduled, isEmpty);
    expect(result.excludedTaskIds,
        ['archive', 'complete', 'disabled', 'future', 'inbox', 'paused']);
  });

  test(
      'archived open children and completed occurrences do not finish a parent',
      () {
    final result = plan([
      task('archived-parent'),
      task('archived-child', parent: 'archived-parent', archived: true),
      task('recurring-parent'),
      task('recurring-child',
          parent: 'recurring-parent',
          recurrence:
              RecurrenceRule(start: day, frequency: RecurrenceFrequency.daily)),
      task('completed-parent'),
      task('completed-child',
          parent: 'completed-parent',
          status: TaskStatus.completed,
          archived: true),
    ], isCompleted: (task) => task.id == 'recurring-child');
    expect(result.placements.single.taskId, 'completed-parent');
    expect(reasons(result), {
      'archived-parent': DailyTaskUnscheduledReason.incompleteSubtasks,
      'recurring-parent': DailyTaskUnscheduledReason.incompleteSubtasks,
    });
  });

  test('nonworking days and elapsed workdays cannot create proposals', () {
    final rest =
        plan([task('rest')], preferences: options(workingDays: [1, 2, 3]));
    expect(rest.placements, isEmpty);
    expect(reasons(rest), {'rest': DailyTaskUnscheduledReason.nonworkingDay});
    final elapsed = plan([task('elapsed')], now: DateTime.utc(2026, 11, 5, 17));
    expect(
        reasons(elapsed), {'elapsed': DailyTaskUnscheduledReason.workdayEnded});
  });

  test('fragmented availability cannot split one task into invented subtasks',
      () {
    final result = plan([task('long', minutes: 45), task('short', minutes: 30)],
        preferences: options(end: 11 * 60),
        events: [
          event('meeting', DateTime.utc(2026, 11, 5, 9, 30),
              DateTime.utc(2026, 11, 5, 10, 30)),
        ]);
    expect(
        reasons(result), {'long': DailyTaskUnscheduledReason.noContiguousTime});
    expect(result.placements.single.taskId, 'short');
    expect(result.placements.single.start, DateTime.utc(2026, 11, 5, 9));
  });

  test('active recurrence reserves effort but is never silently rewritten', () {
    final recurring = task('repeat',
        minutes: 60,
        recurrence:
            RecurrenceRule(start: day, frequency: RecurrenceFrequency.daily));
    final result = plan([recurring, task('extra', minutes: 90)],
        preferences: options(capacity: 120));
    expect(result.placements, isEmpty);
    expect(result.fixedTaskMinutes, 60);
    expect(reasons(result), {
      'repeat': DailyTaskUnscheduledReason.unsupportedRecurrence,
      'extra': DailyTaskUnscheduledReason.capacityExceeded,
    });
    final previousSeed = plan([
      task('timed-repeat',
          minutes: 30,
          at: DateTime.utc(2026, 11, 4, 10),
          recurrence: RecurrenceRule(
              start: day.addDays(-1), frequency: RecurrenceFrequency.daily)),
      task('extra'),
    ]);
    expect(previousSeed.placements, isEmpty);
    expect(reasons(previousSeed)['timed-repeat'],
        DailyTaskUnscheduledReason.unsupportedRecurrence);
  });

  test(
      'a timed recurring seed on this occurrence reserves only its known interval',
      () {
    final result = plan([
      task('timed-repeat',
          minutes: 60,
          at: DateTime.utc(2026, 11, 5, 9),
          recurrence:
              RecurrenceRule(start: day, frequency: RecurrenceFrequency.daily)),
      task('extra'),
    ]);
    expect(result.placements.single.start, DateTime.utc(2026, 11, 5, 10));
    expect(result.fixedTaskMinutes, 60);
  });

  test('unknown fixed duration reserves the rest of the work window', () {
    final result = plan([
      task('unknown', minutes: 0, at: DateTime.utc(2026, 11, 5, 10)),
      task('before', minutes: 30),
      task('after', minutes: 60, priority: TaskPriority.low),
    ]);
    expect(result.placements.single.taskId, 'before');
    expect(result.placements.single.start, DateTime.utc(2026, 11, 5, 9));
    expect(
        reasons(result)['unknown'], DailyTaskUnscheduledReason.missingEstimate);
    expect(
        reasons(result)['after'], DailyTaskUnscheduledReason.capacityExceeded);
  });

  test('spring DST uses elapsed duration and shifts a missing boundary forward',
      () {
    final spring = CalendarDay(2026, 3, 8);
    final elapsed = plan([task('two-hours', minutes: 120)],
        on: spring,
        now: DateTime.utc(2026, 3, 8),
        preferences: options(
            zone: 'America/New_York',
            start: 60,
            end: 240,
            capacity: 180,
            workingDays: [7]));
    expect(elapsed.capacityMinutes, 120);
    expect(elapsed.placements.single.start, DateTime.utc(2026, 3, 8, 6));
    expect(elapsed.placements.single.end, DateTime.utc(2026, 3, 8, 8));
    final missing = plan([task('one-hour', minutes: 60)],
        on: spring,
        now: DateTime.utc(2026, 3, 8),
        preferences: options(
            zone: 'America/New_York',
            start: 150,
            end: 240,
            capacity: 90,
            workingDays: [7]));
    expect(missing.workdayStart, DateTime.utc(2026, 3, 8, 7));
    expect(missing.placements.single.end, DateTime.utc(2026, 3, 8, 8));
  });

  test(
      'fall DST keeps repeated instants distinct and respects a crossing event',
      () {
    final fall = CalendarDay(2026, 11, 1);
    final result = plan([task('first'), task('second')],
        on: fall,
        now: DateTime.utc(2026, 11, 1),
        preferences: options(
            zone: 'America/New_York',
            start: 60,
            end: 180,
            capacity: 120,
            workingDays: [7]),
        events: [
          event('repeated-hour', DateTime.utc(2026, 11, 1, 5, 30),
              DateTime.utc(2026, 11, 1, 6, 30),
              zone: 'America/New_York'),
        ]);
    expect(result.capacityMinutes, 60);
    expect(result.placements.map((p) => p.start), [
      DateTime.utc(2026, 11, 1, 5),
      DateTime.utc(2026, 11, 1, 6, 30),
    ]);
    expect(result.workdayEnd, DateTime.utc(2026, 11, 1, 8));
  });

  test('limits proposals and rejects ambiguous IDs or invalid limits', () {
    final result = plan([task('a'), task('b')], maxPlacements: 1);
    expect(result.placements.single.taskId, 'a');
    expect(reasons(result),
        {'b': DailyTaskUnscheduledReason.planningLimitReached});
    expect(() => plan([task('duplicate'), task('duplicate')]),
        throwsArgumentError);
    expect(() => plan([], maxPlacements: 0), throwsArgumentError);
    expect(() => plan([], maxPlacements: 501), throwsArgumentError);
  });
}
